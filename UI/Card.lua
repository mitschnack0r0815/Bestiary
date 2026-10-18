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
-- Paper like the spellbook's pages (this client's spellbook atlases), cut to the card's shape.
-- Without the atlas the card stays dark.
local PAPER_ATLASES = { "spellbook-Page-Right-C60", "spellbook-Page-Left-C60" }
local PAPER_MARGIN = 0.22 -- cut this much off each side of the page: its edges, binding and shading
local INK = { 0.28, 0.18, 0.08 } -- labels on the paper

-- Forever's unit frame circle (the level badge): a dark disc with a gold rim. The type and family
-- badges, the level gem and the duel's action circles use it; icons go inside its rim.
local GOLD_CIRCLE = "UI-HUD-UnitFrame-SmallCircle"
local GOLD_RING = "Interface\\AddOns\\Bestiary\\Media\\GoldRing" -- Media/GoldRing.tga, 256 px
local GOLD_RING_INNER = 0.80 -- its hole, as a share of its size (the art fits inside)
local CARD_BACK = "Interface\\AddOns\\Bestiary\\Media\\CardBack" -- Media/CardBack.tga, 256 x 512
ns.GOLD_RING, ns.GOLD_RING_INNER = GOLD_RING, GOLD_RING_INNER
local GOLD_INNER = 0.68 -- the part of the circle inside the rim
local goldCircle
function ns.GoldCircle(texture)
	if goldCircle == nil then
		goldCircle = C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(GOLD_CIRCLE) ~= nil or false
	end
	if goldCircle then
		texture:SetAtlas(GOLD_CIRCLE)
	end
	return goldCircle
end
ns.GOLD_INNER = GOLD_INNER

-- The paper: the page's file and the part of it to show, nil if this client has no such atlas
local paper
local function Paper()
	if paper ~= nil then
		return paper or nil
	end
	paper = false
	if not (C_Texture and C_Texture.GetAtlasInfo) then
		return nil
	end
	for _, atlas in ipairs(PAPER_ATLASES) do
		local info = C_Texture.GetAtlasInfo(atlas)
		if info and info.file and info.width and info.height and info.width > 0 then
			local left, right = info.leftTexCoord, info.rightTexCoord
			local top, bottom = info.topTexCoord, info.bottomTexCoord
			-- the middle of the page, as tall as the card is (its width / height)
			local want = (Card.WIDTH - 8) / (Card.HEIGHT - 8)
			local w, h = info.width * (1 - 2 * PAPER_MARGIN), info.height * (1 - 2 * PAPER_MARGIN)
			if w / h > want then
				w = h * want
			else
				h = w / want
			end
			local u = (right - left) * (w / info.width)
			local v = (bottom - top) * (h / info.height)
			local cu, cv = (left + right) / 2, (top + bottom) / 2
			paper = { file = info.file, coords = { cu - u / 2, cu + u / 2, cv - v / 2, cv + v / 2 } }
			return paper
		end
	end
	return nil
end
ns.RING, ns.RING_COVER = RING, COVER
local ROUND_MASK = "Interface\\CharacterFrame\\TempPortraitAlphaMask"
local STAT_COLORS = { attack = { 1, 0.45, 0.4 }, health = { 0.4, 1, 0.45 }, speed = { 1, 0.85, 0.35 },
	heal = { 0.45, 0.95, 1 } }

local BACKDROP = {
	bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
	edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
	tile = true, tileSize = 16, edgeSize = 14,
	insets = { left = 4, right = 4, top = 4, bottom = 4 },
}

-- Softer corners like spell buttons: the action bar's icon mask (falls back to a slight crop)
local SOFT_MASKS = { "UI-HUD-ActionBar-IconFrame-Mask", "UI-Frame-IconMask" }
function ns.SoftCorners(frame, texture)
	texture:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	if not (frame.CreateMaskTexture and C_Texture and C_Texture.GetAtlasInfo) then
		return
	end
	for _, atlas in ipairs(SOFT_MASKS) do
		if C_Texture.GetAtlasInfo(atlas) then
			local mask = frame:CreateMaskTexture()
			mask:SetAtlas(atlas)
			mask:SetAllPoints(texture)
			texture:AddMaskTexture(mask)
			texture:SetTexCoord(0, 1, 0, 1) -- the mask cuts the edge
			return
		end
	end
