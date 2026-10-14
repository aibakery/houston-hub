package main

import (
	"slices"
	"testing"
)

func TestDropboxScopesAndRoutes(t *testing.T) {
	m := parseManifest(t, "../../connectors/dropbox/houston.json")
	// Write scopes add to the read scopes, so narrowing a caller to read-only keeps a granted set.
	readScopes := []string{"account_info.read", "files.metadata.read", "files.content.read", "sharing.read", "file_requests.read"}
	writeScopes := []string{"files.metadata.write", "files.content.write", "sharing.write", "file_requests.write"}
	for _, access := range []string{"read-only", "read-write"} {
		r, err := m.Resolve(nil, map[string]any{"access": access, "client_id": "fixture-app-key", "client_secret": "fixture-secret"}, nil, "oauth")
		if err != nil {
			t.Fatal(err)
		}
		scopes := readScopes
		if access == "read-write" {
			scopes = slices.Concat(readScopes, writeScopes)
		}
		if !slices.Equal(r.Scopes, scopes) {
			t.Fatalf("access=%s scopes %v", access, r.Scopes)
		}
		r.Context.Auth["oauth"]["access_token"] = "fixture-token"
		assertRoutes(t, r, "fixture-token", true,
			"POST https://api.dropboxapi.com/2/files/list_folder", "POST https://api.dropboxapi.com/2/sharing/revoke_shared_link",
			"POST https://content.dropboxapi.com/2/files/download", "POST https://content.dropboxapi.com/2/files/upload")
		// The token never reaches the OAuth endpoint, other hosts or non-POST requests.
		assertRoutes(t, r, "fixture-token", false,
			"POST https://api.dropboxapi.com/oauth2/token", "GET https://api.dropboxapi.com/2/files/list_folder",
			"POST https://notify.dropboxapi.com/2/files/list_folder/longpoll", "GET https://dl.dropboxusercontent.com/apitl/1/file",
			"POST https://api.dropboxapi.com.evil.test/2/files/list_folder")
	}
}
