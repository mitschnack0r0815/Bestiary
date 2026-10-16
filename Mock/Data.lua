local _, ns = ...

-- MOCKUP: made-up collection, squads and an opponent, to see the look in WoW. Nothing here is
-- tracked from real kills. Stats follow the proposal in ARCHITECTURE.md 3.2 and 5.2.

ns.RARITIES = {
	normal = { name = "Common", factor = 1, color = { 0.62, 0.62, 0.62 } },
	elite = { name = "Uncommon", factor = 1.6, color = { 0.12, 1, 0 } },
	rare = { name = "Rare", factor = 1.8, color = { 0, 0.44, 0.87 } },
	rareelite = { name = "Epic", factor = 2.4, color = { 0.64, 0.21, 0.93 } },
	worldboss = { name = "Legendary", factor = 3, color = { 1, 0.5, 0 } },
}
ns.RARITY_ORDER = { worldboss = 1, rareelite = 2, rare = 3, elite = 4, normal = 5 }

ns.FAMILIES = {
	Beast = { icon = "Interface\\Icons\\Ability_Hunter_Pet_Wolf", color = { 0.75, 0.55, 0.3 } },
	Humanoid = { icon = "Interface\\Icons\\INV_Sword_04", color = { 0.8, 0.75, 0.6 } },
	Undead = { icon = "Interface\\Icons\\Spell_Shadow_RaiseDead", color = { 0.5, 0.75, 0.55 } },
	Demon = { icon = "Interface\\Icons\\Spell_Shadow_SummonFelHunter", color = { 0.65, 0.3, 0.85 } },
	Dragonkin = { icon = "Interface\\Icons\\INV_Misc_Head_Dragon_01", color = { 0.9, 0.3, 0.2 } },
	Elemental = { icon = "Interface\\Icons\\Spell_Fire_Fire", color = { 1, 0.6, 0.2 } },
	Giant = { icon = "Interface\\Icons\\INV_Hammer_04", color = { 0.6, 0.6, 0.7 } },
	Mechanical = { icon = "Interface\\Icons\\INV_Gizmo_02", color = { 0.7, 0.8, 0.9 } },
}

-- Combat types (3.5): how the power budget turns into stats, and the look
ns.TYPES = {
	Armor = {
		icon = "Interface\\Icons\\INV_Shield_06", color = { 0.6, 0.75, 1 },
		health = 1.6, attack = 0.16, speed = 35, armor = 0.4,
		leader = "Leader: Armor allies +2 armor",
	},
	Magic = {
		icon = "Interface\\Icons\\Spell_Fire_FlameBolt", color = { 1, 0.45, 0.2 },
		health = 0.7, attack = 0.30, speed = 55, armor = 0,
		leader = "Leader: Magic allies +15% attack",
	},
	Assassin = {
		icon = "Interface\\Icons\\Ability_BackStab", color = { 0.75, 1, 0.4 },
		health = 0.9, attack = 0.24, speed = 80, armor = 0,
		leader = "Leader: Assassin allies +10 speed in round 1",
	},
}
ns.TYPE_ORDER = { "Armor", "Magic", "Assassin" }

ns.CAPS = { 300, 600, 1000 }
ns.MIN_SQUAD, ns.MAX_SQUAD = 3, 7

local function Budget(level, classification, stars)
	return (10 + level * 3) * ns.RARITIES[classification].factor * (1 + 0.15 * (stars - 1))
end

local nextId = 0
local function MakeCard(name, level, classification, family, kind, stars, zone, stamina, exhausted)
	nextId = nextId + 1
	local budget = Budget(level, classification, stars)
	local t = ns.TYPES[kind]
	local attack = math.max(1, math.floor(budget * t.attack + 0.5))
	return {
		id = nextId,
		name = name, level = level, classification = classification, family = family, type = kind,
		stars = stars, zone = zone,
		power = math.floor(budget + 0.5),
		health = math.max(5, math.floor(budget * t.health + 0.5)),
		attack = attack,
		speed = math.floor(t.speed + level / 4),
		armor = math.floor(attack * t.armor + 0.5),
		stamina = stamina or 100,
		exhausted = exhausted, -- duels left to sit out
	}
end
ns.MakeCard = MakeCard

