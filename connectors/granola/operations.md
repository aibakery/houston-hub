# Granola operations

Provider-specific exported operations retain the documented request and pagination semantics.


# Granola

Read notes, folders, and transcripts for one connected Granola account.
Credentials stay on the Houston server; these functions only see JSON from
Granola.

Several Granola keys are several instances of this connector, each with
its own `id`. Use the instance returned by `houston.connectors()` — do not
call Granola URLs yourself.

List endpoints are paginated. When `hasMore` is true, pass the returned
`cursor` on the next call and loop in the same `run`.

## listNotes(opts?)

Granola `GET /v1/notes`. Date filters are **calendar dates**
(`YYYY-MM-DD`). RFC3339 datetimes (e.g. `2026-08-22T00:00:00-07:00`)
are coerced to `YYYY-MM-DD` before the request; a plain `YYYY-MM-DD`
is forwarded unchanged. Optional fields on `opts`:

- `created_after` (string, ISO 8601 date `YYYY-MM-DD`)
- `created_before` (string, ISO 8601 date `YYYY-MM-DD`)
- `updated_after` (string, ISO 8601 date `YYYY-MM-DD`)
- `folder_id` (string, `fol_…`)
- `cursor` (string)
- `page_size` (number, max 30)

Returns `notes` (`{ id, title, … }[]`), `hasMore`, and `cursor`.

## getNote(id, opts?)

Granola `GET /v1/notes/{note_id}`. `id` may be a string or a table with
`id`. Optional fields on `opts` (or on the table):

- `include`: `"transcript"` to inline the transcript when it fits
- `includeTranscript` (boolean) — same as `include = "transcript"`

If the transcript is too large, Granola returns `TRANSCRIPT_TOO_LARGE`;
use `getTranscript` and loop pages in one `run`.

## listFolders(opts?)

Granola `GET /v1/folders`. Optional fields on `opts`:

- `cursor` (string)
- `page_size` (number, max 30)

Returns `folders` (`{ id, name, parent_folder_id, … }[]`), `hasMore`,
and `cursor`.

## getTranscript(id, opts?)

Granola `GET /v1/notes/{note_id}/transcript`. `id` may be a string or a
table with `id`. Optional fields on `opts`:

- `cursor` (string)
- `page_size` (number, max 100)

Returns `transcript` (items with `speaker` and `text`), `hasMore`, and
`cursor`. Loop while `hasMore` in the same `run`.

## Example

	return {
		run = function()
			return c.listNotes({ page_size = 10 })
		end,
	}
