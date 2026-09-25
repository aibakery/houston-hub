-- Shared database contract. SQL and credentials are handled by Houston.
return function(kind, title)
	local function send(ctx, sql, opts, execute)
		if type(sql) ~= "string" or sql == "" then
			error(kind .. ".query/execute requires a SQL string")
		end
		local payload = { source_id = ctx.source_id or ctx.id, query = sql }
		if execute then payload.execute = true end
		if type(opts) == "table" and type(opts.limit) == "number" then
			payload.limit = math.floor(opts.limit)
		end
		local operation = if execute then "execute" else "query"
		local result = connector_http.send({
			connector = kind, operation = operation, method = "POST",
			path = "/api/query", url = "/api/query",
			headers = { ["Content-Type"] = "application/json" },
			body = json.encode(payload),
		})
		if result == nil then
			connector_http.fail({ layer = "decode", connector = kind, operation = operation,
				path = "/api/query", retryable = false, recovery = "reduce limit",
				message = kind .. " query returned an empty body" })
		end
		return result
	end
	return {
		name = kind,
		description = "Query a connected " .. title .. " database.",
		signatures = { query = "query(sql, opts?)", execute = "execute(sql)" },
		functions = { query = function(ctx, sql, opts) return send(ctx, sql, opts, false) end },
		writes = { execute = function(ctx, sql) return send(ctx, sql, nil, true) end },
		help = "# " .. title .. [[

Credentials stay on the Houston server. Use the instance from houston.connectors().

query(sql, opts?) runs one read-only statement (SELECT, WITH, SHOW, DESCRIBE,
EXPLAIN as supported by your database). Optional opts.limit defaults to 100,
maximum 10000. Returns columns, rows, row_count, kind, and source_id.
Multi-statement SQL is rejected. Query always enforces read-only access.

execute(sql) is available only with read-write access. Runs one data or schema
mutation (INSERT, UPDATE, DELETE, CREATE, ALTER, DROP, etc.). Houston requires
both a read-write connector and your write permission. Returns affected_rows
for Postgres and Supabase; ClickHouse does not report an affected-row count.
Use query for reads. Transaction/session control and bulk COPY are unsupported.

Example:
return { run = function() return c.query("SELECT 1 AS n") end }
]],
	}
end
