-- Shared fixture helpers call the real Go manifest engine. Provider expectations
-- live in each bundle; this module has no connector names or provider branches.
return function(call, raw, modules)
	local m = { raw = raw, modules = modules }
	function m.count(value)
		local count = 0
		for _ in value or {} do
			count += 1
		end
		return count
	end
	function m.concat(...)
		local result = {}
		for _, list in { ... } do
			for _, value in list do
				table.insert(result, value)
			end
		end
		return result
	end
	function m.prefix(value, prefix)
		return string.sub(value, 1, #prefix) == prefix
	end
	function m.cut(value, separator)
		local first, last = string.find(value, separator, 1, true)
		if not first then
			return value, "", false
		end
		return string.sub(value, 1, first - 1), string.sub(value, last + 1), true
	end
	function m.fail(message, ...)
		local details = {}
		for index = 1, select("#", ...) do
			details[index] = tostring((select(index, ...)))
		end
		error(if #details > 0 then string.format(message, table.unpack(details)) else tostring(message), 2)
	end
	function m.publisherClient(auth)
		return call("publisher_client", { auth = auth })
	end
	function m.base64(text)
		return call("base64", { text = text })
	end
	function m.render(text, context)
		return call("render", { text = text, context = context })
	end
	function m.some(values, predicate)
		for _, value in values do
			if predicate(value) then
				return true
			end
		end
		return false
	end
	function m.sortedEqual(a, b, unique)
		table.sort(a)
		table.sort(b)
		if unique then
			local distinct = {}
			for _, value in a do
				if value ~= distinct[#distinct] then
					table.insert(distinct, value)
				end
			end
			a = distinct
		end
		assert(m.equal(a, b), "expected " .. table.concat(a, "\n") .. "\nreceived " .. table.concat(b, "\n"))
	end
	function m.endpoints()
		local source = m.modules["connector.luau"]
		local entries = {}
		for method, path, rest in
			string.gmatch(source, '\n\t[%w_]+ = %{method = "([A-Z]+)", path = "([^"]+)"([^\n]*)')
		do
			local write = method ~= "GET"
			local flag, value = string.match(rest, "([%w_]+) = (true)")
			if not flag then
				flag, value = string.match(rest, "([%w_]+) = (false)")
			end
			if flag == "write" or flag == "read" then
				write = (value == "true") ~= (flag == "read")
			end
			table.insert(entries, {
				method = method,
				path = path,
				rest = rest,
				write = write,
				custom = string.find(rest, "custom = {", 1, true) ~= nil,
			})
		end
		local _, count = string.gsub(source, "= %{method = ", "")
		assert(#entries > 0 and #entries == count, "endpoint table was not fully read")
		return entries
	end
	function m.endpointRules()
		local source = m.modules["connector.luau"]
		local prefix = string.match(source, 'local API = "https://[^/"]+([^"]*)"')
			or string.match(source, 'local API = "https://" %.%. config%.[%w_]+ %.%. "([^"]*)"')
			or ""
		local entries = m.endpoints()
		local narrows = m.some(entries, function(entry)
			return entry.custom
		end)
		local want, got = {}, {}
		for _, entry in entries do
			local gates = { "" }
			if entry.write then
				gates = { '{{ is config.access "read-write" }}' }
			elseif narrows and not entry.custom then
				gates = { '{{ is config.access "read-only" }}', '{{ is config.access "read-write" }}' }
			end
			local paths = { prefix .. string.gsub(entry.path, "}:[%w_]+$", "}") }
			if string.find(entry.path, "{format}", 1, true) then
				paths = {}
				local formats = assert(
					string.match(source, "local FORMATS = table.freeze%(%{([^}]*)%}%)"),
					"missing formats"
				)
				for format in string.gmatch(formats, '"([^"]+)"') do
					table.insert(paths, prefix .. string.gsub(entry.path, "{format}", format))
				end
			end
			for _, path in paths do
				for _, gate in gates do
					table.insert(want, entry.method .. " " .. path .. " " .. gate)
				end
			end
		end
		for _, rule in m.raw.proxy do
			if m.count(rule.action.headers and rule.action.headers.set) == 0 then
				continue
			end
			for _, method in rule.match.method do
				for _, path in rule.match.path do
					table.insert(got, method .. " " .. path .. " " .. (rule["if"] or ""))
				end
			end
		end
		m.sortedEqual(want, got, true)
	end
	function m.resolve(publisher, config, auth, method)
		return call(
			"resolve",
			{ publisher = publisher, config = config, auth_config = auth, auth_method = method }
		)
	end
	function m.draft(publisher, config, auth, method)
		return call(
			"draft",
			{ publisher = publisher, config = config, auth_config = auth, auth_method = method }
		)
	end
	function m.recipe(r, method, href, headers)
		return call("recipe", { rules = r.Proxy or r, method = method, url = href, headers = headers })
	end
	function m.prepare(recipe, context, headers)
		return call("prepare", { recipe = recipe, context = context, headers = headers })
	end
	function m.prepareUrl(recipe, context)
		return call("prepare_url", { recipe = recipe, context = context })
	end
	function m.renderPaths(r, context)
		return call("render_paths", { rules = r.Proxy, context = context })
	end
	function m.database(r)
		return call("database", { rules = r.Proxy, context = r.Context })
	end
	function m.credentials(context)
		local _, err = call("credentials", { context = context })
		return err
	end
	function m.discovery(method, scopes, facts)
		return call("discovery", { auth_method = method, scopes = scopes, facts = facts })
	end
	function m.exports(config, method, scopes, facts)
		return call("exports", { config = config, auth_method = method, scopes = scopes, facts = facts })
	end
	function m.header(headers, name)
		for key, values in headers or {} do
			if string.lower(key) == string.lower(name) then
				return values[1] or ""
			end
		end
		return ""
	end
	function m.equal(a, b)
		if type(a) ~= type(b) then
			return false
		end
		if type(a) ~= "table" then
			return a == b
		end
		for key, value in a do
			if not m.equal(value, b[key]) then
				return false
			end
		end
		for key in b do
			if a[key] == nil then
				return false
			end
		end
		return true
	end
	function m.routes(r, authorization, allowed, routes)
		for _, route in routes do
			local method, href = string.match(route, "^(%S+) (.+)$")
			assert(method and href, "expected METHOD URL: " .. route)
			local recipe, err = m.recipe(r, method, href)
			assert((err == nil) == allowed, route .. ": " .. tostring(err))
			if allowed then
				local headers, problem = m.prepare(recipe, r.Context, { Authorization = { "forged" } })
				assert(problem == nil, route .. ": " .. tostring(problem))
				assert(m.header(headers, "Authorization") == authorization, "credential injection: " .. route)
			end
		end
	end
	function m.rejectOverrides(r, routes)
		for _, route in routes do
			local method, href = string.match(route, "^(%S+) (.+)$")
			local recipe, err = m.recipe(r, method, href)
			assert(recipe and not err, route)
			for _, name in { "X-HTTP-Method-Override", "X-HTTP-Method", "X-Method-Override" } do
				local headers = { [name] = { "DELETE" } }
				local _, matchError = m.recipe(r, method, href, headers)
				assert(matchError, "method override selected a route: " .. route)
				local _, prepareError = m.prepare(recipe, r.Context, headers)
				assert(prepareError, "method override was prepared: " .. route)
			end
		end
	end
	function m.rejectPreparedOverrides(recipe, context, route)
		for _, name in { "X-HTTP-Method-Override", "X-HTTP-Method", "X-Method-Override" } do
			local _, err = m.prepare(recipe, context, { [name] = { "DELETE" } })
			assert(err, "method override was prepared: " .. route)
		end
	end
	function m.refused(r, reason, routes)
		for _, route in routes do
			local method, href = string.match(route, "^(%S+) (.+)$")
			local recipe, err = m.recipe(r, method, href)
			if not err then
				_, err = m.prepare(recipe, r.Context)
			end
			assert(err and string.find(err, reason, 1, true), route .. ": " .. tostring(err))
		end
	end
	function m.authentication(cases)
		for _, case in cases do
			local r, err = m.resolve(case.publisher, case.config, case.auth, case.method)
			assert(r and not err, tostring(err))
			for name, value in r.PublicConfig or {} do
				assert(m.raw.config[name].type ~= "secret", "secret field in public config: " .. name)
				assert(
					type(value) ~= "string" or not string.find(value, "secret", 1, true),
					"credential in public config: " .. name
				)
			end
			if case.native then
				local db, problem = m.database(r)
				assert(db and not problem, tostring(problem))
				assert(
					db.Password == "synthetic-root-secret"
						and db.Host == "database.example.com"
						and db.TLSMode == "verify-full",
					"native credentials or TLS changed"
				)
			else
				if case.oauth then
					r.Context.Auth[case.method].access_token = "synthetic-oauth-token"
					assert(not case.scopes or m.count(r.Scopes) > 0, "OAuth scopes missing")
				end
				assert(not m.credentials(r.Context), "credentials unavailable")
				local recipe, problem = m.recipe(r, case.endpoint[1], case.endpoint[2])
				assert(recipe and not problem, tostring(problem))
				local headers, prepareError =
					m.prepare(recipe, r.Context, { Authorization = { "caller-forgery" } })
				assert(not prepareError, tostring(prepareError))
				if case.query then
					local href, urlError = m.prepareUrl(recipe, r.Context)
					assert(
						not urlError and href == case.endpoint[2] .. "?access_token=synthetic-method-secret",
						"query credential injection"
					)
					assert(m.header(headers, "Authorization") == "", "query credential also sent as header")
				else
					assert(
						m.header(headers, case.header) == case.expected,
						"credential injection: " .. case.method
					)
				end
				local _, denied = m.recipe(r, "GET", "https://unlisted.example.com/")
				assert(denied, "unlisted origin accepted")
			end
		end
	end
	return m
end
