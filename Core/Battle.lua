local _, ns = ...

-- Battles (ARCHITECTURE.md 5.5): the Pokémon-style fight, its own rules, nothing shared with the
-- board fight (Fight.lua) but the cards. Each side has a team of up to MAX_TEAM; one card each is on the
-- field, the others wait on the bench. The sides take turns strictly: a turn is one move of the
-- card on the field (attack, spell, heal, guard, an ability) or a switch to a card on the bench
-- (that costs the turn). A card knocked out is replaced at once by one its owner picks (free).
-- Families hit each other harder or softer by the type chart (TypeChart.lua).
--
-- Deterministic: a battle is its two teams, the two leads, the seed (only for a speed tie on
-- the first turn) and the list of moves, so any client rebuilds it from those.
--   a       attack (melee, armor counts)         s       spell (ignores armor)
--   h       heal itself (Healers)                m<n>    mend the card in slot n on the bench
--   b       restore: heal every hurt card on the bench a little (Healers)
--   g       guard: the next hit on it is halved (Tanks)
--   x<c>    ability with code c (Abilities.lua)  z       wait (nothing else it can do)
--   w<n>    switch to slot n (costs the turn)    n<n>    send slot n in after a knockout (free)
local Battle = {}
ns.Battle = Battle

Battle.TURN = 4 -- seconds of a real fight one turn stands for: damage per turn is damage per second x this
Battle.MAX_TURNS = 100 -- then the side with more health left in percent wins
Battle.SPELL_COOLDOWN = 2 -- turns a Tank's or Warrior's spell waits before it can be cast again (Mages: none)
Battle.GUARD = 0.5 -- the next hit on a guarding Tank
Battle.BLOCK = 0.7 -- Tanks block: physical hits on them (after armor)
Battle.HEAL = 0.6 -- a heal: this share of one cast of the Healer's spell
Battle.HEALER_MELEE = 0.5 -- Healers are weak fighters: their strength is healing the bench
Battle.HEAL_DECAY = 0.8 -- each heal of a card is this much of the one before
Battle.RESTORE = 0.5 -- restore heals each hurt card on the bench for this share of a heal (mend: a whole heal on one)
Battle.SLOW = 0.7 -- a slowed card's damage
Battle.ENRAGE = 1.5 -- below 30% health
Battle.MAX_TEAM = 3 -- cards per team (decided: 3 v 3 for now, quicker to test)

-- Abilities in battles: cooldown in the user's turns, and how many of the target's turns the
-- effect lasts (from its real duration: one turn per TURN seconds, at most max)
Battle.EFFECTS = {
	stun = { cooldown = 4, max = 1 },
	fear = { cooldown = 4, max = 2 },
	silence = { cooldown = 3, max = 2 },
	disarm = { cooldown = 3, max = 2 },
	slow = { cooldown = 3, max = 4 },
	poison = { cooldown = 3, max = 5 },
}

local function Round(x)
	return math.floor(x + 0.5)
end

-- Control effects: after one wears off, the card can't be controlled again for CONTROL_IMMUNE of
-- its turns (no stun lock by switching in fresh stunners)
Battle.CONTROL = { stun = true, fear = true, silence = true, disarm = true }
Battle.CONTROL_IMMUNE = 2
Battle.POISON = 0.15 -- a poison tick: this share of the poisoner's damage per turn
Battle.ABILITY_HIT = 0.5 -- an ability used as a move hits for this share of the card's damage too

