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
  "group": "analytics",
  "method": "GET",
  "name": "getWebsiteDateRange",
  "query": [],
  "read": true,
  "result": {
   "endDate": "2026-01-01T00:00:00Z",
   "startDate": "2026-01-01T00:00:00Z"
  },
  "route": "/websites/123e4567-e89b-42d3-a456-426614174000/daterange"
 },
 {
  "args": {
   "endAt": 1767312000000,
   "startAt": 1767225600000,
   "websiteId": "123e4567-e89b-42d3-a456-426614174000"
  },
  "cloud": true,
  "group": "errors",
  "method": "GET",
  "name": "getWebsiteErrors",
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
  "route": "/websites/123e4567-e89b-42d3-a456-426614174000/errors"
 },
 {
  "args": {
   "endAt": 1767312000000,
   "startAt": 1767225600000,
   "websiteId": "123e4567-e89b-42d3-a456-426614174000"
  },
  "cloud": true,
  "group": "errors",
  "method": "GET",
  "name": "getWebsiteErrorStats",
  "query": [
   "endAt=1767312000000",
   "startAt=1767225600000"
  ],
  "read": true,
  "result": {
   "firstSeen": "xxxxxxxx",
   "issues": 1,
   "lastSeen": "xxxxxxxx",
   "occurrences": 1,
   "series": [],
   "visits": 1
  },
  "route": "/websites/123e4567-e89b-42d3-a456-426614174000/errors/stats"
 },
 {
  "args": {
   "endAt": 1767312000000,
   "startAt": 1767225600000,
   "type": "release",
   "websiteId": "123e4567-e89b-42d3-a456-426614174000"
  },
  "cloud": true,
  "group": "errors",
  "method": "GET",
  "name": "getWebsiteErrorValues",
  "query": [
   "endAt=1767312000000",
   "startAt=1767225600000",
   "type=release"
  ],
  "read": true,
  "result": [],
  "route": "/websites/123e4567-e89b-42d3-a456-426614174000/errors/values"
 },
 {
  "args": {
   "endAt": 1767312000000,
   "issueId": "123e4567-e89b-42d3-a456-426614174000",
   "startAt": 1767225600000,
   "websiteId": "123e4567-e89b-42d3-a456-426614174000"
  },
  "cloud": true,
  "group": "errors",
  "method": "GET",
  "name": "getWebsiteErrorIssue",
  "query": [
   "endAt=1767312000000",
   "startAt=1767225600000"
  ],
  "read": true,
  "result": {
   "canUpdate": true,
   "createdAt": "xxxxxxxx",
   "fingerprint": "xxxxxxxx",
   "firstSeen": "xxxxxxxx",
   "groupingVersion": 1,
   "id": "123e4567-e89b-42d3-a456-426614174000",
   "issues": 1,
   "lastSeen": "xxxxxxxx",
   "occurrences": 1,
   "resolvedAt": "xxxxxxxx",
   "series": [],
   "status": "unresolved",
   "title": "xxxxxxxx",
   "visits": 1,
   "websiteId": "123e4567-e89b-42d3-a456-426614174000"
  },
  "route": "/websites/123e4567-e89b-42d3-a456-426614174000/errors/123e4567-e89b-42d3-a456-426614174000"
 },
 {
  "args": {
   "body": {
    "status": "unresolved"
   },
   "issueId": "123e4567-e89b-42d3-a456-426614174000",
   "websiteId": "123e4567-e89b-42d3-a456-426614174000"
  },
  "cloud": true,
  "group": "errors",
  "method": "PATCH",
  "name": "updateWebsiteErrorIssue",
  "query": [],
  "read": false,
  "result": {
   "ok": true
  },
  "route": "/websites/123e4567-e89b-42d3-a456-426614174000/errors/123e4567-e89b-42d3-a456-426614174000"
 },
 {
  "args": {
   "endAt": 1767312000000,
   "issueId": "123e4567-e89b-42d3-a456-426614174000",
   "startAt": 1767225600000,
   "websiteId": "123e4567-e89b-42d3-a456-426614174000"
  },
  "cloud": true,
  "group": "errors",
  "method": "GET",
  "name": "getWebsiteErrorEvents",
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
  "route": "/websites/123e4567-e89b-42d3-a456-426614174000/errors/123e4567-e89b-42d3-a456-426614174000/events"
 },
 {
  "args": {
   "eventId": "123e4567-e89b-42d3-a456-426614174000",
   "issueId": "123e4567-e89b-42d3-a456-426614174000",
   "websiteId": "123e4567-e89b-42d3-a456-426614174000"
  },
  "cloud": true,
  "group": "errors",
  "method": "GET",
  "name": "getWebsiteErrorEvent",
  "query": [],
  "read": true,
  "result": {
   "browser": "xxxxxxxx",
   "createdAt": "xxxxxxxx",
   "device": "xxxxxxxx",
   "environment": "xxxxxxxx",
   "frames": [],
   "handled": true,
   "id": "123e4567-e89b-42d3-a456-426614174000",
   "message": "xxxxxxxx",
   "name": "xxxxxxxx",
   "os": "xxxxxxxx",
   "release": "xxxxxxxx",
   "replayId": "123e4567-e89b-42d3-a456-426614174000",
   "sessionId": "123e4567-e89b-42d3-a456-426614174000",
   "stack": "xxxxxxxx",
   "tags": {},
   "urlPath": "xxxxxxxx",
   "visitId": "123e4567-e89b-42d3-a456-426614174000"
  },
  "route": "/websites/123e4567-e89b-42d3-a456-426614174000/errors/123e4567-e89b-42d3-a456-426614174000/events/123e4567-e89b-42d3-a456-426614174000"
 },
 {
  "args": {
   "endAt": 1767312000000,
   "issueId": "123e4567-e89b-42d3-a456-426614174000",
   "startAt": 1767225600000,
   "type": "release",
   "websiteId": "123e4567-e89b-42d3-a456-426614174000"
  },
  "cloud": true,
  "group": "errors",
  "method": "GET",
  "name": "getWebsiteErrorIssueValues",
  "query": [
   "endAt=1767312000000",
   "startAt=1767225600000",
   "type=release"
  ],
  "read": true,
  "result": [],
  "route": "/websites/123e4567-e89b-42d3-a456-426614174000/errors/123e4567-e89b-42d3-a456-426614174000/values"
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
  "name": "getEventData",
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
  "route": "/websites/123e4567-e89b-42d3-a456-426614174000/event-data"
 },
 {
  "args": {
   "endAt": 1767312000000,
   "eventName": "xxxxxxxx",
   "startAt": 1767225600000,
   "websiteId": "123e4567-e89b-42d3-a456-426614174000"
  },
  "cloud": true,
  "group": "analytics",
  "method": "GET",
  "name": "getEventDataPivot",
  "query": [
   "endAt=1767312000000",
   "eventName=xxxxxxxx",
   "startAt=1767225600000"
  ],
  "read": true,
  "result": {
   "count": 1,
   "data": [],
   "page": 1,
   "pageSize": 1
  },
  "route": "/websites/123e4567-e89b-42d3-a456-426614174000/event-data-pivot"
 },
 {
  "args": {
   "endAt": 1767312000000,
   "eventName": "xxxxxxxx",
   "propertyName": "xxxxxxxx",
   "startAt": 1767225600000,
   "websiteId": "123e4567-e89b-42d3-a456-426614174000"
  },
  "cloud": true,
  "group": "analytics",
  "method": "GET",
  "name": "getEventDataArraySeries",
  "query": [
   "endAt=1767312000000",
   "eventName=xxxxxxxx",
   "propertyName=xxxxxxxx",
   "startAt=1767225600000"
  ],
  "read": true,
  "result": [],
  "route": "/websites/123e4567-e89b-42d3-a456-426614174000/event-data-pivot/array-series"
 },
 {
  "args": {
   "endAt": 1767312000000,
   "eventName": "xxxxxxxx",
   "propertyName": "xxxxxxxx",
   "startAt": 1767225600000,
   "websiteId": "123e4567-e89b-42d3-a456-426614174000"
  },
  "cloud": true,
  "group": "analytics",
  "method": "GET",
  "name": "getEventDataDateSeries",
  "query": [
   "endAt=1767312000000",
   "eventName=xxxxxxxx",
   "propertyName=xxxxxxxx",
   "startAt=1767225600000"
  ],
  "read": true,
  "result": [],
  "route": "/websites/123e4567-e89b-42d3-a456-426614174000/event-data-pivot/date-series"
 },
 {
  "args": {
   "endAt": 1767312000000,
   "eventName": "xxxxxxxx",
   "propertyName": "xxxxxxxx",
   "startAt": 1767225600000,
   "websiteId": "123e4567-e89b-42d3-a456-426614174000"
  },
  "cloud": true,
  "group": "analytics",
  "method": "GET",
  "name": "getEventDataNumericSeries",
  "query": [
   "endAt=1767312000000",
   "eventName=xxxxxxxx",
   "propertyName=xxxxxxxx",
   "startAt=1767225600000"
  ],
  "read": true,
  "result": [],
  "route": "/websites/123e4567-e89b-42d3-a456-426614174000/event-data-pivot/numeric-series"
 },
 {
  "args": {
   "endAt": 1767312000000,
   "eventName": "xxxxxxxx",
   "propertyName": "xxxxxxxx",
   "startAt": 1767225600000,
   "websiteId": "123e4567-e89b-42d3-a456-426614174000"
  },
  "cloud": true,
  "group": "analytics",
  "method": "GET",
  "name": "getEventDataNumericStats",
  "query": [
   "endAt=1767312000000",
   "eventName=xxxxxxxx",
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
  "route": "/websites/123e4567-e89b-42d3-a456-426614174000/event-data-pivot/numeric-stats"
 },
 {
  "args": {
   "endAt": 1767312000000,
   "eventName": "xxxxxxxx",
   "propertyName": "xxxxxxxx",
   "startAt": 1767225600000,
   "websiteId": "123e4567-e89b-42d3-a456-426614174000"
  },
  "cloud": true,
  "group": "analytics",
  "method": "GET",
  "name": "getEventDataPropertySeries",
  "query": [
   "endAt=1767312000000",
   "eventName=xxxxxxxx",
   "propertyName=xxxxxxxx",
   "startAt=1767225600000"
  ],
  "read": true,
  "result": [],
  "route": "/websites/123e4567-e89b-42d3-a456-426614174000/event-data-pivot/property-series"
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
  "name": "getEventDataEvents",
  "query": [
   "endAt=1767312000000",
   "startAt=1767225600000"
  ],
  "read": true,
  "result": [],
  "route": "/websites/123e4567-e89b-42d3-a456-426614174000/event-data/events"
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
  "name": "getEventDataFields",
  "query": [
   "endAt=1767312000000",
   "startAt=1767225600000"
  ],
  "read": true,
  "result": [],
  "route": "/websites/123e4567-e89b-42d3-a456-426614174000/event-data/fields"
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
  "name": "getEventDataProperties",
  "query": [
   "endAt=1767312000000",
   "startAt=1767225600000"
  ],
  "read": true,
  "result": [],
  "route": "/websites/123e4567-e89b-42d3-a456-426614174000/event-data/properties"
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
  "name": "getEventDataStats",
  "query": [
   "endAt=1767312000000",
   "startAt=1767225600000"
  ],
  "read": true,
  "result": {
   "events": 1,
   "properties": 1,
   "records": 1
  },
  "route": "/websites/123e4567-e89b-42d3-a456-426614174000/event-data/stats"
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
  "name": "getEventDataValues",
  "query": [
   "endAt=1767312000000",
   "propertyName=xxxxxxxx",
   "startAt=1767225600000"
  ],
  "read": true,
  "result": [],
  "route": "/websites/123e4567-e89b-42d3-a456-426614174000/event-data/values"
 },
 {
  "args": {
   "eventId": "123e4567-e89b-42d3-a456-426614174000",
   "websiteId": "123e4567-e89b-42d3-a456-426614174000"
  },
  "cloud": true,
  "group": "analytics",
  "method": "GET",
  "name": "getEventDataById",
  "query": [],
  "read": true,
  "result": [],
  "route": "/websites/123e4567-e89b-42d3-a456-426614174000/event-data/123e4567-e89b-42d3-a456-426614174000"
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
  "name": "getWebsiteEvents",
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
  "route": "/websites/123e4567-e89b-42d3-a456-426614174000/events"
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
  "name": "getWebsiteEventSeries",
  "query": [
   "endAt=1767312000000",
   "startAt=1767225600000",
   "timezone=xxxxxxxx"
  ],
  "read": true,
  "result": [],
  "route": "/websites/123e4567-e89b-42d3-a456-426614174000/events/series"
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
