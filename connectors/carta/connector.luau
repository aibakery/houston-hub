-- Carta API Platform v1alpha1. Arguments and results keep Carta's native camelCase field names.
type Options = {[string]: any}
type Endpoint = {method: string, path: string, query: {string}?, extra: {string}?, required: {string}?, write: boolean?, body: (boolean | string)?, upload: string?, doc: string, about: string}

local PROVIDER = "Carta"
local API = if auth.method == "playground" then "https://api.playground.carta.team" else "https://api.carta.com"
local DOCS = "https://docs.carta.com/api-platform/reference/v-1-alpha-1-"

local PAGE = {"pageSize", "pageToken"}
local MODIFIED = {"pageSize", "pageToken", "lastModifiedDatetimeAfter", "lastModifiedDatetimeBefore"}
local AS_OF = {"asOfDate", "pageSize", "pageToken"}

-- Operations of Carta's API reference, checked on 2026-10-19. Path {fields} are required;
-- listed query fields are taken from the options and the other fields form the JSON body of
-- POST requests. Reads that need a readwrite_ scope or return a credential are marked write = true.
local endpoints: {[string]: Endpoint} = {
	getCurrentUser = {method = "GET", path = "/v1alpha1/user", doc = "user-get-current-user", about = "{user={id, firstName, lastName, email}}."},

	listIssuers = {method = "GET", path = "/v1alpha1/issuers", query = PAGE, doc = "issuers-list-issuers", about = "Companies whose cap tables you can access, {issuers, nextPageToken}."},
	getIssuer = {method = "GET", path = "/v1alpha1/issuers/{id}", doc = "issuers-get-issuer", about = "A company."},
	listPointsOfContact = {method = "GET", path = "/v1alpha1/issuers/{issuerId}/pointsOfContact", doc = "issuers-list-points-of-contact", about = "The company's contacts."},
	getStockSplitChanges = {method = "POST", path = "/v1alpha1/issuers/{issuerId}/securities:stockSplitChanges", required = {"securities", "since"}, write = false,
		doc = "issuers-get-stock-split-asset-changes", about = "Body {securities={{securityType (lowercase: option_grant or certificate), securityId}}, since={value=date-time}}. Whether a stock split changed those securities since then: {affectedAssets, asOf, splitOccurredSince, ...}."},
	getIssuerCapitalizationTable = {method = "GET", path = "/v1alpha1/issuers/{issuerId}/capitalizationTable", query = {"asOfDate"}, doc = "issuers-get-capitalization-table",
		about = "Cap table summary by share class."},
	getIssuerStakeholderCapitalizationTable = {method = "GET", path = "/v1alpha1/issuers/{issuerId}/stakeholderCapitalizationTable", query = AS_OF,
		doc = "issuers-get-stakeholder-capitalization-table", about = "Cap table by stakeholder; pageSize up to 100."},
	listShareClasses = {method = "GET", path = "/v1alpha1/issuers/{issuerId}/shareClasses", query = AS_OF, doc = "issuers-list-share-classes", about = ""},
	listStakeholders = {method = "GET", path = "/v1alpha1/issuers/{issuerId}/stakeholders", query = PAGE, doc = "issuers-list-stakeholders", about = "People and entities holding securities; pageSize up to 100."},
	getStakeholder = {method = "GET", path = "/v1alpha1/issuers/{issuerId}/stakeholders/{id}", doc = "issuers-get-stakeholder", about = ""},
	getStakeholderEquitySummary = {method = "GET", path = "/v1alpha1/issuers/{issuerId}/stakeholders/{stakeholderId}/equitySummary", query = {"asOfDate", "includeCanceled"},
		doc = "issuers-get-stakeholder-equity-summary", about = "A stakeholder's certificates, options, RSAs and RSUs."},
	listFairMarketValues = {method = "GET", path = "/v1alpha1/issuers/{issuerId}/fairMarketValues", query = PAGE, doc = "issuers-list-fair-market-values", about = "409A valuations."},
	listVestingScheduleTemplates = {method = "GET", path = "/v1alpha1/issuers/{issuerId}/vestingScheduleTemplates", query = PAGE, doc = "issuers-list-vesting-schedule-templates", about = ""},
	listInterests = {method = "GET", path = "/v1alpha1/issuers/{issuerId}/interests", query = AS_OF, doc = "issuers-list-interests", about = "LLC interests; pageSize default and maximum 100."},
	listTransactions = {method = "GET", path = "/v1alpha1/issuers/{issuerId}/transactions", query = {"type", "pageSize", "pageToken"}, required = {"type"},
		doc = "issuers-list-transactions", about = "Security history. type: option, rsu, rsa, certificate, warrant, convertible, piu, sar or phantom; pageSize default 50, up to 1000."},
	listCertificates = {method = "GET", path = "/v1alpha1/issuers/{issuerId}/certificates", query = MODIFIED, doc = "issuers-list-certificates", about = "Share certificates."},
	getCertificate = {method = "GET", path = "/v1alpha1/issuers/{issuerId}/certificates/{id}", doc = "issuers-get-certificate", about = ""},
	listConvertibleNotes = {method = "GET", path = "/v1alpha1/issuers/{issuerId}/convertibleNotes", query = PAGE, doc = "issuers-list-convertible-notes", about = "Convertible notes and SAFEs."},
	getConvertibleNote = {method = "GET", path = "/v1alpha1/issuers/{issuerId}/convertibleNotes/{id}", doc = "issuers-get-convertible-note", about = ""},
	listOptionGrants = {method = "GET", path = "/v1alpha1/issuers/{issuerId}/optionGrants", query = MODIFIED, doc = "issuers-list-option-grants", about = ""},
	getOptionGrant = {method = "GET", path = "/v1alpha1/issuers/{issuerId}/optionGrants/{id}", doc = "issuers-get-option-grant", about = ""},
	listRestrictedStockAwards = {method = "GET", path = "/v1alpha1/issuers/{issuerId}/restrictedStockAwards", query = MODIFIED, doc = "issuers-list-restricted-stock-awards", about = ""},
	getRestrictedStockAward = {method = "GET", path = "/v1alpha1/issuers/{issuerId}/restrictedStockAwards/{id}", doc = "issuers-get-restricted-stock-award", about = ""},
	listRestrictedStockUnits = {method = "GET", path = "/v1alpha1/issuers/{issuerId}/restrictedStockUnits", query = MODIFIED, doc = "issuers-list-restricted-stock-units", about = ""},
	getRestrictedStockUnit = {method = "GET", path = "/v1alpha1/issuers/{issuerId}/restrictedStockUnits/{id}", doc = "issuers-get-restricted-stock-unit", about = ""},
	listOptionExercises = {method = "GET", path = "/v1alpha1/issuers/{issuerId}/optionExercises", query = PAGE, doc = "issuers-list-option-exercises", about = "pageSize up to 100."},
	updateExerciseMoneyMovement = {method = "POST", path = "/v1alpha1/issuers/{issuerId}/optionExercises/{exerciseId}:updateMoneyMovement", doc = "issuers-update-money-movement",
		about = "Body {moneyMovement={completionDate={value=date}}}: when the exercise funds were received."},
	updateExerciseTaxWithholding = {method = "POST", path = "/v1alpha1/issuers/{issuerId}/optionExercises/{exerciseId}:updateTaxWithholding", doc = "issuers-update-tax-withholding",
		about = "Body {taxWithholdings={{name, rate={value}, taxes=money, jurisdiction={country={value}, countrySubdivision?={value}, city?}}}}."},
	createDraftOptionGrant = {method = "POST", path = "/v1alpha1/issuers/{issuerId}/draftOptionGrantSets/{draftOptionGrantSetId}/draftOptionGrants", required = {"draftOptionGrant"},
		doc = "issuers-draftsecurities-create-draft-option-grant", about = "Body {draftOptionGrant}; see the reference for its fields (dates are {year, month, day}). A grant awaiting board approval; vesting templates come from listVestingScheduleTemplates."},
	getDraftOptionGrant = {method = "GET", path = "/v1alpha1/issuers/{issuerId}/draftOptionGrantSets/{draftOptionGrantSetId}/draftOptionGrants/{draftOptionGrantId}",
		doc = "issuers-draftsecurities-get-draft-option-grant", about = ""},
	initiateSecondarySettlement = {method = "POST", path = "/v1alpha1/issuers/{issuerId}/secondaryTransactions", required = {"externalReferenceId", "rightOfFirstRefusalOutcome", "pricePerShare", "securities"},
		doc = "issuers-initiate-settlement", about = "Body {externalReferenceId, rightOfFirstRefusalOutcome, pricePerShare=money, securities={{securityType (option_grant or certificate), securityId, stockOptionType? (ISO or NSO), quantity={value}}}, buyerInformation?}; buyerInformation is required for WAIVED and EXERCISED_BY_STAKEHOLDER. Soft-locks the securities; keep secondaryTransactionId and follow transactionState."},
	getSecondaryTransaction = {method = "GET", path = "/v1alpha1/issuers/{issuerId}/secondaryTransactions/{secondaryTransactionId}", write = true,
		doc = "issuers-get-secondary-transaction", about = "State and per-security settlement outcome, including tax withholding."},
	finalizeSecondarySettlement = {method = "POST", path = "/v1alpha1/issuers/{issuerId}/secondaryTransactions/{secondaryTransactionId}:finalize",
		doc = "issuers-finalize-settlement", about = "Body {securities?={{securityId, stockOptionType?, taxLineItems?}}}. Confirms all money movement (irreversible) is complete; the issuer still approves before the cap table changes."},

	listCorporations = {method = "GET", path = "/v1alpha1/corporations", query = PAGE, doc = "corporations-list-corporations", about = "Corporations for Carta Total Compensation."},
	getCompensationBenchmarkAttributes = {method = "GET", path = "/v1alpha1/corporations/{corporationId}/compensationBenchmarkAttributes",
		doc = "compensation-get-compensation-benchmark-attributes", about = "Valid values for the benchmark filters."},
	getCompensationBenchmarks = {method = "GET", path = "/v1alpha1/corporations/{corporationId}/compensationBenchmarks",
		query = {"postMoneyValuationBucket", "geoAdjustmentLocation", "jobArea", "compensationType", "jobSpecialization", "jobLevel", "pageSize", "pageToken"},
		required = {"postMoneyValuationBucket", "geoAdjustmentLocation", "jobArea"}, doc = "compensation-get-compensation-benchmarks", about = "pageSize default and maximum 100."},

	createDraftIssuer = {method = "POST", path = "/v1alpha1/draftIssuers", doc = "draft-issuers-create-draft-issuer",
		about = "Body {draftIssuer}; see the reference for its fields. Starts a company on Carta Launch; the result's registrationUrl is a one-time link for its primary contact."},
	getDraftIssuer = {method = "GET", path = "/v1alpha1/draftIssuers/{id}", write = true, doc = "draft-issuers-get-draft-issuer",
		about = "Includes the primary contact's one-time registrationUrl; treat it as a secret."},
	uploadOpenCapTable = {method = "POST", path = "/v1alpha1/openCapTables", extra = {"path"}, required = {"path"}, body = false, upload = "application/zip", doc = "open-cap-tables-upload-open-cap-table",
		about = "Sends the OCF ZIP archive at session file path as the raw body. Carta stores submissions during its beta; getOpenCapTable reports state."},
	getOpenCapTable = {method = "GET", path = "/v1alpha1/openCapTables/{id}", doc = "open-cap-tables-get-open-cap-table", about = "Processing status of an OCF upload."},
	uploadFile = {method = "POST", path = "/v1alpha1/files:upload", required = {"file"}, doc = "files-upload-file",
		about = "Body {file={filePayload (base64, at most 3.5 MiB), uploadDetails={name, description?, tags?}}}."},

	listFirms = {method = "GET", path = "/v1alpha1/investors/firms", query = PAGE, doc = "investors-list-firms", about = "Investment firms you can access."},
	listFunds = {method = "GET", path = "/v1alpha1/investors/firms/{firmId}/funds", query = PAGE, doc = "investors-list-funds", about = ""},
	listInvestments = {method = "GET", path = "/v1alpha1/investors/firms/{firmId}/funds/{fundId}/investments", query = PAGE, doc = "investors-list-investments",
		about = "Portfolio companies with cap table data on Carta."},
	listInvestmentCapitalizationTables = {method = "GET", path = "/v1alpha1/investors/firms/{firmId}/funds/{fundId}/investments/{companyId}/capitalizationTables", query = PAGE,
		doc = "investors-list-capitalization-tables", about = ""},
	getInvestmentCapitalizationTable = {method = "GET", path = "/v1alpha1/investors/firms/{firmId}/funds/{fundId}/investments/{companyId}/capitalizationTables/{capitalizationTableId}",
		query = {"asOfDate"}, doc = "investors-get-capitalization-table", about = "capitalizationTableId = companyId selects the primary cap table."},
	getInvestmentStakeholderCapitalizationTable = {method = "GET", path = "/v1alpha1/investors/firms/{firmId}/funds/{fundId}/investments/{companyId}/stakeholderCapitalizationTables/{capitalizationTableId}",
		query = AS_OF, doc = "investors-get-stakeholder-capitalization-table", about = "capitalizationTableId = companyId selects the primary cap table."},
	listInvestmentCertificates = {method = "GET", path = "/v1alpha1/investors/firms/{firmId}/funds/{fundId}/investments/{investmentId}/certificates",
		query = {"asOfDate", "pageSize", "pageToken", "lastModifiedDatetimeAfter", "lastModifiedDatetimeBefore"}, doc = "investors-list-certificates", about = "pageSize up to 100."},
	listInvestmentConvertibleNotes = {method = "GET", path = "/v1alpha1/investors/firms/{firmId}/funds/{fundId}/investments/{investmentId}/convertibleNotes", query = AS_OF,
		doc = "investors-list-convertible-notes", about = "Convertible notes and SAFEs; pageSize up to 100."},
	listInvestmentWarrants = {method = "GET", path = "/v1alpha1/investors/firms/{firmId}/funds/{fundId}/investments/{investmentId}/warrants", query = AS_OF,
		doc = "investors-list-warrants", about = "pageSize up to 100."},
	listCashBalances = {method = "GET", path = "/v1alpha1/investors/firms/{firmId}/funds/{fundId}/cashBalances", query = {"asOfDateTime", "pageSize", "pageToken"},
		doc = "investors-list-cash-balances", about = ""},
	listFundPerformanceMetrics = {method = "GET", path = "/v1alpha1/investors/firms/{firmId}/funds/{fundId}/metrics", query = {"asOfDateTime", "reportType", "pageSize", "pageToken"},
		doc = "investors-list-fund-performance-metrics", about = "reportType: BY_FUND, BY_PARTNER_TYPE or BY_PARTNER."},
	listFirmPerformanceMetrics = {method = "GET", path = "/v1alpha1/investors/firms/{firmId}/metrics", query = {"fundIds", "asOfDateTime", "groupBy", "pageSize", "pageToken"},
		doc = "investors-list-firm-performance-metrics", about = "Aggregated across funds. groupBy: AGGREGATION_TYPE_BY_PARTNER_TYPE or AGGREGATION_TYPE_BY_PARTNER_GROUP."},
	listPartners = {method = "GET", path = "/v1alpha1/investors/firms/{firmId}/partners", query = {"fundIds", "groupId", "pageSize", "pageToken"},
		doc = "investors-list-partners", about = "LPs and GPs across funds; pageSize default 50, up to 100."},
	listPartnerContacts = {method = "GET", path = "/v1alpha1/investors/firms/{firmId}/partnerContacts", query = {"fundIds", "partnerIds", "pageSize", "pageToken"},
		doc = "investors-list-partner-contacts", about = "pageSize default 50, up to 100."},
	listFundInterests = {method = "GET", path = "/v1alpha1/investors/firms/{firmId}/funds/{fundId}/interests", query = PAGE, doc = "investors-list-fund-interests",
		about = "Partner interests; their id is the interestId the accounting writes take. pageSize default 50, up to 100."},
	createCapitalCall = {method = "POST", path = "/v1alpha1/investors/firms/{firmId}/funds/{fundId}/capitalCalls",
		required = {"externalReferenceId", "sourceSystem", "dueDate", "amount", "postAsDraft"}, doc = "investors-create-capital-call",
		about = "Body {externalReferenceId, sourceSystem, dueDate={value=date}, amount={value=decimal}, postAsDraft, interestIds?, purpose?, paymentDetailsId?}. Allocates the amount across the fund's interests (all when interestIds is empty). postAsDraft=false releases the call, posts its journal and may email partners; prefer true."},
	getCapitalCall = {method = "GET", path = "/v1alpha1/investors/firms/{firmId}/funds/{fundId}/capitalCalls/{capitalCallId}", write = true,
		doc = "investors-get-capital-call", about = "Status and allocation."},
	adjustCapitalCall = {method = "POST", path = "/v1alpha1/investors/firms/{firmId}/funds/{fundId}/capitalCalls/{capitalCallId}:adjust",
		required = {"externalReferenceId", "sourceSystem", "amount"}, doc = "investors-adjust-capital-call",
		about = "Body {externalReferenceId, sourceSystem, amount={value=decimal}, note?}. Changes the total of an unreleased call and reallocates it."},
	createCarriedInterestAllocation = {method = "POST", path = "/v1alpha1/investors/firms/{firmId}/funds/{fundId}/carriedInterestAllocations",
		required = {"externalReferenceId", "sourceSystem", "effectiveDate", "deltas"}, doc = "investors-create-carried-interest-allocation",
		about = "Body {externalReferenceId, sourceSystem, effectiveDate={value=date}, deltas={{interestId, amount={value=decimal}}}, notes?}; deltas net to zero with at most 2 decimals. Books carried interest calculated outside Carta."},
	createManagementFee = {method = "POST", path = "/v1alpha1/investors/firms/{firmId}/funds/{fundId}/managementFees",
		required = {"externalReferenceId", "sourceSystem", "periodStart", "periodEnd", "effectiveDate", "amount", "interestAmounts"}, doc = "investors-create-management-fee",
		about = "Body {externalReferenceId, sourceSystem, periodStart, periodEnd, effectiveDate (each {value=date}), amount=money, interestAmounts={{interestId, amount={value=decimal}}}}; interestAmounts sum to amount. Posts the fee journal."},
	getManagementFee = {method = "GET", path = "/v1alpha1/investors/firms/{firmId}/funds/{fundId}/managementFees/{managementFeeId}", write = true,
		doc = "investors-get-management-fee", about = "A fee booked by createManagementFee, with its journal state."},

	listPortfolios = {method = "GET", path = "/v1alpha1/portfolios", query = PAGE, doc = "portfolios-issuers-list-portfolios", about = "Your shareholder portfolios."},
	getPortfolio = {method = "GET", path = "/v1alpha1/portfolios/{portfolioId}", doc = "portfolios-issuers-get-portfolio", about = ""},
	listPortfolioIssuers = {method = "GET", path = "/v1alpha1/portfolios/{portfolioId}/issuers", query = PAGE, doc = "portfolios-issuers-list-portfolio-issuers", about = "Companies you hold securities in."},
	getPortfolioFairMarketValue = {method = "GET", path = "/v1alpha1/portfolios/{portfolioId}/issuers/{issuerId}/fairMarketValue", doc = "portfolios-issuers-get-fair-market-value", about = "Current 409A value."},
	listPortfolioCertificates = {method = "GET", path = "/v1alpha1/portfolios/{portfolioId}/issuers/{issuerId}/certificates", query = MODIFIED, doc = "portfolios-issuers-list-certificates", about = ""},
	getPortfolioCertificate = {method = "GET", path = "/v1alpha1/portfolios/{portfolioId}/issuers/{issuerId}/certificates/{certificateId}", doc = "portfolios-issuers-get-certificate", about = ""},
	listPortfolioConvertibleNotes = {method = "GET", path = "/v1alpha1/portfolios/{portfolioId}/issuers/{issuerId}/convertibleNotes", query = PAGE, doc = "portfolios-issuers-list-convertible-notes", about = "pageSize up to 100."},
	getPortfolioConvertibleNote = {method = "GET", path = "/v1alpha1/portfolios/{portfolioId}/issuers/{issuerId}/convertibleNotes/{id}", doc = "portfolios-issuers-get-convertible-note", about = ""},
	listPortfolioOptionGrants = {method = "GET", path = "/v1alpha1/portfolios/{portfolioId}/issuers/{issuerId}/optionGrants", query = MODIFIED, doc = "portfolios-issuers-list-option-grants", about = ""},
	getPortfolioOptionGrant = {method = "GET", path = "/v1alpha1/portfolios/{portfolioId}/issuers/{issuerId}/optionGrants/{optionGrantId}", doc = "portfolios-issuers-get-option-grant", about = ""},
	listPortfolioRestrictedStockAwards = {method = "GET", path = "/v1alpha1/portfolios/{portfolioId}/issuers/{issuerId}/restrictedStockAwards", query = MODIFIED,
		doc = "portfolios-issuers-list-restricted-stock-awards", about = ""},
	getPortfolioRestrictedStockAward = {method = "GET", path = "/v1alpha1/portfolios/{portfolioId}/issuers/{issuerId}/restrictedStockAwards/{restrictedStockAwardId}",
		doc = "portfolios-issuers-get-restricted-stock-award", about = ""},
	listPortfolioRestrictedStockUnits = {method = "GET", path = "/v1alpha1/portfolios/{portfolioId}/issuers/{issuerId}/restrictedStockUnits", query = MODIFIED,
		doc = "portfolios-issuers-list-restricted-stock-units", about = ""},
	getPortfolioRestrictedStockUnit = {method = "GET", path = "/v1alpha1/portfolios/{portfolioId}/issuers/{issuerId}/restrictedStockUnits/{restrictedStockUnitId}",
		doc = "portfolios-issuers-get-restricted-stock-unit", about = ""},
	listPortfolioSecurityTransactions = {method = "GET", path = "/v1alpha1/portfolios/{portfolioId}/issuers/{issuerId}/securityTransactions", query = PAGE,
		doc = "portfolios-issuers-list-security-transactions", about = "Exercises, sales and settlements, {securitytransactions, nextPageToken}; pageSize default 50, up to 1000."},
	listFundInvestmentDocuments = {method = "GET", path = "/v1alpha1/portfolios/{portfolioId}/fundInvestmentDocuments",
		query = {"fundId", "effectiveDateAfter", "effectiveDateBefore", "sharedDateAfter", "sharedDateBefore", "pageSize", "pageToken"},
		doc = "portfolios-list-fund-investment-documents", about = "Documents funds shared with you as a limited partner."},
	getFundInvestmentDocumentUrl = {method = "GET", path = "/v1alpha1/portfolios/{portfolioId}/fundInvestmentDocuments/{documentId}:download",
		doc = "portfolios-download-fund-investment-document", about = "{downloadUrl, downloadUrlExpirationTime}: a temporary signed link; treat it as a secret."},
}