end

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
	if ns.GoldCircle(holder.ring) then
		holder.gold = true -- the gold circle around it; no color of its own
		holder.ring:SetSize(size / GOLD_INNER, size / GOLD_INNER)
	else
		holder.ring:SetSize(size + 4, size + 4)
		holder.ring:SetColorTexture(1, 1, 1)
		Round(frame, holder.ring)
	end
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
	local page = Paper()
	if page then
		card.paper = card:CreateTexture(nil, "BACKGROUND", nil, 2)
		card.paper:SetPoint("TOPLEFT", 4, -4)
		card.paper:SetPoint("BOTTOMRIGHT", -4, 4)
		card.paper:SetTexture(page.file)
		card.paper:SetTexCoord(unpack(page.coords))
	end

	card.name = card:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	card.name:SetPoint("TOPLEFT", 6, -6)
	card.name:SetPoint("TOPRIGHT", -26, -6) -- room for the power gem
	card.name:SetHeight(22)
	card.name:SetJustifyV("MIDDLE")
	card.name:SetWordWrap(true)
	local Outline = function(text)
		if card.paper then
			local font, size = text:GetFont()
			text:SetFont(font, size, "OUTLINE") -- colored text stays readable on the paper
		end
	end
	Outline(card.name)

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
	if page and top.CreateMaskTexture then
		-- On paper: the cover is that same piece of paper with a round hole for the portrait, so
		-- it can't be seen; around the hole the gold rim of the level circle (decided)
		local hole = top:CreateMaskTexture()
		hole:SetTexture(COVER, "CLAMP", "CLAMP") -- clamped: opaque everywhere but the hole
		hole:SetSize(ART + 6, ART + 6)
		hole:SetPoint("CENTER", card.art)
		local box = ART + 8 -- just over the model: any bigger and it would cover the name
		local u0, u1, v0, v1 = unpack(page.coords)
		local innerW, innerH = Card.WIDTH - 8, Card.HEIGHT - 8
		local x0 = (Card.WIDTH / 2 - box / 2 - 4) / innerW
		local y0 = (34 + ART / 2 - box / 2 - 4) / innerH
		local fw, fh = box / innerW, box / innerH
		card.cover:SetTexture(page.file)
		card.cover:SetTexCoord(u0 + (u1 - u0) * x0, u0 + (u1 - u0) * (x0 + fw), v0 + (v1 - v0) * y0, v0 + (v1 - v0) * (y0 + fh))
		card.cover:SetSize(box, box)
		card.cover:AddMaskTexture(hole)
		card.paperCover = true
	end
	-- The portrait's gold rim: our own texture, drawn at 256 px so it stays sharp (the game has
	-- no ring of its own at this size; stretched small circles look pixelated)
	card.goldRing = top:CreateTexture(nil, "ARTWORK", nil, 3)
	card.goldRing:SetTexture(GOLD_RING)
	card.goldRing:SetSize(ART / GOLD_RING_INNER, ART / GOLD_RING_INNER)
	card.goldRing:SetPoint("CENTER", card.art)
	card.ring:Hide()

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
	if ns.GoldCircle(card.powerRim) then
		card.powerRim:SetSize(27, 27) -- like the level on the player frame
	else
		card.powerRim:SetColorTexture(1, 0.82, 0.2)
		Round(top, card.powerRim)
		card.powerBg = top:CreateTexture(nil, "OVERLAY", nil, 4)
		card.powerBg:SetSize(21, 21)
		card.powerBg:SetPoint("CENTER", card.powerRim)
		card.powerBg:SetColorTexture(0.08, 0.06, 0.04)
		Round(top, card.powerBg)
	end
	card.power = top:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
	card.power:SetPoint("CENTER", card.powerRim, "CENTER", 0, 0)
	card.power:SetTextColor(1, 0.82, 0.2)

	-- Leaders: the dragon around the art (set by SetLeader, it depends on the rarity)
	card.dragon = top:CreateTexture(nil, "OVERLAY", nil, 1)
	card.dragon:Hide()

	-- Its abilities: up to 4 icons beside the art, first right (top, below), then left (below the
	-- copies count)
	card.abilityIcons = {}
	for i = 1, 4 do
		local icon = top:CreateTexture(nil, "OVERLAY", nil, 2)
		icon:SetSize(16, 16)
		if i <= 2 then
			icon:SetPoint("TOPLEFT", card.art, "TOPRIGHT", 3, 2 - (i - 1) * 16) -- touching, no gap
		else
			icon:SetPoint("TOPRIGHT", card.art, "TOPLEFT", -2, -16 - (i - 3) * 16)
		end
		ns.SoftCorners(top, icon)
		icon:Hide()
		card.abilityIcons[i] = icon
	end

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
		Outline(text)
		card.stats[stat] = text
		local label = card:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
		label:SetPoint("BOTTOM", text, "TOP", 0, 0)
		label:SetText(({ attack = "ATK", health = "HP", speed = "SPD" })[stat])
		card.statLabels = card.statLabels or {}
		card.statLabels[stat] = label
		label:SetScale(0.85)
		if card.paper then
			label:SetTextColor(unpack(INK))
		end
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

	-- All copies already in the squad: shaded (not see-through, the paper would look washed out)
	card.usedShade = top:CreateTexture(nil, "OVERLAY", nil, 5)
	card.usedShade:SetPoint("TOPLEFT", 4, -4)
	card.usedShade:SetPoint("BOTTOMRIGHT", -4, 4)
	card.usedShade:SetColorTexture(0, 0, 0, 0.55)
	card.usedShade:Hide()
	card.usedText = top:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	card.usedText:SetPoint("CENTER", card.art, "CENTER", 0, 0)
	card.usedText:SetText("In squad")
	card.usedText:SetTextColor(1, 0.82, 0.2)
	card.usedText:Hide()

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

	-- Knocked out: the card lies face down. Its back (Media/CardBack.tga) with the Bestiary emblem
	-- in a gold ring, above everything on the card (the 3D model too)
	local back = CreateFrame("Frame", nil, card, BackdropTemplateMixin and "BackdropTemplate" or nil)
	back:SetAllPoints()
	back:SetFrameLevel(card:GetFrameLevel() + 10)
	if back.SetBackdrop then
		back:SetBackdrop(BACKDROP)
		back:SetBackdropColor(0, 0, 0, 1)
		back:SetBackdropBorderColor(0.55, 0.42, 0.2, 1)
	end
	local pattern = back:CreateTexture(nil, "ARTWORK", nil, 1)
	pattern:SetPoint("TOPLEFT", 3, -3)
	pattern:SetPoint("BOTTOMRIGHT", -3, 3)
	pattern:SetTexture(CARD_BACK)
	local emblem = back:CreateTexture(nil, "ARTWORK", nil, 2)
	emblem:SetSize(34, 34)
	emblem:SetPoint("CENTER")
	emblem:SetTexture(ns.ICON or "Interface\\Icons\\Ability_Hunter_BeastTaming")
	Round(back, emblem)
	local emblemRing = back:CreateTexture(nil, "ARTWORK", nil, 3)
	emblemRing:SetSize(34 / GOLD_RING_INNER, 34 / GOLD_RING_INNER)
	emblemRing:SetPoint("CENTER")
	emblemRing:SetTexture(GOLD_RING)
	back:Hide()
	card.back = back

	-- Turning over: squeezed to a line, then the other face grows back
	local flip = card:CreateAnimationGroup()
	local shrink = flip:CreateAnimation("Scale")
	shrink:SetScaleFrom(1, 1)
	shrink:SetScaleTo(0.02, 1)
	shrink:SetDuration(0.14)
	shrink:SetSmoothing("IN")
	shrink:SetScript("OnFinished", function()
		card.back:SetShown(card.isDead == true)
	end)
	local grow = flip:CreateAnimation("Scale")
	grow:SetScaleFrom(0.02, 1)
	grow:SetScaleTo(1, 1)
	grow:SetDuration(0.16)
	grow:SetStartDelay(0.14)
	grow:SetSmoothing("OUT")
	card.flip = flip

	card:SetScript("OnEnter", card.ShowTooltip)
	card:SetScript("OnLeave", GameTooltip_Hide)
	return card
