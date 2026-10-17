local _, ns = ...

-- PROTOTYPE page: the mob types you're studying (no card yet), most studied first: progress to
-- the STUDY_SECONDS needed before a kill can drop the card, and what the card would be so far.
-- Hover a row for the details.
local WIDTH = ns.WINDOW_WIDTH
local ROW = 24
local INSET = C_XMLUtil and C_XMLUtil.GetTemplateInfo and C_XMLUtil.GetTemplateInfo("InsetFrameTemplate")
	and "InsetFrameTemplate" or nil

local page = ns.AddPage("Studying", "Interface\\Icons\\Spell_Holy_MagicalSentry", 2)

local title = page:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
title:SetPoint("TOPLEFT", 72, -34)
title:SetText("Studying")
local summary = page:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
summary:SetPoint("LEFT", title, "RIGHT", 14, 0)
local help = page:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
help:SetPoint("TOPLEFT", 72, -56)
help:SetText(("Once you've seen a kind of mob fighting for %d seconds (anyone fighting it counts), killing one can drop its card."):format(ns.STUDY_SECONDS))

-- Column headers
local headers = {}
local function Header(text, x)
	local header = page:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	header:SetPoint("TOPLEFT", 22 + x, -82)
	header:SetText(text)
	headers[#headers + 1] = header
end
Header("Mob", 0)
Header("Progress", 250)
Header("Card so far", 470)
Header("Casts", 590)

local inset = CreateFrame("Frame", nil, page, INSET)
inset:SetPoint("TOPLEFT", 8, -98)
inset:SetPoint("BOTTOMRIGHT", -8, 8)
local scroll = CreateFrame("ScrollFrame", nil, inset, "UIPanelScrollFrameTemplate")
scroll:SetPoint("TOPLEFT", 8, -8)
scroll:SetPoint("BOTTOMRIGHT", -28, 8)
local list = CreateFrame("Frame", nil, scroll)
list:SetSize(WIDTH - 60, 10)
scroll:SetScrollChild(list)
local empty = inset:CreateFontString(nil, "OVERLAY", "GameFontDisable")
empty:SetPoint("CENTER")
empty:SetText("Nothing studied yet. Fight something, or watch others fight.")

local rows = {}

local function Icon(path)
	return ("|T%s:16:16:0:0:64:64:5:59:5:59|t"):format(path)
end

local function Row(i)
	local row = CreateFrame("Frame", nil, list)
	row:SetSize(WIDTH - 70, ROW)
	row:SetPoint("TOPLEFT", 0, -(i - 1) * ROW)
	row:EnableMouse(true)
	if i % 2 == 0 then
		local stripe = row:CreateTexture(nil, "BACKGROUND")
		stripe:SetAllPoints()
		stripe:SetColorTexture(1, 1, 1, 0.03)
	end
	local highlight = row:CreateTexture(nil, "HIGHLIGHT")
	highlight:SetAllPoints()
	highlight:SetColorTexture(1, 1, 1, 0.07)
	row.family = row:CreateTexture(nil, "ARTWORK")
	row.family:SetSize(18, 18)
	row.family:SetPoint("LEFT", 4, 0)
	row.family:SetTexCoord(0.07, 0.93, 0.07, 0.93)
	row.name = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	row.name:SetPoint("LEFT", row.family, "RIGHT", 6, 0)
	row.name:SetWidth(220)
	row.name:SetJustifyH("LEFT")
	row.name:SetWordWrap(false)
	row.bar = CreateFrame("StatusBar", nil, row)
	row.bar:SetPoint("LEFT", 254, 0)
	row.bar:SetSize(160, 12)
	row.bar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
	row.bar:SetMinMaxValues(0, ns.STUDY_SECONDS)
	local bg = row.bar:CreateTexture(nil, "BACKGROUND")
	bg:SetAllPoints()
	bg:SetColorTexture(0, 0, 0, 0.6)
	row.value = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	row.value:SetPoint("LEFT", row.bar, "RIGHT", 8, 0)
	row.card = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	row.card:SetPoint("LEFT", 474, 0)
	row.casts = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	row.casts:SetPoint("LEFT", 594, 0)

	row:SetScript("OnEnter", function(self)
		local entry, info = self.entry, self.info
		if not entry then
			return
		end
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:AddLine(self.mobName, 1, 0.82, 0)
		if info then
			local rarity = ns.RARITIES[info.classification] or ns.RARITIES.normal
			GameTooltip:AddLine(("%s  ·  %s"):format(rarity.name, tostring(info.creatureType)), 1, 1, 1)
		end
		GameTooltip:AddLine(("Studied %.1f of %d seconds"):format(entry.seconds, ns.STUDY_SECONDS), 0.8, 0.8, 0.8)
		if self.view then
			local _, why = ns.TypeFrom(entry, info and info.family, info, self.npcId)
			GameTooltip:AddLine(("Card so far: %s, power %d"):format(self.view.type, self.view.power), 1, 1, 1)
			GameTooltip:AddLine(why, 0.6, 0.6, 0.6, true)
		end
		local spells = {}
		for spell, count in pairs(entry.spells) do
			spells[#spells + 1] = ("%s x%d"):format(spell, count)
		end
		if #spells > 0 then
			table.sort(spells)
			GameTooltip:AddLine("Spells: " .. table.concat(spells, ", "), 0.6, 0.8, 1, true)
		end
		GameTooltip:Show()
	end)
	row:SetScript("OnLeave", GameTooltip_Hide)
	return row
end

local function Refresh()
	local studying = ns.Studying()
	local ready = 0
	for i, item in ipairs(studying) do
		local row = rows[i] or Row(i)
		rows[i] = row
		local entry = ns.Studied(item.npcId)
		local info = ns.MobInfo(item.npcId)
		local view = ns.BuildCard(item.npcId)
		row.entry, row.info, row.view, row.mobName, row.npcId = entry, info, view, item.name, item.npcId
		local rarity = ns.RARITIES[info and info.classification or "normal"] or ns.RARITIES.normal
		local family = info and info.family and ns.FAMILIES[info.family]
		row.family:SetTexture(family and family.icon or "Interface\\Icons\\INV_Misc_QuestionMark")
		row.name:SetText(item.name)
		row.name:SetTextColor(unpack(rarity.color))
		local done = item.seconds >= ns.STUDY_SECONDS
		if done then
			ready = ready + 1
		end
		row.bar:SetValue(math.min(item.seconds, ns.STUDY_SECONDS))
		row.bar:SetStatusBarColor(done and 0.25 or 0.55, done and 0.85 or 0.45, done and 0.3 or 1)
		row.value:SetText(done and "|cff40ff40ready|r" or ("%d%%"):format(item.seconds / ns.STUDY_SECONDS * 100))
		if view then
			local kind = ns.TYPES[view.type]
			row.card:SetText(("%s %s"):format(Icon(kind.icon), view.type))
		else
			row.card:SetText("|cff999999?|r")
		end
		row.casts:SetText(entry and entry.casts > 0 and entry.casts or "|cff999999-|r")
		row:Show()
	end
	for i = #studying + 1, #rows do
		rows[i]:Hide()
	end
	list:SetHeight(math.max(10, #studying * ROW))
	empty:SetShown(#studying == 0)
	summary:SetText(("%d mob types  ·  %d ready to drop"):format(#studying, ready))
end

page:SetScript("OnShow", Refresh)

-- Keep the bars moving while it's open
local elapsed = 0
page:SetScript("OnUpdate", function(_, delta)
	elapsed = elapsed + delta
	if elapsed >= 1 then
		elapsed = 0
		Refresh()
	end
end)

local refreshBefore = ns.Refresh
function ns.Refresh()
	if refreshBefore then
		refreshBefore()
	end
	if page:IsVisible() then
		Refresh()
	end
end
