local _, ns = ...
local Card = ns.Card

-- The window: character-pane frame with side tabs like Grandma's Game Box. Pages from this file:
--   Squads: your three squads of up to 7 real cards (front left, back right), checks, and your
--           collection below
--   Duel:   a twist, a hidden pick of one of your squads against one of the sparring partner's,
--           then the replay and stamina afterwards
-- Other pages add themselves with ns.AddPage.
local WIDTH, HEIGHT = 720, 690
local STEP = Card.WIDTH + 8 -- the collection grid
local ROW_STEP = Card.WIDTH + 1 -- squad and duel rows: 8 slots need to fit the window
local ROW_X = (WIDTH - (ns.MAX_SQUAD * ROW_STEP - 1)) / 2

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
	window:SetPortraitToAsset("Interface\\Icons\\Ability_Hunter_BeastTaming") -- same as ns.ICON
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
	SetTitle("Bestiary: " .. page.name)
end

-- Tabs from top to bottom by their order
local function LayoutTabs()
	table.sort(pages, function(a, b)
		return a.order < b.order
	end)
	for i, page in ipairs(pages) do
		page.tab:ClearAllPoints()
		if i == 1 then
			page.tab:SetPoint("TOPLEFT", window, "TOPRIGHT", 0, -48)
		else
			page.tab:SetPoint("TOPLEFT", pages[i - 1].tab, "BOTTOMLEFT", 0, -17)
		end
	end
end

