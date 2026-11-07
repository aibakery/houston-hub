return {
	contract = function(m)
		-- TestWordPressSiteHostAndAccessBoundaries
		do
			local password = { username = "editor", password = "abcd efgh ijkl mnop qrst uvwx" }
			for _, host in { "", "https://blog.example.com", "blog.example.com/wp", "*.example.com" } do
				do
					local _, err = m.resolve(nil, { site_host = host }, password, "application_password")
					if err == nil then
						m.fail("accepted site domain %s", host)
					end
				end
			end
			local basic = "Basic " .. m.base64("editor:abcd efgh ijkl mnop qrst uvwx")
			for _, access in { "read-only", "read-write" } do
				local r, err = m.resolve(
					nil,
					{ access = access, site_host = "Blog.Example.com" },
					password,
					"application_password"
				)
				assert(not err, tostring(err))
				if (r.PublicConfig["site_host"] ~= "Blog.Example.com") or (m.count(r.PublicConfig) ~= 2) then
					m.fail("unexpected Lua config: %s", r.PublicConfig)
				end
				local assertRoute = function(method, url, allowed)
					local caller = { Authorization = { "forged" } }
					local recipe, err = m.recipe(r, method, url, caller)
					if not allowed then
						if err == nil then
							m.fail("access=%s allowed %s %s", access, method, url)
						end
						return
					end
					if err ~= nil then
						m.fail("access=%s denied %s %s: %s", access, method, url, err)
					end
					local headers, err = m.prepare(recipe, r.Context, caller)
					if
						((err ~= nil) or (m.header(headers, "Authorization") ~= basic))
						or (m.header(caller, "Authorization") ~= "forged")
					then
						m.fail("incorrect credential injection: %s", err)
					end
					m.rejectPreparedOverrides(recipe, r.Context, method .. " " .. url)
				end
				local api = "https://blog.example.com/wp-json/wp/v2"
				for _, path in
					{
						"/posts?status%5B%5D=draft&context=edit",
						"/posts/1",
						"/posts/1/revisions",
						"/posts/1/revisions/2",
						"/pages",
						"/pages/1/revisions/2",
						"/media",
						"/media/3",
						"/categories/4",
						"/tags",
						"/comments?status=hold",
						"/comments/5",
						"/users",
						"/users/me",
						"/search?search=x",
						"/types/post",
						"/statuses",
						"/taxonomies/category",
					}
				do
					assertRoute("GET", api .. path, true)
				end
				assertRoute("GET", api .. "/settings", (access == "read-write"))
				for _, route in
					{
						{ "POST", "/posts" },
						{ "POST", "/posts/1" },
						{ "DELETE", "/posts/1?force=true" },
						{ "POST", "/pages/2" },
						{ "POST", "/media" },
						{ "POST", "/media/3" },
						{ "DELETE", "/media/3?force=true" },
						{ "POST", "/categories" },
						{ "DELETE", "/tags/4?force=true" },
						{ "POST", "/comments/5" },
						{ "DELETE", "/comments/5" },
					}
				do
					assertRoute(route[1], api .. route[2], (access == "read-write"))
				end
				for _, route in
					{
						{ "GET", api .. "/plugins" },
						{ "POST", api .. "/plugins" },
						{ "GET", api .. "/themes" },
						{ "GET", api .. "/users/me/application-passwords" },
						{ "POST", api .. "/users/1/application-passwords" },
						{ "GET", api .. "/users/me/application-passwords/introspect" },
						{ "POST", api .. "/users" },
						{ "POST", api .. "/users/1" },
						{ "DELETE", api .. "/users/1" },
						{ "POST", api .. "/settings" },
						{ "POST", api .. "/media/3/post-process" },
						{ "POST", api .. "/posts/1/autosaves" },
						{ "DELETE", api .. "/posts/1/revisions/2" },
						{ "PUT", api .. "/posts/1" },
						{ "PATCH", api .. "/posts/1" },
						{ "DELETE", api .. "/posts" },
						{ "DELETE", api .. "/comments" },
						{ "DELETE", api .. "/media" },
						{ "POST", "https://blog.example.com/wp-json/batch/v1" },
						{ "GET", api .. "/block-directory/search" },
						{ "POST", api .. "/templates" },
						{ "POST", api .. "/global-styles/1" },
						{ "GET", "https://blog.example.com/wp-json/" },
						{ "GET", "https://blog.example.com/wp-json/wc/v3/orders" },
						{ "GET", "https://blog.example.com/wp-admin/" },
						{ "GET", "https://blog.example.com/?rest_route=/wp/v2/posts" },
						{ "GET", "https://www.blog.example.com/wp-json/wp/v2/posts" },
						{ "GET", "https://blog.example.com.attacker.test/wp-json/wp/v2/posts" },
						{ "GET", "https://blog.example.com:8443/wp-json/wp/v2/posts" },
						{ "GET", "http://blog.example.com/wp-json/wp/v2/posts" },
						{ "GET", api .. "/posts/%2e%2e/users/1/application-passwords" },
					}
				do
					assertRoute(route[1], route[2], false)
				end
			end
		end
	end,
}
