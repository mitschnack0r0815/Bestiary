local _, ns = ...

-- MOCKUP: made-up collection and opponent team, to see the look in WoW. Nothing here is
-- tracked from real kills. Stats come from a first draft of the formula in ARCHITECTURE.md 3.2.

ns.RARITIES = {
	normal = { name = "Common", factor = 1, color = { 0.62, 0.62, 0.62 } },
	elite = { name = "Uncommon", factor = 1.6, color = { 0.12, 1, 0 } },
	rare = { name = "Rare", factor = 1.8, color = { 0, 0.44, 0.87 } },
	rareelite = { name = "Epic", factor = 2.4, color = { 0.64, 0.21, 0.93 } },
	worldboss = { name = "Legendary", factor = 3, color = { 1, 0.5, 0 } },
}
ns.RARITY_ORDER = { worldboss = 1, rareelite = 2, rare = 3, elite = 4, normal = 5 }

-- Stat lean (attack, health, speed) and look per family
ns.FAMILIES = {
	Beast = { icon = "Interface\\Icons\\Ability_Hunter_Pet_Wolf", lean = { 0.35, 0.40, 0.25 }, color = { 0.75, 0.55, 0.3 } },
	Humanoid = { icon = "Interface\\Icons\\INV_Sword_04", lean = { 0.33, 0.45, 0.22 }, color = { 0.8, 0.75, 0.6 } },
	Undead = { icon = "Interface\\Icons\\Spell_Shadow_RaiseDead", lean = { 0.25, 0.60, 0.15 }, color = { 0.5, 0.75, 0.55 } },
	Demon = { icon = "Interface\\Icons\\Spell_Shadow_SummonFelHunter", lean = { 0.48, 0.34, 0.18 }, color = { 0.65, 0.3, 0.85 } },
	Dragonkin = { icon = "Interface\\Icons\\INV_Misc_Head_Dragon_01", lean = { 0.38, 0.50, 0.12 }, color = { 0.9, 0.3, 0.2 } },
	Elemental = { icon = "Interface\\Icons\\Spell_Fire_Fire", lean = { 0.42, 0.40, 0.18 }, color = { 1, 0.6, 0.2 } },
	Giant = { icon = "Interface\\Icons\\INV_Hammer_04", lean = { 0.30, 0.62, 0.08 }, color = { 0.6, 0.6, 0.7 } },
	Mechanical = { icon = "Interface\\Icons\\INV_Gizmo_02", lean = { 0.32, 0.50, 0.18 }, color = { 0.7, 0.8, 0.9 } },
}

-- name, level, classification, family, stars, zone, ability
local COLLECTION = {
	{ "Young Wolf", 2, "normal", "Beast", 3, "Elwynn Forest", "Pack Hunter: +2 attack per other beast" },
	{ "Kobold Vermin", 2, "normal", "Humanoid", 2, "Elwynn Forest", "Candle Toss: hits the back row" },
	{ "Murloc Streamrunner", 6, "normal", "Humanoid", 1, "Elwynn Forest", "Mrglglgl: +20% speed below half health" },
	{ "Mother Fang", 10, "rare", "Beast", 1, "Elwynn Forest", "Venom: poisons the target for 3 turns" },
	{ "Hogger", 11, "elite", "Humanoid", 2, "Elwynn Forest", "Big Bad: first attack deals double damage" },
	{ "Harvest Watcher", 14, "normal", "Mechanical", 2, "Westfall", "Self-Repair: heals 15% at low health" },
	{ "Defias Pillager", 15, "normal", "Humanoid", 4, "Westfall", "Fireball: hits the lowest health enemy" },
	{ "Rotting Dead", 17, "normal", "Undead", 1, "Duskwood", "Rise Again: once, back up at 30% health" },
	{ "Edwin VanCleef", 21, "worldboss", "Humanoid", 1, "The Deadmines", "Blade Flurry: hits two enemies" },
	{ "Crimson Whelp", 23, "normal", "Dragonkin", 3, "Wetlands", "Breath: hits every enemy for a little" },
	{ "Felstalker", 26, "normal", "Demon", 2, "Ashenvale", "Drain Mana: weakens the target's ability" },
	{ "Skeletal Warder", 30, "elite", "Undead", 1, "Scarlet Monastery", "Bone Shield: absorbs the first hit" },
	{ "Rock Elemental", 38, "normal", "Elemental", 1, "Badlands", "Stone Skin: takes 20% less damage" },
	{ "Mosh'Ogg Brute", 41, "normal", "Giant", 1, "Stranglethorn Vale", "Stomp: stuns the front enemy" },
	{ "Jade", 47, "rareelite", "Dragonkin", 1, "Swamp of Sorrows", "Sleep: the target skips a turn" },
	{ "Searing Infernal", 52, "normal", "Demon", 1, "Felwood", "Immolation: burns all enemies each turn" },
}

