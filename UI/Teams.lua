local _, ns = ...
local Card = ns.Card

-- Teams page (ARCHITECTURE.md 5.5): your three battle teams of up to 3 cards (Battle.MAX_TEAM), apart from the
-- squads; no power cap and no leaders in battles. Click a card of the collection to add it,
-- right-click a card of the team to take it out. The order doesn't matter: you pick your lead
-- when you pick the team for a battle.
local WIDTH = ns.WINDOW_WIDTH
local STEP = Card.WIDTH + 8
local SLOT_STEP = Card.WIDTH + 16
local SLOT_X = (WIDTH - (ns.Battle.MAX_TEAM * SLOT_STEP - 16)) / 2
local INSET = C_XMLUtil and C_XMLUtil.GetTemplateInfo and C_XMLUtil.GetTemplateInfo("InsetFrameTemplate") and "InsetFrameTemplate" or nil
local SLOT_BACKDROP = {
	bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
	edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
	tile = true, tileSize = 16, edgeSize = 14,
	insets = { left = 4, right = 4, top = 4, bottom = 4 },
}

local page = ns.AddPage("Teams", "Interface\\Icons\\INV_Misc_Book_08", 4.2)
local current = 1
local filter
local Refresh

local function Button(parent, text, width, height)
	local button = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
	button:SetSize(width, height or 22)
	button:SetText(text)
	return button
end

local function Team()
	return ns.Teams()[current]
end

local teamButtons = {}
for i = 1, ns.TEAM_COUNT do
	local button = Button(page, "", 150, 24)
	button:SetPoint("TOPLEFT", 72 + (i - 1) * 156, -32)
	button:SetScript("OnClick", function()
		current = i
		PlaySound(SOUNDKIT.IG_CHARACTER_INFO_TAB)
		Refresh()
	end)
	teamButtons[i] = button
end

-- The type chart, as a tooltip
local chartButton = Button(page, "Type chart", 110, 24)
chartButton:SetPoint("TOPRIGHT", -16, -32)
function ns.ShowTypeChart(owner)
	GameTooltip:SetOwner(owner, "ANCHOR_BOTTOMLEFT")
	GameTooltip:AddLine("Type chart")
	GameTooltip:AddLine(("Hits on a family it's strong against do x%.2g, hits on one strong against it x%.2g. Giant and Dragonkin are rivals: strong against each other.")
		:format(ns.TYPE_STRONG, ns.TYPE_WEAK), 1, 1, 1, true)
	GameTooltip:AddLine(" ")
	for _, family in ipairs(ns.FAMILY_ORDER) do
		local strong = ns.TypeMatchups(family)
		local icon = ns.FAMILIES[family].icon
		GameTooltip:AddDoubleLine(("|T%s:14:14|t %s"):format(icon, family), "strong vs " .. table.concat(strong, ", "),
			1, 0.82, 0, 0.6, 1, 0.6)
	end
	GameTooltip:Show()
end
chartButton:SetScript("OnEnter", ns.ShowTypeChart)
chartButton:SetScript("OnLeave", GameTooltip_Hide)
chartButton:SetScript("OnClick", ns.ShowTypeChart)

local howTo = page:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
howTo:SetPoint("TOP", 0, -68)
howTo:SetText("Click a card below to add it  ·  Right-click a team card: remove  ·  No power cap, no leaders")

local slots = {}
for i = 1, ns.Battle.MAX_TEAM do
	local slot = CreateFrame("Frame", nil, page, BackdropTemplateMixin and "BackdropTemplate" or nil)
	slot:SetSize(Card.WIDTH, Card.HEIGHT)
	slot:SetPoint("TOPLEFT", SLOT_X + (i - 1) * SLOT_STEP, -84)
	if slot.SetBackdrop then
		slot:SetBackdrop(SLOT_BACKDROP)
		slot:SetBackdropColor(0, 0, 0, 0.35)
		slot:SetBackdropBorderColor(0.35, 0.35, 0.35, 0.8)
	end
	slot.label = slot:CreateFontString(nil, "OVERLAY", "GameFontDisable")
	slot.label:SetPoint("CENTER")
	slot.label:SetText("empty")
	slot.card = Card.Create(slot)
	slot.card:SetAllPoints()
	slot.card.slot = i
	slot.hint = page:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	slot.hint:SetPoint("TOP", slot, "BOTTOM", 0, -3)
	slot.hint:SetWidth(Card.WIDTH + 12)
	slots[i] = slot
