-- Read-write connections add the changes; trash is a move to the trash role.
return {
	scenario = {publisher = {}, auth_method = "", auth_config = {}, config = {host = "imap.example.com", port = 1993, username = "ada@example.com", password = "fixture-password"}},
	config = {access = "read-write"},
	configure = function()
		requests = {}
		imap = {command = function(request)
			table.insert(requests, request)
			if request.command == "store" then return fixture.operation({ids = request.ids}) end
			if request.command == "create" then return fixture.operation({id = request.parent .. "/" .. request.name, name = request.name}) end
			local moved: {string} = json.decode("[]")
			for i in request.ids do table.insert(moved, "9:" .. (100 + i) .. ":" .. request.folder) end
			return fixture.operation({folder = request.folder, ids = moved})
		end}
	end,
	run = function(c)
		local ids = {"7:42:INBOX", "7:43:INBOX"}
		local flagged = c.setFlags({ids = ids, add = {"\\Seen"}})
		assert(requests[1].command == "store" and requests[1].add[1] == "\\Seen" and #requests[1].ids == 2 and requests[1].ids[2] == "7:43:INBOX")
		assert(#flagged.ids == 2 and flagged.ids[2] == "7:43:INBOX", json.encode(flagged))

		local moved = c.moveMessages({ids = ids, folder = "archive"})
		assert(requests[2].command == "move" and requests[2].folder == "archive")
		assert(moved.folder == "archive" and #moved.ids == 2 and moved.ids[1] == "9:101:archive", json.encode(moved))

		local trashed = c.trashMessages({ids = {"7:42:INBOX"}})
		assert(requests[3].command == "move" and requests[3].folder == "trash")
		assert(trashed.folder == "trash" and #trashed.ids == 1 and trashed.ids[1] == "9:101:trash", json.encode(trashed))
		assert(not pcall(c.trashMessages, {ids = {"7:42:INBOX"}, folder = "Archive"}), "trash cannot target another folder")
		assert(#requests == 3, "rejected calls never reach the server")

		local folder = c.createFolder({name = "Receipts", parent = "INBOX"})
		assert(requests[4].command == "create" and requests[4].parent == "INBOX" and requests[4].name == "Receipts")
		assert(folder.id == "INBOX/Receipts" and folder.name == "Receipts", json.encode(folder))

		c.setFlags({ids = {"7:42:INBOX"}, remove = {"\\Seen"}})
		assert(requests[5].remove[1] == "\\Seen" and requests[5].ids[1] == "7:42:INBOX" and requests[5].add == nil)
		assert(#requests == 5)
	end,
}
