# Gmail operations

Provider-specific exported operations retain the documented request and pagination semantics.


Read mail for one connected mailbox. Credentials stay on the Houston
server. This is the mail contract: later mailbox providers implement the
same functions. Use the instance from `houston.connectors()` — do not
call provider URLs yourself.

List-connector signatures are enough to call. Return compact rows;
`truncate` defaults true. Loop pagination in one `run`.

## getProfile()

Mailbox identity (`emailAddress`, plus provider extras).

## listFolders()

Folders in this mailbox (Gmail labels). Returns `folders`
(`{ id, name, type }[]`). Use `id` as `folder` when listing messages.

## listMessages(opts?)

Search and list message ids. Returns **ids only** (`id`, `threadId`) —
not subjects or bodies. Optional filters on `opts`:

- `from`, `to`, `subject` (string, or array of strings)
- `after`, `before` (YYYY-MM-DD)
- `folder` or `folders` (id from `listFolders`, or array)
- `text` (free-text)
- `maxResults` (number, default 100, max 500)
- `pageToken` (string)
- `includeSpamTrash` (boolean)

This list+filters path is search. Returns `messages` (`{ id, threadId }[]`),
`nextPageToken`, and `resultSizeEstimate`. `resultSizeEstimate` is capped
(often ~201) and is **not a count**. Use `#messages` plus `nextPageToken`.
`messages` is omitted when there are no results.

## getMessage(id, opts?)

One message. `id` may be a string or a table with `id`. Returns envelope
fields so callers do not parse headers or MIME:

- `from`, `to`, `cc`, `bcc`, `replyTo`, `subject`, `date`, `messageId`
- `body` (plain text when present)
- `attachments` (metadata rows; use `getAttachment` to download)
- `headers` (raw header list, including `Received`)
- `received` (Received header values, for originating IP when present)

`getMessage("abc")` and `getMessage({ id = "abc" })` are the same call.

## listAttachments(id)

Attachment rows for one message: `id`, `filename`, `mimeType`, `size`,
`inline`, `contentId`. Same rows as `getMessage(id).attachments`. `id`
may be a message id, `{ id }`, or an already-fetched message.

## getAttachment(messageId, attachmentId, path?)

Downloads one listed attachment onto a session path (streams past the
proxy buffer) and returns `{ path, url, size }` where `url` is a Houston
signed GET URL. `attachmentId` is `id` from `listAttachments` /
`getMessage.attachments`. Optional `path` defaults under `attachments/`.
`getAttachment({ messageId, id, path })` is the same call. Do not inline
bytes or base64; give the caller the signed URL.

## getAttachments(messageId, items)

Downloads several attachments in order. `items` is `{ { id, path? }, ... }`.
Returns an array of `{ path, url, size }` in the same order. Uses `http.sendAsync`
handles and `http.wait`.

## listThreads(opts?)

Conversation list. Same optional filters as `listMessages`. Returns
`threads` (`{ id, snippet, historyId }[]`), `nextPageToken`, and
`resultSizeEstimate` (capped; not a count). Prefer this plus `getThread`
for conversation state. Loop pagination in one `run`.

## getThread(id, opts?)

The thread and **all messages** in that conversation. Each message has
the same envelope, body, and attachments fields as `getMessage`.

## getMessages(ids, opts?)

Batch get, at most 50 ids. `ids` is an array of message ids (strings or
`{ id }`), or a table with `ids`. Returns an array of messages (same
shape as `getMessage`). One Houston call. Otherwise loop `getMessage`
in the same `run`.

Write functions are bound only when this instance is read-write.

## sendMessage(body)

Send a message. `body` is typically `{ raw = "<base64url RFC 2822>" }`.

## trashMessage(id)

Move a message to trash. `id` may be a string or a table with `id`.

## Example

	return {
		run = function()
			return c.listMessages({ maxResults = 5, folder = "INBOX" })
		end,
	}
