-- Any mailbox reachable over IMAP, through Houston's TLS connection in the configured TLS
-- mode; credentials stay on Houston. The native imap.command validates options, encodes
-- message IDs and decodes MIME, so each operation here forwards one command and documents it.
type Options = {[string]: any}

local function options(value: any): Options
	if value == nil then return {} end
	assert(type(value) == "table", "opts must be an object")
	for key in value do assert(type(key) == "string", "opts must have named fields") end
	return table.clone(value)
end

local function command(name: string, args: Options): any
	args.command = name
	return await(imap.command(args))
end

local exports: {[string]: any} = {}
local help: {[string]: string} = {}

-- Read and write connections expose every operation; Read and draft (custom) ones add only drafts to the reads.
local WRITES = config.access == "read-write"
local DRAFTS = WRITES or config.access == "custom"

local function export(name: string, allowed: boolean, fn: (any) -> any, doc: string)
	if allowed then
		exports[name], help[name] = fn, doc
	end
end

export("listMailFolders", true, function(...: any): any
	local input = ...
	assert(select("#", ...) <= 1 and (input == nil or type(input) == "table" and next(input) == nil), "listMailFolders takes no options")
	return command("list", {})
end, "listMailFolders() -> {{id, name, parentId?, role?, totalEmails?, unreadEmails?}} sorted by id. id is the full folder name, such as 'INBOX' or 'Archive/2026'; role is inbox, sent, drafts, trash, junk, archive or all. Some servers list containers that hold no messages: use them as parents, not to search. Counts appear when the server reports them in its folder list.")

export("listMessages", true, function(input: any): any
	return command("search", options(input))
end, "listMessages({folder?, from?, to?, cc?, subject?, text?, since?, before?, unread?, flagged?, maxResults?, pageToken?}) -> {messages={{id}}, nextPageToken?}. Searches one folder (default INBOX), most recently added first. Text filters match substrings, case-insensitively; text searches headers and body. since and before take YYYY-MM-DD and compare the day the server received the message: since includes that day, before excludes it. unread and flagged filter by state when true or false. maxResults is 1 to 500 (default 100). Pass nextPageToken as pageToken, repeating the same folder and filters, until it is absent. IDs only: read them with getMessages.")

export("getMessages", true, function(input: any): any
	return command("fetch", options(input))
end, "getMessages({ids, maxBodyBytes?, bodyFormat?}) -> messages in the order of ids, each {id, folder, flags, date, receivedAt, size, subject, from, to, cc, bcc, replyTo, messageId, inReplyTo, body, bodyTruncated, attachments={{id, filename, mimeType, size, inline, contentId}}}. 1 to 50 IDs, and IDs × maxBodyBytes at most 3.5 MiB; the whole reply, as JSON, must stay under 4 MiB. An attachment's size is as stored on the server, about a third above the file's size for base64. bodyFormat: auto (default) chooses nonblank decoded plain text, then an HTML alternative; text or html selects only that format, preserving whitespace and returning an empty string if missing. Whitespace is ignored only when deciding emptiness. A truncated whitespace prefix is not considered empty. maxBodyBytes caps body (default 32768, at most 1048576; 0 skips bodies for a cheap scan) and bodyTruncated reports a cut. flags are IMAP flags such as \\Seen (read), \\Flagged and \\Answered. Reading never marks a message read.")

export("getMessage", true, function(input: any): any
	local args = options(input)
	local id = args.id
	assert(type(id) == "string" and id ~= "", "id must be a nonempty string")
	assert(args.ids == nil, "getMessage takes one id; use getMessages for several")
	args.id, args.ids = nil, {id}
	return command("fetch", args)[1]
end, "getMessage({id, maxBodyBytes?, bodyFormat?}) -> one message shaped like getMessages.")

export("getAttachment", true, function(input: any): any
	local saved = command("download", options(input))
	saved.url = await(fs.signedGetUrl(saved.path))
	return saved
end, "getAttachment({messageId, attachmentId, path}) -> {path, url, size, filename?, mimeType}. Saves an attachment (id from a message's attachments) to a session path, decoded; url is a signed Houston download link. Never inline attachment bytes. The download must finish within 20 seconds.")

local WRITE = " A failed or interrupted change may already have applied: check with getMessages or listMessages before repeating it."

export("setFlags", WRITES, function(input: any): any
	return command("store", options(input))
end, "setFlags({ids, add?, remove?}) -> {ids}. Adds and removes flags on 1 to 1000 messages, e.g. add={'\\\\Seen'} marks read, remove={'\\\\Seen'} marks unread, add={'\\\\Flagged'} stars. Keywords such as $Important are allowed when the server accepts them. Fails without changes if an ID no longer exists." .. WRITE)

export("moveMessages", WRITES, function(input: any): any
	return command("move", options(input))
end, "moveMessages({ids, folder}) -> {folder, ids?}. Moves 1 to 1000 messages to a folder id or role (trash, archive, junk...). Messages get new IDs in the destination: ids lists them in input order when the server reports them. Fails without changes if an ID no longer exists." .. WRITE)

