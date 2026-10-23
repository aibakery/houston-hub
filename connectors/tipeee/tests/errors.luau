local status, payload, responseHeaders, calls = 200, "{}", {}, 0
return {
	scenario = {config={access="read-write"},auth_method="token",auth_config={token="fixture-token"}},
	configure = function()
		calls = 0
		http = {request=function(req)
			calls += 1
			return fixture.operation({statusCode=status,headers=responseHeaders,body=fixture.reader(payload)})
		end}
	end,
	run = function(t)
		local function check(code, body, headers, expected)
			status,payload,responseHeaders = code,body,headers
			local before = calls
			local ok, err = pcall(function() t.requestPayout({project="p"}) end)
			for _, fragment in expected do assert(not ok and string.find(tostring(err),fragment,1,true), tostring(err)) end
			assert(calls == before+1,"connector added an extra retry")
		end
		check(400,'{"code":"00004","debugId":"diagnostic"}',{}, {"HTTP 400","00004",'"retryable":false'})
		check(403,'{"message":"Access denied"}',{}, {"HTTP 403","Access denied"})
		check(422,'{"code":"00001","errors":{"amount":{"template":"Invalid amount","params":{}}}}',{}, {"00001","Invalid amount"})
		check(429,'{"message":"Wait"}',{["retry-after"]={"30"}}, {"Retry-After: 30",'"retryable":true'})
		check(503,string.rep("upstream failure",3000),{}, {"HTTP 503",'"retryable":true'})
		check(200,'{"errors":["Payout unavailable"]}',{}, {"Payout unavailable",'"retryable":false'})
		check(200,'{"errors":"Payout unavailable"}',{}, {"Payout unavailable"})
		check(200,'<html>maintenance</html>',{}, {"Invalid JSON response"})
		status,payload,responseHeaders = 200,"",{}
		assert(not pcall(function() t.getMe() end),"empty read cannot be treated as success")
	end,
}
