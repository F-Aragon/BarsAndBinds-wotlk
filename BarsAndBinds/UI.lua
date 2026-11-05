--[[
	Main window, built with native frames (no libraries).
	Open it with /bnb

	The UI only talks to BB.Bars / BB.Keys (Save, Restore, Rename, Delete,
	GetProfileNames) and refreshes itself on the BARS_CHANGED / KEYS_CHANGED callbacks.
]]
local addonName, BB = ...
local L = BB.L

local UI = {}
BB.UI = UI

local ROWS = 9
local ROW_HEIGHT = 20
local FRAME_WIDTH, FRAME_HEIGHT = 520, 490
local LIST_WIDTH = FRAME_WIDTH - 40
local ROW_WIDTH = LIST_WIDTH - 34

local panels = {}
local tabs = {}
local pending = {}   -- panel/name of the confirmation popup being shown

---------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------
local function setEnabled(button, enabled)
	if enabled then button:Enable() else button:Disable() end
end

local function profileExists(panel, name)
	for _, existing in ipairs(panel.module:GetProfileNames()) do
		if existing == name then return true end
	end
	return false
end

-- Columns of the list: [type] | name | character | class | date
local COL_DATE, COL_CLASS, COL_CHAR, COL_TYPE = 54, 72, 90, 44

local function createColumns(parent, nameFont, smallFont, leftInset, withType)
	local c = {}
	leftInset = leftInset or 6

	c.date = parent:CreateFontString(nil, "ARTWORK", smallFont)
	c.date:SetPoint("RIGHT", parent, "RIGHT", -6, 0)
	c.date:SetWidth(COL_DATE)

	c.class = parent:CreateFontString(nil, "ARTWORK", smallFont)
	c.class:SetPoint("RIGHT", c.date, "LEFT", -8, 0)
	c.class:SetWidth(COL_CLASS)

	c.char = parent:CreateFontString(nil, "ARTWORK", smallFont)
	c.char:SetPoint("RIGHT", c.class, "LEFT", -8, 0)
	c.char:SetWidth(COL_CHAR)

	c.name = parent:CreateFontString(nil, "ARTWORK", nameFont)
	c.name:SetPoint("RIGHT", c.char, "LEFT", -8, 0)

	if withType then
		c.type = parent:CreateFontString(nil, "ARTWORK", smallFont)
		c.type:SetPoint("LEFT", parent, "LEFT", leftInset, 0)
		c.type:SetWidth(COL_TYPE)
		c.name:SetPoint("LEFT", c.type, "RIGHT", 6, 0)
	else
		c.name:SetPoint("LEFT", parent, "LEFT", leftInset, 0)
	end

	for _, fs in pairs(c) do
		fs:SetHeight(14)
		fs:SetJustifyH("LEFT")
	end
	return c
end

local function classText(class)
	local text = L[class]
	local color = RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
	if color then
		return string.format("|cff%02x%02x%02x%s|r",
			math.floor(color.r * 255 + 0.5), math.floor(color.g * 255 + 0.5), math.floor(color.b * 255 + 0.5), text)
	end
	return text
end

-- Two digit year (26 instead of 2026) so the column stays narrow
local function formatDate(meta)
	return (meta and meta.created and date("%d/%m/%y", meta.created)) or "-"
end

-- Shared with TransferUI so both tabs look the same
UI.CreateColumns = createColumns
UI.ClassText = classText
UI.FormatDate = formatDate
UI.ROWS, UI.ROW_HEIGHT = ROWS, ROW_HEIGHT
UI.LIST_WIDTH, UI.ROW_WIDTH = LIST_WIDTH, ROW_WIDTH

---------------------------------------------------------------------
-- Popups
---------------------------------------------------------------------
StaticPopupDialogs["BARSANDBINDS_DELETE"] = {
	text = "Delete the profile \"%s\"?",
	button1 = YES,
	button2 = NO,
	OnAccept = function()
		pending.panel.module:Delete(pending.name, pending.class)
	end,
	timeout = 0,
	whileDead = 1,
	hideOnEscape = 1,
}

