return {
	contract = function(m)
		local prefix =
			assert(string.match(m.modules["connector.luau"], 'local API = "https://hub%.docker%.com([^"]*)"'))
		local want = {}
		for _, entry in m.endpoints() do
			assert(not entry.write, "anonymous endpoint writes")
			table.insert(want, prefix .. entry.path)
		end
		assert(#m.raw.proxy == 1 and m.equal(m.raw.proxy[1].match.method, { "GET" }), "expected one GET rule")
		m.sortedEqual(want, m.concat(m.raw.proxy[1].match.path))
	end,
}
