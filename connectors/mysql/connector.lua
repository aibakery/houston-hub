local function query(sql: any,opts: any)
    if type(sql) ~= "string" or sql == "" then error("query requires a nonempty SQL string") end
    opts = opts or {}
    return db.query({query = sql, params = opts.params, max_rows = opts.limit, read_only = true})
end
local exports = {query = query}
return exports
