local _, ns = ...
local Card = ns.Card

-- MOCKUP window: character-pane frame with side tabs like Grandma's Game Box. Two pages:
-- the collection (team of five on top, all cards below) and a duel replay.
local WIDTH, HEIGHT = 640, 640
local COLUMNS = 5
local GAP = 10

local function TemplateExists(name)
	return C_XMLUtil and C_XMLUtil.GetTemplateInfo and C_XMLUtil.GetTemplateInfo(name) ~= nil
end

local window = CreateFrame("Frame", "BestiaryFrame", UIParent,
	TemplateExists("PortraitFrameTemplate") and "PortraitFrameTemplate" or "BasicFrameTemplateWithInset")
window:SetSize(WIDTH, HEIGHT)
window:SetPoint("TOP", UIParent, "TOP", 0, -100)
window:SetFrameStrata("HIGH")
window:SetToplevel(true)
window:SetClampedToScreen(true)
window:SetClampRectInsets(0, -40, 0, 0)
window:EnableMouse(true)
window:SetMovable(true)
window:RegisterForDrag("LeftButton")
window:SetScript("OnDragStart", window.StartMoving)
window:SetScript("OnDragStop", window.StopMovingOrSizing)
window:Hide()
tinsert(UISpecialFrames, "BestiaryFrame")

local ICON = "Interface\\Icons\\Ability_Hunter_BeastTaming"
if window.SetPortraitToAsset then
	window:SetPortraitToAsset(ICON)
end
local portrait = window.PortraitContainer or window.portrait
if portrait and portrait.SetFrameLevel then
	portrait:SetFrameLevel(window:GetFrameLevel() + 20)
end

local function SetTitle(text)
	if window.SetTitle then
		window:SetTitle(text)
	elseif window.TitleText then
		window.TitleText:SetText(text)
	end
end

local INSET = TemplateExists("InsetFrameTemplate") and "InsetFrameTemplate" or nil

-- Pages and side tabs -------------------------------------------------------------------------

local pages = {}

local function SelectPage(page)
	for _, other in ipairs(pages) do
		other.panel:SetShown(other == page)
		other.tab:SetChecked(other == page)
	end
	SetTitle("Bestiary: " .. page.name .. "  |cff999999(mockup)|r")
end

