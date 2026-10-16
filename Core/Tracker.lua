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
		RecordStyle(unit, entry)
		ReadCastBar(unit, guid, npcId)
		local before = entry.seconds
		entry.seconds = entry.seconds + ns.STUDY_TICK
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

local events = CreateFrame("Frame")
events:RegisterEvent("ADDON_LOADED")
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
events:RegisterEvent("LOOT_OPENED")
events:RegisterEvent("INSTANCE_ENCOUNTER_ENGAGE_UNIT")
events:SetScript("OnEvent", function(_, event, ...)
	if event == "ADDON_LOADED" then
		if ... == addonName then
			BestiaryChar = BestiaryChar or {}
			BestiaryChar.study = BestiaryChar.study or {}
			BestiaryChar.cards = BestiaryChar.cards or {}
			BestiaryChar.drops = BestiaryChar.drops or {}
			BestiaryAccount = BestiaryAccount or {}
			BestiaryAccount.mobs = BestiaryAccount.mobs or {}
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
		Watch("target")
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
	elseif event == "NAME_PLATE_UNIT_ADDED" then
		local unit = ...
		nameplates[unit] = true
		CacheUnit(unit)
	elseif event == "NAME_PLATE_UNIT_REMOVED" then
		local unit = ...
		Watch(unit) -- nameplates of mobs that just died go away
		nameplates[unit] = nil
	elseif event == "UNIT_SPELLCAST_START" or event == "UNIT_SPELLCAST_SUCCEEDED" or event == "UNIT_SPELLCAST_CHANNEL_START" then
		OnCast(event, ...)
	elseif event == "PLAYER_REGEN_ENABLED" then
		WatchAll() -- the last mob may have died this moment
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
end)

C_Timer.NewTicker(ns.STUDY_TICK, function()
	if BestiaryChar then
		StudyTick()
		WatchAll()
	end
end)

-- The target's mob again while fighting (tapping can change after the first look)
C_Timer.NewTicker(2, function()
	if BestiaryChar and Clean(UnitAffectingCombat("player")) then
		CacheUnit("target")
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
