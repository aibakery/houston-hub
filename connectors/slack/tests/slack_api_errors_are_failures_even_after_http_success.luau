return {scenario={["auth_config"]={},["auth_method"]="oauth",["config"]={["workspace_id"]="T_FIXTURE",["client_id"]="fixture-value",["client_secret"]="fixture-private-password !@#"}},config={access="read-write"}, configure=function()

        requests = {}
        responses = {}
        http = {request = function(req)
            requests[#requests + 1] = req
            if req.dest and #responses == 0 then return {status=200, body="", bytes=123} end
            assert(#responses > 0, "unexpected request: " .. req.url)
            local response = table.remove(responses, 1)
            if req.dest then return {status=200,body="",bytes=response.bytes} end
            return {status=200,body=if type(response)=="string" then response else json.encode(response)}
        end}
        fs = {
            stat = function(path) assert(path == "report.txt"); return { size = 11, isFile = true } end,
            signedGetUrl = function(path) return "https://houston.test/files/" .. path end,
        }


end, run=function(slack)
        for _,code in {"missing_scope", "not_in_channel", "ratelimited", "invalid_auth"} do
            responses={{ok=false,error=code}}
            local ok,err=pcall(slack.listMessages,"C1")
            assert(not ok and string.find(tostring(err),code,1,true))
        end
        assert(#requests==4, "must not automatically retry")

end}
