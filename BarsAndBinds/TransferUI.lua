--[[
	Export / Import tab and its two windows.
	  - tab: every saved profile (bars + keys) with a checkbox
	  - "Export selected" opens a window with ONE string holding all selected profiles
	  - "Import..." opens a window where you paste such a string
]]
local addonName, BB = ...
local L = BB.L

local TransferUI = {}
BB.TransferUI = TransferUI

local ROWS = 9
local ROW_HEIGHT = 20

local pendingImport

---------------------------------------------------------------------
-- Popup: confirm overwriting existing profiles
---------------------------------------------------------------------
StaticPopupDialogs["BARSANDBINDS_IMPORT_OVERWRITE"] = {
	text = "%d profile(s) in that text already exist and will be overwritten. Continue?",
	button1 = YES,
	button2 = NO,
	OnAccept = function()
		if pendingImport then
			TransferUI:ApplyImport(pendingImport)
		end
	end,
	OnCancel = function()
		pendingImport = nil
	end,
	timeout = 0,
	whileDead = 1,
	hideOnEscape = 1,
}

---------------------------------------------------------------------
-- Text window (used by both export and import)
---------------------------------------------------------------------
local function createTextWindow(name, titleText)
	local f = CreateFrame("Frame", name, UIParent)
	f:SetWidth(480)
	f:SetHeight(380)
	f:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
	f:SetFrameStrata("DIALOG")
	f:SetToplevel(true)
	f:SetClampedToScreen(true)
	f:SetMovable(true)
	f:EnableMouse(true)
	f:RegisterForDrag("LeftButton")
	f:SetScript("OnDragStart", function(self) self:StartMoving() end)
	f:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
	f:SetBackdrop({
		bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
		edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
		tile = true, tileSize = 32, edgeSize = 32,
		insets = {left = 11, right = 12, top = 12, bottom = 11},
	})
	f:Hide()

	local header = f:CreateTexture(nil, "ARTWORK")
	header:SetTexture("Interface\\DialogFrame\\UI-DialogBox-Header")
	header:SetWidth(256)
	header:SetHeight(64)
	header:SetPoint("TOP", f, "TOP", 0, 12)

	local title = f:CreateFontString(nil, "ARTWORK", "GameFontNormal")
	title:SetPoint("TOP", header, "TOP", 0, -14)
	title:SetText(titleText)

	local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
	close:SetPoint("TOPRIGHT", f, "TOPRIGHT", -5, -5)

	local info = f:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
	info:SetPoint("TOPLEFT", f, "TOPLEFT", 24, -34)
	info:SetWidth(430)
	info:SetHeight(48)
	info:SetJustifyH("LEFT")
	info:SetJustifyV("TOP")

	local background = CreateFrame("Frame", nil, f)
	background:SetPoint("TOPLEFT", f, "TOPLEFT", 18, -88)
	background:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -18, 84)
	background:SetBackdrop({
		bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
		edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
		tile = true, tileSize = 16, edgeSize = 16,
		insets = {left = 4, right = 4, top = 4, bottom = 4},
	})
	background:SetBackdropColor(0, 0, 0, 0.7)

	local scroll = CreateFrame("ScrollFrame", name .. "Scroll", f, "UIPanelScrollFrameTemplate")
	scroll:SetPoint("TOPLEFT", background, "TOPLEFT", 6, -6)
	scroll:SetPoint("BOTTOMRIGHT", background, "BOTTOMRIGHT", -28, 6)

	local edit = CreateFrame("EditBox", nil, scroll)
	edit:SetMultiLine(true)
	edit:SetAutoFocus(false)
	edit:SetFontObject(ChatFontNormal)
	edit:SetWidth(404)
	edit:SetHeight(200)
	edit:SetMaxLetters(0)
	scroll:SetScrollChild(edit)

	edit:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
	edit:SetScript("OnCursorChanged", function(self, x, y, w, h)
		-- keep the cursor visible while typing / pasting
		y = -y
		local offset = scroll:GetVerticalScroll()
		if y < offset then
			scroll:SetVerticalScroll(y)
		else
			y = y + h - scroll:GetHeight()
			if y > offset then scroll:SetVerticalScroll(y) end
		end
	end)

	-- Clicking anywhere in the box focuses the text
	background:EnableMouse(true)
	background:SetScript("OnMouseDown", function() edit:SetFocus() end)

	local status = f:CreateFontString(nil, "ARTWORK", "GameFontNormal")
	status:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 24, 56)
	status:SetWidth(430)
	status:SetJustifyH("LEFT")
	status:SetTextColor(1, 0.25, 0.25)

	table.insert(UISpecialFrames, name)

	return {frame = f, info = info, edit = edit, scroll = scroll, status = status}
end

local function createButton(parent, text, width, onClick)
	local button = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
	button:SetWidth(width)
	button:SetHeight(22)
	button:SetText(text)
	button:SetScript("OnClick", onClick)
	return button
end

