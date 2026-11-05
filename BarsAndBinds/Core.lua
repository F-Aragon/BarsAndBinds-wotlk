--[[
	Bars & Binds
	Merge of Action Bar Saver (Shadowed) and Key Bindings Profiler (zimeng).

	Layout:
	  Core.lua   - namespace, saved variables, callbacks, helpers
	  Bars.lua   - action bar profiles   (BB.Bars)
	  Keys.lua   - key binding profiles  (BB.Keys)
	  UI.lua     - main window (/bnb)
	  Slash.lua  - chat commands (/bnb bars, /bnb keys)

	A future UI should only use the public API of BB.Bars / BB.Keys and listen
	to callbacks via BB:RegisterCallback(event, func):
	  "LOADED", "BARS_CHANGED", "KEYS_CHANGED"
]]
local addonName, BB = ...
_G.BarsAndBinds = BB

local L = setmetatable(BB.locals or {}, {__index = function(_, key) return key end})
BB.L = L

local defaults = {
	bars = {
		macro = true,        -- recreate missing macros on restore
		checkCount = true,   -- check the item is in the bags before restoring it
		restoreRank = true,  -- restore the highest rank of a spell
		spellSubs = {},      -- linked spells
		sets = {},           -- sets[CLASS][profile] = { [slot] = entry }
	},
	keys = {
		sets = {},           -- sets[profile] = { {command=, key1=, key2=}, ... }
	},
}

local function copyDefaults(src, dst)
	for key, value in pairs(src) do
		if type(value) == "table" then
			if type(dst[key]) ~= "table" then dst[key] = {} end
			copyDefaults(value, dst[key])
		elseif dst[key] == nil then
			dst[key] = value
		end
	end
end

-- Callbacks
local callbacks = {}

function BB:RegisterCallback(event, func)
	callbacks[event] = callbacks[event] or {}
	table.insert(callbacks[event], func)
end

function BB:Fire(event, ...)
	if callbacks[event] then
		for _, func in ipairs(callbacks[event]) do
			func(event, ...)
		end
	end
end

-- Helpers
function BB:Print(msg)
	DEFAULT_CHAT_FRAME:AddMessage("|cff33ff99BarsAndBinds|r: " .. msg)
end

-- Profile names are case insensitive
function BB:NormalizeName(name)
	return string.lower(strtrim(name or ""))
end

-- Creation data stored inside every profile
function BB:NewMeta()
	return {
		char = UnitName("player"),
		realm = GetRealmName(),
		class = BB.playerClass,
		created = time(),
	}
end

function BB.SortedKeys(tbl)
	local list = {}
	for key in pairs(tbl) do
		table.insert(list, key)
	end
	table.sort(list)
	return list
end

-- Init
local frame = CreateFrame("Frame")
frame:RegisterEvent("ADDON_LOADED")
frame:SetScript("OnEvent", function(self, event, name)
	if name ~= addonName then return end
	self:UnregisterEvent("ADDON_LOADED")

	BarsAndBindsDB = BarsAndBindsDB or {}
	copyDefaults(defaults, BarsAndBindsDB)

	BB.db = BarsAndBindsDB
	BB.playerClass = select(2, UnitClass("player"))
	BB:Fire("LOADED")
end)
