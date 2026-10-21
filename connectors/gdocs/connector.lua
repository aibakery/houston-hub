-- Google Docs API v1. Arguments and results keep Google's native field names.
local API = "https://docs.googleapis.com/v1"

-- Request layer shared verbatim by the Google connectors (tools/validate checks they match).
type Options = {[string]: any}
type Endpoint = {method: string, path: string, read: boolean, query: {string}?, body: boolean?, defaults: Options?, list: string?, required: {[string]: string}?, help: string}

local function text(value: any, field: string): string
	assert(type(value) == "string" and value ~= "", field .. " must be a nonempty string")
	return value
end

local function options(value: any): Options
	if value == nil then return {} end
	assert(type(value) == "table", "opts must be an object")
	for key in value do assert(type(key) == "string", "opts must have named fields") end
	return table.clone(value)
end

-- Moves the named fields from args into a query string; arrays repeat the key.
local function query(args: Options, names: {string}): string
	local parts: {string} = {}
	for _, name in names do
		local value = args[name]
		args[name] = nil
		for key, item in (if type(value) == "table" then value else {value}) do
			assert(type(key) == "number" and (type(item) == "string" or type(item) == "number" or type(item) == "boolean"), name .. " must be a string, number, boolean or an array of them")
			table.insert(parts, url.encode(name) .. "=" .. url.encode(item))
		end
	end
	return if #parts > 0 then "?" .. table.concat(parts, "&") else ""
end

local function fail(operation: string, response: HttpResponse): never
	local ok, decoded = pcall(json.decode, await(response.body:readPrefix(4096)))
	local problem = if ok and type(decoded) == "table" and type(decoded.error) == "table" then decoded.error else {}
	local reason = type(problem.errors) == "table" and type(problem.errors[1]) == "table" and problem.errors[1].reason
	local message = "Google HTTP " .. tostring(response.statusCode)
	if type(problem.status) == "string" then message ..= " (" .. problem.status .. ")" end
	if type(problem.message) == "string" then message ..= ": " .. string.sub(problem.message, 1, 600) end
	if type(reason) == "string" then message ..= " [" .. reason .. "]" end
	local retry = response.headers["retry-after"]
	if retry and retry[1] then message ..= "; Retry-After: " .. retry[1] end
	local limited = type(reason) == "string" and string.find(string.lower(reason), "ratelimitexceeded", 1, true) ~= nil
	return houston.fail({operation = operation, layer = "upstream", upstream_status = response.statusCode,
		retryable = response.statusCode == 429 or response.statusCode >= 500 or limited, message = message})
end

local function decode(operation: string, response: HttpResponse): any
	if response.statusCode < 200 or response.statusCode >= 300 then fail(operation, response) end
	local raw = await(response.body:readAll())
	if raw == "" then return {success = true} end
	local ok, value = pcall(json.decode, raw)
	if not ok or type(value) ~= "table" or not string.match(raw, "^%s*{") then
		houston.fail({operation = operation, layer = "upstream", upstream_status = response.statusCode,
			retryable = false, message = "Google returned an invalid JSON object"})
	end
	return value
end

local function call(operation: string, method: string, href: string, body: any?): any
	return decode(operation, await(http.request({method = method, url = href,
		headers = if body ~= nil then {["Content-Type"] = {"application/json"}} else nil,
		body = if body ~= nil then json.encode(body) else nil})))
end

-- Accepts a docs.google.com editor URL in place of its file ID; published and responder links (/d/e/...) carry no ID.
local function docsId(value: any, product: string, field: string): any
	if type(value) ~= "string" then return value end
	local rest = string.match(value, "^https://docs%.google%.com/" .. product .. "/d/(.*)$")
		or string.match(value, "^https://docs%.google%.com/" .. product .. "/u/%d+/d/(.*)$")
		or string.match(value, "^https://docs%.google%.com/a/[^/]+/" .. product .. "/d/(.*)$")
	local id: string = if rest then string.match(rest, "^[^/?#]*") or "" else value
	assert(string.match(id, "^[%w_%-]+$") and id ~= "e", field .. " must be an ID or its https://docs.google.com/" .. product .. "/d/<id> URL")
	return id
