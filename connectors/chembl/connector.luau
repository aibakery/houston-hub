-- ChEMBL data web services (https://www.ebi.ac.uk/chembl/api/data), public and read-only. Arguments and results keep ChEMBL's native field names.
type Options = {[string]: any}
type Spec = {name: string, path: string, rows: string, label: string, search: boolean, id: string, about: string,
	compact: string, fields: string, sort: string, filters: {[string]: string}}
type Resource = Spec & {compactSet: {[string]: boolean}, fieldSet: {[string]: boolean}, sortSet: {[string]: boolean}, filterKinds: {[string]: string}}

local API = "https://www.ebi.ac.uk/chembl/api/data"
-- ChEMBL serves at most 1,000 rows per page. Houston ends a call after 30 s and an uncached ChEMBL page can take 5 to
-- 15 s, so a call reads at most two pages and gives the second one less time.
local DEFAULT_LIMIT, MAX_LIMIT, PAGE_SIZE, MAX_PAGES = 100, 2000, 1000, 2
local FIRST_TIMEOUT, NEXT_TIMEOUT = 20000, 8000
local MAX_BYTES = 4 * 1024 * 1024
-- Upper bounds of one row in bytes, which size the first page from the byte budget.
local COMPACT_ROW, FULL_ROW = 2048, 128 * 1024
-- ChEMBL's server refuses request lines over 4,094 bytes; later pages add up to 40 bytes of paging.
local MAX_URL, PAGING_BYTES = 4000, 40
local MAX_TEXT, MAX_OFFSET, MAX_SORT = 1000, 2 ^ 31 - 1, 3
local MIN_SIMILARITY, DEFAULT_SIMILARITY, MIN_SUBSTRUCTURE = 40, 80, 5
local CHEMBL_ID = "^CHEMBL%d+$"
local INCHIKEY = "^" .. string.rep("%u", 14) .. "%-" .. string.rep("%u", 10) .. "%-%u$"

local function words(list: string): {string}
	local out: {string} = {}
	for word in string.gmatch(list, "%S+") do table.insert(out, word) end
	return out
end

local function set(list: string): {[string]: boolean}
	local out: {[string]: boolean} = {}
	for _, word in words(list) do out[word] = true end
	return out
end

-- Filter kinds, in help order, and the lookups ChEMBL accepts for each.
local KINDS = table.freeze({"text", "term", "number", "flag", "id", "smiles"})
local LOOKUP_LISTS: {[string]: string} = table.freeze({
	text = "exact iexact contains icontains startswith istartswith endswith iendswith regex iregex in isnull",
	term = "exact iexact in isnull",
	number = "exact gt gte lt lte range in isnull",
	flag = "exact isnull",
	id = "exact in",
	smiles = "flexmatch connectivity",
})
local LOOKUPS: {[string]: {[string]: boolean}} = {}
local ANY_LOOKUP: {[string]: boolean} = {}
for kind, list in LOOKUP_LISTS do
	LOOKUPS[kind] = set(list)
	for lookup in LOOKUPS[kind] do ANY_LOOKUP[lookup] = true end
end

local PROPERTIES = "molecule_properties__alogp molecule_properties__aromatic_rings molecule_properties__full_mwt "
	.. "molecule_properties__hba molecule_properties__hbd molecule_properties__heavy_atoms molecule_properties__mw_freebase "
	.. "molecule_properties__np_likeness_score molecule_properties__num_ro5_violations molecule_properties__psa "
	.. "molecule_properties__qed_weighted molecule_properties__rtb"
-- Molecule fields and filters shared by the structure searches, which ignore synonyms.
local STRUCTURE_FIELDS = "atc_classifications availability_type biotherapeutic black_box_warning chemical_probe chirality "
	.. "cross_references dosed_ingredient first_approval first_in_class helm_notation inorganic_flag max_phase "
	.. "molecule_chembl_id molecule_hierarchy molecule_properties molecule_structures molecule_type natural_product oral "
	.. "orphan parenteral polymer_flag pref_name prodrug structure_type therapeutic_flag topical usan_stem "
	.. "usan_stem_definition usan_substem usan_year veterinary withdrawn_flag"
local STRUCTURE_TEXT = "pref_name molecule_type structure_type availability_type helm_notation usan_stem "
	.. "usan_stem_definition usan_substem atc_classifications__level5 molecule_structures__standard_inchi_key "
	.. "molecule_properties__full_molformula molecule_properties__ro3_pass"
local STRUCTURE_FILTERS = table.freeze({
	text = STRUCTURE_TEXT,
	number = "max_phase first_approval usan_year chirality veterinary " .. PROPERTIES,
	flag = "oral parenteral topical black_box_warning natural_product first_in_class prodrug inorganic_flag "
		.. "polymer_flag therapeutic_flag dosed_ingredient withdrawn_flag chemical_probe orphan",
	id = "molecule_chembl_id molecule_hierarchy__parent_chembl_id",
	smiles = "molecule_structures__canonical_smiles",
})
local STRUCTURE_SORT = "molecule_chembl_id pref_name max_phase first_approval usan_year molecule_type structure_type " .. PROPERTIES
local MOLECULE_COMPACT = "molecule_chembl_id pref_name max_phase molecule_type first_approval molecule_properties"

local SPECS: {Spec} = {
	{name = "Molecule", path = "molecule", rows = "molecules", label = "molecule", search = true, id = "molecule",
		about = "Compounds, biologics and approved drugs. id is a ChEMBL ID such as CHEMBL25 or a standard InChIKey. q searches names and synonyms. Find an exact structure with filters `[\"molecule_structures__canonical_smiles__flexmatch\"] = smiles` (or `__connectivity` to ignore stereochemistry and salts), a trade name with `molecule_synonyms__molecule_synonym__iexact`. max_phase is the highest development phase, returned as a string such as \"4.0\" (approved); filter it as a number.",
		compact = MOLECULE_COMPACT, fields = STRUCTURE_FIELDS .. " molecule_synonyms", sort = STRUCTURE_SORT,
		filters = {text = STRUCTURE_TEXT .. " molecule_synonyms__molecule_synonym", number = STRUCTURE_FILTERS.number,
			flag = STRUCTURE_FILTERS.flag, id = STRUCTURE_FILTERS.id, smiles = STRUCTURE_FILTERS.smiles}},
	{name = "Target", path = "target", rows = "targets", label = "target", search = true, id = "chembl",
		about = "Proteins, complexes, cell lines and organisms that compounds act on. id is a ChEMBL ID such as CHEMBL203. Find a protein by UniProt accession with `target_components__accession`.",
		compact = "target_chembl_id pref_name target_type organism tax_id",
		fields = "cross_references organism pref_name species_group_flag target_chembl_id target_components target_type tax_id",
		sort = "organism tax_id pref_name target_type species_group_flag target_chembl_id",
		filters = {text = "pref_name organism target_type target_components__accession", number = "tax_id",
			flag = "species_group_flag", id = "target_chembl_id"}},
	{name = "Activity", path = "activity", rows = "activities", label = "activity", search = true, id = "integer",
		about = "Measured bioactivities (IC50, Ki, EC50, inhibition...) of a molecule in an assay. id is the integer activity_id. Prefer standard_* fields; pchembl_value is -log10 of the molar potency, for comparable IC50/Ki/EC50/Kd values. Filter by molecule_chembl_id, target_chembl_id, assay_chembl_id or document_chembl_id rather than listing all 24 million.",
		compact = "activity_id molecule_chembl_id molecule_pref_name target_chembl_id target_pref_name target_organism "
			.. "assay_chembl_id assay_type document_chembl_id standard_type standard_relation standard_value standard_units pchembl_value",
		fields = "action_type activity_comment activity_id activity_properties assay_chembl_id assay_description assay_type "
			.. "assay_variant_accession assay_variant_mutation bao_endpoint bao_format bao_label canonical_smiles "
			.. "data_validity_comment data_validity_description document_chembl_id document_journal document_year "
			.. "ligand_efficiency modality molecule_chembl_id molecule_pref_name parent_molecule_chembl_id pchembl_value "
			.. "potential_duplicate qudt_units record_id relation src_id standard_flag standard_relation standard_text_value "
			.. "standard_type standard_units standard_upper_value standard_value target_chembl_id target_organism "
			.. "target_pref_name target_tax_id text_value toid type units uo_units upper_value value",
		sort = "activity_id pchembl_value standard_value standard_type standard_units document_year molecule_chembl_id "
			.. "molecule_pref_name target_chembl_id target_pref_name target_organism assay_chembl_id assay_type document_chembl_id",
		filters = {term = "standard_type standard_relation standard_units assay_type target_organism target_pref_name "
				.. "molecule_pref_name activity_comment assay_description document_journal modality standard_text_value "
				.. "relation type units qudt_units uo_units text_value assay_variant_accession assay_variant_mutation",
			number = "pchembl_value standard_value standard_upper_value activity_id document_year target_tax_id record_id value upper_value",
			flag = "potential_duplicate standard_flag",
			id = "molecule_chembl_id parent_molecule_chembl_id target_chembl_id assay_chembl_id document_chembl_id"}},
	{name = "Assay", path = "assay", rows = "assays", label = "assay", search = true, id = "chembl",
		about = "Experiments that produced activities. id is a ChEMBL ID such as CHEMBL1217643. assay_type is B (binding), F (functional), A (ADME), T (toxicity), P (physicochemical) or U (unassigned); confidence_score 0 to 9 rates the target assignment (9: single protein, direct).",
		compact = "assay_chembl_id description assay_type assay_organism target_chembl_id document_chembl_id confidence_score",
		fields = "aidx assay_category assay_cell_type assay_chembl_id assay_classifications assay_group assay_organism "
			.. "assay_parameters assay_strain assay_subcellular_fraction assay_tax_id assay_test_type assay_tissue assay_type "
			.. "assay_type_description bao_format bao_label cell_chembl_id confidence_description confidence_score "
			.. "description document_chembl_id relationship_description relationship_type src_assay_id src_id "
			.. "target_chembl_id tissue_chembl_id variant_sequence",
		sort = "assay_chembl_id assay_type assay_organism assay_tax_id confidence_score target_chembl_id document_chembl_id src_id",
		filters = {text = "description assay_type assay_organism assay_category assay_cell_type assay_tissue assay_strain "
				.. "assay_subcellular_fraction assay_test_type relationship_type cell_chembl_id aidx assay_group",
			number = "confidence_score assay_tax_id src_id src_assay_id",
			id = "assay_chembl_id target_chembl_id document_chembl_id"}},
	{name = "Document", path = "document", rows = "documents", label = "document", search = true, id = "chembl",
		about = "Publications, patents and datasets ChEMBL extracted data from. id is a ChEMBL ID such as CHEMBL1139451. Look up a paper with `pubmed_id` or `doi`.",
		compact = "document_chembl_id title journal year doi pubmed_id doc_type",
		fields = "abstract authors chembl_release contact doc_type document_chembl_id doi doi_chembl first_page issue "
			.. "journal journal_full_title last_page patent_id pubmed_id src_id title volume year",
		sort = "document_chembl_id year pubmed_id doi title journal doc_type",
		filters = {text = "title abstract authors journal journal_full_title doc_type doi doi_chembl patent_id volume "
				.. "issue first_page last_page contact",
			number = "year pubmed_id", id = "document_chembl_id"}},
	{name = "Mechanism", path = "mechanism", rows = "mechanisms", label = "mechanism", search = false, id = "integer",
		about = "Curated mechanisms of action of drugs and clinical candidates. id is the integer mec_id. Filter by the parent molecule: parent_molecule_chembl_id, or molecule_chembl_id with the parent's ID.",
		compact = "mec_id molecule_chembl_id parent_molecule_chembl_id target_chembl_id mechanism_of_action action_type max_phase",
		fields = "action_type binding_site_comment direct_interaction disease_efficacy max_phase mec_id mechanism_comment "
			.. "mechanism_of_action mechanism_refs molecular_mechanism molecule_chembl_id parent_molecule_chembl_id "
			.. "record_id selectivity_comment site_id target_chembl_id variant_sequence",
		sort = "mec_id molecule_chembl_id parent_molecule_chembl_id target_chembl_id action_type mechanism_of_action max_phase",
		filters = {text = "action_type mechanism_of_action mechanism_comment selectivity_comment binding_site_comment",
			number = "max_phase mec_id record_id site_id", flag = "direct_interaction disease_efficacy molecular_mechanism",
			id = "molecule_chembl_id parent_molecule_chembl_id target_chembl_id"}},
	{name = "DrugIndication", path = "drug_indication", rows = "drug_indications", label = "drug indication", search = false,
		id = "integer",
		about = "Diseases that drugs and clinical candidates are approved or studied for, with EFO and MeSH terms. id is the integer drugind_id. Filter by parent_molecule_chembl_id, or molecule_chembl_id with the parent's ID; max_phase_for_ind is the highest phase for that indication.",
		compact = "drugind_id molecule_chembl_id parent_molecule_chembl_id efo_id efo_term mesh_id mesh_heading max_phase_for_ind",
		fields = "drugind_id efo_id efo_term indication_refs max_phase_for_ind mesh_heading mesh_id molecule_chembl_id "
			.. "parent_molecule_chembl_id",
		sort = "drugind_id molecule_chembl_id parent_molecule_chembl_id max_phase_for_ind mesh_id mesh_heading efo_id efo_term",
		filters = {text = "efo_term efo_id mesh_heading mesh_id", number = "max_phase_for_ind drugind_id",
			id = "molecule_chembl_id parent_molecule_chembl_id"}},
	-- Structure searches return molecules and have no get or text search.
	{name = "Similarity", path = "similarity", rows = "molecules", label = "similarity search", search = false, id = "",
		about = "", compact = MOLECULE_COMPACT .. " similarity", fields = STRUCTURE_FIELDS .. " similarity",
		sort = STRUCTURE_SORT .. " similarity", filters = STRUCTURE_FILTERS},
	{name = "Substructure", path = "substructure", rows = "molecules", label = "substructure search", search = false,
		id = "", about = "", compact = MOLECULE_COMPACT, fields = STRUCTURE_FIELDS, sort = STRUCTURE_SORT,
		filters = STRUCTURE_FILTERS},
}

local RESOURCES: {Resource} = {}
local BY_NAME: {[string]: Resource} = {}
for _, spec in SPECS do
	local resource: Resource = table.clone(spec) :: any
	resource.compactSet, resource.fieldSet, resource.sortSet = set(spec.compact), set(spec.fields), set(spec.sort)
	resource.filterKinds = {}
	for kind, list in spec.filters do
		for _, field in words(list) do resource.filterKinds[field] = kind end
	end
	table.insert(RESOURCES, resource)
	BY_NAME[spec.name] = resource
end

local function finite(value: any): boolean
	return type(value) == "number" and value == value and math.abs(value) < 2 ^ 53
end

local function number(value: number): string
	return if value % 1 == 0 then string.format("%d", value) else tostring(value)
end

local function integer(value: any, field: string, minimum: number, maximum: number): number
	assert(finite(value) and value % 1 == 0 and value >= minimum and value <= maximum,
		field .. " must be an integer from " .. number(minimum) .. " to " .. number(maximum))
	return value
end

local function text(value: any, field: string): string
	assert(type(value) == "string" and value ~= "" and #value <= MAX_TEXT,
		field .. " must be a nonempty string of at most " .. tostring(MAX_TEXT) .. " bytes")
	return value
end

local function chemblId(value: any, field: string): string
	local id = if type(value) == "string" then string.upper(value) else nil
	assert(id and string.match(id, CHEMBL_ID), field .. " must be a ChEMBL ID such as CHEMBL25")
	return id
end

-- A SMILES string is printable ASCII without spaces.
local function smiles(value: any, field: string, minimum: number): string
	assert(type(value) == "string" and #value >= minimum and #value <= MAX_TEXT and string.match(value, "^[%w%p]+$"),
		field .. " must be a SMILES string of " .. tostring(minimum) .. " to " .. tostring(MAX_TEXT) .. " characters without spaces")
	return value
end

-- A list takes an array or one comma-separated string.
local function list(value: any, field: string, maximum: number): {any}
	local items: {any} = {}
	if type(value) == "string" then
		for item in string.gmatch(value, "[^,]+") do
			local trimmed = string.match(item, "^%s*(.-)%s*$") :: string
			if trimmed ~= "" then table.insert(items, trimmed) end
		end
	else
		assert(type(value) == "table", field .. " must be an array or a comma-separated string")
		for index, item in value do
			assert(index == #items + 1, field .. " must be a dense array")
			table.insert(items, item)
		end
	end
	assert(#items > 0 and #items <= maximum, field .. " must list 1 to " .. tostring(maximum) .. " values")
	return items
end

-- Names are checked before they appear in an error message.
local function name(value: any, field: string): string
	assert(type(value) == "string" and #value <= 100 and string.match(value, "^%-?[%l%d_]+$"),
		field .. " must contain lowercase ChEMBL field names such as pref_name")
	return value
end

local function scalar(value: any, kind: string, key: string): string
	if kind == "number" then
		assert(finite(value), key .. " must be a finite number")
		return number(value)
	elseif kind == "flag" then
		assert(type(value) == "boolean" or (finite(value) and value % 1 == 0), key .. " must be true, false or an integer")
		return if type(value) == "boolean" then tostring(value) else number(value)
	elseif kind == "id" then
		return chemblId(value, key)
	elseif kind == "smiles" then
		return smiles(value, key, 1)
	end
	if finite(value) then return number(value) end
	return text(value, key)
end

local function filterParam(resource: Resource, key: any, value: any): string
	local filter = name(key, "filters")
	local prefix, suffix = string.match(filter, "^(.-)__(%l+)$")
	local field: string, lookup: string = filter, "exact"
	if prefix and suffix and ANY_LOOKUP[suffix] then field, lookup = prefix, suffix end
	local kind = resource.filterKinds[field]
	assert(kind, resource.label .. " has no filter " .. filter .. "; help() lists the filters")
	assert(LOOKUPS[kind][lookup], field .. " accepts only the lookups " .. LOOKUP_LISTS[kind])
	local rendered
	if lookup == "isnull" then
		assert(type(value) == "boolean", key .. " must be true or false")
		rendered = tostring(value)
	elseif lookup == "in" or lookup == "range" then
		local items = list(value, key, if lookup == "range" then 2 else 1000)
		assert(lookup == "in" or #items == 2, key .. " must be {low, high}")
		for index, item in items do
			items[index] = scalar(item, kind, key)
			assert(not string.find(items[index], ",", 1, true), key .. " values must not contain commas")
		end
		rendered = table.concat(items, ",")
	else
		rendered = scalar(value, kind, key)
	end
	return key .. "=" .. url.encode(rendered)
end

-- Returns the only parameter, or nil for complete records, and whether every row field is a compact default.
local function onlyParam(resource: Resource, value: any): (string?, boolean)
	if value == "all" then return nil, false end
	if value == nil then return "only=" .. url.encode(table.concat(words(resource.compact), ",")), true end
	local fields = list(value, "fields", 100)
	local compact = true
	for _, field in fields do
		assert(resource.fieldSet[name(field, "fields")], "fields contains " .. field .. ", which is not a " .. resource.label .. " field")
		compact = compact and resource.compactSet[field] == true
	end
	return "only=" .. url.encode(table.concat(fields, ",")), compact
end

local function options(value: any, operation: string): Options
	assert(value == nil or type(value) == "table", operation .. " options must be a table")
	return table.clone((value or {}) :: Options)
end

local function noneLeft(args: Options, operation: string)
	local unknown = next(args)
	assert(unknown == nil, operation .. " received an unknown option " .. string.sub(tostring(unknown), 1, 64))
end

local function errorCode(err: any): any
	return if type(err) == "table" then err.code else nil
end

local function failure(operation: string, response: HttpResponse, missing: string?): never
	local status = response.statusCode
	local detail = ""
	if status >= 300 and status < 400 then
		response.body:close()
		detail = "unexpected redirect"
	else
		-- ChEMBL errors are JSON with error_message and often a long traceback; other bodies are never shown.
		local ok, decoded = pcall(json.decode, await(response.body:readPrefix(64 * 1024)))
		if ok and type(decoded) == "table" and type(decoded.error_message) == "string" then
			-- houston.fail repairs a character split by the cut.
			detail = string.sub(string.match(string.gsub(decoded.error_message, "%s+", " "), "^ ?(.-) ?$") :: string, 1, 300)
		elseif status == 404 and missing then
			detail = missing .. " was not found"
		end
	end
	local message = "ChEMBL HTTP " .. tostring(status) .. (if detail == "" then "" else ": " .. detail)
	local retry = response.headers["retry-after"]
	if (status == 429 or status == 503) and retry and retry[1] then
		-- Retry-After is either delay seconds or an HTTP date.
		local value = string.sub(retry[1], 1, 32)
		message ..= "; retry after " .. value .. (if string.match(value, "^%d+$") then "s" else "")
	end
	-- Input is validated first, so a 500 with ChEMBL's own error message is a deterministic rejection, such as a SMILES
	-- ChEMBL cannot parse; gateway failures and overload are transient.
	local transient = status == 429 or status == 502 or status == 503 or status == 504 or (status >= 500 and detail == "")
	return houston.fail({operation = operation, layer = "upstream", upstream_status = status, retryable = transient,
		message = message})
end

-- Returns the decoded JSON object and the bytes read. A later page that is too slow or over budget returns nil.
local function fetch(operation: string, target: string, budget: number, later: boolean, missing: string?): (any, number)
	local sent, response = pcall(function()
		return await(http.request({method = "GET", url = target, headers = {Accept = {"application/json"}},
			timeoutMs = if later then NEXT_TIMEOUT else FIRST_TIMEOUT}))
	end)
	if not sent then
		if errorCode(response) ~= "timeout" then error(response, 0) end
		if later then return nil, 0 end
		houston.fail({operation = operation, layer = "upstream", retryable = true,
			message = "ChEMBL did not answer within " .. tostring(FIRST_TIMEOUT // 1000) .. " s; retry, since ChEMBL caches results, or narrow the request"})
	end
	if response.statusCode ~= 200 then failure(operation, response, missing) end
	local read, raw = pcall(function() return await(response.body:readAll(budget)) end)
	if not read then
		local code = errorCode(raw)
		if code == "limit_exceeded" and later then
			return nil, 0
		elseif code == "limit_exceeded" then
			houston.fail({operation = operation, layer = "upstream", upstream_status = 200, retryable = false,
				message = "ChEMBL returned more data than one call can hold; request fewer fields or a lower limit"})
		elseif code == "cancelled" or code == "timeout" then
			error(raw, 0)
		end
		local detail = if type(raw) == "table" and type(raw.message) == "string" then raw.message else tostring(raw)
		houston.fail({operation = operation, layer = "upstream", upstream_status = 200, retryable = true,
			message = "ChEMBL response failed: " .. string.sub(detail, 1, 300)})
	end
	local ok, value = pcall(json.decode, raw)
	if not ok or type(value) ~= "table" or not string.match(raw, "^%s*{") then
		houston.fail({operation = operation, layer = "upstream", upstream_status = 200, retryable = false,
			message = "ChEMBL returned an invalid JSON object"})
	end
	return value, #raw
end

-- Searches and lists: one fixed query, read page by page within the row limit, byte budget and time limit.
local function collect(operation: string, resource: Resource, args: Options, query: {string}): Options
	local limit = integer(if args.limit == nil then DEFAULT_LIMIT else args.limit, "limit", 1, MAX_LIMIT)
	local offset = integer(if args.offset == nil then 0 else args.offset, "offset", 0, MAX_OFFSET)
	args.limit, args.offset = nil, nil
	local path = resource.path
	if args.q ~= nil then
		assert(resource.search, operation .. " has no q text search; use filters")
		table.insert(query, "q=" .. url.encode(text(args.q, "q")))
		path ..= "/search"
		args.q = nil
	end
	if args.filters ~= nil then
		assert(type(args.filters) == "table", "filters must be a table of field__lookup = value")
		for key, value in args.filters do table.insert(query, filterParam(resource, key, value)) end
		args.filters = nil
	end
	table.sort(query)
	if args.order_by ~= nil then
		for _, key in list(args.order_by, "order_by", MAX_SORT) do
			assert(resource.sortSet[string.gsub(name(key, "order_by"), "^%-", "")],
				"order_by contains " .. key .. ", which cannot sort " .. resource.label .. " results; help() lists the sort fields")
			table.insert(query, "order_by=" .. url.encode(key))
		end
		args.order_by = nil
	end
	local only, compact = onlyParam(resource, args.fields)
	args.fields = nil
	if only then table.insert(query, only) end
	noneLeft(args, operation)
	local base = API .. "/" .. path .. ".json?" .. (if #query > 0 then table.concat(query, "&") .. "&" else "")
	assert(#base + PAGING_BYTES <= MAX_URL, "the request is too long: " .. tostring(#base + PAGING_BYTES)
		.. " bytes once URL-encoded, at most " .. tostring(MAX_URL) .. "; use fewer or shorter values")

	local rows = json.decode("[]")
	local result: Options = {[resource.rows] = rows}
	local used, more = 0, false
	for page = 1, MAX_PAGES do
		local size = math.min(limit - #rows, PAGE_SIZE)
		if page == 1 then
			size = math.min(size, MAX_BYTES // (if compact then COMPACT_ROW else FULL_ROW))
		else
			-- Size later pages from the bytes per row so far, so they fit the remaining budget.
			size = math.min(size, (MAX_BYTES - used) // (2 * used / #rows))
			if size < 1 then break end
		end
		local body, bytes = fetch(operation, base .. "limit=" .. tostring(size) .. "&offset=" .. tostring(offset + #rows),
			MAX_BYTES - used, page > 1)
		-- A later page that is too slow or too large ends the call; the caller continues from next_offset.
		if body == nil then break end
		used += bytes
		local found, meta = body[resource.rows], body.page_meta
		if type(found) ~= "table" or type(meta) ~= "table" or not finite(meta.total_count) then
			houston.fail({operation = operation, layer = "upstream", upstream_status = 200, retryable = false,
				message = "ChEMBL returned an unexpected " .. resource.label .. " page"})
		end
		if page == 1 then result.total_count = meta.total_count end
		for _, row in found do table.insert(rows, row) end
		-- ChEMBL links the next page while rows remain after this one.
		more = #found > 0 and type(meta.next) == "string"
		if not more or #rows >= limit then break end
	end
	if more then result.next_offset = offset + #rows end
	return result
end

local function get(resource: Resource): (any, Options?) -> any
	local operation = "get" .. resource.name
	return function(value: any, input: Options?): any
		local args = options(input, operation)
		local id
		if resource.id == "integer" then
			id = number(integer(if type(value) == "string" and string.match(value, "^%d+$") then tonumber(value) else value,
				"id", 1, 2 ^ 53 - 1))
		elseif resource.id == "molecule" then
			id = if type(value) == "string" then string.upper(value) else ""
			assert(string.match(id, INCHIKEY) or string.match(id, CHEMBL_ID),
				"id must be a ChEMBL ID such as CHEMBL25 or a standard InChIKey")
		else
			id = chemblId(value, "id")
		end
		local only = if args.fields == nil then nil else onlyParam(resource, args.fields)
		args.fields = nil
		noneLeft(args, operation)
		local target = API .. "/" .. resource.path .. "/" .. id .. ".json" .. (if only then "?" .. only else "")
		assert(#target <= MAX_URL, "fields is too long once URL-encoded, at most " .. tostring(MAX_URL) .. " bytes")
		return (fetch(operation, target, MAX_BYTES, false, resource.label .. " " .. id))
	end
end

-- The query molecule is a SMILES string or a ChEMBL ID, under ChEMBL's own parameter names.
local function structure(operation: string, args: Options, minimum: number): {string}
	assert((args.smiles == nil) ~= (args.chembl_id == nil), operation .. " takes either smiles or chembl_id")
	local query = if args.smiles ~= nil then "smiles=" .. url.encode(smiles(args.smiles, "smiles", minimum))
		else "chembl_id=" .. chemblId(args.chembl_id, "chembl_id")
	args.smiles, args.chembl_id = nil, nil
	return {query}
end

local function similarMolecules(input: Options?): Options
	local args = options(input, "similarMolecules")
	local query = structure("similarMolecules", args, 1)
	local similarity = integer(if args.similarity == nil then DEFAULT_SIMILARITY else args.similarity, "similarity",
		MIN_SIMILARITY, 100)
	args.similarity = nil
	table.insert(query, "similarity=" .. number(similarity))
	return collect("similarMolecules", BY_NAME.Similarity, args, query)
end

local function substructureMolecules(input: Options?): Options
	local args = options(input, "substructureMolecules")
	return collect("substructureMolecules", BY_NAME.Substructure, args, structure("substructureMolecules", args, MIN_SUBSTRUCTURE))
end

local exports: {[string]: any} = {similarMolecules = similarMolecules, substructureMolecules = substructureMolecules}
local sections: {string} = {}

local function listHelp(lists: {[string]: string}): string
	local parts: {string} = {}
	for _, kind in KINDS do
		if lists[kind] then table.insert(parts, kind .. ": " .. string.gsub(lists[kind], " ", ", ")) end
	end
	return table.concat(parts, "; ")
end

local function filterHelp(resource: Resource): string
	return "Filters by kind: " .. listHelp(resource.filters) .. ".\norder_by: "
		.. string.gsub(resource.sort, " ", ", ") .. ".\nfields: " .. string.gsub(resource.fields, " ", ", ")
		.. ". Default fields: " .. string.gsub(resource.compact, " ", ", ") .. "."
end

for _, resource in RESOURCES do
	if resource.id ~= "" then
		local listName = "search" .. string.gsub(string.gsub(resource.rows, "^%l", string.upper), "_(%l)", string.upper)
		exports[listName] = function(input: Options?): Options
			return collect(listName, resource, options(input, listName), {})
		end
		exports["get" .. resource.name] = get(resource)
		table.insert(sections, "## " .. listName .. "(opts?) and get" .. resource.name .. "(id, opts?)\n\n"
			.. "GET /" .. resource.path .. (if resource.search then " (with q: /" .. resource.path .. "/search)" else "")
			.. " and /" .. resource.path .. "/{id}. Rows come back as `" .. resource.rows .. "`. " .. resource.about
			.. (if resource.search then "" else " No q text search.") .. "\n" .. filterHelp(resource))
	end
end

local HELP = [[ChEMBL: search and read EMBL-EBI's open database of bioactive molecules, their targets, measured bioactivities, assays, source documents, drug mechanisms and indications (ChEMBL data web services, https://www.ebi.ac.uk/chembl/api/data/docs). No account or credentials. Read-only. Calls return completed values; do not wrap them in await(). Records keep ChEMBL's JSON field names and values unchanged; decimals such as max_phase, alogp, standard_value and pchembl_value come back as strings. Data is CC BY-SA 3.0: credit "ChEMBL, EMBL-EBI" when presenting results.

## Searches: search<Rows>(opts?), similarMolecules(opts), substructureMolecules(opts)

Return `{<rows>, total_count, next_offset?}`, for example `{molecules = {...}, total_count = 52, next_offset = 100}`. Options use ChEMBL's names; unknown options, filters, lookups, sort fields and field names are rejected before any request, because ChEMBL itself silently ignores unknown filters and returns every record.
- q: free text, for searches that support it; results rank by relevance unless order_by is given. ChEMBL counts at most 10,000 text matches.
- filters: a table of `field__lookup = value`, all of which must match, such as `{pref_name__icontains = "statin", max_phase = 4, ["molecule_properties__full_mwt__lte"] = 500}`. A bare field means exact. `in` takes an array (values without commas), `range` takes {low, high}, `isnull` takes true or false. Each resource below lists its filters by kind. Lookups by kind: ]] .. listHelp(LOOKUP_LISTS) .. [[. text and term values are strings, number values numbers, flag values true, false or an integer, id values ChEMBL IDs and smiles values SMILES strings.
- order_by: a field, or -field for descending, or an array of up to 3. Descending order puts missing values first; add a filter such as `pchembl_value__isnull = false`.
- fields: an array or comma-separated string of top-level fields for each row, or "all" for complete records. Defaults to the compact fields listed per resource. A nested object such as molecule_properties comes back whole.
- limit: rows to return, 1 to 2000 (default 100). offset: rows to skip (default 0).
next_offset is present exactly when ChEMBL has rows after the last one returned: call again with the same options and offset = next_offset. A call reads at most two ChEMBL pages of up to 1,000 rows and 4 MiB, so it may return fewer than limit rows with next_offset; fields beyond the defaults, or "all", start with a first page of 32 rows.

## similarMolecules({smiles | chembl_id, similarity?, filters?, order_by?, fields?, limit?, offset?})

GET /similarity. Molecules whose Tanimoto similarity to the query structure is at least similarity percent, 40 to 100 (default 80). Each row adds `similarity`, a string percentage; rows come highest first. A chembl_id query excludes that molecule itself; a smiles query includes it. Filters, order_by and fields are those of searchMolecules except the molecule_synonyms ones, plus similarity.

## substructureMolecules({smiles | chembl_id, filters?, order_by?, fields?, limit?, offset?})

GET /substructure. Molecules containing the query structure; smiles has at least 5 characters, and ChEMBL stops at 30,000 matches. Filters, order_by and fields are those of searchMolecules except the molecule_synonyms ones.

## get<Name>(id, opts?)

Returns one complete record; opts.fields selects top-level fields as in the searches. An unknown ID fails with HTTP 404.

]]

local HELP_END = [[


## Errors and limits

Invalid input fails before any request, including requests over 4,000 bytes once URL-encoded (SMILES strings count once encoded). ChEMBL errors come back as upstream errors with the HTTP status and ChEMBL's message, such as a SMILES string it cannot parse (HTTP 500, not retryable). HTTP 429, 502, 503 and 504 are retryable. ChEMBL answers a cached query in about a second and a new one in 5 to 15 s or more, and Houston ends a call after 30 s: a first page slower than 20 s fails as retryable (ChEMBL caches results, so a retry is often fast), and a second page slower than 8 s is skipped in favor of next_offset. Prefer narrow filters and compact fields over many calls.

## Example

Here chembl is the configured ChEMBL connection.

```lua
local found = chembl.searchMolecules({q = "imatinib", fields = {"molecule_chembl_id", "pref_name", "max_phase"}, limit = 5})
local id = found.molecules[1].molecule_chembl_id
local potent = chembl.searchActivities({filters = {molecule_chembl_id = id, standard_type__in = {"IC50", "Ki"},
	pchembl_value__gte = 7}, order_by = "-pchembl_value", limit = 200})
for _, row in potent.activities do print(row.target_pref_name, row.standard_type, row.pchembl_value) end
local moa = chembl.searchMechanisms({filters = {parent_molecule_chembl_id = id}})
local close = chembl.similarMolecules({smiles = "CC(=O)Oc1ccccc1C(=O)O", similarity = 70, filters = {max_phase = 4}})
local target = chembl.getTarget("CHEMBL203")
```]]

local function help(): string
	return HELP .. table.concat(sections, "\n\n") .. HELP_END
end

exports.help = help
return exports
