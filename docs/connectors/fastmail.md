# Fastmail operations

Provider-specific exported operations retain the documented request and pagination semantics.

Use an instance from houston.connectors(). API tokens stay on the server.
Fastmail supplies API, upload, and download URLs in its JMAP session response.
The manifest owns destination checks: `api.fastmail.com`, its subdomains and
`jmap.fastmail.com` allow the declared JMAP routes; `fastmailusercontent.com` and
its subdomains allow only GET `/jmap/download/*`. Each rule lists all hosts sharing
its method/path filters and header action. Fastmail's current [security documentation](https://www.fastmail.help/hc/en-us/articles/1500000280221-How-Fastmail-provides-a-secure-service)
and [technical controls](https://www.fastmail.com/policies/dpa/annex2/) document
the separate attachment domain. Unexpected origins fail with the requested origin
in the error; URL paths and queries are omitted.

The token needs the JMAP Email scope. Sending and `listAliases` sending identities
also need Email submission. Masked addresses (Fastmail aliases that forward to the
account) also need the Masked Email scope. If a scope is missing, `listAliases`
returns the addresses it can see and explains the gap in `notes`. If neither
submission nor Masked Email is enabled, `listAliases` fails and names both scopes.

getProfile() returns emailAddress, accountId, name, capabilities, and canSend.
listFolders() returns folders with id, name, role, parentId, totalEmails, and
unreadEmails. Use an id or a role such as INBOX as a folder filter.
listMailFolders() returns Fastmail folder metadata as `{id, name}` rows sorted by id.

listMessages(opts?) returns messages (`{id}[]`) and nextPageToken. listThreads(opts?)
returns threads (`{id}[]`) with the same pagination. Loop until nextPageToken is nil;
a final page may be empty. Newest first. Filters: from, to, subject, text; after and
before (YYYY-MM-DD or UTC timestamp); folder/folders; alias or aliases. An alias
matches From, To, Cc, or Bcc for that address, and is combined with the other
filters. Arrays of from/to/subject/text/alias combine with AND. maxResults defaults
to 100 (1–500); pageToken is opaque to callers. Spam and trash are excluded unless
a folder is explicit or includeSpamTrash=true. No Gmail q syntax.

getMessage(id, opts?) and getMessages(ids, opts?) return envelope strings (from, to,
cc, bcc, replyTo, subject, date, messageId), body, headers, received, and attachments.
Ids may be strings or `{id}`; getMessages accepts 1–50 ids or `{ids={...}}` and preserves
order. Body parts default to 64 KiB; bodyTruncated flags this. Set
opts.maxBodyValueBytes to change the cap (0 disables it). If a response exceeds
the proxy limit, request fewer messages or smaller bodies.
getThread(id, opts?) returns all messages in conversation order, fetching in batches.

listAttachments(id) returns metadata: id, filename, mimeType, size, inline, contentId.
getAttachment(messageId, attachmentId, path?) returns `{path, url, size}`; the URL is a
signed Houston download. getAttachments(messageId, items) downloads each attachment;
items is `{{id, path?}, ...}`. Bytes are stored in session files, never returned inline.

listAliases() returns `{aliases, notes}`. Each alias has email, canSend, and masked.
Sending identities include identityId and name. Masked addresses include maskedId,
state, description, and forDomain. An address that is both is one row with
canSend=true and masked=true. listIdentities() still returns the raw JMAP identities
and needs Email submission.

Writes appear only with read-write access.

- sendMessage({to={{email="recipient@example.com"}}, subject="Hello", text="Hi", from="alias@example.com", attachments={{path="files/brief.pdf", filename="brief.pdf", mimeType="application/pdf"}}}) sends plain text. `from` is an alias address; identityId still selects an identity directly. Attachments are session files uploaded to Fastmail, not inline base64. cc, bcc, and replyTo use the same address arrays. Sent mail moves from Drafts to Sent.
- replyMessage(id, {text="Thanks", from="other@example.com", all=true}) replies to Reply-To, or From when Reply-To is empty. The subject gains a `Re:` prefix unless it already has one. inReplyTo and references are set when the original message has a Message-ID. With no `from` or identityId, the sender is the identity that received the message (To, then Cc), otherwise the primary identity. `all=true` adds the other original To and Cc recipients, skipping your identities and the person you are replying to. `cc` replaces that list. Attachments work the same way as sendMessage.
- createFolder(name, parent?) creates a mailbox. parent is a folder id or a role such as INBOX.
- moveMessages(ids, folder) and moveMessage(id, folder) replace the message mailboxes with one destination. ids may be one id or a list. folder is an id or a role.
- archiveMessages(ids) moves mail to the Archive mailbox and fails if that mailbox does not exist.
- deleteMessage(ids) and deleteMessages(ids) move mail to Trash. trashMessage(id) does the same for one id.
- destroyMessage(ids) and destroyMessages(ids) permanently destroy the messages. Delete and destroy are different: delete is the Fastmail Trash action.

The token needs Email, and sending needs Email submission, without read-only access on the connection. If sending fails, inspect Drafts and Sent before retrying: delivery may have succeeded.

Example: return {run=function() return c.listMessages({folder="INBOX", alias="support@example.com", maxResults=5}) end}
