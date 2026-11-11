-- Read and draft connections prepare drafts but expose no send or other mail change.
return {scenario={["auth_config"]={["token"]="fixture-private-password !@#"},["auth_method"]="token",["config"]={},["publisher"]={}},config={access="custom"}, configure=function()

        requests, responses = {}, {}
        http = {request = function(req)
            requests[#requests + 1] = req
            assert(#responses > 0, "unexpected request: " .. tostring(req.url))
            return fixture.operation({statusCode=200, headers={}, body=fixture.reader(json.encode(table.remove(responses, 1)))})
        end}
        local MAIL="urn:ietf:params:jmap:mail"
        function result(name, args) return {methodResponses={{name, args, "0"}}} end
        session={username="me@example.com", primaryAccounts={[MAIL]="u1"}, accounts={u1={name="Me"}},
            capabilities={[MAIL]={}}, apiUrl="https://api.fastmail.com/jmap/api/"}
        folders={{id="dr", role="drafts", name="Drafts"}}

end, run=function(fastmail)
    for _, name in {"createDraft", "createReplyDraft", "updateDraft", "deleteDraft", "listMessages", "getMessage"} do
        assert(type(fastmail[name]) == "function", "Read and draft must export " .. name)
    end
    for _, name in {"sendDraft", "sendMessage", "replyMessage", "deleteMessage", "destroyMessage", "moveMessages", "archiveMessages", "createFolder", "markRead"} do
        assert(fastmail[name] == nil, "Read and draft must omit " .. name)
    end
    responses={session, result("Mailbox/get", {list=folders}), result("Email/set", {created={draft={id="d1"}}}),
        result("Email/get", {list={{id="d1", keywords={["$draft"]=true}}}}), result("Email/set", {destroyed={"d1"}})}
    assert(fastmail.createDraft({to={{email="to@example.com"}}, subject="Hi", text="Body"}).id == "d1")
    local draft = json.decode(requests[3].body).methodCalls[1][2].create.draft
    assert(draft.mailboxIds.dr and draft.keywords["$draft"] and draft.to[1].email == "to@example.com")
    assert(fastmail.deleteDraft("d1").id == "d1")
    assert(json.decode(requests[5].body).methodCalls[1][2].destroy[1] == "d1" and #responses == 0)
end}
