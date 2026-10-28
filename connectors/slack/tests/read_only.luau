return {
	scenario = {publisher = {client_id = "fixture-client", client_secret = "fixture-private-secret"}, config = {}, auth_method = "oauth", auth_config = {}},
	config = {access = "read-only"},
	configure = function()
		requests, responses = {}, {}
		http = {request = function(req)
			table.insert(requests, req)
			assert(#responses > 0, "unexpected request: " .. req.url)
			return fixture.operation({statusCode = 200, headers = {}, body = fixture.reader(table.remove(responses, 1))})
		end}
	end,
	run = function(slack)
		local names = {}
		for name, fn in slack do
			assert(type(fn) == "function")
			table.insert(names, name)
		end
		table.sort(names)
		assert(table.concat(names, ",") == "downloadFile,getChannel,getFile,getPermalink,getProfile,getThread,getUser,"
			.. "listChannels,listMembers,listMentions,listMessages,listUsers,searchMessages",
			"read-only exposes only reads: " .. table.concat(names, ","))

		responses = {'{"ok":true,"channels":[],"response_metadata":{"next_cursor":""}}'}
		local page = slack.listChannels()
		assert(json.encode(page.channels) == "[]" and page.nextCursor == nil)
		assert(requests[1].method == "GET" and requests[1].body == nil and requests[1].headers == nil, "credentials stay in the proxy")
		assert(requests[1].url == "https://slack.com/api/users.conversations?exclude_archived=true&types=public_channel%2Cprivate_channel%2Cim%2Cmpim")

		responses = {'{"ok":true,"channels":[{"id":"C1"},{"id":"D1"}],"response_metadata":{"next_cursor":"dGVhbTpDMDYx+/=="}}'}
		page = slack.listChannels({types = "im", exclude_archived = false, limit = 200})
		assert(#page.channels == 2 and page.nextCursor == "dGVhbTpDMDYx+/==")
		assert(requests[2].url == "https://slack.com/api/users.conversations?exclude_archived=false&limit=200&types=im")

		local ok, err = pcall(slack.listChannels, {user = "U_OTHER"})
		assert(not ok and string.find(tostring(err), "unknown option user", 1, true))
		assert(#requests == 2, "invalid input reached Slack")
	end,
}
