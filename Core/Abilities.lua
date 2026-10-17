local _, ns = ...

-- Mob abilities (ARCHITECTURE.md 5.2, decided 2026-10-17): stuns, fears, silences, disarms and
-- roots, slows, poisons and enrages that mobs use, learned from what the game shows and put on
-- their cards. At most MAX_ABILITIES per card (the strongest). Learned from:
--   * the loss of control alert (C_LossOfControl, for us readable even in combat): the type,
--     spell and duration; credited to the mob that just finished a cast, else the one
--     attacking us
--   * the descriptions of the mob's spells we know ("stuns the target for 2 sec", "reduces
--     movement speed")
--   * mob emotes ("becomes enraged", "goes into a frenzy")
--   * poisons and diseases it left on us (the tracker counts them)
-- Saved per mob account wide: BestiaryAccount.mobs[npcId].abilities[key] = { duration, spell,
-- spellId, icon, source }. The fight (Fight.lua) has a hook for each effect.
ns.MAX_ABILITIES = 4

-- code: one letter on the wire and in moves; power: what it adds to the card's power (share of
-- its strength); passive ones work by themselves, the others are an action with a cooldown
ns.ABILITIES = {
	stun = { name = "Stun", code = "s", icon = "Interface\\Icons\\Spell_Holy_SealOfMight", duration = 3, cooldown = 20, power = 0.15,
		text = "Stuns: the target's next turn comes %s s later." },
	fear = { name = "Fear", code = "f", icon = "Interface\\Icons\\Spell_Shadow_Possession", duration = 4, cooldown = 20, power = 0.10,
		text = "Fears: the target's next turn comes %s s later, but any damage breaks it." },
	silence = { name = "Silence", code = "i", icon = "Interface\\Icons\\Ability_Kick", duration = 4, cooldown = 20, power = 0.10,
		text = "Silences: the target can't cast or heal for %s s." },
	disarm = { name = "Disarm", code = "r", icon = "Interface\\Icons\\Ability_Warrior_Disarm", duration = 5, cooldown = 20, power = 0.05,
		text = "Disarms or roots: the target can't attack for %s s." },
	slow = { name = "Slow", code = "w", icon = "Interface\\Icons\\Spell_Frost_FrostShock", duration = 10, cooldown = 15, power = 0.05,
		text = "Slows: the target's turns come 30%% slower for %s s." },
	poison = { name = "Poison", code = "p", icon = "Interface\\Icons\\Spell_Nature_NullifyPoison", duration = 10, cooldown = 15, power = 0.08,
		share = 0.3, -- a tick: this share of the poisoner's attack
		text = "Poisons: %s damage at each of the target's turns for %s s." },
	enrage = { name = "Enrage", code = "e", icon = "Interface\\Icons\\Ability_Racial_BloodRage", passive = true, power = 0.08,
		text = "Enrages: below 30%% health it does 50%% more damage." },
}
ns.ABILITY_ORDER = { "stun", "fear", "silence", "poison", "enrage", "slow", "disarm" }
ns.ABILITY_BY_CODE = {}
for key, ability in pairs(ns.ABILITIES) do
	ability.key = key
	ns.ABILITY_BY_CODE[ability.code] = key
end

local function Clean(value)
	return ns.Clean and ns.Clean(value) or value
end

