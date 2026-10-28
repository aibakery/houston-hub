package main

import (
	"slices"
	"testing"
)

// Houston's Slack app serves every connection: users only choose an access level
// and authorize one workspace.
func TestSlackPublisherOwnedClient(t *testing.T) {
	m := parseManifest(t, "../../connectors/slack/houston.json")
	if !m.Auth["oauth"].PublisherClient() {
		t.Fatal("Slack OAuth client must belong to the publication")
	}
}

func TestSlackScopesAndAccessRoutes(t *testing.T) {
	m := parseManifest(t, "../../connectors/slack/houston.json")
	read := []string{
		"GET https://slack.com/api/auth.test",
		"GET https://slack.com/api/users.conversations?types=im",
		"GET https://slack.com/api/conversations.history?channel=C1",
		"GET https://slack.com/api/conversations.replies?channel=C1&ts=1.2",
		"GET https://slack.com/api/conversations.info?channel=C1",
		"GET https://slack.com/api/conversations.members?channel=C1",
		"GET https://slack.com/api/search.messages?query=hi",
		"GET https://slack.com/api/users.info?user=U1",
		"GET https://slack.com/api/users.list?limit=200",
		"GET https://slack.com/api/chat.getPermalink?channel=C1&message_ts=1.2",
		"GET https://slack.com/api/files.info?file=F1",
		"GET https://files.slack.com/files-pri/T1-F1/download/report.pdf",
		"GET https://files.slack.com/files-pri/T1-F1/download/100%25%20done.pdf",
	}
	writes := []string{
		"POST https://slack.com/api/chat.postMessage",
		"POST https://slack.com/api/chat.update",
		"POST https://slack.com/api/chat.delete",
		"POST https://slack.com/api/conversations.open",
		"POST https://slack.com/api/reactions.add",
		"POST https://slack.com/api/reactions.remove",
		"POST https://slack.com/api/files.getUploadURLExternal",
		"POST https://slack.com/api/files.completeUploadExternal",
	}
	upload := "POST https://files.slack.com/upload/v1/CwABAAAAXQoAAQ%2FBz%3D"
	denied := []string{
		"GET https://slack.com/api/chat.postMessage?channel=C1&text=hi",
		"GET https://slack.com/api/files.getUploadURLExternal?filename=a&length=1",
		"POST https://slack.com/api/oauth.v2.access",
		"GET https://slack.com/api/oauth.v2.access",
		"POST https://slack.com/api/auth.revoke",
		"POST https://slack.com/api/conversations.history",
		"GET https://slack.com/api/users.profile.set",
		"GET https://files.slack.com/upload/v1/signed",
		"POST https://files.slack.com/files-pri/T1-F1/download/report.pdf",
		"GET https://files.slack.com/files-pri/../upload/v1/signed",
		"GET https://slack.com.evil.test/api/auth.test",
		"GET https://evil.slack.com/api/auth.test",
	}
	readScopes := []string{"channels:read", "channels:history", "groups:read", "groups:history", "im:read", "im:history",
		"mpim:read", "mpim:history", "users:read", "search:read", "files:read"}
	for _, access := range []string{"read-only", "read-write"} {
		publisher := map[string]any{"client_id": "fixture-client", "client_secret": "fixture-secret"}
		r, err := m.Resolve(publisher, map[string]any{"access": access}, nil, "oauth")
		if err != nil {
			t.Fatal(err)
		}
		scopes := slices.Clone(readScopes)
		if access == "read-write" {
			scopes = append(scopes, "chat:write", "files:write", "im:write", "mpim:write", "reactions:write")
		}
		if !slices.Equal(r.Scopes, scopes) {
			t.Fatalf("access=%s scopes %v", access, r.Scopes)
		}
		r.Context.Auth["oauth"]["access_token"] = "xoxp-fixture"
		assertRoutes(t, r, "xoxp-fixture", true, read...)
		assertRoutes(t, r, "xoxp-fixture", access == "read-write", writes...)
		// Slack's signed upload URL authenticates itself; the user token must not reach it.
		assertAuthorizedRoutes(t, r, "", access == "read-write", upload)
		assertRoutes(t, r, "xoxp-fixture", false, denied...)
	}
}
