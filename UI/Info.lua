local _, ns = ...

-- Info page: the rules explained, built from the same tables and numbers the game uses
-- (Config, Data, Fight), so it stays right when they change.
local WIDTH = ns.WINDOW_WIDTH
local TEXT_WIDTH = WIDTH - 70
local INSET = C_XMLUtil and C_XMLUtil.GetTemplateInfo and C_XMLUtil.GetTemplateInfo("InsetFrameTemplate")
	and "InsetFrameTemplate" or nil

local page = ns.AddPage("Info", "Interface\\Icons\\INV_Scroll_03", 7)

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
		("Starter boost: x%d while you have fewer than %d different cards, then it fades (halves every %d cards) and is gone at %d."):format(
			ns.STARTER_BOOST, ns.STARTER_CARDS, ns.STARTER_HALF, ns.STARTER_END),
		("Getting a card you already have adds a star (up to %d). Each star makes the card %s stronger. The mob's level doesn't matter: grey mobs drop cards too."):format(ns.MAX_STARS, Pct(ns.STAR_BONUS)),
	})

	local rarities = {}
	for _, key in ipairs({ "normal", "elite", "rare", "rareelite", "worldboss" }) do
		local rarity = ns.RARITIES[key]
		rarities[#rarities + 1] = ("%s  power x%.1f"):format(Colored(rarity.color, rarity.name), rarity.factor)
	end
	Section("Rarity", {
		"A card's rarity comes from the mob: normal mobs are Common, elites Uncommon, rares Rare, rare elites Epic, bosses Legendary. Rarity and stars set a card's power.",
		table.concat(rarities, "     "),
	})

	local roles = {
		Tank = "Lots of health, slow. Hits the enemy's front card. Its armor takes a flat amount off every physical hit.",
		Mage = ("Fragile. Hits the enemy's front card, ignoring armor, and splashes %s of that onto the card behind it."):format(Pct(R.splash)),
		Assassin = ("Fast. One strike for %s of its attack at the enemy's back card. Armor counts %d times against it."):format(Pct(R.assassinStrike), R.assassinArmor),
		Healer = ("Like a Mage, but heals the ally with the lowest health share and half that on the ally behind it. Never deals damage. Each heal is %s weaker than the one before."):format(Pct(1 - R.healFade)),
	}
	local types = {}
	for _, kind in ipairs(ns.ALL_TYPES) do
		local t = ns.TYPES[kind]
		types[#types + 1] = ("%s %s  %s\n      |cffffd200%s|r"):format(Icon(t.icon), Colored(t.color, kind), roles[kind], t.leader)
	end
	types[#types + 1] = "Tank beats Assassin, Assassin beats Mage, Mage beats Tank. Healers support any squad."
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
		"Your first leader is you: every character starts with a card of themselves. It leads like a named card but is only as strong as a common mob's card and never gains stars. Its type comes from your class.",
		"A squad doesn't need a leader, but can have at most one. The leader's bonus goes to allies of its combat type (see above).",
	})

	Section("Squads", {
		("You build three squads of at least %d cards, front to back. Before a duel you pick one in secret; you can switch until you press Ready."):format(ns.MIN_SQUAD),
		("Beyond that only power counts: the sum of a squad's cards must fit under the cap of %d. And at most one named card (the leader)."):format(ns.POWER_CAP),
		"Where a card stands matters: the front takes the Tank and Mage hits, the back takes the Assassin strikes.",
	})

	Section("Friends and duels", {
		"Only Bestiary friends duel each other and share the board. Add a friend by name on the Board tab: they get a request and have to say yes.",
		"Challenge a friend on the Duel tab (type their name or target them) or click them on the Board tab. They pick a squad first, in secret; then you pick yours. Both clients play the same fight.",
	})

	Section("The fight", {
		("It plays out on its own, at most %d rounds. Every card attacks once per round."):format(R.maxRounds),
		"Each side's cards line up fastest first and pair up with the other side's: the faster card of a pair acts first. A bigger squad's extra cards act at the end of the round.",
		"A side with no cards left loses. After the last round, the side with more health left (in percent) wins.",
	})

	local twists = {}
	for _, twist in ipairs(ns.TWISTS) do
		twists[#twists + 1] = ("|cffffd200%s|r  %s"):format(twist.name, twist.text)
	end
	table.insert(twists, 1, "Each duel draws a twist, shown before both pick their squad.")
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
