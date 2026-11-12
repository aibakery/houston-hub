return {
 scenario={config={access="read-only"},auth_method="token",auth_config={key="fixture-key"}},
 configure=function()
  requests={}
  responseValue={data={},count=0,page=1,pageSize=20}
  http={request=function(req)
   table.insert(requests,req)
   return fixture.operation({statusCode=200,headers={},body=fixture.reader(json.encode(responseValue))})
  end}
 end,
 run=function(c)
  responseValue={data=json.decode('[]'),count=0,page=1,pageSize=20}
  local empty=fixture.example("listWebsites")
  assert(empty.count==0 and json.encode(empty.data)=="[]")
  local req=requests[#requests]
  assert(string.find(req.url,"search=Store",1,true) and string.find(req.url,"includeTeams=true",1,true))
  responseValue={{x="/pricing",y=7}}
  assert(fixture.example("getWebsiteMetrics")[1].y==7)
  req=requests[#requests]
  assert(string.find(req.url,"country=US",1,true) and string.find(req.url,"browser=Chrome",1,true))
  responseValue=json.decode('[]')
  local args={websiteId="site",type="path",period="7d",filter={path="c./pricing?plan=pro",country1="neq.US,CA",epf0="1.eq.plan.pro",spf0="1.eq.tier.paid"}}
  local snapshot=json.encode(args)
  assert(json.encode(c.getWebsiteMetrics(args))=="[]")
  req=requests[#requests]
  assert(string.find(req.url,"path=c.%2Fpricing%3Fplan%3Dpro",1,true))
  assert(string.find(req.url,"country1=neq.US%2CCA",1,true))
  assert(string.find(req.url,"epf0=1.eq.plan.pro",1,true))
  assert(string.find(req.url,"spf0=1.eq.tier.paid",1,true))
  assert(json.encode(args)==snapshot)
  local before=#requests
  for _,bad in {
   {websiteId="../other",type="path"},
   {websiteId="site",type="path",filter={unknown="x"}},
   {websiteId="site",type="path",country="US",filter={country="CA"}},
   {websiteId="site",type="path",limit=0/0},
   {websiteId="site",type="path",body={}},
  } do assert(not pcall(c.getWebsiteMetrics,bad)) end
  assert(#requests==before,"invalid arguments reached transport")
  responseValue={data=json.decode('[]'),count=21,page=2,pageSize=20}
  local page=c.listWebsites({page=2,pageSize=20})
  assert(page.page==2 and page.count==21 and #requests==before+1,"hidden pagination")
  c.listWebsites({includeTeams=false,page=1})
  assert(requests[#requests].url=="https://api.umami.is/v1/websites?page=1","false must keep team websites excluded")
 end,
}
