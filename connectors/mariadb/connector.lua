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
	query = [[query(sql, params?) -> {columns, rows, truncated}
  Runs one SELECT, WITH, SHOW, DESCRIBE, EXPLAIN, TABLE or VALUES statement in
  a read-only session. Bind values with ? in sql and pass them in order as
  params (strings, numbers, booleans).
  rows are objects keyed by column name, in columns order; NULL columns are
  absent. Integer and floating-point columns become Lua values; integers beyond
  2^53, DECIMAL, dates, times and text keep MariaDB's text form, such as
  '2026-01-31 09:30:00' for DATETIME. MariaDB stores JSON as text, so decode it
  with json.decode. Binary columns become '\x'-prefixed hex, such as '\x00ff'.
  At most 10,000 rows or 4 MiB are returned; truncated tells when more exist,
  so add LIMIT, filters or aggregation. Give duplicate column names an alias.
  Example: query("SELECT id, name FROM users WHERE team = ? ORDER BY id", {"core"})]],
	execute = [[execute(sql, params?) -> {affectedRows, lastInsertId?}
  Runs one statement that may change data, with the same parameters as query.
  affectedRows counts changed rows; lastInsertId is the AUTO_INCREMENT value an
  INSERT generated. A failed or interrupted call may already have applied its
  change, so check before running it again.
  Example: execute("INSERT INTO tasks (title) VALUES (?)", {"Ship it"})]],
}

function exports.help(): string
	local sections = {"mariadb: SQL on one MariaDB database. Each call is one statement on its own connection; your database grants still apply."}
	for _, name in {"query", "execute"} do
		if exports[name] then
			table.insert(sections, HELP[name])
		end
	end
	return table.concat(sections, "\n\n")
end

return exports
