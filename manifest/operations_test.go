package manifest

import "testing"

func TestOperationAccessFailsClosed(t *testing.T) {
	operations, err := ParseOperations([]byte(`{"listMessages":"read","sendMessage":"write"}`))
	if err != nil {
		t.Fatal(err)
	}
	for _, tc := range []struct {
		name          string
		write, denied bool
	}{
		{"listMessages", false, false}, {"sendMessage", true, false}, {"unknown", false, true},
	} {
		write, err := operations.Write(tc.name)
		if write != tc.write || (err != nil) != tc.denied {
			t.Fatalf("%s: write=%v err=%v", tc.name, write, err)
		}
	}
	for _, raw := range []string{`{"read":"admin"}`, `{"http.request":"read"}`, `{"read":null}`, `{"read":"read","read":"write"}`} {
		if _, err := ParseOperations([]byte(raw)); err == nil {
			t.Fatalf("accepted %s", raw)
		}
	}
}
