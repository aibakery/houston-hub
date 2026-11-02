return {
	scenario = {publisher = {client_id = "fixture-client", client_secret = "fixture-private-secret", bot_token = "fixture-bot-token"},
		config = {}, auth_method = "oauth", auth_config = {}, granted_scopes = {"bot"}, facts = {guild_id = "290926798626357999"}},
	config = {access = "read-write"},
	configure = function()
		calls, queue = 0, {}
		http = {request = function(req)
			calls += 1
			local response = table.remove(queue, 1)
			assert(response, "unexpected request: " .. req.url)
			return fixture.operation({statusCode = response[1], headers = response[3] or {}, body = fixture.reader(response[2])})
		end}
		C, M = "1300000000000000001", "1400000000000000001"
		CHANNEL = {200, '{"id":"' .. C .. '","type":0,"guild_id":"290926798626357999"}'}
	end,
	run = function(discord)
		-- Each case queues the exact responses; a retried call would find the queue empty.
		local function upstream(responses, expected, call)
			queue = responses
			local before, expectedCalls = calls, #responses
			local ok, err = pcall(call or function() discord.listRoles() end)
			for _, text in expected do
				assert(not ok and string.find(tostring(err), text, 1, true), "missing " .. text .. " in " .. tostring(err))
			end
			assert(calls == before + expectedCalls and #queue == 0, "failed call was retried or stopped early")
			return tostring(err)
		end
		local post = function() discord.postMessage(C, "Hi") end

		upstream({{401, '{"message":"401: Unauthorized","code":0}'}},
			{"Houston configuration problem", "reconnecting does not fix it", '"upstream_status":401', '"retryable":false'})
		upstream({{401, '{"message":"401: Unauthorized","code":0}'}}, {"Houston configuration problem"}, function() discord.getChannel(C) end)
		upstream({{403, '{"message":"Missing Access","code":50001}'}},
			{"Houston was removed from this Discord server; open the connection settings and add it again", '"upstream_status":403', '"retryable":false'})
		upstream({{404, '{"message":"Unknown Guild","code":10004}'}}, {"Houston was removed from this Discord server"},
			function() discord.searchMessages("x") end)
		upstream({{404, '{"message":"Unknown Member","code":10007}'}}, {"discord: Unknown Member (code 10007)", '"upstream_status":404'},
			function() discord.getMember("80351110224678912") end)
		upstream({CHANNEL, {403, '{"message":"Missing Permissions","code":50013}'}},
			{"lacks a Discord permission for this action (code 50013)", '"upstream_status":403', '"retryable":false'}, post)
		upstream({CHANNEL, {403, '{"message":"Missing Access","code":50001}'}}, {"discord: Missing Access (code 50001)"},
			function() discord.getMessage(C, M) end)
		upstream({CHANNEL, {400, '{"message":"Invalid Form Body","code":50035,"errors":{"embeds":{"0":{"title":{"_errors":[{"code":"BASE_TYPE_MAX_LENGTH","message":"Must be 256 or fewer in length."}]}}}}}'}},
			{"discord: Invalid Form Body (code 50035): embeds.0.title: Must be 256 or fewer in length.", '"upstream_status":400'}, post)
		upstream({{429, '{"message":"You are being rate limited.","retry_after":64.57,"global":false}', {["retry-after"] = {"65"}}}},
			{"rate limited.; retry after 65s", '"upstream_status":429', '"retryable":true'})
		upstream({{429, '{"message":"You are being rate limited.","retry_after":1.5,"global":true}'}}, {"retry after 2s", '"retryable":true'})
		upstream({CHANNEL, {429, '{"message":"You are being rate limited.","retry_after":3,"code":20028}'}},
			{"(code 20028); retry after 3s", '"retryable":true'}, post)
		upstream({{503, "<html>Service Unavailable</html>"}}, {"discord: HTTP 503", '"retryable":true'})
		upstream({CHANNEL, {502, "<html>Bad Gateway</html>"}}, {"discord: HTTP 502", '"retryable":false'}, post)
		upstream({CHANNEL, {500, '{"message":"500: Internal Server Error","code":0}'}}, {"Internal Server Error", '"retryable":false'},
			function() discord.deleteMessage(C, M) end)
		upstream({{202, '{"message":"Index not yet available. Try again later","code":110000,"documents_indexed":0,"retry_after":2}'}},
			{"still indexing this server for search; retry after 2s", '"upstream_status":202', '"retryable":true'},
			function() discord.searchMessages("deploy") end)
		upstream({{202, '{"message":"Index not yet available. Try again later","code":110000,"documents_indexed":0,"retry_after":0}'}},
			{"retry after a few seconds", '"retryable":true'}, function() discord.searchMessages("deploy") end)
		upstream({{200, "<html>Maintenance</html>"}}, {"discord: invalid JSON response", '"retryable":false'})
		upstream({{200, '"ok"'}}, {"discord: invalid JSON response"})
		local long = upstream({{400, '{"message":"' .. string.rep("x", 5000) .. '","code":50035}'}}, {"discord: HTTP 400"})
		assert(#long < 1000, "error messages stay bounded")
		long = upstream({{400, '{"message":"' .. string.rep("x", 3000) .. '","code":50035}'}}, {"discord: xxxx"})
		assert(#long < 1000, "error messages stay bounded")
	end,
}
