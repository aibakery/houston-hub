return {
 scenario = {publisher = {}, config = {}, auth_method = "token", auth_config = {token = "fixture-private-x-token"}},
 configure = function()
  requests = {}
  status = 200
  payload = '{"data":[],"meta":{"result_count":0}}'
  responseHeaders = {}
  http = {request = function(req)
   table.insert(requests, req)
   assert(req.method == "GET" and req.headers.Authorization == nil, "credentials must remain in the proxy")
   return fixture.operation({statusCode = status, headers = responseHeaders, body = fixture.reader(payload)})
  end}
 end,
 run = function(c)
  local count = 0
  for name, fn in c do
   assert(type(fn) == "function")
   count += 1
  end
  assert(count == 8 and #requests == 0, "only eight read operations; help must be offline")
  local opts = {query = "from:XDevelopers #AI & lang:en", next_token = "next+/=", max_results = 10, ["post.fields"] = {"id", "text"}}
  payload = '{"data":[{"id":"18446744073709551615","text":"hi","note_post":{"text":"long text"}}],"includes":{"users":[]},"meta":{"next_token":"second+/="},"future":null}'
  local result = c.searchRecentTweets(opts)
  assert(result.data[1].id == "18446744073709551615" and result.data[1].note_post.text == "long text")
  assert(json.encode(result.includes.users) == "[]" and result.future == json.decode("null"))
  assert(opts.query == "from:XDevelopers #AI & lang:en" and opts.max_results == 10)
  local url = requests[1].url
  assert(string.find(url, "/tweets/search/recent?", 1, true))
  assert(string.find(url, "query=from%3AXDevelopers%20%23AI%20%26%20lang%3Aen", 1, true))
  assert(string.find(url, "next_token=next%2B%2F%3D", 1, true))
  assert(string.find(url, "post.fields=id%2Ctext", 1, true))
  c.searchRecentTweets({query = "conversation_id:123", next_token = result.meta.next_token})
  assert(string.find(requests[2].url, "next_token=second%2B%2F%3D", 1, true))
  c.searchAllTweets({query = "Houston", max_results = 500, sort_order = "recency", start_time = "2020-01-01T00:00:00Z", since_id = "123"})
  assert(string.find(requests[3].url, "/tweets/search/all?", 1, true))
  assert(string.find(requests[3].url, "max_results=500", 1, true))

  payload = '{"data":{"id":"123","text":"tweet"}}'
  c.getTweet({id = "123"})
  assert(string.find(requests[4].url, "/tweets/123?", 1, true))
  payload = '{"data":[{"id":"123"}],"errors":[{"resource_id":"456","detail":"Not found"}]}'
  assert(c.getTweets({ids = {"123", "456"}}).errors[1].resource_id == "456")
  assert(string.find(requests[5].url, "ids=123%2C456", 1, true))
  payload = '{"data":{"id":"789","username":"XDevelopers"}}'
  c.getUser({id = "789"})
  assert(string.find(requests[6].url, "/users/789?", 1, true))
  assert(not string.find(requests[6].url, "post.fields", 1, true))
  local user = c.getUserByUsername({username = "XDevelopers"})
  assert(string.find(requests[7].url, "/users/by/username/XDevelopers?", 1, true))
  payload = '{"data":[],"meta":{"result_count":0,"next_token":"timeline+/="}}'
  result = c.listUserTweets({id = user.data.id, exclude = {"replies", "retweets"}, max_results = 5})
  assert(string.find(requests[8].url, "/users/789/tweets?", 1, true))
  assert(string.find(requests[8].url, "exclude=replies%2Cretweets", 1, true))
  c.listUserMentions({id = user.data.id, pagination_token = result.meta.next_token, until_id = "999"})
  assert(string.find(requests[9].url, "/users/789/mentions?", 1, true))
  assert(string.find(requests[9].url, "pagination_token=timeline%2B%2F%3D", 1, true))
  payload = '{"meta":{"result_count":0}}'
  assert(c.searchRecentTweets({query = "none"}).data == nil)
  assert(#requests == 10, "unexpected automatic requests")
 end,
}
