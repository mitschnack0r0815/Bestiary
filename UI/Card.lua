local _, ns = ...

-- A 2D card: rounded frame in the rarity color (the game's tooltip border), the name, round art
-- (the creature's 3D portrait, or its spell or family icon) in a ring of the rarity color (the
-- dragon ring for leaders), the combat type badge bottom left and the family badge bottom right,
-- stars, then attack, health and speed. Below them a bar: stamina (squad builder) or health
-- (duel), which can play hits and deaths.
local Card = {}
ns.Card = Card

Card.WIDTH, Card.HEIGHT = 86, 128

local ART = 44
local BADGE = 18
local STAR = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_1"
local DRAGON_SIZE = 1.7 -- the dragon ring around leaders, times the art size
-- Models can't be cut round, so the round frame is drawn above the model: a cover in the card's
-- color hides the model's corners outside the circle, the ring sits on top of that
local RING = "Interface\\AddOns\\Bestiary\\Media\\RingBorder"
local COVER = "Interface\\AddOns\\Bestiary\\Media\\RingCover"
local CARD_BG = { 0.07, 0.06, 0.06 }
ns.RING, ns.RING_COVER = RING, COVER
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

-- The creature's 3D portrait in a model frame over an art texture, zoomed onto its face like
-- the target frame. The game draws any creature it has seen by NPC id; until the model is
-- there (or if it never is), the icon in the art texture shows. Made-up cards have no NPC id.
local PORTRAIT_BG = { 0.09, 0.08, 0.1 }

-- Stands still: no idle animation, facing the camera
local function Freeze(model)
	if model.SetRotation then
		model:SetRotation(0)
	end
	if model.FreezeAnimation then
		model:FreezeAnimation(0, 0, 0)
	elseif model.SetAnimation then
		model:SetAnimation(0)
	end
	if model.SetPaused then
		model:SetPaused(true)
	end
end

-- The dragon ring around leaders: the game's elite dragon border if this client has the atlas,
-- else the dragon cut from the elite target frame
local DRAGON_ATLASES = { "worldquest-questmarker-dragon", "worldquest-questmarker-dragon-silver" }
local function SetDragon(texture)
	if texture.SetAtlas and C_Texture and C_Texture.GetAtlasInfo then
		for _, atlas in ipairs(DRAGON_ATLASES) do
			if C_Texture.GetAtlasInfo(atlas) then
				texture:SetAtlas(atlas)
				texture.atlas = true
				return
			end
		end
	end
	-- UI-TargetingFrame-Elite: 256 x 128, the portrait's center at about (182, 44); the dragon
	-- curls around it to the top and right
	texture:SetTexture("Interface\\TargetingFrame\\UI-TargetingFrame-Elite")
	texture:SetTexCoord(118 / 256, 246 / 256, 0, 108 / 128)
end
ns.SetDragon = SetDragon

function ns.SetPortrait(model, art, data)
	-- no model for training cards, nor for another player's own card (we can't show them)
	if not (data.npcId and model.SetCreature) or (data.player and data.remote) then
		model:Hide()
		return
	end
	model.art, model.icon = art, data.art or ns.FAMILIES[data.family].icon
	local key = data.player and "player" or data.npcId -- your own card shows you
	if model.npcId ~= key then
		model.npcId = key
		model.loaded = false
		model:ClearModel()
		if data.player then
			model:SetUnit("player")
		else
			model:SetCreature(data.npcId)
		end
	end
	if model.SetPortraitZoom then
		model:SetPortraitZoom(1)
	end
	if model.loaded then
		art:SetColorTexture(unpack(PORTRAIT_BG))
		Freeze(model)
	end
	model:Show()
end

local function OnModelLoaded(model)
	model.loaded = true
	if model.art then
		model.art:SetColorTexture(unpack(PORTRAIT_BG)) -- a plain backdrop behind the model
	end
	if model.SetPortraitZoom then
		model:SetPortraitZoom(1)
	end
	Freeze(model)
end

function ns.SetupPortrait(model)
	model:SetScript("OnModelLoaded", OnModelLoaded)
end

