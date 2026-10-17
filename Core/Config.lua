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
-- Stars (decided 2026-10-17): 0 to 5. Once you own a mob's card, every kill of that mob can add
-- a star: STAR_CHANCE for the first, half of that for each next (10%, 5%, 2.5%, 1.25%, 0.625%).
-- Each star makes the card STAR_BONUS stronger in health and damage or healing.
ns.MAX_STARS = 5
ns.STAR_CHANCE = 0.10
function ns.StarChance(card)
	local stars = card.stars or 0
	if card.player or stars >= ns.MAX_STARS then
		return 0
	end
	return ns.STAR_CHANCE * 0.5 ^ stars
end
-- Bad luck protection: every kill of a studied mob type that drops nothing raises its chance by
-- DRY_BONUS of the base chance, up to DRY_MAX times; its next card resets it
ns.DRY_BONUS = 0.2
ns.DRY_MAX = 5
ns.TEST_CHANCE = 0.9 -- Test tab: drop chance while "until the next drop" is on
-- Starter boost: drop chances x5 (500%) until you own STARTER_CARDS different cards, then the
-- extra halves every STARTER_HALF more cards (x3 at 15, x2 at 20, x1.5 at 25 ...), gone at
-- STARTER_END
ns.STARTER_BOOST = 5
ns.STARTER_CARDS = 10
ns.STARTER_HALF = 5
ns.STARTER_END = 40

-- Card levels (3.2, decided 2026-10-17): a card is the real mob at its level. It starts at the
-- mob's level and gains one every GAMES_PER_LEVEL duels, won or lost (sparring too), at most
-- LEVELS_ABOVE_PLAYER above yours, up to 60 (named cards 63). Power is the card's level, and a
-- squad's cap is the sum of levels: CAP_PER_LEVEL times your level.
ns.GAMES_PER_LEVEL = 5
ns.LEVELS_ABOVE_PLAYER = 3
ns.MAX_NORMAL_LEVEL = 60
ns.CAP_PER_LEVEL = 5
ns.STAR_BONUS = 0.03

-- Tanks: more health, less damage (decided 2026-10-17, until something in the game tells tanks
-- and damage dealers apart better)
ns.TANK_HEALTH = 1.25
ns.TANK_DAMAGE = 0.75
ns.TANK_SLOW = 1.25 -- their attack time, so their turns come 25% less often (hits stay as big)

-- Until a mob type is measured (health from the damage meter, melee and spell hits on you), its
-- factors against the typical mob of its level and class are guessed by rarity. Guesses.
ns.GUESSED_FACTORS = {
	normal = { health = 1, damage = 1 },
	elite = { health = 3, damage = 1.75 },
	rare = { health = 1.4, damage = 1.2 },
	rareelite = { health = 3.5, damage = 2 },
	worldboss = { health = 8, damage = 3 },
}

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

-- Our own Lua errors are kept (BestiaryAccount.errors, saved on /reload or logout) so they can
-- be read later; /bst errors prints them. Other addons' errors are left alone; every error still
-- goes on to the game's normal handler.
local pendingErrors = {}
ns.errors = pendingErrors
if geterrorhandler and seterrorhandler then
	local original = geterrorhandler()
	seterrorhandler(function(msg, ...)
		if type(msg) == "string" and msg:find("Bestiary") then
			local list = (BestiaryAccount and BestiaryAccount.errors) or pendingErrors
			local found
			for _, entry in ipairs(list) do
				if entry.msg == msg then
					found = entry
				end
			end
			if found then
				found.count = found.count + 1
			elseif #list < 20 then
				list[#list + 1] = { msg = msg, count = 1, at = time and time() or 0,
					stack = debugstack and debugstack(2, 12, 0) or nil }
			end
		end
		return original(msg, ...)
	end)
end

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
