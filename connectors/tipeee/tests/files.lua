local requests = {}
local payload = "{}"
local status = 200
return {
	scenario = {config = {access = "read-write"}, auth_method = "token", auth_config = {token = "fixture-token"}},
	configure = function()
		requests = {}; payload = "{}"; status = 200
		fs = fixture.files()
		local multipart = http.multipart
		http = {multipart = multipart, request = function(req)
			if req.body ~= nil then req.body = await(req.body:readAll()) end
			table.insert(requests, req)
			return fixture.operation({statusCode=status,headers={},body=fixture.reader(payload)})
		end}
	end,
	run = function(t)
		local bytes = "image\0" .. string.char(255)
		local f = fs.open("image.png","w"); f:write(bytes); await(f:close())
		payload = '{"id":10,"slug":"private-media"}'
		local media = t.uploadMedia({isPrivate=true,type="image",files={uploadedFile={path="image.png",filename="image.png",contentType="image/png"}}})
		local req = requests[1]
		assert(media.id == 10 and req.url == "https://api.tipeee.com/v2.0/media?isPrivate=true&type=image" and req.method == "POST")
		assert(string.find(req.body, 'name="uploadedFile"; filename="image.png"',1,true) and string.find(req.body,bytes,1,true))
		t.updateProjectAvatar({project="p",data={avatar={uploadedFileOptions={x=0,y=1,width=20,height=20}}},files={["avatar[uploadedFile]"]={path="image.png",filename="image.png",contentType="image/png"}}})
		assert(requests[2].method == "POST" and string.find(requests[2].body,'name="_method"\r\n\r\nput',1,true) and string.find(requests[2].body,bytes,1,true))
		status = 206; payload = "{}"
		t.uploadMessageFileChunk({data={fileId="uuid-stable",chunkIndex=0,totalChunks=2,fileName="image.png"},files={file={path="image.png",filename="image.png",contentType="image/png"}}})
		assert(string.find(requests[3].body,'name="chunkIndex"\r\n\r\n0',1,true))
		status = 200; payload = '{"slug":"completed-upload"}'
		assert(t.uploadMessageFileChunk({data={fileId="uuid-stable",chunkIndex=1,totalChunks=2,fileName="image.png"},files={file={path="image.png",filename="image.png",contentType="image/png"}}}).slug == "completed-upload")
		payload = "name,amount\nCreator,10\n"
		local download = t.downloadPayments({report="my-art_2026.csv",lang="en",output="payments.csv"})
		assert(requests[5].url == "https://api.tipeee.com/documents/payments/my-art_2026.csv?lang=en")
		assert(download.path == "payments.csv" and download.size == #payload and type(download.url) == "string")
		local read = fs.open(download.path,"r"); assert(await(read:read(1024)).data == payload); await(read:close())
		payload = "%PDF-fixture\0"
		t.downloadPaymentBill({document="123.pdf",output="bill.pdf"})
		assert(requests[6].url == "https://api.tipeee.com/documents/payment-bill/123.pdf")
		t.downloadTippers({report="campaign.xlsx",noReward=0,output="tippers.xlsx"})
		assert(requests[7].url == "https://api.tipeee.com/documents/tippers/campaign.xlsx?noReward=0&allTabs=0")
		payload = '{"status":"sent"}'
		assert(t.emailTippersExport({report="campaign.xlsx"}).status == "sent")
		assert(requests[8].url == "https://api.tipeee.com/documents/tippers/campaign.xlsx?allTabs=1")
		local before = #requests
		assert(not pcall(function() t.downloadTippers({report="campaign.xlsx",allTabs=1,output="out"}) end))
		assert(not pcall(function() t.downloadPayments({report="no-year.csv",output="out"}) end))
		assert(not pcall(function() t.uploadMedia({files={uploadedFile={path="image.png",filename="x"}}}) end))
		assert(not pcall(function() t.uploadMessageFileChunk({data={fileId="x",chunkIndex=2,totalChunks=2,fileName="x"}}) end))
		assert(#requests == before)
	end,
}