end

-- bar: "stamina", "health" or nil
function Mixin:SetCard(data, bar)
	self.data = data
	local rarity = ns.RarityOf(data)
	local family = ns.FAMILIES[data.family]
	local kind = ns.TYPES[data.type]
	local r, g, b = unpack(rarity.color)
	if self.SetBackdropBorderColor then
		self:SetBackdropBorderColor(r, g, b, 1)
	end
	self.name:SetText(data.name)
	self.name:SetTextColor(r, g, b)
	self.ring:SetVertexColor(r, g, b, 1)
	if self.paperCover then
		self.cover:SetVertexColor(1, 1, 1, 1) -- the paper itself
	else
		self.cover:SetVertexColor(CARD_BG[1], CARD_BG[2], CARD_BG[3], 1) -- matches the card behind it
	end
	self.art:SetTexture(data.art or family.icon)
	ns.SetPortrait(self.model, self.art, data)
	if not self.badge.gold then
		self.badge.ring:SetVertexColor(unpack(kind.color))
		self.familyBadge.ring:SetVertexColor(unpack(family.color))
	end
	self.badge.icon:SetTexture(kind.icon)
	self.familyBadge.icon:SetTexture(family.icon)
	self.power:SetText(data.level or data.power) -- the level, like on the unit frames
	self:SetCount(nil)
	self:SetUsedUp(false)
	for i, star in ipairs(self.stars) do
		star:SetShown(i <= data.stars)
	end
	for i, icon in ipairs(self.abilityIcons) do
		local ability = data.abilities and data.abilities[i]
		icon:SetShown(ability ~= nil)
		if ability then
			icon:SetTexture(select(2, ns.AbilityLook(ability)))
		end
	end
	self.stats.attack:SetText(ns.CardAttack(data)) -- casters and healers: their spell
	-- Healers show what they heal for, not damage
	local healer = data.type == "Healer"
	self.statLabels.attack:SetText(healer and "HEAL" or "ATK")
	self.stats.attack:SetTextColor(unpack(healer and STAT_COLORS.heal or STAT_COLORS.attack))
	self.stats.health:SetText(data.health)
	self.stats.speed:SetText(("%.1f"):format(data.speed)) -- its attack time in seconds

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
	self:SetLeader(ns.IsNamed(data) and not data.battle, data.classification) -- named cards always lead (battles: no leaders)
	self:SetSelected(false)
