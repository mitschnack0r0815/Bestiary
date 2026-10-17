local _, ns = ...

-- Hardcore (ARCHITECTURE.md 7): with BestiaryChar.hardcore on, dying loses every card you own.
-- What you've studied stays (you still know those mobs). Only your own card stays (everyone
-- always has it), back to 1 star. Feign Death doesn't count; a death while the addon was off is caught at the next
-- login. Each loss goes into BestiaryAccount.fallen (the Hall of the Fallen, for later).
-- Also the Test tab's helpers: clearing the collection and filling it with basic cards.

-- Empties the collection (and the squads); your own card stays at 1 star. What you've studied
-- stays.
function ns.ResetCollection()
	local me = BestiaryChar.cards[ns.SELF_ID]
	wipe(BestiaryChar.cards)
	wipe(BestiaryChar.drops)
	if me then
		me.stars, me.stamina, me.exhausted = 0, 100, nil
		BestiaryChar.cards[ns.SELF_ID] = me
	end
	for _, squad in ipairs(ns.squads or {}) do
		wipe(squad.cards)
	end
	if ns.Refresh then
		ns.Refresh()
	end
end

-- Starter mobs everyone has met, for when you haven't seen enough mobs yet
local BASIC = {
	{ 299, "Young Wolf", "Beast" }, { 6, "Kobold Vermin", "Humanoid" }, { 38, "Defias Thug", "Humanoid" },
	{ 732, "Murloc Lurker", "Humanoid" }, { 257, "Kobold Worker", "Humanoid" }, { 1501, "Mindless Zombie", "Undead" },
	{ 3098, "Mottled Boar", "Beast" }, { 2955, "Plainstrider", "Beast" },
}
local BASIC_TYPES = { "Tank", "Tank", "Mage", "Warrior", "Healer" }

-- Gives `count` common 1-star cards (as test cards: they don't count as drops)
function ns.FillBasicCards(count)
	count = count or 5
	local candidates = {}
	for npcId, info in pairs(BestiaryAccount.mobs) do
		if info.family and info.name and not BestiaryChar.cards[npcId]
			and not ns.IsNamed({ classification = info.classification, npcId = npcId, name = info.name }) then
			candidates[#candidates + 1] = { npcId, info.name, info.family }
		end
	end
	table.sort(candidates, function(a, b)
		return a[1] < b[1]
	end)
	for _, basic in ipairs(BASIC) do
		if not BestiaryChar.cards[basic[1]] then
			candidates[#candidates + 1] = basic
		end
	end
	local given, used = 0, {}
	for _, mob in ipairs(candidates) do
		if given >= count then
			break
		end
		if not used[mob[1]] and not BestiaryChar.cards[mob[1]] then
			used[mob[1]] = true
			given = given + 1
			BestiaryChar.cards[mob[1]] = {
				npcId = mob[1], name = mob[2], classification = "normal", family = mob[3],
				type = BASIC_TYPES[(given - 1) % #BASIC_TYPES + 1], stars = 0, zone = "", obtained = time(), test = true,
			}
		end
	end
	if ns.Refresh then
		ns.Refresh()
	end
	return given
end

-- Hardcore ------------------------------------------------------------------------------------

function ns.IsHardcore()
	return BestiaryChar and BestiaryChar.hardcore == true
end

function ns.SetHardcore(on)
	BestiaryChar.hardcore = on and true or nil
	ns.Print(on and "|cffff4040Hardcore on:|r if you die, all your cards are lost (your own card and what you've studied stay)."
		or "Hardcore off: dying costs nothing.")
end

local function Fall()
	local cards = 0
	for npcId in pairs(BestiaryChar.cards) do
		if npcId ~= ns.SELF_ID then
			cards = cards + 1
		end
	end
	BestiaryAccount.fallen = BestiaryAccount.fallen or {}
	tinsert(BestiaryAccount.fallen, { name = UnitName("player"), level = UnitLevel("player"), at = time(),
		zone = GetRealZoneText and GetRealZoneText() or "", cards = cards })
	ns.ResetCollection() -- cards only: what you've studied stays
	BestiaryChar.fallenHandled = true
	ns.Print(("|cffff4040You died. Your cards are lost:|r %d cards. Only your own card remains; what you've studied stays."):format(cards))
	if ns.OnFallen then
		ns.OnFallen(cards)
	end
end

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_DEAD")
events:RegisterEvent("PLAYER_ALIVE")
events:RegisterEvent("PLAYER_UNGHOST")
events:RegisterEvent("PLAYER_LOGIN")
events:SetScript("OnEvent", function(_, event)
	if not BestiaryChar then
		return
	end
	if event == "PLAYER_DEAD" then
		local feigning = UnitIsFeignDeath and UnitIsFeignDeath("player")
		if ns.IsHardcore() and not (issecretvalue and issecretvalue(feigning)) and not feigning
			and not BestiaryChar.fallenHandled then
			Fall()
		end
	elseif event == "PLAYER_LOGIN" then
		-- Died while the addon was off (or the game closed while dead)
		local dead = UnitIsDeadOrGhost and UnitIsDeadOrGhost("player")
		if ns.IsHardcore() and dead and not (issecretvalue and issecretvalue(dead)) and not BestiaryChar.fallenHandled then
			Fall()
		elseif not dead then
			BestiaryChar.fallenHandled = nil
		end
	else
		-- Alive again (spirit healer, resurrection): the next death counts again
		local dead = UnitIsDeadOrGhost and UnitIsDeadOrGhost("player")
		if not dead then
			BestiaryChar.fallenHandled = nil
		end
	end
end)
