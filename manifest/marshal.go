package manifest

import "encoding/json"

// Union serialization must not invent properties of another method type. Empty
// route maps must survive a pinned-release roundtrip because they remove injection.
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
func (r AllowedRequest) MarshalJSON() ([]byte, error) {
	type plain AllowedRequest
	b, e := json.Marshal(plain(r))
	if e != nil {
		return nil, e
	}
	var v map[string]json.RawMessage
	if e = json.Unmarshal(b, &v); e != nil {
		return nil, e
	}
	if r.Headers != nil {
		v["headers"], e = json.Marshal(r.Headers)
		if e != nil {
			return nil, e
		}
	}
	return json.Marshal(v)
}
