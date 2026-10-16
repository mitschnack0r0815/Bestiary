local _, ns = ...

-- Card drops as an alert like the game's loss of control alert: a dark band in the middle of
-- the upper half of the screen with the card's art, "New card" or "+1 star", its name in the
-- rarity color and what it is. It shows right away, stays a few seconds, then fades; more
-- drops queue up. Hovering keeps it and shows the card, clicking opens the collection.
local SHOW = 4 -- seconds fully visible
local FADE = 0.8
local Y = 170 -- above the screen's center...
local RAISE = 0.15 -- ...plus this share of the screen height

local alert = CreateFrame("Button", "BestiaryDropAlert", UIParent)
alert:SetSize(460, 84)
alert:SetFrameStrata("HIGH")
alert:SetClampedToScreen(true)
alert:RegisterForClicks("LeftButtonUp", "RightButtonUp")
alert:Hide()

-- Dark band, fading out to the sides
local function Band(point, x, width, alphaInner, alphaOuter)
	local band = alert:CreateTexture(nil, "BACKGROUND")
	band:SetPoint("TOP", x, 0)
	band:SetPoint("BOTTOM", x, 0)
	band:SetWidth(width)
	band:SetColorTexture(0, 0, 0, 1)
	if band.SetGradient and CreateColor then
		local inner, outer = CreateColor(0, 0, 0, alphaInner), CreateColor(0, 0, 0, alphaOuter)
		if point == "LEFT" then
			band:SetGradient("HORIZONTAL", outer, inner)
		else
			band:SetGradient("HORIZONTAL", inner, outer)
		end
	else
		band:SetAlpha(alphaInner)
	end
	return band
end
local middle = alert:CreateTexture(nil, "BACKGROUND")
middle:SetPoint("TOP")
middle:SetPoint("BOTTOM")
middle:SetWidth(260)
middle:SetColorTexture(0, 0, 0, 0.7)
Band("LEFT", -230, 200, 0.7, 0)
Band("RIGHT", 230, 200, 0.7, 0)

