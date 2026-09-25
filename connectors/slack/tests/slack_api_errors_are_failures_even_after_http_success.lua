return function(slack)

        requests = {}
        responses = {}
        local encode = connector_http.query_string
        connector_http = {
            query_string = encode,
            fail = function(err) error(err.message) end,
            send = function(req)
                table.insert(requests, req)
                assert(#responses > 0, "unexpected request")
                return table.remove(responses, 1)
            end,
        }
        fs = {
            stat = function(path) assert(path == "report.txt"); return { size = 11, isFile = true } end,
            signedGetUrl = function(path) return "https://houston.test/files/" .. path end,
        }
    

        for _,code in {"missing_scope", "not_in_channel", "ratelimited", "invalid_auth"} do
            responses={{ok=false,error=code}}
            local ok,err=pcall(slack.functions.listMessages,{id="c"},"C1")
            assert(not ok and string.find(err,code,1,true))
        end
        assert(#requests==4, "must not automatically retry")
    
end
