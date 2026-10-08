package manifest

import (
	"fmt"
	"sort"
	"strings"
)

type FormField struct {
	Source string `json:"source"`
	Name   string `json:"name"`
	Field  Field  `json:"field"`
}
type MethodAvailability struct {
	Key       string `json:"key"`
	Label     string `json:"label"`
	Type      string `json:"type"`
	Eligible  bool   `json:"eligible"`
	Available bool   `json:"available"`
	Error     string `json:"error,omitempty"`
}
type Resolved struct {
	Context         Context
	PublicConfig    map[string]any
	PublisherFields []FormField
	ConfigFields    []FormField
	AuthFields      []FormField
	// ConnectionFields combines active fields in dependency/presentation order.
	ConnectionFields []FormField
	Methods          []MethodAvailability
	Scopes           []string
	ProxyIndices     []int
}

func (m *Manifest) MethodKeys() []string {
	keys := make([]string, 0, len(m.Auth))
	for k := range m.Auth {
		keys = append(keys, k)
	}
	sort.Slice(keys, func(i, j int) bool {
		a, b := m.Auth[keys[i]], m.Auth[keys[j]]
		if a.Order != b.Order {
			return a.Order < b.Order
		}
		return keys[i] < keys[j]
	})
	return keys
}
func (m *Manifest) fieldOrder(source string) ([]string, error) {
	fields := m.Config
	if source == "publisher" {
		fields = m.Publisher
	}
	done := map[string]bool{}
	out := []string{}
	for len(out) < len(fields) {
		ready := []string{}
		for k, f := range fields {
			if done[k] {
				continue
			}
			refs, e := PredicateReferences(f.If)
			if e != nil {
				return nil, e
			}
			ok := true
			for _, r := range refs {
				if strings.HasPrefix(r, source+".") && !done[strings.TrimPrefix(r, source+".")] {
					ok = false
				}
			}
			if ok {
				ready = append(ready, k)
			}
		}
		if len(ready) == 0 {
			return nil, fmt.Errorf("%s field dependency cycle", source)
		}
		sort.Slice(ready, func(i, j int) bool {
			a, b := fields[ready[i]], fields[ready[j]]
			if a.Order != b.Order {
				return a.Order < b.Order
			}
			return ready[i] < ready[j]
		})
		k := ready[0]
		out = append(out, k)
		done[k] = true
	}
	return out, nil
}
func checkInputs(fields map[string]Field, input map[string]any) error {
	for k, v := range input {
		if _, ok := fields[k]; !ok {
			return fmt.Errorf("undeclared input %s", k)
		}
		if v == nil {
			return fmt.Errorf("input %s cannot be null", k)
		}
	}
	return nil
}
func (m *Manifest) resolveFields(source string, fields map[string]Field, input map[string]any, c *Context, strict bool) ([]FormField, error) {
	if e := checkInputs(fields, input); e != nil {
		return nil, e
	}
	var order []string
	var e error
	if source == "publisher" || source == "config" {
		order, e = m.fieldOrder(source)
		if e != nil {
			return nil, e
		}
	} else {
		for k := range fields {
			order = append(order, k)
		}
		sort.Slice(order, func(i, j int) bool {
			a, b := fields[order[i]], fields[order[j]]
			if a.Order != b.Order {
				return a.Order < b.Order
			}
			return order[i] < order[j]
		})
	}
	result := []FormField{}
	var first error
	for _, k := range order {
		f := fields[k]
		active, e := EvaluatePredicate(f.If, *c)
		ref := source + "." + k
		if e != nil {
			c.Errors[ref] = e
			if first == nil {
				first = e
			}
			continue
		}
		if !active {
			continue
		}
		result = append(result, FormField{Source: source, Name: k, Field: f})
		v, present := input[k]
		if !present && f.Default != nil {
			v = f.Default
			present = true
		}
		if source == "config" && k == "access" && !f.Required && v == nil {
			v = "read-only"
			present = true
		}
		if e := ValidateValue(f, v); e != nil {
			err := fmt.Errorf("%s: %w", ref, e)
			c.Errors[ref] = err
			if first == nil {
				first = err
			}
			continue
		}
		if present {
			switch source {
			case "publisher":
				c.Publisher[k] = v
			case "config":
				c.Config[k] = v
			default:
				c.Auth[c.SelectedAuth][k] = v
			}
		}
	}
	if strict {
		return result, first
	}
	return result, nil
}

// Resolve validates a saved candidate. Retained inactive values are accepted but
// remain absent from all reference contexts. OAuth tokens are lifecycle-owned;
// call RequireCredentials before native header preparation.
func (m *Manifest) Resolve(publisher, config, auth map[string]any, selected string) (*Resolved, error) {
	return m.resolve(publisher, config, auth, selected, false)
}

