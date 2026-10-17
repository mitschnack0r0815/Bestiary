local addonName, ns = ...

-- Builds up knowledge per mob type (NPC id), ARCHITECTURE.md 4.0. This client doesn't let
-- addons read the combat log (registering COMBAT_LOG_EVENT_UNFILTERED is forbidden), and unit
-- values can be secret, so everything comes from the unit API on units we can see: target,
-- mouseover, focus and nameplates.
--   * study time: every STUDY_TICK seconds, each visible mob that's in combat (with anyone)
--     adds STUDY_TICK seconds to its type
--   * what it did: spells it cast (cast events), heals among them, whether it uses mana, its
--     NPC class and attack speed
--   * level, classification, creature type and whether someone else has it tapped
-- Kills go to ns.OnKill, once per mob, from whichever notices first:
--   * a mob we were fighting (on our threat list, or targeting us or our pet) seen dead as
--     target, focus, mouseover or nameplate
--   * looting its corpse (if we can loot it, it's ours)
--   * PARTY_KILL (we or a group member landed the killing blow), if the client sends it
--
-- Saved: BestiaryChar.study[npcId] (per character), BestiaryAccount.mobs[npcId] (account wide).

local tapDenied = {} -- GUID -> true if someone else has it tapped
local deathSeen = {} -- GUID -> GetTime(), so a death is only handled once
local engaged = {} -- GUID -> GetTime() we last saw it fighting us
local nameplates = {} -- unit token -> true while its nameplate is shown
local fightMobs = {} -- mob name -> npcId of mobs fighting us this fight (false: two types share it)
local meterDue = false -- a fight ended whose damage meter we haven't read yet
-- This fight, for measuring health and spell damage once the damage meter can be read
local fightGuids = {} -- npcId -> { guid = true } of the mobs of that type fighting us
local fightKills = {} -- npcId -> kills
local fightSpellHits = {} -- npcId -> { plain spell hits on us, as factors of a typical hit }
local fightTapped = false -- someone else's mob died in it: its damage isn't all in our meter

-- Measuring (ARCHITECTURE.md 4.0): samples per mob type, account wide (they don't depend on
-- who measured), the median is the value. Samples are factors against the typical mob of the
-- same level and NPC class (LevelStats.lua), so mobs of one type at different levels agree and a
-- card can have them at any level (3.2).
local MAX_SAMPLES = 25

local function AddSample(list, value)
	list[#list + 1] = value
	if #list > MAX_SAMPLES then
		table.remove(list, 1)
	end
end

function ns.Median(list)
	if not list or #list == 0 then
		return nil
	end
	local sorted = {}
	for i, value in ipairs(list) do
		sorted[i] = value
	end
	table.sort(sorted)
	local middle = (#sorted + 1) / 2
	return (sorted[math.floor(middle)] + sorted[math.ceil(middle)]) / 2
end

local function Measured(npcId)
	local info = BestiaryAccount.mobs[npcId]
	if not info then
		return nil
	end
	info.measured = nil -- raw numbers from the first version, without their level
	info.factors = info.factors or { melee = {}, health = {}, spells = {} }
	return info.factors
end
ns.Measured = function(npcId)
	local info = BestiaryAccount.mobs[npcId]
	return info and info.factors
end

local function Factor(value, base)
	return math.floor(value / base * 1000 + 0.5) / 1000
end

-- Our armor, read whenever it isn't secret (the last value counts during combat)
local playerArmor

local function ReadArmor()
	local _, effective = UnitArmor("player")
	effective = ns.Clean(effective) -- defined below, called later
	if effective then
		playerArmor = effective
	end
end

local guidLevels = {} -- GUID -> level of mobs seen this fight
local speedSeen = {} -- GUID -> true once its attack speed was counted (this session)

-- The level of that very mob if we saw it, else the last one seen of its type
local function MobLevel(npcId, guid)
	local info = BestiaryAccount.mobs[npcId]
	local level = guid and guidLevels[guid] or info and info.level
	if not level or level < 1 then
		return ns.MAX_LEVEL -- skull: treated as a boss
	end
	return level
end

local function MobClass(npcId)
	local info = BestiaryAccount.mobs[npcId]
	return info and info.class, info and info.attackSpeed
end

ns.debug = false

local function IsSecret(value)
	return issecretvalue and issecretvalue(value) or false
end

-- nil for secret values, so they're never compared or stored
local function Clean(value)
	if IsSecret(value) then
		return nil
	end
	return value
end
ns.Clean = Clean

function ns.EmptyStudy()
	return {
		seconds = 0, casts = 0, heals = 0, spells = {}, spellIds = {}, spellIcons = {},
		mana = false, class = nil, attackSpeed = nil,
		magicHits = 0, physicalHits = 0, poisons = 0, -- what it did to you (instant casts too)
		resists = 0, -- its casts we resisted (spell unknown, it never hit)
		spellDamage = {}, -- spell name -> damage it did to us, from the damage meter
		stealth = 0, tankBuffs = 0, -- buffs that say what it is
	}
end

local function Study(npcId)
	local study = BestiaryChar.study
	local entry = study[npcId]
	if not entry then
		entry = ns.EmptyStudy()
		study[npcId] = entry
	end
	return entry
end

local function MobInfo(npcId)
	return BestiaryAccount.mobs[npcId]
end
ns.MobInfo = MobInfo

local function Debug(msg)
	if ns.debug then
		ns.Print("|cff999999" .. msg .. "|r")
	end
end
ns.Debug = Debug

-- The mob behind a unit token: guid, npcId; nil for players, pets, players' summons and
-- secret GUIDs
local function Mob(unit)
	if not Clean(UnitExists(unit)) then
		return
	end
	local controlled = UnitPlayerControlled(unit)
	if IsSecret(controlled) or controlled then
		return
	end
	local guid = Clean(UnitGUID(unit))
	local npcId = ns.NpcId(guid)
	if npcId then
		return guid, npcId
	end
end

-- Dungeon and raid bosses: they show in the boss frames (boss1-5), whatever their level
local function IsBoss(unit)
	if UnitIsBossMob and Clean(UnitIsBossMob(unit)) then
		return true
	end
	for i = 1, 5 do
		local boss = "boss" .. i
		if Clean(UnitExists(boss)) and Clean(UnitIsUnit(unit, boss)) then
			return true
		end
	end
	return false
end

-- Remember what the unit API says about a mob
local function CacheUnit(unit)
	local guid, npcId = Mob(unit)
	if not guid then
		return
	end
	local info = BestiaryAccount.mobs[npcId] or {}
	local name = Clean(UnitName(unit))
	local level = Clean(UnitLevel(unit))
	local classification = Clean(UnitClassification(unit))
	local creatureType = Clean(UnitCreatureType(unit))
	if name then
		info.name = name
	end
	if level then
		info.level = level
		guidLevels[guid] = level
	end
	-- Its NPC class and attack speed: which row of the level table it scales with
	local _, class = UnitClass(unit)
	class = Clean(class)
	if class then
		info.class = class
	end
	-- Its attack speed: each mob counted once, the most common reading wins, so a mob we slowed
	-- or one that's enraged doesn't change it (it's only readable out of combat anyway)
	local speed = UnitAttackSpeed and Clean((UnitAttackSpeed(unit)))
	if speed and speed > 0 and not speedSeen[guid] then
		speedSeen[guid] = true
		local tenths = math.floor(speed * 10 + 0.5)
		info.speeds = info.speeds or {}
		info.speeds[tenths] = (info.speeds[tenths] or 0) + 1
		local best, count = nil, 0
		for value, seen in pairs(info.speeds) do
			if seen > count or (seen == count and value == 20) then -- ties: the usual 2.0 s
				best, count = value, seen
			end
		end
		info.attackSpeed = best / 10
	end
	if classification then
		info.classification = ns.CLASSIFICATIONS[classification] or "normal"
	end
	if IsBoss(unit) then
		info.boss = true -- once a boss, always a boss (outside its encounter it looks elite)
	end
	if level == -1 or info.boss then
		info.classification = "worldboss" -- skull level, or a dungeon or raid boss
	end
	info.classification = info.classification or "normal"
	if creatureType then
		info.creatureType = creatureType
		info.family = ns.CREATURE_TYPES[creatureType] -- false for critters, nil if unknown
	end
	if info.name then
		BestiaryAccount.mobs[npcId] = info
	end
	if UnitIsTapDenied and Clean(UnitIsTapDenied(unit)) then
		tapDenied[guid] = true
	end
	-- Its maximum health, to tell sturdy mobs from frail ones (Tank or Assassin). Clients that
	-- only give percentages report 100 for every mob: that's no information.
	local health = Clean(UnitHealthMax(unit))
	if health and health > 0 and health ~= 100 and info.name then
		info.maxHealth = math.max(info.maxHealth or 0, health)
	end
end

-- What the unit API tells about how a mob fights
local function RecordStyle(unit, entry)
	local powerType = Clean(UnitPowerType(unit))
	local maxPower = Clean(UnitPowerMax(unit, 0))
	if powerType == 0 and maxPower and maxPower > 0 then
		entry.mana = true
	end
	local _, class = UnitClass(unit)
	class = Clean(class)
	if class then
		entry.class = class
	end
	if UnitAttackSpeed then
		local speed = Clean((UnitAttackSpeed(unit)))
		if speed and speed > 0 then
			entry.attackSpeed = speed
		end
	end
end

-- Spell names that heal (lower case parts), English and German
local HEAL_WORDS = { "heal", "renew", "mend", "rejuven", "regrowth", "holy light", "flash of light",
	"heil", "erneuerung", "verjüngung", "nachwachsen" }

local function IsHeal(spellName)
	local name = spellName:lower()
	for _, word in ipairs(HEAL_WORDS) do
		if name:find(word, 1, true) then
			return true
		end
	end
end

local function SpellName(spellId)
	if C_Spell and C_Spell.GetSpellName then
		return C_Spell.GetSpellName(spellId)
	end
	return GetSpellInfo and (GetSpellInfo(spellId))
end

-- Casts. Spell ids (and sometimes names) of mobs can be secret in combat, so a cast counts
-- even when we can't tell what it was, and the cast bar (UnitCastingInfo / UnitChannelInfo) is
-- read on every study tick as a second source that often still has the name and icon.
-- Each cast counts once: by its cast GUID when we can read it, else by unit and start time.
local castSeen = {} -- key -> GetTime()
local unkeyedCast = {} -- mob GUID -> GetTime() of a cast event we couldn't key
local castDone = {} -- mob GUID -> { time, npcId } of its last finished cast, for resists

local function RecordCast(guid, npcId, key, spellId, spellName, texture, how)
	local now = GetTime()
	if key then
		if castSeen[key] then
			return
		end
		castSeen[key] = now
	end
	local entry = Study(npcId)
	entry.casts = entry.casts + 1
	if spellName then
		entry.spells[spellName] = (entry.spells[spellName] or 0) + 1
		if spellId and spellId > 0 then
			entry.spellIds[spellName] = spellId
		end
		if texture then
			entry.spellIcons[spellName] = texture
		end
		if IsHeal(spellName) then
			entry.heals = entry.heals + 1
		end
	end
	local info = BestiaryAccount.mobs[npcId]
	Debug(("Cast (%s): %s - %s"):format(how, (info and info.name) or "?", spellName or "spell hidden"))
end

local function OnCast(event, unit, castGUID, spellId)
	local guid, npcId = Mob(unit)
	if not guid then
		return
	end
	castGUID, spellId = Clean(castGUID), Clean(spellId)
	local spellName = spellId and Clean(SpellName(spellId))
	-- One cast arrives once per unit token showing the mob (target and its nameplate)
	local key = "event:" .. guid .. event
	if castSeen[key] and GetTime() - castSeen[key] < 0.2 then
		return
	end
	castSeen[key] = GetTime()
	if event ~= "UNIT_SPELLCAST_START" then
		castDone[guid] = { time = GetTime(), npcId = npcId, guid = guid }
		ns.FightLog.Count(npcId, "casts")
	end
	if not castGUID then
		-- Can't key it: the end of a cast we saw start doesn't count again
		local recent = unkeyedCast[guid] and GetTime() - unkeyedCast[guid] < 4
		unkeyedCast[guid] = GetTime()
		if event == "UNIT_SPELLCAST_SUCCEEDED" and recent then
			return
		end
	end
	RecordCast(guid, npcId, castGUID, spellId, spellName, nil, "event")
end

-- The spell id is the 9th value of UnitCastingInfo on modern clients, the 8th on some older
local function CastBar(unit)
	if not UnitCastingInfo then
		return
	end
	local values = { UnitCastingInfo(unit) }
	local channel = false
	if values[1] == nil then
		if not UnitChannelInfo then
			return
		end
		values = { UnitChannelInfo(unit) }
		channel = true
	end
	if values[1] == nil then
		return
	end
	local spellId = values[channel and 8 or 9]
	if channel == false and (spellId == nil or IsSecret(spellId) == false and type(spellId) ~= "number") then
		spellId = values[8]
	end
	spellId = Clean(spellId)
	return Clean(values[1]), Clean(values[3]), Clean(values[4]), not channel and Clean(values[7]) or nil,
		type(spellId) == "number" and spellId or nil
end

-- What a mob is casting right now, from its cast bar
local function ReadCastBar(unit, guid, npcId)
	local name, texture, startTime, castID, spellId = CastBar(unit)
	if not name and not startTime then
		return
	end
	if type(castID) ~= "string" then
		castID = nil
	end
	local key = castID or (startTime and (guid .. ":" .. startTime))
	if not key or castSeen[key] then
		return
	end
	-- A cast event we couldn't key just counted this cast: only learn the name
	if unkeyedCast[guid] and GetTime() - unkeyedCast[guid] < 4 then
		castSeen[key] = GetTime()
		if name then
			local entry = Study(npcId)
			entry.spells[name] = (entry.spells[name] or 0) + 1
			if texture then
				entry.spellIcons[name] = texture
			end
			if spellId and spellId > 0 then
				entry.spellIds[name] = spellId
			end
			if IsHeal(name) then
				entry.heals = entry.heals + 1
			end
		end
		return
	end
	RecordCast(guid, npcId, key, spellId, name, texture, "cast bar")
end

-- Instant casts leave no cast bar, and this client doesn't always send cast events for mobs.
-- They still show as auras (a debuff on you, a buff a mob put on itself: each names its caster)
-- and as spell damage you take. ------------------------------------------------------------

local PHYSICAL = 1

-- Auras of a unit: list of { name, icon, spellId, source, dispel, id }, secret fields left out.
-- In combat this client doesn't hand out secret auras to addons at all: the call raises an error
-- ("Auras cannot be accessed when secret") instead of returning secret values. Then we learn
-- nothing from auras this time; the error must not turn anything off.
local function Auras(unit, filter)
	local list = {}
	for i = 1, 40 do
		local name, icon, spellId, source, dispel, id
		if C_UnitAuras and C_UnitAuras.GetAuraDataByIndex then
			local ok, aura = pcall(C_UnitAuras.GetAuraDataByIndex, unit, i, filter)
			if not ok or not aura then
				break
			end
			name, icon, spellId, source = Clean(aura.name), Clean(aura.icon), Clean(aura.spellId), Clean(aura.sourceUnit)
			dispel, id = Clean(aura.dispelName), Clean(aura.auraInstanceID)
		elseif UnitAura then
			local ok, n, ic, _, dt, _, expires, src, _, _, sid = pcall(UnitAura, unit, i, filter)
			if not ok or not n then
				break
			end
			name, icon, spellId, source, dispel = Clean(n), Clean(ic), Clean(sid), Clean(src), Clean(dt)
			id = Clean(expires) and (tostring(sid) .. ":" .. tostring(expires))
		else
			break
		end
		list[#list + 1] = { name = name, icon = icon, spellId = spellId, source = source, dispel = dispel, id = id }
	end
	return list
end

-- Debuffs mobs put on us: casts (instant ones too); poisons point to an Assassin
local function ScanPlayerDebuffs()
	for _, aura in ipairs(Auras("player", "HARMFUL")) do
		local guid, npcId
		if aura.source then
			guid, npcId = Mob(aura.source)
		end
		if guid and aura.id then
			local key = "aura:" .. tostring(aura.id)
			if not castSeen[key] then
				RecordCast(guid, npcId, key, aura.spellId, aura.name, aura.icon, "debuff on you")
				if aura.dispel == "Poison" then
					local entry = Study(npcId)
					entry.poisons = entry.poisons + 1
				end
			end
		end
	end
end

-- Buff names (lower case parts, English and German) that say what a mob is
local STEALTH_WORDS = { "stealth", "prowl", "verstohlenheit", "schleichen" }
local TANK_WORDS = { "stoneskin", "harden", "shield wall", "shield block", "defensive stance", "rock skin",
	"steinhaut", "verhärten", "schildwall", "schildblock", "verteidigungshaltung" }

local function Has(name, words)
	name = name:lower()
	for _, word in ipairs(words) do
		if name:find(word, 1, true) then
			return true
		end
	end
end

-- Buffs on a visible mob (also before the fight: Lightning Shield, Demon Skin, Stealth are put
-- on long before). Each one is a cast of the mob that put it there: itself, or an ally it
-- supports. Stealth and armor buffs on itself say Assassin or Tank.
local function ScanBuffs(unit)
	local guid = Mob(unit)
	if not guid then
		return
	end
	for _, aura in ipairs(Auras(unit, "HELPFUL")) do
		if aura.source and aura.id then
			local casterGuid, casterId = Mob(aura.source)
			local key = "aura:" .. guid .. ":" .. tostring(aura.id)
			if casterGuid and not castSeen[key] then
				local onItself = casterGuid == guid
				RecordCast(casterGuid, casterId, key, aura.spellId, aura.name, aura.icon, onItself and "buff on itself" or "buff on an ally")
				if onItself and aura.name then
					local entry = Study(casterId)
					if Has(aura.name, STEALTH_WORDS) then
						entry.stealth = entry.stealth + 1
					elseif Has(aura.name, TANK_WORDS) then
						entry.tankBuffs = entry.tankBuffs + 1
					end
				end
			end
		end
	end
end
ns.ScanBuffs = ScanBuffs

-- Damage we take (UNIT_COMBAT): spell schools mean spells. Credited to the one visible mob
-- that targets us; with several (or none), nobody gets it.
local function Attacker()
	local found
	local function Check(unit)
		local guid, npcId = Mob(unit)
		if guid and Clean(UnitIsUnit(unit .. "target", "player")) and (not found or found.guid ~= guid) then
			if found then
				found.many = true
			else
				found = { guid = guid, npcId = npcId }
			end
		end
	end
	Check("target")
	Check("focus")
	for unit in pairs(nameplates) do
		Check(unit)
	end
	return found and not found.many and found or nil
end

-- How long after a mob's cast finishes a resist on us still counts as its spell (travel time)
local RESIST_WINDOW = 2

-- The one mob that finished a cast just now (nil if none or several): a spell hit is its spell
local function RecentCaster()
	local now, found = GetTime(), nil
	for _, cast in pairs(castDone) do
		if now - cast.time <= RESIST_WINDOW then
			if found and found.npcId ~= cast.npcId then
				return nil
			end
			found = cast
		end
	end
	return found
end

local function OnCombat(unit, action, flag, amount, school)
	unit, action, flag, amount, school = Clean(unit), Clean(action), Clean(flag), Clean(amount), Clean(school)
	if unit == "player" and action and action ~= "HEAL" and action ~= "ENERGIZE" then
		-- Into the fight log: spells and resists are whoever just finished a cast, the rest
		-- whoever targets us
		local who
		if action == "RESIST" or (school and school ~= PHYSICAL) then
			local cast = RecentCaster()
			who = cast and cast.npcId
		end
		if not who and action ~= "RESIST" then
			local attacker = Attacker()
			who = attacker and attacker.npcId
		end
		local wound = action == "WOUND"
		ns.FightLog.Hit(who, school, wound and amount or 0, wound and flag or action)
	end
	if unit == "player" and action == "RESIST" then
		-- Melee can't be resisted: it was the spell of whoever just finished a cast
		local now, credited = GetTime(), {}
		for guid, cast in pairs(castDone) do
			if now - cast.time <= RESIST_WINDOW and not credited[cast.npcId] then
				credited[cast.npcId] = true
				local entry = Study(cast.npcId)
				entry.resists = entry.resists + 1
				ns.FightLog.Count(cast.npcId, "resists")
				local info = MobInfo(cast.npcId)
				Debug(("Resisted a spell of %s"):format((info and info.name) or "?"))
			end
		end
		return
	end
	if unit ~= "player" or action ~= "WOUND" or not school then
		return
	end
	-- Plain hits only (no crit, crushing, glancing, block or partial resist) are measured
	local plain = flag == "" and amount and amount > 0
	if school ~= PHYSICAL and plain then
		local cast = RecentCaster()
		if cast then
			local class = MobClass(cast.npcId)
			fightSpellHits[cast.npcId] = fightSpellHits[cast.npcId] or {}
			tinsert(fightSpellHits[cast.npcId], Factor(amount, ns.BaseHit(MobLevel(cast.npcId, cast.guid), class)))
		end
	end
	local attacker = Attacker()
	if not attacker then
		return
	end
	local entry = Study(attacker.npcId)
	if school == PHYSICAL then
		entry.physicalHits = entry.physicalHits + 1
		-- Its raw hit: our armor taken back out
		local measured = Measured(attacker.npcId)
		if plain and playerArmor and measured then
			local level = MobLevel(attacker.npcId, attacker.guid)
			local class, speed = MobClass(attacker.npcId)
			local raw = amount / (1 - ns.ArmorReduction(playerArmor, level))
			AddSample(measured.melee, Factor(raw, ns.BaseHit(level, class, speed)))
		end
	else
		entry.magicHits = entry.magicHits + 1
	end
end

-- An error that doesn't stop anything: kept for /bst errors (once per message), not printed
local function Noted(what, err)
	local list = (BestiaryAccount and BestiaryAccount.errors) or ns.errors
	local msg = ("Bestiary %s: %s"):format(what, tostring(err))
	for _, entry in ipairs(list) do
		if entry.msg == msg then
			entry.count = entry.count + 1
			return
		end
	end
	if #list < 20 then
		list[#list + 1] = { msg = msg, count = 1, at = time(), stack = debugstack and debugstack(2, 12, 0) or nil }
	end
end

-- Study time: mobs in combat we can see
local function StudyTick()
	local seen = {}
	local function Look(unit)
		local guid, npcId = Mob(unit)
		if not guid or seen[guid] then
			return
		end
		local dead = UnitIsDead(unit)
		if IsSecret(dead) or dead or not Clean(UnitAffectingCombat(unit)) then
			return
		end
		seen[guid] = true
		local info = BestiaryAccount.mobs[npcId]
		if not info then
			CacheUnit(unit)
			info = BestiaryAccount.mobs[npcId]
		end
		local entry = Study(npcId)
		-- Study time first: what else we read about it is extra, and an error there (a client
		-- that refuses a read) must not stop the studying
		local before = entry.seconds
		entry.seconds = entry.seconds + ns.STUDY_TICK
		for _, extra in ipairs({ RecordStyle, ReadCastBar, ScanBuffs }) do
			local ok, err = pcall(extra, unit, extra == RecordStyle and entry or guid, npcId)
			if not ok then
				Noted("studying extras", err)
			end
		end
		entry.name = entry.name or (info and info.name)
		if before < ns.STUDY_SECONDS and entry.seconds >= ns.STUDY_SECONDS and not (info and info.family == false) then
			ns.Print(("You've studied |cffffd200%s|r. It can drop its card now."):format((info and info.name) or "?"))
			if ns.Refresh then
				ns.Refresh()
			end
		end
	end
	Look("target")
	Look("mouseover")
	Look("focus")
	for unit in pairs(nameplates) do
		Look(unit)
	end
end

-- One of our kills, however we noticed it
local function Kill(guid, npcId, how)
	if not npcId or deathSeen[guid] then
		return
	end
	deathSeen[guid] = GetTime()
	engaged[guid] = nil
	if meterDue then -- died in the fight whose damage meter is still to be read
		fightKills[npcId] = (fightKills[npcId] or 0) + 1
		ns.FightLog.Count(npcId, "kills")
		fightGuids[npcId] = fightGuids[npcId] or {}
		fightGuids[npcId][guid] = true
		fightTapped = fightTapped or tapDenied[guid] or false
	end
	local info = MobInfo(npcId)
	if tapDenied[guid] and how ~= "looted" then
		Debug(("%s died, tapped by someone else: no card."):format((info and info.name) or "?"))
		return
	end
	Debug(("Kill noticed (%s): %s"):format(how, (info and info.name) or "?"))
	if ns.OnKill then
		ns.OnKill(guid, npcId, info and info.name)
	end
end

-- Whether a mob is fighting us: we're on its threat list, or it targets us or our pet
local function FightingUs(unit)
	if UnitThreatSituation and Clean(UnitThreatSituation("player", unit)) ~= nil then
		return true
	end
	local target = unit .. "target"
	return Clean(UnitIsUnit(target, "player")) or Clean(UnitIsUnit(target, "pet"))
		or Clean(UnitIsUnit("pettarget", unit)) or false
end

-- Remembers mobs fighting us, and notices when one of them is dead
local function Watch(unit)
	local guid, npcId = Mob(unit)
	if not guid then
		return
	end
	local dead = UnitIsDead(unit)
	if IsSecret(dead) then
		return
	elseif dead then
		if engaged[guid] then
			Kill(guid, npcId, "seen dead")
		end
	elseif FightingUs(unit) then
		engaged[guid] = GetTime()
		fightGuids[npcId] = fightGuids[npcId] or {}
		fightGuids[npcId][guid] = true
		ns.FightLog.Mob(npcId, guid, guidLevels[guid])
		local info = MobInfo(npcId)
		if info and info.name then
			-- two mob types with one name can't be told apart in the damage meter
			local known = fightMobs[info.name]
			fightMobs[info.name] = (known == nil or known == npcId) and npcId or false
		end
	end
end

local function WatchAll()
	Watch("target")
	Watch("focus")
	Watch("mouseover")
	for unit in pairs(nameplates) do
		Watch(unit)
	end
end

local function OnPartyKill(_, targetGUID)
	targetGUID = Clean(targetGUID)
	Kill(targetGUID, ns.NpcId(targetGUID), "party kill")
end

local function OnLoot()
	if not (GetLootSourceInfo and GetNumLootItems) then
		return
	end
	for slot = 1, GetNumLootItems() do
		local sources = { GetLootSourceInfo(slot) } -- guid, quantity, guid, quantity...
		for i = 1, #sources, 2 do
			local guid = Clean(sources[i])
			local npcId = ns.NpcId(guid)
			if npcId then
				Kill(guid, npcId, "looted")
			end
		end
	end
end

-- The damage meter (C_DamageMeter) -------------------------------------------------------------
-- Mob casts are always secret here, but Blizzard's damage meter lists every spell that hit us
-- with the mob that cast it ("Shadow Bolt, 87, Defias Renegade Mage"). It's secret in combat,
-- so it's read once per fight, when the combat restriction lifts. Spells that missed, were
-- resisted or do no damage aren't in it.
local MELEE = 6603 -- "Attack"

local function CombatRestricted()
	if InCombatLockdown() then
		return true
	end
	local restricted = C_RestrictedActions and C_RestrictedActions.IsAddOnRestrictionActive
	local combat = Enum.AddOnRestrictionType and Enum.AddOnRestrictionType.Combat or 0
	return restricted and Clean(restricted(combat)) or false
end

local function ReadMeter()
	local meter = C_DamageMeter
	local types = Enum.DamageMeterType
	if not (meter and types and Enum.DamageMeterSessionType) then
		return
	end
	local current = Enum.DamageMeterSessionType.Current
	-- Mob names -> NPC id: the mobs we saw fight us, and the enemies we damaged
	local names = {}
	for name, npcId in pairs(fightMobs) do
		names[name] = npcId
	end
	local ok, enemies = pcall(meter.GetCombatSessionFromType, current, types.EnemyDamageTaken)
	for _, source in ipairs(ok and enemies and enemies.combatSources or {}) do
		local name, npcId = Clean(source.name), Clean(source.sourceCreatureID)
		if name and npcId and npcId > 0 then
			local known = names[name]
			names[name] = (known == nil or known == npcId) and npcId or false
		end
	end
	local playerGUID = Clean(UnitGUID("player"))
	local log = { spells = {}, health = {} } -- for the fight log
	local okMine, mine = pcall(meter.GetCombatSessionSourceFromType, current, types.DamageDone, playerGUID)
	log.done = okMine and mine and Clean(mine.totalAmount) or nil

	-- Health: the damage it took to die, minus overkill. Only when we're alone, it was the
	-- only mob of its type fighting us and the only kill of the fight (else the numbers mix).
	local kills = 0
	for _, count in pairs(fightKills) do
		kills = kills + count
	end
	if kills == 1 and not fightTapped and not IsInGroup() then
		local npcId = next(fightKills)
		local guids = 0
		for _ in pairs(fightGuids[npcId] or {}) do
			guids = guids + 1
		end
		local total = 0
		for _, source in ipairs(ok and enemies and enemies.combatSources or {}) do
			if Clean(source.sourceCreatureID) == npcId then
				total = total + (Clean(source.totalAmount) or 0)
			end
		end
		local overkill = 0
		local okDone, done = pcall(meter.GetCombatSessionSourceFromType, current, types.DamageDone, playerGUID)
		for _, spell in ipairs(okDone and done and done.combatSpells or {}) do
			overkill = overkill + (Clean(spell.overkillAmount) or 0)
		end
		local measured = Measured(npcId)
		if guids == 1 and total - overkill > 0 and measured then
			local level = MobLevel(npcId, next(fightGuids[npcId]))
			AddSample(measured.health, Factor(total - overkill, ns.BaseHealth(level, (MobClass(npcId)))))
			log.health[npcId] = total - overkill
			Debug(("Damage meter: %s took %d to kill (%d overkill)"):format(MobInfo(npcId).name or "?", total - overkill, overkill))
		end
	end

	local taken, mobSpells = nil, {} -- npcId -> names of its spells that hit us this fight
	ok, taken = pcall(meter.GetCombatSessionSourceFromType, current, types.DamageTaken, playerGUID)
	log.taken = ok and taken and Clean(taken.totalAmount) or nil
	for _, spell in ipairs(ok and taken and taken.combatSpells or {}) do
		local details = spell.combatSpellDetails or {}
		local spellId, amount = Clean(spell.spellID), Clean(spell.totalAmount)
		local mobName = Clean(details.unitName)
		local npcId = mobName and names[mobName]
		if npcId and Clean(details.isMob) and not Clean(details.isPet) and spellId and spellId > 0 and spellId ~= MELEE then
			local name = Clean(SpellName(spellId))
			if name then
				local entry = Study(npcId)
				entry.spells[name] = (entry.spells[name] or 0) + 1
				entry.spellIds[name] = spellId
				ns.LearnSpell(npcId, name, spellId) -- its cast time and description (account wide)
				local icon = C_Spell and C_Spell.GetSpellTexture and Clean(C_Spell.GetSpellTexture(spellId))
				if icon then
					entry.spellIcons[name] = icon
				end
				if amount then
					entry.spellDamage[name] = (entry.spellDamage[name] or 0) + amount
				end
				Debug(("Damage meter: %s hit you with %s (%s)"):format(mobName, name, tostring(amount)))
				mobSpells[npcId] = mobSpells[npcId] or {}
				tinsert(mobSpells[npcId], name)
				log.spells[npcId] = log.spells[npcId] or {}
				tinsert(log.spells[npcId], { name = name, id = spellId, damage = amount })
			end
		end
	end

	-- Spell hits per cast: the plain hits after its casts belong to its spell when only one of
	-- its spells hit us this fight (spells always hit full unless resisted: no armor to undo)
	for npcId, amounts in pairs(fightSpellHits) do
		local spells = mobSpells[npcId]
		local measured = Measured(npcId)
		if spells and #spells == 1 and measured then
			measured.spells[spells[1]] = measured.spells[spells[1]] or {}
			for _, factor in ipairs(amounts) do
				AddSample(measured.spells[spells[1]], factor)
			end
		end
	end
	return log
end

-- After a fight, as soon as the meter can be read; kills waiting for it are decided then
local function TryMeter()
	if not meterDue or CombatRestricted() then
		return
	end
	meterDue = false
	local ok, err = pcall(ReadMeter)
	local log = ok and err or {}
	ns.FightLog.Meter(log.spells, log.health, log.taken, log.done)
	wipe(fightMobs)
	wipe(fightGuids)
	wipe(fightKills)
	wipe(fightSpellHits)
	wipe(guidLevels)
	fightTapped = false
	if not ok then
		Debug("Damage meter: " .. tostring(err))
	end
	if ns.OnMeterRead then
		ns.OnMeterRead()
	end
end

-- Whether the fight's damage meter is still to be read (Cards.lua holds kills back until then)
function ns.MeterDue()
	return meterDue
end

local events = CreateFrame("Frame")
events:RegisterEvent("ADDON_LOADED")
events:RegisterEvent("PLAYER_REGEN_DISABLED")
pcall(events.RegisterEvent, events, "ADDON_RESTRICTION_STATE_CHANGED")
events:RegisterEvent("PARTY_KILL")
events:RegisterEvent("PLAYER_TARGET_CHANGED")
events:RegisterEvent("UPDATE_MOUSEOVER_UNIT")
events:RegisterEvent("NAME_PLATE_UNIT_ADDED")
events:RegisterEvent("NAME_PLATE_UNIT_REMOVED")
events:RegisterEvent("UNIT_SPELLCAST_START")
events:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED")
events:RegisterEvent("UNIT_SPELLCAST_CHANNEL_START")
events:RegisterEvent("PLAYER_REGEN_ENABLED")
events:RegisterEvent("UNIT_HEALTH")
events:RegisterEvent("UNIT_AURA")
events:RegisterEvent("UNIT_COMBAT")
events:RegisterEvent("LOOT_OPENED")
events:RegisterEvent("INSTANCE_ENCOUNTER_ENGAGE_UNIT")
-- A part that fails is switched off for this session instead of failing on every event (which
-- floods the game with errors); the error is kept for /bst errors.
local function Failed(what, err)
	local list = ns.errors
	local msg = ("Bestiary %s: %s"):format(what, tostring(err))
	for _, entry in ipairs(list) do
		if entry.msg == msg then
			entry.count = entry.count + 1
			return
		end
	end
	if #list < 20 then
		list[#list + 1] = { msg = msg, count = 1, at = time(), stack = debugstack and debugstack(2, 12, 0) or nil }
	end
	ns.Print(("|cffff6060Turned off %s after an error.|r Type /bst errors to see it."):format(what))
end

local function OnEvent(_, event, ...)
	if event == "ADDON_LOADED" then
		if ... == addonName then
			BestiaryChar = BestiaryChar or {}
			BestiaryChar.study = BestiaryChar.study or {}
			BestiaryChar.cards = BestiaryChar.cards or {}
			BestiaryChar.drops = BestiaryChar.drops or {}
			BestiaryAccount = BestiaryAccount or {}
			BestiaryAccount.mobs = BestiaryAccount.mobs or {}
			-- errors recorded before the saved variables were there
			BestiaryAccount.errors = BestiaryAccount.errors or {}
			for _, entry in ipairs(ns.errors) do
				tinsert(BestiaryAccount.errors, entry)
			end
			ns.errors = BestiaryAccount.errors
			-- Cards from older versions: combat types were called Armor and Magic
			for _, card in pairs(BestiaryChar.cards) do
				card.type = ({ Armor = "Tank", Magic = "Mage" })[card.type] or card.type
			end
			-- Study entries from older versions: fill in what's new
			for _, entry in pairs(BestiaryChar.study) do
				for key, value in pairs(ns.EmptyStudy()) do
					if entry[key] == nil then
						entry[key] = value
					end
				end
			end
			events:UnregisterEvent("ADDON_LOADED")
		end
	elseif not BestiaryChar then
		return
	elseif event == "PARTY_KILL" then
		OnPartyKill(...)
	elseif event == "PLAYER_TARGET_CHANGED" then
		CacheUnit("target")
		ScanBuffs("target")
		Watch("target")
	elseif event == "UNIT_AURA" then
		local unit = ...
		if unit == "player" then
			ScanPlayerDebuffs()
		elseif unit == "target" or unit == "focus" or unit == "mouseover" or nameplates[unit] then
			ScanBuffs(unit)
		end
	elseif event == "UNIT_COMBAT" then
		OnCombat(...)
	elseif event == "UNIT_HEALTH" then
		local unit = ...
		if unit == "target" or unit == "focus" or nameplates[unit] then
			Watch(unit)
		end
	elseif event == "LOOT_OPENED" then
		OnLoot()
	elseif event == "INSTANCE_ENCOUNTER_ENGAGE_UNIT" then
		for i = 1, 5 do
			CacheUnit("boss" .. i)
		end
	elseif event == "UPDATE_MOUSEOVER_UNIT" then
		CacheUnit("mouseover")
		ScanBuffs("mouseover")
	elseif event == "NAME_PLATE_UNIT_ADDED" then
		local unit = ...
		nameplates[unit] = true
		CacheUnit(unit)
		ScanBuffs(unit)
	elseif event == "NAME_PLATE_UNIT_REMOVED" then
		local unit = ...
		Watch(unit) -- nameplates of mobs that just died go away
		nameplates[unit] = nil
	elseif event == "UNIT_SPELLCAST_START" or event == "UNIT_SPELLCAST_SUCCEEDED" or event == "UNIT_SPELLCAST_CHANNEL_START" then
		OnCast(event, ...)
	elseif event == "PLAYER_REGEN_DISABLED" then
		if meterDue then -- the last fight's meter was never read: don't mix it into this one
			wipe(fightMobs)
			wipe(fightGuids)
			wipe(fightKills)
			wipe(fightSpellHits)
			fightTapped = false
		end
		meterDue = true
		ReadArmor()
		ns.FightLog.Start(playerArmor)
	elseif event == "ADDON_RESTRICTION_STATE_CHANGED" then
		TryMeter()
	elseif event == "PLAYER_REGEN_ENABLED" then
		WatchAll() -- the last mob may have died this moment
		ns.FightLog.End(Clean(UnitIsDeadOrGhost("player")) or nil)
		C_Timer.After(1, TryMeter) -- in case the restriction event doesn't come
		wipe(castDone)
		-- Forget what's long over (deaths stay a while so looting doesn't count them again)
		local now = GetTime()
		for guid, time in pairs(deathSeen) do
			if now - time > 900 then
				deathSeen[guid] = nil
			end
		end
		for key, time in pairs(castSeen) do
			if now - time > 60 then
				castSeen[key] = nil
			end
		end
		wipe(unkeyedCast)
		for guid, time in pairs(engaged) do
			if now - time > 300 then
				engaged[guid], tapDenied[guid] = nil, nil
			end
		end
	end
end

events:SetScript("OnEvent", function(self, event, ...)
	local ok, err = pcall(OnEvent, self, event, ...)
	if not ok then
		self:UnregisterEvent(event)
		Failed(event, err)
	end
end)

local studyTicker
studyTicker = C_Timer.NewTicker(ns.STUDY_TICK, function()
	if BestiaryChar then
		local ok, err = pcall(function()
			StudyTick()
			WatchAll()
			if not InCombatLockdown() then
				ReadArmor()
			end
		end)
		if not ok then
			studyTicker:Cancel()
			Failed("studying", err)
		end
	end
end)

-- The target's mob again while fighting (tapping can change after the first look)
local targetTicker
targetTicker = C_Timer.NewTicker(2, function()
	if BestiaryChar and Clean(UnitAffectingCombat("player")) then
		local ok, err = pcall(CacheUnit, "target")
		if not ok then
			targetTicker:Cancel()
			Failed("target checks", err)
		end
	end
end)

function ns.Studied(npcId)
	return BestiaryChar.study[npcId]
end

function ns.DebugReport(npcId)
	local entry = BestiaryChar.study[npcId]
	local info = MobInfo(npcId)
	if not entry and not info then
		ns.Print("Nothing known about that mob yet.")
		return
	end
	ns.Print(("%s (npc %d): %s, %s, level %s"):format(
		(info and info.name) or (entry and entry.name) or "?", npcId,
		info and info.classification or "classification unknown",
		info and tostring(info.creatureType) or "type unknown",
		info and tostring(info.level) or "?"))
	if entry then
		ns.Print(("  hit you with %d spells and %d melee hits, %d poisons"):format(entry.magicHits or 0,
			entry.physicalHits or 0, entry.poisons or 0))
		ns.Print(("  studied %d%%, %d casts (%d heals), mana %s, class %s, attack speed %s"):format(
			math.min(100, entry.seconds / ns.STUDY_SECONDS * 100), entry.casts, entry.heals, entry.mana and "yes" or "no",
			tostring(entry.class), entry.attackSpeed and ("%.1f s"):format(entry.attackSpeed) or "?"))
		local spells = {}
		for spell, count in pairs(entry.spells) do
			spells[#spells + 1] = ("%s x%d%s"):format(spell, count, entry.spellIds[spell] and (" #" .. entry.spellIds[spell]) or "")
		end
		ns.Print("  spells: " .. (#spells > 0 and table.concat(spells, ", ") or "none seen"))
		if ns.BuildCard then
			local card = ns.BuildCard(npcId)
			if card then
				ns.Print(("  card would be: %s %s, power %d"):format(card.type, ns.RARITIES[card.classification].name, card.power))
			end
		end
	end
end
