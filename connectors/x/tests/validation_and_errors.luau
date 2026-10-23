return {
 scenario = {publisher = {}, config = {}, auth_method = "token", auth_config = {token = "fixture-private-x-token"}},
 configure = function()
  calls = 0
  status = 200
  payload = '{}'
  responseHeaders = {}
  http = {request = function()
   calls += 1
   return fixture.operation({statusCode = status, headers = responseHeaders, body = fixture.reader(payload)})
  end}
 end,
 run = function(c)
  local function rejected(fn)
   local before = calls
   assert(not pcall(fn), "invalid input accepted")
   assert(calls == before, "invalid input reached X")
  end
  for _, value in {0, 9, 101, 1.5, "10", false, json.decode("null")} do
   rejected(function() c.searchRecentTweets({query = "test", max_results = value}) end)
  end
  for _, value in {123, "", "../search/recent", "123?query=x", "https://x.com/x/status/123"} do
   rejected(function() c.getTweet({id = value}) end)
  end
  rejected(function() c.searchRecentTweets() end)
  rejected(function() c.searchRecentTweets({}) end)
  rejected(function() c.searchRecentTweets({query = "test", pagination_token = "wrong"}) end)
  rejected(function() c.searchAllTweets({query = "test", sort_order = "popular"}) end)
  rejected(function() c.searchRecentTweets({query = "test", since_id = 123}) end)
  rejected(function() c.getUserByUsername({username = "@XDevelopers"}) end)
  rejected(function() c.getTweets({ids = {}}) end)
  rejected(function() c.getTweets({ids = {123}}) end)
  rejected(function() c.getTweets({ids = {[1] = "123", [3] = "456"}}) end)
  rejected(function() c.getTweets({ids = table.create(101, "123")}) end)
  rejected(function() c.getTweet({id = "123", ["post.fields"] = {bad = "text"}}) end)
  rejected(function() c.listUserMentions({id = "123", exclude = "replies"}) end)
  for _, raw in {"not-json", "null", "[]", "{}", '{"errors":[{"detail":"not found"}]}', '{"data":null}'} do
   payload = raw
   local before = calls
   assert(not pcall(c.getTweet, {id = "123"}), "invalid response accepted: " .. raw)
   assert(calls == before + 1, "failure was retried")
  end
  for _, code in {401, 402, 403, 429, 503} do
   status = code
   payload = 'fixture-private-x-token'
   responseHeaders = {["x-rate-limit-reset"] = {"1800000000"}}
   local before = calls
   local ok, err = pcall(c.getTweet, {id = "123"})
   assert(not ok and string.find(tostring(err), "X HTTP " .. tostring(code), 1, true))
   assert(not string.find(tostring(err), payload, 1, true), "upstream body leaked")
   if code == 429 then assert(string.find(tostring(err), "1800000000", 1, true)) end
   assert(calls == before + 1)
  end
 end,
}
