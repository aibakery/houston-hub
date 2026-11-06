-- PostgreSQL over Houston's TLS connection in the configured TLS mode. Credentials stay on Houston.
type Params = {string | number | boolean}
type Result = {columns: {string}, rows: {{[string]: any}}, truncated: boolean, affectedRows: number?}

local MAX_ROWS = 10000
local help = {
	text = "postgres: SQL on one PostgreSQL database. Each call is one statement on its own connection; your database grants still apply.",
	functions = {} :: {[string]: any},
}
local exports: {[string]: any} = {help = help}

-- Both operations bind the same parameter types and return the same row format.
local parameterSchema = {
	type = "array",
	items = {type = {"string", "number", "boolean"}},
	description = "Bound values in SQL placeholder order.",
}
local resultSchema = {
	type = "object",
	properties = {
		columns = {type = "array", items = {type = "string"}},
		rows = {type = "array", items = {type = "object", additionalProperties = true}},
		truncated = {type = "boolean", description = "More rows exist; narrow the query or page with SQL."},
		affectedRows = {type = "integer"},
	},
	required = {"columns", "rows", "truncated"},
	additionalProperties = false,
}

help.functions.query = {
	description = [[Runs one statement in a read-only transaction. Bind values with $1, $2, ...
  in sql and pass them in order as params (strings, numbers, booleans).
  Parameters take their type from context; cast where needed, as in $1::jsonb.
  rows are objects keyed by column name, in columns order; NULL columns are
  absent. Booleans, integers, floats and json/jsonb columns become Lua values;
  integers beyond 2^53 and every other type keep PostgreSQL's text form, such as
  '2026-01-31 09:30:00+00' for timestamptz or '\x0102' for bytea.
  At most 10,000 rows or 4 MiB are returned; truncated tells when more exist,
  so add LIMIT, filters or aggregation. Give duplicate column names an alias.]],
	args = {"sql", "params"},
	inputSchema = {
		type = "object",
		properties = {
			sql = {type = "string", minLength = 1, description = "One SQL statement; use bound parameters for values."},
			params = parameterSchema,
		},
		required = {"sql"},
		additionalProperties = false,
		examples = {{sql = "SELECT id FROM users WHERE team = $1", params = {"core"}}},
	},
	outputSchema = resultSchema,
	annotations = {readOnlyHint = true, openWorldHint = true},
}
function exports.query(sql: string, params: Params?): Result
	return await(db.query({sql = sql, params = params, maxRows = MAX_ROWS, readOnly = true}))
end

if config.access == "read-write" then
	help.functions.execute = {
		description = [[Runs one statement that may change data, outside any transaction, with the
  same parameters as query. affectedRows counts the inserted, updated or deleted
  rows; rows hold any RETURNING values. A failed or interrupted call may already
  have applied its change, so check before running it again.]],
		args = {"sql", "params"},
		inputSchema = {
			type = "object",
			properties = {
				sql = {type = "string", minLength = 1, description = "One SQL statement; use bound parameters for values."},
				params = parameterSchema,
			},
			required = {"sql"},
			additionalProperties = false,
			examples = {{sql = "UPDATE tasks SET done = true WHERE id = $1 RETURNING id", params = {42}}},
		},
		outputSchema = resultSchema,
		annotations = {readOnlyHint = false, openWorldHint = true},
	}
	function exports.execute(sql: string, params: Params?): Result
		return await(db.query({sql = sql, params = params, maxRows = MAX_ROWS, readOnly = false}))
	end
end

return exports
