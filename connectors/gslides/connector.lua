-- Google Slides API v1. Arguments and results keep Google's native field names.
local API = "https://slides.googleapis.com/v1"

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

-- Older APIs name the reason in errors[], newer ones in an ErrorInfo detail.
local function reasonOf(problem: any): string?
	for _, list in {problem.errors, problem.details} :: {any} do
		if type(list) == "table" then
			for _, item in list do
				if type(item) == "table" and type(item.reason) == "string" then return item.reason end
			end
		end
	end
	return nil
end

local function fail(operation: string, response: HttpResponse): never
	local ok, decoded = pcall(json.decode, await(response.body:readPrefix(4096)))
	local problem = if ok and type(decoded) == "table" and type(decoded.error) == "table" then decoded.error else {}
	local reason = reasonOf(problem)
	local message = "Google HTTP " .. tostring(response.statusCode)
	if type(problem.status) == "string" then message ..= " (" .. problem.status .. ")" end
	if type(problem.message) == "string" then message ..= ": " .. string.sub(problem.message, 1, 600) end
	if reason then message ..= " [" .. reason .. "]" end
	local retry = response.headers["retry-after"]
	if retry and retry[1] then message ..= "; Retry-After: " .. retry[1] end
	local limited = reason ~= nil and string.find(string.lower(reason), "ratelimitexceeded", 1, true) ~= nil
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

