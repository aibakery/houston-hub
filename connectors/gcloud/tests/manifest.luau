return {
	contract = function(m)
		local AUTH = "https://www.googleapis.com/auth/"
		local SCOPES = {
			["read-only"] = {"cloud-platform.read-only", "run.readonly", "monitoring.read", "compute.readonly", "cloud-billing.readonly"},
			["read-write"] = {"cloud-platform"},
		}
		local run = "https://run.googleapis.com/v2/projects/my-project-123/locations/us-central1"
		local compute = "https://compute.googleapis.com/compute/v1/projects/my-project-123"
		local build = "https://cloudbuild.googleapis.com/v1/projects/my-project-123/locations/global"
		local storage = "https://storage.googleapis.com/storage/v1/b/assets"
		local reads = {
			"GET https://cloudresourcemanager.googleapis.com/v3/projects:search?query=state%3AACTIVE",
			"GET https://cloudresourcemanager.googleapis.com/v3/projects/my-project-123",
			"GET https://run.googleapis.com/v1/projects/my-project-123/locations",
			"GET " .. run .. "/services", "GET " .. run .. "/services/api", "GET " .. run .. "/services/api/revisions",
			"GET " .. run .. "/services/api/revisions/api-00042-xyz", "GET " .. run .. "/jobs", "GET " .. run .. "/jobs/export",
			"GET " .. run .. "/jobs/export/executions", "GET " .. run .. "/jobs/export/executions/export-abc12",
			"GET " .. run .. "/jobs/export/executions/export-abc12/tasks",
			"POST https://logging.googleapis.com/v2/entries:list",
			"GET https://logging.googleapis.com/v2/projects/my-project-123/logs",
			"GET https://storage.googleapis.com/storage/v1/b?project=my-project-123", "GET " .. storage, "GET " .. storage .. "/o?prefix=reports%2F",
			"GET " .. storage .. "/o/reports%2F2026-10.csv", "GET " .. storage .. "/o/a%3Ab%2F..x?alt=media",
			"GET https://monitoring.googleapis.com/v3/projects/my-project-123/timeSeries?filter=x",
			"GET https://monitoring.googleapis.com/v3/projects/my-project-123/alertPolicies",
			"GET https://monitoring.googleapis.com/v3/projects/my-project-123/uptimeCheckConfigs",
			"POST https://monitoring.googleapis.com/v1/projects/my-project-123/location/global/prometheus/api/v1/query",
			"POST https://monitoring.googleapis.com/v1/projects/my-project-123/location/global/prometheus/api/v1/query_range",
			"GET " .. compute .. "/aggregated/instances", "GET " .. compute .. "/zones/us-central1-a/instances/worker-1",
			"GET https://cloudbilling.googleapis.com/v1/billingAccounts", "GET https://cloudbilling.googleapis.com/v1/projects/my-project-123/billingInfo",
			"GET https://serviceusage.googleapis.com/v1/projects/my-project-123/services?filter=state%3AENABLED",
			"GET https://artifactregistry.googleapis.com/v1/projects/my-project-123/locations/us-central1/repositories",
			"GET https://artifactregistry.googleapis.com/v1/projects/my-project-123/locations/us-central1/repositories/containers/dockerImages",
		}
		local writes = {
			"GET " .. run .. "/operations/op-1",
			"PATCH " .. run .. "/services/api?updateMask=traffic",
			"POST " .. run .. "/jobs/export:run", "POST " .. run .. "/jobs/export/executions/export-abc12:cancel",
			"GET " .. compute .. "/zones/us-central1-a/operations/operation-1",
			"POST " .. compute .. "/zones/us-central1-a/instances/worker-1/start", "POST " .. compute .. "/zones/us-central1-a/instances/worker-1/stop",
			"POST " .. compute .. "/zones/us-central1-a/instances/worker-1/reset",
			"POST https://storage.googleapis.com/upload/storage/v1/b/assets/o?uploadType=media&name=a%2Fb.csv",
			"DELETE " .. storage .. "/o/reports%2F2026-10.csv",
			"GET " .. build .. "/builds", "GET " .. build .. "/builds/b-1", "GET " .. build .. "/triggers",
			"POST " .. build .. "/builds/b-1:retry", "POST " .. build .. "/builds/b-1:cancel",
		}
		for access, scopes in SCOPES do
			local r, err = m.resolve({client_id = "publisher-client", client_secret = "publisher-secret"}, {access = access}, nil, "oauth")
			assert(r and not err, tostring(err))
			local want = {AUTH .. "userinfo.email"}
			for _, scope in scopes do table.insert(want, AUTH .. scope) end
			assert(m.equal(r.Scopes, want), "requested OAuth scopes for " .. access)
			r.Context.Auth.oauth.access_token = "fixture-token"
			m.routes(r, "Bearer fixture-token", true, reads)
			m.rejectOverrides(r, reads)
			m.routes(r, "Bearer fixture-token", access == "read-write", writes)
			if access == "read-write" then m.rejectOverrides(r, writes) end
			-- The token never reaches Google's token endpoint, batch endpoints, lookalike hosts, other
			-- Google APIs, secret payloads, IAM changes, other custom methods or routes the connector
			-- never calls, at either access level.
			m.routes(r, "Bearer fixture-token", false, {
				"POST https://oauth2.googleapis.com/token",
				"GET https://www.googleapis.com/oauth2/v2/userinfo",
				"POST https://run.googleapis.com/batch",
				"POST https://storage.googleapis.com/batch/storage/v1",
				"POST https://compute.googleapis.com/batch/compute/v1",
				"GET https://run.googleapis.com.evil.test/v2/projects/my-project-123/locations/us-central1/services",
				"GET https://evil.run.googleapis.com/v2/projects/my-project-123/locations/us-central1/services",
				"GET https://secretmanager.googleapis.com/v1/projects/my-project-123/secrets/db/versions/latest:access",
				"GET https://bigquery.googleapis.com/bigquery/v2/projects/my-project-123/datasets",
				"POST https://cloudresourcemanager.googleapis.com/v3/projects/my-project-123:setIamPolicy",
				"POST https://cloudresourcemanager.googleapis.com/v3/projects/my-project-123:getIamPolicy",
				"DELETE https://cloudresourcemanager.googleapis.com/v3/projects/my-project-123",
				"GET https://cloudresourcemanager.googleapis.com/v3/projects/my-project-123:undelete",
				"GET " .. run .. "/services/api:getIamPolicy",
				"POST " .. run .. "/services/api:setIamPolicy",
				"DELETE " .. run .. "/services/api",
				"POST " .. run .. "/services",
				"POST " .. run .. "/jobs/export:delete",
				"POST " .. run .. "/jobs/export%3Arun",
				"GET " .. compute .. "/zones/us-central1-a/instances/worker-1/serialPort",
				"GET " .. compute .. "/zones/us-central1-a/instances/worker-1/getSerialPortOutput",
				"POST " .. compute .. "/zones/us-central1-a/instances/worker-1/setMetadata",
				"DELETE " .. compute .. "/zones/us-central1-a/instances/worker-1",
				"POST https://logging.googleapis.com/v2/entries:write",
				"POST https://logging.googleapis.com/v2/entries:tail",
				"DELETE https://logging.googleapis.com/v2/projects/my-project-123/logs/syslog",
				"PATCH " .. storage,
				"DELETE " .. storage,
				"GET " .. storage .. "/iam",
				"POST https://storage.googleapis.com/resumable/upload/storage/v1/b/assets/o",
				"POST https://serviceusage.googleapis.com/v1/projects/my-project-123/services/run.googleapis.com:enable",
				"PUT https://cloudbilling.googleapis.com/v1/projects/my-project-123/billingInfo",
				"POST https://cloudbuild.googleapis.com/v1/projects/my-project-123/builds",
				"POST " .. build .. "/triggers/t-1:run",
				"POST https://monitoring.googleapis.com/v3/projects/my-project-123/alertPolicies",
			})
		end
	end,
}
