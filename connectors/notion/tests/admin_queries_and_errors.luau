return {
 scenario={publisher={},config={},auth_method="admin",auth_config={token="fixture-admin-private-token"}},
 config={access="read-write"},
 configure=function()
  requests={}
  responseBody='{"object":"list","results":[],"has_more":false,"next_cursor":null}'
  http={request=function(req)
   table.insert(requests,req)
   return fixture.operation({statusCode=200,headers={},body=fixture.reader(responseBody)})
  end}
 end,
 run=function(c)
  c.adminListPersonalAccessTokens({space_id="space",status={"active","expired"},creator_ids={"user-1","user-2"},page_size=5})
  assert(requests[1].url=="https://api.notion.com/admin/v1/spaces/space/personal_access_tokens?page_size=5&status%5B%5D=active&status%5B%5D=expired&creator_ids%5B%5D=user-1&creator_ids%5B%5D=user-2")
  c.adminListMcpClientConnections({user_ids={"u"},workspace_ids={"w"},cursor="a+b"})
  assert(requests[2].url=="https://api.notion.com/admin/v1/mcp_client_connections?cursor=a%2Bb&user_ids%5B%5D=u&workspace_ids%5B%5D=w")
  c.adminUpdateAgentCreditLimit({space_id="space",agent_id="agent",credit_limit=json.decode('null')})
  assert(requests[3].method=="PUT" and json.encode(json.decode(requests[3].body).credit_limit)=="null")
  responseBody='{"type":"error","code":"validation_error","message":"invalid limit"}'
  assert(not pcall(c.adminListUsers,{space_id="space"}))
  assert(not pcall(c.adminListAnalyticsReports,{}))
  assert(#requests==4)
 end,
}
