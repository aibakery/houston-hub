package main

import (
	"slices"
	"testing"

	"github.com/aibakery/houston-hub/manifest"
)

// resolveMicrosoft resolves a Microsoft Graph bundle for an access level and checks it requests
// a refresh token and the profile plus exactly the given data scopes.
func resolveMicrosoft(t *testing.T, m *manifest.Manifest, access string, scopes ...string) *manifest.Resolved {
	t.Helper()
	publisher := map[string]any{"client_id": "publisher-client", "client_secret": "publisher-secret"}
	r, err := m.Resolve(publisher, map[string]any{"access": access}, nil, "oauth")
	if err != nil {
		t.Fatal(err)
	}
	if want := append([]string{"offline_access", "User.Read"}, scopes...); !slices.Equal(r.Scopes, want) {
		t.Fatalf("access=%s scopes %v", access, r.Scopes)
	}
	r.Context.Auth["oauth"]["access_token"] = "fixture-token"
	return r
}

// deniedEverywhere lists Graph routes neither connector may reach: Microsoft's token endpoint,
// batches that could wrap writes, other users and APIs, sharing-link redemption and lookalike hosts.
var deniedEverywhere = []string{
	"POST https://login.microsoftonline.com/common/oauth2/v2.0/token", "POST https://graph.microsoft.com/v1.0/$batch",
	"GET https://graph.microsoft.com/v1.0/users/other@example.com/messages", "GET https://graph.microsoft.com/beta/me/messages",
	"GET https://graph.microsoft.com/v1.0/me/events", "GET https://graph.microsoft.com/v1.0/shares/u!abc/driveItem",
	"GET https://graph.microsoft.com.evil.test/v1.0/me", "GET https://graph.microsoft.com/v1.0/me/messages/%2e%2e/x",
	"GET https://graph.microsoft.com/v1.0/me/drive/items/f1%2F..%2Fx",
}

func TestOutlookScopesAndRoutes(t *testing.T) {
	m := parseManifest(t, "../../connectors/outlook/houston.json")
	const api = "https://graph.microsoft.com/v1.0/me"
	// Read and draft (custom) asks for Mail.ReadWrite only, but Microsoft may keep Mail.Send from an
	// earlier grant to the same app: these routes are what refuse its sends.
	for access, scopes := range map[string][]string{
		"read-only":  {"Mail.Read"},
		"custom":     {"Mail.ReadWrite"},
		"read-write": {"Mail.ReadWrite", "Mail.Send"},
	} {
		r := resolveMicrosoft(t, m, access, scopes...)
		reads := []string{"GET " + api + "?$select=userPrincipalName", "GET " + api + "/mailFolders?$top=100", "GET " + api + "/mailFolders/inbox",
			"GET " + api + "/mailFolders/F1/childFolders", "GET " + api + "/mailFolders/inbox/messages?%24skip=10",
			"GET " + api + "/messages?$search=%22from%3Aana%22", "GET " + api + "/messages/AAMk-_%3D", "GET " + api + "/messages/m1/attachments",
			"GET " + api + "/messages/m1/attachments/A1%3D/$value"}
		assertRoutes(t, r, "fixture-token", true, reads...)
		assertRejectsMethodOverrides(t, r, reads...)
		drafts := []string{"POST " + api + "/messages", "POST " + api + "/messages/m1/attachments", "POST " + api + "/messages/m1/createReply",
			"POST " + api + "/messages/m1/createReplyAll", "POST " + api + "/messages/m1/createForward",
			"PATCH " + api + "/messages/m1", "DELETE " + api + "/messages/m1"}
		assertRoutes(t, r, "fixture-token", access != "read-only", drafts...)
		sends := []string{"POST " + api + "/sendMail", "POST " + api + "/messages/m1/send", "POST " + api + "/messages/m1/reply",
			"POST " + api + "/messages/m1/replyAll", "POST " + api + "/messages/m1/forward", "POST " + api + "/messages/m1/move",
			"POST " + api + "/mailFolders", "POST " + api + "/mailFolders/F1/childFolders"}
		assertRoutes(t, r, "fixture-token", access == "read-write", sends...)
		if access != "read-only" {
			assertRejectsMethodOverrides(t, r, drafts...)
		}
		// Routes the connector never calls stay denied, including the mailbox's MIME, permanent
		// deletes, copies, folder changes and OneDrive.
		assertRoutes(t, r, "fixture-token", false, append(deniedEverywhere,
			"GET "+api+"/messages/m1/$value", "POST "+api+"/messages/m1/permanentDelete", "POST "+api+"/messages/m1/copy",
			"POST "+api+"/messages/m1/attachments/createUploadSession", "PATCH "+api+"/mailFolders/F1", "DELETE "+api+"/mailFolders/F1",
			"GET "+api+"/drive", "PUT "+api+"/messages/m1", "GET "+api+"/mailFolders/inbox/messages/delta",
			"POST "+api+"/mailFolders/inbox/messages", "PATCH "+api+"/messages/m1/attachments/A1", "DELETE "+api+"/messages/m1/attachments/A1")...)
	}
}

