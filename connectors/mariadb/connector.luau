-- MariaDB over Houston's verified-TLS connection. Credentials stay on Houston.
type Params = {string | number | boolean}
type Result = {
	columns: {string}, rows: {{[string]: any}}, truncated: boolean,
	affectedRows: number?, lastInsertId: number?,
}

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
	query = [[Runs one SELECT, WITH, SHOW, DESCRIBE, EXPLAIN, TABLE or VALUES statement in
  a read-only session. Bind values with ? in sql and pass them in order as
  params (strings, numbers, booleans).
  rows are objects keyed by column name, in columns order; NULL columns are
  absent. Integer and floating-point columns become Lua values; integers beyond
  2^53, DECIMAL, dates, times and text keep MariaDB's text form, such as
  '2026-01-31 09:30:00' for DATETIME. MariaDB stores JSON as text, so decode it
  with json.decode. Binary columns become '\x'-prefixed hex, such as '\x00ff'.
  At most 10,000 rows or 4 MiB are returned; truncated tells when more exist,
  so add LIMIT, filters or aggregation. Give duplicate column names an alias.]],
	execute = [[Runs one statement that may change data, with the same parameters as query.
  affectedRows counts changed rows; lastInsertId is the AUTO_INCREMENT value an
  INSERT generated. A failed or interrupted call may already have applied its
  change, so check before running it again.]],
}

local parameters = {type = "array", items = {type = {"string", "number", "boolean"}}, description = "Bound values in SQL placeholder order."}
local examples = {query = {sql = "SELECT id FROM users WHERE team = ?", params = {"core"}}, execute = {sql = "INSERT INTO tasks (title) VALUES (?)", params = {"Ship it"}}}
local extraResultProperties: {[string]: any} = {affectedRows = {type = "integer"}, lastInsertId = {type = "integer"}}

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
exports.help = {text = "mariadb: SQL on one MariaDB database. Each call is one statement on its own connection; your database grants still apply.", functions = docs}

return exports
