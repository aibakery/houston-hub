package helpschema

import (
	"reflect"
	"testing"
)

func TestFields(t *testing.T) {
	source := `local PAGE: {string} = {"take", "skip"}
local FILTERS = {"status",
 "afterStart"}
local LOOP = LOOP
local NONE: {string} = table.freeze({})
`
	for _, tc := range []struct {
		definition string
		want       []string
		bad        bool
	}{
		{`query = list(FILTERS, PAGE, {"limit"}), doc = "reference"`, []string{"status", "afterStart", "take", "skip", "limit"}, false},
		{`query = join(PAGE, {"filter"})`, []string{"take", "skip", "filter"}, false},
		{`query = paged("status"), required = {"status"}`, []string{"status", "take", "skip"}, false},
		{`query = PAGE`, []string{"take", "skip"}, false},
		{`query = NONE`, []string{}, false},
		{`required = {"id"}`, []string{}, false},
		{`query = MISSING`, nil, true},
		{`query = LOOP`, nil, true},
		{`query = custom(PAGE)`, nil, true},
	} {
		got, err := Fields(source, tc.definition, "query")
		if tc.bad {
			if err == nil {
				t.Fatalf("expected error: %s", tc.definition)
			}
			continue
		}
		if err != nil || !reflect.DeepEqual(got, tc.want) {
			t.Fatalf("%s: %v %v", tc.definition, got, err)
		}
	}
}
