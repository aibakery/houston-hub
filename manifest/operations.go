package manifest

import (
	"bytes"
	"encoding/json"
	"fmt"
	"regexp"
)

// Operations is release metadata reviewed with the connector implementation.
// It is independent of discovery, categories and caller grants.
type Operations map[string]string

var operationNameRE = regexp.MustCompile(`^[A-Za-z_][A-Za-z0-9_]{0,63}$`)

func ParseOperations(raw []byte) (Operations, error) {
	decoder := json.NewDecoder(bytes.NewReader(raw))
	if err := scanJSON(decoder, "operations"); err != nil {
		return nil, err
	}
	var operations Operations
	if err := json.Unmarshal(raw, &operations); err != nil {
		return nil, err
	}
	return operations, operations.Validate()
}

func (operations Operations) Validate() error {
	for name, access := range operations {
		if !operationNameRE.MatchString(name) || (access != "read" && access != "write") {
			return fmt.Errorf("invalid operation access for %q", name)
		}
	}
	return nil
}

// Write fails closed even for callers who have a write grant.
func (operations Operations) Write(name string) (bool, error) {
	switch operations[name] {
	case "read":
		return false, nil
	case "write":
		return true, nil
	default:
		return false, fmt.Errorf("operation %q has no reviewed access classification", name)
	}
}
