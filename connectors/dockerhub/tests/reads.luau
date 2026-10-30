-- Each export reads one exact public URL without a credential and returns Docker Hub's JSON unchanged, nulls included.
return {
	scenario = {publisher = {}, config = {}, auth_method = "", auth_config = {}},
	configure = function()
		requests, responses = {}, {}
		http = {request = function(req)
			table.insert(requests, req)
			assert(req.method == "GET" and req.body == nil, "every request is a GET without a body")
			assert(req.headers.Accept[1] == "application/json" and req.headers.Authorization == nil, "Docker Hub is read without a credential")
			assert(req.timeoutMs == 15000, "headers get 15 s of the call")
			assert(#responses > 0, "unexpected request: " .. req.url)
			return fixture.operation({statusCode = 200, headers = {}, body = fixture.reader(table.remove(responses, 1))})
		end}
		function respond(body) table.insert(responses, body) end
	end,
	run = function(dockerhub)
		local API = "https://hub.docker.com/v2"
		local NULL = json.decode("null")
		local function got(path)
			local req = requests[#requests]
			assert(req.url == API .. path, req.url)
		end

		local names = {}
		for name, fn in dockerhub do
			assert(type(fn) == "function")
			table.insert(names, name)
		end
		table.sort(names)
		assert(table.concat(names, ",") == "getRepository,getTag,listRepositories,listTags", table.concat(names, ","))
		assert(#requests == 0, "initialization reached Docker Hub")

		-- A namespace's first page, with the next page's URL left as Docker Hub sent it.
		respond('{"count":420,"next":"https://hub.docker.com/v2/namespaces/docker/repositories?page=2&page_size=2","previous":null,'
			.. '"results":[{"name":"highland_builder","namespace":"docker","repository_type":"image","status":1,"status_description":"active",'
			.. '"description":"Image for performing Docker build requests","is_private":false,"star_count":7,"pull_count":19263991,'
			.. '"last_updated":"2026-10-22T18:51:12.424492Z","date_registered":"2015-05-19T21:13:35.937763Z","affiliation":"",'
			.. '"media_types":["application/vnd.oci.image.index.v1+json"],"categories":[{"name":"Operating systems","slug":"operating-systems"}],'
			.. '"storage_size":489508503351,"source":null,"registry_region":{"name":"us-east-1","label":"US"}},'
			.. '{"name":"whalesay","namespace":"docker","repository_type":null,"pull_count":145616122,"categories":[],"storage_size":103666708}]}')
		local page = dockerhub.listRepositories({namespace = "docker", page_size = 2})
		got("/namespaces/docker/repositories?page_size=2")
		assert(page.count == 420 and #page.results == 2 and page.previous == NULL and page.next == "https://hub.docker.com/v2/namespaces/docker/repositories?page=2&page_size=2")
		assert(page.results[1].storage_size == 489508503351 and page.results[1].source == NULL and page.results[2].repository_type == NULL)
		assert(json.encode(page.results[2].categories) == "[]")
		-- Every option, in the endpoint's order; the filter is percent-encoded.
		respond('{"count":0,"next":null,"previous":null,"results":[]}')
		local empty = dockerhub.listRepositories({namespace = "bitnami", name = "redis cluster", ordering = "-pull_count", page = 2, page_size = 50})
		got("/namespaces/bitnami/repositories?name=redis%20cluster&ordering=-pull_count&page=2&page_size=50")
		assert(empty.count == 0 and empty.next == NULL and json.encode(empty.results) == "[]")
		-- JSON null options are left out.
		respond('{"count":0,"next":null,"previous":null,"results":[]}')
		dockerhub.listRepositories({namespace = "ai", name = NULL, ordering = NULL})
		got("/namespaces/ai/repositories")
		-- The last pages Docker Hub lists without signing in, and a namespace with a dot.
		respond('{"count":420,"next":"https://hub.docker.com/v2/namespaces/docker/repositories?page=11","previous":null,"results":[]}')
		dockerhub.listRepositories({namespace = "docker", page = 10})
		got("/namespaces/docker/repositories?page=10")
		respond('{"count":1381,"next":null,"previous":null,"results":[]}')
		dockerhub.listTags({namespace = "library", repository = "nginx", page = 1000, page_size = 1})
		got("/namespaces/library/repositories/nginx/tags?page=1000&page_size=1")
		respond('{"count":0,"next":null,"previous":null,"results":[]}')
		dockerhub.listRepositories({namespace = "a.b"})
		got("/namespaces/a.b/repositories")

		respond('{"user":"library","name":"nginx","namespace":"library","repository_type":"image","description":"Official build of Nginx.",'
			.. '"is_private":false,"star_count":21414,"pull_count":13533095179,"last_updated":"2026-10-29T01:52:06.381447Z","affiliation":null,'
			.. '"hub_user":"stackbrew","full_description":"# Quick reference\\n","permissions":{"read":true,"write":false,"admin":false},'
			.. '"immutable_tags_settings":{"enabled":false,"rules":[".*"]},"storage_size":258813768582,"source":null}')
		local repo = dockerhub.getRepository({namespace = "library", repository = "nginx"})
		got("/namespaces/library/repositories/nginx")
		assert(repo.pull_count == 13533095179 and repo.affiliation == NULL and repo.full_description == "# Quick reference\n")
		assert(repo.immutable_tags_settings.rules[1] == ".*")
		respond('{"name":"docker-model-backend-vllm","namespace":"docker"}')
		dockerhub.getRepository({namespace = "docker", repository = "docker-model-backend-vllm"})
		got("/namespaces/docker/repositories/docker-model-backend-vllm")
		respond('{"name":"v1.10-migrator","namespace":"docker"}')
		dockerhub.getRepository({namespace = "docker", repository = "v1.10-migrator"})
		got("/namespaces/docker/repositories/v1.10-migrator")

		-- Tags with their per-platform images; attestations and nulls come back unchanged.
		local tag = '{"creator":7,"id":19451,"images":[{"architecture":"amd64","features":"","variant":null,'
			.. '"digest":"sha256:8e0328743c8e52ead9fac9c198d0893d63cd38e41b1d9ea629e092a8ac229a93","os":"linux","os_features":"","os_version":null,'
			.. '"size":63911306,"status":"active","last_pulled":"2026-10-30T18:20:12.533304581Z","last_pushed":"2026-10-28T04:50:26.757399428Z"},'
			.. '{"architecture":"unknown","variant":null,"digest":"sha256:' .. string.rep("ab", 32) .. '","os":"unknown","size":2891767,"status":"active"}],'
			.. '"last_updated":"2026-10-28T04:53:32.454364Z","last_updater_username":"doijanky","name":"latest","repository":21171,"full_size":63911306,'
			.. '"v2":true,"tag_status":"active","tag_last_pulled":"2026-10-30T18:30:07.204630028Z","tag_last_pushed":"2026-10-28T04:53:32.454364Z",'
			.. '"media_type":"application/vnd.oci.image.index.v1+json","content_type":"image",'
			.. '"digest":"sha256:600f7cd45e27aa13e9304c834ab7c1b0ff39df85ee1dcc5087955455d77bc83b"}'
		respond('{"count":795,"next":"https://hub.docker.com/v2/namespaces/library/repositories/nginx/tags?name=alpine&page=2&page_size=1",'
			.. '"previous":null,"results":[' .. tag .. ']}')
		local tags = dockerhub.listTags({namespace = "library", repository = "nginx", name = "alpine", page_size = 1})
		got("/namespaces/library/repositories/nginx/tags?name=alpine&page_size=1")
		local first = tags.results[1]
		assert(tags.count == 795 and first.digest == "sha256:600f7cd45e27aa13e9304c834ab7c1b0ff39df85ee1dcc5087955455d77bc83b")
		assert(first.images[1].variant == NULL and first.images[1].size == 63911306 and first.images[2].architecture == "unknown")
		assert(first.images[2].last_pushed == nil and first.tag_last_pushed == "2026-10-28T04:53:32.454364Z")
		-- The last page Docker Hub lists without signing in still links a next page, which it would refuse with HTTP 403:
		-- a loop following next stops at the reach error, before any request.
		respond('{"count":1381,"next":"https://hub.docker.com/v2/namespaces/library/repositories/nginx/tags?page=11&page_size=100",'
			.. '"previous":"https://hub.docker.com/v2/namespaces/library/repositories/nginx/tags?page=9&page_size=100","results":[' .. tag .. ']}')
		local reached = dockerhub.listTags({namespace = "library", repository = "nginx", page = 10, page_size = 100})
		got("/namespaces/library/repositories/nginx/tags?page=10&page_size=100")
		assert(type(reached.next) == "string" and #reached.results == 1)
		local before = #requests
		local ok, err = pcall(function() dockerhub.listTags({namespace = "library", repository = "nginx", page = 11, page_size = 100}) end)
		assert(not ok and string.find(tostring(err), "lists stop after the first 100 repositories or 1,000 tags", 1, true), tostring(err))
		assert(#requests == before, "a page beyond reach reached Docker Hub")
		respond('{"count":1,"next":null,"previous":null,"results":[]}')
		local last = dockerhub.listTags({namespace = "docker", repository = "whalesay", name = "nothing-matches"})
		got("/namespaces/docker/repositories/whalesay/tags?name=nothing-matches")
		assert(last.next == NULL and json.encode(last.results) == "[]")
		-- Old single-manifest tags can have null images and a full_size of 0.
		respond('{"name":"latest","images":null,"full_size":0,"media_type":"application/vnd.docker.distribution.manifest.v1+prettyjws"}')
		local old = dockerhub.getTag({namespace = "docker", repository = "whalesay", tag = "latest"})
		got("/namespaces/docker/repositories/whalesay/tags/latest")
		assert(old.images == NULL and old.full_size == 0)

		respond(tag)
		local latest = dockerhub.getTag({namespace = "library", repository = "nginx", tag = "latest"})
		got("/namespaces/library/repositories/nginx/tags/latest")
		assert(latest.name == "latest" and #latest.images == 2 and latest.images[1].os_version == NULL)
		respond('{"name":"1.27.5-alpine3.21-perl"}')
		dockerhub.getTag({namespace = "library", repository = "nginx", tag = "1.27.5-alpine3.21-perl"})
		got("/namespaces/library/repositories/nginx/tags/1.27.5-alpine3.21-perl")
		respond('{"name":"Release_2"}')
		dockerhub.getTag({namespace = "bitnami", repository = "redis", tag = "Release_2"})
		got("/namespaces/bitnami/repositories/redis/tags/Release_2")
		assert(#responses == 0)
	end,
}
