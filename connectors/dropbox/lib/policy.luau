-- Folder permissions use Dropbox's canonical paths; continuation tokens retain their original query boundary.
type Object = {[string]: any}
type Grant = {path: string, access: "read-only" | "read-write"}
local DENIED = "Dropbox path is outside the permitted folder access"
local specs: {[string]: {fields: string, kind: string}} = {
	getMetadata = {fields = "path include_media_info include_deleted", kind = "read"},
	listFolder = {fields = "path recursive limit include_deleted include_media_info include_mounted_folders include_non_downloadable_files", kind = "list"},
	listFolderContinue = {fields = "cursor", kind = "continue"},
	listFolderGetLatestCursor = {fields = "path recursive include_deleted include_media_info include_mounted_folders include_non_downloadable_files", kind = "list"},
	search = {fields = "query options match_field_options include_highlights", kind = "search"},
	searchContinue = {fields = "cursor", kind = "continue"},
	listRevisions = {fields = "path limit before_rev include_restorable_info", kind = "read"},
	getTemporaryLink = {fields = "path", kind = "read"},
	download = {fields = "path session_path", kind = "read"},
	downloadZip = {fields = "path session_path", kind = "read"},
	export = {fields = "path export_format session_path", kind = "read"},
	getPreview = {fields = "path session_path", kind = "read"},
	getThumbnail = {fields = "path format size mode session_path", kind = "read"},
	createFolder = {fields = "path autorename", kind = "write"},
	upload = {fields = "path session_path mode autorename mute client_modified strict_conflict content_hash", kind = "write"},
	move = {fields = "from_path to_path autorename", kind = "move"},
	copy = {fields = "from_path to_path autorename", kind = "copy"},
	delete = {fields = "path parent_rev", kind = "delete"},
	restore = {fields = "path rev", kind = "restore"},
}

local function ordinary(value: any, root: boolean?): string
	assert(type(value) == "string", "Dropbox path must be a string")
	if value == "" and root then return value end
	assert(string.sub(value, 1, 1) == "/" and value ~= "/" and string.sub(value, -1) ~= "/", "Custom access requires an absolute Dropbox path; use '' for the root")
	assert(utf8.len(value) ~= nil and not string.find(value, "[%z\1-\31\127\\]"), "Dropbox path contains invalid characters")
	assert(not string.find(value, "//", 1, true), "Dropbox path contains an empty component")
	for part in string.gmatch(value, "[^/]+") do
		assert(part ~= "." and part ~= ".." and string.sub(part, -1) ~= " ", "Dropbox path contains a noncanonical component")
	end
	return value
end

