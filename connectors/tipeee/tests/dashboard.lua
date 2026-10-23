local requests = {}
local payload = "{}"
return {
 scenario={config={access="read-write"},auth_method="token",auth_config={token="fixture-token"}},
 configure=function()
  requests={}; payload="{}"
  fs=fixture.files()
  local multipart=http.multipart
  http={multipart=multipart,request=function(req)
   if req.body then req.body=await(req.body:readAll()) end
   table.insert(requests,req)
   return fixture.operation({statusCode=200,headers={},body=fixture.reader(payload)})
  end}
 end,
 run=function(t)
  local function last() return requests[#requests] end
  local API="https://api.tipeee.com"
  payload='{"isUnique":false,"uniqueSlug":"my-art-2"}'
  assert(t.checkProjectSlug({slug="my-art"}).uniqueSlug=="my-art-2")
  assert(last().url==API.."/v2.0/project/unique?slug=my-art")
  payload='{"price":1,"modules":{"stock":{"available":{"unlimited":true}}}}'
  assert(t.getRewardTemplate({project="my-art"}).modules.stock.available.unlimited)
  assert(last().url==API.."/v2.0/projects/my-art/rewards_default")
  payload='{"items":[{"id":7}],"pager":{"next":2}}'
  assert(t.listTopTippers({project="my-art",page=1,perPage=10}).pager.next==2)
  assert(last().url==API.."/v2.0/projects/my-art/top/tippers?page=1&perPage=10")
  payload='[]'
  assert(json.encode(t.listNewsDrafts({project="my-art"}))=="[]")
  assert(last().url==API.."/v2.0/projects/my-art/news/drafts")
  payload='{"items":[],"pager":{"next":"older"},"add_data":{"unread":2}}'
  assert(t.listProjectFeed({user="creator",project="my-art",read="false",type="ALL",perPage=15,token="a+b",direction="next"}).add_data.unread==2)
  assert(last().url==API.."/v2.0/feed/users/creator/projects/my-art?read=false&type=ALL&perPage=15&token=a%2Bb&direction=next")
  t.markProjectFeedRead({user="creator",project="my-art"})
  assert(last().method=="PUT" and last().url==API.."/v2.0/feed/users/creator/projects/my-art/read" and last().body==nil)
  t.markNotificationRead({user="creator",notification=7})
  assert(last().method=="PUT" and last().url==API.."/v2.0/feed/users/creator/notifications/7/read")
  t.getMessageSupporter({project="my-art",user=7})
  assert(last().url==API.."/v2.0/inbox/projects/my-art/subscription/7")
  t.listSupportMessages({project="my-art",page=1,perPage=10})
  assert(last().url==API.."/v2.0/projects/my-art/admin/messages?page=1&perPage=10")
  local f=fs.open("note.txt","w"); f:write("Details"); await(f:close())
  payload='{"id":8}'
  assert(t.sendSupportMessage({project="my-art",data={content="A question"},files={["attachementsFile[0][uploadedFile]"]={path="note.txt",filename="note.txt",contentType="text/plain"}}}).id==8)
  assert(last().method=="POST" and last().url==API.."/v2.0/projects/my-art/admins/messages")
  assert(string.find(last().body,'name="content"\r\n\r\nA question',1,true))
  assert(string.find(last().body,'name="attachementsFile[0][uploadedFile]"; filename="note.txt"',1,true))
  assert(string.find(last().body,"Details",1,true))
  local before=#requests
  assert(not pcall(function() t.sendSupportMessage({project="p",data={content=string.rep("a",3001)}}) end))
  assert(not pcall(function() t.checkProjectSlug() end))
  assert(#requests==before)
 end,
}
