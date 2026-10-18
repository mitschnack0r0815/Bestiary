local _, ns = ...
local Card = ns.Card
local Battles = ns.Battles
local Battle = ns.Battle

-- Battle page (ARCHITECTURE.md 5.5): Pokémon-style battles. Pick a team and the card it leads
-- with (blind), then take turns: a move of your card on the field (the buttons below it) or a
-- switch (click a card of your bench). After a knockout you pick the next card. Their card is
-- top right, yours bottom left, the benches beside them. Of theirs only the card on the field is
-- shown (decided); their bench stays face down until the battle is over.
local WIDTH = ns.WINDOW_WIDTH
local BIG = 1.45 -- the cards on the field
local SMALL = 0.66 -- the benches
local BIG_W, BIG_H = Card.WIDTH * BIG, Card.HEIGHT * BIG
local SMALL_W, SMALL_H = Card.WIDTH * SMALL, Card.HEIGHT * SMALL
local AI_DELAY = 0.9
local MOVE_W, MOVE_H = 128, 34
local SLOT_BACKDROP = {
	bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
	edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
	tile = true, tileSize = 16, edgeSize = 14,
	insets = { left = 4, right = 4, top = 4, bottom = 4 },
}
local ICONS = {
	attack = "Interface\\Icons\\Ability_MeleeDamage",
	spell = "Interface\\Icons\\Spell_Fire_FlameBolt",
	heal = "Interface\\Icons\\Spell_Holy_Heal",
	mend = "Interface\\Icons\\Spell_Holy_FlashHeal",
	restore = "Interface\\Icons\\Spell_Holy_PrayerOfHealing02",
	guard = "Interface\\Icons\\Ability_Defend",
	wait = "Interface\\Icons\\INV_Misc_PocketWatch_01",
	immune = "Interface\\Icons\\Spell_Holy_DivineIntervention",
}

local page = ns.AddPage("Battle", "Interface\\Icons\\Ability_Hunter_Pet_Bear", 4.4)

local function Button(parent, text, width, height)
	local button = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
	button:SetSize(width, height or 22)
	button:SetText(text)
	return button
end

local shown -- the game on the page
local pickedTeam, pickedLead -- before Ready
local mending -- picked Mend: the next click on a bench card is its target
local seenEvents = {}
local Refresh

-- Top ----------------------------------------------------------------------------------------------

local theirName = page:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
theirName:SetPoint("TOPLEFT", 72, -34)

local challengeButton = Button(page, "Challenge target", 150, 24)
challengeButton:SetPoint("TOPRIGHT", -16, -32)
local challengeName = CreateFrame("EditBox", nil, page, "InputBoxTemplate")
challengeName:SetSize(130, 24)
challengeName:SetPoint("RIGHT", challengeButton, "LEFT", -10, 0)
challengeName:SetAutoFocus(false)
challengeName:SetMaxLetters(48)
local challengeHint = challengeName:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
challengeHint:SetPoint("LEFT", 2, 0)
challengeHint:SetText("Name (or your target)")

local sparringButton = Button(page, "New sparring battle", 140, 22)
sparringButton:SetPoint("TOPRIGHT", -16, -62)
local chartButton = Button(page, "Type chart", 100, 22)
chartButton:SetPoint("RIGHT", sparringButton, "LEFT", -8, 0)
chartButton:SetScript("OnEnter", function(self)
	ns.ShowTypeChart(self)
end)
chartButton:SetScript("OnLeave", GameTooltip_Hide)

-- Cards ------------------------------------------------------------------------------------------

local function Slot(scale, w, h)
	local slot = CreateFrame("Frame", nil, page, BackdropTemplateMixin and "BackdropTemplate" or nil)
	slot:SetSize(w, h)
	if slot.SetBackdrop then
		slot:SetBackdrop(SLOT_BACKDROP)
		slot:SetBackdropColor(0, 0, 0, 0.35)
		slot:SetBackdropBorderColor(0.25, 0.25, 0.25, 0.5)
	end
	slot.card = Card.Create(slot)
	slot.card:SetScale(scale)
	slot.card:SetPoint("TOPLEFT")
	slot.card:Hide()
	slot.back = CreateFrame("Frame", nil, slot, BackdropTemplateMixin and "BackdropTemplate" or nil)
	slot.back:SetAllPoints()
	if slot.back.SetBackdrop then
		slot.back:SetBackdrop(SLOT_BACKDROP)
		slot.back:SetBackdropColor(0.15, 0.1, 0.2, 0.95)
		slot.back:SetBackdropBorderColor(0.6, 0.5, 0.8, 1)
	end
	slot.mark = slot.back:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
	slot.mark:SetPoint("CENTER")
	slot.mark:SetText("?")
	slot.back:Hide()
	slot.note = page:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	slot.note:SetPoint("TOP", slot, "BOTTOM", 0, -2)
	return slot
