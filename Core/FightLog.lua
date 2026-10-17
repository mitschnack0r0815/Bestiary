local _, ns = ...

-- The fight database (ARCHITECTURE.md 4.0): one record per fight, account wide in
-- BestiaryAccount.fights (the newest MAX_FIGHTS), so we can learn from the data later: how hard
-- mobs hit at which level, against which armor, which spells they use, how much health they
-- have. The tracker feeds it; the damage meter part is added once the meter can be read after
-- the fight. /bst fights (or the Test tab) shows it as text to copy out.
--
-- A record:
--   at, zone, subzone, seconds, me = { level, class, armor, group, died }
--   mobs[npcId] = { name, level (lowest seen), top (highest), class, rarity, attackSpeed,
--                   seen (mobs of that type), kills, casts, resists,
--                   spells[name] = { id, damage } (from the damage meter), health (if measured) }
--   hits = { { t, npcId (0: unknown), school, amount, flag }, ... } every hit on us, in order
--   meter = { taken, done } totals, if the meter was read
local FightLog = {}
ns.FightLog = FightLog

local MAX_FIGHTS = 500
local MAX_HITS = 300 -- hits kept per fight

local current -- the record being filled, nil outside fights
local started -- GetTime() at its start
local guids -- GUID -> true of the mobs in it

local function Save()
	if not current then
		return
	end
	local list = BestiaryAccount.fights
	if next(current.mobs) or #current.hits > 0 then
		list[#list + 1] = current
		while #list > MAX_FIGHTS do
			table.remove(list, 1)
		end
	end
	current = nil
end

function FightLog.Start(armor)
	if not BestiaryAccount then
		return
	end
	BestiaryAccount.fights = BestiaryAccount.fights or {}
	Save() -- the last one, if its meter was never read
	local _, class = UnitClass("player")
	current = {
		at = time(), zone = GetRealZoneText and GetRealZoneText() or "", subzone = GetSubZoneText and GetSubZoneText() or "",
		me = { level = UnitLevel("player"), class = class, armor = armor,
			group = IsInRaid() and "raid" or IsInGroup() and "party" or "solo" },
		mobs = {}, hits = {},
	}
	started, guids = GetTime(), {}
end

local function Mob(npcId)
	if not current or not npcId then
		return
	end
	local mob = current.mobs[npcId]
	if not mob then
		mob = { seen = 0, kills = 0, casts = 0, resists = 0, spells = {} }
		current.mobs[npcId] = mob
	end
	local info = BestiaryAccount.mobs[npcId]
	if info then
		mob.name, mob.class, mob.rarity, mob.attackSpeed = info.name, info.class, info.classification, info.attackSpeed
	end
	return mob
end

-- A mob fighting us, with its own level if known
function FightLog.Mob(npcId, guid, level)
	local mob = Mob(npcId)
	if not mob then
		return
	end
	if guid and not guids[guid] then
		guids[guid] = true
		mob.seen = mob.seen + 1
	end
	if level and level ~= 0 then
		mob.level = math.min(mob.level or level, level)
		mob.top = math.max(mob.top or level, level)
	end
end

-- A hit on us: npcId of who we think it was (nil: unknown), school bit mask, flag as UNIT_COMBAT
-- gives it ("" plain, CRITICAL, CRUSHING, GLANCING, BLOCK, RESIST...)
function FightLog.Hit(npcId, school, amount, flag)
	if not current or #current.hits >= MAX_HITS then
		return
	end
	current.hits[#current.hits + 1] = { math.floor((GetTime() - started) * 10 + 0.5) / 10, npcId or 0, school, amount, flag or "" }
end

function FightLog.Count(npcId, what)
	local mob = Mob(npcId)
	if mob then
		mob[what] = mob[what] + 1
	end
end

-- Combat is over (the meter may still be locked)
function FightLog.End(died)
	if current and not current.seconds then
		current.seconds = math.floor(GetTime() - started + 0.5)
		current.me.died = died or nil
	end
end

-- What the damage meter said; then the record is done
function FightLog.Meter(spells, health, taken, done)
	if current then
		for npcId, list in pairs(spells or {}) do
			local mob = Mob(npcId)
			for _, spell in ipairs(list) do
				mob.spells[spell.name] = { id = spell.id, damage = (mob.spells[spell.name] and mob.spells[spell.name].damage or 0) + (spell.damage or 0) }
			end
		end
		for npcId, amount in pairs(health or {}) do
			Mob(npcId).health = amount
		end
		current.meter = { taken = taken, done = done }
	end
	FightLog.End()
	Save()
end

-- Everything as text, one block per fight, newest last
local SCHOOLS = { [1] = "physical", [2] = "holy", [4] = "fire", [8] = "nature", [16] = "frost", [32] = "shadow", [64] = "arcane" }

function FightLog.Text()
	local lines = {}
	local list = BestiaryAccount.fights or {}
	lines[#lines + 1] = ("Bestiary fight log: %d fights (newest %d kept)"):format(#list, MAX_FIGHTS)
	for i, fight in ipairs(list) do
		local me = fight.me
		lines[#lines + 1] = ""
		lines[#lines + 1] = ("#%d %s  %s%s  %ss  me: level %s %s, armor %s, %s%s%s"):format(i,
			date("%Y-%m-%d %H:%M", fight.at), fight.zone, fight.subzone ~= "" and (" / " .. fight.subzone) or "",
			tostring(fight.seconds or "?"), tostring(me.level), tostring(me.class), tostring(me.armor), me.group,
			me.died and ", died" or "",
			fight.meter and (", meter: took %s, did %s"):format(tostring(fight.meter.taken), tostring(fight.meter.done)) or "")
		for npcId, mob in pairs(fight.mobs) do
			local spells = {}
			for name, spell in pairs(mob.spells) do
				spells[#spells + 1] = ("%s %d (%d)"):format(name, spell.id or 0, spell.damage or 0)
			end
			lines[#lines + 1] = ("  mob %d %s  level %s%s %s %s  speed %s  seen %d, killed %d, casts %d, resists %d%s%s"):format(
				npcId, tostring(mob.name), tostring(mob.level), mob.top and mob.top ~= mob.level and ("-" .. mob.top) or "",
				tostring(mob.rarity), tostring(mob.class), tostring(mob.attackSpeed), mob.seen, mob.kills, mob.casts,
				mob.resists, mob.health and ("  health " .. mob.health) or "",
				#spells > 0 and ("  spells: " .. table.concat(spells, ", ")) or "")
		end
		local hits = {}
		for _, hit in ipairs(fight.hits) do
			hits[#hits + 1] = ("%.1f:%d:%s:%d%s"):format(hit[1], hit[2], SCHOOLS[hit[3]] or tostring(hit[3]), hit[4] or 0,
				hit[5] ~= "" and (":" .. hit[5]) or "")
		end
		if #hits > 0 then
			lines[#lines + 1] = "  hits (seconds:npc:school:amount:flag): " .. table.concat(hits, " ")
		end
	end
	return table.concat(lines, "\n")
end

function FightLog.Show()
	if ns.ShowDump then
		ns.ShowDump(FightLog.Text())
	end
end

function FightLog.Clear()
	BestiaryAccount.fights = {}
	current = nil
end
