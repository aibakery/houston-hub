package manifest

import (
	"encoding/json"
	"fmt"
	"strings"
	"testing"
)

const factsManifest = `{"schema_version":1,"name":"Bound","files":["main.luau"],
 "config":{"host":{"type":"string","label":"Host","required":true}},
 "publisher":{"client_id":{"type":"string","label":"Client","required":true},"client_secret":{"type":"secret","label":"Secret","required":true},"bot":{"type":"secret","label":"Bot","required":true}},
 "auth":{"oauth":{"type":"oauth2","label":"Install","authorize_url":"https://example.com/authorize","token_url":"https://example.com/token","client_id":"{{publisher.client_id}}","client_secret":"{{publisher.client_secret}}","pkce":"none",
  "token_response":{"checks":[{"op":"exists","path":"/team/id"}],"facts":{"team_id":"/team/id","team_name":"/team/name"},"label":"/team/name"}}},
 "proxy":[
  {"match":{"protocol":"http","host":["api.example.com"],"method":["GET"],"path":["/teams/{{auth.oauth.team_id}}","/teams/{{auth.oauth.team_id}}/channels/{channel}","/channels/{channel}"]},"action":{"headers":{"set":{"Authorization":"Bot {{publisher.bot}}","X-Team":"{{auth.oauth.team_id}}"}}}},
  {"match":{"protocol":"http","host":["api.example.com"],"method":["PUT"],"path":["/teams/{{auth.oauth.team_id}}/files/{name}"],"opaque_path_parameters":["name"]},"action":{"headers":{"set":{"Authorization":"Bot {{publisher.bot}}"}}}}
 ]}`

