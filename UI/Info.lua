local _, ns = ...

-- Info page: the rules explained, built from the same tables and numbers the game uses
-- (Config, Data, Fight), so it stays right when they change.
local WIDTH = ns.WINDOW_WIDTH
local TEXT_WIDTH = WIDTH - 70
local INSET = C_XMLUtil and C_XMLUtil.GetTemplateInfo and C_XMLUtil.GetTemplateInfo("InsetFrameTemplate")
	and "InsetFrameTemplate" or nil

local page = ns.AddPage("Info", "Interface\\Icons\\INV_Scroll_03", 8)

local title = page:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
title:SetPoint("TOPLEFT", 72, -34)
title:SetText("How Bestiary works")

local inset = CreateFrame("Frame", nil, page, INSET)
inset:SetPoint("TOPLEFT", 8, -64)
inset:SetPoint("BOTTOMRIGHT", -8, 8)
local scroll = CreateFrame("ScrollFrame", nil, inset, "UIPanelScrollFrameTemplate")
scroll:SetPoint("TOPLEFT", 10, -10)
scroll:SetPoint("BOTTOMRIGHT", -28, 10)
local content = CreateFrame("Frame", nil, scroll)
content:SetSize(TEXT_WIDTH, 10)
scroll:SetScrollChild(content)

local function Icon(path, size)
	return ("|T%s:%d:%d:0:0:64:64:5:59:5:59|t"):format(path, size or 16, size or 16)
end

local function Colored(color, text)
	local r, g, b = unpack(color)
	return ("|cff%02x%02x%02x%s|r"):format(r * 255, g * 255, b * 255, text)
end

local function Pct(x)
	return ("%d%%"):format(math.floor(x * 100 + 0.5))
end

