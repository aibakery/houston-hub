# Dropbox operations

Provider-specific exported operations retain the documented request and pagination semantics.


# Dropbox

Read files for one connected Dropbox account. Credentials stay on the
Houston server. This is the storage/drive contract: later file-drive
providers implement the same functions. Use the instance from
`houston.connectors()` — do not call provider URLs yourself.

List-connector signatures are enough to call. Return compact rows;
`truncate` defaults true. Loop pagination in one `run`.

## listFiles(opts?)

Search and list files. Rows already have `id`, `name`, `mime`, `size`,
`modified`, and `folder` (boolean) — do not `getFile` every row. `mime` is
best-effort from the name (folders match Drive's folder mime). Optional
filters on `opts`:

- `folder` (Dropbox path or `id:...`; default the connected root)
- `name`, `text` (search; `name` is filename-only)
- `mime`, `after`, `before` (best-effort local filter; YYYY-MM-DD)
- `pageSize` or `maxResults` (number)
- `pageToken` (string)

`folder` maps to a list-folder path. `name` / `text` use Dropbox search.
Do not call `/files/list_folder` yourself.

Returns `files` and `nextPageToken`. Loop pages in the same `run`.

## getFile(id, opts?)

One file. `id` may be a string or a table with `id` (Dropbox path or
`id:...`). Same shared fields as `listFiles`.

`getFile("id:abc")` and `getFile({ id = "id:abc" })` are the same call.
This does not download file bytes into Houston.

## downloadFile(id, path, opts?)

Downloads file bytes onto the session path (streams past the proxy buffer)
and returns `{ path, url, bytes }` where `url` is a Houston signed GET URL.
Do not return the file bytes from `run`; give the caller the signed URL.

## getCurrentAccount()

Dropbox account profile (`account_id`, `email`, `name`). Extra to this
provider; not part of the storage/drive contract.

## Example

	return {
		run = function()
			return c.listFiles({ folder = "/Reports", pageSize = 10 })
		end,
	}
