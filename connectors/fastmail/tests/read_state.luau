return {
    scenario = {auth_method = "token", auth_config = {token = "fixture-private-password !@#"}, config = {}, publisher = {}},
    config = {access = "read-write"},
    configure = function()
        requests, responses = {}, {}
        local MAIL = "urn:ietf:params:jmap:mail"
        local state = {
            username = "me@example.com", primaryAccounts = {[MAIL] = "u1"}, accounts = {u1 = {name = "Me"}},
            capabilities = {[MAIL] = {}}, apiUrl = "https://api.fastmail.com/jmap/api/",
        }
        http = {request = function(req)
            requests[#requests + 1] = req
            assert(req.headers.Authorization == nil)
            if req.method == "GET" then
                assert(#requests == 1 and req.url == "https://api.fastmail.com/jmap/session")
                return fixture.operation({statusCode = 200, headers = {}, body = fixture.reader(json.encode(state))})
            end
            assert(req.method == "POST" and req.url == state.apiUrl)
            local body = json.decode(req.body)
            assert(#body.using == 2 and body.using[2] == MAIL, "read state requires no submission scope")
            assert(#body.methodCalls == 1 and body.methodCalls[1][1] == "Email/set")
            assert(body.methodCalls[1][2].accountId == "u1")
            assert(#responses > 0, "unexpected write")
            local response = table.remove(responses, 1)
            return fixture.operation({statusCode = 200, headers = {}, body = fixture.reader(json.encode({
                methodResponses = {{"Email/set", response, "0"}},
            }))})
        end}
        function update(n) return json.decode(requests[n].body).methodCalls[1][2].update end
        function checkPatch(patch, value)
            local count = 0
            for key, actual in patch do
                count += 1
                assert(key == "keywords/$seen" and actual == value, "patch must preserve other keywords and mailboxes")
            end
            assert(count == 1)
        end
    end,
    run = function(mail)
        for _, fn in {mail.markRead, mail.markUnread} do
            for _, invalid in {"", {}, {id = ""}, {"valid", ""}} do
                assert(not pcall(fn, invalid))
            end
        end
        assert(#requests == 0, "validate every ID before discovery or mutation")

        responses = {json.decode([[{"updated":{"m":null}}]])}
        local marked = mail.markRead("m")
        assert(#marked.ids == 1 and marked.ids[1] == "m")
        checkPatch(update(2).m, true)

        responses = {json.decode([[{"updated":{"m":null}}]])}
        local unread = mail.markUnread({id = "m"})
        assert(#unread.ids == 1 and unread.ids[1] == "m")
        checkPatch(update(3).m, json.decode("null"))

        local ids, first = {}, {}
        for i = 1, 51 do
            ids[i] = {id = "m" .. i}
            if i <= 50 then first["m" .. i] = json.decode("null") end
        end
        responses = {{updated = first}, {updated = {m51 = {}}}}
        marked = mail.markRead(ids)
        assert(#marked.ids == 51 and #requests == 5)
        for batch, request in {update(4), update(5)} do
            local count = 0
            for id, patch in request do
                count += 1
                checkPatch(patch, true)
                local index = tonumber(string.sub(id, 2))
                assert(if batch == 1 then index <= 50 else index == 51)
            end
            assert(count == (if batch == 1 then 50 else 1))
        end
        for i, id in marked.ids do assert(id == "m" .. i) end

        for i = 52, 101 do ids[i] = {id = "m" .. i} end
        responses = {{updated = first}, {notUpdated = {m51 = {type = "forbidden", description = "read-only mailbox"}}}}
        local ok, err = pcall(mail.markUnread, ids)
        assert(not ok and string.find(tostring(err), "m51: forbidden", 1, true))
        assert(string.find(tostring(err), '"operation":"markUnread"', 1, true))
        assert(#requests == 7 and #responses == 0, "partial failure must stop before batch 3 without replay")
        for _, request in {update(6), update(7)} do
            for _, patch in request do checkPatch(patch, json.decode("null")) end
        end

        responses = {{updated = {}}}
        ok, err = pcall(mail.markRead, {"missing"})
        assert(not ok and string.find(tostring(err), "Missing update confirmation for missing", 1, true))
        responses = {{notUpdated = {missing = {type = "notFound"}}}}
        ok, err = pcall(mail.markRead, "missing")
        assert(not ok and string.find(tostring(err), "missing: notFound", 1, true))
        assert(#requests == 9 and #responses == 0)
    end,
}
