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
   "endAt": 1767312000000,
   "propertyName": "xxxxxxxx",
   "startAt": 1767225600000,
   "websiteId": "123e4567-e89b-42d3-a456-426614174000"
  },
  "cloud": true,
  "group": "analytics",
  "method": "GET",
  "name": "getSessionDataStats",
  "query": [
   "endAt=1767312000000",
   "propertyName=xxxxxxxx",
   "startAt=1767225600000"
  ],
  "read": true,
  "result": [],
  "route": "/websites/123e4567-e89b-42d3-a456-426614174000/session-data/stats"
 },
 {
  "args": {
   "endAt": 1767312000000,
   "startAt": 1767225600000,
   "websiteId": "123e4567-e89b-42d3-a456-426614174000"
  },
  "cloud": true,
  "group": "analytics",
  "method": "GET",
  "name": "getSessionDataValues",
  "query": [
   "endAt=1767312000000",
   "startAt=1767225600000"
  ],
  "read": true,
  "result": [],
  "route": "/websites/123e4567-e89b-42d3-a456-426614174000/session-data/values"
 },
 {
  "args": {
   "endAt": 1767312000000,
   "startAt": 1767225600000,
   "websiteId": "123e4567-e89b-42d3-a456-426614174000"
  },
  "cloud": true,
  "group": "analytics",
  "method": "GET",
  "name": "getWebsiteSessions",
  "query": [
   "endAt=1767312000000",
   "startAt=1767225600000"
  ],
  "read": true,
  "result": {
   "count": 0,
   "data": [],
   "page": 1,
   "pageSize": 0
  },
  "route": "/websites/123e4567-e89b-42d3-a456-426614174000/sessions"
 },
 {
  "args": {
   "endAt": 1767312000000,
   "startAt": 1767225600000,
   "websiteId": "123e4567-e89b-42d3-a456-426614174000"
  },
  "cloud": true,
  "group": "analytics",
  "method": "GET",
  "name": "getWebsiteSessionStats",
  "query": [
   "endAt=1767312000000",
   "startAt=1767225600000"
  ],
  "read": true,
  "result": {},
  "route": "/websites/123e4567-e89b-42d3-a456-426614174000/sessions/stats"
 },
 {
  "args": {
   "endAt": 1767312000000,
   "startAt": 1767225600000,
   "timezone": "xxxxxxxx",
   "websiteId": "123e4567-e89b-42d3-a456-426614174000"
  },
  "cloud": true,
  "group": "analytics",
  "method": "GET",
  "name": "getWebsiteSessionsWeekly",
  "query": [
   "endAt=1767312000000",
   "startAt=1767225600000",
   "timezone=xxxxxxxx"
  ],
  "read": true,
  "result": [],
  "route": "/websites/123e4567-e89b-42d3-a456-426614174000/sessions/weekly"
 },
 {
  "args": {
   "sessionId": "123e4567-e89b-42d3-a456-426614174000",
   "websiteId": "123e4567-e89b-42d3-a456-426614174000"
  },
  "cloud": true,
  "group": "analytics",
  "method": "DELETE",
  "name": "deleteWebsiteSession",
  "query": [],
  "read": false,
  "result": {
   "ok": true
  },
  "route": "/websites/123e4567-e89b-42d3-a456-426614174000/sessions/123e4567-e89b-42d3-a456-426614174000"
 },
 {
  "args": {
   "sessionId": "123e4567-e89b-42d3-a456-426614174000",
   "websiteId": "123e4567-e89b-42d3-a456-426614174000"
  },
  "cloud": true,
  "group": "analytics",
  "method": "GET",
  "name": "getWebsiteSession",
  "query": [],
  "read": true,
  "result": {
   "browser": "xxxxxxxx",
   "canDelete": true,
   "city": "xxxxxxxx",
   "country": "xxxxxxxx",
   "device": "xxxxxxxx",
   "distinctIds": [],
   "events": 1,
   "firstAt": "2026-01-01T00:00:00Z",
   "id": "123e4567-e89b-42d3-a456-426614174000",
   "language": "xxxxxxxx",
   "lastAt": "2026-01-01T00:00:00Z",
   "os": "xxxxxxxx",
   "region": "xxxxxxxx",
   "screen": "xxxxxxxx",
   "stitchedSessionCount": 0,
   "totaltime": 1,
   "views": 1,
   "visits": 1,
   "websiteId": "123e4567-e89b-42d3-a456-426614174000"
  },
  "route": "/websites/123e4567-e89b-42d3-a456-426614174000/sessions/123e4567-e89b-42d3-a456-426614174000"
 },
 {
  "args": {
   "endAt": 1767312000000,
   "sessionId": "123e4567-e89b-42d3-a456-426614174000",
   "startAt": 1767225600000,
   "websiteId": "123e4567-e89b-42d3-a456-426614174000"
  },
  "cloud": true,
  "group": "analytics",
  "method": "GET",
  "name": "getWebsiteSessionActivity",
  "query": [
   "endAt=1767312000000",
   "startAt=1767225600000"
  ],
  "read": true,
  "result": [],
  "route": "/websites/123e4567-e89b-42d3-a456-426614174000/sessions/123e4567-e89b-42d3-a456-426614174000/activity"
 },
 {
  "args": {
   "sessionId": "123e4567-e89b-42d3-a456-426614174000",
   "websiteId": "123e4567-e89b-42d3-a456-426614174000"
  },
  "cloud": true,
  "group": "analytics",
  "method": "GET",
  "name": "getWebsiteSessionProperties",
  "query": [],
  "read": true,
  "result": [],
  "route": "/websites/123e4567-e89b-42d3-a456-426614174000/sessions/123e4567-e89b-42d3-a456-426614174000/properties"
 },
 {
  "args": {
   "endAt": 1767312000000,
   "sessionId": "123e4567-e89b-42d3-a456-426614174000",
   "startAt": 1767225600000,
   "websiteId": "123e4567-e89b-42d3-a456-426614174000"
  },
  "cloud": true,
  "group": "replays",
  "method": "GET",
  "name": "getWebsiteSessionReplays",
  "query": [
   "endAt=1767312000000",
   "startAt=1767225600000"
  ],
  "read": true,
  "result": {
   "count": 1,
   "data": [],
   "page": 1,
   "pageSize": 1
  },
  "route": "/websites/123e4567-e89b-42d3-a456-426614174000/sessions/123e4567-e89b-42d3-a456-426614174000/replays"
 },
 {
  "args": {
   "websiteId": "123e4567-e89b-42d3-a456-426614174000"
  },
  "cloud": true,
  "group": "shares",
  "method": "GET",
  "name": "getWebsiteShares",
  "query": [],
  "read": true,
  "result": {
   "count": 1,
   "data": [],
   "page": 1,
   "pageSize": 1
  },
  "route": "/websites/123e4567-e89b-42d3-a456-426614174000/shares"
 },
 {
  "args": {
   "body": {
    "name": "xxxxxxxx"
   },
   "websiteId": "123e4567-e89b-42d3-a456-426614174000"
  },
  "cloud": true,
  "group": "shares",
  "method": "POST",
  "name": "createWebsiteShare",
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
  "route": "/websites/123e4567-e89b-42d3-a456-426614174000/shares"
 },
 {
  "args": {
   "endAt": 1767312000000,
   "startAt": 1767225600000,
   "websiteId": "123e4567-e89b-42d3-a456-426614174000"
  },
  "cloud": true,
  "group": "analytics",
  "method": "GET",
  "name": "getWebsiteStats",
  "query": [
   "endAt=1767312000000",
   "startAt=1767225600000"
  ],
  "read": true,
  "result": {
   "bounces": 1,
   "comparison": {
    "bounces": 1,
    "pageviews": 1,
    "totaltime": 1,
    "visitors": 1,
    "visits": 1
   },
   "pageviews": 1,
   "totaltime": 1,
   "visitors": 1,
   "visits": 1
  },
  "route": "/websites/123e4567-e89b-42d3-a456-426614174000/stats"
 },
 {
  "args": {
   "body": {},
   "websiteId": "123e4567-e89b-42d3-a456-426614174000"
  },
  "cloud": true,
  "group": "websites",
  "method": "POST",
  "name": "transferWebsite",
  "query": [],
  "read": false,
  "result": {
   "createdAt": "2026-01-01T00:00:00Z",
   "createdBy": "xxxxxxxx",
   "deletedAt": "2026-01-01T00:00:00Z",
   "domain": "xxxxxxxx",
   "id": "xxxxxxxx",
   "name": "xxxxxxxx",
   "recorderEnabled": true,
   "replayConfig": "xxxxxxxx",
   "resetAt": "2026-01-01T00:00:00Z",
   "teamId": "xxxxxxxx",
   "updatedAt": "2026-01-01T00:00:00Z",
   "userId": "xxxxxxxx"
  },
  "route": "/websites/123e4567-e89b-42d3-a456-426614174000/transfer"
 },
 {
  "args": {
   "endAt": 1767312000000,
   "startAt": 1767225600000,
   "type": "utm_source",
   "websiteId": "123e4567-e89b-42d3-a456-426614174000"
  },
  "cloud": true,
  "group": "analytics",
  "method": "GET",
  "name": "getWebsiteUtmMetrics",
  "query": [
   "endAt=1767312000000",
   "startAt=1767225600000",
   "type=utm_source"
  ],
  "read": true,
  "result": [],
  "route": "/websites/123e4567-e89b-42d3-a456-426614174000/utm/metrics"
 },
 {
  "args": {
   "endAt": 1767312000000,
   "startAt": 1767225600000,
   "type": "path",
   "websiteId": "123e4567-e89b-42d3-a456-426614174000"
  },
  "cloud": true,
  "group": "analytics",
  "method": "GET",
  "name": "getWebsiteValues",
  "query": [
   "endAt=1767312000000",
   "startAt=1767225600000",
   "type=path"
  ],
  "read": true,
  "result": [],
  "route": "/websites/123e4567-e89b-42d3-a456-426614174000/values"
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
