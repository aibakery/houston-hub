-- Read-write connections add the changes; trash is a move to the trash role.
return {
	scenario = {publisher = {}, auth_method = "", auth_config = {}, config = {host = "imap.example.com", port = 1993, username = "ada@example.com", password = "fixture-password"}},
	config = {access = "read-write"},
	configure = function()
		requests = {}
		imap = {command = function(request)
			table.insert(requests, request)
			return fixture.operation({command = request.command})
		end}
	end,
	run = function(c)
		assert(c.setFlags({ids = {"7:42:INBOX"}, add = {"\\Seen"}}).command == "store")
		assert(requests[1].add[1] == "\\Seen" and requests[1].ids[1] == "7:42:INBOX")
		assert(c.moveMessages({ids = {"7:42:INBOX"}, folder = "archive"}).command == "move" and requests[2].folder == "archive")
		assert(c.trashMessages({ids = {"7:42:INBOX"}}).command == "move" and requests[3].folder == "trash")
		assert(not pcall(c.trashMessages, {ids = {"7:42:INBOX"}, folder = "Archive"}), "trash cannot target another folder")
		assert(c.createFolder({name = "Receipts", parent = "INBOX"}).command == "create" and requests[4].parent == "INBOX")
		assert(#requests == 4)
		assert(c.setFlags({ids = {"7:42:INBOX"}, remove = {"\\Seen"}}).command == "store")
		assert(requests[5].remove[1] == "\\Seen" and requests[5].ids[1] == "7:42:INBOX" and requests[5].add == nil)
		assert(#requests == 5)
	end,
}