end

-- Moves {placeholders} and declared query fields from args into the URL; remaining fields form the JSON body.
local function target(name: string, endpoint: Endpoint, args: Options): string
	local defaults: Options = endpoint.defaults or {}
	for key, value in defaults do
		if args[key] == nil then args[key] = value end
	end
	local required: {[string]: string} = endpoint.required or {}
	for field, kind in required do
		local value = args[field]
		assert(if kind == "array" then type(value) == "table" and value[1] ~= nil elseif kind == "string" then type(value) == "string" and value ~= "" elseif kind == "object" then type(value) == "table" and next(value) ~= nil and value[1] == nil else false,
			name .. " requires " .. field .. " as a nonempty " .. kind)
	end
	local path = string.gsub(endpoint.path, "{(%w+)}", function(field: string)
		local value = url.segment(text(args[field], field), field)
		args[field] = nil
		return value
	end)
	path ..= query(args, endpoint.query or {})
	if not endpoint.body then assert(next(args) == nil, name .. " received an unknown option") end
	return API .. path
end

local function invoke(name: string, endpoint: Endpoint, input: any): any
	local args = options(input)
	local result = call(name, endpoint.method, target(name, endpoint, args), if endpoint.body then args else nil)
	if endpoint.list and result[endpoint.list] == nil then result[endpoint.list] = json.decode("[]") end
	return result
end

local exports: {[string]: any} = {}
local help: {[string]: string} = {}

-- Exposes an operation when it only reads or the connection allows writes.
local function export(name: string, isRead: boolean, fn: (any) -> any, doc: string)
	if isRead or config.access == "read-write" then
		exports[name], help[name] = fn, doc
	end
end

local function exportEndpoints(endpoints: {[string]: Endpoint})
	for name, endpoint in endpoints do
		export(name, endpoint.read, function(args: Options?): any return invoke(name, endpoint, args) end, endpoint.help)
	end
end

-- help() introduces the API, then documents exactly the configured operations.
local function helpWith(overview: {string}): () -> string
	return function(): string
		local names: {string} = {}
		for name in help do table.insert(names, name) end
		table.sort(names)
		local lines = table.clone(overview)
		for _, name in names do table.insert(lines, help[name]) end
		return table.concat(lines, "\n")
	end
end
-- End of the shared request layer.