---------------------------------------------------------------------
-- Export window
---------------------------------------------------------------------
function TransferUI:ShowExport(text, numBars, numKeys)
	if not self.export then
		local w = createTextWindow("BarsAndBindsExportFrame", "Export profiles")
		self.export = w

		-- Read only: any edit puts the text back
		w.edit:SetScript("OnTextChanged", function(self, userInput)
			if userInput then
				self:SetText(TransferUI.exportText or "")
				self:HighlightText()
			end
			w.scroll:UpdateScrollChildRect()
		end)
		w.edit:SetScript("OnEditFocusGained", function(self) self:HighlightText() end)

		local selectAll = createButton(w.frame, "Select all", 120, function()
			w.edit:SetFocus()
			w.edit:HighlightText()
		end)
		selectAll:SetPoint("BOTTOMRIGHT", w.frame, "BOTTOM", -6, 24)

		local close = createButton(w.frame, "Close", 120, function() w.frame:Hide() end)
		close:SetPoint("BOTTOMLEFT", w.frame, "BOTTOM", 6, 24)
	end

	local w = self.export
	self.exportText = text
	w.info:SetText(string.format("Exported %d action bar profile(s) and %d key binding profile(s) in a single text. Select all the text, copy it and save it. Use Import... later to add them back.", numBars, numKeys))
	w.status:SetText("")

	w.frame:Show()
	w.edit:SetText(text)
	w.scroll:SetVerticalScroll(0)
	w.edit:SetFocus()
	w.edit:HighlightText()
end

---------------------------------------------------------------------
-- Import window
---------------------------------------------------------------------
function TransferUI:ApplyImport(data)
	local numBars, numKeys = BB.Transfer:Apply(data)
	pendingImport = nil

	BB:Print(string.format("Imported %d action bar profile(s) and %d key binding profile(s).", numBars, numKeys))

	if self.import then
		self.import.edit:SetText("")
		self.import.status:SetText("")
		self.import.frame:Hide()
	end
end

function TransferUI:DoImport()
	local w = self.import
	local data, err = BB.Transfer:Parse(w.edit:GetText())

	if not data then
		w.status:SetText(err)
		return
	end

	w.status:SetText("")
	local collisions = BB.Transfer:CountCollisions(data)
	if collisions > 0 then
		pendingImport = data
		StaticPopup_Show("BARSANDBINDS_IMPORT_OVERWRITE", collisions)
	else
		self:ApplyImport(data)
	end
end

function TransferUI:ShowImport()
	if not self.import then
		local w = createTextWindow("BarsAndBindsImportFrame", "Import profiles")
		self.import = w

		w.info:SetText("Paste an export string below and click Import. Every profile inside it will be added. Action bar profiles saved by another class can only be restored on that class.")

		w.edit:SetScript("OnTextChanged", function()
			w.scroll:UpdateScrollChildRect()
			w.status:SetText("")
		end)

		local import = createButton(w.frame, "Import", 120, function() TransferUI:DoImport() end)
		import:SetPoint("BOTTOMRIGHT", w.frame, "BOTTOM", -6, 24)

		local cancel = createButton(w.frame, "Cancel", 120, function() w.frame:Hide() end)
		cancel:SetPoint("BOTTOMLEFT", w.frame, "BOTTOM", 6, 24)
	end

	local w = self.import
	w.status:SetText("")
	w.frame:Show()
	w.edit:SetText("")
	w.edit:SetFocus()
end

