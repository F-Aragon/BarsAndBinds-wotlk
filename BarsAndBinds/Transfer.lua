--[[
	Export / import of profiles.

	Export string format:  BNB1:<checksum>:<base64 of the serialized data>
	  - one single string holds every selected profile (action bars and key bindings)
	  - it is plain ASCII, so it survives copy / paste in the game's edit boxes
	  - imported text is NEVER executed: it goes through a small parser and every
	    field is validated and copied into fresh tables before it is stored
]]
local addonName, BB = ...
local L = BB.L

local Transfer = {}
BB.Transfer = Transfer

local PREFIX = "BNB1"
local MAX_TEXT = 4000000
local MAX_BINDINGS = 3000
local MAX_ACTION_BUTTONS = 144
local MAX_NAME = 40

---------------------------------------------------------------------
-- Serialization (length prefixed, so any byte is safe inside strings)
--   s<len>:<bytes>   string
--   n<number>;       number
--   T / F            booleans
--   { key value ... }  table
---------------------------------------------------------------------
local function serialize(value, out)
	local kind = type(value)
	if kind == "string" then
		out[#out + 1] = "s" .. #value .. ":" .. value
	elseif kind == "number" then
		out[#out + 1] = "n" .. string.format("%.14g", value) .. ";"
	elseif kind == "boolean" then
		out[#out + 1] = value and "T" or "F"
	elseif kind == "table" then
		out[#out + 1] = "{"
		for k, v in pairs(value) do
			local vt = type(v)
			if vt == "string" or vt == "number" or vt == "boolean" or vt == "table" then
				serialize(k, out)
				serialize(v, out)
			end
		end
		out[#out + 1] = "}"
	end
end

-- Returns value, nextPosition. Raises an error on malformed data.
local function parseValue(s, pos, depth)
	if depth > 10 then error("too deep") end

	local c = string.sub(s, pos, pos)
	if c == "s" then
		local len, start = string.match(s, "^(%d+):()", pos + 1)
		if not len then error("bad string") end
		local stop = start + tonumber(len) - 1
		if stop > #s then error("truncated") end
		return string.sub(s, start, stop), stop + 1

	elseif c == "n" then
		local num, nextPos = string.match(s, "^([%+%-%d%.eE]+);()", pos + 1)
		num = num and tonumber(num)
		if not num then error("bad number") end
		return num, nextPos

	elseif c == "T" then
		return true, pos + 1

	elseif c == "F" then
		return false, pos + 1

	elseif c == "{" then
		local tbl = {}
		pos = pos + 1
		while string.sub(s, pos, pos) ~= "}" do
			if pos > #s then error("truncated") end
			local key, val
			key, pos = parseValue(s, pos, depth + 1)
			if type(key) ~= "string" and type(key) ~= "number" then error("bad key") end
			val, pos = parseValue(s, pos, depth + 1)
			tbl[key] = val
		end
		return tbl, pos + 1
	end

	error("unexpected data")
end

---------------------------------------------------------------------
-- Base64 + checksum
---------------------------------------------------------------------
local B64 = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
local encodeMap, decodeMap = {}, {}
for i = 1, 64 do
	local ch = string.sub(B64, i, i)
	encodeMap[i - 1] = ch
	decodeMap[string.byte(ch)] = i - 1
end

local function base64Encode(data)
	local out = {}
	for i = 1, #data, 3 do
		local a, b, c = string.byte(data, i, i + 2)
		local n = a * 65536 + (b or 0) * 256 + (c or 0)
		out[#out + 1] = encodeMap[math.floor(n / 262144) % 64]
			.. encodeMap[math.floor(n / 4096) % 64]
			.. (b and encodeMap[math.floor(n / 64) % 64] or "=")
			.. (c and encodeMap[n % 64] or "=")
	end
	return table.concat(out)
end

local function base64Decode(text)
	local len = #text
	if len == 0 or len % 4 ~= 0 then return nil end

	local out = {}
	for i = 1, len, 4 do
		local c1, c2, c3, c4 = string.byte(text, i, i + 3)
		local v1, v2, v3, v4 = decodeMap[c1], decodeMap[c2], decodeMap[c3], decodeMap[c4]
		local pad3, pad4 = (c3 == 61), (c4 == 61)   -- 61 = "="

		if not v1 or not v2 then return nil end
		if pad3 and not pad4 then return nil end
		if (pad3 or pad4) and i + 3 ~= len then return nil end
		if not pad3 and not v3 then return nil end
		if not pad4 and not v4 then return nil end

		local n = v1 * 262144 + v2 * 4096 + (v3 or 0) * 64 + (v4 or 0)
		local b1 = math.floor(n / 65536)
		local b2 = math.floor(n / 256) % 256
		local b3 = n % 256

		if pad3 then
			out[#out + 1] = string.char(b1)
		elseif pad4 then
			out[#out + 1] = string.char(b1, b2)
		else
			out[#out + 1] = string.char(b1, b2, b3)
		end
	end
	return table.concat(out)
end

-- Adler-32 style, detects truncated / damaged text
local function checksum(data)
	local a, b = 1, 0
	for i = 1, #data do
		a = (a + string.byte(data, i)) % 65521
		b = (b + a) % 65521
	end
	return string.format("%04x%04x", b, a)
end

---------------------------------------------------------------------
-- Listing
---------------------------------------------------------------------
-- Every saved profile: {id, kind = "bars"|"keys", class, name, meta, label}
function Transfer:GetAvailable()
	local items = {}

	local classes = BB.SortedKeys(BB.db.bars.sets)
	-- Your own class first
	for i, class in ipairs(classes) do
		if class == BB.playerClass then
			table.remove(classes, i)
			table.insert(classes, 1, class)
			break
		end
	end

	for _, class in ipairs(classes) do
		for _, name in ipairs(BB.SortedKeys(BB.db.bars.sets[class])) do
			local set = BB.db.bars.sets[class][name]
			table.insert(items, {
				id = "bars:" .. class .. ":" .. name,
				kind = "bars", class = class, name = name,
				meta = type(set) == "table" and set.meta or nil,
				label = string.format("|cff33ff99Bars|r (%s): %s", L[class], name),
			})
		end
	end

	for _, name in ipairs(BB.SortedKeys(BB.db.keys.sets)) do
		local list = BB.db.keys.sets[name]
		table.insert(items, {
			id = "keys:" .. name,
			kind = "keys", name = name,
			meta = type(list) == "table" and list.meta or nil,
			label = string.format("|cff66ccffKeys|r: %s", name),
		})
	end

	return items
end

---------------------------------------------------------------------
-- Export
---------------------------------------------------------------------
-- items: entries from GetAvailable(). Returns text, numBars, numKeys
function Transfer:Export(items)
	local payload = {v = 1, bars = {}, keys = {}}
	local numBars, numKeys = 0, 0

	for _, item in ipairs(items) do
		if item.kind == "bars" then
			local classSets = BB.db.bars.sets[item.class]
			local set = classSets and classSets[item.name]
			if set then
				payload.bars[item.class] = payload.bars[item.class] or {}
				payload.bars[item.class][item.name] = set
				numBars = numBars + 1
			end
		elseif item.kind == "keys" then
			local list = BB.db.keys.sets[item.name]
			if list then
				payload.keys[item.name] = list
				numKeys = numKeys + 1
			end
		end
	end

	local out = {}
	serialize(payload, out)
	local data = table.concat(out)

	return string.format("%s:%s:%s", PREFIX, checksum(data), base64Encode(data)), numBars, numKeys
end

---------------------------------------------------------------------
-- Import: validation
---------------------------------------------------------------------
local ALLOWED_TYPES = {spell = true, item = true, macro = true, companion = true, equipmentset = true}

local function cleanString(value, maxLen)
	if type(value) == "string" and #value <= maxLen then
		return value
	end
	return nil
end

local function cleanEntry(entry)
	if type(entry) ~= "table" or not ALLOWED_TYPES[entry.type] then return nil end

	local clean = {type = entry.type}

	if type(entry.id) == "number" then
		clean.id = entry.id
	else
		clean.id = cleanString(entry.id, 200)
	end
	if clean.id == nil then return nil end

	if type(entry.spellID) == "number" and entry.spellID >= 1 and entry.spellID < 10000000 then
		clean.spellID = math.floor(entry.spellID)
	end

	clean.name = cleanString(entry.name, 200)
	clean.rank = cleanString(entry.rank, 100)
	clean.subType = cleanString(entry.subType, 50)
	clean.icon = cleanString(entry.icon, 300)
	clean.body = cleanString(entry.body, 2000)

	if entry.type == "spell" and not clean.name then return nil end
	if entry.type == "macro" and not clean.body then return nil end
	if entry.type == "companion" and not clean.subType then return nil end

	return clean
end

local function cleanMeta(meta)
	if type(meta) ~= "table" then return nil end

	local clean = {
		char = cleanString(meta.char, 50),
		realm = cleanString(meta.realm, 50),
		class = cleanString(meta.class, 20),
	}
	if clean.class and not string.match(clean.class, "^%u+$") then
		clean.class = nil
	end
	if type(meta.created) == "number" and meta.created > 0 and meta.created < 4102444800 then
		clean.created = math.floor(meta.created)
	end
	return clean
end

local function cleanSet(set)
	if type(set) ~= "table" then return nil end

	local clean = {}
	for slot, entry in pairs(set) do
		if type(slot) == "number" and slot >= 1 and slot <= MAX_ACTION_BUTTONS and slot == math.floor(slot) then
			local cleanOne = cleanEntry(entry)
			if cleanOne then clean[slot] = cleanOne end
		end
	end
	clean.meta = cleanMeta(set.meta)
	return clean
end

local function cleanKeys(list)
	if type(list) ~= "table" then return nil end

	local clean, count = {}, 0
	for _, binding in pairs(list) do
		if type(binding) == "table" then
			local command = cleanString(binding.command, 100)
			local key1 = cleanString(binding.key1, 50)
			local key2 = cleanString(binding.key2, 50)
			if command and command ~= "" and (key1 or key2) then
				count = count + 1
				if count > MAX_BINDINGS then break end
				table.insert(clean, {command = command, key1 = key1, key2 = key2})
			end
		end
	end
	clean.meta = cleanMeta(list.meta)
	return clean
end

local function cleanName(name)
	if type(name) ~= "string" then return nil end
	name = BB:NormalizeName(string.sub(name, 1, MAX_NAME))
	if name == "" then return nil end
	return name
end

local ERR_FORMAT = "That text is not a Bars & Binds export string."
local ERR_CORRUPT = "The text is incomplete or damaged. Make sure you copied the whole string."
local ERR_UNREADABLE = "The data inside the string could not be read."
local ERR_EMPTY = "There are no profiles in that text."

-- Returns data, or nil + error message.
-- data = {bars = {[class] = {[name] = set}}, keys = {[name] = list}, numBars, numKeys}
function Transfer:Parse(text)
	text = string.gsub(text or "", "%s", "")
	if text == "" then
		return nil, "Paste an export string first."
	elseif #text > MAX_TEXT then
		return nil, ERR_FORMAT
	end

	local sum, body = string.match(text, "^" .. PREFIX .. ":(%x%x%x%x%x%x%x%x):([%w%+/=]+)$")
	if not sum then
		return nil, ERR_FORMAT
	end

	local raw = base64Decode(body)
	if not raw or checksum(raw) ~= string.lower(sum) then
		return nil, ERR_CORRUPT
	end

	local ok, payload, nextPos = pcall(parseValue, raw, 1, 0)
	if not ok or type(payload) ~= "table" or nextPos ~= #raw + 1 or payload.v ~= 1 then
		return nil, ERR_UNREADABLE
	end

	local data = {bars = {}, keys = {}, numBars = 0, numKeys = 0}

	if type(payload.bars) == "table" then
		for class, sets in pairs(payload.bars) do
			if type(class) == "string" and string.match(class, "^%u+$") and #class <= 20 and type(sets) == "table" then
				for name, set in pairs(sets) do
					local cleanProfile, key = cleanSet(set), cleanName(name)
					if cleanProfile and key then
						data.bars[class] = data.bars[class] or {}
						if not data.bars[class][key] then data.numBars = data.numBars + 1 end
						data.bars[class][key] = cleanProfile
					end
				end
			end
		end
	end

	if type(payload.keys) == "table" then
		for name, list in pairs(payload.keys) do
			local cleanProfile, key = cleanKeys(list), cleanName(name)
			if cleanProfile and key then
				if not data.keys[key] then data.numKeys = data.numKeys + 1 end
				data.keys[key] = cleanProfile
			end
		end
	end

	if data.numBars + data.numKeys == 0 then
		return nil, ERR_EMPTY
	end

	return data
end

---------------------------------------------------------------------
-- Import: apply
---------------------------------------------------------------------
-- How many profiles in data already exist (and would be overwritten)
function Transfer:CountCollisions(data)
	local count = 0

	for class, sets in pairs(data.bars) do
		local existing = BB.db.bars.sets[class]
		if existing then
			for name in pairs(sets) do
				if existing[name] then count = count + 1 end
			end
		end
	end

	for name in pairs(data.keys) do
		if BB.db.keys.sets[name] then count = count + 1 end
	end

	return count
end

function Transfer:Apply(data)
	for class, sets in pairs(data.bars) do
		BB.db.bars.sets[class] = BB.db.bars.sets[class] or {}
		for name, set in pairs(sets) do
			BB.db.bars.sets[class][name] = set
		end
	end

	for name, list in pairs(data.keys) do
		BB.db.keys.sets[name] = list
	end

	BB:Fire("BARS_CHANGED")
	BB:Fire("KEYS_CHANGED")
	return data.numBars, data.numKeys
end
