return {
	contract = function(m)
		for _, case in
			{
				{ scopes = {}, exports = {} },
				{ scopes = { "account_info.read" }, exports = { "getCurrentAccount", "getSpaceUsage" } },
				{
					scopes = { "files.metadata.read" },
					exports = {
						"getMetadata",
						"listFolder",
						"listFolderContinue",
						"listFolderGetLatestCursor",
						"listRevisions",
						"search",
						"searchContinue",
						"statFile",
					},
				},
			}
		do
			local result, err = m.exports({ access = "read-write" }, "oauth", case.scopes)
			assert(result and not err, tostring(err))
			if #case.exports == 0 then
				assert(
					result.type == "error"
						and string.find(result.error, "configured bundle has no exports", 1, true),
					"empty grant exposed operations"
				)
			else
				assert(
					result.type == "result" and m.equal(result.exports, case.exports),
					"wrong configured exports"
				)
				local documented = {}
				for name in string.gmatch("\n" .. result.help, "\n([^%s%(]+)%(") do
					table.insert(documented, name)
				end
				assert(m.equal(documented, case.exports), "help does not match configured exports")
			end
		end
	end,
}