export("trashMessages", WRITES, function(input: any): any
	local args = options(input)
	assert(args.folder == nil, "trashMessages always moves to the trash folder")
	args.folder = "trash"
	return command("move", args)
end, "trashMessages({ids}) -> {folder, ids?}. Moves messages to the trash folder, like moveMessages with folder='trash'. Nothing is deleted permanently here, but many providers empty their trash automatically after some days." .. WRITE)

export("createFolder", WRITES, function(input: any): any
	return command("create", options(input))
end, "createFolder({name, parent?}) -> {id, name}. Creates name at the top level or inside parent (a folder id or role); name cannot contain the folder separator. Some servers keep every folder inside INBOX: pass parent='INBOX' there.")

local DRAFT_FIELDS = {"to", "cc", "bcc", "subject", "html", "from", "replyTo", "inReplyTo", "replyAll", "folder"}

-- Copies the public draft fields, sends text as body (text is the search filter in imap.command) and flattens
-- attachments into the parallel lists imap.command takes.
local function draft(name: string, input: any, replace: string?): any
	local args = options(input)
	local out: Options = {replace = replace, body = args.text}
	args.text = nil
	for _, field in DRAFT_FIELDS do
		out[field], args[field] = args[field], nil
	end
	assert(replace ~= nil or args.id == nil, "createDraft takes no id; use updateDraft to replace a draft")
	local files = args.attachments
	args.attachments, args.id = nil, nil
	for key in args do error(name .. " has no " .. key .. " option") end
	if files ~= nil then
		assert(type(files) == "table", "attachments must be a list of paths or {path, filename?, mimeType?}")
		local paths: {string}, names: {string}, kinds: {string} = json.decode("[]"), json.decode("[]"), json.decode("[]")
		for _, item in files do
			local file = if type(item) == "string" then {path = item} else item
			assert(type(file) == "table" and type(file.path) == "string", "each attachment needs a path")
			for key in file do
				assert(key == "path" or key == "filename" or key == "mimeType", "attachments take path, filename and mimeType")
			end
			table.insert(paths, file.path)
			table.insert(names, file.filename or "")
			table.insert(kinds, file.mimeType or "")
		end
		out.attachmentPaths, out.attachmentNames, out.attachmentTypes = paths, names, kinds
	end
	return command("draft", out)
end

local DRAFT = "to, cc, bcc and replyTo take an address ('Ana <ana@example.com>') or an array of them; from defaults to the account's address when its username is one. text and/or html give the body. inReplyTo=<message id> makes a reply: to, subject (Re:) and threading headers default from the original; replyAll=true also copies its To and Cc (except you) into cc. attachments={'path' or {path, filename?, mimeType?}} reads session files, at most 20 files and 6 MiB in all, and must finish within 20 seconds. Saved with the \\Draft and \\Seen flags; nothing is ever sent. id is absent when the server can't report it."

export("createDraft", DRAFTS, function(input: any): any
	return draft("createDraft", input, nil)
end, "createDraft({to?, subject?, text?, html?, cc?, bcc?, replyTo?, from?, attachments?, inReplyTo?, replyAll?, folder?}) -> {id?, folder, messageId}. Saves a new draft in folder (default the drafts role) for the user to review and send. " .. DRAFT .. WRITE)

export("updateDraft", DRAFTS, function(input: any): any
	local id = if type(input) == "table" then input.id else nil
	assert(type(id) == "string" and id ~= "", "id must be a nonempty string")
	return draft("updateDraft", input, id)
end, "updateDraft({id, ...createDraft fields}) -> {id?, folder, messageId}. Replaces a draft (a message with the \\Draft flag) with a new version built only from the given fields, so pass every field to keep. Saves the new version first, then deletes the old one permanently, or moves it to the trash on servers without UIDPLUS. The draft gets a new id; fields work as in createDraft." .. WRITE)

export("deleteDraft", DRAFTS, function(input: any): any
	local args = options(input)
	local id = args.id
	args.id = nil
	assert(type(id) == "string" and id ~= "" and next(args) == nil, "deleteDraft takes one id and nothing else")
	return command("discard", {ids = {id}})
end, "deleteDraft({id}) -> {folder, ids?}. Moves a draft to the trash folder, and fails without changes unless the message has the \\Draft flag." .. WRITE)

function exports.help(): string
	local names: {string} = {}
	for name in help do table.insert(names, name) end
	table.sort(names)
	local lines = {
		"IMAP mailbox of the connected account. Operations take one named options object and return plain data; read-only connections expose only the reads, and Read and draft connections add only the draft operations.",
		"Message IDs are opaque strings tied to their folder: keep them as returned. They change when a message moves, and IDs from before a server reset fail clearly instead of matching another message.",
		"Folders are folder ids from listMailFolders or roles (inbox, sent, drafts, trash, junk, archive, all); an exact folder name wins over a role.",
		"Each call opens one connection to the mail server: call sequentially rather than in parallel. Errors carry the server's message. Nothing here sends mail: drafts are saved for the user to review and send.",
		"Example: local page = listMessages({unread=true, maxResults=20}); local ids = {}; for _, m in page.messages do table.insert(ids, m.id) end; getMessages({ids=ids, maxBodyBytes=0}).",
	}
	for _, name in names do table.insert(lines, help[name]) end
	return table.concat(lines, "\n")
end

return exports
