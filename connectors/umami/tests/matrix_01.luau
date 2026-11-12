-- Independent route/body/response examples from Umami's official API contract.
return {
 scenario={config={deployment="self-hosted",host="analytics.example.com",access="read-write"},auth_method="token",auth_config={key="fixture-umami-key"}},
 configure=function()
  requests={}
  responseValue={}
  responseText=false
  http={request=function(req)
   table.insert(requests,req)
   return fixture.operation({statusCode=200,headers={},body=fixture.reader(if responseText then responseValue else json.encode(responseValue))})
  end}
 end,
 run=function(c)
  local cases=json.decode([==[[
 {
  "args": {
   "body": {
    "password": "xxxxxxxx",
    "token": "xxxxxx"
   }
  },
  "cloud": true,
  "group": "account",
  "method": "POST",
  "name": "disableTwoFactor",
  "query": [],
  "read": false,
  "result": {
   "ok": true
  },
  "route": "/2fa/disable"
 },
 {
  "args": {},
  "cloud": true,
  "group": "account",
  "method": "POST",
  "name": "cancelTwoFactorSetup",
  "query": [],
  "read": false,
  "result": {
   "ok": true
  },
  "route": "/2fa/setup/cancel"
 },
 {
  "args": {
   "body": {
    "token": "xxxxxx"
   }
  },
  "cloud": true,
  "group": "account",
  "method": "POST",
  "name": "confirmTwoFactorSetup",
  "query": [],
  "read": false,
  "result": {
   "backupCodes": []
  },
  "route": "/2fa/setup/confirm"
 },
 {
  "args": {},
  "cloud": true,
  "group": "account",
  "method": "POST",
  "name": "initiateTwoFactorSetup",
  "query": [],
  "read": false,
  "result": {
   "manualKey": "xxxxxxxx",
   "qrCodeDataUrl": "xxxxxxxx"
  },
  "route": "/2fa/setup/initiate"
 },
 {
  "args": {},
  "cloud": true,
  "group": "account",
  "method": "GET",
  "name": "getTwoFactorStatus",
  "query": [],
  "read": true,
  "result": {
   "globalRequired": true,
   "isConfigured": true,
   "isEnabled": true,
   "isRequired": true,
   "requiredReason": null
  },
  "route": "/2fa/status"
 },
 {
  "args": {
   "body": {
    "required": true
   }
  },
  "cloud": true,
  "group": "administration",
  "method": "POST",
  "name": "postAdmin2faGlobal",
  "query": [],
  "read": false,
  "result": {
   "ok": true,
   "required": "xxxxxxxx"
  },
  "route": "/admin/2fa/global"
 },
 {
  "args": {},
  "cloud": true,
  "group": "administration",
  "method": "GET",
  "name": "getAdminTeams",
  "query": [],
  "read": true,
  "result": {
   "count": 1,
   "data": [],
   "page": 1,
   "pageSize": 1
  },
  "route": "/admin/teams"
 },
 {
  "args": {
   "body": {
    "required": true
   },
   "teamId": "123e4567-e89b-42d3-a456-426614174000"
  },
  "cloud": true,
  "group": "administration",
  "method": "POST",
  "name": "postAdminTeamsTeamId2fa",
  "query": [],
  "read": false,
  "result": {
   "ok": true,
   "teamId": "xxxxxxxx",
   "twoFactorRequired": "xxxxxxxx"
  },
  "route": "/admin/teams/123e4567-e89b-42d3-a456-426614174000/2fa"
 },
 {
  "args": {},
  "cloud": true,
  "group": "administration",
  "method": "GET",
  "name": "getAdminUsers",
  "query": [],
  "read": true,
  "result": {
   "count": 1,
   "data": [],
   "page": 1,
   "pageSize": 1
  },
  "route": "/admin/users"
 },
 {
  "args": {
   "userId": "123e4567-e89b-42d3-a456-426614174000"
  },
  "cloud": true,
  "group": "administration",
  "method": "DELETE",
  "name": "deleteAdminUsersUserId2fa",
  "query": [],
  "read": false,
  "result": {
   "ok": true,
   "reset": {
    "backupCodes": "xxxxxxxx",
    "otpUsed": "xxxxxxxx",
    "rateLimit": "xxxxxxxx",
    "twoFactorAuth": "xxxxxxxx"
   },
   "userId": "xxxxxxxx"
  },
  "route": "/admin/users/123e4567-e89b-42d3-a456-426614174000/2fa"
 },
 {
  "args": {
   "userId": "123e4567-e89b-42d3-a456-426614174000"
  },
  "cloud": true,
  "group": "administration",
  "method": "GET",
  "name": "getAdminUsersUserId2fa",
  "query": [],
  "read": true,
  "result": {
   "isEnabled": true
  },
  "route": "/admin/users/123e4567-e89b-42d3-a456-426614174000/2fa"
 },
 {
  "args": {
   "body": {
    "required": true
   },
   "userId": "123e4567-e89b-42d3-a456-426614174000"
  },
  "cloud": true,
  "group": "administration",
  "method": "POST",
  "name": "postAdminUsersUserId2fa",
  "query": [],
  "read": false,
  "result": {
   "ok": true,
   "twoFactorRequired": "xxxxxxxx",
   "userId": "xxxxxxxx"
  },
  "route": "/admin/users/123e4567-e89b-42d3-a456-426614174000/2fa"
 },
 {
  "args": {},
  "cloud": true,
  "group": "administration",
  "method": "GET",
  "name": "getAdminWebsites",
  "query": [],
  "read": true,
  "result": {
   "count": 1,
   "data": [],
   "page": 1,
   "pageSize": 1
  },
  "route": "/admin/websites"
 },
 {
  "args": {},
  "cloud": true,
  "group": "account",
  "method": "POST",
  "name": "logout",
  "query": [],
  "read": false,
  "result": {
   "ok": true
  },
  "route": "/auth/logout"
 },
 {
  "args": {},
  "cloud": true,
  "group": "account",
  "method": "POST",
  "name": "sso",
  "query": [],
  "read": false,
  "result": {
   "token": "xxxxxxxx",
   "user": "xxxxxxxx"
  },
  "route": "/auth/sso"
 },
 {
  "args": {},
  "cloud": true,
  "group": "account",
  "method": "GET",
  "name": "getSubscription",
  "query": [],
  "read": true,
  "result": {
   "hasSubscription": true,
   "isBusiness": true,
   "isNoBilling": true,
   "isPro": true,
   "unlimitedWebsites": true
  },
  "route": "/auth/subscription"
 },
 {
  "args": {},
  "cloud": true,
  "group": "account",
  "method": "POST",
  "name": "verify",
  "query": [],
  "read": true,
  "result": {
   "teams": "xxxxxxxx"
  },
  "route": "/auth/verify"
 },
 {
  "args": {
   "body": []
  },
  "cloud": true,
  "group": "collection",
  "method": "POST",
  "name": "batch",
  "query": [],
  "read": false,
  "result": {
   "cache": "xxxxxxxx",
   "details": [],
   "errors": 1,
   "processed": 1,
   "size": "xxxxxxxx"
  },
  "route": "/batch"
 },
 {
  "args": {},
  "cloud": true,
  "group": "boards",
  "method": "GET",
  "name": "getBoards",
  "query": [],
  "read": true,
  "result": {
   "count": 1,
   "data": [],
   "page": 1,
   "pageSize": 1
  },
  "route": "/boards"
 },
 {
  "args": {
   "body": {
    "name": "xxxxxxxx",
    "type": "mixed"
   }
  },
  "cloud": true,
  "group": "boards",
  "method": "POST",
  "name": "createBoard",
  "query": [],
  "read": false,
  "result": {
   "createdAt": "2026-01-01T00:00:00Z",
   "description": "xxxxxxxx",
   "id": "xxxxxxxx",
   "name": "xxxxxxxx",
   "parameters": "xxxxxxxx",
   "teamId": "xxxxxxxx",
   "type": "xxxxxxxx",
   "updatedAt": "2026-01-01T00:00:00Z",
   "userId": "xxxxxxxx"
  },
  "route": "/boards"
 },
 {
  "args": {
   "boardId": "123e4567-e89b-42d3-a456-426614174000"
  },
  "cloud": true,
  "group": "boards",
  "method": "DELETE",
  "name": "deleteBoard",
  "query": [],
  "read": false,
  "result": {
   "ok": true
  },
  "route": "/boards/123e4567-e89b-42d3-a456-426614174000"
 },
 {
  "args": {
   "boardId": "123e4567-e89b-42d3-a456-426614174000"
  },
  "cloud": true,
  "group": "boards",
  "method": "GET",
  "name": "getBoard",
  "query": [],
  "read": true,
  "result": {
   "createdAt": "2026-01-01T00:00:00Z",
   "description": "xxxxxxxx",
   "id": "xxxxxxxx",
   "name": "xxxxxxxx",
   "parameters": "xxxxxxxx",
   "teamId": "xxxxxxxx",
   "type": "xxxxxxxx",
   "updatedAt": "2026-01-01T00:00:00Z",
   "userId": "xxxxxxxx"
  },
  "route": "/boards/123e4567-e89b-42d3-a456-426614174000"
 },
 {
  "args": {
   "boardId": "123e4567-e89b-42d3-a456-426614174000",
   "body": {}
  },
  "cloud": true,
  "group": "boards",
  "method": "POST",
  "name": "updateBoard",
  "query": [],
  "read": false,
  "result": {
   "createdAt": "2026-01-01T00:00:00Z",
   "description": "xxxxxxxx",
   "id": "xxxxxxxx",
   "name": "xxxxxxxx",
   "parameters": "xxxxxxxx",
   "teamId": "xxxxxxxx",
   "type": "xxxxxxxx",
   "updatedAt": "2026-01-01T00:00:00Z",
   "userId": "xxxxxxxx"
  },
  "route": "/boards/123e4567-e89b-42d3-a456-426614174000"
 },
 {
  "args": {
   "boardId": "123e4567-e89b-42d3-a456-426614174000",
   "body": {}
  },
  "cloud": true,
  "group": "boards",
  "method": "POST",
  "name": "cloneBoard",
  "query": [],
  "read": false,
  "result": {
   "createdAt": "2026-01-01T00:00:00Z",
   "description": "xxxxxxxx",
   "id": "xxxxxxxx",
   "name": "xxxxxxxx",
   "parameters": "xxxxxxxx",
   "teamId": "xxxxxxxx",
   "type": "xxxxxxxx",
   "updatedAt": "2026-01-01T00:00:00Z",
   "userId": "xxxxxxxx"
  },
  "route": "/boards/123e4567-e89b-42d3-a456-426614174000/clone"
 }
]]==])
  for _,case in cases do
   responseValue=case.result
   responseText=case.name=="getScriptsTelemetry"
   local before=json.encode(case.args)
   local result=c[case.name](case.args)
   assert(json.encode(result)==json.encode(case.result),"response: "..case.name)
   assert(json.encode(case.args)==before,"mutated input: "..case.name)
   local req=requests[#requests]
   assert(req.method==case.method,"method: "..case.name)
   local base="https://analytics.example.com/api"..case.route
   assert(req.url==base or string.sub(req.url,1,#base+1)==base.."?","route: "..case.name)
   for _,query in case.query do assert(string.find(req.url,query,1,true),"query: "..case.name) end
   if case.args.body~=nil then assert(req.body and json.encode(json.decode(req.body))==json.encode(case.args.body),"body: "..case.name)
   else assert(req.body==nil,"unexpected body: "..case.name) end
   assert(req.headers.Authorization==nil,"credentials must stay in native injection")
  end
 end,
}