func TestOneDriveScopesAndRoutes(t *testing.T) {
	m := parseManifest(t, "../../connectors/onedrive/houston.json")
	const api = "https://graph.microsoft.com/v1.0/me/drive"
	for access, scope := range map[string]string{"read-only": "Files.Read", "read-write": "Files.ReadWrite"} {
		r := resolveMicrosoft(t, m, access, scope)
		reads := []string{"GET " + api, "GET " + api + "/root", "GET " + api + "/root/children?$skiptoken=MjAx",
			"GET " + api + "/root/search(q='O%27%27Brien%20plan')", "GET " + api + "/root:/Documents/Q3%20report.pdf:",
			"GET " + api + "/items/D4648F06C91D9D3D%2154927", "GET " + api + "/items/f1/children", "GET " + api + "/items/f1/content?format=pdf",
			"GET " + api + "/items/f1/permissions",
			// Business accounts may page through drive-keyed links.
			"GET https://graph.microsoft.com/v1.0/drives/b!x-1/items/01ABC/children?%24skiptoken=UGFn",
			"GET https://graph.microsoft.com/v1.0/drives/b!x-1/root/children?%24skiptoken=UGFn"}
		assertRoutes(t, r, "fixture-token", true, reads...)
		assertRejectsMethodOverrides(t, r, reads...)
		// Content redirects to preauthenticated hosts, which never receive the token.
		assertAuthorizedRoutes(t, r, "", true,
			"GET https://contoso-my.sharepoint.com/personal/ana/_layouts/15/download.aspx?UniqueId=1&tempauth=abc",
			"GET https://b0mpua.by3301.files.1drv.com/y23vmag", "GET https://my.microsoftpersonalcontent.com/y/abc",
			"GET https://public.bn1304.livefilestore.com/y4m", "GET https://westus1-mediap.svc.ms/transform/pdf?provider=spo")
		writes := []string{"POST " + api + "/root/children", "POST " + api + "/items/f1/children", "POST " + api + "/items/f1/copy",
			"POST " + api + "/items/f1/createLink", "POST " + api + "/items/f1/invite", "PATCH " + api + "/items/f1", "DELETE " + api + "/items/f1",
			"DELETE " + api + "/items/f1/permissions/p1", "PUT " + api + "/items/f1/content",
			"PUT " + api + "/root:/report.pdf:/content?@microsoft.graph.conflictBehavior=rename",
			"PUT " + api + "/items/D4648F06C91D9D3D%21101:/Q3%20plan.pdf:/content?@microsoft.graph.conflictBehavior=replace"}
		assertRoutes(t, r, "fixture-token", access == "read-write", writes...)
		if access == "read-write" {
			assertRejectsMethodOverrides(t, r, writes...)
		}
		// Routes the connector never calls stay denied: upload sessions, permanent deletes, other
		// drives' items, mail, writes to preauthenticated hosts and lookalike content hosts. The proxy
		// cannot filter queries, so the connector refuses $expand in nextLinks itself.
		assertRoutes(t, r, "fixture-token", false, append(deniedEverywhere,
			"POST "+api+"/items/f1/createUploadSession", "POST "+api+"/items/f1:/x.pdf:/createUploadSession",
			"POST "+api+"/items/f1/permanentDelete", "GET https://graph.microsoft.com/v1.0/drives/b!x-1/items/01ABC",
			"GET https://graph.microsoft.com/v1.0/me/messages", "PATCH "+api+"/items/f1/permissions/p1", "PUT "+api+"/items/f1",
			"GET "+api+"/sharedWithMe", "GET "+api+"/items/f1/thumbnails")...)
		assertRoutes(t, r, "", false, "PUT https://contoso-my.sharepoint.com/upload", "GET https://sharepoint.com/x",
			"GET https://contoso.sharepoint.com.evil.test/x", "GET https://evil.test/contoso.sharepoint.com/x")
	}
}
