local _, ns = ...
local Card = ns.Card

-- MOCKUP window: character-pane frame with side tabs like Grandma's Game Box. Two pages:
--   Squads: three squads of up to 7 cards (front left, back right), checks, a quick test
--           against training squads, and the collection below
--   Duel:   a twist, a hidden pick of one of your squads against one of the opponent's, then
--           the replay and stamina afterwards
local WIDTH, HEIGHT = 720, 690
local STEP = Card.WIDTH + 8
local ROW_X = (WIDTH - (ns.MAX_SQUAD * STEP - 8)) / 2

local function TemplateExists(name)
	return C_XMLUtil and C_XMLUtil.GetTemplateInfo and C_XMLUtil.GetTemplateInfo(name) ~= nil
end

local window = CreateFrame("Frame", "BestiaryFrame", UIParent,
	TemplateExists("PortraitFrameTemplate") and "PortraitFrameTemplate" or "BasicFrameTemplateWithInset")
window:SetSize(WIDTH, HEIGHT)
window:SetPoint("TOP", UIParent, "TOP", 0, -80)
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

if window.SetPortraitToAsset then
	window:SetPortraitToAsset("Interface\\Icons\\Ability_Hunter_BeastTaming")
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
local SLOT_BACKDROP = {
	bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
	edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
	tile = true, tileSize = 16, edgeSize = 14,
	insets = { left = 4, right = 4, top = 4, bottom = 4 },
}

local function Colored(color, text)
	local r, g, b = unpack(color)
	return ("|cff%02x%02x%02x%s|r"):format(r * 255, g * 255, b * 255, text)
end

local function Button(parent, text, width, height)
	local button = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
	button:SetSize(width, height or 22)
	button:SetText(text)
	return button
end

-- An empty, rounded slot outline
local function SlotFrame(parent)
	local slot = CreateFrame("Frame", nil, parent, BackdropTemplateMixin and "BackdropTemplate" or nil)
	slot:SetSize(Card.WIDTH, Card.HEIGHT)
	if slot.SetBackdrop then
		slot:SetBackdrop(SLOT_BACKDROP)
		slot:SetBackdropColor(0, 0, 0, 0.35)
		slot:SetBackdropBorderColor(0.35, 0.35, 0.35, 0.8)
	end
	slot.label = slot:CreateFontString(nil, "OVERLAY", "GameFontDisable")
	slot.label:SetPoint("CENTER")
	return slot
end

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

-- Squads page ---------------------------------------------------------------------------------

local squadsPage = AddPage("Squads", "Interface\\Icons\\INV_Misc_Book_09")
local current = 1 -- selected squad
local filter -- combat type shown in the collection, nil for all
local Refresh

local squadButtons = {}
for i = 1, 3 do
	local button = Button(squadsPage, "", 150, 24)
	button:SetPoint("TOPLEFT", 72 + (i - 1) * 156, -32)
	button:SetScript("OnClick", function()
		current = i
		PlaySound(SOUNDKIT.IG_CHARACTER_INFO_TAB)
		Refresh()
	end)
	squadButtons[i] = button
end

