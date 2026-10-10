return {
 scenario={config={client_id="fixture-client",client_secret="fixture-private-secret"},auth_method="oauth",auth_config={}},
 config={access="read-only"},
 configure=function()
  calls=0
  http={request=function(req)
   calls+=1
   return fixture.operation({statusCode=200,headers={},body=fixture.reader('{"object":"list","results":[],"has_more":false,"next_cursor":null}')})
  end}
 end,
 run=function(c)
  for _,name in {"createPage","updatePage","deleteBlock","sendFileUpload","streamSession","updateSession","batchManageAgents","createMeetingNote","adminListUsers"} do assert(c[name]==nil,"read-only leaked "..name) end
  c.getPage({page_id="p"}); c.search({query="Roadmap"}); c.createViewQuery({view_id="v"})
  assert(calls>0)
  for name,fn in c do assert(type(name)=="string" and type(fn)=="function") end
 end,
}
