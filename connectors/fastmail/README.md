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
