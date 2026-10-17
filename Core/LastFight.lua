local _, ns = ...

-- PROTOTYPE: everything this client lets an addon find out about the last fight, for the Test
-- page's "Dump last fight" button (and /bst lastfight).
--   * while fighting: our own casts (never secret), UNIT_COMBAT on us / target / pet, casts of
--     other units (secret for anything that isn't us or our pet), mobs on nameplates, kills,
--     restriction changes, damage meter updates
--   * chat messages during the fight and up to AFTER_SECONDS after it (XP, loot, money, rep, skill)
--   * snapshots of us before and after (health, power, XP, money, durability, auras), and of the
--     target right after (usually the corpse)
--   * when dumped: Blizzard's damage meter (C_DamageMeter, every meter type, every source, every
--     spell) and the death recap. Both are secret in combat, so dump after the fight.
-- Every value goes through Show(), so secrets print as <secret> and are never compared.
-- The dump is shown in a copyable window and saved to BestiaryAccount.lastFightDump.

local MAX_EVENTS = 400
local AFTER_SECONDS = 15

local fight -- the fight being recorded, or the last one
local lastFight

local function IsSecret(value)
	return issecretvalue and issecretvalue(value) or false
end

local function Plain(value)
	if IsSecret(value) then
		return nil
	end
	return value
end

local function SpellName(spellId)
	spellId = Plain(spellId)
	if type(spellId) ~= "number" then
		return nil
	end
	local name
	if C_Spell and C_Spell.GetSpellName then
		name = C_Spell.GetSpellName(spellId)
	elseif GetSpellInfo then
		name = GetSpellInfo(spellId)
	end
	return Plain(name)
end

local function Show(value)
	if IsSecret(value) then
		return "<secret>"
	end
	if type(value) == "string" then
		return ("%q"):format(value)
	end
	return tostring(value)
end

local function Clock()
	return fight and ("%6.1f"):format(GetTime() - fight.start) or "     ?"
end

