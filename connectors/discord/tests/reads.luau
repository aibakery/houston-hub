return {
	scenario = {publisher = {client_id = "fixture-client", client_secret = "fixture-private-secret", bot_token = "fixture-bot-token"},
		config = {}, auth_method = "oauth", auth_config = {}, granted_scopes = {"bot"}, facts = {guild_id = "290926798626357999"}},
	config = {access = "read-only"},
	configure = function()
		requests, responses = {}, {}
		http = {request = function(req)
			table.insert(requests, req)
			assert(#responses > 0, "unexpected request: " .. req.url)
			local response = table.remove(responses, 1)
			if type(response) == "string" then response = {body = response} end
			return fixture.operation({statusCode = response.status or 200, headers = {}, body = fixture.reader(response.body)})
		end}
		API = "https://discord.com/api/v10/"
		G, C, T, M, U = "290926798626357999", "1300000000000000001", "1300000000000000002", "1400000000000000001", "80351110224678912"
		CHANNEL = '{"id":"' .. C .. '","type":0,"guild_id":"' .. G .. '","name":"general"}'
		function sent(index)
			local req = requests[index or #requests]
			assert(req.method == "GET" and req.body == nil, "reads send GET without a body")
			assert(req.headers["User-Agent"][1] == "DiscordBot (https://ok-houston.com, 1.0)", "Discord's bot User-Agent")
			assert(req.headers.Authorization == nil, "credentials stay in the proxy")
			return req.url
		end
		function rejected(fn, ...)
			local before = #requests
			local ok, err = pcall(fn, ...)
			assert(not ok and #requests == before, "invalid input reached Discord")
			return tostring(err)
		end
	end,
	run = function(discord)
		responses = {'{"id":"' .. G .. '","name":"Fixture"}', '{"id":"' .. G .. '","approximate_member_count":3}'}
		assert(discord.getServer().name == "Fixture" and sent() == API .. "guilds/" .. G)
		assert(discord.getServer({with_counts = true}).approximate_member_count == 3 and sent() == API .. "guilds/" .. G .. "?with_counts=true")

		responses = {"[]", '[' .. CHANNEL .. ',{"id":"1300000000000000003","type":4,"guild_id":"' .. G .. '","name":"Info"}]'}
		assert(json.encode(discord.listChannels()) == "[]" and sent() == API .. "guilds/" .. G .. "/channels")
		local channels = discord.listChannels()
		assert(#channels == 2 and channels[2].type == 4)

		responses = {CHANNEL}
		local before = #requests
		assert(discord.getChannel(C).name == "general" and #requests == before + 1 and sent() == API .. "channels/" .. C)

		responses = {CHANNEL, "[]"}
		assert(json.encode(discord.listMessages(C)) == "[]")
		assert(sent(#requests - 1) == API .. "channels/" .. C, "the channel is checked first")
		assert(sent() == API .. "channels/" .. C .. "/messages?limit=25")
		local opts = {before = M, limit = 100}
		responses = {CHANNEL, '[{"id":"1399999999999999999","channel_id":"' .. C .. '","content":"hi"}]'}
		local messages = discord.listMessages(C, opts)
		assert(#messages == 1 and messages[1].content == "hi" and opts.limit == 100 and opts.after == nil, "options are not mutated")
		assert(sent() == API .. "channels/" .. C .. "/messages?before=" .. M .. "&limit=100")

		responses = {CHANNEL, '{"id":"' .. M .. '","channel_id":"' .. C .. '","content":"hello","reactions":[]}'}
		assert(discord.getMessage(C, M).content == "hello" and sent() == API .. "channels/" .. C .. "/messages/" .. M)

		local thread = '{"id":"' .. T .. '","type":11,"guild_id":"' .. G .. '","parent_id":"' .. C .. '"}'
		responses = {'{"threads":[],"members":[]}', '{"threads":[' .. thread .. '],"members":[]}'}
		local active = discord.listThreads()
		assert(json.encode(active.threads) == "[]" and sent() == API .. "guilds/" .. G .. "/threads/active")
		assert(discord.listThreads().threads[1].parent_id == C)
		responses = {thread, '[]'}
		assert(json.encode(discord.listMessages(T, {after = M, limit = 1})) == "[]", "threads are channels")
		assert(sent() == API .. "channels/" .. T .. "/messages?after=" .. M .. "&limit=1")

		responses = {CHANNEL, '{"threads":[],"members":[],"has_more":false}', CHANNEL, '{"threads":[' .. thread .. '],"members":[],"has_more":true}'}
		assert(discord.listArchivedThreads(C).has_more == false and sent() == API .. "channels/" .. C .. "/threads/archived/public?limit=25")
		assert(discord.listArchivedThreads(C, {before = "2026-01-31T12:00:00.000000+00:00", limit = 2}).has_more)
		assert(sent() == API .. "channels/" .. C .. "/threads/archived/public?before=2026-01-31T12%3A00%3A00.000000%2B00%3A00&limit=2")

		responses = {'{"total_results":0,"messages":[],"doing_deep_historical_index":false}',
			'{"total_results":1,"messages":[[{"id":"' .. M .. '","content":"deploy done"}]],"doing_deep_historical_index":false}'}
		assert(discord.searchMessages("deploy").total_results == 0 and sent() == API .. "guilds/" .. G .. "/messages/search?content=deploy")
		local found = discord.searchMessages("", {channel_id = {C, T}, author_id = U, author_type = {"-bot"}, has = {"link"},
			sort_by = "relevance", limit = 5, offset = 5, pinned = false})
		assert(found.messages[1][1].content == "deploy done")
		assert(sent() == API .. "guilds/" .. G .. "/messages/search?author_id=" .. U .. "&author_type=-bot&channel_id=" .. C
			.. "&channel_id=" .. T .. "&has=link&limit=5&offset=5&pinned=false&sort_by=relevance")

		responses = {"[]", '[{"user":{"id":"' .. U .. '","username":"ana"},"nick":"Ana","roles":[]}]', '{"user":{"id":"' .. U .. '"},"roles":["1"]}'}
		assert(json.encode(discord.searchMembers("zz")) == "[]" and sent() == API .. "guilds/" .. G .. "/members/search?limit=25&query=zz")
		assert(discord.searchMembers("an a", {limit = 1000})[1].nick == "Ana")
		assert(sent() == API .. "guilds/" .. G .. "/members/search?limit=1000&query=an%20a")
		assert(discord.getMember(U).user.id == U and sent() == API .. "guilds/" .. G .. "/members/" .. U)

		responses = {"[]", '[{"id":"' .. G .. '","name":"@everyone"}]'}
		assert(json.encode(discord.listRoles()) == "[]" and sent() == API .. "guilds/" .. G .. "/roles")
		assert(discord.listRoles()[1].name == "@everyone")

		assert(string.find(rejected(discord.getChannel, 1300000000000000001), "must be a Discord ID string", 1, true))
		rejected(discord.getChannel, "../users/@me")
		rejected(discord.getChannel, "0123")
		rejected(discord.getChannel, "18446744073709551616")
		rejected(discord.getMember, "@me")
		rejected(discord.getMessage, C, "1.5")
		assert(string.find(rejected(discord.listMessages, C, {before = M, after = M}), "only one of before", 1, true))
		rejected(discord.listMessages, C, {limit = 0})
		rejected(discord.listMessages, C, {limit = 101})
		rejected(discord.listMessages, C, {limit = 0 / 0})
		assert(string.find(rejected(discord.listMessages, C, {cursor = "x"}), "unknown option cursor", 1, true))
		rejected(discord.listArchivedThreads, C, {limit = 1})
		rejected(discord.listArchivedThreads, C, {before = "yesterday"})
		rejected(discord.getServer, {with_counts = "yes"})
		rejected(discord.searchMessages, string.rep("x", 1025))
		rejected(discord.searchMessages, "x", {limit = 26})
		rejected(discord.searchMessages, "x", {offset = 9976})
		rejected(discord.searchMessages, "x", {channel_id = {}})
		rejected(discord.searchMessages, "x", {has = {"links"}})
		rejected(discord.searchMessages, "x", {guild_id = "1"})
		rejected(discord.searchMembers, "")
		rejected(discord.searchMembers, string.rep("x", 101))
		rejected(discord.searchMembers, "ana", {limit = 1001})
	end,
}
