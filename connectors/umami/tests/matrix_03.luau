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
  "name": "pixels.get",
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
  "name": "pixels.update",
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
  "name": "pixels.shares.list",
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
  "name": "pixels.shares.create",
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
  "name": "websites.analytics.realtime",
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
  "name": "collection.record",
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
  "name": "system.telemetryScript",
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
  "name": "collection.send",
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
  "name": "shares.create",
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
  "name": "shares.delete",
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
  "name": "shares.get",
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
  "name": "shares.update",
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
  "name": "shares.bySlug",
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
  "name": "teams.list",
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
  "name": "teams.create",
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
  "name": "teams.join",
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
  "name": "teams.delete",
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
  "name": "teams.get",
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
  "name": "teams.update",
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
  "name": "teams.boards",
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
  "name": "teams.links",
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
  "name": "teams.pixels",
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
  "name": "teams.members.list",
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
  "name": "teams.members.create",
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
   responseText=case.name=="system.telemetryScript"
   local before=json.encode(case.args)
   local fn=c
   for part in string.gmatch(case.name,"[^.]+") do fn=fn[part] end
   local result=fn(case.args)
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
