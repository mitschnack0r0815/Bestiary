local _, ns = ...

-- Stats for the Stats tab, saved per character in BestiaryChar.stats:
--   duels: wins, losses, draws, streaks, by squad and by twist
--   cards: per card of yours (damage dealt and taken, healing, kills, deaths, duels, best of duel)
--   foes: per opponent card (damage dealt to you, your cards it killed)
--   hunting: kills that counted, cards and stars dropped
-- Everything about the collection itself is computed live from the cards.

local function Stats()
	BestiaryChar.stats = BestiaryChar.stats or {}
	local stats = BestiaryChar.stats
	stats.duels = stats.duels or { wins = 0, losses = 0, draws = 0, streak = 0, bestStreak = 0, squads = {}, twists = {} }
	stats.cards = stats.cards or {}
	stats.foes = stats.foes or {}
	stats.hunting = stats.hunting or { kills = 0, drops = 0, newCards = 0, stars = 0 }
	return stats
end
ns.Stats = Stats

-- A card's key: real cards by NPC id, made-up ones by name
function ns.StatKey(card)
	return card.npcId and ("npc" .. card.npcId) or ("mock:" .. card.name)
end

local function Entry(list, card)
	local key = ns.StatKey(card)
	local entry = list[key]
	if not entry then
		entry = { name = card.name, damage = 0, taken = 0, healing = 0, kills = 0, deaths = 0, duels = 0, best = 0 }
		list[key] = entry
	end
	entry.name, entry.type, entry.classification, entry.family = card.name, card.type, card.classification, card.family
	entry.npcId = card.npcId
	return entry
end

local function Result(record, winner)
	record.wins = (record.wins or 0) + (winner == 1 and 1 or 0)
	record.losses = (record.losses or 0) + (winner == 2 and 1 or 0)
	record.draws = (record.draws or 0) + (winner == 0 and 1 or 0)
end

-- A finished duel: events and sides from ns.Fight; you are side 1
function ns.RecordDuel(events, winner, sides, squadName, twist)
	local stats = Stats()
	local duels = stats.duels
	Result(duels, winner)
	if winner == 1 then
		duels.streak = math.max(0, duels.streak) + 1
		duels.bestStreak = math.max(duels.bestStreak, duels.streak)
	elseif winner == 2 then
		duels.streak = math.min(0, duels.streak) - 1
	else
		duels.streak = 0
	end
	duels.squads[squadName] = duels.squads[squadName] or {}
	Result(duels.squads[squadName], winner)
	if twist then
		duels.twists[twist] = duels.twists[twist] or {}
		Result(duels.twists[twist], winner)
	end

	-- Per card, from the events
	local this = {} -- unit -> { damage, healing } in this duel
	local function Unit(side, slot)
		return sides[side][slot]
	end
	local function Mine(unit)
		return unit.side == 1 and Entry(stats.cards, unit.card) or nil
	end
	local lastHitter = {}
	for _, event in ipairs(events) do
		if event.kind == "hit" then
			local attacker, target = Unit(event.side, event.slot), Unit(event.targetSide, event.targetSlot)
			this[attacker] = this[attacker] or { damage = 0, healing = 0 }
			this[attacker].damage = this[attacker].damage + event.damage
			lastHitter[target] = attacker
			local mine = Mine(attacker)
			if mine then
				mine.damage = mine.damage + event.damage
			else
				local foe = Entry(stats.foes, attacker.card)
				foe.damage = foe.damage + event.damage
			end
			local hurt = Mine(target)
			if hurt then
				hurt.taken = hurt.taken + event.damage
			end
		elseif event.kind == "heal" then
			local healer = Unit(event.side, event.slot)
			this[healer] = this[healer] or { damage = 0, healing = 0 }
			this[healer].healing = this[healer].healing + event.amount
			local mine = Mine(healer)
			if mine then
				mine.healing = mine.healing + event.amount
			end
		elseif event.kind == "death" then
			local dead = Unit(event.side, event.slot)
			local killer = lastHitter[dead]
			local mine = Mine(dead)
			if mine then
				mine.deaths = mine.deaths + 1
			end
			if killer then
				local yours = Mine(killer)
				if yours then
					yours.kills = yours.kills + 1
				else
					local foe = Entry(stats.foes, killer.card)
					foe.kills = foe.kills + 1
				end
			end
		end
	end

	-- Duels fought, and the best card of the duel (most damage and healing) on your side
	local best, bestScore = nil, -1
	for _, unit in ipairs(sides[1]) do
		local mine = Entry(stats.cards, unit.card)
		mine.duels = mine.duels + 1
		local done = this[unit]
		local score = done and (done.damage + done.healing) or 0
		if score > bestScore then
			best, bestScore = mine, score
		end
	end
	if best then
		best.best = best.best + 1
	end
	if ns.Refresh then
		ns.Refresh()
	end
end

-- Hunting
function ns.RecordKill()
	local hunting = Stats().hunting
	hunting.kills = hunting.kills + 1
end

function ns.RecordDrop(result)
	local hunting = Stats().hunting
	hunting.drops = hunting.drops + 1
	if result == "new" then
		hunting.newCards = hunting.newCards + 1
	else
		hunting.stars = hunting.stars + 1
	end
end
