-- MariaDB over Houston's verified-TLS connection. Credentials stay on Houston.
type Params = {string | number | boolean}
type Result = {
	columns: {string}, rows: {{[string]: any}}, truncated: boolean,
	affectedRows: number?, lastInsertId: number?,
}

local MAX_ROWS = 10000

local help = {
	text = "mariadb: SQL on one MariaDB database. Each call is one statement on its own connection; your database grants still apply.",
	functions = {} :: {[string]: any},
}
local exports: {[string]: any} = {help = help}
local parameterSchema = {type = "array", items = {type = {"string", "number", "boolean"}}}

help.functions.query = {
	description = [[Runs one SELECT, WITH, SHOW, DESCRIBE, EXPLAIN, TABLE or VALUES statement in
  a read-only session. Bind values with ? in sql and pass them in order as
  params (strings, numbers, booleans).
  rows are objects keyed by column name, in columns order; NULL columns are
  absent. Integer and floating-point columns become Lua values; integers beyond
  2^53, DECIMAL, dates, times and text keep MariaDB's text form, such as
  '2026-01-31 09:30:00' for DATETIME. MariaDB stores JSON as text, so decode it
  with json.decode. Binary columns become '\x'-prefixed hex, such as '\x00ff'.
  At most 10,000 rows or 4 MiB are returned; truncated tells when more exist,
  so add LIMIT, filters or aggregation. Give duplicate column names an alias.]],
	args = {"sql", "params"},
	inputSchema = {
		type = "object",
		properties = {sql = {type = "string", minLength = 1}, params = parameterSchema},
		required = {"sql"},
		additionalProperties = false,
		examples = {{sql = "SELECT id FROM users WHERE team = ?", params = {"core"}}},
	},
	annotations = {readOnlyHint = true, openWorldHint = true},
}
function exports.query(sql: string, params: Params?): Result
	return await(db.query({sql = sql, params = params, maxRows = MAX_ROWS, readOnly = true}))
end

if config.access == "read-write" then
	help.functions.execute = {
		description = [[Runs one statement that may change data, with the same parameters as query.
	  affectedRows counts changed rows; lastInsertId is the AUTO_INCREMENT value an
	  INSERT generated. A failed or interrupted call may already have applied its
	  change, so check before running it again.]],
		args = {"sql", "params"},
		inputSchema = {
			type = "object",
			properties = {sql = {type = "string", minLength = 1}, params = parameterSchema},
			required = {"sql"},
			additionalProperties = false,
			examples = {{sql = "INSERT INTO tasks (title) VALUES (?)", params = {"Ship it"}}},
		},
		annotations = {readOnlyHint = false, openWorldHint = true},
	}
	function exports.execute(sql: string, params: Params?): Result
		return await(db.query({sql = sql, params = params, readOnly = false}))
	end
end

return exports
