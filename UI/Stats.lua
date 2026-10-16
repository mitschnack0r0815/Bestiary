local _, ns = ...

-- Stats page: your duel record and leaderboards of your cards (heavy hitters, healers, walls,
-- killers, MVPs, the fallen), the opponent cards that hurt you most, hunting and the collection.
-- Duel stats come from BestiaryChar.stats (Core/Stats.lua), the collection is counted live.
local WIDTH = ns.WINDOW_WIDTH
local COLUMN = math.floor((WIDTH - 90) / 2)
local TOP = 5 -- entries per leaderboard
local INSET = C_XMLUtil and C_XMLUtil.GetTemplateInfo and C_XMLUtil.GetTemplateInfo("InsetFrameTemplate")
	and "InsetFrameTemplate" or nil

local page = ns.AddPage("Stats", "Interface\\Icons\\INV_Misc_Book_04", 7)

local title = page:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
title:SetPoint("TOPLEFT", 72, -34)
title:SetText("Stats")
local record = page:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
record:SetPoint("LEFT", title, "RIGHT", 18, 0)

local inset = CreateFrame("Frame", nil, page, INSET)
inset:SetPoint("TOPLEFT", 8, -64)
inset:SetPoint("BOTTOMRIGHT", -8, 8)
local scroll = CreateFrame("ScrollFrame", nil, inset, "UIPanelScrollFrameTemplate")
scroll:SetPoint("TOPLEFT", 10, -10)
scroll:SetPoint("BOTTOMRIGHT", -28, 10)
local content = CreateFrame("Frame", nil, scroll)
content:SetSize(WIDTH - 70, 10)
scroll:SetScrollChild(content)

local function Icon(path, size)
	return ("|T%s:%d:%d:0:0:64:64:5:59:5:59|t"):format(path, size or 14, size or 14)
end

local function Colored(color, text)
	local r, g, b = unpack(color)
	return ("|cff%02x%02x%02x%s|r"):format(r * 255, g * 255, b * 255, text)
end

local function Grey(text)
	return "|cff999999" .. text .. "|r"
end

-- A card's name with its type icon, in its rarity color
local function CardName(entry)
	local rarity = ns.RARITIES[entry.classification or "normal"] or ns.RARITIES.normal
	local kind = ns.TYPES[entry.type or ""]
	return (kind and (Icon(kind.icon) .. " ") or "") .. Colored(rarity.color, entry.name or "?")
end

local function WinRate(r)
	local games = (r.wins or 0) + (r.losses or 0) + (r.draws or 0)
	if games == 0 then
		return Grey("no duels")
	end
	return ("%d-%d-%d  |cffffd200%d%%|r"):format(r.wins or 0, r.losses or 0, r.draws or 0, (r.wins or 0) / games * 100 + 0.5)
end

