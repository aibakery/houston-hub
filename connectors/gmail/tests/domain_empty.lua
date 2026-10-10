return {
    scenario = {config = {client_id = "fixture-client", client_secret = "fixture-private-secret"}, auth_method = "oauth", auth_config = {}},
    configure = function()
        http = {request = function(request)
            assert(string.find(request.url, "/labels", 1, true))
            return {status = 200, body = '{"labels":[]}'}
        end}
    end,
    run = function(exports)
        assert(not pcall(exports.listMailFolders, "unexpected"))
        local folders = exports.listMailFolders()
        assert(#folders == 0)
        assert(json.encode(folders) == "[]", "empty folders must remain a JSON array")
    end,
}
