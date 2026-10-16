local _, ns = ...

-- Builds cards from what the tracker learned about a mob (ARCHITECTURE.md 4.0) and rolls drops
-- on kills (3.3, 4.1, 4.2). Saved cards (BestiaryChar.cards[npcId]) only keep what came from
-- the game; stats are computed from them by the formula, so it can change while balancing.

-- The combat type from what was seen of the mob (the combat log is closed to addons, so no
-- damage numbers): heal casts, mana and casting, its NPC class, attack speed, else its family
-- NPC classes only say how a mob uses resources: Warrior (rage, no mana), Paladin (mana, often
-- a caster beast or hybrid), Mage (mana caster). So only the clear ones decide here; Paladin
-- just means mana.
local CLASS_TYPES = { MAGE = "Mage", WARLOCK = "Mage", PRIEST = "Mage", ROGUE = "Assassin", HUNTER = "Assassin" }
local MANA_CLASSES = { PALADIN = true, MAGE = true, WARLOCK = true, PRIEST = true, SHAMAN = true, DRUID = true }
local CASTS_PER_10S = 1 -- casting at least this often makes a caster even without mana

local function TypeFrom(entry, family)
	local mana = entry.mana or MANA_CLASSES[entry.class or ""]
	local rate = entry.seconds > 0 and entry.casts / entry.seconds * 10 or 0
	if entry.heals >= 2 and entry.heals >= entry.casts * 0.35 then
		return "Healer", ("%d of its %d casts heal"):format(entry.heals, entry.casts)
	elseif mana and entry.casts >= 2 then
		return "Mage", ("uses mana and cast %d spells"):format(entry.casts)
	elseif entry.casts >= 3 and rate >= CASTS_PER_10S then
		return "Mage", ("casts a lot: %d spells, %.1f per 10 s"):format(entry.casts, rate)
	elseif CLASS_TYPES[entry.class or ""] then
		return CLASS_TYPES[entry.class], "its class is " .. entry.class:lower()
	elseif entry.attackSpeed and entry.attackSpeed < 1.8 then
		return "Assassin", ("fast attacks, every %.1f s"):format(entry.attackSpeed)
	elseif entry.attackSpeed and entry.attackSpeed > 2.6 then
		return "Tank", ("slow, heavy attacks, every %.1f s"):format(entry.attackSpeed)
	end
	local lean = { Giant = "Tank", Mechanical = "Tank", Undead = "Tank", Beast = "Assassin",
		Humanoid = "Assassin", Demon = "Mage", Dragonkin = "Mage", Elemental = "Mage" }
	return lean[family] or "Tank", "nothing telling seen, so by its family (" .. tostring(family) .. ")"
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
		type = TypeFrom(entry, info.family),
		spell = spell,
		art = spell and (ns.SpellIcon(entry.spellIds[spell], spell) or (entry.spellIcons or {})[spell]) or nil,
		zone = GetRealZoneText and GetRealZoneText() or "",
		stars = 1,
	}
	return ns.CardView(card)
end

-- A card with its stats (3.2 and 5.2): budget from rarity and stars, split by combat type,
-- nudged a little by the NPC id so cards of the same rarity and type still differ
function ns.CardView(card)
	local rarity = ns.RARITIES[card.classification] or ns.RARITIES.normal
	local budget = ns.BASE_POWER * rarity.factor * (1 + ns.STAR_BONUS * ((card.stars or 1) - 1))
	local kind = ns.TYPES[card.type] or ns.TYPES.Tank
	local nudge = function(salt)
		return 0.9 + ns.Seed(card.npcId, salt) * 0.2
	end
	local view = {}
	for key, value in pairs(card) do
		view[key] = value
	end
	view.id = "npc" .. card.npcId
	view.power = ns.PowerFromBudget(budget) -- 0-63, like a level
	view.health = math.max(5, math.floor(budget * kind.health * nudge(1) + 0.5))
	view.attack = math.max(1, math.floor(budget * kind.attack * nudge(2) + 0.5))
	-- Speed 1-10: the type's speed, one up or down by the NPC id
	view.speed = math.max(1, math.min(ns.MAX_SPEED, kind.speed + math.floor(ns.Seed(card.npcId, 3) * 3) - 1))
	view.armor = math.floor(view.attack * kind.armor + 0.5)
	view.stamina = card.stamina or 100
	view.zone = card.zone or ""
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
	return math.min(1, chance), #reasons > 0 and table.concat(reasons, ", ") or nil
end

-- Gives the card of this mob type, or +1 star if it's owned. Returns "new", "star" or nil (at
-- max stars). test: doesn't count for the farm window.
function ns.GiveCard(npcId, guid, test)
	local cards = BestiaryChar.cards
	local owned = cards[npcId]
	local result
	if owned then
		if owned.stars >= ns.MAX_STARS then
			return
		end
		owned.stars = owned.stars + 1
		result = "star"
	else
		local view = ns.BuildCard(npcId)
		if not view then
			return
		end
		cards[npcId] = {
			npcId = npcId, name = view.name, classification = view.classification, family = view.family,
			type = view.type, spell = view.spell, art = view.art, zone = view.zone,
			stars = 1, obtained = time(),
		}
		owned = cards[npcId]
		result = "new"
	end
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

-- Test tab: the next kill we take part in drops its card, studied or not (only this session)
ns.forceDrop = false
-- Test tab: drop chance TEST_CHANCE for studied mobs until the next drop (only this session)
ns.testChance = false

function ns.OnKill(guid, npcId, name)
	ns.RecordKill()
	local entry = ns.Studied(npcId)
	local info = ns.MobInfo(npcId)
	local forced = ns.forceDrop
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
	local chance, why = ns.DropChance(npcId, info.classification)
	local roll = math.random()
	ns.Debug(("%s died: %.0f%% chance%s, rolled %.0f%%."):format(name or "?", chance * 100,
		why and (" (" .. why .. ")") or "", roll * 100))
	if roll >= chance then
		return
	end
	if ns.testChance then
		ns.testChance = false
		ns.Print("Test drop chance used up, back to normal.")
	end
	if not ns.GiveCard(npcId, guid) then
		ns.Debug((info.name or name or "?") .. " is already at " .. ns.MAX_STARS .. " stars.")
	end
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

-- The collection as card views, rarest first
function ns.Collection()
	local list = {}
	for _, card in pairs(BestiaryChar.cards) do
		list[#list + 1] = ns.CardView(card)
	end
	table.sort(list, function(a, b)
		local ra, rb = ns.RARITY_ORDER[a.classification], ns.RARITY_ORDER[b.classification]
		if ra ~= rb then
			return ra < rb
		end
		return a.name < b.name
	end)
	return list
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