-- Cards in a scroll frame: models may not be clipped by it, so a card's model only shows while
-- its art is fully inside the visible part. Hooked to the scroll frame; call after laying out.
function ns.ClipCards(scroll, cards)
	local function Clip()
		local top, bottom = scroll:GetTop(), scroll:GetBottom()
		if not top then
			return
		end
		for _, card in ipairs(cards) do
			local artTop, artBottom = card.art:GetTop(), card.art:GetBottom()
			local inside = artTop and artTop <= top + 1 and artBottom >= bottom - 1
			card.model:SetAlpha(inside and 1 or 0)
		end
	end
	if not scroll.clipHooked then
		scroll.clipHooked = true
		scroll:HookScript("OnVerticalScroll", Clip)
		scroll:HookScript("OnScrollRangeChanged", Clip)
		scroll:HookScript("OnShow", Clip)
	end
	scroll.clipCards = cards
	Clip()
	C_Timer.After(0, Clip) -- once the new layout has positions
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

	card.name = card:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	card.name:SetPoint("TOPLEFT", 6, -6)
	card.name:SetPoint("TOPRIGHT", -26, -6) -- room for the power gem
	card.name:SetHeight(22)
	card.name:SetJustifyV("MIDDLE")
	card.name:SetWordWrap(true)

	-- Round art: the icon (or a dark backdrop) cut round; the ring goes on the layer above the model
	card.art = card:CreateTexture(nil, "ARTWORK", nil, 2)
	card.art:SetSize(ART, ART)
	card.art:SetPoint("TOP", 0, -34)
	Round(card, card.art)

	-- The creature's 3D portrait over the art (cards from real mobs); the icon stays as the
	-- fallback underneath. Models draw above the card's textures, so everything that has to be
	-- on top of the art lives on its own layer above the model.
	card.model = CreateFrame("PlayerModel", nil, card)
	card.model:SetAllPoints(card.art)
	card.model:SetFrameLevel(card:GetFrameLevel() + 1)
	card.model:Hide()
	ns.SetupPortrait(card.model)
	card.top = CreateFrame("Frame", nil, card)
	card.top:SetAllPoints()
	card.top:SetFrameLevel(card:GetFrameLevel() + 2)
	local top = card.top

	-- Above the model: the cover hides its corners outside the circle, then the ring
	card.cover = top:CreateTexture(nil, "ARTWORK", nil, 1)
	card.cover:SetSize(ART + 6, ART + 6)
	card.cover:SetPoint("CENTER", card.art)
	card.cover:SetTexture(COVER)
	card.ring = top:CreateTexture(nil, "ARTWORK", nil, 2)
	card.ring:SetSize(ART + 6, ART + 6)
	card.ring:SetPoint("CENTER", card.art)
	card.ring:SetTexture(RING)

	card.badge = Medallion(top, BADGE, nil, "OVERLAY")
	card.badge.ring:SetPoint("CENTER", card.art, "BOTTOMLEFT", 2, 3)
	-- The family on the other side
	card.familyBadge = Medallion(top, BADGE, nil, "OVERLAY")
	card.familyBadge.ring:SetPoint("CENTER", card.art, "BOTTOMRIGHT", -2, 3)

	-- Power, in the top right corner: a gold number in a dark round gem with a gold rim
	-- How many copies (normal cards): "2x" in the top left corner, beside the art
	card.count = top:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
	card.count:SetPoint("CENTER", card, "TOPLEFT", 13, -40)
	card.count:SetTextColor(1, 0.82, 0.2)
	card.count:Hide()

	card.powerRim = top:CreateTexture(nil, "OVERLAY", nil, 3)
	card.powerRim:SetSize(24, 24)
	card.powerRim:SetPoint("CENTER", card, "TOPRIGHT", -13, -13) -- the card's top right corner
	card.powerRim:SetColorTexture(1, 0.82, 0.2)
	Round(top, card.powerRim)
	card.powerBg = top:CreateTexture(nil, "OVERLAY", nil, 4)
	card.powerBg:SetSize(21, 21)
	card.powerBg:SetPoint("CENTER", card.powerRim)
	card.powerBg:SetColorTexture(0.08, 0.06, 0.04)
	Round(top, card.powerBg)
	card.power = top:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
	card.power:SetPoint("CENTER", card.powerRim, "CENTER", 0, 0)
	card.power:SetTextColor(1, 0.82, 0.2)

	-- Leaders: the dragon ring around the art
	card.dragon = top:CreateTexture(nil, "OVERLAY", nil, 1)
	card.dragon:SetPoint("CENTER", card.art, "CENTER", 0, 0)
	SetDragon(card.dragon)
	if card.dragon.atlas then
		-- Sized so the dragon's own gold ring sits on the edge of the art
		card.dragon:SetSize(ART * DRAGON_SIZE, ART * DRAGON_SIZE)
	else
		card.dragon:SetSize(ART * 1.8, ART * 1.5)
		card.dragon:SetPoint("CENTER", card.art, "CENTER", 6, 2)
	end
	card.dragon:Hide()

	card.stars = {}
	for i = 1, 5 do
		local star = top:CreateTexture(nil, "OVERLAY")
		star:SetSize(10, 10)
		star:SetTexture(STAR)
		star:SetPoint("TOP", card.art, "BOTTOM", (i - 3) * 11, -10)
		card.stars[i] = star
	end

	card.stats = {}
	for i, stat in ipairs({ "attack", "health", "speed" }) do
		local text = card:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		text:SetPoint("BOTTOM", card, "BOTTOMLEFT", 6 + (Card.WIDTH - 12) * (i * 2 - 1) / 6, 11)
		text:SetTextColor(unpack(STAT_COLORS[stat]))
		card.stats[stat] = text
		local label = card:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
		label:SetPoint("BOTTOM", text, "TOP", 0, 0)
		label:SetText(({ attack = "ATK", health = "HP", speed = "SPD" })[stat])
		label:SetScale(0.85)
	end

	card.bar = CreateFrame("StatusBar", nil, card)
	card.bar:SetPoint("BOTTOMLEFT", 8, 5)
	card.bar:SetPoint("BOTTOMRIGHT", -8, 5)
	card.bar:SetHeight(4)
	card.bar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
	local barBg = card.bar:CreateTexture(nil, "BACKGROUND")
	barBg:SetAllPoints()
	barBg:SetColorTexture(0, 0, 0, 0.7)
	card.bar:Hide()

	local highlight = card:CreateTexture(nil, "HIGHLIGHT")
	highlight:SetPoint("TOPLEFT", 4, -4)
	highlight:SetPoint("BOTTOMRIGHT", -4, 4)
	highlight:SetColorTexture(1, 1, 1, 0.07)

	card.check = top:CreateTexture(nil, "OVERLAY", nil, 4)
	card.check:SetSize(20, 20)
	card.check:SetPoint("TOPRIGHT", 0, 2)
	card.check:SetTexture("Interface\\Buttons\\UI-CheckBox-Check")
	card.check:Hide()

	-- Exhausted: darkened, with a note
	card.tired = top:CreateTexture(nil, "OVERLAY", nil, 5)
	card.tired:SetPoint("TOPLEFT", 4, -4)
	card.tired:SetPoint("BOTTOMRIGHT", -4, 4)
	card.tired:SetColorTexture(0, 0, 0, 0.6)
	card.tiredText = top:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	card.tiredText:SetPoint("CENTER", card.art)
	card.tiredText:SetTextColor(1, 0.4, 0.3)

	-- Red flash when hit
	card.flash = top:CreateTexture(nil, "OVERLAY", nil, 6)
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
	card.damage = top:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
	card.damage:SetPoint("CENTER", card.art)
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

	card.dead = top:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
	card.dead:SetPoint("CENTER", card.art)
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
	self.name:SetText(data.name)
	self.name:SetTextColor(r, g, b)
	self.ring:SetVertexColor(r, g, b, 1)
	self.cover:SetVertexColor(CARD_BG[1], CARD_BG[2], CARD_BG[3], 1) -- matches the card behind it
	self.art:SetTexture(data.art or family.icon)
	ns.SetPortrait(self.model, self.art, data)
	self.badge.ring:SetVertexColor(unpack(kind.color))
	self.badge.icon:SetTexture(kind.icon)
	self.familyBadge.ring:SetVertexColor(unpack(family.color))
	self.familyBadge.icon:SetTexture(family.icon)
	self.power:SetText(data.power)
	self:SetCount(nil)
	self:SetUsedUp(false)
	for i, star in ipairs(self.stars) do
		star:SetShown(i <= data.stars)
	end
	self.stats.attack:SetText(data.attack)
	self.stats.health:SetText(data.health)
	self.stats.speed:SetText(data.speed)

	self.barKind = bar
	self.maxHp = nil
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
	self:SetLeader(ns.IsNamed(data)) -- named cards always lead
	self:SetSelected(false)
