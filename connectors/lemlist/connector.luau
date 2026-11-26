-- lemlist API (https://api.lemlist.com/api). Arguments and results keep lemlist's native field names.
type Options = {[string]: any}
type Endpoint = {
	method: string, path: string, query: {string}?, required: {string}?, access: string?,
	body: (boolean | string)?, variables: boolean?, version: boolean?, jsonQuery: {string}?, about: string,
}

local PROVIDER = "lemlist"
local API = "https://api.lemlist.com/api"
local DOCS = "https://developer.lemlist.com/api-reference/getting-started/overview"
local NULL = json.decode("null")
local NONE: {string} = table.freeze({})
local DEFAULT_LIMIT = 100
local reference: {[string]: {example: Options, types: {[string]: string}}} = require("lib/reference.luau")

local PAGE = {"offset", "limit"}
local PAGED = {"page", "limit"}
local SORT = {"sortBy", "sortOrder"}
local ENRICH = {"findEmail", "verifyEmail", "linkedinEnrichment", "findPhone", "webhookUrl"}

local function list(...: {string}): {string}
	local fields: {string} = {}
	for _, group in {...} do table.move(group, 1, #group, #fields + 1, fields) end
	return fields
end

-- Operations from lemlist's public OpenAPI (checked 2026-11-23) that an API key can call. Path {fields}
-- and listed query fields come from the options; the other fields form the JSON body. Credential uploads,
-- audio uploads and CSV exports are left out. getTeam is a write because it returns the team's Slack
-- webhook URL and webhook signing secrets; the database searches and batch stats only read.
local endpoints: {[string]: Endpoint} = {
	getTeam = {method = "GET", path = "/team", access = "data:write", version = true, about = "Team, members and settings, including Slack webhook URL and webhook secrets."},
	getTeamSenders = {method = "GET", path = "/team/senders", query = {"state"}, about = "Team members with their sending channels and campaigns."},
	getTeamCredits = {method = "GET", path = "/team/credits", about = "Remaining credits."},
	getTeamCrmUsers = {method = "GET", path = "/team/crmUsers", about = "CRM connected by each user."},
	getUser = {method = "GET", path = "/users/{userId}", about = "A team member with mailboxes and LinkedIn limits."},
	getUserChannels = {method = "GET", path = "/user/channels", about = "Mailboxes, LinkedIn and WhatsApp accounts of the key's user."},
	updateUserLinkedinLimits = {method = "PATCH", path = "/users/{userId}/linkedin-limits", access = "data:write", about = "Body {inviteLimit?, visitLimit?, sendLimit?, ...}."},
	listMessageTemplates = {method = "GET", path = "/message-templates", query = list({"search", "tags", "userIds"}, PAGED), about = "Lists the team's library message templates (the templates of the Templates page), newest first, with the page's own filters: a name search, tags and creators. Campaign step bodies are not templates: read them from GET /campaigns/{campaignId}/sequences."},
	listMessageTemplateTags = {method = "GET", path = "/message-templates/tags", query = list({"search", "userIds"}, PAGED), about = "Template tags."},
	getMessageTemplate = {method = "GET", path = "/message-templates/{templateId}", about = "Returns one library message template with its body."},
	listSnippets = {method = "GET", path = "/snippets", query = list({"search", "userIds"}, PAGED), about = "Lists the team's snippets (the fragments of the Templates page > Snippets), by name, with a name search and a creator filter."},
	getSnippet = {method = "GET", path = "/snippets/{snippetId}", about = "Returns one snippet with its content."},
	listFields = {method = "GET", path = "/fields", query = {"entity", "source"}, about = "Custom and standard fields; entity is contact or company."},

	listCampaigns = {method = "GET", path = "/campaigns", version = true, query = list(PAGE, {"page", "status", "createdBy", "search"}, SORT),
		about = "{campaigns, pagination}. status: running, draft, archived, ended, paused or errors. limit <= 100."},
	createCampaign = {method = "POST", path = "/campaigns", access = "data:write", required = {"name"}, about = "Body {name, timezone?, autoReview?}. Creates a draft with an empty sequence."},
	getCampaign = {method = "GET", path = "/campaigns/{campaignId}", about = "A campaign with its sequence and senders."},
	updateCampaign = {method = "PATCH", path = "/campaigns/{campaignId}", access = "data:write", about = "Body {name?, stopOnEmailReplied?, stopOnMeetingBooked?, disableTrackOpen?, ...}."},
	startCampaign = {method = "POST", path = "/campaigns/{campaignId}/start", access = "data:write", body = false, about = "Starts or resumes sending."},
	pauseCampaign = {method = "POST", path = "/campaigns/{campaignId}/pause", access = "data:write", body = false, about = "Pauses sending."},
	duplicateCampaign = {method = "POST", path = "/campaigns/{campaignId}/duplicate", access = "data:write", about = "Body {name?}. Copies a campaign without its leads."},
	getCampaignReports = {method = "GET", path = "/campaigns/reports", query = {"campaignIds"}, required = {"campaignIds"}, about = "Aggregated statistics; campaignIds is an array or comma-separated string."},
	getCampaignStatutes = {method = "GET", path = "/campaigns/{campaignId}/statutes", about = "Lead counts by state."},
	getCampaignStats = {method = "GET", path = "/v2/campaigns/{campaignId}/stats", query = {"startDate", "endDate", "sendUser", "ABSelected", "channels"},
		jsonQuery = {"channels"}, required = {"startDate", "endDate"}, about = "Step-level statistics between ISO dates; channels is an array."},
	getBatchCampaignStats = {method = "POST", path = "/v2/campaigns/stats/batch", required = {"campaignIds", "startDate", "endDate"},
		about = "Body {campaignIds (<= 100), startDate, endDate, sendUser?, channels?}."},
	skipStepForEveryone = {method = "POST", path = "/campaigns/{campaignId}/steps/{stepId}/skip", access = "data:write", body = false, about = "Skips a step for every lead waiting on it."},
	skipStepForLeads = {method = "POST", path = "/campaigns/{campaignId}/steps/{stepId}/skip-for-leads", access = "data:write", required = {"leads"}, about = "Body {leads={leadId or email, ...}}."},
	addCampaignSignalTrigger = {method = "POST", path = "/campaigns/{campaignId}/triggers/watch-lists", access = "data:write", required = {"watchListId"}, about = "Feeds a signal agent's leads into the campaign."},
	removeCampaignSignalTrigger = {method = "DELETE", path = "/campaigns/{campaignId}/triggers/watch-lists/{watchListId}", access = "data:write", about = "Stops that feed."},

	getCampaignSequences = {method = "GET", path = "/campaigns/{campaignId}/sequences", about = "Sequences and their steps; ids are sequenceId and stepId."},
	addSequenceStep = {method = "POST", path = "/sequences/{sequenceId}/steps", access = "data:write", required = {"type"},
		about = "Body {type (email, linkedinInvite, linkedinSend, manual, phone, api, conditional, ...), delay?, index?, subject?, message?, ...}."},
	updateSequenceStep = {method = "PATCH", path = "/sequences/{sequenceId}/steps/{stepId}", access = "data:write", required = {"type"}, about = "Body {type, delay?, subject?, message?, ...}."},
	deleteSequenceStep = {method = "DELETE", path = "/sequences/{sequenceId}/steps/{stepId}", access = "data:write", about = "Delete Sequence Step."},
	listConditionBranches = {method = "GET", path = "/sequences/{sequenceId}/steps/{stepId}/branches", about = "Branches of a conditional step."},
	addConditionBranch = {method = "POST", path = "/sequences/{sequenceId}/steps/{stepId}/branches", access = "data:write", about = "Body {name?, delayType?, delay?, customField?, customOperator?, customValue?, ...}."},
	reorderConditionBranches = {method = "PATCH", path = "/sequences/{sequenceId}/steps/{stepId}/branches", access = "data:write", required = {"order"}, about = "Body {order={branchSequenceId, ...}}."},
	updateConditionBranch = {method = "PATCH", path = "/sequences/{sequenceId}/steps/{stepId}/branches/{branchSequenceId}", access = "data:write", about = "Body: the addConditionBranch fields to change."},
	deleteConditionBranch = {method = "DELETE", path = "/sequences/{sequenceId}/steps/{stepId}/branches/{branchSequenceId}", access = "data:write", about = "Removes a branch and the whole sub-tree behind it - the branch's own sub-sequence, and every sequence only reachable through it. removedSequenceIds lists what was deleted alongside the branch entry; a sequence another step still points at is left alone."},
	getStepSender = {method = "GET", path = "/sequences/{sequenceId}/steps/{stepId}/sender", about = "The sender forced on a step."},
	setStepSender = {method = "PUT", path = "/sequences/{sequenceId}/steps/{stepId}/sender", access = "data:write", required = {"userId"}, about = "Body {userId, channel?}."},
	removeStepSender = {method = "DELETE", path = "/sequences/{sequenceId}/steps/{stepId}/sender", access = "data:write", about = "Back to the campaign's sender rotation."},
	getAbTestVariant = {method = "GET", path = "/sequences/{sequenceId}/steps/{stepId}/ab-test", about = "The step's B variant."},
	createAbTestVariant = {method = "POST", path = "/sequences/{sequenceId}/steps/{stepId}/ab-test", access = "data:write", body = false, about = "Adds a B variant copied from A."},
	updateAbTestVariant = {method = "PATCH", path = "/sequences/{sequenceId}/steps/{stepId}/ab-test", access = "data:write", about = "Body {subject?, message?, cc?, plainText?, ...}."},
	deleteAbTestVariant = {method = "DELETE", path = "/sequences/{sequenceId}/steps/{stepId}/ab-test", access = "data:write", query = {"variant"}, about = "Removes variant 'A' or 'B' (default 'B')."},
	selectAbTestWinner = {method = "POST", path = "/sequences/{sequenceId}/steps/{stepId}/ab-test/winner", access = "data:write", required = {"variant"}, about = "variant is 'A' or 'B'. Keeps one variant."},

	listSenders = {method = "GET", path = "/senders", query = {"campaignId"}, about = "Senders and the campaigns they send for."},
	getCampaignSenders = {method = "GET", path = "/campaigns/{campaignId}/senders", about = "A campaign's senders and channels."},
	addCampaignSenders = {method = "POST", path = "/campaigns/{campaignId}/senders", access = "data:write", required = {"senders"}, about = "Body {senders={{userId, channels?}}}."},
	replaceCampaignSenders = {method = "PUT", path = "/campaigns/{campaignId}/senders", access = "data:write", required = {"senders"}, about = "Replaces all senders."},
	updateCampaignSenderChannels = {method = "PATCH", path = "/campaigns/{campaignId}/senders/{userId}", access = "data:write", required = {"channels"}, about = "Enables or disables channels of one sender in the pool of a campaign, or changes the alias of a mailbox. The changes apply in order. The other channels of the sender do not change. Requires the Email Pro plan."},
	removeCampaignSender = {method = "DELETE", path = "/campaigns/{campaignId}/senders/{userId}", access = "data:write", about = "Removes a sender."},

	listSchedules = {method = "GET", path = "/schedules", query = list(PAGE, {"page"}, SORT), about = "Sending schedules."},
	createSchedule = {method = "POST", path = "/schedules", access = "data:write", about = "Body {name?, timezone?, start?='09:00', ['end']?='18:00', weekdays?={1, ..., 5}}; lemlist fills defaults. Set secondsToWait with updateSchedule."},
	getSchedule = {method = "GET", path = "/schedules/{scheduleId}", about = "Get Schedule."},
	updateSchedule = {method = "PATCH", path = "/schedules/{scheduleId}", access = "data:write", about = "Body: the createSchedule fields to change."},
	deleteSchedule = {method = "DELETE", path = "/schedules/{scheduleId}", access = "data:write", about = "Delete Schedule."},
	getCampaignSchedules = {method = "GET", path = "/campaigns/{campaignId}/schedules", about = "A campaign's schedules."},
	setCampaignSchedule = {method = "POST", path = "/campaigns/{campaignId}/schedules/{scheduleId}", access = "data:write", body = false, about = "Uses a schedule for a campaign."},

	getLead = {method = "GET", path = "/leads", version = true, query = {"id", "ids", "email", "campaignId"}, about = "A lead by id or email, across campaigns."},
	listCampaignLeads = {method = "GET", path = "/campaigns/{campaignId}/leads", query = list({"state"}, PAGE), about = "Leads of a campaign; limit <= 500."},
	addLeadToCampaign = {method = "POST", path = "/campaigns/{campaignId}/leads", access = "data:write", query = list({"deduplicate", "updateStrategy"}, {"linkedinEnrichment", "findEmail", "verifyEmail", "findPhone"}),
		about = "Body {email?, firstName?, lastName?, companyName?, linkedinUrl?, phone?, icebreaker?, ...custom variables}."},
	updateCampaignLead = {method = "PATCH", path = "/campaigns/{campaignId}/leads/{leadId}", access = "data:write", query = {"updateStrategy"}, about = "Body {firstName?, lastName?, companyName?, ...}."},
	removeCampaignLead = {method = "DELETE", path = "/campaigns/{campaignId}/leads/{leadIdOrEmail}", access = "data:write", query = {"action"},
		about = "Unsubscribes the lead from the campaign; action='remove' deletes it instead."},
	resumeLead = {method = "POST", path = "/leads/start/{leadId}", access = "data:write", query = {"campaignId"}, body = false, about = "Resumes a paused lead."},
	pauseLead = {method = "POST", path = "/leads/pause/{leadId}", access = "data:write", query = {"campaignId"}, body = false, about = "Pauses a lead."},
	launchLead = {method = "POST", path = "/leads/review/{leadId}", access = "data:write", body = false, about = "Launches a lead waiting for review."},
	markLeadInterested = {method = "POST", path = "/leads/interested/{leadIdOrEmail}", access = "data:write", about = "Body {pauseAllCampaignsForThisLead?, pauseCampaignForThisCompany?, pauseAllCampaignsForThisCompany?}. In every campaign."},
	markLeadNotInterested = {method = "POST", path = "/leads/notinterested/{leadIdOrEmail}", access = "data:write", about = "Body {pauseAllCampaignsForThisLead?, pauseCampaignForThisCompany?, pauseAllCampaignsForThisCompany?}. In every campaign."},
	markCampaignLeadInterested = {method = "POST", path = "/campaigns/{campaignId}/leads/{leadIdOrEmail}/interested", access = "data:write", about = "Body {pauseAllCampaignsForThisLead?, pauseCampaignForThisCompany?, pauseAllCampaignsForThisCompany?}. In one campaign."},
	markCampaignLeadNotInterested = {method = "POST", path = "/campaigns/{campaignId}/leads/{leadIdOrEmail}/notinterested", access = "data:write", about = "Body {pauseAllCampaignsForThisLead?, pauseCampaignForThisCompany?, pauseAllCampaignsForThisCompany?}. In one campaign."},
	personalizeLeadStep = {method = "PUT", path = "/campaigns/{campaignId}/leads/{leadIdOrEmail}/steps/{stepId}/personalization", access = "data:write",
		about = "Body {variant?, subject?, message?, cc?, ...}. Overrides a step's content for one lead."},
	resetLeadStepPersonalization = {method = "DELETE", path = "/campaigns/{campaignId}/leads/{leadIdOrEmail}/steps/{stepId}/personalization", access = "data:write", about = "Removes the override."},
	addLeadVariables = {method = "POST", path = "/leads/{leadId}/variables", access = "data:write", variables = true, body = false, about = "variables={name=value}. Adds custom variables."},
	updateLeadVariables = {method = "PATCH", path = "/leads/{leadId}/variables", access = "data:write", variables = true, body = false, about = "variables={name=value}. Changes existing ones."},
	deleteLeadVariables = {method = "DELETE", path = "/leads/{leadId}/variables", access = "data:write", variables = true, body = false, about = "variables={name=true}. Erases values."},
	getCrmFilters = {method = "GET", path = "/crm/filters", query = {"type"}, about = "CRM lists and views to import leads from."},
	importLeadsFromCrm = {method = "POST", path = "/campaigns/{campaignId}/leads/import", access = "data:write", required = {"filterId"}, about = "Body {filterId, filterType?, userId?, deduplicate?}."},

	getDatabaseFilters = {method = "GET", path = "/database/filters", query = {"usage", "mode"}, about = "Filter ids and values for the database searches."},
	searchPeopleDatabase = {method = "POST", path = "/database/people", about = "Counts against the daily database search quota. Body {filters={{filterId, ['in']={...}, out={...}}}, page?, size?, excludes?, search?}."},
	searchCompaniesDatabase = {method = "POST", path = "/database/companies", about = "Counts against the daily search quota. Body {filters, page?, size?}."},
	listPersonas = {method = "GET", path = "/database/personas", query = {"mode"}, about = "Lists the personas saved by your team. A persona is a named, reusable set of People Database filters; its id can then be referenced elsewhere in the API, for example through the persona filter of a Signal Agent."},
	createPersona = {method = "POST", path = "/database/personas", access = "data:write", required = {"name", "filters", "mode"}, about = "Creates a persona for your team from a name and a set of People Database filters."},
	deletePersona = {method = "DELETE", path = "/database/personas/{personaId}", access = "data:write", about = "Permanently deletes one of your team's personas. There is no undo."},
	listSavedSearches = {method = "GET", path = "/database/saved-searches", query = {"mode"}, about = "Lists the People Database saved searches of your team, sorted by name. Saved searches are team-shared: every member sees the same list."},
	createSavedSearch = {method = "POST", path = "/database/saved-searches", access = "data:write", required = {"name", "filters", "mode"}, about = "Creates a People Database saved search for your team. It shows up in the 'Saved searches' menu of the People Database."},
	getSavedSearch = {method = "GET", path = "/database/saved-searches/{savedSearchId}", about = "A saved search."},
	updateSavedSearch = {method = "PATCH", path = "/database/saved-searches/{savedSearchId}", access = "data:write", about = "Body {name?, filters?, mode?}."},
	deleteSavedSearch = {method = "DELETE", path = "/database/saved-searches/{savedSearchId}", access = "data:write", about = "Permanently deletes one of your team's saved searches. There is no undo."},

	searchTasks = {method = "GET", path = "/v2/tasks", query = list({"taskId", "contactId", "companyId", "leadId", "campaignId", "assignedTo", "objectType", "type", "channel",
		"status", "priority", "title", "search", "dueDateFrom", "dueDateTo", "completedAtFrom", "completedAtTo", "hasCampaign", "hasDueDate", "include"}, SORT, PAGED),
		about = "Tasks. status: due, upcoming, paused, done, ignored or pending; limit <= 100."},
	listTaskFilters = {method = "GET", path = "/v2/tasks/filters", query = {"scope", "search"}, about = "Values usable in searchTasks."},
	createTask = {method = "POST", path = "/tasks", access = "data:write", required = {"type", "assignedTo", "dueDate"}, about = "Body {type, assignedTo (userId), dueDate, recordId? or leadId?, title?, message?, priority?}."},
	updateTask = {method = "PATCH", path = "/tasks", access = "data:write", required = {"id"}, about = "Body {id, assignedTo?, dueDate?, title?, message?, priority?, done?}."},
	ignoreTasks = {method = "POST", path = "/tasks/ignore", access = "data:write", required = {"ids"}, about = "Ignore Tasks."},

	listInboxConversations = {method = "GET", path = "/inbox", query = {"userId", "page", "limit"}, required = {"userId"}, about = "Conversations of a user's inbox."},
	getConversation = {method = "GET", path = "/inbox/{contactId}", query = {"userId", "limit", "skip", "markAsRead"},
		about = "Messages with a contact; limit <= 10. markAsRead=true marks it read and needs write access."},
	sendEmail = {method = "POST", path = "/inbox/email", access = "data:write", required = {"sendUserId", "sendUserEmail", "sendUserMailboxId", "message"},
		about = "Body {sendUserId, sendUserEmail, sendUserMailboxId, contactId? or leadId?, subject?, message, cc?, replyToActivityId?}."},
	sendLinkedinMessage = {method = "POST", path = "/inbox/linkedin", access = "data:write", required = {"sendUserId", "leadId", "contactId", "message"}, about = "Send LinkedIn Message."},
	sendWhatsappMessage = {method = "POST", path = "/inbox/whatsapp", access = "data:write", required = {"sendUserId", "sendUserWhatsappAccountId", "contactId", "leadId", "message"},
		about = "Body {sendUserId, sendUserWhatsappAccountId, contactId, leadId, message}."},
	sendSms = {method = "POST", path = "/inbox/sms", access = "data:write", required = {"sendUserId", "from", "message"}, about = "Body {sendUserId, from, contactId? or leadId?, message}."},
	listInboxLabels = {method = "GET", path = "/inbox/labels", about = "Conversation labels."},
	createInboxLabel = {method = "POST", path = "/inbox/labels", access = "data:write", required = {"labelName"}, about = "Creates a new label available to the team."},
	getInboxLabel = {method = "GET", path = "/inbox/labels/{labelId}", about = "Get info of a specific label."},
	addConversationLabels = {method = "POST", path = "/inbox/conversations/labels/{contactId}", access = "data:write", required = {"labelIds", "appendLabels"}, about = "Attaches one or more labels to one or more conversations."},
	removeConversationLabels = {method = "DELETE", path = "/inbox/conversations/labels/{contactId}", access = "data:write", body = true, required = {"labelIds"}, about = "Removes one or more labels from one conversation."},
	listDrafts = {method = "GET", path = "/inbox/{contactId}/drafts", query = {"draftOwner"}, about = "Drafts for a contact; draftOwner (userId) defaults to the key's user."},
	createDraft = {method = "POST", path = "/inbox/{contactId}/drafts", access = "data:write", query = {"draftOwner"}, required = {"channel", "content"},
		about = "Body {channel, content, subject?, cc?, replyToActivityId?}. Nothing is sent."},
	getDraft = {method = "GET", path = "/inbox/{contactId}/drafts/{draftId}", query = {"draftOwner"}, about = "Retrieves a single draft with its full content, including attachments."},
	updateDraft = {method = "PATCH", path = "/inbox/{contactId}/drafts/{draftId}", access = "data:write", query = {"draftOwner"}, about = "Body {subject?, cc?, content?}."},
	deleteDraft = {method = "DELETE", path = "/inbox/{contactId}/drafts/{draftId}", access = "data:write", query = {"draftOwner"}, about = "Soft-deletes a draft by setting its deletedAt timestamp."},

	listContacts = {method = "GET", path = "/contacts", query = list({"idsOrEmails", "crmIds", "search", "email", "listId", "notInAnyCampaign", "companyId", "companyDomain",
		"companyLinkedinUrl", "withPrimaryCompany", "crmSyncStatus"}, PAGE), about = "CRM contacts; limit <= 500."},
	upsertContact = {method = "POST", path = "/contacts", access = "data:write", query = {"updateStrategy"},
		about = "Body {email? or linkedinUrl? or contactId?, firstName?, lastName?, jobTitle?, phone?, companyName?, ...}. Creates or updates."},
	mergeContacts = {method = "POST", path = "/contacts/merge", access = "data:write", required = {"primaryId", "secondaryIds"}, about = "Irreversible."},
	getContact = {method = "GET", path = "/contacts/{idOrEmail}", about = "A contact by id or email."},
	deleteContact = {method = "DELETE", path = "/contacts/{idOrEmail}", access = "data:write", about = "Deletes a lemlist contact resolved by its id (ctc_xxx) or email. Cascades to the contact's leads, opportunities, list associations, inbox conversations and activities. No CRM-side propagation — only the lemlist record is removed."},
	listContactNotes = {method = "GET", path = "/contacts/{idOrEmail}/notes", query = list(PAGED, SORT), about = "Notes on a contact."},
	createContactNote = {method = "POST", path = "/contacts/{idOrEmail}/notes", access = "data:write", required = {"note"}, about = "Writes a note on a contact resolved by its id (ctc_xxx) or email, exactly as a note written in the lemlist app: it is stored as a note of the contact, pushed to your connected CRM (HubSpot, Salesforce, Pipedrive) like an in-app note, and logged in the team activity feed."},
	listContactLists = {method = "GET", path = "/contacts/lists", query = {"search"}, about = "Retrieves all static and dynamic contact lists for the team. Optionally filter by name."},
	createContactList = {method = "POST", path = "/contacts/lists", access = "data:write", required = {"name"}, about = "Creates a new static contact list. After creating the list, use POST /contacts/lists/{listId}/entities to add contacts to it."},
	updateContactListMembers = {method = "POST", path = "/contacts/lists/{listId}/entities", access = "data:write", query = {"action"}, required = {"contactIds"},
		about = "Body {contactIds}; action is add (default) or remove."},

	listCompanies = {method = "GET", path = "/companies", query = list({"idsOrDomains", "crmIds", "search", "fields", "listId", "crmSyncStatus"}, PAGE, SORT), about = "CRM companies; limit <= 500."},
	upsertCompany = {method = "POST", path = "/companies", access = "data:write", query = {"updateStrategy"}, about = "Body {name?, domain?, linkedinUrl?, companyId?, industry?, size?, ...}. Creates or updates."},
	mergeCompanies = {method = "POST", path = "/companies/merge", access = "data:write", required = {"primaryId", "secondaryIds"}, about = "Irreversible."},
	getCompany = {method = "GET", path = "/companies/{companyId}", about = "Retrieves one lemlist company by its id (cpn_xxx) and returns the company object itself, unwrapped. Answers 404 COMPANY_NOT_FOUND_BY_ID when no company of your team carries this id, where GET /companies?idsOrDomains= answers 200 with an empty data array."},
	deleteCompany = {method = "DELETE", path = "/companies/{companyId}", access = "data:write", query = {"force"}, about = "Deletes a company; force also when contacts are linked."},
	listCompanyNotes = {method = "GET", path = "/companies/{companyId}/notes", query = list(PAGED, SORT), about = "Notes on a company."},
	createCompanyNote = {method = "POST", path = "/companies/{companyId}/notes", access = "data:write", required = {"note"}, about = "Create Company Note."},
	listCompanyLists = {method = "GET", path = "/companies/lists", query = {"search"}, about = "Retrieves all static and dynamic company lists for the team. Optionally filter by name."},
	createCompanyList = {method = "POST", path = "/companies/lists", access = "data:write", required = {"name"}, about = "Creates a new static company list. After creating the list, use POST /companies/lists/{listId}/entities to add companies to it."},
	updateCompanyListMembers = {method = "POST", path = "/companies/lists/{listId}/entities", access = "data:write", query = {"action"}, required = {"companyIds"},
		about = "Body {companyIds}; action is add (default) or remove."},

	listActivities = {method = "GET", path = "/activities", version = true, query = list({"type", "campaignId", "leadId", "contactId", "isFirst", "minDate", "maxDate"}, PAGE),
		about = "Activity feed (emailsSent, emailsReplied, linkedinInviteAccepted, ...), newest first; limit <= 100."},
	deleteActivityRecording = {method = "DELETE", path = "/activities/{activityId}/recording-transcript", access = "data:write", about = "Deletes a call's recording and transcript."},

	listUnsubscribedVariables = {method = "GET", path = "/v2/unsubscribes/variables", query = PAGE, about = "Unsubscribed values (emails, domains, phones, LinkedIn URLs)."},
	unsubscribeVariables = {method = "POST", path = "/v2/unsubscribes/variables", access = "data:write", required = {"values"}, about = "Use it for values containing '/'."},
	getUnsubscribedVariable = {method = "GET", path = "/v2/unsubscribes/variables/{value}", about = "One value's status."},
	unsubscribeVariable = {method = "POST", path = "/v2/unsubscribes/variables/{value}", access = "data:write", body = false, about = "Unsubscribes one value."},
	resubscribeVariable = {method = "DELETE", path = "/v2/unsubscribes/variables/{value}", access = "data:write", about = "Resubscribes one value."},
	getContactSubscription = {method = "GET", path = "/v2/unsubscribes/contacts/{contactId}", about = "A contact's subscription status."},
	unsubscribeContact = {method = "POST", path = "/v2/unsubscribes/contacts/{contactId}", access = "data:write", body = false, about = "Unsubscribes a contact."},
	resubscribeContact = {method = "DELETE", path = "/v2/unsubscribes/contacts/{contactId}", access = "data:write", about = "Resubscribes a contact."},

	listWebhooks = {method = "GET", path = "/hooks", about = "Webhooks, without their secrets."},
	addWebhook = {method = "POST", path = "/hooks", access = "data:write", required = {"targetUrl"},
		about = "Body {targetUrl, type?, campaignId?, isFirst?=true, secret?}. lemlist then posts events to targetUrl."},
	deleteWebhook = {method = "DELETE", path = "/hooks/{hookId}", access = "data:write", about = "Delete Webhook."},

	enrich = {method = "POST", path = "/enrich", access = "data:write", body = false, query = list(ENRICH, {"email", "linkedinUrl", "firstName", "lastName", "companyName", "companyDomain", "jobTitle"}),
		about = "Starts an enrichment; returns {id}. Poll getEnrichment."},
	bulkEnrich = {method = "POST", path = "/v2/enrichments/bulk", access = "data:write", query = {"webhookUrl"}, body = "requests", required = {"requests"},
		about = "requests={{input={email?, linkedinUrl?, ...}, enrichmentRequests={'find_email', ...}}} (<= 500)."},
	getEnrichment = {method = "GET", path = "/enrich/{enrichId}", about = "Enrichment status and result."},
	enrichLead = {method = "POST", path = "/leads/{leadId}/enrich", access = "data:write", body = false, query = list(ENRICH, {"force"}), about = "Enriches a campaign lead."},
	listEnrichmentProviders = {method = "GET", path = "/v2/enrichments/providers", query = {"type"}, required = {"type"}, about = "Providers usable in waterfalls (beta)."},
	disconnectEnrichmentProvider = {method = "DELETE", path = "/v2/enrichments/providers/{providerId}/connection", access = "data:write", about = "Removes a provider's own API key."},
	listEnrichmentWaterfalls = {method = "GET", path = "/v2/enrichments/waterfalls", query = {"type"}, about = "Provider order per enrichment type (beta)."},
	getEnrichmentWaterfall = {method = "GET", path = "/v2/enrichments/waterfalls/{waterfallId}", about = "Returns one waterfall of your team, default or custom."},
	updateEnrichmentWaterfall = {method = "PATCH", path = "/v2/enrichments/waterfalls/{waterfallId}", access = "data:write", about = "Body {name?, providers?}."},
	resetEnrichmentWaterfall = {method = "PUT", path = "/v2/enrichments/waterfalls/{waterfallId}/reset", access = "data:write", body = false, about = "Restores the default order."},
	runContactSourcing = {method = "POST", path = "/contact-sourcing", access = "data:write", required = {"companyIds"}, about = "Body {companyIds, overwrite?}. Finds people at companies."},
	getContactSourcingRun = {method = "GET", path = "/contact-sourcing", query = {"runId", "companyId"}, about = "A sourcing run's results."},
	addSourcedContact = {method = "POST", path = "/contact-sourcing/contacts", access = "data:write", required = {"leadId", "companyId"}, about = "Body {leadId, companyId, listId?, findEmail?}."},

	listSignals = {method = "GET", path = "/watchlist/signals", query = list({"watchListId", "type", "status", "receivedAtFrom", "receivedAtTo"}, PAGED, SORT), about = "Signals detected by signal agents."},
	updateSignals = {method = "PUT", path = "/watchlist/signals", access = "data:write", required = {"signalIds", "status"}, about = "Body {signalIds, status='handled' or 'ignored', reason?}."},
	pushExternalSignals = {method = "POST", path = "/watchlist/{watchListId}/external-signals", access = "data:write", about = "Body {contact?, company?, customFields?}."},
	listSignalAgents = {method = "GET", path = "/watchlist", query = list({"type", "status"}, PAGED), about = "Signal agents."},
	createSignalAgent = {method = "POST", path = "/watchlist", access = "data:write", required = {"name", "type"}, about = "Body {name, type, filters?, personaId?, campaignId?, activate?, ...}."},
	updateSignalAgent = {method = "PATCH", path = "/watchlist", access = "data:write", required = {"watchListId"}, about = "Body {watchListId, name?, filters?, activate?, ...}."},
	deleteSignalAgent = {method = "DELETE", path = "/watchlist", access = "data:write", query = {"watchListId"}, required = {"watchListId"}, about = "Delete Signal Agent."},
	monitorCrmLists = {method = "POST", path = "/watchlist/crm-lists", access = "data:write", required = {"watchListId", "crmListIds"}, about = "Switches a Signal Agent to the CRM list source and monitors every company (or contact) of the given CRM lists. The lists replace the ones it monitored: entities left out stop being monitored. Only companies with a domain and contacts with a LinkedIn URL are monitored."},
	getSignalAgentHistory = {method = "GET", path = "/watchlist/history", query = list({"watchListId"}, PAGED), required = {"watchListId"}, about = "Configuration changes."},
	listSignalTypes = {method = "GET", path = "/watchlist/library", about = "Available signal types."},
	listSignalFilters = {method = "GET", path = "/watchlist/filters", query = {"type"}, about = "Filters per signal type."},
	getSignalFilterValues = {method = "GET", path = "/watchlist/filter-values", query = {"filterId", "query"}, required = {"filterId"}, about = "Autocompletes a filter's values."},

	getWarmupErrors = {method = "GET", path = "/warmup/errors", about = "Mailboxes whose warm-up fails."},
	startWarmup = {method = "POST", path = "/warmup/{userMailboxId}/start", access = "data:write", body = false, about = "Starts warm-up for a mailbox."},
	pauseWarmup = {method = "POST", path = "/warmup/{userMailboxId}/pause", access = "data:write", body = false, about = "Pauses warm-up."},
	getWarmupSettings = {method = "GET", path = "/warmup/{userMailboxId}/settings", about = "Warm-up settings and status."},
	updateWarmupSettings = {method = "PATCH", path = "/warmup/{userMailboxId}/settings", access = "data:write", about = "Body {warmEmailMax?, warmEmailRampup?, answerPercentage?, ...}."},

	listDeliverabilityAlerts = {method = "GET", path = "/deliverability/alerts", about = "Deliverability alerts."},
	createDeliverabilityAlert = {method = "POST", path = "/deliverability/alerts", access = "data:write",
		required = {"widget", "metric", "severity", "scope", "threshold", "comparisonOperator", "periodDays", "periodMode"}, about = "Body: the alert definition."},
	getDeliverabilityAlert = {method = "GET", path = "/deliverability/alerts/{alertId}", about = "Get Deliverability Alert."},
	updateDeliverabilityAlert = {method = "PATCH", path = "/deliverability/alerts/{alertId}", access = "data:write", about = "Body {threshold?, enabled?, ...}."},
	deleteDeliverabilityAlert = {method = "DELETE", path = "/deliverability/alerts/{alertId}", access = "data:write", about = "Delete Deliverability Alert."},
	listDeliverabilityIncidents = {method = "GET", path = "/deliverability/incidents", query = {"type", "state", "userId", "since", "until", "limit", "skip"}, about = "Triggered incidents."},
	getSenderPictureStatus = {method = "GET", path = "/sender-picture/mailboxes", query = {"userId"}, about = "Profile picture sync per mailbox."},
	syncSenderPicture = {method = "POST", path = "/sender-picture/sync", access = "data:write", about = "Body {scope, mailboxId?, email?, userId?}."},
	testEmailAccount = {method = "POST", path = "/user/email-accounts/{emailAccountId}/test", access = "data:write", body = false, about = "Tests a mailbox connection."},
	disconnectEmailAccount = {method = "DELETE", path = "/user/email-accounts/{emailAccountId}", access = "data:write", about = "Disconnects a mailbox."},
}

local function hasBody(endpoint: Endpoint): boolean
	if endpoint.body ~= nil then return endpoint.body ~= false end
	return endpoint.method == "POST" or endpoint.method == "PATCH" or endpoint.method == "PUT"
end

-- lemlist IDs are three lowercase letters, an underscore and 17 characters (cam_..., lea_...).
-- The fields below must be such IDs, so that a value cannot select a sibling route such as
-- /contacts/export or /inbox/labels. Other IDs (templates, alerts, personas, ...) only need to
-- be one safe segment.
local LEMLIST_IDS = table.freeze({campaignId = true, leadId = true, userId = true, sequenceId = true, stepId = true,
	branchSequenceId = true, scheduleId = true, contactId = true, companyId = true, listId = true, watchListId = true,
	userMailboxId = true, activityId = true, hookId = true})

local function lemlistId(value: any): boolean
	return type(value) == "string" and #value == 21 and string.match(value, "^%l%l%l_[%w_]+$") ~= nil
end

local function email(value: any): boolean
	return type(value) == "string" and #value <= 320 and string.match(value, "^[%w%.%+_%-]+@[%w%-]+%.[%w%.%-]+$") ~= nil
end

-- Emails go into the path unencoded: some lemlist routes do not decode %40.
local function segment(value: any, field: string): string
	if LEMLIST_IDS[field] then
		assert(lemlistId(value), field .. " must be a lemlist ID such as " .. string.sub(field, 1, 3) .. "_...")
		return value
	elseif field == "leadIdOrEmail" or field == "idOrEmail" then
		assert(lemlistId(value) or email(value), field .. " must be a lemlist ID or an email address")
		return value
	elseif field == "value" then
		assert(type(value) == "string" and #value <= 320 and string.match(value, "^[%w%.@%+_%-]+$") and string.match(value, "%w"),
			field .. " must be an email, domain or phone number without '/', '%' or spaces")
		assert(string.match(value, "^%.") == nil, field .. " must not start with a dot")
		return value
	end
	assert(type(value) == "string" and #value <= 128 and string.match(value, "^[%w_%-]+$"), field .. " must be an ID")
	return value
end

local function scalar(value: any, field: string): string
	local kind = type(value)
	assert(kind == "string" or kind == "boolean" or kind == "number", field .. " must be a string, boolean, number or array of those")
	return url.encode(value)
end

-- Arrays become comma-separated values, as lemlist expects for campaignIds.
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

-- lemlist reads an access_token from the query or body before the Authorization header.
local function noToken(fields: {[string]: any}, where: string)
	for key in fields do
		assert(type(key) ~= "string" or string.lower(key) ~= "access_token", where .. " must not contain access_token")
	end
end

local function fail(name: string, status: number, message: string): never
	return houston.fail({operation = name, layer = "upstream", upstream_status = status,
		retryable = status == 429 or status >= 500, message = message})
end

-- Errors are plain text (authentication, plan limits, rate limits), {error} or {error, code}.
local function failStatus(name: string, response: HttpResponse): never
	local status = response.statusCode
	local raw = await(response.body:readPrefix(16 * 1024))
	local message = PROVIDER .. " HTTP " .. tostring(status)
	local ok, value = pcall(json.decode, raw)
	if ok and type(value) == "table" and (type(value.error) == "string" or type(value.message) == "string") then
		if type(value.code) == "string" then message ..= " (" .. string.sub(value.code, 1, 100) .. ")" end
		message ..= ": " .. string.sub(if type(value.error) == "string" then value.error else value.message, 1, 600)
		if type(value.details) == "table" then message ..= " " .. string.sub(json.encode(value.details), 1, 600) end
	elseif string.match(raw, "%S") and not string.match(raw, "^%s*<") then
		message ..= ": " .. string.sub(raw, 1, 600)
	end
	if status == 402 and string.find(raw, "route is available starting", 1, true) then message ..= " (the lemlist plan does not include this API)" end
	local retry = response.headers["retry-after"]
	if retry and retry[1] then message ..= "; Retry-After: " .. retry[1] end
	return fail(name, status, message)
end

-- Reads return JSON objects or arrays. Writes may answer with no body, {} or plain text.
local function decode(name: string, endpoint: Endpoint, response: HttpResponse): any
	if response.statusCode < 200 or response.statusCode >= 300 then failStatus(name, response) end
	local raw = await(response.body:readAll())
	local ok, value = pcall(json.decode, raw)
	if ok and type(value) == "table" then return value end
	if endpoint.access and not string.match(raw, "^%s*[%[{]") then
		if not string.match(raw, "%S") then return {} end
		return {message = string.sub(raw, 1, 2000)}
	end
	return fail(name, response.statusCode, PROVIDER .. " returned invalid JSON")
end

local function request(name: string, endpoint: Endpoint, input: Options?): any
	local args: Options = {}
	if input ~= nil then
		assert(type(input) == "table", "opts must be an object")
		for key in input do assert(type(key) == "string", "opts must have named fields") end
		args = table.clone(input)
	end
	noToken(args, name .. " options")
	local path = string.gsub(endpoint.path, "{([%w_]+)}", function(field: string)
		local value = segment(args[field], field)
		args[field] = nil
		return value
	end)
	for _, field in endpoint.required or NONE do
		assert(args[field] ~= nil and args[field] ~= NULL, field .. " is required")
	end
	local query: {string} = {}
	if endpoint.version then table.insert(query, "version=v2") end
	for _, field in endpoint.query or NONE do
		local value = args[field]
		-- Without a limit, some offset lists (unsubscribes) return the whole collection.
		if field == "limit" and value == nil and table.find(endpoint.query or NONE, "offset") then value = DEFAULT_LIMIT end
		-- lemlist marks the conversation read for any markAsRead value, false included.
		if field == "markAsRead" and value ~= nil then
			assert(type(value) == "boolean", "markAsRead must be a boolean")
			assert(not value or houston.allows("data:write"), "markAsRead=true marks the conversation read and needs write access")
			if not value then value = nil end
		end
		if value ~= nil and table.find(endpoint.jsonQuery or NONE, field) then
			assert(type(value) == "table", field .. " must be an array")
			queryValue(value, field)
			table.insert(query, field .. "=" .. url.encode(json.encode(value)))
		elseif value ~= nil then
			table.insert(query, field .. "=" .. queryValue(value, field))
		end
		args[field] = nil
	end
	if endpoint.variables then
		local variables = args.variables
		assert(variables ~= NULL and type(variables) == "table" and next(variables) ~= nil,"variables must be a nonempty object of name = value")
		local names: {string} = {}
		for key, value in variables do
			assert(type(key) == "string" and string.match(key, "^[%w_%-]+$"), "variable names must be letters, digits, _ or -")
			table.insert(names, key)
		end
		noToken(variables, "variables")
		table.sort(names)
		for _, key in names do table.insert(query, key .. "=" .. scalar(variables[key], key)) end
		args.variables = nil
	end
	if #query > 0 then path ..= "?" .. table.concat(query, "&") end
	local headers: HttpHeaders = {Accept = {"application/json"}}
	local body: string? = nil
	if type(endpoint.body) == "string" then
		local field = endpoint.body
		assert(type(args[field]) == "table" and #args[field] > 0, field .. " must be a nonempty array")
		for _, item in args[field] do
			if type(item) == "table" then noToken(item, field) end
		end
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

local function inputSchema(name: string, endpoint: Endpoint): Options
	local properties: Options = {}
	local required: {string} = json.decode("[]")
	for field in string.gmatch(endpoint.path, "{([%w_]+)}") do
		properties[field] = {type = "string", minLength = 1}
		table.insert(required, field)
	end
	local types = reference[name].types
	for _, field in endpoint.query or NONE do
		local kind = if table.find(endpoint.jsonQuery or NONE, field) then "array" else types[field]
		properties[field] = if kind == "integer" or kind == "number" or kind == "boolean" or kind == "array" then {type = kind} else {}
	end
	local only = not hasBody(endpoint)
	if endpoint.variables then
		properties.variables = {type = "object", minProperties = 1}
		table.insert(required, "variables")
	elseif type(endpoint.body) == "string" then
		properties[endpoint.body] = {type = "array", minItems = 1}
		only = true
	end
	for _, field in endpoint.required or NONE do
		if properties[field] == nil then properties[field] = {} end
		if not table.find(required, field) then table.insert(required, field) end
	end
	table.sort(required)
	return {type = "object", properties = properties, required = required, additionalProperties = not only,
		examples = {reference[name].example}}
end

local help: Options = {
	text = "lemlist API (" .. DOCS .. "). Every function takes one options object with lemlist's field names: path IDs, query options and, for writes, the JSON body fields side by side. Results are lemlist's JSON unchanged. Calls return completed values: use them directly, without await. Select a function's section for its arguments and a runnable example, or a topic below.",
	functions = {},
	sections = {
		ids = "IDs look like cam_ (campaign), lea_ (lead), seq_ (sequence), stp_ (step), usr_ (user), ctc_ (contact), cpn_ (company), usm_ (mailbox), skd_ (schedule), wat_ (signal agent). OrEmail parameters also accept an email. Arrays in query options become comma-separated lists, except getCampaignStats channels (a JSON array). Dates are ISO 8601. Find sequence and step IDs with getCampaignSequences, leads with listCampaignLeads({campaignId='cam_...', state='interested'}) and sender mailboxes with getUserChannels.",
		paging = "Lists return one page. Offset lists default to limit=100 (campaign leads, contacts and companies accept 500); others take page and limit. Fetch the next page while a full page comes back. There is no hidden paging.",
		errors = "lemlist allows about 20 requests per 2 seconds per key (HTTP 429 with Retry-After); HTTP 402 means the plan or credits do not allow the call. Errors report the HTTP status and lemlist's message.",
		access = if houston.allows("data:write")
			then "Writes take effect at once: send* functions message real people; starting campaigns or launching leads sends their sequence; findEmail, verifyEmail, findPhone, linkedinEnrichment, enrich and sourcing spend credits; merges and deletes cannot be undone. A write answering with no body returns {} and plain text returns {message}; lemlist also answers {} to some invalid requests, so read the resource back to confirm. There are no automatic retries: after a timeout or 5xx, check before repeating a write."
			else "This connection has read access: changes, team settings (they include webhook secrets) and markAsRead need write access.",
	},
}

local exports: {[string]: any} = {help = help}
for name, endpoint in endpoints do
	if not endpoint.access or houston.allows(endpoint.access) then
		help.functions[name] = {description = endpoint.about .. " (" .. endpoint.method .. " /api" .. endpoint.path .. ")",
			inputSchema = inputSchema(name, endpoint), annotations = {readOnlyHint = endpoint.method == "GET" or endpoint.access == nil}}
		exports[name] = function(args: Options?): any return request(name, endpoint, args) end
	end
end
return exports
