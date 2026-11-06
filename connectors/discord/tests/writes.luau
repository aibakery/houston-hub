return {
	scenario = {publisher = {client_id = "fixture-client", client_secret = "fixture-private-secret", bot_token = "fixture-bot-token"},
		config = {}, auth_method = "oauth", auth_config = {}, granted_scopes = {"bot"}, facts = {guild_id = "290926798626357999"}},
	config = {access = "read-write"},
	configure = function()
		requests, responses = {}, {}
		http = {request = function(req)
			table.insert(requests, req)
			assert(#responses > 0, "unexpected request: " .. req.url)
			local response = table.remove(responses, 1)
			if type(response) == "string" then response = {body = response} end
			return fixture.operation({statusCode = response.status or 200, headers = {}, body = fixture.reader(response.body or "")})
		end}
		API = "https://discord.com/api/v10/"
		G, C, A, F, M, U, R = "290926798626357999", "1300000000000000001", "1300000000000000005", "1300000000000000006",
			"1400000000000000001", "80351110224678912", "1500000000000000001"
		CHANNEL = '{"id":"' .. C .. '","type":0,"guild_id":"' .. G .. '","name":"general"}'
		POSTED = '{"id":"1400000000000000009","channel_id":"' .. C .. '","content":"Hi"}'
		function sent(index, method, path)
			local req = requests[index]
			assert(requests[index - 1].method == "GET" and requests[index - 1].url == API .. "channels/" .. string.match(path, "^channels/(%d+)"),
				"the channel is checked before " .. method)
			assert(req.method == method and req.url == API .. path, "unexpected " .. req.method .. " " .. req.url)
			assert(req.headers["User-Agent"][1] == "DiscordBot (https://ok-houston.com, 1.0)" and req.headers.Authorization == nil)
			if req.body == nil then return nil end
			assert(req.headers["Content-Type"][1] == "application/json")
			return json.decode(req.body)
		end
		function silent(body)
			assert(json.encode(body.allowed_mentions.parse) == "[]", "mentions notify nobody by default")
		end
		function rejected(fn, ...)
			local before = #requests
			local ok, err = pcall(fn, ...)
			assert(not ok and #requests == before, "invalid input reached Discord")
			return tostring(err)
		end
	end,
	run = function(discord)
		for _, name in {"postMessage", "reply", "editMessage", "deleteMessage", "addReaction", "removeReaction", "createThread"} do
			assert(type(discord[name]) == "function", name .. " is exported with read-write access")
		end

		responses = {CHANNEL, POSTED}
		assert(fixture.example("postMessage").id == "1400000000000000009")
		local body = sent(2, "POST", "channels/" .. C .. "/messages")
		assert(body.content == "Hi @everyone" and body.message_reference == nil and body.users == nil)
		silent(body)
		assert(body.allowed_mentions.users == nil and body.allowed_mentions.roles == nil)

		local opts = {allowed_mentions = {users = {U}, roles = R, replied_user = true}, embeds = {{title = "Q3", url = "https://example.com"}},
			flags = 4096, nonce = "run-42", enforce_nonce = true}
		responses = {CHANNEL, POSTED}
		discord.reply(C, M, "<@" .. U .. "> done", opts)
		body = sent(4, "POST", "channels/" .. C .. "/messages")
		assert(body.message_reference.message_id == M and body.content == "<@" .. U .. "> done")
		silent(body)
		assert(body.allowed_mentions.users[1] == U and body.allowed_mentions.roles[1] == R and body.allowed_mentions.replied_user == true)
		assert(body.embeds[1].title == "Q3" and body.flags == 4096 and body.nonce == "run-42" and body.enforce_nonce == true)
		assert(opts.content == nil and opts.message_reference == nil and opts.allowed_mentions.parse == nil, "options are not mutated")

		responses = {CHANNEL, POSTED}
		fixture.example("editMessage")
		body = sent(6, "PATCH", "channels/" .. C .. "/messages/" .. M)
		assert(body.content == "Edited" and body.flags == 4)
		silent(body)

		responses = {CHANNEL, {status = 204}}
		assert(fixture.example("deleteMessage") == true)
		assert(sent(8, "DELETE", "channels/" .. C .. "/messages/" .. M) == nil)

		responses = {CHANNEL, {status = 204}, CHANNEL, {status = 204}, CHANNEL, {status = 204}, CHANNEL, {status = 204}}
		assert(fixture.example("addReaction") == true)
		sent(10, "PUT", "channels/" .. C .. "/messages/" .. M .. "/reactions/%F0%9F%91%8D/@me")
		discord.addReaction(C, M, "<a:party_blob:1600000000000000001>")
		sent(12, "PUT", "channels/" .. C .. "/messages/" .. M .. "/reactions/party_blob%3A1600000000000000001/@me")
		fixture.example("removeReaction")
		sent(14, "DELETE", "channels/" .. C .. "/messages/" .. M .. "/reactions/houston%3A1600000000000000002/@me")
		discord.removeReaction(C, M, "1️⃣")
		sent(16, "DELETE", "channels/" .. C .. "/messages/" .. M .. "/reactions/1%EF%B8%8F%E2%83%A3/@me")

		local thread = '{"id":"1300000000000000007","type":11,"guild_id":"' .. G .. '","parent_id":"' .. C .. '","name":"Plan"}'
		responses = {CHANNEL, {status = 201, body = thread}}
		assert(fixture.example("createThread").id == "1300000000000000007")
		body = sent(18, "POST", "channels/" .. C .. "/threads")
		assert(body.name == "Plan" and body.type == 11, "a thread without a message is public")
		responses = {'{"id":"' .. A .. '","type":5,"guild_id":"' .. G .. '"}', {status = 201, body = thread}}
		discord.createThread(A, "News", {auto_archive_duration = 1440})
		body = sent(20, "POST", "channels/" .. A .. "/threads")
		assert(body.type == 10 and body.auto_archive_duration == 1440, "announcement channels get announcement threads")
		responses = {CHANNEL, {status = 201, body = thread}}
		fixture.example("createThread", 2)
		body = sent(22, "POST", "channels/" .. C .. "/messages/" .. M .. "/threads")
		assert(body.name == "Follow-up" and body.rate_limit_per_user == 30 and body.type == nil and body.message == nil)

		responses = {'{"id":"' .. F .. '","type":15,"guild_id":"' .. G .. '"}'}
		local ok, err = pcall(discord.createThread, F, "Post")
		assert(not ok and string.find(tostring(err), "text or announcement channel", 1, true) and #requests == 23, "forum posts are not created")

		rejected(discord.postMessage, C, "")
		assert(string.find(rejected(discord.postMessage, C, string.rep("é", 2001)), "at most 2000 characters", 1, true))
		responses = {CHANNEL, POSTED}
		discord.postMessage(C, string.rep("é", 2000), {flags = 4100})
		assert(utf8.len(sent(25, "POST", "channels/" .. C .. "/messages").content) == 2000, "Discord counts characters, not bytes")

		assert(string.find(rejected(discord.postMessage, C, "Hi", {allowed_mentions = {parse = {"everyone"}}}), "use users, roles or replied_user", 1, true))
		rejected(discord.postMessage, C, "Hi", {allowed_mentions = {users = {"@everyone"}}})
		rejected(discord.postMessage, C, "Hi", {flags = 8})
		rejected(discord.postMessage, C, "Hi", {nonce = string.rep("x", 26)})
		rejected(discord.postMessage, C, "Hi", {embeds = {{}, {}, {}, {}, {}, {}, {}, {}, {}, {}, {}}})
		rejected(discord.postMessage, C, "Hi", {tts = true})
		rejected(discord.postMessage, C, "Hi", {message_reference = {message_id = M}})
		rejected(discord.postMessage, 1300000000000000001, "Hi")
		rejected(discord.reply, C, "not-an-id", "Hi")
		rejected(discord.editMessage, C, M, "Edited", {flags = 4096})
		rejected(discord.deleteMessage, C, "")
		assert(string.find(rejected(discord.addReaction, C, M, "thumbsup"), "Unicode emoji", 1, true))
		rejected(discord.addReaction, C, M, ":thumbsup:")
		rejected(discord.addReaction, C, M, "a/b")
		rejected(discord.addReaction, C, M, "%F0%9F%91%8D")
		rejected(discord.addReaction, C, M, "")
		rejected(discord.addReaction, C, M, "..")
		rejected(discord.removeReaction, C, M, "name:../1")
		rejected(discord.createThread, C, "")
		rejected(discord.createThread, C, string.rep("x", 101))
		rejected(discord.createThread, C, "Plan", {auto_archive_duration = 30})
		rejected(discord.createThread, C, "Plan", {type = 12})
		rejected(discord.createThread, C, "Plan", {message = "x"})

		-- The documented reply maps positional arguments and nested mention options
		-- to the same payload as the independently checked caller-owned options above.
		responses = {CHANNEL, POSTED}
		fixture.example("reply")
		body = sent(#requests, "POST", "channels/" .. C .. "/messages")
		assert(body.content == "<@" .. U .. "> done" and body.message_reference.message_id == M)
		silent(body)
		assert(body.allowed_mentions.users[1] == U and body.allowed_mentions.roles[1] == R and body.allowed_mentions.replied_user == true)
		assert(body.embeds[1].title == "Q3" and body.flags == 4096 and body.nonce == "run-42" and body.enforce_nonce == true)
	end,
}