ns.collection = {
	MakeCard("Young Wolf", 2, "normal", "Beast", "Assassin", 3, "Elwynn Forest"),
	MakeCard("Kobold Vermin", 2, "normal", "Humanoid", "Assassin", 2, "Elwynn Forest", 40),
	MakeCard("Kobold Geomancer", 7, "normal", "Humanoid", "Magic", 3, "Elwynn Forest"),
	MakeCard("Defias Renegade Mage", 9, "normal", "Humanoid", "Magic", 2, "Elwynn Forest"),
	MakeCard("Murloc Streamrunner", 6, "normal", "Humanoid", "Assassin", 1, "Elwynn Forest"),
	MakeCard("Mother Fang", 10, "rare", "Beast", "Assassin", 1, "Elwynn Forest"),
	MakeCard("Hogger", 11, "elite", "Humanoid", "Armor", 2, "Elwynn Forest"),
	MakeCard("Harvest Watcher", 14, "normal", "Mechanical", "Armor", 2, "Westfall"),
	MakeCard("Defias Pillager", 15, "normal", "Humanoid", "Magic", 4, "Westfall", 75),
	MakeCard("Rotting Dead", 17, "normal", "Undead", "Armor", 1, "Duskwood", 0, 2),
	MakeCard("Edwin VanCleef", 21, "worldboss", "Humanoid", "Assassin", 1, "The Deadmines"),
	MakeCard("Crimson Whelp", 23, "normal", "Dragonkin", "Magic", 3, "Wetlands"),
	MakeCard("Felstalker", 26, "normal", "Demon", "Magic", 2, "Ashenvale"),
	MakeCard("Skeletal Warder", 30, "elite", "Undead", "Armor", 1, "Scarlet Monastery"),
	MakeCard("Rock Elemental", 38, "normal", "Elemental", "Armor", 1, "Badlands"),
	MakeCard("Mosh'Ogg Brute", 41, "normal", "Giant", "Armor", 1, "Stranglethorn Vale"),
	MakeCard("Jade", 47, "rareelite", "Dragonkin", "Magic", 1, "Swamp of Sorrows"),
	MakeCard("Searing Infernal", 52, "normal", "Demon", "Magic", 1, "Felwood"),
}

ns.byId = {}
for _, card in ipairs(ns.collection) do
	ns.byId[card.id] = card
end

local function Find(name)
	for _, card in ipairs(ns.collection) do
		if card.name == name then
			return card.id
		end
	end
end

-- Your three squads: card ids front to back, the leader's id, the cap they're built for
local function Squad(name, cap, leader, ...)
	local cards = {}
	for i = 1, select("#", ...) do
		cards[i] = Find(select(i, ...))
	end
	return { name = name, cap = cap, leader = Find(leader), cards = cards }
end

ns.squads = {
	Squad("Iron Wall", 600, "Skeletal Warder",
		"Skeletal Warder", "Harvest Watcher", "Defias Pillager", "Crimson Whelp", "Kobold Vermin"),
	Squad("Glass Cannon", 600, "Hogger",
		"Hogger", "Felstalker", "Defias Renegade Mage", "Kobold Geomancer", "Crimson Whelp"),
	Squad("Night Knives", 600, "Mother Fang",
		"Edwin VanCleef", "Mother Fang", "Young Wolf", "Murloc Streamrunner", "Kobold Vermin"),
}

function ns.SquadCards(squad)
	local cards = {}
	for i, id in ipairs(squad.cards) do
		cards[i] = ns.byId[id]
	end
	return cards
end

function ns.Power(cards)
	local power = 0
	for _, card in ipairs(cards) do
		power = power + card.power
	end
	return power
end

