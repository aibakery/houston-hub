return {
	scenario={config={host="erp.example.com",install_path="/dolibarr",access="read-write"},auth_method="key",auth_config={token="fixture-token"}},
	configure=function()
		requests={};payload="{}"
		http={request=function(req)
			table.insert(requests,req)
			return fixture.operation({statusCode=200,headers={},body=fixture.reader(payload)})
		end}
	end,
	run=function(c)
		local routes,examples=require("lib/example-routes.luau"),require("lib/examples.luau")
		local count=0
		for name in c do if name~="help" then count+=1;assert(routes[name],name) end end
		assert(count==48)
		for name,route in routes do
			for index,example in examples[name] do
				local path=string.gsub(route.path,"{id}",tostring(example.id))
				local options=table.clone(example.opts or {})
				if route.list then options.limit=options.limit or 100;options.page=options.page or 0 end
				local names,query={},{}
				for key in options do table.insert(names,key) end
				table.sort(names)
				for _,key in names do
					local value=options[key]
					if type(value)=="table" then local items={};for _,item in value do table.insert(items,tostring(item)) end;value=table.concat(items,",")
					elseif type(value)=="boolean" then value=if value then "1" else "0" end
					table.insert(query,key .. "=" .. url.encode(value))
				end
				if #query>0 then path..="?" .. table.concat(query,"&") end
				local scalar=table.find({"id","lineID","paymentID","number"},route.returns)~=nil
				local list=route.list or string.sub(route.returns,1,1)=="["
				payload=if scalar then "12" elseif list then '[{"id":"12","pass":"secret"}]' else '{"id":"12","futureField":true,"pass":"secret"}'
				local before=#requests
				local result=fixture.example(name,index)
				assert(#requests==before+1,name)
				local req=requests[#requests]
				assert(req.method==route.method and req.url=="https://erp.example.com/dolibarr/api/index.php" .. path,name .. ": " .. req.url)
				assert(req.headers.DOLAPIKEY==nil)
				if scalar then assert(result==12) elseif list then assert(result[1].id=="12" and result[1].pass==nil) else assert(result.futureField and result.pass==nil) end
				if route.fields~="" then
					assert(req.headers["Content-Type"][1]=="application/json")
					assert(json.encode(json.decode(req.body))==json.encode(example.fields or {}),name)
				else assert(req.body==nil,name) end
			end
		end
	end,
}
