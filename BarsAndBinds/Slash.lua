--[[
	Chat commands.
	  /bnb             - open the window
	  /bnb bars <cmd>  - action bar profiles
	  /bnb keys <cmd>  - key binding profiles
]]
local addonName, BB = ...
local L = BB.L

local function parse(msg)
	local cmd, rest = string.match(msg or "", "^%s*(%S*)%s*(.-)%s*$")
	return string.lower(cmd or ""), rest or ""
end

local function say(msg)
	DEFAULT_CHAT_FRAME:AddMessage(msg)
end

local function ready()
	if not BB.db then
		BB:Print("Addon is not loaded yet.")
		return false
	end
	return true
end

---------------------------------------------------------------------
-- Action bars
---------------------------------------------------------------------
local function barsHelp()
	BB:Print(L["Slash commands"])
	say("/bnb bars save <profile> - Saves your current action bar setup under the given profile.")
	say("/bnb bars restore <profile> - Changes your action bars to the passed profile.")
	say("/bnb bars delete <profile> - Deletes the saved profile.")
	say("/bnb bars rename <oldProfile> <newProfile> - Renames a saved profile.")
	say("/bnb bars list - Lists all saved profiles.")
	say("/bnb bars errors - Lists the errors that happened on the last restore (if any).")
	say("/bnb bars link \"<spell 1>\" \"<spell 2>\" - Links two spells, INCLUDE QUOTES. If one can't be found the other is used.")
	say("/bnb bars macro - Toggles restoring macros that have been deleted.")
	say("/bnb bars count - Toggles checking the item is in your bags before restoring it.")
	say("/bnb bars rank - Toggles restoring the highest spell rank instead of the saved one.")
end

local function barsCommand(msg)
	if not ready() then return end
	local Bars = BB.Bars
	local cmd, arg = parse(msg)
	local name = BB:NormalizeName(arg)

	if cmd == "save" and name ~= "" then
		Bars:Save(name)

	elseif cmd == "restore" and name ~= "" then
		Bars:Restore(name)

	elseif cmd == "delete" and name ~= "" then
		Bars:Delete(name)

	elseif cmd == "rename" and name ~= "" then
		local old, new = string.match(name, "^(%S+)%s+(.+)$")
		Bars:Rename(old or name, new or "")

	elseif cmd == "link" and arg ~= "" then
		local first, second = string.match(string.lower(arg), "\"(.-)\"%s+\"(.-)\"")
		Bars:Link(strtrim(first or ""), strtrim(second or ""))

	elseif cmd == "errors" then
		if #Bars.errors == 0 then
			BB:Print(L["No errors found!"])
		else
			BB:Print(string.format(L["Errors found: %d"], #Bars.errors))
			for _, text in ipairs(Bars.errors) do
				say(text)
			end
		end

	elseif cmd == "list" then
		local classes = BB.SortedKeys(BB.db.bars.sets)
		for _, class in ipairs(classes) do
			local names = Bars:GetProfileNames(class)
			if #names > 0 then
				say(string.format("|cff33ff99%s|r: %s", L[class], table.concat(names, ", ")))
			end
		end

	elseif cmd == "macro" then
		Bars:ToggleOption("macro")
	elseif cmd == "count" then
		Bars:ToggleOption("checkCount")
	elseif cmd == "rank" then
		Bars:ToggleOption("restoreRank")

	else
		barsHelp()
	end
end

---------------------------------------------------------------------
-- Key bindings
---------------------------------------------------------------------
local function keysHelp()
	BB:Print("Key Bindings commands:")
	say("/bnb keys save <profile> - Save your current key bindings.")
	say("/bnb keys restore <profile> - Restore your key bindings.")
	say("/bnb keys rename <old> <new> - Rename a profile.")
	say("/bnb keys list - List your key binding profiles on this account.")
	say("/bnb keys delete <profile> - Delete a profile.")
	say("/bnb keys clear - Delete all saved key binding profiles.")
end

local function keysCommand(msg)
	if not ready() then return end
	local Keys = BB.Keys
	local cmd, arg = parse(msg)
	local name = BB:NormalizeName(arg)

	if cmd == "save" and name ~= "" then
		Keys:Save(name)
	elseif cmd == "restore" and name ~= "" then
		Keys:Restore(name)
	elseif cmd == "delete" and name ~= "" then
		Keys:Delete(name)
	elseif cmd == "rename" and name ~= "" then
		local old, new = string.match(name, "^(%S+)%s+(.+)$")
		Keys:Rename(old or name, new or "")
	elseif cmd == "list" then
		BB:Print(L["Key Binding List:"])
		for _, profile in ipairs(Keys:GetProfileNames()) do
			say(profile)
		end
	elseif cmd == "clear" then
		Keys:Clear()
	else
		keysHelp()
	end
end

---------------------------------------------------------------------
-- Registration
---------------------------------------------------------------------
SLASH_BARSANDBINDS1 = "/bnb"
SlashCmdList["BARSANDBINDS"] = function(msg)
	local section, rest = parse(msg)
	if section == "bars" then
		barsCommand(rest)
	elseif section == "keys" then
		keysCommand(rest)
	elseif section == "" or section == "ui" then
		BB.UI:Toggle()
	else
		BB:Print("/bnb - open the window")
		BB:Print("/bnb bars <cmd> - action bar profiles")
		BB:Print("/bnb keys <cmd> - key binding profiles")
	end
end
