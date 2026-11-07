-- Standard base64 (RFC 4648) for Graph's fileAttachment contentBytes. A buffer keeps memory
-- proportional to the data, which can be a few megabytes.
local ALPHABET = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
local PAD = string.byte("=")
local CODES: {[number]: number} = {}
for i = 1, 64 do CODES[i - 1] = string.byte(ALPHABET, i) end

local function encode(data: string): string
	local out = buffer.create((#data + 2) // 3 * 4)
	local position = 0
	for i = 1, #data, 3 do
		local a, b, c = string.byte(data, i, i + 2)
		local n = a * 65536 + (b or 0) * 256 + (c or 0)
		buffer.writeu8(out, position, CODES[n // 262144])
		buffer.writeu8(out, position + 1, CODES[n // 4096 % 64])
		buffer.writeu8(out, position + 2, if b then CODES[n // 64 % 64] else PAD)
		buffer.writeu8(out, position + 3, if c then CODES[n % 64] else PAD)
		position += 4
	end
	return buffer.tostring(out)
end

return {encode = encode}