end

-- The card whose turn it is: sparks wander around its border, like the game's autocast shine
-- on pet action buttons (two "worms" of sparks, each a head and a fading tail)
local SPARK = "Interface\\ItemSocketingFrame\\UI-ItemSockets"
local SPARK_COORDS = { 0.3984375, 0.4453125, 0.40234375, 0.44921875 }
local WORMS, SPARKS_PER_WORM = 2, 7
local LAPS_PER_SECOND = 0.3
local SPARK_GAP = 6 -- pixels between the sparks of a worm
local SPARK_SCALE = 1.5 -- 50% bigger than the pet buttons' shine (decided: easier to see)

-- A point on the border, distance d clockwise from the top left corner
local function OnBorder(d, w, h)
	if d < w then
		return d, 0
	elseif d < w + h then
		return w, d - w
	elseif d < 2 * w + h then
		return w - (d - w - h), h
	end
	return 0, h - (d - 2 * w - h)
end

local function MoveSparks(shine, elapsed)
	shine.time = shine.time + elapsed
	local w, h = shine:GetWidth(), shine:GetHeight()
	if not w or w <= 0 then
		return
	end
	local around = 2 * (w + h)
	for _, spark in ipairs(shine.sparks) do
		local d = ((shine.time * LAPS_PER_SECOND + (spark.worm - 1) / WORMS) * around - spark.lag * SPARK_GAP) % around
		local x, y = OnBorder(d, w, h)
		spark.texture:SetPoint("CENTER", shine, "TOPLEFT", x, -y)
	end
