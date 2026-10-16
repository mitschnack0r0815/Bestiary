local _, ns = ...

-- A 2D card: rarity-colored frame, name, the family icon as art, stars, then attack, health
-- and speed. The small size (duel) adds a health bar and can play hits and deaths.
local Card = {}
ns.Card = Card

local SIZES = {
	big = { width = 104, height = 146, art = 52, name = "GameFontNormalSmall", stat = "GameFontHighlight" },
	small = { width = 88, height = 124, art = 40, name = "GameFontNormalSmall", stat = "GameFontHighlightSmall" },
}
local STAR = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_1"
local STAT_COLORS = { attack = { 1, 0.4, 0.35 }, health = { 0.35, 1, 0.4 }, speed = { 1, 0.85, 0.3 } }

local function Edge(frame, layer)
	local edges = {}
	for i = 1, 4 do
		edges[i] = frame:CreateTexture(nil, layer)
	end
	edges[1]:SetPoint("TOPLEFT")
	edges[1]:SetPoint("TOPRIGHT")
	edges[2]:SetPoint("BOTTOMLEFT")
	edges[2]:SetPoint("BOTTOMRIGHT")
	edges[3]:SetPoint("TOPLEFT")
	edges[3]:SetPoint("BOTTOMLEFT")
	edges[4]:SetPoint("TOPRIGHT")
	edges[4]:SetPoint("BOTTOMRIGHT")
	return edges
end

local function SetEdge(edges, width, r, g, b, a)
	edges[1]:SetHeight(width)
	edges[2]:SetHeight(width)
	edges[3]:SetWidth(width)
	edges[4]:SetWidth(width)
	for _, edge in ipairs(edges) do
		edge:SetColorTexture(r, g, b, a or 1)
	end
end

local Mixin = {}

