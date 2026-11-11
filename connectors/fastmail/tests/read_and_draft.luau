-- Read and draft connections prepare drafts but expose no send or other mail change.
return {scenario={["auth_config"]={["token"]="fixture-private-password !@#"},["auth_method"]="token",["config"]={},["publisher"]={}},config={access="custom"}, run=function(fastmail)
    for _, name in {"createDraft", "createReplyDraft", "updateDraft", "deleteDraft", "listMessages", "getMessage"} do
        assert(type(fastmail[name]) == "function", "Read and draft must export " .. name)
    end
    for _, name in {"sendDraft", "sendMessage", "replyMessage", "deleteMessage", "destroyMessage", "moveMessages", "archiveMessages", "createFolder", "markRead"} do
        assert(fastmail[name] == nil, "Read and draft must omit " .. name)
    end
end}
