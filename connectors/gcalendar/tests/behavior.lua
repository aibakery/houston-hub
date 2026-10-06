return {scenario={["auth_config"]={},["auth_method"]="oauth",["config"]={},["publisher"]={["client_id"]="fixture-value",["client_secret"]="fixture-private-password !@#"}},config={access="read-write"},configure=function()
    requests, responses = {}, {}
    http={request=function(req)
        requests[#requests+1]=req
        assert(#responses>0,"unexpected request: "..req.url)
        local response=table.remove(responses,1)
        if response.status then return response end
        return {status=200,body=json.encode(response)}
    end}
end,run=function(c)
responses={{items={{id="event1"}},nextPageToken="next+1"},{id="new"}}
local page=c.listEvents({calendarId="primary",pageToken="start+1"})
assert(page.nextPageToken=="next+1")
assert(string.find(requests[1].url,"pageToken=start%2B1",1,true))
local event=c.insertEvent("primary",{summary="Meeting"})
assert(event.id=="new")
assert(requests[2].method=="POST")
responses={{status=403,body="denied"}}
assert(not pcall(c.listCalendars))
end}
