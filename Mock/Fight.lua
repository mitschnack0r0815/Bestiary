local _, ns = ...

-- The fight rules from ARCHITECTURE.md 5.2, as a first draft: no damage rolls, a seeded random
-- generator only for ties. ns.Fight(squadA, squadB, seed, twist) returns the events for the
-- replay and the winner (1, 2 or 0 for a draw). Squads are { cards = { card... }, leader = id }.
local MAX_ROUNDS = 20
local ASSASSIN_STRIKE = 0.6
local SPLASH = 0.5
local TYPE_TIE = { Assassin = 1, Magic = 2, Armor = 3 }

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

local function Units(squad, side, twist)
	local units = {}
	local leader = squad.leader and ns.byId[squad.leader]
	for slot, card in ipairs(squad.cards) do
		local unit = {
			card = card, side = side, slot = slot,
			hp = card.health, maxHp = card.health,
			attack = card.attack, speed = card.speed, armor = card.armor,
			kind = card.type, leader = leader and card.id == leader.id,
		}
		-- Leader abilities: one per combat type for now
		if leader then
			if leader.type == "Armor" and unit.kind == "Armor" then
				unit.armor = unit.armor + 2
			elseif leader.type == "Magic" and unit.kind == "Magic" then
				unit.attack = math.floor(unit.attack * 1.15 + 0.5)
			elseif leader.type == "Assassin" and unit.kind == "Assassin" then
				unit.firstRoundSpeed = 10
			end
		end
		if twist == "consecrated" and card.family == "Undead" then
			unit.armor = 0
		elseif twist == "shieldwall" then
			unit.armor = unit.armor * 2
			unit.speed = math.floor(unit.speed * 0.8)
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

	local function Hit(unit, target, amount, magic, splash)
		local damage = magic and amount or math.max(1, amount - target.armor)
		damage = math.min(damage, target.hp)
		target.hp = target.hp - damage
		events[#events + 1] = {
			kind = "hit", side = unit.side, slot = unit.slot, targetSide = target.side,
			targetSlot = target.slot, damage = damage, hp = target.hp, splash = splash,
		}
		if target.hp == 0 then
			events[#events + 1] = { kind = "death", side = target.side, slot = target.slot }
		end
	end

	local function Act(unit)
		local enemies = sides[3 - unit.side]
		if unit.kind == "Assassin" then
			for _ = 1, 2 do
				local target = Back(enemies)
				if not target then
					return
				end
				Hit(unit, target, math.max(1, math.floor(unit.attack * ASSASSIN_STRIKE + 0.5)))
			end
			return
		end
		local target = twist == "ambush" and Back(enemies) or Front(enemies)
		if not target then
			return
		end
		if unit.kind == "Magic" then
			local behind = Behind(enemies, target)
			Hit(unit, target, unit.attack, true)
			if behind then
				Hit(unit, behind, math.max(1, math.floor(unit.attack * SPLASH + 0.5)), true, true)
			end
		else
			Hit(unit, target, unit.attack)
		end
	end

	for round = 1, MAX_ROUNDS do
		events[#events + 1] = { kind = "round", round = round }
		local order = {}
		for _, units in ipairs(sides) do
			for _, unit in ipairs(units) do
				if unit.hp > 0 then
					unit.initiative = unit.speed + (round == 1 and unit.firstRoundSpeed or 0)
					unit.coin = random(1000)
					order[#order + 1] = unit
				end
			end
		end
		table.sort(order, function(a, b)
			if a.initiative ~= b.initiative then
				return a.initiative > b.initiative
			elseif a.kind ~= b.kind then
				return TYPE_TIE[a.kind] < TYPE_TIE[b.kind]
			elseif a.slot ~= b.slot then
				return a.slot < b.slot
			end
			return a.coin < b.coin
		end)
		for _, unit in ipairs(order) do
			if unit.hp > 0 then
				Act(unit)
				if twist == "fog" and round == 1 and unit.kind == "Assassin" then
					Act(unit)
				end
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