-- Request layer shared verbatim by the Cal.com, Calendly, Carta, Carta CRM, Figma, Gusto, Resend and Vercel connectors
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

-- Carta IDs are numeric strings, UUIDs or short IDs; "-" selects every fund of a firm.
local function identifier(value: any, field: string): string
	if type(value) == "number" then
		assert(value >= 0 and value % 1 == 0 and value <= 9007199254740991, field .. " must be a Carta ID")
		return string.format("%d", value)
	end
	assert(type(value) == "string" and string.match(value, "^[%w_%-]+$") and #value <= 64, field .. " must be a Carta ID")
	return value
end

-- Carta errors are google.rpc.Status objects {code, message, details=[{reason}]}; a rate
-- limit answers {message}, and a missing token plain text.
local function failStatus(name: string, response: HttpResponse): never
	local message = "Carta HTTP " .. tostring(response.statusCode)
	local ok, value = pcall(json.decode, await(response.body:readPrefix(16 * 1024)))
	if ok and type(value) == "table" then
		local reasons: {string} = {}
		if type(value.details) == "table" then
			for _, detail in value.details do
				if type(detail) == "table" and type(detail.reason) == "string" then table.insert(reasons, detail.reason) end
			end
		end
		if #reasons > 0 then message ..= " (" .. string.sub(table.concat(reasons, ", "), 1, 200) .. ")" end
		if type(value.message) == "string" then message ..= ": " .. string.sub(value.message, 1, 600) end
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
	-- Carta reads list filters (fundIds, partnerIds) as comma-separated values.
	for _, field in endpoint.query or NONE do
		if args[field] ~= nil then table.insert(query, field .. "=" .. table.concat(queryParts(args[field], field), ",")) end
		args[field] = nil
	end
	if #query > 0 then path ..= "?" .. table.concat(query, "&") end
	local headers: HttpHeaders = {Accept = {"application/json"}}
	local extra: Options = {}
	for _, field in endpoint.extra or NONE do extra[field], args[field] = args[field], nil end
	local body: (string | File)? = nil
	if hasBody(endpoint) then
		headers["Content-Type"] = {"application/json"}
		body = json.encode(args)
		args = {}
	end
	local unknown = next(args)
	assert(unknown == nil, name .. " has no option " .. tostring(unknown))
	-- uploadOpenCapTable streams the session file at path as the raw body.
	if endpoint.upload then
		assert(type(extra.path) == "string" and extra.path ~= "", "path must be a session file path")
		assert(await(fs.stat(extra.path)).isFile, "path must be a session file")
		headers["Content-Type"] = {endpoint.upload}
		body = fs.open(extra.path, "r")
	end
	local response = await(http.request({method = endpoint.method, url = API .. path, headers = headers, body = body}))
	if response.statusCode < 200 or response.statusCode >= 300 then failStatus(name, response) end
	-- Accepted settlements may answer 202 without a body.
	return object(name, endpoint, response) or {success = true}
end

return operations(endpoints, request, {
	"Carta API Platform v1alpha1" .. (if auth.method == "playground" then " on the playground (shared test data that resets daily)" else "") .. ". Every function takes one named options object with Carta's camelCase names; ? marks optional fields and ...body the JSON body fields. Results are Carta's JSON unchanged, such as {issuers, nextPageToken}; a write answered without a body returns {success=true}. Connector calls return completed values: use them directly, without await.",
	"Start from listIssuers() for companies, listFirms() then listFunds({firmId}) for investment firms (fundId '-' selects every fund for cash balances, metrics and investment securities, and investmentId '-' every investment for those securities), or listPortfolios() for shareholdings. Only the companies, firms and portfolios shared at sign-in are visible, within the user's Carta role.",
	"IDs are strings. Lists return one page: pageSize defaults to 25, at most 50 unless noted (larger values are reduced); while nextPageToken is nonempty, pass it as pageToken with the same other options. Query dates are YYYY-MM-DD and date-times ISO 8601 UTC. In bodies Carta wraps scalars: a date or date-time is {value='2026-11-01'}, a decimal {value='2500.00'}, money {currencyCode={value='USD'}, amount={value='2500.00'}}. Array filters (fundIds, partnerIds) are sent comma-separated.",
	"Examples: local issuer = carta.listIssuers({pageSize=50}).issuers[1]; carta.getIssuerCapitalizationTable({issuerId=issuer.id, asOfDate='2026-10-19'}); carta.listStakeholders({issuerId=issuer.id, pageSize=100}); carta.listTransactions({issuerId=issuer.id, type='option'}); carta.listFundPerformanceMetrics({firmId=firm.id, fundId='-', reportType='BY_FUND'}).",
	"Read-only connections omit writes, getCapitalCall, getManagementFee and getSecondaryTransaction, which need write scopes, and getDraftIssuer, whose registration link is a credential. Fund accounting writes are idempotent on externalReferenceId and sourceSystem: repeating the same request returns the original with replayed=true, and a different payload under the same reference fails with 409. Other writes are not: after a timeout or 5xx, check whether the write took effect (read or list the resource, or look in Carta) before repeating it. Carta allows 10 requests per second and 300 per minute (half on the playground).",
	"Errors report the HTTP status, Carta's reasons (INSUFFICIENT_SCOPE, ACCESS_TO_RESOURCE_RESTRICTED for a resource not shared at sign-in, MISSING_INTERNAL_PERMISSION for the user's Carta role) and message.",
})
