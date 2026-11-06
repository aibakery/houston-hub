-- PostgreSQL over Houston's TLS connection in the configured TLS mode. Credentials stay on Houston.
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
	query = [[Runs one statement in a read-only transaction. Bind values with $1, $2, ...
  in sql and pass them in order as params (strings, numbers, booleans).
  Parameters take their type from context; cast where needed, as in $1::jsonb.
  rows are objects keyed by column name, in columns order; NULL columns are
  absent. Booleans, integers, floats and json/jsonb columns become Lua values;
  integers beyond 2^53 and every other type keep PostgreSQL's text form, such as
  '2026-01-31 09:30:00+00' for timestamptz or '\x0102' for bytea.
  At most 10,000 rows or 4 MiB are returned; truncated tells when more exist,
  so add LIMIT, filters or aggregation. Give duplicate column names an alias.]],
	execute = [[Runs one statement that may change data, outside any transaction, with the
  same parameters as query. affectedRows counts the inserted, updated or deleted
  rows; rows hold any RETURNING values. A failed or interrupted call may already
  have applied its change, so check before running it again.]],
}

local parameters = {type = "array", items = {type = {"string", "number", "boolean"}}, description = "Bound values in SQL placeholder order."}
local examples = {query = {sql = "SELECT id FROM users WHERE team = $1", params = {"core"}}, execute = {sql = "UPDATE tasks SET done = true WHERE id = $1 RETURNING id", params = {42}}}

local resultProperties: {[string]: any} = {
	columns = {type = "array", items = {type = "string"}},
	rows = {type = "array", items = {type = "object", additionalProperties = true}},
	truncated = {type = "boolean", description = "More rows exist; narrow the query or page with SQL."},
	affectedRows = {type = "integer"},
}
local rowSchema = {
	type = "object", properties = resultProperties,
	required = {"columns", "rows", "truncated"}, additionalProperties = false,
}
local docs: {[string]: any} = {}
-- Describe the configured exports once; Houston renders help and binds examples
-- to the unchanged query(sql, params?) / execute(sql, params?) call shapes.
for name in exports do
	docs[name] = {
		description = HELP[name], args = {"sql", "params"},
		inputSchema = {
			type = "object", properties = {
				sql = {type = "string", minLength = 1, description = "One SQL statement; use bound parameters for values."},
				params = parameters,
			}, required = {"sql"}, additionalProperties = false, examples = {examples[name]},
		},
		outputSchema = rowSchema,
		annotations = {readOnlyHint = name == "query", openWorldHint = true},
	}
end
exports.help = {text = "postgres: SQL on one PostgreSQL database. Each call is one statement on its own connection; your database grants still apply.", functions = docs}

return exports
