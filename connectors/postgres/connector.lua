local function query(sql: any,opts: any)
    if type(sql) ~= "string" or sql == "" then error("query requires a nonempty SQL string") end
    opts = opts or {}
    return db.query({query = sql, params = opts.params, max_rows = opts.limit, read_only = true})
end
local exports = {query = query}
if config.access == "read-write" then
    exports.execute = function(sql: any,opts: any)
        if type(sql) ~= "string" or sql == "" then error("execute requires a nonempty SQL string") end
        return db.query({query = sql, params = if opts then opts.params else nil, read_only = false})
    end
end

local operationHelp: {[string]: string} = {
	execute = [==[execute(sql,opts?) -> provider result. Nonempty SQL required; opts.params supplies bound parameters. Available only when effective access is read-write. The statement may mutate data; never automatically replay a partially completed operation.]==],
	query = [==[query(sql,opts?) -> provider rows. Nonempty SQL required; opts.params supplies bound parameters and opts.limit limits returned rows. Runs a read-only query; provider/database grants remain authoritative.]==],
}

function exports.help(): string
	local names: {string} = {}
	for name in (exports :: {[string]: any}) do
		if name ~= "help" then names[#names + 1] = name end
	end
	table.sort(names)
	local sections = {"postgres: configured connection help. Credentials stay on Houston. Use only the functions listed below. Provider scopes are enforced by real calls; help makes no network requests."}
	for _, name in names do
		local text = operationHelp[name]
		assert(text, "missing help for configured function " .. name)
		sections[#sections + 1] = text
	end
	return table.concat(sections, "\n\n")
end

return exports
