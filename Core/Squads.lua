local addonName, ns = ...

-- Your three squads of real cards (BestiaryChar.squads, per character): card ids front to back
-- ("npc<id>", the id of a card view). And the sparring partner you duel until duels between
-- players exist: three squads (Tank, Mage and Warrior heavy) made from mobs you've seen, about
-- as strong as your own squads.
ns.SPARRING_NAME = "Sparring Partner"

local sparringCards = {} -- id -> card view of the current sparring squads and of opponents' squads

local function NewSquads()
	local squads = {}
	for i = 1, 3 do
		squads[i] = { name = "Squad " .. i, cap = ns.POWER_CAP, cards = {} }
	end
	return squads
end

-- Everyone starts with a card of their own character (ARCHITECTURE.md 3.6): a leader, since
-- it's "named", but only as strong as a common mob's card and it never gains stars. Saved under
-- NPC id 0; its type comes from the class.
ns.SELF_ID = 0
local CLASS_TYPE = { WARRIOR = "Tank", PALADIN = "Tank", ROGUE = "Warrior", HUNTER = "Warrior",
	PRIEST = "Healer", DRUID = "Healer", MAGE = "Mage", WARLOCK = "Mage", SHAMAN = "Mage" }

local function EnsureSelfCard()
	local name = UnitName("player")
	local _, class = UnitClass("player")
	if not name or not class then
		return
	end
	local card = BestiaryChar.cards[ns.SELF_ID]
	if not card then
		card = { npcId = ns.SELF_ID, stars = 0, obtained = time() }
		BestiaryChar.cards[ns.SELF_ID] = card
		ns.Print(("Your first card is yourself: |cffffd200%s|r, a %s and your first leader."):format(name, CLASS_TYPE[class] or "Tank"))
	end
	card.player = true
	card.name = name
	card.classification = "normal"
	card.family = "Humanoid"
	card.type = CLASS_TYPE[class] or "Tank"
	card.class = class
	card.spell = ns.CLASS_SPELLS[class] -- casters and healers cast their class's spell
	card.zone = GetRealZoneText and GetRealZoneText() or card.zone or ""
	card.stars = 0
	if ns.Refresh then
		ns.Refresh()
	end
end

-- The cap follows your level (CAP_PER_LEVEL per level)
local function SetCap(level)
	ns.POWER_CAP = ns.PowerCap(level)
	ns.CAPS = { ns.POWER_CAP }
	for _, squad in ipairs(ns.squads or {}) do
		squad.cap = ns.POWER_CAP
	end
end

local events = CreateFrame("Frame")
events:RegisterEvent("ADDON_LOADED")
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("PLAYER_LEVEL_UP")
events:SetScript("OnEvent", function(_, event, name)
	if event == "PLAYER_LOGIN" or event == "PLAYER_LEVEL_UP" then
		SetCap(event == "PLAYER_LEVEL_UP" and name or nil) -- level up: the new level comes with it
		if BestiaryChar then
			EnsureSelfCard()
		end
		return
	end
	if name ~= addonName then
		return
	end
	-- after the tracker made BestiaryChar
	BestiaryChar.squads = BestiaryChar.squads or NewSquads()
	for _, squad in ipairs(BestiaryChar.squads) do
		squad.cap = ns.POWER_CAP
	end
	ns.squads = BestiaryChar.squads
	ns.MigrateStars()
	ns.MigrateTypes()
	ns.RefreshCards(true)
	SetCap()
	events:UnregisterEvent("ADDON_LOADED")
end)

-- A card view by its id: one of yours ("npc<id>" for the first copy, "npc<id>:<n>" for the
-- others) or one of the sparring partner's
function ns.CardById(id)
	if sparringCards[id] then
		return sparringCards[id]
	end
	local npcId, copy = nil, 1
	if type(id) == "string" then
		local idText, copyText = id:match("^npc(%d+):?(%d*)$")
		npcId, copy = tonumber(idText), tonumber(copyText) or 1
	end
	local card = npcId and BestiaryChar.cards[npcId]
	if not card or copy > ns.Copies(card) then
		return nil
	end
	local view = ns.CardView(card)
	if copy > 1 then
		view.id, view.copy = ("npc%d:%d"):format(npcId, copy), copy
	end
	return view
end

-- The ids of all copies of a card ("npc12", "npc12:2", ...)
function ns.CopyIds(view)
	local saved = BestiaryChar.cards[view.npcId]
	local ids = { ("npc%d"):format(view.npcId) }
	for copy = 2, saved and ns.Copies(saved) or 1 do
		ids[copy] = ("npc%d:%d"):format(view.npcId, copy)
	end
	return ids
end

-- A copy of this card not in the squad yet, nil if all are in it
function ns.FreeCopy(squad, view)
	local used = {}
	for _, id in ipairs(squad.cards) do
		used[id] = true
	end
	for _, id in ipairs(ns.CopyIds(view)) do
		if not used[id] then
			return id
		end
	end
