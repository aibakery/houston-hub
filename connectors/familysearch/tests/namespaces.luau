return {
	scenario = {config = {environment = "production"}, access = {data = "write"}, auth_method = "token", auth_config = {token = "fixture-token"}},
	configure = function()
		http = {request = function() error("namespace discovery and help must not make network requests") end}
	end,
	run = function(c)
		local catalog = require("catalog.luau")
		local expected = {}
		for _, endpoint in catalog do expected[endpoint.export] = true end
		assert(#c.functions == 0 and #c.namespaces == 9, "start discovery with nine resource namespaces")
		local roots = {"authorities", "discovery", "discussions", "genealogies", "memories", "places", "sources", "tree", "users"}
		for _, name in roots do assert(table.find(c.namespaces, name) and type(c[name]) == "table") end
		local overview = c.help()
		assert(#overview < 3000, "root help must remain a compact resource overview")
		assert(string.find(overview, "genealogies", 1, true) and string.find(overview, "memories", 1, true))
		local functions, scopes, maximum = 0, 0, 0
		local function inspect(node, path)
			scopes += 1
			assert(#node.functions <= 16 and #node.namespaces <= 13, "resource scopes must remain browsable")
			assert(#node.functions + #node.namespaces > 0, "every discovered namespace must offer available work")
			maximum = math.max(maximum, #node.functions)
			local localHelp = node.help()
			for _, name in node.functions do
				local qualified = path .. "." .. name
				assert(type(node[name]) == "function" and expected[qualified], "discovery must match the catalog: " .. qualified)
				assert(string.find(localHelp, name, 1, true), "local help must document every local operation")
				expected[qualified] = nil
				functions += 1
			end
			for _, name in node.namespaces do
				assert(string.find(localHelp, name, 1, true), "local help must guide callers to every child")
				inspect(node[name], if path == "" then name else path .. "." .. name)
			end
		end
		inspect(c, "")
		assert(functions == 216 and scopes == 35 and maximum == 16 and next(expected) == nil)
		local personHelp = c.tree.persons.help("readPerson")
		assert(string.find(personHelp, "pid", 1, true) and string.find(personHelp, "relatives", 1, true) and string.find(personHelp, "sourceDescriptions", 1, true))
		local artifactHelp = c.memories.artifacts.help("downloadMemoryArtifact")
		assert(string.find(artifactHelp, "variant", 1, true) and string.find(artifactHelp, "thumbnail", 1, true) and string.find(artifactHelp, "path", 1, true))
		assert(string.find(c.tree.persons.help("usage"), "do not await", 1, true), "shared calling conventions remain available in a focused scope")
	end,
}