end

-- Status effects above a card on the field: icon and turns left
local STATUS_TEXT = {
	stun = "Stunned: it loses its next turn (it can still switch out).",
	fear = "Feared: it loses its turns until something hits it.",
	silence = "Silenced: no spells or heals.",
	disarm = "Disarmed: no attacks.",
	slow = "Slowed: it does 30% less damage.",
	poison = "Poisoned: takes %d damage at the start of each of its side's turns, on the bench too.",
	guard = "Guarding: the next hit on it is halved.",
	immune = "Just controlled: no stun, fear, silence or disarm works on it for now.",
}

local function StatusIcons(slot)
	slot.status = {}
	for i = 1, 6 do
		local icon = CreateFrame("Frame", nil, slot)
		icon:SetSize(22, 22)
		icon:SetPoint("BOTTOMLEFT", slot, "TOPLEFT", (i - 1) * 25, 3)
		icon.texture = icon:CreateTexture(nil, "ARTWORK")
		icon.texture:SetAllPoints()
		ns.SoftCorners(icon, icon.texture)
		icon.text = icon:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
		icon.text:SetPoint("BOTTOMRIGHT", 2, -1)
		icon:SetScript("OnEnter", function(self)
			if self.status then
				GameTooltip:SetOwner(self, "ANCHOR_TOP")
				GameTooltip:AddLine(self.status.name)
				GameTooltip:AddLine(STATUS_TEXT[self.status.key]:format(self.status.damage or 0), 1, 1, 1, true)
				if self.status.turns then
					GameTooltip:AddLine(("%d %s left"):format(self.status.turns, self.status.turns == 1 and "turn" or "turns"), 0.7, 0.7, 0.7)
				end
				GameTooltip:Show()
			end
		end)
		icon:SetScript("OnLeave", GameTooltip_Hide)
		icon:Hide()
		slot.status[i] = icon
	end
end

local theirField = Slot(BIG, BIG_W, BIG_H)
theirField:SetPoint("TOPRIGHT", -150, -112)
StatusIcons(theirField)
local myField = Slot(BIG, BIG_W, BIG_H)
myField:SetPoint("TOPLEFT", 150, -300)
StatusIcons(myField)

local function BenchRow(x, y, label)
	local row = {}
	for i = 1, Battle.MAX_TEAM do
		local slot = Slot(SMALL, SMALL_W, SMALL_H)
		slot:SetPoint("TOPLEFT", x + (i - 1) * (SMALL_W + 8), y)
		row[i] = slot
	end
	row.label = page:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	row.label:SetPoint("BOTTOMLEFT", row[1], "TOPLEFT", 0, 4)
	row.label:SetText(label)
	return row
end

local theirBench = BenchRow(72, -112, "Their team")
local myBench = BenchRow(WIDTH - 72 - Battle.MAX_TEAM * (SMALL_W + 8) + 8, -410, "Your team")

local centerText = page:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
centerText:SetPoint("CENTER", page, "TOPLEFT", WIDTH / 2, -270)
centerText:SetFont(centerText:GetFont(), 26, "THICKOUTLINE")
local matchText = page:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
matchText:SetPoint("TOP", centerText, "BOTTOM", 0, -8)
matchText:SetWidth(300)

-- Bottom: team pick, lead, moves, log --------------------------------------------------------------

local promptText = page:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
promptText:SetPoint("TOP", 0, -570)
promptText:SetWidth(WIDTH - 40)

local pickButtons, pickInfo = {}, {}
for i = 1, ns.TEAM_COUNT do
	local button = Button(page, "", 180, 26)
	button:SetPoint("TOP", (i - 2) * 200, -596)
	pickButtons[i] = button
	local text = page:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	text:SetPoint("TOP", button, "BOTTOM", 0, -3)
	text:SetWidth(196)
	pickInfo[i] = text
end

