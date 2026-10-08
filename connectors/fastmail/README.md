---
description: Give agents access to Fastmail to find conversations, organize your inbox, and send replies.
---
# Fastmail

Connect agents to your Fastmail inbox so they can find important conversations,
read messages, and help you stay on top of email.

## Find what matters

- Find emails by person, topic, date, or folder.
- Read a whole conversation to catch up on the context.
- Download attachments and work with them alongside your other files.

## Keep your inbox moving

When you grant permission to send and organize mail, agents can also:

- Send emails or reply to a person or an entire conversation.
- Choose which email address to send from and include attachments.
- Create folders, move messages, archive finished conversations, and clear out
  mail you no longer need.

You choose whether agents can only read your mail or also make changes.
Your messages stay in Fastmail.

## Folder metadata for agents

`listMailFolders()` takes no arguments and returns every available folder as
`{id: string, name: string}[]`, sorted by ID. IDs are nonempty, unique within this
connection, and opaque; names are display text and may repeat. An empty mailbox
returns an empty array. Provider failures raise an error. `listFolders()` also
remains available for Fastmail-specific folder details.

Call the configured connection's help and inspect its available functions before
using provider-specific operations. Read-write settings expose mail-changing
functions, but each caller still needs an appropriate grant.

## Operation reference

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
Manual API token scopes are unknown during discovery; no live requests are made
to infer them. Available exports reflect configuration and caller grants, while
the first real operation checks the JMAP session and reports missing scopes.
Read this help before calling a mutation; never send or delete to test a signature.

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
getThread(id, opts?) returns `{id, messages}` in conversation order, fetching in batches.

listAttachments(id) returns metadata: id, filename, mimeType, size, inline, contentId.
getAttachment(messageId, attachmentId, path?) returns `{path, url, size}`; the URL is a
signed Houston download. getAttachments(messageId, items) downloads each attachment;
items is `{{id, path?}, ...}`. Bytes are stored in session files, never returned inline.
The default path is `attachments/<encoded-message-id>/<encoded-attachment-id>`;
batch paths must be distinct. The batch result is an ordered array of
`{path, url, size}`. Links expire; session files stay private to the caller and
execution workspace.

listAliases() returns `{aliases, notes}`. Each alias has email, canSend, and masked.
Sending identities include identityId and name. Masked addresses include maskedId,
state, description, and forDomain. An address that is both is one row with
canSend=true and masked=true. listIdentities() returns `{identities}` containing the raw JMAP identities
and needs Email submission.

Writes appear only when the connection is read-write and the caller has write access.
The available functions listed by the configured instance are authoritative; this
reference also describes functions that may be unavailable.

`sendMessage` and `replyMessage` return `{id, submissionId}`. `subject` defaults
to an empty string for sending; `text` and a nonempty `to` array are required.
Without `identityId` or `from`, sending uses the identity matching the account
username, or the sole identity; ambiguity is an error. `identityId` takes
precedence over `from`. Replying requires `text`; `all` defaults to false and
`subject` can override the derived reply subject. Optional `cc`, `bcc`, `replyTo`
and session-file `attachments` work for both operations. Attachment MIME type
defaults to `application/octet-stream` and filename to the path basename.

`createFolder` returns `{id, name}`; omitting `parent` creates a top-level folder.
Move, archive and delete return `{ids, folderId}`; `trashMessage` returns `{id}`.
Destroy returns `{ids}`. IDs accept strings or `{id}` rows. `archiveMessage` is
an alias of `archiveMessages`. Batch mutations use groups of 50 and can partially
complete before a failure. No mutation is automatically replayed.

- sendMessage({to={{email="recipient@example.com"}}, subject="Hello", text="Hi", from="alias@example.com", attachments={{path="files/brief.pdf", filename="brief.pdf", mimeType="application/pdf"}}}) sends plain text. `from` is an alias address; identityId still selects an identity directly. Attachments are session files uploaded to Fastmail, not inline base64. cc, bcc, and replyTo use the same address arrays. Sent mail moves from Drafts to Sent.
- replyMessage(id, {text="Thanks", from="other@example.com", all=true}) replies to Reply-To, or From when Reply-To is empty. The subject gains a `Re:` prefix unless it already has one. inReplyTo and references are set when the original message has a Message-ID. With no `from` or identityId, the sender is the identity that received the message (To, then Cc), otherwise the primary identity. `all=true` adds the other original To and Cc recipients, skipping your identities and the person you are replying to. `cc` replaces that list. Attachments work the same way as sendMessage.
- createFolder(name, parent?) creates a mailbox. parent is a folder id or a role such as INBOX.
- moveMessages(ids, folder) and moveMessage(id, folder) replace the message mailboxes with one destination. ids may be one id or a list. folder is an id or a role.
- archiveMessages(ids) moves mail to the Archive mailbox and fails if that mailbox does not exist.
- deleteMessage(ids) and deleteMessages(ids) move mail to Trash. trashMessage(id) does the same for one id.
- destroyMessage(ids) and destroyMessages(ids) permanently destroy the messages. Delete and destroy are different: delete is the Fastmail Trash action.

The token needs Email, and sending needs Email submission, without read-only access on the connection. If sending fails, inspect Drafts and Sent before retrying: delivery may have succeeded.

Example: return {run=function() return c.listMessages({folder="INBOX", alias="support@example.com", maxResults=5}) end}