StaticPopupDialogs["BARSANDBINDS_OVERWRITE"] = {
	text = "A profile named \"%s\" already exists. Overwrite it?",
	button1 = YES,
	button2 = NO,
	OnAccept = function()
		pending.panel.selected = pending.panel.module:GetId(pending.name, BB.playerClass)
		pending.panel.module:Save(pending.name)
	end,
	timeout = 0,
	whileDead = 1,
	hideOnEscape = 1,
}

local function doRename()
	local frameName = StaticPopup_Visible("BARSANDBINDS_RENAME")
	local box = frameName and _G[frameName .. "EditBox"]
	if not box then return end

	local panel, old, class = pending.panel, pending.name, pending.class
	local new = BB:NormalizeName(box:GetText())
	if panel.module:Rename(old, new, class) then
		panel.selected = panel.module:GetId(new, class)
		UI:Refresh()
	end
end

StaticPopupDialogs["BARSANDBINDS_RENAME"] = {
	text = "New name for the profile \"%s\":",
	button1 = ACCEPT,
	button2 = CANCEL,
	hasEditBox = 1,
	maxLetters = 40,
	OnAccept = doRename,
	EditBoxOnEnterPressed = function()
		doRename()
		local _, popup = StaticPopup_Visible("BARSANDBINDS_RENAME")
		if popup then popup:Hide() end
	end,
	timeout = 0,
	whileDead = 1,
	hideOnEscape = 1,
}

---------------------------------------------------------------------
-- Panel refresh
---------------------------------------------------------------------
local function refreshPanel(panel)
	local entries = panel.module:GetEntries()

	-- Drop the selection if the profile is gone
	panel.selectedEntry = nil
	for _, entry in ipairs(entries) do
		if entry.id == panel.selected then
			panel.selectedEntry = entry
			break
		end
	end
	if not panel.selectedEntry then panel.selected = nil end

	FauxScrollFrame_Update(panel.scroll, #entries, ROWS, ROW_HEIGHT)
	local offset = FauxScrollFrame_GetOffset(panel.scroll)

	for i = 1, ROWS do
		local row = panel.rows[i]
		local entry = entries[i + offset]
		if entry then
			local meta = entry.meta
			local class = entry.class or (meta and meta.class)
			local restorable = not entry.class or entry.class == BB.playerClass

			row.entry = entry
			row.cols.name:SetText(entry.name)
			if restorable then
				row.cols.name:SetTextColor(1, 1, 1)
			else
				row.cols.name:SetTextColor(0.55, 0.55, 0.55)   -- other class: can't be restored
			end
			row.cols.char:SetText((meta and meta.char) or "-")
			row.cols.class:SetText(class and classText(class) or "-")
			row.cols.date:SetText(formatDate(meta))
			row:Show()
			if entry.id == panel.selected then row:LockHighlight() else row:UnlockHighlight() end
		else
			row.entry = nil
			row:Hide()
		end
	end

	if #entries == 0 then panel.empty:Show() else panel.empty:Hide() end

	-- Profiles of other classes can be renamed / deleted but not restored
	local entry = panel.selectedEntry
	local canRestore = entry and (not entry.class or entry.class == BB.playerClass)
	setEnabled(panel.restoreButton, canRestore and not InCombatLockdown())
	setEnabled(panel.renameButton, entry ~= nil)
	setEnabled(panel.deleteButton, entry ~= nil)

	if panel.checkboxes then
		for _, box in ipairs(panel.checkboxes) do
			box:SetChecked(BB.db.bars[box.option] and 1 or nil)
		end
	end

	if panel.label and panel.getLabel then
		panel.label:SetText(panel.getLabel())
	end
end

function UI:Refresh()
	if not self.frame then return end
	for _, panel in ipairs(panels) do
		if panel.refresh then
			panel.refresh()
		else
			refreshPanel(panel)
		end
	end
end

---------------------------------------------------------------------
-- Actions
---------------------------------------------------------------------
local function doSave(panel)
	local name = BB:NormalizeName(panel.editBox:GetText())
	if name == "" then
		BB:Print(L["Type a profile name first."])
		return
	end

	panel.editBox:ClearFocus()

	if profileExists(panel, name) then
		pending.panel, pending.name = panel, name
		StaticPopup_Show("BARSANDBINDS_OVERWRITE", name)
	else
		panel.selected = panel.module:GetId(name, BB.playerClass)
		panel.module:Save(name)
	end
end

local function doRestore(panel)
	local entry = panel.selectedEntry
	if entry then
		panel.module:Restore(entry.name, entry.class)
	end
end

local function doRename_Ask(panel)
	local entry = panel.selectedEntry
	if not entry then return end
	pending.panel, pending.name, pending.class = panel, entry.name, entry.class

	local popup = StaticPopup_Show("BARSANDBINDS_RENAME", entry.name)
	if popup then
		local box = _G[popup:GetName() .. "EditBox"]
		box:SetText(entry.name)
		box:HighlightText()
	end
end

local function doDelete(panel)
	local entry = panel.selectedEntry
	if not entry then return end
	pending.panel, pending.name, pending.class = panel, entry.name, entry.class
	StaticPopup_Show("BARSANDBINDS_DELETE", entry.name)
end

---------------------------------------------------------------------
-- Widgets
---------------------------------------------------------------------
local function createButton(parent, text, width, onClick)
	local button = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
	button:SetWidth(width)
	button:SetHeight(22)
	button:SetText(text)
	button:SetScript("OnClick", onClick)
	return button
end

local function createCheckbox(panel, id, label, tip, option)
	local box = CreateFrame("CheckButton", "BarsAndBindsCheck" .. id, panel.frame, "OptionsCheckButtonTemplate")
	_G[box:GetName() .. "Text"]:SetText(label)
	box.option = option

	box:SetScript("OnClick", function(self)
		local checked = self:GetChecked() and true or false
		PlaySound(checked and "igMainMenuOptionCheckBoxOn" or "igMainMenuOptionCheckBoxOff")
		BB.Bars:SetOption(option, checked)
	end)
	box:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:SetText(label, 1, 1, 1)
		GameTooltip:AddLine(tip, 1, 0.82, 0, true)
		GameTooltip:Show()
	end)
	box:SetScript("OnLeave", function() GameTooltip:Hide() end)

	return box