-- Move buttons: icon and name; the tooltip says what it does
local moveButtons = {}
for i = 1, 7 do
	local button = Button(page, "", MOVE_W, MOVE_H)
	button.icon = button:CreateTexture(nil, "OVERLAY")
	button.icon:SetSize(MOVE_H - 10, MOVE_H - 10)
	button.icon:SetPoint("LEFT", 5, 0)
	ns.SoftCorners(button, button.icon)
	local text = button:GetFontString()
	if text then
		text:ClearAllPoints()
		text:SetPoint("LEFT", button.icon, "RIGHT", 4, 0)
		text:SetPoint("RIGHT", -4, 0)
		text:SetJustifyH("LEFT")
	end
	button:SetMotionScriptsWhileDisabled(true)
	button:SetScript("OnLeave", GameTooltip_Hide)
	button:Hide()
	moveButtons[i] = button
end

local logBox = CreateFrame("Frame", nil, page, BackdropTemplateMixin and "BackdropTemplate" or nil)
logBox:SetPoint("TOPLEFT", 60, -600)
logBox:SetPoint("TOPRIGHT", -60, -600)
logBox:SetHeight(108)
if logBox.SetBackdrop then
	logBox:SetBackdrop(SLOT_BACKDROP)
	logBox:SetBackdropColor(0, 0, 0, 0.45)
	logBox:SetBackdropBorderColor(0.4, 0.33, 0.2, 0.9)
end
local log = CreateFrame("ScrollingMessageFrame", nil, logBox)
log:SetPoint("TOPLEFT", 8, -6)
log:SetPoint("BOTTOMRIGHT", -8, 6)
log:SetFontObject(GameFontHighlightSmall)
log:SetJustifyH("LEFT")
log:SetFading(false)
log:SetMaxLines(1000)
log:EnableMouseWheel(true)
log:SetScript("OnMouseWheel", function(self, delta)
	if delta > 0 then
		self:ScrollUp()
	else
		self:ScrollDown()
	end
end)
logBox:Hide()
local logGame, logShown

local quitButton = Button(page, "Resign", 140, 26)
quitButton:SetPoint("BOTTOM", -170, 18)
local readyButton = Button(page, "Ready", 160, 28)
readyButton:SetPoint("BOTTOM", 0, 17)

-- Showing ------------------------------------------------------------------------------------------

local function ClearSlot(slot, faceDown)
	slot.card:Hide()
	slot.card:SetActive(false)
	slot.card:SetScript("OnClick", nil)
	slot.mark:SetText("?")
	slot.back:SetShown(faceDown == true)
	slot.note:SetText("")
	for _, icon in ipairs(slot.status or {}) do
		icon:Hide()
	end
end

local function ClearAll()
	ClearSlot(theirField)
	ClearSlot(myField)
	for i = 1, Battle.MAX_TEAM do
		ClearSlot(theirBench[i])
		ClearSlot(myBench[i])
	end
	for _, button in ipairs(moveButtons) do
		button:Hide()
	end
	for i = 1, ns.TEAM_COUNT do
		pickButtons[i]:Hide()
		pickInfo[i]:Hide()
	end
	readyButton:Hide()
	logBox:Hide()
	matchText:SetText("")
end

local function Name(game, unit)
	local color = unit.side == Battles.MySide(game) and "|cff40ff40" or "|cffff6060"
	return color .. unit.card.name .. "|r"
end

-- A card in the log: theirs only by name while it's on the field (their bench stays hidden)
local function Seen(game, state, unit)
	if unit.side == Battles.MySide(game) or state.winner or state.sides[unit.side].active == unit.slot then
		return Name(game, unit)
	end
	return "|cffff6060a card on their bench|r"
end

-- A card view shown in a slot
local function ShowCard(slot, view, hp, maxHp)
	view.battle = true -- no leaders, cap or stamina in battles
	slot.card:SetCard(view, "health")
	if maxHp then
		slot.card:SetMaxHealth(maxHp)
		slot.card:SetHealth(hp)
	end
	slot.card:SetUsedUp(false)
	slot.card:SetSelected(false)
	slot.card:SetDead(hp ~= nil and hp <= 0)
	slot.card:Show()
end