local endpoints: {[string]: Endpoint} = {
	getDocument = {method = "GET", path = "/documents/{documentId}", read = true, defaults = {includeTabsContent = true},
		query = {"includeTabsContent", "suggestionsViewMode", "commentsViewMode", "fields"},
		help = "getDocument({documentId, includeTabsContent?, suggestionsViewMode?, commentsViewMode?, fields?}) -> {documentId, title, revisionId?, tabs=[{tabProperties={tabId, title, index?, parentTabId?, nestingLevel?}, documentTab={body={content}, headers?, footers?, footnotes?, lists?, inlineObjects?, namedStyles, documentStyle, commentAnchors?}, childTabs?}]}. tabs are in display order and nest up to three levels; a link's ?tab=t.<id> names the open tab, tabId 't.<id>'. content is a list of {startIndex?, endIndex, paragraph?={elements=[{startIndex, endIndex, textRun?={content, textStyle}, person?, richLink?, dateElement?, dropdown?, footnoteReference?, inlineObjectElement?}], paragraphStyle={namedStyleType='NORMAL_TEXT'|'TITLE'|'HEADING_1'...}, bullet?}, table?={rows, columns, tableRows=[{tableCells=[{content}]}]}, sectionBreak?, tableOfContents?}. Fields equal to 0 are omitted, such as the first element's startIndex, the first tab's index and a top-level tab's nestingLevel. revisionId is present only for editors and valid for 24 hours. Responses carry every style and fail over 8 MiB; fields='title,tabs(tabProperties,childTabs(tabProperties,childTabs(tabProperties)))' lists the tabs only. includeTabsContent=false returns the first tab in the legacy body field and no tabs. suggestionsViewMode is SUGGESTIONS_INLINE (the default for anyone who can comment or edit, marking suggested text with suggestedInsertionIds and suggestedDeletionIds), PREVIEW_SUGGESTIONS_ACCEPTED or PREVIEW_WITHOUT_SUGGESTIONS (the default for viewers, who get HTTP 403 for the other two). Take indexes for batchUpdate from a SUGGESTIONS_INLINE read: suggested text shifts them. commentsViewMode='COMMENTS_VIEW_MODE_INCLUDED' with suggestionsViewMode='SUGGESTIONS_INLINE' adds comments=[{commentId, anchorId, headPost={postId, author, content, createTime}, replies, status, plainTextQuote}] and suggestions=[{suggestionId, status, summaryText, headPost, replies}]; each tab's documentTab.commentAnchors=[{anchorId, ranges}] locates them."},
	createDocument = {method = "POST", path = "/documents", read = false, body = true,
		help = "createDocument({title?}) -> the new document, with documentId and revisionId. Creates an empty document in the root of My Drive; Google ignores any other field, so add content with batchUpdate."},
	batchUpdate = {method = "POST", path = "/documents/{documentId}:batchUpdate", read = false, body = true, required = {requests = "array"},
		help = "batchUpdate({documentId, requests, writeControl?}) -> {documentId, replies, writeControl, suggestionResponses?, commentUpdateState?}. Applies requests in order, all or nothing; replies and suggestionResponses (createdSuggestionIds, ...) match requests one to one. Indexes count UTF-16 code units, not the UTF-8 bytes # counts: é is 1 unit and an emoji 2. Take them from getDocument's startIndex and endIndex, never from offsets in getDocumentText. A body's text starts at index 1. Locations and ranges take tabId (omitted: the first tab), and segmentId for a header, footer or footnote. Each request sees the indexes shifted by earlier ones: edit from the end backwards, or use replaceAllText and endOfSegmentLocation, which need no index. Kinds include insertText={text, location={index, tabId?} or endOfSegmentLocation={tabId?}}, deleteContentRange={range={startIndex, endIndex, tabId?}}, replaceAllText={containsText={text, matchCase?, searchByRegex?}, replaceText, tabsCriteria?={tabIds}} (every tab unless tabsCriteria is given), updateTextStyle={range, textStyle={bold?, italic?, link?={url}, ...}, fields='bold,link'}, updateParagraphStyle={range, paragraphStyle={namedStyleType='HEADING_1'}, fields='namedStyleType'}, createParagraphBullets={range, bulletPreset='BULLET_DISC_CIRCLE_SQUARE'|'NUMBERED_DECIMAL_ALPHA_ROMAN'}, insertTable={rows, columns, location or endOfSegmentLocation}, insertTableRow={tableCellLocation={tableStartLocation={index}, rowIndex, columnIndex}, insertBelow}, insertInlineImage={uri, location or endOfSegmentLocation} (a public PNG, JPEG or GIF under 50 MB), insertPageBreak, insertPerson={personProperties={email}, location}, insertDate, insertRichLink, addDocumentTab={tabProperties={title, parentTabId?}}, updateDocumentTabProperties, deleteTab, createHeader={type='DEFAULT'}, createFooter, createFootnote, insertComment={content, range, assigneeEmailAddress?}, addCommentReply={commentId or suggestionId, post={content?, commentAction?='RESOLVE'|'REOPEN'}}, updateCommentPost, deleteComment, deleteCommentReply, acceptSuggestion={suggestionId}, rejectSuggestion and deleteSuggestion. Text edits can be saved while their comments or suggestions fail: check that commentUpdateState is ALL_SAVED, not ALL_FAILED_UNKNOWN_REASON. The final newline of a body, header, footer, footnote or table cell cannot be deleted: end ranges before it. A newline in inserted text starts a new paragraph. writeControl={writeMode='SUGGEST'} records the edits as suggestions for an editor to accept, and refuses addDocumentTab, deleteTab, updateDocumentTabProperties, createNamedRange, deleteNamedRange, deleteHeader, deleteFooter and updateTableColumnProperties. writeControl={requiredRevisionId=doc.revisionId} fails with HTTP 400 if the document changed since that read; targetRevisionId instead merges the edits with changes made since. Example: requests={{replaceAllText={containsText={text='{{client}}', matchCase=true}, replaceText='Acme'}}, {insertText={endOfSegmentLocation={}, text='\\nNext steps'}}}."},
}

