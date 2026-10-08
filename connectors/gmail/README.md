# Gmail

Read-only access to Gmail.

## Metadata operations

`listMailFolders()` takes no arguments and returns every available mail label as
`{id: string, name: string}[]`, sorted by ID. IDs are nonempty, unique within this
connection, and opaque. Names are display text and may repeat. Empty results are
arrays. Provider failures raise errors. `listFolders()` also remains available
for Gmail-specific label details.

Use configured functions and provider-specific help for the other operations.
