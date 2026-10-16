return {
	scenario = {publisher = {client_id = "Iv23liFixture", client_secret = "fixture-client-secret"}, config = {access = "read-write"},
		auth_method = "oauth", auth_config = {}},
	configure = function()
		requests = {}
		responses = {}
		fs = fixture.files()
		opened = {}
		local open = fs.open
		fs.open = function(path, mode)
			local file = open(path, mode)
			table.insert(opened, file)
			return file
		end
		admissionFailure = false
		http = {request = function(req)
			if admissionFailure then error("HTTP admission failed") end
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
		assert(#names == 141, "wrong surface for Connect with GitHub: " .. #names)
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
			"http://codeload.github.com/o/r",
			"https://gist.githubusercontent.com/o/1/raw", "https://evil.actions.githubusercontent.com.example/x",
			"https://evil.blob.core.windows.net/x", "https://a.b.actions.githubusercontent.com/x"} do
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
		for _, bad in {"../x.tar.gz", "/etc/x"} do
			assert(rejected(function() github.downloadTarball({owner = "o", repo = "r", ref = "main", save_as = bad}) end, "") == 0, "invalid save_as reached GitHub")
		end
		assert(rejected(function() github.getRepo({owner = "o", repo = "r", save_as = "repo.json"}) end, "getRepo has no option save_as") == 0)

		admissionFailure = true
		assert(rejected(function() github.downloadTarball({owner = "o", repo = "r", ref = "main", save_as = "z.tar.gz"}) end, "HTTP admission failed") == 0)
		assert(not pcall(function() opened[#opened]:write("x") end), "a failed download left its file open")
		admissionFailure = false
		respond(200, "blob\0raw")
		github.getBlob({owner = "o", repo = "r", file_sha = "3a0f86fb8db8eea7ccbb9a95f325ddbedfb25e15", save_as = "blob.bin"})
		assert(requests[#requests].headers.Accept[1] == "application/vnd.github.raw+json" and contents("blob.bin") == "blob\0raw")
		respond(302, "", {location = {"https://CODELOAD.github.com/o/r/legacy.zip/refs/heads/main"}})
		respond(200, "upper")
		github.downloadZipball({owner = "o", repo = "r", ref = "main", save_as = "upper.zip"})
		assert(contents("upper.zip") == "upper", "host names are case-insensitive")
		for _, code in {301, 307} do
			respond(code, "", {location = {signed}})
			respond(200, "moved")
			github.downloadZipball({owner = "o", repo = "r", ref = "main", save_as = "moved.zip"})
			assert(requests[#requests].url == signed and contents("moved.zip") == "moved", "did not follow " .. code)
		end
		respond(301, '{"message":"Moved Permanently","url":"https://api.github.com/repositories/1/tarball/main"}', {location = {"https://api.github.com/repositories/1/tarball/main"}})
		assert(rejected(function() github.downloadTarball({owner = "o", repo = "old", ref = "main", save_as = "old.tar.gz"}) end, "renamed or transferred") == 1)
		redirect("https://api.github.com/repositories/1/tarball/main")
		assert(rejected(function() github.downloadTarball({owner = "o", repo = "old", ref = "main", save_as = "old.tar.gz"}) end, "renamed or transferred") == 1)
		respond(200, '[{"name":"a.md","download_url":"https://raw.githubusercontent.com/o/r/main/a.md?token=SIGNED"}]', {["content-type"] = {"application/json; charset=utf-8"}})
		assert(rejected(function() github.getContent({owner = "o", repo = "r", path = "docs", save_as = "docs.bin"}) end, "is a directory") == 1)
		assert(not string.find(contents("docs.bin"), "SIGNED", 1, true), "saved a directory listing with signed links")
		respond(202, "")
		assert(rejected(function() github.getContent({owner = "o", repo = "r", path = "a.bin", save_as = "a.bin"}) end, "GitHub HTTP 202") == 1)
	end,
}
