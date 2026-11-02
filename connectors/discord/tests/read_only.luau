return {
	scenario = {publisher = {client_id = "fixture-client", client_secret = "fixture-private-secret", bot_token = "fixture-bot-token"},
		config = {}, auth_method = "oauth", auth_config = {}, granted_scopes = {"bot"}, facts = {guild_id = "290926798626357999"},
		caller_access = "read-only"},
	config = {access = "read-write"},
	configure = function()
		requests = {}
		http = {request = function(req)
			table.insert(requests, req)
			return fixture.operation({statusCode = 200, headers = {}, body = fixture.reader("[]")})
		end}
	end,
	run = function(discord)
		local names = {}
		for name, fn in discord do
			assert(type(fn) == "function")
			table.insert(names, name)
		end
		table.sort(names)
		assert(table.concat(names, ",") == "getChannel,getMember,getMessage,getServer,listArchivedThreads,listChannels,"
			.. "listMessages,listRoles,listThreads,searchMembers,searchMessages",
			"a read-only caller gets only reads: " .. table.concat(names, ","))
		assert(json.encode(discord.listRoles()) == "[]" and #requests == 1)
		assert(requests[1].url == "https://discord.com/api/v10/guilds/290926798626357999/roles")
	end,
}