-- "2 Armor · 1 Magic · 2 Assassin"
function ns.TypeMix(cards)
	local counts = {}
	for _, card in ipairs(cards) do
		counts[card.type] = (counts[card.type] or 0) + 1
	end
	local parts = {}
	for _, kind in ipairs(ns.TYPE_ORDER) do
		if counts[kind] then
			local r, g, b = unpack(ns.TYPES[kind].color)
			parts[#parts + 1] = ("|cff%02x%02x%02x%d %s|r"):format(r * 255, g * 255, b * 255, counts[kind], kind)
		end
	end
	return table.concat(parts, "  ·  ")
end

-- Families with 2 or more cards: list of { family, count }
function ns.Families(cards)
	local counts, list = {}, {}
	for _, card in ipairs(cards) do
		counts[card.family] = (counts[card.family] or 0) + 1
	end
	for family, count in pairs(counts) do
		if count >= 2 then
			list[#list + 1] = { family = family, count = count }
		end
	end
	table.sort(list, function(a, b)
		return a.count > b.count
	end)
	return list
end

-- Roster rules (6.1). Returns a list of { ok, text }; the squad can be locked in if all are ok.
function ns.Checks(squad)
	local cards = ns.SquadCards(squad)
	local checks = {}
	local function Check(ok, text)
		checks[#checks + 1] = { ok = ok, text = text }
	end
	local leader = ns.byId[squad.leader or 0]
	local leaderIn = false
	for _, id in ipairs(squad.cards) do
		leaderIn = leaderIn or id == squad.leader
	end
	Check(leader ~= nil and leaderIn, leaderIn and "Leader" or "No leader")
	Check(#cards >= ns.MIN_SQUAD, #cards >= ns.MIN_SQUAD and ("%d cards"):format(#cards) or ("At least %d cards"):format(ns.MIN_SQUAD))
	local power = ns.Power(cards)
	Check(power <= squad.cap, power <= squad.cap and "Within cap" or "Over the cap")
	local legendaries, biggest = 0, nil
	for _, card in ipairs(cards) do
		if card.classification == "worldboss" then
			legendaries = legendaries + 1
		end
		if card.power > squad.cap * 0.4 then
			biggest = card
		end
	end
	if legendaries > 1 then
		Check(false, "Only one Legendary")
	end
	if biggest then
		Check(false, biggest.name .. " is over 40% of the cap")
	end
	for _, card in ipairs(cards) do
		if card.exhausted then
			Check(false, card.name .. " is exhausted")
		elseif card.stamina < 50 then
			checks[#checks + 1] = { warn = true, text = ("%s: stamina %d"):format(card.name, card.stamina) }
		end
	end
	return checks
end

function ns.CanLockIn(squad)
	for _, check in ipairs(ns.Checks(squad)) do
		if check.ok == false then
			return false
		end
	end
	return true
end

-- Training squads for the quick test: five cards of one type with the same total power
function ns.TrainingSquad(kind, power)
	local per = power / 5
	local level = math.max(1, math.floor((per - 10) / 3 + 0.5))
	local cards = {}
	for i = 1, 5 do
		local card = MakeCard("Training " .. kind, level, "normal", "Humanoid", kind, 1, "")
		cards[i] = card
	end
	return { cards = cards, leader = nil }
end

-- The opponent, with three squads of their own (made up)
local opponent = {
	shredder = MakeCard("Venture Co. Shredder", 20, "elite", "Mechanical", "Armor", 3, "Stonetalon Mountains"),
	kodo = MakeCard("Barrens Kodo", 16, "normal", "Beast", "Armor", 4, "The Barrens"),
	defender = MakeCard("Razormane Defender", 14, "normal", "Humanoid", "Armor", 5, "The Barrens"),
	geomancer = MakeCard("Razormane Geomancer", 15, "normal", "Humanoid", "Magic", 4, "The Barrens"),
	stormer = MakeCard("Kolkar Stormer", 15, "elite", "Humanoid", "Magic", 3, "The Barrens"),
	windcaller = MakeCard("Witchwing Windcaller", 18, "normal", "Humanoid", "Magic", 4, "The Barrens"),
	thornweaver = MakeCard("Razormane Thornweaver", 12, "normal", "Humanoid", "Magic", 5, "The Barrens"),
	echeyakee = MakeCard("Echeyakee", 13, "rare", "Beast", "Assassin", 3, "The Barrens"),
	huntress = MakeCard("Savannah Huntress", 12, "normal", "Beast", "Assassin", 5, "The Barrens"),
	lashtail = MakeCard("Sunscale Lashtail", 14, "normal", "Beast", "Assassin", 4, "The Barrens"),
	zhevra = MakeCard("Zhevra Runner", 15, "normal", "Beast", "Assassin", 4, "The Barrens"),
}
for _, card in pairs(opponent) do
	ns.byId[card.id] = card
end
local o = opponent
ns.opponent = {
	name = "Ricarda",
	squads = {
		{ name = "Iron Hide", leader = o.shredder.id, cards = { o.shredder.id, o.kodo.id, o.defender.id, o.geomancer.id } },
		{ name = "Storm Circle", leader = o.stormer.id, cards = { o.kodo.id, o.stormer.id, o.windcaller.id, o.thornweaver.id, o.geomancer.id } },
		{ name = "Savannah Hunt", leader = o.echeyakee.id, cards = { o.echeyakee.id, o.huntress.id, o.lashtail.id, o.zhevra.id } },
	},
}

-- Twists (6.2) the mock duel draws from
ns.TWISTS = {
	{ key = "calm", name = "Calm Waters", text = "No twist." },
	{ key = "fog", name = "Fog", text = "Assassins act twice in round 1." },
	{ key = "consecrated", name = "Consecrated Ground", text = "Undead have no armor." },
	{ key = "ambush", name = "Ambush", text = "Everyone hits the back row first." },
	{ key = "shieldwall", name = "Shield Wall", text = "Armor counts double, everyone is slower." },
}
