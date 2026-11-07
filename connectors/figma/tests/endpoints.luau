return {
	contract = function(m)
		local want = {}
		for _, entry in m.endpoints() do
			table.insert(want, entry.method .. " " .. entry.path .. " " .. tostring(entry.write))
		end
		for _, method in { "auth.token", "auth.oauth" } do
			local got = {}
			for _, rule in m.raw.proxy do
				local gate = rule["if"] or ""
				if
					not string.find(gate, method .. " ", 1, true)
					and not string.find(gate, method .. ")", 1, true)
				then
					continue
				end
				for _, verb in rule.match.method do
					for _, path in rule.match.path do
						table.insert(
							got,
							verb
								.. " "
								.. path
								.. " "
								.. tostring(string.find(gate, '"read-write"', 1, true) ~= nil)
						)
					end
				end
			end
			m.sortedEqual(table.clone(want), got)
		end
	end,
}
