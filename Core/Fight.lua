local _, ns = ...

-- The fight rules from ARCHITECTURE.md 5.2, as a first draft: no damage rolls, a seeded random
-- generator only for ties. ns.Fight(squadA, squadB, seed, twist) returns the events for the
-- replay and the winner (1, 2 or 0 for a draw). Squads are { cards = { card... } }; the leader is the squad's named card.
local MAX_ROUNDS = 20
local ASSASSIN_STRIKE = 1.6 -- an Assassin's one strike per round, times its attack
local ASSASSIN_ARMOR = 3 -- armor counts this many times against an Assassin's strike
local FOG = 1.5 -- Fog twist: Assassins hit this much harder in round 1
local SPLASH = 0.5
local HEAL_FADE = 0.9 -- each heal of a Healer is 10% weaker than its previous one
local HEALER_LEADER = 1.2 -- a Healer leader: all heals +20%
-- For the Info tab
ns.FIGHT_RULES = {
	maxRounds = MAX_ROUNDS, assassinStrike = ASSASSIN_STRIKE, assassinArmor = ASSASSIN_ARMOR,
	fog = FOG, splash = SPLASH, healFade = HEAL_FADE, healerLeader = HEALER_LEADER,
}

-- Family bonuses (3.4): with 2 or 4 cards of a family in the squad, those cards get the bonus.
-- Numbers are placeholders for balancing. Abilities don't exist yet, so Elemental strengthens
-- splash instead of ability damage, and speed bonuses are flat (speed runs 1-10).
local FAMILY_BONUS = {
	Beast = { { speed = 1, text = "+1 speed" }, { speed = 2, text = "+2 speed" } },
	Humanoid = { { stats = 0.1, text = "+10% attack and health" }, { stats = 0.2, speed = 1, text = "+20% attack and health, +1 speed" } },
	Undead = { { rise = 0.2, text = "the first to die gets back up at 20% health" }, { rise = 0.4, text = "the first to die gets back up at 40% health" } },
	Demon = { { attack = 0.15, drain = 0.02, text = "+15% attack, lose 2% health each turn" }, { attack = 0.35, drain = 0.02, text = "+35% attack, lose 2% health each turn" } },
	Dragonkin = { { health = 0.15, text = "+15% health" }, { health = 0.3, text = "+30% health" } },
	Elemental = { { splash = 0.2, text = "splash +20%" }, { splash = 0.5, text = "splash +50%" } },
	Giant = { { health = 0.2, speed = -1, text = "+20% health, -1 speed" }, { health = 0.4, speed = -1, text = "+40% health, -1 speed" } },
	Mechanical = { { guard = 0.1, text = "take 10% less damage" }, { guard = 0.2, text = "take 20% less damage" } },
}
ns.FAMILY_BONUS = FAMILY_BONUS