-- The sections: { heading, body lines }
local function Sections()
	local R = ns.FIGHT_RULES
	local sections = {}
	local function Section(heading, lines)
		sections[#sections + 1] = { heading = heading, text = table.concat(lines, "\n") }
	end

	Section("Getting cards", {
		("Every kind of mob has to be studied first: once you've seen it fighting for %d seconds (anyone fighting it counts, as long as you can see it), killing one can drop its card."):format(ns.STUDY_SECONDS),
		"The card is built from what you saw: its spells, whether it heals, uses mana or attacks fast or slow.",
		("Drop chance per kill: %s for normal mobs, %s elite, %s rare, %s rare elite, %s boss. A rare's or boss's first card drops for sure."):format(
			Pct(ns.DROP_CHANCE.normal), Pct(ns.DROP_CHANCE.elite), Pct(ns.DROP_CHANCE.rare), Pct(ns.DROP_CHANCE.rareelite), Pct(ns.DROP_CHANCE.worldboss)),
		("In a group x%.2f, in a raid x%.2f. Each card of the same mob in the last hour halves the chance."):format(ns.GROUP_FACTOR.party, ns.GROUP_FACTOR.raid),
		("Bad luck protection: every kill of a mob that drops nothing raises its chance by %d%%, up to x%d; its next card resets it."):format(ns.DRY_BONUS * 100, ns.DRY_MAX),
		("Starter boost: x%d while you have fewer than %d different cards, then it fades (halves every %d cards) and is gone at %d."):format(
			ns.STARTER_BOOST, ns.STARTER_CARDS, ns.STARTER_HALF, ns.STARTER_END),
		("Normal (Common) cards can be owned up to %d times: getting one again gives another copy, and a squad can use as many copies as you own. Rarer cards only once."):format(ns.MAX_COPIES),
		("Stars: once you own a mob's card, every kill of that mob can add a star: %g%% for the first, then half as likely for each next (%g%%, %g%%, ...), up to %d. Each star makes the card %s stronger in health and damage or healing."):format(
			ns.STAR_CHANCE * 100, ns.STAR_CHANCE * 50, ns.STAR_CHANCE * 25, ns.MAX_STARS, Pct(ns.STAR_BONUS)),
	})

	Section("Levels", {
		"A card is the real mob: its health, hits and spells as Bestiary measured them on you (health from the damage meter, hits with your armor taken back out), scaled the way the game scales mobs by level. Until a mob is measured, its rarity sets a guess.",
		"A card starts at the level of the mob it dropped from: grey mobs drop low cards.",
		("Every %d duels (won or lost, the sparring partner counts too) a card gains a level, but never more than %d above your own level, and at most %d (named cards %d)."):format(
			ns.GAMES_PER_LEVEL, ns.LEVELS_ABOVE_PLAYER, ns.MAX_NORMAL_LEVEL, ns.MAX_LEVEL),
	})

	local rarities = {}
	for _, key in ipairs({ "normal", "elite", "rare", "rareelite", "worldboss" }) do
		local rarity = ns.RARITIES[key]
		rarities[#rarities + 1] = Colored(rarity.color, rarity.name)
	end
	Section("Rarity", {
		"A card's rarity comes from the mob: normal mobs are Common, elites Uncommon, rares Rare, rare elites Epic, bosses Legendary. Rarer mobs are stronger mobs, so their cards are too.",
		table.concat(rarities, "     "),
	})

	local roles = {
		Tank = ("Blocks: while you have a living Tank, the enemy's attacks and spells have to target a Tank. %s more health, %s less damage and %s slower attacks than the mob."):format(Pct(ns.TANK_HEALTH - 1), Pct(1 - ns.TANK_DAMAGE), Pct(ns.TANK_SLOW - 1)),
		Mage = "Only casts: its spell ignores armor and has no cooldown.",
		Warrior = "Melee damage: its edge is the real mob's hits and attack time.",
		Healer = ("Only heals: an ally you pick, like a Mage's spell (its cast time, no cooldown); each heal is %s weaker than the one before. With nobody hurt it waits, and gets its turn the moment an ally is hurt."):format(Pct(1 - R.healFade)),
	}
	local types = {}
	for _, kind in ipairs(ns.ALL_TYPES) do
		local t = ns.TYPES[kind]
		types[#types + 1] = ("%s %s  %s\n      |cffffd200%s|r"):format(Icon(t.icon), Colored(t.color, kind), roles[kind], t.leader)
	end
	types[#types + 1] = "Healers support any squad."
	Section("Combat types", types)

	local families = {}
	local names = {}
	for family in pairs(ns.FAMILIES) do
		names[#names + 1] = family
	end
	table.sort(names)
	for _, family in ipairs(names) do
		local bonus = ns.FAMILY_BONUS[family]
		if bonus then
			families[#families + 1] = ("%s |cffffd200%s|r   2 cards: %s   ·   4 cards: %s"):format(
				Icon(ns.FAMILIES[family].icon), family, bonus[1].text, bonus[2].text)
		end
	end
	table.insert(families, 1, "With 2 or 4 cards of the same family in a squad, those cards get a bonus. Only the cards of that family get it.")
	Section("Family bonuses", families)

	Section("Leaders", {
		"Only named mobs lead: rares, rare elites, bosses, and known named mobs like Hogger or Mor'Ladim. A named card always leads its squad and wears the dragon ring.",
		"Your first leader is you: every character starts with a card of themselves. It leads like a named card but is only as strong as a common mob of your level and never gains stars. Its level is always yours, its type comes from your class.",
		"A squad doesn't need a leader, but can have at most one. The leader's bonus goes to allies of its combat type (see above).",
	})

	Section("Squads", {
		"You build three squads, front to back, as many cards as fit under the power cap. Before a duel you pick one in secret; you can switch until you press Ready.",
		("Only power counts: a card's power is its level, and the sum of a squad's levels must fit under the cap, %d times your level (%d now). And at most one named card (the leader)."):format(ns.CAP_PER_LEVEL, ns.POWER_CAP),
		"The order in a squad doesn't matter: you pick every target yourself (Tanks block, see Combat types).",
	})

	Section("Friends and duels", {
		"Only Bestiary friends duel each other and share the board. Add a friend on the Friends tab (by name or your target): they get a request and have to say yes.",
		"Challenge a friend on the Duel tab (type their name or target them) or click Duel next to them on the Friends tab. They pick a squad and ban a twist first, in secret; then you do. Both clients play the same fight.",
		"Games have no timers: they're saved and go on whenever you're both online, even after a reload or days later. Your turn shows on the Duel tab and in chat.",
	})

	Section("The fight", {
		"Turn based on a virtual clock, no rounds: every card gets its next turn after its real attack time (shown on the card, in seconds), so fast mobs get more turns than slow ones. Whichever card's time comes first, on either side, acts next.",
		("On your card's turn, click a circle under a card. Tanks and Warriors: Attack (their melee) or their Spell (the mob's real spell with its real cast time, at least 1.5 s; every %d s). Mages only cast, Healers only heal."):format(R.spellCooldown),
		"A spell's strength: as measured on you; until then from the numbers in the spell's description; else twice the card's melee hit. Cards update themselves when Bestiary learns more about their mob (type, spell).",
		("Health, attack, spells and armor are the real mob at the card's level. Fights run %d times faster than real ones: every hit counts %d times. Armor takes a share off physical hits, like in the game."):format(ns.PACE, ns.PACE),
		("A side with no cards left loses. After %d virtual seconds, the side with more health left (in percent) wins."):format(R.maxTime),
	})

	local twists = {}
	for _, twist in ipairs(ns.TWISTS) do
		twists[#twists + 1] = ("|cffffd200%s|r  %s"):format(twist.name, twist.text)
	end
	table.insert(twists, 1, ("Each duel offers %d twists. Both players ban one in secret, then the twist is drawn from the ones left."):format(ns.TWIST_CHOICES))
	Section("Twists", twists)

	Section("Stamina", {
		"Fighting wears cards out: a card loses stamina by how much health it lost in the duel (60% of the health lost in percent). Cards that didn't fight rest and get 25 back.",
		"At 0 stamina a card sits out the next 2 duels, then comes back full.",
	})
	return sections
end

local blocks = {}

local function Block(i)
	local block = blocks[i]
	if not block then
		block = {}
		block.heading = content:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
		block.heading:SetWidth(TEXT_WIDTH)
		block.heading:SetJustifyH("LEFT")
		block.text = content:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
		block.text:SetWidth(TEXT_WIDTH)
		block.text:SetJustifyH("LEFT")
		block.text:SetSpacing(4)
		block.text:SetPoint("TOPLEFT", block.heading, "BOTTOMLEFT", 0, -6)
		if i == 1 then
			block.heading:SetPoint("TOPLEFT", 4, -4)
		else
			block.heading:SetPoint("TOPLEFT", blocks[i - 1].text, "BOTTOMLEFT", 0, -18)
		end
		blocks[i] = block
	end
	return block
end

local function Refresh()
	local height = 8
	for i, section in ipairs(Sections()) do
		local block = Block(i)
		block.heading:SetText(section.heading)
		block.text:SetText(section.text)
		height = height + (block.heading:GetStringHeight() or 16) + 6 + (block.text:GetStringHeight() or 16) + 18
	end
	content:SetHeight(math.max(10, height))
end

page:SetScript("OnShow", Refresh)
