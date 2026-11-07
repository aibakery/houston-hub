package manifest

import "slices"

// AuthFacts contains only release-declared authentication facts, never credentials.
// Nil scopes mean unknown; a non-nil empty list means no declared scopes granted.
// Facts holds the selected OAuth method's declared token-response facts.
type AuthFacts struct {
	Method string            `json:"method"`
	Scopes *[]string         `json:"scopes,omitempty"`
	Facts  map[string]string `json:"facts,omitempty"`
}

func (m Manifest) DiscoveryAuth(method string, granted []string, facts map[string]string) AuthFacts {
	out := AuthFacts{Method: method}
	a := m.Auth[method]
	if !a.RequiresAuthorization() {
		return out
	}
	for name, value := range facts {
		if _, declared := a.TokenResponse.Facts[name]; declared {
			if out.Facts == nil {
				out.Facts = map[string]string{}
			}
			out.Facts[name] = value
		}
	}
	if granted == nil {
		return out
	}
	scopes := []string{}
	for _, group := range a.Scopes {
		for _, scope := range group.Values {
			if slices.Contains(granted, scope) {
				scopes = append(scopes, scope)
			}
		}
	}
	slices.Sort(scopes)
	scopes = slices.Compact(scopes)
	out.Scopes = &scopes
	return out
}
