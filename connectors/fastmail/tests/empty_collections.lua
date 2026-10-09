return {
    scenario = {auth_method = "token", auth_config = {token = "fixture-private-token"}, config = {}, publisher = {}},
    config = {access = "read-only"},
    configure = function()
        requests, responses = {}, {}
        http = {request = function(request)
            requests[#requests + 1] = request
            local response = table.remove(responses, 1)
            assert(response, "unexpected request: " .. request.url)
            return {status = 200, body = json.encode(response)}
        end}
        function result(name, data) return {methodResponses = {{name, data, "0"}}} end
        responses = {
            {
                username = "me@example.com", primaryAccounts = {["urn:ietf:params:jmap:mail"] = "u1"},
                accounts = {u1 = {name = "Me"}}, capabilities = {}, apiUrl = "https://api.fastmail.com/jmap/api/",
            },
            result("Email/query", {ids = json.decode("[]"), position = 0, total = 0}),
            result("Email/query", {ids = json.decode("[]"), position = 0, total = 0}),
            result("Thread/get", {list = {{id = "empty", emailIds = json.decode("[]")}}}),
            result("Email/get", {list = {{id = "m", attachments = json.decode("[]")}}}),
            result("Email/get", {list = {{id = "m", attachments = json.decode("[]")}}}),
        }
    end,
    run = function(fastmail)
        assert(json.encode(fastmail.listMessages({includeSpamTrash = true}).messages) == "[]")
        assert(json.encode(fastmail.listThreads({includeSpamTrash = true}).threads) == "[]")
        assert(json.encode(fastmail.getThread("empty").messages) == "[]")
        assert(json.encode(fastmail.listAttachments("m")) == "[]")
        local message = fastmail.getMessage("m")
        assert(json.encode(message.attachments) == "[]" and json.encode(message.received) == "[]")
        assert(json.encode(fastmail.getAttachments({messageId = "m", items = {}})) == "[]")
        assert(#responses == 0 and #requests == 6, "empty selections and threads must not fetch bodies")
    end,
}
