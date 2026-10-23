-- Base64 (RFC 4648): Gmail returns bodies and attachments as base64url; MIME parts use standard base64.
-- Buffers keep memory proportional to the data, which can be several megabytes.
local ALPHABET = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
local PAD, CR, LF = string.byte("="), 13, 10
local CODES: {[number]: number} = {}
local VALUES: {[number]: number} = {[string.byte("-")] = 62, [string.byte("_")] = 63}
for i = 1, 64 do
	CODES[i - 1] = string.byte(ALPHABET, i)
	VALUES[string.byte(ALPHABET, i)] = i - 1
end

-- wrap breaks the output into 76-character MIME lines.
local function encode(data: string, wrap: boolean?): string
	local size = (#data + 2) // 3 * 4
	local out = buffer.create(if wrap and size > 0 then size + (size - 1) // 76 * 2 else size)
	local position, column = 0, 0
	for i = 1, #data, 3 do
		local a, b, c = string.byte(data, i, i + 2)
		local n = a * 65536 + (b or 0) * 256 + (c or 0)
		buffer.writeu8(out, position, CODES[n // 262144])
		buffer.writeu8(out, position + 1, CODES[n // 4096 % 64])
		buffer.writeu8(out, position + 2, if b then CODES[n // 64 % 64] else PAD)
		buffer.writeu8(out, position + 3, if c then CODES[n % 64] else PAD)
		position, column = position + 4, column + 4
		if wrap and column == 76 and i + 3 <= #data then
			buffer.writeu8(out, position, CR)
			buffer.writeu8(out, position + 1, LF)
			position, column = position + 2, 0
		end
	end
	return buffer.tostring(out)
end

-- Accepts both alphabets, with or without padding and line breaks.
local function decode(data: string): string
	local clean = string.gsub(data, "[%s=]", "")
	local length = #clean
	assert(length % 4 ~= 1, "invalid base64 data")
	local out = buffer.create(length // 4 * 3 + math.max(length % 4 - 1, 0))
	local position = 0
	for i = 1, length, 4 do
		local a, b, c, d = string.byte(clean, i, i + 3)
		local va, vb = VALUES[a], VALUES[b]
		local vc, vd = if c then VALUES[c] else 0, if d then VALUES[d] else 0
		assert(va and vb and vc and vd, "invalid base64 data")
		local n = va * 262144 + vb * 4096 + vc * 64 + vd
		buffer.writeu8(out, position, n // 65536)
		if c then buffer.writeu8(out, position + 1, n // 256 % 256) end
		if d then buffer.writeu8(out, position + 2, n % 256) end
		position += 3
	end
	return buffer.tostring(out)
end

return {encode = encode, decode = decode}
