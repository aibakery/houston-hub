return {scenario={["auth_config"]={["token"]="fixture-private-password !@#"},["auth_method"]="token",["config"]={},["publisher"]={}},config={access="read-only"}, configure=function()

        requests, responses = {}, {}
        http = {request = function(req)
            requests[#requests + 1] = req
            assert(#responses > 0, "unexpected request: " .. tostring(req.url))
            local response = table.remove(responses, 1)
            return fixture.operation({statusCode=200, headers={}, body=fixture.reader(json.encode(response))})
        end}
        local MAIL="urn:ietf:params:jmap:mail"
        local SUB="urn:ietf:params:jmap:submission"
        function session()
            return {username="me@example.com", primaryAccounts={[MAIL]="u1"}, accounts={u1={name="Me"}},
                capabilities={[MAIL]={}, [SUB]={}}, apiUrl="https://api.fastmail.com/jmap/api/"}
        end
        function result(name, args) return {methodResponses={{name, args, "0"}}} end

end, run=function(fastmail)
        responses={session(), result("Identity/get", {list={{id="i", email="me@example.com", name="Me"}}})}
        local listed = fastmail.listAliases()
        assert(#listed.aliases == 1 and listed.aliases[1].canSend and not listed.aliases[1].masked)
        assert(#listed.notes == 1 and string.find(listed.notes[1], "Masked Email", 1, true))
        assert(#requests == 2)
        assert(fastmail.replyMessage == nil and fastmail.deleteMessage == nil)

end}
