-- Any mailbox reachable over IMAP, through Houston's verified-TLS connection; credentials
-- stay on Houston. The native imap.command validates options, encodes message IDs and
-- decodes MIME, so each operation here forwards one command and documents it.
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

-- Exposes an operation when it only reads or the connection allows changes.
local function export(name: string, isRead: boolean, fn: (any) -> any, doc: string)
	if isRead or config.access == "read-write" then
		exports[name], help[name] = fn, doc
	end
end

export("listMailFolders", true, function(...: any): any
	assert(select("#", ...) == 0, "listMailFolders takes no arguments")
	return command("list", {})
end, "listMailFolders() -> {{id, name, parentId?, role?, totalEmails?, unreadEmails?}} sorted by id. id is the full folder name, such as 'INBOX' or 'Archive/2026'; role is inbox, sent, drafts, trash, junk, archive or all. Some servers list containers that hold no messages: use them as parents, not to search. Counts appear when the server reports them in its folder list.")

export("listMessages", true, function(input: any): any
	return command("search", options(input))
end, "listMessages({folder?, from?, to?, cc?, subject?, text?, since?, before?, unread?, flagged?, maxResults?, pageToken?}) -> {messages={{id}}, nextPageToken?}. Searches one folder (default INBOX), most recently added first. Text filters match substrings, case-insensitively; text searches headers and body. since and before take YYYY-MM-DD and compare the day the server received the message: since includes that day, before excludes it. unread and flagged filter by state when true or false. maxResults is 1 to 500 (default 100). Pass nextPageToken as pageToken until it is absent. IDs only: read them with getMessages.")

export("getMessages", true, function(input: any): any
	return command("fetch", options(input))
end, "getMessages({ids, maxBodyBytes?}) -> messages in the order of ids, each {id, folder, flags, date, receivedAt, size, subject, from, to, cc, bcc, replyTo, messageId, inReplyTo, body, bodyTruncated, attachments={{id, filename, mimeType, size, inline, contentId}}}. 1 to 50 IDs, and IDs × maxBodyBytes at most 3.5 MiB; the whole reply, as JSON, must stay under 4 MiB. An attachment's size is as stored on the server, about a third above the file's size for base64. body is the decoded plain text, else the HTML; maxBodyBytes caps it (default 65536, at most 1048576; 0 skips bodies for a cheap scan) and bodyTruncated reports a cut. flags are IMAP flags such as \\Seen (read), \\Flagged and \\Answered. Reading never marks a message read.")

export("getMessage", true, function(input: any): any
	local args = options(input)
	local id = args.id
	assert(type(id) == "string" and id ~= "", "id must be a nonempty string")
	assert(args.ids == nil, "getMessage takes one id; use getMessages for several")
	args.id, args.ids = nil, {id}
	return command("fetch", args)[1]
end, "getMessage({id, maxBodyBytes?}) -> one message shaped like getMessages.")

export("getAttachment", true, function(input: any): any
	local saved = command("download", options(input))
	saved.url = await(fs.signedGetUrl(saved.path))
	return saved
end, "getAttachment({messageId, attachmentId, path}) -> {path, url, size, filename?, mimeType}. Saves an attachment (id from a message's attachments) to a session path, decoded; url is a signed Houston download link. Never inline attachment bytes. The download must finish within 20 seconds.")

local WRITE = " A failed or interrupted change may already have applied: check with getMessages or listMessages before repeating it."

export("setFlags", false, function(input: any): any
	return command("store", options(input))
end, "setFlags({ids, add?, remove?}) -> {ids}. Adds and removes flags on 1 to 1000 messages, e.g. add={'\\\\Seen'} marks read, remove={'\\\\Seen'} marks unread, add={'\\\\Flagged'} stars. Keywords such as $Important are allowed when the server accepts them. Fails without changes if an ID no longer exists." .. WRITE)

export("moveMessages", false, function(input: any): any
	return command("move", options(input))
end, "moveMessages({ids, folder}) -> {folder, ids?}. Moves 1 to 1000 messages to a folder id or role (trash, archive, junk...). Messages get new IDs in the destination: ids lists them in input order when the server reports them. Fails without changes if an ID no longer exists." .. WRITE)

export("trashMessages", false, function(input: any): any
	local args = options(input)
	assert(args.folder == nil, "trashMessages always moves to the trash folder")
	args.folder = "trash"
	return command("move", args)
end, "trashMessages({ids}) -> {folder, ids?}. Moves messages to the trash folder, like moveMessages with folder='trash'. Nothing is deleted permanently." .. WRITE)

export("createFolder", false, function(input: any): any
	return command("create", options(input))
end, "createFolder({name, parent?}) -> {id, name}. Creates name at the top level or inside parent (a folder id or role); name cannot contain the folder separator. Some servers keep every folder inside INBOX: pass parent='INBOX' there.")

function exports.help(): string
	local names: {string} = {}
	for name in help do table.insert(names, name) end
	table.sort(names)
	local lines = {
		"IMAP mailbox of the connected account. Operations take one named options object and return plain data; read-only connections expose only the reads.",
		"Message IDs are opaque strings tied to their folder: keep them as returned. They change when a message moves, and IDs from before a server reset fail clearly instead of matching another message.",
		"Folders are folder ids from listMailFolders or roles (inbox, sent, drafts, trash, junk, archive, all); an exact folder name wins over a role.",
		"Each call opens one connection to the mail server: call sequentially rather than in parallel. Errors carry the server's message. No sending: draft replies elsewhere.",
		"Example: local page = listMessages({unread=true, maxResults=20}); local ids = {}; for _, m in page.messages do table.insert(ids, m.id) end; getMessages({ids=ids, maxBodyBytes=0}).",
	}
	for _, name in names do table.insert(lines, help[name]) end
	return table.concat(lines, "\n")
end

return exports
