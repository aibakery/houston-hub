package manifest

import (
	"fmt"
	"net/http"
	"reflect"
	"strings"
)

// WithConnectionLabels overlays presentation rules without expanding the pinned
// connector's request authority. Only the selected request can run, so other
// methods' label requests neither authorize destinations nor require inputs.
func (m *Manifest) WithConnectionLabels(labels []ConnectionLabelRule, c Context) (*Manifest, error) {
	next := *m
	next.ConnectionLabel = labels
	if err := next.Validate(); err != nil {
		return nil, err
	}
	rule, err := next.SelectConnectionLabel(c)
	if err != nil {
		return nil, err
	}
	if rule == nil || rule.Request == nil {
		return &next, nil
	}
	request, err := prepareConnectionLabelRequest(rule.Request, c)
	if err != nil {
		return nil, err
	}
	method := m.Auth[c.SelectedAuth]
	var approved []*ConnectionLabelRequest
	if account := method.Account; account != nil {
		approved = append(approved, &ConnectionLabelRequest{URL: account.URL, Method: account.Method, Headers: account.Headers})
	}
	if shared := method.Shared; shared != nil {
		approved = append(approved, &ConnectionLabelRequest{URL: shared.URL, Method: shared.Method, Headers: shared.Headers, Body: shared.Body})
	}
	previous, err := m.SelectConnectionLabel(c)
	if err != nil {
		return nil, err
	}
	if previous != nil && previous.Request != nil {
		approved = append(approved, previous.Request)
	}
	for _, recipe := range approved {
		allowed, err := prepareConnectionLabelRequest(recipe, c)
		if err == nil && reflect.DeepEqual(allowed, request) {
			return &next, nil
		}
	}
	// General proxy routes may permit writes. Only GET can become a new
	// background lookup; POST requires an exact existing lifecycle recipe.
	if request.Method != http.MethodGet {
		return nil, fmt.Errorf("connection label request is outside the pinned connector's authority")
	}
	var active ProxyRules
	for _, proxy := range m.Proxy {
		if proxy.Match.Protocol != "http" {
			continue
		}
		enabled, err := EvaluatePredicate(proxy.If, c)
		if err != nil {
			return nil, err
		}
		if enabled {
			active = append(active, proxy)
		}
	}
	active, err = active.render(c)
	if err != nil {
		return nil, err
	}
	active, err = active.RenderPaths(c)
	if err != nil {
		return nil, err
	}
	proxy, err := active.HTTPRecipe(request.Method, request.URL, nil)
	if err == nil {
		// Ordinary callers may add public provider metadata such as Accept or
		// preflight headers. Do not let an overlay add a saved credential under
		// another header: private references must come from the pinned recipe.
		caller := http.Header{}
		for name, header := range rule.Request.Headers {
			if m.connectionLabelTemplate(header.Value, map[string]bool{}) == nil {
				if values, exists := request.Headers[http.CanonicalHeaderKey(name)]; exists {
					caller[http.CanonicalHeaderKey(name)] = append([]string(nil), values...)
				}
			}
		}
		headers, headerErr := proxy.Prepare(c, caller)
		target, targetErr := proxy.PrepareURL(c)
		if headerErr == nil && targetErr == nil && target == request.URL && reflect.DeepEqual(headers, request.Headers) {
			return &next, nil
		}
	}
	return nil, fmt.Errorf("connection label request is outside the pinned connector's authority")
}

type preparedConnectionLabelRequest struct {
	URL, Method string
	Headers     http.Header
	Body        map[string]any
}

func prepareConnectionLabelRequest(recipe *ConnectionLabelRequest, c Context) (preparedConnectionLabelRequest, error) {
	var out preparedConnectionLabelRequest
	var err error
	out.URL, out.Headers, err = recipe.Prepare(c)
	if err != nil {
		return out, err
	}
	out.Method, out.Body = recipe.Method, recipe.Body
	if out.Method == "" {
		out.Method = http.MethodGet
	}
	return out, nil
}