local function withDocument(name: string, endpoint: Endpoint, args: Options): any
	if string.find(endpoint.path, "{documentId}", 1, true) then
		args.documentId = docsId(args.documentId, "document", "documentId")
	else
		assert(args.documentId == nil, name .. " assigns the documentId")
	end
	return invoke(name, endpoint, args)
end
for name, endpoint in endpoints do
	export(name, endpoint.read, function(input: any): any return withDocument(name, endpoint, options(input)) end, endpoint.help)
end

local NONE: {any} = table.freeze({})
local function inline(element: any): string
	local person = element.person and element.person.personProperties
	local link = element.richLink and element.richLink.richLinkProperties
	local date = element.dateElement and element.dateElement.dateElementProperties
	local dropdown = element.dropdown and element.dropdown.dropdownProperties
	return if element.textRun then element.textRun.content or ""
		elseif person then person.name or person.email or ""
		elseif link then link.title or link.uri or ""
		elseif date then date.displayText or ""
		elseif dropdown then dropdown.displayValue or ""
		else ""
end

-- Appends the text of structural elements: paragraphs as written, table rows as lines of tab-separated cells.
local function collect(content: any, out: {string})
	for _, element in content or NONE do
		if element.paragraph then
			for _, item in element.paragraph.elements or NONE do table.insert(out, inline(item)) end
		elseif element.table then
			for _, row in element.table.tableRows or NONE do
				local cells: {string} = {}
				for _, cell in row.tableCells or NONE do
					local parts: {string} = {}
					collect(cell.content, parts)
					local cellText = string.gsub(table.concat(parts), "\n+$", "")
					table.insert(cells, (string.gsub(cellText, "[\t\n\v]", " ")))
				end
				table.insert(out, table.concat(cells, "\t") .. "\n")
			end
		end
	end
end

-- Flattens tabs in display order, each child tab after its parent. Google marks embedded objects in
-- text runs with U+E907 and soft line breaks with U+000B.
local function tabTexts(tabs: any, wanted: string?, out: {Options})
	for _, tab in tabs or NONE do
		local properties = tab.tabProperties or {}
		if wanted == nil or properties.tabId == wanted then
			local parts: {string} = {}
			collect(tab.documentTab and tab.documentTab.body and tab.documentTab.body.content, parts)
			local tabText = string.gsub(table.concat(parts), "\u{E907}", "")
			table.insert(out, {tabId = properties.tabId, title = properties.title, parentTabId = properties.parentTabId,
				nestingLevel = properties.nestingLevel or 0, text = (string.gsub(tabText, "\v", "\n"))})
		end
		tabTexts(tab.childTabs, wanted, out)
	end
end

