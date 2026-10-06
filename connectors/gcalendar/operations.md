# Google Calendar operations

Provider-specific exported operations retain the documented request and pagination semantics.


# Google Calendar

Read calendars and events for one connected Google Calendar account.
Credentials stay on the Houston server; these functions only see JSON from
Calendar.

Several Calendar accounts are several instances of this connector, each
with its own `id`. Use the instance returned by `houston.connectors()` — do
not call Calendar URLs yourself.

## listCalendars(opts?)

Calendar `calendarList.list`. Optional fields on `opts`:

- `maxResults` (number)
- `pageToken` (string)
- `minAccessRole` (string)
- `showDeleted` (boolean)
- `showHidden` (boolean)

Returns `items` (`{ id, summary, ... }[]`) and `nextPageToken`.

## listEvents(calendarId, opts?)

Calendar `events.list`. `calendarId` may be a string (e.g. `"primary"`)
or a table with `calendarId`. Optional fields on `opts`:

- `timeMin` / `timeMax` (RFC3339 strings)
- `maxResults` (number)
- `pageToken` (string)
- `q` (string)
- `singleEvents` (boolean)
- `orderBy` (string)
- `timeZone` (string)

Returns `items` (`{ id, summary, start, end, ... }[]`) and
`nextPageToken`. `listEvents` already has `id`, `summary`, `start`,
and `end`. Do not `getEvent` every row unless you need extra fields
(attendees, description, conference data). Loop pagination in one
`run`.

## getEvent(calendarId, eventId, opts?)

Calendar `events.get`. `calendarId` and `eventId` may be strings, or a
table with those fields. Optional `timeZone` on `opts`.

Returns the Event resource. Use only when `listEvents` is missing a
field you need.

Write functions are bound only when this instance is read-write.

## insertEvent(calendarId, event)

Calendar `events.insert`. `calendarId` may be a string (e.g. `"primary"`)
or a table with `calendarId` and `event`. `event` is the Event resource.

## deleteEvent(calendarId, eventId)

Calendar `events.delete`. `calendarId` and `eventId` may be strings, or a
table with those fields.

## Example

	return {
		run = function()
			return c.listEvents("primary", { maxResults = 10 })
		end,
	}
