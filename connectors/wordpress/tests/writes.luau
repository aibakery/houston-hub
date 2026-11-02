return {
	scenario = {publisher = {}, config = {site_host = "blog.example.com", access = "read-write"}, auth_method = "application_password",
		auth_config = {username = "editor", password = "abcd efgh ijkl mnop qrst uvwx"}},
	configure = function()
		requests = {}
		uploaded = nil
		payload = "{}"
		fs = fixture.files()
		http = {request = function(req)
			table.insert(requests, req)
			if req.body ~= nil and type(req.body) ~= "string" then
				uploaded = await(req.body:readAll())
				await(req.body:close())
			end
			return fixture.operation({statusCode = 200, headers = {}, body = fixture.reader(payload)})
		end}
	end,
	run = function(wp)
		local API = "https://blog.example.com/wp-json/wp/v2"
		local NULL = json.decode("null")
		local function last() return requests[#requests] end
		local function sent() return json.decode(last().body) end

		local names = {}
		for name in wp do if name ~= "help" then table.insert(names, name) end end
		table.sort(names)
		assert(table.concat(names, ",") == "createCategory,createComment,createPage,createPost,createTag,deleteCategory,deleteComment,deleteMedia,deletePage,deletePost,deleteTag,"
			.. "getCategory,getComment,getMedia,getPage,getPageRevision,getPost,getPostRevision,getPostStatus,getPostType,getSettings,getTag,getTaxonomy,getUser,"
			.. "listCategories,listComments,listMedia,listPageRevisions,listPages,listPostRevisions,listPostStatuses,listPostTypes,listPosts,listTags,listTaxonomies,listUsers,"
			.. "search,updateCategory,updateComment,updateMedia,updatePage,updatePost,updateTag,uploadMedia",
			"wrong read-write surface: " .. table.concat(names, ","))

		payload = '{"id":42,"status":"draft","title":{"raw":"Launch notes"},"tags":[]}'
		local post = wp.createPost({title = "Launch notes", content = "<!-- wp:paragraph --><p>Hi</p><!-- /wp:paragraph -->",
			status = "draft", categories = {4}, tags = json.decode("[]"), excerpt = NULL})
		assert(last().method == "POST" and last().url == API .. "/posts" and last().headers["Content-Type"][1] == "application/json")
		local body = sent()
		assert(body.title == "Launch notes" and body.categories[1] == 4 and json.encode(body.tags) == "[]" and body.excerpt == NULL)
		assert(post.id == 42 and json.encode(post.tags) == "[]")

		wp.updatePost({id = 42, status = "future", date = "2026-11-10T09:00:00"})
		assert(last().method == "POST" and last().url == API .. "/posts/42")
		body = sent()
		assert(body.status == "future" and body.date == "2026-11-10T09:00:00" and body.id == nil, "path ID leaked into the body")
		wp.deletePost({id = 42})
		assert(last().method == "DELETE" and last().url == API .. "/posts/42" and last().body == nil)
		wp.deletePage({id = 8, force = true})
		assert(last().url == API .. "/pages/8?force=true")

		wp.createTag({name = "Launch"})
		assert(last().url == API .. "/tags" and sent().name == "Launch")
		wp.updateCategory({id = 4, parent = 0, description = "News"})
		assert(last().url == API .. "/categories/4" and sent().parent == 0)
		wp.deleteTag({id = 9, force = true})
		assert(last().method == "DELETE" and last().url == API .. "/tags/9?force=true")

		wp.updateComment({id = 5, status = "approved"})
		assert(last().method == "POST" and last().url == API .. "/comments/5" and sent().status == "approved" and sent().id == nil)
		wp.createComment({post = 42, parent = 5, content = "Thanks!"})
		assert(last().url == API .. "/comments" and sent().parent == 5)
		payload = '[{"id":5,"author_email":"reader@example.com"}]'
		assert(wp.listComments({status = "hold", context = "edit"}).items[1].author_email == "reader@example.com")
		assert(last().url == API .. "/comments?context=edit&status=hold")

		local photo = fs.open("photos/Café team.jpg", "w")
		photo:write("\255\216\255jpeg")
		await(photo:close())
		payload = '{"id":77,"media_type":"image","source_url":"https://blog.example.com/wp-content/uploads/cafe-team.jpg"}'
		local media = wp.uploadMedia({path = "photos/Café team.jpg", content_type = "Image/JPEG", filename = "cafe team.jpg", alt_text = "Team photo", post = 42})
		assert(last().method == "POST" and last().url == API .. "/media?alt_text=Team%20photo&post=42", last().url)
		assert(last().headers["Content-Type"][1] == "image/jpeg")
		assert(last().headers["Content-Disposition"][1] == 'attachment; filename="cafe team.jpg"', last().headers["Content-Disposition"][1])
		assert(uploaded == "\255\216\255jpeg" and media.id == 77, "the file is sent as the raw body")
		local plain = fs.open("photos/team.jpg", "w")
		plain:write("jpeg")
		await(plain:close())
		wp.uploadMedia({path = "photos/team.jpg", content_type = "image/jpeg"})
		assert(last().url == API .. "/media" and last().headers["Content-Disposition"][1] == 'attachment; filename="team.jpg"')
		wp.updateMedia({id = 77, caption = "The team"})
		assert(last().url == API .. "/media/77" and sent().caption == "The team")
		wp.deleteMedia({id = 77, force = true})
		assert(last().method == "DELETE" and last().url == API .. "/media/77?force=true")

		payload = "[]"
		wp.listUsers({search = "jane", search_columns = {"email"}, orderby = "email"})
		assert(last().url == API .. "/users?orderby=email&search=jane&search_columns%5B%5D=email", last().url)
		payload = '{"title":"Blog","timezone":"Europe/Paris","email":"admin@example.com"}'
		assert(wp.getSettings().timezone == "Europe/Paris")
		assert(last().method == "GET" and last().url == API .. "/settings")
		payload = '{"id":2,"email":"editor@example.com"}'
		assert(wp.getUser({id = "me", context = "edit"}).email == "editor@example.com")
		assert(last().url == API .. "/users/me?context=edit")
		assert(#requests == 17)
	end,
}
