return {
	contract = function(m)
		local source = m.modules["connector.luau"]
		local rows = {}
		for host, name in string.gmatch(source, '{host = "([^"]+)", name = "([^"]+)", id = %d+}') do
			table.insert(rows, { value = host, label = name })
		end
		assert(#rows > 0 and m.equal(rows, m.raw.config.chain.options), "chain choices differ from connector")
		local keyed, explorer = {}, {}
		for path in string.gmatch(source, '{name = "[%w_]+", path = "([^"]+)"') do
			table.insert(keyed, "/{chain}/api/v2" .. path)
			table.insert(explorer, "/api/v2" .. path)
		end
		assert(
			#keyed > 0
				and m.equal(m.raw.proxy[1].match.path, keyed)
				and m.equal(m.raw.proxy[2].match.path, explorer),
			"endpoint paths differ from proxy rules"
		)
	end,
}
