package main

import (
	"slices"
	"testing"
)

// Houston's one Discord bot serves every connection, so each connection's routes are pinned
// to the server its install bound: guild routes by the proxy, channel routes by the Luau guard.
func TestDiscordBoundServerRoutes(t *testing.T) {
	m := parseManifest(t, "../../connectors/discord/houston.json")
	if !m.Auth["oauth"].PublisherClient() {
		t.Fatal("Discord OAuth client must belong to the publication")
	}
	if a := m.Auth["oauth"]; !a.TokenResponse.ScopesUnreported || !a.RefreshResponse.ScopesUnreported {
		t.Fatal(`Discord answers bot installs with an empty "scope"; the guild check proves the install`)
	}
	const api, guild, other = "https://discord.com/api/v10", "290926798626357999", "390926798626357000"
	read := []string{
		"GET " + api + "/guilds/" + guild, "GET " + api + "/guilds/" + guild + "?with_counts=true",
		"GET " + api + "/guilds/" + guild + "/channels", "GET " + api + "/guilds/" + guild + "/threads/active",
		"GET " + api + "/guilds/" + guild + "/roles", "GET " + api + "/guilds/" + guild + "/members/search?query=a&limit=25",
		"GET " + api + "/guilds/" + guild + "/members/80351110224678912",
		"GET " + api + "/guilds/" + guild + "/messages/search?content=hi&channel_id=1&channel_id=2",
		"GET " + api + "/channels/1300000000000000001", "GET " + api + "/channels/1300000000000000001/messages?limit=25",
		"GET " + api + "/channels/1300000000000000001/messages/1400000000000000001",
		"GET " + api + "/channels/1300000000000000001/threads/archived/public?limit=25",
	}
	writes := []string{
		"POST " + api + "/channels/1300000000000000001/messages",
		"PATCH " + api + "/channels/1300000000000000001/messages/1400000000000000001",
		"DELETE " + api + "/channels/1300000000000000001/messages/1400000000000000001",
		"PUT " + api + "/channels/1300000000000000001/messages/1400000000000000001/reactions/%F0%9F%91%8D/@me",
		"DELETE " + api + "/channels/1300000000000000001/messages/1400000000000000001/reactions/houston%3A1600000000000000001/@me",
		"POST " + api + "/channels/1300000000000000001/messages/1400000000000000001/threads",
		"POST " + api + "/channels/1300000000000000001/threads",
	}
	denied := []string{
		// Another server, listing the bot's servers, DMs and the bot's own account.
		"GET " + api + "/guilds/" + other, "GET " + api + "/guilds/" + other + "/channels", "GET " + api + "/guilds/" + other + "/members/search?query=a",
		"GET " + api + "/guilds/" + other + "/messages/search?content=hi", "GET " + api + "/guilds/" + guild + "0/roles",
		"GET " + api + "/guilds/%7B%7Bauth.oauth.guild_id%7D%7D/roles", "GET " + api + "/guilds/{{auth.oauth.guild_id}}/roles",
		"GET " + api + "/users/@me/guilds", "DELETE " + api + "/users/@me/guilds/" + guild, "GET " + api + "/users/@me",
		"POST " + api + "/users/@me/channels", "GET " + api + "/users/@me/channels",
		// Member listing needs a privileged intent; member management, bans, webhooks and invites are not exposed.
		"GET " + api + "/guilds/" + guild + "/members?limit=1000", "PATCH " + api + "/guilds/" + guild + "/members/80351110224678912",
		"DELETE " + api + "/guilds/" + guild + "/members/80351110224678912", "PUT " + api + "/guilds/" + guild + "/bans/80351110224678912",
		"GET " + api + "/guilds/" + guild + "/webhooks", "POST " + api + "/channels/1300000000000000001/webhooks",
		"GET " + api + "/channels/1300000000000000001/invites", "PATCH " + api + "/channels/1300000000000000001",
		"DELETE " + api + "/channels/1300000000000000001", "DELETE " + api + "/channels/1300000000000000001/messages/1/reactions",
		"PUT " + api + "/channels/1300000000000000001/messages/1/reactions/x/80351110224678912",
		"POST " + api + "/channels/1300000000000000001/messages/bulk-delete", "GET " + api + "/channels/1300000000000000001/messages/1/reactions/x",
		// Token and revocation endpoints, other API versions, traversal and lookalike hosts.
		"POST https://discord.com/api/oauth2/token", "POST https://discord.com/api/oauth2/token/revoke", "GET https://discord.com/api/oauth2/@me",
		"GET https://discord.com/api/v9/guilds/" + guild, "GET https://discord.com/api/guilds/" + guild,
		"GET " + api + "/channels/1300000000000000001/messages/..%2F..%2Fusers%2F@me",
		"GET " + api + "/guilds/" + guild + "/channels/../../users/@me/guilds",
		"GET https://discord.com.evil.test/api/v10/guilds/" + guild, "GET https://evil.discord.com/api/v10/guilds/" + guild,
		"GET https://discordapp.com/api/v10/guilds/" + guild, "GET https://canary.discord.com/api/v10/guilds/" + guild,
	}
	publisher := map[string]any{"client_id": "fixture-client", "client_secret": "fixture-secret", "bot_token": "fixture-bot-token"}
	for _, access := range []string{"read-only", "read-write"} {
		r, err := m.Resolve(publisher, map[string]any{"access": access}, nil, "oauth")
		if err != nil {
			t.Fatal(err)
		}
		if !slices.Equal(r.Scopes, []string{"bot"}) {
			t.Fatalf("access=%s scopes %v", access, r.Scopes)
		}
		r.Context.Auth["oauth"]["access_token"] = "fixture-user-token"
		r.Context.Auth["oauth"]["guild_id"] = guild
		if r.Proxy, err = r.Proxy.RenderPaths(r.Context); err != nil {
			t.Fatal(err)
		}
		// Every route carries the publication's bot token; the installer's OAuth token is never sent.
		assertAuthorizedRoutes(t, r, "Bot fixture-bot-token", true, read...)
		assertAuthorizedRoutes(t, r, "Bot fixture-bot-token", access == "read-write", writes...)
		assertAuthorizedRoutes(t, r, "Bot fixture-bot-token", false, denied...)
	}
}
