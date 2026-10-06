# Google Drive operations

Provider-specific exported operations retain the documented request and pagination semantics.


Read files for one connected Google Drive account. Credentials stay on the
Houston server. This is the storage/drive contract: later file-drive
providers implement the same functions. Use the instance from
`houston.connectors()` — do not call provider URLs yourself.

List-connector signatures are enough to call. Return compact rows;
`truncate` defaults true. Loop pagination in one `run`.

## listFiles(opts?)

Search and list files. Rows already have `id`, `name`, `mime`, `size`,
`modified`, and `folder` (boolean) — do not `getFile` every row. Optional
filters on `opts`:

- `folder` (Drive folder id)
- `name`, `mime`, `text` (string, or array of strings)
- `after`, `before` (YYYY-MM-DD)
- `pageSize` or `maxResults` (number)
- `pageToken` (string)
- `orderBy` (string)
- `q` (raw Drive search string; escape hatch, compiled with the filters)

Filters are compiled to Drive `q` inside this module (`name contains`,
`mimeType =`, `'id' in parents`, `modifiedTime`, `fullText contains`).
Pass `q` only when you need a vendor clause the filters do not cover.

Returns `files` and `nextPageToken`. Loop pages in the same `run`.

## getFile(id, opts?)

One file. `id` may be a string or a table with `id`. Same shared fields as
`listFiles`, plus `webViewLink`, `webContentLink`, and `exportLinks` when
Drive provides them. Use those vendor links when you do not need to
process bytes — they do not include a Google access token.

`getFile("abc")` and `getFile({ id = "abc" })` are the same call.
This does not download file bytes into Houston.

## downloadFile(id, path, opts?)

Downloads file bytes onto the session path (streams past the proxy buffer)
and returns `{ path, url, bytes }` where `url` is a Houston signed GET URL.
Optional `opts.mimeType` uses Drive `files.export` for Google-native types.
Do not return the file bytes from `run`; give the caller the signed URL.

Write functions are bound only when this instance is read-write.

## createFile(meta?)

Drive `files.create`. `meta` is the File resource metadata (for example
`{ name = "notes.md", mimeType = "text/markdown" }`).

## deleteFile(id)

Drive `files.delete`. `id` may be a string or a table with `id`.

## uploadFile(path, meta?)

Uploads a session file (PUT bytes there first with `fs.signedPutUrl` when
the caller is sending a file). `meta` may include `name`, `mimeType`, and
`parents`. Streams the file through Houston; does not inline bytes in MCP.

## Example

	return {
		run = function()
			return c.listFiles({ folder = "root", name = "notes", pageSize = 10 })
		end,
	}
