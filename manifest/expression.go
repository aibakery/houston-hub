package manifest

import (
	"encoding/json"
	"fmt"
	"math"
	"math/big"
	"regexp"
	"strconv"
	"strings"
)

var nameRE = regexp.MustCompile(`^[a-z][a-z0-9_]{0,63}$`)
var scalarRefRE = regexp.MustCompile(`^(config|publisher)\.[a-z][a-z0-9_]{0,63}$|^auth\.[a-z][a-z0-9_]{0,63}\.[a-z][a-z0-9_]{0,63}$`)
var methodRefRE = regexp.MustCompile(`^auth\.[a-z][a-z0-9_]{0,63}$`)

// Context is a private server-only reference snapshot. Auth leaves resolve only
// for SelectedAuth even when other stored method inputs are present in Auth.
type Context struct {
	Publisher    map[string]any
	Config       map[string]any
	Auth         map[string]map[string]any
	SelectedAuth string
	// Errors contains unresolved active prerequisite failures. Evaluation checks
	// every referenced prerequisite before it evaluates any boolean operand.
	Errors map[string]error
}

func (c Context) Lookup(ref string) (any, bool, error) {
	if err := c.Errors[ref]; err != nil {
		return nil, false, err
	}
	p := strings.Split(ref, ".")
	if len(p) == 2 {
		switch p[0] {
		case "publisher":
			v, ok := c.Publisher[p[1]]
			return v, ok, nil
		case "config":
			v, ok := c.Config[p[1]]
			return v, ok, nil
		case "auth":
			return true, p[1] == c.SelectedAuth, nil
		}
	}
	if len(p) == 3 && p[0] == "auth" {
		if p[1] != c.SelectedAuth {
			return nil, false, nil
		}
		v, ok := c.Auth[p[1]][p[2]]
		return v, ok, nil
	}
	return nil, false, fmt.Errorf("invalid reference %s", ref)
}

type segment struct {
	text string
	refs []string
}

func parseTemplate(s string) ([]segment, error) {
	var out []segment
	for len(s) > 0 {
		i := strings.Index(s, "{{")
		if i < 0 {
			if strings.Contains(s, "}}") {
				return nil, fmt.Errorf("unmatched template delimiter")
			}
			out = append(out, segment{text: s})
			break
		}
		if i > 0 {
			out = append(out, segment{text: s[:i]})
		}
		s = s[i+2:]
		j := strings.Index(s, "}}")
		if j < 0 {
			return nil, fmt.Errorf("unclosed template")
		}
		expr := s[:j]
		var refs []string
		for _, r := range strings.Split(expr, "||") {
			r = strings.TrimSpace(r)
			if !scalarRefRE.MatchString(r) {
				return nil, fmt.Errorf("invalid value reference %q", r)
			}
			refs = append(refs, r)
		}
		out = append(out, segment{refs: refs})
		s = s[j+2:]
	}
	return out, nil
}
func TemplateReferences(s string) ([]string, error) {
	parts, err := parseTemplate(s)
	if err != nil {
		return nil, err
	}
	var refs []string
	for _, p := range parts {
		refs = append(refs, p.refs...)
	}
	return refs, nil
}
func renderPart(p segment, c Context) (any, error) {
	for _, r := range p.refs {
		v, ok, e := c.Lookup(r)
		if e != nil {
			return nil, e
		}
		if ok {
			return v, nil
		}
	}
	return nil, fmt.Errorf("unresolved template reference")
}