local PAGE = "{objectId, pageType, revisionId?, pageElements=[{objectId, size, transform, title?, description?, shape?={shapeType, text?={textElements=[{startIndex?, endIndex, textRun?={content, style}, autoText?, paragraphMarker?}]}, placeholder?={type, index?}}, table?={rows, columns, tableRows=[{tableCells=[{text?}]}]}, image?, video?, line?, sheetsChart?, wordArt?, elementGroup?={children}}], slideProperties?={layoutObjectId, isSkipped?, notesPage}}"
local endpoints: {[string]: Endpoint} = {
	getPresentation = {method = "GET", path = "/presentations/{presentationId}", read = true, query = {"commentsViewMode", "fields"},
		help = "getPresentation({presentationId, commentsViewMode?, fields?}) -> {presentationId, title, revisionId?, locale, pageSize={width, height}, slides=[" .. PAGE .. "], layouts=[{objectId, layoutProperties={displayName}}], masters, notesMaster}. slides are in presentation order, and absent for an empty deck; pageElements are in stacking order, back to front. Fields equal to 0 are omitted, such as a translateX at the left edge. revisionId is present only for editors and valid for 24 hours. Every layout and master comes too, and responses over 8 MiB fail: fields='presentationId,title,revisionId,slides.objectId' lists the slide IDs only. commentsViewMode='COMMENTS_VIEW_MODE_INCLUDED' adds comments=[{commentId, anchorId, headPost={postId, author, content, createTime}, replies, status, plainTextQuote}] and each slide's commentAnchors, or fails with HTTP 403 for users who cannot see comments."},
	getPage = {method = "GET", path = "/presentations/{presentationId}/pages/{pageObjectId}", read = true, query = {"commentsViewMode", "fields"},
		help = "getPage({presentationId, pageObjectId, commentsViewMode?, fields?}) -> " .. PAGE .. ". One slide, layout, master or notes page; with commentsViewMode, also its comments and commentAnchors."},
	getThumbnail = {method = "GET", path = "/presentations/{presentationId}/pages/{pageObjectId}/thumbnail", read = true, query = {"thumbnailProperties.thumbnailSize"},
		help = "getThumbnail({presentationId, pageObjectId, thumbnailSize?}) -> {width, height, contentUrl}. Renders the page as a PNG; thumbnailSize is SMALL (200 px wide), MEDIUM (800), LARGE (1600) or WIDTH2000_PX, else Google's choice. contentUrl is the image link: a plain GET without credentials fetches it for 30 minutes. Google allows only about 60 thumbnails per minute per user."},
	createPresentation = {method = "POST", path = "/presentations", read = false, body = true,
		help = "createPresentation({title?}) -> the new presentation, with presentationId, revisionId and one title slide whose placeholders are CENTERED_TITLE and SUBTITLE. Creates it in the root of My Drive; Google assigns the presentationId and ignores other fields, so add content with batchUpdate."},
	batchUpdate = {method = "POST", path = "/presentations/{presentationId}:batchUpdate", read = false, body = true, required = {requests = "array"},
		help = "batchUpdate({presentationId, requests, writeControl?}) -> {presentationId, replies, writeControl, commentUpdateState?}. Applies requests in order, all or nothing; replies match requests one to one, e.g. {createSlide={objectId}} or {insertComment={commentThread={commentId}}}. Kinds include createSlide={objectId?, insertionIndex?, slideLayoutReference?={predefinedLayout='TITLE_AND_BODY'|'TITLE_ONLY'|'BLANK'|'SECTION_HEADER'...} or {layoutId}, placeholderIdMappings?={{layoutPlaceholder={type='TITLE'|'BODY'|'CENTERED_TITLE'|'SUBTITLE', index?}, objectId}}}; a predefinedLayout fails with HTTP 400 when the deck's master lacks it, as in many themed decks: pass layoutId from getPresentation's layouts instead. Also duplicateObject={objectId}, deleteObject={objectId}, updateSlidesPosition={slideObjectIds, insertionIndex}, updateSlideProperties={objectId, slideProperties={isSkipped}, fields='isSkipped'}, replaceAllText={containsText={text, matchCase?, searchByRegex?}, replaceText, pageObjectIds?}, insertText={objectId, text, insertionIndex?, cellLocation?={rowIndex, columnIndex}}, deleteText={objectId, textRange={type='ALL'} or {type='FIXED_RANGE', startIndex, endIndex}}, updateTextStyle={objectId, textRange, style={bold?, fontSize?={magnitude, unit='PT'}, link?={url}, ...}, fields='bold'}, updateParagraphStyle={objectId, textRange, style={alignment='CENTER'}, fields='alignment'}, createParagraphBullets={objectId, textRange, bulletPreset='BULLET_DISC_CIRCLE_SQUARE'|'NUMBERED_DIGIT_ALPHA_ROMAN'}, createShape={objectId?, shapeType='TEXT_BOX'|'RECTANGLE'..., elementProperties={pageObjectId, size, transform}}, createImage={url, elementProperties} (a public PNG, JPEG or GIF under 50 MB), createTable={rows, columns, elementProperties}, replaceAllShapesWithImage, updateShapeProperties, updatePageProperties, updatePageElementTransform, groupObjects, insertComment={content, objectId or shapeTextAnchor or tableCellTextAnchor or tableAnchor, assigneeEmailAddress?}, addCommentReply={commentId, post={content?, commentAction?='RESOLVE'|'REOPEN'}}, updateCommentPost, deleteComment and deleteCommentReply (your own posts only). createSheetsChart, replaceAllShapesWithSheetsChart and refreshSheetsChart need Sheets access this connector does not request. Text indexes count UTF-16 code units within one shape or table cell, not the UTF-8 bytes # counts: é is 1 unit and an emoji 2. Take them from getPage's textElements, never from offsets in getPresentationText. insertText without insertionIndex inserts at the start: prefer replaceAllText for edits, and deleteText with textRange={type='ALL'} then insertText to replace a shape's text. A shape's final newline cannot be deleted. Sizes and positions use EMU: 914400 per inch, 12700 per point, e.g. size={width={magnitude=3000000, unit='EMU'}, height={magnitude=500000, unit='EMU'}}, transform={scaleX=1, scaleY=1, translateX=311700, translateY=1000000, unit='EMU'}; pageSize from getPresentation gives the slide's size. Give new objects your own objectId, 5 to 50 letters, digits, _, - or : starting with a letter, digit or _, to edit them later in the same batch. Speaker notes are the shape whose ID is slideProperties.notesPage.notesProperties.speakerNotesObjectId: write them with insertText on that ID, which creates the shape if needed. A new slide's notes ID is known only after a getPage, so write its notes in a second batch. Comments can fail while other edits are saved: when a batch writes comments, check that commentUpdateState is ALL_SAVED, not ALL_FAILED_UNKNOWN_REASON; other batches report NO_UPDATES_REQUESTED or omit it. writeControl={requiredRevisionId=deck.revisionId} fails with HTTP 400 if the presentation changed since that read. Example: requests={{createSlide={objectId='q3_summary', slideLayoutReference={predefinedLayout='TITLE_AND_BODY'}, placeholderIdMappings={{layoutPlaceholder={type='TITLE'}, objectId='q3_summary_title'}, {layoutPlaceholder={type='BODY'}, objectId='q3_summary_body'}}}}, {insertText={objectId='q3_summary_title', text='Q3 results'}}, {insertText={objectId='q3_summary_body', text='Revenue up 12%\\nTwo new customers'}}}."},
}

