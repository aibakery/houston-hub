return {
	contract = function(m)
		local entries = m.endpoints()
		local function host(entry)
			return if string.find(entry.rest, "host = VIDEO_API", 1, true)
				then "graph-video.facebook.com"
				else "graph.facebook.com"
		end
		local want, got = {}, {}
		for _, entry in entries do
			local path = string.gsub(entry.path, "^/[^/]+", "/{id}")
			path = string.gsub(path, "{[%w_]+}", "{id}")
			table.insert(want, entry.method .. " " .. host(entry) .. "/v26.0" .. path)
		end
		for _, rule in m.raw.proxy do
			for _, hostname in rule.match.host do
				for _, method in rule.match.method do
					for _, path in rule.match.path do
						table.insert(got, method .. " " .. hostname .. path)
					end
				end
			end
		end
		m.sortedEqual(want, got, true)
		for _, access in { "read-only", "read-write" } do
			local r, err = m.resolve(nil, { access = access }, { token = "EAAPAGE" }, "token")
			assert(r and not err, tostring(err))
			for _, entry in entries do
				local route = entry.method
					.. " https://"
					.. host(entry)
					.. "/v26.0"
					.. string.gsub(entry.path, "{[%w_]+}", "101_1")
				m.routes(r, "Bearer EAAPAGE", not entry.write or access == "read-write", { route })
			end
		end
	end,
}
