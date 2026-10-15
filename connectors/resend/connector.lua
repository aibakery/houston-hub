-- Resend API (unversioned REST). Arguments and results keep Resend's native snake_case field names.
type Options = {[string]: any}
type Endpoint = {
	method: string, path: string, query: {string}?, extra: {string}?, required: {string}?,
	write: boolean?, body: (boolean | string)?, upload: boolean?, doc: string, about: string,
}

local PROVIDER = "Resend"
local API = "https://api.resend.com"
local DOCS = "https://resend.com/docs/api-reference/"
local USER_AGENT = "Houston"
-- Some Resend lists return every item when limit is omitted, so the connector always pages.
local PAGE_SIZE = 100

local PAGE = {"limit", "after", "before"}
local FORWARD = {"limit", "after"}
local function paged(...: string): {string}
	local fields = {...}
	table.move(PAGE, 1, #PAGE, #fields + 1, fields)
	return fields
end

-- Operations in Resend's OpenAPI and API reference, checked on 2026-10-15. Path {fields} and
-- listed query fields are taken from the options; the other fields form the JSON body (see
-- hasBody). Webhook and log reads are writes because they return signing secrets and logged
-- request bodies. Inboxes (private beta), API key creation and changes, OAuth grants and the
-- deprecated audiences are not exposed.
local endpoints: {[string]: Endpoint} = {
	sendEmail = {method = "POST", path = "/emails", extra = {"idempotency_key"}, doc = "emails/send-email",
		about = "Body {from='Name <you@your-domain>', to (address or array of at most 50), subject, html?, text?, cc?, bcc?, reply_to?, headers?, attachments?={{filename, content (base64) or path (public URL), content_type?, content_id?}}, tags?={{name, value}}, scheduled_at? (ISO 8601 or 'in 1 hour', at most 30 days ahead), topic_id?, template?={id (or alias), variables?}}. Sends real email; returns {id}."},
	sendBatchEmails = {method = "POST", path = "/emails/batch", body = "emails", extra = {"idempotency_key"}, doc = "emails/send-batch-emails",
		about = "emails: an array of 1..100 sendEmail bodies, without attachments. Returns {data={{id}}} in order; one invalid email rejects the whole batch."},
	listEmails = {method = "GET", path = "/emails", query = PAGE, doc = "emails/list-emails", about = "Sent emails, newest first, with last_event."},
	getEmail = {method = "GET", path = "/emails/{email_id}", doc = "emails/retrieve-email",
		about = "A sent email with html, text and last_event (sent, delivered, bounced, opened, clicked, scheduled, ...)."},
	updateEmail = {method = "PATCH", path = "/emails/{email_id}", doc = "emails/update-email", about = "Body {scheduled_at} (ISO 8601). Reschedules a scheduled email."},
	cancelEmail = {method = "POST", path = "/emails/{email_id}/cancel", body = false, doc = "emails/cancel-email", about = "Cancels a scheduled email."},
	shareEmail = {method = "POST", path = "/emails/{email_id}/share", doc = "emails/share-email",
		about = "Body {expires_in? (such as '2 hours'; default and maximum 48h)}. Returns a public link to a sent or received email that anyone can open."},
	getEmailMetrics = {method = "GET", path = "/emails/metrics", doc = "emails/get-metrics",
		query = {"start_date", "end_date", "timezone", "granularity", "metrics", "dimensions", "domain_id", "email_id", "broadcast_id"},
		about = "Delivered, bounced, opened, clicked, ... counts as totals, and data rows when dimensions (period, domain, email or broadcast) are set. Defaults to the last 7 days. Cached up to 15 minutes."},
	listEmailAttachments = {method = "GET", path = "/emails/{email_id}/attachments", query = PAGE, doc = "emails/list-email-attachments",
		about = "Attachments of a sent email, with signed download_url links."},
	getEmailAttachment = {method = "GET", path = "/emails/{email_id}/attachments/{attachment_id}", extra = {"path"}, doc = "emails/retrieve-email-attachment",
		about = "A sent email's attachment with a signed download_url. With path, also saves the file there and returns {path, url, size, attachment}."},
	listReceivedEmails = {method = "GET", path = "/emails/receiving", query = PAGE, doc = "emails/list-received-emails",
		about = "Emails received on your domains, newest first."},
	getReceivedEmail = {method = "GET", path = "/emails/receiving/{email_id}", query = {"html_format"}, doc = "emails/retrieve-received-email",
		about = "A received email with from, to, subject, html, text, headers, attachments and raw.download_url (a signed .eml link). Inline images are data: URIs in html unless html_format='cid'."},
	listReceivedEmailAttachments = {method = "GET", path = "/emails/receiving/{email_id}/attachments", query = PAGE, doc = "emails/list-received-email-attachments",
		about = "Attachments of a received email, with signed download_url links valid for an hour."},
	getReceivedEmailAttachment = {method = "GET", path = "/emails/receiving/{email_id}/attachments/{attachment_id}", extra = {"path"},
		doc = "emails/retrieve-received-email-attachment", about = "As getEmailAttachment, for a received email."},

	createDomain = {method = "POST", path = "/domains", doc = "domains/create-domain",
		about = "Body {name, region? (us-east-1, eu-west-1, sa-east-1 or ap-northeast-1), custom_return_path?, open_tracking?, click_tracking?, tls? (opportunistic or enforced), tracking_subdomain?, capabilities?}. Returns the DNS records to add."},
	listDomains = {method = "GET", path = "/domains", query = PAGE, doc = "domains/list-domains", about = "Sending and receiving domains with their status."},
	getDomain = {method = "GET", path = "/domains/{domain_id}", doc = "domains/get-domain", about = "A domain with its status and DNS records."},
	updateDomain = {method = "PATCH", path = "/domains/{domain_id}", doc = "domains/update-domain",
		about = "Body {open_tracking?, click_tracking?, tls?, tracking_subdomain?, capabilities?}."},
	deleteDomain = {method = "DELETE", path = "/domains/{domain_id}", doc = "domains/delete-domain", about = "Removes a domain; email can no longer be sent from it."},
	verifyDomain = {method = "POST", path = "/domains/{domain_id}/verify", body = false, doc = "domains/verify-domain",
		about = "Starts DNS verification; read getDomain for the result."},
	claimDomain = {method = "POST", path = "/domains/claim", doc = "domains/claim-domain",
		about = "Body as createDomain. Claims a domain another Resend account verified; returns a TXT record proving ownership."},
	getDomainClaim = {method = "GET", path = "/domains/{domain_id}/claim", doc = "domains/get-domain-claim", about = "A domain claim and its TXT record."},
	verifyDomainClaim = {method = "POST", path = "/domains/{domain_id}/claim/verify", body = false, doc = "domains/verify-domain-claim",
		about = "Starts checking the claim's TXT record; read getDomainClaim for the result. The moved domain then needs its new DNS records verified."},
	listApiKeys = {method = "GET", path = "/api-keys", query = PAGE, doc = "api-keys/list-api-keys",
		about = "API keys' id, name, created_at and last_used_at, never their tokens."},

	createTemplate = {method = "POST", path = "/templates", doc = "templates/create-template",
		about = "Body {name, html, alias?, from?, subject?, reply_to?, text?, variables?={{key, type ('string' or 'number'), fallback_value?}}}. Creates a draft; html uses {{{KEY}}} placeholders."},
	listTemplates = {method = "GET", path = "/templates", query = PAGE, doc = "templates/list-templates", about = "Templates with their status (draft or published)."},
	getTemplate = {method = "GET", path = "/templates/{template_id}", doc = "templates/get-template", about = "A template; template_id is its ID or alias."},
	updateTemplate = {method = "PATCH", path = "/templates/{template_id}", doc = "templates/update-template",
		about = "Body: the createTemplate fields to change. Changes the draft until publishTemplate."},
	deleteTemplate = {method = "DELETE", path = "/templates/{template_id}", doc = "templates/delete-template", about = "Deletes a template."},
	publishTemplate = {method = "POST", path = "/templates/{template_id}/publish", body = false, doc = "templates/publish-template",
		about = "Publishes the draft; only published templates can be sent."},
	duplicateTemplate = {method = "POST", path = "/templates/{template_id}/duplicate", body = false, doc = "templates/duplicate-template", about = "Copies a template; returns the new id."},

	createContact = {method = "POST", path = "/contacts", doc = "contacts/create-contact",
		about = "Body {email, first_name?, last_name?, unsubscribed?, properties?={key=value}, segments?={{id}}, topics?={{id, subscription ('opt_in' or 'opt_out')}}}."},
	listContacts = {method = "GET", path = "/contacts", query = paged("segment_id"), doc = "contacts/list-contacts", about = "Contacts, optionally of one segment."},
	getContact = {method = "GET", path = "/contacts/{contact_id}", doc = "contacts/get-contact", about = "A contact; contact_id is its ID or email address."},
	updateContact = {method = "PATCH", path = "/contacts/{contact_id}", doc = "contacts/update-contact",
		about = "Body {email?, first_name?, last_name?, unsubscribed?, properties?}. unsubscribed=true stops every broadcast to the contact."},
	deleteContact = {method = "DELETE", path = "/contacts/{contact_id}", doc = "contacts/delete-contact", about = "Deletes a contact."},
	createContactImport = {method = "POST", path = "/contacts/imports", upload = true, extra = {"path"}, required = {"path"}, doc = "contacts/create-contact-import",
		about = "Imports contacts from the CSV session file at path. Body {column_map?={email?, first_name?, last_name?, unsubscribed?, properties?={key={column, type?}}}, on_conflict? (upsert or skip), segments?={{id}}, topics?={{id, subscription}}}. Runs in the background; returns {id}."},
	listContactImports = {method = "GET", path = "/contacts/imports", query = paged("status"), doc = "contacts/list-contact-imports",
		about = "Contact imports; status: queued, in_progress, completed or failed."},
	getContactImport = {method = "GET", path = "/contacts/imports/{import_id}", doc = "contacts/get-contact-import", about = "An import's status and counts."},
	listContactSegments = {method = "GET", path = "/contacts/{contact_id}/segments", query = PAGE, doc = "contacts/list-contact-segments", about = "Segments a contact belongs to."},
	addContactToSegment = {method = "POST", path = "/contacts/{contact_id}/segments/{segment_id}", body = false, doc = "contacts/add-contact-to-segment",
		about = "Adds a contact to a segment."},
	removeContactFromSegment = {method = "DELETE", path = "/contacts/{contact_id}/segments/{segment_id}", doc = "contacts/delete-contact-segment",
		about = "Removes a contact from a segment."},
	listContactTopics = {method = "GET", path = "/contacts/{contact_id}/topics", query = PAGE, doc = "contacts/get-contact-topics",
		about = "A contact's topic subscriptions."},
	updateContactTopics = {method = "PATCH", path = "/contacts/{contact_id}/topics", doc = "contacts/update-contact-topics",
		about = "Body {topics={{id, subscription ('opt_in' or 'opt_out')}}}."},

	createBroadcast = {method = "POST", path = "/broadcasts", doc = "broadcasts/create-broadcast",
		about = "Body {segment_id, from, subject, html?, text?, name?, reply_to?, preview_text?, topic_id?, send?, scheduled_at?}. Creates a draft; send=true emails the segment now, or at scheduled_at."},
	listBroadcasts = {method = "GET", path = "/broadcasts", query = PAGE, doc = "broadcasts/list-broadcasts", about = "Broadcasts with their status (draft, scheduled, queued, sent, ...)."},
	getBroadcast = {method = "GET", path = "/broadcasts/{broadcast_id}", doc = "broadcasts/get-broadcast", about = "A broadcast with its content."},
	updateBroadcast = {method = "PATCH", path = "/broadcasts/{broadcast_id}", doc = "broadcasts/update-broadcast", about = "Body: the createBroadcast fields to change, for a draft."},
	deleteBroadcast = {method = "DELETE", path = "/broadcasts/{broadcast_id}", doc = "broadcasts/delete-broadcast", about = "Deletes a draft broadcast."},
	sendBroadcast = {method = "POST", path = "/broadcasts/{broadcast_id}/send", doc = "broadcasts/send-broadcast",
		about = "Body {scheduled_at?}. Emails every contact in the segment, now or at scheduled_at."},
	cancelBroadcast = {method = "POST", path = "/broadcasts/{broadcast_id}/cancel", body = false, doc = "broadcasts/cancel-broadcast",
		about = "Cancels a queued or scheduled broadcast; emails already sent stay sent."},
	duplicateBroadcast = {method = "POST", path = "/broadcasts/{broadcast_id}/duplicate", body = false, doc = "broadcasts/duplicate-broadcast",
		about = "Copies a broadcast as a new draft."},
	listBroadcastRecipients = {method = "GET", path = "/broadcasts/{broadcast_id}/recipients", query = paged("type", "email", "bounce_type"), required = {"type"},
		doc = "broadcasts/list-broadcast-recipients",
		about = "Recipients with one event. type: sent, delivered, opened, clicked, bounced, complained, unsubscribed or suppressed; bounce_type (with bounced): permanent, transient or undetermined."},
	listBroadcastClickedLinks = {method = "GET", path = "/broadcasts/{broadcast_id}/clicked-links", query = PAGE, doc = "broadcasts/list-broadcast-clicked-links",
		about = "Links clicked in a broadcast."},

	createWebhook = {method = "POST", path = "/webhooks", doc = "webhooks/create-webhook",
		about = "Body {endpoint (an https URL you control), events={'email.delivered', 'email.bounced', ...}}. Returns its signing_secret."},
	listWebhooks = {method = "GET", path = "/webhooks", query = PAGE, doc = "webhooks/list-webhooks", about = "Webhooks with endpoint, events and status, without secrets."},
	getWebhook = {method = "GET", path = "/webhooks/{webhook_id}", write = true, doc = "webhooks/get-webhook", about = "A webhook with its signing_secret."},
	updateWebhook = {method = "PATCH", path = "/webhooks/{webhook_id}", doc = "webhooks/update-webhook", about = "Body {endpoint?, events?, status? (enabled or disabled)}."},
	deleteWebhook = {method = "DELETE", path = "/webhooks/{webhook_id}", doc = "webhooks/delete-webhook", about = "Deletes a webhook."},
	rotateWebhookSigningSecret = {method = "POST", path = "/webhooks/{webhook_id}/signing-secret/rotate", body = false, doc = "webhooks/rotate-signing-secret",
		about = "Returns a new signing_secret; the old one stays valid for 24 hours."},
	listWebhookEvents = {method = "GET", path = "/webhooks/{webhook_id}/events", query = FORWARD, doc = "webhooks/list-events",
		about = "Events delivered to a webhook, newest first; pages forward only."},
	getWebhookEvent = {method = "GET", path = "/webhooks/{webhook_id}/events/{event_id}", doc = "webhooks/get-event", about = "An event (msg_...) with its payload."},
	replayWebhookEvent = {method = "POST", path = "/webhooks/{webhook_id}/events/{event_id}/replay", body = false, doc = "webhooks/replay-event",
		about = "Delivers an event to the webhook again."},
	listWebhookEventAttempts = {method = "GET", path = "/webhooks/{webhook_id}/events/{event_id}/attempts", query = FORWARD, doc = "webhooks/list-event-attempts",
		about = "Delivery attempts of an event, with response status."},

	createSegment = {method = "POST", path = "/segments", doc = "segments/create-segment", about = "Body {name, filter?}."},
	listSegments = {method = "GET", path = "/segments", query = PAGE, doc = "segments/list-segments", about = "Contact segments."},
	getSegment = {method = "GET", path = "/segments/{segment_id}", doc = "segments/get-segment", about = "A segment."},
	updateSegment = {method = "PATCH", path = "/segments/{segment_id}", doc = "segments/update-segment", about = "Body {name}."},
	deleteSegment = {method = "DELETE", path = "/segments/{segment_id}", doc = "segments/delete-segment", about = "Deletes a segment."},
	listSegmentContacts = {method = "GET", path = "/segments/{segment_id}/contacts", query = PAGE, doc = "segments/list-segment-contacts", about = "Contacts in a segment."},

	createTopic = {method = "POST", path = "/topics", doc = "topics/create-topic",
		about = "Body {name, default_subscription ('opt_in' or 'opt_out', permanent), description?, visibility? (public or private)}."},
	listTopics = {method = "GET", path = "/topics", query = PAGE, doc = "topics/list-topics", about = "Subscription topics."},
	getTopic = {method = "GET", path = "/topics/{topic_id}", doc = "topics/get-topic", about = "A topic."},
	updateTopic = {method = "PATCH", path = "/topics/{topic_id}", doc = "topics/update-topic", about = "Body {name?, description?, visibility?}."},
	deleteTopic = {method = "DELETE", path = "/topics/{topic_id}", doc = "topics/delete-topic", about = "Deletes a topic."},

	createContactProperty = {method = "POST", path = "/contact-properties", doc = "contact-properties/create-contact-property",
		about = "Body {key (letters, digits and _), type ('string' or 'number'), fallback_value?}."},
	listContactProperties = {method = "GET", path = "/contact-properties", query = PAGE, doc = "contact-properties/list-contact-properties", about = "Custom contact properties."},
	getContactProperty = {method = "GET", path = "/contact-properties/{property_id}", doc = "contact-properties/get-contact-property", about = "A contact property."},
	updateContactProperty = {method = "PATCH", path = "/contact-properties/{property_id}", doc = "contact-properties/update-contact-property", about = "Body {fallback_value}."},
	deleteContactProperty = {method = "DELETE", path = "/contact-properties/{property_id}", doc = "contact-properties/delete-contact-property",
		about = "Deletes a contact property."},

	listLogs = {method = "GET", path = "/logs", query = PAGE, doc = "logs/list-logs",
		about = "API requests made with your keys: endpoint, method, response_status and user_agent."},
	getLog = {method = "GET", path = "/logs/{log_id}", write = true, doc = "logs/retrieve-log", about = "A request with its request_body and response_body, which can hold secrets."},

	createAutomation = {method = "POST", path = "/automations", doc = "automations/create-automation",
		about = "Body {name, steps, connections, status? (enabled or disabled)}; see the reference for step and connection shapes."},
	listAutomations = {method = "GET", path = "/automations", query = paged("status"), doc = "automations/list-automations", about = "Automations; status: enabled or disabled."},
	getAutomation = {method = "GET", path = "/automations/{automation_id}", doc = "automations/get-automation", about = "An automation with its steps and connections."},
	updateAutomation = {method = "PATCH", path = "/automations/{automation_id}", doc = "automations/update-automation",
		about = "Body: the createAutomation fields to change."},
	deleteAutomation = {method = "DELETE", path = "/automations/{automation_id}", doc = "automations/delete-automation", about = "Deletes an automation."},
	duplicateAutomation = {method = "POST", path = "/automations/{automation_id}/duplicate", body = false, doc = "automations/duplicate-automation",
		about = "Copies an automation."},
	stopAutomation = {method = "POST", path = "/automations/{automation_id}/stop", body = false, doc = "automations/stop-automation",
		about = "Stops a running automation."},
	listAutomationRuns = {method = "GET", path = "/automations/{automation_id}/runs", query = paged("status"), doc = "automations/list-automation-runs",
		about = "Runs; status is a comma-separated list of running, completed, failed and cancelled."},
	getAutomationRun = {method = "GET", path = "/automations/{automation_id}/runs/{run_id}", doc = "automations/get-automation-run", about = "A run with its steps."},

	createEvent = {method = "POST", path = "/events", doc = "events/create-event", about = "Body {name (such as 'user.created'), schema?}. Defines an event automations can wait for."},
	listEvents = {method = "GET", path = "/events", query = PAGE, doc = "events/list-events", about = "Defined events."},
	sendEvent = {method = "POST", path = "/events/send", doc = "events/send-event",
		about = "Body {event (name), contact_id? or email?, payload?}. Starts the automations triggered by the event, which can send email."},
	getEvent = {method = "GET", path = "/events/{identifier}", doc = "events/get-event", about = "An event; identifier is its ID or name."},
	updateEvent = {method = "PATCH", path = "/events/{identifier}", doc = "events/update-event", about = "Body {schema}."},
	deleteEvent = {method = "DELETE", path = "/events/{identifier}", doc = "events/delete-event", about = "Deletes an event."},

	addSuppression = {method = "POST", path = "/suppressions", doc = "suppressions/add-suppression", about = "Body {email}. Resend stops sending to the address."},
	listSuppressions = {method = "GET", path = "/suppressions", query = paged("origin"), doc = "suppressions/list-suppressions",
		about = "Suppressed addresses; origin: bounce, complaint or manual."},
	addSuppressions = {method = "POST", path = "/suppressions/batch/add", doc = "suppressions/add-batch-suppressions", about = "Body {emails} (at most 100)."},
	removeSuppressions = {method = "POST", path = "/suppressions/batch/remove", doc = "suppressions/remove-batch-suppressions",
		about = "Body {emails} or {ids} (at most 100). Resend may send to them again."},
	getSuppression = {method = "GET", path = "/suppressions/{suppression}", doc = "suppressions/get-suppression", about = "A suppression; suppression is its ID or email address."},
	removeSuppression = {method = "DELETE", path = "/suppressions/{suppression}", doc = "suppressions/remove-suppression", about = "Removes a suppression."},
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

local function encode(value: string): string
	return (string.gsub(value, "[^A-Za-z0-9%-_%.~]", function(c: string)
		return string.format("%%%02X", string.byte(c))
	end))
end

local function scalar(value: any, field: string): string
	local kind = type(value)
	assert(kind == "string" or kind == "boolean" or kind == "number", field .. " must be a string, boolean, number or array of those")
	return encode(tostring(value))
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

-- Reads at most 16 KiB of an error body; one read can return any part of it.
local function errorBody(response: HttpResponse): string
	local parts: {string} = {}
	local size, limit = 0, 16 * 1024
	while size < limit do
		local chunk = await(response.body:read(limit - size))
		if chunk.done then break end
		table.insert(parts, chunk.data)
		size += #chunk.data
	end
	response.body:close()
	return table.concat(parts)
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

-- IDs are UUIDs, or msg_... for webhook events. Contacts and suppressions also take an email
-- address, templates an alias and events a name, such as user.created. Each is one encoded
-- path segment, as in Resend's SDK; separators, percent signs, control characters and dot
-- segments are refused.
local function identifier(value: any, field: string): string
	assert(type(value) == "string" and value ~= "" and not string.find(value, "[/\\%%%c]") and not string.match(value, "^%.+$"),
		field .. " must be an ID, email address, alias or name")
	return encode(value)
end

-- Resend errors are {statusCode, name, message}. Rate limits and in-flight idempotent requests
-- clear on their own; daily and monthly quotas (also HTTP 429) do not.
local function failStatus(name: string, response: HttpResponse): never
	local status = response.statusCode
	local ok, value = pcall(json.decode, errorBody(response))
	local problem = if ok and type(value) == "table" then value else {}
	local code = if type(problem.name) == "string" then problem.name else nil
	local message = PROVIDER .. " HTTP " .. tostring(status)
	if code then message ..= " (" .. code .. ")" end
	if type(problem.message) == "string" then message ..= ": " .. string.sub(problem.message, 1, 600) end
	local retry = response.headers["retry-after"]
	if retry and retry[1] then message ..= "; Retry-After: " .. retry[1] end
	return houston.fail({operation = name, layer = "upstream", upstream_status = status, message = message,
		retryable = status >= 500 or code == "rate_limit_exceeded" or code == "concurrent_idempotent_requests" or (status == 429 and code == nil)})
end

local function decode(name: string, endpoint: Endpoint, response: HttpResponse): any
	if response.statusCode < 200 or response.statusCode >= 300 then failStatus(name, response) end
	return object(name, endpoint, response) or {}
end

-- Attachment links are signed URLs on Resend's CDN hosts, which receive no API key.
local function save(name: string, attachment: any, path: string): any
	local url = attachment.download_url
	assert(type(url) == "string" and string.match(url, "^https://"), PROVIDER .. " returned no attachment download_url")
	local response = await(http.request({method = "GET", url = url, headers = {["User-Agent"] = {USER_AGENT}}}))
	if response.statusCode ~= 200 then failStatus(name, response) end
	local file = fs.open(path, "w")
	file:write(response.body)
	await(file:close())
	return {path = path, url = await(fs.signedGetUrl(path)), size = await(fs.stat(path)).size, attachment = attachment}
end

-- The CSV file streams from the session; other form fields are JSON-encoded when structured.
local function upload(args: Options, path: string): (any, string)
	assert(await(fs.exists(path)), "path " .. path .. " is not a session file")
	local fields: {string} = {}
	for field in args do table.insert(fields, field) end
	table.sort(fields)
	local parts: {any} = {}
	for _, field in fields do
		local value, kind = args[field], type(args[field])
		assert(value ~= NULL and (kind == "string" or kind == "number" or kind == "boolean" or kind == "table"),
			field .. " must be a string, number, boolean, object or array")
		table.insert(parts, {name = field, body = if kind == "table" then json.encode(value) else tostring(value)})
	end
	table.insert(parts, {name = "file", filename = string.match(path, "[^/]+$"), contentType = "text/csv", body = fs.open(path, "r")})
	return http.multipart(parts)
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
		local value = args[field]
		if value == nil and field == "limit" then value = PAGE_SIZE end
		if value ~= nil then table.insert(query, field .. "=" .. scalar(value, field)) end
		args[field] = nil
	end
	if #query > 0 then path ..= "?" .. table.concat(query, "&") end
	local extra: Options = {}
	for _, field in endpoint.extra or NONE do
		extra[field] = args[field]
		args[field] = nil
	end
	local headers: HttpHeaders = {Accept = {"application/json"}, ["User-Agent"] = {USER_AGENT}}
	local key = extra.idempotency_key
	if key ~= nil then
		assert(type(key) == "string" and #key >= 1 and #key <= 256, "idempotency_key must be a string of 1 to 256 characters")
		headers["Idempotency-Key"] = {key}
	end
	local target = extra.path
	assert(target == nil or (type(target) == "string" and target ~= ""), "path must be a session file path")
	local body: any, contentType = nil, "application/json"
	if endpoint.upload then
		body, contentType = upload(args, target)
		args = {}
	elseif type(endpoint.body) == "string" then
		local field = endpoint.body
		assert(type(args[field]) == "table" and #args[field] > 0, field .. " must be a nonempty array")
		body = json.encode(args[field])
		args[field] = nil
	elseif hasBody(endpoint) then
		body = json.encode(args)
		args = {}
	end
	local unknown = next(args)
	assert(unknown == nil, name .. " has no option " .. tostring(unknown))
	if body then headers["Content-Type"] = {contentType} end
	local result = decode(name, endpoint, await(http.request({method = endpoint.method, url = API .. path, headers = headers, body = body})))
	if target and not endpoint.upload then return save(name, result, target) end
	return result
end

return operations(endpoints, request, {
	"Resend API. Every function takes one named options object with Resend's snake_case names; ? marks optional fields and ...body the JSON body fields. Results are Resend's JSON unchanged, such as {id} for a send or {object='list', has_more, data} for a list. In bodies, pass json.decode('[]') for empty arrays and json.decode('null') to clear a field. Connector calls return completed values: use them directly, without await.",
	"IDs are UUIDs; contacts and suppressions also accept an email address, templates an alias and events a name. Lists return one page: limit is 1..100 (this connector sends 100 when omitted); while has_more, pass after = the last item's id (or before = the first item's id to go back). Multi-value query fields such as metrics or domain_id are comma-separated strings.",
	"Sending: from must use a domain verified in Resend (see listDomains); without one, only onboarding@resend.dev can send, and only to the account owner's address. Use html, text or a published template. scheduled_at schedules up to 30 days ahead; cancelEmail or updateEmail change a scheduled email. Pass idempotency_key (1..256 characters, kept 24 hours) to sendEmail and sendBatchEmails so a repeated call never sends twice. Attachments take base64 content or a public URL as path, at most 40 MB per email.",
	"Examples: resend.sendEmail({from='Acme <hello@acme.com>', to={'ana@example.com'}, subject='Welcome', html='<p>Hi Ana</p>', idempotency_key='welcome/ana'}); resend.sendBatchEmails({emails={{from=..., to='a@example.com', subject='Hi', text='Hello'}}}); resend.listEmails({limit=20}); resend.getReceivedEmail({email_id=id, html_format='cid'}); resend.getReceivedEmailAttachment({email_id=id, attachment_id=a.id, path='invoice.pdf'}) saves a session file; resend.createContact({email='ana@example.com', segments={{id=segment}}}).",
	"Read-only connections omit writes, getWebhook (signing secrets) and getLog (logged request bodies). A Resend key with Sending access can only send email; other calls fail with HTTP 401 restricted_api_key. Resend allows 10 requests per second per team; the free plan sends 100 emails a day and 3,000 a month (HTTP 429 daily_quota_exceeded or monthly_quota_exceeded).",
	"Side effects: sendEmail, sendBatchEmails, sendBroadcast, createBroadcast with send=true and sendEvent (through automations) email real people; shareEmail creates a public link. There are no automatic retries: after a timeout or 5xx, check listEmails or getEmail before repeating a send without an idempotency_key. Errors report the HTTP status, Resend's error name and message.",
})
