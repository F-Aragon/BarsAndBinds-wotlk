--[[
	Action bar profiles (from Action Bar Saver by Shadowed).

	Storage: db.bars.sets[CLASS][profile][slot] = {
		type = "spell"|"item"|"macro"|"companion"|"equipmentset",
		id, name, rank, spellID, icon, body, subType
	}
]]
local addonName, BB = ...
local L = BB.L

local Bars = {}
BB.Bars = Bars

local MAX_MACROS = 54
local MAX_CHAR_MACROS = 18
local MAX_GLOBAL_MACROS = 36
local MAX_ACTION_BUTTONS = 144
local POSSESSION_START = 121
local POSSESSION_END = 132

local errors = {}
Bars.errors = errors

local spellCache, macroCache, macroNameCache = {}, {}, {}
local spellIDCache = {}   -- spell id -> spellbook index
local iconCache

local function skipSlot(slot)
	return slot >= POSSESSION_START and slot <= POSSESSION_END
end

---------------------------------------------------------------------
-- Data access (used by the slash commands and by a future UI)
---------------------------------------------------------------------
function Bars:GetSets(class)
	class = class or BB.playerClass
	local all = BB.db.bars.sets
	all[class] = all[class] or {}
	return all[class]
end

function Bars:GetProfileNames(class)
	return BB.SortedKeys(self:GetSets(class))
end

function Bars:GetMeta(name, class)
	local set = self:GetSets(class)[name]
	return set and set.meta
end

-- Unique id of a profile inside the UI list (the same name can exist in two classes)
function Bars:GetId(name, class)
	return (class or BB.playerClass) .. ":" .. name
end

-- Every saved profile of every class, your own class first.
-- Returns { {id, name, class, meta}, ... }
function Bars:GetEntries()
	local entries = {}
	local classes = BB.SortedKeys(BB.db.bars.sets)

	for i, class in ipairs(classes) do
		if class == BB.playerClass then
			table.remove(classes, i)
			table.insert(classes, 1, class)
			break
		end
	end

	for _, class in ipairs(classes) do
		local sets = BB.db.bars.sets[class]
		for _, name in ipairs(BB.SortedKeys(sets)) do
			local set = sets[name]
			table.insert(entries, {
				id = self:GetId(name, class),
				name = name,
				class = class,
				meta = type(set) == "table" and set.meta or nil,
			})
		end
	end

	return entries
end

function Bars:GetOptions()
	return BB.db.bars
end

function Bars:HasProfile(name, class)
	return self:GetSets(class)[name] ~= nil
end

---------------------------------------------------------------------
-- Save
---------------------------------------------------------------------
function Bars:Save(name)
	local set = {}

	for slot = 1, MAX_ACTION_BUTTONS do
		if not skipSlot(slot) then
			local type, id, subType = GetActionInfo(slot)
			if type and id then
				if type == "companion" then
					local _, creatureName = GetCompanionInfo(subType, id)
					set[slot] = {type = type, id = id, subType = subType, name = creatureName}
				elseif type == "equipmentset" then
					set[slot] = {type = type, id = id}
				elseif type == "item" then
					set[slot] = {type = type, id = id, name = (GetItemInfo(id))}
				elseif type == "spell" and id > 0 then
					local spell, rank = GetSpellName(id, BOOKTYPE_SPELL)
					if spell then
						-- The spell id is the same in every client language (the name is not)
						local link = GetSpellLink(id, BOOKTYPE_SPELL)
						local spellID = link and tonumber(string.match(link, "spell:(%d+)"))
						set[slot] = {
							type = type, id = id, name = spell,
							rank = (rank ~= "" and rank) or nil,
							spellID = spellID,
						}
					end
				elseif type == "macro" then
					local macroName, icon, body = GetMacroInfo(id)
					if macroName and icon and body then
						set[slot] = {type = type, id = id, name = macroName, icon = icon, body = body}
					end
				end
			end
		end
	end

	set.meta = BB:NewMeta()
	self:GetSets()[name] = set
	BB:Print(string.format(L["Saved profile %s!"], name))
	BB:Fire("BARS_CHANGED")
	return true
end

---------------------------------------------------------------------
-- Caches
---------------------------------------------------------------------
local function cacheMacros()
	table.wipe(macroCache)
	table.wipe(macroNameCache)

	local blacklist = {}
	for i = 1, MAX_MACROS do
		local name, _, body = GetMacroInfo(i)
		if name then
			macroCache[i] = body
			-- Duplicated names can't be used to find a macro
			if blacklist[name] then
				-- nothing
			elseif macroNameCache[name] then
				macroNameCache[name] = nil
				blacklist[name] = true
			else
				macroNameCache[name] = i
			end
		end
	end
end

