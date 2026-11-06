-- ClickHouse over Houston's verified HTTPS connection. Credentials stay on Houston.
type Params = {[string]: string | number | boolean}
type Result = {columns: {string}, rows: {{[string]: any}}, truncated: boolean}

local MAX_ROWS = 10000

local help = {
	text = "clickhouse: SQL on one ClickHouse database. Each call is one statement on its own connection; your database grants and settings profiles still apply.",
	functions = {} :: {[string]: any},
}
local exports: {[string]: any} = {help = help}
local parameterSchema = {type = "object", additionalProperties = {type = {"string", "number", "boolean"}}}

help.functions.query = {
	description = [[Runs one query with readonly=1. Bind values with ClickHouse placeholders such
  as {day:Date} in sql and pass them by name in params (strings, numbers,
  booleans); ClickHouse binds them on the server, so they are never quoted into
  the SQL. rows are objects keyed by column name, in columns order; NULL columns
  are absent. Numbers, booleans, arrays, tuples and maps become Lua values;
  integers beyond 2^53 and Decimal values become strings, and dates and times
  keep ClickHouse's text form, such as '2026-01-31 09:30:00'. Select hex(column)
  for binary strings.
  At most 10,000 rows or 4 MiB are returned; truncated tells when more exist,
  so add LIMIT, filters or aggregation. Give duplicate column names an alias.]],
	args = {"sql", "params"},
	inputSchema = {
		type = "object",
		properties = {sql = {type = "string", minLength = 1}, params = parameterSchema},
		required = {"sql"},
		additionalProperties = false,
		examples = {{sql = "SELECT count() AS n FROM events WHERE day = {day:Date}", params = {day = "2026-01-31"}}},
	},
	annotations = {readOnlyHint = true, openWorldHint = true},
}
function exports.query(sql: string, params: Params?): Result
	return await(db.query({sql = sql, params = params, maxRows = MAX_ROWS, readOnly = true}))
end

if config.access == "read-write" then
	help.functions.execute = {
		description = [[Runs one statement that may change data or schema, such as INSERT, ALTER or
	  CREATE, with the same parameters as query. ClickHouse reports no affected-row
	  count. A failed or interrupted call may already have applied its change, so
	  check before running it again.]],
		args = {"sql", "params"},
		inputSchema = {
			type = "object",
			properties = {sql = {type = "string", minLength = 1}, params = parameterSchema},
			required = {"sql"},
			additionalProperties = false,
			examples = {{sql = "INSERT INTO events (day, event) VALUES ({day:Date}, {event:String})", params = {day = "2026-01-31", event = "signup"}}},
		},
		annotations = {readOnlyHint = false, openWorldHint = true},
	}
	function exports.execute(sql: string, params: Params?): Result
		return await(db.query({sql = sql, params = params, readOnly = false}))
	end
end

return exports
