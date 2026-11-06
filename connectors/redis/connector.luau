-- Redis over Houston's verified-TLS connection. Credentials stay on Houston.
type Arg = string | number

local function command(readOnly: boolean, name: string, ...: Arg): any
	return await(db.command({args = {name, ...}, readOnly = readOnly}))
end

local exports: {[string]: any} = {
	query = function(name: string, ...: Arg): any
		return command(true, name, ...)
	end,
}
if config.access == "read-write" then
	exports.execute = function(name: string, ...: Arg): any
		return command(false, name, ...)
	end
end

local HELP: {[string]: string} = {
	query = [[Runs one command that Redis flags as read-only, such as GET, MGET, HGETALL,
  SCAN, TTL, ZRANGE or XRANGE, with string or number arguments in redis-cli
  order. Other commands fail. A missing value is nil; inside an array it is a
  JSON null. Arrays, maps, numbers and booleans become Lua values; integers
  beyond 2^53 become strings, and values that are not valid UTF-8 become
  '\x'-prefixed hex. Replies are limited to 4 MiB, so read large values
  in ranges with SCAN, HSCAN, LRANGE or GETRANGE.]],
	execute = [[Runs any command your Redis user may run, except AUTH and HELLO, which the
  connection settings own. A failed or interrupted call may already have
  applied its change, so check before running it again.]],
}

local docs: {[string]: any} = {}
local writeValues: {Arg} = {"greeting", "hello", "EX", 3600}
local examples: {[string]: any} = {
	query = {command = "HGETALL", values = {"user:42"}},
	execute = {command = "SET", values = writeValues},
}
for name in exports do
	docs[name] = {
		description = HELP[name], args = {"command", "...values"},
		inputSchema = {
			type = "object", properties = {
				command = {type = "string", minLength = 1, description = "Redis command name. Query requires a command Redis flags read-only."},
				values = {type = "array", items = {type = {"string", "number"}}, description = "Remaining redis-cli arguments in order; required arguments depend on the selected command."},
			}, required = {"command"}, additionalProperties = false, examples = {examples[name]},
		},
		annotations = {readOnlyHint = name == "query", openWorldHint = true},
	}
end
exports.help = {text = "redis: commands on one Redis database. Each call is one command on its own connection; your Redis ACL still applies.", functions = docs}

return exports
