return {scenario={["auth_config"]={},["auth_method"]="oauth",["config"]={["workspace_id"]="T_FIXTURE"},["publisher"]={["client_id"]="fixture-value",["client_secret"]="fixture-private-password !@#"}},config={access="read-write"}, configure=function()

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
        responses = {
            {ok=true, channels={{id="C1"}}, response_metadata={next_cursor="next+one"}},
            {ok=true, messages={{ts="1790000000.000001"}}, response_metadata={next_cursor="page2"}},
            {ok=true, user_id="U1"},
            {ok=true, messages={matches={{text="hi"}}, paging={page=1,pages=3}}},
        }
        local channels = slack.listChannels({user="U_OTHER"})
        assert(channels.nextCursor == "next+one")
        assert(not string.find(requests[1].url, "U_OTHER", 1, true))
        assert(string.find(requests[1].url, "users.conversations", 1, true))
        local opts={cursor="next+one"}
        local thread=slack.getThread("C1", "1790000000.000001", opts)
        assert(thread.nextCursor=="page2" and opts.channel==nil)
        assert(string.find(requests[2].url, "ts=1790000000.000001", 1, true))
        assert(string.find(requests[2].url, "cursor=next%2Bone", 1, true))
        local mentions=slack.listMentions({query="in:general",page=1})
        assert(mentions.nextPage==2)
        assert(string.find(requests[4].url, "query=%3C%40U1%3E%20in%3Ageneral", 1, true))
        local ok,err=pcall(slack.getThread,"C1",1790000000.000001)
        assert(not ok and string.find(tostring(err),"timestamp must be",1,true))

end}
