return {
	scenario = {publisher = {}, config = {access = "read-only"}, auth_method = "token", auth_config = {token = "fixture-page-token"}},
	configure = function()
		requests, responses = {}, {}
		http = {request = function(req)
			table.insert(requests, req)
			assert(#responses > 0, "unexpected request: " .. req.url)
			return fixture.operation(table.remove(responses, 1))
		end}
		function respond(body)
			table.insert(responses, {statusCode = 200, headers = {}, body = fixture.reader(body)})
		end
		function rejected(call, expected)
			local before = #requests
			local ok, err = pcall(call)
			assert(not ok and string.find(tostring(err), expected, 1, true), "expected " .. expected .. ", got " .. tostring(err))
			assert(#requests == before, "invalid input reached Meta")
		end
	end,
	run = function(meta)
		local names = {}
		for name in meta do table.insert(names, name) end
		table.sort(names)
		assert(table.concat(names, ",") == table.concat({
			"getInsights", "getInstagramAccount", "getObject", "getPage", "listComments",
			"listConversations", "listFeed", "listHashtagRecentMedia", "listHashtagTopMedia", "listInstagramChildren",
			"listInstagramComments", "listInstagramMedia", "listInstagramReplies", "listInstagramStories", "listInstagramTags",
			"listMessages", "listPhotos", "listPublishedPosts", "listRatings", "listReactions", "listReels",
			"listScheduledPosts", "listTaggedPosts", "listVideos", "searchInstagramHashtag",
		}, ","), table.concat(names, ","))

		-- Reads go to /v26.0 with Meta's field list; the proxy adds the credential.
		respond('{"id":"101","name":"Bakery","instagram_business_account":{"id":"17841400000000001","username":"bakery"}}')
		local page = meta.getPage({fields = "id,name,instagram_business_account{id,username}"})
		assert(page.instagram_business_account.id == "17841400000000001")
		local req = requests[1]
		assert(req.method == "GET" and req.url == "https://graph.facebook.com/v26.0/me?fields=id%2Cname%2Cinstagram_business_account%7Bid%2Cusername%7D")
		assert(req.headers.Authorization == nil and req.headers.Accept[1] == "application/json" and req.body == nil)

		-- Default fields, path IDs and paging options.
		respond('{"data":[]}')
		local empty = meta.listInstagramChildren({media = "17900000000000001"})
		assert(json.encode(empty.data) == "[]")
		assert(requests[2].url == "https://graph.facebook.com/v26.0/17900000000000001/children?fields=id%2Cmedia_type%2Cmedia_url%2Cthumbnail_url%2Ctimestamp")
		respond('{"data":[{"id":"101_1","message":"Fresh bread"},{"id":"101_2"}],"paging":{"cursors":{"before":"QkVG","after":"QUZU"}}}')
		local feed = meta.listFeed({fields = "id,message", limit = 2, after = "QUFB", since = 1760000000, include_hidden = true})
		assert(#feed.data == 2 and feed.data[1].message == "Fresh bread" and feed.paging.cursors.after == "QUZU")
		assert(requests[3].url == "https://graph.facebook.com/v26.0/me/feed?fields=id%2Cmessage&since=1760000000&include_hidden=true&limit=2&after=QUFB")
		respond('{"data":[{"id":"t_1","updated_time":"2026-10-19T08:00:00+0000"}]}')
		meta.listConversations({platform = "instagram", fields = "id,updated_time"})
		assert(requests[4].url == "https://graph.facebook.com/v26.0/me/conversations?fields=id%2Cupdated_time&platform=instagram")
		respond('{"data":[{"name":"page_media_view","period":"day","values":[{"value":42,"end_time":"2026-10-18T07:00:00+0000"}]}]}')
		local insights = meta.getInsights({object = "me", metric = {"page_media_view", "page_follows"}, period = "day", since = "2026-10-01", ["until"] = "2026-10-18"})
		assert(insights.data[1].values[1].value == 42)
		assert(requests[5].url == "https://graph.facebook.com/v26.0/me/insights?metric=page_media_view,page_follows&period=day&since=2026-10-01&until=2026-10-18")
		respond('{"data":[{"id":"17843853986012965"}]}')
		meta.searchInstagramHashtag({user_id = "17841400000000001", q = "sourdough"})
		assert(requests[6].url == "https://graph.facebook.com/v26.0/ig_hashtag_search?user_id=17841400000000001&q=sourdough")
		respond('{"id":"t_1","messages":{"data":[]}}')
		meta.getObject({id = "t_1", fields = "messages.limit(5){message,from}"})
		assert(requests[7].url == "https://graph.facebook.com/v26.0/t_1?fields=messages.limit%285%29%7Bmessage%2Cfrom%7D")

		-- Meta echoes the access token in paging links; results drop it, and the link pages on.
		respond(json.encode({data = {{id = "c1"}}, paging = {
			cursors = {after = "QUZU"},
			next = "https://graph.facebook.com/v26.0/101_1/comments?access_token=EAAPAGE&fields=id%2Cmessage&limit=1&after=QUZU",
			previous = "https://graph.facebook.com/v26.0/101_1/comments?fields=id&limit=1&before=QkVG&access_token=EAAPAGE",
		}}))
		local comments = meta.listComments({object = "101_1", fields = "id,message", limit = 1})
		assert(comments.paging.next == "https://graph.facebook.com/v26.0/101_1/comments?fields=id%2Cmessage&limit=1&after=QUZU", comments.paging.next)
		assert(comments.paging.previous == "https://graph.facebook.com/v26.0/101_1/comments?fields=id&limit=1&before=QkVG", comments.paging.previous)
		respond('{"data":[]}')
		meta.listComments({next = comments.paging.next})
		assert(requests[9].url == comments.paging.next)
		-- A me route pages through the Page's own ID, with Meta's internal parameters.
		local feedNext = "https://graph.facebook.com/v26.0/101/feed?fields=id&limit=25&until=1760000000&__paging_token=enc_AdBz"
		respond('{"data":[]}')
		meta.listFeed({next = feedNext})
		assert(requests[10].url == feedNext)

		-- Graph honours ?method=delete and batch even on GET, and a Page can read its own token.
		rejected(function() meta.listFeed({method = "delete"}) end, "has no option method")
		rejected(function() meta.getObject({id = "101", batch = "[]"}) end, "has no option batch")
		rejected(function() meta.getPage({fields = "id,access_token"}) end, "cannot request access tokens")
		rejected(function() meta.getPage({fields = "id,PAGE_TOKEN"}) end, "cannot request access tokens")
		rejected(function() meta.getObject({id = "101", fields = "id&method=delete"}) end, "Graph field list")
		for _, link in {
			"https://graph.facebook.com/v26.0/101/feed?limit=25&method=delete",
			"https://graph.facebook.com/v26.0/101/feed?limit=25&access_token=EAAOTHER",
			"https://graph.facebook.com/v26.0/101/feed?batch=%5B%5D",
			"https://graph.facebook.com/v26.0/101/feed?suppress_http_code=1",
			"https://graph.facebook.com/v26.0/101/feed?m%65thod=delete",
			"https://graph.facebook.com/v26.0/101/comments?limit=25",
			"https://graph.facebook.com/v26.0/101/feed/extra?limit=25",
			"https://graph.facebook.com/v25.0/101/feed?limit=25",
			"https://graph.facebook.com.evil.test/v26.0/101/feed?limit=25",
			"http://graph.facebook.com/v26.0/101/feed?limit=25",
		} do
			rejected(function() meta.listFeed({next = link}) end, "paging.next link")
		end
		rejected(function() meta.listFeed({next = "https://graph.facebook.com/v26.0/101/feed?fields=access%5Ftoken"}) end, "cannot request access tokens")
		rejected(function() meta.listFeed({next = feedNext, limit = 5}) end, "pass next alone")
		rejected(function() meta.getPage({next = feedNext}) end, "has no option next")

		-- IDs are single path segments given as strings, and required options come first.
		rejected(function() meta.listComments({object = "../me"}) end, "one Meta ID")
		rejected(function() meta.listComments({object = 1234567890}) end, "ID string")
		rejected(function() meta.listComments({}) end, "ID string")
		rejected(function() meta.getInsights({object = "me"}) end, "metric is required")
		rejected(function() meta.getInsights({object = "me", metric = {}}) end, "empty array")
		rejected(function() meta.getInsights({object = "me", metric = {name = "x"}}) end, "not an object")
		rejected(function() meta.searchInstagramHashtag({q = "bread"}) end, "user_id is required")
		rejected(function() meta.listFeed({limit = {}}) end, "empty array")
		assert(#responses == 0)
	end,
}