function Card.Create(parent, size)
	local layout = SIZES[size]
	local card = CreateFrame("Button", nil, parent)
	for key, func in pairs(Mixin) do
		card[key] = func
	end
	card.layout = layout
	card:SetSize(layout.width, layout.height)
	card:RegisterForClicks("LeftButtonUp", "RightButtonUp")

	card.bg = card:CreateTexture(nil, "BACKGROUND")
	card.bg:SetAllPoints()
	card.bg:SetColorTexture(0.07, 0.06, 0.05, 0.95)
	card.tint = card:CreateTexture(nil, "BACKGROUND", nil, 1)
	card.tint:SetPoint("TOPLEFT", 3, -3)
	card.tint:SetPoint("BOTTOMRIGHT", -3, 3)
	card.edges = Edge(card, "BORDER")

	card.name = card:CreateFontString(nil, "OVERLAY", layout.name)
	card.name:SetPoint("TOPLEFT", 5, -5)
	card.name:SetPoint("TOPRIGHT", -5, -5)
	card.name:SetHeight(24)
	card.name:SetJustifyV("MIDDLE")

	card.art = card:CreateTexture(nil, "ARTWORK")
	card.art:SetSize(layout.art, layout.art)
	card.art:SetPoint("TOP", 0, -30)
	card.art:SetTexCoord(0.07, 0.93, 0.07, 0.93)
	card.artEdges = Edge(card, "ARTWORK")
	for _, edge in ipairs(card.artEdges) do
		edge:ClearAllPoints()
	end
	local a = card.art
	card.artEdges[1]:SetPoint("BOTTOMLEFT", a, "TOPLEFT", -1, 0)
	card.artEdges[1]:SetPoint("BOTTOMRIGHT", a, "TOPRIGHT", 1, 0)
	card.artEdges[2]:SetPoint("TOPLEFT", a, "BOTTOMLEFT", -1, 0)
	card.artEdges[2]:SetPoint("TOPRIGHT", a, "BOTTOMRIGHT", 1, 0)
	card.artEdges[3]:SetPoint("TOPRIGHT", a, "TOPLEFT")
	card.artEdges[3]:SetPoint("BOTTOMRIGHT", a, "BOTTOMLEFT")
	card.artEdges[4]:SetPoint("TOPLEFT", a, "TOPRIGHT")
	card.artEdges[4]:SetPoint("BOTTOMLEFT", a, "BOTTOMRIGHT")

	card.level = card:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
	card.level:SetPoint("BOTTOMRIGHT", card.art, "BOTTOMRIGHT", -1, 2)

	card.stars = {}
	for i = 1, 5 do
		local star = card:CreateTexture(nil, "OVERLAY")
		star:SetSize(11, 11)
		star:SetTexture(STAR)
		star:SetPoint("TOP", card.art, "BOTTOM", (i - 3) * 12, -3)
		card.stars[i] = star
	end

	card.stats = {}
	for i, stat in ipairs({ "attack", "health", "speed" }) do
		local text = card:CreateFontString(nil, "OVERLAY", layout.stat)
		text:SetPoint("BOTTOM", card, "BOTTOMLEFT", layout.width * (i * 2 - 1) / 6, size == "small" and 14 or 8)
		text:SetTextColor(unpack(STAT_COLORS[stat]))
		card.stats[stat] = text
		local label = card:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
		label:SetPoint("BOTTOM", text, "TOP", 0, 0)
		label:SetText(({ attack = "ATK", health = "HP", speed = "SPD" })[stat])
	end

	local highlight = card:CreateTexture(nil, "HIGHLIGHT")
	highlight:SetAllPoints()
	highlight:SetColorTexture(1, 1, 1, 0.08)

	card.selected = card:CreateTexture(nil, "OVERLAY", nil, 2)
	card.selected:SetAllPoints()
	card.selected:SetColorTexture(1, 0.82, 0, 0.12)
	card.selected:Hide()
	card.check = card:CreateTexture(nil, "OVERLAY", nil, 3)
	card.check:SetSize(18, 18)
	card.check:SetPoint("TOPRIGHT", -3, -3)
	card.check:SetTexture("Interface\\Buttons\\UI-CheckBox-Check")
	card.check:Hide()

	if size == "small" then
		card.bar = CreateFrame("StatusBar", nil, card)
		card.bar:SetPoint("BOTTOMLEFT", 5, 4)
		card.bar:SetPoint("BOTTOMRIGHT", -5, 4)
		card.bar:SetHeight(6)
		card.bar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
		card.bar:SetStatusBarColor(0.2, 0.85, 0.25)
		local barBg = card.bar:CreateTexture(nil, "BACKGROUND")
		barBg:SetAllPoints()
		barBg:SetColorTexture(0, 0, 0, 0.7)

		-- Red flash when hit
		card.flash = card:CreateTexture(nil, "OVERLAY", nil, 4)
		card.flash:SetAllPoints()
		card.flash:SetColorTexture(1, 0.1, 0.05, 0.5)
		card.flash:SetAlpha(0)
		card.flashAnim = card.flash:CreateAnimationGroup()
		local flashIn = card.flashAnim:CreateAnimation("Alpha")
		flashIn:SetFromAlpha(0)
		flashIn:SetToAlpha(1)
		flashIn:SetDuration(0.08)
		flashIn:SetOrder(1)
		local flashOut = card.flashAnim:CreateAnimation("Alpha")
		flashOut:SetFromAlpha(1)
		flashOut:SetToAlpha(0)
		flashOut:SetDuration(0.35)
		flashOut:SetOrder(2)

		-- Damage number floating up
		card.damage = card:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
		card.damage:SetPoint("CENTER", card.art, "CENTER")
		card.damage:SetTextColor(1, 0.25, 0.2)
		card.damage:SetAlpha(0)
		card.damageAnim = card.damage:CreateAnimationGroup()
		local appear = card.damageAnim:CreateAnimation("Alpha")
		appear:SetFromAlpha(0)
		appear:SetToAlpha(1)
		appear:SetDuration(0.05)
		local rise = card.damageAnim:CreateAnimation("Translation")
		rise:SetOffset(0, 30)
		rise:SetDuration(0.7)
		local fade = card.damageAnim:CreateAnimation("Alpha")
		fade:SetFromAlpha(1)
		fade:SetToAlpha(0)
		fade:SetStartDelay(0.4)
		fade:SetDuration(0.3)

		card.dead = card:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
		card.dead:SetPoint("CENTER", card.art, "CENTER")
		card.dead:SetText("X")
		card.dead:SetTextColor(0.9, 0.1, 0.1)
		card.dead:Hide()
	end

	card:SetScript("OnEnter", card.ShowTooltip)
	card:SetScript("OnLeave", GameTooltip_Hide)
	return card
