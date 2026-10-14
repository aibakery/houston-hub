-- Dropbox API v2. Every route is a POST: RPC routes exchange JSON bodies, while
-- download and upload routes pass their argument in the Dropbox-API-Arg header.
type Options = {[string]: any}
type Endpoint = {route: string, read: boolean, style: ("download" | "upload")?, void: boolean?, help: string}
local API = "https://api.dropboxapi.com/2/"
local CONTENT = "https://content.dropboxapi.com/2/"
local MAX_SAFE_INTEGER = 9007199254740991
local MAX_UPLOAD_BYTES = 150 * 1024 * 1024 -- Dropbox's limit for one upload request.

local function text(value: any, field: string): string
	assert(type(value) == "string" and value ~= "", field .. " must be a nonempty string")
	return value
end

local function options(value: any): Options
	if value == nil then return {} end
	assert(type(value) == "table", "opts must be an object")
	for key in value do assert(type(key) == "string", "opts must have named fields") end
	return table.clone(value)
end

-- Dropbox-API-Arg must be HTTP header safe: escape DEL and every non-ASCII character.
local function headerJSON(value: Options): string
	return (string.gsub(json.encode(value), "[\127-\244][\128-\191]*", function(char: string): string
		local code = utf8.codepoint(char)
		if code < 0x10000 then return string.format("\\u%04x", code) end
		code -= 0x10000
		return string.format("\\u%04x\\u%04x", 0xD800 + code // 0x400, 0xDC00 + code % 0x400)
	end))
end

local function fail(operation: string, response: HttpResponse): never
	local chunk = await(response.body:read(4096))
	response.body:close()
	local raw = if chunk.done then "" else chunk.data
	-- Route errors are JSON with an error_summary such as "path/not_found/.."; bad input is plain text.
	local ok, decoded = pcall(json.decode, raw)
	local problem = if ok and type(decoded) == "table" then decoded else {}
	local summary = if type(problem.error_summary) == "string" then problem.error_summary else raw
	local message = "Dropbox HTTP " .. tostring(response.statusCode)
	if summary ~= "" then message ..= ": " .. string.sub(summary, 1, 600) end
	local user = problem.user_message
	if type(user) == "table" and type(user.text) == "string" then message ..= " (" .. string.sub(user.text, 1, 300) .. ")" end
	local retry = response.headers["retry-after"]
	if retry and retry[1] then message ..= "; Retry-After: " .. retry[1] end
	-- Dropbox asks callers to retry when concurrent writes to one namespace collide.
	local contended = string.find(summary, "too_many_write_operations", 1, true) ~= nil
	return houston.fail({operation = operation, layer = "upstream", upstream_status = response.statusCode,
		retryable = response.statusCode == 429 or response.statusCode >= 500 or contended, message = message})
end

local function invalid(operation: string, response: HttpResponse, message: string): never
	return houston.fail({operation = operation, layer = "upstream", upstream_status = response.statusCode, retryable = false, message = message})
end

-- Returns the JSON object or array Dropbox sent, or {success=true} for routes whose result is null.
local function decode(operation: string, response: HttpResponse): any
	if response.statusCode < 200 or response.statusCode >= 300 then fail(operation, response) end
	local raw = await(response.body:readAll())
	if string.match(raw, "^%s*$") or string.match(raw, "^%s*null%s*$") then return {success = true} end
	local ok, value = pcall(json.decode, raw)
	if not ok or type(value) ~= "table" then invalid(operation, response, "Dropbox returned invalid JSON") end
	return value
end

local function rpc(name: string, endpoint: Endpoint, input: any): any
	local args = options(input)
	if endpoint.void then assert(next(args) == nil, name .. " takes no options") end
	return decode(name, await(http.request({method = "POST", url = API .. endpoint.route,
		headers = if endpoint.void then nil else {["Content-Type"] = {"application/json"}},
		body = if endpoint.void then nil else json.encode(args)})))
end

-- Content routes take a session file path beside Dropbox's argument, which travels in a header.
local function content(endpoint: Endpoint, input: any, headers: HttpHeaders): (HttpRequest, string)
	local args = options(input)
	local path = text(args.session_path, "session_path")
	args.session_path = nil
	headers["Dropbox-API-Arg"] = {headerJSON(args)}
	return {method = "POST", url = CONTENT .. endpoint.route, headers = headers}, path
end

-- Streams the response body to a session file; Dropbox describes it in the Dropbox-API-Result header.
local function download(name: string, endpoint: Endpoint, input: any): Options
	local request, path = content(endpoint, input, {})
	local response = await(http.request(request))
	if response.statusCode < 200 or response.statusCode >= 300 then fail(name, response) end
	local header = response.headers["dropbox-api-result"]
	local ok, result = pcall(json.decode, if header and header[1] then header[1] else "")
	if not ok or type(result) ~= "table" then
		response.body:close()
		invalid(name, response, "Dropbox returned no Dropbox-API-Result metadata")
	end
	local opened, output = pcall(function(): File return fs.open(path, "w") end)
	if not opened then
		response.body:close()
		error(output, 0)
	end
	output:write(response.body)
	await(output:close())
	return {session_path = path, url = await(fs.signedGetUrl(path)), size = await(fs.stat(path)).size, result = result}
end

local function upload(name: string, endpoint: Endpoint, input: any): any
	local request, path = content(endpoint, input, {["Content-Type"] = {"application/octet-stream"}})
	assert(await(fs.stat(path)).size <= MAX_UPLOAD_BYTES, "upload sends at most 150 MiB; larger files are not supported")
	request.body = fs.open(path, "r")
	return decode(name, await(http.request(request)))
end

local CURSOR = "({cursor}) -> the next page."
local ENTRIES = " complete.entries holds one result per entry."
local function job(starters: string, tags: string?): string
	return "({async_job_id}) -> {['.tag']=" .. (tags or "'in_progress'|'complete'|'failed'") .. ", ...}. Polls " .. starters .. "."
end
local endpoints: {[string]: Endpoint} = {
	-- Account
	getCurrentAccount = {route = "users/get_current_account", read = true, void = true,
		help = "() -> {account_id, name, email, root_info, ...}. root_info.root_namespace_id addresses a team space as 'ns:<id>/...'."},
	getSpaceUsage = {route = "users/get_space_usage", read = true, void = true, help = "() -> {used, allocation}. Bytes used and the quota."},
	getAccount = {route = "users/get_account", read = true, help = "({account_id}) -> {account_id, name, email, ...}. Another Dropbox user, e.g. a folder member."},

	-- Files and folders
	getMetadata = {route = "files/get_metadata", read = true,
		help = "({path, include_media_info?, include_deleted?}) -> file, folder or deleted metadata; ['.tag'] tells which."},
	listFolder = {route = "files/list_folder", read = true,
		help = "({path, recursive?, limit?, include_deleted?, include_media_info?}) -> {entries, cursor, has_more}. path='' is the root. limit is a hint up to 2000."},
	listFolderContinue = {route = "files/list_folder/continue", read = true, help = CURSOR .. " Also returns later changes when called with a saved cursor."},
	listFolderGetLatestCursor = {route = "files/list_folder/get_latest_cursor", read = true,
		help = "({path, recursive?}) -> {cursor}. A cursor at the current state; listFolderContinue on it later returns only changes."},
	search = {route = "files/search_v2", read = true,
		help = "({query, options?={path?, max_results?, file_status?, filename_only?, file_extensions?, file_categories?}}) -> {matches, has_more, cursor?}. Matches names and content; matches[i].metadata.metadata is the file."},
	searchContinue = {route = "files/search/continue_v2", read = true, help = CURSOR},
	listRevisions = {route = "files/list_revisions", read = true, help = "({path, limit?, before_rev?}) -> {is_deleted, entries, has_more}. A file's versions, newest first; pass the last entry's rev as before_rev for older ones."},
	getTemporaryLink = {route = "files/get_temporary_link", read = true,
		help = "({path}) -> {metadata, link}. A direct download link valid for four hours, to hand to a person or an outside client; Houston scripts transfer files with download."},
	download = {route = "files/download", read = true, style = "download", help = "({path, rev?, session_path}) -> {session_path, url, size, result=file metadata}."},
	downloadZip = {route = "files/download_zip", read = true, style = "download",
		help = "({path, session_path}) -> {session_path, url, size, result={metadata}}. A folder as a zip, up to 20 GB and 10,000 files."},
	export = {route = "files/export", read = true, style = "download",
		help = "({path, export_format?, session_path}) -> {session_path, url, size, result={export_metadata, file_metadata}}. Converts files that have no downloadable bytes, such as Paper docs: their metadata has export_info.export_as, and export_info.export_options lists other export_format values."},
	getPreview = {route = "files/get_preview", read = true, style = "download",
		help = "({path, rev?, session_path}) -> {session_path, url, size, result=file metadata}. A PDF preview of documents or an HTML preview of spreadsheets."},
	getThumbnail = {route = "files/get_thumbnail", read = true, style = "download",
		help = "({path, format?='jpeg'|'png'|'webp', size?='w64h64'|'w256h256'|...|'w2048h1536', mode?, session_path}) -> {session_path, url, size, result=file metadata}. Images only; defaults to a 64x64 JPEG."},
	createFolder = {route = "files/create_folder_v2", read = false, help = "({path, autorename?}) -> {metadata}."},
	upload = {route = "files/upload", read = false, style = "upload",
		help = "({path, session_path, mode?='add'|'overwrite'|{['.tag']='update', update=rev}, autorename?, mute?}) -> file metadata. Sends a session file of at most 150 MiB; the default mode 'add' never replaces an existing file."},
	saveUrl = {route = "files/save_url", read = false,
		help = "({path, url}) -> {['.tag']='async_job_id'|'complete', ...}. Dropbox downloads a public URL into path within 15 minutes; poll saveUrlCheckJobStatus."},
	saveUrlCheckJobStatus = {route = "files/save_url/check_job_status", read = false, help = job("saveUrl")},
	move = {route = "files/move_v2", read = false, help = "({from_path, to_path, autorename?}) -> {metadata}. Moves or renames a file or folder."},
	copy = {route = "files/copy_v2", read = false, help = "({from_path, to_path, autorename?}) -> {metadata}."},
	delete = {route = "files/delete_v2", read = false,
		help = "({path, parent_rev?}) -> {metadata}. Deleted files stay recoverable with restore for the account's retention period."},
	restore = {route = "files/restore", read = false, help = "({path, rev}) -> file metadata. Restores a deleted file or an earlier revision from listRevisions."},
	moveBatch = {route = "files/move_batch_v2", read = false,
		help = "({entries={{from_path, to_path}, ...}, autorename?}) -> {['.tag']='async_job_id'|'complete', ...}. Up to 1,000 entries; poll moveBatchCheck."},
	moveBatchCheck = {route = "files/move_batch/check_v2", read = false, help = job("moveBatch", "'in_progress'|'complete'") .. ENTRIES},
	copyBatch = {route = "files/copy_batch_v2", read = false,
		help = "({entries={{from_path, to_path}, ...}, autorename?}) -> {['.tag']='async_job_id'|'complete', ...}. Up to 1,000 entries; poll copyBatchCheck."},
	copyBatchCheck = {route = "files/copy_batch/check_v2", read = false, help = job("copyBatch", "'in_progress'|'complete'") .. ENTRIES},
	deleteBatch = {route = "files/delete_batch", read = false,
		help = "({entries={{path}, ...}}) -> {['.tag']='async_job_id'|'complete', ...}. Up to 1,000 entries; poll deleteBatchCheck."},
	deleteBatchCheck = {route = "files/delete_batch/check", read = false, help = job("deleteBatch") .. ENTRIES},

	-- Shared links
	listSharedLinks = {route = "sharing/list_shared_links", read = true,
		help = "({path?, cursor?, direct_only?}) -> {links, has_more, cursor?}. Without path, every link the account created; pass cursor back for the next page."},
	getSharedLinkMetadata = {route = "sharing/get_shared_link_metadata", read = true, help = "({url, path?, link_password?}) -> link metadata. path selects an item inside a shared folder link."},
	getSharedLinkFile = {route = "sharing/get_shared_link_file", read = true, style = "download",
		help = "({url, path?, link_password?, session_path}) -> {session_path, url, size, result=link metadata}. Downloads a file behind a shared link, including links from other accounts."},
	createSharedLinkWithSettings = {route = "sharing/create_shared_link_with_settings", read = false,
		help = "({path, settings?={requested_visibility?, audience?, access?, expires?, link_password?, allow_download?}}) -> link metadata. Fails with shared_link_already_exists when a link exists; use listSharedLinks({path, direct_only=true})."},
	modifySharedLinkSettings = {route = "sharing/modify_shared_link_settings", read = false, help = "({url, settings, remove_expiration?}) -> link metadata."},
	revokeSharedLink = {route = "sharing/revoke_shared_link", read = false, help = "({url}) -> {success=true}."},

	-- Shared folders
	listSharedFolders = {route = "sharing/list_folders", read = true, help = "({limit?}) -> {entries, cursor?}. Shared folders the account has joined."},
	listSharedFoldersContinue = {route = "sharing/list_folders/continue", read = true, help = CURSOR},
	listMountableFolders = {route = "sharing/list_mountable_folders", read = true, help = "({limit?}) -> {entries, cursor?}. Shared folders the account can add to its Dropbox."},
	listMountableFoldersContinue = {route = "sharing/list_mountable_folders/continue", read = true, help = CURSOR},
	getSharedFolderMetadata = {route = "sharing/get_folder_metadata", read = true,
		help = "({shared_folder_id}) -> shared folder metadata. The ID is a folder's shared_folder_id or sharing_info.shared_folder_id."},
	listFolderMembers = {route = "sharing/list_folder_members", read = true, help = "({shared_folder_id, limit?}) -> {users, groups, invitees, cursor?}."},
	listFolderMembersContinue = {route = "sharing/list_folder_members/continue", read = true, help = CURSOR},
	shareFolder = {route = "sharing/share_folder", read = false,
		help = "({path, member_policy?, acl_update_policy?, shared_link_policy?, force_async?}) -> {['.tag']='complete', ...} or {['.tag']='async_job_id', ...}; poll checkShareJobStatus."},
	checkShareJobStatus = {route = "sharing/check_share_job_status", read = false, help = job("shareFolder")},
	addFolderMember = {route = "sharing/add_folder_member", read = false,
		help = "({shared_folder_id, members={{member={['.tag']='email', email}, access_level?='editor'|'viewer'}, ...}, quiet?, custom_message?}) -> {success=true}. Dropbox emails new members unless quiet=true."},
	updateFolderMember = {route = "sharing/update_folder_member", read = false,
		help = "({shared_folder_id, member={['.tag']='email'|'dropbox_id', ...}, access_level}) -> member result."},
	removeFolderMember = {route = "sharing/remove_folder_member", read = false,
		help = "({shared_folder_id, member={['.tag']='email', email}, leave_a_copy}) -> {['.tag']='async_job_id', ...}; poll checkRemoveMemberJobStatus."},
	checkRemoveMemberJobStatus = {route = "sharing/check_remove_member_job_status", read = false, help = job("removeFolderMember")},
	unshareFolder = {route = "sharing/unshare_folder", read = false,
		help = "({shared_folder_id, leave_a_copy?}) -> {['.tag']='complete'} or {['.tag']='async_job_id', ...}; poll checkJobStatus."},
	checkJobStatus = {route = "sharing/check_job_status", read = false, help = job("unshareFolder and relinquishFolderMembership")},
	mountFolder = {route = "sharing/mount_folder", read = false, help = "({shared_folder_id}) -> shared folder metadata. Adds a shared folder to the account's Dropbox."},
	unmountFolder = {route = "sharing/unmount_folder", read = false, help = "({shared_folder_id}) -> {success=true}. Removes it from the account's Dropbox without leaving it."},
	relinquishFolderMembership = {route = "sharing/relinquish_folder_membership", read = false,
		help = "({shared_folder_id, leave_a_copy?}) -> {['.tag']='complete'} or {['.tag']='async_job_id', ...}. Leaves a shared folder; poll checkJobStatus."},

	-- Shared files
	listReceivedFiles = {route = "sharing/list_received_files", read = true, help = "({limit?}) -> {entries, cursor?}. Files others shared with the account."},
	listReceivedFilesContinue = {route = "sharing/list_received_files/continue", read = true, help = CURSOR},
	getSharedFileMetadata = {route = "sharing/get_file_metadata", read = true, help = "({file}) -> shared file metadata. file is a path or 'id:...'."},
	listFileMembers = {route = "sharing/list_file_members", read = true, help = "({file, include_inherited?, limit?}) -> {users, groups, invitees, cursor?}."},
	listFileMembersContinue = {route = "sharing/list_file_members/continue", read = true, help = CURSOR},
	addFileMember = {route = "sharing/add_file_member", read = false,
		help = "({file, members={{['.tag']='email', email}, ...}, access_level?, quiet?, custom_message?}) -> one result per member. Dropbox emails them unless quiet=true."},
	removeFileMember = {route = "sharing/remove_file_member_2", read = false, help = "({file, member={['.tag']='email', email}}) -> {['.tag']='success'|'member_error', ...}."},
	unshareFile = {route = "sharing/unshare_file", read = false, help = "({file}) -> {success=true}. Removes every member."},
	relinquishFileMembership = {route = "sharing/relinquish_file_membership", read = false, help = "({file}) -> {success=true}. Leaves a file shared with the account."},

	-- File requests
	listFileRequests = {route = "file_requests/list_v2", read = true, help = "({limit?}) -> {file_requests, cursor, has_more}."},
	listFileRequestsContinue = {route = "file_requests/list/continue", read = true, help = CURSOR},
	getFileRequest = {route = "file_requests/get", read = true, help = "({id}) -> file request."},
	createFileRequest = {route = "file_requests/create", read = false,
		help = "({title, destination, deadline?={deadline, allow_late_uploads?}, open?, description?}) -> file request with its url. Anyone with the url can upload into destination."},
	updateFileRequest = {route = "file_requests/update", read = false, help = "({id, title?, destination?, deadline?={['.tag']='update', deadline?, allow_late_uploads?}|'no_update', open?, description?}) -> file request. open=false closes it; deadline={['.tag']='update'} alone clears the deadline."},
	deleteFileRequest = {route = "file_requests/delete", read = false, help = "({ids={id, ...}}) -> {file_requests}. Only closed requests can be deleted."},
}

local exports: {[string]: any} = {}
local help: {[string]: string} = {}

-- Exposes an operation when it only reads or the connection allows writes.
local function export(name: string, isRead: boolean, fn: (...any) -> any, doc: string)
	if isRead or config.access == "read-write" then
		exports[name], help[name] = fn, doc
	end
end

for name, endpoint in endpoints do
	local call: (string, Endpoint, any) -> any = if endpoint.style == "download" then download elseif endpoint.style == "upload" then upload else rpc
	export(name, endpoint.read, function(args: Options?): any return call(name, endpoint, args) end,
		name .. endpoint.help .. " [" .. endpoint.route .. "]")
end

-- Fixed-signature file lookup shared with other storage connectors.
export("statFile", true, function(...: any): {id: string, name: string, isFolder: boolean, size: number?}
	assert(select("#", ...) == 1, "statFile takes exactly one file ID or path")
	local file = rpc("statFile", endpoints.getMetadata, {path = text((...), "file ID")})
	local isFolder = file[".tag"] == "folder"
	local size = if isFolder then nil else file.size
	if type(file.id) ~= "string" or file.id == "" or type(file.name) ~= "string"
		or (not isFolder and (type(size) ~= "number" or size < 0 or size % 1 ~= 0 or size > MAX_SAFE_INTEGER)) then
		houston.fail({operation = "statFile", layer = "upstream", retryable = false, message = "Dropbox returned invalid file metadata"})
	end
	return {id = file.id, name = file.name, isFolder = isFolder, size = size}
end, "statFile(id) -> {id, name, isFolder, size?}. One positional 'id:...' or path; size is absent for folders.")

exports.help = function(): string
	local names: {string} = {}
	for name in help do table.insert(names, name) end
	table.sort(names)
	local lines = {
		"Dropbox API v2. Each operation takes one options table with Dropbox's snake_case arguments, calls the route in brackets and returns Dropbox's JSON unchanged; routes without a result return {success=true}. Read-only connections omit changes.",
		"Every argument and result is documented by route under User endpoints at https://docs.dropboxapi.com/dropbox-api/api-reference/overview. Union values are a tag string or a table, e.g. mode='overwrite' or mode={['.tag']='update', update='<rev>'}.",
		"Paths start with '/', are case-insensitive and use '' for the root folder (not '/'). Most routes also accept 'id:...' from metadata, and 'ns:<namespace_id>/...' reaches a team space.",
		"Lists return one page. While has_more is true, or a sharing list returns a cursor, pass cursor to the matching ...Continue operation; listSharedLinks takes its cursor back and listRevisions pages with before_rev.",
		"Files move through session paths: downloads save to session_path and return {session_path, url, size, result}, where url is a signed Houston link and result is Dropbox's metadata; upload reads session_path. Never inline file bytes. A transfer must finish within the call's time limit and stops at Houston's 256 MiB file limit; upload also stops at Dropbox's 150 MiB single-request limit.",
		"No hidden paging, polling or retries. Batch, URL-saving and sharing jobs may return an async_job_id: poll the status operation their help names. Errors report the HTTP status and Dropbox's error_summary, e.g. 'Dropbox HTTP 409: path/not_found/..'. A failed or timed-out change may already have happened; check before repeating.",
		"Connector calls return completed values; do not await them. Example: local page = dropbox.listFolder({path='/Reports', limit=100}); local file = dropbox.download({path=page.entries[1].path_lower, session_path='report.pdf'}); return file.url.",
	}
	for _, name in names do table.insert(lines, help[name]) end
	return table.concat(lines, "\n")
end
return exports
