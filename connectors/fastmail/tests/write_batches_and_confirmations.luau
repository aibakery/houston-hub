return {
    scenario = {auth_method = "token", auth_config = {token = "fixture-private-token"}, config = {}, publisher = {}},
    config = {access = "read-write"},
    configure = function()
        requests, responses = {}, {}
        http = {request = function(request)
            requests[#requests + 1] = request
            local response = table.remove(responses, 1)
            assert(response, "unexpected request: " .. request.url)
            return fixture.operation({statusCode=200, headers={}, body=fixture.reader(json.encode(response))})
        end}
        function result(name, data) return {methodResponses = {{name, data, "0"}}} end
        function args(index) return json.decode(requests[index].body).methodCalls[1][2] end
        folders = {{id = "ar", role = "archive"}, {id = "dr", role = "drafts"}, {id = "se", role = "sent"}}
        responses[1] = {
            username = "me@example.com", primaryAccounts = {["urn:ietf:params:jmap:mail"] = "u1"},
            accounts = {u1 = {name = "Me"}}, capabilities = {["urn:ietf:params:jmap:submission"] = {}},
            apiUrl = "https://api.fastmail.com/jmap/api/",
        }
    end,
    run = function(fastmail)
        local ids, updated = {}, {}
        for index = 1, 51 do
            ids[index] = "m" .. index
            if index <= 50 then updated[ids[index]] = json.decode("null") end
        end
        responses[#responses + 1] = result("Mailbox/get", {list = folders})
        responses[#responses + 1] = result("Email/set", {updated = updated})
        responses[#responses + 1] = result("Email/set", {updated = {m51 = json.decode("null")}})
        local moved = fastmail.moveMessages({ids = ids, folder = "archive"})
        assert(#moved.ids == 51 and moved.ids[1] == "m1" and moved.ids[51] == "m51" and moved.folderId == "ar")
        local first, second = args(3).update, args(4).update
        assert(first.m1.mailboxIds.ar and first.m50.mailboxIds.ar and first.m51 == nil)
        assert(second.m51.mailboxIds.ar and second.m50 == nil)

        local destroyed = {}
        for index = 1, 50 do destroyed[index] = ids[index] end
        responses = {result("Email/set", {destroyed = destroyed}), result("Email/set", {destroyed = {}})}
        local before = #requests
        local ok, err = pcall(fastmail.destroyMessages, ids)
        assert(not ok and string.find(tostring(err), "Missing destroy confirmation for m51", 1, true))
        assert(#requests == before + 2, "a partial destructive batch must never replay")
        assert(#args(before + 1).destroy == 50 and args(before + 2).destroy[1] == "m51")

        local identities = {list = {{id = "me", email = "me@example.com"}}}
        responses = {
            result("Identity/get", identities), result("Mailbox/get", {list = folders}),
            result("Email/set", {created = {draft = {id = "draft"}}}),
            result("EmailSubmission/set", {created = {send = {}}}),
        }
        before = #requests
        ok, err = pcall(fastmail.sendMessage, {to = {{email = "to@example.com"}}, text = "Hello"})
        assert(not ok and string.find(tostring(err), "Missing submission confirmation", 1, true))
        assert(#requests == before + 4, "an ambiguous send must never replay")

        responses = {
            result("Identity/get", identities), result("Mailbox/get", {list = folders}),
            result("Email/set", {created = {draft = {id = ""}}}),
        }
        before = #requests
        ok, err = pcall(fastmail.sendMessage, {to = {{email = "to@example.com"}}, text = "Hello"})
        assert(not ok and string.find(tostring(err), "Missing draft creation confirmation", 1, true))
        assert(#requests == before + 3, "invalid draft IDs must never be submitted")
        assert(#responses == 0)
    end,
}
