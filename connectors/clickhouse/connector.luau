-- ClickHouse over Houston's verified HTTPS connection. Credentials stay on Houston.
type Params = {[string]: string | number | boolean}
type Result = {columns: {string}, rows: {{[string]: any}}, truncated: boolean}

local MAX_ROWS = 10000

local function query(sql: string, params: Params?): Result
	return await(db.query({sql = sql, params = params, maxRows = MAX_ROWS, readOnly = true}))
end

local function execute(sql: string, params: Params?): Result
	return await(db.query({sql = sql, params = params, readOnly = false}))
end

local exports: {[string]: any} = {query = query}
if config.access == "read-write" then
	exports.execute = execute
end

local HELP: {[string]: string} = {
	query = [[Runs one query with readonly=1. Bind values with ClickHouse placeholders such
  as {day:Date} in sql and pass them by name in params (strings, numbers,
  booleans); ClickHouse binds them on the server, so they are never quoted into
  the SQL. rows are objects keyed by column name, in columns order; NULL columns
  are absent. Numbers, booleans, arrays, tuples and maps become Lua values;
  integers beyond 2^53 and Decimal values become strings, and dates and times
  keep ClickHouse's text form, such as '2026-01-31 09:30:00'. Select hex(column)
  for binary strings.
  At most 10,000 rows or 4 MiB are returned; truncated tells when more exist,
  so add LIMIT, filters or aggregation. Give duplicate column names an alias.]],
	execute = [[Runs one statement that may change data or schema, such as INSERT, ALTER or
  CREATE, with the same parameters as query. Returns columns, rows and truncated
  (empty arrays for a command with no result). ClickHouse reports no affected-row
  count. A failed or interrupted call may already have applied its change, so
  check before running it again.]],
}

local parameters = {type = "object", additionalProperties = {type = {"string", "number", "boolean"}}, description = "Values keyed by the names in typed SQL placeholders, such as {day:Date}."}
local examples = {query = {sql = "SELECT event, count() AS n FROM events WHERE day = {day:Date} GROUP BY event", params = {day = "2026-01-31"}}, execute = {sql = "INSERT INTO events (day, event) VALUES ({day:Date}, {event:String})", params = {day = "2026-01-31", event = "signup"}}}
local extraResultProperties: {[string]: any} = {}

-- Request layer shared verbatim by the native-SQL connectors (structured documentation).
local resultProperties: {[string]: any} = {
	columns = {type = "array", items = {type = "string"}},
	rows = {type = "array", items = {type = "object", additionalProperties = true}},
	truncated = {type = "boolean", description = "More rows exist; narrow the query or page with SQL."},
}
for name, property in extraResultProperties do resultProperties[name] = property end
local rowSchema = {
	type = "object", properties = resultProperties,
	required = {"columns", "rows", "truncated"}, additionalProperties = false,
}
local docs: {[string]: any} = {}
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
-- End of the shared request layer.
exports.help = {text = "clickhouse: SQL on one ClickHouse database. Each call is one statement on its own connection; your database grants and settings profiles still apply.", functions = docs}

return exports
