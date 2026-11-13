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
   "websiteId": "123e4567-e89b-42d3-a456-426614174000"
  },
  "cloud": true,
  "group": "replays",
  "method": "GET",
  "name": "websites.replays.recorderConfig",
  "query": [],
  "read": true,
  "result": {
   "enabled": true
  },
  "route": "/websites/123e4567-e89b-42d3-a456-426614174000/recorder"
 },
 {
  "args": {
   "endAt": 1767312000000,
   "startAt": 1767225600000,
   "websiteId": "123e4567-e89b-42d3-a456-426614174000"
  },
  "cloud": true,
  "group": "replays",
  "method": "GET",
  "name": "websites.replays.list",
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
  "route": "/websites/123e4567-e89b-42d3-a456-426614174000/replays"
 },
 {
  "args": {
   "websiteId": "123e4567-e89b-42d3-a456-426614174000"
  },
  "cloud": true,
  "group": "replays",
  "method": "GET",
  "name": "websites.replays.saved",
  "query": [],
  "read": true,
  "result": {
   "count": 1,
   "data": [],
   "page": 1,
   "pageSize": 1
  },
  "route": "/websites/123e4567-e89b-42d3-a456-426614174000/replays/saved"
 },
 {
  "args": {
   "replayId": "123e4567-e89b-42d3-a456-426614174000",
   "websiteId": "123e4567-e89b-42d3-a456-426614174000"
  },
  "cloud": true,
  "group": "replays",
  "method": "GET",
  "name": "websites.replays.isSaved",
  "query": [],
  "read": true,
  "result": {
   "isSaved": true
  },
  "route": "/websites/123e4567-e89b-42d3-a456-426614174000/replays/saved/123e4567-e89b-42d3-a456-426614174000"
 },
 {
  "args": {
   "body": {
    "isSaved": true
   },
   "replayId": "123e4567-e89b-42d3-a456-426614174000",
   "websiteId": "123e4567-e89b-42d3-a456-426614174000"
  },
  "cloud": true,
  "group": "replays",
  "method": "POST",
  "name": "websites.replays.save",
  "query": [],
  "read": false,
  "result": {
   "ok": true
  },
  "route": "/websites/123e4567-e89b-42d3-a456-426614174000/replays/saved/123e4567-e89b-42d3-a456-426614174000"
 },
 {
  "args": {
   "replayId": "123e4567-e89b-42d3-a456-426614174000",
   "websiteId": "123e4567-e89b-42d3-a456-426614174000"
  },
  "cloud": true,
  "group": "replays",
  "method": "GET",
  "name": "websites.replays.get",
  "query": [],
  "read": true,
  "result": {
   "chunkCount": 1,
   "endedAt": "2026-01-01T00:00:00Z",
   "eventCount": 1,
   "events": [],
   "sessionId": "xxxxxxxx",
   "startedAt": "2026-01-01T00:00:00Z"
  },
  "route": "/websites/123e4567-e89b-42d3-a456-426614174000/replays/123e4567-e89b-42d3-a456-426614174000"
 },
 {
  "args": {
   "websiteId": "123e4567-e89b-42d3-a456-426614174000"
  },
  "cloud": true,
  "group": "websites",
  "method": "POST",
  "name": "websites.reset",
  "query": [],
  "read": false,
  "result": {
   "ok": true
  },
  "route": "/websites/123e4567-e89b-42d3-a456-426614174000/reset"
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
  "name": "websites.analytics.retention",
  "query": [
   "endAt=1767312000000",
   "startAt=1767225600000"
  ],
  "read": true,
  "result": [],
  "route": "/websites/123e4567-e89b-42d3-a456-426614174000/retention"
 },
 {
  "args": {
   "currency": "xxxxxxxx",
   "endAt": 1767312000000,
   "startAt": 1767225600000,
   "websiteId": "123e4567-e89b-42d3-a456-426614174000"
  },
  "cloud": true,
  "group": "analytics",
  "method": "GET",
  "name": "websites.revenue.chart",
  "query": [
   "currency=xxxxxxxx",
   "endAt=1767312000000",
   "startAt=1767225600000"
  ],
  "read": true,
  "result": {
   "chart": []
  },
  "route": "/websites/123e4567-e89b-42d3-a456-426614174000/revenue/chart"
 },
 {
  "args": {
   "currency": "xxxxxxxx",
   "endAt": 1767312000000,
   "startAt": 1767225600000,
   "type": "country",
   "websiteId": "123e4567-e89b-42d3-a456-426614174000"
  },
  "cloud": true,
  "group": "analytics",
  "method": "GET",
  "name": "websites.revenue.metrics",
  "query": [
   "currency=xxxxxxxx",
   "endAt=1767312000000",
   "startAt=1767225600000",
   "type=country"
  ],
  "read": true,
  "result": [],
  "route": "/websites/123e4567-e89b-42d3-a456-426614174000/revenue/metrics"
 },
 {
  "args": {
   "currency": "xxxxxxxx",
   "endAt": 1767312000000,
   "startAt": 1767225600000,
   "websiteId": "123e4567-e89b-42d3-a456-426614174000"
  },
  "cloud": true,
  "group": "analytics",
  "method": "GET",
  "name": "websites.revenue.sessions",
  "query": [
   "currency=xxxxxxxx",
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
  "route": "/websites/123e4567-e89b-42d3-a456-426614174000/revenue/sessions"
 },
 {
  "args": {
   "currency": "xxxxxxxx",
   "endAt": 1767312000000,
   "startAt": 1767225600000,
   "websiteId": "123e4567-e89b-42d3-a456-426614174000"
  },
  "cloud": true,
  "group": "analytics",
  "method": "GET",
  "name": "websites.revenue.stats",
  "query": [
   "currency=xxxxxxxx",
   "endAt=1767312000000",
   "startAt=1767225600000"
  ],
  "read": true,
  "result": {
   "comparison": "xxxxxxxx"
  },
  "route": "/websites/123e4567-e89b-42d3-a456-426614174000/revenue/stats"
 },
 {
  "args": {
   "type": "segment",
   "websiteId": "123e4567-e89b-42d3-a456-426614174000"
  },
  "cloud": true,
  "group": "reports",
  "method": "GET",
  "name": "websites.segments.list",
  "query": [],
  "read": true,
  "result": {
   "count": 1,
   "data": [],
   "page": 1,
   "pageSize": 1
  },
  "route": "/websites/123e4567-e89b-42d3-a456-426614174000/segments"
 },
 {
  "args": {
   "body": {
    "name": "xxxxxxxx",
    "parameters": {},
    "type": "segment"
   },
   "websiteId": "123e4567-e89b-42d3-a456-426614174000"
  },
  "cloud": true,
  "group": "reports",
  "method": "POST",
  "name": "websites.segments.create",
  "query": [],
  "read": false,
  "result": {
   "createdAt": "2026-01-01T00:00:00Z",
   "id": "xxxxxxxx",
   "name": "xxxxxxxx",
   "parameters": "xxxxxxxx",
   "type": "xxxxxxxx",
   "updatedAt": "2026-01-01T00:00:00Z",
   "websiteId": "xxxxxxxx"
  },
  "route": "/websites/123e4567-e89b-42d3-a456-426614174000/segments"
 },
 {
  "args": {
   "segmentId": "123e4567-e89b-42d3-a456-426614174000",
   "websiteId": "123e4567-e89b-42d3-a456-426614174000"
  },
  "cloud": true,
  "group": "reports",
  "method": "DELETE",
  "name": "websites.segments.delete",
  "query": [],
  "read": false,
  "result": {
   "ok": true
  },
  "route": "/websites/123e4567-e89b-42d3-a456-426614174000/segments/123e4567-e89b-42d3-a456-426614174000"
 },
 {
  "args": {
   "segmentId": "123e4567-e89b-42d3-a456-426614174000",
   "websiteId": "123e4567-e89b-42d3-a456-426614174000"
  },
  "cloud": true,
  "group": "reports",
  "method": "GET",
  "name": "websites.segments.get",
  "query": [],
  "read": true,
  "result": {
   "createdAt": "2026-01-01T00:00:00Z",
   "id": "xxxxxxxx",
   "name": "xxxxxxxx",
   "parameters": "xxxxxxxx",
   "type": "xxxxxxxx",
   "updatedAt": "2026-01-01T00:00:00Z",
   "websiteId": "xxxxxxxx"
  },
  "route": "/websites/123e4567-e89b-42d3-a456-426614174000/segments/123e4567-e89b-42d3-a456-426614174000"
 },
 {
  "args": {
   "body": {
    "name": "xxxxxxxx",
    "parameters": {},
    "type": "segment"
   },
   "segmentId": "123e4567-e89b-42d3-a456-426614174000",
   "websiteId": "123e4567-e89b-42d3-a456-426614174000"
  },
  "cloud": true,
  "group": "reports",
  "method": "POST",
  "name": "websites.segments.update",
  "query": [],
  "read": false,
  "result": {
   "createdAt": "2026-01-01T00:00:00Z",
   "id": "xxxxxxxx",
   "name": "xxxxxxxx",
   "parameters": "xxxxxxxx",
   "type": "xxxxxxxx",
   "updatedAt": "2026-01-01T00:00:00Z",
   "websiteId": "xxxxxxxx"
  },
  "route": "/websites/123e4567-e89b-42d3-a456-426614174000/segments/123e4567-e89b-42d3-a456-426614174000"
 },
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
  "name": "websites.sessionData.pivot",
  "query": [
   "endAt=1767312000000",
   "propertyName=xxxxxxxx",
   "startAt=1767225600000"
  ],
  "read": true,
  "result": {
   "count": 1,
   "data": [],
   "page": 1,
   "pageSize": 1
  },
  "route": "/websites/123e4567-e89b-42d3-a456-426614174000/session-data-pivot"
 },
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
  "name": "websites.sessionData.arraySeries",
  "query": [
   "endAt=1767312000000",
   "propertyName=xxxxxxxx",
   "startAt=1767225600000"
  ],
  "read": true,
  "result": [],
  "route": "/websites/123e4567-e89b-42d3-a456-426614174000/session-data/array-series"
 },
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
  "name": "websites.sessionData.dateSeries",
  "query": [
   "endAt=1767312000000",
   "propertyName=xxxxxxxx",
   "startAt=1767225600000"
  ],
  "read": true,
  "result": [],
  "route": "/websites/123e4567-e89b-42d3-a456-426614174000/session-data/date-series"
 },
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
  "name": "websites.sessionData.numericSeries",
  "query": [
   "endAt=1767312000000",
   "propertyName=xxxxxxxx",
   "startAt=1767225600000"
  ],
  "read": true,
  "result": [],
  "route": "/websites/123e4567-e89b-42d3-a456-426614174000/session-data/numeric-series"
 },
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
  "name": "websites.sessionData.numericStats",
  "query": [
   "endAt=1767312000000",
   "propertyName=xxxxxxxx",
   "startAt=1767225600000"
  ],
  "read": true,
  "result": {
   "average": 1,
   "max": 1,
   "median": 1,
   "min": 1,
   "total": 1
  },
  "route": "/websites/123e4567-e89b-42d3-a456-426614174000/session-data/numeric-stats"
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
  "name": "websites.sessionData.properties",
  "query": [
   "endAt=1767312000000",
   "startAt=1767225600000"
  ],
  "read": true,
  "result": [],
  "route": "/websites/123e4567-e89b-42d3-a456-426614174000/session-data/properties"
 },
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
  "name": "websites.sessionData.propertySeries",
  "query": [
   "endAt=1767312000000",
   "propertyName=xxxxxxxx",
   "startAt=1767225600000"
  ],
  "read": true,
  "result": [],
  "route": "/websites/123e4567-e89b-42d3-a456-426614174000/session-data/property-series"
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
