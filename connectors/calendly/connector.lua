-- Calendly API v2. Arguments and results keep Calendly's native snake_case fields.
type Options = {[string]: any}
type Endpoint = {method: string, path: string, query: {string}?, extra: {string}?, required: {string}?, write: boolean?, body: (boolean | string)?, doc: string, about: string}

local PROVIDER = "Calendly"
local API = "https://api.calendly.com"
local DOCS = "https://developer.calendly.com/api-docs/calendly-api/"

-- Operations in Calendly's public OpenAPI, checked on 2026-10-14. Path {fields} name
-- the resource and take its UUID or Calendly URI. Listed query fields are taken from
-- the options; the other fields form the JSON body (see hasBody).
local endpoints: {[string]: Endpoint} = {
	getCurrentUser = {method = "GET", path = "/users/me", doc = "users/get-current-user",
		about = "The connected user. resource.uri is your user URI, resource.current_organization your organization URI."},
	getUser = {method = "GET", path = "/users/{user}", doc = "users/get-user", about = "A user."},

	getOrganization = {method = "GET", path = "/organizations/{organization}", doc = "organizations/get-organization", about = "An organization."},
	listOrganizationMemberships = {method = "GET", path = "/organization_memberships", doc = "organizations/list-organization-memberships",
		query = {"organization", "user", "email", "role", "count", "page_token"},
		about = "Members of an organization, or a user's membership. Pass organization or user. role: owner, admin or user."},
	getOrganizationMembership = {method = "GET", path = "/organization_memberships/{membership}", doc = "organizations/get-organization-membership", about = "A membership."},
	removeOrganizationMembership = {method = "DELETE", path = "/organization_memberships/{membership}", doc = "organizations/delete-organization-membership",
		about = "Removes a user from the organization. Needs an admin; the owner cannot be removed."},
	listOrganizationInvitations = {method = "GET", path = "/organizations/{organization}/invitations", doc = "organizations/list-organization-invitations",
		query = {"email", "status", "sort", "count", "page_token"}, about = "Invitations. status: pending, accepted or declined."},
	getOrganizationInvitation = {method = "GET", path = "/organizations/{organization}/invitations/{invitation}", doc = "organizations/get-organization-invitation", about = "An invitation."},
	inviteUserToOrganization = {method = "POST", path = "/organizations/{organization}/invitations", doc = "organizations/create-organization-invitation",
		about = "Body {email}. Emails an invitation to join the organization and uses a seat."},
	revokeOrganizationInvitation = {method = "DELETE", path = "/organizations/{organization}/invitations/{invitation}", doc = "organizations/revoke-organization-invitation",
		about = "Revokes a pending invitation."},
	listTeams = {method = "GET", path = "/teams", doc = "organizations/list-teams", query = {"user", "count", "page_token"}, about = "Teams, optionally those of a user."},
	getTeam = {method = "GET", path = "/teams/{team}", doc = "organizations/get-team", about = "A team."},

	listEventTypes = {method = "GET", path = "/event_types", doc = "event-types/list-event-types",
		query = {"user", "organization", "active", "admin_managed", "user_availability_schedule", "sort", "count", "page_token"},
		about = "Event types of a user or an organization; pass one. sort: name, position, created_at or updated_at with :asc or :desc."},
	getEventType = {method = "GET", path = "/event_types/{event_type}", doc = "event-types/get-event-type", about = "An event type."},
	createEventType = {method = "POST", path = "/event_types", doc = "event-types/create-event-type",
		about = "Body {owner (user URI), name, duration?, duration_options?, active? (default false), color?, description?, locale?, locations?}. One-on-one event types only."},
	updateEventType = {method = "PATCH", path = "/event_types/{event_type}", doc = "event-types/update-event-type",
		about = "Body: the createEventType fields to change, except owner. One-on-one event types only."},
	listEventTypeAvailableTimes = {method = "GET", path = "/event_type_available_times", doc = "event-types/list-event-type-available-times",
		query = {"event_type", "start_time", "end_time"}, required = {"event_type", "start_time", "end_time"},
		about = "Bookable start times in a future range of at most 31 days, unpaginated."},
	listEventTypeHosts = {method = "GET", path = "/event_type_memberships", doc = "event-types/list-event-type-memberships",
		query = {"event_type", "count", "page_token"}, required = {"event_type"}, about = "Hosts of an event type."},
	createOneOffEventType = {method = "POST", path = "/one_off_event_types", doc = "event-types/create-one-off-event-type",
		about = "Body {name, host (user URI), duration, date_setting, co_hosts?, timezone?, location?}. date_setting is {type='date_range', start_date, end_date}, {type='days_in_future', days, only_weekdays} or {type='spots', spots={{start_time, end_time}}}."},
	getEventTypeAvailability = {method = "GET", path = "/event_type_availability_schedules", doc = "availability/get-event-type-availability",
		query = {"event_type"}, required = {"event_type"}, about = "An event type's weekly and date-specific availability rules."},
	updateEventTypeAvailability = {method = "PATCH", path = "/event_type_availability_schedules", doc = "availability/update-event-type-availability",
		query = {"event_type"}, required = {"event_type"},
		about = "Body {availability_rule={timezone, rules={{type='wday', wday='monday', intervals={{from='09:00', to='17:00'}}}, {type='date', date='2026-12-24', intervals=json.decode('[]')}}}}. Replaces the event type's rules."},

	listUserAvailabilitySchedules = {method = "GET", path = "/user_availability_schedules", doc = "availability/list-user-availability-schedules",
		query = {"user"}, required = {"user"}, about = "A user's availability schedules, unpaginated."},
	getUserAvailabilitySchedule = {method = "GET", path = "/user_availability_schedules/{schedule}", doc = "availability/get-user-availability-schedule", about = "An availability schedule."},
	listUserBusyTimes = {method = "GET", path = "/user_busy_times", doc = "availability/list-user-busy-times",
		query = {"user", "start_time", "end_time"}, required = {"user", "start_time", "end_time"},
		about = "Calendly and conflict-checked calendar events in a future range of at most 7 days, unpaginated."},
	listUserLocations = {method = "GET", path = "/locations", doc = "locations/list-user-locations",
		query = {"user"}, required = {"user"}, about = "Meeting locations a user has configured."},

	listScheduledEvents = {method = "GET", path = "/scheduled_events", doc = "scheduled-events/list-scheduled-events",
		query = {"user", "organization", "group", "invitee_email", "status", "min_start_time", "max_start_time", "sort", "count", "page_token"},
		about = "Booked meetings of a user, organization or group; pass one. Another user's events need both user and organization and an admin. status: active or canceled; sort: start_time:asc or start_time:desc."},
	getScheduledEvent = {method = "GET", path = "/scheduled_events/{event}", doc = "scheduled-events/get-scheduled-event", about = "A booked meeting."},
	cancelScheduledEvent = {method = "POST", path = "/scheduled_events/{event}/cancellation", doc = "scheduled-events/create-scheduled-event-cancellation",
		about = "Body {reason?}. Cancels the meeting for every invitee and notifies them."},
	listInvitees = {method = "GET", path = "/scheduled_events/{event}/invitees", doc = "scheduled-events/list-event-invitees",
		query = {"status", "email", "sort", "count", "page_token"}, about = "Invitees of a meeting, with their answers. sort: created_at:asc or created_at:desc."},
	getInvitee = {method = "GET", path = "/scheduled_events/{event}/invitees/{invitee}", doc = "scheduled-events/get-event-invitee", about = "An invitee."},
	createInvitee = {method = "POST", path = "/invitees", doc = "scheduled-events/create-event-invitee",
		about = "Books a meeting (paid plans). Body {event_type, start_time, invitee={email, timezone, name?}, location?={kind, location?}, event_guests?, questions_and_answers?, tracking?}. Take start_time from listEventTypeAvailableTimes. Calendly emails the invitee and hosts."},
	createInviteeNoShow = {method = "POST", path = "/invitee_no_shows", doc = "scheduled-events/create-invitee-no-show",
		about = "Body {invitee (invitee URI)}. Marks an invitee as a no-show."},
	getInviteeNoShow = {method = "GET", path = "/invitee_no_shows/{no_show}", doc = "scheduled-events/get-invitee-no-show", about = "A no-show mark."},
	deleteInviteeNoShow = {method = "DELETE", path = "/invitee_no_shows/{no_show}", doc = "scheduled-events/delete-invitee-no-show", about = "Removes a no-show mark."},

	createSchedulingLink = {method = "POST", path = "/scheduling_links", doc = "scheduling-links/create-scheduling-link",
		about = "Body {owner (event type URI), owner_type='EventType', max_event_count=1}. Returns a single-use resource.booking_url; unused links expire after 90 days."},
	createShare = {method = "POST", path = "/shares", doc = "shares/create-share",
		about = "Body {event_type, name?, duration?, start_date?, end_date?, availability_rule?, ...}. A single-use link with customized settings; omitted fields copy the one-on-one event type."},

	listRoutingForms = {method = "GET", path = "/routing_forms", doc = "routing-forms/list-routing-forms",
		query = {"organization", "sort", "count", "page_token"}, required = {"organization"}, about = "Routing forms."},
	getRoutingForm = {method = "GET", path = "/routing_forms/{form}", doc = "routing-forms/get-routing-form", about = "A routing form with its questions."},
	listRoutingFormSubmissions = {method = "GET", path = "/routing_form_submissions", doc = "routing-forms/list-routing-form-submissions",
		query = {"form", "sort", "count", "page_token"}, required = {"form"}, about = "Submissions of a routing form."},
	getRoutingFormSubmission = {method = "GET", path = "/routing_form_submissions/{submission}", doc = "routing-forms/get-routing-form-submission", about = "A submission."},

	listWebhookSubscriptions = {method = "GET", path = "/webhook_subscriptions", doc = "webhooks/list-webhook-subscriptions",
		query = {"organization", "scope", "user", "group", "sort", "count", "page_token"}, required = {"organization", "scope"},
		about = "Webhook subscriptions. scope: organization, user (pass user) or group (pass group)."},
	getWebhookSubscription = {method = "GET", path = "/webhook_subscriptions/{webhook}", doc = "webhooks/get-webhook-subscription", about = "A webhook subscription."},
	createWebhookSubscription = {method = "POST", path = "/webhook_subscriptions", doc = "webhooks/create-webhook-subscription",
		about = "Body {url, events, organization, scope, user?, group?, signing_key?}. Calendly then posts those events to url, a receiver you control (paid plans)."},
	deleteWebhookSubscription = {method = "DELETE", path = "/webhook_subscriptions/{webhook}", doc = "webhooks/delete-webhook-subscription", about = "Stops a webhook subscription."},
	getSampleWebhookData = {method = "GET", path = "/sample_webhook_data", doc = "webhooks/get-sample-webhook-data",
		query = {"event", "organization", "scope", "user", "group"}, required = {"event", "organization", "scope"},
		about = "An example payload for a webhook event such as invitee.created."},

	listGroups = {method = "GET", path = "/groups", doc = "groups/list-groups",
		query = {"organization", "count", "page_token"}, required = {"organization"}, about = "Groups of an organization."},
	getGroup = {method = "GET", path = "/groups/{group}", doc = "groups/get-group", about = "A group."},
	listGroupRelationships = {method = "GET", path = "/group_relationships", doc = "groups/list-group-relationships",
		query = {"organization", "owner", "group", "count", "page_token"}, about = "Group memberships and admin roles."},
	getGroupRelationship = {method = "GET", path = "/group_relationships/{relationship}", doc = "groups/get-group-relationship", about = "A group relationship."},

	listContacts = {method = "GET", path = "/contacts", doc = "contacts/list-contacts",
		query = {"email", "phone_number", "name", "company", "job_title", "timezone", "country", "state", "city", "exclude", "sort", "count", "page_token"},
		about = "Contacts. Filters accept one value or an array; exclude='custom_fields' omits custom fields."},
	getContact = {method = "GET", path = "/contacts/{contact}", doc = "contacts/get-contact", query = {"exclude"}, about = "A contact."},
	createContact = {method = "POST", path = "/contacts", doc = "contacts/create-contact",
		about = "Body {name, emails, phone_numbers?, company?, job_title?, city?, state?, country?, timezone?, linkedin?, custom_fields?={{uuid, value}}}."},
	updateContact = {method = "PATCH", path = "/contacts/{contact}", doc = "contacts/patch-contacts-uuid", about = "Body: the createContact fields to change."},
	deleteContact = {method = "DELETE", path = "/contacts/{contact}", doc = "contacts/delete-contacts-uuid", about = "Deletes a contact."},
	listContactCustomFields = {method = "GET", path = "/contacts/custom_field_definitions", doc = "contacts/list-contact-custom-field-definitions",
		about = "Custom contact field definitions, unpaginated."},
	getContactCustomField = {method = "GET", path = "/contacts/custom_field_definitions/{field}", doc = "contacts/get-contact-custom-field-definition", about = "A custom field definition."},

	listMeetingRecaps = {method = "GET", path = "/meeting_recaps", doc = "notetaker/list-meeting-recaps",
		query = {"event", "attendee", "status", "start_time", "end_time", "count", "page_token"},
		about = "Notetaker recaps (paid plans). event is a scheduled event URI; status: available (default), processing or unavailable."},
	getMeetingRecap = {method = "GET", path = "/meeting_recaps/{recap}", doc = "notetaker/get-meeting-recaps-uuid-recap", about = "A recap with its summary, action items and discussion."},
	getMeetingRecapTranscript = {method = "GET", path = "/meeting_recaps/{recap}/transcript", doc = "notetaker/get-transcript-meeting-recaps", about = "A recap's transcript."},
	updateMeetingRecap = {method = "PATCH", path = "/meeting_recaps/{recap}", doc = "notetaker/update-meeting-recaps-uuid",
		about = "Body {summary_md?, action_items_md?, discussion_md?} in Markdown."},
	deleteMeetingRecap = {method = "DELETE", path = "/meeting_recaps/{recap}", doc = "notetaker/delete-meeting-recaps-uuid", about = "Deletes a recap."},

	listActivityLogEntries = {method = "GET", path = "/activity_log_entries", doc = "activity-log/list-activity-log-entries",
		query = {"organization", "search_term", "actor", "namespace", "action", "min_occurred_at", "max_occurred_at", "sort", "count", "page_token"},
		required = {"organization"}, about = "Organization audit log (Enterprise admins). count is 1..1000."},
	listOutgoingCommunications = {method = "GET", path = "/outgoing_communications", doc = "outgoing-communications/list-outgoing-communications",
		query = {"organization", "min_created_at", "max_created_at", "count", "page_token"}, required = {"organization"},
		about = "Emails and texts Calendly sent for the organization (Enterprise admins)."},
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

-- Responses identify resources by URI, such as https://api.calendly.com/scheduled_events/<uuid>.
-- A path field takes the UUID or the URI of its own kind, the path segment before it.
-- Calendly's examples also show singular kinds, such as user_availability_schedule/<uuid>.
local function identifier(value: any, field: string, kind: string): string
	assert(type(value) == "string", field .. " must be a UUID or Calendly URI")
	local id = value
	local uriKind, uriId = string.match(value, "^https://api%.calendly%.com/.-([%w_]+)/([^/]+)$")
	if uriKind and uriId then
		assert(uriKind == kind or uriKind .. "s" == kind, field .. " must be a " .. kind .. " URI or UUID")
		id = uriId
	end
	assert(string.match(id, "^[%w%-_]+$"), field .. " must be a UUID or Calendly URI")
	return id
end

-- Calendly reads array filters (actor, namespace, contact filters) as comma-separated values.
local function queryValue(value: any, field: string): string
	if type(value) ~= "table" then return scalar(value, field) end
	local parts: {string} = {}
	for index, item in value do
		assert(type(index) == "number" and index == #parts + 1, field .. " must be an array, not an object")
		table.insert(parts, scalar(item, field))
	end
	assert(#parts > 0, field .. " must not be an empty array")
	return table.concat(parts, ",")
end

-- Calendly errors are {title, message, details?: [{parameter?, message}]}; a missing
-- scope adds required_scopes.
local function failStatus(name: string, response: HttpResponse): never
	local message = "Calendly HTTP " .. tostring(response.statusCode)
	local ok, value = pcall(json.decode, await(response.body:readPrefix(16 * 1024)))
	if ok and type(value) == "table" then
		if type(value.title) == "string" then message ..= " (" .. value.title .. ")" end
		if type(value.message) == "string" then message ..= ": " .. string.sub(value.message, 1, 600) end
		if type(value.required_scopes) == "table" then message ..= " " .. string.sub(json.encode(value.required_scopes), 1, 600) end
		if type(value.details) == "table" then message ..= " " .. string.sub(json.encode(value.details), 1, 600) end
	end
	local reset = response.headers["x-ratelimit-reset"]
	if response.statusCode == 429 and reset and reset[1] then message ..= "; rate limit resets in " .. reset[1] .. "s" end
	return fail(name, response, message)
end

local function decode(name: string, endpoint: Endpoint, response: HttpResponse): any
	if response.statusCode < 200 or response.statusCode >= 300 then failStatus(name, response) end
	-- Deletions answer 204 without a body.
	return object(name, endpoint, response) or {success = true}
end

local function request(name: string, endpoint: Endpoint, input: Options?): any
	local args = options(input)
	local path = string.gsub(endpoint.path, "{([%w_]+)}", function(field: string)
		-- Every path field follows the collection it names, such as /scheduled_events/{event}.
		local kind = string.match(endpoint.path, "([%w_]+)/{" .. field .. "}") :: string
		local id = identifier(args[field], field, kind)
		args[field] = nil
		return id
	end)
	for _, field in endpoint.required or NONE do
		assert(args[field] ~= nil and args[field] ~= NULL, field .. " is required")
	end
	local query: {string} = {}
	for _, field in endpoint.query or NONE do
		if args[field] ~= nil then table.insert(query, field .. "=" .. queryValue(args[field], field)) end
		args[field] = nil
	end
	if #query > 0 then path ..= "?" .. table.concat(query, "&") end
	local headers: HttpHeaders = {Accept = {"application/json"}}
	local body: string? = nil
	if hasBody(endpoint) then
		headers["Content-Type"] = {"application/json"}
		body = json.encode(args)
		args = {}
	end
	local unknown = next(args)
	assert(unknown == nil, name .. " has no option " .. tostring(unknown))
	return decode(name, endpoint, await(http.request({method = endpoint.method, url = API .. path, headers = headers, body = body})))
end

return operations(endpoints, request, {
	"Calendly API v2. Every function takes one named options object with Calendly's snake_case names; ? marks optional fields and ...body the JSON body fields. Results are Calendly's JSON unchanged: single objects usually as {resource}, lists as {collection, pagination}; deletes return {success=true}. In bodies, pass json.decode('[]') for empty arrays and json.decode('null') to clear a field. Connector calls return completed values: use them directly, without await.",
	"Calendly identifies resources by URI, such as https://api.calendly.com/users/AAAA. Query and body fields that reference a resource (user, organization, event_type, invitee, owner, host, form, ...) take the full URI; path fields (event, invitee, contact, ...) take the UUID or the URI of that kind of resource. Start with getCurrentUser(): resource.uri is your user and resource.current_organization your organization.",
	"Lists return one page: count is 1..100 (default 20) and pagination.next_page_token, while not null, is the next call's page_token. Array filters are sent comma-separated. Times are ISO 8601 UTC, such as 2026-10-14T09:00:00Z.",
	"Examples: local me = calendly.getCurrentUser().resource; calendly.listScheduledEvents({user=me.uri, status='active', min_start_time='2026-10-14T00:00:00Z', sort='start_time:asc', count=50}); calendly.listInvitees({event=event.uri}); calendly.listEventTypeAvailableTimes({event_type=type.uri, start_time='2026-10-15T00:00:00Z', end_time='2026-10-22T00:00:00Z'}); calendly.createSchedulingLink({owner=type.uri, owner_type='EventType', max_event_count=1}).",
	"Read-only connections omit writes. Calendly's own permissions also apply: organization-wide lists and webhooks need an admin or owner, the activity log and outgoing communications need Enterprise, and createInvitee, webhooks and recaps need a paid plan. A 403 for a missing scope lists the required scopes. Calendly has no API to delete event types or reschedule meetings.",
	"Side effects: createInvitee books a real meeting and cancelScheduledEvent cancels one for every invitee, and Calendly emails them; inviteUserToOrganization emails an invitation. There are no automatic retries: after a timeout or 5xx, read the resource again before repeating a write. Errors report the HTTP status, Calendly's title, message and invalid parameters.",
})