-- What an ability does, in words; card: the card that has it (for numbers like a poison's tick)
function ns.AbilityText(ability, card)
	local def = ns.ABILITIES[ability.key]
	local seconds = ability.duration or def.duration or 0
	if ability.key == "poison" then
		local tick = card and card.attack and math.max(1, math.floor(card.attack * def.share + 0.5))
		return def.text:format(tick and tostring(tick) or ("%d%% of its attack as"):format(def.share * 100), seconds)
	end
	return def.text:format(seconds)
end

-- Saves an ability of a mob type; returns true if it's new
function ns.LearnAbility(npcId, key, fields)
	local info = npcId and BestiaryAccount.mobs[npcId]
	if not info or not ns.ABILITIES[key] then
		return false
	end
	info.abilities = info.abilities or {}
	local known = info.abilities[key]
	local new = known == nil
	known = known or {}
	for field, value in pairs(fields or {}) do
		if value ~= nil and known[field] == nil then
			known[field] = value
		end
	end
	if fields and fields.duration and fields.duration > 0 then
		known.duration = fields.duration -- the latest real duration
	end
	info.abilities[key] = known
	if new then
		ns.Print(("Learned: |cffffd200%s|r can %s%s."):format(info.name or "?", ns.ABILITIES[key].name:lower(),
			known.spell and (" (" .. known.spell .. ")") or ""))
		if ns.Debug then
			ns.Debug(("ability %s of %s from %s"):format(key, info.name or "?", tostring(known.source)))
		end
	end
	return new
end

-- Spell descriptions ---------------------------------------------------------------------------

-- Words that name an effect (English and German), checked in lower case
local WORDS = {
	stun = { "stun", "betäub" },
	fear = { "fear", "terror", "flee", "furcht", "entsetz" },
	silence = { "silence", "interrupt", "schweig", "unterbr" },
	disarm = { "disarm", "root", "immobil", "entwaffn", "wurzel" },
	slow = { "movement speed", "attack speed", "slows", "slowed", "verlangsam", "geschwindigkeit" },
	poison = { "poison", "disease", "gift", "krankheit" },
}

-- Effects in a spell description: { key = duration (or true) }
function ns.ParseSpellEffects(text)
	if type(text) ~= "string" or text == "" then
		return nil
	end
	local lower = text:lower()
	local seconds = tonumber(lower:match("for (%d+) sec") or lower:match("(%d+) sek") or lower:match("(%d+) sec"))
	local effects
	for key, words in pairs(WORDS) do
		for _, word in ipairs(words) do
			if lower:find(word, 1, true) then
				effects = effects or {}
				effects[key] = seconds or true
				break
			end
		end
	end
	-- "increases movement speed" isn't a slow
	if effects and effects.slow and lower:find("increases", 1, true) and not lower:find("reduc", 1, true) then
		effects.slow = nil
	end
	return effects
end

-- Loss of control --------------------------------------------------------------------------------

local LOC_TYPES = {
	{ "STUN", "stun" }, { "SLEEP", "stun" }, { "INCAPACITATE", "stun" },
	{ "FEAR", "fear" }, { "CHARM", "fear" }, { "CONFUSE", "fear" }, { "POSSESS", "fear" }, { "HORROR", "fear" },
	{ "SILENCE", "silence" }, { "INTERRUPT", "silence" },
	{ "DISARM", "disarm" }, { "ROOT", "disarm" }, { "PACIFY", "disarm" },
}

function ns.LossOfControlKey(locType)
	if type(locType) ~= "string" then
		return nil
	end
	for _, pair in ipairs(LOC_TYPES) do
		if locType:find(pair[1], 1, true) then
			return pair[2]
		end
	end
end

local function OnLossOfControl(unit, index)
	if not (C_LossOfControl and C_LossOfControl.GetActiveLossOfControlData) then
		return
	end
	if unit and Clean(unit) ~= "player" then
		return
	end
	local ok, data = pcall(C_LossOfControl.GetActiveLossOfControlData, Clean(index) or 1)
	if not ok or type(data) ~= "table" then
		return
	end
	local key = ns.LossOfControlKey(Clean(data.locType))
	if not key then
		return
	end
	-- who: the mob that just finished a cast, else the one attacking us
	local who = ns.RecentCaster and ns.RecentCaster()
	who = who or (ns.Attacker and ns.Attacker())
	if not who then
		return
	end
	local spellId = Clean(data.spellID)
	local name = spellId and C_Spell and C_Spell.GetSpellName and Clean(C_Spell.GetSpellName(spellId))
	local duration = Clean(data.duration)
	ns.LearnAbility(who.npcId, key, {
		duration = type(duration) == "number" and math.floor(duration * 10 + 0.5) / 10 or nil,
		spell = name, spellId = spellId, icon = Clean(data.iconTexture), source = "loss of control",
	})
end

-- Emotes: enrage ---------------------------------------------------------------------------------

local ENRAGE_WORDS = { "enrage", "frenzy", "berserk", "raserei", "wütend", "tobsucht" }

-- The mob type with this name we've seen (the one seen fighting us lately first)
local function MobByName(name)
	for npcId, info in pairs(BestiaryAccount.mobs) do
		if info.name == name then
			return npcId
		end
	end
end

local function OnEmote(text, name)
	text, name = Clean(text), Clean(name)
	if type(text) ~= "string" or type(name) ~= "string" then
		return
	end
	local lower = text:lower()
	for _, word in ipairs(ENRAGE_WORDS) do
		if lower:find(word, 1, true) then
			ns.LearnAbility(MobByName(name), "enrage", { source = "emote" })
			return
		end
	end
end

local events = CreateFrame("Frame")
events:RegisterEvent("LOSS_OF_CONTROL_ADDED")
events:RegisterEvent("CHAT_MSG_MONSTER_EMOTE")
events:SetScript("OnEvent", function(_, event, ...)
	if not BestiaryAccount then
		return
	end
	local ok, err = pcall(event == "LOSS_OF_CONTROL_ADDED" and OnLossOfControl or OnEmote, ...)
	if not ok and ns.Debug then
		ns.Debug("abilities: " .. tostring(err))
	end
end)

-- A card's abilities ------------------------------------------------------------------------------

-- Your own card: 4 abilities of your class (decided 2026-10-17), real Classic spells (rank 1
-- ids) mapped to our effects. Polymorph and Hibernate break on damage like fear; damage over time
-- is the poison effect under the spell's name; roots stop attacks like disarm.
local function A(key, spellId, spell, duration, onSpell)
	return { key = key, spellId = spellId, spell = spell, duration = duration, onSpell = onSpell }
end
ns.CLASS_ABILITIES = {
	WARRIOR = { A("slow", 1715, "Hamstring", 10), A("disarm", 676, "Disarm", 5), A("fear", 5246, "Intimidating Shout", 4),
		A("enrage", 18499, "Berserker Rage") },
	PALADIN = { A("stun", 853, "Hammer of Justice", 3), A("fear", 2878, "Turn Undead", 5), A("poison", 26573, "Consecration", 8),
		A("silence", 20184, "Judgement of Justice", 4) },
	ROGUE = { A("stun", 408, "Kidney Shot", 2), A("silence", 1766, "Kick", 4), A("slow", 3408, "Crippling Poison", 8),
		A("poison", 2823, "Deadly Poison", 12) },
	HUNTER = { A("stun", 19503, "Scatter Shot", 3), A("slow", 5116, "Concussive Shot", 4), A("poison", 1978, "Serpent Sting", 12),
		A("fear", 1513, "Scare Beast", 6) },
	MAGE = { A("slow", 116, "Frostbolt", 4, true), A("silence", 2139, "Counterspell", 4), A("fear", 118, "Polymorph", 6),
		A("disarm", 122, "Frost Nova", 6) },
	WARLOCK = { A("fear", 5782, "Fear", 5), A("poison", 172, "Corruption", 12), A("slow", 18223, "Curse of Exhaustion", 10),
		A("silence", 19244, "Spell Lock", 3) },
	SHAMAN = { A("silence", 8042, "Earth Shock", 2), A("slow", 8056, "Frost Shock", 6), A("poison", 8050, "Flame Shock", 12),
		A("enrage", 16166, "Elemental Mastery") },
	PRIEST = { A("fear", 8122, "Psychic Scream", 4), A("poison", 589, "Shadow Word: Pain", 12), A("silence", 15487, "Silence", 4),
		A("slow", 15407, "Mind Flay", 3) },
	DRUID = { A("stun", 5211, "Bash", 2), A("fear", 2637, "Hibernate", 6), A("disarm", 339, "Entangling Roots", 6),
		A("poison", 8921, "Moonfire", 9) },
}
-- The spell casters' and healers' own cards cast (their signature spell)
ns.CLASS_SPELLS = { MAGE = "Frostbolt", WARLOCK = "Shadow Bolt", SHAMAN = "Lightning Bolt", PRIEST = "Lesser Heal",
	DRUID = "Healing Touch" }

function ns.ClassAbilities(class)
	local list = {}
	for i, ability in ipairs(ns.CLASS_ABILITIES[class or ""] or {}) do
		local copy = {}
		for k, v in pairs(ability) do
			copy[k] = v
		end
		copy.spell = ns.SpellNameOf(ability.spellId) or ability.spell -- in the client's language
		list[i] = copy
	end
	return list
end

function ns.SpellNameOf(spellId)
	local name = spellId and C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(spellId)
	return ns.Clean and ns.Clean(name) or name
end

-- An ability's name and icon to show: its spell's (by id or name) if known, else the effect's
function ns.AbilityLook(ability)
	local def = ns.ABILITIES[ability.key]
	local name = ability.spell or ns.SpellNameOf(ability.spellId) or def.name
	local icon = ability.icon
	if not icon and ability.spellId and C_Spell and C_Spell.GetSpellTexture then
		icon = ns.Clean and ns.Clean(C_Spell.GetSpellTexture(ability.spellId))
	end
	if not icon and ability.spell then
		icon = ns.SpellIcon(nil, ability.spell)
	end
	return name, icon or def.icon
end

-- Test cards (Test tab: "Fill with 5 basic cards") and training cards (the sparring partner)
-- have no mob behind them that we learned from: they get a set by combat type
ns.TEST_ABILITIES = {
	Tank = { { key = "stun", duration = 3 }, { key = "disarm", duration = 5 } },
	Mage = { { key = "slow", duration = 4, onSpell = true }, { key = "silence", duration = 4 } },
	Warrior = { { key = "poison", duration = 10 }, { key = "enrage" } },
	Healer = { { key = "fear", duration = 4 } },
}

function ns.TestAbilities(kind)
	local list = {}
	for i, ability in ipairs(ns.TEST_ABILITIES[kind] or {}) do
		list[i] = { key = ability.key, duration = ability.duration, onSpell = ability.onSpell }
	end
	return list
end

-- What a mob type can do, strongest first, at most MAX_ABILITIES: { key, duration, spell, icon,
-- onSpell (part of the card's signature spell: it comes with the cast, no own action) }
function ns.MobAbilities(npcId, signature)
	local info = npcId and BestiaryAccount.mobs[npcId]
	if not info then
		return {}
	end
	local found = {}
	for key, known in pairs(info.abilities or {}) do
		found[key] = { key = key, duration = known.duration, spell = known.spell, icon = known.icon }
	end
	-- from the descriptions of its spells
	for name in pairs(info.spellData or {}) do
		local data = ns.SpellData(npcId, name)
		for key, duration in pairs(data and data.effects or {}) do
			if not found[key] then
				found[key] = { key = key, duration = type(duration) == "number" and duration or nil, spell = name }
			end
		end
	end
	-- poisons it left on us
	local study = BestiaryChar and BestiaryChar.study and BestiaryChar.study[npcId]
	if study and (study.poisons or 0) > 0 and not found.poison then
		found.poison = { key = "poison" }
	end
	local list = {}
	for _, key in ipairs(ns.ABILITY_ORDER) do
		local ability = found[key]
		if ability and #list < ns.MAX_ABILITIES then
			ability.duration = ability.duration or ns.ABILITIES[key].duration
			ability.onSpell = signature ~= nil and ability.spell == signature or nil
			list[#list + 1] = ability
		end
	end
	return list
end

-- On the wire: "s30*#853+w100" (code, duration in tenths, * if part of the signature spell,
-- # and the spell id if known: the other side shows its name and icon)
function ns.EncodeAbilities(list)
	local parts = {}
	for _, ability in ipairs(list or {}) do
		local def = ns.ABILITIES[ability.key]
		if def then
			parts[#parts + 1] = def.code .. math.floor((ability.duration or 0) * 10 + 0.5) .. (ability.onSpell and "*" or "")
				.. (ability.spellId and ("#" .. ability.spellId) or "")
		end
	end
	return table.concat(parts, "+")
end

function ns.DecodeAbilities(text)
	local list = {}
	for part in (text or ""):gmatch("[^+]+") do
		local code, tenths, star, spellId = part:match("^(%a)(%d+)(%*?)#?(%d*)$")
		local key = code and ns.ABILITY_BY_CODE[code]
		if key and #list < ns.MAX_ABILITIES then
			list[#list + 1] = { key = key, duration = tonumber(tenths) / 10, onSpell = star == "*" or nil,
				spellId = tonumber(spellId) }
		end
	end
	return list
end
