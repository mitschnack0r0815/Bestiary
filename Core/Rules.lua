local _, ns = ...

-- The game's rules shared by everything: rarities, families, combat types, squad limits and
-- checks, named leaders, twists (ARCHITECTURE.md 3, 5 and 6).

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
	Elemental = { icon = "Interface\\Icons\\Spell_Nature_Cyclone", color = { 0.5, 0.75, 1 } },
	Giant = { icon = "Interface\\Icons\\INV_Hammer_04", color = { 0.6, 0.6, 0.7 } },
	Mechanical = { icon = "Interface\\Icons\\INV_Gizmo_02", color = { 0.7, 0.8, 0.9 } },
}

-- Combat types (3.5): how the power budget turns into stats, and the look
ns.TYPES = {
	Tank = {
		icon = "Interface\\Icons\\INV_Shield_06", color = { 0.6, 0.75, 1 },
		health = 1.6, attack = 0.16, speed = 3, armor = 0.4,
		leader = "Leader: Tank allies +2 armor",
	},
	Mage = {
		icon = "Interface\\Icons\\Spell_Fire_FlameBolt", color = { 1, 0.45, 0.2 },
		health = 0.7, attack = 0.30, speed = 5, armor = 0,
		leader = "Leader: Mage allies +15% attack",
	},
	Assassin = {
		icon = "Interface\\Icons\\Ability_BackStab", color = { 0.75, 1, 0.4 },
		health = 0.9, attack = 0.24, speed = 8, armor = 0,
		leader = "Leader: Assassin allies +2 speed in round 1",
	},
	-- Built like Mage, heals instead of damaging (3.5)
	Healer = {
		icon = "Interface\\Icons\\Spell_Holy_Heal", color = { 0.55, 1, 0.85 },
		health = 0.7, attack = 0.30, speed = 5, armor = 0,
		leader = "Leader: all heals +20%",
	},
}
ns.MAX_SPEED = 10 -- speed runs from 1 to this
ns.ALL_TYPES = { "Tank", "Mage", "Assassin", "Healer" }
ns.TYPE_ORDER = { "Tank", "Mage", "Assassin" }

ns.POWER_CAP = 100 -- one fixed cap for now, in level-like power (choosing a cap comes later)
ns.CAPS = { ns.POWER_CAP }

-- Named mobs lead (decided): a card from a named mob is always its squad's leader, and a squad
-- holds at most one. The game has no "named" flag; rares, rare elites and bosses (skull level,
-- boss frames) are the named ones it can tell apart. Named elites that aren't rare (Hogger)
-- look like any elite to an addon, so they don't count.
ns.NAMED = { rare = true, rareelite = true, worldboss = true }

function ns.IsNamed(card)
	return card.player == true or ns.NAMED[card.classification] == true
		or ns.IsKnownNamed(card.npcId, card.name) == true
end

-- The squad's leader: its named card, if it has one
function ns.SquadLeader(cards)
	for _, card in ipairs(cards) do
		if ns.IsNamed(card) then
			return card
		end
	end
end

-- No minimum or maximum size (decided): only the power cap counts. As many slots as the
-- weakest cards (common, 1 star: 13) fit under the cap: 7 at a cap of 100.
ns.MIN_SQUAD = 1
ns.MAX_SQUAD = math.floor(ns.POWER_CAP / ns.PowerFromBudget(ns.BASE_POWER))

-- Copies (decided): a normal (Common) card that isn't named can be owned up to 3 times, and a
-- squad can hold as many copies as you own. Everything else once.
ns.MAX_COPIES = 3
function ns.CanHaveCopies(card)
	return card.classification == "normal" and not ns.IsNamed(card)
end

function ns.Copies(card)
	return ns.CanHaveCopies(card) and math.min(ns.MAX_COPIES, card.copies or 1) or 1
end

function ns.Power(cards)
	local power = 0
	for _, card in ipairs(cards) do
		power = power + card.power
	end
	return power
end

-- "[shield] 2  [fire] 1  [dagger] 2": each type's icon and how many
function ns.TypeMix(cards)
	local counts = {}
	for _, card in ipairs(cards) do
		counts[card.type] = (counts[card.type] or 0) + 1
	end
	local parts = {}
	for _, kind in ipairs(ns.ALL_TYPES) do
		if counts[kind] then
			local r, g, b = unpack(ns.TYPES[kind].color)
			parts[#parts + 1] = ("|T%s:16:16:0:0:64:64:5:59:5:59|t |cff%02x%02x%02x%d|r"):format(
				ns.TYPES[kind].icon, r * 255, g * 255, b * 255, counts[kind])
		end
	end
	return table.concat(parts, "   ")
end

-- Roster rules (6.1). Returns a list of { ok, text }; the squad can be locked in if all are ok.
function ns.Checks(squad)
	local cards = ns.SquadCards(squad)
	local checks = {}
	local function Check(ok, text)
		checks[#checks + 1] = { ok = ok, text = text }
	end
	local named = {}
	for _, card in ipairs(cards) do
		if ns.IsNamed(card) then
			named[#named + 1] = card
		end
	end
	-- No leader is fine (named cards are rare); more than one isn't
	if #named == 1 then
		Check(true, "Leader: " .. named[1].name)
	elseif #named > 1 then
		Check(false, "Only one named card")
	end
	Check(#cards >= ns.MIN_SQUAD, #cards == 0 and "No cards yet" or ("%d %s"):format(#cards, #cards == 1 and "card" or "cards"))
	local power = ns.Power(cards)
	Check(power <= squad.cap, power <= squad.cap and "Within cap" or "Over the cap")
	for _, card in ipairs(cards) do
		if card.exhausted then
			Check(false, card.name .. " is exhausted")
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

-- Training cards: one type, a given power, no mob behind them. For headless balance runs and
-- the sparring partner when you haven't seen enough mobs yet.
function ns.TrainingCard(kind, power, name, n)
	local t = ns.TYPES[kind]
	local attack = math.max(1, math.floor(power * t.attack + 0.5))
	return {
		id = "training:" .. kind .. ":" .. (n or 1),
		name = name or ("Training " .. kind), classification = "normal", family = "Humanoid", type = kind,
		stars = 1, zone = "", power = ns.PowerFromBudget(power),
		health = math.max(5, math.floor(power * t.health + 0.5)),
		attack = attack, speed = t.speed, armor = math.floor(attack * t.armor + 0.5),
		stamina = 100,
	}
end

-- Five training cards of one type with the same total power
function ns.TrainingSquad(kind, power)
	local cards = {}
	for i = 1, 5 do
		cards[i] = ns.TrainingCard(kind, power / 5, nil, i)
	end
	return { cards = cards }
end

-- Twists (6.2): each duel draws one
ns.TWISTS = {
	{ key = "calm", name = "Calm Waters", text = "No twist." },
	{ key = "fog", name = "Fog", text = "Assassins hit 50% harder in round 1." },
	{ key = "consecrated", name = "Consecrated Ground", text = "Undead have no armor." },
	{ key = "ambush", name = "Ambush", text = "Everyone hits the back row first." },
	{ key = "shieldwall", name = "Shield Wall", text = "Armor counts double, everyone is slower." },
}
