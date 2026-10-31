return {
	scenario = {publisher = {}, config = {access = "read-write"}, auth_method = "token", auth_config = {token = "fixture-token"}},
	configure = function()
		requests = {}
		payload = '{"success":true,"errors":[],"messages":[],"result":{}}'
		http = {request = function(req)
			table.insert(requests, req)
			return fixture.operation({statusCode = 200, headers = {}, body = fixture.reader(payload)})
		end}
	end,
	run = function(cloudflare)
		local API = "https://api.cloudflare.com/client/v4"
		local ACCOUNT = "0123456789abcdef0123456789abcdef"
		local ZONE = API .. "/zones/023e105f4ecef8ad9ca31a8372d0c353"
		local RECORD = "372e67954025e0ba6aaa6d586b9e0b59"
		local function last() return requests[#requests] end
		local function sent(method, target, body)
			local req = last()
			assert(req.method == method and req.url == target, req.method .. " " .. req.url)
			assert(req.headers.Authorization == nil and req.headers.Accept[1] == "application/json")
			if body == nil then
				assert(req.body == nil and req.headers["Content-Type"] == nil, tostring(req.body))
			else
				assert(req.headers["Content-Type"][1] == "application/json" and json.encode(json.decode(req.body)) == json.encode(body), req.body)
			end
		end
		local function rejected(fn, expected)
			local before = #requests
			local ok, err = pcall(fn)
			assert(not ok and string.find(tostring(err), expected, 1, true), "wrong validation error: " .. tostring(err))
			assert(#requests == before, "invalid input reached Cloudflare")
		end

		local names = {}
		for name in cloudflare do table.insert(names, name) end
		table.sort(names)
		assert(table.concat(names, ",") == "createDnsRecord,createWorkerDeployment,deleteDnsRecord,getAccount,getDnsRecord,getPagesDeployment,getPagesDeploymentLogs,getPagesProject,getR2Bucket,getWorkerVersion,getZone,getZoneAnalytics,listAccounts,listDnsRecords,listPagesDeployments,listPagesProjects,listR2Buckets,listWorkerDeployments,listWorkerScripts,listWorkerVersions,listZones,purgeCache,rollbackPagesDeployment,updateDnsRecord",
			"wrong read-write surface: " .. table.concat(names, ","))

		payload = '{"success":true,"errors":[],"messages":[],"result":{"id":"' .. RECORD .. '","type":"A","name":"api.example.com","content":"198.51.100.4","proxied":true,"ttl":1,"comment":null}}'
		local record = cloudflare.createDnsRecord({zone_id = "023e105f4ecef8ad9ca31a8372d0c353", type = "A", name = "api.example.com", content = "198.51.100.4", proxied = true, ttl = 1})
		sent("POST", ZONE .. "/dns_records", {type = "A", name = "api.example.com", content = "198.51.100.4", proxied = true, ttl = 1})
		assert(record.result.id == RECORD)
		cloudflare.createDnsRecord({zone_id = "023e105f4ecef8ad9ca31a8372d0c353", type = "MX", name = "example.com", content = "mx.example.net", priority = 10, tags = {"owner:mail"}})
		sent("POST", ZONE .. "/dns_records", {type = "MX", name = "example.com", content = "mx.example.net", priority = 10, tags = {"owner:mail"}})

		cloudflare.updateDnsRecord({zone_id = "023e105f4ecef8ad9ca31a8372d0c353", dns_record_id = RECORD, content = "198.51.100.5", comment = "moved"})
		sent("PATCH", ZONE .. "/dns_records/" .. RECORD, {content = "198.51.100.5", comment = "moved"})
		-- An explicit JSON null clears a field.
		local NULL = json.decode("null")
		cloudflare.updateDnsRecord({zone_id = "023e105f4ecef8ad9ca31a8372d0c353", dns_record_id = RECORD, comment = NULL})
		assert(last().body == '{"comment":null}', last().body)

		payload = '{"success":true,"errors":[],"messages":[],"result":{"id":"' .. RECORD .. '"}}'
		assert(cloudflare.deleteDnsRecord({zone_id = "023e105f4ecef8ad9ca31a8372d0c353", dns_record_id = RECORD}).result.id == RECORD)
		sent("DELETE", ZONE .. "/dns_records/" .. RECORD)

		payload = '{"success":true,"errors":[],"messages":[],"result":{"id":"023e105f4ecef8ad9ca31a8372d0c353"}}'
		cloudflare.purgeCache({zone_id = "023e105f4ecef8ad9ca31a8372d0c353", files = {"https://www.example.com/app.css"}})
		sent("POST", ZONE .. "/purge_cache", {files = {"https://www.example.com/app.css"}})
		cloudflare.purgeCache({zone_id = "023e105f4ecef8ad9ca31a8372d0c353", purge_everything = true})
		sent("POST", ZONE .. "/purge_cache", {purge_everything = true})

		local versions = {{version_id = "bcf48806-b317-4351-9ee7-36e7d557d4de", percentage = 100}}
		payload = '{"success":true,"errors":[],"messages":[],"result":{"id":"6d4b3a52-0000-4b6c-9c1a-1d2e3f4a5b6c","strategy":"percentage","versions":[{"version_id":"bcf48806-b317-4351-9ee7-36e7d557d4de","percentage":100}]}}'
		local deployment = cloudflare.createWorkerDeployment({account_id = ACCOUNT, script_name = "api", strategy = "percentage", versions = versions,
			annotations = {["workers/message"] = "Roll back to 41"}})
		sent("POST", API .. "/accounts/" .. ACCOUNT .. "/workers/scripts/api/deployments",
			{strategy = "percentage", versions = versions, annotations = {["workers/message"] = "Roll back to 41"}})
		assert(deployment.result.versions[1].percentage == 100)

		cloudflare.rollbackPagesDeployment({account_id = ACCOUNT, project_name = "site", deployment_id = "4f0b3a52-3c5d-4b6c-9c1a-1d2e3f4a5b6c"})
		sent("POST", API .. "/accounts/" .. ACCOUNT .. "/pages/projects/site/deployments/4f0b3a52-3c5d-4b6c-9c1a-1d2e3f4a5b6c/rollback")

		-- A write answering without a body returns nil.
		payload = ""
		assert(cloudflare.deleteDnsRecord({zone_id = "023e105f4ecef8ad9ca31a8372d0c353", dns_record_id = RECORD}) == nil)
		assert(#requests == 10)

		rejected(function() cloudflare.createDnsRecord({zone_id = "023e105f4ecef8ad9ca31a8372d0c353", type = "A", content = "198.51.100.4"}) end, "name is required")
		rejected(function() cloudflare.createDnsRecord({zone_id = "023e105f4ecef8ad9ca31a8372d0c353", type = "A", name = "x", id = RECORD}) end, "createDnsRecord has no option id")
		rejected(function() cloudflare.updateDnsRecord({zone_id = "023e105f4ecef8ad9ca31a8372d0c353", dns_record_id = RECORD}) end, "updateDnsRecord needs a body field")
		rejected(function() cloudflare.updateDnsRecord({zone_id = "023e105f4ecef8ad9ca31a8372d0c353", content = "x"}) end, "dns_record_id is required")
		rejected(function() cloudflare.purgeCache({zone_id = "023e105f4ecef8ad9ca31a8372d0c353"}) end, "purgeCache needs a body field")
		rejected(function() cloudflare.purgeCache({zone_id = "023e105f4ecef8ad9ca31a8372d0c353", everything = true}) end, "purgeCache has no option everything")
		rejected(function() cloudflare.createWorkerDeployment({account_id = ACCOUNT, script_name = "api", versions = versions}) end, "strategy is required")
		rejected(function() cloudflare.createWorkerDeployment({account_id = ACCOUNT, script_name = "api", strategy = "percentage", versions = versions, force = true}) end,
			"createWorkerDeployment has no option force")
		rejected(function() cloudflare.rollbackPagesDeployment({account_id = ACCOUNT, project_name = "site", deployment_id = "x", force = true}) end,
			"rollbackPagesDeployment has no option force")
	end,
}
