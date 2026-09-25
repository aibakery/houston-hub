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
    

        local c = { id = "private-slack" }
        responses = {
            {ok=true, channels={{id="C1"}}, response_metadata={next_cursor="next+one"}},
            {ok=true, messages={{ts="1790000000.000001"}}, response_metadata={next_cursor="page2"}},
            {ok=true, user_id="U1"},
            {ok=true, messages={matches={{text="hi"}}, paging={page=1,pages=3}}},
        }
        local channels = slack.functions.listChannels(c, {user="U_OTHER"})
        assert(channels.nextCursor == "next+one")
        assert(not string.find(requests[1].url, "U_OTHER", 1, true))
        assert(string.find(requests[1].url, "users.conversations", 1, true))
        local opts={cursor="next+one"}
        local thread=slack.functions.getThread(c, "C1", "1790000000.000001", opts)
        assert(thread.nextCursor=="page2" and opts.channel==nil)
        assert(string.find(requests[2].url, "ts=1790000000.000001", 1, true))
        assert(string.find(requests[2].url, "cursor=next%2Bone", 1, true))
        local mentions=slack.functions.listMentions(c, {query="in:general",page=1})
        assert(mentions.nextPage==2)
        assert(string.find(requests[4].url, "query=%3C%40U1%3E%20in%3Ageneral", 1, true))
        assert(requests[4].connector_id=="private-slack")
        local ok,err=pcall(slack.functions.getThread,c,"C1",1790000000.000001)
        assert(not ok and string.find(err,"timestamp must be",1,true))
    
end
