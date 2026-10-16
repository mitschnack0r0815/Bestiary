local _, ns = ...

-- A 2D card: rounded frame in the rarity color (the game's tooltip border), the family icon as
-- round portrait art with a rarity ring, a round combat type badge, level, stars, then attack,
-- health and speed. Below them a bar: stamina (squad builder) or health (duel), which can play
-- hits and deaths.
local Card = {}
ns.Card = Card

Card.WIDTH, Card.HEIGHT = 86, 128

local ART = 44
local BADGE = 18
local STAR = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_1"
local CROWN = "Interface\\GroupFrame\\UI-Group-LeaderIcon"
local ROUND_MASK = "Interface\\CharacterFrame\\TempPortraitAlphaMask"
local STAT_COLORS = { attack = { 1, 0.45, 0.4 }, health = { 0.4, 1, 0.45 }, speed = { 1, 0.85, 0.35 } }

local BACKDROP = {
	bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
	edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
	tile = true, tileSize = 16, edgeSize = 14,
	insets = { left = 4, right = 4, top = 4, bottom = 4 },
}

-- Makes a texture round (falls back to square on clients without mask textures)
local function Round(frame, texture)
	if not frame.CreateMaskTexture then
		return
	end
	local mask = frame:CreateMaskTexture()
	mask:SetTexture(ROUND_MASK, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
	mask:SetAllPoints(texture)
	texture:AddMaskTexture(mask)
end

-- A round picture with a colored ring around it
local function Medallion(frame, size, ring, layer)
	local holder = {}
	holder.ring = frame:CreateTexture(nil, layer, nil, 1)
	holder.ring:SetSize(size + 4, size + 4)
	holder.ring:SetColorTexture(1, 1, 1)
	Round(frame, holder.ring)
	holder.icon = frame:CreateTexture(nil, layer, nil, 2)
	holder.icon:SetSize(size, size)
	holder.icon:SetPoint("CENTER", holder.ring)
	Round(frame, holder.icon)
	return holder
end

local Mixin = {}

function Card.Create(parent)
	local card = CreateFrame("Button", nil, parent, BackdropTemplateMixin and "BackdropTemplate" or nil)
	for key, func in pairs(Mixin) do
		card[key] = func
	end
	card:SetSize(Card.WIDTH, Card.HEIGHT)
	card:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	if card.SetBackdrop then
		card:SetBackdrop(BACKDROP)
		card:SetBackdropColor(0.07, 0.06, 0.06, 0.96)
	end

	-- Soft family color over the top half
	card.tint = card:CreateTexture(nil, "BACKGROUND", nil, 1)
	card.tint:SetPoint("TOPLEFT", 4, -4)
	card.tint:SetPoint("TOPRIGHT", -4, -4)
	card.tint:SetHeight(Card.HEIGHT / 2)

	card.name = card:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	card.name:SetPoint("TOPLEFT", 6, -6)
	card.name:SetPoint("TOPRIGHT", -6, -6)
	card.name:SetHeight(22)
	card.name:SetJustifyV("MIDDLE")
	card.name:SetWordWrap(true)

	card.art = Medallion(card, ART, nil, "ARTWORK")
	card.art.ring:SetPoint("TOP", 0, -28)

	card.badge = Medallion(card, BADGE, nil, "OVERLAY")
	card.badge.ring:SetPoint("CENTER", card.art.ring, "BOTTOMLEFT", 7, 7)

	card.levelBg = card:CreateTexture(nil, "OVERLAY", nil, 1)
	card.levelBg:SetSize(20, 20)
	card.levelBg:SetPoint("CENTER", card.art.ring, "BOTTOMRIGHT", -7, 7)
	card.levelBg:SetColorTexture(0, 0, 0, 0.85)
	Round(card, card.levelBg)
	card.level = card:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
	card.level:SetPoint("CENTER", card.levelBg)

	card.crown = card:CreateTexture(nil, "OVERLAY", nil, 3)
	card.crown:SetSize(18, 18)
	card.crown:SetPoint("CENTER", card.art.ring, "TOPLEFT", 6, -4)
	card.crown:SetTexture(CROWN)
	card.crown:Hide()

	card.stars = {}
	for i = 1, 5 do
		local star = card:CreateTexture(nil, "OVERLAY")
		star:SetSize(10, 10)
		star:SetTexture(STAR)
		star:SetPoint("TOP", card.art.ring, "BOTTOM", (i - 3) * 11, -3)
		card.stars[i] = star
	end

	card.stats = {}
	for i, stat in ipairs({ "attack", "health", "speed" }) do
		local text = card:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		text:SetPoint("BOTTOM", card, "BOTTOMLEFT", 6 + (Card.WIDTH - 12) * (i * 2 - 1) / 6, 14)
		text:SetTextColor(unpack(STAT_COLORS[stat]))
		card.stats[stat] = text
		local label = card:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
		label:SetPoint("BOTTOM", text, "TOP", 0, 0)
		label:SetText(({ attack = "ATK", health = "HP", speed = "SPD" })[stat])
		label:SetScale(0.85)
	end

	card.bar = CreateFrame("StatusBar", nil, card)
	card.bar:SetPoint("BOTTOMLEFT", 8, 7)
	card.bar:SetPoint("BOTTOMRIGHT", -8, 7)
	card.bar:SetHeight(5)
	card.bar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
	local barBg = card.bar:CreateTexture(nil, "BACKGROUND")
	barBg:SetAllPoints()
	barBg:SetColorTexture(0, 0, 0, 0.7)
	card.bar:Hide()

	local highlight = card:CreateTexture(nil, "HIGHLIGHT")
	highlight:SetPoint("TOPLEFT", 4, -4)
	highlight:SetPoint("BOTTOMRIGHT", -4, 4)
	highlight:SetColorTexture(1, 1, 1, 0.07)

	card.check = card:CreateTexture(nil, "OVERLAY", nil, 4)
	card.check:SetSize(20, 20)
	card.check:SetPoint("TOPRIGHT", 0, 2)
	card.check:SetTexture("Interface\\Buttons\\UI-CheckBox-Check")
	card.check:Hide()

	-- Exhausted: darkened, with a note
	card.tired = card:CreateTexture(nil, "OVERLAY", nil, 5)
	card.tired:SetPoint("TOPLEFT", 4, -4)
	card.tired:SetPoint("BOTTOMRIGHT", -4, 4)
	card.tired:SetColorTexture(0, 0, 0, 0.6)
	card.tiredText = card:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	card.tiredText:SetPoint("CENTER", card.art.ring)
	card.tiredText:SetTextColor(1, 0.4, 0.3)

	-- Red flash when hit
	card.flash = card:CreateTexture(nil, "OVERLAY", nil, 6)
	card.flash:SetPoint("TOPLEFT", 4, -4)
	card.flash:SetPoint("BOTTOMRIGHT", -4, 4)
	card.flash:SetColorTexture(1, 0.1, 0.05, 0.45)
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
	card.damage:SetPoint("CENTER", card.art.ring)
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
	card.dead:SetPoint("CENTER", card.art.ring)
	card.dead:SetText("X")
	card.dead:SetTextColor(0.9, 0.1, 0.1)
	card.dead:Hide()

	card:SetScript("OnEnter", card.ShowTooltip)
	card:SetScript("OnLeave", GameTooltip_Hide)
	return card
end

-- bar: "stamina", "health" or nil
function Mixin:SetCard(data, bar)
	self.data = data
	local rarity = ns.RARITIES[data.classification]
	local family = ns.FAMILIES[data.family]
	local kind = ns.TYPES[data.type]
	local r, g, b = unpack(rarity.color)
	if self.SetBackdropBorderColor then
		self:SetBackdropBorderColor(r, g, b, 1)
	end
	local fr, fg, fb = unpack(family.color)
	self.tint:SetColorTexture(fr, fg, fb, 0.12)
	self.name:SetText(data.name)
	self.name:SetTextColor(r, g, b)
	self.art.ring:SetVertexColor(r, g, b)
	self.art.icon:SetTexture(family.icon)
	self.badge.ring:SetVertexColor(unpack(kind.color))
	self.badge.icon:SetTexture(kind.icon)
	self.level:SetText(data.level)
	for i, star in ipairs(self.stars) do
		star:SetShown(i <= data.stars)
	end
	self.stats.attack:SetText(data.attack)
	self.stats.health:SetText(data.health)
	self.stats.speed:SetText(data.speed)

	self.barKind = bar
	self.bar:SetShown(bar ~= nil)
	if bar == "stamina" then
		self.bar:SetMinMaxValues(0, 100)
		self.bar:SetValue(data.stamina)
		self.bar:SetStatusBarColor(0.25, 0.55, 1)
	elseif bar == "health" then
		self:SetHealth(data.health)
	end
	local tired = bar == "stamina" and data.exhausted
	self.tired:SetShown(tired)
	self.tiredText:SetShown(tired)
	if tired then
		self.tiredText:SetText(("Exhausted\n%d duels"):format(data.exhausted))
	end
	self:SetDead(false)
	self:SetLeader(false)
	self:SetSelected(false)
end

function Mixin:SetSelected(selected)
	self.check:SetShown(selected)
end

function Mixin:SetLeader(leader)
	self.crown:SetShown(leader)
end

function Mixin:ShowTooltip()
	local data = self.data
	if not data then
		return
	end
	local rarity = ns.RARITIES[data.classification]
	local kind = ns.TYPES[data.type]
	GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
	GameTooltip:AddLine(data.name, unpack(rarity.color))
	GameTooltip:AddLine(("Level %d %s  ·  %s"):format(data.level, data.family, rarity.name), 1, 1, 1)
	GameTooltip:AddLine(data.type, unpack(kind.color))
	GameTooltip:AddLine(("%d of 5 stars  ·  Power %d"):format(data.stars, data.power), 0.8, 0.8, 0.8)
	GameTooltip:AddLine(" ")
	GameTooltip:AddDoubleLine("Attack", data.attack, 1, 1, 1, 1, 1, 1)
	GameTooltip:AddDoubleLine("Health", data.health, 1, 1, 1, 1, 1, 1)
	GameTooltip:AddDoubleLine("Speed", data.speed, 1, 1, 1, 1, 1, 1)
	if data.armor > 0 then
		GameTooltip:AddDoubleLine("Armor", data.armor, 1, 1, 1, 1, 1, 1)
	end
	GameTooltip:AddDoubleLine("Stamina", data.stamina .. " / 100", 1, 1, 1, 1, 1, 1)
	GameTooltip:AddLine(" ")
	if data.classification ~= "normal" then
		GameTooltip:AddLine(kind.leader, 1, 0.82, 0, true)
	end
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

function Mixin:Hit(damage, hp, magic)
	self:SetHealth(hp)
	self.damage:SetText("-" .. damage)
	if magic then
		self.damage:SetTextColor(0.6, 0.6, 1)
	else
		self.damage:SetTextColor(1, 0.25, 0.2)
	end
	self.damageAnim:Stop()
	self.damageAnim:Play()
	self.flashAnim:Stop()
	self.flashAnim:Play()
end

function Mixin:SetDead(dead)
	self:SetAlpha(dead and 0.45 or 1)
	self.art.icon:SetDesaturated(dead)
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
