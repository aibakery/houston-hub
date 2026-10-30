-- Carta CRM public API v1. Arguments and results keep Carta CRM's native field names.
type Options = {[string]: any}
type Endpoint = {method: string, path: string, query: {string}?, extra: {string}?, required: {string}?, write: boolean?, body: (boolean | string)?, doc: string, about: string}

local PROVIDER = "Carta CRM"
local API = "https://crm-public-api.app.carta.com"
local DOCS = "https://docs.carta.com/crm/reference/public-"
local PAGE: {string} = {"limit", "offset"}

local function paged(...: string): {string}
	local fields = {...}
	for _, field in PAGE do table.insert(fields, field) end
	return fields
end

-- A curated subset of Carta CRM's public API reference, checked on 2026-10-19. Path {fields}
-- are required; listed query fields are taken from the options and the other fields form the
-- JSON body of POST, PATCH and PUT requests. Search and aggregate POSTs only read.
local endpoints: {[string]: Endpoint} = {
	getMe = {method = "GET", path = "/v1/me", doc = "organization-configuration-controller-get-current-user",
		about = "The user and organization the API key acts as."},
	getOrganization = {method = "GET", path = "/v1/organization", doc = "organization-configuration-controller-get-organization", about = ""},
	listUsers = {method = "GET", path = "/v1/organization/users", doc = "organization-configuration-controller-get-users", about = "Users of the organization."},
	getObjectsCount = {method = "GET", path = "/v1/objects-count", doc = "objects-count-controller-get-objects-count",
		about = "Totals of contacts, deals, fundraisings, investors and notes."},

	listCompanies = {method = "GET", path = "/v1/companies", query = paged("listId", "search"), doc = "company-controller-get-companies", about = "{companies}."},
	searchCompanies = {method = "POST", path = "/v1/companies/search", write = false, doc = "company-controller-search-companies",
		about = "Body {filters?, search?, limit?, offset?}; see Filters."},
	aggregateCompanies = {method = "POST", path = "/v1/companies/aggregate", write = false, required = {"group_by"}, doc = "company-controller-aggregate-companies",
		about = "Body {group_by, group_by_granularity?, filters?, metric?}: counts per group."},
	getCompany = {method = "GET", path = "/v1/companies/{id}", doc = "company-controller-get-company-by-id", about = ""},
	createCompany = {method = "POST", path = "/v1/companies", required = {"name"}, doc = "company-controller-create-company",
		about = "Body {name, image?, lists?, fields?}. A website in fields starts enrichment."},
	updateCompany = {method = "PATCH", path = "/v1/companies/{id}", doc = "company-controller-update-company",
		about = "Body: fields to change {name?, lists?, fields?, cartaIssuerId?, cartaCorporationId?}."},
	deleteCompany = {method = "DELETE", path = "/v1/companies/{id}", doc = "company-controller-delete-company", about = "Permanent."},
	listCompanyFields = {method = "GET", path = "/v1/companies/fields", doc = "company-controller-get-all-company-fields", about = "Standard and custom fields, with their fieldId."},
	listCompanyLists = {method = "GET", path = "/v1/companies/lists", doc = "company-metadata-controller-get-company-lists", about = ""},
	addCompanyToList = {method = "POST", path = "/v1/companies/{id}/lists/{listId}", body = false, doc = "company-controller-add-company-to-list", about = ""},
	removeCompanyFromList = {method = "DELETE", path = "/v1/companies/{id}/lists/{listId}", doc = "company-controller-remove-company-from-list", about = ""},
	getCompanyAngles = {method = "GET", path = "/v1/companies/angles", query = {"domain"}, required = {"domain"}, doc = "company-controller-get-company-angles",
		about = "Who in your network can introduce you to people at a company domain."},
	listCompanyInteractions = {method = "GET", path = "/v1/companies/{id}/interactions", query = paged("type"), doc = "company-controller-get-company-interactions",
		about = "Past emails and meetings with the company's people, newest first. type: EMAIL or EVENT."},
	listCompanyRelations = {method = "GET", path = "/v1/companies/{id}/relations", query = PAGE, doc = "company-controller-get-company-relations",
		about = "Relationships with the company's contacts, one row per participant."},
	listCompanyNotes = {method = "GET", path = "/v1/companies/{id}/notes", doc = "company-linking-controller-get-linked-notes", about = "id may be a company domain."},
	linkCompanyNote = {method = "POST", path = "/v1/companies/{id}/notes/{noteId}", body = false, doc = "company-linking-controller-link-note", about = ""},

	listContacts = {method = "GET", path = "/v1/contacts", doc = "contacts-controller-get-contacts",
		query = paged("search", "queryTerms", "listIds", "folderIds", "currentCompany", "titles", "tagsAny", "locationCity", "locationCountry", "addedAfter", "addedBefore", "relationshipStatus", "interactionFrequencyGoals"),
		about = "{contacts}. Array filters match any value."},
	getContact = {method = "GET", path = "/v1/contacts/{id}", doc = "contacts-controller-get-contact-by-id", about = ""},
	createContact = {method = "POST", path = "/v1/contacts", required = {"name"}, doc = "contacts-controller-create-contact",
		about = "Body {name, listId?, firstName?, lastName?, emailDetail?, phone?, title?, tags?, jobs?, location?, socialLinks?, fields?, ...}. Enriches the contact unless enrich=false."},
	updateContact = {method = "PATCH", path = "/v1/contacts/{id}", doc = "contacts-controller-update-contact", about = "Body: fields to change; jobs, location and homeLocation are replaced whole."},
	deleteContact = {method = "DELETE", path = "/v1/contacts/{id}", doc = "contacts-controller-delete-contact", about = "Permanent, from every list."},
	listContactFields = {method = "GET", path = "/v1/contacts/fields", doc = "contacts-controller-get-all-contact-fields", about = ""},
	listContactLists = {method = "GET", path = "/v1/contacts/lists", doc = "contact-lists-controller-get-lists", about = "The folder and list tree."},
	addContactToList = {method = "POST", path = "/v1/contacts/{id}/lists/{listId}", body = false, doc = "contacts-controller-add-contact-to-list", about = ""},
	removeContactFromList = {method = "DELETE", path = "/v1/contacts/{id}/lists/{listId}", doc = "contacts-controller-remove-contact-from-list", about = "Keeps the contact in other lists."},
	findContactDuplicates = {method = "GET", path = "/v1/contacts/duplicates", query = paged("types"), doc = "contacts-controller-find-contact-duplicates",
		about = "Suspected duplicates; types: email, linkedin, name."},
	listContactInteractions = {method = "GET", path = "/v1/contacts/{id}/interactions", query = paged("type"), doc = "contacts-controller-get-contact-interactions", about = ""},
	listContactNotes = {method = "GET", path = "/v1/contacts/{id}/notes", doc = "contact-linking-controller-get-linked-notes", about = ""},
	linkContactNote = {method = "POST", path = "/v1/contacts/{id}/notes/{noteId}", body = false, doc = "contact-linking-controller-link-note", about = ""},

	listDeals = {method = "GET", path = "/v1/deals", query = paged("pipelines", "stages", "search"), doc = "deal-controller-get-deals",
		about = "{deals}. Without pipelines, the default pipeline."},
	searchDeals = {method = "POST", path = "/v1/deals/search", write = false, doc = "deal-controller-search-deals", about = "Body {filters?, search?, limit?, offset?}."},
	aggregateDeals = {method = "POST", path = "/v1/deals/aggregate", write = false, required = {"group_by"}, doc = "deal-controller-aggregate-deals", about = "Body {group_by, pipeline_id?, group_by_granularity?, filters?, metric?}."},
	aggregateDealStageHistory = {method = "POST", path = "/v1/deals/stage-history/aggregate", write = false, required = {"group_by"}, doc = "deal-controller-aggregate-deal-stage-history",
		about = "Body {group_by, group_by_granularity?, count_by?, filters?}: stage transitions per group."},
	getDeal = {method = "GET", path = "/v1/deals/{id}", doc = "deal-controller-get-deal-by-id", about = ""},
	createDeal = {method = "POST", path = "/v1/deals", doc = "deal-controller-create-deal",
		about = "Body {company={name, url?, ...}, pipelineId?, stageId?, dealLead?, tags?, comment?, fields?, people?}."},
	updateDeal = {method = "PATCH", path = "/v1/deals/{id}", doc = "deal-controller-update-deal", about = "Body: fields to change, such as stageId."},
	deleteDeal = {method = "DELETE", path = "/v1/deals/{id}", doc = "deal-controller-delete-deal", about = "Permanent."},
	listDealFields = {method = "GET", path = "/v1/deals/fields", doc = "deal-metadata-controller-get-all-deal-fields", about = ""},
	listDealPipelines = {method = "GET", path = "/v1/deals/pipelines", doc = "deal-metadata-controller-get-pipelines-with-stages", about = "Pipelines with their stages."},
	getDealStageHistory = {method = "GET", path = "/v1/deals/{id}/stage-history", doc = "deal-controller-get-deal-stage-history", about = ""},
	listDealNotes = {method = "GET", path = "/v1/deals/{id}/notes", doc = "deal-linking-controller-get-linked-notes", about = ""},
	linkDealNote = {method = "POST", path = "/v1/deals/{id}/notes/{noteId}", body = false, doc = "deal-linking-controller-link-note", about = ""},

	listFundraisings = {method = "GET", path = "/v1/fundraisings", query = paged("stages", "search"), doc = "fundraising-controller-get-fundraising", about = "LP prospects, {fundraising}."},
	searchFundraisings = {method = "POST", path = "/v1/fundraisings/search", write = false, doc = "fundraising-controller-search-fundraisings", about = "Body {filters?, search?, limit?, offset?}."},
	aggregateFundraisings = {method = "POST", path = "/v1/fundraisings/aggregate", write = false, required = {"group_by"}, doc = "fundraising-controller-aggregate-fundraisings", about = "Body {group_by, group_by_granularity?, filters?, metric?}."},
	getFundraising = {method = "GET", path = "/v1/fundraisings/{id}", doc = "fundraising-controller-get-fundraising-by-id", about = ""},
	createFundraising = {method = "POST", path = "/v1/fundraisings", required = {"name"}, doc = "fundraising-controller-create-fundraising",
		about = "Body {name, stageId?, investorId?, originContactId?, fields?}."},
	updateFundraising = {method = "PATCH", path = "/v1/fundraisings/{id}", doc = "fundraising-controller-update-fundraising", about = ""},
	deleteFundraising = {method = "DELETE", path = "/v1/fundraisings/{id}", doc = "fundraising-controller-delete-deal", about = "Permanent."},
	listFundraisingFields = {method = "GET", path = "/v1/fundraisings/fields", doc = "fundraising-controller-get-all-fundraising-fields", about = ""},
	listFundraisingStages = {method = "GET", path = "/v1/fundraisings/stages", doc = "fundraising-controller-get-stages", about = ""},
	listFundraisingNotes = {method = "GET", path = "/v1/fundraisings/{id}/notes", doc = "fundraising-linking-controller-get-linked-notes", about = ""},
	linkFundraisingNote = {method = "POST", path = "/v1/fundraisings/{id}/notes/{noteId}", body = false, doc = "fundraising-linking-controller-link-note", about = ""},

	listInvestors = {method = "GET", path = "/v1/investors", query = paged("search"), doc = "investors-controller-get-investors", about = "{investors}."},
	searchInvestors = {method = "POST", path = "/v1/investors/search", write = false, doc = "investors-controller-search-investors", about = "Body {filters?, search?, limit?, offset?}."},
	aggregateInvestors = {method = "POST", path = "/v1/investors/aggregate", write = false, required = {"group_by"}, doc = "investors-controller-aggregate-investors", about = "Body {group_by, group_by_granularity?, filters?, metric?}."},
	getInvestor = {method = "GET", path = "/v1/investors/{id}", doc = "investors-controller-get-investor-by-id", about = ""},
	createInvestor = {method = "POST", path = "/v1/investors", required = {"name"}, doc = "investors-controller-create-investor", about = "Body {name, fields?, originContactId?}."},
	updateInvestor = {method = "PATCH", path = "/v1/investors/{id}", doc = "investors-controller-update-investor", about = ""},
	deleteInvestor = {method = "DELETE", path = "/v1/investors/{id}", doc = "investors-controller-delete-investor", about = ""},
	listInvestorFields = {method = "GET", path = "/v1/investors/fields", doc = "investors-controller-get-all-investor-fields", about = ""},
	getInvestorCapitalActivity = {method = "GET", path = "/v1/investors/{id}/capital-activity", doc = "fund-admin-controller-get-capital-activity",
		about = "Released capital calls and distributions of this LP across the firm's funds (Fund Admin)."},
	listInvestorNotes = {method = "GET", path = "/v1/investors/{id}/notes", doc = "investor-linking-controller-get-linked-notes", about = ""},
	linkInvestorNote = {method = "POST", path = "/v1/investors/{id}/notes/{noteId}", body = false, doc = "investor-linking-controller-link-note", about = ""},

	getFundClosingsStatus = {method = "GET", path = "/v1/funds/closings-status", query = {"fundCartaIds"}, required = {"fundCartaIds"}, doc = "fund-admin-controller-get-closings-status",
		about = "fundCartaIds: up to 25 Carta fund IDs, an array or comma-separated string. Whether closings are set up per fund, with the ledger URL."},
	listClosingProspectStatuses = {method = "GET", path = "/v1/funds/{fundCartaId}/closing-prospect-statuses", query = {"prospectPublicIds"}, doc = "fund-admin-controller-get-closing-prospect-statuses",
		about = "prospectPublicIds?: an array or comma-separated string. KYC, risk and commitment state of a fund's closing prospects."},

	listFees = {method = "GET", path = "/v1/fees", query = paged("search"), doc = "fees-controller-get-fees", about = "Newest first, with totalAmount."},
	searchFees = {method = "POST", path = "/v1/fees/search", write = false, doc = "fees-controller-search-fees", about = "Body {filters?, search?, limit?, offset?}."},
	aggregateFees = {method = "POST", path = "/v1/fees/aggregate", write = false, required = {"group_by"}, doc = "fees-controller-aggregate-fees", about = "Body {group_by, group_by_granularity?, filters?, metric?}."},
	getFee = {method = "GET", path = "/v1/fees/{id}", doc = "fees-controller-get-fee-by-id", about = ""},
	createFee = {method = "POST", path = "/v1/fees", required = {"name"}, doc = "fees-controller-create-fee",
		about = "Body {name, fields?}. Amount, date and deal are custom fields; read listFeeFields first."},
	updateFee = {method = "PATCH", path = "/v1/fees/{id}", doc = "fees-controller-update-fee", about = ""},
	deleteFee = {method = "DELETE", path = "/v1/fees/{id}", doc = "fees-controller-delete-fee", about = "Moves it to the trash."},
	listFeeFields = {method = "GET", path = "/v1/fees/fields", doc = "fees-controller-get-all-fee-fields", about = ""},
	listFeesByDeal = {method = "GET", path = "/v1/fees/by-deal/{dealId}", doc = "fees-controller-get-fees-by-deal", about = ""},
	listFeesByContact = {method = "GET", path = "/v1/fees/by-contact/{contactId}", doc = "fees-controller-get-fees-by-contact", about = "contactId is the contact's common ID, not its record id."},

	listNotes = {method = "GET", path = "/v1/notes", doc = "notes-controller-get-notes",
		query = paged("search", "folderId", "createdAfter", "createdBefore", "sort", "linkedEntityType", "linkedEntityId", "hasLinkedEntity"),
		about = "sort: newest or oldest. linkedEntityType: deal, investor, contact, calendarEvent or company."},
	listNotesByDomain = {method = "GET", path = "/v1/notes/by-domain", query = paged("domain", "entityTypes"), required = {"domain"}, doc = "notes-controller-get-notes-by-domain",
		about = "Notes on a company domain's company, deals, investors and fundraisings."},
	listNoteFolders = {method = "GET", path = "/v1/notes/folders", doc = "notes-controller-get-folders", about = ""},
	getNote = {method = "GET", path = "/v1/notes/{id}", doc = "notes-controller-get-note-by-id", about = ""},
	createNote = {method = "POST", path = "/v1/notes", required = {"title"}, doc = "notes-controller-create-note", about = "Body {title, text?, folderId?, calendarEventIds?}."},
	updateNote = {method = "PATCH", path = "/v1/notes/{id}", doc = "notes-controller-update-note", about = ""},
	deleteNote = {method = "DELETE", path = "/v1/notes/{id}", doc = "notes-controller-delete-note", about = "Permanent."},

	listTasks = {method = "GET", path = "/v1/tasks", query = paged("done", "entityType"), doc = "tasks-controller-search-tasks", about = "Tasks assigned to you."},
	listTasksByEntity = {method = "GET", path = "/v1/tasks/by-entity", query = paged("entityId"), required = {"entityId"}, doc = "tasks-controller-get-tasks-by-entity", about = ""},
	getTask = {method = "GET", path = "/v1/tasks/{id}", doc = "tasks-controller-get-task-by-id", about = ""},
	createTask = {method = "POST", path = "/v1/tasks", required = {"entityId", "entityType", "title", "dueDate"}, doc = "tasks-controller-create-task",
		about = "Body {entityId, entityType (DEAL, NOTE, CONTACT, FUNDRAISING_OPPORTUNITY, COMPANY or INVESTOR), title, dueDate, assignees?, emailNotifications?, comment?}."},
	updateTask = {method = "PATCH", path = "/v1/tasks/{id}", doc = "tasks-controller-update-task", about = "Body {title?, dueDate?, done?, assignees?, comment?}."},
	deleteTask = {method = "DELETE", path = "/v1/tasks/{id}", doc = "tasks-controller-delete-task", about = ""},

	listIcMeetings = {method = "GET", path = "/v1/ic-meetings", query = paged("search"), doc = "ic-meeting-controller-search-ic-meetings", about = "Investment committee meetings, newest first."},
	getIcMeeting = {method = "GET", path = "/v1/ic-meetings/{id}", doc = "ic-meeting-controller-get-ic-meeting-by-id", about = ""},
	listIcMeetingFields = {method = "GET", path = "/v1/ic-meetings/fields", doc = "ic-meeting-controller-get-ic-meeting-fields", about = ""},
	listIcMeetingRequests = {method = "GET", path = "/v1/ic-meetings/{id}/requests", doc = "ic-meeting-controller-get-ic-meeting-requests", about = "The agenda."},
	createIcMeeting = {method = "POST", path = "/v1/ic-meetings", doc = "ic-meeting-controller-create-ic-meeting", about = "Body {name?, fields?}."},
	updateIcMeeting = {method = "PATCH", path = "/v1/ic-meetings/{id}", doc = "ic-meeting-controller-update-ic-meeting", about = ""},
	deleteIcMeeting = {method = "DELETE", path = "/v1/ic-meetings/{id}", query = {"agenda"}, doc = "ic-meeting-controller-delete-ic-meeting",
		about = "A meeting with requests on its agenda needs agenda (see reference)."},
	listIcRequests = {method = "GET", path = "/v1/ic-requests", query = paged("icMeetingId", "search"), doc = "ic-request-controller-search-ic-requests", about = ""},
	getIcRequest = {method = "GET", path = "/v1/ic-requests/{id}", doc = "ic-request-controller-get-ic-request-by-id", about = ""},
	listIcRequestFields = {method = "GET", path = "/v1/ic-requests/fields", doc = "ic-request-controller-get-ic-request-fields", about = ""},
	createIcRequest = {method = "POST", path = "/v1/ic-requests", doc = "ic-request-controller-create-ic-request", about = "Body {name?, icMeetingId?, fields?}."},
	updateIcRequest = {method = "PATCH", path = "/v1/ic-requests/{id}", doc = "ic-request-controller-update-ic-request", about = ""},
	deleteIcRequest = {method = "DELETE", path = "/v1/ic-requests/{id}", doc = "ic-request-controller-delete-ic-request", about = ""},

	listInteractions = {method = "GET", path = "/v1/interactions", query = paged("domain", "type"), required = {"domain"}, doc = "interactions-controller-get-interactions",
		about = "Emails and meetings with people at a domain."},
	listCalendarEvents = {method = "GET", path = "/v1/calendar-events", query = paged("startDate", "endDate", "mine"), doc = "calendar-event-linking-controller-get-calendar-events",
		about = "External meetings, default now to +90 days (Interactions module)."},
	listCalendarEventNotes = {method = "GET", path = "/v1/calendar-events/{id}/notes", doc = "calendar-event-linking-controller-get-linked-notes", about = ""},
	linkCalendarEventNote = {method = "POST", path = "/v1/calendar-events/{id}/notes/{noteId}", body = false, doc = "calendar-event-linking-controller-link-note", about = ""},

	listThemes = {method = "GET", path = "/v1/themes", query = paged("search"), doc = "themes-controller-get-themes", about = ""},
	createTheme = {method = "POST", path = "/v1/themes", required = {"name"}, doc = "themes-controller-create-theme", about = "Body {name, comments?}; returns an existing theme of that name."},
	listThemeFolders = {method = "GET", path = "/v1/themes/{id}/folders", query = PAGE, doc = "themes-controller-get-theme-folders", about = ""},
	listThemeItems = {method = "GET", path = "/v1/themes/{id}/theme-items", query = paged("folderId"), doc = "themes-controller-get-theme-items", about = ""},
	addThemeItem = {method = "POST", path = "/v1/themes/{id}/theme-items", required = {"entityId", "entityType"}, doc = "themes-controller-create-theme-item",
		about = "Body {entityId, entityType}. Adds a theme mention to the entity."},
	removeThemeItem = {method = "DELETE", path = "/v1/themes/{id}/theme-items/{itemId}", doc = "themes-controller-delete-theme-item", about = ""},

	listReports = {method = "GET", path = "/v1/reports", query = {"entityType"}, required = {"entityType"}, doc = "reports-controller-list-reports",
		about = "Saved reports; entityType: contact, deal, fundraising, investor, company or fees."},
	getReport = {method = "GET", path = "/v1/reports/{id}", query = {"entityType"}, required = {"entityType"}, doc = "reports-controller-get-report", about = ""},
	getReportData = {method = "GET", path = "/v1/reports/{id}/data", query = paged("entityType", "search"), required = {"entityType"}, doc = "reports-controller-get-report-data",
		about = "Runs the report: {rows, count}."},

	searchPeople = {method = "GET", path = "/v1/people/search", query = paged("query"), required = {"query"}, doc = "people-controller-search-people",
		about = "Public LinkedIn profiles matching a name."},
	searchLpCatalog = {method = "GET", path = "/v1/lp-discovery", doc = "lp-discovery-controller-search",
		query = paged("search", "types", "regions", "countries", "minAumUsd", "maxAumUsd", "sortBy", "sortDirection"),
		about = "Carta's shared institutional LP catalogue, not your investors."},
	getLpCatalogEntry = {method = "GET", path = "/v1/lp-discovery/{id}", doc = "lp-discovery-controller-get-one", about = ""},
	getLpCatalogFacets = {method = "GET", path = "/v1/lp-discovery/facets", doc = "lp-discovery-controller-get-facets", about = "Valid types, regions and countries for searchLpCatalog."},
	addLpToFundraising = {method = "POST", path = "/v1/lp-discovery/{id}/add-to-fundraising", body = false, doc = "lp-discovery-controller-add-to-fundraising",
		about = "Copies a catalogue LP into your fundraising pipeline; created=false when it exists."},
	addLpToInvestors = {method = "POST", path = "/v1/lp-discovery/{id}/add-to-investors", body = false, doc = "lp-discovery-controller-add-to-investors", about = ""},

	listEmailCampaigns = {method = "GET", path = "/v1/email-campaigns", query = paged("status"), doc = "email-campaign-controller-list-campaigns", about = ""},
	getEmailCampaign = {method = "GET", path = "/v1/email-campaigns/{id}", doc = "email-campaign-controller-get-campaign", about = ""},
	getEmailHistory = {method = "GET", path = "/v1/email-history", query = paged("email", "campaignIds", "from", "to", "event"), doc = "email-campaign-controller-get-email-history",
		about = "Campaign email events, newest first (limit up to 100, default 50)."},
}

