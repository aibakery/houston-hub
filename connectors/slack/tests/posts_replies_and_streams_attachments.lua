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
    

        responses={
            {ok=true,ts="1.000001"},
            {ok=true,upload_url="https://files.slack.com/upload/v1/signed",file_id="F1"},
            "OK - 11",
            {ok=true,files={{id="F1"}}},
            {ok=true,file={url_private_download="https://files.slack.com/files-pri/T1-F1/report.txt"}},
            {bytes=11},
        }
        local c={id="c"}
        local opts={username="someone-else",attachments={{text="attachment"}}}
        slack.writes.reply(c,"C1","1.000000","Hello",opts)
        assert(opts.username=="someone-else", "do not mutate options")
        slack.writes.uploadFile(c,"report.txt",{channel="C1",thread_ts="1.000000",text="report"})
        assert(requests[3].src=="report.txt" and requests[3].body==nil)
        assert(requests[3].raw and requests[3].method=="POST")
        local file=slack.functions.downloadFile(c,"F1","copy.txt")
        assert(requests[6].dest=="copy.txt")
        assert(file.url=="https://houston.test/files/copy.txt" and file.bytes==11)
        assert(#requests==6)
    
end