-- The best entries of a list by a field: "1. Name   value (extra)"
local function Board(list, field, format, extra)
	local entries = {}
	for _, entry in pairs(list) do
		if (entry[field] or 0) > 0 then
			entries[#entries + 1] = entry
		end
	end
	table.sort(entries, function(a, b)
		if a[field] ~= b[field] then
			return a[field] > b[field]
		end
		return (a.name or "") < (b.name or "")
	end)
	local lines = {}
	for i = 1, math.min(TOP, #entries) do
		local entry = entries[i]
		lines[#lines + 1] = ("%d. %s   |cffffffff%s|r%s"):format(i, CardName(entry), format(entry[field]),
			extra and Grey("   " .. extra(entry)) or "")
	end
	if #lines == 0 then
		lines[1] = Grey("Nothing yet. Fight some duels!")
	end
	return lines
end

local function Count(n, one, many)
	return ("%d %s"):format(n, n == 1 and one or many)
end

local function PerDuel(entry, field)
	return entry.duels > 0 and ("%.0f per duel"):format(entry[field] / entry.duels) or ""
end

-- Left column: duels and your cards
local function DuelSections()
	local stats = ns.Stats()
	local duels = stats.duels
	local sections = {}
	local function Section(heading, lines)
		sections[#sections + 1] = { heading = heading, text = table.concat(lines, "\n") }
	end

	local lines = {
		"Record (won-lost-draw):  " .. WinRate(duels),
		("Streak:  %s   ·   best %s"):format(
			duels.streak > 0 and ("|cff40ff40%d won|r"):format(duels.streak)
			or duels.streak < 0 and ("|cffff4040%d lost|r"):format(-duels.streak) or Grey("none"),
			Count(duels.bestStreak, "win", "wins")),
	}
	local squads = {}
	for name in pairs(duels.squads) do
		squads[#squads + 1] = name
	end
	table.sort(squads)
	for _, name in ipairs(squads) do
		lines[#lines + 1] = ("%s:  %s"):format(name, WinRate(duels.squads[name]))
	end
	Section("Duels", lines)

	local twists = {}
	for _, twist in ipairs(ns.TWISTS) do
		if duels.twists[twist.name] then
			twists[#twists + 1] = ("%s:  %s"):format(twist.name, WinRate(duels.twists[twist.name]))
		end
	end
	if #twists > 0 then
		Section("By twist", twists)
	end

	local cards = stats.cards
	Section(Icon("Interface\\Icons\\Ability_Warrior_Cleave", 16) .. " Heavy hitters", Board(cards, "damage",
		function(v) return v .. " damage" end, function(e) return PerDuel(e, "damage") end))
	Section(Icon("Interface\\Icons\\Spell_Holy_Heal", 16) .. " Healers", Board(cards, "healing",
		function(v) return v .. " healed" end, function(e) return PerDuel(e, "healing") end))
	Section(Icon("Interface\\Icons\\INV_Shield_06", 16) .. " Walls", Board(cards, "taken",
		function(v) return v .. " damage taken" end, function(e) return Count(e.deaths, "death", "deaths") end))
	Section(Icon("Interface\\Icons\\Ability_BackStab", 16) .. " Killers", Board(cards, "kills",
		function(v) return Count(v, "kill", "kills") end))
	Section(Icon("Interface\\Icons\\INV_Misc_Coin_01", 16) .. " Best of the duel", Board(cards, "best",
		function(v) return Count(v, "time", "times") end, function(e) return ("of %s"):format(Count(e.duels, "duel", "duels")) end))
	Section(Icon("Interface\\Icons\\Spell_Shadow_DeathScream", 16) .. " Fell the most", Board(cards, "deaths",
		function(v) return Count(v, "death", "deaths") end, function(e) return ("in %s"):format(Count(e.duels, "duel", "duels")) end))
	Section(Icon("Interface\\Icons\\Ability_Rogue_FeignDeath", 16) .. " Nemesis  " .. Grey("enemy cards that hurt you most"),
		Board(stats.foes, "damage", function(v) return v .. " damage" end,
			function(e) return Count(e.kills, "kill", "kills") end))
	return sections
end

-- Right column: hunting and the collection
local function CollectionSections()
	local stats = ns.Stats()
	local hunting = stats.hunting
	local sections = {}
	local function Section(heading, lines)
		sections[#sections + 1] = { heading = heading, text = table.concat(lines, "\n") }
	end

	local studied, ready, seconds, most = 0, 0, 0, nil
	for npcId, entry in pairs(BestiaryChar.study) do
		local info = ns.MobInfo(npcId)
		if not (info and info.family == false) and entry.seconds > 0 then
			studied = studied + 1
			seconds = seconds + entry.seconds
			if entry.seconds >= ns.STUDY_SECONDS then
				ready = ready + 1
			end
			if not most or entry.seconds > most.seconds then
				most = { name = (info and info.name) or entry.name or "?", seconds = entry.seconds }
			end
		end
	end
	Section(Icon("Interface\\Icons\\Ability_Hunter_BeastTaming", 16) .. " Hunting", {
		("Kills that counted:  |cffffffff%d|r"):format(hunting.kills),
		("Drops:  |cffffffff%d|r   %s"):format(hunting.drops,
			Grey(("%s, %s, %s"):format(Count(hunting.newCards, "new card", "new cards"),
				Count(hunting.copies or 0, "copy", "copies"), Count(hunting.stars, "star", "stars")))),
		("Drop rate:  |cffffffff%s|r"):format(hunting.kills > 0 and ("%.1f%%"):format(hunting.drops / hunting.kills * 100) or "-"),
		("Mob types studied:  |cffffffff%d|r   %s"):format(studied, Grey(ready .. " ready to drop")),
		("Time spent studying:  |cffffffff%d:%02d|r %s"):format(seconds / 60, seconds % 60, Grey("min")),
		most and ("Most studied:  |cffffd200%s|r  %s"):format(most.name, Grey(("%d s"):format(most.seconds))) or Grey("Nothing studied yet."),
	})

	local collection = ns.Collection()
	local byRarity, byType, byFamily, stars, named, strongest = {}, {}, {}, 0, 0, nil
	for _, card in ipairs(collection) do
		byRarity[card.classification] = (byRarity[card.classification] or 0) + 1
		byType[card.type] = (byType[card.type] or 0) + 1
		byFamily[card.family] = (byFamily[card.family] or 0) + 1
		stars = stars + card.stars
		if ns.IsNamed(card) then
			named = named + 1
		end
		if not strongest or card.power > strongest.power then
			strongest = card
		end
	end
	local lines = {
		("Cards:  |cffffffff%d|r   ·   stars: |cffffffff%d|r   ·   leaders: |cffffffff%d|r"):format(#collection, stars, named),
		strongest and ("Strongest:  %s  %s"):format(CardName(strongest), Grey("power " .. strongest.power)) or Grey("No cards yet."),
	}
	local rarities = {}
	for _, key in ipairs({ "normal", "elite", "rare", "rareelite", "worldboss" }) do
		rarities[#rarities + 1] = Colored(ns.RARITIES[key].color, ns.RARITIES[key].name) .. " " .. (byRarity[key] or 0)
	end
	lines[#lines + 1] = table.concat(rarities, "   ")
	local types = {}
	for _, kind in ipairs(ns.ALL_TYPES) do
		types[#types + 1] = Icon(ns.TYPES[kind].icon) .. " " .. kind .. " " .. (byType[kind] or 0)
	end
	lines[#lines + 1] = table.concat(types, "   ")
	local families, names = {}, {}
	for family in pairs(ns.FAMILIES) do
		names[#names + 1] = family
	end
	table.sort(names)
	for _, family in ipairs(names) do
		if byFamily[family] then
			families[#families + 1] = Icon(ns.FAMILIES[family].icon) .. " " .. family .. " " .. byFamily[family]
		end
	end
	if #families > 0 then
		lines[#lines + 1] = table.concat(families, "   ")
	end
	Section(Icon("Interface\\Icons\\INV_Misc_Book_11", 16) .. " Collection", lines)
	return sections
end

-- Two columns of heading + text blocks
local columns = { {}, {} }

local function Block(column, i, x)
	local blocks = columns[column]
	local block = blocks[i]
	if not block then
		block = {}
		block.heading = content:CreateFontString(nil, "OVERLAY", "GameFontNormal")
		block.heading:SetWidth(COLUMN)
		block.heading:SetJustifyH("LEFT")
		block.text = content:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		block.text:SetWidth(COLUMN)
		block.text:SetJustifyH("LEFT")
		block.text:SetSpacing(4)
		block.text:SetPoint("TOPLEFT", block.heading, "BOTTOMLEFT", 0, -5)
		if i == 1 then
			block.heading:SetPoint("TOPLEFT", x, -4)
		else
			block.heading:SetPoint("TOPLEFT", blocks[i - 1].text, "BOTTOMLEFT", 0, -14)
		end
		blocks[i] = block
	end
	return block
end

local function Fill(column, x, sections)
	local height = 8
	for i, section in ipairs(sections) do
		local block = Block(column, i, x)
		block.heading:SetText(section.heading)
		block.text:SetText(section.text)
		block.heading:Show()
		block.text:Show()
		height = height + (block.heading:GetStringHeight() or 14) + 5 + (block.text:GetStringHeight() or 14) + 14
	end
	for i = #sections + 1, #columns[column] do
		columns[column][i].heading:Hide()
		columns[column][i].text:Hide()
	end
	return height
end

local function Refresh()
	local duels = ns.Stats().duels
	record:SetText(WinRate(duels))
	local left = Fill(1, 4, DuelSections())
	local right = Fill(2, COLUMN + 30, CollectionSections())
	content:SetHeight(math.max(10, left, right))
end

page:SetScript("OnShow", Refresh)

local refreshBefore = ns.Refresh
function ns.Refresh()
	if refreshBefore then
		refreshBefore()
	end
	if page:IsVisible() then
		Refresh()
	end
end
