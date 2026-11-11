-- A token without Email submission prepares drafts but never sends.
return {scenario={["auth_config"]={["token"]="fixture-private-password !@#"},["auth_method"]="token",["config"]={},["publisher"]={}},config={access="read-write"}, configure=function()

        requests, responses = {}, {}
        http = {request = function(req)
            requests[#requests + 1] = req
            if req.body ~= nil and type(req.body) ~= "string" then
                assert(await(req.body:readAll()) == "payload")
                await(req.body:close())
            end
            assert(#responses > 0, "unexpected request: " .. tostring(req.url))
            local response = table.remove(responses, 1)
            return fixture.operation({statusCode=200, headers={}, body=fixture.reader(json.encode(response))})
        end}
        fs = fixture.files()
        local input = fs.open("files/brief.pdf", "w")
        input:write("payload")
        await(input:close())
        local MAIL="urn:ietf:params:jmap:mail"
        local CORE="urn:ietf:params:jmap:core"
        local SUB="urn:ietf:params:jmap:submission"
        function session()
            -- The server supports submission, but this token's account may not use it.
            return {username="me@example.com", primaryAccounts={[MAIL]="u1"}, accounts={u1={name="Me", accountCapabilities={[MAIL]={}}}},
                capabilities={[CORE]={}, [MAIL]={}, [SUB]={}}, apiUrl="https://api.fastmail.com/jmap/api/",
                uploadUrl="https://api.fastmail.com/jmap/upload/{accountId}/"}
        end
        function result(name, args) return {methodResponses={{name, args, "0"}}} end
        function results(...)
            local out = {}
            for index, item in {...} do out[index] = {item[1], item[2], tostring(index - 1)} end
            return {methodResponses=out}
        end
        folders={{id="in", role="inbox", name="Inbox"}, {id="dr", role="drafts", name="Drafts"}, {id="se", role="sent", name="Sent"}}
        function original()
            return {id="m", messageId={"<m@example.com>"}, references={"<old@example.com>"},
                from={{name="Sender", email="sender@example.com"}}, replyTo=json.decode("null"),
                to={{email="me@example.com"}, {email="other@example.com"}}, cc={{email="cc@example.com"}}, subject="Hello"}
        end
        function saved(id, extra)
            local msg = {id=id, keywords={["$draft"]=true, ["$seen"]=true}, mailboxIds={dr=true},
                from={{name="Me", email="me@example.com"}}, to={{email="sender@example.com"}},
                cc={{email="other@example.com"}}, bcc=json.decode("null"), replyTo=json.decode("null"), subject="Re: Hello",
                inReplyTo={"<m@example.com>"}, references={"<old@example.com>", "<m@example.com>"},
                attachments={{blobId="b1", name="a.csv", type="text/csv", charset="iso-8859-1", disposition="attachment", cid=json.decode("null")},
                    {blobId="img", name="logo.png", type="image/png", disposition="inline", cid="c1"},
                    {blobId="b2", name="b.pdf", type="application/pdf", disposition="attachment", cid="x2"}}}
            for key, value in extra or {} do msg[key] = value end
            return msg
        end
        function jmapSince(start)
            local out = {}
            for i = start + 1, #requests do
                local req = requests[i]
                if type(req.body) == "string" then
                    local decoded = json.decode(req.body)
                    for _, methodCall in decoded.methodCalls do out[#out + 1] = {name=methodCall[1], args=methodCall[2]} end
                elseif req.body ~= nil then
                    out[#out + 1] = {name="upload", req=req}
                end
            end
            return out
        end

end, run=function(fastmail)
        responses={session(), result("Mailbox/get", {list=folders}), {blobId="blob1", type="application/pdf", size=7},
            result("Email/set", {created={draft={id="d1", threadId="t1"}}})}
        local made = fastmail.createDraft({subject="Plan", text="Draft body", attachments={{path="files/brief.pdf", mimeType="application/pdf"}}})
        assert(made.id == "d1" and made.threadId == "t1")
        local calls = jmapSince(0)
        assert(#calls == 3 and calls[1].name == "Mailbox/get" and calls[2].name == "upload" and calls[3].name == "Email/set")
        local draft = calls[3].args.create.draft
        assert(draft.from[1].email == "me@example.com" and draft.to == nil and draft.subject == "Plan")
        assert(draft.mailboxIds.dr and draft.keywords["$draft"] and draft.keywords["$seen"])
        assert(draft.bodyValues.text.value == "Draft body" and draft.htmlBody == nil)
        assert(draft.attachments[1].blobId == "blob1" and draft.attachments[1].name == "brief.pdf")

        local mark = #requests
        local ok, err = pcall(function() fastmail.createDraft({text="x", identityId="i"}) end)
        assert(not ok and string.find(tostring(err), "Email submission", 1, true) and #requests == mark)
        ok, err = pcall(function() fastmail.createDraft({text="x", from="Support"}) end)
        assert(not ok and string.find(tostring(err), "email address", 1, true) and #requests == mark)
        ok, err = pcall(function() fastmail.replyMessage("m", {text="x"}) end)
        assert(not ok and string.find(tostring(err), "Email submission", 1, true) and #requests == mark)

        responses={results({"Email/get", {list={original()}}}, {"Mailbox/get", {list=folders}}),
            result("Email/set", {created={draft={id="d2", threadId="t-orig"}}})}
        mark = #requests
        made = fastmail.createReplyDraft({id="m", text="Thanks", all=true})
        assert(made.id == "d2" and made.threadId == "t-orig")
        calls = jmapSince(mark)
        assert(#calls == 3 and calls[1].name == "Email/get" and calls[2].name == "Mailbox/get")
        assert(#requests == mark + 2, "the original message and folders share one request")
        local wanted = {}
        for _, property in calls[1].args.properties do wanted[property] = true end
        assert(wanted["header:X-Delivered-To:asAddresses:all"] and wanted["header:X-Resolved-To:asAddresses:all"])
        draft = calls[3].args.create.draft
        assert(draft.from[1].email == "me@example.com" and draft.subject == "Re: Hello")
        assert(draft.to[1].email == "sender@example.com" and #draft.cc == 2 and draft.cc[1].email == "other@example.com")
        assert(draft.inReplyTo[1] == "<m@example.com>" and draft.references[1] == "<old@example.com>" and draft.references[2] == "<m@example.com>")
        assert(draft.keywords["$draft"] and draft.mailboxIds.dr)

        local toAlias = original()
        toAlias.to = {{email="support@example.com"}, {email="other@example.com"}}
        -- Fastmail's header comes first; a later instance from the sender must not count as yours.
        toAlias["header:X-Delivered-To:asAddresses:all"] = {{{email="Support@example.com"}}, {{email="other@example.com"}}}
        toAlias["header:X-Resolved-To:asAddresses:all"] = {{{email="me@example.com"}}}
        responses={results({"Email/get", {list={toAlias}}}, {"Mailbox/get", {list=folders}}),
            result("Email/set", {created={draft={id="d-alias"}}})}
        mark = #requests
        assert(fastmail.createReplyDraft({id="m", text="Thanks", all=true}).id == "d-alias")
        draft = jmapSince(mark)[3].args.create.draft
        assert(draft.from[1].email == "Support@example.com", "a reply comes from the alias the message was delivered to")
        assert(#draft.cc == 2 and draft.cc[1].email == "other@example.com" and draft.cc[2].email == "cc@example.com")

        responses={result("Email/get", {list={saved("d2", {textBody={{partId="1", type="text/plain"}}, htmlBody={{partId="2", type="text/html"}},
                bodyValues={["1"]={value="Hi"}, ["2"]={value="<p>Hi</p>"}}})}}),
            result("Email/set", {created={draft={id="d3", threadId="t-orig"}}}), result("Email/set", {destroyed={"d2"}})}
        mark = #requests
        made = fastmail.updateDraft({id="d2", subject="Re: Hello again", cc={}})
        assert(made.id == "d3")
        calls = jmapSince(mark)
        assert(#calls == 3 and calls[1].args.fetchTextBodyValues and calls[1].args.fetchHTMLBodyValues)
        draft = calls[2].args.create.draft
        assert(draft.subject == "Re: Hello again" and draft.cc == nil and draft.to[1].email == "sender@example.com")
        assert(draft.from[1].email == "me@example.com" and draft.keywords["$draft"] and draft.mailboxIds.dr)
        assert(draft.bodyValues.text.value == "Hi" and draft.bodyValues.html.value == "<p>Hi</p>" and draft.htmlBody[1].type == "text/html")
        assert(#draft.attachments == 3 and draft.attachments[3].blobId == "b2" and draft.attachments[1].blobId == "b1" and draft.attachments[1].name == "a.csv" and draft.attachments[1].disposition == "attachment")
        assert(draft.attachments[1].charset == "iso-8859-1" and draft.attachments[2].cid == "c1" and draft.attachments[2].disposition == "inline")
        assert(draft.inReplyTo[1] == "<m@example.com>" and #draft.references == 2)
        assert(calls[3].args.destroy[1] == "d2" and calls[3].args.create == nil)

        responses={result("Email/get", {list={saved("d3")}}), result("Email/set", {created={draft={id="d4"}}}), result("Email/set", {destroyed={"d3"}})}
        mark = #requests
        made = fastmail.updateDraft({id="d3", text="New body", from="ME@example.com", attachments={}})
        assert(made.id == "d4" and made.threadId == nil)
        calls = jmapSince(mark)
        assert(#calls == 3 and not calls[1].args.fetchTextBodyValues)
        for _, property in calls[1].args.properties do assert(property ~= "bodyValues") end
        draft = calls[2].args.create.draft
        assert(draft.from[1].email == "ME@example.com" and draft.from[1].name == "Me" and draft.bodyValues.text.value == "New body")
        assert(draft.htmlBody == nil and draft.attachments == nil and draft.subject == "Re: Hello")

        responses={result("Email/get", {list={saved("m", {keywords={["$seen"]=true}})}})}
        mark = #requests
        ok, err = pcall(function() fastmail.updateDraft({id="m", subject="x"}) end)
        assert(not ok and string.find(tostring(err), "not a draft", 1, true) and #requests == mark + 1)

        responses={result("Email/get", {list={saved("d4", {textBody={{partId="1", type="text/plain"}}, htmlBody={{partId="2", type="text/html"}},
                bodyValues={["1"]={value="Hi"}, ["2"]={value="<p>Hi <img src=\"cid:c1\"></p>"}}})}}),
            {blobId="blob1", type="application/pdf", size=7}, result("Email/set", {created={draft={id="d5"}}}),
            result("Email/set", {notDestroyed={d4={type="serverFail"}}})}
        mark = #requests
        ok, err = pcall(function() fastmail.updateDraft({id="d4", attachments={{path="files/brief.pdf"}}}) end)
        assert(not ok and string.find(tostring(err), "Saved new draft d5", 1, true) and string.find(tostring(err), "old draft d4", 1, true))
        calls = jmapSince(mark)
        assert(#calls == 4 and calls[2].name == "upload")
        draft = calls[3].args.create.draft
        assert(#draft.attachments == 2 and draft.attachments[1].blobId == "blob1" and draft.attachments[2].blobId == "img")
        assert(draft.bodyValues.html.value == "<p>Hi <img src=\"cid:c1\"></p>")

        responses={result("Email/get", {list={saved("d5")}}), result("Email/set", {destroyed={"d5"}})}
        mark = #requests
        assert(fastmail.deleteDraft({id="d5"}).id == "d5")
        calls = jmapSince(mark)
        assert(#calls == 2 and calls[2].args.destroy[1] == "d5")

        responses={result("Email/get", {list={saved("m", {keywords={["$seen"]=true}})}})}
        mark = #requests
        ok, err = pcall(function() fastmail.deleteDraft("m") end)
        assert(not ok and string.find(tostring(err), "not a draft", 1, true) and #requests == mark + 1)

        mark = #requests
        ok, err = pcall(function() fastmail.sendDraft("d4") end)
        assert(not ok and string.find(tostring(err), "Email submission", 1, true) and #requests == mark)
        assert(#responses == 0)

end}
