local _, ns = ...
local Board = ns.Board

-- Friends page: your Bestiary friends (Core/Board.lua keeps them). Only friends duel each other
-- and share the board, and both have to agree: adding someone sends a request. One row per
-- player: status, your duel record against them, when you last heard from them, and buttons
-- (Duel / Remove, Accept / Decline, or Ask again / Cancel).
local WIDTH = ns.WINDOW_WIDTH
local ROW = 30
local INSET = C_XMLUtil and C_XMLUtil.GetTemplateInfo and C_XMLUtil.GetTemplateInfo("InsetFrameTemplate")
	and "InsetFrameTemplate" or nil

local page = ns.AddPage("Friends", "Interface\\FriendsFrame\\FriendsFrameScrollIcon", 5)

local title = page:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
title:SetPoint("TOPLEFT", 72, -34)
title:SetText("Bestiary friends")
local summary = page:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
summary:SetPoint("LEFT", title, "RIGHT", 14, 0)
local help = page:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
help:SetPoint("TOPLEFT", 72, -56)
help:SetText("Only friends duel each other and share the board. Both have to agree: adding someone asks them first.")

local function Button(parent, text, width, height)
	local button = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
	button:SetSize(width, height or 22)
	button:SetText(text)
	return button
end

-- Adding
local addBox = CreateFrame("EditBox", nil, page, "InputBoxTemplate")
addBox:SetSize(170, 24)
addBox:SetPoint("TOPLEFT", 84, -78)
addBox:SetAutoFocus(false)
addBox:SetMaxLetters(48)
local addHint = addBox:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
addHint:SetPoint("LEFT", 2, 0)
addHint:SetText("Player name")
local addButton = Button(page, "Add friend", 100, 24)
addButton:SetPoint("LEFT", addBox, "RIGHT", 8, 0)
local targetButton = Button(page, "Add target", 100, 24)
targetButton:SetPoint("LEFT", addButton, "RIGHT", 6, 0)
local addNote = page:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
addNote:SetPoint("LEFT", targetButton, "RIGHT", 10, 0)
addNote:SetPoint("RIGHT", page, "RIGHT", -16, 0)
addNote:SetJustifyH("LEFT")
addNote:SetText("They need Bestiary and your faction.")

-- Header and list
local headers = { { "Player", 0 }, { "Status", 190 }, { "Duels", 360 }, { "Last heard", 440 } }
for _, header in ipairs(headers) do
	local text = page:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	text:SetPoint("TOPLEFT", 22 + header[2], -112)
	text:SetText(header[1])
end
local inset = CreateFrame("Frame", nil, page, INSET)
inset:SetPoint("TOPLEFT", 8, -128)
inset:SetPoint("BOTTOMRIGHT", -8, 8)
local scroll = CreateFrame("ScrollFrame", nil, inset, "UIPanelScrollFrameTemplate")
scroll:SetPoint("TOPLEFT", 8, -6)
scroll:SetPoint("BOTTOMRIGHT", -28, 6)
local list = CreateFrame("Frame", nil, scroll)
list:SetSize(WIDTH - 60, 10)
scroll:SetScrollChild(list)
local empty = inset:CreateFontString(nil, "OVERLAY", "GameFontDisable")
empty:SetPoint("CENTER")
empty:SetText("No Bestiary friends yet. Add someone above: they get a request to accept.")

local function Ago(seconds)
	if not seconds then
		return "|cff999999not this session|r"
	elseif seconds < 90 then
		return "just now"
	elseif seconds < 5400 then
		return ("%d min ago"):format(seconds / 60)
	end
	return ("%d h ago"):format(seconds / 3600)
end

local STATUS = {
	friend = "|cff40ff40Friend|r",
	asked = "|cff999999Asked, waiting for them|r",
	incoming = "|cffffd200Wants to be your friend|r",
}

local rows = {}
local Refresh

