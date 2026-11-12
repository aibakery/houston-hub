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
   "startAt": 1767225600000,
   "websiteId": "123e4567-e89b-42d3-a456-426614174000"
  },
  "cloud": true,
  "group": "analytics",
  "method": "GET",
  "name": "websites.events.stats",
  "query": [
   "endAt=1767312000000",
   "startAt=1767225600000"
  ],
  "read": true,
  "result": {
   "data": {
    "comparison": [],
    "length": 1
   }
  },
  "route": "/websites/123e4567-e89b-42d3-a456-426614174000/events/stats"
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
  "name": "websites.export",
  "query": [
   "endAt=1767312000000",
   "startAt=1767225600000"
  ],
  "read": true,
  "result": {
   "zip": "xxxxxxxx"
  },
  "route": "/websites/123e4567-e89b-42d3-a456-426614174000/export"
 },
 {
  "args": {
   "websiteId": "123e4567-e89b-42d3-a456-426614174000"
  },
  "cloud": true,
  "group": "reports",
  "method": "GET",
  "name": "websites.funnels.list",
  "query": [],
  "read": true,
  "result": {
   "count": 1,
   "data": [],
   "page": 1,
   "pageSize": 1
  },
  "route": "/websites/123e4567-e89b-42d3-a456-426614174000/funnels"
 },
 {
  "args": {
   "body": {
    "name": "xxxxxxxx",
    "parameters": {
     "steps": [
      {
       "type": "path",
       "value": "xxxxxxxx"
      },
      {
       "type": "path",
       "value": "xxxxxxxx"
      }
     ],
     "window": 1
    }
   },
   "websiteId": "123e4567-e89b-42d3-a456-426614174000"
  },
  "cloud": true,
  "group": "reports",
  "method": "POST",
  "name": "websites.funnels.create",
  "query": [],
  "read": false,
  "result": {
   "ok": true
  },
  "route": "/websites/123e4567-e89b-42d3-a456-426614174000/funnels"
 },
 {
  "args": {
   "endAt": 1767312000000,
   "startAt": 1767225600000,
   "steps": "[{\"type\":\"path\",\"value\":\"/pricing\"},{\"type\":\"event\",\"value\":\"Signup\"}]",
   "websiteId": "123e4567-e89b-42d3-a456-426614174000",
   "window": 1
  },
  "cloud": true,
  "group": "reports",
  "method": "GET",
  "name": "websites.funnels.stats",
  "query": [
   "endAt=1767312000000",
   "startAt=1767225600000",
   "steps=%5B%7B%22type%22%3A%22path%22%2C%22value%22%3A%22%2Fpricing%22%7D%2C%7B%22type%22%3A%22event%22%2C%22value%22%3A%22Signup%22%7D%5D"
  ],
  "read": true,
  "result": [],
  "route": "/websites/123e4567-e89b-42d3-a456-426614174000/funnels/stats"
 },
 {
  "args": {
   "funnelId": "123e4567-e89b-42d3-a456-426614174000",
   "websiteId": "123e4567-e89b-42d3-a456-426614174000"
  },
  "cloud": true,
  "group": "reports",
  "method": "DELETE",
  "name": "websites.funnels.delete",
  "query": [],
  "read": false,
  "result": {
   "ok": true
  },
  "route": "/websites/123e4567-e89b-42d3-a456-426614174000/funnels/123e4567-e89b-42d3-a456-426614174000"
 },
 {
  "args": {
   "funnelId": "123e4567-e89b-42d3-a456-426614174000",
   "websiteId": "123e4567-e89b-42d3-a456-426614174000"
  },
  "cloud": true,
  "group": "reports",
  "method": "GET",
  "name": "websites.funnels.get",
  "query": [],
  "read": true,
  "result": {
   "ok": true
  },
  "route": "/websites/123e4567-e89b-42d3-a456-426614174000/funnels/123e4567-e89b-42d3-a456-426614174000"
 },
 {
  "args": {
   "body": {
    "name": "xxxxxxxx",
    "parameters": {
     "steps": [
      {
       "type": "path",
       "value": "xxxxxxxx"
      },
      {
       "type": "path",
       "value": "xxxxxxxx"
      }
     ],
     "window": 1
    }
   },
   "funnelId": "123e4567-e89b-42d3-a456-426614174000",
   "websiteId": "123e4567-e89b-42d3-a456-426614174000"
  },
  "cloud": true,
  "group": "reports",
  "method": "POST",
  "name": "websites.funnels.update",
  "query": [],
  "read": false,
  "result": {
   "ok": true
  },
  "route": "/websites/123e4567-e89b-42d3-a456-426614174000/funnels/123e4567-e89b-42d3-a456-426614174000"
 },
 {
  "args": {
   "endAt": 1767312000000,
   "funnelId": "123e4567-e89b-42d3-a456-426614174000",
   "startAt": 1767225600000,
   "websiteId": "123e4567-e89b-42d3-a456-426614174000"
  },
  "cloud": true,
  "group": "reports",
  "method": "GET",
  "name": "websites.funnels.savedStats",
  "query": [
   "endAt=1767312000000",
   "startAt=1767225600000"
  ],
  "read": true,
  "result": [],
  "route": "/websites/123e4567-e89b-42d3-a456-426614174000/funnels/123e4567-e89b-42d3-a456-426614174000/stats"
 },
 {
  "args": {
   "websiteId": "123e4567-e89b-42d3-a456-426614174000"
  },
  "cloud": true,
  "group": "reports",
  "method": "GET",
  "name": "websites.goals.list",
  "query": [],
  "read": true,
  "result": {
   "count": 1,
   "data": [],
   "page": 1,
   "pageSize": 1
  },
  "route": "/websites/123e4567-e89b-42d3-a456-426614174000/goals"
 },
 {
  "args": {
   "body": {
    "name": "xxxxxxxx",
    "parameters": {
     "type": "path",
     "value": "xxxxxxxx"
    }
   },
   "websiteId": "123e4567-e89b-42d3-a456-426614174000"
  },
  "cloud": true,
  "group": "reports",
  "method": "POST",
  "name": "websites.goals.create",
  "query": [],
  "read": false,
  "result": {
   "ok": true
  },
  "route": "/websites/123e4567-e89b-42d3-a456-426614174000/goals"
 },
 {
  "args": {
   "endAt": 1767312000000,
   "startAt": 1767225600000,
   "type": "path",
   "value": "xxxxxxxx",
   "websiteId": "123e4567-e89b-42d3-a456-426614174000"
  },
  "cloud": true,
  "group": "reports",
  "method": "GET",
  "name": "websites.goals.stats",
  "query": [
   "endAt=1767312000000",
   "startAt=1767225600000",
   "type=path",
   "value=xxxxxxxx"
  ],
  "read": true,
  "result": {
   "num": 1,
   "total": 1
  },
  "route": "/websites/123e4567-e89b-42d3-a456-426614174000/goals/stats"
 },
 {
  "args": {
   "goalId": "123e4567-e89b-42d3-a456-426614174000",
   "websiteId": "123e4567-e89b-42d3-a456-426614174000"
  },
  "cloud": true,
  "group": "reports",
  "method": "DELETE",
  "name": "websites.goals.delete",
  "query": [],
  "read": false,
  "result": {
   "ok": true
  },
  "route": "/websites/123e4567-e89b-42d3-a456-426614174000/goals/123e4567-e89b-42d3-a456-426614174000"
 },
 {
  "args": {
   "goalId": "123e4567-e89b-42d3-a456-426614174000",
   "websiteId": "123e4567-e89b-42d3-a456-426614174000"
  },
  "cloud": true,
  "group": "reports",
  "method": "GET",
  "name": "websites.goals.get",
  "query": [],
  "read": true,
  "result": {
   "ok": true
  },
  "route": "/websites/123e4567-e89b-42d3-a456-426614174000/goals/123e4567-e89b-42d3-a456-426614174000"
 },
 {
  "args": {
   "body": {
    "name": "xxxxxxxx",
    "parameters": {
     "type": "path",
     "value": "xxxxxxxx"
    }
   },
   "goalId": "123e4567-e89b-42d3-a456-426614174000",
   "websiteId": "123e4567-e89b-42d3-a456-426614174000"
  },
  "cloud": true,
  "group": "reports",
  "method": "POST",
  "name": "websites.goals.update",
  "query": [],
  "read": false,
  "result": {
   "ok": true
  },
  "route": "/websites/123e4567-e89b-42d3-a456-426614174000/goals/123e4567-e89b-42d3-a456-426614174000"
 },
 {
  "args": {
   "endAt": 1767312000000,
   "goalId": "123e4567-e89b-42d3-a456-426614174000",
   "startAt": 1767225600000,
   "websiteId": "123e4567-e89b-42d3-a456-426614174000"
  },
  "cloud": true,
  "group": "reports",
  "method": "GET",
  "name": "websites.goals.savedStats",
  "query": [
   "endAt=1767312000000",
   "startAt=1767225600000"
  ],
  "read": true,
  "result": {
   "num": 1,
   "total": 1
  },
  "route": "/websites/123e4567-e89b-42d3-a456-426614174000/goals/123e4567-e89b-42d3-a456-426614174000/stats"
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
  "name": "websites.replays.heatmaps",
  "query": [
   "endAt=1767312000000",
   "startAt=1767225600000"
  ],
  "read": true,
  "result": {
   "mode": "click",
   "pages": [],
   "points": [],
   "scroll": {
    "buckets": [],
    "pageH": 1,
    "pageW": 1,
    "totalSessions": 1,
    "viewportH": 1,
    "viewportW": 1
   },
   "snapshot": {
    "id": "xxxxxxxx",
    "kind": "iframe",
    "pageH": 1,
    "pageW": 1,
    "url": "xxxxxxxx",
    "viewportH": 1,
    "viewportW": 1
   }
  },
  "route": "/websites/123e4567-e89b-42d3-a456-426614174000/heatmaps"
 },
 {
  "args": {
   "endAt": 1767312000000,
   "startAt": 1767225600000,
   "steps": 2,
   "websiteId": "123e4567-e89b-42d3-a456-426614174000"
  },
  "cloud": true,
  "group": "analytics",
  "method": "GET",
  "name": "websites.analytics.journeys",
  "query": [
   "endAt=1767312000000",
   "startAt=1767225600000"
  ],
  "read": true,
  "result": [],
  "route": "/websites/123e4567-e89b-42d3-a456-426614174000/journeys"
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
  "name": "websites.analytics.metrics",
  "query": [
   "endAt=1767312000000",
   "startAt=1767225600000",
   "type=path"
  ],
  "read": true,
  "result": [],
  "route": "/websites/123e4567-e89b-42d3-a456-426614174000/metrics"
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
  "name": "websites.analytics.expandedMetrics",
  "query": [
   "endAt=1767312000000",
   "startAt=1767225600000",
   "type=path"
  ],
  "read": true,
  "result": [],
  "route": "/websites/123e4567-e89b-42d3-a456-426614174000/metrics/expanded"
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
  "name": "websites.analytics.pageviews",
  "query": [
   "endAt=1767312000000",
   "startAt=1767225600000"
  ],
  "read": true,
  "result": {
   "pageviews": [],
   "sessions": []
  },
  "route": "/websites/123e4567-e89b-42d3-a456-426614174000/pageviews"
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
  "name": "websites.performance.chart",
  "query": [
   "endAt=1767312000000",
   "startAt=1767225600000"
  ],
  "read": true,
  "result": {
   "chart": []
  },
  "route": "/websites/123e4567-e89b-42d3-a456-426614174000/performance/chart"
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
  "name": "websites.performance.metrics",
  "query": [
   "endAt=1767312000000",
   "startAt=1767225600000",
   "type=path"
  ],
  "read": true,
  "result": [],
  "route": "/websites/123e4567-e89b-42d3-a456-426614174000/performance/metrics"
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
  "name": "websites.performance.stats",
  "query": [
   "endAt=1767312000000",
   "startAt=1767225600000"
  ],
  "read": true,
  "result": {
   "cls": {
    "p50": 1,
    "p75": 1,
    "p95": 1
   },
   "count": 1,
   "fcp": {
    "p50": 1,
    "p75": 1,
    "p95": 1
   },
   "inp": {
    "p50": 1,
    "p75": 1,
    "p95": 1
   },
   "lcp": {
    "p50": 1,
    "p75": 1,
    "p95": 1
   },
   "ttfb": {
    "p50": 1,
    "p75": 1,
    "p95": 1
   }
  },
  "route": "/websites/123e4567-e89b-42d3-a456-426614174000/performance/stats"
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
