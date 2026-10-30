-- PDFs stream from the server's website to a session file; Cloudflare's refusals fail clearly with the PDF's address.
return {
	scenario = {publisher = {}, config = {}, auth_method = "", auth_config = {}},
	configure = function()
		requests, responses = {}, {}
		fs = fixture.files()
		http = {request = function(req)
			table.insert(requests, req)
			assert(req.method == "GET" and req.headers.Authorization == nil and req.headers.Cookie == nil)
			assert(#responses > 0, "unexpected request: " .. req.url)
			local queued = table.remove(responses, 1)
			if queued.requestError then error(queued.requestError, 0) end
			return fixture.operation({statusCode = queued.status or 200, headers = queued.headers or {["content-type"] = {"application/pdf"}},
				body = queued.reader or fixture.reader(queued.body or "")})
		end}
	end,
	run = function(rxiv)
		-- A PDF larger than readAll's default limit flows through native Reader and File streaming.
		local size = 8 * 1024 * 1024 + 17
		responses = {{body = "%PDF-1.4" .. string.rep("p", size - 8)}}
		local saved = rxiv.downloadPdf({server = "biorxiv", doi = "10.1101/339747", version = "4", session_path = "papers/339747.pdf"})
		assert(requests[1].url == "https://www.biorxiv.org/content/10.1101/339747v4.full.pdf", requests[1].url)
		assert(requests[1].headers.Accept[1] == "application/pdf" and requests[1].timeoutMs == 8000)
		assert(saved.session_path == "papers/339747.pdf" and saved.size == size and type(saved.url) == "string")
		assert(saved.pdf_url == "https://www.biorxiv.org/content/10.1101/339747v4.full.pdf")
		local file = fs.open("papers/339747.pdf", "r")
		local first = await(file:read(8))
		await(file:close())
		assert(first.data == "%PDF-1.4", "downloaded bytes changed")

		local function refused(response, opts, expected, absent)
			responses = {response}
			local before = #requests
			local ok, err = pcall(rxiv.downloadPdf, opts)
			for _, text in expected do
				assert(not ok and string.find(tostring(err), text, 1, true), "missing " .. text .. " in " .. tostring(err))
			end
			if absent then assert(not string.find(tostring(err), absent, 1, true), "unexpected " .. absent .. " in " .. tostring(err)) end
			assert(#requests == before + 1 and #responses == 0)
		end
		local BIO = {server = "biorxiv", doi = "10.64898/2026.10.15.759504", version = 1, session_path = "bio.pdf"}
		local MED = {server = "medrxiv", doi = "10.1101/2020.09.09.20191205", version = 2, session_path = "med.pdf"}
		local BIO_URL = "https://www.biorxiv.org/content/10.64898/2026.10.15.759504v1.full.pdf"
		local MED_URL = "https://www.medrxiv.org/content/10.1101/2020.09.09.20191205v2.full.pdf"
		-- A refused download leaves an existing file unchanged.
		local existing = fs.open("bio.pdf", "w")
		existing:write("kept")
		await(existing:close())
		local function kept()
			local file = fs.open("bio.pdf", "r")
			local chunk = await(file:read(16))
			await(file:close())
			assert(chunk.data == "kept", "a refused download changed the session file")
		end
		-- Cloudflare's rate limit asks for a long wait, which Houston leaves to the caller.
		refused({status = 429, body = "error code: 1015", headers = {["retry-after"] = {"43"}, ["content-type"] = {"text/plain"}}}, BIO,
			{"bioRxiv HTTP 429; retry after 43s; open " .. BIO_URL .. " in a browser instead", '"retryable":true', '"upstream_status":429'}, "1015")
		kept()
		refused({status = 403, body = "<html><title>Attention Required! | Cloudflare</title>Sorry, you have been blocked</html>",
			headers = {["content-type"] = {"text/html"}}}, MED,
			{"medRxiv HTTP 403: blocked the automated download; open " .. MED_URL .. " in a browser instead", '"retryable":false'}, "Cloudflare")
		refused({status = 404, body = "<html>Not found</html>"}, BIO,
			{"bioRxiv HTTP 404: has no PDF of version 1 of 10.64898/2026.10.15.759504; getPreprint lists the versions", '"retryable":false'}, "browser")
		refused({status = 302, headers = {location = {"https://connect.biorxiv.org/login"}}}, MED,
			{"medRxiv HTTP 302: answered with an unexpected redirect; open " .. MED_URL, '"retryable":false'}, "login")
		refused({status = 503, body = ""}, BIO, {"bioRxiv HTTP 503; open " .. BIO_URL, '"retryable":true'})
		-- A challenge page sent with 200 is not a PDF.
		refused({body = "<html>Just a moment...</html>", headers = {["content-type"] = {"text/html; charset=UTF-8"}}}, MED,
			{"medRxiv returned a web page instead of the PDF; open " .. MED_URL, '"retryable":false'}, "moment")
		refused({body = "x", headers = {}}, BIO, {"bioRxiv returned a web page instead of the PDF"})
		refused({requestError = {code = "timeout", message = "request deadline"}}, BIO, {"bioRxiv did not answer within 8 s; retry", '"retryable":true'})
		kept()
		-- A stream that breaks surfaces at the file's close instead of returning a download.
		refused({reader = compression.gunzip(fixture.reader("not a gzip stream"))}, BIO, {"bioRxiv download failed", '"retryable":true'})
		-- An invalid session path fails before any request.
		local before = #requests
		assert(not pcall(rxiv.downloadPdf, {server = "biorxiv", doi = "10.1101/339747", version = 1, session_path = "../escape.pdf"}))
		assert(#requests == before, "an invalid session path reached bioRxiv")
	end,
}
