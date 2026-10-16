local _, ns = ...

-- Prototype rules (ARCHITECTURE.md 3 and 4). Numbers are first guesses for balancing.

ns.STUDY_SECONDS = 10 -- seconds a mob type must be seen fighting before it can drop a card (4.0)
ns.STUDY_TICK = 0.5 -- how often visible mobs in combat are counted (each adds this much)

-- Drop chance per kill by classification (3.3). Rares, rare elites and bosses drop for sure the
-- first time once studied.
ns.DROP_CHANCE = { normal = 0.04, elite = 0.15, rare = 0.25, rareelite = 0.35, worldboss = 0.25 }
ns.FIRST_DROP_SURE = { rare = true, rareelite = true, worldboss = true }
ns.GROUP_FACTOR = { solo = 1, party = 0.75, raid = 0.25 }
ns.FARM_WINDOW = 3600 -- each card from the same mob type in this many seconds halves the chance
ns.MAX_STARS = 5
ns.TEST_CHANCE = 0.9 -- Test tab: drop chance while "until the next drop" is on
-- Starter boost: drop chances x5 (500%) until you own STARTER_CARDS different cards, then the
-- extra halves every STARTER_HALF more cards (x3 at 15, x2 at 20, x1.5 at 25 ...), gone at
-- STARTER_END
ns.STARTER_BOOST = 5
ns.STARTER_CARDS = 10
ns.STARTER_HALF = 5
ns.STARTER_END = 40

-- Card power (3.2): level doesn't count
ns.BASE_POWER = 60 -- stat budget of a common 1-star card

-- The power shown on cards and counted against the cap reads like a level: 0 to 63, where a
-- Legendary card with 5 stars (the biggest budget) is 63. Stats still come from the budget.
ns.MAX_POWER = 63
function ns.PowerFromBudget(budget)
	local most = ns.BASE_POWER * ns.RARITIES.worldboss.factor * (1 + ns.STAR_BONUS * (ns.MAX_STARS - 1))
	return math.max(1, math.floor(budget / most * ns.MAX_POWER + 0.5))
end
ns.STAR_BONUS = 0.15

-- Classification as the game reports it -> our rarity key. Skull-level mobs (UnitLevel -1) count
-- as bosses too.
ns.CLASSIFICATIONS = {
	normal = "normal", trivial = "normal", minus = "normal",
	elite = "elite", rare = "rare", rareelite = "rareelite", worldboss = "worldboss",
}

-- UnitCreatureType is localized; map the names we know to our families. Critters and
-- "Not specified" never drop cards.
ns.CREATURE_TYPES = {
	-- English
	["Beast"] = "Beast", ["Humanoid"] = "Humanoid", ["Undead"] = "Undead", ["Demon"] = "Demon",
	["Dragonkin"] = "Dragonkin", ["Elemental"] = "Elemental", ["Giant"] = "Giant",
	["Mechanical"] = "Mechanical", ["Critter"] = false, ["Not specified"] = false, ["Totem"] = false,
	-- German
	["Wildtier"] = "Beast", ["Untoter"] = "Undead", ["Dämon"] = "Demon", ["Drachkin"] = "Dragonkin",
	["Elementar"] = "Elemental", ["Riese"] = "Giant", ["Mechanisch"] = "Mechanical",
	["Kleintier"] = false, ["Nicht spezifiziert"] = false,
}

function ns.Print(msg)
	print("|cffc0ff60Bestiary:|r " .. msg)
end

-- NPC id from a creature GUID ("Creature-0-1-2-3-<npcId>-<spawn>"), nil for players, pets...
function ns.NpcId(guid)
	if not guid then
		return
	end
	local kind, _, _, _, _, npcId = strsplit("-", guid)
	if kind == "Creature" or kind == "Vehicle" then
		return tonumber(npcId)
	end
end

-- A number from the NPC id that's the same on every client, for stat nudges
function ns.Seed(npcId, salt)
	local x = (npcId * 2654435761 + (salt or 0) * 40503) % 4294967296
	x = (x * 1103515245 + 12345) % 2147483648
	return x / 2147483648 -- 0..1
end

function ns.SpellIcon(spellId, spellName)
	local id = spellId and spellId > 0 and spellId or spellName
	if not id then
		return
	end
	if C_Spell and C_Spell.GetSpellTexture then
		return C_Spell.GetSpellTexture(id)
	end
	return GetSpellTexture and GetSpellTexture(id)
end
