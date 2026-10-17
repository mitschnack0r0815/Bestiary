local _, ns = ...

-- Builds cards from what the tracker learned about a mob (ARCHITECTURE.md 4.0) and rolls drops
-- on kills (3.3, 4.1, 4.2). Saved cards (BestiaryChar.cards[npcId]) only keep what came from
-- the game; stats are computed from them by the formula, so it can change while balancing.

-- The combat type from what was seen of the mob (the combat log is closed to addons, so no
-- damage numbers): heal casts, mana and casting, its NPC class, attack speed, else its family
-- NPC classes only say how a mob uses resources: Warrior (rage, no mana), Paladin (mana, often
-- a caster beast or hybrid), Mage (mana caster). So only the clear ones decide here; Paladin
-- just means mana.
local CLASS_TYPES = { MAGE = "Mage", WARLOCK = "Mage", PRIEST = "Mage", ROGUE = "Warrior", HUNTER = "Warrior" }
local MANA_CLASSES = { PALADIN = true, MAGE = true, WARLOCK = true, PRIEST = true, SHAMAN = true, DRUID = true }
local CASTS_PER_10S = 1 -- casting at least this often makes a caster even without mana

-- Sturdiness: a mob's maximum health against what's normal for its level and rarity. Normal is
-- the median of mobs you've seen of the same rarity within 2 levels (with at least
-- PEERS_NEEDED of them), else typical Classic health by level (BASE_HEALTH, for normal mobs,
-- times RARITY_HEALTH). Returns the ratio and what it was compared with, nil if unknown.
local PEERS_NEEDED = 5
local BASE_HEALTH = { [1] = 42, [5] = 110, [10] = 200, [15] = 330, [20] = 480, [25] = 690, [30] = 1000,
	[35] = 1340, [40] = 1660, [45] = 2000, [50] = 2400, [55] = 2800, [60] = 3200, [63] = 3450 }
local RARITY_HEALTH = { normal = 1, rare = 1.4, elite = 3, rareelite = 3.5 }

local function TypicalHealth(level)
	local below, above
	for at in pairs(BASE_HEALTH) do
		if at <= level and (not below or at > below) then
			below = at
		end
		if at >= level and (not above or at < above) then
			above = at
		end
	end
	below, above = below or above, above or below
	if below == above then
		return BASE_HEALTH[below]
	end
	local part = (level - below) / (above - below)
	return BASE_HEALTH[below] + (BASE_HEALTH[above] - BASE_HEALTH[below]) * part
end

