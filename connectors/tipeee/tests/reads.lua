local requests = {}
local payload = "{}"
return {
	scenario = {config = {access = "read-only"}, auth_method = "token", auth_config = {token = "fixture-token"}},
	configure = function()
		requests = {}; payload = "{}"
		http = {request = function(req)
			assert(req.headers.Authorization == nil and not string.find(req.url, "access_token", 1, true), "credentials belong in server proxy")
			table.insert(requests, req)
			return fixture.operation({statusCode = 200, headers = {}, body = fixture.reader(payload)})
		end}
	end,
	run = function(t)
		local API = "https://api.tipeee.com"
		local names = "downloadMedia downloadPaymentBill downloadPaymentTips downloadPayments downloadPrivateMedia getCampaignRewardStats getCloseDate getDiscordGuild getNews getPayoutState getRecurringIndicators getReward getStatistics getUnreadMessages getWidgetGoal listCampaignRewards listCampaigns listCategories listComments listNews listPayments listRewards listTippers searchMessageTippers"
		local expected = {}
		for name in string.gmatch(names, "%S+") do expected[name] = true; assert(type(t[name]) == "function", name) end
		for name in t do assert(expected[name], "unexpected read-only export " .. name) end
		assert(#requests == 0)
		payload = '{"id":7,"name":"Print","api_key":"private-stream-key","nullable":null}'
		local reward = t.getReward({project="my-project",reward=7})
		assert(reward.id == 7 and reward.name == "Print" and reward.api_key == nil and reward.nullable == json.decode("null"))
		assert(requests[1].url == API .. "/v2.0/projects/my-project/rewards/7" and requests[1].method == "GET" and requests[1].body == nil)
		payload = '{"items":[{"id":9,"project":{"api_key":"secret","name":"Creator"}}],"pager":{"currentPage":0,"next":1,"perPage":100}}'
		local opts = {project = "my-project", campaign = "2026-10", page = 0, perPage = 100, noReward = 0}
		local page = t.listTippers(opts)
		assert(requests[2].url == API .. "/v2.0/projects/my-project/campaigns/2026-10/subscriptions?noReward=0&page=0&perPage=100")
		assert(page.pager.next == 1 and page.items[1].project.name == "Creator" and page.items[1].project.api_key == nil)
		assert(opts.project == "my-project" and opts.noReward == 0 and #requests == 2)
		payload = '{"items":[],"pager":{"next":null}}'
		assert(json.encode(t.listNews({project="my-project", statusFilter="draft"}).items) == "[]")
		assert(requests[3].url == API .. "/v2.0/projects/my-project/news?statusFilter=draft")
		t.listRewards({project="my-project",stock="available",priceMin=10,rewardSort="price"})
		assert(requests[4].url == API .. "/v2.0/projects/my-project/rewards?stock=available&priceMin=10&rewardSort=price")
		payload = '{"items":[],"pager":{"token":"next-cursor"}}'
		assert(t.listComments({thread="my-news-thread",perPage=10,token="next&value",direction="next"}).pager.token == "next-cursor")
		assert(requests[5].url == API .. "/v2.0/threads/my-news-thread/comments?perPage=10&token=next%26value&direction=next")
		payload = "[]"
		assert(json.encode(t.listCampaigns({project="my-project"})) == "[]")
		t.getStatistics({project="my-project",type="PER_PROJECT_CAMPAIGN",timeUnit="DAY"})
		assert(requests[7].url == API .. "/v2.0/projects/my-project/statistics?type=PER_PROJECT_CAMPAIGN&timeUnit=DAY")
		local before = #requests
		for _, project in {"../bad","x/y","x%2fy","https://evil.example"} do
			assert(not pcall(function() t.getReward({project=project,reward=1}) end))
		end
		for _, bad in {{project="valid",_method="delete"},{project="valid",access_token="forged"},{project="valid",files={x={}}}} do
			assert(not pcall(function() t.listRewards(bad) end))
		end
		assert(not pcall(function() t.getStatistics({project="p",timeUnit="DAY"}) end))
		assert(not pcall(function() t.downloadPayments({report="../../evil.csv",output="out"}) end))
		assert(not pcall(function() t.listNews({project="p",status="draft"}) end))
		assert(#requests == before, "invalid input reached network")
	end,
}
