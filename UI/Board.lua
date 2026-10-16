local _, ns = ...
local Board = ns.Board

-- Board page: write short posts shared with your Bestiary friends (Core/Board.lua syncs them).
-- Your own posts can be edited and deleted. Friends are managed on the Friends tab.
local WIDTH = ns.WINDOW_WIDTH
local TEXT_WIDTH = WIDTH - 150
local INSET = C_XMLUtil and C_XMLUtil.GetTemplateInfo and C_XMLUtil.GetTemplateInfo("InsetFrameTemplate")
	and "InsetFrameTemplate" or nil

local page = ns.AddPage("Board", "Interface\\Icons\\INV_Letter_15", 6)
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
inset:SetPoint("BOTTOMRIGHT", -8, 56)
local scroll = CreateFrame("ScrollFrame", nil, inset, "UIPanelScrollFrameTemplate")
scroll:SetPoint("TOPLEFT", 8, -8)
scroll:SetPoint("BOTTOMRIGHT", -28, 8)
local content = CreateFrame("Frame", nil, scroll)
content:SetSize(WIDTH - 60, 10)
scroll:SetScrollChild(content)
local empty = inset:CreateFontString(nil, "OVERLAY", "GameFontDisable")
empty:SetPoint("CENTER")
empty:SetText("Nothing posted yet. Write something above!")

-- Who sees it: your friends (managed on the Friends tab)
local sharedLabel = page:CreateFontString(nil, "OVERLAY", "GameFontNormal")
sharedLabel:SetPoint("BOTTOMLEFT", 16, 30)
local hint = page:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
hint:SetPoint("TOPLEFT", sharedLabel, "BOTTOMLEFT", 0, -4)
hint:SetText("Nothing is sent on its own: press Sync now to swap posts with your friends. Add friends on the Friends tab.")
local syncButton = Button(page, "Sync now", 90, 22)
syncButton:SetPoint("BOTTOMRIGHT", -16, 22)

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

	-- Who sees it
	local friends = 0
	for _, contact in ipairs(Board.Contacts()) do
		if contact.state == "friend" then
			friends = friends + 1
		end
	end
	sharedLabel:SetText(friends == 0 and "Shared with: |cff999999no friends yet|r"
		or ("Shared with your %d %s"):format(friends, friends == 1 and "friend" or "friends"))
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