local function cacheSpells()
	table.wipe(spellCache)
	table.wipe(spellIDCache)

	for book = 1, MAX_SKILLLINE_TABS do
		local _, _, offset, numSpells = GetSpellTabInfo(book)
		for i = 1, numSpells or 0 do
			local index = offset + i
			local spell, rank = GetSpellName(index, BOOKTYPE_SPELL)
			if spell then
				-- Later entries are higher ranks, so this keeps the max rank
				spellCache[spell] = index
				local link = GetSpellLink(index, BOOKTYPE_SPELL)
				local spellID = link and tonumber(string.match(link, "spell:(%d+)"))
				if spellID then spellIDCache[spellID] = index end
				spellCache[string.lower(spell)] = index
				if rank and rank ~= "" then
					spellCache[spell .. rank] = index
				end
			end
		end
	end
end

---------------------------------------------------------------------
-- Macros
---------------------------------------------------------------------
function Bars:FindMacro(entry)
	if macroCache[entry.id] == entry.body then
		return entry.id
	end

	for id, body in pairs(macroCache) do
		if body == entry.body then
			return id
		end
	end

	return macroNameCache[entry.name]
end

function Bars:RestoreMacros(set)
	local perCharacter = true

	for _, entry in pairs(set) do
		if entry.type == "macro" and not self:FindMacro(entry) then
			local globalNum, charNum = GetNumMacros()
			if globalNum >= MAX_GLOBAL_MACROS and charNum >= MAX_CHAR_MACROS then
				table.insert(errors, L["Unable to restore macros, you already have 18 global and 18 per character ones created."])
				break
			elseif charNum >= MAX_CHAR_MACROS then
				perCharacter = false
			end

			-- CreateMacro wants the icon index, not the path
			if not iconCache then
				iconCache = {}
				for i = 1, GetNumMacroIcons() do
					iconCache[(GetMacroIconInfo(i))] = i
				end
			end

			-- A macro without a name must use a space or it won't be saved
			local name = (entry.name and entry.name ~= "") and entry.name or " "
			CreateMacro(name, iconCache[entry.icon] or 1, entry.body, nil, perCharacter)
			cacheMacros()
		end
	end
end

---------------------------------------------------------------------
-- Restore
---------------------------------------------------------------------
function Bars:RestoreSpell(slot, name, rank, spellID, tried)
	local opts = BB.db.bars
	local index

	-- 1) By spell id: works even if the profile was saved in another client language
	local byID = spellID and spellIDCache[spellID]
	if byID then
		if opts.restoreRank then
			-- Use the local name of that spell to find its highest known rank
			local localName = GetSpellName(byID, BOOKTYPE_SPELL)
			index = (localName and spellCache[localName]) or byID
		else
			index = byID
		end
	end

	-- 2) By name (profiles saved before spell ids were stored, or spell not found by id)
	if not index then
		if (opts.restoreRank or not rank) and spellCache[name] then
			index = spellCache[name]
		elseif rank and spellCache[name .. rank] then
			index = spellCache[name .. rank]
		end
	end

	if index then
		PickupSpell(index, BOOKTYPE_SPELL)
	end

	if GetCursorInfo() == "spell" then
		PlaceAction(slot)
		return true
	end

	-- Bad restore, try the linked spells
	tried = tried or {}
	local lower = string.lower(name)
	tried[lower] = true

	for spell, linked in pairs(opts.spellSubs) do
		local alt
		if lower == spell then alt = linked elseif lower == linked then alt = spell end
		if alt and not tried[alt] and spellCache[alt] then
			return self:RestoreSpell(slot, alt, nil, nil, tried)
		end
	end

	table.insert(errors, string.format(L["Unable to restore spell \"%s\" to slot #%d, it does not appear to have been learned yet."], name, slot))
	ClearCursor()
	return false
end

function Bars:RestoreAction(slot, entry)
	local type = entry.type

	if type == "spell" then
		return self:RestoreSpell(slot, entry.name, entry.rank, entry.spellID)

	elseif type == "equipmentset" then
		local index = -1
		for j = 1, GetNumEquipmentSets() do
			if GetEquipmentSetInfo(j) == entry.id then
				index = j
				break
			end
		end

		PickupEquipmentSet(index)
		if GetCursorInfo() ~= "equipmentset" then
			table.insert(errors, string.format(L["Unable to restore equipment set \"%s\" to slot #%d, it does not appear to exist anymore."], entry.id, slot))
			ClearCursor()
			return false
		end

	elseif type == "companion" then
		PickupCompanion(entry.subType, entry.id)
		if GetCursorInfo() ~= "companion" then
			table.insert(errors, string.format(L["Unable to restore companion \"%s\" to slot #%d, it does not appear to exist yet."], entry.name or entry.id, slot))
			ClearCursor()
			return false
		end

	elseif type == "item" then
		local missing = BB.db.bars.checkCount and GetItemCount(entry.id) == 0
		if not missing then
			PickupItem(entry.id)
		end
		if missing or GetCursorInfo() ~= "item" then
			local label = (entry.name and entry.name ~= "") and entry.name or entry.id
			table.insert(errors, string.format(L["Unable to restore item \"%s\" to slot #%d, cannot be found in inventory."], label, slot))
			ClearCursor()
			return false
		end

	elseif type == "macro" then
		local macroID = self:FindMacro(entry)
		if macroID then
			PickupMacro(macroID)
		end
		if not macroID or GetCursorInfo() ~= "macro" then
			table.insert(errors, string.format(L["Unable to restore macro id #%d to slot #%d, it appears to have been deleted."], entry.id, slot))
			ClearCursor()
			return false
		end

	else
		return false
	end

	PlaceAction(slot)
	return true
