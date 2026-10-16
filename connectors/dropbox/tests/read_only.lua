return {
	scenario = {config = {own_app = true, client_id = "fixture-app-key", client_secret = "fixture-private-secret"}, auth_method = "own_app", auth_config = {}},
	config = {access = "read-only"},
	run = function(c)
		local reads = {}
		for _, name in {
			"getCurrentAccount", "getSpaceUsage", "getAccount", "statFile",
			"getMetadata", "listFolder", "listFolderContinue", "listFolderGetLatestCursor", "search", "searchContinue", "listRevisions",
			"getTemporaryLink", "download", "downloadZip", "export", "getPreview", "getThumbnail",
			"listSharedLinks", "getSharedLinkMetadata", "getSharedLinkFile",
			"listSharedFolders", "listSharedFoldersContinue", "listMountableFolders", "listMountableFoldersContinue",
			"getSharedFolderMetadata", "listFolderMembers", "listFolderMembersContinue",
			"listReceivedFiles", "listReceivedFilesContinue", "getSharedFileMetadata", "listFileMembers", "listFileMembersContinue",
			"listFileRequests", "listFileRequestsContinue", "getFileRequest",
		} do
			reads[name] = true
			assert(type(c[name]) == "function", "read-only lacks " .. name)
		end
		for name in c do
			assert(name == "help" or reads[name], "read-only exposes " .. name)
		end
	end,
}
