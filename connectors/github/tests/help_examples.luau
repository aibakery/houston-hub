return {
	scenario={config={access="read-write"},auth_method="token",auth_config={token="fixture-token"}},
	configure=function()
		fs=fixture.files();requests={};mode="json";payload='{"id":42}'
		http={request=function(req)
			table.insert(requests,req)
			local status,headers,body=200,{},payload
			if req.url=="https://gist.githubusercontent.com/octocat/example/raw/revision/notes.md" or req.url=="https://objects.githubusercontent.com/fixture-artifact" then
				assert(req.headers==nil and req.method=="GET")
				body="fixture bytes"
			elseif mode=="gist" then
				body='{"files":{"notes.md":{"raw_url":"https://gist.githubusercontent.com/octocat/example/raw/revision/notes.md"}}}'
			elseif mode=="download" then
				status=302;headers={location={"https://objects.githubusercontent.com/fixture-artifact"}};body=""
			elseif mode=="raw" then body="fixture bytes"
			elseif mode=="diff" then body="diff --git a/README.md b/README.md\n+Example\n"
			elseif mode=="empty" then status=204;body=""
			end
			return fixture.operation({statusCode=status,headers=headers,body=fixture.reader(body)})
		end}
	end,
	run=function(c)
		local routes,docs=require("lib/example-routes.luau"),require("lib/help.luau")
		local wrappers={listWorkflows="workflows",listWorkflowRuns="workflow_runs",listRunsForWorkflow="workflow_runs",listRunJobs="jobs",listArtifacts="artifacts",listRunArtifacts="artifacts",listCheckRuns="check_runs",listCheckSuites="check_suites"}
		local count=0
		for name in c do if name~="help" then count+=1;assert(routes[name],name) end end
		assert(count==161,tostring(count))
		for name,route in routes do
			if route.auth=="oauth" then continue end
			for index,example in docs[name].inputSchema.examples do
				local body=table.clone(example)
				local path=string.gsub(route.path,"{([%w_]+)}",function(field) body[field]=nil;return url.encode(tostring(example[field])) end)
				local query={}
				for _,field in route.query do
					local value=example[field]
					if value~=nil and not (name=="getTree" and field=="recursive" and value==false) then table.insert(query,field .. "=" .. url.encode(value)) end
					body[field]=nil
				end
				if #query>0 then path..="?" .. table.concat(query,"&") end
				local accept="application/vnd.github+json"
				mode="json"
				if name=="downloadGistFile" then mode="gist";body.filename=nil
				elseif example.save_as then mode=if name=="getContent" or name=="getBlob" then "raw" else "download";accept=route.save
				elseif example.format then mode="diff";accept="application/vnd.github." .. example.format
				elseif route.method~="GET" and not route.body then mode="empty" end
				body.save_as=nil;body.format=nil
				local item={id=42,future_field=true,download_url="https://example.com/file?token=private",temp_clone_token="private"}
				local expected: any=item
				if wrappers[name] then expected={[wrappers[name]]={item},total_count=1}
				elseif string.match(name,"^list") then expected={item}
				elseif string.match(name,"^search") then expected={items={item},total_count=1,incomplete_results=false} end
				payload=json.encode(expected)
				item.download_url="https://example.com/file";item.temp_clone_token=nil
				local before=#requests
				local result=fixture.example(name,index)
				local req=requests[before+1]
				assert(#requests==before+(if mode=="gist" or mode=="download" then 2 else 1),name)
				assert(req.method==route.method and req.url=="https://api.github.com" .. path,name .. ": " .. req.url)
				assert(req.headers.Authorization==nil and req.headers.Accept[1]==accept and req.headers["X-GitHub-Api-Version"][1]==route.version,name)
				if example.save_as then assert(result.path==example.save_as and result.size==13 and type(result.url)=="string",name)
				elseif mode=="diff" then assert(type(result)=="string" and string.find(result,"diff --git",1,true)==1,name)
				elseif mode=="empty" then assert(result.success,name)
				else assert(json.encode(result)==json.encode(expected),name) end
				if route.body then assert(req.headers["Content-Type"][1]=="application/json" and json.encode(json.decode(req.body))==json.encode(body),name)
				else assert(req.body==nil,name) end
			end
		end
	end,
}