end

function Mixin:SetActive(active)
	if active and not self.shine then
		local shine = CreateFrame("Frame", nil, self)
		shine:SetPoint("TOPLEFT", 2, -2)
		shine:SetPoint("BOTTOMRIGHT", -2, 2)
		shine:SetFrameLevel(self:GetFrameLevel() + 6)
		shine.sparks, shine.time = {}, 0
		for worm = 1, WORMS do
			for lag = 0, SPARKS_PER_WORM - 1 do
				local texture = shine:CreateTexture(nil, "OVERLAY")
				texture:SetTexture(SPARK)
				texture:SetTexCoord(unpack(SPARK_COORDS))
				texture:SetBlendMode("ADD")
				local size = (16 - lag * 1.6) * SPARK_SCALE
				texture:SetSize(size, size)
				texture:SetVertexColor(1, 0.85, 0.35, 1 - lag * 0.07)
				shine.sparks[#shine.sparks + 1] = { texture = texture, worm = worm, lag = lag }
			end
		end
		shine:SetScript("OnUpdate", MoveSparks)
		self.shine = shine
	end
	if self.shine then
		self.shine:SetShown(active)
	end
end

-- "2x": how many copies (or how many are still free); nil hides it
function Mixin:SetCount(count)
	self.count:SetShown(count ~= nil)
	if count then
		self.count:SetText(count .. "x")
		self.count:SetTextColor(count > 0 and 1 or 0.6, count > 0 and 0.82 or 0.6, count > 0 and 0.2 or 0.6)
	end
end

-- Shaded with "In squad" (all copies already in the squad), still listed
function Mixin:SetUsedUp(used)
	self.usedShade:SetShown(used)
	self.usedText:SetShown(used)
	self.art:SetDesaturated(used)
end

function Mixin:SetSelected(selected)
	self.check:SetShown(selected)
end

-- The dragon frames of this client's target frame (Blizzard_UnitFrame/Camelot/TargetFrameUtils:
-- bosses gold winged, rares silver winged, elites gold), drawn at their real size around a 58 px
-- portrait whose top right corner is 26, 19 px inside the frame's; scaled to our art
local BOSS_FRAMES = {
	worldboss = { "UI-HUD-UnitFrame-Target-PortraitOn-Boss-Gold-Winged", 11, -4 },
	rare = { "UI-HUD-UnitFrame-Target-PortraitOn-Boss-Rare-Silver-Winged", 8, -7 },
	rareelite = { "UI-HUD-UnitFrame-Target-PortraitOn-Boss-Rare-Silver-Winged", 8, -7 },
	other = { "UI-HUD-UnitFrame-Target-PortraitOn-Boss-Gold", 0, 1 },
}
local PORTRAIT, PORTRAIT_X, PORTRAIT_Y = 58, -26, -19

local function SetBossFrame(texture, art, classification)
	local frame = BOSS_FRAMES[classification] or BOSS_FRAMES.other
	local info = C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(frame[1])
	if not info or not info.width then
		return false
	end
	local scale = ART / PORTRAIT
	texture:SetAtlas(frame[1])
	texture:SetSize(info.width * scale, info.height * scale)
	texture:ClearAllPoints()
	texture:SetPoint("TOPRIGHT", art, "TOPRIGHT", (frame[2] - PORTRAIT_X) * scale, (frame[3] - PORTRAIT_Y) * scale)
	return true
end

function Mixin:SetLeader(leader, classification)
	if leader and not SetBossFrame(self.dragon, self.art, classification) then
		-- older clients: the quest marker dragon, or the one cut from the elite target frame
		SetDragon(self.dragon)
		self.dragon:ClearAllPoints()
		if self.dragon.atlas then
			self.dragon:SetSize(ART * DRAGON_SIZE, ART * DRAGON_SIZE)
			self.dragon:SetPoint("CENTER", self.art, "CENTER", 0, 0)
		else
			self.dragon:SetSize(ART * 1.8, ART * 1.5)
			self.dragon:SetPoint("CENTER", self.art, "CENTER", 6, 2)
		end
	end
	self.dragon:SetShown(leader)
