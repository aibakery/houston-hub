# Dropbox

Read-only access to Dropbox files and account info.

## Metadata operations

`statFile(id)` takes exactly one nonempty provider ID scoped to this connection.
It returns `{id: string, name: string, isFolder: boolean, size?: integer}`.
Names are display text. Size is nonnegative bytes when known for a file; folders
and cloud-native documents may omit it. Missing or inaccessible IDs and provider
failures raise errors. Extra provider fields are excluded.

Use configured functions and provider-specific help for the other operations.
