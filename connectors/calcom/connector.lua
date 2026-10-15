-- Cal.com API v2. Arguments and results keep Cal.com's native camelCase fields.
type Options = {[string]: any}
type Endpoint = {
	method: string, path: string, version: string?, query: {string}?, extra: {string}?, required: {string}?,
	write: boolean?, body: (boolean | string)?, doc: string, about: string,
}

local PROVIDER = "Cal.com"
local API = "https://api.cal.com"
local DOCS = "https://cal.com/docs/api-reference/v2/"

-- Cal.com versions each controller with a cal-api-version header; without the expected
-- value an endpoint silently falls back to its legacy behavior, or does not exist.
local BOOKINGS = "2026-02-25"
local BOOKING_LIST = "2026-05-01"
local BOOKING_DETAILS = "2024-08-13"
local EVENT_TYPES = "2026-06-12"
local SLOTS = "2024-09-04"
local PRIVATE_LINKS = "2024-09-04"
local SCHEDULES = "2024-06-11"
local WORKFLOWS = "2026-09-22"

local function list(...: {string}): {string}
	local fields: {string} = {}
	for _, group in {...} do table.move(group, 1, #group, #fields + 1, fields) end
	return fields
end
local PAGE = {"take", "skip"}
local BOOKING_FILTERS = {"status", "attendeeEmail", "attendeeName", "bookingUid", "eventTypeIds", "eventTypeId", "afterStart", "beforeEnd",
	"afterCreatedAt", "beforeCreatedAt", "afterUpdatedAt", "beforeUpdatedAt", "sortStart", "sortEnd", "sortCreated", "sortUpdatedAt"}
local SLOT_OPTIONS = {"start", "end", "timeZone", "duration", "format", "bookingUidToReschedule"}

-- Operations in Cal.com's public OpenAPI that a user API key can call, checked on
-- 2026-10-14. Path {fields} and listed query fields are taken from the options; the
-- other fields form the JSON body (see hasBody). Webhook reads are writes because they
-- return signing secrets; the routing-form slot calculation only reads.
local endpoints: {[string]: Endpoint} = {
	getMe = {method = "GET", path = "/v2/me", doc = "me/get-my-profile", about = "The connected user: id, username, email, timeZone, defaultScheduleId, ..."},
	updateMe = {method = "PATCH", path = "/v2/me", doc = "me/update-my-profile",
		about = "Body {name?, email?, timeZone?, timeFormat? (12 or 24), weekStart?, defaultScheduleId?, locale?, bio?, avatarUrl?, metadata?}."},
	listOutOfOffice = {method = "GET", path = "/v2/me/ooo", doc = "out-of-office/get-all-out-of-office-entries-for-the-authenticated-user",
		query = list(PAGE, {"sortStart", "sortEnd"}), about = "Out-of-office entries."},
	createOutOfOffice = {method = "POST", path = "/v2/me/ooo", doc = "out-of-office/create-an-out-of-office-entry-for-the-authenticated-user",
		about = "Body {start, end, reason? (unspecified, vacation, travel, sick or public_holiday), notes?, toUserId? (redirect bookings)}."},
	updateOutOfOffice = {method = "PATCH", path = "/v2/me/ooo/{oooId}", doc = "out-of-office/update-an-out-of-office-entry-for-the-authenticated-user",
		about = "Body: the createOutOfOffice fields to change."},
	deleteOutOfOffice = {method = "DELETE", path = "/v2/me/ooo/{oooId}", doc = "out-of-office/delete-an-out-of-office-entry-for-the-authenticated-user", about = "Deletes an entry."},

	listBookings = {method = "GET", path = "/v2/bookings", version = BOOKING_LIST, doc = "bookings/get-all-bookings",
		query = list(BOOKING_FILTERS, {"teamsIds", "teamId", "cursor", "limit"}),
		about = "Bookings you host or attend. status: upcoming, recurring, past, cancelled or unconfirmed (one per call). limit is 1..100 (default 50); continue with cursor=pagination.nextCursor while pagination.hasMore."},
	getBooking = {method = "GET", path = "/v2/bookings/{bookingUid}", version = BOOKINGS, doc = "bookings/get-a-booking", about = "A booking with its attendees, location and status."},
	getBookingBySeat = {method = "GET", path = "/v2/bookings/by-seat/{seatUid}", version = BOOKINGS, doc = "bookings/get-a-booking-by-seat-uid", about = "The booking holding a seat."},
	createBooking = {method = "POST", path = "/v2/bookings", version = BOOKINGS, doc = "bookings/create-a-booking",
		about = "Body {start, attendee={name, email, timeZone, phoneNumber?, language?}, eventTypeId (or eventTypeSlug with username or teamSlug), guests?, location?, lengthInMinutes?, bookingFieldsResponses?, metadata?}. Take start from getSlots. Add recurrenceCount for recurring event types. Cal.com emails the attendees and hosts."},
	cancelBooking = {method = "POST", path = "/v2/bookings/{bookingUid}/cancel", version = BOOKINGS, doc = "bookings/cancel-a-booking",
		about = "Body {cancellationReason?, cancelSubsequentBookings?}, or {seatUid, cancellationReason?} for one seat. Notifies attendees."},
	rescheduleBooking = {method = "POST", path = "/v2/bookings/{bookingUid}/reschedule", version = BOOKINGS, doc = "bookings/reschedule-a-booking",
		about = "Body {start, reschedulingReason?, rescheduledBy?, lengthInMinutes?}, plus seatUid for a seat. Creates a new booking uid and notifies attendees."},
	requestBookingReschedule = {method = "POST", path = "/v2/bookings/{bookingUid}/request-reschedule", version = BOOKINGS, doc = "bookings/request-to-reschedule-a-booking",
		about = "Body {rescheduleReason?}. Cancels the booking and asks the attendee to pick a new time."},
	confirmBooking = {method = "POST", path = "/v2/bookings/{bookingUid}/confirm", version = BOOKINGS, body = false, doc = "bookings/confirm-a-booking", about = "Accepts a booking that requires confirmation."},
	declineBooking = {method = "POST", path = "/v2/bookings/{bookingUid}/decline", version = BOOKINGS, doc = "bookings/decline-a-booking",
		about = "Body {reason?}. Rejects a booking that requires confirmation."},
	markBookingAbsence = {method = "POST", path = "/v2/bookings/{bookingUid}/mark-absent", version = BOOKINGS, doc = "bookings/mark-a-booking-absence",
		about = "Body {host?, attendees?={{email, absent}}}. Records no-shows after the meeting."},
	reassignBooking = {method = "POST", path = "/v2/bookings/{bookingUid}/reassign", version = BOOKINGS, body = false, doc = "bookings/reassign-a-booking-to-auto-selected-host",
		about = "Moves a round-robin booking to another available host."},
	reassignBookingToUser = {method = "POST", path = "/v2/bookings/{bookingUid}/reassign/{userId}", version = BOOKINGS, doc = "bookings/reassign-a-booking-to-a-specific-host",
		about = "Body {reason?}. Moves a round-robin booking to the given host."},
	getBookingReferences = {method = "GET", path = "/v2/bookings/{bookingUid}/references", version = BOOKINGS, doc = "bookings/get-booking-references",
		query = {"type"}, about = "Calendar events and video meetings created for a booking."},
	getBookingRecordings = {method = "GET", path = "/v2/bookings/{bookingUid}/recordings", version = BOOKINGS, doc = "bookings/get-all-the-recordings-for-the-booking", about = "Cal Video recordings."},
	getBookingTranscripts = {method = "GET", path = "/v2/bookings/{bookingUid}/transcripts", version = BOOKINGS,
		doc = "bookings/get-cal-video-real-time-transcript-download-links-for-the-booking", about = "Cal Video transcript download links."},
	getBookingConferencingSessions = {method = "GET", path = "/v2/bookings/{bookingUid}/conferencing-sessions", version = BOOKINGS,
		doc = "bookings/get-video-meeting-sessions-only-supported-for-cal-video", about = "Cal Video sessions with participants and join times."},
	getBookingCalendarLinks = {method = "GET", path = "/v2/bookings/{bookingUid}/calendar-links", version = BOOKINGS,
		doc = "bookings/get-add-to-calendar-links-for-a-booking", about = "Add-to-calendar links for Google, Outlook, Yahoo and ICS."},
	updateBookingLocation = {method = "PATCH", path = "/v2/bookings/{bookingUid}/location", version = BOOKING_DETAILS,
		doc = "bookings/update-booking-location-for-an-existing-booking", about = "Body {location={type, ...}}. Changes where the meeting takes place."},
	listBookingAttendees = {method = "GET", path = "/v2/bookings/{bookingUid}/attendees", version = BOOKING_DETAILS,
		doc = "bookings-attendees/get-all-attendees-for-a-booking", about = "Attendees of a booking."},
	getBookingAttendee = {method = "GET", path = "/v2/bookings/{bookingUid}/attendees/{attendeeId}", version = BOOKING_DETAILS,
		doc = "bookings-attendees/get-a-specific-attendee-for-a-booking", about = "An attendee."},
	addBookingAttendee = {method = "POST", path = "/v2/bookings/{bookingUid}/attendees", version = BOOKING_DETAILS,
		doc = "bookings-attendees/add-an-attendee-to-a-booking", about = "Body {name, email, timeZone, phoneNumber?, language?}. Notifies the new attendee."},
	addBookingGuests = {method = "POST", path = "/v2/bookings/{bookingUid}/guests", version = BOOKING_DETAILS,
		doc = "bookings-guests/add-guests-to-an-existing-booking", about = "Body {guests={{email, name?, timeZone?}}}: at most 10 per call and 30 per booking. Notifies the guests."},
	getBookingRoutingTrace = {method = "GET", path = "/v2/bookings/{bookingUid}/routing-trace", version = BOOKING_DETAILS,
		doc = "bookings-routing-trace/get-the-routing-trace-for-a-booking", about = "How a routing form chose the booking's host."},

	listEventTypes = {method = "GET", path = "/v2/event-types", version = EVENT_TYPES, doc = "event-types/list-event-types",
		query = {"username", "eventSlug", "usernames", "orgSlug", "orgId", "sortCreatedAt"},
		about = "Your event types without filters, or another user's public ones by username (and eventSlug)."},
	getEventType = {method = "GET", path = "/v2/event-types/{eventTypeId}", version = EVENT_TYPES, doc = "event-types/get-an-event-type", about = "An event type."},
	createEventType = {method = "POST", path = "/v2/event-types", version = EVENT_TYPES, doc = "event-types/create-an-event-type",
		about = "Body {title, slug, lengthInMinutes, description?, locations?, bookingFields?, scheduleId?, hidden?, ...}."},
	updateEventType = {method = "PATCH", path = "/v2/event-types/{eventTypeId}", version = EVENT_TYPES, doc = "event-types/update-an-event-type",
		about = "Body: the createEventType fields to change."},
	deleteEventType = {method = "DELETE", path = "/v2/event-types/{eventTypeId}", version = EVENT_TYPES, doc = "event-types/delete-an-event-type", about = "Deletes an event type."},
	getEventTypeSchedulingConfig = {method = "GET", path = "/v2/event-types/{eventTypeId}/scheduling-config", version = EVENT_TYPES,
		doc = "event-types/get-scheduling-configuration", about = "Availability, limits and buffers that decide an event type's slots."},
	getEventTypeHistory = {method = "GET", path = "/v2/event-types/{eventTypeId}/history", version = EVENT_TYPES, doc = "event-types/get-event-type-history",
		query = {"cursor", "limit"}, about = "Changes made to an event type; limit is 1..50."},
	getBookingFields = {method = "GET", path = "/v2/event-types/{eventTypeId}/booking-fields", version = EVENT_TYPES, doc = "event-types/get-booking-fields",
		about = "Questions the booking form asks."},
	addBookingFields = {method = "POST", path = "/v2/event-types/{eventTypeId}/booking-fields", version = EVENT_TYPES, doc = "event-types/add-custom-booking-fields",
		about = "Body {bookingFields={{type, slug, label, required, ...}}}. Adds custom questions."},
	updateBookingFields = {method = "PATCH", path = "/v2/event-types/{eventTypeId}/booking-fields", version = EVENT_TYPES, doc = "event-types/update-booking-fields",
		about = "Body {bookingFields}. Changes the questions with matching slugs."},
	replaceBookingFields = {method = "PUT", path = "/v2/event-types/{eventTypeId}/booking-fields", version = EVENT_TYPES, doc = "event-types/replace-booking-fields",
		about = "Body {bookingFields}. Replaces every question."},
	deleteBookingField = {method = "DELETE", path = "/v2/event-types/{eventTypeId}/booking-fields/{slug}", version = EVENT_TYPES,
		doc = "event-types/delete-a-custom-booking-field", about = "Deletes a custom question."},
	listEventTypeWebhooks = {method = "GET", path = "/v2/event-types/{eventTypeId}/webhooks", write = true, doc = "event-types-webhooks/get-all-webhooks",
		query = PAGE, about = "Webhooks of an event type."},
	getEventTypeWebhook = {method = "GET", path = "/v2/event-types/{eventTypeId}/webhooks/{webhookId}", write = true, doc = "event-types-webhooks/get-a-webhook", about = "A webhook."},
	createEventTypeWebhook = {method = "POST", path = "/v2/event-types/{eventTypeId}/webhooks", doc = "event-types-webhooks/create-a-webhook",
		about = "Body as createWebhook, for one event type's bookings."},
	updateEventTypeWebhook = {method = "PATCH", path = "/v2/event-types/{eventTypeId}/webhooks/{webhookId}", doc = "event-types-webhooks/update-a-webhook",
		about = "Body: the createWebhook fields to change."},
	deleteEventTypeWebhook = {method = "DELETE", path = "/v2/event-types/{eventTypeId}/webhooks/{webhookId}", doc = "event-types-webhooks/delete-a-webhook", about = "Deletes a webhook."},
	listPrivateLinks = {method = "GET", path = "/v2/event-types/{eventTypeId}/private-links", version = PRIVATE_LINKS,
		doc = "event-types-private-links/get-all-private-links-for-an-event-type", about = "Private booking links of an event type."},
	createPrivateLink = {method = "POST", path = "/v2/event-types/{eventTypeId}/private-links", version = PRIVATE_LINKS,
		doc = "event-types-private-links/create-a-private-link-for-an-event-type", about = "Body {expiresAt?, maxUsageCount?}. Returns a booking URL for a hidden event type."},
	updatePrivateLink = {method = "PATCH", path = "/v2/event-types/{eventTypeId}/private-links/{linkId}", version = PRIVATE_LINKS,
		doc = "event-types-private-links/update-a-private-link-for-an-event-type", about = "Body {expiresAt?, maxUsageCount?}."},
	deletePrivateLink = {method = "DELETE", path = "/v2/event-types/{eventTypeId}/private-links/{linkId}", version = PRIVATE_LINKS,
		doc = "event-types-private-links/delete-a-private-link-for-an-event-type", about = "Disables a private link."},

	listWebhooks = {method = "GET", path = "/v2/webhooks", write = true, doc = "webhooks/get-all-webhooks", query = PAGE, about = "Your webhooks for all your bookings."},
	getWebhook = {method = "GET", path = "/v2/webhooks/{webhookId}", write = true, doc = "webhooks/get-a-webhook", about = "A webhook."},
	createWebhook = {method = "POST", path = "/v2/webhooks", doc = "webhooks/create-a-webhook",
		about = "Body {subscriberUrl, triggers={'BOOKING_CREATED', ...}, active, secret?, payloadTemplate?}. Cal.com then posts those events to subscriberUrl, a receiver you control."},
	updateWebhook = {method = "PATCH", path = "/v2/webhooks/{webhookId}", doc = "webhooks/update-a-webhook", about = "Body: the createWebhook fields to change."},
	deleteWebhook = {method = "DELETE", path = "/v2/webhooks/{webhookId}", doc = "webhooks/delete-a-webhook", about = "Deletes a webhook."},

	getSlots = {method = "GET", path = "/v2/slots", version = SLOTS, doc = "slots/get-available-time-slots-for-an-event-type",
		query = list(SLOT_OPTIONS, {"eventTypeId", "eventTypeSlug", "username", "usernames", "teamSlug", "organizationSlug"}), required = {"start", "end"},
		about = "Bookable times between start and end, as data keyed by date with {start} slots ({start, end} with format='range'). Pass eventTypeId, or eventTypeSlug with username or teamSlug."},
	reserveSlot = {method = "POST", path = "/v2/slots/reservations", version = SLOTS, doc = "slots/reserve-a-slot",
		about = "Body {eventTypeId, slotStart, slotDuration?, reservationDuration? (minutes, default 5)}. Holds a slot while booking."},
	getSlotReservation = {method = "GET", path = "/v2/slots/reservations/{reservationUid}", version = SLOTS, doc = "slots/get-reserved-slot", about = "A slot reservation."},
	updateSlotReservation = {method = "PATCH", path = "/v2/slots/reservations/{reservationUid}", version = SLOTS, doc = "slots/update-a-reserved-slot",
		about = "Body as reserveSlot."},
	deleteSlotReservation = {method = "DELETE", path = "/v2/slots/reservations/{reservationUid}", version = SLOTS, doc = "slots/delete-a-reserved-slot", about = "Releases a slot."},

	listSchedules = {method = "GET", path = "/v2/schedules", version = SCHEDULES, doc = "schedules/get-all-schedules", about = "Your availability schedules."},
	getDefaultSchedule = {method = "GET", path = "/v2/schedules/default", version = SCHEDULES, doc = "schedules/get-default-schedule", about = "Your default schedule."},
	getSchedule = {method = "GET", path = "/v2/schedules/{scheduleId}", version = SCHEDULES, doc = "schedules/get-a-schedule", about = "A schedule."},
	createSchedule = {method = "POST", path = "/v2/schedules", version = SCHEDULES, doc = "schedules/create-a-schedule",
		about = "Body {name, timeZone, isDefault, availability?={{days={'Monday', ...}, startTime='09:00', endTime='17:00'}}, overrides?={{date, startTime, endTime}}}."},
	updateSchedule = {method = "PATCH", path = "/v2/schedules/{scheduleId}", version = SCHEDULES, doc = "schedules/update-a-schedule",
		about = "Body: the createSchedule fields to change; availability and overrides are replaced whole."},
	deleteSchedule = {method = "DELETE", path = "/v2/schedules/{scheduleId}", version = SCHEDULES, doc = "schedules/delete-a-schedule", about = "Deletes a schedule."},

	listCalendars = {method = "GET", path = "/v2/calendars", doc = "calendars/get-all-calendars",
		about = "Connected calendars, the calendars checked for conflicts and the destination calendar, with credential IDs."},
	getBusyTimes = {method = "GET", path = "/v2/calendars/busy-times", doc = "calendars/get-busy-times",
		query = {"dateFrom", "dateTo", "timeZone", "calendar"}, required = {"dateFrom", "dateTo", "calendar"},
		about = "Busy intervals in connected calendars. calendar is an array of one or more 'credentialId,externalId' from listCalendars."},
	listConferencingApps = {method = "GET", path = "/v2/conferencing", doc = "conferencing/list-your-conferencing-applications", about = "Installed video apps."},
	getDefaultConferencingApp = {method = "GET", path = "/v2/conferencing/default", doc = "conferencing/get-your-default-conferencing-application", about = "Your default video app."},
	setDefaultConferencingApp = {method = "POST", path = "/v2/conferencing/{app}/default", body = false, doc = "conferencing/set-your-default-conferencing-application",
		about = "Makes an installed app the default: google-meet, zoom, msteams or daily-video."},
	calculateRoutingFormSlots = {method = "POST", path = "/v2/routing-forms/{routingFormId}/calculate-slots", write = false, body = "answers",
		doc = "routing-forms/calculate-slots-based-on-routing-form-response", query = list(SLOT_OPTIONS, {"rescheduleWithSameHost"}), required = {"start", "end"},
		about = "answers: the form answers keyed by field. Returns the routed event type and its slots without saving a response."},

	listVerifiedEmails = {method = "GET", path = "/v2/verified-resources/emails", doc = "verified-resources/get-list-of-verified-emails", query = PAGE,
		about = "Emails verified for workflow messages."},
	getVerifiedEmail = {method = "GET", path = "/v2/verified-resources/emails/{id}", doc = "verified-resources/get-verified-email-by-id", about = "A verified email."},
	requestEmailVerificationCode = {method = "POST", path = "/v2/verified-resources/emails/verification-code/request", doc = "verified-resources/request-email-verification-code",
		about = "Body {email}. Emails a verification code."},
	verifyEmail = {method = "POST", path = "/v2/verified-resources/emails/verification-code/verify", doc = "verified-resources/verify-an-email", about = "Body {email, code}."},
	listVerifiedPhones = {method = "GET", path = "/v2/verified-resources/phones", doc = "verified-resources/get-list-of-verified-phone-numbers", query = PAGE,
		about = "Phone numbers verified for workflow messages."},
	getVerifiedPhone = {method = "GET", path = "/v2/verified-resources/phones/{id}", doc = "verified-resources/get-verified-phone-number-by-id", about = "A verified phone number."},
	requestPhoneVerificationCode = {method = "POST", path = "/v2/verified-resources/phones/verification-code/request",
		doc = "verified-resources/request-phone-number-verification-code", about = "Body {phone}. Texts a verification code."},
	verifyPhone = {method = "POST", path = "/v2/verified-resources/phones/verification-code/verify", doc = "verified-resources/verify-a-phone-number", about = "Body {phone, code}."},

	listWorkflows = {method = "GET", path = "/v2/workflows", version = WORKFLOWS, doc = "workflows/get-your-workflows", query = PAGE,
		about = "Automated reminders and follow-ups."},
	getWorkflow = {method = "GET", path = "/v2/workflows/{workflowId}", version = WORKFLOWS, doc = "workflows/get-your-workflow", about = "A workflow."},
	getWorkflowConditionFields = {method = "GET", path = "/v2/workflows/{workflowId}/condition-fields", version = WORKFLOWS,
		doc = "workflows/get-the-fields-a-workflows-conditions-can-read", about = "Fields a workflow's conditions can test."},
	createWorkflow = {method = "POST", path = "/v2/workflows", version = WORKFLOWS, doc = "workflows/create-a-workflow",
		about = "Body {name, activation, trigger, steps}. Steps send emails or texts to attendees or hosts."},
	updateWorkflow = {method = "PATCH", path = "/v2/workflows/{workflowId}", version = WORKFLOWS, doc = "workflows/update-your-workflow",
		about = "Body: the createWorkflow fields to change."},
	deleteWorkflow = {method = "DELETE", path = "/v2/workflows/{workflowId}", version = WORKFLOWS, doc = "workflows/delete-your-workflow", about = "Deletes a workflow."},

	listTeams = {method = "GET", path = "/v2/teams", doc = "teams/get-teams", about = "Teams you belong to."},
	getTeam = {method = "GET", path = "/v2/teams/{teamId}", doc = "teams/get-a-team", about = "A team."},
	listTeamBookings = {method = "GET", path = "/v2/teams/{teamId}/bookings", doc = "teams-bookings/get-team-bookings",
		query = list(BOOKING_FILTERS, PAGE), about = "A team's bookings. status is one value or a comma-separated string such as 'upcoming,past'; take is 1..250 (default 100)."},
	listTeamEventTypes = {method = "GET", path = "/v2/teams/{teamId}/event-types", version = EVENT_TYPES, doc = "team-event-types/list-team-event-types",
		query = {"eventSlug", "hostsLimit", "sortCreatedAt"}, about = "A team's event types."},
	getTeamEventType = {method = "GET", path = "/v2/teams/{teamId}/event-types/{eventTypeId}", version = EVENT_TYPES, doc = "team-event-types/get-a-team-event-type",
		about = "A team event type with its hosts."},
	listTeamMemberships = {method = "GET", path = "/v2/teams/{teamId}/memberships", doc = "teams-memberships/get-all-memberships",
		query = list(PAGE, {"emails"}), about = "Team members and their roles."},
	listTeamSchedules = {method = "GET", path = "/v2/teams/{teamId}/schedules", doc = "teams-schedules/get-all-team-member-schedules", query = PAGE,
		about = "Availability schedules of team members."},

	listTimezones = {method = "GET", path = "/v2/timezones", doc = "timezones/get-timezones", query = {"search", "limit"}, about = "Supported time zones."},
}

-- Request layer shared verbatim by the Cal.com, Calendly and Resend connectors (tools/validate
-- checks they match). It uses each connector's PROVIDER, DOCS and Endpoint type.
local NULL = json.decode("null")
local NONE: {string} = table.freeze({})

local function options(input: Options?): Options
	if input == nil then return {} end
	assert(type(input) == "table", "opts must be an object")
	for key in input do assert(type(key) == "string", "opts must have named fields") end
	return table.clone(input)
end

local function scalar(value: any, field: string): string
	local kind = type(value)
	assert(kind == "string" or kind == "boolean" or kind == "number", field .. " must be a string, boolean, number or array of those")
	return url.encode(value)
end

-- Only GET reads unless write says otherwise.
local function writes(endpoint: Endpoint): boolean
	if endpoint.write ~= nil then return endpoint.write end
	return endpoint.method ~= "GET"
end

-- POST, PATCH and PUT send the remaining options as the JSON body unless body is false
-- (no body) or names the one option to send.
local function hasBody(endpoint: Endpoint): boolean
	return endpoint.body ~= false and (endpoint.method == "POST" or endpoint.method == "PATCH" or endpoint.method == "PUT")
end

local function fail(name: string, response: HttpResponse, message: string): never
	return houston.fail({operation = name, layer = "upstream", upstream_status = response.statusCode,
		retryable = response.statusCode == 429 or response.statusCode >= 500, message = message})
end

-- A successful response's JSON object, or nil when a write answers without a body.
local function object(name: string, endpoint: Endpoint, response: HttpResponse): Options?
	local raw = await(response.body:readAll())
	if endpoint.method ~= "GET" and string.match(raw, "^%s*$") then return nil end
	local ok, value = pcall(json.decode, raw)
	if not ok or type(value) ~= "table" or not string.match(raw, "^%s*{") then
		fail(name, response, PROVIDER .. " returned an invalid JSON object")
	end
	return value
end

-- name({path fields, query fields?, extra fields?, ...body}) built from the endpoint itself.
-- Extra fields are options the connector's own request consumes, such as a request header.
local function signature(endpoint: Endpoint): string
	local fields: {string} = {}
	for field in string.gmatch(endpoint.path, "{([%w_]+)}") do table.insert(fields, field) end
	for _, group in {endpoint.query or NONE, endpoint.extra or NONE} do
		for _, field in group do
			table.insert(fields, if table.find(endpoint.required or NONE, field) then field else field .. "?")
		end
	end
	if type(endpoint.body) == "string" then
		table.insert(fields, endpoint.body)
	elseif hasBody(endpoint) then
		table.insert(fields, "...body")
	end
	return "({" .. table.concat(fields, ", ") .. "})"
end

-- A function for each endpoint the connection's access allows, and help listing them after intro.
local function operations(endpoints: {[string]: Endpoint}, request: (string, Endpoint, Options?) -> any, intro: {string}): {[string]: any}
	local exports: {[string]: any} = {}
	for name, endpoint in endpoints do
		if not writes(endpoint) or config.access == "read-write" then
			exports[name] = function(args: Options?): any return request(name, endpoint, args) end
		end
	end
	exports.help = function(): string
		local names: {string} = {}
		for name in exports do if name ~= "help" then table.insert(names, name) end end
		table.sort(names)
		local lines = table.clone(intro)
		table.insert(lines, "Each function below names its route and reference page, " .. DOCS .. "<page>.")
		for _, name in names do
			local endpoint = endpoints[name]
			table.insert(lines, name .. signature(endpoint) .. ": " .. endpoint.about .. " " .. endpoint.method .. " " .. endpoint.path .. " (" .. endpoint.doc .. ")")
		end
		return table.concat(lines, "\n")
	end
	return exports
end
-- End of the shared request layer.

-- Event types, schedules, teams and users have numeric IDs; bookings, seats, webhooks,
-- reservations and links have string IDs; apps and booking fields have slugs.
local function identifier(value: any, field: string): string
	if type(value) == "number" then
		assert(value >= 0 and value % 1 == 0 and value <= 9007199254740991, field .. " must be a nonnegative integer ID")
		return string.format("%d", value)
	end
	assert(type(value) == "string" and string.match(value, "^[%w_%-]+$"), field .. " must be an ID, uid or slug")
	return value
end

-- Arrays repeat their key (calendar=a&calendar=b), as Cal.com's busy times require; other
-- lists, such as eventTypeIds, are comma-separated strings.
local function queryPairs(parts: {string}, field: string, value: any)
	if type(value) ~= "table" then
		table.insert(parts, field .. "=" .. scalar(value, field))
		return
	end
	local count = 0
	for index, item in value do
		count += 1
		assert(type(index) == "number" and index == count, field .. " must be an array, not an object")
		table.insert(parts, field .. "=" .. scalar(item, field))
	end
	assert(count > 0, field .. " must not be an empty array")
end

-- Cal.com errors are {status="error", error={code, message, details?}}.
local function errorMessage(status: number, value: any): string
	local message = "Cal.com HTTP " .. tostring(status)
	local problem = if type(value) == "table" and type(value.error) == "table" then value.error else nil
	if problem then
		if type(problem.code) == "string" then message ..= " (" .. problem.code .. ")" end
		if type(problem.message) == "string" then message ..= ": " .. string.sub(problem.message, 1, 600) end
		if problem.details ~= nil then message ..= " " .. string.sub(json.encode(problem.details), 1, 600) end
	end
	return message
end

local function failStatus(name: string, response: HttpResponse): never
	local ok, value = pcall(json.decode, await(response.body:readPrefix(16 * 1024)))
	local message = errorMessage(response.statusCode, if ok then value else nil)
	local retry = response.headers["retry-after"]
	if retry and retry[1] then message ..= "; Retry-After: " .. retry[1] end
	return fail(name, response, message)
end

local function decode(name: string, endpoint: Endpoint, response: HttpResponse): any
	if response.statusCode < 200 or response.statusCode >= 300 then failStatus(name, response) end
	local value = object(name, endpoint, response)
	-- Some deletions, such as deleteWorkflow, succeed without a body.
	if value == nil then return {status = "success"} end
	if value.status ~= "success" then fail(name, response, errorMessage(response.statusCode, value)) end
	return value
end

local function request(name: string, endpoint: Endpoint, input: Options?): any
	local args = options(input)
	local path = string.gsub(endpoint.path, "{([%w_]+)}", function(field: string)
		local id = identifier(args[field], field)
		args[field] = nil
		return id
	end)
	for _, field in endpoint.required or NONE do
		assert(args[field] ~= nil and args[field] ~= NULL, field .. " is required")
	end
	local query: {string} = {}
	for _, field in endpoint.query or NONE do
		if args[field] ~= nil then queryPairs(query, field, args[field]) end
		args[field] = nil
	end
	if #query > 0 then path ..= "?" .. table.concat(query, "&") end
	local headers: HttpHeaders = {Accept = {"application/json"}}
	if endpoint.version then headers["cal-api-version"] = {endpoint.version} end
	local body: string? = nil
	if type(endpoint.body) == "string" then
		local field = endpoint.body
		assert(type(args[field]) == "table", field .. " must be an object")
		body = json.encode(args[field])
		args[field] = nil
	elseif hasBody(endpoint) then
		body = json.encode(args)
		args = {}
	end
	local unknown = next(args)
	assert(unknown == nil, name .. " has no option " .. tostring(unknown))
	if body then headers["Content-Type"] = {"application/json"} end
	return decode(name, endpoint, await(http.request({method = endpoint.method, url = API .. path, headers = headers, body = body})))
end

return operations(endpoints, request, {
	"Cal.com API v2. Every function takes one named options object with Cal.com's camelCase names; ? marks optional fields and ...body the JSON body fields. end is a Luau keyword, so write it as ['end']='2026-10-22'. In bodies, pass json.decode('[]') for empty arrays and json.decode('null') to clear a field. Results are Cal.com's JSON unchanged: {status='success', data, pagination?}; a write without a response body returns {status='success'}. The connector sends each endpoint's cal-api-version. Connector calls return completed values: use them directly, without await.",
	"Bookings are identified by their uid (bookingUid); event types, schedules, teams, users and attendees by numeric IDs. Times are ISO 8601, such as 2026-10-14T09:00:00Z, and time zones IANA names such as Europe/Paris. Lists such as eventTypeIds='100,200' are comma-separated strings; only getBusyTimes takes calendar as an array.",
	"Paging: listBookings uses cursor and limit (continue with pagination.nextCursor while pagination.hasMore); getEventTypeHistory also uses a cursor. listTeamBookings returns pagination totals for take and skip. Other take/skip lists (take 1..250, default 250) return a plain data array: increase skip while a full page comes back. Event types, schedules, teams, calendars and apps are unpaginated.",
	"To book: getSlots({eventTypeId=123, start='2026-10-15', ['end']='2026-10-22', timeZone='Europe/Paris'}) returns data[date] = {{start=...}}; then createBooking({eventTypeId=123, start=slot.start, attendee={name='Ana', email='ana@example.com', timeZone='Europe/Paris'}}). Other examples: listBookings({status='upcoming', afterStart='2026-10-14T00:00:00Z', limit=20}); cancelBooking({bookingUid=uid, cancellationReason='Conflict'}); rescheduleBooking({bookingUid=uid, start='2026-10-16T14:00:00Z'}).",
	"Read-only connections omit writes and webhook reads, whose responses include signing secrets; calculateRoutingFormSlots only reads. Bookings, cancellations, reschedules, reassignments and added attendees or guests email the people involved and update connected calendars; verification-code requests send an email or text; workflows send messages automatically. Team functions need team membership. Connecting calendars or video apps, organization administration and API key rotation happen in Cal.com, not here.",
	"There are no automatic retries: after a timeout or 5xx, read the booking or resource again before repeating a write. Errors report the HTTP status, Cal.com's error code, message and validation details.",
})