local function withPresentation(name: string, endpoint: Endpoint, args: Options): any
	if string.find(endpoint.path, "{presentationId}", 1, true) then
		args.presentationId = docsId(args.presentationId, "presentation", "presentationId")
	else
		assert(args.presentationId == nil, name .. " assigns the presentationId")
	end
	return invoke(name, endpoint, args)
end
for name, endpoint in endpoints do
	if name ~= "getThumbnail" then
		export(name, endpoint.read, function(input: any): any return withPresentation(name, endpoint, options(input)) end, endpoint.help)
	end
end
-- Only PNG exists, so thumbnails take just a size, under a plain name.
local SIZES = table.freeze({SMALL = true, MEDIUM = true, LARGE = true, WIDTH2000_PX = true})
export("getThumbnail", true, function(input: any): any
	local args = options(input)
	assert(args["thumbnailProperties.thumbnailSize"] == nil, "getThumbnail received an unknown option")
	assert(args.thumbnailSize == nil or SIZES[args.thumbnailSize], "thumbnailSize must be SMALL, MEDIUM, LARGE or WIDTH2000_PX")
	args["thumbnailProperties.thumbnailSize"], args.thumbnailSize = args.thumbnailSize, nil
	return withPresentation("getThumbnail", endpoints.getThumbnail, args)
end, endpoints.getThumbnail.help)

local NONE: {any} = table.freeze({})
local function shapeText(content: any): string
	local parts: {string} = {}
	for _, element in (content and content.textElements) or NONE do
		local run = element.textRun or element.autoText
		if run and type(run.content) == "string" then table.insert(parts, run.content) end
	end
	return (string.gsub(table.concat(parts), "\v", "\n"))
end

-- Appends the text of page elements in stacking order: shapes as written, groups element by element,
-- and table rows as lines of tab-separated cells.
local function collect(elements: any, out: {string})
	for _, element in elements or NONE do
		if element.shape then
			table.insert(out, shapeText(element.shape.text))
		elseif element.table then
			for _, row in element.table.tableRows or NONE do
				local cells: {string} = {}
				for _, cell in row.tableCells or NONE do
					local cellText = string.gsub(shapeText(cell.text), "\n+$", "")
					table.insert(cells, (string.gsub(cellText, "[\t\n]", " ")))
				end
				table.insert(out, table.concat(cells, "\t") .. "\n")
			end
		elseif element.wordArt and type(element.wordArt.renderedText) == "string" then
			table.insert(out, element.wordArt.renderedText .. "\n")
		elseif element.elementGroup then
			collect(element.elementGroup.children, out)
		end
	end
end

local function notes(slide: any): string
	local page = slide.slideProperties and slide.slideProperties.notesPage
	local id = page and page.notesProperties and page.notesProperties.speakerNotesObjectId
	for _, element in (page and page.pageElements) or NONE do
		if id ~= nil and element.objectId == id and element.shape then return shapeText(element.shape.text) end
	end
	return ""
end

