return {
	scenario = {publisher = {client_id = "fixture-client", client_secret = "fixture-private-secret", bot_token = "fixture-bot-token"},
		config = {}, auth_method = "oauth", auth_config = {}, granted_scopes = {"bot"}, facts = {guild_id = "290926798626357999"}},
	config = {access = "read-write"},
	configure = function()
		requests, guard = {}, nil
		http = {request = function(req)
			table.insert(requests, req)
			assert(guard, "unexpected request: " .. req.url)
			local response = guard
			guard = nil
			return fixture.operation({statusCode = response[1], headers = {}, body = fixture.reader(response[2])})
		end}
	end,
	run = function(discord)
		local C, M, E = "1300000000000000001", "1400000000000000001", "1600000000000000001"
		local foreign = {200, '{"id":"' .. C .. '","type":0,"guild_id":"390926798626357000","name":"secret-plans","topic":"acquisition"}'}
		local thread = {200, '{"id":"' .. C .. '","type":11,"guild_id":"390926798626357000","parent_id":"1","name":"secret-thread"}'}
		local dm = {200, '{"id":"' .. C .. '","type":1,"recipients":[{"id":"80351110224678912","username":"ana"}],"last_message_id":"1"}'}
		local missing = {404, '{"message":"Unknown Channel","code":10003}'}
		local hidden = {403, '{"message":"Missing Access","code":50001}'}
		local unbound = {200, '{"id":"' .. C .. '","type":0,"name":"no-guild"}'}
		local calls = {
			function() return discord.getChannel(C) end,
			function() return discord.listMessages(C) end,
			function() return discord.getMessage(C, M) end,
			function() return discord.listArchivedThreads(C) end,
			function() return discord.postMessage(C, "Hi") end,
			function() return discord.reply(C, M, "Hi") end,
			function() return discord.editMessage(C, M, "Hi") end,
			function() return discord.deleteMessage(C, M) end,
			function() return discord.addReaction(C, M, "👍") end,
			function() return discord.removeReaction(C, M, "houston:" .. E) end,
			function() return discord.createThread(C, "Plan") end,
			function() return discord.createThread(C, "Plan", {message = M}) end,
		}
		for _, response in {foreign, thread, dm, missing, hidden, unbound} do
			for index, call in calls do
				guard = response
				local before = #requests
				local ok, err = pcall(call)
				local message = tostring(err)
				assert(not ok, "call " .. index .. " accepted a channel outside the server")
				assert(#requests == before + 1 and requests[#requests].method == "GET"
					and requests[#requests].url == "https://discord.com/api/v10/channels/" .. C, "call " .. index .. " sent more than the guard request")
				assert(string.find(message, "channel " .. C .. " is not in this server, or Houston's bot cannot view it", 1, true)
					and string.find(message, '"upstream_status":404', 1, true), "one generic error: " .. message)
				for _, leak in {"secret", "acquisition", "390926798626357000", "ana", "Unknown Channel", "Missing Access", "no-guild"} do
					assert(not string.find(message, leak, 1, true), "the foreign channel leaked " .. leak)
				end
			end
		end
	end,
}
