return {
 scenario={publisher={},config={},auth_method="admin",auth_config={token="fixture-notion-private-token"}},
 config={access="read-only"},
 configure=function()
  calls=0
  http={request=function(req)
   calls+=1
   return fixture.operation({statusCode=200,headers={},body=fixture.reader('{"object":"list","results":[],"has_more":false,"next_cursor":null}')})
  end}
 end,
 run=function(c)
  for _,name in {"adminCreateLegalHold","adminUpdateLegalHold","adminDeleteAgent","adminRevokePersonalAccessToken","adminEnqueueSpaceExport","getPage","search","streamSession"} do assert(c[name]==nil,"read-only leaked "..name) end
  c.adminListUsers({space_id="s"}); c.adminGetAgentsCreditUsage({space_id="s"})
  assert(calls>0)
  for name,fn in c do assert(type(name)=="string" and type(fn)=="function") end
 end,
}