end

function Mixin:ShowTooltip()
	if self.data then
		Card.ShowTooltipFor(self, self.data)
	end
end

-- The card's tooltip for any frame (also the loot window's rows)
-- Only what the card itself doesn't show (decided): no level, stars, ATK/HEAL, HP or speed
function Card.ShowTooltipFor(owner, data)
	local rarity = ns.RarityOf(data)
	local kind = ns.TYPES[data.type]
	GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
	GameTooltip:AddLine(data.name, unpack(rarity.color))
	-- the badges are only icons: their names
	GameTooltip:AddLine(("%s  ·  %s  ·  |cff%02x%02x%02x%s|r"):format(rarity.name, data.family,
		kind.color[1] * 255, kind.color[2] * 255, kind.color[3] * 255, data.type), 1, 1, 1)
	if not data.battle then -- battles: no cap, no leaders, no stamina (data.battle: shown for a battle)
		GameTooltip:AddLine(("Power %d (counts against the squad cap)"):format(data.power), 1, 0.82, 0.2)
	end
	local saved = not data.remote and not data.player and ns.SavedCard(data)
	if saved then
		GameTooltip:AddLine(data.level >= ns.LevelCap(saved) and "Can't level higher for now"
			or ("%d of %d duels to the next level"):format(saved.games or 0, ns.GAMES_PER_LEVEL), 0.8, 0.8, 0.8)
		if data.level < ns.LevelCap(saved) and ns.CardXp then
			local xp, need = ns.CardXp(saved)
			GameTooltip:AddLine(("Battle XP: %d / %d to the next level"):format(xp, need), 0.69, 0.5, 1)
		end
	end
	-- a Tank's or Warrior's spell isn't on the card (casters' and healers' is their ATK/HEAL)
	if data.spellPower and data.type ~= "Mage" and data.type ~= "Healer" then
		GameTooltip:AddDoubleLine("Spell: " .. (data.spell or "Spell"), ("%d, %.1f s cast"):format(data.spellPower,
			data.castTime or ns.SPELL_TIME), 1, 1, 1, 1, 1, 1)
	elseif data.spell then
		GameTooltip:AddLine(data.spell, 1, 1, 1)
	end
	if data.armor > 0 then
		GameTooltip:AddDoubleLine("Armor", data.armor, 1, 1, 1, 1, 1, 1)
	end
	for _, ability in ipairs(data.abilities or {}) do
		local def = ns.ABILITIES[ability.key]
		local how = def.passive and "" or ability.onSpell and "  |cff999999(with its spell)|r"
			or ("  |cff999999(every %d s)|r"):format(def.cooldown)
		local name = ns.AbilityLook(ability)
		GameTooltip:AddLine(("|cffffd200%s|r%s"):format(name ~= def.name and (def.name .. ": " .. name) or def.name, how), 1, 1, 1)
		GameTooltip:AddLine("   " .. ns.AbilityText(ability, data), 0.8, 0.8, 0.8, true)
	end
	if not data.battle then
		GameTooltip:AddDoubleLine("Stamina", data.stamina .. " / 100", 1, 1, 1, 1, 1, 1)
	end
	if ns.IsNamed(data) and not data.battle then
		GameTooltip:AddLine(" ")
		GameTooltip:AddLine(data.player and (data.remote and (data.remote .. " themselves: always leads, one leader per squad")
			or "That's you: always leads its squad, one leader per squad")
			or "Named: always leads its squad, one per squad", 1, 0.82, 0, true)
		GameTooltip:AddLine(kind.leader, 1, 0.82, 0, true)
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

-- Knocked out: face down. animate: turn it over (in a fight), else at once.
function Mixin:SetDead(dead, animate)
	dead = dead == true
	if self.isDead == dead then
		return
	end
	self.isDead = dead
	self.flip:Stop()
	if animate then
		self.flip:Play() -- the back shows halfway (Create)
	else
		self.back:SetShown(dead)
	end
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
