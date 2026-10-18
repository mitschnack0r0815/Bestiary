local addonName, ns = ...

-- Battle teams (ARCHITECTURE.md 5.5): three teams of up to 3 cards (Battle.MAX_TEAM) for Pokémon-style battles,
-- kept apart from the squads (BestiaryChar.teams, per character, card ids like squads). Only
-- the team size limits them (decided: no power cap and no leaders in battles). Battles give cards
-- XP (no stamina in this mode).
ns.TEAM_COUNT = 3

-- Battle XP (decided): every card that was on the field gets XP_FOUGHT, XP_KO more per card it
-- knocked out and XP_WIN more if its side won; XP_PER_LEVEL makes a level (up to the card's
-- level cap, Cards.lua)
ns.XP_FOUGHT = 20
ns.XP_KO = 15
ns.XP_WIN = 15
ns.XP_PER_LEVEL = 100

local function NewTeams()
	local teams = {}
	for i = 1, ns.TEAM_COUNT do
		teams[i] = { name = "Team " .. i, cards = {} }
	end
	return teams
end

local events = CreateFrame("Frame")
events:RegisterEvent("ADDON_LOADED")
events:SetScript("OnEvent", function(_, _, name)
	if name ~= addonName then
		return
	end
	BestiaryChar.teams = BestiaryChar.teams or NewTeams()
	ns.teams = BestiaryChar.teams
	events:UnregisterEvent("ADDON_LOADED")
end)

function ns.Teams()
	if not ns.teams and BestiaryChar then
		BestiaryChar.teams = BestiaryChar.teams or NewTeams()
		ns.teams = BestiaryChar.teams
	end
	return ns.teams or {}
end

-- A team's cards as views; cards you no longer have drop out (same as squads)
function ns.TeamCards(team)
	for i = #team.cards, ns.Battle.MAX_TEAM + 1, -1 do
		team.cards[i] = nil -- teams from when they held more
	end
	return ns.SquadCards(team)
end

-- The rules for a team: { ok, text } like the squad checks
function ns.TeamChecks(team)
	local cards = ns.TeamCards(team)
	local checks = {}
	local function Check(ok, text)
		checks[#checks + 1] = { ok = ok, text = text }
	end
	Check(#cards >= 1 and #cards <= ns.Battle.MAX_TEAM, #cards == 0 and "No cards yet"
		or #cards > ns.Battle.MAX_TEAM and ("%d cards: at most %d, take some out"):format(#cards, ns.Battle.MAX_TEAM)
		or ("%d of %d cards"):format(#cards, ns.Battle.MAX_TEAM))
	return checks
end

function ns.TeamReady(team)
	for _, check in ipairs(ns.TeamChecks(team)) do
		if not check.ok then
			return false
		end
	end
	return true
end

-- Whether a team from the other side keeps the rules (size, copies, stars, levels; no cap)
function ns.ValidTeam(cards)
	if not cards or #cards < 1 or #cards > ns.Battle.MAX_TEAM then
		return false, "team size"
	end
	local count = {}
	for _, card in ipairs(cards) do
		local key = card.npcId or card.name
		count[key] = (count[key] or 0) + 1
		if count[key] > (ns.CanHaveCopies(card) and ns.MAX_COPIES or 1) then
			return false, "too many copies of " .. card.name
		end
		if card.stars < 0 or card.stars > ns.MAX_STARS then
			return false, "stars"
		end
		if card.level < 1 or card.level > ns.MAX_LEVEL then
			return false, "level"
		end
	end
	return true
end

-- XP ----------------------------------------------------------------------------------------------

-- XP of a saved card toward its next level, and how much it needs
function ns.CardXp(card)
	return card.xp or 0, ns.XP_PER_LEVEL
end

-- A battle is over: our cards that fought get XP. units: our side of the battle; won: true if
-- we won. Copies of a card share it (counted once, the best of them). Returns a list of
-- { name, xp, level (if it went up) }.
function ns.GiveBattleXp(units, won)
	local best, order = {}, {}
	for _, unit in ipairs(units) do
		local card = unit.card.npcId and BestiaryChar.cards[unit.card.npcId]
		if card and not card.player and unit.fought then
			local xp = ns.XP_FOUGHT + ns.XP_KO * (unit.kos or 0) + (won and ns.XP_WIN or 0)
			if not best[card] then
				order[#order + 1] = card
			end
			best[card] = math.max(best[card] or 0, xp)
		end
	end
	local results = {}
	for _, card in ipairs(order) do
		local result = { name = card.name, xp = best[card] }
		if ns.CardLevel(card) < ns.LevelCap(card) then
			card.xp = (card.xp or 0) + best[card]
			while card.xp >= ns.XP_PER_LEVEL and ns.CardLevel(card) < ns.LevelCap(card) do
				card.xp = card.xp - ns.XP_PER_LEVEL
				card.level = card.level + 1
				result.level = card.level
			end
			if ns.CardLevel(card) >= ns.LevelCap(card) then
				card.xp = 0
			end
		else
			result.capped = true
		end
		results[#results + 1] = result
	end
	return results
end

-- Sparring partner ------------------------------------------------------------------------------

-- Its team for a battle (seed: the battle's number): one of its sparring squads cut to 5 cards,
-- about as strong as your strongest team (there's no cap, it just plays fair)
function ns.SparringTeam(seed)
	local target = 0
	for _, team in ipairs(ns.Teams()) do
		target = math.max(target, ns.Power(ns.TeamCards(team)))
	end
	target = target > 0 and target or ns.POWER_CAP / 2
	local squads = ns.SparringSquads(seed)
	local squad = squads[seed % #squads + 1]
	local cards, power = {}, 0
	for _, id in ipairs(squad.cards) do
		local view = ns.CardById(id)
		if view and #cards < ns.Battle.MAX_TEAM and (#cards < 2 or power + view.power <= target) then
			cards[#cards + 1] = view
			power = power + view.power
		end
	end
	return cards, squad.style or squad.name
end
