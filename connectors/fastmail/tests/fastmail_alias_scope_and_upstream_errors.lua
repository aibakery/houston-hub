return {scenario={["auth_config"]={["token"]="fixture-private-password !@#"},["auth_method"]="token",["config"]={},["publisher"]={}},config={access="read-write"}, configure=function()

        requests, responses = {}, {}
        http = {request = function(req)
            requests[#requests + 1] = req
            assert(#responses > 0, "unexpected request: " .. tostring(req.url))
            local response = table.remove(responses, 1)
            if type(response) == "string" then return {status=200, body=response} end
            if response.status then return {status=response.status, body=response.body or ""} end
            return {status=200, body=json.encode(response)}
        end}
        local MAIL="urn:ietf:params:jmap:mail"
        function session()
            return {username="me@example.com", primaryAccounts={[MAIL]="u1"}, accounts={u1={name="Me"}},
                capabilities={[MAIL]={}}, apiUrl="https://api.fastmail.com/jmap/api/"}
        end
        function result(name, args) return {methodResponses={{name, args, "0"}}} end

end, run=function(fastmail)
        responses={session(), {status=401, body="No Authorization header"}, {status=200, body="not-json"},
            result("Mailbox/get", {list={{id="in", role="inbox", name="Inbox"}, {id="tr", role="trash", name="Trash"}}})}
        local ok, err = pcall(fastmail.listAliases)
        assert(not ok)
        local text = tostring(err)
        assert(string.find(text, "Email submission", 1, true) and string.find(text, "Masked Email", 1, true))
        assert(#requests == 1)
        assert(type(fastmail.sendMessage) == "function", "manual token scopes are unknown at discovery")
        ok, err = pcall(fastmail.sendMessage, {to={{email="recipient@example.com"}}, text="Do not send"})
        assert(not ok and string.find(tostring(err), "Email submission", 1, true))
        assert(#requests == 1, "missing submission scope must fail before draft or send")
        ok, err = pcall(fastmail.listFolders)
        assert(not ok and string.find(tostring(err), "upstream HTTP 401", 1, true) and string.find(tostring(err), "No Authorization header", 1, true))
        ok, err = pcall(fastmail.listFolders)
        assert(not ok and string.find(tostring(err), "invalid JSON", 1, true))
        ok, err = pcall(fastmail.archiveMessages, "m")
        assert(not ok and string.find(tostring(err), "no Archive mailbox", 1, true))
        assert(#responses == 0)

end}