local function ShowStatuses(slot, unit)
	local list = {}
	local function Add(key, turns, damage)
		local def = ns.ABILITIES[key]
		list[#list + 1] = { key = key, turns = turns, damage = damage, name = def and def.name or (key == "guard" and "Guard" or "Immune"),
			icon = def and def.icon or ICONS[key] }
	end
	if unit.hp > 0 then
		if unit.stunned then Add("stun", unit.stunned) end
		if unit.feared then Add("fear", unit.feared) end
		if unit.silenced then Add("silence", unit.silenced) end
		if unit.disarmed then Add("disarm", unit.disarmed) end
		if unit.slowed then Add("slow", unit.slowed) end
		if unit.poison then Add("poison", unit.poison.turns, unit.poison.damage) end
		if unit.guard then Add("guard") end
		if (unit.immune or 0) > 0 and not (unit.stunned or unit.feared or unit.silenced or unit.disarmed) then
			Add("immune", unit.immune)
		end
	end
	for i, icon in ipairs(slot.status) do
		local status = list[i]
		icon:SetShown(status ~= nil)
		icon.status = status
		if status then
			icon.texture:SetTexture(status.icon)
			icon.text:SetText(status.turns or "")
		end
	end
end

-- What happened, in words
local VERBS = { stun = "stuns", fear = "fears", silence = "silences", disarm = "disarms", slow = "slows", poison = "poisons" }

local function Describe(game, state, event)
	local function Unit(side, slot)
		return state.sides[side].units[slot]
	end
	if event.kind == "hit" then
		local by, at = Unit(event.side, event.slot), Unit(event.targetSide, event.targetSlot)
		local how
		if event.action == "spell" then
			how = ("casts %s at %s"):format(by.spellName or "a spell", Name(game, at))
		elseif event.ability then
			how = ("uses %s on %s"):format((ns.AbilityLook(event.ability)), Name(game, at))
		else
			how = ("hits %s"):format(Name(game, at))
		end
		local effective = ns.TypeWords(event.factor or 1)
		return ("%s %s: %d%s%s"):format(Name(game, by), how, event.damage, effective and (", " .. effective) or "",
			event.guarded and " |cff999999(guarded)|r" or "")
	elseif event.kind == "heal" then
		local by, at = Unit(event.side, event.slot), Unit(event.targetSide, event.targetSlot)
		return by == at and ("%s heals itself for |cff40ff40%d|r"):format(Name(game, by), event.amount)
			or ("%s heals %s for |cff40ff40%d|r"):format(Name(game, by), Seen(game, state, at), event.amount)
	elseif event.kind == "effect" then
		return ("%s %s %s (%d %s)"):format(Name(game, Unit(event.side, event.slot)), VERBS[event.effect] or event.effect,
			Name(game, Unit(event.targetSide, event.targetSlot)), event.turns, event.turns == 1 and "turn" or "turns")
	elseif event.kind == "immune" then
		return ("%s can't be controlled again so soon"):format(Name(game, Unit(event.targetSide, event.targetSlot)))
	elseif event.kind == "tick" then
		return ("%s takes %d poison damage"):format(Seen(game, state, Unit(event.side, event.slot)), event.damage)
	elseif event.kind == "guard" then
		return ("%s guards"):format(Name(game, Unit(event.side, event.slot)))
	elseif event.kind == "wait" then
		return ("%s %s"):format(Name(game, Unit(event.side, event.slot)), event.why and ("is " .. event.why .. ": its turn passes") or "waits")
	elseif event.kind == "unfeared" then
		return ("%s is hit out of its fear"):format(Name(game, Unit(event.side, event.slot)))
	elseif event.kind == "faint" then
		return ("%s is knocked out!"):format(Seen(game, state, Unit(event.side, event.slot)))
	elseif event.kind == "switch" or event.kind == "send" or event.kind == "lead" then
		local mine = event.side == Battles.MySide(game)
		local who = mine and "You" or (game.role == "sparring" and ns.SPARRING_NAME or game.other)
		local verb = event.kind == "switch" and "switch to" or event.kind == "send" and "send in" or "lead with"
		if not mine then
			verb = event.kind == "switch" and "switches to" or event.kind == "send" and "sends in" or "leads with"
		end
		return ("%s %s %s"):format(who, verb, Name(game, Unit(event.side, event.slot)))
	elseif event.kind == "end" and event.why == "turns" then
		return "Out of turns: the side with more health left wins"
	end
end

