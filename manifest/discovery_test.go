package manifest

import (
	"encoding/json"
	"testing"
)

func TestDiscoveryAuthOnlyExposesDeclaredScopes(t *testing.T) {
	m := Manifest{Auth: map[string]AuthMethod{"oauth": {Type: "oauth2", Scopes: []ScopeGroup{{Values: []string{"read", "write", "read"}}}}, "token": {Type: "manual"}}}
	for _, tc := range []struct {
		method  string
		granted []string
		want    string
	}{
		{"oauth", nil, `{"method":"oauth"}`},
		{"oauth", []string{}, `{"method":"oauth","scopes":[]}`},
		{"oauth", []string{"read", "upstream-private-value"}, `{"method":"oauth","scopes":["read"]}`},
		{"token", []string{"read"}, `{"method":"token"}`},
	} {
		got, err := json.Marshal(m.DiscoveryAuth(tc.method, tc.granted))
		if err != nil || string(got) != tc.want {
			t.Fatalf("got %s, %v; want %s", got, err, tc.want)
		}
	}
}
