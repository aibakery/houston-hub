return {scenario={["auth_config"]={["token"]="fixture-private-password !@#"},["auth_method"]="token",["config"]={},["publisher"]={}},config={access="read-write"}, configure=function()

        requests, responses = {}, {}
        http = {request = function(req)
            requests[#requests + 1] = req
            assert(#responses > 0, "unexpected request: " .. tostring(req.url))
            local response = table.remove(responses, 1)
            if type(response) == "string" then return {status=200, body=response} end
            if response.status then return {status=response.status, body=response.body or ""} end
            return {status=200, body=json.encode(response)}
        end}
        fs = {
            signedGetUrl=function(path) return "https://houston.test/" .. path end,
            stat=function() return {size=10, isFile=true} end,
        }
        local MAIL="urn:ietf:params:jmap:mail"
        local SUB="urn:ietf:params:jmap:submission"
        local MASKED="https://www.fastmail.com/dev/maskedemail"
        local CORE="urn:ietf:params:jmap:core"
        function session()
            return {username="me@example.com", primaryAccounts={[MAIL]="u1", [MASKED]="m1"},
                accounts={u1={name="Me"}}, capabilities={[CORE]={}, [MAIL]={}, [SUB]={}, [MASKED]={}},
                apiUrl="https://phl.api.fastmail.com/jmap/api/",
                uploadUrl="https://phl.api.fastmail.com/jmap/upload/{accountId}/",
                downloadUrl="https://www.fastmailusercontent.com/jmap/download/{accountId}/{blobId}/{name}?type={type}"}
        end
        function result(name, args) return {methodResponses={{name, args, "0"}}} end
        folders={{id="in", role="inbox", name="Inbox"}, {id="tr", role="trash", name="Trash"},
            {id="sp", role="junk", name="Spam"}, {id="dr", role="drafts", name="Drafts"},
            {id="se", role="sent", name="Sent"}, {id="ar", role="archive", name="Archive"}}
        identities={list={{id="i-me", email="me@example.com", name="Me"}, {id="i-sup", email="support@example.com", name="Support"}}}
        masked={list={{id="mask-sup", email="support@example.com", state="enabled", description="Support", forDomain="example.com"},
            {id="mask-admin", email="admin@example.com", state="enabled", description="Billing", forDomain="example.com"}}}
        function original()
            return {id="m", messageId={"<m@example.com>"}, references={"<old@example.com>", "<m@example.com>"},
                from={{name="Sender", email="sender@example.com"}}, replyTo=json.decode("null"),
                to={{email="support@example.com"}, {email="other@example.com"}}, cc={{email="cc@example.com"}}, subject="Hello"}
        end
        function bare()
            return {id="m2", messageId=json.decode("null"), from={{email="sender@example.com"}},
                to={{email="me@example.com"}}, subject="Re: Hello"}
        end
        function jmapSince(start)
            local out = {}
            for i = start + 1, #requests do
                local req = requests[i]
                if req.src then
                    out[#out + 1] = {upload=req}
                elseif type(req.body) == "string" then
                    local decoded = json.decode(req.body)
                    out[#out + 1] = {name=decoded.methodCalls[1][1], args=decoded.methodCalls[1][2], using=decoded.using, req=req}
                end
            end
            return out
        end

end, run=function(fastmail)
        responses={session(), result("Identity/get", identities), result("MaskedEmail/get", masked),
            result("Mailbox/get", {list=folders}), result("Email/query", {ids={"m"}, position=0, total=1}),
            result("Email/get", {list={original()}}), result("Identity/get", identities), result("Mailbox/get", {list=folders}),
            result("Email/set", {created={draft={id="d1"}}}), result("EmailSubmission/set", {created={send={id="s1"}}}),
            result("Email/get", {list={bare()}}), result("Identity/get", identities), result("Mailbox/get", {list=folders}),
            result("Email/set", {created={draft={id="d2"}}}), result("EmailSubmission/set", {created={send={id="s2"}}}),
            result("Email/get", {list={original()}}), result("Identity/get", identities), result("Mailbox/get", {list=folders}),
            result("Email/set", {created={draft={id="d3"}}}), result("EmailSubmission/set", {created={send={id="s3"}}}),
            result("Email/get", {list={original()}}), result("Identity/get", identities),
            result("Mailbox/get", {list=folders}), result("Mailbox/set", {created={folder={id="f1", name="Projects"}}}),
            result("Mailbox/get", {list=folders}), result("Email/set", json.decode([[{"updated":{"a":null,"b":null}}]])),
            result("Mailbox/get", {list=folders}), result("Mailbox/get", {list=folders}), result("Email/set", json.decode([[{"updated":{"c":null}}]])),
            result("Mailbox/get", {list=folders}), result("Email/set", json.decode([[{"updated":{"a":null,"b":null}}]])),
            result("Email/set", {destroyed={"a"}}),
            result("Identity/get", identities), result("Mailbox/get", {list=folders}),
            {blobId="blob1", type="application/pdf", size=10},
            result("Email/set", {created={draft={id="d4"}}}), result("EmailSubmission/set", {created={send={id="s4"}}})}

        local mark = #requests
        local listed = fastmail.listAliases()
        local calls = jmapSince(mark)
        assert(#calls == 2 and calls[1].name == "Identity/get" and calls[2].name == "MaskedEmail/get")
        assert(calls[2].args.accountId == "m1")
        assert(calls[2].using[3] == "https://www.fastmail.com/dev/maskedemail")
        assert(json.encode(listed.notes) == "[]")
        local by = {}
        for _, alias in listed.aliases do by[alias.email] = alias end
        assert(by["support@example.com"].canSend and by["support@example.com"].masked and by["support@example.com"].identityId == "i-sup")
        assert(by["admin@example.com"].masked and not by["admin@example.com"].canSend and by["admin@example.com"].name == "Billing")
        assert(by["me@example.com"].canSend and not by["me@example.com"].masked)
        local profile = fastmail.getProfile()
        assert(profile.canSend and profile.emailAddress == "me@example.com" and profile.accountId == "u1")
        assert(profile.capabilities[1] == "https://www.fastmail.com/dev/maskedemail")

        mark = #requests
        local page = fastmail.listMessages({alias="support@example.com", from="a@example.com", folder="INBOX"})
        assert(page.messages[1].id == "m")
        calls = jmapSince(mark)
        local conditions = calls[2].args.filter.conditions
        assert(#conditions == 3 and conditions[1].from == "a@example.com" and conditions[3].inMailbox == "in")
        assert(conditions[2].operator == "OR" and #conditions[2].conditions == 4)
        local keys = {}
        for _, item in conditions[2].conditions do for k, v in item do keys[k] = v end end
        assert(keys.to == "support@example.com" and keys.cc == "support@example.com" and keys.bcc == "support@example.com" and keys.from == "support@example.com")

        mark = #requests
        local sent = fastmail.replyMessage("m", {text="Thanks"})
        assert(sent.id == "d1" and sent.submissionId == "s1")
        calls = jmapSince(mark)
        local draft = calls[4].args.create.draft
        assert(calls[4].name == "Email/set" and draft.from[1].email == "support@example.com")
        assert(draft.subject == "Re: Hello" and draft.to[1].email == "sender@example.com" and draft.cc == nil)
        assert(draft.inReplyTo[1] == "<m@example.com>" and #draft.references == 2)
        assert(draft.references[1] == "<old@example.com>" and draft.references[2] == "<m@example.com>")
        assert(calls[5].args.create.send.identityId == "i-sup")

        mark = #requests
        sent = fastmail.replyMessage("m2", {text="Again", from="me@example.com"})
        assert(sent.id == "d2")
        calls = jmapSince(mark)
        draft = calls[4].args.create.draft
        assert(draft.from[1].email == "me@example.com" and draft.subject == "Re: Hello")
        assert(draft.inReplyTo == nil and draft.references == nil)
        assert(calls[5].args.create.send.identityId == "i-me")

        mark = #requests
        fastmail.replyMessage("m", {text="All", all=true})
        calls = jmapSince(mark)
        draft = calls[4].args.create.draft
        assert(draft.to[1].email == "sender@example.com" and #draft.cc == 2)
        assert(draft.cc[1].email == "other@example.com" and draft.cc[2].email == "cc@example.com")

        mark = #requests
        local ok, err = pcall(function() fastmail.replyMessage("m", {text="Nope", from="missing@example.com"}) end)
        assert(not ok and string.find(tostring(err), "missing@example.com", 1, true) and string.find(tostring(err), "listAliases", 1, true))
        calls = jmapSince(mark)
        assert(#calls == 2 and calls[2].name == "Identity/get")

        mark = #requests
        local folder = fastmail.createFolder("Projects", "INBOX")
        assert(folder.id == "f1" and folder.name == "Projects")
        calls = jmapSince(mark)
        assert(calls[2].name == "Mailbox/set" and calls[2].args.create.folder.name == "Projects" and calls[2].args.create.folder.parentId == "in")

        mark = #requests
        local moved = fastmail.moveMessages({"a", "b"}, "archive")
        assert(moved.folderId == "ar" and moved.ids[1] == "a" and moved.ids[2] == "b")
        calls = jmapSince(mark)
        assert(calls[2].args.update.a.mailboxIds.ar and not calls[2].args.update.a.mailboxIds["in"])
        assert(calls[2].args.update.b.mailboxIds.ar)

        mark = #requests
        local archived = fastmail.archiveMessages("c")
        assert(archived.folderId == "ar" and archived.ids[1] == "c")
        calls = jmapSince(mark)
        assert(#calls == 3 and calls[3].args.update.c.mailboxIds.ar)

        mark = #requests
        local deleted = fastmail.deleteMessages({"a", "b"})
        assert(deleted.folderId == "tr")
        calls = jmapSince(mark)
        assert(calls[2].args.update.a.mailboxIds.tr and calls[2].args.destroy == nil)

        mark = #requests
        local destroyed = fastmail.destroyMessage("a")
        assert(destroyed.ids[1] == "a")
        calls = jmapSince(mark)
        assert(calls[1].name == "Email/set" and calls[1].args.destroy[1] == "a" and calls[1].args.update == nil)

        mark = #requests
        sent = fastmail.sendMessage({to={{email="to@example.com"}}, subject="Hi", text="Body", from="support@example.com",
            attachments={{path="files/brief.pdf", mimeType="application/pdf"}}})
        assert(sent.id == "d4" and sent.submissionId == "s4")
        calls = jmapSince(mark)
        assert(calls[1].name == "Identity/get" and calls[2].name == "Mailbox/get" and calls[3].upload)
        local upload = calls[3].upload
        assert(upload.method == "POST" and upload.url == "https://phl.api.fastmail.com/jmap/upload/u1/" and upload.src == "files/brief.pdf")
        assert(upload.body == nil and upload.headers["Content-Type"] == "application/pdf")
        draft = calls[4].args.create.draft
        assert(draft.from[1].email == "support@example.com" and draft.attachments[1].blobId == "blob1")
        assert(draft.attachments[1].name == "brief.pdf" and draft.attachments[1].disposition == "attachment")
        assert(draft.attachments[1].type == "application/pdf")
        assert(calls[5].args.create.send.identityId == "i-sup")
        assert(#responses == 0)

end}
