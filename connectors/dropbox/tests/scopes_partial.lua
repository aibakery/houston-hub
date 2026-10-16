return {
	scenario = {publisher = {client_id = "fixture-app-key", client_secret = "fixture-private-secret"}, auth_method = "oauth", granted_scopes = {"files.metadata.read","sharing.read","files.content.write",}},
	config = {access = "read-write"},
	run = function(c)
		local expected = {}
		expected.getAccount = true
		expected.getMetadata = true
		expected.listFolder = true
		expected.listFolderContinue = true
		expected.listFolderGetLatestCursor = true
		expected.search = true
		expected.searchContinue = true
		expected.listRevisions = true
		expected.createFolder = true
		expected.upload = true
		expected.saveUrl = true
		expected.saveUrlCheckJobStatus = true
		expected.move = true
		expected.copy = true
		expected.delete = true
		expected.restore = true
		expected.moveBatch = true
		expected.moveBatchCheck = true
		expected.copyBatch = true
		expected.copyBatchCheck = true
		expected.deleteBatch = true
		expected.deleteBatchCheck = true
		expected.listSharedLinks = true
		expected.getSharedLinkMetadata = true
		expected.getSharedLinkFile = true
		expected.listSharedFolders = true
		expected.listSharedFoldersContinue = true
		expected.listMountableFolders = true
		expected.listMountableFoldersContinue = true
		expected.getSharedFolderMetadata = true
		expected.listFolderMembers = true
		expected.listFolderMembersContinue = true
		expected.listReceivedFiles = true
		expected.listReceivedFilesContinue = true
		expected.getSharedFileMetadata = true
		expected.listFileMembers = true
		expected.listFileMembersContinue = true
		expected.statFile = true
		for name in expected do assert(type(c[name]) == "function", "missing permitted export: " .. name) end
		for name in c do assert(name == "help" or expected[name], "unexpected export: " .. name) end
	end,
}