end

-- "2x": how many copies (or how many are still free); nil hides it
function Mixin:SetCount(count)
	self.count:SetShown(count ~= nil)
	if count then
		self.count:SetText(count .. "x")
		self.count:SetTextColor(count > 0 and 1 or 0.6, count > 0 and 0.82 or 0.6, count > 0 and 0.2 or 0.6)
	end
end

-- Greyed out (all copies already in the squad), still listed
function Mixin:SetUsedUp(used)
	self:SetAlpha(used and 0.4 or 1)
	self.art:SetDesaturated(used)
end

function Mixin:SetSelected(selected)
	self.check:SetShown(selected)
end

function Mixin:SetLeader(leader)
	self.dragon:SetShown(leader)
	self.ring:SetShown(not leader) -- the dragon is the leader's ring
end

function Mixin:ShowTooltip()
	if self.data then
		Card.ShowTooltipFor(self, self.data)
	end
end

-- The card's tooltip for any frame (also the loot window's rows)
function Card.ShowTooltipFor(owner, data)
	local rarity = ns.RARITIES[data.classification]
	local kind = ns.TYPES[data.type]
	GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
	GameTooltip:AddLine(data.name, unpack(rarity.color))
	GameTooltip:AddLine(("%s  ·  %s"):format(data.family, rarity.name), 1, 1, 1)
	GameTooltip:AddLine(data.type, unpack(kind.color))
	GameTooltip:AddLine(("%d of 5 stars  ·  Power %d"):format(data.stars, data.power), 0.8, 0.8, 0.8)
	GameTooltip:AddLine(" ")
	GameTooltip:AddDoubleLine("Attack", data.attack, 1, 1, 1, 1, 1, 1)
	GameTooltip:AddDoubleLine("Health", data.health, 1, 1, 1, 1, 1, 1)
	GameTooltip:AddDoubleLine("Speed", data.speed .. " / " .. ns.MAX_SPEED, 1, 1, 1, 1, 1, 1)
	if data.armor > 0 then
		GameTooltip:AddDoubleLine("Armor", data.armor, 1, 1, 1, 1, 1, 1)
	end
	GameTooltip:AddDoubleLine("Stamina", data.stamina .. " / 100", 1, 1, 1, 1, 1, 1)
	GameTooltip:AddLine(" ")
	if ns.IsNamed(data) then
		GameTooltip:AddLine(data.player and (data.remote and (data.remote .. " themselves: always leads, one leader per squad")
			or "That's you: always leads its squad, one leader per squad")
			or "Named: always leads its squad, one per squad", 1, 0.82, 0, true)
		GameTooltip:AddLine(kind.leader, 1, 0.82, 0, true)
	end
	if data.spell then
		GameTooltip:AddLine("Signature: " .. data.spell, 0.8, 0.8, 0.8)
	end
	if data.zone ~= "" then
		GameTooltip:AddLine("Caught in " .. data.zone, 0.6, 0.6, 0.6)
	end
	GameTooltip:Show()
end

-- Health in a fight can go above the card's own (family bonuses)
function Mixin:SetMaxHealth(maxHp)
	self.maxHp = maxHp
	self:SetHealth(maxHp)
end

function Mixin:SetHealth(hp)
	local maxHp = self.maxHp or self.data.health
	self.bar:SetMinMaxValues(0, maxHp)
	self.bar:SetValue(hp)
	self.stats.health:SetText(hp)
	local part = hp / maxHp
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

function Mixin:Heal(amount, hp)
	self:SetHealth(hp)
	self.damage:SetText("+" .. amount)
	self.damage:SetTextColor(0.3, 1, 0.4)
	self.damageAnim:Stop()
	self.damageAnim:Play()
end

function Mixin:SetDead(dead)
	self:SetAlpha(dead and 0.45 or 1)
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
