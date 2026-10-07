package manifest

import (
	"encoding/json"
	"fmt"
)

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
	if a.Type == "manual" {
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
