local _, ns = ...
local Board = ns.Board

-- Board page: write short posts shared with your Bestiary friends (Core/Board.lua syncs them).
-- Your own posts can be edited and deleted. At the bottom: your friends (click: duel, right-click:
-- remove), open requests, a box to add a friend, and Sync now. Only friends can duel each other.
local WIDTH = ns.WINDOW_WIDTH
local TEXT_WIDTH = WIDTH - 150
local INSET = C_XMLUtil and C_XMLUtil.GetTemplateInfo and C_XMLUtil.GetTemplateInfo("InsetFrameTemplate")
	and "InsetFrameTemplate" or nil

local page = ns.AddPage("Board", "Interface\\Icons\\INV_Letter_15", 5)
local editing -- id of the own post being edited

local title = page:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
title:SetPoint("TOPLEFT", 72, -34)
title:SetText("Board")
local summary = page:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
summary:SetPoint("LEFT", title, "RIGHT", 14, 0)

local function Button(parent, text, width, height)
	local button = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
	button:SetSize(width, height or 22)
	button:SetText(text)
	return button
end

local function EditBox(width)
	local box = CreateFrame("EditBox", nil, page, "InputBoxTemplate")
	box:SetSize(width, 24)
	box:SetAutoFocus(false)
	return box
end

-- Writing
local input = EditBox(WIDTH - 230)
input:SetPoint("TOPLEFT", 84, -62)
input:SetMaxLetters(200)
local postButton = Button(page, "Post", 90, 24)
postButton:SetPoint("LEFT", input, "RIGHT", 8, 0)
local counter = page:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
counter:SetPoint("TOPRIGHT", input, "BOTTOMRIGHT", 0, -1)

-- Posts
local inset = CreateFrame("Frame", nil, page, INSET)
inset:SetPoint("TOPLEFT", 8, -100)
inset:SetPoint("BOTTOMRIGHT", -8, 96)
local scroll = CreateFrame("ScrollFrame", nil, inset, "UIPanelScrollFrameTemplate")
scroll:SetPoint("TOPLEFT", 8, -8)
scroll:SetPoint("BOTTOMRIGHT", -28, 8)
local content = CreateFrame("Frame", nil, scroll)
content:SetSize(WIDTH - 60, 10)
scroll:SetScrollChild(content)
local empty = inset:CreateFontString(nil, "OVERLAY", "GameFontDisable")
empty:SetPoint("CENTER")
empty:SetText("Nothing posted yet. Write something above!")

-- Sharing
local sharedLabel = page:CreateFontString(nil, "OVERLAY", "GameFontNormal")
sharedLabel:SetPoint("BOTTOMLEFT", 16, 66)
sharedLabel:SetText("Friends:")
local contactButtons = {}
local addBox = EditBox(160)
addBox:SetPoint("BOTTOMLEFT", 22, 18)
local addHint = page:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
addHint:SetPoint("BOTTOMLEFT", addBox, "TOPLEFT", -4, 2)
addHint:SetText("Add a friend (they need Bestiary):")
local addButton = Button(page, "Add", 60, 22)
addButton:SetPoint("LEFT", addBox, "RIGHT", 6, 0)
local syncButton = Button(page, "Sync now", 90, 22)
syncButton:SetPoint("BOTTOMRIGHT", -16, 18)
local hint = page:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
hint:SetPoint("LEFT", addButton, "RIGHT", 12, 0)
hint:SetPoint("RIGHT", syncButton, "LEFT", -12, 0)
hint:SetJustifyH("LEFT")
hint:SetText("Friends duel each other and share this board. Click a friend to duel, right-click to remove.")

local function Ago(at)
	local seconds = (GetServerTime and GetServerTime() or time()) - at
	if seconds < 90 then
		return "just now"
	elseif seconds < 5400 then
		return ("%d min ago"):format(seconds / 60)
	elseif seconds < 129600 then
		return ("%d h ago"):format(seconds / 3600)
	end
	return ("%d days ago"):format(seconds / 86400)
end

