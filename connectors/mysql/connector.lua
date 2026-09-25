-- MySQL connector: run one read-only SQL statement through Houston's query API.
-- Host primitives used: http.send (Houston /api/query) and json.
-- Credentials stay on the Houston server; this module never sees the connection URL.

local function require_ctx(ctx)
	if type(ctx) ~= "table" or type(ctx.id) ~= "string" or ctx.id == "" then
		error("mysql connector id is required")
	end
end

local function source_id(ctx)
	if type(ctx.source_id) == "string" and ctx.source_id ~= "" then
		return ctx.source_id
	end
	return ctx.id
end

local function payload_json(source, sql, opts)
	local payload = {
		source_id = source,
		query = sql,
	}
	if type(opts) == "table" and type(opts.limit) == "number" then
		payload.limit = math.floor(opts.limit)
	end
	return json.encode(payload)
end

local functions = {}

function functions.query(ctx, sql, opts)
	require_ctx(ctx)
	if type(sql) ~= "string" or sql == "" then
		error("mysql.query requires a SQL string")
	end
	local decoded = connector_http.send({
		connector = "mysql",
		operation = "query",
		method = "POST",
		path = "/api/query",
		url = "/api/query",
		headers = { ["Content-Type"] = "application/json" },
		body = payload_json(source_id(ctx), sql, opts),
	})
	if decoded == nil then
		connector_http.fail({
			layer = "decode",
			connector = "mysql",
			operation = "query",
			path = "/api/query",
			retryable = false,
			recovery = "reduce limit",
			message = "mysql query returned an empty body",
		})
	end
	return decoded
end

return {
	name = "mysql",
	description = "Run read-only SQL on a connected MySQL database.",
	signatures = {
		query = "query(sql, opts?)",
	},
	help = [[
# MySQL

Run one read-only SQL statement against a connected MySQL database.
Credentials stay on the Houston server; these functions never see the
connection URL or password.

Several databases are several instances of this connector, each with
its own `id`. Use the instance returned by `houston.connectors()` — do not
open a MySQL connection yourself.

V1 runs a single statement. Writes (`INSERT`, `UPDATE`, `DELETE`, DDL)
and multi-statement input are rejected. Discover schema with `SHOW` or
`DESCRIBE` through this same function.

## query(sql, opts?)

Houston `POST /api/query`. `sql` is one read-only statement (`SELECT`,
`WITH`, `SHOW`, `DESCRIBE`, `EXPLAIN`). Optional `opts.limit` is a number
(server default 100, max 10000).

Returns `columns` (string array) and `rows` (array of objects keyed by
column name), plus `kind`, `source_id`, and `row_count`.

## Example

	return {
		run = function()
			return c.query("SELECT 1 AS n")
		end,
	}
]],
	functions = functions,
}
