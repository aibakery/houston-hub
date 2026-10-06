package interfaces

import (
	"encoding/json"
	"testing"
)

func TestGuards(t *testing.T) {
	defs, err := Resolve([]string{"files.metadata@1"})
	if err != nil {
		t.Fatal(err)
	}
	op, _ := OperationFor(defs, "statFile")
	for _, args := range [][]any{{"f"}} {
		if err := ValidateArguments(op, args); err != nil {
			t.Fatal(err)
		}
	}
	for _, args := range [][]any{{}, {""}, {1}, {"f", "extra"}} {
		if err := ValidateArguments(op, args); err == nil {
			t.Fatalf("accepted %#v", args)
		}
	}
	var value any
	json.Unmarshal([]byte(`{"id":"id:1","name":"Report","isFolder":false,"size":42}`), &value)
	if err := ValidateResult(op, value); err != nil {
		t.Fatal(err)
	}
	value.(map[string]any)["size"] = 1.5
	if err := ValidateResult(op, value); err == nil {
		t.Fatal("accepted fractional byte size")
	}
}
func TestConfiguredCompletenessAndDetachedRegistry(t *testing.T) {
	defs, _ := Resolve([]string{"mail.folders@1", "files.metadata@1"})
	active, err := Configured(defs, []string{"listMailFolders", "providerExtra"})
	if err != nil || len(active) != 1 {
		t.Fatalf("%v %v", active, err)
	}
	defs[0].Operations["invented"] = Operation{}
	if _, err := Configured(defs, []string{"listMailFolders"}); err == nil {
		t.Fatal("partial interface accepted")
	}
	fresh, _ := Resolve([]string{"mail.folders@1"})
	if len(fresh[0].Operations) != 1 {
		t.Fatal("registry mutated")
	}
}