// Prepare renders a label request without allowing provider method-override
// parameters or headers to change its declared read operation.
func (recipe ConnectionLabelRequest) Prepare(c Context) (string, http.Header, error) {
	rendered, err := RenderString(recipe.URL, c)
	if err != nil || HTTPSURL(rendered, true) != nil {
		return "", nil, fmt.Errorf("connection label destination unavailable")
	}
	headers, err := (HTTPRecipe{URL: rendered, Headers: recipe.Headers}).Prepare(c, nil)
	if err != nil {
		return "", nil, err
	}
	if recipe.Body != nil {
		headers.Set("Content-Type", "application/json")
	}
	if err := methodOverride(rendered, headers); err != nil {
		return "", nil, err
	}
	return rendered, headers, nil
}

// SelectConnectionLabel does not resolve inputs or perform requests. Presentation
// failures must not change connection setup or runtime authorization.
func (m *Manifest) SelectConnectionLabel(c Context) (*ConnectionLabelRule, error) {
	for i := range m.ConnectionLabel {
		rule := &m.ConnectionLabel[i]
		match, err := EvaluatePredicate(rule.If, c)
		if err != nil {
			return nil, err
		}
		if match {
			return rule, nil
		}
	}
	return nil, nil
}

func (m *Manifest) connectionLabelTemplate(value string, used map[string]bool) error {
	refs, err := TemplateReferences(value)
	if err != nil {
		return err
	}
	for _, ref := range refs {
		field, err := m.reference(ref)
		if err != nil {
			return err
		}
		if field.Type == "secret" || strings.HasPrefix(ref, "publisher.") {
			return fmt.Errorf("connection labels require public connection values")
		}
		used[ref] = true
	}
	return nil
}

func (m *Manifest) validateConnectionLabels(used map[string]bool) error {
	for i, rule := range m.ConnectionLabel {
		if err := m.validateConnectionLabel(rule, used); err != nil {
			return fmt.Errorf("connection_label[%d]: %w", i, err)
		}
	}
	return nil
}

func (m *Manifest) validateConnectionLabel(rule ConnectionLabelRule, used map[string]bool) error {
	if err := m.validatePredicate(rule.If, "connection_label", used); err != nil {
		return err
	}
	if (rule.Value == nil) == (rule.Request == nil) {
		return fmt.Errorf("exactly one of value or request is required")
	}
	if rule.Value != nil {
		if rule.Select != "" {
			return fmt.Errorf("select requires request")
		}
		return m.connectionLabelTemplate(*rule.Value, used)
	}
	if !validPointer(rule.Select) {
		return fmt.Errorf("request requires a valid select pointer")
	}
	r := rule.Request
	if r.Method != "" && r.Method != "GET" && r.Method != "POST" {
		return fmt.Errorf("connection label requests use GET or POST")
	}
	if r.Body != nil && r.Method != "POST" {
		return fmt.Errorf("connection label body requires POST")
	}
	for _, value := range r.Body {
		if _, err := scalarString(value); err != nil {
			return fmt.Errorf("connection label body values must be literal scalars")
		}
		if s, ok := value.(string); ok && strings.Contains(s, "{{") {
			return fmt.Errorf("connection label body values must be literal scalars")
		}
	}
	if err := m.connectionLabelTemplate(r.URL, used); err != nil {
		return err
	}
	// Schemes remain literal; only public connection values can supply host or
	// path parts. The transport validates the fully rendered HTTPS URL again.
	if !strings.HasPrefix(r.URL, "https://") {
		return fmt.Errorf("connection label URL requires literal https:// scheme")
	}
	parts, err := parseTemplate(r.URL)
	if err != nil {
		return err
	}
	var sample strings.Builder
	for _, part := range parts {
		if len(part.refs) == 0 {
			sample.WriteString(part.text)
		} else {
			sample.WriteString("value")
		}
	}
	if err := HTTPSURL(sample.String(), true); err != nil {
		return err
	}
	if err := m.validateHeaders(r.Headers, used); err != nil {
		return err
	}
	// The URL is public, but publisher-owned credentials must still never be
	// delivered to a recipient selected by a connection setting.
	host := strings.TrimPrefix(r.URL, "https://")
	if end := strings.IndexAny(host, "/?#"); end >= 0 {
		host = host[:end]
	}
	credentials := make([]string, 0, len(r.Headers))
	for _, header := range r.Headers {
		credentials = append(credentials, header.Value)
	}
	for _, method := range m.Auth {
		if method.Type == "composio" {
			credentials = append(credentials, method.APIKey)
		}
	}
	return m.publisherRecipient(credentials, []string{host})
}
