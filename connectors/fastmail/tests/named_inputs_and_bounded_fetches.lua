return {
    scenario = {auth_method = "token", auth_config = {token = "fixture-private-token"}, config = {}, publisher = {}},
    config = {access = "read-write"},
    configure = function()
        requests, responses = {}, {}
        http = {request = function(request)
            requests[#requests + 1] = request
            local response = table.remove(responses, 1)
            assert(response, "unexpected request: " .. request.url)
            return fixture.operation({statusCode=200, headers={}, body=fixture.reader(if type(response)=="string" then response else json.encode(response))})
        end}
        fs = fixture.files()
        function result(name, data) return {methodResponses = {{name, data, "0"}}} end
        function args(index) return json.decode(requests[index].body).methodCalls[1][2] end
        responses[1] = {
            username = "me@example.com", primaryAccounts = {["urn:ietf:params:jmap:mail"] = "u1"},
            accounts = {u1 = {name = "Me"}}, capabilities = {}, apiUrl = "https://api.fastmail.com/jmap/api/",
            downloadUrl = "https://www.fastmailusercontent.com/jmap/download/{accountId}/{blobId}/{name}?type={type}",
        }
    end,
    run = function(fastmail)
        responses[#responses + 1] = result("Email/query", {ids = {}, position = 0, total = 0})
        local page = fastmail.listMessages({includeSpamTrash = true})
        assert(#page.messages == 0 and page.nextPageToken == nil)
        assert(#requests == 2, "an unfiltered query does not need folder metadata")

        responses[1] = result("Email/get", {list = {{id = "m2", preview = "two"}, {id = "m1", preview = "one"}}})
        local messages = fastmail.getMessages({ids = {{id = "m1"}, "m2"}, maxBodyValueBytes = 42})
        assert(messages[1].id == "m1" and messages[2].id == "m2", "preserve caller order")
        assert(args(3).maxBodyValueBytes == 42)

        responses[1] = result("Email/get", {list = {{id = "m1", preview = "one"}}})
        assert(fastmail.getMessage({id = "m1", maxBodyValueBytes = 7}).body == "one")
        assert(args(4).maxBodyValueBytes == 7)

        local ids, firstBatch = {}, {}
        for index = 1, 51 do ids[index] = "m" .. index end
        for index = 50, 1, -1 do firstBatch[#firstBatch + 1] = {id = ids[index]} end
        responses = {
            result("Thread/get", {list = {{id = "thread", emailIds = ids}}}),
            result("Email/get", {list = firstBatch}),
            result("Email/get", {list = {{id = "m51"}}}),
        }
        local thread = fastmail.getThread({id = "thread", maxBodyValueBytes = 12})
        assert(#thread.messages == 51 and thread.messages[1].id == "m1" and thread.messages[51].id == "m51")
        assert(#args(6).ids == 50 and #args(7).ids == 1 and args(7).ids[1] == "m51")
        assert(args(6).maxBodyValueBytes == 12 and args(7).maxBodyValueBytes == 12)

        local attachment = {blobId = "blob", name = "a +.txt", type = "text/plain", size = 3}
        responses = {result("Email/get", {list = {{id = "m1", attachments = {attachment}}}}), string.char(0,255,120)}
        local files = fastmail.getAttachments({messageId = "m1", items = {{id = "blob", path = "mail/a.txt"}}})
        assert(#files == 1 and files[1].path == "mail/a.txt" and files[1].size == 3)
        assert(files[1].url == "https://houston.test/mail/a.txt")
        local metadata = args(8)
        assert(metadata.fetchTextBodyValues == nil and metadata.fetchHTMLBodyValues == nil, "attachment lookup must not fetch message bodies")
        local properties = {}
        for _, name in metadata.properties do properties[name] = true end
        assert(properties.attachments and not properties.bodyValues and not properties.textBody and not properties.htmlBody)
        local downloaded = fs.open("mail/a.txt", "r")
        assert(await(downloaded:readAll()) == string.char(0,255,120))
        await(downloaded:close())
        assert(requests[9].url == "https://www.fastmailusercontent.com/jmap/download/u1/blob/a%20%2B.txt?type=text%2Fplain")

        local before = #requests
        assert(#fastmail.getAttachments({messageId = "m1", items = {}}) == 0)
        assert(#requests == before, "empty attachment selection needs no transport")
        responses = {result("Email/get", {list = {{id = "m1", attachments = {attachment}}}})}
        local ok, err = pcall(fastmail.getAttachments, {messageId = "m1", items = {
            {id = "blob", path = "same.txt"}, {id = "blob", path = "same.txt"},
        }})
        assert(not ok and string.find(tostring(err), "distinct", 1, true))
        assert(#requests == before + 1, "validate every destination before downloading")

        responses = {
            result("Mailbox/get", {list = {{id = "in", role = "inbox"}}}),
            result("Mailbox/set", {created = {folder = {id = "projects"}}}),
        }
        local folder = fastmail.createFolder({name = "Projects", parentId = "in"})
        assert(folder.id == "projects" and folder.name == "Projects")
        local created = args(#requests).create.folder
        assert(created.name == "Projects" and created.parentId == "in")
        assert(#responses == 0)
    end,
}
