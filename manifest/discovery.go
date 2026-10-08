package manifest

import "slices"

// AuthFacts contains only release-declared authentication facts, never credentials.
// Nil scopes mean unknown; a non-nil empty list means no declared scopes granted.
type AuthFacts struct {
	Method string    `json:"method"`
	Scopes *[]string `json:"scopes,omitempty"`
}

func (m Manifest) DiscoveryAuth(method string, granted []string) AuthFacts {
	facts := AuthFacts{Method: method}
	if m.Auth[method].Type != "oauth2" || granted == nil {
		return facts
	}
	scopes := []string{}
	for _, group := range m.Auth[method].Scopes {
		for _, scope := range group.Values {
			if slices.Contains(granted, scope) {
				scopes = append(scopes, scope)
			}
		}
	}
	slices.Sort(scopes)
	scopes = slices.Compact(scopes)
	facts.Scopes = &scopes
	return facts
}
