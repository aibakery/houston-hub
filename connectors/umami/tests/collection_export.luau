return {
 scenario={config={deployment="self-hosted",host="analytics.example.com",access="read-write"},auth_method="token",auth_config={key="fixture-key"}},
 configure=function()
  fs=fixture.files()
  requests={}
  responseValue={}
  http={request=function(req)
   table.insert(requests,req)
   return fixture.operation({statusCode=200,headers={},body=fixture.reader(json.encode(responseValue))})
  end}
 end,
 run=function(c)
  local site="123e4567-e89b-42d3-a456-426614174000"
  responseValue={cache="session-cache",sessionId="session",visitId="visit"}
  local sent=c.collection.send({body={type="event",payload={website=site,url="https://example.com/pricing",name="Signup"}}})
  assert(sent.cache=="session-cache")
  responseValue={ok=true}
  assert(c.collection.record({cache=sent.cache,body={type="record",payload={website=site,events={{type=2,timestamp=1}}}}}).ok)
  assert(requests[#requests].headers["x-umami-cache"][1]=="session-cache")
  local before=#requests
  assert(not pcall(c.collection.record,{body={type="record",payload={website=site,events={{type=2}}}}}))
  assert(#requests==before)
  responseValue={size=2,processed=1,errors=1,details={{index=1,error="invalid website"}},cache="session-cache"}
  local batch=c.collection.batch({body={{type="event",payload={website=site,url="/"}},{type="event",payload={website="invalid",url="/"}}}})
  assert(batch.processed==1 and batch.errors==1 and batch.details[1].index==1)
  assert(#requests==before+1,"partially accepted collection was replayed")
  responseValue={sessionId="session",events=json.decode('[]'),startedAt=json.decode('null'),endedAt=json.decode('null'),eventCount=0,chunkCount=0}
  local replay=c.websites.replays.get({websiteId=site,replayId="replay",["until"]=100,chunkIndex=2,eventIndex=4})
  assert(replay.eventCount==0)
  assert(string.find(requests[#requests].url,"until=100",1,true) and string.find(requests[#requests].url,"chunkIndex=2",1,true))
  responseValue={zip=base64.encode("PK"..string.char(0,1,255))}
  local exported=c.websites.export({websiteId=site,destination="analytics.zip",startAt=1767225600000,endAt=1767312000000})
  assert(exported.path=="analytics.zip" and exported.size==5 and type(exported.url)=="string")
  local file=fs.open("analytics.zip","r")
  assert(await(file:read(10)).data=="PK"..string.char(0,1,255)); await(file:close())
 end,
}
