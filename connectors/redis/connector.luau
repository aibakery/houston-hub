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
	query = [[query(command, ...args) -> reply
  Runs one command that Redis flags as read-only, such as GET, MGET, HGETALL,
  SCAN, TTL, ZRANGE or XRANGE, with string or number arguments in redis-cli
  order. Other commands fail. A missing value is nil; inside an array it is a
  JSON null. Arrays, maps, numbers and booleans become Lua values; integers
  beyond 2^53 become strings, and values that are not valid UTF-8 become
  '\x'-prefixed hex. Replies are limited to 4 MiB, so read large values
  in ranges with SCAN, HSCAN, LRANGE or GETRANGE.
  Example: query("HGETALL", "user:42")]],
	execute = [[execute(command, ...args) -> reply
  Runs any command your Redis user may run, except AUTH and HELLO, which the
  connection settings own. A failed or interrupted call may already have
  applied its change, so check before running it again.
  Example: execute("SET", "greeting", "hello", "EX", 3600)]],
}

function exports.help(): string
	local sections = {"redis: commands on one Redis database. Each call is one command on its own connection; your Redis ACL still applies."}
	for _, name in {"query", "execute"} do
		if exports[name] then
			table.insert(sections, HELP[name])
		end
	end
	return table.concat(sections, "\n\n")
end

return exports