func TestOAuthFactsValidation(t *testing.T) {
	m, err := Parse([]byte(factsManifest))
	if err != nil {
		t.Fatal(err)
	}
	if f, err := m.reference("auth.oauth.team_id"); err != nil || f.Type != "string" {
		t.Fatalf("declared fact did not resolve as a string: %v %v", f, err)
	}
	if _, err := m.reference("auth.oauth.other"); err == nil {
		t.Fatal("undeclared fact resolved")
	}
	many := map[string]string{}
	for i := range MaxFacts + 1 {
		many[fmt.Sprintf("f%d", i)] = fmt.Sprintf("/f%d", i)
	}
	tooMany, _ := json.Marshal(many)
	for _, tc := range []struct{ old, new, want string }{
		{`"team_id":"/team/id"`, `"Team":"/team/id"`, "invalid or reserved OAuth fact name"},
		{`"team_id":"/team/id"`, `"access_token":"/team/id"`, "invalid or reserved OAuth fact name"},
		{`"team_id":"/team/id"`, `"team_id":"team/id"`, "pointers outside credentials"},
		{`"team_id":"/team/id"`, `"team_id":"/access_token"`, "pointers outside credentials"},
		{`"label":"/team/name"`, `"label":"/refresh_token/x"`, "pointers outside credentials"},
		{`"label":"/team/name"`, `"label":""`, "empty token selector"},
		{`"pkce":"none",`, `"pkce":"none","refresh_response":{"facts":{"team_id":"/team/id"}},`, "refresh_response forbids facts, label"},
		{`"pkce":"none",`, `"pkce":"none","refresh_response":{"label":"/team/name"},`, "refresh_response forbids facts, label"},
		{`"pkce":"none",`, `"pkce":"none","account":{"url":"https://example.com/me","label":"/name"},`, "token_response.label conflicts with account"},
		{`"pkce":"none",`, `"pkce":"none","authorize_params":{"team":"{{auth.oauth.team_id}}"},`, "browser parameters require public publisher/config values"},
		{`"pkce":"none",`, `"pkce":"none","authorize_params":{"scope":"bot"},`, "reserved or invalid OAuth parameter scope"},
		{`"pkce":"none",`, `"pkce":"none","scope_parameter":"user_scope","token_params":{"scope":"bot"},`, "reserved or invalid OAuth parameter scope"},
		{`"host":["api.example.com"],"method":["GET"]`, `"host":["{{auth.oauth.team_id}}"],"method":["GET"]`, "host requires a required, unconditional string setting"},
		{`{"match":{"protocol":"http","host":["api.example.com"],"method":["PUT"]`, `{"if":"{{ is auth.oauth.team_id \"T1\" }}","match":{"protocol":"http","host":["api.example.com"],"method":["PUT"]`, "cannot be used in predicates"},
		{`"/channels/{channel}"`, `"/channels/x{{auth.oauth.team_id}}"`, "exactly one declared OAuth fact reference"},
		{`"/channels/{channel}"`, `"/channels/{{config.host}}"`, "exactly one declared OAuth fact reference"},
		{`"/channels/{channel}"`, `"/channels/{{auth.oauth.access_token}}"`, "exactly one declared OAuth fact reference"},
		{`"/channels/{channel}"`, `"/channels/{{auth.oauth.other}}"`, "exactly one declared OAuth fact reference"},
		{`"/channels/{channel}"`, `"/channels/{{auth.oauth.team_id || auth.oauth.team_name}}"`, "exactly one declared OAuth fact reference"},
		{`"pkce":"none",`, `"pkce":"none","refresh_response":{"scopes_unreported":true},`, "refresh_response forbids facts, label and scopes_unreported"},
		{`"token_response":{"checks":[{"op":"exists","path":"/team/id"}],`, `"token_response":{"scopes_unreported":true,`, "scopes_unreported requires checks"},
		{`"token_response":{"checks":`, `"token_response":{"revoked":[{"op":"exists","path":"/error"}],"checks":`, "token_response forbids revoked"},
		{`"pkce":"none",`, `"pkce":"none","refresh_response":{"revoked":[{"op":"matches","path":"/error"}]},`, "revoked checks require equals"},
		{`"pkce":"none",`, `"pkce":"none","refresh_response":{"revoked":[{"op":"exists","path":"/error"}]},`, "revoked checks require equals"},
		{`"pkce":"none",`, `"pkce":"none","refresh_response":{"checks":[{"op":"equals","path":"/ok","value":true}],"revoked":[{"op":"equals","path":"/ok","value":false}]},`, "revoked checks cannot test a path that checks test"},
		{`"token_response":{"checks":`, `"token_response":{"revoked":[{"op":"matches","path":"/error"}],"checks":`, "token_response forbids revoked"},
		{`"label":"/team/name"}`, `"label":"/team/name","scopes":"/scope","scopes_unreported":true}`, "token scopes conflict with scopes_unreported"},
	} {
		raw := strings.Replace(factsManifest, tc.old, tc.new, 1)
		if raw == factsManifest {
			t.Fatalf("fixture replacement %q missing", tc.old)
		}
		if _, err := Parse([]byte(raw)); err == nil || !strings.Contains(err.Error(), tc.want) {
			t.Errorf("%s: want %q, got %v", tc.new, tc.want, err)
		}
	}
	facts := strings.Replace(factsManifest, `"facts":{"team_id":"/team/id","team_name":"/team/name"}`, `"facts":`+string(tooMany), 1)
	if _, err := Parse([]byte(facts)); err == nil || !strings.Contains(err.Error(), "at most 16 facts") {
		t.Errorf("accepted more than %d facts: %v", MaxFacts, err)
	}
	revoked := strings.Replace(factsManifest, `"pkce":"none",`, `"pkce":"none","refresh_response":{"revoked":[{"op":"equals","path":"/error","value":"invalid_grant"}]},`, 1)
	if m, err := Parse([]byte(revoked)); err != nil || len(m.Auth["oauth"].RefreshResponse.Revoked) != 1 {
		t.Errorf("refresh revocation checks: %v", err)
	}
	botScope := strings.Replace(factsManifest, `"pkce":"none",`, `"pkce":"none","scope_parameter":"user_scope","authorize_params":{"scope":"mcp:connect"},`, 1)
	if m, err := Parse([]byte(botScope)); err != nil || m.Auth["oauth"].AuthorizeParams["scope"] != "mcp:connect" {
		t.Errorf("bot scope beside user_scope: %v", err)
	}
	unreported := strings.Replace(factsManifest, `"label":"/team/name"}`, `"label":"/team/name","scopes_unreported":true}`, 1)
	if m, err := Parse([]byte(unreported)); err != nil || !m.Auth["oauth"].TokenResponse.ScopesUnreported || m.Auth["oauth"].TokenResponse.Scopes != "" {
		t.Errorf("checked install with unreported scopes: %v", err)
	}
	templatedHost := strings.Replace(factsManifest, `"host":["api.example.com"],"method":["GET"]`, `"host":["{{config.host}}"],"method":["GET"]`, 1)
	templatedHost = strings.Replace(templatedHost, `"Authorization":"Bot {{publisher.bot}}","X-Team"`, `"X-Team"`, 1)
	if _, err := Parse([]byte(templatedHost)); err != nil {
		t.Errorf("a public fact was treated as a publisher credential: %v", err)
	}
}

