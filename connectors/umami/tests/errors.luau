return {
 scenario={config={access="read-write"},auth_method="token",auth_config={key="fixture-key"}},
 configure=function()
  calls=0
  status=429
  raw='{"error":{"code":"rate-limit","message":"Slow down"}}'
  http={request=function(_req)
   calls+=1
   return fixture.operation({statusCode=status,headers={["retry-after"]={"15"}},body=fixture.reader(raw)})
  end}
 end,
 run=function(c)
  local ok,err=pcall(c.profile.get)
  assert(not ok and string.find(tostring(err),"429",1,true) and string.find(tostring(err),"Retry-After: 15",1,true))
  assert(calls==1,"connector must not replay a rate-limited request")
  status=500
  ok,err=pcall(c.websites.create,{body={name="Demo",domain="example.com"}})
  assert(not ok and calls==2,"mutation was replayed")
  status=200
  for _,body in {"not JSON",'{"error":{"message":"failure"}}','{"ok":false}',"{}","null"} do
   raw=body
   assert(not pcall(c.websites.create,{body={name="Demo",domain="example.com"}}))
  end
  status=302
  raw="redirect"
  assert(not pcall(c.profile.get))
 end,
}
