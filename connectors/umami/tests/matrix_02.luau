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
   "boardId": "123e4567-e89b-42d3-a456-426614174000"
  },
  "cloud": true,
  "group": "boards",
  "method": "GET",
  "name": "getBoardShares",
  "query": [],
  "read": true,
  "result": {
   "count": 1,
   "data": [],
   "page": 1,
   "pageSize": 1
  },
  "route": "/boards/123e4567-e89b-42d3-a456-426614174000/shares"
 },
 {
  "args": {
   "boardId": "123e4567-e89b-42d3-a456-426614174000",
   "body": {
    "name": "xxxxxxxx"
   }
  },
  "cloud": true,
  "group": "boards",
  "method": "POST",
  "name": "createBoardShare",
  "query": [],
  "read": false,
  "result": {
   "createdAt": "2026-01-01T00:00:00Z",
   "entityId": "xxxxxxxx",
   "id": "xxxxxxxx",
   "name": "xxxxxxxx",
   "parameters": "xxxxxxxx",
   "shareType": 1,
   "slug": "xxxxxxxx",
   "updatedAt": "2026-01-01T00:00:00Z"
  },
  "route": "/boards/123e4567-e89b-42d3-a456-426614174000/shares"
 },
 {
  "args": {},
  "cloud": true,
  "group": "boards",
  "method": "GET",
  "name": "getDashboard",
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
  "route": "/dashboard"
 },
 {
  "args": {
   "body": {}
  },
  "cloud": true,
  "group": "boards",
  "method": "POST",
  "name": "postDashboard",
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
  "route": "/dashboard"
 },
 {
  "args": {},
  "cloud": true,
  "group": "system",
  "method": "GET",
  "name": "getHeartbeat",
  "query": [],
  "read": true,
  "result": {
   "ok": true
  },
  "route": "/heartbeat"
 },
 {
  "args": {},
  "cloud": true,
  "group": "links",
  "method": "GET",
  "name": "getLinks",
  "query": [],
  "read": true,
  "result": {
   "count": 1,
   "data": [],
   "page": 1,
   "pageSize": 1
  },
  "route": "/links"
 },
 {
  "args": {
   "body": {
    "name": "xxxxxxxx",
    "slug": "xxxxxxxx",
    "url": "xxxxxxxx"
   }
  },
  "cloud": true,
  "group": "links",
  "method": "POST",
  "name": "createLink",
  "query": [],
  "read": false,
  "result": {
   "createdAt": "2026-01-01T00:00:00Z",
   "deletedAt": "2026-01-01T00:00:00Z",
   "id": "xxxxxxxx",
   "name": "xxxxxxxx",
   "slug": "xxxxxxxx",
   "teamId": "xxxxxxxx",
   "updatedAt": "2026-01-01T00:00:00Z",
   "url": "xxxxxxxx",
   "userId": "xxxxxxxx"
  },
  "route": "/links"
 },
 {
  "args": {
   "endAt": 1767312000000,
   "ids": "123e4567-e89b-42d3-a456-426614174000",
   "startAt": 1767225600000
  },
  "cloud": true,
  "group": "links",
  "method": "GET",
  "name": "getLinksCharts",
  "query": [
   "endAt=1767312000000",
   "ids=123e4567-e89b-42d3-a456-426614174000",
   "startAt=1767225600000"
  ],
  "read": true,
  "result": {
   "data": {}
  },
  "route": "/links/charts"
 },
 {
  "args": {
   "linkId": "123e4567-e89b-42d3-a456-426614174000"
  },
  "cloud": true,
  "group": "links",
  "method": "DELETE",
  "name": "deleteLink",
  "query": [],
  "read": false,
  "result": {
   "ok": true
  },
  "route": "/links/123e4567-e89b-42d3-a456-426614174000"
 },
 {
  "args": {
   "linkId": "123e4567-e89b-42d3-a456-426614174000"
  },
  "cloud": true,
  "group": "links",
  "method": "GET",
  "name": "getLink",
  "query": [],
  "read": true,
  "result": {
   "createdAt": "2026-01-01T00:00:00Z",
   "deletedAt": "2026-01-01T00:00:00Z",
   "id": "xxxxxxxx",
   "name": "xxxxxxxx",
   "slug": "xxxxxxxx",
   "teamId": "xxxxxxxx",
   "updatedAt": "2026-01-01T00:00:00Z",
   "url": "xxxxxxxx",
   "userId": "xxxxxxxx"
  },
  "route": "/links/123e4567-e89b-42d3-a456-426614174000"
 },
 {
  "args": {
   "body": {},
   "linkId": "123e4567-e89b-42d3-a456-426614174000"
  },
  "cloud": true,
  "group": "links",
  "method": "POST",
  "name": "updateLink",
  "query": [],
  "read": false,
  "result": {
   "createdAt": "2026-01-01T00:00:00Z",
   "deletedAt": "2026-01-01T00:00:00Z",
   "id": "xxxxxxxx",
   "name": "xxxxxxxx",
   "slug": "xxxxxxxx",
   "teamId": "xxxxxxxx",
   "updatedAt": "2026-01-01T00:00:00Z",
   "url": "xxxxxxxx",
   "userId": "xxxxxxxx"
  },
  "route": "/links/123e4567-e89b-42d3-a456-426614174000"
 },
 {
  "args": {
   "linkId": "123e4567-e89b-42d3-a456-426614174000"
  },
  "cloud": true,
  "group": "links",
  "method": "GET",
  "name": "getLinkShares",
  "query": [],
  "read": true,
  "result": {
   "count": 1,
   "data": [],
   "page": 1,
   "pageSize": 1
  },
  "route": "/links/123e4567-e89b-42d3-a456-426614174000/shares"
 },
 {
  "args": {
   "body": {
    "name": "xxxxxxxx"
   },
   "linkId": "123e4567-e89b-42d3-a456-426614174000"
  },
  "cloud": true,
  "group": "links",
  "method": "POST",
  "name": "createLinkShare",
  "query": [],
  "read": false,
  "result": {
   "createdAt": "2026-01-01T00:00:00Z",
   "entityId": "xxxxxxxx",
   "id": "xxxxxxxx",
   "name": "xxxxxxxx",
   "parameters": "xxxxxxxx",
   "shareType": 1,
   "slug": "xxxxxxxx",
   "updatedAt": "2026-01-01T00:00:00Z"
  },
  "route": "/links/123e4567-e89b-42d3-a456-426614174000/shares"
 },
 {
  "args": {},
  "cloud": true,
  "group": "account",
  "method": "GET",
  "name": "getMe",
  "query": [],
  "read": true,
  "result": {},
  "route": "/me"
 },
 {
  "args": {},
  "cloud": true,
  "group": "account",
  "method": "GET",
  "name": "getMyApiKeys",
  "query": [],
  "read": true,
  "result": [],
  "route": "/me/api-keys"
 },
 {
  "args": {
   "body": {
    "name": "xxxxxxxx"
   }
  },
  "cloud": true,
  "group": "account",
  "method": "POST",
  "name": "createMyApiKey",
  "query": [],
  "read": false,
  "result": {
   "createdAt": "2026-01-01T00:00:00Z",
   "id": "xxxxxxxx",
   "key": "xxxxxxxx",
   "keyPrefix": "xxxxxxxx",
   "name": "xxxxxxxx"
  },
  "route": "/me/api-keys"
 },
 {
  "args": {
   "keyId": "123e4567-e89b-42d3-a456-426614174000"
  },
  "cloud": true,
  "group": "account",
  "method": "DELETE",
  "name": "deleteMyApiKey",
  "query": [],
  "read": false,
  "result": {
   "ok": true
  },
  "route": "/me/api-keys/123e4567-e89b-42d3-a456-426614174000"
 },
 {
  "args": {
   "body": {
    "currentPassword": "xxxxxxxx",
    "newPassword": "xxxxxxxx"
   }
  },
  "cloud": false,
  "group": "account",
  "method": "POST",
  "name": "updateMyPassword",
  "query": [],
  "read": false,
  "result": {
   "createdAt": "2026-01-01T00:00:00Z",
   "id": "xxxxxxxx",
   "role": "xxxxxxxx",
   "username": "xxxxxxxx"
  },
  "route": "/me/password"
 },
 {
  "args": {},
  "cloud": true,
  "group": "account",
  "method": "GET",
  "name": "getMyTeams",
  "query": [],
  "read": true,
  "result": {
   "count": 1,
   "data": [],
   "page": 1,
   "pageSize": 1
  },
  "route": "/me/teams"
 },
 {
  "args": {},
  "cloud": true,
  "group": "account",
  "method": "GET",
  "name": "getMyWebsites",
  "query": [],
  "read": true,
  "result": {
   "count": 1,
   "data": [],
   "page": 1,
   "pageSize": 1
  },
  "route": "/me/websites"
 },
 {
  "args": {},
  "cloud": true,
  "group": "pixels",
  "method": "GET",
  "name": "getPixels",
  "query": [],
  "read": true,
  "result": {
   "count": 1,
   "data": [],
   "page": 1,
   "pageSize": 1
  },
  "route": "/pixels"
 },
 {
  "args": {
   "body": {
    "name": "xxxxxxxx",
    "slug": "xxxxxxxx"
   }
  },
  "cloud": true,
  "group": "pixels",
  "method": "POST",
  "name": "createPixel",
  "query": [],
  "read": false,
  "result": {
   "createdAt": "2026-01-01T00:00:00Z",
   "deletedAt": "2026-01-01T00:00:00Z",
   "id": "xxxxxxxx",
   "name": "xxxxxxxx",
   "slug": "xxxxxxxx",
   "teamId": "xxxxxxxx",
   "updatedAt": "2026-01-01T00:00:00Z",
   "userId": "xxxxxxxx"
  },
  "route": "/pixels"
 },
 {
  "args": {
   "endAt": 1767312000000,
   "ids": "123e4567-e89b-42d3-a456-426614174000",
   "startAt": 1767225600000
  },
  "cloud": true,
  "group": "pixels",
  "method": "GET",
  "name": "getPixelsCharts",
  "query": [
   "endAt=1767312000000",
   "ids=123e4567-e89b-42d3-a456-426614174000",
   "startAt=1767225600000"
  ],
  "read": true,
  "result": {
   "data": {}
  },
  "route": "/pixels/charts"
 },
 {
  "args": {
   "pixelId": "123e4567-e89b-42d3-a456-426614174000"
  },
  "cloud": true,
  "group": "pixels",
  "method": "DELETE",
  "name": "deletePixel",
  "query": [],
  "read": false,
  "result": {
   "ok": true
  },
  "route": "/pixels/123e4567-e89b-42d3-a456-426614174000"
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
