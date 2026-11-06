return {
	scenario={config={access="read-write"},auth_method="token",auth_config={token="fixture-page-token"}},
	configure=function()
		fs=fixture.files();requests={}
		houston=table.clone(houston)
		houston.unseal=function(value)
			assert(value=="opaque-next-listComments")
			return {operation="listComments",url="https://graph.facebook.com/v26.0/101_456/comments?after=next-page"}
		end
		local multipart=http.multipart
		http={multipart=multipart,request=function(req)
			if req.body~=nil and type(req.body)~="string" then req.body=await(req.body:readAll()) end
			table.insert(requests,req)
			return fixture.operation({statusCode=200,headers={},body=fixture.reader('{"id":"101_456","future_field":true,"access_token":"private","nested":{"token":"private"}}')})
		end}
	end,
	run=function(c)
		for _,path in {"photo.jpg","video.mp4"} do local file=fs.open(path,"w");file:write("fixture media");await(file:close()) end
		local routes,examples=require("lib/example-routes.luau"),require("lib/examples.luau")
		local count=0
		for name in c do if name~="help" then count+=1;assert(routes[name],name) end end
		assert(count==39,tostring(count))
		for name,route in routes do
			for index,example in examples[name] do
				local body=table.clone(example)
				local path=string.gsub(route.path,"{([%w_]+)}",function(field)
					body[field]=nil;return if example.next then "" else url.encode(example[field])
				end)
				local query={}
				local fields=example.fields or (if route.fields~="" then route.fields else nil)
				if route.method=="GET" and fields then table.insert(query,"fields=" .. url.encode(fields));body.fields=nil end
				for _,field in route.query do
					local value=example[field]
					if value~=nil then
						if type(value)=="table" then local parts={};for _,part in value do table.insert(parts,tostring(part)) end;value=table.concat(parts,",") end
						table.insert(query,field .. "=" .. url.encode(tostring(value)))
					end
					body[field]=nil
				end
				if #query>0 then path..="?" .. table.concat(query,"&") end
				local expectedURL=route.host .. path
				if example.next then expectedURL="https://graph.facebook.com/v26.0/101_456/comments?after=next-page" end
				local before=#requests
				local result=fixture.example(name,index)
				assert(#requests==before+1,name)
				local req=requests[#requests]
				assert(req.method==route.method and req.url==expectedURL,name .. ": " .. req.url .. " != " .. expectedURL)
				assert(req.headers.Authorization==nil and result.future_field and result.access_token==nil and result.nested.token==nil,name)
				if route.method=="POST" then
					if route.upload and body.path then
						assert(string.find(req.headers["Content-Type"][1],"multipart/form-data; boundary=",1,true))
						assert(string.find(req.body,'name="source"; filename="' .. body.path .. '"\r\nContent-Type: application/octet-stream',1,true),name)
						assert(string.find(req.body,"fixture media",1,true),name)
						body.path=nil
						for field,value in body do
							local content=if type(value)=="table" then json.encode(value) else tostring(value)
							assert(string.find(req.body,'name="' .. field .. '"\r\n\r\n' .. content .. '\r\n',1,true),name .. ": " .. field)
						end
					else assert(json.encode(json.decode(req.body))==json.encode(body),name) end
				else assert(req.body==nil,name) end
			end
		end
	end,
}
