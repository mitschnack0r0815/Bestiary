local _, ns = ...
local Card = ns.Card

-- PROTOTYPE page for testing drops: pick a mob (your target, or one from the list of mobs seen),
-- look at the card it would give and everything recorded about it, show its drop alert
-- without keeping it, give or remove its card, or make the next kill drop for sure.
local WIDTH = ns.WINDOW_WIDTH
local LIST_WIDTH = 260
local PREVIEW_SCALE = 1.6
local ROW = 20
local INSET = C_XMLUtil and C_XMLUtil.GetTemplateInfo and C_XMLUtil.GetTemplateInfo("InsetFrameTemplate")
	and "InsetFrameTemplate" or nil

local page = ns.AddPage("Test", "Interface\\Icons\\INV_Misc_Gear_01", 9)
local selected -- npc id

local title = page:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
title:SetPoint("TOPLEFT", 72, -34)
title:SetText("Test drops")
local help = page:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
help:SetPoint("TOPLEFT", 72, -56)
help:SetText("Target a mob or pick one from the list. Simulate only shows the drop alert; Give, Rebuild and Remove change your collection.")

local function Button(text, width)
	local button = CreateFrame("Button", nil, page, "UIPanelButtonTemplate")
	button:SetSize(width, 24)
	button:SetText(text)
	return button
end

-- Mobs seen -----------------------------------------------------------------------------------

local listInset = CreateFrame("Frame", nil, page, INSET)
listInset:SetPoint("TOPLEFT", 8, -98)
listInset:SetPoint("BOTTOMLEFT", 8, 8)
listInset:SetWidth(LIST_WIDTH)
local listLabel = page:CreateFontString(nil, "OVERLAY", "GameFontNormal")
listLabel:SetPoint("BOTTOMLEFT", listInset, "TOPLEFT", 6, 6)
local targetButton = Button("Target", 70)
targetButton:SetPoint("BOTTOMRIGHT", listInset, "TOPRIGHT", 0, 2)
local listScroll = CreateFrame("ScrollFrame", nil, listInset, "UIPanelScrollFrameTemplate")
listScroll:SetPoint("TOPLEFT", 6, -6)
listScroll:SetPoint("BOTTOMRIGHT", -26, 6)
local list = CreateFrame("Frame", nil, listScroll)
list:SetSize(LIST_WIDTH - 32, 10)
listScroll:SetScrollChild(list)
local listEmpty = listInset:CreateFontString(nil, "OVERLAY", "GameFontDisable")
listEmpty:SetPoint("CENTER")
listEmpty:SetWidth(LIST_WIDTH - 30)
listEmpty:SetText("No mobs seen yet. Target or mouse over one.")

-- The selected mob ----------------------------------------------------------------------------

local RIGHT_X = LIST_WIDTH + 28

local preview = Card.Create(page)
preview:SetScale(PREVIEW_SCALE)
preview:SetPoint("TOPLEFT", page, "TOPLEFT", RIGHT_X / PREVIEW_SCALE, -84 / PREVIEW_SCALE)
preview:Hide()
local nextDrop = page:CreateFontString(nil, "OVERLAY", "GameFontNormal")
nextDrop:SetPoint("TOP", page, "TOPLEFT", RIGHT_X + Card.WIDTH * PREVIEW_SCALE / 2, -84 - Card.HEIGHT * PREVIEW_SCALE - 8)
nextDrop:SetWidth(Card.WIDTH * PREVIEW_SCALE + 40)

local details = page:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
details:SetPoint("TOPLEFT", page, "TOPLEFT", RIGHT_X + Card.WIDTH * PREVIEW_SCALE + 18, -86)
details:SetPoint("RIGHT", page, "RIGHT", -16, 0)
details:SetJustifyH("LEFT")
details:SetJustifyV("TOP")
details:SetSpacing(3)
local nothing = page:CreateFontString(nil, "OVERLAY", "GameFontDisable")
nothing:SetPoint("TOP", page, "TOPLEFT", (RIGHT_X + WIDTH) / 2, -180)
nothing:SetText("Target a mob, or pick one from the list.")

local BUTTONS_Y = -84 - Card.HEIGHT * PREVIEW_SCALE - 40
local simulateButton = Button("Simulate drop", 100)
simulateButton:SetPoint("TOPLEFT", RIGHT_X, BUTTONS_Y)
local giveButton = Button("Give card", 100)
giveButton:SetPoint("LEFT", simulateButton, "RIGHT", 6, 0)
local rebuildButton = Button("Rebuild card", 100)
rebuildButton:SetPoint("LEFT", giveButton, "RIGHT", 6, 0)
local removeButton = Button("Remove card", 100)
removeButton:SetPoint("LEFT", rebuildButton, "RIGHT", 6, 0)

