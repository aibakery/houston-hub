-- Redis over Houston's verified-TLS connection. Credentials stay on Houston.
type Arg = string | number
local help = {
	text = "redis: commands on one Redis database. Each call is one command on its own connection; your Redis ACL still applies.",
	functions = {} :: {[string]: any},
}
local exports: {[string]: any} = {help = help}
local argumentSchema = {type = "array", items = {type = {"string", "number"}}}

help.functions.query = {
	description = [[Runs one command that Redis flags as read-only, such as GET, MGET, HGETALL,
  SCAN, TTL, ZRANGE or XRANGE, with string or number arguments in redis-cli
  order. Other commands fail. A missing value is nil; inside an array it is a
  JSON null. Arrays, maps, numbers and booleans become Lua values; integers
  beyond 2^53 become strings, and values that are not valid UTF-8 become
  '\x'-prefixed hex. Replies are limited to 4 MiB, so read large values
  in ranges with SCAN, HSCAN, LRANGE or GETRANGE.]],
	args = {"command", "...arguments"},
	inputSchema = {
		type = "object",
		properties = {command = {type = "string", minLength = 1}, arguments = argumentSchema},
		required = {"command"},
		additionalProperties = false,
		examples = {{command = "HGETALL", arguments = {"user:42"}}},
	},
	annotations = {readOnlyHint = true, openWorldHint = true},
}
function exports.query(name: string, ...: Arg): any
	return await(db.command({args = {name, ...}, readOnly = true}))
end

if config.access == "read-write" then
	help.functions.execute = {
		description = [[Runs any command your Redis user may run, except AUTH and HELLO, which the
	  connection settings own. A failed or interrupted call may already have
	  applied its change, so check before running it again.]],
		args = {"command", "...arguments"},
		inputSchema = {
			type = "object",
			properties = {command = {type = "string", minLength = 1}, arguments = argumentSchema},
			required = {"command"},
			additionalProperties = false,
			examples = {{command = "SET", arguments = {"greeting", "hello", "EX", 3600} :: {Arg}}},
		},
		annotations = {readOnlyHint = false, openWorldHint = true},
	}
	function exports.execute(name: string, ...: Arg): any
		return await(db.command({args = {name, ...}, readOnly = false}))
	end
end

return exports
