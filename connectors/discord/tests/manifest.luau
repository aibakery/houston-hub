return {
	contract = function(m)
		-- TestDiscordBoundServerRoutes
		do
			if not (m.publisherClient(m.raw.auth["oauth"])) then
				m.fail("Discord OAuth client must belong to the publication")
			end
			local api, guild, other =
				"https://discord.com/api/v10", "290926798626357999", "390926798626357000"
			local read = {
				"GET " .. api .. "/guilds/" .. guild,
				"GET " .. api .. "/guilds/" .. guild .. "?with_counts=true",
				"GET " .. api .. "/guilds/" .. guild .. "/channels",
				"GET " .. api .. "/guilds/" .. guild .. "/threads/active",
				"GET " .. api .. "/guilds/" .. guild .. "/roles",
				"GET " .. api .. "/guilds/" .. guild .. "/members/search?query=a&limit=25",
				"GET " .. api .. "/guilds/" .. guild .. "/members/80351110224678912",
				"GET "
					.. api
					.. "/guilds/"
					.. guild
					.. "/messages/search?content=hi&channel_id=1&channel_id=2",
				"GET " .. api .. "/channels/1300000000000000001",
				"GET " .. api .. "/channels/1300000000000000001/messages?limit=25",
				"GET " .. api .. "/channels/1300000000000000001/messages/1400000000000000001",
				"GET " .. api .. "/channels/1300000000000000001/threads/archived/public?limit=25",
			}
			local writes = {
				"POST " .. api .. "/channels/1300000000000000001/messages",
				"PATCH " .. api .. "/channels/1300000000000000001/messages/1400000000000000001",
				"DELETE " .. api .. "/channels/1300000000000000001/messages/1400000000000000001",
				"PUT "
					.. api
					.. "/channels/1300000000000000001/messages/1400000000000000001/reactions/%F0%9F%91%8D/@me",
				"DELETE "
					.. api
					.. "/channels/1300000000000000001/messages/1400000000000000001/reactions/houston%3A1600000000000000001/@me",
				"POST " .. api .. "/channels/1300000000000000001/messages/1400000000000000001/threads",
				"POST " .. api .. "/channels/1300000000000000001/threads",
			}
			local denied = {
				"GET " .. api .. "/guilds/" .. other,
				"GET " .. api .. "/guilds/" .. other .. "/channels",
				"GET " .. api .. "/guilds/" .. other .. "/members/search?query=a",
				"GET " .. api .. "/guilds/" .. other .. "/messages/search?content=hi",
				"GET " .. api .. "/guilds/" .. guild .. "0/roles",
				"GET " .. api .. "/guilds/%7B%7Bauth.oauth.guild_id%7D%7D/roles",
				"GET " .. api .. "/guilds/{{auth.oauth.guild_id}}/roles",
				"GET " .. api .. "/users/@me/guilds",
				"DELETE " .. api .. "/users/@me/guilds/" .. guild,
				"GET " .. api .. "/users/@me",
				"POST " .. api .. "/users/@me/channels",
				"GET " .. api .. "/users/@me/channels",
				"GET " .. api .. "/guilds/" .. guild .. "/members?limit=1000",
				"PATCH " .. api .. "/guilds/" .. guild .. "/members/80351110224678912",
				"DELETE " .. api .. "/guilds/" .. guild .. "/members/80351110224678912",
				"PUT " .. api .. "/guilds/" .. guild .. "/bans/80351110224678912",
				"GET " .. api .. "/guilds/" .. guild .. "/webhooks",
				"POST " .. api .. "/channels/1300000000000000001/webhooks",
				"GET " .. api .. "/channels/1300000000000000001/invites",
				"PATCH " .. api .. "/channels/1300000000000000001",
				"DELETE " .. api .. "/channels/1300000000000000001",
				"DELETE " .. api .. "/channels/1300000000000000001/messages/1/reactions",
				"PUT " .. api .. "/channels/1300000000000000001/messages/1/reactions/x/80351110224678912",
				"POST " .. api .. "/channels/1300000000000000001/messages/bulk-delete",
				"GET " .. api .. "/channels/1300000000000000001/messages/1/reactions/x",
				"POST https://discord.com/api/oauth2/token",
				"POST https://discord.com/api/oauth2/token/revoke",
				"GET https://discord.com/api/oauth2/@me",
				"GET https://discord.com/api/v9/guilds/" .. guild,
				"GET https://discord.com/api/guilds/" .. guild,
				"GET " .. api .. "/channels/1300000000000000001/messages/..%2F..%2Fusers%2F@me",
				"GET " .. api .. "/guilds/" .. guild .. "/channels/../../users/@me/guilds",
				"GET https://discord.com.evil.test/api/v10/guilds/" .. guild,
				"GET https://evil.discord.com/api/v10/guilds/" .. guild,
				"GET https://discordapp.com/api/v10/guilds/" .. guild,
				"GET https://canary.discord.com/api/v10/guilds/" .. guild,
			}
			local publisher = {
				client_id = "fixture-client",
				client_secret = "fixture-secret",
				bot_token = "fixture-bot-token",
			}
			for _, access in { "read-only", "read-write" } do
				local r, err = m.resolve(publisher, { access = access }, nil, "oauth")
				assert(not err, tostring(err))
				if not (m.equal(r.Scopes, { "bot" })) then
					m.fail("access=%s scopes %s", access, r.Scopes)
				end
				r.Context.Auth["oauth"].access_token = "fixture-user-token"
				r.Context.Auth["oauth"].guild_id = guild
				do
					r.Proxy, err = m.renderPaths(r, r.Context)
					assert(not err, tostring(err))
				end
				m.routes(r, "Bot fixture-bot-token", true, read)
				m.routes(r, "Bot fixture-bot-token", (access == "read-write"), writes)
				m.routes(r, "Bot fixture-bot-token", false, denied)
			end
		end
		-- TestDiscordScopesProvenByGuild
		do
			local r = m.raw.auth["oauth"].token_response
			if
				not r.scopes_unreported
				or not (
					m.some(r.checks, function(c)
						return ((c.op == "exists") and (c.path == "/guild/id"))
					end)
				)
			then
				m.fail("Discord scopes must be unreported and proven by /guild/id: %s", r)
			end
		end
	end,
}