-- Only the text-bearing fields of each element, through two levels of nested groups; deeper groups come whole.
local RUNS = "text.textElements(textRun.content,autoText.content)"
local ELEMENT = "shape." .. RUNS .. ",table.tableRows.tableCells." .. RUNS .. ",wordArt.renderedText"
local TEXT_FIELDS = "presentationId,title,revisionId,slides(objectId,pageElements(" .. ELEMENT .. ",elementGroup.children(" .. ELEMENT .. ",elementGroup.children(" .. ELEMENT
	.. ",elementGroup))),slideProperties(isSkipped,notesPage(notesProperties.speakerNotesObjectId,pageElements(objectId,shape." .. RUNS .. "))))"
export("getPresentationText", true, function(input: any): Options
	local args = options(input)
	assert(args.fields == nil and args.commentsViewMode == nil, "getPresentationText received an unknown option")
	args.fields = TEXT_FIELDS
	local deck = withPresentation("getPresentationText", endpoints.getPresentation, args)
	local slides: {Options} = json.decode("[]")
	for _, slide in deck.slides or NONE do
		local parts: {string} = {}
		collect(slide.pageElements, parts)
		table.insert(slides, {objectId = slide.objectId, isSkipped = slide.slideProperties and slide.slideProperties.isSkipped, text = table.concat(parts), notes = notes(slide)})
	end
	return {presentationId = deck.presentationId, title = deck.title, revisionId = deck.revisionId, slides = slides}
end, "getPresentationText({presentationId}) -> {presentationId, title, revisionId?, slides=[{objectId, isSkipped?, text, notes}]}. The text of every slide in presentation order, and its speaker notes; slides is [] for an empty deck. Shapes, text boxes and groups appear in stacking order, back to front rather than by position, each ending with '\\n'; table rows are lines of tab-separated cells. Images, videos and charts are left out: read their alt text (title, description) with getPage, or look at the slide with getThumbnail. Offsets in text are not batchUpdate indexes.")

local overview = {
	"Google Slides API v1. Operations take one named options object with Google's camelCase fields and return Google's JSON unchanged, except getPresentationText. Calls return completed values: use instance.getPresentationText(...) directly, without await.",
	"presentationId is the ID or the presentation's https://docs.google.com/presentation/d/<id>/edit URL; such a link's #slide=id.<pageObjectId> names the slide that was open. Links from Publish to the web (/presentation/d/e/...) carry no ID. This connector cannot search for files: ask for the URL, or find the ID with the Google Drive connector (listFiles with q=\"mimeType = 'application/vnd.google-apps.presentation' and trashed = false\"). PowerPoint files opened in Slides are refused with HTTP 400 until saved as Google Slides (File > Save as Google Slides).",
	"Slides, layouts, masters and notes pages are pages; the shapes, text boxes, images, tables, lines, videos, charts and groups on them are page elements, with objectIds shared across one presentation. Read the words with getPresentationText, structure and positions with getPresentation or getPage, and how a slide looks with getThumbnail.",
	"Every contentUrl, of thumbnails and images alike, opens without sign-in as the connected account for 30 minutes: show it only to people who may see the presentation, and never print, log or store it.",
	"No hidden paging or retries. Errors report the HTTP status and Google's message. Google allows about 600 reads, 60 thumbnails and 60 writes per minute per user, and 3000, 300 and 600 per minute across all Houston users; HTTP 429 errors are retryable after a pause.",
}
if config.access == "read-write" then
	table.insert(overview, "Writes change slides, their content and comments. An empty Luau table encodes as a JSON object: write an empty array as json.decode('[]'). Presentations cannot be deleted, renamed, moved or shared here: use the Google Drive connector. A failed or timed-out write may already have succeeded: check with getPresentation before repeating it (getPresentationText leaves out comments), give new slides and elements your own objectId so a repeat fails with HTTP 400 instead of adding them twice, or pass writeControl={requiredRevisionId=deck.revisionId}, with deck read by getPresentation.")
end
exports.help = helpWith(overview)
return exports