local function within(path: string, root: string): boolean
	return root == "" or path == root or string.sub(path, 1, #root + 1) == root .. "/"
end

local function denied(): never
	error(DENIED, 0)
end

local function fields(value: any, allowed: string)
	assert(type(value) == "table", "opts must be an object")
	local permitted: {[string]: boolean} = {}
	for key in string.gmatch(allowed, "%S+") do permitted[key] = true end
	for key in value do assert(permitted[key] == true, "This option is unavailable with custom folder access: " .. tostring(key)) end
end

return function(raw: string, metadata: (string) -> Object?): any
	local parsed = json.decode(raw)
	assert(type(parsed) == "table" and next(parsed) ~= nil, "Folder access must be a nonempty JSON object mapping paths to read-only or read-write")
	local configured: {Grant} = {}
	local writable = false
	for path, access in parsed do
		assert(type(path) == "string" and (access == "read-only" or access == "read-write"), "Folder access maps each absolute folder path to read-only or read-write")
		table.insert(configured, {path = if path == "/" then "" else ordinary(path), access = access})
		writable = writable or access == "read-write"
	end
	assert(#configured <= 64, "Folder access supports at most 64 folder rules")
	table.sort(configured, function(a: Grant, b: Grant): boolean return a.path < b.path end)
	local grants: {Grant}? = nil
	local function rules(): {Grant}
		if grants then return grants end
		local resolved: {Grant} = {}
		local seen: {[string]: boolean} = {}
		for _, grant in configured do
			local path = grant.path
			if path ~= "" then
				local info = metadata(path)
				assert(info and info[".tag"] == "folder" and type(info.path_lower) == "string", "A configured Dropbox folder is missing or unavailable")
				path = ordinary(info.path_lower)
			end
			assert(not seen[path], "Folder access contains two rules for the same Dropbox folder")
			seen[path] = true
			table.insert(resolved, {path = path, access = grant.access})
		end
		grants = resolved
		return resolved
	end
	local function permission(path: string): string?
		local selected: Grant? = nil
		for _, grant in rules() do
			if within(path, grant.path) and (selected == nil or #grant.path > #selected.path) then selected = grant end
		end
		return if selected then selected.access else nil
	end
	local function authorize(path: string, write: boolean, subtree: boolean?)
		local access = permission(path)
		if access == nil or (write and (access ~= "read-write" or houston.access ~= "read-write")) then denied() end
		if write and subtree then
			for _, grant in rules() do
				assert(not (grant.access == "read-only" and within(grant.path, path)), "This operation would change a read-only folder subtree")
			end
		end
	end
	local function lookup(path: string): Object?
		local ok, info = pcall(metadata, path)
		if not ok then denied() end
		return info
	end
	local function metadataPath(info: Object): string
		local ok, path = pcall(ordinary, info.path_lower)
		if not ok then denied() end
		return path
	end
	local function canonical(path: any, destination: boolean?): string
		local original = ordinary(path, true)
		rules()
		if original == "" then return "" end
		local info = lookup(original)
		if info then
			return metadataPath(info)
		end
		if not destination then denied() end
		local parent, leaf = string.match(original, "^(.*)/([^/]+)$")
		assert(parent ~= nil and leaf ~= nil, "Dropbox destination is invalid")
		if parent == "" then return "/" .. leaf end
		local folder = lookup(parent)
		if not folder or folder[".tag"] ~= "folder" then denied() end
		return metadataPath(folder :: Object) .. "/" .. leaf
	end
	local function resultPath(info: any, root: string?): string
		assert(type(info) == "table" and type(info.path_lower) == "string", "Dropbox returned metadata without a verifiable folder path")
		local path = ordinary(info.path_lower)
		authorize(path, false)
		assert(root == nil or within(path, root), "Dropbox returned metadata outside the requested folder")
		return path
	end
	local function parent(path: string): string
		return string.match(path, "^(.*)/[^/]+$") or ""
	end
	local policy: any = {writable = writable and houston.access == "read-write", supports = function(name: string): boolean return specs[name] ~= nil end}
	local function prepare(name: string, value: any): (Object, Object)
		local spec = specs[name]
		assert(spec, "Operation is unavailable with custom folder access")
		fields(value, spec.fields)
		local args = table.clone(value)
		local context: Object = {}
		if spec.kind == "continue" then
			local token = houston.unseal(args.cursor)
			assert(type(token) == "table" and token.operation == name and type(token.cursor) == "string", "Invalid Dropbox continuation token")
			context.root = ordinary(token.root, true)
			authorize(context.root, false)
			args.cursor = token.cursor
			return args, context
		end
		assert(args.autorename == nil or args.autorename == false, "Autorename is unavailable with custom folder access; choose an explicit destination")
		if spec.kind == "search" then
			fields(args.options, "path max_results order_by file_status filename_only file_extensions file_categories")
			args.options = table.clone(args.options)
			context.root = canonical(args.options.path)
			authorize(context.root, false)
			args.options.path = context.root
		elseif spec.kind == "move" or spec.kind == "copy" then
			args.from_path = canonical(args.from_path)
			args.to_path = canonical(args.to_path, true)
			authorize(args.from_path, spec.kind == "move", spec.kind == "move")
			authorize(args.to_path, true, true)
			context.root = parent(args.to_path)
		else
			local write = spec.kind == "write" or spec.kind == "delete" or spec.kind == "restore"
			args.path = canonical(args.path, spec.kind == "write" or spec.kind == "restore")
			authorize(args.path, write, write)
			context.root = if spec.kind == "write" or spec.kind == "restore" then parent(args.path) else args.path
			if spec.kind == "restore" then
				assert(type(args.rev) == "string" and string.match(args.rev, "^[0-9a-f]+$"), "rev must be a Dropbox revision")
				local revision = lookup("rev:" .. args.rev)
				if not revision then denied() end
				authorize(metadataPath(revision :: Object), false)
			end
		end
		return args, context
	end
	policy.prepare = function(name: string, value: any): (Object, Object)
		local ok, args, context = pcall(prepare, name, value)
		if not ok then
			if string.find(tostring(args), DENIED, 1, true) then denied() end
			error(args, 0)
		end
		return args, context
	end
	policy.result = function(name: string, result: any, context: Object): any
		assert(type(result) == "table", "Dropbox returned an invalid result")
		if name == "listFolder" or name == "listFolderContinue" or name == "listFolderGetLatestCursor" then
			if name ~= "listFolderGetLatestCursor" then
				assert(type(result.entries) == "table" and type(result.has_more) == "boolean", "Dropbox returned an invalid folder page")
				for _, entry in result.entries do resultPath(entry, context.root) end
			end
			assert(type(result.cursor) == "string", "Dropbox returned no folder cursor")
			result.cursor = houston.seal({operation = "listFolderContinue", root = context.root, cursor = result.cursor})
		elseif name == "search" or name == "searchContinue" then
			assert(type(result.matches) == "table" and type(result.has_more) == "boolean", "Dropbox returned an invalid search page")
			for _, match in result.matches do
				assert(type(match.metadata) == "table", "Dropbox returned invalid search metadata")
				resultPath(match.metadata.metadata, context.root)
			end
			if result.cursor ~= nil then
				assert(type(result.cursor) == "string", "Dropbox returned an invalid search cursor")
				result.cursor = houston.seal({operation = "searchContinue", root = context.root, cursor = result.cursor})
			end
		elseif name == "listRevisions" then
			assert(type(result.entries) == "table", "Dropbox returned invalid revisions")
			for _, entry in result.entries do resultPath(entry, context.root) end
		elseif name == "getTemporaryLink" or name == "downloadZip" or name == "createFolder" or name == "move" or name == "copy" or name == "delete" then
			resultPath(result.metadata, context.root)
		elseif name == "export" then
			resultPath(result.file_metadata, context.root)
		else
			resultPath(result, context.root)
		end
		return result
	end
	policy.help = function(): string
		local lines = {"Custom folder access: unlisted paths are denied; the most specific configured folder wins. Effective caller access: " .. houston.access .. "."}
		for _, grant in configured do
			local access = if houston.access == "read-only" then "read-only" else grant.access
			table.insert(lines, (if grant.path == "" then "/" else grant.path) .. ": " .. access)
		end
		table.insert(lines, "Folder rules must name existing folders in this account's member root. Paths are checked using Dropbox's canonical metadata, including Unicode names. Use ordinary absolute paths, not IDs, namespace aliases or revision paths. Parent folders must exist before creating a child. Search requires options.path. Pagination cursors are Houston tokens, tied to this connection and its current settings; keep them intact. Moves and deletes cannot change a read-only subtree. Autorename, revision downloads, batch/jobs, sharing, file requests and account-wide operations are unavailable in this mode.")
		return table.concat(lines, "\n")
	end
	policy.documentation = function(name: string, doc: string): string
		doc = string.gsub(doc, "rev%?, ", "")
		doc = string.gsub(doc, "autorename%?, ", "")
		doc = string.gsub(doc, ", autorename%?", "")
		if name == "search" then
			doc = string.gsub(doc, "options%?=", "options=")
			doc = string.gsub(doc, "path%?", "path")
		end
		return doc
	end
	return policy
end
