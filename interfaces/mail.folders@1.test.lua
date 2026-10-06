return {
    scenario = {},
    configure = function()
        responses = {
            {status = 200, body = '[{"id":"z","name":"Inbox","extra":true},{"id":"a","name":"Inbox"}]'},
            {status = 200, body = '[]'},
            {status = 503, body = 'private upstream diagnostics'},
        }
        http = {request = function(request)
            assert(request.url == "https://interface.example.com/folders")
            return table.remove(responses, 1)
        end}
    end,
    run = function(example)
        local folders = example.listMailFolders()
        assert(#folders == 2 and folders[1].id == "a" and folders[2].id == "z")
        assert(folders[1].name == "Inbox" and folders[2].name == "Inbox")
        assert(folders[2].extra == nil)
        assert(json.encode(example.listMailFolders()) == "[]")
        local ok, err = pcall(example.listMailFolders)
        assert(not ok and not string.find(tostring(err), "private upstream diagnostics", 1, true))
        assert(#responses == 0)
    end,
}
