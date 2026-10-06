package manifest

import "strings"

// Conjunctions form a bounded constraint set, so simple overlap can be proven
// without treating array position as precedence. Runtime still checks exactly one.
func (m *Manifest) proxiesOverlap(a, b Proxy) bool {
	literals := map[string]any{}
	selected := ""
	visited := map[string]bool{}
	possible := true
	var add func(string)
	var ref func(string)
	ref = func(r string) {
		if visited[r] {
			return
		}
		visited[r] = true
		f, e := m.reference(r)
		if e != nil {
			possible = false
			return
		}
		add(f.If)
		if strings.HasPrefix(r, "auth.") {
			parts := strings.Split(r, ".")
			if selected != "" && selected != parts[1] {
				possible = false
			}
			selected = parts[1]
			add(m.Auth[parts[1]].If)
		}
	}
	var walk func(predicate)
	walk = func(p predicate) {
		if p.ref != "" {
			ref(p.ref)
			if p.op == "is" {
				if old, ok := literals[p.ref]; ok && !equal(old, p.literal) {
					possible = false
				}
				literals[p.ref] = p.literal
			}
		}
		for _, c := range p.children {
			walk(c)
		}
	}
	add = func(s string) {
		if s == "" {
			return
		}
		p, e := parsePredicate(s)
		if e != nil {
			possible = false
			return
		}
		walk(p)
	}
	add(a.If)
	add(b.If)
	return possible
}