-- Adds a page with a side tab. order: lower comes first.
local function AddPage(name, icon, order)
	local page = { name = name, order = order or #pages + 1 }
	page.panel = CreateFrame("Frame", nil, window)
	page.panel:SetAllPoints()
	page.panel:SetFrameLevel(window:GetFrameLevel() + 5)
	page.panel:Hide()

	local tab = CreateFrame("CheckButton", nil, window)
	tab:SetSize(32, 32)
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
	LayoutTabs()
	return page.panel
end
ns.AddPage = AddPage
ns.WINDOW_WIDTH, ns.WINDOW_HEIGHT = WIDTH, HEIGHT

-- Squads page ---------------------------------------------------------------------------------

local squadsPage = AddPage("Squads", "Interface\\Icons\\INV_Misc_Book_09", 3)
local current = 1 -- selected squad
local filter -- combat type shown in the collection, "Named" for named cards (leaders), nil for all
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
capButton:Disable() -- the cap is fixed at ns.POWER_CAP for now
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
howTo:SetText("Drag cards in and around  ·  Right-click: remove  ·  The named card leads")

local slots = {}
for i = 1, ns.MAX_SQUAD do
	local slot = SlotFrame(squadsPage)
	slot:SetPoint("TOPLEFT", ROW_X + (i - 1) * ROW_STEP, -84)
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
powerBar:SetPoint("TOP", 0, -248)
powerBar:SetSize(330, 14)
powerBar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
local powerBg = powerBar:CreateTexture(nil, "BACKGROUND")
powerBg:SetAllPoints()
powerBg:SetColorTexture(0, 0, 0, 0.6)
local powerText = powerBar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
powerText:SetPoint("CENTER")
local powerLabel = squadsPage:CreateFontString(nil, "OVERLAY", "GameFontNormal")
powerLabel:SetPoint("RIGHT", powerBar, "LEFT", -8, 0)

local mixText = squadsPage:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
mixText:SetPoint("TOP", 0, -272)
local familyText = squadsPage:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
familyText:SetPoint("TOP", 0, -298)
familyText:SetWidth(WIDTH - 40)
local checkText = squadsPage:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
checkText:SetPoint("TOP", 0, -320)
checkText:SetWidth(WIDTH - 2 * ROW_X)
checkText:SetJustifyH("CENTER")
checkText:SetSpacing(4)

local collectionLabel = squadsPage:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
collectionLabel:SetPoint("TOPLEFT", ROW_X, -356)

local filterButtons = {}
local FILTERS = { "All", "Tank", "Mage", "Assassin", "Named" }
for i, kind in ipairs(FILTERS) do
	local button = Button(squadsPage, kind, 76, 20)
	button:SetPoint("TOPRIGHT", -16 - (#FILTERS - i) * 80, -354)
	button:SetScript("OnClick", function()
		filter = kind ~= "All" and kind or nil
		Refresh()
	end)
	button.kind = kind
	filterButtons[i] = button
end

local gridInset = CreateFrame("Frame", nil, squadsPage, INSET)
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
emptyGrid:SetText("No cards yet. Kill studied mobs to collect cards, then drag them into a squad.")

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
	end
end

local function Place(squad, id, position)
	Remove(squad, id)
	if #squad.cards >= ns.MAX_SQUAD then
		UIErrorsFrame:AddMessage("A squad holds at most " .. ns.MAX_SQUAD .. " cards.", 1, 0.2, 0.2)
		return
	end
	local leader = ns.SquadLeader(ns.SquadCards(squad))
	if leader and ns.IsNamed(ns.CardById(id)) then
		UIErrorsFrame:AddMessage(("Only one named card per squad: %s already leads it."):format(leader.name), 1, 0.2, 0.2)
		return
	end
	tinsert(squad.cards, math.min(position or #squad.cards + 1, #squad.cards + 1), id)
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
		if mouseButton == "RightButton" or (not self.slot and PositionOf(squad, id)) then
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
	mixText:SetText(mix ~= "" and mix or "|cff999999No cards yet|r")
	familyText:SetText(ns.FamilyText(cards, true))

	local parts = {}
	for _, check in ipairs(ns.Checks(squad)) do
		if check.warn then
			parts[#parts + 1] = "|TInterface\\RaidFrame\\ReadyCheck-Waiting:14:14|t |cffffcc00" .. check.text .. "|r"
		elseif check.ok then
			parts[#parts + 1] = "|TInterface\\RaidFrame\\ReadyCheck-Ready:14:14|t |cff40ff40" .. check.text .. "|r"
		else
			parts[#parts + 1] = "|TInterface\\RaidFrame\\ReadyCheck-NotReady:14:14|t |cffff4040" .. check.text .. "|r"
		end
	end
	checkText:SetText(table.concat(parts, "    "))

	-- Collection
	local list = {}
	local collection = ns.Collection()
	for _, data in ipairs(collection) do
		if not filter or data.type == filter or (filter == "Named" and ns.IsNamed(data)) then
			list[#list + 1] = data
		end
	end
	table.sort(list, function(a, b)
		local ra, rb = ns.RARITY_ORDER[a.classification], ns.RARITY_ORDER[b.classification]
		if ra ~= rb then
			return ra < rb
		end
		return a.name < b.name
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
		card:Show()
	end
	for i = #list + 1, #gridCards do
		gridCards[i]:Hide()
	end
	grid:SetHeight(math.ceil(#list / COLUMNS) * (Card.HEIGHT + 8))
	ns.ClipCards(scroll, gridCards)
	collectionLabel:SetText(("Collection  |cff999999%d cards|r"):format(#collection))
	emptyGrid:SetShown(#collection == 0)
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

local duelPage = AddPage("Duel", "Interface\\Icons\\Ability_DualWield", 4)

local theirName = duelPage:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
theirName:SetPoint("TOPLEFT", 72, -34)
local twistText = duelPage:CreateFontString(nil, "OVERLAY", "GameFontHighlight") -- under the VS

local function CardRow(y)
	local row = {}
	for i = 1, ns.MAX_SQUAD do
		local slot = SlotFrame(duelPage)
		slot:SetPoint("TOPLEFT", ROW_X + (i - 1) * ROW_STEP, y)
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
twistText:SetPoint("TOP", vsText, "BOTTOM", 0, -2)
twistText:SetWidth(WIDTH - 40)
roundText:SetPoint("TOP", twistText, "BOTTOM", 0, -4)
local logText = duelPage:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
logText:SetPoint("TOP", roundText, "BOTTOM", 0, -4)
logText:SetWidth(WIDTH - 40)

local myRow = CardRow(-300)

local pickLabel = duelPage:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
pickLabel:SetPoint("TOP", 0, -456)
pickLabel:SetText("")

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

local readyButton = Button(duelPage, "Ready", 160, 28)
readyButton:SetPoint("TOP", 0, -556)

local resultText = duelPage:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
resultText:SetPoint("TOP", 0, -592)
resultText:SetWidth(WIDTH - 40)

local skipButton = Button(duelPage, "Skip to the end", 140, 26)
skipButton:SetPoint("BOTTOM", -76, 18)
local newButton = Button(duelPage, "New duel", 140, 26)
newButton:SetPoint("BOTTOM", 76, 18)

local duelSeed = time and time() % 100000 or 1 -- a different sparring partner every session
local sparring -- the sparring partner's squads for this duel
local twist, ticker, steps, stepIndex, outcome
local picked -- the squad picked before Ready, can still change


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
		end
	end
end

-- Before Ready, your picked squad can be put in a different order: drag a card in your row onto
-- another slot. That changes the squad itself (also on the Squads tab).
local reorderFrom

local function ReorderStart(card)
	if not picked or not card.data or not card.slot then
		return
	end
	reorderFrom = card.slot
	ghost:SetCard(card.data)
	ghost:Show()
	GameTooltip:Hide()
end

local function ReorderStop()
	if not reorderFrom then
		return
	end
	ghost:Hide()
	local target
	for i, slot in ipairs(myRow) do
		if slot:IsMouseOver() then
			target = i
		end
	end
	if picked and target and target ~= reorderFrom then
		local id = tremove(picked.cards, reorderFrom)
		tinsert(picked.cards, math.min(target, #picked.cards + 1), id)
		ShowSquad(myRow, picked)
		PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
	end
	reorderFrom = nil
end

for i, slot in ipairs(myRow) do
	slot.card.slot = i
	slot.card:RegisterForDrag("LeftButton")
	slot.card:SetScript("OnDragStart", ReorderStart)
	slot.card:SetScript("OnDragStop", ReorderStop)
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
	if event.kind == "heal" then
		return ("%s%s|r heals %s for |cff40ff40%d|r"):format(color, attacker.name, target.name, event.amount)
	end
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
				target:Hit(event.damage, event.hp, RowFor(event.side)[event.slot].card.data.type == "Mage")
			else
				target:SetHealth(event.hp)
			end
		elseif event.kind == "heal" then
			local target = RowFor(event.targetSide)[event.targetSlot].card
			if animate then
				if not event.splash then
					logText:SetText(Describe(event))
				end
				target:Heal(event.amount, event.hp)
			else
				target:SetHealth(event.hp)
			end
		elseif event.kind == "drain" then
			local card = RowFor(event.side)[event.slot].card
			if animate then
				card:Hit(event.damage, event.hp, true)
			else
				card:SetHealth(event.hp)
			end
		elseif event.kind == "rise" then
			local card = RowFor(event.side)[event.slot].card
			card:SetDead(false)
			card:SetHealth(event.hp)
			if animate then
				logText:SetText(("%s rises again!"):format(card.data.name))
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
		local card = ns.SavedCard(unit.card)
		local loss = math.floor((1 - unit.hp / unit.maxHp) * 100 * 0.6 + 0.5)
		if card then
			fought[card] = true
			card.stamina = math.max(0, (card.stamina or 100) - loss)
			if card.stamina == 0 then
				card.exhausted = 2
			end
		end
		myRow[unit.slot].note:SetText(loss > 0 and ("|cff6aa0ffstamina -%d|r"):format(loss) or "|cff999999no stamina lost|r")
	end
	-- Saved on the real cards: the ones that didn't fight rest
	for _, card in pairs(BestiaryChar.cards) do
		if not fought[card] then
			if card.exhausted then
				card.exhausted = card.exhausted - 1
				if card.exhausted == 0 then
					card.exhausted = nil
					card.stamina = 100
				end
			else
				card.stamina = math.min(100, (card.stamina or 100) + 25)
			end
		end
	end
end

local remote -- the duel with another player shown on this page (ns.Duel), nil for sparring
local opponentName -- who we're fighting: the sparring partner or a player

local challengeButton = Button(duelPage, "Challenge target", 150, 24)
challengeButton:SetPoint("TOPRIGHT", -16, -32)
-- A name to challenge; empty: the button challenges your target
local challengeName = CreateFrame("EditBox", nil, duelPage, "InputBoxTemplate")
challengeName:SetSize(130, 24)
challengeName:SetPoint("RIGHT", challengeButton, "LEFT", -10, 0)
challengeName:SetAutoFocus(false)
challengeName:SetMaxLetters(48)
local challengeHint = challengeName:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
challengeHint:SetPoint("LEFT", 2, 0)
challengeHint:SetText("Name (or your target)")

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
	if remote then
		remote.playing = nil
	end
	if not outcome.recorded then
		outcome.recorded = true
		ns.RecordDuel(outcome.events, outcome.winner, outcome.sides, outcome.mine.name, outcome.twist)
	end
	resultText:SetText(("%s sent |cffffd200%s|r (%s).  New duel: the sparring partner, or challenge a player."):format(
		opponentName, outcome.theirs.style or outcome.theirs.name, ns.TypeMix(ns.SquadCards(outcome.theirs))))
	newButton:SetText("New duel")
end

-- Plays a fight: mine and theirs are squads ({ name, cards = ids }), the rest from ns.Fight with
-- us as side 1
local function Play(mine, theirs, events, winner, sides, twistName)
	ShowSquad(myRow, mine)
	ShowSquad(theirRow, theirs)
	for _, button in ipairs(pickButtons) do
		button:Disable()
	end
	readyButton:Disable()
	pickLabel:SetText(("Fight!   |cff40ff40You:|r %s    |cffff6060%s:|r %s"):format(
		ns.FamilyText(ns.SquadCards(mine)), opponentName, ns.FamilyText(ns.SquadCards(theirs))))
	outcome = { winner = winner, sides = sides, mine = mine, theirs = theirs, events = events, twist = twistName }
	for side, units in ipairs(sides) do
		for _, unit in ipairs(units) do
			RowFor(side)[unit.slot].card:SetMaxHealth(unit.maxHp)
		end
	end

	-- Group events into steps: a hit with its splash and the deaths it caused play together
	steps = {}
	local step
	for _, event in ipairs(events) do
		if (event.kind == "hit" or event.kind == "heal") and not event.splash then
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

-- Against the sparring partner: the fight runs here
local function SparringFight(mine)
	local theirs = sparring[(duelSeed * 7) % 3 + 1]
	local events, winner, sides = ns.Fight({ cards = ns.SquadCards(mine) }, { cards = ns.SquadCards(theirs) },
		duelSeed, twist.key)
	Play(mine, theirs, events, winner, sides, twist.name)
end

-- The pick buttons: your three squads, the ones that can't be sent greyed out
local function SetupPicks(enabled)
	picked = nil
	readyButton:Disable()
	for i, button in ipairs(pickButtons) do
		local squad = ns.squads[i]
		local fits = ns.CanLockIn(squad) and squad.cap <= ns.POWER_CAP
		button:SetText(squad.name)
		button:SetEnabled(enabled and fits)
		button:UnlockHighlight()
		button:SetScript("OnClick", function()
			-- Pick (or switch): shows the squad, Ready locks it in
			picked = squad
			for j, other in ipairs(pickButtons) do
				if j == i then
					other:LockHighlight()
				else
					other:UnlockHighlight()
				end
			end
			ShowSquad(myRow, squad)
			readyButton:Enable()
			pickLabel:SetText(("%s picked. Switch or drag cards to reorder, then press Ready."):format(squad.name))
			PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
		end)
		local cards = ns.SquadCards(squad)
		pickInfo[i]:SetText(fits and (ns.TypeMix(cards) .. "\n" .. ns.FamilyText(cards)) or "|cffff4040can't be sent|r (see Squads)")
	end
end

-- An empty board: twist, face-down opponent, nobody picked
local function Board(name, theTwist)
	StopReplay()
	opponentName = name
	theirName:SetText(("vs |cffff6060%s|r   |cff999999cap %d|r"):format(name, ns.POWER_CAP))
	twistText:SetText(("Twist: |cffffd200%s|r  %s"):format(theTwist.name, theTwist.text))
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
	skipButton:Disable()
end

local function NewDuel()
	if remote and not remote.finished then
		return -- a duel with a player is going on
	end
	remote = nil
	duelSeed = duelSeed + 1
	twist = ns.TWISTS[duelSeed % #ns.TWISTS + 1]
	sparring = ns.SparringSquads(duelSeed)
	Board(ns.SPARRING_NAME, twist)
	pickLabel:SetText(("Pick your squad. %s picks too, without seeing yours."):format(ns.SPARRING_NAME))
	newButton:SetText("New duel")
	SetupPicks(true)
end

-- Duels with players ---------------------------------------------------------------------------

local WAITING = {
	challenged = "Challenge sent to %s. They pick first, without seeing yours.",
	incoming = "%s challenged you. Pick your squad, then press Ready.",
	picking = "%s locked in their squad. Pick yours, then press Ready.",
	accepted = "Locked in. Waiting for %s to pick...",
	revealed = "Your squad is shown. Waiting for %s's squad...",
}

-- Shows a duel with a player in its current step
local function ShowRemote(duel)
	remote = duel
	if duel.state ~= "fight" then
		Board(duel.other, duel.twist)
		if duel.mySquad then
			ShowSquad(myRow, duel.mySquad)
		end
		pickLabel:SetText((WAITING[duel.state] or "%s"):format(duel.other))
		SetupPicks(duel.state == "incoming" or duel.state == "picking")
		newButton:SetText("Cancel duel")
	end
end

-- A duel with a player ended without a fight
local ENDINGS = {
	declined = "%s declined (%s).",
	expired = "The duel with %s ended: %s.",
	cancelled = "The duel with %s was cancelled (by %s).",
	offline = "%s is offline.",
	forfeit = "%s loses by forfeit: %s.",
}

local function Ended(duel, event, detail)
	if remote ~= duel then
		ns.Print((ENDINGS[event] or "%s: %s"):format(duel.other, tostring(detail)))
		return
	end
	for _, button in ipairs(pickButtons) do
		button:Disable()
	end
	readyButton:Disable()
	newButton:SetText("New duel")
	pickLabel:SetText("")
	resultText:SetText((ENDINGS[event] or "%s: %s"):format(duel.other, tostring(detail)))
	if event == "forfeit" then
		vsText:SetText("VICTORY!")
		ns.RecordForfeit(duel.other)
	end
end

StaticPopupDialogs["BESTIARY_CHALLENGE"] = {
	text = "%s challenges you to a Bestiary duel.\nTwist: %s",
	button1 = ACCEPT or "Accept",
	button2 = DECLINE or "Decline",
	timeout = 110,
	whileDead = true,
	hideOnEscape = true,
	OnAccept = function(_, duel)
		ns.Show("Duel")
		ShowRemote(duel)
	end,
	OnCancel = function(_, duel, reason)
		if reason == "clicked" or reason == "override" then
			ns.Duel.Decline(duel, "declined")
		end
	end,
}

function ns.Duel.OnEvent(event, duel, detail)
	if event == "incoming" then
		PlaySound(SOUNDKIT.READY_CHECK)
		StaticPopup_Show("BESTIARY_CHALLENGE", duel.other, duel.twist.name, duel)
	elseif event == "challenged" or event == "picking" or event == "accepted" or event == "revealed" then
		if event == "picking" then
			PlaySound(SOUNDKIT.READY_CHECK)
			ns.Show("Duel")
		end
		if remote == duel or event == "challenged" or event == "picking" then
			ShowRemote(duel)
		end
	elseif event == "fight" then
		remote = duel
		duel.playing = true -- the page keeps it when it opens
		ns.Show("Duel")
		Board(duel.other, duel.twist)
		local theirs = ns.ForeignSquad(duel.other, duel.theirs)
		Play(duel.mySquad, theirs, detail.events, detail.winner, detail.sides, duel.twist.name)
		newButton:SetText("New duel")
	else
		Ended(duel, event, detail)
	end
end

-- The player you can challenge: your target, if it's a player of your faction
local function ChallengeTarget()
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

local function Challenge(name)
	local duel, why = ns.Duel.Challenge(name)
	if not duel then
		UIErrorsFrame:AddMessage("Can't challenge: " .. why, 1, 0.2, 0.2)
	end
	return duel
end
ns.ChallengePlayer = function(name)
	ns.Show("Duel")
	return Challenge(name or ChallengeTarget())
end

-- The typed name, else the target
local function ChallengeWho()
	local typed = strtrim(challengeName:GetText() or ""):gsub("%s", "")
	if typed ~= "" then
		return typed
	end
	return ChallengeTarget()
end

local function UpdateChallenge()
	local typed = strtrim(challengeName:GetText() or "")
	challengeHint:SetShown(typed == "" and not challengeName:HasFocus())
	challengeButton:SetText(typed ~= "" and ("Challenge " .. typed) or "Challenge target")
end

local function ChallengeClicked()
	local name = ChallengeWho()
	if not name then
		UIErrorsFrame:AddMessage("Type a name or target a player of your faction to challenge them.", 1, 0.2, 0.2)
		return
	end
	if Challenge(name) then
		challengeName:SetText("")
		challengeName:ClearFocus()
	end
	UpdateChallenge()
end

challengeButton:SetScript("OnClick", ChallengeClicked)
challengeName:SetScript("OnEnterPressed", ChallengeClicked)
challengeName:SetScript("OnEscapePressed", function(self)
	self:SetText("")
	self:ClearFocus()
end)
challengeName:SetScript("OnTextChanged", UpdateChallenge)
challengeName:SetScript("OnEditFocusGained", UpdateChallenge)
challengeName:SetScript("OnEditFocusLost", UpdateChallenge)
challengeButton:SetScript("OnEnter", function(self)
	GameTooltip:SetOwner(self, "ANCHOR_LEFT")
	GameTooltip:AddLine("Challenge the typed name, or your target if the box is empty")
	GameTooltip:AddLine("They need Bestiary too. They pick a squad first, in secret; then you pick yours.", 1, 1, 1, true)
	GameTooltip:Show()
end)
challengeButton:SetScript("OnLeave", GameTooltip_Hide)

readyButton:SetScript("OnClick", function()
	if not picked then
		return
	end
	PlaySound(SOUNDKIT.READY_CHECK)
	local squad = picked
	picked = nil -- locked in: no more reordering
	readyButton:Disable()
	for _, button in ipairs(pickButtons) do
		button:Disable()
	end
	if remote and not remote.finished then
		remote.mySquad = squad
		if remote.role == "opponent" then
			ns.Duel.Accept(remote, ns.SquadCards(squad))
		else
			ns.Duel.Reveal(remote, ns.SquadCards(squad))
		end
	else
		SparringFight(squad)
	end
end)

skipButton:SetScript("OnClick", function()
	StopReplay()
	for i = stepIndex + 1, #steps do
		ApplyStep(steps[i], false)
	end
	stepIndex = #steps
	Finish()
end)
newButton:SetScript("OnClick", function()
	if remote and not remote.finished then
		ns.Duel.Cancel(remote)
		return
	end
	NewDuel()
end)

duelPage:SetScript("OnShow", function()
	if remote and (not remote.finished or remote.playing) then
		return -- keep showing the duel with the player
	end
	NewDuel()
end)
-- Closing during a replay: it plays to the end at once, so stamina and stats still count
duelPage:SetScript("OnHide", function()
	if ticker then
		skipButton:GetScript("OnClick")()
	end
end)

-- Opening -------------------------------------------------------------------------------------

-- The first tab when the window opens for the first time (pages from other files are in by then)
window:SetScript("OnShow", function(self)
	if not self.opened then
		self.opened = true
		SelectPage(pages[1])
	end
end)

ns.ICON = "Interface\\Icons\\Ability_Hunter_BeastTaming"

-- Opens the window on a page ("Squads" or "Duel"), or on the one it was on
function ns.Show(pageName)
	window:Show()
	for _, page in ipairs(pages) do
		if page.name == pageName then
			SelectPage(page)
		end
	end
end

function ns.Toggle()
	window:SetShown(not window:IsShown())
end

SLASH_BESTIARY1 = "/bestiary"
SLASH_BESTIARY2 = "/bst"
SlashCmdList["BESTIARY"] = function(msg)
	local raw = strtrim(msg or "")
	msg = raw:lower()
	if msg == "minimap" then
		ns.ToggleMinimapButton()
	elseif msg == "debug" then
		ns.debug = not ns.debug
		ns.Print(ns.debug and "Debug on: kills and drop rolls are printed. /bst mob shows what's known about your target."
			or "Debug off.")
	elseif msg == "mob" then
		local npcId = ns.NpcId(UnitGUID("target"))
		if npcId then
			ns.DebugReport(npcId)
		else
			ns.Print("Target a mob first.")
		end
	elseif msg == "test" then
		ns.Show("Test")
	elseif msg == "info" then
		ns.Show("Info")
	elseif msg == "duel" or msg:find("^duel ") then
		local name = strtrim(raw:sub(6))
		ns.ChallengePlayer(name ~= "" and name or nil)
	elseif msg == "board" then
		ns.Show("Board")
	elseif msg == "stats" then
		ns.Show("Stats")
	elseif msg == "study" or msg == "studying" then
		ns.Show("Studying")
	elseif msg == "" then
		ns.Toggle()
	else
		ns.Print("/bst: open  ·  /bst mob: what's known about your target  ·  /bst debug: print kills and drop rolls  ·  /bst duel [name]: challenge a player (or your target)  ·  /bst board  ·  /bst study  ·  /bst stats  ·  /bst info: how it works  ·  /bst test: test drops  ·  /bst minimap")
	end
end
