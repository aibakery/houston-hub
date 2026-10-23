return {
 scenario={publisher={},config={},auth_method="token",auth_config={token="fixture-notion-private-token"}},
 config={access="read-write"},
 configure=function()
  requests,responses={},{}
  fs=fixture.files()
  http={request=function(req)
   table.insert(requests,req)
   assert(#responses>0,"unexpected request")
   local response=table.remove(responses,1)
   return fixture.operation({statusCode=response.status or 200,headers=response.headers or {},body=fixture.reader(response.body or '{}')})
  end}
 end,
 run=function(c)
  local null=json.decode('null')
  responses={{body='{"object":"list","results":[],"has_more":true,"next_cursor":"x +/&?","request_status":{"type":"incomplete"}}'}, {body='{"object":"list","results":[{"id":"p"}],"has_more":false,"next_cursor":null}'}}
  local page=c.queryDataSource({data_source_id="ds",filter_properties={"title","abc:def"},filter={property="Status",status={equals="Done"}},sorts={{timestamp="last_edited_time",direction="descending"}},page_size=2})
  assert(page.has_more and #page.results==0 and page.request_status.type=="incomplete")
  assert(requests[1].url=="https://api.notion.com/v1/data_sources/ds/query?filter_properties%5B%5D=title&filter_properties%5B%5D=abc%3Adef")
  local body=json.decode(requests[1].body)
  assert(body.page_size==2 and body.filter.status.equals=="Done" and body.sorts[1].direction=="descending")
  local last=c.listBlockChildren({block_id="b",start_cursor=page.next_cursor,page_size=2})
  assert(requests[2].url=="https://api.notion.com/v1/blocks/b/children?start_cursor=x%20%2B%2F%26%3F&page_size=2")
  assert(not last.has_more and json.encode(last.next_cursor)=="null")
  responses={{body='{"object":"property_item","type":"number","number":4}'},{body='{"object":"page","id":"p"}'},{body='{"object":"list","results":[],"next_cursor":null,"has_more":false}'}}
  assert(c.getPageProperty({page_id="p",property_id="foo%3Abar"}).number==4)
  assert(requests[3].url=="https://api.notion.com/v1/pages/p/properties/foo%3Abar")
  c.updatePage({page_id="p",cover=null,properties={Relation={relation=json.decode('[]')}},in_trash=false})
  body=json.decode(requests[4].body)
  assert(json.encode(body.cover)=="null" and json.encode(body.properties.Relation.relation)=="[]" and body.in_trash==false)
  c.listUsers({start_cursor=null,page_size=null})
  assert(requests[5].url=="https://api.notion.com/v1/users","null optional queries must be omitted")
  local count=#requests
  for _,args in {{page_id=""},{page_id=".."},{page_id="p",unknown=true},{page_id="p",filter_properties={[2]="hole"}},{page_id="p",filter_properties={named="bad"}}} do assert(not pcall(c.getPage,args)) end
  for _,size in {0,-1,101,1.5,"10"} do assert(not pcall(c.listUsers,{page_size=size})) end
  assert(not pcall(c.getPage,"p"))
  assert(not pcall(c.getPage,{"p"}))
  assert(not pcall(c.listComments,{}))
  assert(not pcall(c.updateSession,{continue_from="event"}))
  assert(#requests==count,"invalid input reached provider")
  for _,bad in {"not JSON","[]","null","true",'{"object":"error","code":"validation_error","message":"bad"}','{"type":"error","code":"validation_error","message":"bad"}'} do
   responses={{body=bad}}
   assert(not pcall(c.getPage,{page_id="p"}),"accepted invalid response "..bad)
  end
  for _,status in {400,401,403,404,409,429,500,529} do
   responses={{status=status,headers={["retry-after"]={"7"}},body='{"object":"error","code":"rate_limited","message":"slow down","request_id":"req-123"}'}}
   local before=#requests
   local ok,err=pcall(c.getPage,{page_id="p"})
   assert(not ok,"accepted HTTP error")
   assert(#requests==before+1,"error triggered hidden retry")
   local message=tostring(err)
   assert(string.find(message,"rate_limited",1,true) and string.find(message,"req-123",1,true) and string.find(message,"Retry-After: 7",1,true),message)
  end
  responses={{status=204}}
  assert(c.deleteComment({comment_id="c"}).success)
  assert(#responses==0)
 end,
}