local function Row(i)
	local row = CreateFrame("Frame", nil, list)
	row:SetSize(WIDTH - 70, ROW)
	row:SetPoint("TOPLEFT", 0, -(i - 1) * ROW)
	if i % 2 == 0 then
		local stripe = row:CreateTexture(nil, "BACKGROUND")
		stripe:SetAllPoints()
		stripe:SetColorTexture(1, 1, 1, 0.03)
	end
	row.name = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	row.name:SetPoint("LEFT", 6, 0)
	row.name:SetWidth(180)
	row.name:SetJustifyH("LEFT")
	row.status = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	row.status:SetPoint("LEFT", 196, 0)
	row.record = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	row.record:SetPoint("LEFT", 366, 0)
	row.heard = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	row.heard:SetPoint("LEFT", 446, 0)
	row.first = Button(row, "", 76, 20)
	row.first:SetPoint("RIGHT", -84, 0)
	row.second = Button(row, "", 76, 20)
	row.second:SetPoint("RIGHT", -4, 0)
	row.battle = Button(row, "Battle", 76, 20)
	row.battle:SetPoint("RIGHT", -164, 0)
	row.battle:SetScript("OnClick", function(self)
		ns.ChallengeBattle(self:GetParent().contact.name)
	end)
	row.first.row, row.second.row = row, row
	row.first:SetScript("OnClick", function(self)
		local contact = self.row.contact
		if contact.state == "friend" then
			ns.ChallengePlayer(contact.name)
		elseif contact.state == "incoming" then
			Board.AcceptFriend(contact.name)
		else
			Board.AddFriend(contact.name) -- ask again
			ns.Print(("Asked %s again."):format(contact.name))
		end
	end)
	row.second:SetScript("OnClick", function(self)
		local contact = self.row.contact
		if contact.state == "incoming" then
			Board.DeclineFriend(contact.name)
		else
			Board.RemoveFriend(contact.name)
		end
	end)
	return row
end

function Refresh()
	local contacts = Board.Contacts()
	local friends = 0
	for i, contact in ipairs(contacts) do
		local row = rows[i] or Row(i)
		rows[i] = row
		row.contact = contact
		if contact.state == "friend" then
			friends = friends + 1
		end
		row.name:SetText(contact.name)
		row.status:SetText(STATUS[contact.state] or contact.state)
		local record = ns.RecordAgainst and ns.RecordAgainst(contact.name)
		row.record:SetText(record and ("%d-%d-%d"):format(record.wins or 0, record.losses or 0, record.draws or 0)
			or "|cff999999-|r")
		row.heard:SetText(Ago(ns.Comm.LastHeard(contact.name)))
		row.battle:SetShown(contact.state == "friend")
		if contact.state == "friend" then
			row.first:SetText("Duel")
			row.second:SetText("Remove")
		elseif contact.state == "incoming" then
			row.first:SetText("Accept")
			row.second:SetText("Decline")
		else
			row.first:SetText("Ask again")
			row.second:SetText("Cancel")
		end
		row:Show()
	end
	for i = #contacts + 1, #rows do
		rows[i]:Hide()
	end
	list:SetHeight(math.max(10, #contacts * ROW))
	empty:SetShown(#contacts == 0)
	summary:SetText(("%d friends"):format(friends))
	addHint:SetShown((addBox:GetText() or "") == "" and not addBox:HasFocus())
end

-- The target, if it's a player of your faction
local function TargetName()
	if not UnitExists("target") or not UnitIsPlayer("target") or UnitIsUnit("target", "player")
		or not UnitIsFriend("player", "target") then
		return
	end
	local name, realm = UnitName("target")
	if not name or (issecretvalue and (issecretvalue(name) or issecretvalue(realm))) then
		return
	end
	return realm and realm ~= "" and (name .. "-" .. realm) or name
end

local function Add(name)
	if name and Board.AddFriend(name) then
		ns.Print(("Friend request sent to |cffffd200%s|r."):format(name))
		return true
	end
	UIErrorsFrame:AddMessage("Type a player's name (not your own).", 1, 0.2, 0.2)
end

local function AddTyped()
	if Add(strtrim(addBox:GetText() or "")) then
		addBox:SetText("")
		addBox:ClearFocus()
	end
end
addButton:SetScript("OnClick", AddTyped)
addBox:SetScript("OnEnterPressed", AddTyped)
addBox:SetScript("OnEscapePressed", function(self)
	self:SetText("")
	self:ClearFocus()
end)
addBox:SetScript("OnTextChanged", function()
	Refresh()
end)
addBox:SetScript("OnEditFocusGained", function()
	addHint:Hide()
end)
addBox:SetScript("OnEditFocusLost", function()
	Refresh()
end)
targetButton:SetScript("OnClick", function()
	local name = TargetName()
	if name then
		Add(name)
	else
		UIErrorsFrame:AddMessage("Target a player of your faction first.", 1, 0.2, 0.2)
	end
end)

page:SetScript("OnShow", Refresh)
-- "Last heard" moves along while open
local elapsed = 0
page:SetScript("OnUpdate", function(_, delta)
	elapsed = elapsed + delta
	if elapsed >= 5 then
		elapsed = 0
		Refresh()
	end
end)

-- Refresh when the list changes (Board.OnChange is the board page's; chain onto it)
local boardChange = Board.OnChange
function Board.OnChange()
	if boardChange then
		boardChange()
	end
	if page:IsVisible() then
		Refresh()
	end
end
