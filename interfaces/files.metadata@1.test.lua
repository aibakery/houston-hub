return {
    scenario = {},
    configure = function()
        requests = {}
        responses = {
            {status = 200, body = '{"id":"file:1","name":"Report","isFolder":false,"size":42,"private":"excluded"}'},
            {status = 200, body = '{"id":"folder:1","name":"Reports","isFolder":true,"size":999}'},
            {status = 200, body = '{"id":"cloud:1","name":"Document","isFolder":false}'},
            {status = 404, body = 'private upstream diagnostics'},
            {status = 503, body = 'private upstream diagnostics'},
        }
        http = {request = function(request)
            assert(request.url == "https://interface.example.com/stat" and request.method == "POST")
            requests[#requests + 1] = json.decode(request.body).id
            return table.remove(responses, 1)
        end}
    end,
    run = function(example)
        local file = example.statFile("file:1")
        assert(file.id == "file:1" and file.name == "Report" and not file.isFolder and file.size == 42)
        assert(file.private == nil)
        local folder = example.statFile("folder:1")
        assert(folder.isFolder and folder.size == nil)
        assert(example.statFile("cloud:1").size == nil)
        for _, id in {"missing", "failed"} do
            local ok, err = pcall(example.statFile, id)
            assert(not ok and not string.find(tostring(err), "private upstream diagnostics", 1, true))
        end
        assert(not pcall(example.statFile, ""))
        assert(table.concat(requests, ",") == "file:1,folder:1,cloud:1,missing,failed")
        assert(#responses == 0)
    end,
}
