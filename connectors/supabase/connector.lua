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
return exports
