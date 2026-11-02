package manifest

import (
	"encoding/json"
	"testing"
)

func TestDiscoveryAuthOnlyExposesDeclaredScopesAndFacts(t *testing.T) {
	m := Manifest{Auth: map[string]AuthMethod{"oauth": {Type: "oauth2", Scopes: []ScopeGroup{{Values: []string{"read", "write", "read"}}}, TokenResponse: TokenResponse{Facts: map[string]string{"team_id": "/team/id"}}}, "token": {Type: "manual"}}}
	for _, tc := range []struct {
		method  string
		granted []string
		facts   map[string]string
		want    string
	}{
		{"oauth", nil, nil, `{"method":"oauth"}`},
		{"oauth", []string{}, nil, `{"method":"oauth","scopes":[]}`},
		{"oauth", []string{"read", "upstream-private-value"}, nil, `{"method":"oauth","scopes":["read"]}`},
		{"oauth", nil, map[string]string{"team_id": "T1", "undeclared": "private"}, `{"method":"oauth","facts":{"team_id":"T1"}}`},
		{"token", []string{"read"}, map[string]string{"team_id": "T1"}, `{"method":"token"}`},
	} {
		got, err := json.Marshal(m.DiscoveryAuth(tc.method, tc.granted, tc.facts))
		if err != nil || string(got) != tc.want {
			t.Fatalf("got %s, %v; want %s", got, err, tc.want)
		}
	}
}
