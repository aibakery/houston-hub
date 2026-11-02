return {
	scenario = {publisher = {}, config = {site_host = "Blog.Example.com"}, auth_method = "application_password",
		auth_config = {username = "editor", password = "abcd efgh ijkl mnop qrst uvwx"}},
	configure = function()
		requests = {}
		payload = "{}"
		responseHeaders = {}
		http = {request = function(req)
			table.insert(requests, req)
			return fixture.operation({statusCode = 200, headers = responseHeaders, body = fixture.reader(payload)})
		end}
	end,
	run = function(wp)
		local API = "https://blog.example.com/wp-json/wp/v2"
		local function last() return requests[#requests] end

		local names = {}
		for name in wp do if name ~= "help" then table.insert(names, name) end end
		table.sort(names)
		assert(table.concat(names, ",") == "getCategory,getComment,getMedia,getPage,getPageRevision,getPost,getPostRevision,getPostStatus,getPostType,getTag,getTaxonomy,getUser,"
			.. "listCategories,listComments,listMedia,listPageRevisions,listPages,listPostRevisions,listPostStatuses,listPostTypes,listPosts,listTags,listTaxonomies,listUsers,search",
			"wrong read-only surface: " .. table.concat(names, ","))
		assert(#requests == 0, "initialization reached WordPress")

		payload = '[{"id":7,"status":"publish","title":{"rendered":"Hello"},"sticky":false,"tags":[],"featured_media":0}]'
		responseHeaders = {["x-wp-total"] = {"31"}, ["x-wp-totalpages"] = {"4"}}
		local opts = {search = "Café & co/1", categories = {4, 2}, per_page = 10, orderby = "include", include = {12, 3}}
		local page = wp.listPosts(opts)
		assert(last().method == "GET" and last().body == nil and last().headers.Accept[1] == "application/json")
		assert(last().headers.Authorization == nil, "Lua must not set credentials")
		assert(last().url == API .. "/posts?categories%5B%5D=4&categories%5B%5D=2&include%5B%5D=12&include%5B%5D=3&orderby=include&per_page=10&search=Caf%C3%A9%20%26%20co%2F1", last().url)
		assert(opts.search == "Café & co/1" and opts.categories ~= nil, "caller options were modified")
		assert(page.total == 31 and page.total_pages == 4 and page.items[1].title.rendered == "Hello")
		assert(page.items[1].sticky == false and json.encode(page.items[1].tags) == "[]")

		payload = "[]"
		responseHeaders = {}
		local empty = wp.listPostRevisions({parent = 7})
		assert(last().url == API .. "/posts/7/revisions")
		assert(json.encode(empty.items) == "[]" and empty.total == nil and empty.total_pages == nil)

		payload = '{"id":12,"title":{"rendered":"Draft"},"status":"draft","date_gmt":null,"_embedded":{"author":[{"id":2}]}}'
		local post = wp.getPost({id = 12, context = "view", _fields = "id,title,status,date_gmt", _embed = true})
		assert(last().url == API .. "/posts/12?_embed=true&_fields=id%2Ctitle%2Cstatus%2Cdate_gmt&context=view", last().url)
		assert(post.title.rendered == "Draft" and post.date_gmt == json.decode("null") and post._embedded.author[1].id == 2)

		wp.getPageRevision({parent = 3, id = 9})
		assert(last().url == API .. "/pages/3/revisions/9")
		payload = '{"id":2,"name":"Editor","slug":"editor"}'
		assert(wp.getUser({id = "me"}).slug == "editor")
		assert(last().url == API .. "/users/me")
		payload = '[{"id":5,"status":"hold"}]'
		assert(wp.listComments({status = "hold", context = "view"}).items[1].status == "hold")
		assert(last().url == API .. "/comments?context=view&status=hold")
		payload = '[{"id":7,"title":"Pricing","type":"post","subtype":"post","url":"https://blog.example.com/pricing"}]'
		assert(wp.search({search = "pricing", subtype = {"post", "page"}}).items[1].title == "Pricing")
		assert(last().url == API .. "/search?search=pricing&subtype%5B%5D=post&subtype%5B%5D=page")
		payload = '{"slug":"post","rest_base":"posts","taxonomies":["category","post_tag"]}'
		assert(wp.getPostType({id = "post"}).rest_base == "posts")
		assert(last().url == API .. "/types/post")
		wp.getTaxonomy({id = "post_tag"})
		assert(last().url == API .. "/taxonomies/post_tag")
		wp.listMedia({media_type = "image", parent = 12})
		assert(last().url == API .. "/media?media_type=image&parent=12")
		payload = "[]"
		wp.listUsers({slug = {"jane"}, who = "authors", per_page = 5})
		assert(last().url == API .. "/users?per_page=5&slug%5B%5D=jane&who=authors", last().url)

		-- The edit context adds post passwords and commenters' and users' email and IP addresses.
		local before = #requests
		for _, call in {
			function() wp.listPosts({context = "edit", _fields = "id,password"}) end,
			function() wp.getPage({id = 3, context = "edit"}) end,
			function() wp.listComments({context = "edit"}) end,
			function() wp.getComment({id = 5, context = "edit"}) end,
			function() wp.listUsers({context = {"edit"}}) end,
			function() wp.getUser({id = "me", context = "edit"}) end,
			-- WordPress matches these against commenters' email and IP, and every user column for administrators.
			function() wp.listUsers({search = "@acme.com"}) end,
			function() wp.listUsers({search_columns = {"email"}, search = "a"}) end,
			function() wp.listUsers({orderby = "email"}) end,
			function() wp.listComments({status = "hold", search = "10.0."}) end,
			function() wp.listComments({author_email = "reader@example.com"}) end,
			function() wp.listUsers({email = "reader@example.com"}) end,
			function() wp.getComment({id = 5, author_ip = "10.0.0.1"}) end,
		} do
			local ok, err = pcall(call)
			assert(not ok and (string.find(tostring(err), "needs read-write access", 1, true) or string.find(tostring(err), "not available on read-only connections", 1, true)), tostring(err))
		end
		assert(#requests == before and #requests == 11, "edit context reached WordPress")
	end,
}