-- Thin lines above and below in the rarity color, fading to the sides like the band
local lines = {}
for _, edge in ipairs({ "TOP", "BOTTOM" }) do
	for _, side in ipairs({ -1, 1 }) do
		local line = alert:CreateTexture(nil, "BORDER")
		line:SetHeight(2)
		line:SetWidth(230)
		line:SetPoint(edge, alert, edge, side * 115, 0)
		line:SetColorTexture(1, 1, 1, 1)
		line.side = side
		lines[#lines + 1] = line
	end
end

-- Round art like the cards: a ring in the rarity color, the icon or the creature inside
local function Round(texture)
	if alert.CreateMaskTexture then
		local mask = alert:CreateMaskTexture()
		mask:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
		mask:SetAllPoints(texture)
		texture:AddMaskTexture(mask)
	end
end
local icon = alert:CreateTexture(nil, "ARTWORK", nil, 2)
icon:SetSize(60, 60)
icon:SetPoint("LEFT", 94, 0)
Round(icon)
-- The model fits inside the circle (the band behind is see-through, so no cover here)
local portrait = CreateFrame("PlayerModel", nil, alert)
portrait:SetSize(42, 42)
portrait:SetPoint("CENTER", icon)
-- The ring above the model
local above = CreateFrame("Frame", nil, alert)
above:SetAllPoints()
above:SetFrameLevel(portrait:GetFrameLevel() + 1)
local iconBorder = above:CreateTexture(nil, "ARTWORK")
iconBorder:SetSize(68, 68)
iconBorder:SetPoint("CENTER", icon)
iconBorder:SetTexture(ns.RING)
portrait:Hide()
ns.SetupPortrait(portrait)

local kind = alert:CreateFontString(nil, "OVERLAY", "GameFontNormal")
kind:SetPoint("TOPLEFT", iconBorder, "TOPRIGHT", 14, -2)
local name = alert:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
name:SetPoint("TOPLEFT", kind, "BOTTOMLEFT", 0, -3)
name:SetJustifyH("LEFT")
local info = alert:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
info:SetPoint("TOPLEFT", name, "BOTTOMLEFT", 0, -3)

local queue = {} -- { view, result, tag }
local current, shownAt

local function Sound(...)
	for i = 1, select("#", ...) do
		local sound = SOUNDKIT[select(i, ...)]
		if sound then
			PlaySound(sound)
			return
		end
	end
end

local function Colored(color, text)
	local r, g, b = unpack(color)
	return ("|cff%02x%02x%02x%s|r"):format(r * 255, g * 255, b * 255, text)
end

local function Display(entry)
	current = entry
	local view = entry.view
	local rarity = ns.RARITIES[view.classification] or ns.RARITIES.normal
	local r, g, b = unpack(rarity.color)
	icon:SetTexture(view.art or ns.FAMILIES[view.family].icon)
	ns.SetPortrait(portrait, icon, view)
	iconBorder:SetVertexColor(r, g, b, 1)
	for _, line in ipairs(lines) do
		if line.SetGradient and CreateColor then
			local solid, clear = CreateColor(r, g, b, 1), CreateColor(r, g, b, 0)
			if line.side < 0 then
				line:SetGradient("HORIZONTAL", clear, solid)
			else
				line:SetGradient("HORIZONTAL", solid, clear)
			end
		else
			line:SetColorTexture(r, g, b, 0.8)
		end
	end
	local what = entry.result == "new" and "NEW CARD"
		or entry.result == "copy" and ("COPY %d OF %d"):format(ns.Copies(view), ns.MAX_COPIES)
		or entry.result == "max" and ("ALREADY " .. ns.MAX_STARS .. " STARS")
		or ("+1 STAR  ·  " .. view.stars .. " of " .. ns.MAX_STARS)
	kind:SetText(entry.tag and (what .. "  |cffff8040(" .. entry.tag .. ")|r") or what)
	name:SetText(view.name)
	name:SetTextColor(r, g, b)
	local kindInfo = ns.TYPES[view.type]
	info:SetText(("%s  ·  %s  ·  %s  ·  Power %d"):format(
		kindInfo and Colored(kindInfo.color, view.type) or view.type, rarity.name, view.family, view.power))
	shownAt = GetTime()
	alert:ClearAllPoints()
	alert:SetPoint("CENTER", UIParent, "CENTER", 0, Y + UIParent:GetHeight() * RAISE)
	alert:SetAlpha(1)
	alert:Show()
	if view.classification ~= "normal" then
		Sound("UI_EPICLOOT_TOAST", "RAID_WARNING", "READY_CHECK")
	else
		Sound("LOOTWINDOWCOINSOUND", "IG_BACKPACK_OPEN")
	end
end

local function ShowNext()
	local entry = tremove(queue, 1)
	if entry then
		Display(entry)
	else
		current = nil
		alert:Hide()
	end
end

-- Stays while hovered, then fades
alert:SetScript("OnUpdate", function(self)
	if not current then
		return
	end
	if self:IsMouseOver() then
		shownAt = GetTime()
		self:SetAlpha(1)
		return
	end
	local age = GetTime() - shownAt
	if age > SHOW + FADE then
		ShowNext()
	elseif age > SHOW then
		self:SetAlpha(1 - (age - SHOW) / FADE)
	end
end)

alert:SetScript("OnEnter", function(self)
	if current then
		ns.Card.ShowTooltipFor(self, current.view)
	end
end)
alert:SetScript("OnLeave", GameTooltip_Hide)
alert:SetScript("OnClick", function(_, button)
	if button == "LeftButton" then
		ns.Show("Collection")
	end
	ShowNext()
end)

-- A card dropped (the first argument, the mob's GUID, isn't needed any more). tag (test tab):
-- shown next to "New card".
function ns.ShowLoot(_, view, result, tag)
	queue[#queue + 1] = { view = view, result = result, tag = tag }
	if not current then
		ShowNext()
	end
end
