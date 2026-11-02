return {
	scenario = {publisher = {client_id = "fixture-client", client_secret = "fixture-private-secret", bot_token = "fixture-bot-token"},
		config = {}, auth_method = "oauth", auth_config = {}, granted_scopes = {"bot"}},
	config = {access = "read-write"},
	configure = function()
		http = {request = function(req) error("unexpected request: " .. req.url) end}
	end,
	run = function(discord)
		-- Without the server fact from the install, nothing can be addressed.
		local C, M = "1300000000000000001", "1400000000000000001"
		for _, call in {
			function() discord.getServer() end, function() discord.listChannels() end, function() discord.listRoles() end,
			function() discord.searchMessages("x") end, function() discord.getMember("80351110224678912") end,
			function() discord.getChannel(C) end, function() discord.listMessages(C) end, function() discord.postMessage(C, "Hi") end,
			function() discord.addReaction(C, M, "👍") end, function() discord.createThread(C, "Plan") end,
		} do
			local ok, err = pcall(call)
			assert(not ok and string.find(tostring(err), "not bound to a Discord server", 1, true), tostring(err))
		end
	end,
}