function ns.Sturdiness(npcId, info)
	if not info or not info.maxHealth or not info.level or info.level < 1 or not RARITY_HEALTH[info.classification] then
		return nil -- unknown, skull level, or a boss (one of a kind)
	end
	local peers = {}
	for otherId, other in pairs(BestiaryAccount.mobs) do
		if otherId ~= npcId and other.maxHealth and other.level and other.classification == info.classification
			and math.abs(other.level - info.level) <= 2 then
			peers[#peers + 1] = other.maxHealth * (TypicalHealth(info.level) / TypicalHealth(other.level))
		end
	end
	if #peers >= PEERS_NEEDED then
		table.sort(peers)
		local median = peers[math.floor((#peers + 1) / 2)]
		return info.maxHealth / median, ("%d similar mobs"):format(#peers)
	end
	return info.maxHealth / (TypicalHealth(info.level) * RARITY_HEALTH[info.classification]), "typical health"
end

-- The combat type from what was seen of the mob (the combat log is closed to addons, so no
-- damage numbers): heal casts, mana and casting, its NPC class; then Tank or Warrior from its
-- attack speed and its sturdiness (health against similar mobs) added up; else its family.
local function TypeFrom(entry, family, info, npcId)
	local mana = entry.mana or MANA_CLASSES[entry.class or ""]
	local rate = entry.seconds > 0 and entry.casts / entry.seconds * 10 or 0
	if entry.heals >= 2 and entry.heals >= entry.casts * 0.35 then
		return "Healer", ("%d of its %d casts heal"):format(entry.heals, entry.casts)
	elseif mana and entry.casts >= 2 then
		return "Mage", ("uses mana and cast %d spells"):format(entry.casts)
	elseif entry.casts >= 3 and rate >= CASTS_PER_10S then
		return "Mage", ("casts a lot: %d spells, %.1f per 10 s"):format(entry.casts, rate)
	elseif (entry.magicHits or 0) > 3 and entry.magicHits >= (entry.physicalHits or 0) * 0.5 then
		-- instant casts (shocks...) don't show as casts, but as spell damage on you
		return "Mage", ("hit you with %d spells (and %d melee hits)"):format(entry.magicHits, entry.physicalHits or 0)
	elseif CLASS_TYPES[entry.class or ""] then
		return CLASS_TYPES[entry.class], "its class is " .. entry.class:lower()
	end
	local tank, assassin, reasons = 0, 0, {}
	if entry.attackSpeed and entry.attackSpeed < 1.8 then
		assassin = assassin + 1
		reasons[#reasons + 1] = ("fast attacks (%.1f s)"):format(entry.attackSpeed)
	elseif entry.attackSpeed and entry.attackSpeed > 2.6 then
		tank = tank + 1
		reasons[#reasons + 1] = ("slow, heavy attacks (%.1f s)"):format(entry.attackSpeed)
	end
	if (entry.stealth or 0) > 0 then
		assassin = assassin + 1
		reasons[#reasons + 1] = "uses stealth"
	end
	if (entry.tankBuffs or 0) > 0 then
		tank = tank + 1
		reasons[#reasons + 1] = "hardens itself"
	end
	if (entry.poisons or 0) > 0 then
		assassin = assassin + 1
		reasons[#reasons + 1] = entry.poisons == 1 and "poisoned you" or ("poisoned you %d times"):format(entry.poisons)
	end
	local ratio, against = ns.Sturdiness(npcId, info)
	if ratio then
		local sturdy = ratio >= 1.6 and 2 or ratio >= 1.25 and 1 or 0
		local frail = ratio <= 0.6 and 2 or ratio <= 0.8 and 1 or 0
		tank, assassin = tank + sturdy, assassin + frail
		if sturdy > 0 or frail > 0 then
			reasons[#reasons + 1] = ("%s: %d%% health of %s"):format(sturdy > 0 and "sturdy" or "frail", ratio * 100, against)
		end
	end
	if tank ~= assassin then
		return tank > assassin and "Tank" or "Warrior", table.concat(reasons, ", ")
	end
	local lean = { Giant = "Tank", Mechanical = "Tank", Undead = "Tank", Beast = "Warrior",
		Humanoid = "Warrior", Demon = "Mage", Dragonkin = "Mage", Elemental = "Mage" }
	local why
	if #reasons > 0 then
		why = table.concat(reasons, " but ") .. ", even, so by its family"
	else
		why = (ratio and ("%d%% health of %s, "):format(ratio * 100, against) or "") .. "nothing telling, so by its family"
	end
	return lean[family] or "Tank", why .. " (" .. tostring(family) .. ")"
end
ns.TypeFrom = TypeFrom

-- The spell it used most
local function SignatureSpell(entry)
	local best, count = nil, 0
	for spell, n in pairs(entry.spells) do
		if n > count then
			best, count = spell, n
		end
	end
	return best
end

-- What a card is made of; the same fields a saved card has
function ns.BuildCard(npcId)
	local entry = ns.Studied(npcId) or ns.EmptyStudy()
	local info = ns.MobInfo(npcId)
	if not info or not info.family then
		return
	end
	local spell = SignatureSpell(entry)
	local card = {
		npcId = npcId,
		name = info.name or entry.name,
		classification = info.classification,
		family = info.family,
		type = TypeFrom(entry, info.family, info, npcId),
		spell = spell,
		art = spell and (ns.SpellIcon(entry.spellIds[spell], spell) or (entry.spellIcons or {})[spell]) or nil,
		zone = GetRealZoneText and GetRealZoneText() or "",
		stars = 0,
	}
	return ns.CardView(card)
end

-- Card levels (3.2, decided 2026-10-17): a card starts at the level of the mob it dropped
-- from, and gains a level every GAMES_PER_LEVEL duels (won or lost, sparring too), never more
-- than LEVELS_ABOVE_PLAYER above your own level, up to 60 (named cards: 63). Your own card is
-- always your level.
function ns.LevelCap(card)
	local top = (ns.IsNamed(card) or card.classification == "worldboss") and ns.MAX_LEVEL or ns.MAX_NORMAL_LEVEL
	return math.min(top, (UnitLevel("player") or 1) + ns.LEVELS_ABOVE_PLAYER)
end

-- The level a mob drops its card at: its own, skull level counts as 63
function ns.DropLevel(npcId, classification)
	local info = BestiaryAccount.mobs[npcId]
	local level = info and info.level
	if not level or level < 1 then
		level = ns.MAX_LEVEL
	end
	local named = ns.NAMED[classification or (info and info.classification) or "normal"]
	return math.min(level, named and ns.MAX_LEVEL or ns.MAX_NORMAL_LEVEL)
end

function ns.CardLevel(card)
	if card.player then
		return UnitLevel("player") or 1
	end
	if not card.level and card.npcId and not card.remote then
		card.level = ns.DropLevel(card.npcId, card.classification) -- cards from before levels
	end
	return card.level or 1
end

-- A duel is over: each card in it counts a game (copies once). Returns the
-- cards that went up a level.
function ns.CardsPlayed(views)
	local done, up = {}, {}
	for _, view in ipairs(views) do
		local card = view.npcId and not done[view.npcId] and ns.SavedCard(view)
		if card and not card.player then
			done[view.npcId] = true
			if ns.CardLevel(card) < ns.LevelCap(card) then
				card.games = (card.games or 0) + 1
				if card.games >= ns.GAMES_PER_LEVEL then
					card.games = 0
					card.level = card.level + 1
					up[#up + 1] = card
				end
			end
		end
	end
	return up
end

-- How this mob type compares to the typical mob of its level and NPC class (LevelStats.lua):
-- measured factors (medians), else a guess by rarity. Returns health, melee, spell factors
-- (name -> factor) and whether health and melee were measured.
function ns.MobFactors(npcId, classification)
	local guess = ns.GUESSED_FACTORS[classification] or ns.GUESSED_FACTORS.normal
	local measured = npcId and ns.Measured and ns.Measured(npcId)
	local health = measured and ns.Median(measured.health)
	local melee = measured and ns.Median(measured.melee)
	local spells = {}
	for name, list in pairs(measured and measured.spells or {}) do
		spells[name] = ns.Median(list)
	end
	return health or guess.health, melee or guess.damage, spells, health ~= nil, melee ~= nil
end

-- Spells (decided 2026-10-17) ----------------------------------------------------------------
-- What the game's spell data says about a mob's spell (static data, not secret): its cast time,
-- and the damage in its description ("causes 18 to 20 Frost damage"). Saved account wide per mob
-- (info.spellData[name] = { id, cast = seconds, low, high }; low = false: read, no numbers in
-- it), filled once the game has loaded the spell. A spell's strength: measured on you, else from
-- its description, else SPELL_FALLBACK times the card's melee hit.
ns.SPELL_FALLBACK = 2
ns.GCD = 1.5 -- even an instant spell takes this long
ns.SPELL_TIME = 3 -- the cast when the game doesn't tell

local RANGE_PATTERNS = { "(%d+) to (%d+)", "(%d+) bis (%d+)" }
local SINGLE_PATTERNS = { "(%d+) %a+ damage", "(%d+) damage", "(%d+) %a*[Ss]chaden" }

-- Damage numbers in a spell description: low, high (nil if none)
function ns.ParseSpellDamage(text)
	if type(text) ~= "string" then
		return nil
	end
	for _, pattern in ipairs(RANGE_PATTERNS) do
		local low, high = text:match(pattern)
		if low then
			return tonumber(low), tonumber(high)
		end
	end
	for _, pattern in ipairs(SINGLE_PATTERNS) do
		local value = text:match(pattern)
		if value then
			return tonumber(value), tonumber(value)
		end
	end
end

local function ReadSpell(data)
	if not (C_Spell and data.id) then
		return
	end
	if data.cast == nil and C_Spell.GetSpellInfo then
		local ok, spellInfo = pcall(C_Spell.GetSpellInfo, data.id)
		local cast = ok and type(spellInfo) == "table" and ns.Clean(spellInfo.castTime)
		if type(cast) == "number" then
			data.cast = cast / 1000
		end
	end
	if data.low == nil and C_Spell.GetSpellDescription then
		local ok, text = pcall(C_Spell.GetSpellDescription, data.id)
		text = ok and ns.Clean(text)
		if type(text) == "string" and text ~= "" then
			local low, high = ns.ParseSpellDamage(text)
			data.low, data.high = low or false, high
		elseif C_Spell.RequestLoadSpellData then
			pcall(C_Spell.RequestLoadSpellData, data.id) -- not loaded yet: read again next time
		end
	end
end

-- A mob's spell got known (Tracker.lua, from the damage meter)
function ns.LearnSpell(npcId, name, id)
	local info = BestiaryAccount.mobs[npcId]
	if not info or not name or not id or id <= 0 then
		return
	end
	info.spellData = info.spellData or {}
	local data = info.spellData[name] or {}
	data.id = id
	info.spellData[name] = data
	ReadSpell(data)
end

function ns.SpellData(npcId, name)
	local info = npcId and BestiaryAccount.mobs[npcId]
	if not info or not name then
		return nil
	end
	local data = info.spellData and info.spellData[name]
	if not data then
		-- learned before spell data was kept: its id from the study
		local entry = BestiaryChar.study[npcId]
		local id = entry and entry.spellIds and entry.spellIds[name]
		if id and id > 0 then
			ns.LearnSpell(npcId, name, id)
			data = info.spellData[name]
		end
	end
	if data and (data.cast == nil or data.low == nil) then
		ReadSpell(data)
	end
	return data
end

-- A card with its stats (3.2 and 5.2): the real mob at the card's level. Health and melee hits
-- are the typical mob of that level and NPC class times this mob's factors, its attack time is
-- the mob's own. Fights run PACE times faster than real ones: real mobs take long to kill each
-- other (two level 60 mobs: over a minute), so every hit and spell counts PACE times (decided),
-- keeping the proportions. Stars add STAR_BONUS each.
ns.PACE = 4

function ns.CardView(card)
	local view = {}
	for key, value in pairs(card) do
		view[key] = value
	end
	local info = card.npcId and BestiaryAccount.mobs[card.npcId]
	local class = card.class or (info and info.class)
	local attackSpeed = card.attackSpeed or (info and info.attackSpeed) or ns.ATTACK_SPEED
	attackSpeed = math.max(0.5, math.floor(attackSpeed * 10 + 0.5) / 10) -- tenths, like the fight clock
	local level = ns.CardLevel(card)
	local healthFactor, meleeFactor, spells = 1, 1, {}
	if not card.player then
		healthFactor, meleeFactor, spells = ns.MobFactors(card.npcId, card.classification)
	end
	local stars = 1 + ns.STAR_BONUS * (card.stars or 0)
	view.id = "npc" .. card.npcId
	view.level = level
	view.power = level -- what counts against the cap: the sum of levels (decided)
	view.class = class
	view.hit = ns.BaseHit(level, class, attackSpeed) * meleeFactor * stars
	view.attackSpeed = attackSpeed
	-- Its spell: the signature spell, or for Mages and Healers without one a spell of their own.
	-- Strength (a factor of the typical 2 s hit, like melee): measured, else its description,
	-- else SPELL_FALLBACK times its melee. Cast time from the game's spell data.
	if card.spell or card.type == "Mage" or card.type == "Healer" then
		local data = card.spell and not card.player and ns.SpellData(card.npcId, card.spell)
		local factor, source = card.spell and spells[card.spell], "measured"
		if not factor and data and data.low then
			local mobLevel = info and info.level and info.level > 0 and info.level or level
			factor = (data.low + (data.high or data.low)) / 2 / ns.BaseHit(mobLevel, class)
			source = "spell text"
		end
		if not factor then
			factor, source = meleeFactor * ns.SPELL_FALLBACK, "guess"
		end
		view.spellHit = ns.BaseHit(level, class) * factor * stars
		view.spellSource = source
		local cast = data and data.cast or ns.SPELL_TIME
		view.castTime = math.floor(math.max(ns.GCD, cast) * 10 + 0.5) / 10
	end
	view.health = math.max(1, math.floor(ns.BaseHealth(level, class) * healthFactor * stars + 0.5))
	-- Attack: one melee hit; spell power: one cast. Both at fight pace.
	view.attack = math.max(1, math.floor(view.hit * ns.PACE + 0.5))
	if view.spellHit then
		view.spellPower = math.max(1, math.floor(view.spellHit * ns.PACE + 0.5))
	end
	-- Speed: its attack time in seconds (lower is faster): when its turns come
	view.speed = attackSpeed
	view.armor = ns.BaseArmor(level, class)
	view.stamina = card.stamina or 100
	view.zone = card.zone or ""
	if card.stats then
		-- from a duel: its stats came with it (the owner's measurements of that mob)
		view.health, view.attack, view.armor = card.stats.health, card.stats.attack, card.stats.armor
		view.spellPower, view.castTime = card.stats.spellPower, card.stats.castTime
	end
	return view
end

-- Drops

local function GroupFactor()
	if IsInRaid and IsInRaid() then
		return ns.GROUP_FACTOR.raid
	elseif IsInGroup and IsInGroup() then
		return ns.GROUP_FACTOR.party
	end
	return ns.GROUP_FACTOR.solo
end

-- Chance this kill drops the card, and why
-- Starter boost for a small collection (number of different cards owned)
function ns.StarterBoost()
	local owned = 0
	for _ in pairs(BestiaryChar.cards) do
		owned = owned + 1
	end
	if owned < ns.STARTER_CARDS then
		return ns.STARTER_BOOST, owned
	elseif owned >= ns.STARTER_END then
		return 1, owned
	end
	return 1 + (ns.STARTER_BOOST - 1) * 0.5 ^ ((owned - ns.STARTER_CARDS) / ns.STARTER_HALF), owned
end

function ns.DropChance(npcId, classification)
	if ns.testChance then
		return ns.TEST_CHANCE, "test tab: until the next drop"
	end
	local owned = BestiaryChar.cards[npcId]
	if ns.FIRST_DROP_SURE[classification] and not owned then
		return 1, "first card of a " .. ns.RARITIES[classification].name:lower() .. " mob"
	end
	local chance = (ns.DROP_CHANCE[classification] or ns.DROP_CHANCE.normal) * GroupFactor()
	local now, recent = time(), 0
	local drops = BestiaryChar.drops[npcId]
	if drops then
		for i = #drops, 1, -1 do
			if now - drops[i] > ns.FARM_WINDOW then
				tremove(drops, i)
			else
				recent = recent + 1
			end
		end
	end
	chance = chance / 2 ^ recent
	local reasons = {}
	if recent > 0 then
		reasons[#reasons + 1] = recent .. " drop(s) from it in the last hour"
	end
	local boost, owned = ns.StarterBoost()
	if boost > 1 then
		chance = chance * boost
		reasons[#reasons + 1] = ("starter boost x%.1f at %d cards"):format(boost, owned)
	end
	local dry = BestiaryChar.dry and BestiaryChar.dry[npcId] or 0
	if dry > 0 then
		local luck = math.min(ns.DRY_MAX, 1 + ns.DRY_BONUS * dry)
		chance = chance * luck
		reasons[#reasons + 1] = ("bad luck protection x%.1f after %d kills without it"):format(luck, dry)
	end
	return math.min(1, chance), #reasons > 0 and table.concat(reasons, ", ") or nil
end

-- Whether a card drop of this mob can still give something: a new card, or another copy of a
-- normal card (up to 3). Stars don't come from card drops but from their own roll (StarChance).
function ns.CanDrop(npcId)
	local owned = BestiaryChar.cards[npcId]
	return not owned or (ns.CanHaveCopies(owned) and ns.Copies(owned) < ns.MAX_COPIES)
end

local function Given(npcId, guid, owned, result, test)
	if not test then
		BestiaryChar.drops[npcId] = BestiaryChar.drops[npcId] or {}
		tinsert(BestiaryChar.drops[npcId], time())
		ns.RecordDrop(result)
	end
	if ns.ShowLoot then
		ns.ShowLoot(guid, ns.CardView(owned), result, test and "given" or nil)
	end
	if ns.Refresh then
		ns.Refresh()
	end
	return result
end

-- +1 star on an owned card. Returns "star", nil at max stars.
function ns.AddStar(npcId, guid, test)
	local owned = BestiaryChar.cards[npcId]
	if not owned or owned.player or (owned.stars or 0) >= ns.MAX_STARS then
		return
	end
	owned.stars = (owned.stars or 0) + 1
	return Given(npcId, guid, owned, "star", test)
end

-- Gives the card of this mob type, or another copy (normal cards). Forced drops and the Test tab
-- add a star once nothing else is left (noStar: not). Returns "new", "copy", "star" or nil.
-- test: doesn't count for the farm window.
function ns.GiveCard(npcId, guid, test, noStar)
	local cards = BestiaryChar.cards
	local owned = cards[npcId]
	local result
	if owned then
		if ns.CanHaveCopies(owned) and ns.Copies(owned) < ns.MAX_COPIES then
			owned.copies = ns.Copies(owned) + 1
			result = "copy"
		elseif noStar then
			return
		else
			return ns.AddStar(npcId, guid, test)
		end
	else
		local view = ns.BuildCard(npcId)
		if not view then
			return
		end
		cards[npcId] = {
			npcId = npcId, name = view.name, classification = view.classification, family = view.family,
			type = view.type, spell = view.spell, art = view.art, zone = view.zone,
			stars = 0, obtained = time(), level = ns.DropLevel(npcId, view.classification), games = 0,
		}
		owned = cards[npcId]
		result = "new"
	end
	return Given(npcId, guid, owned, result, test)
end

-- Test tab: the next kill we take part in drops its card, studied or not (only this session)
ns.forceDrop = false
-- Test tab: drop chance TEST_CHANCE for studied mobs until the next drop (only this session)
ns.testChance = false

-- Seen casting, but its spells were only ever resisted and none of them is known (the damage
-- meter only names spells that hit): a card would guess its spells, too likely wrong. No card
-- until one of its spells lands (decided, ARCHITECTURE.md 4.0).
function ns.SpellsResisted(entry)
	return entry ~= nil and (entry.casts or 0) > 0 and (entry.resists or 0) > 0 and next(entry.spells) == nil
end

-- Kills of casting mobs whose spells we don't know yet wait until the damage meter of that
-- fight is read (after combat): a spell that hit us in that fight is known then.
local waiting = {}

function ns.OnMeterRead()
	local list = waiting
	waiting = {}
	for _, kill in ipairs(list) do
		ns.OnKill(kill.guid, kill.npcId, kill.name, true)
	end
	ns.RefreshCards()
end

-- Cards follow what's learned about their mob (decided 2026-10-17): its combat type, signature
-- spell and art are built again from what's known now (stats are computed live anyway). A spell
-- once known stays until another one is used more. Called after each fight and at login.
function ns.RefreshCards(quiet)
	local changes = {}
	for npcId, owned in pairs(BestiaryChar.cards) do
		if not owned.player and not owned.test and ns.Studied(npcId) then
			local view = ns.BuildCard(npcId)
			if view then
				local spell = view.spell or owned.spell
				if view.type ~= owned.type or spell ~= owned.spell then
					changes[#changes + 1] = ("%s: %s%s"):format(owned.name or "?", view.type, spell and (", " .. spell) or "")
				end
				owned.type, owned.spell = view.type, spell
				owned.art = view.spell and view.art or owned.art
				owned.classification, owned.family, owned.name = view.classification, view.family, view.name
			end
		end
	end
	if #changes > 0 then
		if not quiet then
			ns.Print("Learned more, cards updated: " .. table.concat(changes, "; "))
		end
		if ns.Refresh then
			ns.Refresh()
		end
	end
end

function ns.OnKill(guid, npcId, name, afterMeter)
	if not afterMeter then
		ns.RecordKill()
	end
	local entry = ns.Studied(npcId)
	local info = ns.MobInfo(npcId)
	local forced = ns.forceDrop
	if not afterMeter and entry and entry.casts > 0 and next(entry.spells) == nil and ns.MeterDue and ns.MeterDue() then
		waiting[#waiting + 1] = { guid = guid, npcId = npcId, name = name }
		ns.Debug(("%s died: its spells are unknown, waiting for the damage meter."):format(name or "?"))
		return
	end
	if ns.SpellsResisted(entry) then
		ns.Debug(("%s died: it cast spells but they were only resisted, so they're unknown: no card."):format(name or "?"))
		if forced then
			ns.Print(("Forced drop: %s's spells were only resisted, so they're unknown: no card. Still armed."):format(name or "?"))
		end
		return
	end
	if not info then
		ns.Debug(("%s died: never targeted or seen on a nameplate, so no card data."):format(name or "?"))
		if forced then
			ns.Print(("Forced drop: %s was never targeted, so there's no card data. Still armed."):format(name or "?"))
		end
		return
	elseif info.family == false then
		ns.Debug(("%s died: critters don't drop cards."):format(name or "?"))
		return
	elseif not info.family then
		ns.Debug(("%s died: unknown creature type %q."):format(name or "?", tostring(info.creatureType)))
		if forced then
			ns.Print(("Forced drop: %s has an unknown creature type %q. Still armed."):format(name or "?", tostring(info.creatureType)))
		end
		return
	end
	if forced then
		ns.forceDrop = false
		if not ns.GiveCard(npcId, guid) then
			ns.Print(("Forced drop: %s is already at %d stars."):format(info.name or name or "?", ns.MAX_STARS))
		end
		if ns.Refresh then
			ns.Refresh()
		end
		return
	end
	local seconds = entry and entry.seconds or 0
	if seconds < ns.STUDY_SECONDS then
		ns.Debug(("%s died: studied %d%%, no card yet."):format(name or "?", seconds / ns.STUDY_SECONDS * 100))
		return
	end
	-- Owned: a roll for a star first, then a card drop only if it can still give a copy
	local owned = BestiaryChar.cards[npcId]
	if owned then
		local starChance = ns.StarChance(owned)
		if starChance > 0 then
			local starRoll = math.random()
			ns.Debug(("%s died: %.2f%% star chance (%d stars), rolled %.2f%%."):format(name or "?", starChance * 100,
				owned.stars or 0, starRoll * 100))
			if starRoll < starChance then
				ns.AddStar(npcId, guid)
			end
		end
		if not ns.CanDrop(npcId) then
			return
		end
	end
	local chance, why = ns.DropChance(npcId, info.classification)
	local roll = math.random()
	ns.Debug(("%s died: %.0f%% chance%s, rolled %.0f%%."):format(name or "?", chance * 100,
		why and (" (" .. why .. ")") or "", roll * 100))
	BestiaryChar.dry = BestiaryChar.dry or {}
	if roll >= chance then
		if not ns.testChance then
			BestiaryChar.dry[npcId] = (BestiaryChar.dry[npcId] or 0) + 1 -- bad luck protection
		end
		return
	end
	if not ns.testChance then
		BestiaryChar.dry[npcId] = nil -- a real drop ends the bad luck
	end
	if ns.testChance then
		ns.testChance = false
		ns.Print("Test drop chance used up, back to normal.")
	end
	ns.GiveCard(npcId, guid, nil, true)
end

-- The Assassin type is called Warrior now (decided 2026-10-17)
function ns.MigrateTypes()
	for _, card in pairs(BestiaryChar.cards) do
		if card.type == "Assassin" then
			card.type = "Warrior"
		end
	end
end

-- Cards from before stars started at 0 had 1 as their lowest: one star less, once
function ns.MigrateStars()
	if BestiaryChar.starsFromZero then
		return
	end
	for _, card in pairs(BestiaryChar.cards) do
		card.stars = math.max(0, (card.stars or 1) - 1)
	end
	BestiaryChar.starsFromZero = true
end

-- Test tab: builds the card again from what's known now (type, art, signature spell), keeping
-- its stars. Cards are fixed once they drop; this is for when the data was wrong back then.
function ns.RebuildCard(npcId)
	local owned = BestiaryChar.cards[npcId]
	local view = ns.BuildCard(npcId)
	if not owned or not view then
		return
	end
	owned.type, owned.spell, owned.art = view.type, view.spell, view.art
	owned.classification, owned.family, owned.name = view.classification, view.family, view.name
	if ns.Refresh then
		ns.Refresh()
	end
	return owned
end

-- Test tab: take a card out of the collection again
function ns.RemoveCard(npcId)
	BestiaryChar.cards[npcId] = nil
	BestiaryChar.drops[npcId] = nil
	if ns.Refresh then
		ns.Refresh()
	end
end

-- The number on a card's ATK: what its action deals (casters and healers: their spell)
function ns.CardAttack(view)
	if (view.type == "Mage" or view.type == "Healer") and view.spellPower then
		return view.spellPower
	end
	return view.attack
end

-- Sorting the collection (the Collection and Squads tabs share it, saved per character)
ns.SORTS = {
	{ key = "rarity", name = "Rarity" },
	{ key = "level", name = "Level" },
	{ key = "attack", name = "Attack" },
	{ key = "health", name = "Health" },
	{ key = "speed", name = "Speed" },
}

function ns.SortKey()
	return BestiaryChar and BestiaryChar.sort or "rarity"
end

-- step: +1 the next sort, -1 the one before
function ns.NextSort(step)
	local current = 1
	for i, sort in ipairs(ns.SORTS) do
		if sort.key == ns.SortKey() then
			current = i
		end
	end
	BestiaryChar.sort = ns.SORTS[(current - 1 + step) % #ns.SORTS + 1].key
	if ns.Refresh then
		ns.Refresh()
	end
end

function ns.SortName()
	for _, sort in ipairs(ns.SORTS) do
		if sort.key == ns.SortKey() then
			return sort.name
		end
	end
end

-- Highest first (speed: fastest, the shortest attack time); ties: rarest, then by name
local VALUES = {
	level = function(view) return view.level or 0 end,
	attack = ns.CardAttack,
	health = function(view) return view.health end,
	speed = function(view) return -(view.speed or 0) end,
}

function ns.SortCards(list, key)
	local value = VALUES[key or ns.SortKey()]
	table.sort(list, function(a, b)
		if value then
			local va, vb = value(a), value(b)
			if va ~= vb then
				return va > vb
			end
		end
		local ra, rb = ns.RARITY_ORDER[a.classification], ns.RARITY_ORDER[b.classification]
		if ra ~= rb then
			return ra < rb
		end
		return a.name < b.name
	end)
	return list
end

-- The collection as card views, in the chosen order
function ns.Collection()
	local list = {}
	for _, card in pairs(BestiaryChar.cards) do
		list[#list + 1] = ns.CardView(card)
	end
	return ns.SortCards(list)
end

-- A button that cycles through the sorts (left click: next, right click: back)
function ns.SortButton(parent, width)
	local button = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
	button:SetSize(width or 110, 20)
	button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	button:SetScript("OnClick", function(_, mouse)
		ns.NextSort(mouse == "RightButton" and -1 or 1)
		PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
	end)
	button:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_TOP")
		GameTooltip:AddLine("Sort the cards")
		for _, sort in ipairs(ns.SORTS) do
			local on = sort.key == ns.SortKey()
			GameTooltip:AddLine((on and "> " or "   ") .. sort.name, on and 1 or 0.7, on and 0.82 or 0.7, on and 0 or 0.7)
		end
		GameTooltip:AddLine("Left click: next  ·  Right click: back", 0.6, 0.6, 0.6)
		GameTooltip:Show()
	end)
	button:SetScript("OnLeave", GameTooltip_Hide)
	function button:Update()
		self:SetText("Sort: " .. (ns.SortName() or "?"))
	end
	return button
end

-- Mob types being studied (no card yet), most studied first
function ns.Studying()
	local list = {}
	for npcId, entry in pairs(BestiaryChar.study) do
		local info = ns.MobInfo(npcId)
		if not BestiaryChar.cards[npcId] and entry.seconds > 0 and (not info or info.family ~= false) then
			list[#list + 1] = { npcId = npcId, name = (info and info.name) or entry.name or "?", seconds = entry.seconds }
		end
	end
	table.sort(list, function(a, b)
		return a.seconds > b.seconds
	end)
	return list
end
