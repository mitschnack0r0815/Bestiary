local _, ns = ...

-- Round button on the minimap edge, like the ones of Grandma's Game Box. Left-click opens the
-- window, right-click shows a menu, drag moves it around the minimap. Angle and hidden state
-- are saved in BestiaryAccount.minimap.
local DEFAULT_ANGLE = 200

local button = CreateFrame("Button", "BestiaryMinimapButton", Minimap)
button:SetSize(31, 31)
button:SetFrameStrata("MEDIUM")
button:SetFrameLevel(8)
button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
button:RegisterForDrag("LeftButton")
button:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
button:Hide()

-- Same textures and offsets as standard minimap buttons
local background = button:CreateTexture(nil, "BACKGROUND")
background:SetSize(20, 20)
background:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
background:SetPoint("TOPLEFT", 7, -5)

local icon = button:CreateTexture(nil, "ARTWORK")
icon:SetSize(17, 17)
icon:SetTexCoord(0.05, 0.95, 0.05, 0.95)
icon:SetPoint("TOPLEFT", 7, -6)
icon:SetTexture(ns.ICON)

local border = button:CreateTexture(nil, "OVERLAY")
border:SetSize(53, 53)
border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
border:SetPoint("TOPLEFT")

local function Settings()
	BestiaryAccount = BestiaryAccount or {}
	BestiaryAccount.minimap = BestiaryAccount.minimap or { angle = DEFAULT_ANGLE }
	return BestiaryAccount.minimap
end

local function UpdatePosition()
	local angle = math.rad(Settings().angle)
	local radius = Minimap:GetWidth() / 2 + 5
	button:ClearAllPoints()
	button:SetPoint("CENTER", Minimap, "CENTER", math.cos(angle) * radius, math.sin(angle) * radius)
end

-- While dragging, follow the cursor around the minimap edge
local function FollowCursor()
	local mx, my = Minimap:GetCenter()
	local cx, cy = GetCursorPosition()
	local scale = Minimap:GetEffectiveScale()
	Settings().angle = math.deg(math.atan2(cy / scale - my, cx / scale - mx))
	UpdatePosition()
end

button:SetScript("OnDragStart", function(self)
	self:SetScript("OnUpdate", FollowCursor)
	GameTooltip:Hide()
end)
button:SetScript("OnDragStop", function(self)
	self:SetScript("OnUpdate", nil)
end)

local MENU = {
	{ title = "Bestiary" },
	{ text = "Collection", func = function() ns.Show("Collection") end },
	{ text = "Studying", func = function() ns.Show("Studying") end },
	{ text = "Squads (mockup)", func = function() ns.Show("Squads") end },
	{ text = "Duel (mockup)", func = function() ns.Show("Duel") end },
	{ text = "Stats", func = function() ns.Show("Stats") end },
	{ text = "Info", func = function() ns.Show("Info") end },
	{ text = "Test drops", func = function() ns.Show("Test") end },
	{ divider = true },
	{ text = "Hide minimap button", func = function() ns.ToggleMinimapButton() end },
}

local ShowMenu
if MenuUtil and MenuUtil.CreateContextMenu then
	ShowMenu = function(owner)
		MenuUtil.CreateContextMenu(owner, function(_, root)
			for _, item in ipairs(MENU) do
				if item.title then
					root:CreateTitle(item.title)
				elseif item.divider then
					root:CreateDivider()
				else
					root:CreateButton(item.text, item.func)
				end
			end
		end)
	end
else
	local dropdown = CreateFrame("Frame", "BestiaryMinimapMenu", UIParent, "UIDropDownMenuTemplate")
	UIDropDownMenu_Initialize(dropdown, function(_, level)
		for _, item in ipairs(MENU) do
			if item.divider then
				if UIDropDownMenu_AddSeparator then
					UIDropDownMenu_AddSeparator(level)
				end
			else
				local info = UIDropDownMenu_CreateInfo()
				info.text = item.title or item.text
				info.isTitle = item.title and true or nil
				info.notCheckable = true
				info.func = item.func
				UIDropDownMenu_AddButton(info, level)
			end
		end
	end, "MENU")
	ShowMenu = function()
		ToggleDropDownMenu(1, nil, dropdown, "cursor", 0, 0)
	end
end

button:SetScript("OnClick", function(self, mouseButton)
	if mouseButton == "RightButton" then
		GameTooltip:Hide()
		ShowMenu(self)
	else
		ns.Toggle()
	end
end)

button:SetScript("OnEnter", function(self)
	GameTooltip:SetOwner(self, "ANCHOR_LEFT")
	GameTooltip:AddLine("Bestiary |cff999999(prototype)|r")
	if BestiaryChar then
		GameTooltip:AddLine(("%d cards  ·  %d mob types studying"):format(#ns.Collection(), #ns.Studying()), 1, 1, 1)
	end
	GameTooltip:AddLine("Left-click: Open", 0.7, 0.7, 0.7)
	GameTooltip:AddLine("Right-click: Menu", 0.7, 0.7, 0.7)
	GameTooltip:AddLine("Drag: move", 0.7, 0.7, 0.7)
	GameTooltip:Show()
end)
button:SetScript("OnLeave", GameTooltip_Hide)

function ns.ToggleMinimapButton()
	local settings = Settings()
	settings.hide = not settings.hide
	button:SetShown(not settings.hide)
	if settings.hide then
		print("|cffc0ff60Bestiary:|r Minimap button hidden. Type /bst minimap to show it again.")
	end
end

-- SavedVariables are only there after login
local loader = CreateFrame("Frame")
loader:RegisterEvent("PLAYER_LOGIN")
loader:SetScript("OnEvent", function()
	UpdatePosition()
	button:SetShown(not Settings().hide)
end)