local OPPONENT = {
	{ "Bristleback Quilboar", 9, "normal", "Humanoid", 3, "The Barrens", "Thorns: hurts attackers" },
	{ "Plainstrider", 8, "normal", "Beast", 4, "The Barrens", "Kick: pushes the target back" },
	{ "Kolkar Centaur", 15, "elite", "Humanoid", 1, "The Barrens", "Charge: acts first in round one" },
	{ "Venture Co. Shredder", 20, "normal", "Mechanical", 2, "Stonetalon Mountains", "Saw Blade: bleeds the target" },
	{ "Thunderhawk Cloudscraper", 21, "normal", "Beast", 3, "The Barrens", "Lightning Breath: hits the front two" },
}

local function Budget(level, classification, stars)
	return (10 + level * 3) * ns.RARITIES[classification].factor * (1 + 0.15 * (stars - 1))
end

local function MakeCard(entry, index)
	local name, level, classification, family, stars, zone, ability = unpack(entry)
	local lean = ns.FAMILIES[family].lean
	local budget = Budget(level, classification, stars)
	return {
		id = index,
		name = name, level = level, classification = classification, family = family,
		stars = stars, zone = zone, ability = ability,
		power = math.floor(budget + 0.5),
		attack = math.max(1, math.floor(budget * lean[1] * 0.5 + 0.5)),
		health = math.max(5, math.floor(budget * lean[2] * 2.5 + 0.5)),
		speed = math.floor(40 + lean[3] * 200 + level / 2),
	}
end

ns.collection = {}
for i, entry in ipairs(COLLECTION) do
	ns.collection[i] = MakeCard(entry, i)
end

ns.opponent = { name = "Ricarda", cards = {} }
for i, entry in ipairs(OPPONENT) do
	ns.opponent.cards[i] = MakeCard(entry, 100 + i)
end

-- Your team, front to back: indexes into ns.collection
ns.team = { 5, 8, 7, 10, 2 }

function ns.TeamCards()
	local cards = {}
	for _, index in ipairs(ns.team) do
		cards[#cards + 1] = ns.collection[index]
	end
	return cards
end

function ns.TeamPower(cards)
	local power = 0
	for _, card in ipairs(cards) do
		power = power + card.power
	end
	return power
end

-- Family bonuses the team gets: list of { family, count }
function ns.TeamFamilies(cards)
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

-- A tiny stand-in for the real fight: everyone acts in speed order and hits the frontmost
-- enemy. Returns the list of events the replay plays back.
function ns.MockFight(mine, theirs)
	local seed = 12345
	local function Random(n)
		seed = (seed * 1103515245 + 12345) % 2147483648
		return seed % n + 1
	end
	local sides = { {}, {} }
	for side, cards in ipairs({ mine, theirs }) do
		for slot, card in ipairs(cards) do
			sides[side][slot] = { card = card, side = side, slot = slot, hp = card.health }
		end
	end
	local events = {}
	for round = 1, 30 do
		local order = {}
		for _, side in ipairs(sides) do
			for _, unit in ipairs(side) do
				if unit.hp > 0 then
					order[#order + 1] = unit
				end
			end
		end
		table.sort(order, function(a, b)
			return a.card.speed > b.card.speed
		end)
		for _, unit in ipairs(order) do
			if unit.hp > 0 then
				local target
				for _, enemy in ipairs(sides[3 - unit.side]) do
					if enemy.hp > 0 then
						target = enemy
						break
					end
				end
				if not target then
					events[#events + 1] = { kind = "win", side = unit.side }
					return events
				end
				local damage = math.max(1, unit.card.attack + Random(5) - 3)
				target.hp = math.max(0, target.hp - damage)
				events[#events + 1] = {
					kind = "hit", round = round, side = unit.side, slot = unit.slot,
					targetSide = target.side, targetSlot = target.slot, damage = damage, hp = target.hp,
				}
				if target.hp == 0 then
					events[#events + 1] = { kind = "death", side = target.side, slot = target.slot }
				end
			end
		end
	end
	events[#events + 1] = { kind = "win", side = 1 }
	return events
end