// ResolveDraft returns active form metadata even when required inputs are not
// supplied. Context.Errors records failures and no failed prerequisite is false.
func (m *Manifest) ResolveDraft(publisher, config, auth map[string]any, selected string) (*Resolved, error) {
	return m.resolve(publisher, config, auth, selected, true)
}
func (m *Manifest) resolve(publisher, config, auth map[string]any, selected string, draft bool) (*Resolved, error) {
	r := &Resolved{Context: Context{Publisher: map[string]any{}, Config: map[string]any{}, Auth: map[string]map[string]any{}, SelectedAuth: selected, Errors: map[string]error{}}, PublicConfig: map[string]any{}}
	c := &r.Context
	var e error
	r.PublisherFields, e = m.resolveFields("publisher", m.Publisher, publisher, c, false)
	if e != nil {
		return r, e
	}
	r.ConfigFields, e = m.resolveFields("config", m.Config, config, c, !draft)
	if e != nil {
		return r, e
	}
	eligible := 0
	selectedOK := selected == ""
	for _, key := range m.MethodKeys() {
		a := m.Auth[key]
		yes, e := EvaluatePredicate(a.If, *c)
		status := MethodAvailability{Key: key, Label: a.Label, Type: a.Type, Eligible: yes, Available: yes}
		if e != nil {
			status.Error = e.Error()
			status.Available = false
			r.Methods = append(r.Methods, status)
			if !draft {
				return r, e
			}
			continue
		}
		if yes {
			eligible++
			if a.Type == "oauth2" {
				for _, s := range []string{a.ClientID, a.ClientSecret} {
					if s == "" {
						continue
					}
					value, e := RenderString(s, *c)
					if e != nil || value == "" {
						status.Available = false
						status.Error = "publisher OAuth client settings are incomplete"
					}
				}
			}
			if selected == key {
				selectedOK = status.Available
			}
		}
		r.Methods = append(r.Methods, status)
	}
	if selected == "" && eligible > 0 {
		selectedOK = false
	}
	if !selectedOK && !draft {
		return r, fmt.Errorf("selected authentication method unavailable; explicit configuration required")
	}
	if selected != "" {
		a, ok := m.Auth[selected]
		if !ok {
			return r, fmt.Errorf("unknown selected auth method")
		}
		c.Auth[selected] = map[string]any{}
		if a.Type == "manual" {
			r.AuthFields, e = m.resolveFields("auth."+selected, a.Config, auth, c, !draft)
			if e != nil {
				return r, e
			}
		} else {
			if len(auth) > 0 {
				return r, fmt.Errorf("OAuth inputs are lifecycle-owned")
			}
			seen := map[string]bool{}
			for _, g := range a.Scopes {
				yes, e := EvaluatePredicate(g.If, *c)
				if e != nil {
					if !draft {
						return r, e
					}
					continue
				}
				if yes {
					for _, s := range g.Values {
						if !seen[s] {
							r.Scopes = append(r.Scopes, s)
							seen[s] = true
						}
					}
				}
			}
		}
	} else if len(auth) > 0 {
		return r, fmt.Errorf("auth inputs require selected method")
	}
	for k, v := range c.Config {
		if m.Config[k].Type != "secret" {
			r.PublicConfig[k] = v
		}
	}
	r.ConnectionFields = m.connectionOrder(r.ConfigFields, r.AuthFields)

	for i, p := range m.Proxy {
		yes, err := EvaluatePredicate(p.If, *c)
		if err != nil {
			if !draft {
				return r, err
			}
			continue
		}
		if yes {
			r.ProxyIndices = append(r.ProxyIndices, i)
		}
	}
	active := m.Proxy.Select(r.ProxyIndices)
	valid := len(active) > 0
	for _, p := range active {
		if p.Match.Protocol != active[0].Match.Protocol {
			valid = false
		}
	}
	if !valid {
		r.ProxyIndices = nil
		if !draft {
			return r, fmt.Errorf("require active proxy rules with one protocol")
		}
		return r, nil
	}
	if selected != "" && m.Auth[selected].Type == "oauth2" && active[0].Match.Protocol != "http" {
		return r, fmt.Errorf("OAuth requires HTTP proxy")
	}
	if !draft {
		preparation := *c
		// OAuth setup precedes acquisition; use a private stand-in only here.
		if selected != "" && m.Auth[selected].Type == "oauth2" {
			preparation.Auth = map[string]map[string]any{selected: {"access_token": "pending-oauth-acquisition"}}
		}
		for i, p := range active {
			if p.Match.Protocol != "http" {
				if i > 0 {
					break
				}
				if _, err := p.ResolveDatabase(*c); err != nil {
					return r, err
				}
				continue
			}
			recipe := p.Action.httpRecipe("")
			if _, err := recipe.Prepare(preparation, nil); err != nil {
				return r, err
			}
			for _, value := range p.Action.Headers.Set {
				refs, _ := TemplateReferences(value)
				for _, ref := range refs {
					if strings.HasPrefix(ref, "publisher.") {
						if _, _, err := c.Lookup(ref); err != nil {
							return r, err
						}
					}
				}
			}
			if p.Action.BasicAuth.Enabled() {
				for _, value := range []string{p.Action.BasicAuth.Username, p.Action.BasicAuth.Password} {
					if _, err := RenderString(value, *c); err != nil {
						return r, err
					}
				}
			}
		}
	}
	return r, nil
}
func (m *Manifest) connectionOrder(root, auth []FormField) []FormField {
	all := append(append([]FormField{}, root...), auth...)
	out := []FormField{}
	done := map[string]bool{}
	priority := map[string]bool{}
	var mark func(string)
	mark = func(ref string) {
		if !strings.HasPrefix(ref, "config.") || priority[ref] {
			return
		}
		priority[ref] = true
		f := m.Config[strings.TrimPrefix(ref, "config.")]
		refs, _ := PredicateReferences(f.If)
		for _, r := range refs {
			mark(r)
		}
	}
	for _, a := range m.Auth {
		refs, _ := PredicateReferences(a.If)
		for _, r := range refs {
			mark(r)
		}
		for _, g := range a.Scopes {
			refs, _ := PredicateReferences(g.If)
			for _, r := range refs {
				mark(r)
			}
		}
		for _, f := range a.Config {
			refs, _ := PredicateReferences(f.If)
			for _, r := range refs {
				mark(r)
			}
		}
	}
	for len(all) > 0 {
		sort.Slice(all, func(i, j int) bool {
			a, b := all[i], all[j]
			pa, pb := priority[a.Source+"."+a.Name], priority[b.Source+"."+b.Name]
			if pa != pb {
				return pa
			}
			if a.Field.Order != b.Field.Order {
				return a.Field.Order < b.Field.Order
			}
			if a.Source != b.Source {
				return a.Source == "config"
			}
			return a.Name < b.Name
		})
		pick := -1
		for i, f := range all {
			ready := true
			refs, _ := PredicateReferences(f.Field.If)
			for _, ref := range refs {
				if strings.HasPrefix(ref, "config.") && !done[ref] {
					for _, pending := range all {
						if pending.Source+"."+pending.Name == ref {
							ready = false
						}
					}
				}
			}
			if ready {
				pick = i
				break
			}
		}
		if pick < 0 {
			break
		}
		f := all[pick]
		out = append(out, f)
		done[f.Source+"."+f.Name] = true
		all = append(all[:pick], all[pick+1:]...)
	}
	return out
}