local function ShowLog(game, state)
	if logGame ~= game.id or (logShown or 0) > #state.events then
		log:Clear()
		logGame, logShown = game.id, 0
	end
	for i = logShown + 1, #state.events do
		local text = Describe(game, state, state.events[i])
		if text then
			log:AddMessage(("|cff999999%3d|r  %s"):format((state.events[i].turn or 0) + 1, text))
		end
	end
	logShown = #state.events
	logBox:Show()
end

local function FieldSlot(game, side)
	return side == Battles.MySide(game) and myField or theirField
end

-- New events since we last looked animate (only on the field)
local function Animate(game, state)
	local from = seenEvents[game.id]
	seenEvents[game.id] = #state.events
	if not from or not page:IsVisible() then
		return
	end
	for i = from + 1, #state.events do
		local event = state.events[i]
		local active = function(side, slot)
			return state.sides[side].active == slot
		end
		if event.kind == "hit" and active(event.targetSide, event.targetSlot) then
			FieldSlot(game, event.side).card:Lunge(event.side == Battles.MySide(game) and 1 or -1)
			FieldSlot(game, event.targetSide).card:Hit(event.damage, event.hp, event.magic)
		elseif event.kind == "heal" and active(event.targetSide, event.targetSlot) then
			FieldSlot(game, event.targetSide).card:Heal(event.amount, event.hp)
		elseif event.kind == "tick" and active(event.side, event.slot) then
			FieldSlot(game, event.side).card:Hit(event.damage, event.hp, true)
		end
	end
end

-- Both benches: every card of the team (the one on the field shaded), knocked out ones face down.
-- Theirs stays hidden: "?" on the bench, "Field" for the one fighting, "KO" once knocked out (all
-- shown once the battle is over).
local function ShowBenches(game, state)
	for side = 1, 2 do
		local mine = side == Battles.MySide(game)
		local row = mine and myBench or theirBench
		local team = state.sides[side]
		for slot = 1, Battle.MAX_TEAM do
			local unit = team.units[slot]
			local frame = row[slot]
			ClearSlot(frame)
			if unit and not mine and not state.winner then
				frame.back:Show()
				frame.mark:SetText(unit.hp <= 0 and "|cff999999KO|r" or slot == team.active and "|cffffd200Field|r" or "?")
			elseif unit then
				ShowCard(frame, unit.card, unit.hp, unit.maxHp)
				if slot == team.active and unit.hp > 0 then
					frame.card:SetUsedUp(true)
					frame.card.usedText:SetText("Fighting")
				end
				if unit.poison and unit.hp > 0 then
					frame.note:SetText("|cff60ff60poisoned|r")
				end
				frame.card.unit = unit
			end
		end
	end
end

