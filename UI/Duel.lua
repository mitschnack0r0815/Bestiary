local _, ns = ...
local Card = ns.Card
local Duel = ns.Duel

-- Duel page (ARCHITECTURE.md 5.2 and 6): your one game (the sparring partner or a player, saved
-- and resumable; a new one only once it's over), the twist ban and squad pick, then the turn-based fight: on your card's
-- turn click one of the action circles under the cards it can target (the active card has sparks
-- wandering around it). Their moves come in as whispers whenever they play.
local WIDTH = ns.WINDOW_WIDTH
local ROW_STEP = Card.WIDTH + 8
local ROW_X = (WIDTH - (ns.MAX_SQUAD * ROW_STEP - 8)) / 2
local AI_DELAY = 0.8 -- seconds between the sparring partner's moves
local SLOT_BACKDROP = {
	bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
	edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
	tile = true, tileSize = 16, edgeSize = 14,
	insets = { left = 4, right = 4, top = 4, bottom = 4 },
}

local page = ns.AddPage("Duel", "Interface\\Icons\\Ability_DualWield", 4)

local function Button(parent, text, width, height)
	local button = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
	button:SetSize(width, height or 22)
	button:SetText(text)
	return button
end

local shown -- the game on the page
local pickedSquad, pickedBan -- before Ready
local seenEvents = {} -- game id -> events already shown (animations only for new ones)

-- Top: who, the games, challenging ------------------------------------------------------------

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

local sparringButton = Button(page, "New sparring duel", 130, 22)
sparringButton:SetPoint("TOPRIGHT", -16, -62)

-- The board ---------------------------------------------------------------------------------------

-- Action circles under a card: round icons, one per action that can target it (no text; the
-- tooltip tells the numbers). Clicking one plays that move.
local CIRCLE = 30
local ROUND_MASK = "Interface\\CharacterFrame\\TempPortraitAlphaMask"
local ICONS = {
	attack = "Interface\\Icons\\Ability_MeleeDamage",
	spell = "Interface\\Icons\\Spell_Fire_FlameBolt",
	heal = "Interface\\Icons\\Spell_Holy_Heal",
	wait = "Interface\\Icons\\INV_Misc_PocketWatch_01",
}

local function Circle(slot)
	local button = CreateFrame("Button", nil, slot)
	button:SetSize(CIRCLE, CIRCLE)
	button.icon = button:CreateTexture(nil, "ARTWORK")
	button.ring = button:CreateTexture(nil, "BACKGROUND")
	button.ring:SetAllPoints()
	if ns.GoldCircle(button.ring) then
		-- Forever's level circle: the icon sits inside its gold rim
		local inner = CIRCLE * ns.GOLD_INNER
		button.icon:SetSize(inner, inner)
		button.icon:SetPoint("CENTER")
	else
		button.icon:SetPoint("TOPLEFT", 2, -2)
		button.icon:SetPoint("BOTTOMRIGHT", -2, 2)
		button.ring:SetDrawLayer("OVERLAY")
		button.ring:SetTexture(ns.RING)
	end
	if button.CreateMaskTexture then
		local mask = button:CreateMaskTexture()
		mask:SetTexture(ROUND_MASK, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
		mask:SetAllPoints(button.icon)
		button.icon:AddMaskTexture(mask)
	end
	local highlight = button:CreateTexture(nil, "HIGHLIGHT")
	highlight:SetAllPoints(button.icon)
	highlight:SetColorTexture(1, 1, 1, 0.25)
	button:Hide()
	return button
end

local function CardRow(y)
	local row = {}
	for i = 1, ns.MAX_SQUAD do
		local slot = CreateFrame("Frame", nil, page, BackdropTemplateMixin and "BackdropTemplate" or nil)
		slot:SetSize(Card.WIDTH, Card.HEIGHT)
		slot:SetPoint("TOPLEFT", ROW_X + (i - 1) * ROW_STEP, y)
		if slot.SetBackdrop then
			slot:SetBackdrop(SLOT_BACKDROP)
			slot:SetBackdropColor(0, 0, 0, 0.35)
			slot:SetBackdropBorderColor(0.25, 0.25, 0.25, 0.5)
		end
		slot.card = Card.Create(slot)
		slot.card:SetAllPoints()
		slot.card:Hide()
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
		slot.note = page:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		slot.note:SetPoint("TOP", slot, "BOTTOM", 0, -2)
		slot.circles = {}
		for c = 1, 3 do
			slot.circles[c] = Circle(slot)
		end
		row[i] = slot
	end
	return row
end

local theirRow = CardRow(-88)

local centerText = page:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
centerText:SetPoint("TOP", 0, -252)
centerText:SetFont(centerText:GetFont(), 24, "THICKOUTLINE")
local twistText = page:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
twistText:SetPoint("TOP", centerText, "BOTTOM", 0, -2)
twistText:SetWidth(WIDTH - 40)
-- Who's next on the clock
local nextText = page:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
nextText:SetPoint("TOP", twistText, "BOTTOM", 0, -2)
nextText:SetWidth(WIDTH - 40)

local myRow = CardRow(-306)

local function RowFor(game, side)
	return side == Duel.MySide(game) and myRow or theirRow
end

-- Bottom: pick and ban, or actions --------------------------------------------------------------

local promptText = page:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
promptText:SetPoint("TOP", 0, -470)
promptText:SetWidth(WIDTH - 40)

local pickButtons, pickInfo = {}, {}
for i = 1, 3 do
	local button = Button(page, "", 180, 26)
	button:SetPoint("TOP", (i - 2) * 190, -494)
	pickButtons[i] = button
	local text = page:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	text:SetPoint("TOP", button, "BOTTOM", 0, -3)
	pickInfo[i] = text
end

local banLabel = page:CreateFontString(nil, "OVERLAY", "GameFontNormal")
banLabel:SetPoint("TOP", 0, -566)
banLabel:SetText("Ban one twist (the other player bans one too, in secret; the twist is drawn from what's left):")
local banButtons = {}
for i = 1, ns.TWIST_CHOICES do
	local button = Button(page, "", 180, 24)
	button:SetPoint("TOP", (i - 2) * 190, -584)
	banButtons[i] = button
end

local logText = page:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
logText:SetPoint("TOP", 0, -498)
logText:SetWidth(WIDTH - 40)
logText:SetJustifyV("TOP")
logText:SetSpacing(2)

local quitButton = Button(page, "Resign", 140, 26)
quitButton:SetPoint("BOTTOM", -170, 18)
local readyButton = Button(page, "Ready", 160, 28)
readyButton:SetPoint("BOTTOM", 0, 17)

-- Showing ---------------------------------------------------------------------------------------

local Refresh

local function Colored(color, text)
	local r, g, b = unpack(color)
	return ("|cff%02x%02x%02x%s|r"):format(r * 255, g * 255, b * 255, text)
end

local function ClearRow(row, faceDown)
	for _, slot in ipairs(row) do
		slot.card:Hide()
		slot.card:SetActive(false)
		for _, circle in ipairs(slot.circles) do
			circle:Hide()
		end
		slot.back:SetShown(faceDown == true)
		slot.note:SetText("")
	end
end

-- A squad you might pick (before the fight)
local function ShowSquad(row, squad)
	ClearRow(row)
	for i, view in ipairs(squad and ns.SquadCards(squad) or {}) do
		local slot = row[i]
		slot.card:SetCard(view, "health")
		slot.card:Show()
		slot.card:SetSelected(false)
		slot.card:SetUsedUp(false)
	end
end

-- The fight as it stands
local function ShowUnits(game, state)
	for side, units in ipairs(state.sides) do
		local row = RowFor(game, side)
		ClearRow(row)
		for slot, unit in ipairs(units) do
			local card = row[slot].card
			card:SetCard(unit.card, "health")
			card:SetMaxHealth(unit.maxHp)
			card:SetHealth(unit.hp)
			card:SetDead(unit.hp <= 0)
			card:SetSelected(false)
			card:SetActive(state.actor == unit and not state.winner)
			card:SetUsedUp(false)
			card:Show()
			card.unit = unit
		end
	end
end

local function Name(game, unit)
	local color = unit.side == Duel.MySide(game) and "|cff40ff40" or "|cffff6060"
	return color .. unit.card.name .. "|r"
end

local function Describe(game, state, event)
	local function Unit(side, slot)
		return state.sides[side][slot]
	end
	if event.kind == "hit" then
		local by, at = Unit(event.side, event.slot), Unit(event.targetSide, event.targetSlot)
		local how = event.action == "spell" and (by.spellName or "a spell") or "attacks"
		return event.action == "spell" and ("%s casts %s at %s: %d"):format(Name(game, by), how, Name(game, at), event.damage)
			or ("%s hits %s for %d"):format(Name(game, by), Name(game, at), event.damage)
	elseif event.kind == "heal" then
		return ("%s heals %s for |cff40ff40%d|r"):format(Name(game, Unit(event.side, event.slot)),
			Name(game, Unit(event.targetSide, event.targetSlot)), event.amount)
	elseif event.kind == "wait" then
		return ("%s waits"):format(Name(game, Unit(event.side, event.slot)))
	elseif event.kind == "death" then
		return ("%s dies"):format(Name(game, Unit(event.side, event.slot)))
	elseif event.kind == "rise" then
		return ("%s rises again!"):format(Name(game, Unit(event.side, event.slot)))
	end
end

-- The last few things that happened
local function ShowLog(game, state)
	local lines = {}
	for i = #state.events, 1, -1 do
		local text = Describe(game, state, state.events[i])
		if text then
			table.insert(lines, 1, text)
			if #lines >= 4 then
				break
			end
		end
	end
	logText:SetText(table.concat(lines, "\n"))
end

-- New events since we last looked: hits, heals, deaths animate
local function Animate(game, state)
	local from = seenEvents[game.id]
	seenEvents[game.id] = #state.events
	if not from or not page:IsVisible() then
		return
	end
	for i = from + 1, #state.events do
		local event = state.events[i]
		if event.kind == "hit" then
			RowFor(game, event.side)[event.slot].card:Lunge(event.side == Duel.MySide(game) and 1 or -1)
			RowFor(game, event.targetSide)[event.targetSlot].card:Hit(event.damage, event.hp, event.magic)
		elseif event.kind == "heal" then
			RowFor(game, event.targetSide)[event.targetSlot].card:Heal(event.amount, event.hp)
		elseif event.kind == "drain" then
			RowFor(game, event.side)[event.slot].card:Hit(event.damage, event.hp, true)
		end
	end
end

-- The icon of an action of this card: its spell's own icon if the game knows it
local function ActionIcon(unit, key)
	if (key == "spell" or key == "heal") and unit.spellName then
		local icon = ns.SpellIcon(nil, unit.spellName)
		if icon then
			return icon
		end
	end
	return ICONS[key]
end

-- On our turn: under every card an action of our card can target, a circle per action
local function ShowCircles(game, state)
	local actor = state.actor
	local list = {} -- slot frame -> actions
	for _, entry in ipairs(ns.Fight.Actions(state, actor)) do
		if entry.ready then
			for _, target in ipairs(ns.Fight.Targets(state, actor, entry.key)) do
				local slot = RowFor(game, target.side)[target.slot]
				list[slot] = list[slot] or {}
				tinsert(list[slot], { entry = entry, target = target })
			end
		end
	end
	for slot, actions in pairs(list) do
		for i, item in ipairs(actions) do
			local circle = slot.circles[i]
			if circle then
				local entry, target = item.entry, item.target
				circle:ClearAllPoints()
				circle:SetPoint("TOP", slot, "BOTTOM", (i - (#actions + 1) / 2) * (CIRCLE + 4), -3)
				circle.icon:SetTexture(ActionIcon(actor, entry.key))
				circle:SetScript("OnClick", function()
					if Duel.Move(game, { action = entry.key, side = target.side, slot = target.slot }) then
						PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
						Refresh()
					end
				end)
				circle:SetScript("OnEnter", function(self)
					local amount = ns.Fight.Estimate(state, actor, entry.key, target)
					GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
					GameTooltip:AddLine(entry.name)
					if entry.key == "wait" then
						GameTooltip:AddLine("Nobody to heal: this turn passes", 1, 1, 1)
					else
						GameTooltip:AddLine((entry.key == "heal" and "Heals %s for %d" or "%s takes %d damage"):format(
							target.card.name, amount), 1, 1, 1)
					end
					GameTooltip:Show()
				end)
				circle:SetScript("OnLeave", GameTooltip_Hide)
				circle:Show()
			end
		end
	end
end

local function SetPickShown(show)
	for i = 1, 3 do
		pickButtons[i]:SetShown(show)
		pickInfo[i]:SetShown(show)
	end
	banLabel:SetShown(show)
	for _, button in ipairs(banButtons) do
		button:SetShown(show)
	end
end

local function SetupPick(game)
	SetPickShown(true)
	for i, button in ipairs(pickButtons) do
		local squad = ns.squads[i]
		local cards = ns.SquadCards(squad)
		local fits = ns.CanLockIn(squad)
		button:SetText(squad.name)
		button:SetEnabled(fits)
		if pickedSquad == squad then
			button:LockHighlight()
		else
			button:UnlockHighlight()
		end
		button:SetScript("OnClick", function()
			pickedSquad = squad
			PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
			Refresh()
		end)
		local power = ("|cffffd200Power %d / %d|r"):format(ns.Power(cards), squad.cap)
		pickInfo[i]:SetText(fits and (ns.TypeMix(cards) .. "\n" .. ns.FamilyText(cards) .. "\n" .. power)
			or ("|cffff4040can't be sent|r (see Squads)\n" .. power))
	end
	for i, button in ipairs(banButtons) do
		local twist = ns.TwistByKey(game.twists[i])
		button:SetText((pickedBan == twist.key and "|cffff4040Banned:|r " or "") .. twist.name)
		if pickedBan == twist.key then
			button:LockHighlight()
		else
			button:UnlockHighlight()
		end
		button:SetScript("OnClick", function()
			pickedBan = twist.key
			PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
			Refresh()
		end)
		button:SetScript("OnEnter", function(self)
			GameTooltip:SetOwner(self, "ANCHOR_TOP")
			GameTooltip:AddLine(twist.name)
			GameTooltip:AddLine(twist.text, 1, 1, 1, true)
			GameTooltip:Show()
		end)
		button:SetScript("OnLeave", GameTooltip_Hide)
	end
	readyButton:Show()
	readyButton:SetEnabled(pickedSquad ~= nil and pickedBan ~= nil)
	ShowSquad(myRow, pickedSquad)
	ClearRow(theirRow, true)
	promptText:SetText(pickedSquad and pickedBan and "Press Ready to lock in."
		or "Pick a squad and ban a twist. The other side can't see yours until both are locked in.")
end

local aiPending = false

local function RunAI()
	if aiPending or not shown or shown.role ~= "sparring" or Duel.Turn(shown) ~= "theirs" then
		return
	end
	aiPending = true
	C_Timer.After(AI_DELAY, function()
		aiPending = false
		if shown and page:IsVisible() and Duel.RunAI(shown) then
			Refresh()
		end
	end)
end

Refresh = function()
	if not BestiaryChar then
		return
	end
	local before = shown
	shown = Duel.Shown() or Duel.NewSparring() -- one game at a time: always that one
	if shown ~= before then
		pickedSquad, pickedBan = nil, nil
	end
	local game = shown
	sparringButton:SetEnabled(not Duel.Current())
	theirName:SetText(("vs |cffff6060%s|r  |cff999999%s|r"):format(game.role == "sparring" and ns.SPARRING_NAME or game.other,
		Duel.Status(game)))
	SetPickShown(false)
	readyButton:Hide()
	nextText:SetText("")
	logText:SetText("")
	centerText:SetText("VS")
	centerText:SetTextColor(1, 0.82, 0)
	local offered = {}
	for _, key in ipairs(game.twists) do
		offered[#offered + 1] = ns.TwistByKey(key).name
	end
	twistText:SetText(game.twist and ("Twist: |cffffd200%s|r  %s"):format(ns.TwistByKey(game.twist).name, ns.TwistByKey(game.twist).text)
		or ("Twists on offer: |cffffd200%s|r"):format(table.concat(offered, ", ")))
	quitButton:SetShown(Duel.Active(game))
	quitButton:SetText(game.step == "incoming" and "Decline" or game.step == "playing" and "Resign" or "Cancel")

	local state = Duel.State(game)
	if state then
		ShowUnits(game, state)
		Animate(game, state)
		ShowLog(game, state)
		if game.step == "over" then
			local won = game.winner == 1
			centerText:SetText(won and "VICTORY!" or game.winner == 2 and "DEFEAT" or "DRAW")
			centerText:SetTextColor(won and 1 or 0.9, won and 0.82 or 0.2, won and 0 or 0.15)
			for slot, loss in pairs(game.stamina or {}) do
				local row = RowFor(game, Duel.MySide(game))
				if row[slot] then
					row[slot].note:SetText(loss > 0 and ("|cff6aa0ffstamina -%d|r"):format(loss) or "|cff999999no stamina lost|r")
				end
			end
			promptText:SetText(game.reason and ("|cffffd200%s|r"):format(game.reason)
				or (game.levelUps and #game.levelUps > 0 and ("Level up: " .. table.concat(game.levelUps, ", ")) or ""))
		else
			centerText:SetText(("%.1f s"):format(state.time))
			-- The next turns on the clock
			local parts = {}
			for i, unit in ipairs(ns.Fight.Upcoming(state)) do
				if i > 6 then
					break
				end
				local wait = unit.next - state.time
				parts[#parts + 1] = Name(game, unit) .. (unit.waiting and " |cff999999waits for a hurt ally|r"
					or wait > 0 and (" |cff999999+%.1f s|r"):format(wait) or " |cff999999now|r")
			end
			nextText:SetText("Next:  " .. table.concat(parts, "  ·  "))
			if Duel.Turn(game) == "mine" then
				ShowCircles(game, state)
				promptText:SetText(("Your turn: %s. Click a circle under a card."):format(Name(game, state.actor)))
			else
				promptText:SetText(game.role == "sparring" and ("%s is thinking..."):format(ns.SPARRING_NAME)
					or ("%s's turn (%s). It comes in whenever they play, even after a reload."):format(game.other,
						state.actor and Name(game, state.actor) or "?"))
				RunAI()
			end
		end
		return
	end

	-- Before the fight
	ClearRow(theirRow, true)
	ClearRow(myRow)
	if game.step == "incoming" or game.step == "picking" then
		SetupPick(game)
		if game.step == "picking" and game.role == "challenger" then
			promptText:SetText(promptText:GetText() .. "  " .. game.other .. " already locked in.")
		end
	else
		local waiting = {
			challenged = "Challenge sent. %s picks a squad and bans a twist first.",
			accepted = "Locked in. Waiting for %s to pick...",
			revealed = "Your squad is shown. Waiting for %s's squad...",
		}
		if game.myWire then
			local cards = ns.DecodeSquad(game.myWire) or {}
			for i, view in ipairs(cards) do
				myRow[i].card:SetCard(view, "health")
				myRow[i].card:Show()
				myRow[i].card:SetSelected(false)
				myRow[i].card:SetUsedUp(false)
			end
		end
		promptText:SetText(game.step == "over" and ("|cffffd200%s|r"):format(game.reason or Duel.Status(game))
			or (waiting[game.step] or "%s"):format(game.other))
	end
end

readyButton:SetScript("OnClick", function()
	if shown and pickedSquad and pickedBan then
		PlaySound(SOUNDKIT.READY_CHECK)
		Duel.Pick(shown, pickedSquad, pickedBan)
		pickedSquad, pickedBan = nil, nil
		Refresh()
	end
end)

quitButton:SetScript("OnClick", function()
	if shown then
		Duel.Quit(shown)
		Refresh()
	end
end)

sparringButton:SetScript("OnClick", function()
	local game, why = Duel.NewSparring()
	if not game then
		UIErrorsFrame:AddMessage(why, 1, 0.2, 0.2)
		return
	end
	shown, pickedSquad, pickedBan = game, nil, nil
	Refresh()
end)

-- Challenging ------------------------------------------------------------------------------------

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
	local game, why = Duel.Challenge(name)
	if not game then
		UIErrorsFrame:AddMessage("Can't challenge: " .. why, 1, 0.2, 0.2)
		return
	end
	shown, pickedSquad, pickedBan = game, nil, nil
	Refresh()
	return game
end

-- /bst duel [name] and the Friends tab: challenge them, or your target; nobody: just open the page
ns.ChallengePlayer = function(name)
	ns.Show("Duel")
	name = name or ChallengeTarget()
	return name and Challenge(name)
end

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
	GameTooltip:AddLine("They need Bestiary too. Games are turn based and saved: play your turns whenever you're both online.", 1, 1, 1, true)
	GameTooltip:Show()
end)
challengeButton:SetScript("OnLeave", GameTooltip_Hide)

-- Duel events ------------------------------------------------------------------------------------

StaticPopupDialogs["BESTIARY_CHALLENGE"] = {
	text = "%s challenges you to a Bestiary duel.",
	button1 = ACCEPT or "Accept",
	button2 = LATER or "Later",
	timeout = 0,
	whileDead = true,
	hideOnEscape = true,
	OnAccept = function(_, game)
		shown, pickedSquad, pickedBan = game, nil, nil
		ns.Show("Duel")
		Refresh()
	end,
}

function Duel.OnEvent(event, game)
	local other = game.role == "sparring" and ns.SPARRING_NAME or game.other
	if event == "incoming" then
		PlaySound(SOUNDKIT.READY_CHECK)
		StaticPopup_Show("BESTIARY_CHALLENGE", game.other, nil, game)
	elseif game.role ~= "sparring" and not (page:IsVisible() and shown == game) then
		if event == "picking" then
			ns.Print(("%s locked in: pick your squad (/bst duel)."):format(other))
		elseif event == "start" then
			ns.Print(("The duel with %s has started (/bst duel)."):format(other))
		elseif event == "move" and Duel.Turn(game) == "mine" then
			ns.Print(("%s played: your turn (/bst duel)."):format(other))
		elseif event == "over" then
			ns.Print(("The duel with %s is over: %s."):format(other, Duel.Status(game)))
		end
	end
	if page:IsVisible() then
		Refresh()
	end
end

page:SetScript("OnShow", function()
	Refresh()
end)