local function AddPage(name, icon)
	local page = { name = name }
	page.panel = CreateFrame("Frame", nil, window)
	page.panel:SetAllPoints()
	page.panel:SetFrameLevel(window:GetFrameLevel() + 5)
	page.panel:Hide()

	local tab = CreateFrame("CheckButton", nil, window)
	tab:SetSize(32, 32)
	if #pages == 0 then
		tab:SetPoint("TOPLEFT", window, "TOPRIGHT", 0, -48)
	else
		tab:SetPoint("TOPLEFT", pages[#pages].tab, "BOTTOMLEFT", 0, -17)
	end
	local frame = tab:CreateTexture(nil, "BACKGROUND")
	frame:SetSize(64, 64)
	frame:SetPoint("TOPLEFT", -3, 11)
	frame:SetTexture("Interface\\SpellBook\\SpellBook-SkillLineTab")
	tab:SetNormalTexture(icon)
	tab:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
	tab:SetCheckedTexture("Interface\\Buttons\\CheckButtonHilight")
	tab:GetCheckedTexture():SetBlendMode("ADD")
	tab:SetScript("OnClick", function()
		SelectPage(page)
		PlaySound(SOUNDKIT.IG_CHARACTER_INFO_TAB)
	end)
	tab:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:SetText(name)
		GameTooltip:Show()
	end)
	tab:SetScript("OnLeave", GameTooltip_Hide)
	page.tab = tab
	pages[#pages + 1] = page
	return page.panel
end

-- Collection page -----------------------------------------------------------------------------

local collection = AddPage("Collection", "Interface\\Icons\\INV_Misc_Book_09")

local teamLabel = collection:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
teamLabel:SetPoint("TOPLEFT", 72, -34)
teamLabel:SetText("Your team")

local teamInfo = collection:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
teamInfo:SetPoint("LEFT", teamLabel, "RIGHT", 14, 0)

local frontLabel = collection:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
local backLabel = collection:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")

local teamSlots = {}
for i = 1, 5 do
	local slot = CreateFrame("Frame", nil, collection)
	slot:SetSize(88, 124)
	slot:SetPoint("TOPLEFT", 72 + (i - 1) * 98, -62)
	local empty = slot:CreateTexture(nil, "BACKGROUND")
	empty:SetAllPoints()
	empty:SetColorTexture(0, 0, 0, 0.4)
	local emptyText = slot:CreateFontString(nil, "OVERLAY", "GameFontDisable")
	emptyText:SetPoint("CENTER")
	emptyText:SetText("empty")
	slot.card = Card.Create(slot, "small")
	slot.card:SetAllPoints()
	slot.card.bar:Hide()
	slot.card:SetScript("OnClick", function()
		tremove(ns.team, i)
		ns.RefreshCollection()
	end)
	teamSlots[i] = slot
end
frontLabel:SetPoint("TOP", teamSlots[1], "BOTTOM", 0, -2)
frontLabel:SetText("front")
backLabel:SetPoint("TOP", teamSlots[5], "BOTTOM", 0, -2)
backLabel:SetText("back")

local bonusText = collection:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
bonusText:SetPoint("TOPLEFT", teamSlots[1], "BOTTOMLEFT", 0, -18)
bonusText:SetJustifyH("LEFT")

local hint = collection:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
hint:SetPoint("TOPRIGHT", -16, -40)
hint:SetJustifyH("RIGHT")
hint:SetText("Click a card to add it to the team.\nClick a team card to take it out.")

local gridInset = CreateFrame("Frame", nil, collection, INSET)
gridInset:SetPoint("TOPLEFT", 8, -242)
gridInset:SetPoint("BOTTOMRIGHT", -8, 8)

local gridTitle = collection:CreateFontString(nil, "OVERLAY", "GameFontNormal")
gridTitle:SetPoint("BOTTOMLEFT", gridInset, "TOPLEFT", 8, 4)

local scroll = CreateFrame("ScrollFrame", nil, gridInset, "UIPanelScrollFrameTemplate")
scroll:SetPoint("TOPLEFT", 8, -8)
scroll:SetPoint("BOTTOMRIGHT", -28, 8)
local grid = CreateFrame("Frame", nil, scroll)
grid:SetSize(COLUMNS * (104 + GAP), 10)
scroll:SetScrollChild(grid)

local function InTeam(index)
	for slot, teamIndex in ipairs(ns.team) do
		if teamIndex == index then
			return slot
		end
	end
end

local gridCards = {}

function ns.RefreshCollection()
	local team = ns.TeamCards()
	for i, slot in ipairs(teamSlots) do
		local data = team[i]
		slot.card:SetShown(data ~= nil)
		if data then
			slot.card:SetCard(data)
		end
	end
	teamInfo:SetText(("Power |cffffffff%d|r / cap 400"):format(ns.TeamPower(team)))
	local bonuses = {}
	for _, bonus in ipairs(ns.TeamFamilies(team)) do
		bonuses[#bonuses + 1] = ("|cffffd200%d %s|r: %s bonus"):format(bonus.count, bonus.family,
			bonus.count >= 4 and "big" or "small")
	end
	bonusText:SetText(#bonuses > 0 and ("Family bonuses: " .. table.concat(bonuses, "   ")) or "No family bonus (field 2 of one family)")

	local sorted = {}
	for i, data in ipairs(ns.collection) do
		sorted[i] = data
	end
	table.sort(sorted, function(a, b)
		local ra, rb = ns.RARITY_ORDER[a.classification], ns.RARITY_ORDER[b.classification]
		if ra ~= rb then
			return ra < rb
		end
		return a.level > b.level
	end)
	for i, data in ipairs(sorted) do
		local card = gridCards[i]
		if not card then
			card = Card.Create(grid, "big")
			card:SetPoint("TOPLEFT", ((i - 1) % COLUMNS) * (104 + GAP), -math.floor((i - 1) / COLUMNS) * (146 + GAP))
			card:SetScript("OnClick", function(self)
				local slot = InTeam(self.data.id)
				if slot then
					tremove(ns.team, slot)
				elseif #ns.team < 5 then
					ns.team[#ns.team + 1] = self.data.id
				else
					UIErrorsFrame:AddMessage("Your team is full. Take a card out first.", 1, 0.2, 0.2)
					return
				end
				PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
				ns.RefreshCollection()
			end)
			gridCards[i] = card
		end
		card:SetCard(data)
		card:SetSelected(InTeam(data.id) ~= nil)
	end
	grid:SetHeight(math.ceil(#sorted / COLUMNS) * (146 + GAP))
	gridTitle:SetText(("Collection: %d cards"):format(#sorted))
end

collection:SetScript("OnShow", ns.RefreshCollection)

-- Duel page -----------------------------------------------------------------------------------

local duel = AddPage("Duel", "Interface\\Icons\\Ability_DualWield")

local theirName = duel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
theirName:SetPoint("TOPLEFT", 72, -34)
local theirPower = duel:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
theirPower:SetPoint("LEFT", theirName, "RIGHT", 12, 0)

local CARD_STEP = 98
local ROW_X = (WIDTH - (5 * CARD_STEP - 10)) / 2

local function CardRow(y)
	local cards = {}
	for i = 1, 5 do
		local card = Card.Create(duel, "small")
		card:SetPoint("TOPLEFT", ROW_X + (i - 1) * CARD_STEP, y)
		cards[i] = card
	end
	return cards
end

local theirCards = CardRow(-64)

local vsText = duel:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
vsText:SetPoint("TOP", 0, -206)
vsText:SetFont(vsText:GetFont(), 28, "THICKOUTLINE")

local roundText = duel:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
roundText:SetPoint("TOP", vsText, "BOTTOM", 0, -4)

local logText = duel:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
logText:SetPoint("TOP", roundText, "BOTTOM", 0, -6)
logText:SetWidth(WIDTH - 40)

local myCards = CardRow(-300)

local myName = duel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
myName:SetPoint("TOPLEFT", myCards[1], "BOTTOMLEFT", 0, -8)
local myPower = duel:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
myPower:SetPoint("LEFT", myName, "RIGHT", 12, 0)

local orderHint = duel:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
orderHint:SetPoint("TOPRIGHT", myCards[5], "BOTTOMRIGHT", 0, -10)
orderHint:SetText("front on the left, back on the right")

local fightButton = CreateFrame("Button", nil, duel, "UIPanelButtonTemplate")
fightButton:SetSize(140, 30)
fightButton:SetPoint("BOTTOM", -76, 20)
fightButton:SetText("Fight!")
local skipButton = CreateFrame("Button", nil, duel, "UIPanelButtonTemplate")
skipButton:SetSize(140, 30)
skipButton:SetPoint("BOTTOM", 76, 20)
skipButton:SetText("Skip to the end")

local ticker, events, step

local function CardFor(side, slot)
	return (side == 1 and myCards or theirCards)[slot]
end

local function Describe(event)
	local attacker = CardFor(event.side, event.slot).data
	local target = CardFor(event.targetSide, event.targetSlot).data
	local color = event.side == 1 and "|cff40ff40" or "|cffff6060"
	return ("%s%s|r hits %s for %d"):format(color, attacker.name, target.name, event.damage)
end

local function Apply(event, animate)
	if event.kind == "hit" then
		roundText:SetText("Round " .. event.round)
		logText:SetText(Describe(event))
		local target = CardFor(event.targetSide, event.targetSlot)
		if animate then
			CardFor(event.side, event.slot):Lunge(event.side == 1 and 1 or -1)
			target:Hit(event.damage, event.hp)
			PlaySound(SOUNDKIT.IG_QUEST_LOG_ABANDON_QUEST or 846)
		else
			target:SetHealth(event.hp)
		end
	elseif event.kind == "death" then
		CardFor(event.side, event.slot):SetDead(true)
	elseif event.kind == "win" then
		local won = event.side == 1
		vsText:SetText(won and "VICTORY!" or "DEFEAT")
		vsText:SetTextColor(won and 1 or 0.9, won and 0.82 or 0.15, won and 0 or 0.1)
		if animate then
			PlaySound(won and SOUNDKIT.READY_CHECK or SOUNDKIT.IG_QUEST_FAILED)
		end
		fightButton:SetText("Fight again")
		fightButton:Enable()
		skipButton:Disable()
	end
end

local function StopReplay()
	if ticker then
		ticker:Cancel()
		ticker = nil
	end
end

local function ResetDuel()
	StopReplay()
	local mine, theirs = ns.TeamCards(), ns.opponent.cards
	for i = 1, 5 do
		myCards[i]:SetShown(mine[i] ~= nil)
		if mine[i] then
			myCards[i]:SetCard(mine[i])
		end
		theirCards[i]:SetCard(theirs[i])
	end
	theirName:SetText("|cffff6060" .. ns.opponent.name .. "|r")
	theirPower:SetText(("Power %d"):format(ns.TeamPower(theirs)))
	myName:SetText("|cff40ff40You|r")
	myPower:SetText(("Power %d"):format(ns.TeamPower(mine)))
	vsText:SetText("VS")
	vsText:SetTextColor(1, 0.82, 0)
	roundText:SetText("")
	logText:SetText(#mine > 0 and "Click Fight! to watch the battle." or "Put some cards in your team first.")
	fightButton:SetText("Fight!")
	fightButton:SetEnabled(#mine > 0)
	skipButton:Disable()
	return mine, theirs
end

fightButton:SetScript("OnClick", function()
	local mine, theirs = ResetDuel()
	events = ns.MockFight(mine, theirs)
	step = 0
	fightButton:Disable()
	skipButton:Enable()
	ticker = C_Timer.NewTicker(0.6, function()
		step = step + 1
		local event = events[step]
		if not event then
			StopReplay()
			return
		end
		Apply(event, true)
		-- A death comes right with the hit that caused it
		if events[step + 1] and events[step + 1].kind == "death" then
			step = step + 1
			Apply(events[step], true)
		end
	end)
end)

skipButton:SetScript("OnClick", function()
	StopReplay()
	for i = step + 1, #events do
		Apply(events[i], false)
	end
	step = #events
end)

duel:SetScript("OnShow", function()
	ResetDuel()
end)
duel:SetScript("OnHide", StopReplay)

-- Opening -------------------------------------------------------------------------------------

SelectPage(pages[1])

SLASH_BESTIARY1 = "/bestiary"
SLASH_BESTIARY2 = "/bst"
SlashCmdList["BESTIARY"] = function()
	window:SetShown(not window:IsShown())
end
