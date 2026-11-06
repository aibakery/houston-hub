return {
 scenario={publisher={client_id="fixture-client",client_secret="fixture-private-secret"},auth_method="oauth",auth_config={}},
 config={access="read-write"},
 configure=function()
  requests={}
  fs=fixture.files()
  http={request=function(req)
   table.insert(requests,req)
   if req.headers and req.headers.Accept[1]=="text/event-stream" then
    return fixture.operation({statusCode=200,headers={["content-type"]={"text/event-stream; charset=utf-8"}},body=fixture.reader("event: message\ndata: {\"text\":\"hello\"}\n\n")})
   end
   if req.headers==nil then return fixture.operation({statusCode=200,headers={},body=fixture.reader(string.char(0,255).."attachment")}) end
   return fixture.operation({statusCode=200,headers={},body=fixture.reader('{"object":"page","id":"p"}')})
  end}
 end,
 run=function(c)
  assert(c.adminListUsers==nil)
  c.getPage({page_id="p"})
  c.search({query="Roadmap"})
  c.createPage({parent={page_id="p"},properties={title={title={{text={content="New"}}}}},markdown="# Hello"})
  c.updateBlock({block_id="b",paragraph={rich_text={{text={content="Updated"}}}}})
  c.deleteBlock({block_id="b"})
  local saved=c.streamSession({agent_id="a",message="Hello",path="stream.sse"})
  assert(saved.path=="stream.sse" and saved.size==#"event: message\ndata: {\"text\":\"hello\"}\n\n")
  assert(await(fs.open(saved.path,"r"):readAll())=="event: message\ndata: {\"text\":\"hello\"}\n\n")
  local replay=c.streamSession({session_id="s",continue_from="event-1",path="replay.sse"})
  assert(json.decode(requests[7].body).continue_from=="event-1")
  assert(json.decode(requests[7].body).path==nil)
  local downloaded=c.downloadFile({url="https://s3.us-west-2.amazonaws.com/secure.notion-static.com/file?signature=x",path="attachment.bin"})
  assert(downloaded.size==12 and await(fs.open(downloaded.path,"r"):readAll())==string.char(0,255).."attachment")
  assert(#requests==8 and requests[8].headers==nil)
  assert(not pcall(c.downloadFile,{url="http://example.com/file",path="bad"}))
  local example=fixture.example("streamSession")
  assert(example.path=="session.sse" and example.size>0)
  local body=json.decode(requests[#requests].body)
  assert(body.agent_id=="notion_ai" and body.message=="Summarize the project roadmap." and body.path==nil)
  example=fixture.example("streamSession",2)
  assert(example.path=="continued.sse" and example.size>0)
  body=json.decode(requests[#requests].body)
  assert(body.session_id=="b55c9c91-384d-452b-81db-d1ef79372b75" and body.continue_from==body.session_id and body.path==nil)
  example=fixture.example("downloadFile")
  assert(example.path=="guide.pdf" and example.size==12)
  assert(await(fs.open(example.path,"r"):readAll())==string.char(0,255).."attachment")
 end,
}
