-- Routing expectations come from official Notion OpenAPI, not connector descriptors.
return {
 scenario={publisher={},config={},auth_method="admin",auth_config={token="fixture-notion-private-token"}},
 config={access="read-write"},
 configure=function()
  requests={}
  fs=fixture.files()
  local file=fs.open("upload.bin","w"); file:write("notion"..string.char(0,255)); await(file:close())
  local multipart=http.multipart
  http={multipart=multipart,request=function(req)
   table.insert(requests,req)
   if type(req.body)=="userdata" then req.uploaded=await(req.body:readAll()) end
   return fixture.operation({statusCode=200,headers={},body=fixture.reader('{"object":"fixture","results":[],"next_cursor":null,"has_more":false,"future":{"retained":true}}')})
  end}
 end,
 run=function(c)
  local cases=json.decode([==[
[
    {"args":{"workspace_id":"query-workspace_id"},"json_body":false,"method":"GET","name":"adminListAnalyticsReports","url":"https://api.notion.com/admin/v1/analytics/reports?workspace_id=query-workspace_id"},
    {"args":{},"json_body":false,"method":"GET","name":"adminListLegalHolds","url":"https://api.notion.com/admin/v1/legal_holds"},
    {"args":{"future_field":{"nested":"preserve"}},"json_body":true,"method":"POST","name":"adminCreateLegalHold","url":"https://api.notion.com/admin/v1/legal_holds"},
    {"args":{"legal_hold_id":"id-legal_hold_id"},"json_body":false,"method":"GET","name":"adminGetLegalHold","url":"https://api.notion.com/admin/v1/legal_holds/id-legal_hold_id"},
    {"args":{"future_field":{"nested":"preserve"},"legal_hold_id":"id-legal_hold_id"},"json_body":true,"method":"PATCH","name":"adminUpdateLegalHold","url":"https://api.notion.com/admin/v1/legal_holds/id-legal_hold_id"},
    {"args":{"future_field":{"nested":"preserve"},"legal_hold_id":"id-legal_hold_id"},"json_body":true,"method":"POST","name":"adminExportLegalHold","url":"https://api.notion.com/admin/v1/legal_holds/id-legal_hold_id/export"},
    {"args":{"legal_hold_id":"id-legal_hold_id"},"json_body":false,"method":"POST","name":"adminReleaseLegalHold","url":"https://api.notion.com/admin/v1/legal_holds/id-legal_hold_id/release"},
    {"args":{"legal_hold_id":"id-legal_hold_id","space_id":"id-space_id"},"json_body":false,"method":"GET","name":"adminListLegalHoldPages","url":"https://api.notion.com/admin/v1/legal_holds/id-legal_hold_id/spaces/id-space_id/pages"},
    {"args":{"legal_hold_id":"id-legal_hold_id"},"json_body":false,"method":"GET","name":"adminListLegalHoldUsers","url":"https://api.notion.com/admin/v1/legal_holds/id-legal_hold_id/users"},
    {"args":{"future_field":{"nested":"preserve"},"legal_hold_id":"id-legal_hold_id"},"json_body":true,"method":"POST","name":"adminAddLegalHoldUsers","url":"https://api.notion.com/admin/v1/legal_holds/id-legal_hold_id/users"},
    {"args":{"legal_hold_id":"id-legal_hold_id","user_id":"id-user_id"},"json_body":false,"method":"DELETE","name":"adminRemoveLegalHoldUser","url":"https://api.notion.com/admin/v1/legal_holds/id-legal_hold_id/users/id-user_id"},
    {"args":{"legal_hold_id":"id-legal_hold_id"},"json_body":false,"method":"GET","name":"adminListLegalHoldWorkspaces","url":"https://api.notion.com/admin/v1/legal_holds/id-legal_hold_id/workspaces"},
    {"args":{"future_field":{"nested":"preserve"}},"json_body":true,"method":"POST","name":"adminRevokeUserSession","url":"https://api.notion.com/admin/v1/managed_users/revoke_session"},
    {"args":{},"json_body":false,"method":"GET","name":"adminListMcpClientConnections","url":"https://api.notion.com/admin/v1/mcp_client_connections"},
    {"args":{"future_field":{"nested":"preserve"}},"json_body":true,"method":"PUT","name":"adminUpdateMcpClientConnectionEnterpriseManagedAccess","url":"https://api.notion.com/admin/v1/mcp_client_connections/enterprise_managed_access"},
    {"args":{"future_field":{"nested":"preserve"}},"json_body":true,"method":"POST","name":"adminRevokeMcpClientConnection","url":"https://api.notion.com/admin/v1/mcp_client_connections/revoke"},
    {"args":{"space_id":"id-space_id"},"json_body":false,"method":"GET","name":"adminGetWorkflowsMetadataForSpace","url":"https://api.notion.com/admin/v1/spaces/id-space_id/agents"},
    {"args":{"future_field":{"nested":"preserve"},"space_id":"id-space_id"},"json_body":true,"method":"PATCH","name":"adminUpdateAgentCreationPolicy","url":"https://api.notion.com/admin/v1/spaces/id-space_id/agents/creation_policy"},
    {"args":{"space_id":"id-space_id"},"json_body":false,"method":"GET","name":"adminGetAgentsCreditUsage","url":"https://api.notion.com/admin/v1/spaces/id-space_id/agents/credit_usage"},
    {"args":{"agent_id":"id-agent_id","space_id":"id-space_id"},"json_body":false,"method":"DELETE","name":"adminDeleteAgent","url":"https://api.notion.com/admin/v1/spaces/id-space_id/agents/id-agent_id"},
    {"args":{"agent_id":"id-agent_id","future_field":{"nested":"preserve"},"space_id":"id-space_id"},"json_body":true,"method":"PUT","name":"adminUpdateAgentCreditLimit","url":"https://api.notion.com/admin/v1/spaces/id-space_id/agents/id-agent_id/credit_limit"},
    {"args":{"agent_id":"id-agent_id","space_id":"id-space_id"},"json_body":false,"method":"GET","name":"adminGetAgentCreditUsage","url":"https://api.notion.com/admin/v1/spaces/id-space_id/agents/id-agent_id/credit_usage"},
    {"args":{"agent_id":"id-agent_id","space_id":"id-space_id"},"json_body":false,"method":"GET","name":"adminGetAgentPermissions","url":"https://api.notion.com/admin/v1/spaces/id-space_id/agents/id-agent_id/permissions"},
    {"args":{"agent_id":"id-agent_id","future_field":{"nested":"preserve"},"space_id":"id-space_id"},"json_body":true,"method":"PATCH","name":"adminUpdateAgentPermissions","url":"https://api.notion.com/admin/v1/spaces/id-space_id/agents/id-agent_id/permissions"},
    {"args":{"agent_id":"id-agent_id","future_field":{"nested":"preserve"},"space_id":"id-space_id"},"json_body":true,"method":"PATCH","name":"adminUpdateAgentStatus","url":"https://api.notion.com/admin/v1/spaces/id-space_id/agents/id-agent_id/status"},
    {"args":{"future_field":{"nested":"preserve"},"space_id":"id-space_id"},"json_body":true,"method":"PATCH","name":"adminUpdateWorkspaceCreditLimit","url":"https://api.notion.com/admin/v1/spaces/id-space_id/credit_limit"},
    {"args":{"future_field":{"nested":"preserve"},"space_id":"id-space_id"},"json_body":true,"method":"POST","name":"adminEnqueueSpaceExport","url":"https://api.notion.com/admin/v1/spaces/id-space_id/exports"},
    {"args":{"export_job_id":"id-export_job_id","space_id":"id-space_id"},"json_body":false,"method":"GET","name":"adminGetSpaceExportStatus","url":"https://api.notion.com/admin/v1/spaces/id-space_id/exports/id-export_job_id"},
    {"args":{"space_id":"id-space_id"},"json_body":false,"method":"GET","name":"adminListPermissionGroups","url":"https://api.notion.com/admin/v1/spaces/id-space_id/groups"},
    {"args":{"future_field":{"nested":"preserve"},"space_id":"id-space_id"},"json_body":true,"method":"POST","name":"adminCreatePermissionGroup","url":"https://api.notion.com/admin/v1/spaces/id-space_id/groups"},
    {"args":{"group_id":"id-group_id","space_id":"id-space_id"},"json_body":false,"method":"GET","name":"adminRetrievePermissionGroup","url":"https://api.notion.com/admin/v1/spaces/id-space_id/groups/id-group_id"},
    {"args":{"future_field":{"nested":"preserve"},"group_id":"id-group_id","space_id":"id-space_id"},"json_body":true,"method":"PATCH","name":"adminUpdatePermissionGroup","url":"https://api.notion.com/admin/v1/spaces/id-space_id/groups/id-group_id"},
    {"args":{"group_id":"id-group_id","space_id":"id-space_id"},"json_body":false,"method":"DELETE","name":"adminDeletePermissionGroup","url":"https://api.notion.com/admin/v1/spaces/id-space_id/groups/id-group_id"},
    {"args":{"group_id":"id-group_id","space_id":"id-space_id"},"json_body":false,"method":"GET","name":"adminListPermissionGroupMembers","url":"https://api.notion.com/admin/v1/spaces/id-space_id/groups/id-group_id/members"},
    {"args":{"future_field":{"nested":"preserve"},"group_id":"id-group_id","space_id":"id-space_id"},"json_body":true,"method":"POST","name":"adminAddPermissionGroupMember","url":"https://api.notion.com/admin/v1/spaces/id-space_id/groups/id-group_id/members"},
    {"args":{"future_field":{"nested":"preserve"},"group_id":"id-group_id","space_id":"id-space_id","user_id":"id-user_id"},"json_body":true,"method":"PATCH","name":"adminUpdatePermissionGroupMember","url":"https://api.notion.com/admin/v1/spaces/id-space_id/groups/id-group_id/members/users/id-user_id"},
    {"args":{"group_id":"id-group_id","space_id":"id-space_id","user_id":"id-user_id"},"json_body":false,"method":"DELETE","name":"adminRemovePermissionGroupMember","url":"https://api.notion.com/admin/v1/spaces/id-space_id/groups/id-group_id/members/users/id-user_id"},
    {"args":{"space_id":"id-space_id"},"json_body":false,"method":"GET","name":"adminListPersonalAccessTokens","url":"https://api.notion.com/admin/v1/spaces/id-space_id/personal_access_tokens"},
    {"args":{"bot_id":"id-bot_id","space_id":"id-space_id"},"json_body":false,"method":"DELETE","name":"adminRevokePersonalAccessToken","url":"https://api.notion.com/admin/v1/spaces/id-space_id/personal_access_tokens/id-bot_id"},
    {"args":{"space_id":"id-space_id"},"json_body":false,"method":"GET","name":"adminListUsers","url":"https://api.notion.com/admin/v1/spaces/id-space_id/users"}
]
]==])
  for _,case in cases do
   assert(type(c[case.name])=="function","missing endpoint "..case.name)
   local input=case.args
   if case.name=="sendFileUpload" then input.path="upload.bin"; input.filename="source.bin"; input.content_type="application/octet-stream"; input.part_number=2 end
   local before=json.encode(input)
   local result=c[case.name](input)
   assert(json.encode(input)==before,"mutated caller options: "..case.name)
   local req=requests[#requests]
   assert(req.method==case.method,"wrong method: "..case.name)
   assert(req.url==case.url,"wrong route: "..case.name.." "..req.url)
   assert(req.headers["Notion-Version"][1]=="2026-06-01")
   assert(req.headers.Authorization==nil,"Lua must not possess auth credentials")
   assert(result.future.retained and json.encode(result.results)=="[]" and json.encode(result.next_cursor)=="null","response data lost")
   if case.json_body then
    local body=json.decode(req.body)
    assert(body.future_field.nested=="preserve","nested request fields lost")
    for field in input do if field~="future_field" then assert(body[field]==nil,"URL field leaked into body") end end
   elseif case.name=="sendFileUpload" then
    assert(string.find(req.headers["Content-Type"][1],"multipart/form-data; boundary=",1,true))
    assert(string.find(req.uploaded,'name="part_number"',1,true) and string.find(req.uploaded,'filename="source.bin"',1,true))
    assert(string.find(req.uploaded,"notion"..string.char(0,255),1,true),"binary upload changed")
   else assert(req.body==nil,"unexpected request body: "..case.name) end
  end
  assert(#requests==#cases,"hidden network request or retry")
  assert(#cases==40,"official API coverage unexpectedly changed")
 end,
}
