local _, ns = ...
local Card = ns.Card

-- PROTOTYPE page: your real cards, from real kills. The mob types still being studied have
-- their own tab (UI/Studying.lua).
local WIDTH = ns.WINDOW_WIDTH
local STEP = Card.WIDTH + 8
local COLUMNS = math.floor((WIDTH - 60) / STEP)
local INSET = C_XMLUtil and C_XMLUtil.GetTemplateInfo and C_XMLUtil.GetTemplateInfo("InsetFrameTemplate")
	and "InsetFrameTemplate" or nil

local page = ns.AddPage("Collection", "Interface\\Icons\\INV_Misc_Book_11", 1)

local title = page:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
title:SetPoint("TOPLEFT", 72, -34)
title:SetText("Your bestiary")
local summary = page:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
summary:SetPoint("LEFT", title, "RIGHT", 14, 0)
local help = page:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
help:SetPoint("TOPLEFT", 72, -56)
help:SetText("Mob types you're still studying are on the Studying tab.")
local sortButton = ns.SortButton(page, 120)
sortButton:SetPoint("TOPRIGHT", -16, -50)

local cardInset = CreateFrame("Frame", nil, page, INSET)
cardInset:SetPoint("TOPLEFT", 8, -76)
cardInset:SetPoint("BOTTOMRIGHT", -8, 8)
local cardScroll = CreateFrame("ScrollFrame", nil, cardInset, "UIPanelScrollFrameTemplate")
cardScroll:SetPoint("TOPLEFT", 8, -8)
cardScroll:SetPoint("BOTTOMRIGHT", -28, 8)
local grid = CreateFrame("Frame", nil, cardScroll)
grid:SetSize(WIDTH - 60, 10)
cardScroll:SetScrollChild(grid)
local empty = cardInset:CreateFontString(nil, "OVERLAY", "GameFontDisable")
empty:SetPoint("CENTER")
empty:SetText("No cards yet. Go fight something!")

local cards = {}

local function Refresh()
	sortButton:Update()
	local collection = ns.Collection()
	for i, view in ipairs(collection) do
		local card = cards[i]
		if not card then
			card = Card.Create(grid)
			card:SetPoint("TOPLEFT", ((i - 1) % COLUMNS) * STEP, -math.floor((i - 1) / COLUMNS) * (Card.HEIGHT + 8))
			cards[i] = card
		end
		card:SetCard(view)
		if ns.CanHaveCopies(view) then
			card:SetCount(ns.Copies(view)) -- 1x to 3x
		end
		card:Show()
	end
	for i = #collection + 1, #cards do
		cards[i]:Hide()
	end
	grid:SetHeight(math.max(10, math.ceil(#collection / COLUMNS) * (Card.HEIGHT + 8)))
	ns.ClipCards(cardScroll, cards)
	empty:SetShown(#collection == 0)

	local stars = 0
	for _, view in ipairs(collection) do
		stars = stars + view.stars
	end
	summary:SetText(("%d cards  ·  %d stars"):format(#collection, stars))
end

page:SetScript("OnShow", Refresh)

-- Called when something changes (new card, finished studying); other pages chain onto this
function ns.Refresh()
	if page:IsVisible() then
		Refresh()
	end
end