-- A card in a battle
local function Unit(card, side, slot)
	local attackTime = math.max(0.5, card.attackSpeed or card.speed or 2)
	local castTime = math.max(1.5, card.castTime or 3)
	if card.type == "Tank" then
		attackTime = attackTime / (ns.TANK_SLOW or 1) -- turns don't come slower in a battle, so their hits don't either
	end
	local unit = {
		card = card, side = side, slot = slot,
		maxHp = card.health, hp = card.health,
		armor = card.armor or 0, level = card.level or 1,
		melee = math.max(1, Round((card.attack or 1) * Battle.TURN / attackTime * (card.type == "Healer" and Battle.HEALER_MELEE or 1))),
		cooldowns = {},
		heals = 0,
	}
	if card.spellPower then
		-- Mages cast all the time: per turn like melee; a Healer's heal and the others' spell are
		-- one cast
		unit.spell = math.max(1, Round(card.spellPower * (card.type == "Mage" and Battle.TURN / castTime or 1)))
		unit.spellName = card.spell
	end
	-- An ability that's part of the signature spell comes with every cast of it
	unit.abilities, unit.onSpell = {}, {}
	for _, ability in ipairs(card.abilities or {}) do
		local def = ns.ABILITIES[ability.key]
		if def and def.passive then
			unit[ability.key] = true -- enrage
		elseif def and ability.onSpell and unit.spell then
			unit.onSpell[#unit.onSpell + 1] = ability
		elseif def and Battle.EFFECTS[ability.key] then
			unit.abilities[#unit.abilities + 1] = ability
		end
	end
	return unit
end

local function Event(state, event)
	event.turn = state.count
	state.events[#state.events + 1] = event
end

function Battle.Active(state, side)
	local team = state.sides[side]
	return team.units[team.active]
end

local function Alive(team)
	local n = 0
	for _, unit in ipairs(team.units) do
		if unit.hp > 0 then
			n = n + 1
		end
	end
	return n
end
Battle.Alive = function(state, side)
	return Alive(state.sides[side])
end

local function HealthShare(team)
	local hp, max = 0, 0
	for _, unit in ipairs(team.units) do
		hp, max = hp + math.max(0, unit.hp), max + unit.maxHp
	end
	return max > 0 and hp / max or 0
end
Battle.HealthShare = function(state, side)
	return HealthShare(state.sides[side])
end

local function End(state, winner, why)
	state.winner = winner
	state.need, state.turn = nil, nil
	Event(state, { kind = "end", winner = winner, why = why })
end

-- teams: two lists of card views; leads: the slot each side starts with
function Battle.New(teamA, teamB, leadA, leadB, seed)
	local state = { sides = {}, count = 0, events = {}, seed = seed or 0 }
	for side, cards in ipairs({ teamA, teamB }) do
		local units = {}
		for slot, card in ipairs(cards) do
			units[slot] = Unit(card, side, slot)
		end
		state.sides[side] = { units = units, active = side == 1 and leadA or leadB }
	end
	for side = 1, 2 do
		local unit = Battle.Active(state, side)
		if not unit then
			End(state, 0, "no lead")
			return state
		end
		unit.fought, unit.cameIn = true, 0
		Event(state, { kind = "lead", side = side, slot = unit.slot })
	end
	-- The faster card on the field starts (its attack time; casters: their cast time); a tie by
	-- the seed
	local a, b = Battle.Active(state, 1).card.speed or 2, Battle.Active(state, 2).card.speed or 2
	state.turn = a < b and 1 or b < a and 2 or (state.seed % 2 + 1)
	Battle.BeginTurn(state)
	return state
end

-- Damage --------------------------------------------------------------------------------------

local function ArmorShare(armor, level)
	if armor <= 0 then
		return 0
	end
	return math.min(0.75, armor / (armor + 400 + 85 * level))
end

-- How much a move of unit does to target: amount and the type factor
function Battle.Damage(unit, target, key)
	local amount = key == "spell" and unit.spell or unit.melee
	if not amount then
		return 0, 1
	end
	local factor = ns.TypeFactor(unit.card.family, target.card.family)
	amount = amount * factor
	if key ~= "spell" then
		amount = amount * (1 - ArmorShare(target.armor, unit.level)) * (target.card.type == "Tank" and Battle.BLOCK or 1)
	end
	if unit.slowed then
		amount = amount * Battle.SLOW
	end
	if unit.enrage and unit.hp < unit.maxHp * 0.3 then
		amount = amount * Battle.ENRAGE
	end
	if target.guard then
		amount = amount * Battle.GUARD
	end
	return math.max(1, Round(amount)), factor
end

-- An ability used as its own move also hits: ABILITY_HIT of the card's usual damage (Mages: their
-- spell). Returns damage, type factor and "spell" or "attack".
function Battle.AbilityDamage(unit, target)
	local how = unit.card.type == "Mage" and unit.spell and "spell" or "attack"
	local damage, factor = Battle.Damage(unit, target, how)
	return math.max(1, Round(damage * Battle.ABILITY_HIT)), factor, how
end

function Battle.HealAmount(unit, restore)
	local amount = (unit.spell or 0) * Battle.HEAL * Battle.HEAL_DECAY ^ unit.heals * (restore and Battle.RESTORE or 1)
	return math.max(1, Round(amount))
end

local function Faint(state, unit)
	unit.hp = 0
	unit.poison = nil
	Event(state, { kind = "faint", side = unit.side, slot = unit.slot })
end

local function Hurt(state, by, target, damage)
	target.hp = math.max(0, target.hp - damage)
	if target.guard then
		target.guard = nil -- one hit
	end
	if target.feared and target.hp > 0 then
		target.feared = nil
		Event(state, { kind = "unfeared", side = target.side, slot = target.slot })
	end
	if target.hp <= 0 then
		Faint(state, target)
		if by then
			by.kos = (by.kos or 0) + 1
		end
	end
end

-- Statuses that end when a card leaves the field; poison stays
local function ClearVolatile(unit)
	unit.stunned, unit.feared, unit.silenced, unit.disarmed, unit.slowed, unit.guard = nil, nil, nil, nil, nil, nil
end

local function Afflict(state, unit, target, ability)
	local rule = Battle.EFFECTS[ability.key]
	if not rule or target.hp <= 0 then
		return
	end
	local turns = math.max(1, math.min(rule.max, math.ceil((ability.duration or ns.ABILITIES[ability.key].duration or 2) / Battle.TURN)))
	if Battle.CONTROL[ability.key] then
		if (target.immune or 0) > 0 then
			Event(state, { kind = "immune", side = unit.side, slot = unit.slot, targetSide = target.side, targetSlot = target.slot,
				effect = ability.key })
			return
		end
		target.immune = turns + Battle.CONTROL_IMMUNE
	end
	if ability.key == "stun" then
		target.stunned = turns
	elseif ability.key == "fear" then
		target.feared = turns
	elseif ability.key == "silence" then
		target.silenced = turns
	elseif ability.key == "disarm" then
		target.disarmed = turns
	elseif ability.key == "slow" then
		target.slowed = turns
	elseif ability.key == "poison" then
		target.poison = { turns = turns, damage = math.max(1, Round(unit.melee * Battle.POISON)) }
	end
	Event(state, { kind = "effect", side = unit.side, slot = unit.slot, targetSide = target.side, targetSlot = target.slot,
		effect = ability.key, turns = turns, ability = ability })
end

-- Turns -----------------------------------------------------------------------------------------

-- The start of a side's turn: poison ticks on its cards (on the bench too). If its card on the
-- field goes down, it sends another in first.
function Battle.BeginTurn(state)
	local side = state.turn
	local team = state.sides[side]
	state.begun = true -- a card sent in after a poison knockout doesn't start the turn again
	for _, unit in ipairs(team.units) do
		if unit.poison and unit.hp > 0 then
			local damage = math.min(unit.hp, unit.poison.damage)
			unit.hp = unit.hp - damage
			Event(state, { kind = "tick", side = side, slot = unit.slot, damage = damage, hp = unit.hp })
			unit.poison.turns = unit.poison.turns - 1
			if unit.poison.turns <= 0 then
				unit.poison = nil
			end
			if unit.hp <= 0 then
				Faint(state, unit)
			end
		end
	end
	local active = Battle.Active(state, side)
	if active then
		active.guard = nil -- a guard lasts until the guarding card's next turn
	end
	if Alive(team) == 0 then
		End(state, 3 - side)
	elseif active.hp <= 0 then
		state.need = side
	end
end

-- The end of a side's turn: its card's statuses and cooldowns count down, the other side's turn
local function EndTurn(state)
	local side = state.turn
	local unit = Battle.Active(state, side)
	if unit then
		for _, key in ipairs({ "stunned", "feared", "silenced", "disarmed", "slowed", "immune" }) do
			if unit[key] then
				unit[key] = unit[key] - 1
				if unit[key] <= 0 then
					unit[key] = nil
				end
			end
		end
		for key, left in pairs(unit.cooldowns) do
			unit.cooldowns[key] = left > 1 and left - 1 or nil
		end
	end
	state.count = state.count + 1
	state.begun = false
	if state.count >= Battle.MAX_TURNS then
		local a, b = HealthShare(state.sides[1]), HealthShare(state.sides[2])
		End(state, a > b and 1 or b > a and 2 or 0, "turns")
		return
	end
	local other = 3 - side
	state.turn = other
	if Alive(state.sides[other]) == 0 then
		End(state, side)
	elseif Battle.Active(state, other).hp <= 0 then
		state.need = other -- knocked out: they send a card in, then it's their turn
	else
		Battle.BeginTurn(state)
	end
end

-- Who moves now: side, and "send" (a card in after a knockout) or "act"; nil when it's over
function Battle.Expecting(state)
	if state.winner then
		return nil
	elseif state.need then
		return state.need, "send"
	end
	return state.turn, "act"
end

-- Moves -----------------------------------------------------------------------------------------

-- What the card on the field can do: list of { key, move, name, ready, why, ability }
function Battle.Moves(state, side)
	local unit = Battle.Active(state, side)
	local enemy = Battle.Active(state, 3 - side)
	local list = {}
	if not unit or unit.hp <= 0 then
		return list
	end
	local function Add(entry)
		list[#list + 1] = entry
	end
	local held = unit.stunned and "stunned" or unit.feared and "feared" or nil
	local kind = unit.card.type
	if kind ~= "Mage" then
		Add({ key = "attack", move = "a", name = "Attack", ready = not held and not unit.disarmed,
			why = held or (unit.disarmed and "disarmed") })
	end
	if unit.spell and kind ~= "Healer" then
		local cooldown = unit.cooldowns.spell
		Add({ key = "spell", move = "s", name = unit.spellName or "Spell", ready = not held and not unit.silenced and not cooldown,
			why = held or (unit.silenced and "silenced") or (cooldown and ("ready in %d turns"):format(cooldown)) })
	end
	if kind == "Healer" and unit.spell then
		Add({ key = "heal", move = "h", name = unit.spellName or "Heal", ready = not held and not unit.silenced and unit.hp < unit.maxHp,
			why = held or (unit.silenced and "silenced") or (unit.hp >= unit.maxHp and "full health") })
		local hurt = false
		for _, other in ipairs(state.sides[side].units) do
			if other ~= unit and other.hp > 0 and other.hp < other.maxHp then
				hurt = true
			end
		end
		local why = held or (unit.silenced and "silenced") or (not hurt and "nobody hurt on the bench")
		Add({ key = "mend", move = "m", name = "Mend", ready = not why, why = why, bench = true })
		Add({ key = "restore", move = "b", name = "Restore", ready = not why, why = why })
	end
	if kind == "Tank" then
		Add({ key = "guard", move = "g", name = "Guard", ready = not held and not unit.cooldowns.guard,
			why = held or (unit.cooldowns.guard and ("ready in %d turns"):format(unit.cooldowns.guard)) })
	end
	for _, ability in ipairs(unit.abilities) do
		local def = ns.ABILITIES[ability.key]
		local cooldown = unit.cooldowns[ability.key]
		local immune = Battle.CONTROL[ability.key] and enemy and (enemy.immune or 0) > 0 and enemy.immune
		Add({ key = ability.key, move = "x" .. def.code, name = def.name, ability = ability,
			ready = not held and not cooldown and not immune and enemy ~= nil and enemy.hp > 0,
			why = held or (cooldown and ("ready in %d turns"):format(cooldown))
				or (immune and ("immune to control for %d turns"):format(immune)) })
	end
	local any = false
	for _, entry in ipairs(list) do
		any = any or entry.ready
	end
	if not any then
		Add({ key = "wait", move = "z", name = "Wait", ready = true })
	end
	return list
end

-- Cards on the bench that can come in
function Battle.Bench(state, side)
	local team = state.sides[side]
	local list = {}
	for slot, unit in ipairs(team.units) do
		if slot ~= team.active and unit.hp > 0 then
			list[#list + 1] = unit
		end
	end
	return list
end

local function MoveEntry(state, side, move)
	for _, entry in ipairs(Battle.Moves(state, side)) do
		if entry.move == move:sub(1, #entry.move) and entry.ready then
			return entry
		end
	end
end

-- Whether side may make this move now
function Battle.Legal(state, side, move)
	local expected, phase = Battle.Expecting(state)
	if expected ~= side or type(move) ~= "string" then
		return false
	end
	local kind, slot = move:sub(1, 1), tonumber(move:sub(2))
	local team = state.sides[side]
	if phase == "send" then
		return kind == "n" and slot ~= nil and team.units[slot] ~= nil and team.units[slot].hp > 0
	end
	if kind == "w" then
		return slot ~= nil and slot ~= team.active and team.units[slot] ~= nil and team.units[slot].hp > 0
	elseif kind == "m" then
		local target = slot and team.units[slot]
		return MoveEntry(state, side, "m") ~= nil and target ~= nil and slot ~= team.active and target.hp > 0
			and target.hp < target.maxHp
	elseif kind == "x" then
		return #move == 2 and MoveEntry(state, side, move) ~= nil
	end
	return #move == 1 and kind ~= "n" and MoveEntry(state, side, move) ~= nil
end

local function SwitchIn(state, side, slot, kind)
	local team = state.sides[side]
	local leaving = team.units[team.active]
	if leaving then
		ClearVolatile(leaving)
	end
	team.active = slot
	team.units[slot].cameIn = state.count
	team.units[slot].fought = true -- was on the field (battle XP)
	Event(state, { kind = kind, side = side, slot = slot, from = leaving and leaving.slot })
end

-- Plays a move (it must be legal)
function Battle.Apply(state, side, move)
	local _, phase = Battle.Expecting(state)
	local kind, slot = move:sub(1, 1), tonumber(move:sub(2))
	if phase == "send" then
		SwitchIn(state, side, slot, "send")
		state.need = nil
		if not state.begun then
			Battle.BeginTurn(state) -- it's that side's turn now (the one whose card went down)
		end
		return
	end
	local unit = Battle.Active(state, side)
	local enemy = Battle.Active(state, 3 - side)
	if kind == "w" then
		SwitchIn(state, side, slot, "switch")
	elseif kind == "a" or kind == "s" then
		local key = kind == "a" and "attack" or "spell"
		local damage, factor = Battle.Damage(unit, enemy, key)
		Event(state, { kind = "hit", side = side, slot = unit.slot, targetSide = enemy.side, targetSlot = enemy.slot,
			action = key, damage = damage, factor = factor, hp = math.max(0, enemy.hp - damage), magic = key == "spell",
			guarded = enemy.guard })
		Hurt(state, unit, enemy, damage)
		if key == "spell" then
			if unit.card.type ~= "Mage" then
				unit.cooldowns.spell = Battle.SPELL_COOLDOWN + 1 -- counts down at the end of this turn
			end
			for _, ability in ipairs(unit.onSpell) do
				Afflict(state, unit, enemy, ability)
			end
		end
	elseif kind == "h" or kind == "m" or kind == "b" then
		local targets = kind == "h" and { unit } or kind == "m" and { state.sides[side].units[slot] } or Battle.Bench(state, side)
		local heal = Battle.HealAmount(unit, kind == "b")
		for _, target in ipairs(targets) do
			local amount = math.min(heal, target.maxHp - target.hp)
			if amount > 0 then
				target.hp = target.hp + amount
				Event(state, { kind = "heal", side = side, slot = unit.slot, targetSide = side, targetSlot = target.slot,
					amount = amount, hp = target.hp, bench = kind ~= "h" })
			end
		end
		unit.heals = unit.heals + 1
	elseif kind == "g" then
		unit.guard = true
		unit.cooldowns.guard = 3 -- not on its next two turns
		Event(state, { kind = "guard", side = side, slot = unit.slot })
	elseif kind == "x" then
		local key = ns.ABILITY_BY_CODE[move:sub(2, 2)]
		for _, ability in ipairs(unit.abilities) do
			if ability.key == key then
				local damage, factor, how = Battle.AbilityDamage(unit, enemy)
				Event(state, { kind = "hit", side = side, slot = unit.slot, targetSide = enemy.side, targetSlot = enemy.slot,
					action = key, ability = ability, damage = damage, factor = factor, hp = math.max(0, enemy.hp - damage),
					magic = how == "spell", guarded = enemy.guard })
				Hurt(state, unit, enemy, damage)
				Afflict(state, unit, enemy, ability)
				unit.cooldowns[key] = Battle.EFFECTS[key].cooldown + 1
				break
			end
		end
	elseif kind == "z" then
		Event(state, { kind = "wait", side = side, slot = unit.slot,
			why = unit.stunned and "stunned" or unit.feared and "feared" or nil })
	end
	if Alive(state.sides[3 - side]) == 0 then
		End(state, side)
		return
	end
	EndTurn(state)
end

-- Rebuilds a battle from its moves (strings, in order; each knows its side by whose move it is).
-- Returns the state and the number of the first move that isn't legal, if any.
function Battle.Replay(teamA, teamB, leadA, leadB, seed, moves)
	local state = Battle.New(teamA, teamB, leadA, leadB, seed)
	for i, move in ipairs(moves or {}) do
		local side = Battle.Expecting(state)
		if not side or not Battle.Legal(state, side, move) then
			return state, i
		end
		Battle.Apply(state, side, move)
	end
	return state
end

-- Sparring partner -----------------------------------------------------------------------------

-- How the families of two cards meet: above 1 good for unit, below 1 good for enemy
local function TypeEdge(unit, enemy)
	return ns.TypeFactor(unit.card.family, enemy.card.family) / ns.TypeFactor(enemy.card.family, unit.card.family)
end

-- The bench card that meets this enemy best (type first, then health)
local function BestBench(state, side, enemy)
	local best, score
	for _, unit in ipairs(Battle.Bench(state, side)) do
		local value = TypeEdge(unit, enemy) + unit.hp / unit.maxHp * 0.5
		if not score or value > score then
			best, score = unit, value
		end
	end
	return best
end

-- The sparring partner's lead: its first card that isn't a Healer
function Battle.AILead(cards)
	for slot, card in ipairs(cards) do
		if card.type ~= "Healer" then
			return slot
		end
	end
	return 1
end

-- Whether an effect is worth using on this enemy now
local function Useful(key, enemy)
	if key == "stun" or key == "fear" then
		return true
	elseif key == "silence" then
		return enemy.spell ~= nil and (enemy.card.type == "Mage" or enemy.card.type == "Healer") and not enemy.silenced
	elseif key == "disarm" then
		return enemy.card.type ~= "Mage" and not enemy.disarmed
	elseif key == "slow" then
		return not enemy.slowed
	elseif key == "poison" then
		return not enemy.poison and enemy.hp > enemy.maxHp * 0.4
	end
end

-- The sparring partner's move: after a knockout, send the card that meets theirs best; switch
-- out of a bad type matchup (not right after coming in); heal when low; knock out if it can; use
-- its abilities when they help; else the move that hurts most
function Battle.AI(state)
	local side, phase = Battle.Expecting(state)
	if not side then
		return nil
	end
	local enemy = Battle.Active(state, 3 - side)
	if phase == "send" then
		local best = BestBench(state, side, enemy)
		return best and ("n" .. best.slot)
	end
	local unit = Battle.Active(state, side)
	local moves = {}
	for _, entry in ipairs(Battle.Moves(state, side)) do
		if entry.ready then
			moves[entry.key] = entry
		end
	end
	local best = BestBench(state, side, enemy)
	local settled = state.count - (unit.cameIn or -10) > 2
	local held = unit.stunned or unit.feared
	if best and best.hp > best.maxHp * 0.5 and TypeEdge(best, enemy) > TypeEdge(unit, enemy)
		and (TypeEdge(unit, enemy) < 1 and settled or held) then
		return "w" .. best.slot
	end
	if moves.wait and best and best.hp > best.maxHp * 0.5 then
		return "w" .. best.slot -- disarmed or silenced with nothing else to do
	end
	if moves.heal and unit.hp < unit.maxHp * 0.45 then
		return "h"
	end
	if moves.mend then
		-- the whole bench if that heals more, else the most hurt card on it
		local restored, worst = 0, nil
		for _, other in ipairs(Battle.Bench(state, side)) do
			restored = restored + math.min(other.maxHp - other.hp, Battle.HealAmount(unit, true))
			if not worst or other.hp / other.maxHp < worst.hp / worst.maxHp then
				worst = other
			end
		end
		local mended = worst and math.min(worst.maxHp - worst.hp, Battle.HealAmount(unit)) or 0
		if math.max(restored, mended) >= Battle.HealAmount(unit) * 0.6 then
			return restored > mended and "b" or ("m" .. worst.slot)
		end
	end
	local attack = moves.attack and Battle.Damage(unit, enemy, "attack") or 0
	local spell = moves.spell and Battle.Damage(unit, enemy, "spell") or 0
	if math.max(attack, spell) >= enemy.hp then
		return spell >= attack and "s" or "a" -- the knockout
	end
	for _, key in ipairs({ "stun", "fear", "silence", "disarm", "poison", "slow" }) do
		if moves[key] and Useful(key, enemy) then
			return moves[key].move
		end
	end
	if moves.guard and unit.hp < unit.maxHp * 0.6 and state.count % 4 < 2 then
		return "g"
	end
	if spell > 0 and spell >= attack then
		return "s"
	elseif attack > 0 then
		return "a"
	end
	for _, entry in ipairs(Battle.Moves(state, side)) do
		if entry.ready and entry.key ~= "mend" then
			return entry.move
		end
	end
	return moves.restore and "b" or "z"
end
