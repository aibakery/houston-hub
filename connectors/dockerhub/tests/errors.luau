-- Invalid input never reaches Docker Hub, and its errors and bad bodies map to clear failures.
return {
	scenario = {publisher = {}, config = {}, auth_method = "", auth_config = {}},
	configure = function()
		calls = 0
		status, payload, responseHeaders = 200, "{}", {}
		http = {request = function(req)
			calls += 1
			if requestError then error(requestError, 0) end
			assert(string.sub(req.url, 1, 26) == "https://hub.docker.com/v2/", req.url)
			-- A body whose read fails stands in for a stalled or dropped error body.
			local body = if readError
				then {readAll = function() error(readError, 0) end, readPrefix = function() error(readError, 0) end, close = function() end}
				else fixture.reader(payload)
			return fixture.operation({statusCode = status, headers = responseHeaders, body = body})
		end}
	end,
	run = function(dockerhub)
		local function rejected(fn, expected)
			local before = calls
			local ok, err = pcall(fn)
			assert(not ok and string.find(tostring(err), expected, 1, true), "wrong validation error: " .. tostring(err))
			assert(calls == before, "invalid input reached Docker Hub")
		end
		local function repo(opts) return function() dockerhub.getRepository(opts) end end
		local function tags(opts)
			return function()
				opts.namespace, opts.repository = "library", "nginx"
				dockerhub.listTags(opts)
			end
		end

		for _, namespace in {"", "Library", "-x", "_x", ".x", "a/b", ".", "..", "%2e%2e", "lib rary", string.rep("a", 256), 42, {"library"}} do
			rejected(repo({namespace = namespace, repository = "nginx"}), "namespace must be a Docker Hub user or organization name in lowercase")
		end
		for _, repository in {"", "Nginx", ".", "..", ".nginx", "-nginx", "nginx/tags", "nginx?x=1", "nginx%2F", "ngi nx", string.rep("n", 256)} do
			rejected(repo({namespace = "library", repository = repository}), "repository must be a repository name in lowercase")
		end
		for _, tag in {"", ".", "..", ".latest", "-latest", "a/b", "a:b", "a b", "a%2F", string.rep("t", 129), 1} do
			rejected(function() dockerhub.getTag({namespace = "library", repository = "nginx", tag = tag}) end, "tag must be a tag such as latest")
		end
		rejected(repo({repository = "nginx"}), "namespace must be")
		rejected(function() dockerhub.listRepositories() end, "namespace must be")
		rejected(function() dockerhub.listRepositories("docker") end, "opts must be an object")
		rejected(function() dockerhub.listRepositories({"docker"}) end, "opts must have named fields")
		rejected(repo({namespace = "library", repository = "nginx", page = 1}), "getRepository has no option page")
		rejected(function() dockerhub.listRepositories({namespace = "docker", ordering = "stars"}) end,
			"ordering must be one of name, -name, last_updated, -last_updated, pull_count, -pull_count")
		rejected(function() dockerhub.listRepositories({namespace = "docker", ordering = {"name"}}) end, "ordering must be one of")
		-- Tags can't be ordered: Docker Hub's undocumented ordering sorts names backwards.
		rejected(tags({ordering = "name"}), "listTags has no option ordering")
		for _, value in {0, -1, 1.5, "2", 1001} do
			rejected(tags({page = value}), "page must be an integer from 1 to 1000")
		end
		rejected(function() dockerhub.listRepositories({namespace = "docker", page = 101, page_size = 1}) end, "page must be an integer from 1 to 100")
		for _, value in {0, 101, 2.5, "10"} do
			rejected(tags({page_size = value}), "page_size must be an integer from 1 to 100")
		end
		for _, value in {"", "  ", string.rep("x", 256), 5, {"alpine"}} do
			rejected(tags({name = value}), "name must be a nonempty string of at most 255 bytes")
		end
		-- A next URL is not a page number, so another route can't be smuggled in.
		rejected(tags({page = "https://hub.docker.com/v2/orgs/docker/members?page=2"}), "page must be an integer")
		rejected(tags({next = "https://hub.docker.com/v2/namespaces/library/repositories/nginx/tags?page=2"}), "listTags has no option next")
		-- Pages beyond what Docker Hub lists without signing in fail before any request, with Docker Hub's default page size of 10.
		local reach = "Houston reads Docker Hub without signing in, so lists stop after the first 100 repositories or 1,000 tags"
		rejected(function() dockerhub.listRepositories({namespace = "docker", page = 11}) end, "listRepositories: " .. reach)
		rejected(function() dockerhub.listRepositories({namespace = "docker", page = 2, page_size = 100}) end, "listRepositories: " .. reach)
		rejected(tags({page = 101}), "listTags: " .. reach)
		rejected(tags({page = 11, page_size = 100}), "listTags: " .. reach)

		local function upstream(code, body, headers, expected, absent, call)
			status, payload, responseHeaders = code, body, headers
			local before = calls
			local ok, err = pcall(call or repo({namespace = "library", repository = "nginx"}))
			for _, text in expected do
				assert(not ok and string.find(tostring(err), text, 1, true), "missing " .. text .. " in " .. tostring(err))
			end
			if absent then assert(not string.find(tostring(err), absent, 1, true), "unexpected " .. absent .. " in " .. tostring(err)) end
			assert(calls == before + 1, "a failed request was repeated")
		end
		upstream(404, '{"message":"object not found","errinfo":{}}', {},
			{"Docker Hub HTTP 404: object not found. The repository doesn't exist or is private", '"retryable":false', '"upstream_status":404'})
		upstream(404, '{"message":"httperror 404: tag \'nope\' not found","errinfo":{"namespace":"library","repository":"nginx","tag":"nope"}}', {},
			{"Docker Hub HTTP 404: httperror 404: tag 'nope' not found", '"retryable":false'}, "private")
		-- Should Docker Hub lower its cap, its refusal still gets the hint.
		upstream(403, '{"message":"pagination offset too large for anonymous requests; sign in to page further","errinfo":{}}', {},
			{"Docker Hub HTTP 403: pagination offset too large", "lists stop after the first 100 repositories or 1,000 tags; narrow the list with name",
				'"retryable":false', '"upstream_status":403'}, nil, tags({page = 100, page_size = 10}))
		upstream(403, '{"message":"forbidden","errinfo":null}', {}, {"Docker Hub HTTP 403: forbidden", '"retryable":false'}, "narrow")
		upstream(400, '{"message":"httperror 400: Invalid ordering value","errinfo":{"ordering":"bad"}}', {},
			{"Docker Hub HTTP 400: httperror 400: Invalid ordering value", '"retryable":false'})
		upstream(400, '{"fields":{"ordering":["Invalid"]},"text":"Invalid ordering value"}', {}, {"Docker Hub HTTP 400: Invalid ordering value"})
		upstream(400, json.encode({message = string.rep("y", 1000)}), {}, {"Docker Hub HTTP 400: " .. string.rep("y", 300)}, string.rep("y", 301))
		upstream(401, '{"message":"unauthorized","errinfo":{}}', {}, {"Docker Hub HTTP 401: unauthorized", '"retryable":false'})
		upstream(429, '{"message":"rate limit exceeded"}', {["retry-after"] = {"42"}, ["x-ratelimit-reset"] = {"1793385363"}},
			{"Docker Hub HTTP 429: rate limit exceeded; retry after 42s", '"retryable":true', '"upstream_status":429'})
		upstream(429, "", {["retry-after"] = {"Fri, 30 Oct 2026 19:00:00 GMT"}}, {"Docker Hub HTTP 429; retry after Fri, 30 Oct 2026 19:00:00 GMT", '"retryable":true'}, "GMTs")
		upstream(429, "", {}, {"Docker Hub HTTP 429", '"retryable":true'}, "retry after")
		upstream(503, "<html>Service Unavailable</html>", {}, {"Docker Hub HTTP 503", '"retryable":true'}, "Service")
		upstream(500, '{"message":null,"errinfo":null}', {}, {"Docker Hub HTTP 500", '"retryable":true'})
		upstream(301, "", {location = {"https://elsewhere.example.com/v2/"}}, {"Docker Hub HTTP 301: unexpected redirect", '"retryable":false'}, "elsewhere")
		upstream(200, "<html>maintenance</html>", {}, {"Docker Hub returned an invalid JSON object", '"retryable":false'}, "maintenance")
		upstream(200, "[]", {}, {"Docker Hub returned an invalid JSON object"})
		status, payload, responseHeaders = 200, '{"count":1,"next":null,"previous":null,"results":null}', {}
		local ok, err = pcall(tags({}))
		assert(not ok and string.find(tostring(err), "Docker Hub returned an invalid list", 1, true), tostring(err))

		requestError = {code = "timeout", message = "request deadline"}
		upstream(200, "", {}, {"Docker Hub did not answer within 15 s; retry", '"retryable":true'})
		-- Other request failures pass through unchanged: the stand-in table loses its message across the export boundary, so
		-- only the absence of an upstream failure (no retryable flag) is checked.
		requestError = {code = "access_denied", message = "origin not allowed"}
		upstream(200, "", {}, {"error"}, "retryable")
		requestError = nil
		-- An error body that stalls or breaks still gives the structured failure, with Retry-After on a 503.
		readError = {code = "timeout", message = "await timed out"}
		upstream(503, "", {["retry-after"] = {"30"}}, {"Docker Hub HTTP 503; retry after 30s", '"retryable":true', '"upstream_status":503'}, "timed out")
		readError = {code = "io_error", message = "connection reset by peer"}
		upstream(404, "", {}, {"Docker Hub HTTP 404", '"retryable":false'}, "reset")
		readError = nil
	end,
}