-- Rows: author and time, the text, Edit and Delete on your own posts
local rows = {}
local Refresh

local function Row(i)
	local row = CreateFrame("Frame", nil, content)
	row:SetWidth(WIDTH - 70)
	row.head = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	row.head:SetPoint("TOPLEFT", 4, -4)
	row.text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	row.text:SetPoint("TOPLEFT", row.head, "BOTTOMLEFT", 0, -3)
	row.text:SetWidth(TEXT_WIDTH)
	row.text:SetJustifyH("LEFT")
	row.text:SetSpacing(2)
	row.edit = Button(row, "Edit", 56, 18)
	row.edit:SetPoint("TOPRIGHT", -62, -4)
	row.delete = Button(row, "Delete", 56, 18)
	row.delete:SetPoint("TOPRIGHT", -2, -4)
	row.line = row:CreateTexture(nil, "BACKGROUND")
	row.line:SetPoint("BOTTOMLEFT", 0, 0)
	row.line:SetPoint("BOTTOMRIGHT", 0, 0)
	row.line:SetHeight(1)
	row.line:SetColorTexture(1, 1, 1, 0.08)
	row.edit:SetScript("OnClick", function(self)
		local post = self:GetParent().post
		editing = post.id
		input:SetText(post.text)
		input:SetFocus()
		Refresh()
	end)
	row.delete:SetScript("OnClick", function(self)
		Board.Delete(self:GetParent().post.id)
		if editing == self:GetParent().post.id then
			editing = nil
			input:SetText("")
		end
	end)
	if i == 1 then
		row:SetPoint("TOPLEFT", 0, 0)
	else
		row:SetPoint("TOPLEFT", rows[i - 1], "BOTTOMLEFT", 0, -2)
	end
	return row
end

