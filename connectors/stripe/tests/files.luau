return {
	scenario = {config = {access = "read-write"}, auth_method = "token", auth_config = {token = "rk_test_fixture"}},
	configure = function()
		requests = {}
		fs = fixture.files()
		opened = {}
		local open = fs.open
		fs.open = function(path,mode)
			local file = open(path,mode)
			table.insert(opened,file)
			return file
		end
		payload = '{"id":"file_1","purpose":"dispute_evidence","url":null}'
		status = 200
		stream = nil
		transportFailure = false
		admissionFailure = false
		local multipart = http.multipart
		http = {multipart=multipart,request=function(req)
			if admissionFailure then rejectedBody = req.body; error("HTTP admission failed") end
			if req.body ~= nil and type(req.body) ~= "string" then req.body = await(req.body:readAll()) end
			table.insert(requests,req)
			if transportFailure then error("transport failed") end
			return fixture.operation({statusCode=status,headers={},body=stream or fixture.reader(payload)})
		end}
	end,
	run = function(c)
		local file = fs.open("input/evidence.pdf","w")
		file:write("%PDF-fixture\0binary")
		await(file:close())
		assert(c.uploadFile({path="input/evidence.pdf",purpose="dispute_evidence",content_type="application/pdf",file_link_data={create=false},idempotency_key="upload-1"}).id == "file_1")
		local req = requests[1]
		assert(req.url == "https://files.stripe.com/v1/files" and req.method == "POST" and req.headers.Authorization == nil)
		assert(req.headers["Idempotency-Key"][1] == "upload-1" and string.find(req.headers["Content-Type"][1],"multipart/form-data",1,true))
		for _, part in {'name="file"; filename="evidence.pdf"','Content-Type: application/pdf','%PDF-fixture\0binary','name="purpose"\r\n\r\ndispute_evidence','name="file_link_data[create]"\r\n\r\nfalse'} do
			assert(string.find(req.body,part,1,true), "missing multipart field " .. part)
		end
		local before = #requests
		assert(not pcall(c.uploadFile,{path="missing.pdf",purpose="dispute_evidence"}))
		assert(not pcall(c.uploadFile,{path="input/evidence.pdf"}))
		assert(not pcall(c.downloadFile,{file_id="../files",path="bad.pdf"}))
		assert(#requests == before, "invalid file input reached Stripe")
		local oversized = {path="input/evidence.pdf",purpose="dispute_evidence"}
		for i=1,128 do oversized["field_" .. i] = "x" end
		local ok, err = pcall(c.uploadFile,oversized)
			assert(not ok and err.code == "invalid_argument" and string.find(err.message,"128 parts",1,true),tostring(err))
		assert(not pcall(function() await(opened[#opened]:read(1)) end), "multipart validation left the file open")
		assert(#requests == before, "invalid multipart reached HTTP")
		admissionFailure = true
		ok, err = pcall(c.uploadFile,{path="input/evidence.pdf",purpose="dispute_evidence"})
		assert(not ok and string.find(tostring(err),"HTTP admission failed",1,true),tostring(err))
			assert(not pcall(function() await(opened[#opened]:read(1)) end), "HTTP admission left the file open")
			assert(not pcall(function() await(rejectedBody:readAll()) end), "HTTP admission left the multipart reader open")
		admissionFailure = false
		local size = 8 * 1024 * 1024 + 17
		stream = fixture.reader(string.rep("d",size))
		local saved = c.downloadFile({file_id="file_1",path="output.pdf"})
		assert(saved.path == "output.pdf" and saved.size == size and type(saved.url) == "string")
		assert(requests[#requests].url == "https://files.stripe.com/v1/files/file_1/contents")
		file = fs.open(saved.path,"r")
		local total = 0
		while true do
			local chunk = await(file:read(1024 * 1024))
			if chunk.done then break end
			assert(chunk.data == string.rep("d",#chunk.data)); total += #chunk.data
		end
		await(file:close()); assert(total == size)
		stream = compression.gunzip(fixture.reader("not gzip"))
		assert(not pcall(c.downloadFile,{file_id="file_1",path="broken.pdf"}), "broken stream returned success")
		stream, status, payload = nil, 403, '{"error":{"message":"File cannot be downloaded"}}'
		ok, err = pcall(c.downloadFile,{file_id="file_1",path="denied.pdf"})
		assert(not ok and string.find(tostring(err),"File cannot be downloaded",1,true),tostring(err))
		transportFailure = true
		ok, err = pcall(c.downloadFile,{file_id="file_1",path="transport.pdf"})
		assert(not ok and string.find(tostring(err),"transport failed",1,true),tostring(err))
	end,
}
