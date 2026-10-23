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


        responses={
            {ok=true,ts="1.000001"},
            {ok=true,upload_url="https://files.slack.com/upload/v1/signed",file_id="F1"},
            "OK - 11",
            {ok=true,files={{id="F1"}}},
            {ok=true,file={url_private_download="https://files.slack.com/files-pri/T1-F1/report.txt"}},
            {bytes=11},
        }
end, run=function(slack)
        local opts={username="someone-else",attachments={{text="attachment"}}}
        slack.reply("C1","1.000000","Hello",opts)
        assert(opts.username=="someone-else", "do not mutate options")
        slack.uploadFile("report.txt",{channel="C1",thread_ts="1.000000",text="report"})
        assert(requests[3].src=="report.txt" and requests[3].body==nil)
        assert(requests[3].method=="POST")
        local file=slack.downloadFile("F1","copy.txt")
        assert(requests[6].dest=="copy.txt")
        assert(file.url=="https://houston.test/files/copy.txt" and file.bytes==11)
        assert(#requests==6)

end}
