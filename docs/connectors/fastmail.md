# Fastmail operations

Call your configured connection's `help()` for its available operations, argument
types, defaults, and mutation behavior. The [connector source](../../connectors/fastmail/connector.lua)
uses local Luau annotations to check the implementation. Callers pass ordinary
tables with named keys; no type imports are needed.
Write operations are available only when the connection allows changes.

Each operation completes before returning its result. The connector's native
`http.request` is synchronous; callers do not receive a handle to pass to
`http.wait`. Message batches and attachment transfers run sequentially, keeping
in-flight requests bounded and returning results in the requested order.

Prefer named fields when an operation needs more than a single ID. For example,
with a configured connection named `mail`:

```lua
local page = mail.listMessages({folder = "INBOX", maxResults = 20})
local messages = mail.getMessages({ids = page.messages, maxBodyValueBytes = 8192})
local thread = mail.getThread({id = "thread-id", maxBodyValueBytes = 8192})

local files = mail.getAttachments({
    messageId = "message-id",
    items = {{id = "blob-id", path = "attachments/report.pdf"}},
})

local folder = mail.createFolder({name = "Projects", parentId = "parent-folder-id"})
local moved = mail.moveMessages({ids = {"message-id"}, folder = folder.id})
local reply = mail.replyMessage({id = "message-id", text = "Thanks!", all = false})
```

Existing positional forms, such as `getMessage(id, options)`,
`getAttachments(messageId, items)`, and `moveMessages(ids, folder)`, remain
supported. IDs can also be `{id = "..."}` rows returned by list operations.
Pagination uses the returned `nextPageToken`; pass it as `pageToken` on the next
call and stop when it is absent. Filters supplied as arrays combine with AND.

Message bodies default to 64 KiB per body value. Use a smaller
`maxBodyValueBytes` or fewer message IDs when reading large messages; a value of
zero removes the body-value cap. Threads fetch messages in batches of 50 but
return the complete conversation, so large threads still produce large results.
Attachment metadata does not fetch message bodies. Downloads and uploads stream
through private session files; returned download URLs expire.

Moving, archiving, deleting, and destroying messages use batches of 50.
`deleteMessage(s)` moves mail to Trash; `destroyMessage(s)` permanently removes
it. A later batch can fail after earlier batches succeeded. Sending can also
succeed before a response is lost. These operations are never automatically
retried; inspect the mailbox before deciding whether to retry.