end

local mixText = page:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
mixText:SetPoint("TOP", 0, -258)
local familyText = page:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
familyText:SetPoint("TOP", 0, -284)
familyText:SetWidth(WIDTH - 40)
local checkText = page:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
checkText:SetPoint("TOP", 0, -322)
checkText:SetWidth(WIDTH - 80)

local collectionLabel = page:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
collectionLabel:SetPoint("TOPLEFT", 24, -356)
local sortButton = ns.SortButton(page, 110, function()
	Refresh()
end)
sortButton:SetPoint("LEFT", collectionLabel, "RIGHT", 10, 0)

local FILTERS = { "All", "Tank", "Mage", "Warrior", "Healer" }
local filterButtons = {}
for i, kind in ipairs(FILTERS) do
	local button = Button(page, kind, 76, 20)
	button:SetPoint("TOPRIGHT", -16 - (#FILTERS - i) * 80, -354)
	button:SetScript("OnClick", function()
		filter = kind ~= "All" and kind or nil
		Refresh()
	end)
	button.kind = kind
	filterButtons[i] = button
end

local gridInset = CreateFrame("Frame", nil, page, INSET)
gridInset:SetPoint("TOPLEFT", 8, -378)
gridInset:SetPoint("BOTTOMRIGHT", -8, 8)
local scroll = CreateFrame("ScrollFrame", nil, gridInset, "UIPanelScrollFrameTemplate")
scroll:SetPoint("TOPLEFT", 8, -8)
scroll:SetPoint("BOTTOMRIGHT", -28, 8)
local grid = CreateFrame("Frame", nil, scroll)
grid:SetSize(WIDTH - 60, 10)
scroll:SetScrollChild(grid)
local COLUMNS = math.floor((WIDTH - 60) / STEP)
local emptyGrid = gridInset:CreateFontString(nil, "OVERLAY", "GameFontDisable")
emptyGrid:SetPoint("CENTER")
emptyGrid:SetText("No cards yet. Kill studied mobs to collect cards.")

local function Remove(team, id)
	for i, cardId in ipairs(team.cards) do
		if cardId == id then
			tremove(team.cards, i)
			return true
		end
	end
end

local function Add(team, id)
	if #team.cards >= ns.Battle.MAX_TEAM then
		UIErrorsFrame:AddMessage(("A team holds at most %d cards."):format(ns.Battle.MAX_TEAM), 1, 0.2, 0.2)
		return
	end
	team.cards[#team.cards + 1] = id
end

local function OnClick(self, mouseButton)
	if type(self.data) ~= "table" then
		return
	end
	local team = Team()
	if self.slot then
		if mouseButton == "RightButton" then
			Remove(team, self.data.id)
			PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_OFF)
		end
	else
		local free = ns.FreeCopy(team, self.data)
		if mouseButton == "RightButton" or not free then
			local copies = ns.CopyIds(self.data)
			for i = #copies, 1, -1 do
				if Remove(team, copies[i]) and mouseButton == "RightButton" then
					break
				end
			end
			PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_OFF)
		else
			Add(team, free)
			PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
		end
	end
	Refresh()
end

for _, slot in ipairs(slots) do
	slot.card:SetScript("OnClick", OnClick)
end

-- "Beast 2 · Undead 1", and what they're strong against
local function FamilyLine(cards)
	local counts, order = {}, {}
	for _, card in ipairs(cards) do
		if not counts[card.family] then
			order[#order + 1] = card.family
		end
		counts[card.family] = (counts[card.family] or 0) + 1
	end
	local strong = {}
	local parts = {}
	for _, family in ipairs(order) do
		parts[#parts + 1] = ("|T%s:14:14|t %s %d"):format(ns.FAMILIES[family].icon, family, counts[family])
		for _, other in ipairs((ns.TypeMatchups(family))) do
			strong[other] = true
		end
	end
	local covered = {}
	for _, family in ipairs(ns.FAMILY_ORDER) do
		if strong[family] then
			covered[#covered + 1] = family
		end
	end
	if #parts == 0 then
		return ""
	end
	return table.concat(parts, "   ") .. (#covered > 0 and ("\n|cff999999Strong against:|r " .. table.concat(covered, ", ")) or "")
end

-- A card's battle XP under it
local function XpText(view)
	local saved = not view.player and ns.SavedCard(view)
	if not saved then
		return ""
	elseif view.level >= ns.LevelCap(saved) then
		return "|cff999999max level for now|r"
	end
	local xp, need = ns.CardXp(saved)
	return ("|cffb080ffXP %d / %d|r"):format(xp, need)
end

local gridCards = {}

function Refresh()
	if not BestiaryChar then
		return
	end
	local team = Team()
	local cards = ns.TeamCards(team)
	for i, button in ipairs(teamButtons) do
		button:SetText(ns.Teams()[i].name)
		if i == current then
			button:LockHighlight()
		else
			button:UnlockHighlight()
		end
	end
	for i, slot in ipairs(slots) do
		local data = cards[i]
		slot.card:SetShown(data ~= nil)
		slot.hint:SetText(data and XpText(data) or "")
		if data then
			data.battle = true
			slot.card:SetCard(data)
		end
	end
	local mix = ns.TypeMix(cards)
	mixText:SetText(mix ~= "" and mix or "|cff999999No cards yet|r")
	familyText:SetText(FamilyLine(cards))
	local parts = {}
	for _, check in ipairs(ns.TeamChecks(team)) do
		parts[#parts + 1] = (check.ok and "|TInterface\\RaidFrame\\ReadyCheck-Ready:14:14|t |cff40ff40%s|r"
			or "|TInterface\\RaidFrame\\ReadyCheck-NotReady:14:14|t |cffff4040%s|r"):format(check.text)
	end
	checkText:SetText(table.concat(parts, "    "))

	local list = {}
	local collection = ns.Collection()
	for _, data in ipairs(collection) do
		if not filter or data.type == filter then
			list[#list + 1] = data
		end
	end
	sortButton:Update()
	for i, data in ipairs(list) do
		local card = gridCards[i]
		if not card then
			card = Card.Create(grid)
			card:SetPoint("TOPLEFT", ((i - 1) % COLUMNS) * STEP, -math.floor((i - 1) / COLUMNS) * (Card.HEIGHT + 8))
			card:SetScript("OnClick", OnClick)
			gridCards[i] = card
		end
		data.battle = true
		card:SetCard(data)
		local inTeam = ns.CopiesIn(team, data)
		local free = ns.Copies(data) - inTeam
		card:SetSelected(inTeam > 0)
		if ns.CanHaveCopies(data) then
			card:SetCount(free)
		end
		card:SetUsedUp(free <= 0)
		card:Show()
	end
	for i = #list + 1, #gridCards do
		gridCards[i]:Hide()
	end
	grid:SetHeight(math.ceil(#list / COLUMNS) * (Card.HEIGHT + 8))
	ns.ClipCards(scroll, gridCards)
	collectionLabel:SetText(("Collection  |cff999999%d|r"):format(#collection))
	emptyGrid:SetShown(#collection == 0)
	for _, button in ipairs(filterButtons) do
		if (button.kind == "All" and not filter) or button.kind == filter then
			button:LockHighlight()
		else
			button:UnlockHighlight()
		end
	end
end

page:SetScript("OnShow", Refresh)