local force = CreateFrame("CheckButton", nil, page, "UICheckButtonTemplate")
force:SetPoint("TOPLEFT", RIGHT_X - 4, BUTTONS_Y - 36)
local forceText = force.text or force.Text or force:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
forceText:ClearAllPoints()
forceText:SetPoint("LEFT", force, "RIGHT", 2, 1)
forceText:SetFontObject("GameFontHighlight")
forceText:SetText("Force a drop on the next kill (any mob you help kill)")
local forceNote = page:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
forceNote:SetPoint("TOPLEFT", force, "BOTTOMLEFT", 4, -2)
forceNote:SetPoint("RIGHT", page, "RIGHT", -16, 0)
forceNote:SetJustifyH("LEFT")
forceNote:SetText("Skips studying and the drop roll once, then turns itself off. Only for this session. The mob must have been targeted or on a nameplate so its type is known.")

local boost = CreateFrame("CheckButton", nil, page, "UICheckButtonTemplate")
boost:SetPoint("TOPLEFT", force, "BOTTOMLEFT", 0, -34)
local boostText = boost.text or boost.Text or boost:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
boostText:ClearAllPoints()
boostText:SetPoint("LEFT", boost, "RIGHT", 2, 1)
boostText:SetFontObject("GameFontHighlight")
boostText:SetText(("Drop chance %d%% until the next drop"):format(ns.TEST_CHANCE * 100))
local boostNote = page:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
boostNote:SetPoint("TOPLEFT", boost, "BOTTOMLEFT", 4, -2)
boostNote:SetPoint("RIGHT", page, "RIGHT", -16, 0)
boostNote:SetJustifyH("LEFT")
boostNote:SetText("Every kill of a studied mob rolls against this instead of the normal chance. Turns itself off after a card drops. Only for this session.")

-- Hardcore: dying loses the bestiary
local hardcore = CreateFrame("CheckButton", nil, page, "UICheckButtonTemplate")
hardcore:SetPoint("TOPLEFT", boost, "BOTTOMLEFT", 0, -34)
local hardcoreText = hardcore.text or hardcore.Text or hardcore:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
hardcoreText:ClearAllPoints()
hardcoreText:SetPoint("LEFT", hardcore, "RIGHT", 2, 1)
hardcoreText:SetFontObject("GameFontHighlight")
hardcoreText:SetText("|cffff4040Hardcore:|r lose all cards when this character dies")
local hardcoreNote = page:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
hardcoreNote:SetPoint("TOPLEFT", hardcore, "BOTTOMLEFT", 4, -2)
hardcoreNote:SetPoint("RIGHT", page, "RIGHT", -16, 0)
hardcoreNote:SetJustifyH("LEFT")
hardcoreNote:SetText("Every card you own is gone; your own card and what you've studied stay. Saved for this character. Feign Death doesn't count.")

-- The collection
local clearButton = Button("Clear collection", 140)
clearButton:SetPoint("TOPLEFT", hardcoreNote, "BOTTOMLEFT", -4, -14)
local fillButton = Button("Fill with 5 basic cards", 170)
fillButton:SetPoint("LEFT", clearButton, "RIGHT", 8, 0)

local rules = page:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
rules:SetPoint("BOTTOMLEFT", page, "BOTTOMLEFT", RIGHT_X, 16)
rules:SetPoint("RIGHT", page, "RIGHT", -16, 0)
rules:SetJustifyH("LEFT")
rules:SetSpacing(2)

-- Contents ------------------------------------------------------------------------------------

local function Colored(color, text)
	local r, g, b = unpack(color)
	return ("|cff%02x%02x%02x%s|r"):format(r * 255, g * 255, b * 255, text)
end