end

function Bars:Restore(name, class)
	class = class or BB.playerClass
	local set = self:GetSets(class)[name]

	table.wipe(errors)

	if not set then
		BB:Print(string.format(L["No profile with the name \"%s\" exists."], name))
		return false
	elseif class ~= BB.playerClass then
		BB:Print(string.format(L["Cannot restore profile \"%s\", you can only restore profiles saved to your class."], name))
		return false
	elseif InCombatLockdown() then
		BB:Print(string.format(L["Unable to restore profile \"%s\", you are in combat."], name))
		return false
	end

	cacheSpells()
	cacheMacros()

	if BB.db.bars.macro then
		self:RestoreMacros(set)
	end

	ClearCursor()

	-- Mute sounds while picking things up / placing them
	local soundToggle = GetCVar("Sound_EnableAllSound")
	SetCVar("Sound_EnableAllSound", 0)

	for slot = 1, MAX_ACTION_BUTTONS do
		if not skipSlot(slot) then
			local type, id = GetActionInfo(slot)
			if id or type then
				PickupAction(slot)
				ClearCursor()
			end

			if set[slot] then
				self:RestoreAction(slot, set[slot])
			end
		end
	end

	SetCVar("Sound_EnableAllSound", soundToggle)

	if #errors == 0 then
		BB:Print(string.format(L["Restored profile %s!"], name))
	else
		BB:Print(string.format(L["Restored profile %s, failed to restore %d buttons type /bnb bars errors for more information."], name, #errors))
	end
	return true, #errors
end

---------------------------------------------------------------------
-- Delete / rename / options
---------------------------------------------------------------------
function Bars:Delete(name, class)
	local sets = self:GetSets(class)
	if not sets[name] then
		BB:Print(string.format(L["No profile with the name \"%s\" exists."], name))
		return false
	end

	sets[name] = nil
	BB:Print(string.format(L["Deleted saved profile %s."], name))
	BB:Fire("BARS_CHANGED")
	return true
end

function Bars:Rename(old, new, class)
	local sets = self:GetSets(class)

	if new == old then
		BB:Print(string.format(L["You cannot rename \"%s\" to \"%s\" they are the same profile names."], old, new))
	elseif new == "" then
		BB:Print(string.format(L["No name specified to rename \"%s\" to."], old))
	elseif sets[new] then
		BB:Print(string.format(L["Cannot rename \"%s\" to \"%s\" a profile already exists for %s."], old, new, L[class or BB.playerClass]))
	elseif not sets[old] then
		BB:Print(string.format(L["No profile with the name \"%s\" exists."], old))
	else
		sets[new] = sets[old]
		sets[old] = nil
		BB:Print(string.format(L["Renamed \"%s\" to \"%s\""], old, new))
		BB:Fire("BARS_CHANGED")
		return true
	end
	return false
end

function Bars:Link(first, second)
	if first == "" or second == "" then
		BB:Print(L["Invalid spells passed, remember you must put quotes around both of them."])
		return false
	end

	BB.db.bars.spellSubs[first] = second
	BB:Print(string.format(L["Spells \"%s\" and \"%s\" are now linked."], first, second))
	return true
end

-- option: "macro", "checkCount" or "restoreRank"
local toggleMessages = {
	macro = {L["Auto macro restoration is now enabled!"], L["Auto macro restoration is now disabled!"]},
	checkCount = {L["Checking item count is now enabled!"], L["Checking item count is now disabled!"]},
	restoreRank = {L["Auto restoring highest spell rank is now enabled!"], L["Auto restoring highest spell rank is now disabled!"]},
}

function Bars:SetOption(option, value)
	BB.db.bars[option] = value and true or false
	local msg = toggleMessages[option]
	if msg then
		BB:Print(value and msg[1] or msg[2])
	end
end

function Bars:ToggleOption(option)
	self:SetOption(option, not BB.db.bars[option])
end
