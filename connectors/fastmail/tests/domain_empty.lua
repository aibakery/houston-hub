return {
    scenario = {publisher = {}, config = {}, auth_method = "token", auth_config = {token = "fixture-private-token"}},
    configure = function()
        requests = 0
        http = {request = function(_request)
            requests += 1
            if requests == 1 then
                return {status = 200, body = json.encode({username = "mail@example.test", primaryAccounts = {["urn:ietf:params:jmap:mail"] = "account"}, accounts = {account = {name = "Account"}}, apiUrl = "https://api.fastmail.com/jmap/api/"})}
            end
            return {status = 200, body = '{"methodResponses":[["Mailbox/get",{"list":[]},"0"]]}'}
        end}
    end,
    run = function(exports)
        assert(not pcall(exports.listMailFolders, "unexpected"))
        local folders = exports.listMailFolders()
        assert(#folders == 0)
        assert(json.encode(folders) == "[]", "empty folders must remain a JSON array")
    end,
}
