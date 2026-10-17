local _, ns = ...
local Card = ns.Card

-- The window: character-pane frame with side tabs like Grandma's Game Box. Pages from this file:
--   Squads: your three squads of up to 7 real cards, checks, and your
--           collection below
-- Other pages add themselves with ns.AddPage.
local WIDTH, HEIGHT = 860, 760 -- room for a bigger duel board
local STEP = Card.WIDTH + 8 -- the collection grid
local ROW_STEP = ns.MAX_SQUAD > 7 and Card.WIDTH + 1 or Card.WIDTH + 8 -- squad rows fit the window
local ROW_X = (WIDTH - (ns.MAX_SQUAD * ROW_STEP - 1)) / 2

local function TemplateExists(name)
	return C_XMLUtil and C_XMLUtil.GetTemplateInfo and C_XMLUtil.GetTemplateInfo(name) ~= nil
end

local window = CreateFrame("Frame", "BestiaryFrame", UIParent,
	TemplateExists("PortraitFrameTemplate") and "PortraitFrameTemplate" or "BasicFrameTemplateWithInset")
window:SetSize(WIDTH, HEIGHT)
window:SetPoint("TOP", UIParent, "TOP", 0, -50)
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
local filter -- combat type shown in the collection, "Leader" for named cards (leaders), nil for all
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
capButton:Disable() -- the cap follows your level (ns.PowerCap)
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

local sortButton = ns.SortButton(squadsPage, 110, function()
	Refresh() -- this page isn't in ns.Refresh's chain
end)
sortButton:SetPoint("LEFT", collectionLabel, "RIGHT", 10, 0)

local filterButtons = {}
local FILTERS = { "All", "Tank", "Mage", "Warrior", "Leader" }
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

-- A card dropped onto a slot: onto another card of the squad, the two swap places; a card from
-- the collection takes that card's slot (the other one goes back to the collection); onto an
-- empty slot, it goes to the end
local function Drop(squad, id, target)
	local occupant = squad.cards[target]
	local from = PositionOf(squad, id)
	if not occupant then
		Place(squad, id)
	elseif from then
		squad.cards[from], squad.cards[target] = occupant, id -- swap
	elseif occupant ~= id then
		local leader = ns.SquadLeader(ns.SquadCards(squad))
		if leader and leader.id ~= occupant and ns.IsNamed(ns.CardById(id)) then
			UIErrorsFrame:AddMessage(("Only one named card per squad: %s already leads it."):format(leader.name), 1, 0.2, 0.2)
			return
		end
		squad.cards[target] = id -- replaces it
	end
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
	dragging = { id = card.data.id, fromSlot = card.slot, data = card.data }
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
		local id = dragging.id
		if not dragging.fromSlot then
			id = ns.FreeCopy(squad, dragging.data) -- from the collection: the next free copy
		end
		if id then
			Drop(squad, id, target)
			PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
		else
			UIErrorsFrame:AddMessage(("All your copies of %s are in this squad."):format(dragging.data.name), 1, 0.2, 0.2)
		end
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
		if self.slot then
			if mouseButton == "RightButton" then
				Remove(squad, id) -- this copy leaves the squad
				PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_OFF)
			end
		else
			-- a card of the collection: left adds a free copy (with none left, takes them all out),
			-- right takes one copy out
			local free = ns.FreeCopy(squad, self.data)
			local copies = ns.CopyIds(self.data)
			if mouseButton == "RightButton" or not free then
				for i = #copies, 1, -1 do
					if PositionOf(squad, copies[i]) then
						Remove(squad, copies[i])
						if mouseButton == "RightButton" then
							break
						end
					end
				end
				PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_OFF)
			else
				if self.data.exhausted then
					UIErrorsFrame:AddMessage(self.data.name .. " is exhausted.", 1, 0.2, 0.2)
				end
				Place(squad, free)
				PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
			end
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

	-- The row (the order doesn't matter in a fight)
	for i, slot in ipairs(slots) do
		local data = cards[i]
		slot.card:SetShown(data ~= nil)
		slot.hint:SetText("")
		if data then
			slot.card:SetCard(data, "stamina")
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
		if not filter or data.type == filter or (filter == "Leader" and ns.IsNamed(data)) then
			list[#list + 1] = data
		end
	end
	sortButton:Update() -- the list keeps the collection's order
	for i, data in ipairs(list) do
		local card = gridCards[i]
		if not card then
			card = Card.Create(grid)
			card:SetPoint("TOPLEFT", ((i - 1) % COLUMNS) * STEP, -math.floor((i - 1) / COLUMNS) * (Card.HEIGHT + 8))
			SetupCard(card)
			gridCards[i] = card
		end
		card:SetCard(data, "stamina")
		-- copies: how many are still free for this squad; grey once all are in it
		local inSquad = ns.CopiesIn(squad, data)
		local free = ns.Copies(data) - inSquad
		card:SetSelected(inSquad > 0)
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

squadsPage:SetScript("OnShow", function()
	Refresh()
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
	elseif msg == "errors" or msg == "errors clear" then
		local list = BestiaryAccount and BestiaryAccount.errors or ns.errors
		if msg == "errors clear" then
			wipe(list)
			ns.Print("Recorded errors cleared.")
		elseif #list == 0 then
			ns.Print("No errors recorded.")
		else
			for _, entry in ipairs(list) do
				ns.Print(("|cffff6060%dx|r %s"):format(entry.count, entry.msg))
			end
		end
	elseif msg == "lastfight" or msg == "dumplastfight" then
		ns.DumpLastFight()
	elseif msg == "fights" then
		ns.FightLog.Show()
	elseif msg == "board" then
		ns.Show("Board")
	elseif msg == "friends" then
		ns.Show("Friends")
	elseif msg == "stats" then
		ns.Show("Stats")
	elseif msg == "study" or msg == "studying" then
		ns.Show("Studying")
	elseif msg == "" then
		ns.Toggle()
	else
		ns.Print("/bst: open  ·  /bst mob: what's known about your target  ·  /bst debug: print kills and drop rolls  ·  /bst duel [name]: challenge a player (or your target)  ·  /bst friends  ·  /bst board  ·  /bst study  ·  /bst stats  ·  /bst info: how it works  ·  /bst test: test drops  ·  /bst lastfight: dump the last fight  ·  /bst fights: the fight log  ·  /bst minimap")
	end
end
