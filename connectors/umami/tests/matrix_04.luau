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
   "teamId": "123e4567-e89b-42d3-a456-426614174000",
   "userId": "123e4567-e89b-42d3-a456-426614174000"
  },
  "cloud": true,
  "group": "teams",
  "method": "DELETE",
  "name": "deleteTeamUser",
  "query": [],
  "read": false,
  "result": {
   "ok": true
  },
  "route": "/teams/123e4567-e89b-42d3-a456-426614174000/users/123e4567-e89b-42d3-a456-426614174000"
 },
 {
  "args": {
   "teamId": "123e4567-e89b-42d3-a456-426614174000",
   "userId": "123e4567-e89b-42d3-a456-426614174000"
  },
  "cloud": true,
  "group": "teams",
  "method": "GET",
  "name": "getTeamUser",
  "query": [],
  "read": true,
  "result": {
   "createdAt": "2026-01-01T00:00:00Z",
   "id": "xxxxxxxx",
   "role": "xxxxxxxx",
   "teamId": "xxxxxxxx",
   "updatedAt": "2026-01-01T00:00:00Z",
   "userId": "xxxxxxxx"
  },
  "route": "/teams/123e4567-e89b-42d3-a456-426614174000/users/123e4567-e89b-42d3-a456-426614174000"
 },
 {
  "args": {
   "body": {
    "role": "team-member"
   },
   "teamId": "123e4567-e89b-42d3-a456-426614174000",
   "userId": "123e4567-e89b-42d3-a456-426614174000"
  },
  "cloud": true,
  "group": "teams",
  "method": "POST",
  "name": "updateTeamUser",
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
  "route": "/teams/123e4567-e89b-42d3-a456-426614174000/users/123e4567-e89b-42d3-a456-426614174000"
 },
 {
  "args": {
   "teamId": "123e4567-e89b-42d3-a456-426614174000"
  },
  "cloud": true,
  "group": "teams",
  "method": "GET",
  "name": "getTeamWebsites",
  "query": [],
  "read": true,
  "result": {
   "count": 1,
   "data": [],
   "page": 1,
   "pageSize": 1
  },
  "route": "/teams/123e4567-e89b-42d3-a456-426614174000/websites"
 },
 {
  "args": {
   "body": {
    "password": "xxxxxxxx",
    "role": "admin",
    "username": "xxxxxxxx"
   }
  },
  "cloud": false,
  "group": "administration",
  "method": "POST",
  "name": "createUser",
  "query": [],
  "read": false,
  "result": {
   "id": "xxxxxxxx",
   "role": "xxxxxxxx",
   "username": "xxxxxxxx"
  },
  "route": "/users"
 },
 {
  "args": {
   "userId": "123e4567-e89b-42d3-a456-426614174000"
  },
  "cloud": false,
  "group": "administration",
  "method": "DELETE",
  "name": "deleteUser",
  "query": [],
  "read": false,
  "result": {
   "ok": true
  },
  "route": "/users/123e4567-e89b-42d3-a456-426614174000"
 },
 {
  "args": {
   "userId": "123e4567-e89b-42d3-a456-426614174000"
  },
  "cloud": false,
  "group": "administration",
  "method": "GET",
  "name": "getUser",
  "query": [],
  "read": true,
  "result": {
   "_count": {
    "apiKeys": 1,
    "boards": 1,
    "createdBy": 1,
    "links": 1,
    "pixels": 1,
    "reports": 1,
    "teams": 1,
    "twoFactorAuth": 1,
    "twoFactorBackupCodes": 1,
    "twoFactorOtpUseds": 1,
    "twoFactorRateLimit": 1,
    "websites": 1
   },
   "apiKeys": [],
   "boards": [],
   "createdAt": "2026-01-01T00:00:00Z",
   "createdBy": [],
   "id": "xxxxxxxx",
   "links": [],
   "password": "xxxxxxxx",
   "pixels": [],
   "reports": [],
   "role": "xxxxxxxx",
   "teams": [],
   "twoFactorAuth": {
    "createdAt": "2026-01-01T00:00:00Z",
    "id": "xxxxxxxx",
    "isEnabled": true,
    "secret": "xxxxxxxx",
    "updatedAt": "2026-01-01T00:00:00Z",
    "userId": "xxxxxxxx"
   },
   "twoFactorBackupCodes": [],
   "twoFactorOtpUseds": [],
   "twoFactorRateLimit": {
    "attempts": 1,
    "id": "xxxxxxxx",
    "lockedUntil": "2026-01-01T00:00:00Z",
    "updatedAt": "2026-01-01T00:00:00Z",
    "userId": "xxxxxxxx"
   },
   "twoFactorRequired": true,
   "username": "xxxxxxxx",
   "websites": []
  },
  "route": "/users/123e4567-e89b-42d3-a456-426614174000"
 },
 {
  "args": {
   "body": {},
   "userId": "123e4567-e89b-42d3-a456-426614174000"
  },
  "cloud": false,
  "group": "administration",
  "method": "POST",
  "name": "updateUser",
  "query": [],
  "read": false,
  "result": {
   "createdAt": "2026-01-01T00:00:00Z",
   "id": "xxxxxxxx",
   "role": "xxxxxxxx",
   "username": "xxxxxxxx"
  },
  "route": "/users/123e4567-e89b-42d3-a456-426614174000"
 },
 {
  "args": {
   "userId": "123e4567-e89b-42d3-a456-426614174000"
  },
  "cloud": false,
  "group": "administration",
  "method": "GET",
  "name": "getUserTeams",
  "query": [],
  "read": true,
  "result": {
   "count": 1,
   "data": [],
   "page": 1,
   "pageSize": 1
  },
  "route": "/users/123e4567-e89b-42d3-a456-426614174000/teams"
 },
 {
  "args": {
   "userId": "123e4567-e89b-42d3-a456-426614174000"
  },
  "cloud": false,
  "group": "administration",
  "method": "GET",
  "name": "getUserWebsites",
  "query": [],
  "read": true,
  "result": {
   "count": 1,
   "data": [],
   "page": 1,
   "pageSize": 1
  },
  "route": "/users/123e4567-e89b-42d3-a456-426614174000/websites"
 },
 {
  "args": {},
  "cloud": true,
  "group": "websites",
  "method": "GET",
  "name": "listWebsites",
  "query": [],
  "read": true,
  "result": {
   "count": 0,
   "data": [],
   "page": 1,
   "pageSize": 0
  },
  "route": "/websites"
 },
 {
  "args": {
   "body": {
    "domain": "xxxxxxxx",
    "name": "xxxxxxxx"
   }
  },
  "cloud": true,
  "group": "websites",
  "method": "POST",
  "name": "createWebsite",
  "query": [],
  "read": false,
  "result": {
   "createdAt": "2026-01-01T00:00:00Z",
   "createdBy": "123e4567-e89b-42d3-a456-426614174000",
   "deletedAt": "2026-01-01T00:00:00Z",
   "domain": "xxxxxxxx",
   "id": "123e4567-e89b-42d3-a456-426614174000",
   "name": "xxxxxxxx",
   "recorderEnabled": true,
   "replayConfig": {},
   "resetAt": "2026-01-01T00:00:00Z",
   "shareId": "xxxxxxxx",
   "teamId": "123e4567-e89b-42d3-a456-426614174000",
   "updatedAt": "2026-01-01T00:00:00Z",
   "userId": "123e4567-e89b-42d3-a456-426614174000"
  },
  "route": "/websites"
 },
 {
  "args": {
   "endAt": 1767312000000,
   "ids": "123e4567-e89b-42d3-a456-426614174000",
   "startAt": 1767225600000
  },
  "cloud": true,
  "group": "websites",
  "method": "GET",
  "name": "getWebsitesCharts",
  "query": [
   "endAt=1767312000000",
   "ids=123e4567-e89b-42d3-a456-426614174000",
   "startAt=1767225600000"
  ],
  "read": true,
  "result": {
   "data": {}
  },
  "route": "/websites/charts"
 },
 {
  "args": {
   "websiteId": "123e4567-e89b-42d3-a456-426614174000"
  },
  "cloud": true,
  "group": "websites",
  "method": "DELETE",
  "name": "deleteWebsite",
  "query": [],
  "read": false,
  "result": {
   "ok": true
  },
  "route": "/websites/123e4567-e89b-42d3-a456-426614174000"
 },
 {
  "args": {
   "websiteId": "123e4567-e89b-42d3-a456-426614174000"
  },
  "cloud": true,
  "group": "websites",
  "method": "GET",
  "name": "getWebsite",
  "query": [],
  "read": true,
  "result": {
   "createdAt": "2026-01-01T00:00:00Z",
   "createdBy": "123e4567-e89b-42d3-a456-426614174000",
   "deletedAt": "2026-01-01T00:00:00Z",
   "domain": "xxxxxxxx",
   "id": "123e4567-e89b-42d3-a456-426614174000",
   "name": "xxxxxxxx",
   "recorderEnabled": true,
   "replayConfig": {},
   "resetAt": "2026-01-01T00:00:00Z",
   "shareId": "xxxxxxxx",
   "teamId": "123e4567-e89b-42d3-a456-426614174000",
   "updatedAt": "2026-01-01T00:00:00Z",
   "userId": "123e4567-e89b-42d3-a456-426614174000"
  },
  "route": "/websites/123e4567-e89b-42d3-a456-426614174000"
 },
 {
  "args": {
   "body": {},
   "websiteId": "123e4567-e89b-42d3-a456-426614174000"
  },
  "cloud": true,
  "group": "websites",
  "method": "POST",
  "name": "updateWebsite",
  "query": [],
  "read": false,
  "result": {
   "createdAt": "2026-01-01T00:00:00Z",
   "createdBy": "123e4567-e89b-42d3-a456-426614174000",
   "deletedAt": "2026-01-01T00:00:00Z",
   "domain": "xxxxxxxx",
   "id": "123e4567-e89b-42d3-a456-426614174000",
   "name": "xxxxxxxx",
   "recorderEnabled": true,
   "replayConfig": {},
   "resetAt": "2026-01-01T00:00:00Z",
   "shareId": "xxxxxxxx",
   "teamId": "123e4567-e89b-42d3-a456-426614174000",
   "updatedAt": "2026-01-01T00:00:00Z",
   "userId": "123e4567-e89b-42d3-a456-426614174000"
  },
  "route": "/websites/123e4567-e89b-42d3-a456-426614174000"
 },
 {
  "args": {
   "websiteId": "123e4567-e89b-42d3-a456-426614174000"
  },
  "cloud": true,
  "group": "analytics",
  "method": "GET",
  "name": "getWebsiteActive",
  "query": [],
  "read": true,
  "result": {
   "visitors": 0
  },
  "route": "/websites/123e4567-e89b-42d3-a456-426614174000/active"
 },
 {
  "args": {
   "endAt": 1767312000000,
   "startAt": 1767225600000,
   "websiteId": "123e4567-e89b-42d3-a456-426614174000"
  },
  "cloud": true,
  "group": "reports",
  "method": "GET",
  "name": "getWebsiteAnnotations",
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
  "route": "/websites/123e4567-e89b-42d3-a456-426614174000/annotations"
 },
 {
  "args": {
   "body": {
    "date": "2026-01-01T00:00:00Z",
    "note": "xxxxxxxx"
   },
   "websiteId": "123e4567-e89b-42d3-a456-426614174000"
  },
  "cloud": true,
  "group": "reports",
  "method": "POST",
  "name": "createWebsiteAnnotation",
  "query": [],
  "read": false,
  "result": {
   "allDay": true,
   "createdAt": "2026-01-01T00:00:00Z",
   "date": "2026-01-01T00:00:00Z",
   "id": "xxxxxxxx",
   "note": "xxxxxxxx",
   "updatedAt": "2026-01-01T00:00:00Z",
   "userId": "xxxxxxxx",
   "websiteId": "xxxxxxxx"
  },
  "route": "/websites/123e4567-e89b-42d3-a456-426614174000/annotations"
 },
 {
  "args": {
   "annotationId": "123e4567-e89b-42d3-a456-426614174000",
   "websiteId": "123e4567-e89b-42d3-a456-426614174000"
  },
  "cloud": true,
  "group": "reports",
  "method": "DELETE",
  "name": "deleteWebsiteAnnotation",
  "query": [],
  "read": false,
  "result": {
   "ok": true
  },
  "route": "/websites/123e4567-e89b-42d3-a456-426614174000/annotations/123e4567-e89b-42d3-a456-426614174000"
 },
 {
  "args": {
   "annotationId": "123e4567-e89b-42d3-a456-426614174000",
   "websiteId": "123e4567-e89b-42d3-a456-426614174000"
  },
  "cloud": true,
  "group": "reports",
  "method": "GET",
  "name": "getWebsiteAnnotation",
  "query": [],
  "read": true,
  "result": {
   "allDay": true,
   "createdAt": "2026-01-01T00:00:00Z",
   "date": "2026-01-01T00:00:00Z",
   "id": "xxxxxxxx",
   "note": "xxxxxxxx",
   "updatedAt": "2026-01-01T00:00:00Z",
   "userId": "xxxxxxxx",
   "websiteId": "xxxxxxxx"
  },
  "route": "/websites/123e4567-e89b-42d3-a456-426614174000/annotations/123e4567-e89b-42d3-a456-426614174000"
 },
 {
  "args": {
   "annotationId": "123e4567-e89b-42d3-a456-426614174000",
   "body": {
    "date": "2026-01-01T00:00:00Z",
    "note": "xxxxxxxx"
   },
   "websiteId": "123e4567-e89b-42d3-a456-426614174000"
  },
  "cloud": true,
  "group": "reports",
  "method": "POST",
  "name": "updateWebsiteAnnotation",
  "query": [],
  "read": false,
  "result": {
   "allDay": true,
   "createdAt": "2026-01-01T00:00:00Z",
   "date": "2026-01-01T00:00:00Z",
   "id": "xxxxxxxx",
   "note": "xxxxxxxx",
   "updatedAt": "2026-01-01T00:00:00Z",
   "userId": "xxxxxxxx",
   "websiteId": "xxxxxxxx"
  },
  "route": "/websites/123e4567-e89b-42d3-a456-426614174000/annotations/123e4567-e89b-42d3-a456-426614174000"
 },
 {
  "args": {
   "endAt": 1767312000000,
   "model": "first-click",
   "startAt": 1767225600000,
   "step": "xxxxxxxx",
   "type": "path",
   "websiteId": "123e4567-e89b-42d3-a456-426614174000"
  },
  "cloud": true,
  "group": "analytics",
  "method": "GET",
  "name": "getWebsiteAttribution",
  "query": [
   "endAt=1767312000000",
   "model=first-click",
   "startAt=1767225600000",
   "step=xxxxxxxx",
   "type=path"
  ],
  "read": true,
  "result": {
   "paidAds": [],
   "referrer": [],
   "total": {
    "pageviews": 1,
    "visitors": 1,
    "visits": 1
   },
   "utm_campaign": [],
   "utm_content": [],
   "utm_medium": [],
   "utm_source": [],
   "utm_term": []
  },
  "route": "/websites/123e4567-e89b-42d3-a456-426614174000/attribution"
 },
 {
  "args": {
   "endAt": 1767312000000,
   "fields": "[\"browser\",\"country\"]",
   "startAt": 1767225600000,
   "websiteId": "123e4567-e89b-42d3-a456-426614174000"
  },
  "cloud": true,
  "group": "analytics",
  "method": "GET",
  "name": "getWebsiteBreakdown",
  "query": [
   "endAt=1767312000000",
   "fields=%5B%22browser%22%2C%22country%22%5D",
   "startAt=1767225600000"
  ],
  "read": true,
  "result": [],
  "route": "/websites/123e4567-e89b-42d3-a456-426614174000/breakdown"
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
