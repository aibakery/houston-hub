return {
	scenario={config={access="read-write"},auth_method="token",auth_config={token="fixture-token"}},
	configure=function()
		fs=fixture.files()
		requests={}
		local multipart=http.multipart
		http={multipart=multipart,request=function(req)
			if req.body~=nil and type(req.body)~="string" then req.body=await(req.body:readAll()) end
			table.insert(requests,req)
			return fixture.operation({statusCode=200,headers={},body=fixture.reader('{"futureField":true,"api_key":"private"}')})
		end}
	end,
	run=function(c)
		local upload=fs.open("upload.png","w");upload:write("fixture image");await(upload:close())
		local routes,examples=require("lib/example-routes.luau"),require("lib/examples.luau")
		local count=0
		for name in c do if name~="help" then count+=1;assert(routes[name],name) end end
		assert(count==89)
		local function fields(value,prefix,result)
			if value==json.decode("null") then return end
			if type(value)~="table" then result[prefix]=tostring(value);return end
			for key,child in value do
				local index=if type(key)=="number" then tostring(key-1) else key
				fields(child,if prefix=="" then index else prefix .. "[" .. index .. "]",result)
			end
		end
		for name,route in routes do
			for index,example in examples[name] do
				local path=string.gsub(route.path,"{([%w_]+)}",function(field) return tostring(example[field]) end)
				local query={}
				for _,field in route.query do
					local value=example[field]
					if value~=nil and value~=json.decode("null") then table.insert(query,field .. "=" .. url.encode(value)) end
				end
				if name=="downloadTippers" then table.insert(query,"allTabs=0") elseif name=="emailTippersExport" then table.insert(query,"allTabs=1") end
				if #query>0 then path..="?" .. table.concat(query,"&") end
				local before=#requests
				local result=fixture.example(name,index)
				assert(#requests==before+1,name)
				local req=requests[#requests]
				local method=if route.body=="form" and route.method=="PUT" then "POST" else route.method
				assert(req.method==method and req.url=="https://api.tipeee.com" .. path,name .. ": " .. req.url)
				assert(req.headers.Authorization==nil)
				if route.body=="download" then assert(result.path==example.output and result.size>0 and type(result.url)=="string")
				else assert(result.futureField and result.api_key==nil,name) end
				if route.body=="json" then
					assert(json.encode(json.decode(req.body))==json.encode(example.data or {}),name)
				elseif route.body=="form" then
					assert(string.find(req.headers["Content-Type"][1],"multipart/form-data; boundary=",1,true))
					local expected={};fields(example.data or {},"",expected)
					if route.method=="PUT" then expected._method="put" end
					for key,value in expected do assert(string.find(req.body,'name="' .. key .. '"\r\n\r\n' .. value .. '\r\n',1,true),name .. ": " .. key) end
					for field,spec in example.files or {} do
						assert(string.find(req.body,'name="' .. field .. '"; filename="' .. spec.filename .. '"',1,true),name)
						assert(string.find(req.body,"fixture image",1,true),name)
					end
				else assert(req.body==nil,name) end
			end
		end
	end,
}
