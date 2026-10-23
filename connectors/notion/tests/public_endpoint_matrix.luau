-- Routing expectations come from official Notion OpenAPI, not connector descriptors.
return {
 scenario={publisher={},config={},auth_method="token",auth_config={token="fixture-notion-private-token"}},
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
    {"args":{"future_field":{"nested":"preserve"}},"json_body":true,"method":"POST","name":"batchManageAgents","url":"https://api.notion.com/v1/agents/batch"},
    {"args":{"future_field":{"nested":"preserve"}},"json_body":true,"method":"POST","name":"queryAgents","url":"https://api.notion.com/v1/agents/query"},
    {"args":{"agent_id":"id-agent_id"},"json_body":false,"method":"GET","name":"getAgent","url":"https://api.notion.com/v1/agents/id-agent_id"},
    {"args":{"agent_id":"id-agent_id"},"json_body":false,"method":"DELETE","name":"deleteAgent","url":"https://api.notion.com/v1/agents/id-agent_id"},
    {"args":{"agent_id":"id-agent_id","future_field":{"nested":"preserve"}},"json_body":true,"method":"PATCH","name":"updateAgentCreditLimit","url":"https://api.notion.com/v1/agents/id-agent_id/credit_limit"},
    {"args":{"agent_id":"id-agent_id"},"json_body":false,"method":"GET","name":"getAgentInsights","url":"https://api.notion.com/v1/agents/id-agent_id/insights"},
    {"args":{"agent_id":"id-agent_id","future_field":{"nested":"preserve"}},"json_body":true,"method":"PATCH","name":"updateAgentStatus","url":"https://api.notion.com/v1/agents/id-agent_id/status"},
    {"args":{},"json_body":false,"method":"GET","name":"listPlugins","url":"https://api.notion.com/v1/ai/plugins"},
    {"args":{"id":"id-id"},"json_body":false,"method":"GET","name":"getPlugin","url":"https://api.notion.com/v1/ai/plugins/id-id"},
    {"args":{"id":"id-id"},"json_body":false,"method":"GET","name":"getSkill","url":"https://api.notion.com/v1/ai/skills/id-id"},
    {"args":{"task_id":"id-task_id"},"json_body":false,"method":"GET","name":"getAsyncTask","url":"https://api.notion.com/v1/async_tasks/id-task_id"},
    {"args":{"future_field":{"nested":"preserve"}},"json_body":true,"method":"POST","name":"createMeetingNote","url":"https://api.notion.com/v1/blocks/meeting_notes"},
    {"args":{"future_field":{"nested":"preserve"}},"json_body":true,"method":"POST","name":"queryMeetingNotes","url":"https://api.notion.com/v1/blocks/meeting_notes/query"},
    {"args":{"block_id":"id-block_id"},"json_body":false,"method":"GET","name":"getBlock","url":"https://api.notion.com/v1/blocks/id-block_id"},
    {"args":{"block_id":"id-block_id","future_field":{"nested":"preserve"}},"json_body":true,"method":"PATCH","name":"updateBlock","url":"https://api.notion.com/v1/blocks/id-block_id"},
    {"args":{"block_id":"id-block_id"},"json_body":false,"method":"DELETE","name":"deleteBlock","url":"https://api.notion.com/v1/blocks/id-block_id"},
    {"args":{"block_id":"id-block_id"},"json_body":false,"method":"GET","name":"listBlockChildren","url":"https://api.notion.com/v1/blocks/id-block_id/children"},
    {"args":{"block_id":"id-block_id","future_field":{"nested":"preserve"}},"json_body":true,"method":"PATCH","name":"appendBlockChildren","url":"https://api.notion.com/v1/blocks/id-block_id/children"},
    {"args":{"block_id":"query-block_id"},"json_body":false,"method":"GET","name":"listComments","url":"https://api.notion.com/v1/comments?block_id=query-block_id"},
    {"args":{"future_field":{"nested":"preserve"}},"json_body":true,"method":"POST","name":"createComment","url":"https://api.notion.com/v1/comments"},
    {"args":{"comment_id":"id-comment_id"},"json_body":false,"method":"GET","name":"getComment","url":"https://api.notion.com/v1/comments/id-comment_id"},
    {"args":{"comment_id":"id-comment_id","future_field":{"nested":"preserve"}},"json_body":true,"method":"PATCH","name":"updateComment","url":"https://api.notion.com/v1/comments/id-comment_id"},
    {"args":{"comment_id":"id-comment_id"},"json_body":false,"method":"DELETE","name":"deleteComment","url":"https://api.notion.com/v1/comments/id-comment_id"},
    {"args":{},"json_body":false,"method":"GET","name":"listCustomEmojis","url":"https://api.notion.com/v1/custom_emojis"},
    {"args":{"future_field":{"nested":"preserve"}},"json_body":true,"method":"POST","name":"createDataSource","url":"https://api.notion.com/v1/data_sources"},
    {"args":{"data_source_id":"id-data_source_id"},"json_body":false,"method":"GET","name":"getDataSource","url":"https://api.notion.com/v1/data_sources/id-data_source_id"},
    {"args":{"data_source_id":"id-data_source_id","future_field":{"nested":"preserve"}},"json_body":true,"method":"PATCH","name":"updateDataSource","url":"https://api.notion.com/v1/data_sources/id-data_source_id"},
    {"args":{"data_source_id":"id-data_source_id","future_field":{"nested":"preserve"}},"json_body":true,"method":"POST","name":"queryDataSource","url":"https://api.notion.com/v1/data_sources/id-data_source_id/query"},
    {"args":{"data_source_id":"id-data_source_id"},"json_body":false,"method":"GET","name":"listDataSourceTemplates","url":"https://api.notion.com/v1/data_sources/id-data_source_id/templates"},
    {"args":{"future_field":{"nested":"preserve"}},"json_body":true,"method":"POST","name":"createDatabase","url":"https://api.notion.com/v1/databases"},
    {"args":{"database_id":"id-database_id"},"json_body":false,"method":"GET","name":"getDatabase","url":"https://api.notion.com/v1/databases/id-database_id"},
    {"args":{"database_id":"id-database_id","future_field":{"nested":"preserve"}},"json_body":true,"method":"PATCH","name":"updateDatabase","url":"https://api.notion.com/v1/databases/id-database_id"},
    {"args":{},"json_body":false,"method":"GET","name":"listFileUploads","url":"https://api.notion.com/v1/file_uploads"},
    {"args":{"future_field":{"nested":"preserve"}},"json_body":true,"method":"POST","name":"createFileUpload","url":"https://api.notion.com/v1/file_uploads"},
    {"args":{"file_upload_id":"id-file_upload_id"},"json_body":false,"method":"GET","name":"getFileUpload","url":"https://api.notion.com/v1/file_uploads/id-file_upload_id"},
    {"args":{"file_upload_id":"id-file_upload_id"},"json_body":false,"method":"POST","name":"completeFileUpload","url":"https://api.notion.com/v1/file_uploads/id-file_upload_id/complete"},
    {"args":{"file_upload_id":"id-file_upload_id"},"json_body":false,"method":"POST","name":"sendFileUpload","url":"https://api.notion.com/v1/file_uploads/id-file_upload_id/send"},
    {"args":{"future_field":{"nested":"preserve"}},"json_body":true,"method":"POST","name":"createPage","url":"https://api.notion.com/v1/pages"},
    {"args":{"page_id":"id-page_id"},"json_body":false,"method":"GET","name":"getPage","url":"https://api.notion.com/v1/pages/id-page_id"},
    {"args":{"future_field":{"nested":"preserve"},"page_id":"id-page_id"},"json_body":true,"method":"PATCH","name":"updatePage","url":"https://api.notion.com/v1/pages/id-page_id"},
    {"args":{"page_id":"id-page_id"},"json_body":false,"method":"GET","name":"getPageMarkdown","url":"https://api.notion.com/v1/pages/id-page_id/markdown"},
    {"args":{"future_field":{"nested":"preserve"},"page_id":"id-page_id"},"json_body":true,"method":"PATCH","name":"updatePageMarkdown","url":"https://api.notion.com/v1/pages/id-page_id/markdown"},
    {"args":{"future_field":{"nested":"preserve"},"page_id":"id-page_id"},"json_body":true,"method":"POST","name":"movePage","url":"https://api.notion.com/v1/pages/id-page_id/move"},
    {"args":{"page_id":"id-page_id","property_id":"id-property_id"},"json_body":false,"method":"GET","name":"getPageProperty","url":"https://api.notion.com/v1/pages/id-page_id/properties/id-property_id"},
    {"args":{"future_field":{"nested":"preserve"}},"json_body":true,"method":"POST","name":"search","url":"https://api.notion.com/v1/search"},
    {"args":{"future_field":{"nested":"preserve"}},"json_body":true,"method":"POST","name":"updateSession","url":"https://api.notion.com/v1/sessions"},
    {"args":{"future_field":{"nested":"preserve"}},"json_body":true,"method":"POST","name":"querySessions","url":"https://api.notion.com/v1/sessions/query"},
    {"args":{"session_id":"id-session_id"},"json_body":false,"method":"GET","name":"getSession","url":"https://api.notion.com/v1/sessions/id-session_id"},
    {"args":{"future_field":{"nested":"preserve"},"session_id":"id-session_id"},"json_body":true,"method":"POST","name":"cancelSession","url":"https://api.notion.com/v1/sessions/id-session_id/cancel"},
    {"args":{"future_field":{"nested":"preserve"},"session_id":"id-session_id"},"json_body":true,"method":"POST","name":"querySessionEvents","url":"https://api.notion.com/v1/sessions/id-session_id/events/query"},
    {"args":{},"json_body":false,"method":"GET","name":"listUsers","url":"https://api.notion.com/v1/users"},
    {"args":{},"json_body":false,"method":"GET","name":"getSelf","url":"https://api.notion.com/v1/users/me"},
    {"args":{"user_id":"id-user_id"},"json_body":false,"method":"GET","name":"getUser","url":"https://api.notion.com/v1/users/id-user_id"},
    {"args":{},"json_body":false,"method":"GET","name":"listViews","url":"https://api.notion.com/v1/views"},
    {"args":{"future_field":{"nested":"preserve"}},"json_body":true,"method":"POST","name":"createView","url":"https://api.notion.com/v1/views"},
    {"args":{"view_id":"id-view_id"},"json_body":false,"method":"GET","name":"getView","url":"https://api.notion.com/v1/views/id-view_id"},
    {"args":{"future_field":{"nested":"preserve"},"view_id":"id-view_id"},"json_body":true,"method":"PATCH","name":"updateView","url":"https://api.notion.com/v1/views/id-view_id"},
    {"args":{"view_id":"id-view_id"},"json_body":false,"method":"DELETE","name":"deleteView","url":"https://api.notion.com/v1/views/id-view_id"},
    {"args":{"future_field":{"nested":"preserve"},"view_id":"id-view_id"},"json_body":true,"method":"POST","name":"createViewQuery","url":"https://api.notion.com/v1/views/id-view_id/queries"},
    {"args":{"query_id":"id-query_id","view_id":"id-view_id"},"json_body":false,"method":"GET","name":"getViewQueryResults","url":"https://api.notion.com/v1/views/id-view_id/queries/id-query_id"},
    {"args":{"query_id":"id-query_id","view_id":"id-view_id"},"json_body":false,"method":"DELETE","name":"deleteViewQuery","url":"https://api.notion.com/v1/views/id-view_id/queries/id-query_id"}
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
   assert(req.headers["Notion-Version"][1]=="2026-03-11")
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
  assert(#cases==61,"official API coverage unexpectedly changed")
 end,
}
