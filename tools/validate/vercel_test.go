package main

import "testing"

// Vercel tokens always read and write, so the proxy enforces the access level. Environment
// variable reads return their values, so they need read-write too.
func TestVercelAccessRoutes(t *testing.T) {
	m := parseManifest(t, "../../connectors/vercel/houston.json")
	const api = "https://api.vercel.com"
	for _, access := range []string{"read-only", "read-write"} {
		r, err := m.Resolve(nil, map[string]any{"access": access, "team": "team_fixture"}, map[string]any{"token": "vcp_fixture"}, "token")
		if err != nil {
			t.Fatal(err)
		}
		assertRoutes(t, r, "vcp_fixture", true,
			"GET "+api+"/v2/user", "GET "+api+"/v10/projects?teamId=team_fixture", "GET "+api+"/v9/projects/web",
			"GET "+api+"/v7/deployments?projectId=web&state=READY,ERROR", "GET "+api+"/v13/deployments/web-abc.vercel.app",
			"GET "+api+"/v3/deployments/dpl_1/events?follow=0", "GET "+api+"/v1/projects/prj_1/deployments/dpl_1/runtime-logs",
			"GET "+api+"/v6/domains/example.com/config", "GET "+api+"/v9/projects/web/domains/www.example.com",
			"GET "+api+"/v2/teams?limit=5", "GET "+api+"/v5/domains", "GET "+api+"/v5/domains/example.com", "GET "+api+"/v9/projects/web/domains",
			"GET "+api+"/v1/projects/prj_1/promote/aliases?failedOnly=true")
		assertRoutes(t, r, "vcp_fixture", access == "read-write",
			"GET "+api+"/v10/projects/web/env?decrypt=true", "GET "+api+"/v1/projects/web/env/e1",
			"POST "+api+"/v13/deployments?forceNew=1", "POST "+api+"/v10/projects/prj_1/promote/dpl_1", "POST "+api+"/v1/projects/prj_1/rollback/dpl_1",
			"PATCH "+api+"/v12/deployments/dpl_1/cancel", "POST "+api+"/v10/projects/web/env", "PATCH "+api+"/v9/projects/web/env/e1",
			"DELETE "+api+"/v9/projects/web/env/e1")
		// Token management, shared team variables, bypass secrets, drains, deployment files and
		// project or domain deletion are not exposed, nor other hosts.
		assertRoutes(t, r, "vcp_fixture", false,
			"GET "+api+"/v6/user/tokens", "POST "+api+"/v3/user/tokens", "GET "+api+"/v1/env", "GET "+api+"/v1/env/e1",
			"PATCH "+api+"/v1/projects/web/protection-bypass", "GET "+api+"/v4/aliases", "GET "+api+"/v1/drains",
			"GET "+api+"/v8/deployments/dpl_1/files/f1", "POST "+api+"/v1/projects/web/token", "DELETE "+api+"/v9/projects/web",
			"PATCH "+api+"/v9/projects/web", "DELETE "+api+"/v13/deployments/dpl_1", "DELETE "+api+"/v6/domains/example.com",
			"POST "+api+"/v2/files", "POST "+api+"/login/oauth/token", "GET "+api+"/v9/projects/%2e%2e/env",
			"GET "+api+"/v10/projects/web/env/e1", "GET https://vercel.com/api/v2/user", "GET https://api.vercel.com.example.com/v2/user",
			"GET http://api.vercel.com:8080/v2/user")
	}
}
