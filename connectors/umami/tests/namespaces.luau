return {
 scenario={config={deployment="self-hosted",host="analytics.example.com",access="read-write"},auth_method="token",auth_config={key="fixture-umami-key"}},
 run=function(c)
  assert(#c.namespaces==10,"root discovery must show the ten resource namespaces")
  local overview=c.help()
  assert(#overview<3000,"root help must remain a compact resource overview")
  assert(string.find(overview,"websites",1,true) and string.find(overview,"profile",1,true))
  local count=0
  local branches=0
  local function inspect(node)
   branches+=1
   local help=node.help()
   for _,name in node.functions do
    assert(type(node[name])=="function","discovered operation must be callable")
    assert(string.find(help,name,1,true),"local overview must document every operation")
    count+=1
   end
   for _,name in node.namespaces do
    assert(string.find(help,name,1,true),"local overview must document every child")
    inspect(node[name])
   end
  end
  inspect(c)
  assert(count==184 and branches==34,"full access must discover every operation and namespace")
  local details=c.websites.analytics.help("metrics")
  assert(string.find(details,"websiteId",1,true) and string.find(details,"country",1,true))
  assert(string.find(c.profile.twoFactor.help("status"),"two-factor",1,true))
  assert(string.find(c.administration.users.twoFactor.help("setPolicy"),"userId",1,true))
 end,
}