end

local BUTTON_THIRD = math.floor((LIST_WIDTH - 4 - 12) / 3)

local function createPanel(parent, id, module, getLabel)
	local panel = {id = id, module = module, getLabel = getLabel, rows = {}}
	local frame = CreateFrame("Frame", nil, parent)
	frame:SetPoint("TOPLEFT", parent, "TOPLEFT", 20, -68)
	frame:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", -20, 20)
	panel.frame = frame

	-- Header
	local label = frame:CreateFontString(nil, "ARTWORK", "GameFontNormal")
	label:SetPoint("TOPLEFT", frame, "TOPLEFT", 4, 0)
	panel.label = label

	-- Column headers
	local headerFrame = CreateFrame("Frame", nil, frame)
	headerFrame:SetPoint("TOPLEFT", frame, "TOPLEFT", 6, -20)
	headerFrame:SetWidth(ROW_WIDTH)
	headerFrame:SetHeight(14)
	local head = createColumns(headerFrame, "GameFontNormalSmall", "GameFontNormalSmall")
	head.name:SetText("Profile")
	head.char:SetText("Character")
	head.class:SetText("Class")
	head.date:SetText("Date")

	-- List
	local list = CreateFrame("Frame", nil, frame)
	list:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, -36)
	list:SetWidth(LIST_WIDTH)
	list:SetHeight(ROWS * ROW_HEIGHT + 12)
	list:SetBackdrop({
		bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
		edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
		tile = true, tileSize = 16, edgeSize = 16,
		insets = {left = 4, right = 4, top = 4, bottom = 4},
	})
	list:SetBackdropColor(0, 0, 0, 0.6)
	list:EnableMouseWheel(true)

	local scroll = CreateFrame("ScrollFrame", "BarsAndBindsScroll" .. id, list, "FauxScrollFrameTemplate")
	scroll:SetPoint("TOPLEFT", list, "TOPLEFT", 6, -6)
	scroll:SetPoint("BOTTOMRIGHT", list, "BOTTOMRIGHT", -28, 6)
	scroll:SetScript("OnVerticalScroll", function(self, offset)
		FauxScrollFrame_OnVerticalScroll(self, offset, ROW_HEIGHT, function() refreshPanel(panel) end)
	end)
	panel.scroll = scroll

	local function onWheel(_, delta)
		local bar = _G[scroll:GetName() .. "ScrollBar"]
		bar:SetValue(bar:GetValue() - delta * ROW_HEIGHT)
	end
	list:SetScript("OnMouseWheel", onWheel)

	for i = 1, ROWS do
		local row = CreateFrame("Button", nil, list)
		row:SetWidth(ROW_WIDTH)
		row:SetHeight(ROW_HEIGHT)
		row:SetPoint("TOPLEFT", list, "TOPLEFT", 6, -6 - (i - 1) * ROW_HEIGHT)
		row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
		row:EnableMouseWheel(true)
		row:SetScript("OnMouseWheel", onWheel)

		row.cols = createColumns(row, "GameFontHighlight", "GameFontHighlightSmall")
		row.cols.date:SetTextColor(0.6, 0.6, 0.6)

		row:SetScript("OnClick", function(self)
			panel.selected = self.entry and self.entry.id
			panel.editBox:SetText(self.entry and self.entry.name or "")
			panel.editBox:ClearFocus()
			refreshPanel(panel)
		end)

		panel.rows[i] = row
	end

	local empty = list:CreateFontString(nil, "ARTWORK", "GameFontDisable")
	empty:SetPoint("CENTER", list, "CENTER", 0, 0)
	empty:SetText("No profiles saved yet.")
	panel.empty = empty

	-- Name + Save
	local nameLabel = frame:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
	nameLabel:SetPoint("TOPLEFT", list, "BOTTOMLEFT", 4, -10)
	nameLabel:SetText("Profile name:")

	local editBox = CreateFrame("EditBox", nil, frame, "InputBoxTemplate")
	editBox:SetWidth(LIST_WIDTH - 112)
	editBox:SetHeight(22)
	editBox:SetPoint("TOPLEFT", nameLabel, "BOTTOMLEFT", 4, -2)
	editBox:SetAutoFocus(false)
	editBox:SetMaxLetters(40)
	editBox:SetScript("OnEnterPressed", function() doSave(panel) end)
	editBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
	panel.editBox = editBox

	local saveButton = createButton(frame, "Save", 90, function() doSave(panel) end)
	saveButton:SetPoint("LEFT", editBox, "RIGHT", 10, 0)

	-- Actions
	local restoreButton = createButton(frame, "Restore", BUTTON_THIRD, function() doRestore(panel) end)
	restoreButton:SetPoint("TOPLEFT", editBox, "BOTTOMLEFT", -4, -12)
	panel.restoreButton = restoreButton

	local renameButton = createButton(frame, "Rename", BUTTON_THIRD, function() doRename_Ask(panel) end)
	renameButton:SetPoint("LEFT", restoreButton, "RIGHT", 6, 0)
	panel.renameButton = renameButton

	local deleteButton = createButton(frame, "Delete", BUTTON_THIRD, function() doDelete(panel) end)
	deleteButton:SetPoint("LEFT", renameButton, "RIGHT", 6, 0)
	panel.deleteButton = deleteButton

	panel.anchor = restoreButton
	return panel
