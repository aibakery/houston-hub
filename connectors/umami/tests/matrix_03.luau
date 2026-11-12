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
   "pixelId": "123e4567-e89b-42d3-a456-426614174000"
  },
  "cloud": true,
  "group": "pixels",
  "method": "GET",
  "name": "getPixel",
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
   "userId": "xxxxxxxx"
  },
  "route": "/pixels/123e4567-e89b-42d3-a456-426614174000"
 },
 {
  "args": {
   "body": {},
   "pixelId": "123e4567-e89b-42d3-a456-426614174000"
  },
  "cloud": true,
  "group": "pixels",
  "method": "POST",
  "name": "updatePixel",
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
  "route": "/pixels/123e4567-e89b-42d3-a456-426614174000"
 },
 {
  "args": {
   "pixelId": "123e4567-e89b-42d3-a456-426614174000"
  },
  "cloud": true,
  "group": "pixels",
  "method": "GET",
  "name": "getPixelShares",
  "query": [],
  "read": true,
  "result": {
   "count": 1,
   "data": [],
   "page": 1,
   "pageSize": 1
  },
  "route": "/pixels/123e4567-e89b-42d3-a456-426614174000/shares"
 },
 {
  "args": {
   "body": {
    "name": "xxxxxxxx"
   },
   "pixelId": "123e4567-e89b-42d3-a456-426614174000"
  },
  "cloud": true,
  "group": "pixels",
  "method": "POST",
  "name": "createPixelShare",
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
  "route": "/pixels/123e4567-e89b-42d3-a456-426614174000/shares"
 },
 {
  "args": {
   "websiteId": "123e4567-e89b-42d3-a456-426614174000"
  },
  "cloud": true,
  "group": "analytics",
  "method": "GET",
  "name": "getRealtime",
  "query": [],
  "read": true,
  "result": {
   "countries": {},
   "events": [],
   "referrers": {},
   "series": {
    "views": [],
    "visitors": []
   },
   "timestamp": 1,
   "totals": {
    "countries": 1,
    "events": 1,
    "views": 1,
    "visitors": 1
   },
   "urls": {}
  },
  "route": "/realtime/123e4567-e89b-42d3-a456-426614174000"
 },
 {
  "args": {
   "body": {
    "payload": {
     "events": [],
     "website": "123e4567-e89b-42d3-a456-426614174000"
    },
    "type": "record"
   }
  },
  "cloud": true,
  "group": "collection",
  "method": "POST",
  "name": "record",
  "query": [],
  "read": false,
  "result": {
   "ok": true
  },
  "route": "/record"
 },
 {
  "args": {},
  "cloud": true,
  "group": "system",
  "method": "GET",
  "name": "getScriptsTelemetry",
  "query": [],
  "read": true,
  "result": "/* telemetry */",
  "route": "/scripts/telemetry"
 },
 {
  "args": {
   "body": {
    "payload": {
     "eventId": "123e4567-e89b-42d3-a456-426614174000",
     "message": "xxxxxxxx",
     "name": "xxxxxxxx",
     "timestamp": 1,
     "url": "xxxxxxxx",
     "version": 1,
     "website": "123e4567-e89b-42d3-a456-426614174000"
    },
    "type": "error"
   }
  },
  "cloud": true,
  "group": "collection",
  "method": "POST",
  "name": "send",
  "query": [],
  "read": false,
  "result": {
   "beep": "xxxxxxxx"
  },
  "route": "/send"
 },
 {
  "args": {
   "body": {
    "entityId": "123e4567-e89b-42d3-a456-426614174000",
    "name": "xxxxxxxx",
    "parameters": {},
    "shareType": 1
   }
  },
  "cloud": true,
  "group": "shares",
  "method": "POST",
  "name": "createShare",
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
  "route": "/share"
 },
 {
  "args": {
   "shareId": "123e4567-e89b-42d3-a456-426614174000"
  },
  "cloud": true,
  "group": "shares",
  "method": "DELETE",
  "name": "deleteShare",
  "query": [],
  "read": false,
  "result": {
   "ok": true
  },
  "route": "/share/id/123e4567-e89b-42d3-a456-426614174000"
 },
 {
  "args": {
   "shareId": "123e4567-e89b-42d3-a456-426614174000"
  },
  "cloud": true,
  "group": "shares",
  "method": "GET",
  "name": "getShare",
  "query": [],
  "read": true,
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
  "route": "/share/id/123e4567-e89b-42d3-a456-426614174000"
 },
 {
  "args": {
   "body": {
    "name": "xxxxxxxx",
    "parameters": {},
    "slug": "xxxxxxxx"
   },
   "shareId": "123e4567-e89b-42d3-a456-426614174000"
  },
  "cloud": true,
  "group": "shares",
  "method": "POST",
  "name": "updateShare",
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
  "route": "/share/id/123e4567-e89b-42d3-a456-426614174000"
 },
 {
  "args": {
   "slug": "xxxxxxxx"
  },
  "cloud": true,
  "group": "shares",
  "method": "GET",
  "name": "getShareBySlug",
  "query": [],
  "read": true,
  "result": {},
  "route": "/share/xxxxxxxx"
 },
 {
  "args": {},
  "cloud": true,
  "group": "teams",
  "method": "GET",
  "name": "getTeams",
  "query": [],
  "read": true,
  "result": {
   "count": 1,
   "data": [],
   "page": 1,
   "pageSize": 1
  },
  "route": "/teams"
 },
 {
  "args": {
   "body": {
    "name": "xxxxxxxx"
   }
  },
  "cloud": true,
  "group": "teams",
  "method": "POST",
  "name": "createTeam",
  "query": [],
  "read": false,
  "result": [
   "xxxxxxxx",
   "xxxxxxxx"
  ],
  "route": "/teams"
 },
 {
  "args": {
   "body": {
    "accessCode": "xxxxxxxx"
   }
  },
  "cloud": true,
  "group": "teams",
  "method": "POST",
  "name": "joinTeam",
  "query": [],
  "read": false,
  "result": {
   "createdAt": "2026-01-01T00:00:00Z",
   "id": "xxxxxxxx",
   "role": "xxxxxxxx",
   "teamId": "xxxxxxxx",
   "updatedAt": "2026-01-01T00:00:00Z",
   "userId": "xxxxxxxx"
  },
  "route": "/teams/join"
 },
 {
  "args": {
   "teamId": "123e4567-e89b-42d3-a456-426614174000"
  },
  "cloud": true,
  "group": "teams",
  "method": "DELETE",
  "name": "deleteTeam",
  "query": [],
  "read": false,
  "result": {
   "ok": true
  },
  "route": "/teams/123e4567-e89b-42d3-a456-426614174000"
 },
 {
  "args": {
   "teamId": "123e4567-e89b-42d3-a456-426614174000"
  },
  "cloud": true,
  "group": "teams",
  "method": "GET",
  "name": "getTeam",
  "query": [],
  "read": true,
  "result": {
   "accessCode": "xxxxxxxx",
   "createdAt": "2026-01-01T00:00:00Z",
   "deletedAt": "2026-01-01T00:00:00Z",
   "id": "xxxxxxxx",
   "logoUrl": "xxxxxxxx",
   "name": "xxxxxxxx",
   "twoFactorRequired": true,
   "updatedAt": "2026-01-01T00:00:00Z"
  },
  "route": "/teams/123e4567-e89b-42d3-a456-426614174000"
 },
 {
  "args": {
   "body": {},
   "teamId": "123e4567-e89b-42d3-a456-426614174000"
  },
  "cloud": true,
  "group": "teams",
  "method": "POST",
  "name": "updateTeam",
  "query": [],
  "read": false,
  "result": {
   "accessCode": "xxxxxxxx",
   "createdAt": "2026-01-01T00:00:00Z",
   "deletedAt": "2026-01-01T00:00:00Z",
   "id": "xxxxxxxx",
   "logoUrl": "xxxxxxxx",
   "name": "xxxxxxxx",
   "twoFactorRequired": true,
   "updatedAt": "2026-01-01T00:00:00Z"
  },
  "route": "/teams/123e4567-e89b-42d3-a456-426614174000"
 },
 {
  "args": {
   "teamId": "123e4567-e89b-42d3-a456-426614174000"
  },
  "cloud": true,
  "group": "teams",
  "method": "GET",
  "name": "getTeamBoards",
  "query": [],
  "read": true,
  "result": {
   "count": 1,
   "data": [],
   "page": 1,
   "pageSize": 1
  },
  "route": "/teams/123e4567-e89b-42d3-a456-426614174000/boards"
 },
 {
  "args": {
   "teamId": "123e4567-e89b-42d3-a456-426614174000"
  },
  "cloud": true,
  "group": "teams",
  "method": "GET",
  "name": "getTeamLinks",
  "query": [],
  "read": true,
  "result": {
   "count": 1,
   "data": [],
   "page": 1,
   "pageSize": 1
  },
  "route": "/teams/123e4567-e89b-42d3-a456-426614174000/links"
 },
 {
  "args": {
   "teamId": "123e4567-e89b-42d3-a456-426614174000"
  },
  "cloud": true,
  "group": "teams",
  "method": "GET",
  "name": "getTeamPixels",
  "query": [],
  "read": true,
  "result": {
   "count": 1,
   "data": [],
   "page": 1,
   "pageSize": 1
  },
  "route": "/teams/123e4567-e89b-42d3-a456-426614174000/pixels"
 },
 {
  "args": {
   "teamId": "123e4567-e89b-42d3-a456-426614174000"
  },
  "cloud": true,
  "group": "teams",
  "method": "GET",
  "name": "getTeamUsers",
  "query": [],
  "read": true,
  "result": {
   "count": 1,
   "data": [],
   "page": 1,
   "pageSize": 1
  },
  "route": "/teams/123e4567-e89b-42d3-a456-426614174000/users"
 },
 {
  "args": {
   "body": {
    "role": "team-member",
    "userId": "123e4567-e89b-42d3-a456-426614174000"
   },
   "teamId": "123e4567-e89b-42d3-a456-426614174000"
  },
  "cloud": true,
  "group": "teams",
  "method": "POST",
  "name": "createTeamUser",
  "query": [],
  "read": false,
  "result": {
   "createdAt": "2026-01-01T00:00:00Z",
   "id": "xxxxxxxx",
   "role": "xxxxxxxx",
   "teamId": "xxxxxxxx",
   "updatedAt": "2026-01-01T00:00:00Z",
   "userId": "xxxxxxxx"
  },
  "route": "/teams/123e4567-e89b-42d3-a456-426614174000/users"
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