local function UpdateCounter()
	local text = input:GetText() or ""
	counter:SetText(("%d / 200"):format(#text))
	postButton:SetText(editing and "Save" or "Post")
end

function Refresh()
	local posts = Board.List()
	local height = 0
	for i, post in ipairs(posts) do
		local row = rows[i] or Row(i)
		rows[i] = row
		row.post = post
		local own = Board.Own(post)
		row.head:SetText(("%s%s|r  |cff999999%s%s|r"):format(own and "|cff40ff40" or "|cffffd200", post.author,
			date and date("%d.%m. %H:%M", post.created) or Ago(post.created),
			post.modified > post.created and "  (edited)" or ""))
		row.text:SetText(post.text)
		row.edit:SetShown(own)
		row.delete:SetShown(own)
		local h = 4 + (row.head:GetStringHeight() or 12) + 3 + (row.text:GetStringHeight() or 14) + 8
		row:SetHeight(h)
		height = height + h + 2
		row:Show()
	end
	for i = #posts + 1, #rows do
		rows[i]:Hide()
	end
	content:SetHeight(math.max(10, height))
	empty:SetShown(#posts == 0)

	-- Who it's shared with
	local contacts = Board.Contacts()
	for i, contact in ipairs(contacts) do
		local button = contactButtons[i]
		if not button then
			button = Button(page, "", 96, 20)
			button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
			button:SetScript("OnClick", function(self, mouse)
				local contact = self.contact
				if contact.state == "incoming" then
					if mouse == "RightButton" then
						Board.DeclineFriend(contact.name)
					else
						Board.AcceptFriend(contact.name)
					end
				elseif mouse == "RightButton" then
					Board.RemoveFriend(contact.name)
				elseif contact.state == "friend" and ns.ChallengePlayer then
					ns.ChallengePlayer(contact.name)
				end
			end)
			button:SetScript("OnEnter", function(self)
				local contact = self.contact
				GameTooltip:SetOwner(self, "ANCHOR_TOP")
				GameTooltip:AddLine(contact.name)
				if contact.state == "incoming" then
					GameTooltip:AddLine("Wants to be your Bestiary friend", 1, 1, 1)
					GameTooltip:AddLine("Click: accept  ·  Right-click: decline", 0.7, 0.7, 0.7)
				elseif contact.state == "asked" then
					GameTooltip:AddLine("Asked, waiting for them to say yes", 1, 1, 1)
					GameTooltip:AddLine("Right-click: take it back", 0.7, 0.7, 0.7)
				else
					GameTooltip:AddLine(contact.lastSync and contact.lastSync > 0
						and ("Board in sync " .. Ago(contact.lastSync)) or "Board not in sync yet", 1, 1, 1)
					GameTooltip:AddLine("Click: challenge to a duel  ·  Right-click: remove", 0.7, 0.7, 0.7)
				end
				GameTooltip:Show()
			end)
			button:SetScript("OnLeave", GameTooltip_Hide)
			contactButtons[i] = button
			if i == 1 then
				button:SetPoint("LEFT", sharedLabel, "RIGHT", 10, 0)
			else
				button:SetPoint("LEFT", contactButtons[i - 1], "RIGHT", 4, 0)
			end
		end
		button.contact = contact
		button:SetText(contact.state == "friend" and contact.name
			or contact.state == "asked" and ("|cff999999" .. contact.name .. " ?|r")
			or ("|cff40ff40" .. contact.name .. " !|r"))
		button:SetShown(i <= 6)
	end
	for i = #contacts + 1, #contactButtons do
		contactButtons[i]:Hide()
	end
	local friends = 0
	for _, contact in ipairs(contacts) do
		if contact.state == "friend" then
			friends = friends + 1
		end
	end
	sharedLabel:SetText(#contacts == 0 and "Friends: |cff999999none yet|r"
		or (#contacts > 6 and ("Friends (%d):"):format(friends) or "Friends:"))
	summary:SetText(("%d posts  ·  %d friends"):format(#posts, friends))
	UpdateCounter()
end

local function Submit()
	local text = input:GetText()
	if editing then
		Board.Edit(editing, text)
		editing = nil
	else
		Board.Post(text)
	end
	input:SetText("")
	input:ClearFocus()
	UpdateCounter()
end

postButton:SetScript("OnClick", Submit)
input:SetScript("OnEnterPressed", Submit)
input:SetScript("OnEscapePressed", function(self)
	editing = nil
	self:SetText("")
	self:ClearFocus()
	UpdateCounter()
end)
input:SetScript("OnTextChanged", UpdateCounter)

local function Add()
	local name = addBox:GetText()
	if Board.AddContact(name) then
		addBox:SetText("")
		addBox:ClearFocus()
	else
		UIErrorsFrame:AddMessage("Type a player's name (not your own).", 1, 0.2, 0.2)
	end
end
addButton:SetScript("OnClick", Add)
addBox:SetScript("OnEnterPressed", Add)
addBox:SetScript("OnEscapePressed", function(self)
	self:ClearFocus()
end)
syncButton:SetScript("OnClick", function()
	Board.SyncAll()
	ns.Print("Board: syncing with everyone you share it with.")
end)

page:SetScript("OnShow", Refresh)

function Board.OnChange()
	if page:IsVisible() then
		Refresh()
	end
end

-- Friend requests
StaticPopupDialogs["BESTIARY_FRIEND"] = {
	text = "%s wants to be your Bestiary friend.\nFriends duel each other and share the board.",
	button1 = ACCEPT or "Accept",
	button2 = DECLINE or "Decline",
	timeout = 0,
	whileDead = true,
	hideOnEscape = true,
	OnAccept = function(_, name)
		Board.AcceptFriend(name)
	end,
	OnCancel = function(_, name, reason)
		if reason == "clicked" then
			Board.DeclineFriend(name)
		end
	end,
}

function Board.OnRequest(name)
	PlaySound(SOUNDKIT.READY_CHECK)
	StaticPopup_Show("BESTIARY_FRIEND", name, nil, name)
end

function Board.OnFriend(name)
	ns.Print(("You and |cffffd200%s|r are Bestiary friends now: you can duel each other and share the board."):format(name))
end

function Board.OnDeclined(name)
	ns.Print(("%s doesn't want to be Bestiary friends."):format(name))
end
