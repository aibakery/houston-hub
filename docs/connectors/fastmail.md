# Fastmail operations

Provider-specific exported operations retain the documented request and pagination semantics.

Use an instance from houston.connectors(). API tokens stay on the server.
getProfile() returns emailAddress, accountId, name. listFolders() returns folders
with id/name/role; use an id or a role such as INBOX as a folder filter.

listMessages(opts?) returns messages ({id}[]) and nextPageToken. listThreads(opts?)
returns threads ({id}[]) with the same pagination. Loop until nextPageToken is nil;
a final page may be empty. Newest first. Filters: from, to, subject, text; after and
before (YYYY-MM-DD or UTC timestamp); folder/folders. Arrays combine with AND.
maxResults defaults to 100 (1–500); pageToken is opaque to callers. Spam/trash are
excluded unless a folder is explicit or includeSpamTrash=true. No Gmail q syntax.

getMessage(id, opts?) and getMessages(ids, opts?) return envelope strings (from, to,
cc, bcc, replyTo, subject, date, messageId), body, headers, received, and attachments.
Ids may be strings or {id}; getMessages accepts 1–50 ids or {ids={...}} and preserves
order. Body parts default to 64 KiB; bodyTruncated flags this. Set
opts.maxBodyValueBytes to change the cap (0 disables it). If a response exceeds
the proxy limit, request fewer messages or smaller bodies.
getThread(id, opts?) returns all messages in conversation order, fetching in batches.

listAttachments(id) returns metadata: id, filename, mimeType, size, inline, contentId.
getAttachment(messageId, attachmentId, path?) returns {path,url,size}; the URL is a
signed Houston download. getAttachments(messageId, items) downloads each attachment;
items is {{id,path?},...}. Bytes are stored in session files, never returned inline.

Writes appear only with read-write access. trashMessage(id) moves mail to Trash.
listIdentities() needs the token's Email submission scope and returns identities.
sendMessage({to={{email="recipient@example.com"}},subject="Hello",text="Hi"}) sends
plain text using your primary identity; optional identityId selects another identity.
cc, bcc, replyTo use the same address arrays. Sent mail is moved from Drafts to Sent.
The token needs Email and Email submission scopes without Read-only access.
If sending fails, inspect Drafts/Sent before retrying: delivery may have succeeded.

Example: return {run=function() return c.listMessages({folder="INBOX",maxResults=5}) end}