local capButton = Button(squadsPage, "", 110, 24)
capButton:SetPoint("TOPRIGHT", -16, -32)
capButton:SetScript("OnClick", function()
	local squad = ns.squads[current]
	for i, cap in ipairs(ns.CAPS) do
		if cap == squad.cap then
			squad.cap = ns.CAPS[i % #ns.CAPS + 1]
			break
		end
	end
	Refresh()
end)

local frontLabel = squadsPage:CreateFontString(nil, "OVERLAY", "GameFontNormal")
frontLabel:SetPoint("TOPLEFT", ROW_X, -66)
frontLabel:SetText("|TInterface\\ChatFrame\\ChatFrameExpandArrow:12:12:0:0:16:16:16:0:0:16|t FRONT")
local backLabel = squadsPage:CreateFontString(nil, "OVERLAY", "GameFontNormal")
backLabel:SetPoint("TOPRIGHT", -ROW_X, -66)
backLabel:SetText("BACK |TInterface\\ChatFrame\\ChatFrameExpandArrow:12:12|t")
local howTo = squadsPage:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
howTo:SetPoint("TOP", 0, -68)
howTo:SetText("Drag cards in and around  ·  Right-click: remove  ·  Shift-click: make leader")

local slots = {}
for i = 1, ns.MAX_SQUAD do
	local slot = SlotFrame(squadsPage)
	slot:SetPoint("TOPLEFT", ROW_X + (i - 1) * STEP, -84)
	slot.label:SetText(i <= ns.MIN_SQUAD and "empty" or "")
	slot.card = Card.Create(slot)
	slot.card:SetAllPoints()
	slot.card.slot = i
	slot.hint = squadsPage:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	slot.hint:SetPoint("TOP", slot, "BOTTOM", 0, -3)
	slot.hint:SetWidth(Card.WIDTH + 6)
	slots[i] = slot
end

local powerBar = CreateFrame("StatusBar", nil, squadsPage)
powerBar:SetPoint("TOPLEFT", ROW_X, -250)
powerBar:SetSize(330, 14)
powerBar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
local powerBg = powerBar:CreateTexture(nil, "BACKGROUND")
powerBg:SetAllPoints()
powerBg:SetColorTexture(0, 0, 0, 0.6)
local powerText = powerBar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
powerText:SetPoint("CENTER")
local powerLabel = squadsPage:CreateFontString(nil, "OVERLAY", "GameFontNormal")
powerLabel:SetPoint("LEFT", powerBar, "RIGHT", 10, 0)

local mixText = squadsPage:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
mixText:SetPoint("TOPLEFT", ROW_X, -272)
local checkText = squadsPage:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
checkText:SetPoint("TOPLEFT", ROW_X, -292)
checkText:SetWidth(WIDTH - 2 * ROW_X)
checkText:SetJustifyH("LEFT")
local testText = squadsPage:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
testText:SetPoint("TOPLEFT", ROW_X, -312)

local collectionLabel = squadsPage:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
collectionLabel:SetPoint("TOPLEFT", ROW_X, -340)

local filterButtons = {}
for i, kind in ipairs({ "All", "Armor", "Magic", "Assassin" }) do
	local button = Button(squadsPage, kind, 76, 20)
	button:SetPoint("TOPRIGHT", -16 - (4 - i) * 80, -338)
	button:SetScript("OnClick", function()
		filter = kind ~= "All" and kind or nil
		Refresh()
	end)
	button.kind = kind
	filterButtons[i] = button
end

local gridInset = CreateFrame("Frame", nil, squadsPage, INSET)
gridInset:SetPoint("TOPLEFT", 8, -362)
gridInset:SetPoint("BOTTOMRIGHT", -8, 8)
local scroll = CreateFrame("ScrollFrame", nil, gridInset, "UIPanelScrollFrameTemplate")
scroll:SetPoint("TOPLEFT", 8, -8)
scroll:SetPoint("BOTTOMRIGHT", -28, 8)
local grid = CreateFrame("Frame", nil, scroll)
grid:SetSize(WIDTH - 60, 10)
scroll:SetScrollChild(grid)
local COLUMNS = math.floor((WIDTH - 60) / STEP)

-- Squad editing

local function Squad()
	return ns.squads[current]
end

local function PositionOf(squad, id)
	for i, cardId in ipairs(squad.cards) do
		if cardId == id then
			return i
		end
	end
end

local function Remove(squad, id)
	local position = PositionOf(squad, id)
	if position then
		tremove(squad.cards, position)
		if squad.leader == id then
			squad.leader = nil
		end
	end
end

local function Place(squad, id, position)
	Remove(squad, id)
	if #squad.cards >= ns.MAX_SQUAD then
		UIErrorsFrame:AddMessage("A squad holds at most " .. ns.MAX_SQUAD .. " cards.", 1, 0.2, 0.2)
		return
	end
	tinsert(squad.cards, math.min(position or #squad.cards + 1, #squad.cards + 1), id)
end

local function MakeLeader(squad, id)
	local card = ns.byId[id]
	if card.classification == "normal" then
		UIErrorsFrame:AddMessage("Only Elite, Rare or Boss cards can lead.", 1, 0.2, 0.2)
		return
	end
	if not PositionOf(squad, id) then
		Place(squad, id)
	end
	squad.leader = id
	PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
end

-- Dragging: a copy of the card follows the cursor; where it's let go decides what happens

local ghost = Card.Create(UIParent)
ghost:SetFrameStrata("TOOLTIP")
ghost:SetAlpha(0.85)
ghost:EnableMouse(false)
ghost:Hide()
local dragging -- { id, fromSlot }

ghost:SetScript("OnUpdate", function(self)
	local x, y = GetCursorPosition()
	local scale = UIParent:GetEffectiveScale()
	self:ClearAllPoints()
	self:SetPoint("CENTER", UIParent, "BOTTOMLEFT", x / scale, y / scale)
end)

local function StartDrag(card)
	if not card.data then
		return
	end
	dragging = { id = card.data.id, fromSlot = card.slot }
	ghost:SetCard(card.data)
	ghost:Show()
	GameTooltip:Hide()
end

local function StopDrag()
	if not dragging then
		return
	end
	ghost:Hide()
	local squad = Squad()
	local target
	for i, slot in ipairs(slots) do
		if slot:IsMouseOver() then
			target = i
		end
	end
	if target then
		Place(squad, dragging.id, target)
		PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
	elseif dragging.fromSlot then
		Remove(squad, dragging.id) -- dragged out of the squad
		PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_OFF)
	end
	dragging = nil
	Refresh()
end

local function SetupCard(card)
	card:RegisterForDrag("LeftButton")
	card:SetScript("OnDragStart", StartDrag)
	card:SetScript("OnDragStop", StopDrag)
	card:SetScript("OnClick", function(self, mouseButton)
		if type(self.data) ~= "table" then
			return
		end
		local squad = Squad()
		local id = self.data.id
		if IsShiftKeyDown() then
			MakeLeader(squad, id)
		elseif mouseButton == "RightButton" or (not self.slot and PositionOf(squad, id)) then
			Remove(squad, id)
			PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_OFF)
		elseif not self.slot then
			if self.data.exhausted then
				UIErrorsFrame:AddMessage(self.data.name .. " is exhausted.", 1, 0.2, 0.2)
			end
			Place(squad, id)
			PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
		end
		Refresh()
	end)
end

for _, slot in ipairs(slots) do
	SetupCard(slot.card)
end

local gridCards = {}

local QUICK_TEST = { Armor = "Armor wall", Magic = "Magic circle", Assassin = "Assassin pack" }

function Refresh()
	local squad = Squad()
	local cards = ns.SquadCards(squad)
	for i, button in ipairs(squadButtons) do
		button:SetText(ns.squads[i].name)
		if i == current then
			button:LockHighlight()
		else
			button:UnlockHighlight()
		end
	end
	capButton:SetText("Cap: " .. squad.cap)

	-- The row, and where the fight lands on it
	local count = #cards
	for i, slot in ipairs(slots) do
		local data = cards[i]
		slot.card:SetShown(data ~= nil)
		slot.hint:SetText("")
		if data then
			slot.card:SetCard(data, "stamina")
			slot.card:SetLeader(data.id == squad.leader)
			if i == 1 then
				slot.hint:SetText("|cffff8060hit first|r")
			elseif i == 2 then
				slot.hint:SetText("|cffff9cffsplash lands|r")
			end
			if i == count and count > 2 then
				slot.hint:SetText("|cffc0ff60Assassins strike|r")
			end
		end
	end

	local power = ns.Power(cards)
	powerBar:SetMinMaxValues(0, squad.cap)
	powerBar:SetValue(math.min(power, squad.cap))
	powerBar:SetStatusBarColor(power <= squad.cap and 0.3 or 0.9, power <= squad.cap and 0.75 or 0.2, 0.25)
	powerText:SetText(("%d / %d"):format(power, squad.cap))
	powerLabel:SetText("Power")

	local mix = ns.TypeMix(cards)
	for _, family in ipairs(ns.Families(cards)) do
		mix = mix .. ("      |cffffd200%s x%d|r"):format(family.family, family.count)
	end
	mixText:SetText(mix ~= "" and mix or "|cff999999No cards yet|r")

	local parts = {}
	for _, check in ipairs(ns.Checks(squad)) do
		if check.warn then
			parts[#parts + 1] = "|cffffcc00! " .. check.text .. "|r"
		elseif check.ok then
			parts[#parts + 1] = "|cff40ff40+ " .. check.text .. "|r"
		else
			parts[#parts + 1] = "|cffff4040x " .. check.text .. "|r"
		end
	end
	checkText:SetText(table.concat(parts, "    "))

	-- Quick test: the real fight code against training squads of the same power
	if count > 0 then
		local results = {}
		for _, kind in ipairs(ns.TYPE_ORDER) do
			local training = ns.TrainingSquad(kind, power)
			local _, winner = ns.Fight({ cards = cards, leader = squad.leader }, training, 1)
			local result = winner == 1 and "|cff40ff40WIN|r" or winner == 2 and "|cffff4040LOSS|r" or "DRAW"
			results[#results + 1] = QUICK_TEST[kind] .. " " .. result
		end
		testText:SetText("Quick test vs equal power:   " .. table.concat(results, "     "))
	else
		testText:SetText("")
	end

	-- Collection
	local list = {}
	for _, data in ipairs(ns.collection) do
		if not filter or data.type == filter then
			list[#list + 1] = data
		end
	end
	table.sort(list, function(a, b)
		local ra, rb = ns.RARITY_ORDER[a.classification], ns.RARITY_ORDER[b.classification]
		if ra ~= rb then
			return ra < rb
		end
		return a.level > b.level
	end)
	for i, data in ipairs(list) do
		local card = gridCards[i]
		if not card then
			card = Card.Create(grid)
			card:SetPoint("TOPLEFT", ((i - 1) % COLUMNS) * STEP, -math.floor((i - 1) / COLUMNS) * (Card.HEIGHT + 8))
			SetupCard(card)
			gridCards[i] = card
		end
		card:SetCard(data, "stamina")
		card:SetSelected(PositionOf(squad, data.id) ~= nil)
		card:SetLeader(data.id == squad.leader)
		card:Show()
	end
	for i = #list + 1, #gridCards do
		gridCards[i]:Hide()
	end
	grid:SetHeight(math.ceil(#list / COLUMNS) * (Card.HEIGHT + 8))
	collectionLabel:SetText(("Collection  |cff999999%d cards|r"):format(#ns.collection))
	for _, button in ipairs(filterButtons) do
		if (button.kind == "All" and not filter) or button.kind == filter then
			button:LockHighlight()
		else
			button:UnlockHighlight()
		end
	end
end

squadsPage:SetScript("OnShow", function()
	Refresh()
end)

-- Duel page -----------------------------------------------------------------------------------

local duelPage = AddPage("Duel", "Interface\\Icons\\Ability_DualWield")

local theirName = duelPage:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
theirName:SetPoint("TOPLEFT", 72, -34)
local twistText = duelPage:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
twistText:SetPoint("TOPRIGHT", -18, -36)
twistText:SetJustifyH("RIGHT")

local function CardRow(y)
	local row = {}
	for i = 1, ns.MAX_SQUAD do
		local slot = SlotFrame(duelPage)
		slot:SetPoint("TOPLEFT", ROW_X + (i - 1) * STEP, y)
		if slot.SetBackdropBorderColor then
			slot:SetBackdropBorderColor(0.25, 0.25, 0.25, 0.5)
		end
		slot.card = Card.Create(slot)
		slot.card:SetAllPoints()
		slot.card:Hide()
		-- Face down until both have picked
		slot.back = CreateFrame("Frame", nil, slot, BackdropTemplateMixin and "BackdropTemplate" or nil)
		slot.back:SetAllPoints()
		if slot.back.SetBackdrop then
			slot.back:SetBackdrop(SLOT_BACKDROP)
			slot.back:SetBackdropColor(0.15, 0.1, 0.2, 0.95)
			slot.back:SetBackdropBorderColor(0.6, 0.5, 0.8, 1)
		end
		local mark = slot.back:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
		mark:SetPoint("CENTER")
		mark:SetText("?")
		slot.back:Hide()
		slot.note = duelPage:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		slot.note:SetPoint("TOP", slot, "BOTTOM", 0, -2)
		row[i] = slot
	end
	return row
end

local theirRow = CardRow(-62)

local vsText = duelPage:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
vsText:SetPoint("TOP", 0, -212)
vsText:SetFont(vsText:GetFont(), 28, "THICKOUTLINE")
local roundText = duelPage:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
roundText:SetPoint("TOP", vsText, "BOTTOM", 0, -2)
local logText = duelPage:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
logText:SetPoint("TOP", roundText, "BOTTOM", 0, -4)
logText:SetWidth(WIDTH - 40)

local myRow = CardRow(-300)

local pickLabel = duelPage:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
pickLabel:SetPoint("TOP", 0, -456)
pickLabel:SetText("Pick your squad. Ricarda picks too, without seeing yours.")

local pickButtons = {}
for i = 1, 3 do
	local button = Button(duelPage, "", 180, 30)
	button:SetPoint("TOP", (i - 2) * 190, -484)
	pickButtons[i] = button
end
local pickInfo = {}
for i = 1, 3 do
	local text = duelPage:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	text:SetPoint("TOP", pickButtons[i], "BOTTOM", 0, -4)
	pickInfo[i] = text
end

local resultText = duelPage:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
resultText:SetPoint("TOP", 0, -560)
resultText:SetWidth(WIDTH - 40)

local skipButton = Button(duelPage, "Skip to the end", 140, 26)
skipButton:SetPoint("BOTTOM", -76, 18)
local newButton = Button(duelPage, "New duel", 140, 26)
newButton:SetPoint("BOTTOM", 76, 18)

local duelSeed = 1
local twist, ticker, steps, stepIndex, outcome

local function RowFor(side)
	return side == 1 and myRow or theirRow
end

local function ShowSquad(row, squad, faceDown)
	local cards = squad and ns.SquadCards(squad) or {}
	for i, slot in ipairs(row) do
		local data = cards[i]
		slot.note:SetText("")
		slot.card:SetShown(data ~= nil and not faceDown)
		slot.back:SetShown(faceDown and i <= (squad and #squad.cards or 0))
		if data then
			slot.card:SetCard(data, "health")
			slot.card:SetLeader(data.id == squad.leader)
		end
	end
end

local function StopReplay()
	if ticker then
		ticker:Cancel()
		ticker = nil
	end
end

local function Describe(event)
	local attacker = RowFor(event.side)[event.slot].card.data
	local target = RowFor(event.targetSide)[event.targetSlot].card.data
	local color = event.side == 1 and "|cff40ff40" or "|cffff6060"
	return ("%s%s|r %s %s for %d"):format(color, attacker.name, event.splash and "splashes" or "hits", target.name, event.damage)
end

local function ApplyStep(step, animate)
	for _, event in ipairs(step) do
		if event.kind == "round" then
			roundText:SetText("Round " .. event.round)
		elseif event.kind == "hit" then
			local target = RowFor(event.targetSide)[event.targetSlot].card
			if animate then
				if not event.splash then
					RowFor(event.side)[event.slot].card:Lunge(event.side == 1 and 1 or -1)
					logText:SetText(Describe(event))
				end
				target:Hit(event.damage, event.hp, RowFor(event.side)[event.slot].card.data.type == "Magic")
			else
				target:SetHealth(event.hp)
			end
		elseif event.kind == "death" then
			RowFor(event.side)[event.slot].card:SetDead(true)
		end
	end
end

-- Stamina after the duel (6.3): fighters lose health lost in % x 0.6, the others rest
local function UpdateStamina(mySquad, sides)
	local fought = {}
	for _, unit in ipairs(sides[1]) do
		local card = unit.card
		fought[card.id] = true
		local loss = math.floor((1 - unit.hp / unit.maxHp) * 100 * 0.6 + 0.5)
		card.stamina = math.max(0, card.stamina - loss)
		if card.stamina == 0 then
			card.exhausted = 2
		end
		myRow[unit.slot].note:SetText(loss > 0 and ("|cff6aa0ffstamina -%d|r"):format(loss) or "|cff999999no stamina lost|r")
	end
	for _, card in ipairs(ns.collection) do
		if not fought[card.id] then
			if card.exhausted then
				card.exhausted = card.exhausted - 1
				if card.exhausted == 0 then
					card.exhausted = nil
					card.stamina = 100
				end
			else
				card.stamina = math.min(100, card.stamina + 25)
			end
		end
	end
end

local function Finish()
	StopReplay()
	skipButton:Disable()
	local won = outcome.winner == 1
	vsText:SetText(won and "VICTORY!" or outcome.winner == 2 and "DEFEAT" or "DRAW")
	if won then
		vsText:SetTextColor(1, 0.82, 0)
		PlaySound(SOUNDKIT.READY_CHECK)
	else
		vsText:SetTextColor(0.9, 0.2, 0.15)
	end
	UpdateStamina(outcome.mine, outcome.sides)
	resultText:SetText(("Ricarda sent |cffffd200%s|r (%s).  New duel draws a new twist."):format(
		outcome.theirs.name, ns.TypeMix(ns.SquadCards(outcome.theirs))))
end

local function Fight(mine)
	local theirs = ns.opponent.squads[(duelSeed * 7) % 3 + 1]
	ShowSquad(myRow, mine)
	ShowSquad(theirRow, theirs)
	for _, button in ipairs(pickButtons) do
		button:Disable()
	end
	pickLabel:SetText("Both picked. Fight!")
	local events, winner, sides = ns.Fight(
		{ cards = ns.SquadCards(mine), leader = mine.leader },
		{ cards = ns.SquadCards(theirs), leader = theirs.leader },
		duelSeed, twist.key)
	outcome = { winner = winner, sides = sides, mine = mine, theirs = theirs }

	-- Group events into steps: a hit with its splash and the deaths it caused play together
	steps = {}
	local step
	for _, event in ipairs(events) do
		if event.kind == "hit" and not event.splash then
			step = { event }
			steps[#steps + 1] = step
		elseif event.kind == "round" then
			step = { event }
			steps[#steps + 1] = step
		elseif event.kind ~= "end" and step then
			step[#step + 1] = event
		end
	end
	stepIndex = 0
	skipButton:Enable()
	ticker = C_Timer.NewTicker(0.45, function()
		stepIndex = stepIndex + 1
		local current = steps[stepIndex]
		if not current then
			Finish()
			return
		end
		ApplyStep(current, true)
		if current[1].kind == "round" then
			stepIndex = stepIndex + 1 -- a round header doesn't need its own beat
			if steps[stepIndex] then
				ApplyStep(steps[stepIndex], true)
			end
		end
	end)
end

local function NewDuel()
	StopReplay()
	duelSeed = duelSeed + 1
	twist = ns.TWISTS[duelSeed % #ns.TWISTS + 1]
	theirName:SetText("vs |cffff6060Ricarda|r   |cff999999cap 600|r")
	twistText:SetText(("Twist: |cffffd200%s|r\n%s"):format(twist.name, twist.text))
	ShowSquad(myRow, nil)
	ShowSquad(theirRow, nil)
	for i = 1, 5 do
		theirRow[i].back:Show() -- always five, so the size of their pick doesn't show
	end
	vsText:SetText("VS")
	vsText:SetTextColor(1, 0.82, 0)
	roundText:SetText("")
	logText:SetText("")
	resultText:SetText("")
	pickLabel:SetText("Pick your squad. Ricarda picks too, without seeing yours.")
	skipButton:Disable()
	for i, button in ipairs(pickButtons) do
		local squad = ns.squads[i]
		local fits = ns.CanLockIn(squad) and squad.cap <= 600
		button:SetText(squad.name)
		button:SetEnabled(fits)
		button:SetScript("OnClick", function()
			Fight(squad)
		end)
		local cards = ns.SquadCards(squad)
		pickInfo[i]:SetText(fits and ns.TypeMix(cards) or "|cffff4040can't be sent|r (see Squads)")
	end
end

skipButton:SetScript("OnClick", function()
	StopReplay()
	for i = stepIndex + 1, #steps do
		ApplyStep(steps[i], false)
	end
	stepIndex = #steps
	Finish()
end)
newButton:SetScript("OnClick", NewDuel)

duelPage:SetScript("OnShow", NewDuel)
duelPage:SetScript("OnHide", StopReplay)

-- Opening -------------------------------------------------------------------------------------

SelectPage(pages[1])

SLASH_BESTIARY1 = "/bestiary"
SLASH_BESTIARY2 = "/bst"
SlashCmdList["BESTIARY"] = function()
	window:SetShown(not window:IsShown())
end
