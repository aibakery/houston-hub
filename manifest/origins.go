package manifest

import (
	"bytes"
	"fmt"
)

// HTTPOrigins expands grouped source declarations into the existing origin map.
// Validation, credential resolution, matching and pinned snapshots share this form.
type HTTPOrigins map[string]HTTPOrigin

type HTTPOriginGroup struct {
	Match  []string    `json:"match"`
	Config *HTTPOrigin `json:"config"`
}

func (o *HTTPOrigins) UnmarshalJSON(data []byte) error {
	data = bytes.TrimSpace(data)
	if len(data) == 0 || data[0] != '[' {
		var origins map[string]HTTPOrigin
		if err := decode(data, &origins); err != nil {
			return err
		}
		*o = origins
		return nil
	}
	var groups []HTTPOriginGroup
	if err := decode(data, &groups); err != nil {
		return err
	}
	origins := HTTPOrigins{}
	for _, group := range groups {
		if len(group.Match) == 0 || group.Config == nil {
			return fmt.Errorf("origin group requires nonempty match and config")
		}
		for _, origin := range group.Match {
			if _, exists := origins[origin]; exists {
				return fmt.Errorf("duplicate origin in groups")
			}
			origins[origin] = *group.Config
		}
	}
	*o = origins
	return nil
}
