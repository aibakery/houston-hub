-- Supabase Postgres over Houston's verified-TLS connection. Credentials stay on Houston.
type Params = {string | number | boolean}
type Result = {columns: {string}, rows: {{[string]: any}}, truncated: boolean, affectedRows: number?}

local MAX_ROWS = 10000

local function query(sql: string, params: Params?): Result
	return await(db.query({sql = sql, params = params, maxRows = MAX_ROWS, readOnly = true}))
end

local function execute(sql: string, params: Params?): Result
	return await(db.query({sql = sql, params = params, maxRows = MAX_ROWS, readOnly = false}))
end

local exports: {[string]: any} = {query = query}
if config.access == "read-write" then
	exports.execute = execute
end

local HELP: {[string]: string} = {
	query = [[query(sql, params?) -> {columns, rows, truncated}
  Runs one statement in a read-only transaction. Bind values with $1, $2, ...
  in sql and pass them in order as params (strings, numbers, booleans).
  Parameters take their type from context; cast where needed, as in $1::jsonb.
  rows are objects keyed by column name, in columns order; NULL columns are
  absent. Booleans, integers, floats and json/jsonb columns become Lua values;
  integers beyond 2^53 and every other type keep PostgreSQL's text form, such as
  '2026-01-31 09:30:00+00' for timestamptz or '\x0102' for bytea.
  At most 10,000 rows or 4 MiB are returned; truncated tells when more exist,
  so add LIMIT, filters or aggregation. Give duplicate column names an alias.
  Example: query("SELECT id, name FROM users WHERE team = $1 ORDER BY id", {"core"})]],
	execute = [[execute(sql, params?) -> {affectedRows, columns, rows, truncated}
  Runs one statement that may change data, outside any transaction, with the
  same parameters as query. affectedRows counts the inserted, updated or deleted
  rows; rows hold any RETURNING values. A failed or interrupted call may already
  have applied its change, so check before running it again.
  Example: execute("UPDATE tasks SET done = true WHERE id = $1 RETURNING id", {42})]],
}

function exports.help(): string
	local sections = {"supabase: SQL on your Supabase Postgres database. Each call is one statement on its own connection; your database grants still apply."}
	for _, name in {"query", "execute"} do
		if exports[name] then
			table.insert(sections, HELP[name])
		end
	end
	return table.concat(sections, "\n\n")
end

return exports
