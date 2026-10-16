return {
	scenario = {publisher = {client_id = "Iv23liFixture", client_secret = "fixture-client-secret"}, config = {access = "read-write"},
		auth_method = "oauth", auth_config = {}},
	configure = function()
		requests = {}
		responses = {}
		fs = fixture.files()
		http = {request = function(req)
			table.insert(requests, req)
			local next = table.remove(responses, 1) or {statusCode = 200, headers = {}, body = "{}"}
			return fixture.operation({statusCode = next.statusCode, headers = next.headers, body = fixture.reader(next.body)})
		end}
	end,
	run = function(github)
		local API = "https://api.github.com"
		local function respond(statusCode, body, headers)
			table.insert(responses, {statusCode = statusCode, body = body, headers = headers or {}})
		end
		local function redirect(location) respond(302, "", {location = {location}}) end
		local function contents(path)
			local file = fs.open(path, "r")
			local chunk = await(file:read(1024 * 1024))
			await(file:close())
			return if chunk.done then "" else chunk.data
		end
		local function rejected(fn, expected)
			local before = #requests
			local ok, err = pcall(fn)
			assert(not ok and string.find(tostring(err), expected, 1, true), "wrong error: " .. tostring(err))
			return #requests - before
		end

		local names = {}
		for name in github do if name ~= "help" then table.insert(names, name) end end
		assert(#names == 144, "wrong surface for Connect with GitHub: " .. #names)
		for _, name in {"listNotifications", "markNotificationsRead", "markThreadRead", "markThreadDone"} do
			assert(github[name] == nil, "GitHub App tokens cannot use " .. name)
		end

		respond(200, "binary\0bytes")
		local saved = github.getContent({owner = "o", repo = "r", path = "assets/logo.png", ref = "main", save_as = "logo.png"})
		assert(requests[1].url == API .. "/repos/o/r/contents/assets%2Flogo.png?ref=main", requests[1].url)
		assert(requests[1].headers.Accept[1] == "application/vnd.github.raw+json" and requests[1].headers.Authorization == nil)
		assert(saved.path == "logo.png" and saved.size == 12 and type(saved.url) == "string" and contents("logo.png") == "binary\0bytes")

		local signed = "https://codeload.github.com/o/r/legacy.tar.gz/refs/heads/feature/x?token=SIGNED"
		redirect(signed)
		respond(200, "tarball")
		saved = github.downloadTarball({owner = "o", repo = "r", ref = "feature/x", save_as = "src.tar.gz"})
		assert(requests[2].url == API .. "/repos/o/r/tarball/feature%2Fx" and requests[2].headers.Accept[1] == "application/vnd.github+json")
		assert(requests[3].method == "GET" and requests[3].url == signed and requests[3].headers.Authorization == nil)
		assert(saved.size == 7 and contents("src.tar.gz") == "tarball")

		respond(200, '{"id":5,"name":"app.zip","browser_download_url":"https://github.com/o/r/releases/download/v1/app.zip"}')
		local asset = github.getReleaseAsset({owner = "o", repo = "r", asset_id = 5})
		assert(asset.name == "app.zip" and requests[4].headers.Accept[1] == "application/vnd.github+json")
		redirect("https://release-assets.githubusercontent.com/github-production-release-asset/1/abc?sig=SIGNED")
		respond(200, "zip-bytes")
		saved = github.getReleaseAsset({owner = "o", repo = "r", asset_id = 5, save_as = "dist/app.zip"})
		assert(requests[5].url == API .. "/repos/o/r/releases/assets/5" and requests[5].headers.Accept[1] == "application/octet-stream")
		assert(string.find(requests[6].url, "https://release-assets.githubusercontent.com/", 1, true) == 1 and contents("dist/app.zip") == "zip-bytes")

		redirect("https://productionresultssa12.blob.core.windows.net/actions-results/job-logs.txt?sig=SIGNED")
		respond(200, "2026-10-16T00:00:00Z ##[error]Process completed with exit code 1.\n")
		github.downloadJobLogs({owner = "o", repo = "r", job_id = 399444496, save_as = "job.log"})
		assert(requests[7].url == API .. "/repos/o/r/actions/jobs/399444496/logs")
		assert(await(fs.grep("exit code 1", "job.log")).matches[1] ~= nil)
		redirect("https://pipelinesghubeus6.actions.githubusercontent.com/logs.zip?sig=SIGNED")
		respond(200, "zip")
		github.downloadRunLogs({owner = "o", repo = "r", run_id = 30433642, save_as = "run-logs.zip"})
		assert(requests[10].url == "https://pipelinesghubeus6.actions.githubusercontent.com/logs.zip?sig=SIGNED")

		for _, location in {"https://evil.example/x", "https://productionresultssa1.blob.core.windows.net.evil.example/x",
			"http://codeload.github.com/o/r", "https://api.github.com/repositories/1/tarball/main",
			"https://gist.githubusercontent.com/o/1/raw", "https://evil.actions.githubusercontent.com.example/x"} do
			redirect(location)
			local sentRequests = rejected(function() github.downloadZipball({owner = "o", repo = "r", ref = "main", save_as = "src.zip"}) end,
				"redirected the download to an unexpected host")
			assert(sentRequests == 1, "followed a redirect to " .. location)
		end
		respond(403, '{"message":"Must have admin rights to Repository.","status":"403"}')
		assert(rejected(function() github.downloadRunLogs({owner = "o", repo = "r", run_id = 1, save_as = "x.zip"}) end,
			"Must have admin rights") == 1)
		redirect(signed)
		respond(403, "<Error>AuthenticationFailed</Error>")
		assert(rejected(function() github.downloadTarball({owner = "o", repo = "r", ref = "main", save_as = "y.tar.gz"}) end, "GitHub HTTP 403") == 2)
		assert(rejected(function() github.downloadTarball({owner = "o", repo = "r", ref = "main"}) end, "save_as is required") == 0)
		assert(rejected(function() github.getRepo({owner = "o", repo = "r", save_as = "repo.json"}) end, "getRepo has no option save_as") == 0)

		local file = fs.open("build/app.zip", "w")
		file:write("PK\3\4payload")
		await(file:close())
		respond(201, '{"id":8,"name":"app.zip","state":"uploaded"}')
		local uploaded = github.uploadReleaseAsset({owner = "o", repo = "r", release_id = 42, name = "app v1.zip", label = "App", file = "build/app.zip",
			content_type = "application/zip"})
		local req = requests[#requests]
		assert(req.method == "POST" and req.url == "https://uploads.github.com/repos/o/r/releases/42/assets?name=app%20v1.zip&label=App", req.url)
		assert(req.headers["Content-Type"][1] == "application/zip" and req.headers.Authorization == nil)
		local chunk = await(req.body:read(1024))
		assert(chunk.data == "PK\3\4payload")
		await(req.body:close())
		assert(uploaded.state == "uploaded")
		assert(rejected(function() github.uploadReleaseAsset({owner = "o", repo = "r", release_id = 42, name = "x", file = "missing.zip"}) end, "") == 0)
		assert(rejected(function() github.uploadReleaseAsset({owner = "o", repo = "r", release_id = 42, file = "build/app.zip"}) end, "name is required") == 0)
	end,
}
