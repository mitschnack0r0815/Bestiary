local _, ns = ...

-- Turn-based fights on a virtual clock (ARCHITECTURE.md 5.2, decided 2026-10-17). No rounds: all
-- cards are on the table from the start, each with its own clock. A card's turn comes again
-- after its real attack time (a mob that swings every 1.5 s gets more turns than one that swings
-- every 3 s); after a spell or heal, after its real cast time (at least 1.5 s, Cards.lua). The card whose time comes first
-- gets the next turn (ties: the side that didn't just act, then the lower slot). On its turn its
-- owner picks what it does and the target: Tanks and Warriors Attack or cast their Spell (every
-- SPELL_COOLDOWN seconds); Mages only cast (no cooldown), Healers only heal (no cooldown,
-- decided). A Healer with nobody to heal waits: it's off the clock until an ally gets hurt, then
-- its turn comes at once (decided). Tanks block: while a side has a living Tank,
-- attacks and spells must target one of its Tanks. The order in a squad doesn't matter. Fights
-- run ns.PACE times faster than real ones (each hit counts that many times, Cards.lua), so they
-- don't take hundreds of turns.
--
-- Deterministic: Fight.New(cardsA, cardsB, seed, twist) and the same moves give the same fight on
-- every client, so a duel only sends moves, and a game can be rebuilt from them after a reload.
-- A move is { action = "attack" | "spell" | "heal", side, slot } (the target); the card acting is
-- always state.actor. Times are kept in tenths of a second, so no client drifts.
local Fight = {}
ns.Fight = Fight

local MAX_TIME = 180 -- virtual seconds; then the side with more health left wins
local OPENING = 10 -- the first seconds, for twists (Fog, Ambush)
local SPELL_COOLDOWN = 10 -- seconds until a card that isn't a Mage or Healer can cast again
local FOG = 1.5 -- Fog twist: Warriors hit this much harder in the opening
local HEAL_FADE = 0.9 -- each heal of a Healer is 10% weaker than its previous one
local HEALER_LEADER = 1.2 -- a Healer leader: all heals +20%
local TANK_LEADER = 1.2 -- a Tank leader: Tank allies +20% armor
local MAGE_LEADER = 1.15 -- a Mage leader: Mage allies +15% spell damage
local WARRIOR_LEADER = 0.1 -- a Warrior leader: Warrior allies attack 10% faster
local SHIELD_WALL_SLOW = 0.1 -- Shield Wall twist: everyone attacks 10% slower
-- Abilities (Abilities.lua): the hooks for their effects
local GCD = 1.5 -- an ability takes this long (no cast)
local SLOWED = 1.3 -- a slowed card's turns come 30% later
local ENRAGE_BELOW, ENRAGE_DAMAGE = 0.3, 1.5 -- enraged below 30% health: 50% more damage
-- For the Info tab
ns.FIGHT_RULES = {
	maxTime = MAX_TIME, opening = OPENING, spellCooldown = SPELL_COOLDOWN,
	fog = FOG, healFade = HEAL_FADE, healerLeader = HEALER_LEADER,
}

-- Family bonuses (3.4): with 2 or 4 cards of a family in the squad, those cards get the bonus.
-- Numbers are placeholders for balancing. haste: attacks that much faster (a shorter attack
-- time), negative slower.
local FAMILY_BONUS = {
	Beast = { { haste = 0.1, text = "attack 10% faster" }, { haste = 0.2, text = "attack 20% faster" } },
	Humanoid = { { stats = 0.1, text = "+10% attack and health" }, { stats = 0.2, haste = 0.1, text = "+20% attack and health, attack 10% faster" } },
	Undead = { { rise = 0.2, text = "the first to die gets back up at 20% health" }, { rise = 0.4, text = "the first to die gets back up at 40% health" } },
	Demon = { { attack = 0.15, drain = 0.02, text = "+15% attack, lose 2% health each turn" }, { attack = 0.35, drain = 0.02, text = "+35% attack, lose 2% health each turn" } },
	Dragonkin = { { health = 0.15, text = "+15% health" }, { health = 0.3, text = "+30% health" } },
	Elemental = { { spell = 0.15, text = "+15% spell damage and heals" }, { spell = 0.35, text = "+35% spell damage and heals" } },
	Giant = { { health = 0.2, haste = -0.1, text = "+20% health, attack 10% slower" }, { health = 0.4, haste = -0.1, text = "+40% health, attack 10% slower" } },
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

-- The bonuses as text with family icons. long: with what each does (Squads tab), else short
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

local function Round(x)
	return math.floor(x + 0.5)
end

-- Seconds kept in tenths
local function Tenths(x)
	return Round(x * 10) / 10
end

local function Units(cards, side, twist)
	local units = {}
	local leader = ns.SquadLeader(cards) -- the named card, if any
	local bonuses = {}
	for _, bonus in ipairs(ns.FamilyBonuses(cards)) do
		bonuses[bonus.family] = FAMILY_BONUS[bonus.family][bonus.tier]
	end
	for slot, card in ipairs(cards) do
		local unit = {
			card = card, side = side, slot = slot,
			hp = card.health, maxHp = card.health,
			attack = card.attack, spell = card.spellPower, spellName = card.spell,
			castTime = card.castTime or ns.SPELL_TIME,
			armor = card.armor, level = card.level or card.power or 1,
			kind = card.type, leader = leader ~= nil and card == leader, readyAt = 0, heals = 0,
			abilities = card.abilities or {}, abilityReady = {}, -- ability key -> time it's ready again
		}
		local haste = 0
		if leader then
			if leader.type == "Tank" and unit.kind == "Tank" then
				unit.armor = Round(unit.armor * TANK_LEADER)
			elseif leader.type == "Mage" and unit.kind == "Mage" and unit.spell then
				unit.spell = Round(unit.spell * MAGE_LEADER)
			elseif leader.type == "Warrior" and unit.kind == "Warrior" then
				haste = haste + WARRIOR_LEADER
			elseif leader.type == "Healer" then
				unit.healBonus = HEALER_LEADER
			end
		end
		local bonus = bonuses[card.family]
		if bonus then
			local health = (bonus.health or 0) + (bonus.stats or 0)
			unit.maxHp = Round(unit.maxHp * (1 + health))
			unit.hp = unit.maxHp
			unit.attack = Round(unit.attack * (1 + (bonus.attack or 0) + (bonus.stats or 0)))
			if unit.spell then
				unit.spell = Round(unit.spell * (1 + (bonus.spell or 0)))
			end
			haste = haste + (bonus.haste or 0)
			unit.guard, unit.drain, unit.rise = bonus.guard, bonus.drain, bonus.rise
		end
		if twist == "consecrated" and card.family == "Undead" then
			unit.armor = 0
		elseif twist == "shieldwall" then
			unit.armor = unit.armor * 2
			haste = haste - SHIELD_WALL_SLOW
		end
		-- Its turn time: its attack time; casters and healers only cast, so their cast time
		local base = (unit.kind == "Mage" or unit.kind == "Healer") and unit.castTime or card.attackSpeed or ns.ATTACK_SPEED
		unit.interval = math.max(0.5, Tenths(base * (1 - haste)))
		unit.next = unit.interval -- its first turn comes after one turn time
		units[slot] = unit
	end
	return units
end

local function Alive(units)
	for _, unit in ipairs(units) do
		if unit.hp > 0 then
			return true
		end
	end
	return false
end

local function Event(state, event)
	event.time = state.time
	state.events[#state.events + 1] = event
end

local function HealthShare(units)
	local hp, max = 0, 0
	for _, unit in ipairs(units) do
		hp, max = hp + unit.hp, max + unit.maxHp
	end
	return max > 0 and hp / max or 0
end

local function End(state, winner, timeout)
	state.winner = winner
	state.actor = nil
	Event(state, { kind = "end", winner = winner, timeout = timeout })
end

-- Whose turn comes first: the earlier time; ties: the side that didn't just act (before the
-- first move: a coin flip by the seed), then the lower slot
local function First(state, a, b)
	if a.next ~= b.next then
		return a.next < b.next
	end
	if a.side ~= b.side then
		return a.side ~= state.lastSide
	end
	return a.slot < b.slot
end

-- Living cards in the order of their next turns
function Fight.Upcoming(state)
	local list = {}
	for _, units in ipairs(state.sides) do
		for _, unit in ipairs(units) do
			if unit.hp > 0 then
				list[#list + 1] = unit
			end
		end
	end
	table.sort(list, function(a, b)
		return First(state, a, b)
	end)
	return list
end

-- Waiting Healers of a side whose ally just got hurt: their turn comes now
local function Wake(state, side)
	for _, unit in ipairs(state.sides[side]) do
		if unit.waiting and unit.hp > 0 then
			for _, ally in ipairs(state.sides[side]) do
				if ally.hp > 0 and ally.hp < ally.maxHp then
					unit.waiting = nil
					unit.next = state.time
					break
				end
			end
		end
	end
end

-- The next turn: the clock jumps to the card whose time comes first
local Die

local function Advance(state)
	local unit = Fight.Upcoming(state)[1]
	if not unit then
		return
	end
	if unit.next > MAX_TIME then
		local a, b = HealthShare(state.sides[1]), HealthShare(state.sides[2])
		End(state, a > b and 1 or b > a and 2 or 0, true)
		return
	end
	state.time = unit.next
	state.actor = unit
	unit.feared = nil -- its fear is over: it's its turn
	if unit.poison then
		-- Poison: a tick at each of its turns while it lasts; it can kill
		if state.time > unit.poison.untilTime then
			unit.poison = nil
		else
			local damage = math.min(unit.hp, unit.poison.damage)
			unit.hp = unit.hp - damage
			Event(state, { kind = "tick", side = unit.side, slot = unit.slot, damage = damage, hp = unit.hp })
			Wake(state, unit.side)
			if unit.hp <= 0 then
				Die(state, unit)
				if not Alive(state.sides[1]) or not Alive(state.sides[2]) then
					End(state, Alive(state.sides[1]) and 1 or 2)
					return
				end
				if unit.hp <= 0 then
					state.actor = nil
					return Advance(state) -- it died before acting: the next one
				end
			end
		end
	end
	if unit.drain then
		-- Demon bonus: costs health every turn, but never kills
		local loss = math.min(unit.hp - 1, math.max(1, Round(unit.maxHp * unit.drain)))
		if loss > 0 then
			unit.hp = unit.hp - loss
			Event(state, { kind = "drain", side = unit.side, slot = unit.slot, damage = loss, hp = unit.hp })
			Wake(state, unit.side)
		end
	end
	Event(state, { kind = "turn", side = unit.side, slot = unit.slot })
	return unit
end

function Fight.New(cardsA, cardsB, seed, twist)
	local state = {
		seed = seed, twist = twist, time = 0, events = {}, moves = 0,
		sides = { Units(cardsA, 1, twist), Units(cardsB, 2, twist) }, risen = {},
		lastSide = (seed or 1) % 2 + 1, -- the first tie goes to the other side: a coin flip neither chose
	}
	Advance(state)
	return state
end

local function Opening(state)
	return state.time <= OPENING
end

-- What a card can do now: { key, name, amount (before armor), ready, magic, cooldown (seconds) }
function Fight.Actions(state, unit)
	unit = unit or state.actor
	local list = {}
	if not unit then
		return list
	end
	local enraged = Fight.Has(unit, "enrage") and unit.hp < unit.maxHp * ENRAGE_BELOW and ENRAGE_DAMAGE or 1
	local silenced = (unit.silencedUntil or 0) > state.time
	-- Casters only cast, healers only heal (decided)
	if unit.kind ~= "Mage" and unit.kind ~= "Healer" then
		local attack = unit.attack * enraged
		if unit.kind == "Warrior" and state.twist == "fog" and Opening(state) then
			attack = attack * FOG
		end
		list[#list + 1] = { key = "attack", name = "Attack", amount = Round(attack),
			ready = (unit.disarmedUntil or 0) <= state.time }
	end
	local wait = math.max(0, Tenths(unit.readyAt - state.time))
	if unit.kind == "Healer" then
		local amount = Round((unit.spell or unit.attack) * (unit.healBonus or 1) * HEAL_FADE ^ unit.heals)
		local canHeal = #Fight.Targets(state, unit, "heal") > 0
		list[#list + 1] = { key = "heal", name = unit.spellName or "Heal", amount = math.max(1, amount),
			ready = canHeal and not silenced }
	elseif unit.spell then
		list[#list + 1] = { key = "spell", name = unit.spellName or "Spell", amount = Round(unit.spell * enraged), magic = true,
			ready = wait == 0 and not silenced, cooldown = wait }
	end
	-- Its abilities that are actions of their own (not part of its spell, not passive)
	for _, ability in ipairs(unit.abilities) do
		local def = ns.ABILITIES[ability.key]
		if def and not def.passive and not ability.onSpell then
			local ready = Tenths(math.max(0, (unit.abilityReady[ability.key] or 0) - state.time))
			list[#list + 1] = { key = "ability:" .. ability.key, name = ability.spell or def.name, amount = 0,
				ability = ability, ready = ready == 0, cooldown = ready }
		end
	end
	-- Nothing it can do (nobody to heal, silenced, disarmed): its turn passes
	local any = false
	for _, action in ipairs(list) do
		any = any or action.ready
	end
	if not any then
		list[#list + 1] = { key = "wait", name = "Wait", amount = 0, ready = true }
	end
	return list
end

-- Whether a card has an ability (by key)
function Fight.Has(unit, key)
	for _, ability in ipairs(unit.abilities or {}) do
		if ability.key == key then
			return ability
		end
	end
end

function Fight.Action(state, key, unit)
	for _, action in ipairs(Fight.Actions(state, unit)) do
		if action.key == key then
			return action
		end
	end
end

-- Whom an action can target
function Fight.Targets(state, unit, key)
	unit = unit or state.actor
	local list = {}
	if not unit then
		return list
	end
	if key == "wait" then
		return { unit } -- itself
	elseif key == "heal" then
		for _, ally in ipairs(state.sides[unit.side]) do
			if ally.hp > 0 and ally.hp < ally.maxHp then
				list[#list + 1] = ally
			end
		end
		return list
	end
	local blocked = not (state.twist == "ambush" and Opening(state))
	local tanks = {}
	for _, enemy in ipairs(state.sides[3 - unit.side]) do
		if enemy.hp > 0 then
			list[#list + 1] = enemy
			if enemy.kind == "Tank" then
				tanks[#tanks + 1] = enemy
			end
		end
	end
	if blocked and #tanks > 0 then
		return tanks -- Tanks block
	end
	return list
end

function Fight.Legal(state, move)
	local unit = state.actor
	if not unit or state.winner or type(move) ~= "table" then
		return false
	end
	local action = Fight.Action(state, move.action, unit)
	if not action or not action.ready then
		return false
	end
	for _, target in ipairs(Fight.Targets(state, unit, move.action)) do
		if target.side == move.side and target.slot == move.slot then
			return true
		end
	end
	return false
end

-- Damage this action would do to that target (after armor and guard), heal amount for heals
function Fight.Estimate(state, unit, key, target)
	local action = Fight.Action(state, key, unit)
	if not action then
		return 0
	end
	if key == "wait" or action.ability then
		return 0 -- abilities do their effect, no damage
	elseif key == "heal" then
		return math.min(action.amount, target.maxHp - target.hp)
	end
	local damage = action.amount
	if not action.magic then
		damage = math.max(1, Round(damage * (1 - ns.ArmorReduction(target.armor, unit.level))))
	end
	if target.guard then
		damage = math.max(1, Round(damage * (1 - target.guard)))
	end
	return math.min(damage, target.hp)
end

function Die(state, target)
	Event(state, { kind = "death", side = target.side, slot = target.slot })
	if target.rise and not state.risen[target.side] then
		state.risen[target.side] = true
		target.hp = math.max(1, Round(target.maxHp * target.rise))
		Event(state, { kind = "rise", side = target.side, slot = target.slot, hp = target.hp })
	end
end

-- An ability's effect on its target: the hooks (decided). Durations are the mob's real ones.
local function Effect(state, unit, target, ability)
	local key = ability.key
	local seconds = ability.duration or (ns.ABILITIES[key] and ns.ABILITIES[key].duration) or 3
	if target.hp <= 0 then
		return
	end
	if key == "stun" then
		target.next = Tenths(target.next + seconds) -- its next turn comes later
		target.stunnedUntil = Tenths(state.time + seconds) -- for showing it
	elseif key == "fear" then
		if not target.feared then
			target.fearedFrom = target.next -- damage breaks it: back to this
		end
		target.feared = true
		target.next = Tenths(target.next + seconds)
	elseif key == "silence" then
		target.silencedUntil = Tenths(state.time + seconds) -- no spells or heals
	elseif key == "disarm" then
		target.disarmedUntil = Tenths(state.time + seconds) -- no attacks
	elseif key == "slow" then
		if (target.slowedUntil or 0) <= state.time then
			target.next = Tenths(state.time + (target.next - state.time) * SLOWED)
		end
		target.slowedUntil = Tenths(state.time + seconds) -- its turns come later while it lasts
	elseif key == "poison" then
		target.poison = { untilTime = Tenths(state.time + seconds), damage = math.max(1, Round(unit.attack * ns.ABILITIES.poison.share)) }
	else
		return
	end
	Event(state, { kind = "effect", effect = key, side = unit.side, slot = unit.slot, targetSide = target.side,
		targetSlot = target.slot, seconds = seconds })
end

-- Plays a move of the card whose turn it is. Returns false if it isn't legal.
function Fight.Apply(state, move)
	if not Fight.Legal(state, move) then
		return false
	end
	local unit = state.actor
	local target = state.sides[move.side][move.slot]
	local amount = Fight.Estimate(state, unit, move.action, target)
	state.moves = state.moves + 1
	local action = Fight.Action(state, move.action, unit)
	if move.action == "wait" then
		Event(state, { kind = "wait", side = unit.side, slot = unit.slot })
	elseif action.ability then
		Effect(state, unit, target, action.ability)
		unit.abilityReady[action.ability.key] = Tenths(state.time + (ns.ABILITIES[action.ability.key].cooldown or 15))
	elseif move.action == "heal" then
		target.hp = target.hp + amount
		unit.heals = unit.heals + 1
		Event(state, { kind = "heal", side = unit.side, slot = unit.slot, targetSide = target.side,
			targetSlot = target.slot, amount = amount, hp = target.hp, action = "heal" })
	else
		target.hp = target.hp - amount
		Event(state, { kind = "hit", side = unit.side, slot = unit.slot, targetSide = target.side,
			targetSlot = target.slot, damage = amount, hp = target.hp, action = move.action,
			magic = move.action == "spell" })
		if target.feared and amount > 0 then
			-- damage breaks fear
			target.feared = nil
			target.next = math.max(state.time, target.fearedFrom or target.next)
			Event(state, { kind = "unfeared", side = target.side, slot = target.slot })
		end
		if target.hp <= 0 then
			target.hp = 0
			Die(state, target)
		elseif move.action == "spell" then
			-- effects that come with its spell (Frostbolt's slow)
			for _, ability in ipairs(unit.abilities) do
				if ability.onSpell and not ns.ABILITIES[ability.key].passive then
					Effect(state, unit, target, ability)
				end
			end
		end
		Wake(state, target.side)
	end
	-- Its next turn: after its attack time, the cast of a spell or heal, or an ability's moment;
	-- slowed: 30% later. A Healer with nobody to heal is off the clock (past the end) until an
	-- ally gets hurt; any other card that can't act waits a moment.
	local slow = (unit.slowedUntil or 0) > state.time and SLOWED or 1
	if move.action == "wait" then
		if unit.kind == "Healer" and #Fight.Targets(state, unit, "heal") == 0 then
			unit.waiting = true
			unit.next = MAX_TIME + 1
		else
			unit.next = Tenths(state.time + GCD * slow)
		end
	elseif action.ability then
		unit.next = Tenths(state.time + GCD * slow)
	elseif move.action == "attack" then
		unit.next = Tenths(state.time + unit.interval * slow)
	else
		unit.next = Tenths(state.time + unit.castTime * slow)
		-- A Mage's spells and a Healer's heals are what they do: no cooldown (decided). Other
		-- cards' spells have one.
		if unit.kind ~= "Mage" and unit.kind ~= "Healer" then
			unit.readyAt = Tenths(state.time + SPELL_COOLDOWN)
		end
	end
	state.lastSide = unit.side
	if not Alive(state.sides[1]) or not Alive(state.sides[2]) then
		End(state, Alive(state.sides[1]) and 1 or 2)
		return true
	end
	state.actor = nil
	Advance(state)
	return true
end

-- Moves on the wire: action letter, target side and slot ("a2.3")
local ACTION_CODE = { attack = "a", spell = "s", heal = "h", wait = "w" }
local ACTION_OF = { a = "attack", s = "spell", h = "heal", w = "wait" }

-- abilities: their code in capitals ("S2.3": stun the card in slot 3 of side 2)
function Fight.Encode(move)
	local code = ACTION_CODE[move.action]
	local ability = move.action:match("^ability:(.+)$")
	if ability and ns.ABILITIES[ability] then
		code = ns.ABILITIES[ability].code:upper()
	end
	return ("%s%d.%d"):format(code or "a", move.side, move.slot)
end

function Fight.Decode(text)
	local code, side, slot = (text or ""):match("^(%a)(%d)%.(%d+)$")
	if not code then
		return nil
	end
	local action = ACTION_OF[code]
	if not action and code:upper() == code then
		local key = ns.ABILITY_BY_CODE[code:lower()]
		action = key and ("ability:" .. key)
	end
	if not action then
		return nil
	end
	return { action = action, side = tonumber(side), slot = tonumber(slot) }
end

-- A fight from its start and moves (as encoded); stops at the first move that isn't legal
function Fight.Replay(cardsA, cardsB, seed, twist, moves)
	local state = Fight.New(cardsA, cardsB, seed, twist)
	for i, text in ipairs(moves or {}) do
		if not Fight.Apply(state, Fight.Decode(text)) then
			return state, i
		end
	end
	return state
end

-- Whether an ability's effect is already on a target (no point casting it again)
local function Affected(state, target, key)
	if key == "silence" then
		return (target.silencedUntil or 0) > state.time
	elseif key == "disarm" then
		return (target.disarmedUntil or 0) > state.time
	elseif key == "slow" then
		return (target.slowedUntil or 0) > state.time
	elseif key == "poison" then
		return target.poison ~= nil and target.poison.untilTime > state.time
	elseif key == "fear" then
		return target.feared == true
	end
	return false
end

-- The sparring partner's move (simple, decided): a Healer heals the ally with the lowest health
-- share (or waits); the others use a ready ability where it hurts most (silence casters and
-- healers, disarm hitters, poison the toughest, stun or fear the most dangerous), else the
-- strongest action at a target it can kill (the most dangerous one), else at the weakest
function Fight.AI(state)
	local unit = state.actor
	if not unit then
		return
	end
	local actions = Fight.Actions(state, unit)
	local heal = Fight.Action(state, "heal", unit)
	if heal and heal.ready then
		local best
		for _, ally in ipairs(Fight.Targets(state, unit, "heal")) do
			if not best or ally.hp / ally.maxHp < best.hp / best.maxHp then
				best = ally
			end
		end
		if best then
			return { action = "heal", side = best.side, slot = best.slot }
		end
	end
	for _, action in ipairs(actions) do
		if action.ability and action.ready then
			local key, best, bestValue = action.ability.key, nil, 0
			for _, target in ipairs(Fight.Targets(state, unit, action.key)) do
				if not Affected(state, target, key) then
					local caster = target.kind == "Mage" or target.kind == "Healer"
					local danger = math.max(target.attack or 0, target.spell or 0)
					local value = danger
					if key == "silence" then
						value = caster and danger or 0
					elseif key == "disarm" then
						value = caster and 0 or danger
					elseif key == "poison" then
						value = target.hp
					end
					if value > bestValue then
						best, bestValue = target, value
					end
				end
			end
			if best then
				return { action = action.key, side = best.side, slot = best.slot }
			end
		end
	end
	local choice, score
	for _, action in ipairs(actions) do
		if action.ready and (action.key == "attack" or action.key == "spell") then
			for _, target in ipairs(Fight.Targets(state, unit, action.key)) do
				local damage = Fight.Estimate(state, unit, action.key, target)
				local value = damage
				if damage >= target.hp then
					value = value + 10000 + (target.attack or 0) -- a kill, the most dangerous first
				else
					value = value + (target.maxHp - target.hp) * 0.1 -- finish what's hurt
				end
				if not score or value > score then
					choice, score = { action = action.key, side = target.side, slot = target.slot }, value
				end
			end
		end
	end
	if choice then
		return choice
	end
	-- nothing good: whatever it still can do (waiting is only allowed when nothing is left)
	for _, action in ipairs(actions) do
		local target = action.ready and Fight.Targets(state, unit, action.key)[1]
		if target then
			return { action = action.key, side = target.side, slot = target.slot }
		end
	end
	return { action = "wait", side = unit.side, slot = unit.slot }
end