-- The family bonuses a squad has: { family, count, tier (1 or 2), text }, biggest first
function ns.FamilyBonuses(cards)
	local counts = {}
	for _, card in ipairs(cards) do
		counts[card.family] = (counts[card.family] or 0) + 1
	end
	local list = {}
	for family, count in pairs(counts) do
		local tier = count >= 4 and 2 or count >= 2 and 1 or nil
		if tier and FAMILY_BONUS[family] then
			list[#list + 1] = { family = family, count = count, tier = tier, text = FAMILY_BONUS[family][tier].text }
		end
	end
	table.sort(list, function(a, b)
		if a.count ~= b.count then
			return a.count > b.count
		end
		return a.family < b.family
	end)
	return list
end

local function Generator(seed)
	local state = seed % 2147483647
	if state <= 0 then
		state = state + 2147483646
	end
	return function(n)
		state = state * 16807 % 2147483647
		return state % n + 1
	end
end

-- The bonuses as text with family icons. long: with what each does (Squads tab), else short
-- ("2 Beast", Duel tab)
function ns.FamilyText(cards, long)
	local parts = {}
	for _, bonus in ipairs(ns.FamilyBonuses(cards)) do
		local icon = ("|T%s:16:16:0:0:64:64:5:59:5:59|t"):format(ns.FAMILIES[bonus.family].icon)
		if long then
			parts[#parts + 1] = ("%s |cffffd200%d %s:|r %s"):format(icon, bonus.count, bonus.family, bonus.text)
		else
			parts[#parts + 1] = ("%s %d"):format(icon, bonus.count)
		end
	end
	if #parts == 0 then
		return long and "|cff999999No family bonus: 2 or 4 cards of one family give one|r" or "|cff999999no family bonus|r"
	end
	return table.concat(parts, long and "     " or "  ")
end

local function Units(squad, side, twist)
	local units = {}
	local leader = ns.SquadLeader(squad.cards) -- the named card, if any
	local bonuses = {}
	for _, bonus in ipairs(ns.FamilyBonuses(squad.cards)) do
		bonuses[bonus.family] = FAMILY_BONUS[bonus.family][bonus.tier]
	end
	for slot, card in ipairs(squad.cards) do
		local unit = {
			card = card, side = side, slot = slot,
			hp = card.health, maxHp = card.health,
			attack = card.attack, speed = card.speed, armor = card.armor,
			kind = card.type, leader = leader and card.id == leader.id,
		}
		-- Leader abilities: one per combat type for now
		if leader then
			if leader.type == "Tank" and unit.kind == "Tank" then
				unit.armor = unit.armor + 2
			elseif leader.type == "Mage" and unit.kind == "Mage" then
				unit.attack = math.floor(unit.attack * 1.15 + 0.5)
			elseif leader.type == "Assassin" and unit.kind == "Assassin" then
				unit.firstRoundSpeed = 2
			elseif leader.type == "Healer" then
				unit.healBonus = HEALER_LEADER
			end
		end
		local bonus = bonuses[card.family]
		if bonus then
			local health = (bonus.health or 0) + (bonus.stats or 0)
			unit.maxHp = math.floor(unit.maxHp * (1 + health) + 0.5)
			unit.hp = unit.maxHp
			unit.attack = math.floor(unit.attack * (1 + (bonus.attack or 0) + (bonus.stats or 0)) + 0.5)
			unit.speed = math.max(1, math.min(ns.MAX_SPEED, unit.speed + (bonus.speed or 0)))
			unit.splash = SPLASH * (1 + (bonus.splash or 0))
			unit.guard = bonus.guard
			unit.drain = bonus.drain
			unit.rise = bonus.rise
		end
		if twist == "consecrated" and card.family == "Undead" then
			unit.armor = 0
		elseif twist == "shieldwall" then
			unit.armor = unit.armor * 2
			unit.speed = math.max(1, unit.speed - 1)
		end
		units[slot] = unit
	end
	return units
end

local function Front(units)
	for _, unit in ipairs(units) do
		if unit.hp > 0 then
			return unit
		end
	end
end

local function Back(units)
	for i = #units, 1, -1 do
		if units[i].hp > 0 then
			return units[i]
		end
	end
end

local function Behind(units, target)
	for i = target.slot + 1, #units do
		if units[i].hp > 0 then
			return units[i]
		end
	end
end

-- The living ally with the lowest share of its health left, nil if everyone is full
local function Weakest(units)
	local best, share
	for _, unit in ipairs(units) do
		if unit.hp > 0 and unit.hp < unit.maxHp and (not share or unit.hp / unit.maxHp < share) then
			best, share = unit, unit.hp / unit.maxHp
		end
	end
	return best
end

local function HealthShare(units)
	local hp, max = 0, 0
	for _, unit in ipairs(units) do
		hp, max = hp + unit.hp, max + unit.maxHp
	end
	return hp / max
end

function ns.Fight(squadA, squadB, seed, twist)
	local random = Generator(seed or 1)
	local sides = { Units(squadA, 1, twist), Units(squadB, 2, twist) }
	local events = {}

	local risen = {} -- side -> true once its Undead bonus was used

	local function Die(target)
		events[#events + 1] = { kind = "death", side = target.side, slot = target.slot }
		if target.rise and not risen[target.side] then
			risen[target.side] = true
			target.hp = math.max(1, math.floor(target.maxHp * target.rise + 0.5))
			events[#events + 1] = { kind = "rise", side = target.side, slot = target.slot, hp = target.hp }
		end
	end

	local function Hit(unit, target, amount, magic, splash)
		-- Armor takes its value off physical hits, three times off an Assassin's strike
		local armor = unit.kind == "Assassin" and target.armor * ASSASSIN_ARMOR or target.armor
		local damage = magic and amount or math.max(1, amount - armor)
		if target.guard then
			damage = math.max(1, math.floor(damage * (1 - target.guard) + 0.5))
		end
		damage = math.min(damage, target.hp)
		target.hp = target.hp - damage
		events[#events + 1] = {
			kind = "hit", side = unit.side, slot = unit.slot, targetSide = target.side,
			targetSlot = target.slot, damage = damage, hp = target.hp, splash = splash,
		}
		if target.hp == 0 then
			Die(target)
		end
	end

	local function Heal(unit, target, amount, splash)
		local healed = math.min(amount, target.maxHp - target.hp)
		if healed <= 0 then
			return
		end
		target.hp = target.hp + healed
		events[#events + 1] = {
			kind = "heal", side = unit.side, slot = unit.slot, targetSide = target.side,
			targetSlot = target.slot, amount = healed, hp = target.hp, splash = splash,
		}
	end

	local function Act(unit, round)
		local enemies = sides[3 - unit.side]
		if unit.drain then
			-- Demon bonus: costs health every turn, but never kills
			local loss = math.min(unit.hp - 1, math.max(1, math.floor(unit.maxHp * unit.drain + 0.5)))
			if loss > 0 then
				unit.hp = unit.hp - loss
				events[#events + 1] = { kind = "drain", side = unit.side, slot = unit.slot, damage = loss, hp = unit.hp }
			end
		end
		if unit.kind == "Healer" then
			-- Heals, never damages (5.2); nothing to do while everyone is full
			local allies = sides[unit.side]
			local target = Weakest(allies)
			if not target then
				return
			end
			local amount = unit.attack * (unit.healBonus or 1) * HEAL_FADE ^ (unit.heals or 0)
			unit.heals = (unit.heals or 0) + 1
			local behind = Behind(allies, target)
			Heal(unit, target, math.max(1, math.floor(amount + 0.5)))
			if behind then
				Heal(unit, behind, math.max(1, math.floor(amount * SPLASH + 0.5)), true)
			end
			return
		end
		if unit.kind == "Assassin" then
			-- One strike at the enemy's back card
			local target = Back(enemies)
			if target then
				local fog = twist == "fog" and round == 1 and FOG or 1
				Hit(unit, target, math.max(1, math.floor(unit.attack * ASSASSIN_STRIKE * fog + 0.5)))
			end
			return
		end
		local target = twist == "ambush" and Back(enemies) or Front(enemies)
		if not target then
			return
		end
		if unit.kind == "Mage" then
			local behind = Behind(enemies, target)
			Hit(unit, target, unit.attack, true)
			if behind then
				Hit(unit, behind, math.max(1, math.floor(unit.attack * (unit.splash or SPLASH) + 0.5)), true, true)
			end
		else
			Hit(unit, target, unit.attack)
		end
	end

	for round = 1, MAX_ROUNDS do
		events[#events + 1] = { kind = "round", round = round }
		-- Turn order (5.2): each side's cards line up fastest first (ties: front-most), then
		-- they pair up, one card of each side: the faster card of a pair acts first (ties: a
		-- seeded coin flip). The bigger squad's extra cards follow in a row.
		local queues = {}
		for side, units in ipairs(sides) do
			local queue = {}
			for _, unit in ipairs(units) do
				queue[#queue + 1] = unit
			end
			table.sort(queue, function(x, y)
				local sx = x.speed + (round == 1 and x.firstRoundSpeed or 0)
				local sy = y.speed + (round == 1 and y.firstRoundSpeed or 0)
				if sx ~= sy then
					return sx > sy
				end
				return x.slot < y.slot
			end)
			queues[side] = queue
		end
		local order = {}
		for i = 1, math.max(#queues[1], #queues[2]) do
			local a, b = queues[1][i], queues[2][i]
			if a and b then
				local sa = a.speed + (round == 1 and a.firstRoundSpeed or 0)
				local sb = b.speed + (round == 1 and b.firstRoundSpeed or 0)
				if sb > sa or (sb == sa and random(2) == 2) then
					a, b = b, a
				end
			end
			order[#order + 1] = a
			order[#order + 1] = b
		end
		for _, unit in ipairs(order) do
			if unit.hp > 0 then
				Act(unit, round) -- every card attacks once per round
				if not Front(sides[1]) or not Front(sides[2]) then
					local winner = Front(sides[1]) and 1 or 2
					events[#events + 1] = { kind = "end", winner = winner }
					return events, winner, sides
				end
			end
		end
	end
	local a, b = HealthShare(sides[1]), HealthShare(sides[2])
	local winner = a > b and 1 or b > a and 2 or 0
	events[#events + 1] = { kind = "end", winner = winner, timeout = true }
	return events, winner, sides
end
