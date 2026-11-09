// Scope profiles bind broker consent and granted permissions to the configured scope groups.
package manifest

import "fmt"

var pipedreamScopeProfiles = []string{"read_only", "read_write", "admin"}

func (a AuthMethod) ScopeProfile(c Context) (string, error) {
	profile, configured := "", false
	for _, group := range a.Scopes {
		if group.Profile == "" {
			continue
		}
		configured = true
		active, err := EvaluatePredicate(group.If, c)
		if err != nil {
			return "", err
		}
		if active {
			if profile != "" {
				return "", fmt.Errorf("exactly one Pipedream scope profile must be active")
			}
			profile = group.Profile
		}
	}
	if configured && profile == "" {
		return "", fmt.Errorf("exactly one Pipedream scope profile must be active")
	}
	return profile, nil
}