-- Request layer shared verbatim by the endpoint-table connectors
-- (tools/validate checks they match). It uses each connector's PROVIDER, DOCS and Endpoint type.
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

-- A query value's encoded parts: one for a scalar, one per item of a nonempty array. Each
-- connector joins them as its provider expects, comma-separated or with the key repeated.
local function queryParts(value: any, field: string): {string}
	if type(value) ~= "table" then return {scalar(value, field)} end
	local parts: {string} = {}
	for index, item in value do
		assert(type(index) == "number" and index == #parts + 1, field .. " must be an array, not an object")
		table.insert(parts, scalar(item, field))
	end
	assert(#parts > 0, field .. " must not be an empty array")
	return parts
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

-- A successful response's JSON object, or nil when a write answers without a body. With arrays,
-- a top-level JSON array is accepted too, and the second result tells which one came back.
local function object(name: string, endpoint: Endpoint, response: HttpResponse, arrays: boolean?): (any, boolean)
	local raw = await(response.body:readAll())
	if endpoint.method ~= "GET" and writes(endpoint) and string.match(raw, "^%s*$") then return nil, false end
	local ok, value = pcall(json.decode, raw)
	local list = arrays == true and string.match(raw, "^%s*%[") ~= nil
	if not ok or type(value) ~= "table" or not (list or string.match(raw, "^%s*{")) then
		fail(name, response, PROVIDER .. " returned an invalid JSON object")
	end
	return value, list
end

-- name({path fields, query fields?, extra fields?, required body fields, ...body}) built from the
-- endpoint itself.
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
		for _, field in endpoint.required or NONE do
			if not table.find(fields, field) then table.insert(fields, field) end
		end
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

-- IDs are Mongo ObjectIds, UUIDs, integer Carta fund IDs, or for company notes a domain such as
-- acme.com. The manifest sends sibling routes such as /v1/deals/batch without the key.
local function identifier(value: any, field: string): string
	if type(value) == "number" then
		assert(value >= 0 and value % 1 == 0 and value <= 9007199254740991, field .. " must be a Carta CRM ID or domain")
		return string.format("%d", value)
	end
	assert(type(value) == "string" and #value <= 200 and string.match(value, "^[%w][%w%-_.]*$") ~= nil,
		field .. " must be a Carta CRM ID or domain")
	return value
end

-- Array filters repeat the parameter: listIds=a&listIds=b. The reference types these lists as
-- strings instead, so an array is sent comma-separated.
local COMMA_SEPARATED = table.freeze({fundCartaIds = true, prospectPublicIds = true})

local function queryPairs(query: {string}, field: string, value: any)
	local parts = queryParts(value, field)
	if COMMA_SEPARATED[field] then parts = {table.concat(parts, ",")} end
	for _, part in parts do table.insert(query, field .. "=" .. part) end
end

-- Carta CRM errors are {success=false, error, code?}; authentication failures are {message}.
local function failStatus(name: string, response: HttpResponse): never
	local message = "Carta CRM HTTP " .. tostring(response.statusCode)
	local ok, value = pcall(json.decode, await(response.body:readPrefix(16 * 1024)))
	if ok and type(value) == "table" then
		if type(value.code) == "string" then message ..= " (" .. string.sub(value.code, 1, 100) .. ")" end
		-- Carta CRM's own errors carry error; framework errors a specific message and a generic error.
		local text = if type(value.message) == "string" then value.message else value.error
		if type(text) == "string" then message ..= ": " .. string.sub(text, 1, 600) end
		-- Validation failures list their problems in message.
		if type(value.message) == "table" then message ..= " " .. string.sub(json.encode(value.message), 1, 600) end
	end
	local reset = response.headers["ratelimit-reset"]
	if response.statusCode == 429 and reset and reset[1] then message ..= "; rate limit resets in " .. reset[1] .. "s" end
	return fail(name, response, message)
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
	local body: string? = nil
	if hasBody(endpoint) then
		headers["Content-Type"] = {"application/json"}
		body = json.encode(args)
		args = {}
	end
	local unknown = next(args)
	assert(unknown == nil, name .. " has no option " .. tostring(unknown))
	local response = await(http.request({method = endpoint.method, url = API .. path, headers = headers, body = body}))
	if response.statusCode < 200 or response.statusCode >= 300 then failStatus(name, response) end
	return object(name, endpoint, response) or {success = true}
end

return operations(endpoints, request, {
	"Carta CRM public API v1. Every function takes one named options object with Carta CRM's field names; ? marks optional fields and ...body the JSON body fields. Results are Carta CRM's JSON unchanged: lists as {<records>, total?}, records as objects, deletes and note links as {success}; list membership changes return the record. In bodies, pass json.decode('[]') for empty arrays and json.decode('null') to clear a field. Connector calls return completed values: use them directly, without await.",
	"Start with getMe(): the user and organization the key acts as. IDs are usually ObjectIds; company note routes also take a domain such as acme.com. Custom field values go in fields keyed by fieldId: read the record type's list*Fields first.",
	"Lists return one page: limit 1..100 (default 100) and offset (default 0); fetch offset + limit until fewer than limit return. Array query filters repeat the parameter and match any value; fundCartaIds and prospectPublicIds are sent comma-separated.",
	"Search and aggregate bodies take filters {{field_id, operator, value}}: eq, neq, gt, gte, lt, lte, contains, in (array), between ({from, to} as a two-element array), last_x ('12 months'). group_by is a one-element array holding a field ID.",
	"Examples: crm.listDeals({search='acme', limit=25}); crm.searchCompanies({filters={{field_id='lists', operator='in', value={listId}}}}); crm.getReportData({id=reportId, entityType='deal', offset=100}); crm.createTask({entityId=dealId, entityType='DEAL', title='Send memo', dueDate='2026-11-01'}).",
	"Read-only connections omit writes; search and aggregate still work. Each record type needs its module enabled (deals, fundraising, investors, fees, themes, companies, contacts, Interactions); Fund Admin reads need Fund Admin access; the key acts as its user and organization.",
	"Side effects: creating contacts, or records with a website, can start Carta's enrichment; deletes are permanent, except fees (moved to the trash) and IC meetings and requests (archived; an unknown ID also succeeds). No automatic retries: after a timeout or 5xx, check whether the write took effect (search or list for the record) before repeating it; createTheme and the LP catalogue adds are safe to repeat. Errors report the HTTP status, Carta CRM's code and message.",
})
