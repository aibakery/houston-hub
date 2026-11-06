-- Read and draft (custom) connections expose the reads and the draft operations, and no other change.
return {
	scenario = {publisher = {}, auth_method = "", auth_config = {}, config = {host = "imap.example.com", username = "ada@example.com", password = "fixture-password"}},
	config = {access = "custom"},
	configure = function()
		requests = {}
		imap = {command = function(request)
			table.insert(requests, request)
			if request.command == "discard" then return fixture.operation({folder = "Trash"}) end
			return fixture.operation({id = "3:1:Drafts", folder = "Drafts", messageId = "abc@example.com"})
		end}
	end,
	run = function(c)
		local names: {string} = {}
		for name in c do table.insert(names, name) end
		table.sort(names)
		assert(table.concat(names, ",") == "createDraft,deleteDraft,getAttachment,getMessage,getMessages,listMailFolders,listMessages,updateDraft", table.concat(names, ","))
		assert(c.createDraft({to = "grace@example.com", text = "Hi"}).id == "3:1:Drafts" and requests[1].command == "draft")
		assert(c.updateDraft({id = "3:1:Drafts", text = "Hello"}) ~= nil and requests[2].replace == "3:1:Drafts")
		assert(c.deleteDraft({id = "3:1:Drafts"}).folder == "Trash" and requests[3].command == "discard")
	end,
}