-- Only the text-bearing fields of each tab, three levels deep like the Docs editor.
local TAB_TEXT = "tabProperties,documentTab.body.content(paragraph.elements(textRun.content,person.personProperties,richLink.richLinkProperties,dateElement.dateElementProperties.displayText,dropdown.dropdownProperties.displayValue),table.tableRows.tableCells.content)"
local TEXT_FIELDS = "documentId,title,revisionId,tabs(" .. TAB_TEXT .. ",childTabs(" .. TAB_TEXT .. ",childTabs(" .. TAB_TEXT .. ")))"
local PREVIEWS = table.freeze({PREVIEW_WITHOUT_SUGGESTIONS = true, PREVIEW_SUGGESTIONS_ACCEPTED = true})
export("getDocumentText", true, function(input: any): Options
	local args = options(input)
	local tabId = if args.tabId == nil then nil else text(args.tabId, "tabId")
	assert(args.includeTabsContent == nil and args.fields == nil and args.commentsViewMode == nil, "getDocumentText received an unknown option")
	args.suggestionsViewMode = args.suggestionsViewMode or "PREVIEW_WITHOUT_SUGGESTIONS"
	assert(PREVIEWS[args.suggestionsViewMode], "suggestionsViewMode must be PREVIEW_WITHOUT_SUGGESTIONS or PREVIEW_SUGGESTIONS_ACCEPTED")
	args.tabId, args.fields = nil, TEXT_FIELDS
	local document = withDocument("getDocumentText", endpoints.getDocument, args)
	local tabs: {Options} = json.decode("[]")
	tabTexts(document.tabs, tabId, tabs)
	assert(tabId == nil or #tabs > 0, "tabId " .. tostring(tabId) .. " is not a tab of this document")
	return {documentId = document.documentId, title = document.title, revisionId = document.revisionId, tabs = tabs}
end, "getDocumentText({documentId, tabId?, suggestionsViewMode?}) -> {documentId, title, revisionId?, tabs=[{tabId, title, parentTabId?, nestingLevel, text}]}. The plain text of every tab's body in display order, child tabs after their parent, or of tabId alone (the whole document is still read). Paragraphs end with '\\n', table rows are lines of tab-separated cells, and people, dates, dropdowns and rich links appear as their names. Headers, footers, footnotes, tables of contents, images, equations and comments are left out: read them with getDocument. Suggested changes are hidden; suggestionsViewMode='PREVIEW_SUGGESTIONS_ACCEPTED' reads the text as if they were accepted, which needs comment or edit access. Offsets in text are not batchUpdate indexes.")

local overview = {
	"Google Docs API v1. Operations take one named options object with Google's camelCase fields and return Google's JSON unchanged, except getDocumentText. Calls return completed values: use instance.getDocumentText(...) directly, without await.",
	"documentId is the ID or the document's https://docs.google.com/document/d/<id>/edit URL. Links from Publish to the web (/document/d/e/...) carry no ID. This connector cannot search for files: ask for the URL, or find the ID with the Google Drive connector (listFiles with q=\"mimeType = 'application/vnd.google-apps.document' and trashed = false\"). Word files opened in Docs are refused with HTTP 400 until saved as Google Docs (File > Save as Google Docs).",
	"A document has one or more tabs, which may have child tabs. Read its words with getDocumentText, and its structure, styles, comments and indexes with getDocument.",
	"No hidden paging or retries. Errors report the HTTP status and Google's message. Google allows about 300 reads and 60 writes per minute per user, and 3000 and 600 per minute across all Houston users; HTTP 429 errors are retryable after a pause.",
}
if config.access == "read-write" then
	table.insert(overview, "Writes change a document's text, styles, tabs, comments and suggestions. An empty Luau table encodes as a JSON object: write an empty array as json.decode('[]'). Documents cannot be deleted, renamed, moved or shared here: use the Google Drive connector. A failed or timed-out write may already have succeeded: check with getDocumentText before repeating it, or pass writeControl={requiredRevisionId=doc.revisionId} so a repeat fails with HTTP 400 instead of applying twice.")
end
exports.help = helpWith(overview)
return exports