// Render preserves the native scalar type for a single whole-value expression.
func Render(s string, c Context) (any, error) {
	parts, e := parseTemplate(s)
	if e != nil {
		return nil, e
	}
	if len(parts) == 1 && len(parts[0].refs) > 0 {
		return renderPart(parts[0], c)
	}
	var b strings.Builder
	for _, p := range parts {
		if len(p.refs) == 0 {
			b.WriteString(p.text)
		} else {
			v, e := renderPart(p, c)
			if e != nil {
				return nil, e
			}
			s, e := scalarString(v)
			if e != nil {
				return nil, e
			}
			b.WriteString(s)
		}
	}
	return b.String(), nil
}
func RenderString(s string, c Context) (string, error) {
	v, e := Render(s, c)
	if e != nil {
		return "", e
	}
	return scalarString(v)
}
func scalarString(v any) (string, error) {
	if s, ok := v.(string); ok {
		return s, nil
	}
	if _, ok := number(v); ok {
		b, e := json.Marshal(v)
		return string(b), e
	}
	if b, ok := v.(bool); ok {
		return strconv.FormatBool(b), nil
	}
	return "", fmt.Errorf("value is not a scalar")
}
func number(v any) (float64, bool) {
	var n float64
	switch x := v.(type) {
	case json.Number:
		f, e := x.Float64()
		if e != nil {
			return 0, false
		}
		n = f
	case float64:
		n = x
	case float32:
		n = float64(x)
	case int:
		n = float64(x)
	case int64:
		n = float64(x)
	case int32:
		n = float64(x)
	default:
		return 0, false
	}
	return n, !math.IsNaN(n) && !math.IsInf(n, 0)
}

func integer(v any) (int64, bool) {
	if n, ok := v.(json.Number); ok {
		r, valid := new(big.Rat).SetString(string(n))
		if !valid || !r.IsInt() || !r.Num().IsInt64() {
			return 0, false
		}
		x := r.Num().Int64()
		return x, x >= -MaxInteger && x <= MaxInteger
	}
	n, ok := number(v)
	if !ok || math.Trunc(n) != n || math.Abs(n) > MaxInteger {
		return 0, false
	}
	return int64(n), true
}
func equal(a, b any) bool {
	na, oka := number(a)
	nb, okb := number(b)
	if oka || okb {
		return oka && okb && na == nb
	}
	switch x := a.(type) {
	case string:
		y, ok := b.(string)
		return ok && x == y
	case bool:
		y, ok := b.(bool)
		return ok && x == y
	}
	return false
}

type predicate struct {
	op, ref  string
	literal  any
	children []predicate
}
type predParser struct {
	s   string
	pos int
}