// ValidateSubmission rejects keys that were explicitly submitted while inactive;
// saved inactive values can still be retained separately for later reactivation.
func (r *Resolved) ValidateSubmission(source string, submitted map[string]any) error {
	active := map[string]bool{}
	for _, list := range [][]FormField{r.PublisherFields, r.ConfigFields, r.AuthFields} {
		for _, f := range list {
			if f.Source == source {
				active[f.Name] = true
			}
		}
	}
	for k, v := range submitted {
		if !active[k] {
			return fmt.Errorf("inactive or undeclared submitted field %s.%s", source, k)
		}
		if v == nil {
			return fmt.Errorf("null submission forbidden")
		}
	}
	return nil
}

// RequireCredentials is called only after native OAuth refresh has succeeded.
// A missing token can never turn an authenticated request into a guarded omission.
func (m *Manifest) RequireCredentials(c Context) error {
	if c.SelectedAuth != "" {
		a, ok := m.Auth[c.SelectedAuth]
		if !ok {
			return fmt.Errorf("unknown selected method")
		}
		if a.Type == "oauth2" {
			v, ok, e := c.Lookup("auth." + c.SelectedAuth + ".access_token")
			if e != nil {
				return e
			}
			s, isString := v.(string)
			if !ok || !isString || s == "" {
				return fmt.Errorf("OAuth credential unavailable; reconnect required")
			}
		}
	}
	for ref, e := range c.Errors {
		if !strings.HasPrefix(ref, "publisher.") {
			return e
		}
	}
	return nil
}
