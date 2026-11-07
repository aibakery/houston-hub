package manifest

import (
	"encoding/json"
	"fmt"
)

// Proxy headers retain the existing string shorthand on serialization. Account
// headers keep their explicit object form, so existing release digests are stable.
func (h HeaderActions) MarshalJSON() ([]byte, error) {
	set := map[string]any(nil)
	if h.Set != nil {
		set = map[string]any{}
		for key, value := range h.Set {
			if value.If == "" {
				set[key] = value.Value
			} else {
				set[key] = value
			}
		}
	}
	return json.Marshal(struct {
		Set    map[string]any `json:"set,omitempty"`
		Remove []string       `json:"remove,omitempty"`
	}{set, h.Remove})
}

func (h *HeaderActions) UnmarshalJSON(data []byte) error {
	var raw struct {
		Set    map[string]json.RawMessage `json:"set,omitempty"`
		Remove []string                   `json:"remove,omitempty"`
	}
	if err := decode(data, &raw); err != nil {
		return err
	}
	h.Set = nil
	h.Remove = raw.Remove
	if raw.Set != nil {
		h.Set = map[string]HeaderValue{}
		for key, value := range raw.Set {
			var header HeaderValue
			if len(value) > 0 && value[0] == '"' {
				if err := json.Unmarshal(value, &header.Value); err != nil {
					return err
				}
			} else if err := json.Unmarshal(value, &header); err != nil {
				return err
			}
			h.Set[key] = header
		}
	}
	return nil
}

// Union serialization must not invent properties of another method type.
func (a AuthMethod) MarshalJSON() ([]byte, error) {
	type plain AuthMethod
	b, e := json.Marshal(plain(a))
	if e != nil {
		return nil, e
	}
	var v map[string]json.RawMessage
	if e = json.Unmarshal(b, &v); e != nil {
		return nil, e
	}
	if a.Type != "oauth2" {
		delete(v, "token_response")
		delete(v, "refresh_response")
	}
	return json.Marshal(v)
}

// OAuth account headers require a value even when it is explicitly empty.
func (h *HeaderValue) UnmarshalJSON(data []byte) error {

	type plain HeaderValue
	var value plain
	if err := decode(data, &value); err != nil {
		return err
	}
	var keys map[string]json.RawMessage
	if err := json.Unmarshal(data, &keys); err != nil {
		return err
	}
	if _, ok := keys["value"]; !ok {
		return fmt.Errorf("header value required")
	}
	*h = HeaderValue(value)
	return nil
}

// Omit HTTP header actions from database snapshots as well as pass-through rules.
func (a ProxyAction) MarshalJSON() ([]byte, error) {
	type plain ProxyAction
	var headers *HeaderActions
	if a.Headers.Set != nil || a.Headers.Remove != nil {
		headers = &a.Headers
	}
	return json.Marshal(struct {
		plain
		Headers *HeaderActions `json:"headers,omitempty"`
	}{plain(a), headers})
}
