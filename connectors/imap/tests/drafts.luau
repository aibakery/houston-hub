-- Drafts forward one draft or discard command; attachments flatten into parallel lists.
return {
	scenario = {publisher = {}, auth_method = "", auth_config = {}, config = {host = "imap.example.com", username = "ada@example.com", password = "fixture-password"}},
	config = {access = "read-write"},
	configure = function()
		requests = {}
		imap = {command = function(request)
			table.insert(requests, request)
			if request.command == "discard" then return fixture.operation({folder = "Trash", ids = {"9:5:Trash"}}) end
			return fixture.operation({id = "3:" .. #requests .. ":Drafts", folder = "Drafts", messageId = "abc@example.com"})
		end}
	end,
	run = function(c)
		local saved = fixture.example("createDraft")
		assert(saved.id == "3:1:Drafts" and saved.folder == "Drafts" and saved.messageId == "abc@example.com", json.encode(saved))
		local first = requests[1]
		assert(first.command == "draft" and first.to == "Grace <grace@example.com>" and first.cc[2] == "b@example.com" and first.html == "<p>Hi</p>" and first.body == "Hi" and first.text == nil)
		assert(first.attachments == nil and first.replace == nil and first.id == nil)
		assert(json.encode(first.attachmentPaths) == '["files/report.pdf","files/notes"]', json.encode(first.attachmentPaths))
		assert(json.encode(first.attachmentNames) == '["","notes.txt"]' and json.encode(first.attachmentTypes) == '["","text/plain"]')

		fixture.example("createDraft", 2)
		assert(requests[2].inReplyTo == "7:42:INBOX" and requests[2].replyAll == true and json.encode(requests[2].attachmentPaths) == "[]")
		fixture.example("createDraft", 3)
		assert(requests[3].command == "draft" and requests[3].attachmentPaths == nil)

		for _, rejected in {
			{id = "3:1:Drafts"}, {replace = "3:1:Drafts"}, {attachmentPaths = {"x"}}, {send = true}, {text = 42},
			{attachments = {path = "files/a", filename = "a.txt"}},
			{attachments = {{path = "files/a", size = 3}}}, {attachments = {{filename = "a.txt"}}}, {attachments = "files/a"},
		} do
			assert(not pcall(c.createDraft, rejected), json.encode(rejected))
		end
		assert(#requests == 3, "rejected drafts never reach the server")

		local updated = fixture.example("updateDraft")
		assert(updated.id == "3:4:Drafts" and requests[4].replace == "3:1:Drafts" and requests[4].id == nil and requests[4].subject == "Hello again")
		assert(not pcall(c.updateDraft, {subject = "no id"}) and not pcall(c.updateDraft, {id = "3:1:Drafts", replace = "3:2:Drafts"}))
		assert(#requests == 4, "rejected updates never reach the server")

		local discarded = fixture.example("deleteDraft")
		assert(requests[5].command == "discard" and #requests[5].ids == 1 and requests[5].ids[1] == "3:4:Drafts")
		assert(discarded.folder == "Trash" and discarded.ids[1] == "9:5:Trash", json.encode(discarded))
		assert(not pcall(c.deleteDraft, {id = "3:4:Drafts", folder = "Archive"}) and not pcall(c.deleteDraft, {ids = {"3:4:Drafts"}}))
		assert(#requests == 5, "rejected deletes never reach the server")
	end,
}
