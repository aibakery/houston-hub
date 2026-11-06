-- Structured call shapes shared by registration and offline documented examples.
local text = {type = "string"}
local nonempty = {type = "string", minLength = 1}
local messageId = {type = "string", minLength = 1, description = "Opaque message ID returned by this connection; keep its folder and UID validity intact."}
local folder = {type = "string", description = "Exact folder ID or role: inbox, sent, drafts, trash, junk, archive or all."}
local body = {type = "integer", minimum = 0, maximum = 1048576, default = 32768, description = "Body byte cap; zero skips bodies. Number of IDs times this cap must not exceed 3.5 MiB."}
local bodyFormat = {type = "string", enum = {"auto", "text", "html"}, default = "auto"}
local ids = {type = "array", items = messageId, minItems = 1, maxItems = 1000}
local flags = {type = "array", items = nonempty, description = "IMAP flags, such as \\Seen or \\Flagged, or server-supported keywords. Cannot change \\Recent or add \\Deleted; use trashMessages instead."}
local moved = {type = "object", properties = {folder = text, ids = {type = "array", items = messageId}}, required = {"folder"}, additionalProperties = false}
local function input(properties: {[string]: any}, required: {string}, example: any): any
	return {type = "object", properties = properties, required = required, additionalProperties = false, examples = {example}}
end
local empty: {string} = json.decode("[]")
local changeIds = {"7:42:INBOX", "7:43:INBOX"}
local flagAlternatives: {any} = {{required = {"add"}, properties = {add = {minItems = 1}}}, {required = {"remove"}, properties = {remove = {minItems = 1}}}}
local flagExamples: {any} = {{ids = changeIds, add = {"\\Seen"}}, {ids = {"7:42:INBOX"}, remove = {"\\Seen"}}}
return {
	listMailFolders = {args = {}, inputSchema = {type = "object", additionalProperties = false, examples = {{}}}},
	listMessages = {
		inputSchema = input({
			folder = {type = "string", default = "INBOX", description = folder.description},
			from = text, to = text, cc = text, subject = text, text = text,
			since = {type = "string", format = "date", description = "Inclusive server-received calendar date (YYYY-MM-DD)."},
			before = {type = "string", format = "date", description = "Exclusive server-received calendar date (YYYY-MM-DD)."},
			unread = {type = "boolean"}, flagged = {type = "boolean"},
			maxResults = {type = "integer", minimum = 1, maximum = 500, default = 100},
			pageToken = {type = "string", description = "Prior nextPageToken; repeat the same folder and filters."},
		}, empty, {folder = "Archive/2026", unread = true, maxResults = 20}),
		outputSchema = {type = "object", properties = {
			messages = {type = "array", items = {type = "object", properties = {id = messageId}, required = {"id"}, additionalProperties = false}}, nextPageToken = text,
		}, required = {"messages"}, additionalProperties = false},
	},
	getMessages = {inputSchema = input({
		ids = {type = "array", items = messageId, minItems = 1, maxItems = 50},
		maxBodyBytes = body, bodyFormat = bodyFormat,
	}, {"ids"}, {ids = {"7:42:INBOX"}, bodyFormat = "text"})},
	getMessage = {inputSchema = input({id = messageId, maxBodyBytes = body, bodyFormat = bodyFormat}, {"id"}, {id = "7:42:INBOX", maxBodyBytes = 0}),
		outputSchema = {type = "object", properties = {
			id = messageId, folder = text, flags = flags, date = text, receivedAt = text, size = {type = "integer"}, subject = text,
			body = text, bodyTruncated = {type = "boolean"}, messageId = text, inReplyTo = text,
			from = text, to = text, cc = text, bcc = text, replyTo = text,
			attachments = {type = "array", items = {type = "object", properties = {
				id = text, filename = text, mimeType = text, size = {type = "integer"}, inline = {type = "boolean"}, contentId = text,
			}, required = {"id", "mimeType", "size", "inline"}, additionalProperties = false}},
		}, required = {"id", "folder", "flags", "size", "subject", "from", "to", "cc", "bcc", "replyTo", "body", "bodyTruncated", "attachments"}, additionalProperties = false},
	},
	getAttachment = {inputSchema = input({messageId = messageId, attachmentId = {type = "string", pattern = "^[1-9][0-9]*(\\.[1-9][0-9]*)*$", description = "Attachment part ID from getMessage attachments."}, path = nonempty}, {"messageId", "attachmentId", "path"}, {messageId = "7:42:INBOX", attachmentId = "2", path = "files/report.pdf"}),
		outputSchema = {type = "object", properties = {path = text, url = text, size = {type = "integer", minimum = 0}, filename = text, mimeType = text}, required = {"path", "url", "size", "mimeType"}, additionalProperties = false},
	},
	setFlags = {inputSchema = {
		type = "object", properties = {ids = ids, add = flags, remove = flags}, required = {"ids"}, additionalProperties = false,
		anyOf = flagAlternatives, examples = flagExamples,
	}, outputSchema = {type = "object", properties = {ids = ids}, required = {"ids"}, additionalProperties = false}},
	moveMessages = {inputSchema = input({ids = ids, folder = {type = "string", minLength = 1, description = folder.description}}, {"ids", "folder"}, {ids = changeIds, folder = "archive"}), outputSchema = moved},
	trashMessages = {inputSchema = input({ids = ids}, {"ids"}, {ids = {"7:42:INBOX"}}), outputSchema = moved},
	createFolder = {inputSchema = input({name = {type = "string", minLength = 1, description = "Folder name without this server's separator."}, parent = folder}, {"name"}, {name = "Receipts", parent = "INBOX"}),
		outputSchema = {type = "object", properties = {id = text, name = text}, required = {"id", "name"}, additionalProperties = false}},
}
