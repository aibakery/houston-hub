return {
	contract = function(m)
		local want, got = {}, {}
		for line in string.gmatch(m.modules["connector.luau"], "[^\n]+") do
			if not string.find(line, '{name = "', 1, true) then
				continue
			end
			local method = string.match(line, 'method = "([^"]+)"')
			local path = assert(string.match(line, 'path = "([^"]+)"'), "endpoint without path")
			local gate = if method then '{{ is config.access "read-write" }}' else ""
			for _, prefix in { "", "/{base}", "/{base}/{sub}" } do
				table.insert(
					want,
					(method or "GET") .. " " .. prefix .. "/api/index.php" .. path .. " " .. gate
				)
			end
		end
		for _, rule in m.raw.proxy do
			for _, method in rule.match.method do
				for _, path in rule.match.path do
					table.insert(got, method .. " " .. path .. " " .. (rule["if"] or ""))
				end
			end
		end
		assert(#want >= 140, "endpoint table incomplete")
		m.sortedEqual(want, got)
	end,
}