local function Log(list, text)
	if fight and #list < MAX_EVENTS then
		list[#list + 1] = Clock() .. "  " .. text
	end
end

-- Snapshots ------------------------------------------------------------------------------------

local function Durability()
	local current, max = 0, 0
	for slot = 1, 18 do
		local c, m = GetInventoryItemDurability(slot)
		c, m = Plain(c), Plain(m)
		if c and m then
			current, max = current + c, max + m
		end
	end
	return current, max
end

local AURA_FIELDS = { "name", "spellId", "sourceUnit", "applications", "duration", "expirationTime",
	"dispelName", "isHarmful", "isFromPlayerOrPlayerPet", "isStealable", "auraInstanceID" }

local function Auras(unit, filter)
	local lines = {}
	if not (C_UnitAuras and C_UnitAuras.GetAuraDataByIndex) then
		return { "C_UnitAuras.GetAuraDataByIndex missing" }
	end
	for i = 1, 40 do
		local ok, aura = pcall(C_UnitAuras.GetAuraDataByIndex, unit, i, filter)
		if not ok then
			lines[#lines + 1] = "error: " .. tostring(aura)
			break
		end
		if not aura then
			break
		end
		local parts = {}
		for _, field in ipairs(AURA_FIELDS) do
			parts[#parts + 1] = field .. "=" .. Show(aura[field])
		end
		local source = Plain(aura.sourceUnit)
		if source then
			local guid = Plain(UnitGUID(source))
			parts[#parts + 1] = "sourceGUID=" .. Show(guid) .. " sourceName=" .. Show(UnitName(source))
		end
		lines[#lines + 1] = table.concat(parts, " ")
	end
	return lines
end

local function Snapshot()
	local current, max = Durability()
	return {
		health = Plain(UnitHealth("player")), healthMax = Plain(UnitHealthMax("player")),
		power = Plain(UnitPower("player")), powerMax = Plain(UnitPowerMax("player")),
		xp = Plain(UnitXP("player")), xpMax = Plain(UnitXPMax("player")), level = Plain(UnitLevel("player")),
		money = Plain(GetMoney()), durability = current, durabilityMax = max,
		buffs = Auras("player", "HELPFUL"), debuffs = Auras("player", "HARMFUL"),
	}
end

local UNIT_FIELDS = {
	{ "name", UnitName }, { "guid", UnitGUID }, { "level", UnitLevel }, { "classification", UnitClassification },
	{ "creatureType", UnitCreatureType }, { "creatureFamily", UnitCreatureFamily }, { "dead", UnitIsDead },
	{ "tapDenied", UnitIsTapDenied }, { "health", UnitHealth }, { "healthMax", UnitHealthMax },
	{ "powerType", UnitPowerType }, { "class", UnitClass }, { "attackSpeed", UnitAttackSpeed },
	{ "inCombat", UnitAffectingCombat }, { "damageMin", UnitDamage }, { "damageMax", function(unit) return select(2, UnitDamage(unit)) end },
	{ "armor", function(unit) return select(2, UnitArmor(unit)) end },
	{ "natureResist", function(unit) return select(3, UnitResistance(unit, 3)) end },{ "reaction", function(unit) return UnitReaction(unit, "player") end },
}

local function DescribeUnit(unit)
	if not UnitExists(unit) then
		return { unit .. ": none" }
	end
	local parts = {}
	for _, field in ipairs(UNIT_FIELDS) do
		local ok, value = pcall(field[2], unit)
		parts[#parts + 1] = field[1] .. "=" .. (ok and Show(value) or "error")
	end
	local guid = Plain(UnitGUID(unit))
	parts[#parts + 1] = "npcId=" .. Show(guid and ns.NpcId(guid))
	local lines = { unit .. ": " .. table.concat(parts, " ") }
	for _, line in ipairs(Auras(unit, "HELPFUL")) do
		lines[#lines + 1] = "  buff " .. line
	end
	for _, line in ipairs(Auras(unit, "HARMFUL")) do
		lines[#lines + 1] = "  debuff " .. line
	end
	return lines
end

-- Recording ------------------------------------------------------------------------------------

local function StartFight()
	fight = {
		start = GetTime(), date = date("%Y-%m-%d %H:%M:%S"), before = Snapshot(),
		ownCasts = {}, otherCasts = {}, hits = {}, chat = {}, nameplates = {}, misc = {},
		otherCastCount = 0, otherCastSecret = 0, meterUpdates = 0, seenPlates = {},
	}
	lastFight = fight
	for i = 1, 40 do
		local unit = "nameplate" .. i
		if UnitExists(unit) then
			fight.seenPlates[unit] = true
			Log(fight.nameplates, "already there: " .. DescribeUnit(unit)[1])
		end
	end
end

local function EndFight()
	if not fight then
		return
	end
	fight.stop = GetTime()
	fight.after = Snapshot()
	fight.target = DescribeUnit("target")
	fight.recording = nil
end

local function InFight()
	return fight and not fight.stop
end

-- Chat after the fight still belongs to it for a while (XP and loot come after the kill)
local function FightForChat()
	if fight and (not fight.stop or GetTime() - fight.stop < AFTER_SECONDS) then
		return fight
	end
end

local CHAT = {
	CHAT_MSG_COMBAT_XP_GAIN = "xp", CHAT_MSG_LOOT = "loot", CHAT_MSG_MONEY = "money",
	CHAT_MSG_COMBAT_FACTION_CHANGE = "rep", CHAT_MSG_SKILL = "skill", CHAT_MSG_COMBAT_HONOR_GAIN = "honor",
	CHAT_MSG_SYSTEM = "system", CHAT_MSG_MONSTER_SAY = "mob says", CHAT_MSG_MONSTER_YELL = "mob yells",
	CHAT_MSG_MONSTER_EMOTE = "mob emote", CHAT_MSG_TEXT_EMOTE = "emote",
}

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_REGEN_DISABLED")
events:RegisterEvent("PLAYER_REGEN_ENABLED")
events:RegisterEvent("UNIT_SPELLCAST_START")
events:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED")
events:RegisterEvent("UNIT_SPELLCAST_CHANNEL_START")
events:RegisterEvent("UNIT_SPELLCAST_INTERRUPTED")
events:RegisterEvent("UNIT_COMBAT")
events:RegisterEvent("NAME_PLATE_UNIT_ADDED")
events:RegisterEvent("PARTY_KILL")
events:RegisterEvent("PLAYER_DEAD")
events:RegisterEvent("ADDON_RESTRICTION_STATE_CHANGED")
events:RegisterEvent("DAMAGE_METER_COMBAT_SESSION_UPDATED")
events:RegisterEvent("DAMAGE_METER_CURRENT_SESSION_UPDATED")
for event in pairs(CHAT) do
	events:RegisterEvent(event)
end

local function OnEvent(_, event, ...)
	if event == "PLAYER_REGEN_DISABLED" then
		StartFight()
	elseif event == "PLAYER_REGEN_ENABLED" then
		EndFight()
	elseif CHAT[event] then
		if FightForChat() then
			local message, sender = ...
			local from = IsSecret(sender) and " from <secret>" or (sender and sender ~= "" and (" from " .. Show(sender))) or ""
			Log(fight.chat, ("%-9s %s%s"):format(CHAT[event], Show(message), from))
		end
	elseif not fight then
		return
	elseif event == "ADDON_RESTRICTION_STATE_CHANGED" then
		local kind, state = ...
		Log(fight.misc, ("restriction type %s -> state %s"):format(Show(kind), Show(state)))
		-- PLAYER_REGEN_ENABLED comes while the combat restriction is still on (health was secret
		-- then): take the after snapshot again once it's lifted
		if fight.stop and Plain(kind) == 0 and Plain(state) == 0 then
			fight.after = Snapshot()
			fight.target = DescribeUnit("target")
		end
	elseif not InFight() then
		return
	elseif event == "UNIT_SPELLCAST_START" or event == "UNIT_SPELLCAST_SUCCEEDED"
		or event == "UNIT_SPELLCAST_CHANNEL_START" or event == "UNIT_SPELLCAST_INTERRUPTED" then
		local unit, castGUID, spellId = ...
		local short = event:gsub("UNIT_SPELLCAST_", "")
		if unit == "player" or unit == "pet" then
			Log(fight.ownCasts, ("%-6s %-12s spell %s %s"):format(unit, short, Show(spellId), Show(SpellName(spellId))))
		else
			fight.otherCastCount = fight.otherCastCount + 1
			if IsSecret(spellId) then
				fight.otherCastSecret = fight.otherCastSecret + 1
			end
			Log(fight.otherCasts, ("%-12s %-12s spell %s %s castGUID %s castBar %s"):format(Show(unit), short,
				Show(spellId), Show(SpellName(spellId)), Show(castGUID), Show(UnitCastingInfo(unit))))
		end
	elseif event == "UNIT_COMBAT" then
		local unit, action, flag, amount, school = ...
		if unit == "player" or unit == "target" or unit == "pet" then
			Log(fight.hits, ("%-6s %s %s amount %s school %s"):format(Show(unit), Show(action), Show(flag),
				Show(amount), Show(school)))
		end
	elseif event == "NAME_PLATE_UNIT_ADDED" then
		local unit = ...
		Log(fight.nameplates, DescribeUnit(unit)[1])
	elseif event == "PARTY_KILL" then
		local attacker, target = ...
		Log(fight.misc, ("PARTY_KILL attacker %s target %s"):format(Show(attacker), Show(target)))
	elseif event == "PLAYER_DEAD" then
		Log(fight.misc, "PLAYER_DEAD")
	elseif event == "DAMAGE_METER_COMBAT_SESSION_UPDATED" or event == "DAMAGE_METER_CURRENT_SESSION_UPDATED" then
		fight.meterUpdates = fight.meterUpdates + 1
	end
end

events:SetScript("OnEvent", function(self, event, ...)
	local ok, err = pcall(OnEvent, self, event, ...)
	if not ok and ns.debug then
		ns.Print("last fight recorder: " .. tostring(err))
	end
end)

-- Dumping --------------------------------------------------------------------------------------

local dumpedSpells -- spell ids met while dumping, for the spell data section

-- Any value, tables included, secrets as <secret>; spell ids get their name
local function DumpValue(lines, indent, key, value, depth)
	if IsSecret(value) or type(value) ~= "table" then
		local extra = ""
		if (key == "spellID" or key == "spellId") and SpellName(value) then
			extra = "  -- " .. SpellName(value)
			if dumpedSpells and Plain(value) and value > 0 then
				dumpedSpells[value] = true
			end
		end
		lines[#lines + 1] = indent .. key .. " = " .. Show(value) .. extra
		return
	end
	if depth > 6 then
		lines[#lines + 1] = indent .. key .. " = {...}"
		return
	end
	local keys = {}
	for k in pairs(value) do
		keys[#keys + 1] = k
	end
	pcall(table.sort, keys, function(a, b)
		if type(a) == "number" and type(b) == "number" then
			return a < b
		end
		return tostring(a) < tostring(b)
	end)
	if #keys == 0 then
		lines[#lines + 1] = indent .. key .. " = {}"
		return
	end
	lines[#lines + 1] = indent .. key .. " = {"
	for _, k in ipairs(keys) do
		DumpValue(lines, indent .. "  ", IsSecret(k) and "<secret key>" or tostring(k), value[k], depth + 1)
	end
	lines[#lines + 1] = indent .. "}"
end

local function EnumNames(enum)
	local list = {}
	for name, value in pairs(enum or {}) do
		if type(value) == "number" then
			list[#list + 1] = { name = name, value = value }
		end
	end
	table.sort(list, function(a, b) return a.value < b.value end)
	return list
end

local function DumpMeter(Add, lines)
	local meter = C_DamageMeter
	if not meter then
		Add("C_DamageMeter does not exist on this client")
		return
	end
	local ok, available, reason = pcall(meter.IsDamageMeterAvailable)
	Add(("IsDamageMeterAvailable: %s %s"):format(Show(available), Show(reason)))
	local sessions
	ok, sessions = pcall(meter.GetAvailableCombatSessions)
	local newest
	if ok and type(sessions) == "table" then
		for _, session in ipairs(sessions) do
			Add(("session id %s name %s duration %s"):format(Show(session.sessionID), Show(session.name),
				Show(session.durationSeconds)))
			local id = Plain(session.sessionID)
			if id and (not newest or id > newest) then
				newest = id
			end
		end
		if #sessions == 0 then
			Add("no sessions")
		end
	else
		Add("GetAvailableCombatSessions failed: " .. tostring(sessions))
	end
	local current = Enum.DamageMeterSessionType and Enum.DamageMeterSessionType.Current or 1
	Add("current session duration: " .. Show(select(2, pcall(meter.GetSessionDurationSeconds, current))))

	for _, kind in ipairs(EnumNames(Enum.DamageMeterType)) do
		-- the current session; if that's empty, the newest one by id
		local how = "Current"
		local okSession, session = pcall(meter.GetCombatSessionFromType, current, kind.value)
		local sources = okSession and type(session) == "table" and session.combatSources
		if (not sources or #sources == 0) and newest then
			how = "session " .. newest
			okSession, session = pcall(meter.GetCombatSessionFromID, newest, kind.value)
			sources = okSession and type(session) == "table" and session.combatSources
		end
		Add("")
		Add(("== %s (%d), %s"):format(kind.name, kind.value, how))
		if not okSession then
			Add("  error: " .. tostring(session))
		elseif not sources or #sources == 0 then
			Add("  no sources")
		else
			Add(("  total %s max %s duration %s"):format(Show(session.totalAmount), Show(session.maxAmount),
				Show(session.durationSeconds)))
			for i, source in ipairs(sources) do
				DumpValue(lines, "  ", "source " .. i, source, 0)
				local guid, creatureId = Plain(source.sourceGUID), Plain(source.sourceCreatureID)
				local okSource, detail
				if how == "Current" then
					okSource, detail = pcall(meter.GetCombatSessionSourceFromType, current, kind.value, guid, creatureId)
				else
					okSource, detail = pcall(meter.GetCombatSessionSourceFromID, newest, kind.value, guid, creatureId)
				end
				if okSource then
					DumpValue(lines, "    ", "spells of source " .. i, detail, 0)
				else
					Add("    spells of source " .. i .. ": error " .. tostring(detail))
				end
				local recap = Plain(source.deathRecapID)
				if recap and recap ~= 0 and C_DeathRecap then
					local okRecap, recapEvents = pcall(C_DeathRecap.GetRecapEvents, recap)
					DumpValue(lines, "    ", "death recap " .. recap, okRecap and recapEvents or tostring(recapEvents), 0)
				end
			end
		end
	end
end

local function Diff(label, before, after)
	if before and after then
		return ("%s %s -> %s (%+d)"):format(label, before, after, after - before)
	end
	return ("%s %s -> %s"):format(label, Show(before), Show(after))
end

function ns.DumpLastFight()
	dumpedSpells = {}
	local lines = {}
	local function Add(text)
		lines[#lines + 1] = text
	end
	local function Section(title)
		Add("")
		Add("######## " .. title)
	end
	local function Each(list, empty)
		if #list == 0 then
			Add(empty or "(none)")
		end
		for _, line in ipairs(list) do
			Add(line)
		end
		if #list >= MAX_EVENTS then
			Add(("(stopped at %d)"):format(MAX_EVENTS))
		end
	end

	local f = lastFight
	Add("Bestiary: last fight dump, made " .. date("%Y-%m-%d %H:%M:%S") .. ", client " .. Show(select(4, GetBuildInfo())))
	Add("InCombatLockdown " .. Show(InCombatLockdown()) .. "  UnitAffectingCombat " .. Show(UnitAffectingCombat("player")))
	if C_RestrictedActions and C_RestrictedActions.IsAddOnRestrictionActive then
		local states = {}
		for _, kind in ipairs(EnumNames(Enum.AddOnRestrictionType)) do
			local ok, active = pcall(C_RestrictedActions.IsAddOnRestrictionActive, kind.value)
			states[#states + 1] = kind.name .. "=" .. (ok and Show(active) or "error")
		end
		Add("restrictions: " .. table.concat(states, " "))
	end
	if InCombatLockdown() then
		Add("!! still in combat: the damage meter and many values below are secret. Dump again after the fight.")
	end

	if f then
		Section("Fight")
		Add(("started %s, lasted %s s%s"):format(f.date, f.stop and ("%.1f"):format(f.stop - f.start) or "?",
			f.stop and "" or " (still going)"))
		local b, a = f.before, f.after
		if a then
			Add(Diff("health", b.health, a.health) .. " of " .. Show(a.healthMax))
			Add(Diff("power", b.power, a.power) .. " of " .. Show(a.powerMax))
			Add(Diff("xp", b.xp, a.xp) .. " of " .. Show(a.xpMax) .. ", level " .. Show(b.level) .. " -> " .. Show(a.level))
			Add(Diff("money (copper)", b.money, a.money))
			Add(Diff("durability", b.durability, a.durability) .. " of " .. Show(a.durabilityMax))
		end
		Add(("damage meter update events during the fight: %d"):format(f.meterUpdates))

		Section("Chat during and " .. AFTER_SECONDS .. " s after (XP, loot, money, rep, skill, mob talk)")
		Each(f.chat)
		Section("Kills, deaths, restriction changes")
		Each(f.misc)
		Section("Our own casts (player, pet)")
		Each(f.ownCasts)
		Section(("Casts of other units: %d events, %d with a secret spell id"):format(f.otherCastCount, f.otherCastSecret))
		Each(f.otherCasts)
		Section("UNIT_COMBAT (hits on player, target, pet)")
		Each(f.hits)
		Section("Nameplates that showed up")
		Each(f.nameplates)
		Section("Our debuffs before / after (after = readable once out of combat)")
		Each(b.debuffs, "before: none")
		if a then
			Each(a.debuffs, "after: none")
		end
		Section("Our buffs after")
		if a then
			Each(a.buffs)
		end
		Section("Target right after the fight")
		Each(f.target or {}, "fight not over")
	else
		Section("Fight")
		Add("No fight recorded since login or /reload.")
	end

	Section("Target now")
	Each(DescribeUnit("target"))

	Section("Damage meter (C_DamageMeter)")
	local ok, err = pcall(DumpMeter, Add, lines)
	if not ok then
		Add("error: " .. tostring(err))
	end

	-- What the game's spell data says about the spells above (cards use the cast time and the
	-- damage numbers in the description)
	Section("Spell data (C_Spell) of the spells above")
	local ids = {}
	for id in pairs(dumpedSpells or {}) do
		ids[#ids + 1] = id
	end
	table.sort(ids)
	for _, id in ipairs(ids) do
		local okInfo, spellInfo = pcall(C_Spell.GetSpellInfo, id)
		local okText, text = pcall(C_Spell.GetSpellDescription, id)
		local okSub, subtext = pcall(C_Spell.GetSpellSubtext, id)
		local low, high = ns.ParseSpellDamage(okText and Plain(text) or nil)
		Add(("%d %s  castTime %s ms  range %s-%s  subtext %s"):format(id, Show(okInfo and spellInfo and spellInfo.name),
			Show(okInfo and spellInfo and spellInfo.castTime), Show(okInfo and spellInfo and spellInfo.minRange),
			Show(okInfo and spellInfo and spellInfo.maxRange), Show(okSub and subtext or nil)))
		Add(("    description %s"):format(Show(okText and text or nil)))
		Add(("    damage read from it: %s"):format(low and ("%d to %d"):format(low, high) or "none"))
	end
	if #ids == 0 then
		Add("no spells")
	end

	Section("Death recap (most recent)")
	if C_DeathRecap then
		local okHas, has = pcall(C_DeathRecap.HasRecapEvents)
		Add("HasRecapEvents " .. Show(has))
		if okHas and Plain(has) then
			local okEvents, recap = pcall(C_DeathRecap.GetRecapEvents)
			DumpValue(lines, "", "events", okEvents and recap or tostring(recap), 0)
		end
	else
		Add("C_DeathRecap does not exist on this client")
	end

	local text = table.concat(lines, "\n")
	BestiaryAccount.lastFightDump = text
	ns.ShowDump(text)
	ns.Print(("Last fight dumped: %d lines (also saved for the next /reload)."):format(#lines))
end

-- The window -----------------------------------------------------------------------------------

local dump

function ns.ShowDump(text)
	if not dump then
		dump = CreateFrame("Frame", "BestiaryFightDump", UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
		dump:SetSize(760, 520)
		dump:SetPoint("CENTER")
		dump:SetFrameStrata("DIALOG")
		dump:SetMovable(true)
		dump:EnableMouse(true)
		dump:RegisterForDrag("LeftButton")
		dump:SetScript("OnDragStart", dump.StartMoving)
		dump:SetScript("OnDragStop", dump.StopMovingOrSizing)
		if dump.SetBackdrop then
			dump:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
				edgeSize = 14, insets = { left = 3, right = 3, top = 3, bottom = 3 } })
			dump:SetBackdropColor(0.05, 0.05, 0.05, 0.95)
		end
		tinsert(UISpecialFrames, "BestiaryFightDump")
		local title = dump:CreateFontString(nil, "OVERLAY", "GameFontNormal")
		title:SetPoint("TOPLEFT", 12, -10)
		title:SetText("Last fight  |cff999999Ctrl+A, Ctrl+C to copy. Also in BestiaryAccount.lastFightDump.|r")
		local close = CreateFrame("Button", nil, dump, "UIPanelCloseButton")
		close:SetPoint("TOPRIGHT", 0, 0)
		local scroll = CreateFrame("ScrollFrame", nil, dump, "UIPanelScrollFrameTemplate")
		scroll:SetPoint("TOPLEFT", 10, -32)
		scroll:SetPoint("BOTTOMRIGHT", -30, 10)
		local edit = CreateFrame("EditBox", nil, scroll)
		edit:SetMultiLine(true)
		edit:SetAutoFocus(false)
		edit:SetFontObject(ChatFontNormal)
		edit:SetWidth(710)
		edit:SetScript("OnEscapePressed", function() dump:Hide() end)
		scroll:SetScrollChild(edit)
		dump.edit = edit
	end
	dump.edit:SetText(text)
	dump.edit:SetCursorPosition(0)
	dump:Show()
end
