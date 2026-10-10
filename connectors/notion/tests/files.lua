return {
    scenario = {auth_method = "token", auth_config = {token = "fixture-notion-token"}, config = {}, publisher = {}},
    config = {access = "read-write"},
    configure = function()
        requests, responses, signedPaths, writes = {}, {}, {}, {}
        nativeFiles = fixture.files()
        binary = string.char(0, 255, 13, 10) .. "binary payload"
        local file = nativeFiles.open("uploads/report.bin", "w")
        file:write(binary)
        await(file:close())
        local multipart = http.multipart
        streamSources = {}
        function streamed(bytes)
            local native = fixture.reader(bytes)
            local proxy = {closed = false}
            function proxy:read(max) return native:read(max) end
            function proxy:readAll() error("file/SSE responses must stream, never readAll") end
            function proxy:close() self.closed = true; native:close() end
            streamSources[proxy] = native
            return proxy
        end
        fs = {
            open = function(path, mode)
                local native = nativeFiles.open(path, mode)
                if mode == "r" then return native end
                return {
                    write = function(_, source)
                        assert(streamSources[source], "destination must receive the original response Reader")
                        table.insert(writes, {path = path, source = source})
                        return native:write(streamSources[source])
                    end,
                    close = function() return native:close() end,
                }
            end,
            stat = nativeFiles.stat,
            signedGetUrl = function(path)
                table.insert(signedPaths, path)
                return nativeFiles.signedGetUrl(path)
            end,
        }
        http = {
            multipart = multipart,
            request = function(req)
                table.insert(requests, req)
                if req.body ~= nil and type(req.body) ~= "string" then
                    local chunks = {}
                    while true do
                        local chunk = await(req.body:read(7))
                        if chunk.done then break end
                        table.insert(chunks, chunk.data)
                    end
                    req.wire = table.concat(chunks)
                end
                assert(#responses > 0, "unexpected request: " .. req.url)
                return fixture.operation(table.remove(responses, 1))
            end,
        }
        function queueJSON(value, status, headers)
            table.insert(responses, {statusCode = status or 200, headers = headers or {}, body = fixture.reader(json.encode(value))})
        end
        function queueStream(bytes, status, headers)
            local reader = streamed(bytes)
            table.insert(responses, {statusCode = status or 200, headers = headers or {}, body = reader})
            return reader
        end
        function readFile(path)
            local file = nativeFiles.open(path, "r")
            local bytes = await(file:readAll())
            await(file:close())
            return bytes
        end
        function checkSaved(result, path, bytes)
            assert(result.path == path and result.url == "https://houston.test/" .. path)
            assert(result.size == #bytes and readFile(path) == bytes)
            assert(signedPaths[#signedPaths] == path and writes[#writes].path == path)
        end
        function rejected(fn, fragment)
            local ok, err = pcall(fn)
            assert(not ok and string.find(tostring(err), fragment, 1, true), tostring(err))
        end
    end,
    run = function(notion)
        queueJSON({object = "file_upload", id = "up/1", status = "uploaded"})
        local uploaded = notion.sendFileUpload({file_upload_id = "up/1", path = "uploads/report.bin"})
        assert(uploaded.status == "uploaded")
        local req = requests[#requests]
        assert(req.method == "POST" and req.url == "https://api.notion.com/v1/file_uploads/up%2F1/send")
        assert(req.headers["Notion-Version"][1] == "2026-03-11")
        local boundary = string.match(req.headers["Content-Type"][1], "^multipart/form%-data; boundary=(.+)$")
        assert(boundary and req.wire == "--" .. boundary .. '\r\nContent-Disposition: form-data; name="file"; filename="report.bin"\r\nContent-Type: application/octet-stream\r\n\r\n' .. binary .. "\r\n--" .. boundary .. "--\r\n")

        queueJSON({object = "file_upload", id = "up2", status = "pending"})
        notion.sendFileUpload({file_upload_id = "up2", path = "uploads/report.bin", filename = 'quoted"name.pdf', content_type = "application/pdf", part_number = 2})
        req = requests[#requests]
        boundary = string.match(req.headers["Content-Type"][1], "boundary=(.+)$")
        assert(req.wire == "--" .. boundary .. '\r\nContent-Disposition: form-data; name="part_number"\r\n\r\n2\r\n--' .. boundary .. '\r\nContent-Disposition: form-data; name="file"; filename="quoted\\"name.pdf"\r\nContent-Type: application/pdf\r\n\r\n' .. binary .. "\r\n--" .. boundary .. "--\r\n")

        local count = #requests
        for _, part in {0, 1.5, 10001, "1"} do
            rejected(function() notion.sendFileUpload({file_upload_id = "up", path = "uploads/report.bin", part_number = part}) end, "part_number")
        end
        assert(#requests == count, "invalid multipart part numbers must fail before HTTP")
        queueJSON({object = "error", code = "validation_error", message = "part already uploaded", request_id = "request-upload"}, 400)
        rejected(function() notion.sendFileUpload({file_upload_id = "up", path = "uploads/report.bin", part_number = 1}) end, "part already uploaded")
        assert(#requests == count + 1, "uploads must never retry silently")

        local downloadURL = "https://prod-files-secure.s3.us-west-2.amazonaws.com/a/report.bin?signature=opaque%2Bvalue"
        local bytes = string.rep(binary, 1024)
        queueStream(bytes)
        local downloaded = notion.downloadFile({url = downloadURL, path = "downloads/report.bin"})
        checkSaved(downloaded, "downloads/report.bin", bytes)
        req = requests[#requests]
        assert(req.url == downloadURL and req.method == "GET" and req.headers == nil and req.body == nil)
        count = #requests
        rejected(function() notion.downloadFile({url = "http://file.notion.so/file", path = "bad.bin"}) end, "HTTPS")
        assert(#requests == count)
        local failure = queueStream('{"object":"error","message":"expired URL"}', 403)
        local signedCount, writeCount = #signedPaths, #writes
        rejected(function() notion.downloadFile({url = downloadURL, path = "failed.bin"}) end, "expired URL")
        assert(failure.closed and #signedPaths == signedCount and #writes == writeCount)
        assert(not await(nativeFiles.exists("failed.bin")))

        local events = 'id: event-1\nevent: message\ndata: {"text":"Hello"}\n\nid: event-2\nevent: done\ndata: {}\n\n'
        queueStream(events, 200, {["content-type"] = {"text/event-stream; charset=utf-8"}})
        local result = notion.streamSession({path = "sessions/first.sse", agent_id = "agent-1", message = {text = "Hello"}})
        checkSaved(result, "sessions/first.sse", events)
        req = requests[#requests]
        assert(req.method == "POST" and req.url == "https://api.notion.com/v1/sessions")
        assert(req.headers.Accept[1] == "text/event-stream" and req.headers["Content-Type"][1] == "application/json")
        local body = json.decode(req.body)
        assert(body.path == nil and body.agent_id == "agent-1" and body.message.text == "Hello")

        queueStream(events, 200, {["content-type"] = {"TEXT/EVENT-STREAM; charset=utf-8"}})
        result = notion.streamSession({path = "sessions/replay.sse", session_id = "session-1", continue_from = "event-1"})
        checkSaved(result, "sessions/replay.sse", events)
        body = json.decode(requests[#requests].body)
        assert(body.session_id == "session-1" and body.continue_from == "event-1" and body.path == nil)

        signedCount, writeCount = #signedPaths, #writes
        for _, media in {"application/json", "application/x-text/event-stream", "text/event-stream-invalid"} do
            failure = queueStream("unexpected response", 200, {["content-type"] = {media}})
            rejected(function() notion.streamSession({path = "sessions/wrong.sse", session_id = "session-1"}) end, "text/event-stream")
            assert(failure.closed and #signedPaths == signedCount and #writes == writeCount)
        end
        failure = queueStream("missing content type", 200)
        rejected(function() notion.streamSession({path = "sessions/missing.sse", session_id = "session-1"}) end, "text/event-stream")
        assert(failure.closed)
        failure = queueStream('{"object":"error","code":"rate_limited","message":"Slow down","request_id":"request-session"}', 429, {["retry-after"] = {"2"}})
        count = #requests
        rejected(function() notion.streamSession({path = "sessions/error.sse", session_id = "session-1"}) end, "Retry-After: 2")
        assert(failure.closed and #requests == count + 1 and #signedPaths == signedCount and #writes == writeCount)
        assert(#responses == 0)
    end,
}