end

function Mixin:SetCard(data)
	self.data = data
	local rarity = ns.RARITIES[data.classification]
	local family = ns.FAMILIES[data.family]
	local r, g, b = unpack(rarity.color)
	SetEdge(self.edges, 2, r, g, b)
	SetEdge(self.artEdges, 1, r * 0.7, g * 0.7, b * 0.7)
	local fr, fg, fb = unpack(family.color)
	self.tint:SetColorTexture(fr, fg, fb, 0.1)
	self.name:SetText(data.name)
	self.name:SetTextColor(r, g, b)
	self.art:SetTexture(family.icon)
	self.level:SetText(data.level)
	for i, star in ipairs(self.stars) do
		star:SetShown(i <= data.stars)
	end
	self.stats.attack:SetText(data.attack)
	self.stats.health:SetText(data.health)
	self.stats.speed:SetText(data.speed)
	if self.bar then
		self:SetHealth(data.health)
		self:SetDead(false)
	end
end

function Mixin:SetSelected(selected)
	self.selected:SetShown(selected)
	self.check:SetShown(selected)
end

function Mixin:ShowTooltip()
	local data = self.data
	if not data then
		return
	end
	local rarity = ns.RARITIES[data.classification]
	GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
	GameTooltip:AddLine(data.name, unpack(rarity.color))
	GameTooltip:AddLine(("Level %d %s  ·  %s"):format(data.level, data.family, rarity.name), 1, 1, 1)
	GameTooltip:AddLine(("%d of 5 stars  ·  Power %d"):format(data.stars, data.power), 0.8, 0.8, 0.8)
	GameTooltip:AddLine(" ")
	GameTooltip:AddLine(data.ability, 1, 0.82, 0, true)
	GameTooltip:AddLine(" ")
	GameTooltip:AddLine("Caught in " .. data.zone, 0.6, 0.6, 0.6)
	GameTooltip:Show()
end

function Mixin:SetHealth(hp)
	self.bar:SetMinMaxValues(0, self.data.health)
	self.bar:SetValue(hp)
	self.stats.health:SetText(hp)
	local part = hp / self.data.health
	self.bar:SetStatusBarColor(part > 0.5 and 0.2 or 0.9, part > 0.25 and 0.85 or 0.2, 0.2)
end

function Mixin:Hit(damage, hp)
	self:SetHealth(hp)
	self.damage:SetText("-" .. damage)
	self.damageAnim:Stop()
	self.damageAnim:Play()
	self.flashAnim:Stop()
	self.flashAnim:Play()
end

function Mixin:SetDead(dead)
	self:SetAlpha(dead and 0.4 or 1)
	self.art:SetDesaturated(dead)
	self.dead:SetShown(dead)
end

-- Lunges toward the enemy and back. direction: 1 up, -1 down
function Mixin:Lunge(direction)
	if not self.lunge then
		self.lunge = self:CreateAnimationGroup()
		self.lungeOut = self.lunge:CreateAnimation("Translation")
		self.lungeOut:SetDuration(0.12)
		self.lungeOut:SetOrder(1)
		self.lungeBack = self.lunge:CreateAnimation("Translation")
		self.lungeBack:SetDuration(0.18)
		self.lungeBack:SetOrder(2)
	end
	self.lungeOut:SetOffset(0, 16 * direction)
	self.lungeBack:SetOffset(0, -16 * direction)
	self.lunge:Stop()
	self.lunge:Play()
end
