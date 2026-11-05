--[[
	Key binding profiles (from Key Bindings Profiler by zimeng).

	Storage: db.keys.sets[profile] = { {command = "", key1 = "", key2 = ""}, ... }
	Profiles are account wide.
]]
local addonName, BB = ...
local L = BB.L

local Keys = {}
BB.Keys = Keys

function Keys:GetSets()
	return BB.db.keys.sets
end

function Keys:GetProfileNames()
	return BB.SortedKeys(self:GetSets())
end

function Keys:GetMeta(name)
	local list = self:GetSets()[name]
	return list and list.meta
end

function Keys:GetId(name)
	return name
end

-- Returns { {id, name, meta}, ... }  (key profiles have no class restriction)
function Keys:GetEntries()
	local entries = {}
	local sets = self:GetSets()

	for _, name in ipairs(BB.SortedKeys(sets)) do
		local list = sets[name]
		table.insert(entries, {
			id = name,
			name = name,
			meta = type(list) == "table" and list.meta or nil,
		})
	end

	return entries
end

function Keys:Save(name)
	local list = {}

	for i = 1, GetNumBindings() do
		local command, key1, key2 = GetBinding(i)
		if command and (key1 or key2) then
			table.insert(list, {command = command, key1 = key1, key2 = key2})
		end
	end

	list.meta = BB:NewMeta()
	self:GetSets()[name] = list
	SaveBindings(GetCurrentBindingSet())

	BB:Print(string.format(L["Saved key binding profile %s!"], name))
	BB:Fire("KEYS_CHANGED")
	return true, #list
end

-- Returns the number of bindings applied
function Keys:Restore(name)
	local list = self:GetSets()[name]
	if not list then
		BB:Print(string.format(L["No key binding profile with the name \"%s\" exists."], name))
		return false
	elseif InCombatLockdown() then
		BB:Print(string.format(L["Unable to restore key binding profile \"%s\", you are in combat."], name))
		return false
	end

	-- Unbind everything first so the result matches the profile exactly
	for i = 1, GetNumBindings() do
		local _, key1, key2 = GetBinding(i)
		if key1 then SetBinding(key1) end
		if key2 then SetBinding(key2) end
	end

	for _, binding in ipairs(list) do
		if binding.key1 then SetBinding(binding.key1, binding.command) end
		if binding.key2 then SetBinding(binding.key2, binding.command) end
	end

	SaveBindings(GetCurrentBindingSet())

	BB:Print(string.format(L["Restored key binding profile %s, binding count: %d."], name, #list))
	return true, #list
end

function Keys:Delete(name)
	local sets = self:GetSets()
	if not sets[name] then
		BB:Print(string.format(L["Failed to delete key binding profile %s."], name))
		return false
	end

	sets[name] = nil
	BB:Print(string.format(L["Deleted key binding profile %s."], name))
	BB:Fire("KEYS_CHANGED")
	return true
end

function Keys:Rename(old, new)
	local sets = self:GetSets()

	if new == "" or new == old then
		BB:Print(L["Invalid new name."])
	elseif sets[new] then
		BB:Print(string.format(L["A key binding profile named \"%s\" already exists."], new))
	elseif not sets[old] then
		BB:Print(string.format(L["No key binding profile with the name \"%s\" exists."], old))
	else
		sets[new] = sets[old]
		sets[old] = nil
		BB:Print(string.format(L["Renamed \"%s\" to \"%s\""], old, new))
		BB:Fire("KEYS_CHANGED")
		return true
	end
	return false
end

function Keys:Clear()
	table.wipe(self:GetSets())
	BB:Print(L["Saved key bindings on this account are cleared."])
	BB:Fire("KEYS_CHANGED")
end
