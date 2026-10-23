return {
	scenario = {publisher = {client_id = "fixture-client", client_secret = "fixture-private-secret"}, config = {}, auth_method = "oauth", auth_config = {}},
	config = {access = "read-only"},
	configure = function()
		requests, responses = {}, {}
		fs = fixture.files()
		-- Serves the body in fixed-size chunks to cross every parser boundary.
		function chunked(bytes, size)
			local position = 1
			local reader = {closed = false}
			function reader:read(_max)
				if position > #bytes then return fixture.operation({done = true}) end
				local data = string.sub(bytes, position, position + size - 1)
				position += size
				return fixture.operation({done = false, data = data})
			end
			function reader:readAll() error("attachments must stream, never readAll") end
			function reader:close() self.closed = true end
			return reader
		end
		http = {request = function(req)
			table.insert(requests, req)
			assert(#responses > 0, "unexpected request: " .. req.url)
			return fixture.operation(table.remove(responses, 1))
		end}
	end,
	run = function(c)
		local base64 = require("lib/base64.luau")
		local bytes = {}
		for i = 0, 255 do table.insert(bytes, string.char(i)) end
		local binary = table.concat(bytes) .. "tail"
		local payload = '{\n  "size": ' .. #binary .. ',\n  "data": "' .. string.gsub(base64.encode(binary), "[+/=]", {["+"] = "-", ["/"] = "_", ["="] = ""}) .. '"\n}\n'
		for _, size in {1, 3, 7, 64, 100000} do
			local reader = chunked(payload, size)
			responses = {{statusCode = 200, headers = {}, body = reader}}
			local saved = c.getAttachment({messageId = "m:1", attachmentId = "att-1", path = "files/blob.bin"})
			assert(requests[#requests].url == "https://gmail.googleapis.com/gmail/v1/users/me/messages/m%3A1/attachments/att-1", requests[#requests].url)
			assert(saved.path == "files/blob.bin" and saved.url == "https://houston.test/files/blob.bin" and saved.size == #binary, "chunk size " .. size)
			local file = fs.open("files/blob.bin", "r")
			assert(await(file:readAll()) == binary, "decoded bytes differ for chunk size " .. size)
			await(file:close())
			assert(reader.closed)
		end
		responses = {{statusCode = 200, headers = {}, body = chunked('{"size":0}', 4)}}
		assert(not pcall(c.getAttachment, {messageId = "m", attachmentId = "a", path = "x.bin"}), "missing data accepted")
		responses = {{statusCode = 404, headers = {}, body = fixture.reader('{"error":{"code":404,"message":"Requested entity was not found.","status":"NOT_FOUND"}}')}}
		local ok, err = pcall(c.getAttachment, {messageId = "m", attachmentId = "a", path = "x.bin"})
		assert(not ok and string.find(tostring(err), "NOT_FOUND", 1, true), tostring(err))
		local count = #requests
		assert(not pcall(c.getAttachment, {messageId = "m", attachmentId = "a"}), "path is required")
		assert(not pcall(c.getAttachment, {messageId = "m", attachmentId = "a", path = "x", extra = 1}))
		for _, id in {"m/1", "..", ".", "m%2F1", "m\\1", "m\n"} do
			local rejected, problem = pcall(c.getAttachment, {messageId = id, attachmentId = "a", path = "x.bin"})
			assert(not rejected and problem.code == "invalid_argument" and string.find(problem.message, "messageId must be one", 1, true))
		end
		assert(not pcall(c.getAttachment, {messageId = "m", attachmentId = "a/b", path = "x.bin"}))
		assert(#requests == count and #responses == 0)
	end,
}
