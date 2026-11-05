--[[
	Interface -> AddOns panel.
	Shows the addon information, credits and chat commands, plus a button
	that opens the main window (the same one /bnb opens).
]]
local addonName, BB = ...

local panel = CreateFrame("Frame", "BarsAndBindsOptions", UIParent)
panel.name = "Bars & Binds"
panel:Hide()

local texts = {}

-- Text blocks follow the width of the window (see fitText below)
local function addText(font, anchorTo, offsetY, text)
	local fs = panel:CreateFontString(nil, "ARTWORK", font)
	fs:SetPoint("TOPLEFT", anchorTo, "BOTTOMLEFT", 0, offsetY)
	table.insert(texts, fs)
	fs:SetJustifyH("LEFT")
	fs:SetJustifyV("TOP")
	fs:SetText(text)
	return fs
end

local function cmd(command, description)
	return string.format("|cffffd100%s|r - %s", command, description)
end

-- Title
local title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
title:SetPoint("TOPLEFT", panel, "TOPLEFT", 16, -16)
title:SetText("Bars & Binds")

local version = GetAddOnMetadata(addonName, "Version") or "1.0"
local versionText = addText("GameFontHighlightSmall", title, -6, "Version " .. version)

-- Information
local aboutHeader = addText("GameFontNormal", versionText, -14, "Information")
local about = addText("GameFontHighlight", aboutHeader, -6,
	"Save, restore, export and import your action bar and key binding profiles.\n" ..
	"Profiles are stored account wide. Action bar profiles can only be restored by the class that saved them; key binding profiles can be restored by any character.")

-- Credits
local creditsHeader = addText("GameFontNormal", about, -14, "Credits")
local credits = addText("GameFontHighlight", creditsHeader, -6,
	"Created by |cff33ff99Chupanki|r.\n" ..
	"Based on |cffffd100Action Bar Saver|r by Shadowed (action bar profiles).\n" ..
	"Based on |cffffd100Key Bindings Profiler|r by zimeng (key binding profiles).")

-- Commands
local commandsHeader = addText("GameFontNormal", credits, -14, "Commands")
local commands = addText("GameFontHighlight", commandsHeader, -6, table.concat({
	cmd("/bnb", "Opens the main window."),
	cmd("/bnb bars", "Shows the action bar commands and their options."),
	cmd("/bnb keys", "Shows the key binding commands and their options."),
}, "\n"))
commands:SetSpacing(3)

-- Button that opens the main window
local open = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
open:SetWidth(200)
open:SetHeight(24)
open:SetPoint("TOPLEFT", commands, "BOTTOMLEFT", 0, -18)
open:SetText("Open Bars & Binds")
open:SetScript("OnClick", function()
	if not BB.db then
		BB:Print("Addon is not loaded yet.")
		return
	end

	-- Close the options window and the game menu so they do not cover the addon window
	HideUIPanel(InterfaceOptionsFrame)
	HideUIPanel(GameMenuFrame)

	if not BB.UI.frame then BB.UI:Create() end
	BB.UI.frame:Show()
end)

-- Resize the text blocks so they wrap to the current width of the window
local function fitText()
	local width = panel:GetWidth() - 32
	if width < 100 then return end
	for _, fs in ipairs(texts) do
		fs:SetWidth(width)
	end
end
panel:SetScript("OnShow", fitText)
panel:SetScript("OnSizeChanged", fitText)

InterfaceOptions_AddCategory(panel)