---------------------------------------------------------------------
-- Tab content
---------------------------------------------------------------------
function TransferUI:CreatePanel(parent)
	local UI = BB.UI
	local ROWS, ROW_HEIGHT = UI.ROWS, UI.ROW_HEIGHT
	local LIST_WIDTH, ROW_WIDTH = UI.LIST_WIDTH, UI.ROW_WIDTH
	local panel = {items = {}, selected = {}, rows = {}}

	local frame = CreateFrame("Frame", nil, parent)
	frame:SetPoint("TOPLEFT", parent, "TOPLEFT", 20, -68)
	frame:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", -20, 20)
	panel.frame = frame

	-- Header
	local label = frame:CreateFontString(nil, "ARTWORK", "GameFontNormal")
	label:SetPoint("TOPLEFT", frame, "TOPLEFT", 4, 0)
	label:SetText("Select the profiles to export")

	-- Column headers (same geometry as the other tabs, plus the checkbox space and Type)
	local headerFrame = CreateFrame("Frame", nil, frame)
	headerFrame:SetPoint("TOPLEFT", frame, "TOPLEFT", 6, -20)
	headerFrame:SetWidth(ROW_WIDTH)
	headerFrame:SetHeight(14)
	local head = UI.CreateColumns(headerFrame, "GameFontNormalSmall", "GameFontNormalSmall", 30, true)
	head.type:SetText("Type")
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

	local scroll = CreateFrame("ScrollFrame", "BarsAndBindsXferScroll", list, "FauxScrollFrameTemplate")
	scroll:SetPoint("TOPLEFT", list, "TOPLEFT", 6, -6)
	scroll:SetPoint("BOTTOMRIGHT", list, "BOTTOMRIGHT", -28, 6)
	panel.scroll = scroll

	local empty = list:CreateFontString(nil, "ARTWORK", "GameFontDisable")
	empty:SetPoint("CENTER", list, "CENTER", 0, 0)
	empty:SetText("No profiles saved yet.")

	local count = frame:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
	local exportButton

	local function updateButtons()
		local n = 0
		for _ in pairs(panel.selected) do n = n + 1 end
		count:SetText(string.format("%d selected", n))
		if n > 0 then exportButton:Enable() else exportButton:Disable() end
	end

	local function refresh()
		panel.items = BB.Transfer:GetAvailable()

		-- Forget selections of profiles that no longer exist
		local valid = {}
		for _, item in ipairs(panel.items) do valid[item.id] = true end
		for id in pairs(panel.selected) do
			if not valid[id] then panel.selected[id] = nil end
		end

		FauxScrollFrame_Update(scroll, #panel.items, ROWS, ROW_HEIGHT)
		local offset = FauxScrollFrame_GetOffset(scroll)

		for i = 1, ROWS do
			local row = panel.rows[i]
			local item = panel.items[i + offset]
			if item then
				local meta = item.meta
				local class = item.class or (meta and meta.class)

				row.item = item
				row.cols.type:SetText(item.kind == "bars" and "|cff33ff99Bars|r" or "|cff66ccffKeys|r")
				row.cols.name:SetText(item.name)
				row.cols.char:SetText((meta and meta.char) or "-")
				row.cols.class:SetText(class and UI.ClassText(class) or "-")
				row.cols.date:SetText(UI.FormatDate(meta))
				row.check:SetChecked(panel.selected[item.id] and 1 or nil)
				row:Show()
			else
				row.item = nil
				row:Hide()
			end
		end

		if #panel.items == 0 then empty:Show() else empty:Hide() end
		updateButtons()
	end
	panel.refresh = refresh

	scroll:SetScript("OnVerticalScroll", function(self, offset)
		FauxScrollFrame_OnVerticalScroll(self, offset, ROW_HEIGHT, refresh)
	end)

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

		local check = CreateFrame("CheckButton", "BarsAndBindsXferCheck" .. i, row, "UICheckButtonTemplate")
		check:SetWidth(22)
		check:SetHeight(22)
		check:SetPoint("LEFT", row, "LEFT", 2, 0)
		check:EnableMouseWheel(true)
		check:SetScript("OnMouseWheel", onWheel)
		row.check = check

		row.cols = UI.CreateColumns(row, "GameFontHighlight", "GameFontHighlightSmall", 30, true)
		row.cols.date:SetTextColor(0.6, 0.6, 0.6)

		-- Clicking the checkbox or anywhere on the row toggles the profile
		check:SetScript("OnClick", function(self)
			if row.item then
				panel.selected[row.item.id] = self:GetChecked() and true or nil
				updateButtons()
			end
		end)
		row:SetScript("OnClick", function(self)
			if self.item then
				local on = not panel.selected[self.item.id]
				panel.selected[self.item.id] = on or nil
				self.check:SetChecked(on and 1 or nil)
				updateButtons()
			end
		end)

		panel.rows[i] = row
	end

	-- Select all / none
	local half = math.floor((LIST_WIDTH - 6) / 3)

	local selectAll = createButton(frame, "Select all", half, function()
		for _, item in ipairs(panel.items) do panel.selected[item.id] = true end
		refresh()
	end)
	selectAll:SetPoint("TOPLEFT", list, "BOTTOMLEFT", 0, -10)

	local selectNone = createButton(frame, "Select none", half, function()
		for id in pairs(panel.selected) do panel.selected[id] = nil end
		refresh()
	end)
	selectNone:SetPoint("LEFT", selectAll, "RIGHT", 3, 0)

	count:SetPoint("LEFT", selectNone, "RIGHT", 12, 0)

	-- Export / Import (together they fill the width of the list)
	local wide = math.floor((LIST_WIDTH - 6) / 2)

	exportButton = createButton(frame, "Export selected", wide, function()
		local chosen = {}
		for _, item in ipairs(panel.items) do
			if panel.selected[item.id] then table.insert(chosen, item) end
		end
		if #chosen == 0 then return end

		local text, numBars, numKeys = BB.Transfer:Export(chosen)
		TransferUI:ShowExport(text, numBars, numKeys)
	end)
	exportButton:SetPoint("TOPLEFT", selectAll, "BOTTOMLEFT", 0, -10)

	local importButton = createButton(frame, "Import...", wide, function()
		TransferUI:ShowImport()
	end)
	importButton:SetPoint("LEFT", exportButton, "RIGHT", 6, 0)

	local hint = frame:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
	hint:SetPoint("TOPLEFT", exportButton, "BOTTOMLEFT", 2, -14)
	hint:SetWidth(LIST_WIDTH - 8)
	hint:SetJustifyH("LEFT")
	hint:SetText("|cffffd100Export selected|r: turns the checked profiles into one text.\n|cffffd100Import...|r: adds the profiles from a text you paste.")

	return panel
end