local function ShowField(game, state)
	for side = 1, 2 do
		local unit = Battle.Active(state, side)
		local slot = FieldSlot(game, side)
		ClearSlot(slot)
		if unit then
			ShowCard(slot, unit.card, unit.hp, unit.maxHp)
			ShowStatuses(slot, unit)
			local expected = Battle.Expecting(state)
			slot.card:SetActive(expected == side and not state.winner)
		end
	end
	local mine, theirs = Battle.Active(state, Battles.MySide(game)), Battle.Active(state, 3 - Battles.MySide(game))
	if mine and theirs and mine.hp > 0 and theirs.hp > 0 and not state.winner then
		local give, take = ns.TypeFactor(mine.card.family, theirs.card.family), ns.TypeFactor(theirs.card.family, mine.card.family)
		local parts = {}
		if give ~= 1 then
			parts[#parts + 1] = ("Your hits: %s"):format(ns.TypeWords(give))
		end
		if take ~= 1 then
			parts[#parts + 1] = ("Their hits: %s"):format(ns.TypeWords(take))
		end
		matchText:SetText(table.concat(parts, "\n"))
	end
end

-- What a move does, for its tooltip
local function MoveTooltip(button)
	local entry, state, side = button.entry, button.state, button.side
	local unit, enemy = Battle.Active(state, side), Battle.Active(state, 3 - side)
	GameTooltip:SetOwner(button, "ANCHOR_TOP")
	GameTooltip:AddLine(entry.ability and (ns.AbilityLook(entry.ability)) or entry.name)
	if entry.key == "attack" or entry.key == "spell" then
		local damage, factor = Battle.Damage(unit, enemy, entry.key)
		GameTooltip:AddLine(("%s takes %d damage%s"):format(enemy.card.name, damage,
			ns.TypeWords(factor) and (", " .. ns.TypeWords(factor)) or ""), 1, 1, 1, true)
		GameTooltip:AddLine(entry.key == "spell" and "A spell: armor doesn't count" or "A melee hit: armor counts", 0.7, 0.7, 0.7)
		if entry.key == "spell" and unit.card.type ~= "Mage" then
			GameTooltip:AddLine(("Then ready again after %d turns"):format(Battle.SPELL_COOLDOWN), 0.7, 0.7, 0.7)
		end
	elseif entry.ability then
		local damage, factor = Battle.AbilityDamage(unit, enemy)
		GameTooltip:AddLine(("Hits for %d%s, then: %s"):format(damage, ns.TypeWords(factor) and (", " .. ns.TypeWords(factor)) or "",
			STATUS_TEXT[entry.ability.key]:format(math.floor(unit.melee * Battle.POISON + 0.5))), 1, 1, 1, true)
		GameTooltip:AddLine(("Then ready again after %d turns"):format(Battle.EFFECTS[entry.ability.key].cooldown), 0.7, 0.7, 0.7)
	elseif entry.key == "heal" then
		GameTooltip:AddLine(("Heals itself for %d"):format(Battle.HealAmount(unit)), 1, 1, 1)
	elseif entry.key == "mend" then
		GameTooltip:AddLine(("Heals one card on your bench for %d: click it after this"):format(Battle.HealAmount(unit)), 1, 1, 1, true)
	elseif entry.key == "restore" then
		GameTooltip:AddLine(("Heals every hurt card on your bench for %d"):format(Battle.HealAmount(unit, true)), 1, 1, 1, true)
	elseif entry.key == "guard" then
		GameTooltip:AddLine("The next hit on it is halved", 1, 1, 1)
	elseif entry.key == "wait" then
		GameTooltip:AddLine("Nothing it can do now: this turn passes (or switch to a card on your bench)", 1, 1, 1, true)
	end
	if entry.key == "heal" or entry.key == "mend" or entry.key == "restore" then
		GameTooltip:AddLine(("Each heal of this card is %d%% of the one before"):format(Battle.HEAL_DECAY * 100), 0.7, 0.7, 0.7)
	end
	if not entry.ready and entry.why then
		GameTooltip:AddLine("Not now: " .. entry.why, 1, 0.3, 0.3)
	end
	GameTooltip:Show()
end

local function Play(game, move)
	if Battles.Move(game, move) then
		PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
		mending = nil
		Refresh()
		return true
	end
	PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_OFF)
end

local function ShowMoves(game, state)
	local side = Battles.MySide(game)
	local list = Battle.Moves(state, side)
	local x0 = (WIDTH - (#list * (MOVE_W + 6) - 6)) / 2
	for i, button in ipairs(moveButtons) do
		local entry = list[i]
		button:SetShown(entry ~= nil)
		if entry then
			button:ClearAllPoints()
			button:SetPoint("TOPLEFT", page, "TOPLEFT", x0 + (i - 1) * (MOVE_W + 6), -526)
			local unit = Battle.Active(state, side)
			local icon = ICONS[entry.key]
			if entry.ability then
				icon = select(2, ns.AbilityLook(entry.ability))
			elseif (entry.key == "spell" or entry.key == "heal") and unit.spellName then
				icon = ns.SpellIcon(nil, unit.spellName) or icon
			end
			button.icon:SetTexture(icon)
			button.icon:SetDesaturated(not entry.ready)
			button:SetText(entry.ability and (ns.AbilityLook(entry.ability)) or entry.name)
			button:SetEnabled(entry.ready)
			if mending and entry.key == "mend" then
				button:LockHighlight()
			else
				button:UnlockHighlight()
			end
			button.entry, button.state, button.side = entry, state, side
			button:SetScript("OnEnter", MoveTooltip)
			button:SetScript("OnClick", function()
				if entry.key == "mend" then
					mending = not mending
					Refresh()
				else
					Play(game, entry.move)
				end
			end)
		end
	end
end

-- Clicks on our bench: switch, send in after a knockout, or the target of Mend
local function SetupBenchClicks(game, state, phase)
	local side = Battles.MySide(game)
	for slot, frame in ipairs(myBench) do
		local unit = state.sides[side].units[slot]
		if unit then
			if phase == "send" and unit.hp > 0 then
				frame.card:SetActive(true) -- these can come in
			end
			frame.card:SetScript("OnClick", function()
				if phase == "send" then
					Play(game, "n" .. slot)
				elseif mending then
					Play(game, "m" .. slot)
				else
					Play(game, "w" .. slot)
				end
			end)
		end
	end
end

local aiPending = false
local function RunAI()
	if aiPending or not shown or shown.role ~= "sparring" or Battles.Turn(shown) ~= "theirs" then
		return
	end
	aiPending = true
	C_Timer.After(AI_DELAY, function()
		aiPending = false
		if shown and page:IsVisible() and Battles.RunAI(shown) then
			Refresh()
		end
	end)
end

-- Before the battle: the team and the card it leads with (click one of its cards)
local function SetupPick(game)
	for i, button in ipairs(pickButtons) do
		local team = ns.Teams()[i]
		local cards = ns.TeamCards(team)
		local ready = ns.TeamReady(team)
		button:Show()
		pickInfo[i]:Show()
		button:SetText(team.name)
		button:SetEnabled(ready)
		if pickedTeam == team then
			button:LockHighlight()
		else
			button:UnlockHighlight()
		end
		button:SetScript("OnClick", function()
			if pickedTeam ~= team then
				pickedTeam, pickedLead = team, nil
			end
			PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
			Refresh()
		end)
		pickInfo[i]:SetText(ready and ns.TypeMix(cards) or "|cffff4040no cards|r (see Teams)")
	end
	local cards = pickedTeam and ns.TeamCards(pickedTeam) or {}
	for i, view in ipairs(cards) do
		ShowCard(myBench[i], view)
		myBench[i].card:SetSelected(pickedLead == i)
		myBench[i].card:SetScript("OnClick", function()
			pickedLead = i
			PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
			Refresh()
		end)
	end
	if pickedLead and cards[pickedLead] then
		ShowCard(myField, cards[pickedLead])
	end
	for i = 1, Battle.MAX_TEAM do
		theirBench[i].back:Show()
	end
	readyButton:Show()
	readyButton:SetEnabled(pickedTeam ~= nil and pickedLead ~= nil)
	promptText:SetText(not pickedTeam and "Pick a team. The other side never sees your bench, only the card fighting."
		or not pickedLead and "Click the card of your team you lead with."
		or "Press Ready to lock in your team and lead.")
end

Refresh = function()
	if not BestiaryChar then
		return
	end
	local before = shown
	shown = Battles.Shown() or Battles.NewSparring()
	if shown ~= before then
		pickedTeam, pickedLead, mending = nil, nil, nil
	end
	local game = shown
	ClearAll()
	sparringButton:SetEnabled(not Battles.Current())
	theirName:SetText(("vs |cffff6060%s|r  |cff999999%s|r"):format(game.role == "sparring" and ns.SPARRING_NAME or game.other,
		Battles.Status(game)))
	quitButton:SetShown(Battles.Active(game))
	quitButton:SetText(game.step == "incoming" and "Decline" or game.step == "playing" and "Resign" or "Cancel")
	centerText:SetText("VS")
	centerText:SetTextColor(1, 0.82, 0)

	local state = Battles.State(game)
	if state then
		ShowBenches(game, state)
		ShowField(game, state)
		Animate(game, state)
		ShowLog(game, state)
		centerText:SetText("")
		if game.step == "over" then
			local won = game.winner == 1
			centerText:SetText(won and "VICTORY!" or game.winner == 2 and "DEFEAT" or "DRAW")
			centerText:SetTextColor(won and 1 or 0.9, won and 0.82 or 0.2, won and 0 or 0.15)
			local parts = {}
			for _, result in ipairs(game.xp or {}) do
				parts[#parts + 1] = ("%s +%d XP%s"):format(result.name, result.xp,
					result.level and (" |cffffd200(level %d!)|r"):format(result.level) or result.capped and " |cff999999(max level)|r" or "")
			end
			promptText:SetText(game.reason and ("|cffffd200%s|r"):format(game.reason) or table.concat(parts, "  ·  "))
			return
		end
		local turn, phase = Battles.Turn(game)
		if turn == "mine" then
			SetupBenchClicks(game, state, phase)
			if phase == "send" then
				promptText:SetText("Your card is knocked out: click a card of your team to send it in.")
			else
				ShowMoves(game, state)
				promptText:SetText(mending and "Mend: click the card on your bench to heal."
					or "Your turn: pick a move, or click a card of your team to switch to it (that costs the turn).")
			end
		else
			promptText:SetText(game.role == "sparring" and ("%s is thinking..."):format(ns.SPARRING_NAME)
				or ("%s's turn. It comes in whenever they play, even after a reload."):format(game.other))
			RunAI()
		end
		return
	end

	-- Before the battle
	for i = 1, Battle.MAX_TEAM do
		theirBench[i].back:Show()
	end
	if game.step == "incoming" or game.step == "picking" then
		SetupPick(game)
		if game.step == "picking" and game.role == "challenger" then
			promptText:SetText(promptText:GetText() .. "  " .. game.other .. " already locked in.")
		end
	else
		local mine = Battles.Teams(game)
		for i, view in ipairs(mine or {}) do
			ShowCard(myBench[i], view)
		end
		local waiting = {
			challenged = "Challenge sent. %s picks a team first.",
			accepted = "Locked in. Waiting for %s's team...",
			revealed = "Your team is shown. Waiting for %s's team...",
		}
		promptText:SetText(game.step == "over" and ("|cffffd200%s|r"):format(game.reason or Battles.Status(game))
			or (waiting[game.step] or "%s"):format(game.other))
	end
end

readyButton:SetScript("OnClick", function()
	if not shown then
		return
	end
	PlaySound(SOUNDKIT.READY_CHECK)
	if pickedTeam and pickedLead then
		Battles.Pick(shown, pickedTeam, pickedLead)
	end
	pickedTeam, pickedLead = nil, nil
	Refresh()
end)

quitButton:SetScript("OnClick", function()
	if shown then
		Battles.Quit(shown)
		Refresh()
	end
end)

sparringButton:SetScript("OnClick", function()
	local game, why = Battles.NewSparring()
	if not game then
		UIErrorsFrame:AddMessage(why, 1, 0.2, 0.2)
		return
	end
	shown, pickedTeam, pickedLead, mending = game, nil, nil, nil
	Refresh()
end)

-- Challenging --------------------------------------------------------------------------------------

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
	local game, why = Battles.Challenge(name)
	if not game then
		UIErrorsFrame:AddMessage("Can't challenge: " .. why, 1, 0.2, 0.2)
		return
	end
	shown, pickedTeam, pickedLead, mending = game, nil, nil, nil
	Refresh()
	return game
end

-- /bst battle [name] and the Friends tab
ns.ChallengeBattle = function(name)
	ns.Show("Battle")
	name = name or ChallengeTarget()
	return name and Challenge(name)
end

local function UpdateChallenge()
	local typed = strtrim(challengeName:GetText() or "")
	challengeHint:SetShown(typed == "" and not challengeName:HasFocus())
	challengeButton:SetText(typed ~= "" and ("Challenge " .. typed) or "Challenge target")
end

local function ChallengeClicked()
	local typed = strtrim(challengeName:GetText() or ""):gsub("%s", "")
	local name = typed ~= "" and typed or ChallengeTarget()
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

-- Events -----------------------------------------------------------------------------------------

StaticPopupDialogs["BESTIARY_BATTLE"] = {
	text = "%s challenges you to a Bestiary battle.",
	button1 = ACCEPT or "Accept",
	button2 = LATER or "Later",
	timeout = 0,
	whileDead = true,
	hideOnEscape = true,
	OnAccept = function(_, game)
		shown, pickedTeam, pickedLead, mending = game, nil, nil, nil
		ns.Show("Battle")
		Refresh()
	end,
}

function Battles.OnEvent(event, game)
	local other = game.role == "sparring" and ns.SPARRING_NAME or game.other
	if event == "incoming" then
		PlaySound(SOUNDKIT.READY_CHECK)
		StaticPopup_Show("BESTIARY_BATTLE", game.other, nil, game)
	elseif game.role ~= "sparring" and not (page:IsVisible() and shown == game) then
		if event == "picking" then
			ns.Print(("%s locked in their team: pick yours (/bst battle)."):format(other))
		elseif event == "start" then
			ns.Print(("The battle with %s has started (/bst battle)."):format(other))
		elseif event == "move" and Battles.Turn(game) == "mine" then
			ns.Print(("%s played: your turn (/bst battle)."):format(other))
		elseif event == "over" then
			ns.Print(("The battle with %s is over: %s."):format(other, Battles.Status(game)))
		end
	end
	if page:IsVisible() then
		Refresh()
	end
end

page:SetScript("OnShow", Refresh)