end

---------------------------------------------------------------------
-- Window
---------------------------------------------------------------------
local function showTab(index)
	for i, panel in ipairs(panels) do
		if i == index then
			panel.frame:Show()
			tabs[i]:Disable()
		else
			panel.frame:Hide()
			tabs[i]:Enable()
		end
	end
	UI.currentTab = index
end

function UI:Create()
	local frame = CreateFrame("Frame", "BarsAndBindsFrame", UIParent)
	frame:SetWidth(FRAME_WIDTH)
	frame:SetHeight(FRAME_HEIGHT)
	frame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
	frame:SetFrameStrata("DIALOG")
	frame:SetToplevel(true)
	frame:SetClampedToScreen(true)
	frame:SetMovable(true)
	frame:EnableMouse(true)
	frame:RegisterForDrag("LeftButton")
	frame:SetScript("OnDragStart", function(self) self:StartMoving() end)
	frame:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
	frame:SetBackdrop({
		bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
		edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
		tile = true, tileSize = 32, edgeSize = 32,
		insets = {left = 11, right = 12, top = 12, bottom = 11},
	})
	frame:Hide()
	self.frame = frame

	local header = frame:CreateTexture(nil, "ARTWORK")
	header:SetTexture("Interface\\DialogFrame\\UI-DialogBox-Header")
	header:SetWidth(256)
	header:SetHeight(64)
	header:SetPoint("TOP", frame, "TOP", 0, 12)

	local title = frame:CreateFontString(nil, "ARTWORK", "GameFontNormal")
	title:SetPoint("TOP", header, "TOP", 0, -14)
	title:SetText("Bars & Binds")

	local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
	close:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -5, -5)

	-- Addon version at the bottom of the window
	local version = frame:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
	version:SetPoint("BOTTOM", frame, "BOTTOM", 0, 14)
	version:SetText("Version " .. (GetAddOnMetadata(addonName, "Version") or "?"))

	-- Panels
	local barsPanel = createPanel(frame, 1, BB.Bars, function()
		return string.format("Action bar profiles - all classes (playing: %s)", (UnitClass("player")))
	end)
	local keysPanel = createPanel(frame, 2, BB.Keys, function()
		return "Key binding profiles - all characters"
	end)
	panels[1], panels[2] = barsPanel, keysPanel
	panels[3] = BB.TransferUI:CreatePanel(frame)

	-- Bars options (all checked by default)
	local boxes = {}
	boxes[1] = createCheckbox(barsPanel, "Macro", "Recreate deleted macros",
		"When restoring a profile, macros that no longer exist are created again.", "macro")
	boxes[2] = createCheckbox(barsPanel, "Count", "Check items in your bags",
		"Only try to restore an item button if you have the item in your bags.", "checkCount")
	boxes[3] = createCheckbox(barsPanel, "Rank", "Restore highest spell rank",
		"Use the highest rank you know of a spell instead of the rank that was saved.", "restoreRank")

	boxes[1]:SetPoint("TOPLEFT", barsPanel.anchor, "BOTTOMLEFT", -2, -14)
	boxes[2]:SetPoint("TOPLEFT", boxes[1], "BOTTOMLEFT", 0, 0)
	boxes[3]:SetPoint("TOPLEFT", boxes[2], "BOTTOMLEFT", 0, 0)
	barsPanel.checkboxes = boxes

	-- Keys hint
	local hint = keysPanel.frame:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
	hint:SetPoint("TOPLEFT", keysPanel.anchor, "BOTTOMLEFT", 2, -16)
	hint:SetWidth(LIST_WIDTH - 8)
	hint:SetJustifyH("LEFT")
	hint:SetText("Key binding profiles are shared by all your characters. Restoring a profile replaces your current key bindings with the saved ones.")

	-- Tabs
	local names = {"Action Bars", "Key Bindings", "Export / Import"}
	for i = 1, 3 do
		local tab = createButton(frame, names[i], 156, function() showTab(i) end)
		if i == 1 then
			tab:SetPoint("TOPLEFT", frame, "TOPLEFT", 22, -38)
		else
			tab:SetPoint("LEFT", tabs[i - 1], "RIGHT", 4, 0)
		end
		tabs[i] = tab
	end

	-- Close with ESC
	table.insert(UISpecialFrames, "BarsAndBindsFrame")

	frame:SetScript("OnShow", function() UI:Refresh() end)

	-- Restore buttons are disabled in combat
	frame:RegisterEvent("PLAYER_REGEN_DISABLED")
	frame:RegisterEvent("PLAYER_REGEN_ENABLED")
	frame:SetScript("OnEvent", function() UI:Refresh() end)

	showTab(1)
end

function UI:Toggle()
	if not BB.db then
		BB:Print("Addon is not loaded yet.")
		return
	end

	if not self.frame then
		self:Create()
	end

	if self.frame:IsShown() then
		self.frame:Hide()
	else
		self.frame:Show()
	end
end

BB:RegisterCallback("BARS_CHANGED", function() UI:Refresh() end)
BB:RegisterCallback("KEYS_CHANGED", function() UI:Refresh() end)
