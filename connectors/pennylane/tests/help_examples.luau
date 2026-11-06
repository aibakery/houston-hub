return {
	scenario={config={access="read-write"},auth_method="token",auth_config={token="fixture-token"}},
	configure=function()
		fs=fixture.files();requests={};status=200;payload='{"id":42,"future_field":"preserved"}'
		local multipart=http.multipart
		http={multipart=multipart,request=function(req)
			if req.body~=nil and type(req.body)~="string" then req.body=await(req.body:readAll()) end
			table.insert(requests,req)
			return fixture.operation({statusCode=status,headers={},body=fixture.reader(payload)})
		end}
	end,
	run=function(c)
		local file=fs.open("invoice.pdf","w");file:write("fixture invoice");await(file:close())
		local routes,docs=require("lib/example-routes.luau"),require("lib/help.luau")
		local count=0
		for name in c do if name~="help" then count+=1;assert(routes[name],name) end end
		assert(count==182,tostring(count))
		for name,route in routes do
			for index,example in docs[name].inputSchema.examples do
				local body=table.clone(example)
				local path=string.gsub(route.path,"{([%w_]+)}",function(field) body[field]=nil;return tostring(example[field]) end)
				local query={}
				for _,field in route.query do
					local value=example[field]
					if value~=nil then
						if type(value)=="table" then value=json.encode(value) end
						table.insert(query,field .. "=" .. url.encode(value))
					end
					body[field]=nil
				end
				if #query>0 then path..="?" .. table.concat(query,"&") end
				status=if route.method~="GET" and not route.body then 204 else 200
				payload=if status==204 then "" elseif name=="getPaRegistrations" then '[{"id":42,"status":"activated"}]' else '{"id":42,"future_field":"preserved"}'
				local before=#requests
				local result=fixture.example(name,index)
				assert(#requests==before+1,name)
				local req=requests[#requests]
				assert(req.method==route.method and req.url=="https://app.pennylane.com/api/external/v2" .. path,name .. ": " .. req.url)
				assert(req.headers.Authorization==nil,name)
				if status==204 then assert(next(result)==nil,name)
				elseif name=="getPaRegistrations" then assert(result[1].status=="activated")
				else assert(result.id==42 and result.future_field=="preserved",name) end
				if route.wrap=="multipart" then
					assert(string.find(req.headers["Content-Type"][1],"multipart/form-data; boundary=",1,true))
					assert(string.find(req.body,'name="file"; filename="invoice.pdf"\r\nContent-Type: application/pdf',1,true),name)
					assert(string.find(req.body,"fixture invoice",1,true),name)
					for _,field in route.parts do
						local value=example[field]
						if value~=nil then
							local header='name="' .. field .. '"\r\n'
							if type(value)=="table" then header..='Content-Type: application/json\r\n';value=json.encode(value) else value=tostring(value) end
							assert(string.find(req.body,header .. '\r\n' .. value .. '\r\n',1,true),name .. ": " .. field)
						end
					end
				elseif route.body then
					local expected=if route.wrap~="" then body[route.wrap] else body
					assert(req.headers["Content-Type"][1]=="application/json" and json.encode(json.decode(req.body))==json.encode(expected),name)
				else assert(req.body==nil,name) end
			end
		end
	end,
}
