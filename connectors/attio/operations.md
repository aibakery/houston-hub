# Attio operations

Provider-specific exported operations retain the documented request and pagination semantics.


# Attio

Read objects, records, notes, and CRM activity (emails, tasks, comments,
meetings, calls) for one connected Attio workspace. Credentials stay on
the Houston server; these functions only see JSON from Attio.

Several Attio keys are several instances of this connector, each with
its own `id`. Use the instance returned by `houston.connectors()` — do not
call Attio URLs yourself.

List endpoints are paginated with `limit` and `offset`, or with `cursor`
on emails, meetings, and files. Loop in the same `run`. For offset pages,
increase `offset` until a page returns fewer rows than `limit` (or an
empty `data` array). For cursor pages, keep calling while
`pagination.next_cursor` is set — email pages can be short while more
results remain.

CRM **activity** is meetings, tasks, and comment threads — not notes.
Notes often duplicate Granola. Return compact rows; `truncate` defaults
true. List-connector signatures are enough; call `help()` on this
instance for the full contract.

## identify()

Attio `GET /v2/self`. Returns the token and workspace (`active`,
`workspace_id`, `workspace_name`, `workspace_slug`, `scope`, …).

## listObjects()

Attio `GET /v2/objects`. Returns `data` (`{ id, api_slug, singular_noun,
plural_noun, … }[]`).

## queryRecords(object, opts?)

Attio `POST /v2/objects/{object}/records/query`. `object` is a slug or
id (`"people"`, `"companies"`, …), or a table with `object` / `api_slug`.
Optional fields on `opts`:

- `filter` (table)
- `filter_view_id` (string)
- `sorts` (table)
- `limit` (number, default 500)
- `offset` (number, default 0)

Returns `data` (records with `id.record_id` and `values`). Loop with
`offset` in one `run`.

## getRecord(object, recordId)

Attio `GET /v2/objects/{object}/records/{record_id}`. `object` and
`recordId` may be strings, or a table with `object` / `api_slug` and
`record_id` / `id`.

## searchRecords(query, opts?)

Attio `POST /v2/objects/records/search`. `query` is a string, or a table
with `query`. Optional fields on `opts` (or on the table):

- `objects` (string array of slugs or ids; required by Attio)
- `limit` (number, default 25, max 25)
- `request_as` (table; defaults to `{ type = "workspace" }`)

Results are eventually consistent. Use `queryRecords` for up-to-date
rows.

## listNotes(opts?)

Attio `GET /v2/notes`. Optional fields on `opts`:

- `limit` (number, default 10, max 50)
- `offset` (number, default 0)
- `parent_object` (string)
- `parent_record_id` (string)

Returns `data` (`{ id, title, created_at, parent_object,
parent_record_id, content_plaintext, … }[]`). Notes are **newest-first**:
stop paging when `created_at` leaves the window; do not walk the whole
workspace. Return compact rows (`id`, `title`, `created_at`, parent ids)
and `getNote` only for bodies. The same Granola-synced note often
appears on **company and deal** — dedup on title + `created_at`.
`limit` max is 50. Loop with `offset` in one `run`.

## getNote(id)

Attio `GET /v2/notes/{note_id}`. `id` may be a string or a table with
`note_id` / `id`. Use only for the few notes you brief; list rows do
not need full markdown.

## listEmails(opts?)

Attio `GET /v2/emails`. Metadata only — email **content** is never
returned. Requires the token `email:read` scope; without it the call
403s — use meetings/tasks/threads for CRM activity instead. At least
one of `linked_object`+`linked_record_ids`,
`participants`, or `domain` is required by Attio. Optional fields:

- `limit` (number, default 25, max 50)
- `cursor` (string)
- `linked_object` (string, people or companies)
- `linked_record_ids` (comma-separated record ids)
- `participants` (comma-separated email addresses)
- `domain` (string)
- `sent_after` / `sent_before` (timestamps)

Returns `data` (`{ id, subject_line, participants, sent_at, direction,
linked_records, … }[]`) and `pagination.next_cursor`. Loop on
`next_cursor` in one `run`.

## listTasks(opts?)

Attio `GET /v2/tasks`. Optional fields on `opts`:

- `limit` / `offset`
- `sort` (`created_at:asc`, `created_at:desc`, `completed_at:asc`, `completed_at:desc`)
- `linked_object` / `linked_record_id`
- `assignee` (email, member id, or `"null"`)
- `is_completed` (boolean)

Loop with `offset` in one `run`.

## getTask(id)

Attio `GET /v2/tasks/{task_id}`. `id` may be a string or a table with
`task_id` / `id`.

## listThreads(opts?)

Attio `GET /v2/threads`. There is no list-comments endpoint; threads
carry their comments. Optional fields:

- `record_id` + `object` (threads on a record)
- `entry_id` + `list` (threads on a list entry)
- `limit` (default 10, max 50) / `offset`

Each thread includes `comments` (`content_plaintext`, …). Loop with
`offset` in one `run`.

## getThread(id)

Attio `GET /v2/threads/{thread_id}`. Returns the thread and its comments.

## getComment(id)

Attio `GET /v2/comments/{comment_id}`. `id` may be a string or a table
with `comment_id` / `id`.

## listMeetings(opts?)

Attio `GET /v2/meetings`. Optional fields on `opts`:

- `limit` (default 50, max 200) / `cursor`
- `linked_object` / `linked_record_id`
- `participants` (comma-separated emails)
- `sort` (`start_asc`, `start_desc`)
- `ends_from` / `starts_before` / `timezone`

`participants` and `linked_record_id` are combined with OR. Loop on
`pagination.next_cursor` in one `run`.

## getMeeting(id)

Attio `GET /v2/meetings/{meeting_id}`.

## listCallRecordings(meetingId, opts?)

Attio `GET /v2/meetings/{meeting_id}/call_recordings`. `meetingId` may
be a string or a table with `meeting_id` / `id`.

## getCallRecording(meetingId, id)

Attio `GET /v2/meetings/{meeting_id}/call_recordings/{call_recording_id}`.
The response includes `transcript` (`segments`, `raw_transcript`) when
Attio has one.

## listLists()

Attio `GET /v2/lists`. Returns lists the token can access.

## getList(list)

Attio `GET /v2/lists/{list}`. `list` is a slug or id.

## queryListEntries(list, opts?)

Attio `POST /v2/lists/{list}/entries/query`. Same optional `filter`,
`filter_view_id`, `sorts`, `limit`, `offset` as `queryRecords`. Loop
with `offset` in one `run`.

## listWorkspaceMembers()

Attio `GET /v2/workspace_members`.

## getWorkspaceMember(id)

Attio `GET /v2/workspace_members/{workspace_member_id}`.

## listFiles(opts)

Attio `GET /v2/files`. Required on `opts`: `object` and `record_id`.
Optional: `storage_provider`, `parent_folder_id`, `limit`, `cursor`.
Loop on `pagination.next_cursor` in one `run`.

## getFile(id)

Attio `GET /v2/files/{file_id}`.

## listAttributes(target, identifier, opts?)

Attio `GET /v2/{target}/{identifier}/attributes`. `target` is
`"objects"` or `"lists"`; `identifier` is a slug or id. Optional
`limit`, `offset`, `show_archived`. Loop with `offset` in one `run`.

## Example

	return {
		run = function()
			return c.identify()
		end,
	}