func (p *predParser) space() {
	for p.pos < len(p.s) && strings.ContainsRune(" \t\r\n", rune(p.s[p.pos])) {
		p.pos++
	}
}
func (p *predParser) word() string {
	p.space()
	start := p.pos
	for p.pos < len(p.s) && !strings.ContainsRune(" \t\r\n()", rune(p.s[p.pos])) {
		p.pos++
	}
	return p.s[start:p.pos]
}
func (p *predParser) parse() (predicate, error) {
	n := predicate{op: p.word()}
	switch n.op {
	case "isDefined":
		n.ref = p.word()
		if !scalarRefRE.MatchString(n.ref) && !methodRefRE.MatchString(n.ref) {
			return n, fmt.Errorf("invalid predicate reference")
		}
	case "is":
		n.ref = p.word()
		if !scalarRefRE.MatchString(n.ref) {
			return n, fmt.Errorf("is requires a scalar reference")
		}
		p.space()
		if p.pos == len(p.s) {
			return n, fmt.Errorf("is requires literal")
		}
		d := json.NewDecoder(strings.NewReader(p.s[p.pos:]))
		d.UseNumber()
		if e := d.Decode(&n.literal); e != nil {
			return n, fmt.Errorf("invalid predicate literal")
		}
		p.pos += int(d.InputOffset())
		if _, e := scalarString(n.literal); e != nil {
			return n, e
		}
	case "and":
		for {
			p.space()
			if p.pos == len(p.s) || p.s[p.pos] != '(' {
				break
			}
			p.pos++
			child, e := p.parse()
			if e != nil {
				return n, e
			}
			p.space()
			if p.pos == len(p.s) || p.s[p.pos] != ')' {
				return n, fmt.Errorf("and requires parenthesized predicates")
			}
			p.pos++
			n.children = append(n.children, child)
		}
		if len(n.children) < 2 {
			return n, fmt.Errorf("and requires at least two operands")
		}
	default:
		return n, fmt.Errorf("unknown predicate operation %q", n.op)
	}
	return n, nil
}
func parsePredicate(s string) (predicate, error) {
	s = strings.TrimSpace(s)
	if !strings.HasPrefix(s, "{{") || !strings.HasSuffix(s, "}}") {
		return predicate{}, fmt.Errorf("if requires one complete predicate template")
	}
	p := predParser{s: s[2 : len(s)-2]}
	n, e := p.parse()
	if e != nil {
		return n, e
	}
	p.space()
	if p.pos != len(p.s) {
		return n, fmt.Errorf("unexpected predicate operand")
	}
	return n, nil
}
func (p predicate) refs() []string {
	var out []string
	if p.ref != "" {
		out = append(out, p.ref)
	}
	for _, c := range p.children {
		out = append(out, c.refs()...)
	}
	return out
}
func PredicateReferences(s string) ([]string, error) {
	if s == "" {
		return nil, nil
	}
	p, e := parsePredicate(s)
	return p.refs(), e
}
func (p predicate) eval(c Context) (bool, error) {
	if p.op == "and" {
		all := true
		for _, child := range p.children {
			v, e := child.eval(c)
			if e != nil {
				return false, e
			}
			all = all && v
		}
		return all, nil
	}
	v, ok, e := c.Lookup(p.ref)
	if e != nil {
		return false, e
	}
	if p.op == "isDefined" {
		return ok, nil
	}
	return ok && equal(v, p.literal), nil
}
func EvaluatePredicate(s string, c Context) (bool, error) {
	if s == "" {
		return true, nil
	}
	p, e := parsePredicate(s)
	if e != nil {
		return false, e
	}
	for _, ref := range p.refs() {
		if _, _, e := c.Lookup(ref); e != nil {
			return false, e
		}
	}
	return p.eval(c)
}
func (m *Manifest) reference(ref string) (Field, error) {
	p := strings.Split(ref, ".")
	if len(p) == 2 {
		if p[0] == "config" {
			if f, ok := m.Config[p[1]]; ok {
				return f, nil
			}
		}
		if p[0] == "publisher" {
			if f, ok := m.Publisher[p[1]]; ok {
				return f, nil
			}
		}
		if p[0] == "auth" {
			if _, ok := m.Auth[p[1]]; ok {
				return Field{Type: "marker"}, nil
			}
		}
	}
	if len(p) == 3 && p[0] == "auth" {
		if a, ok := m.Auth[p[1]]; ok {
			if a.Type == "oauth2" && p[2] == "access_token" {
				return Field{Type: "secret"}, nil
			}
			if a.Type == "manual" {
				if f, ok := a.Config[p[2]]; ok {
					return f, nil
				}
			}
		}
	}
	return Field{}, fmt.Errorf("undeclared reference %s", ref)
}
func (m *Manifest) validatePredicate(s, phase string, used map[string]bool) error {
	if s == "" {
		return nil
	}
	p, e := parsePredicate(s)
	if e != nil {
		return e
	}
	var walk func(predicate) error
	walk = func(n predicate) error {
		for _, child := range n.children {
			if e := walk(child); e != nil {
				return e
			}
		}
		if n.ref == "" {
			return nil
		}
		f, e := m.reference(n.ref)
		if e != nil {
			return e
		}
		isAuth := strings.HasPrefix(n.ref, "auth.")
		if phase == "publisher" && !strings.HasPrefix(n.ref, "publisher.") {
			return fmt.Errorf("publisher predicates require publisher references")
		}
		if isAuth && phase != "proxy" && phase != "header" {
			return fmt.Errorf("auth references forbidden before selection")
		}
		if f.Type == "secret" {
			parts := strings.Split(n.ref, ".")
			managedToken := len(parts) == 3 && parts[0] == "auth" && m.Auth[parts[1]].Type == "oauth2"
			allowedPresence := phase == "header" || phase == "proxy" && !managedToken
			if n.op != "isDefined" || !allowedPresence {
				return fmt.Errorf("secret references require an allowed presence check; proxy rules cannot depend on OAuth tokens")
			}
		}
		if f.Type == "marker" && n.op != "isDefined" {
			return fmt.Errorf("method markers support only isDefined")
		}
		if n.op == "is" {
			if e := ValidateValue(f, n.literal); e != nil {
				return fmt.Errorf("predicate literal incompatible with %s: %w", n.ref, e)
			}
		}
		if f.Type != "secret" {
			used[n.ref] = true
		}
		return nil
	}
	return walk(p)
}