end

-- How many copies of this card are in the squad
function ns.CopiesIn(squad, view)
	local count, ids = 0, {}
	for _, id in ipairs(ns.CopyIds(view)) do
		ids[id] = true
	end
	for _, id in ipairs(squad.cards) do
		if ids[id] then
			count = count + 1
		end
	end
	return count
end

-- The saved card behind a view (to change stamina), nil for the sparring partner's
function ns.SavedCard(view)
	return view and view.npcId and not sparringCards[view.id] and BestiaryChar.cards[view.npcId] or nil
end

-- A squad's cards as views, front to back. Cards you no longer have drop out of the squad.
function ns.SquadCards(squad)
	local cards = {}
	for i = #squad.cards, 1, -1 do
		if not ns.CardById(squad.cards[i]) then
			tremove(squad.cards, i)
		end
	end
	for i, id in ipairs(squad.cards) do
		cards[i] = ns.CardById(id)
	end
	return cards
end

-- An opponent's squad (card views from a duel) as a squad to show
function ns.ForeignSquad(name, cards)
	for id in pairs(sparringCards) do
		if id:find("^foreign:") then
			sparringCards[id] = nil
		end
	end
	local squad = { name = name, cards = {} }
	for i, view in ipairs(cards) do
		view.id = "foreign:" .. i
		sparringCards[view.id] = view
		squad.cards[i] = view.id
	end
	return squad
end

-- Sparring partner ------------------------------------------------------------------------

local SPARRING_MIN = 3 -- the sparring partner always sends at least this many cards

-- Each squad: its card types front to back
local SPARRING = {
	{ name = "Shield Wall", types = { "Tank", "Tank", "Healer", "Mage", "Tank", "Mage", "Tank" } },
	{ name = "Spell Circle", types = { "Tank", "Mage", "Mage", "Mage", "Healer", "Mage", "Mage" } },
	{ name = "War Band", types = { "Warrior", "Warrior", "Tank", "Warrior", "Warrior", "Warrior", "Warrior" } },
}

local function Random(seed)
	local state = (seed * 7919 + 17) % 2147483647
	return function(n)
		state = state * 16807 % 2147483647
		return state % n + 1
	end
end

-- How strong the sparring partner should be: about your squads' average power
local function TargetPower()
	local total, count = 0, 0
	for _, squad in ipairs(ns.squads or {}) do
		local power = ns.Power(ns.SquadCards(squad))
		if power > 0 then
			total, count = total + power, count + 1
		end
	end
	local target = count > 0 and total / count or ns.POWER_CAP / 2
	return math.max(ns.POWER_CAP * 0.3, math.min(ns.POWER_CAP - 4, target))
end

-- Mobs you've seen that can be on a card (not named: those would lead and be too strong)
local function KnownMobs()
	local mobs = {}
	for npcId, info in pairs(BestiaryAccount.mobs) do
		if info.family and info.name and not ns.IsNamed({ classification = info.classification, npcId = npcId, name = info.name }) then
			mobs[#mobs + 1] = { npcId = npcId, info = info }
		end
	end
	table.sort(mobs, function(a, b)
		return a.npcId < b.npcId
	end)
	return mobs
end

-- The sparring partner's three squads for this duel (seed: the duel's number)
function ns.SparringSquads(seed)
	for id in pairs(sparringCards) do
		if id:find("^sparring:") then
			sparringCards[id] = nil
		end
	end
	local random = Random(seed)
	local target = TargetPower()
	local mobs = KnownMobs()
	local squads = {}
	for s, plan in ipairs(SPARRING) do
		local squad = { name = "Squad " .. s, style = plan.name, cap = ns.POWER_CAP, cards = {} }
		local power, used = 0, {}
		for i, kind in ipairs(plan.types) do
			local view
			if #mobs >= 7 then
				local mob
				repeat
					mob = mobs[random(#mobs)]
				until not used[mob.npcId]
				used[mob.npcId] = true
				view = ns.CardView({
					npcId = mob.npcId, name = mob.info.name, classification = mob.info.classification,
					family = mob.info.family, type = kind, stars = random(3) - 1, zone = "", remote = ns.SPARRING_NAME,
					level = math.min(ns.DropLevel(mob.npcId, mob.info.classification), ns.LevelCap({ classification = mob.info.classification })),
				})
			else
				view = ns.TrainingCard(kind, UnitLevel("player") or 1, "Sparring " .. kind, i)
			end
			if i > SPARRING_MIN and power + view.power > target then
				break
			end
			view.id = ("sparring:%d:%d"):format(s, i)
			sparringCards[view.id] = view
			squad.cards[#squad.cards + 1] = view.id
			power = power + view.power
		end
		squads[s] = squad
	end
	return squads
end
