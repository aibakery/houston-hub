return {
	scenario = {publisher = {}, config = {access = "read-only"}, auth_method = "token", auth_config = {token = "fixture-page-token"}},
	configure = function()
		requests, responses = {}, {}
		-- Sealing is native; a table of opaque handles stands in for it.
		local sealed, count = {}, 0
		houston = table.clone(houston)
		houston.seal = function(value)
			count += 1
			sealed["sealed:" .. count] = json.encode(value)
			return "sealed:" .. count
		end
		houston.unseal = function(token)
			assert(type(token) == "string" and sealed[token], "invalid sealed token")
			return json.decode(sealed[token])
		end
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
			"getInsights", "getInstagramAccount", "getInstagramPublishingLimit", "getObject", "getPage", "listComments",
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

		-- Default fields need no Instagram permission; Instagram functions name their account.
		respond('{"id":"101","name":"Bakery"}')
		meta.getPage()
		assert(requests[2].url == "https://graph.facebook.com/v26.0/me?fields=id%2Cname%2Cusername%2Clink%2Ccategory%2Cabout%2Cdescription%2Cwebsite%2Cphone%2Cemails%2Cfollowers_count%2Cfan_count%2Cverification_status", requests[2].url)
		table.remove(requests, 2)

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
		assert(requests[5].url == "https://graph.facebook.com/v26.0/me/insights?metric=page_media_view%2Cpage_follows&period=day&since=2026-10-01&until=2026-10-18")
		respond('{"data":[{"id":"17843853986012965"}]}')
		meta.searchInstagramHashtag({user_id = "17841400000000001", q = "sourdough"})
		assert(requests[6].url == "https://graph.facebook.com/v26.0/ig_hashtag_search?user_id=17841400000000001&q=sourdough")
		respond('{"id":"t_1","messages":{"data":[]}}')
		meta.getObject({id = "t_1", fields = "messages.limit(5){message,from}"})
		assert(requests[7].url == "https://graph.facebook.com/v26.0/t_1?fields=messages.limit%285%29%7Bmessage%2Cfrom%7D")

		-- Paging links come back sealed for the function that made them, without the token Meta
		-- writes into them, and page on through that function.
		respond(json.encode({data = {{id = "c1"}}, paging = {
			cursors = {after = "QUZU"},
			next = "https://graph.facebook.com/v26.0/101_1/comments?access_token=EAAPAGE&fields=id%2Cmessage&limit=1&after=QUZU",
			previous = "https://graph.facebook.com/v26.0/101_1/comments?fields=id&limit=1&before=QkVG&access_token=EAAPAGE",
		}}))
		local comments = meta.listComments({object = "101_1", fields = "id,message", limit = 1})
		assert(comments.paging.cursors.after == "QUZU" and not string.find(comments.paging.next, "graph", 1, true), comments.paging.next)
		respond('{"data":[]}')
		meta.listComments({next = comments.paging.next})
		assert(requests[9].url == "https://graph.facebook.com/v26.0/101_1/comments?fields=id%2Cmessage&limit=1&after=QUZU" and requests[9].headers.Accept[1] == "application/json", requests[9].url)
		-- previous cannot be replayed, so it is dropped; cursors.before pages backward.
		assert(comments.paging.previous == nil and comments.paging.cursors.after == "QUZU")
		-- Insights page through time the same way, whatever parameters Meta adds.
		local insightsNext = "https://graph.facebook.com/v26.0/101/insights?metric=page_follows&period=day&since=1&until=2&__cppo=1"
		respond(json.encode({data = {}, paging = {next = insightsNext}}))
		local follows = meta.getInsights({object = "me", metric = "page_follows", period = "day"})
		respond('{"data":[]}')
		meta.getInsights({next = follows.paging.next})
		assert(requests[11].url == insightsNext, requests[11].url)

		-- Stories have no like or comment counts to ask for.
		respond('{"data":[]}')
		meta.listInstagramStories({ig_user = "17841400000000001"})
		assert(requests[#requests].url == "https://graph.facebook.com/v26.0/17841400000000001/stories?fields=id%2Ccaption%2Cmedia_type%2Cmedia_product_type%2Cmedia_url%2Cthumbnail_url%2Cpermalink%2Ctimestamp", requests[#requests].url)

		-- Query values are encoded, so they cannot add parameters.
		respond('{"data":[]}')
		meta.listReels({fields = "id", since = "1&method=delete", ["until"] = "a=b"})
		assert(requests[#requests].url == "https://graph.facebook.com/v26.0/me/video_reels?fields=id&since=1%26method%3Ddelete&until=a%3Db", requests[#requests].url)
		-- Token fields and the tokens in Meta's own links, repeated or encoded, are dropped;
		-- text from people and cursors stay as they are.
		respond(json.encode({id = "101", accounts = {data = {{id = "102", name = "Other", access_token = "EAAOTHER", page_token = "EAAPT"}}},
			kept = "https://graph.facebook.com/v26.0/101/feed?since=x%3F&access_token=EAA7", bare = "https://graph.facebook.com/v26.0/101/feed?access_token=EAA9#top", deep = "https://graph.facebook.com/v26.0/101/feed?r=x%253Faccess_token%253DEAA8", piped = "https://graph.facebook.com/v26.0/101/feed?access_token=123%7Csecret&limit=25", nested = "https://graph.facebook.com/v26.0/101/feed?r=x%3Fa%3D1%26access_token%3D123%7Csecret%26b%3D2", named = "https://graph.facebook.com/v26.0/101/feed?limit=5&page_access_token=kept&after=Q",
			comments = {data = {}, paging = {next = "https://graph.facebook.com/v26.0/101_1/comments?access_token=EAA1&access_token=EAA2&limit=5",
				previous = "https://graph.facebook.com/v26.0/101_1/comments?limit=5&redirect=x%3Faccess_token%3DEAAGZBpage0123456789abcdefghijklmnopqrstuvwxyz%26ref%3Dabc"}},
			note = "see https://x.test/cb?access_token=abc&x=1 and thanks", cursors = {after = "QUFB_EAAGZBpage0123456789abcdefghijklmnopqrstuvwxyz"}, comment = "Is EAAGLES2024 still open?"}))
		local leaky = meta.getObject({id = "101", fields = "id,accounts,comments"})
		assert(leaky.accounts.data[1].name == "Other" and leaky.accounts.data[1].access_token == nil and leaky.accounts.data[1].page_token == nil)
		assert(leaky.comments.paging.next == "https://graph.facebook.com/v26.0/101_1/comments?limit=5", leaky.comments.paging.next)
		assert(leaky.comments.paging.previous == "https://graph.facebook.com/v26.0/101_1/comments?limit=5&redirect=x%3Fref%3Dabc", leaky.comments.paging.previous)
		assert(leaky.note == "see https://x.test/cb?access_token=abc&x=1 and thanks" and leaky.comment == "Is EAAGLES2024 still open?", leaky.note)
		assert(leaky.piped == "https://graph.facebook.com/v26.0/101/feed?limit=25" and leaky.nested == "https://graph.facebook.com/v26.0/101/feed?r=x%3Fa%3D1%26b%3D2" and leaky.kept == "https://graph.facebook.com/v26.0/101/feed?since=x%3F", leaky.kept)
		assert(leaky.bare == "https://graph.facebook.com/v26.0/101/feed#top" and leaky.deep == nil and leaky.named == nil, leaky.named)
		assert(leaky.cursors.after == "QUFB_EAAGZBpage0123456789abcdefghijklmnopqrstuvwxyz", leaky.cursors.after)
		-- Graph honours ?method=delete and batch even on GET, and a Page can read its own token.
		rejected(function() meta.listFeed({method = "delete"}) end, "has no option method")
		rejected(function() meta.getObject({id = "101", batch = "[]"}) end, "has no option batch")
		rejected(function() meta.getPage({fields = "id,access_token"}) end, "cannot request access tokens")
		rejected(function() meta.getPage({fields = "id,PAGE_TOKEN"}) end, "cannot request access tokens")
		-- Expanded edges page with padded cursors and zoned times.
		respond('{"id":"17841400000000001"}')
		meta.getObject({id = "17841400000000001", fields = "media.after(QVF/MTAxNTE=).since(2026-10-01T00:00:00+0000){caption}"})
		assert(requests[#requests].url == "https://graph.facebook.com/v26.0/17841400000000001?fields=media.after%28QVF%2FMTAxNTE%3D%29.since%282026-10-01T00%3A00%3A00%2B0000%29%7Bcaption%7D", requests[#requests].url)
		rejected(function() meta.getObject({id = "101", fields = "id&method=delete"}) end, "Graph field list")
		-- next takes only a link sealed by the same function, never a URL a caller wrote.
		rejected(function() meta.listFeed({next = "https://graph.facebook.com/v26.0/101/feed?method=delete"}) end, "paging.next value of an earlier")
		rejected(function() meta.listFeed({next = comments.paging.next}) end, "paging.next value of an earlier")
		rejected(function() meta.listComments({next = houston.seal({operation = "listComments", url = "https://evil.test/v26.0/me"})}) end, "paging.next value of an earlier")
		-- A paging link the scrub cannot clean fails the call instead of ending the list early.
		respond(json.encode({data = {{id = "101_1"}}, paging = {next = "https://graph.facebook.com/v26.0/101/feed?r=x%253Faccess_token%253DEAA8"}}))
		local dirtyOk, dirtyErr = pcall(function() meta.listFeed() end)
		assert(not dirtyOk and string.find(tostring(dirtyErr), "paging link", 1, true), tostring(dirtyErr))
		rejected(function() meta.listComments({next = comments.paging.next, limit = 5}) end, "pass next alone")
		rejected(function() meta.getPage({next = comments.paging.next}) end, "has no option next")

		-- IDs are single path segments given as strings, and required options come first.
		rejected(function() meta.listComments({object = "../me"}) end, "one Meta ID")
		rejected(function() meta.getObject({id = "me?method=delete"}) end, "one Meta ID")
		rejected(function() meta.getObject({id = "101#x"}) end, "one Meta ID")
		rejected(function() meta.getObject({id = ".."}) end, "one Meta ID")
		rejected(function() meta.getObject({id = "101 102"}) end, "one Meta ID")
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