-- Every mob seen with a known family, most studied first
local function KnownMobs()
	local mobs = {}
	for npcId, info in pairs(BestiaryAccount.mobs) do
		if info.family ~= false then
			local entry = ns.Studied(npcId)
			mobs[#mobs + 1] = { npcId = npcId, info = info, seconds = entry and entry.seconds or 0 }
		end
	end
	table.sort(mobs, function(a, b)
		if a.seconds ~= b.seconds then
			return a.seconds > b.seconds
		end
		return (a.info.name or "") < (b.info.name or "")
	end)
	return mobs
end

-- The card the next drop would give: the owned one with one more star, or a new one
local function NextCard(npcId)
	local owned = BestiaryChar.cards[npcId]
	if owned then
		if ns.CanHaveCopies(owned) and ns.Copies(owned) < ns.MAX_COPIES then
			local copy = {}
			for key, value in pairs(owned) do
				copy[key] = value
			end
			copy.copies = ns.Copies(owned) + 1
			return ns.CardView(copy), "copy", owned
		end
		if owned.stars >= ns.MAX_STARS then
			return ns.CardView(owned), "max", owned
		end
		local copy = {}
		for key, value in pairs(owned) do
			copy[key] = value
		end
		copy.stars = owned.stars + 1
		return ns.CardView(copy), "star", owned
	end
	return ns.BuildCard(npcId), "new"
end

local rows = {}

local function Row(i)
	local row = CreateFrame("Button", nil, list)
	row:SetSize(LIST_WIDTH - 32, ROW)
	row:SetPoint("TOPLEFT", 0, -(i - 1) * ROW)
	row.name = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	row.name:SetPoint("LEFT", 4, 0)
	row.name:SetPoint("RIGHT", -60, 0)
	row.name:SetJustifyH("LEFT")
	row.name:SetWordWrap(false)
	row.value = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	row.value:SetPoint("RIGHT", -4, 0)
	row.selected = row:CreateTexture(nil, "BACKGROUND")
	row.selected:SetAllPoints()
	row.selected:SetColorTexture(1, 0.82, 0, 0.18)
	local highlight = row:CreateTexture(nil, "HIGHLIGHT")
	highlight:SetAllPoints()
	highlight:SetColorTexture(1, 1, 1, 0.08)
	row:SetScript("OnClick", function(self)
		selected = self.npcId
		PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
		ns.Refresh()
	end)
	return row
end

local function Details(npcId, view, result, owned)
	local info = ns.MobInfo(npcId)
	local entry = ns.Studied(npcId) or ns.EmptyStudy()
	local rarity = ns.RARITIES[info.classification] or ns.RARITIES.normal
	local lines = {}
	local function Add(text)
		lines[#lines + 1] = text
	end
	Add(("%s  |cff999999npc %d|r"):format(Colored(rarity.color, info.name or "?"), npcId))
	Add(("%s  ·  %s"):format(rarity.name, tostring(info.creatureType)))
	local ready = entry.seconds >= ns.STUDY_SECONDS
	Add(("Studied %d%%  %s"):format(math.min(100, entry.seconds / ns.STUDY_SECONDS * 100),
		ready and "|cff40ff40ready|r" or ""))
	Add(" ")
	Add(("|cffffd200Seen|r  %d casts (%d heals)  ·  mana %s  ·  class %s  ·  attacks %s"):format(entry.casts,
		entry.heals, entry.mana and "yes" or "no", entry.class and entry.class:lower() or "?",
		entry.attackSpeed and ("every %.1f s"):format(entry.attackSpeed) or "?"))
	local spells = {}
	for spell, count in pairs(entry.spells) do
		spells[#spells + 1] = ("%s x%d"):format(spell, count)
	end
	table.sort(spells)
	local named = 0
	for _, count in pairs(entry.spells) do
		named = named + count
	end
	if entry.casts > named then
		spells[#spells + 1] = ("|cff999999%d hidden|r"):format(entry.casts - named)
	end
	Add("|cffffd200Spells|r  " .. (#spells > 0 and table.concat(spells, ", ") or "none seen"))
	Add(" ")
	local kind, why = ns.TypeFrom(entry, info.family)
	Add(("|cffffd200Type|r  %s  |cff999999%s|r"):format(Colored(ns.TYPES[kind].color, kind), why))
	if owned and owned.type ~= kind then
		Add(("|cff999999Your card stays %s (decided when it dropped; Rebuild card updates it).|r"):format(owned.type))
	end
	Add(("|cffffd200Power|r  %d  ·  %d attack, %d health, %d speed%s"):format(view.power, view.attack, view.health,
		view.speed, view.armor > 0 and (", " .. view.armor .. " armor") or ""))
	Add(("|cffffd200Owned|r  %s"):format(owned and (owned.stars .. " of " .. ns.MAX_STARS .. " stars") or "no"))
	if result == "max" then
		Add("|cffffd200Drop chance|r  none, already at max stars")
	elseif ready then
		local chance, reason = ns.DropChance(npcId, info.classification)
		Add(("|cffffd200Drop chance|r  %.1f%% per kill%s"):format(chance * 100,
			reason and ("  |cff999999(" .. reason .. ")|r") or ""))
	else
		Add("|cffffd200Drop chance|r  none until studied")
	end
	return table.concat(lines, "\n")
end

local function Refresh()
	-- The list
	local mobs = KnownMobs()
	for i, mob in ipairs(mobs) do
		local row = rows[i] or Row(i)
		rows[i] = row
		row.npcId = mob.npcId
		local rarity = ns.RARITIES[mob.info.classification] or ns.RARITIES.normal
		row.name:SetText(Colored(rarity.color, mob.info.name or "?"))
		local owned = BestiaryChar.cards[mob.npcId]
		if owned then
			row.value:SetText(("|cffffd200card %d|r|TInterface\\TargetingFrame\\UI-RaidTargetingIcon_1:10:10|t"):format(owned.stars))
		elseif not mob.info.family then
			row.value:SetText("|cffff4040type?|r")
		elseif mob.seconds >= ns.STUDY_SECONDS then
			row.value:SetText("|cff40ff40ready|r")
		else
			row.value:SetText(("%d%%"):format(mob.seconds / ns.STUDY_SECONDS * 100))
		end
		row.selected:SetShown(mob.npcId == selected)
		row:Show()
	end
	for i = #mobs + 1, #rows do
		rows[i]:Hide()
	end
	list:SetHeight(math.max(10, #mobs * ROW))
	listEmpty:SetShown(#mobs == 0)
	listLabel:SetText(("Mobs seen  |cff999999%d|r"):format(#mobs))

	-- The selected mob
	local info = selected and ns.MobInfo(selected)
	local view, result, owned
	if info and info.family then
		view, result, owned = NextCard(selected)
	end
	preview:SetShown(view ~= nil)
	nothing:SetShown(view == nil)
	if view then
		preview:SetCard(view)
		nextDrop:SetText(result == "new" and "Next drop: |cff40ff40new card|r"
			or result == "copy" and ("Next drop: |cff40ff40copy %d of %d|r"):format(ns.Copies(owned) + 1, ns.MAX_COPIES)
			or result == "star" and ("Next drop: |cff40ff40+1 star|r (%d to %d)"):format(owned.stars, owned.stars + 1)
			or ("|cff999999At %d stars, no more drops|r"):format(ns.MAX_STARS))
		details:SetText(Details(selected, view, result, owned))
	else
		nextDrop:SetText("")
		details:SetText("")
		if info then
			nothing:SetText(("%s: unknown creature type %q, it can't have a card."):format(info.name or "?", tostring(info.creatureType)))
		else
			nothing:SetText("Target a mob, or pick one from the list.")
		end
	end
	simulateButton:SetEnabled(view ~= nil)
	giveButton:SetEnabled(view ~= nil and result ~= "max")
	removeButton:SetEnabled(owned ~= nil)
	rebuildButton:SetEnabled(owned ~= nil)

	boost:SetChecked(ns.testChance)
	boostText:SetTextColor(ns.testChance and 0.25 or 1, 1, ns.testChance and 0.25 or 1)
	hardcore:SetChecked(ns.IsHardcore())
	force:SetChecked(ns.forceDrop)
	forceText:SetTextColor(ns.forceDrop and 0.25 or 1, 1, ns.forceDrop and 0.25 or 1)

	rules:SetText(("Drop rules now: %d s of study, then per kill normal %d%%, elite %d%%, rare %d%%, rare elite %d%%, boss %d%%. "
		.. "Rares and bosses drop for sure the first time. Group x%.2f, raid x%.2f, halved for each drop of that mob in the last hour. "
		.. "Starter boost: x" .. ns.STARTER_BOOST .. " under " .. ns.STARTER_CARDS .. " cards, then halving every "
		.. ns.STARTER_HALF .. " cards, gone at " .. ns.STARTER_END .. ".")
		:format(ns.STUDY_SECONDS, ns.DROP_CHANCE.normal * 100, ns.DROP_CHANCE.elite * 100, ns.DROP_CHANCE.rare * 100,
			ns.DROP_CHANCE.rareelite * 100, ns.DROP_CHANCE.worldboss * 100, ns.GROUP_FACTOR.party, ns.GROUP_FACTOR.raid))
end

-- Actions -------------------------------------------------------------------------------------

local function SelectTarget()
	local npcId = ns.NpcId(UnitGUID("target"))
	if npcId and ns.MobInfo(npcId) then
		selected = npcId
		return true
	end
end

targetButton:SetScript("OnClick", function()
	if not SelectTarget() then
		UIErrorsFrame:AddMessage("Target a mob first.", 1, 0.2, 0.2)
	end
	Refresh()
end)

rebuildButton:SetScript("OnClick", function()
	local before = BestiaryChar.cards[selected] and BestiaryChar.cards[selected].type
	local card = ns.RebuildCard(selected)
	if card then
		ns.Print(("Rebuilt %s: %s%s."):format(card.name, card.type, before ~= card.type and (" (was " .. tostring(before) .. ")") or ""))
		PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
	end
	Refresh()
end)

simulateButton:SetScript("OnClick", function()
	local view, result = NextCard(selected)
	if view then
		ns.ShowLoot(nil, view, result, "test, not kept")
	end
end)

giveButton:SetScript("OnClick", function()
	if not ns.GiveCard(selected, nil, true) then
		UIErrorsFrame:AddMessage("Already at " .. ns.MAX_STARS .. " stars.", 1, 0.2, 0.2)
	end
	Refresh()
end)

removeButton:SetScript("OnClick", function()
	local owned = BestiaryChar.cards[selected]
	if owned then
		ns.RemoveCard(selected)
		ns.Print(("Removed %s from your collection."):format(owned.name or "?"))
		PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_OFF)
	end
	Refresh()
end)

StaticPopupDialogs["BESTIARY_CLEAR"] = {
	text = "Clear your whole collection?\nAll cards are removed and the squads emptied. Your own card stays.",
	button1 = YES or "Yes",
	button2 = NO or "No",
	timeout = 0,
	whileDead = true,
	hideOnEscape = true,
	OnAccept = function()
		ns.ResetCollection()
		ns.Print("Collection cleared.")
	end,
}

StaticPopupDialogs["BESTIARY_HARDCORE"] = {
	text = "Play this character hardcore?\nIf it dies, every card it owns is lost. Your own card and what you've studied stay.",
	button1 = YES or "Yes",
	button2 = NO or "No",
	timeout = 0,
	whileDead = true,
	hideOnEscape = true,
	OnAccept = function()
		ns.SetHardcore(true)
		Refresh()
	end,
	OnCancel = function()
		Refresh()
	end,
}

clearButton:SetScript("OnClick", function()
	StaticPopup_Show("BESTIARY_CLEAR")
end)

fillButton:SetScript("OnClick", function()
	local given = ns.FillBasicCards(5)
	ns.Print(("Added %d basic cards (common, 1 star)."):format(given))
	PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
end)

hardcore:SetScript("OnClick", function(self)
	if self:GetChecked() then
		self:SetChecked(false) -- only after saying yes
		StaticPopup_Show("BESTIARY_HARDCORE")
	else
		ns.SetHardcore(false)
	end
	Refresh()
end)

boost:SetScript("OnClick", function(self)
	ns.testChance = self:GetChecked() and true or false
	ns.Print(ns.testChance and ("Drop chance is %d%% until the next drop (studied mobs only)."):format(ns.TEST_CHANCE * 100)
		or "Drop chance back to normal.")
	Refresh()
end)

force:SetScript("OnClick", function(self)
	ns.forceDrop = self:GetChecked() and true or false
	ns.Print(ns.forceDrop and "Forced drop armed: the next mob you help kill drops its card."
		or "Forced drop off.")
	Refresh()
end)

page:SetScript("OnShow", function()
	if not selected then
		SelectTarget()
	end
	Refresh()
end)

-- While open: follow the target, keep the study numbers moving
local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_TARGET_CHANGED")
events:SetScript("OnEvent", function()
	if page:IsVisible() then
		C_Timer.After(0, function() -- after the tracker cached the new target
			if SelectTarget() then
				Refresh()
			end
		end)
	end
end)
local elapsed = 0
page:SetScript("OnUpdate", function(_, delta)
	elapsed = elapsed + delta
	if elapsed >= 1 then
		elapsed = 0
		Refresh()
	end
end)

-- Called when something changes (new card, finished studying, forced drop used)
local refreshCollection = ns.Refresh
function ns.Refresh()
	if refreshCollection then
		refreshCollection()
	end
	if page:IsVisible() then
		Refresh()
	end
end
