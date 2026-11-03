-- Pennylane Company API v2. Arguments and results keep Pennylane's native snake_case field names.
type Options = {[string]: any}
type Endpoint = {
	method: string, path: string, query: {string}?, required: {string}?, body: (boolean | string)?, parts: {string}?,
	write: boolean?, scope: string?, about: string?, doc: string?,
}

local API = "https://app.pennylane.com/api/external/v2"
local DOCS = "https://pennylane.readme.io/reference/"

local PAGE = {"cursor", "limit"}
local SORTED = {"cursor", "limit", "sort"}
local LIST = {"cursor", "limit", "filter", "sort"}
local CHANGES = {"cursor", "limit", "start_date"}
local MANY = "customer_invoices|quotes|commercial_documents"
local WEBHOOKS = "companies:webhook_subscriptions:all"
local E_INVOICE = {"invoice_options", "override_invoice_lines"}

local function join(first: {string}, second: {string}): {string}
	local joined = table.clone(first)
	table.move(second, 1, #second, #joined + 1, joined)
	return joined
end

-- Every operation of Pennylane's Company API v2 OpenAPI (pennylane.readme.io/openapi/accounting.json),
-- checked on 2026-11-03, except the deprecated postLedgerAttachments, whose ledger scope no longer
-- works. Names are Pennylane's operationIds, which also name the reference pages. Path {fields} and
-- listed query fields come from the options; body = false sends no body, "multipart" uploads the
-- session file named by file, and another string names the one option sent as the JSON body.
-- The export jobs only read, so read-only connections can start them.
local endpoints: {[string]: Endpoint} = {
	getMe = {method = "GET", path = "/me", about = "The token's user (null for some tokens), company {id, name, reg_no, accounting_logic} and scopes. Needs no scope."},
	getCompanyFeatures = {method = "GET", path = "/company/features", about = "Plan features such as installments and custom_fields."},
	getFiscalYears = {method = "GET", path = "/fiscal_years", query = SORTED, scope = "fiscal_years", doc = "company-fiscal-years", about = "Sort: id, start."},
	getTrialBalance = {method = "GET", path = "/trial_balance", query = {"period_start", "period_end", "is_auxiliary", "cursor", "limit"}, required = {"period_start", "period_end"}, scope = "trial_balance",
		about = "Balances per ledger account; is_auxiliary=true details customer and supplier accounts."},
	getNumberings = {method = "GET", path = "/numberings", query = SORTED, scope = MANY, about = "Numbering sequences that finalizing documents needs."},
	getBillingEmailTemplates = {method = "GET", path = "/billing_email_templates", query = LIST, scope = MANY, about = "Filter: id, kind, locale."},
	getCustomerInvoiceTemplates = {method = "GET", path = "/customer_invoice_templates", query = SORTED, scope = "customer_invoice_templates"},
	getPaRegistrations = {method = "GET", path = "/pa_registrations", query = {"filter", "sort"}, scope = "pa_registrations",
		about = "The company's e-invoicing directory registrations, all at once. Filter: id, siret, status (activated is live)."},

	getCustomerInvoices = {method = "GET", path = "/customer_invoices", query = join(LIST, {"include"}), scope = "customer_invoices",
		about = "Invoices and credit notes. Filter: id, date, customer_id, billing_subscription_id, quote_id, invoice_number, draft, credit_note, external_reference, flow_id, category_id (in). Sort: id, date. include='invoice_lines' (experimental)."},
	getCustomerInvoice = {method = "GET", path = "/customer_invoices/{id}", scope = "customer_invoices"},
	postCustomerInvoices = {method = "POST", path = "/customer_invoices", required = {"date", "deadline", "customer_id", "invoice_lines"}, scope = "customer_invoices",
		about = "invoice_lines={{label, quantity, raw_currency_unit_price='100.00', unit, vat_rate='FR_200'} or {product_id, quantity}}. draft=true keeps a draft; otherwise the invoice is finalized and numbered."},
	createCustomerInvoiceFromQuote = {method = "POST", path = "/customer_invoices/create_from_quote", required = {"quote_id", "draft"}, scope = "customer_invoices"},
	importCustomerInvoices = {method = "POST", path = "/customer_invoices/import", required = {"file_attachment_id", "date", "deadline", "customer_id", "currency_amount_before_tax", "currency_amount", "currency_tax", "invoice_lines"}, scope = "customer_invoices",
		about = "Records an invoice issued elsewhere from an uploaded PDF; amounts must add up."},
	createCustomerInvoiceEInvoiceImport = {method = "POST", path = "/customer_invoices/e_invoices/imports", body = "multipart", parts = join({"send_to_pa"}, E_INVOICE), scope = "customer_invoices",
		about = "Imports a Factur-X PDF, UBL or CII file."},
	updateCustomerInvoice = {method = "PUT", path = "/customer_invoices/{id}", scope = "customer_invoices"},
	updateImportedCustomerInvoice = {method = "PUT", path = "/customer_invoices/{id}/update_imported", scope = "customer_invoices"},
	deleteCustomerInvoices = {method = "DELETE", path = "/customer_invoices/{id}", body = false, scope = "customer_invoices", about = "Deletes a draft invoice."},
	finalizeCustomerInvoice = {method = "PUT", path = "/customer_invoices/{id}/finalize", body = false, scope = "customer_invoices", about = "Numbers a draft; it can then no longer be deleted."},
	markAsPaidCustomerInvoice = {method = "PUT", path = "/customer_invoices/{id}/mark_as_paid", body = false, scope = "customer_invoices"},
	sendByEmailCustomerInvoice = {method = "POST", path = "/customer_invoices/{id}/send_by_email", scope = "customer_invoices",
		about = "Body {recipients?, email_template_id?}. Emails the customer; HTTP 409 while the PDF is still being generated."},
	sendToPaCustomerInvoice = {method = "POST", path = "/customer_invoices/{id}/send_to_pa", body = false, scope = "customer_invoices", about = "Sends the e-invoice to the customer through the e-invoicing platform."},
	linkCreditNote = {method = "POST", path = "/customer_invoices/{id}/link_credit_note", required = {"credit_note_id"}, scope = "customer_invoices"},
	getCustomerInvoiceInvoiceLines = {method = "GET", path = "/customer_invoices/{customer_invoice_id}/invoice_lines", query = SORTED, scope = "customer_invoices", about = "Sort: id, rank."},
	getCustomerInvoiceInvoiceLineSections = {method = "GET", path = "/customer_invoices/{customer_invoice_id}/invoice_line_sections", query = SORTED, scope = "customer_invoices"},
	getCustomerInvoicePayments = {method = "GET", path = "/customer_invoices/{customer_invoice_id}/payments", query = SORTED, scope = "customer_invoices"},
	getCustomerInvoiceCustomHeaderFields = {method = "GET", path = "/customer_invoices/{customer_invoice_id}/custom_header_fields", query = SORTED, scope = "customer_invoices"},
	getCustomerInvoiceMatchedTransactions = {method = "GET", path = "/customer_invoices/{customer_invoice_id}/matched_transactions", query = SORTED, scope = "customer_invoices"},
	postCustomerInvoiceMatchedTransactions = {method = "POST", path = "/customer_invoices/{customer_invoice_id}/matched_transactions", required = {"transaction_id"}, scope = "customer_invoices"},
	deleteCustomerInvoiceMatchedTransactions = {method = "DELETE", path = "/customer_invoices/{customer_invoice_id}/matched_transactions/{id}", body = false, scope = "customer_invoices", about = "id is the transaction's."},
	getCustomerInvoiceAppendices = {method = "GET", path = "/customer_invoices/{customer_invoice_id}/appendices", query = PAGE, scope = "customer_invoices"},
	postCustomerInvoiceAppendices = {method = "POST", path = "/customer_invoices/{customer_invoice_id}/appendices", body = "multipart", scope = "customer_invoices"},
	getCustomerInvoiceCategories = {method = "GET", path = "/customer_invoices/{customer_invoice_id}/categories", query = PAGE, scope = "customer_invoices"},
	putCustomerInvoiceCategories = {method = "PUT", path = "/customer_invoices/{customer_invoice_id}/categories", body = "categories", scope = "customer_invoices"},

	listQuotes = {method = "GET", path = "/quotes", query = LIST, scope = "quotes", about = "Filter: id, customer_id, status (pending, accepted, denied, expired, invoiced)."},
	getQuote = {method = "GET", path = "/quotes/{id}", scope = "quotes"},
	postQuotes = {method = "POST", path = "/quotes", required = {"date", "deadline", "customer_id", "invoice_lines"}, scope = "quotes"},
	updateQuote = {method = "PUT", path = "/quotes/{id}", scope = "quotes"},
	updateStatusQuote = {method = "PUT", path = "/quotes/{id}/update_status", required = {"status"}, scope = "quotes"},
	sendByEmailQuote = {method = "POST", path = "/quotes/{id}/send_by_email", scope = "quotes", about = "Body {recipients?, email_template_id?}. Emails the customer."},
	getQuoteInvoiceLines = {method = "GET", path = "/quotes/{quote_id}/invoice_lines", query = SORTED, scope = "quotes"},
	getQuoteInvoiceLineSections = {method = "GET", path = "/quotes/{quote_id}/invoice_line_sections", query = SORTED, scope = "quotes"},
	getQuoteAppendices = {method = "GET", path = "/quotes/{quote_id}/appendices", query = PAGE, scope = "quotes"},
	postQuoteAppendices = {method = "POST", path = "/quotes/{quote_id}/appendices", body = "multipart", scope = "quotes"},

	listCommercialDocuments = {method = "GET", path = "/commercial_documents", query = LIST, scope = "commercial_documents",
		about = "Pro formas, shipping and purchasing orders. Filter: id, customer_id, document_type."},
	getCommercialDocument = {method = "GET", path = "/commercial_documents/{id}", scope = "commercial_documents"},
	postCommercialDocuments = {method = "POST", path = "/commercial_documents", required = {"document_type", "date", "deadline", "customer_id", "invoice_lines"}, scope = "commercial_documents"},
	updateCommercialDocument = {method = "PUT", path = "/commercial_documents/{id}", scope = "commercial_documents"},
	sendByEmailCommercialDocument = {method = "POST", path = "/commercial_documents/{id}/send_by_email", scope = "commercial_documents", about = "Emails the customer."},
	getCommercialDocumentInvoiceLines = {method = "GET", path = "/commercial_documents/{commercial_document_id}/invoice_lines", query = SORTED, scope = "commercial_documents"},
	getCommercialDocumentInvoiceLineSections = {method = "GET", path = "/commercial_documents/{commercial_document_id}/invoice_line_sections", query = SORTED, scope = "commercial_documents"},
	getCommercialDocumentAppendices = {method = "GET", path = "/commercial_documents/{commercial_document_id}/appendices", query = PAGE, scope = "commercial_documents"},
	postCommercialDocumentAppendices = {method = "POST", path = "/commercial_documents/{commercial_document_id}/appendices", body = "multipart", scope = "commercial_documents"},

	getBillingSubscriptions = {method = "GET", path = "/billing_subscriptions", query = LIST, scope = "billing_subscriptions", about = "Recurring invoices. Filter: id, start, customer_id, status."},
	getBillingSubscription = {method = "GET", path = "/billing_subscriptions/{id}", scope = "billing_subscriptions"},
	postBillingSubscriptions = {method = "POST", path = "/billing_subscriptions", required = {"start", "mode", "payment_conditions", "payment_method", "recurring_rule", "customer_id", "customer_invoice_data"}, scope = "billing_subscriptions"},
	putBillingSubscriptions = {method = "PUT", path = "/billing_subscriptions/{id}", scope = "billing_subscriptions"},
	getBillingSubscriptionInvoiceLines = {method = "GET", path = "/billing_subscriptions/{billing_subscription_id}/invoice_lines", query = SORTED, scope = "billing_subscriptions"},
	getBillingSubscriptionInvoiceLineSections = {method = "GET", path = "/billing_subscriptions/{billing_subscription_id}/invoice_line_sections", query = SORTED, scope = "billing_subscriptions"},

	getCustomers = {method = "GET", path = "/customers", query = LIST, scope = "customers",
		about = "Companies and individuals. Filter: id, customer_type, ledger_account_id, name (start_with, eq), external_reference, reg_no, emails (in)."},
	getCustomer = {method = "GET", path = "/customers/{id}", scope = "customers"},
	postCustomer = {method = "POST", path = "/customers", scope = "customers", about = "Body {customer_type='company', name, billing_address={address, postal_code, city, country_alpha2}, ...} or {customer_type='individual', first_name, last_name, billing_address, ...}."},
	putCustomer = {method = "PUT", path = "/customers/{id}", scope = "customers"},
	getCompanyCustomer = {method = "GET", path = "/company_customers/{id}", scope = "customers"},
	postCompanyCustomer = {method = "POST", path = "/company_customers", required = {"name", "billing_address"}, scope = "customers"},
	putCompanyCustomer = {method = "PUT", path = "/company_customers/{id}", scope = "customers"},
	getIndividualCustomer = {method = "GET", path = "/individual_customers/{id}", scope = "customers"},
	postIndividualCustomer = {method = "POST", path = "/individual_customers", required = {"first_name", "last_name", "billing_address"}, scope = "customers"},
	putIndividualCustomer = {method = "PUT", path = "/individual_customers/{id}", scope = "customers"},
	getCustomerContacts = {method = "GET", path = "/customers/{customer_id}/contacts", query = SORTED, scope = "customers"},
	getCustomerContact = {method = "GET", path = "/customers/{customer_id}/contacts/{id}", scope = "customers"},
	postCustomerContact = {method = "POST", path = "/customers/{customer_id}/contacts", required = {"first_name", "last_name", "email"}, scope = "customers"},
	putCustomerContact = {method = "PUT", path = "/customers/{customer_id}/contacts/{id}", scope = "customers"},
	deleteCustomerContact = {method = "DELETE", path = "/customers/{customer_id}/contacts/{id}", body = false, scope = "customers"},
	getCustomerElectronicBillingAddresses = {method = "GET", path = "/customers/{customer_id}/electronic_billing_addresses", scope = "customers"},
	getCustomerCategories = {method = "GET", path = "/customers/{customer_id}/categories", query = PAGE, scope = "customers"},
	putCustomerCategories = {method = "PUT", path = "/customers/{customer_id}/categories", body = "categories", scope = "customers"},

	getSuppliers = {method = "GET", path = "/suppliers", query = LIST, scope = "suppliers", about = "Filter: id, ledger_account_id, name (start_with), external_reference, emails (in)."},
	getSupplier = {method = "GET", path = "/suppliers/{id}", scope = "suppliers"},
	postSupplier = {method = "POST", path = "/suppliers", required = {"name"}, scope = "suppliers"},
	putSupplier = {method = "PUT", path = "/suppliers/{id}", scope = "suppliers"},
	getSupplierCategories = {method = "GET", path = "/suppliers/{supplier_id}/categories", query = PAGE, scope = "suppliers"},
	putSupplierCategories = {method = "PUT", path = "/suppliers/{supplier_id}/categories", body = "categories", scope = "suppliers"},

	getSupplierInvoices = {method = "GET", path = "/supplier_invoices", query = LIST, scope = "supplier_invoices",
		about = "Filter: id, supplier_id, invoice_number, date, category_id (in), external_reference, payment_status, flow_id, electronic_billing_address. Sort: id, date."},
	getSupplierInvoice = {method = "GET", path = "/supplier_invoices/{id}", scope = "supplier_invoices"},
	importSupplierInvoice = {method = "POST", path = "/supplier_invoices/import", required = {"file_attachment_id", "supplier_id", "date", "deadline", "currency_amount_before_tax", "currency_amount", "currency_tax", "invoice_lines"}, scope = "supplier_invoices",
		about = "Creates a supplier invoice from an uploaded PDF; amounts must add up. HTTP 409 if the file was already imported."},
	createSupplierInvoiceEInvoiceImport = {method = "POST", path = "/supplier_invoices/e_invoices/imports", body = "multipart", parts = E_INVOICE, scope = "supplier_invoices",
		about = "Imports a Factur-X PDF, UBL or CII file."},
	putSupplierInvoice = {method = "PUT", path = "/supplier_invoices/{id}", scope = "supplier_invoices"},
	validateAccountingSupplierInvoice = {method = "PUT", path = "/supplier_invoices/{id}/validate_accounting", body = false, scope = "supplier_invoices"},
	updateSupplierInvoicePaymentStatus = {method = "PUT", path = "/supplier_invoices/{supplier_invoice_id}/payment_status", required = {"payment_status"}, scope = "supplier_invoices"},
	putSupplierInvoiceEInvoiceStatus = {method = "PUT", path = "/supplier_invoices/{supplier_invoice_id}/e_invoice_status", scope = "supplier_invoices", about = "Body {status='disputed' or 'refused', reason} or {status='approved'} for a received e-invoice."},
	getSupplierInvoiceLines = {method = "GET", path = "/supplier_invoices/{supplier_invoice_id}/invoice_lines", query = SORTED, scope = "supplier_invoices"},
	getSupplierInvoicePayments = {method = "GET", path = "/supplier_invoices/{supplier_invoice_id}/payments", query = SORTED, scope = "supplier_invoices"},
	getSupplierInvoiceMatchedTransactions = {method = "GET", path = "/supplier_invoices/{supplier_invoice_id}/matched_transactions", query = SORTED, scope = "supplier_invoices"},
	postSupplierInvoiceMatchedTransactions = {method = "POST", path = "/supplier_invoices/{supplier_invoice_id}/matched_transactions", required = {"transaction_id"}, scope = "supplier_invoices"},
	deleteSupplierInvoiceMatchedTransactions = {method = "DELETE", path = "/supplier_invoices/{supplier_invoice_id}/matched_transactions/{id}", body = false, scope = "supplier_invoices", about = "id is the transaction's."},
	postSupplierInvoiceLinkedPurchaseRequests = {method = "POST", path = "/supplier_invoices/{supplier_invoice_id}/linked_purchase_requests", required = {"purchase_request_id"}, scope = "supplier_invoices"},
	getSupplierInvoiceCategories = {method = "GET", path = "/supplier_invoices/{supplier_invoice_id}/categories", query = PAGE, scope = "supplier_invoices"},
	putSupplierInvoiceCategories = {method = "PUT", path = "/supplier_invoices/{supplier_invoice_id}/categories", body = "categories", scope = "supplier_invoices"},

	getPurchaseRequests = {method = "GET", path = "/purchase_requests", query = LIST, scope = "purchase_requests", about = "Filter: id, reviewed_by_id, user_id, supplier_id."},
	getPurchaseRequest = {method = "GET", path = "/purchase_requests/{id}", scope = "purchase_requests"},
	createPurchaseRequestImport = {method = "POST", path = "/purchase_requests/imports", required = {"file_attachment_id", "reason", "supplier_id", "purchase_order_number", "currency_amount_before_tax", "currency_amount", "currency_tax", "delivery_address", "purchase_request_lines"}, scope = "purchase_requests",
		about = "Creates a purchase order from an uploaded file."},

	getProducts = {method = "GET", path = "/products", query = LIST, scope = "products", about = "Filter: id, label, reference, external_reference."},
	getProduct = {method = "GET", path = "/products/{id}", scope = "products"},
	postProducts = {method = "POST", path = "/products", required = {"label", "price_before_tax", "vat_rate"}, scope = "products", doc = "postproducts-1"},
	putProduct = {method = "PUT", path = "/products/{id}", scope = "products"},

	getBankAccounts = {method = "GET", path = "/bank_accounts", query = SORTED, scope = "bank_accounts"},
	getBankAccount = {method = "GET", path = "/bank_accounts/{id}", scope = "bank_accounts"},
	postBankAccount = {method = "POST", path = "/bank_accounts", required = {"name"}, scope = "bank_accounts"},
	getBankEstablishments = {method = "GET", path = "/bank_establishments", query = LIST, scope = "bank_establishments", about = "Filter: id."},
	getTransactions = {method = "GET", path = "/transactions", query = LIST, scope = "transactions", about = "Bank transactions. Filter: id, bank_account_id, journal_id, date."},
	getTransaction = {method = "GET", path = "/transactions/{id}", scope = "transactions"},
	createTransaction = {method = "POST", path = "/transactions", required = {"bank_account_id", "label", "date", "amount"}, scope = "transactions"},
	updateTransaction = {method = "PUT", path = "/transactions/{id}", scope = "transactions"},
	getTransactionMatchedInvoices = {method = "GET", path = "/transactions/{transaction_id}/matched_invoices", query = PAGE, scope = "transactions"},
	getTransactionCategories = {method = "GET", path = "/transactions/{transaction_id}/categories", query = PAGE, scope = "transactions"},
	putTransactionCategories = {method = "PUT", path = "/transactions/{transaction_id}/categories", body = "categories", scope = "transactions"},

	getCategoryGroups = {method = "GET", path = "/category_groups", query = PAGE, scope = "categories", about = "Analytical axes."},
	getCategoryGroup = {method = "GET", path = "/category_groups/{id}", scope = "categories"},
	postCategoryGroups = {method = "POST", path = "/category_groups", required = {"label"}, scope = "categories"},
	putCategoryGroup = {method = "PUT", path = "/category_groups/{id}", required = {"label"}, scope = "categories"},
	getCategoryGroupCategories = {method = "GET", path = "/category_groups/{category_group_id}/categories", query = PAGE, scope = "categories"},
	getCategories = {method = "GET", path = "/categories", query = LIST, scope = "categories", about = "Analytical categories. Filter: id, label, category_group_id, analytical_code."},
	getCategory = {method = "GET", path = "/categories/{id}", scope = "categories"},
	postCategories = {method = "POST", path = "/categories", required = {"label", "category_group_id"}, scope = "categories"},
	updateCategory = {method = "PUT", path = "/categories/{id}", scope = "categories"},

	getJournals = {method = "GET", path = "/journals", query = LIST, scope = "journals", about = "Filter: type."},
	getJournal = {method = "GET", path = "/journals/{id}", scope = "journals"},
	postJournals = {method = "POST", path = "/journals", required = {"code", "label"}, scope = "journals"},
	getLedgerAccounts = {method = "GET", path = "/ledger_accounts", query = LIST, scope = "ledger_accounts", about = "Chart of accounts; limit up to 1000. Filter: id, number (start_with, eq, in), enabled."},
	getLedgerAccount = {method = "GET", path = "/ledger_accounts/{id}", scope = "ledger_accounts"},
	postLedgerAccounts = {method = "POST", path = "/ledger_accounts", required = {"number", "label"}, scope = "ledger_accounts"},
	updateLedgerAccount = {method = "PUT", path = "/ledger_accounts/{id}", scope = "ledger_accounts"},
	getLedgerEntries = {method = "GET", path = "/ledger_entries", query = LIST, scope = "ledger_entries", about = "Journal entries, drafts included. Filter: id, date, journal_id. Sort: id, date."},
	getLedgerEntry = {method = "GET", path = "/ledger_entries/{id}", scope = "ledger_entries"},
	postLedgerEntries = {method = "POST", path = "/ledger_entries", required = {"date", "label", "journal_id", "ledger_entry_lines"}, scope = "ledger_entries",
		about = "ledger_entry_lines={{ledger_account_id, debit='100.00', credit='0.00', label?}, ...} must balance; file_attachment_id? attaches an upload."},
	putLedgerEntries = {method = "PUT", path = "/ledger_entries/{id}", scope = "ledger_entries"},
	getLedgerEntriesLedgerEntryLines = {method = "GET", path = "/ledger_entries/{ledger_entry_id}/ledger_entry_lines", query = LIST, scope = "ledger_entries", about = "Filter: ledger_account_id."},
	getLedgerEntriesDmsFiles = {method = "GET", path = "/ledger_entries/{ledger_entry_id}/dms_files", query = PAGE, scope = "ledger_entries", about = "Documents attached to the entry."},
	getLedgerEntryLines = {method = "GET", path = "/ledger_entry_lines", query = LIST, scope = "ledger_entries", about = "Filter: id, journal_id, ledger_account_id, ledger_entry_id, date. Sort: id, date."},
	getLedgerEntryLine = {method = "GET", path = "/ledger_entry_lines/{id}", scope = "ledger_entries"},
	getLedgerEntryLinesLetteredLedgerEntryLines = {method = "GET", path = "/ledger_entry_lines/{ledger_entry_line_id}/lettered_ledger_entry_lines", query = SORTED, scope = "ledger_entries"},
	postLedgerEntryLinesLetter = {method = "POST", path = "/ledger_entry_lines/lettering", required = {"unbalanced_lettering_strategy", "ledger_entry_lines"}, scope = "ledger_entries",
		about = "Reconciles (letters) lines: ledger_entry_lines={{id}, ...}, unbalanced_lettering_strategy 'none' or 'partial'."},
	deleteLedgerEntryLinesUnletter = {method = "DELETE", path = "/ledger_entry_lines/lettering", required = {"unbalanced_lettering_strategy", "ledger_entry_lines"}, scope = "ledger_entries"},
	getLedgerEntryLinesCategories = {method = "GET", path = "/ledger_entry_lines/{ledger_entry_line_id}/categories", query = SORTED, scope = "ledger_entries"},
	putLedgerEntryLinesCategories = {method = "PUT", path = "/ledger_entry_lines/{ledger_entry_line_id}/categories", body = "categories", scope = "ledger_entries"},

	exportFec = {method = "POST", path = "/exports/fecs", write = false, required = {"period_start", "period_end"}, scope = "exports:fec",
		about = "Starts a FEC (French audit file) export; poll getFecExport({id}) until status is ready and file_url is set."},
	getFecExport = {method = "GET", path = "/exports/fecs/{id}", scope = "exports:fec"},
	exportGeneralLedger = {method = "POST", path = "/exports/general_ledgers", write = false, required = {"period_start", "period_end"}, scope = "exports:gl", about = "Starts an xlsx general ledger export."},
	getGeneralLedgerExport = {method = "GET", path = "/exports/general_ledgers/{id}", scope = "exports:gl"},
	exportAnalyticalGeneralLedger = {method = "POST", path = "/exports/analytical_general_ledgers", write = false, required = {"period_start", "period_end"}, scope = "exports:agl",
		about = "Starts an xlsx analytical general ledger export."},
	getAnalyticalGeneralLedgerExport = {method = "GET", path = "/exports/analytical_general_ledgers/{id}", scope = "exports:agl"},

	getCustomerInvoicesChanges = {method = "GET", path = "/changelogs/customer_invoices", query = CHANGES, scope = "customer_invoices"},
	getQuoteChanges = {method = "GET", path = "/changelogs/quotes", query = CHANGES, scope = "quotes"},
	getSupplierInvoicesChanges = {method = "GET", path = "/changelogs/supplier_invoices", query = CHANGES, scope = "supplier_invoices"},
	getCustomerChanges = {method = "GET", path = "/changelogs/customers", query = CHANGES, scope = "customers"},
	getSupplierChanges = {method = "GET", path = "/changelogs/suppliers", query = CHANGES, scope = "suppliers"},
	getProductChanges = {method = "GET", path = "/changelogs/products", query = CHANGES, scope = "products"},
	getTransactionChanges = {method = "GET", path = "/changelogs/transactions", query = CHANGES, scope = "transactions"},
	getLedgerEntriesChanges = {method = "GET", path = "/changelogs/ledger_entries", query = CHANGES, scope = "ledger_entries"},
	getLedgerEntryLineChanges = {method = "GET", path = "/changelogs/ledger_entry_lines", query = CHANGES, scope = "ledger_entries"},
	getLedgerEntriesCategoryChanges = {method = "GET", path = "/changelogs/ledger_entries_categories", query = CHANGES, scope = "ledger_entries"},
	getLedgerEntryLinesCategoryChanges = {method = "GET", path = "/changelogs/ledger_entry_lines_categories", query = CHANGES, scope = "ledger_entries"},

	getSepaMandates = {method = "GET", path = "/sepa_mandates", query = LIST, scope = "customer_mandates", about = "Filter: id, customer_id."},
	getSepaMandate = {method = "GET", path = "/sepa_mandates/{id}", scope = "customer_mandates"},
	postSepaMandates = {method = "POST", path = "/sepa_mandates", required = {"bic", "iban", "signed_at", "identifier", "customer_id"}, scope = "customer_mandates"},
	putSepaMandate = {method = "PUT", path = "/sepa_mandates/{id}", scope = "customer_mandates"},
	deleteSepaMandate = {method = "DELETE", path = "/sepa_mandates/{id}", body = false, scope = "customer_mandates"},
	getGocardlessMandates = {method = "GET", path = "/gocardless_mandates", query = LIST, scope = "customer_mandates", about = "Filter: id, customer_id, external_reference."},
	getGocardlessMandate = {method = "GET", path = "/gocardless_mandates/{id}", scope = "customer_mandates"},
	postGocardlessMandateMailRequests = {method = "POST", path = "/gocardless_mandates/mail_requests", required = {"customer_id", "email"}, scope = "customer_mandates", about = "Emails the customer a mandate request."},
	postGocardlessMandateAssociations = {method = "POST", path = "/gocardless_mandates/{gocardless_mandate_id}/associations", required = {"customer_id"}, scope = "customer_mandates"},
	postGocardlessMandateCancellations = {method = "POST", path = "/gocardless_mandates/{gocardless_mandate_id}/cancellations", body = false, scope = "customer_mandates"},
	getProAccountMandates = {method = "GET", path = "/pro_account/mandates", query = LIST, scope = "customer_mandates", about = "Filter: status, customer_id."},
	postProAccountMandateMailRequests = {method = "POST", path = "/pro_account/mandate_requests", required = {"customer_id"}, scope = "customer_mandates", about = "Emails the customer a mandate request."},
	getProAccountMandateMigrations = {method = "GET", path = "/pro_account/mandate_migrations", query = LIST, scope = "customer_mandates", about = "Filter: customer_id, status."},
	postProAccountMandateMigrations = {method = "POST", path = "/pro_account/mandate_migrations", required = {"mandate_type", "mandate_id"}, scope = "customer_mandates"},

	postFileAttachments = {method = "POST", path = "/file_attachments", body = "multipart", scope = "file_attachments",
		about = "Returns {id, url, filename}; pass id as file_attachment_id to the import functions or postLedgerEntries."},

	getWebhookSubscriptions = {method = "GET", path = "/webhook_subscriptions", query = PAGE, scope = WEBHOOKS, about = "The token's webhooks, without their secrets."},
	getWebhookSubscription = {method = "GET", path = "/webhook_subscriptions/{id}", scope = WEBHOOKS},
	postWebhookSubscriptions = {method = "POST", path = "/webhook_subscriptions", required = {"callback_url", "events"}, scope = WEBHOOKS,
		about = "Pennylane then posts the events to callback_url, an HTTPS receiver you control. The result's secret signs deliveries and is shown only once."},
	putWebhookSubscription = {method = "PUT", path = "/webhook_subscriptions/{id}", scope = WEBHOOKS, about = "Body {callback_url?, events?, enabled?}; enabled=true restarts a disabled webhook."},
	deleteWebhookSubscription = {method = "DELETE", path = "/webhook_subscriptions/{id}", body = false, scope = WEBHOOKS},
}

local NULL = json.decode("null")
local NONE: {string} = table.freeze({})
local MAX_ID = 9007199254740991
local CONTENT_TYPES = table.freeze({
	pdf = "application/pdf", png = "image/png", jpg = "image/jpeg", jpeg = "image/jpeg", tif = "image/tiff",
	tiff = "image/tiff", bmp = "image/bmp", gif = "image/gif", xml = "application/xml",
})

local function writes(endpoint: Endpoint): boolean
	if endpoint.write ~= nil then return endpoint.write end
	return endpoint.method ~= "GET"
end

local function hasBody(endpoint: Endpoint): boolean
	return endpoint.method ~= "GET" and endpoint.body ~= false
end

-- Pennylane IDs are integers; digits-only strings are accepted too.
local function identifier(value: any, field: string): string
	if type(value) == "number" then
		assert(value >= 0 and value % 1 == 0 and value <= MAX_ID, field .. " must be a nonnegative integer ID")
		return string.format("%d", value)
	end
	assert(type(value) == "string" and #value <= 19 and string.match(value, "^%d+$"), field .. " must be a nonnegative integer ID")
	return value
end

local function isArray(value: any): boolean
	if type(value) ~= "table" then return false end
	local count = 0
	for key in value do
		if type(key) ~= "number" then return false end
		count += 1
	end
	return count == #value
end

local function queryValue(value: any, field: string): string
	if field == "filter" then
		if type(value) == "string" then
			assert(string.match(value, "^%s*%["), "filter must be an array of {field, operator, value} or its JSON text")
			return url.encode(value)
		end
		assert(isArray(value) and #value > 0, "filter must be a nonempty array of {field, operator, value}")
		for _, condition in value do
			assert(type(condition) == "table" and type(condition.field) == "string" and type(condition.operator) == "string" and condition.value ~= nil,
				"each filter condition needs field, operator and value")
		end
		return url.encode(json.encode(value))
	end
	if field == "limit" then
		assert(type(value) == "number" and value % 1 == 0 and value >= 1 and value <= 1000, "limit must be an integer from 1 to 1000")
	end
	local kind = type(value)
	assert(kind == "string" or kind == "number" or kind == "boolean", field .. " must be a string, number or boolean")
	return url.encode(value)
end

-- At most limit bytes of text, without a trailing partial UTF-8 character.
local function clip(text: string, limit: number): string
	if #text <= limit then return text end
	return (string.gsub(string.sub(text, 1, limit), "[\xC0-\xFF][\x80-\xBF]*$", ""))
end

local function fail(name: string, response: HttpResponse, message: string): never
	return houston.fail({operation = name, layer = "upstream", upstream_status = response.statusCode,
		retryable = response.statusCode == 429 or response.statusCode >= 500, message = message})
end

-- Pennylane errors are {status, error}, or {message, code?, field?, payload?} for invalid
-- requests; rate limits answer in plain text.
local function failStatus(name: string, endpoint: Endpoint, response: HttpResponse): never
	local raw = await(response.body:readPrefix(16 * 1024))
	local message = "Pennylane HTTP " .. tostring(response.statusCode)
	local ok, value = pcall(json.decode, raw)
	if ok and type(value) == "table" then
		local text = if type(value.error) == "string" then value.error elseif type(value.message) == "string" then value.message else nil
		if text then message ..= ": " .. clip(text, 600) end
		if type(value.code) == "string" then message ..= " (" .. value.code .. ")" end
		if type(value.field) == "string" then message ..= " field " .. clip(value.field, 200) end
		if value.payload ~= nil then message ..= " " .. clip(json.encode(value.payload), 600) end
	elseif raw ~= "" and not string.match(raw, "^%s*<") then
		message ..= ": " .. clip(raw, 300)
	end
	if response.statusCode == 403 and endpoint.scope then
		local scopes: {string} = {}
		for scope in string.gmatch(endpoint.scope :: string, "[^|]+") do
			table.insert(scopes, if string.find(scope, ":", 1, true) then scope elseif writes(endpoint) then scope .. ":all" else scope .. ":readonly or " .. scope .. ":all")
		end
		message ..= ". The token needs the " .. table.concat(scopes, " or ") .. " scope"
	end
	local retry = response.headers["retry-after"]
	if retry and retry[1] then message ..= "; Retry-After: " .. retry[1] end
	return fail(name, response, message)
end

-- A session file and the endpoint's other form fields as one multipart body. Everything is
-- validated before the file opens, and the file is closed again if building the body fails.
local function multipart(name: string, endpoint: Endpoint, args: Options): (any, string)
	local source = args.file
	assert(type(source) == "string" and source ~= "", "file must be a session file path")
	local filename = if args.filename ~= nil then args.filename else string.match(source, "[^/]+$")
	assert(type(filename) == "string" and filename ~= "" and #filename <= 255 and not string.find(filename, '[%c"/\\]'), "filename must be a plain file name")
	local extension = string.lower(string.match(filename, "%.(%w+)$") or "")
	local contentType = args.content_type or CONTENT_TYPES[extension] or "application/octet-stream"
	assert(type(contentType) == "string" and string.match(contentType, "^[%w.+-]+/[%w.+-]+$"), "content_type must be a media type such as application/pdf")
	args.file, args.filename, args.content_type = nil, nil, nil
	local parts: {any} = {}
	for _, field in endpoint.parts or NONE do
		local value = args[field]
		args[field] = nil
		if type(value) == "table" then
			table.insert(parts, {name = field, body = json.encode(value), contentType = "application/json"})
		elseif type(value) == "boolean" then
			table.insert(parts, {name = field, body = tostring(value)})
		else
			assert(value == nil, field .. " must be a boolean or JSON object")
		end
	end
	local unknown = next(args)
	assert(unknown == nil, name .. " has no option " .. tostring(unknown))
	local file = fs.open(source, "r")
	local ok, body, bodyType = pcall(function()
		await(file)
		table.insert(parts, {name = "file", filename = filename, contentType = contentType, body = file})
		return http.multipart(parts)
	end)
	if not ok then
		pcall(function() await(file:close()) end)
		error(body)
	end
	return body, bodyType
end

local function request(name: string, endpoint: Endpoint, input: Options?): any
	assert(input == nil or type(input) == "table", "opts must be an object")
	local args: Options = if input then table.clone(input) else {}
	for key in args do assert(type(key) == "string", "opts must have named fields") end
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
		if args[field] ~= nil then table.insert(query, field .. "=" .. queryValue(args[field], field)) end
		args[field] = nil
	end
	if #query > 0 then path ..= "?" .. table.concat(query, "&") end
	local headers: HttpHeaders = {Accept = {"application/json"}}
	local body: any = nil
	if endpoint.body == "multipart" then
		local contentType
		body, contentType = multipart(name, endpoint, args)
		headers["Content-Type"] = {contentType}
	elseif type(endpoint.body) == "string" then
		local field = endpoint.body :: string
		assert(isArray(args[field]) and #args[field] > 0, field .. " must be a nonempty array")
		body = json.encode(args[field])
		args[field] = nil
	elseif hasBody(endpoint) then
		body = json.encode(args)
		args = {}
	end
	local unknown = next(args)
	assert(unknown == nil, name .. " has no option " .. tostring(unknown))
	if type(body) == "string" then headers["Content-Type"] = {"application/json"} end
	local response = await(http.request({method = endpoint.method, url = API .. path, headers = headers, body = body}))
	if response.statusCode < 200 or response.statusCode >= 300 then failStatus(name, endpoint, response) end
	local raw = await(response.body:readAll())
	-- Actions such as sendByEmailCustomerInvoice answer 204 without a body.
	if string.match(raw, "^%s*$") then
		if endpoint.method ~= "GET" then return {} end
		fail(name, response, "Pennylane returned an empty response")
	end
	local ok, value = pcall(json.decode, raw)
	if ok and (type(value) == "table" or endpoint.method ~= "GET") then return value end
	if endpoint.method ~= "GET" then
		fail(name, response, "Pennylane accepted the request with HTTP " .. tostring(response.statusCode) .. " but returned invalid JSON; the change may have been made, so read it back before repeating it")
	end
	return fail(name, response, "Pennylane returned invalid JSON")
end

local function signature(endpoint: Endpoint): string
	local fields: {string} = {}
	for field in string.gmatch(endpoint.path, "{([%w_]+)}") do table.insert(fields, field) end
	local paged = false
	for _, field in endpoint.query or NONE do
		if field == "cursor" or field == "limit" then
			paged = true
		else
			table.insert(fields, if table.find(endpoint.required or NONE, field) then field else field .. "?")
		end
	end
	if endpoint.body == "multipart" then
		table.insert(fields, "file")
		for _, field in endpoint.parts or NONE do table.insert(fields, field .. "?") end
		table.insert(fields, "filename?")
		table.insert(fields, "content_type?")
	elseif type(endpoint.body) == "string" then
		table.insert(fields, endpoint.body :: string)
	elseif hasBody(endpoint) then
		for _, field in endpoint.required or NONE do
			if not table.find(fields, field) then table.insert(fields, field) end
		end
		table.insert(fields, "...body")
	end
	if paged then table.insert(fields, "...page") end
	return "({" .. table.concat(fields, ", ") .. "})"
end

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
	local lines = {
		"Pennylane Company API v2 for the company that owns the API token. Each function takes one options object with Pennylane's snake_case names: {id} path fields are integer IDs, ? marks optional fields, ...body the other JSON body fields and ...page cursor? and limit?. Results are Pennylane's JSON unchanged; an action Pennylane answers without content returns {}. Connector calls return completed values: use them directly, without await. Functions without a method read with GET. Names are Pennylane's operationIds; each one's reference page is " .. DOCS .. "<name in lowercase> unless another page is noted.",
		"Paging: lists return {items, has_more, next_cursor}; pass cursor=next_cursor while has_more, re-sending the same filter and sort. limit is 1..100 (default 20), up to 1000 for getLedgerAccounts, getTrialBalance and the get...Changes functions. filter is an array of {field, operator, value} conditions combined with AND, using the fields each function lists; operators are eq, not_eq, lt, lteq, gt, gteq, in and not_in (with an array value) and start_with. sort is one field, '-' first for descending; most lists sort by id, newest first. get...Changes functions list {id, operation, processed_at} events of the last 4 weeks: pass start_date (RFC 3339) or cursor, not both.",
		"Formats: IDs are integers, amounts strings such as '120.00' (send them as strings), dates 'YYYY-MM-DD'. Linked records come as {id, url} and nested lists such as invoice_lines as {url}; read them with the matching function. public_file_url, file url and export file_url values are signed links valid 30 minutes that need no credentials: anyone holding one can download the file, and this connector does not fetch them.",
		"Examples: pennylane.getCustomerInvoices({filter={{field='date', operator='gteq', value='2026-01-01'}, {field='customer_id', operator='in', value={12, 34}}}, sort='-date', limit=50}); pennylane.getCustomerInvoiceInvoiceLines({customer_invoice_id=42}); pennylane.getTrialBalance({period_start='2026-01-01', period_end='2026-03-31'}); local job = pennylane.exportFec({period_start='2025-01-01', period_end='2025-12-31'}), then pennylane.getFecExport({id=job.id}) until file_url is set.",
		"Errors report the HTTP status with Pennylane's message, code and field. A 403 names the token scope the call needs; journal and ledger functions also answer 403 for an invalid token, which getMe tells apart. Pennylane allows 25 requests per 5 seconds per token; a 429 includes Retry-After.",
	}
	if config.access == "read-write" then
		table.insert(lines, "Files: postFileAttachments({file='invoice.pdf'}) uploads a session file (PDF, PNG, JPEG, TIFF, BMP or GIF up to 100 MB; filename? and content_type? override its name and type, which otherwise come from the path) and returns its id for file_attachment_id. Appendices and e-invoice imports take file the same way; invoice_options and override_invoice_lines are tables sent as JSON. put...Categories functions take categories={{id=7, weight='1'}} and replace the record's analytical categories.")
		table.insert(lines, "Writes change the company's accounting: sendByEmail... and mandate requests email customers, sendToPaCustomerInvoice transmits an e-invoice, finalized invoices can no longer be deleted, and webhooks send company data to their callback_url. Pennylane has no idempotency keys, and only Houston retries rate-limited requests, at most twice with a short Retry-After: after a timeout, 5xx or invalid write response, read or list the records before repeating a create.")
	else
		table.insert(lines, "This connection is read-only: it lists no writes. The export functions only start report files.")
	end
	for _, name in names do
		local endpoint = endpoints[name]
		local line = name .. signature(endpoint) .. (if endpoint.method == "GET" then "" else " " .. endpoint.method)
		if endpoint.about then line ..= ". " .. endpoint.about end
		if endpoint.doc then line ..= " (page " .. endpoint.doc .. ")" end
		table.insert(lines, line)
	end
	return table.concat(lines, "\n")
end

return exports