func TestOAuthFactPathsRenderPerConnection(t *testing.T) {
	m, err := Parse([]byte(factsManifest))
	if err != nil {
		t.Fatal(err)
	}
	publisher := map[string]any{"client_id": "client", "client_secret": "secret", "bot": "bot-secret"}
	r, err := m.Resolve(publisher, map[string]any{"host": "example.org"}, nil, "oauth")
	if err != nil {
		t.Fatal(err)
	}
	denied := []string{"GET https://api.example.com/teams/A", "GET https://api.example.com/teams/%7B%7Bauth.oauth.team_id%7D%7D", "PUT https://api.example.com/teams/A/files/x"}
	for _, request := range denied {
		method, url, _ := strings.Cut(request, " ")
		if _, err := r.Proxy.HTTPRecipe(method, url, nil); err == nil {
			t.Errorf("unrendered template matched %s", request)
		}
	}
	if _, err := r.Proxy.HTTPRecipe("GET", "https://api.example.com/channels/1", nil); err != nil {
		t.Fatalf("literal route unavailable before rendering: %v", err)
	}
	if _, err := r.Proxy.RenderPaths(r.Context); err == nil {
		t.Fatal("missing fact rendered")
	}
	r.Context.Auth["oauth"] = map[string]any{"access_token": "token", "team_id": "A", "team_name": "Team A"}
	rendered, err := r.Proxy.RenderPaths(r.Context)
	if err != nil {
		t.Fatal(err)
	}
	if r.Proxy[0].Match.Path[0] != "/teams/{{auth.oauth.team_id}}" || m.Proxy[0].Match.Path[0] != "/teams/{{auth.oauth.team_id}}" {
		t.Fatal("rendering changed the resolved or manifest rules")
	}
	for _, request := range []string{"GET https://api.example.com/teams/A", "GET https://api.example.com/teams/A/channels/9", "PUT https://api.example.com/teams/A/files/a%2Fb"} {
		method, url, _ := strings.Cut(request, " ")
		recipe, err := rendered.HTTPRecipe(method, url, nil)
		if err != nil {
			t.Fatalf("%s: %v", request, err)
		}
		if h, err := recipe.Prepare(r.Context, nil); method == "GET" && (err != nil || h.Get("X-Team") != "A") {
			t.Fatalf("fact header not injected: %v", err)
		}
	}
	for _, request := range []string{"GET https://api.example.com/teams/B", "GET https://api.example.com/teams/B/channels/9", "GET https://api.example.com/teams/AB", "PUT https://api.example.com/teams/B/files/x"} {
		method, url, _ := strings.Cut(request, " ")
		if _, err := rendered.HTTPRecipe(method, url, nil); err == nil {
			t.Errorf("rule rendered for team A matched %s", request)
		}
	}
	for _, unsafe := range []string{"", ".", "..", "...", "a/b", `a\b`, "%41", "*", "{id}", "a?b", "a#b", "a\x01", "a b", "équipe"} {
		r.Context.Auth["oauth"]["team_id"] = unsafe
		if _, err := r.Proxy.RenderPaths(r.Context); err == nil {
			t.Errorf("rendered unsafe segment %q", unsafe)
		}
	}
	manual := strings.Replace(factsManifest, `"auth":{`, `"auth":{"token":{"type":"manual","label":"Token","config":{"token":{"type":"secret","label":"Token","required":true}}},`, 1)
	manual = strings.Replace(manual, `"X-Team":"{{auth.oauth.team_id}}"`, `"X-Team":"{{auth.oauth.team_id || auth.token.token}}"`, 1)
	if m, err = Parse([]byte(manual)); err != nil {
		t.Fatal(err)
	}
	if _, err := m.Resolve(publisher, map[string]any{"host": "example.org"}, nil, "oauth"); err != nil {
		t.Fatal(err)
	}
	if _, err := m.Resolve(publisher, map[string]any{"host": "example.org"}, map[string]any{"token": "manual"}, "token"); err == nil || !strings.Contains(err.Error(), "proxy path") {
		t.Errorf("fact path rule resolved for a manual method: %v", err)
	}
}
