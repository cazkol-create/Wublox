-- @ScriptType: LocalScript
-- ============================================================
--  HudScript.lua  |  LocalScript
--  Location: StarterGui/WuxiaHUD/HudScript
--
--  FIXED: Directly connects to RemoteEvents in ReplicatedStorage.
--  No longer depends on BindableEvents from MainClient (race-condition removed).
-- ============================================================

local Players           = game:GetService("Players")
local TweenService      = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService  = game:GetService("UserInputService")

local player    = Players.LocalPlayer
local playerGui = player.PlayerGui
local GameData  = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("GameData"))

-- Wait for the Remotes folder (created by MainServer)
local remotesFolder = ReplicatedStorage:WaitForChild("Remotes", 20)
assert(remotesFolder, "[HudScript] Remotes folder missing — is MainServer running?")

local function getRemote(name)
	return remotesFolder:WaitForChild(name, 10)
end

local reUpdateHUD    = getRemote(GameData.Remotes.UpdateHUD)
local reNotify       = getRemote(GameData.Remotes.Notify)
local reBreakthrough = getRemote(GameData.Remotes.RealmBreakthrough)
local reMeditate     = getRemote(GameData.Remotes.RequestMeditate)
local reJoinSect     = getRemote(GameData.Remotes.RequestJoinSect)
local reLeaveSect    = getRemote(GameData.Remotes.RequestLeaveSect)

-- ============================================================
-- COLOR PALETTE
-- ============================================================
local function rgb(r,g,b) return Color3.fromRGB(r,g,b) end
local C = {
	bg        = rgb(10,  8, 18),
	panel     = rgb(18, 14, 32),
	border    = rgb(80, 60,120),
	text      = rgb(220,210,240),
	dim       = rgb(120,110,140),
	gold      = rgb(255,210, 60),
	righteous = rgb(100,160,255),
	chaotic   = rgb(220, 50, 50),
	neutral   = rgb(160,160,180),
	white     = rgb(255,255,255),
	black     = rgb(0,  0,  0),
	qi        = rgb(100,200,255),
	red       = rgb(200, 60, 60),
	darkBlue  = rgb(30, 20, 60),
	darkGreen = rgb(20, 40, 20),
	darkPanel = rgb(20, 16, 36),
}

-- ============================================================
-- UI FACTORY HELPERS
-- ============================================================
local function makeFrame(parent, size, pos, color, transparency)
	local f = Instance.new("Frame")
	f.Size = size;  f.Position = pos
	f.BackgroundColor3 = color or C.panel
	f.BackgroundTransparency = transparency or 0
	f.BorderSizePixel = 0;  f.Parent = parent
	return f
end

local function makeLabel(parent, text, size, pos, textColor, fontSize)
	local l = Instance.new("TextLabel")
	l.Size = size;  l.Position = pos
	l.BackgroundTransparency = 1
	l.Text = text;  l.TextColor3 = textColor or C.text
	l.TextSize = fontSize or 14
	l.Font = Enum.Font.GothamBold
	l.TextXAlignment = Enum.TextXAlignment.Left
	l.TextTruncate = Enum.TextTruncate.AtEnd
	l.Parent = parent
	return l
end

local function makeButton(parent, text, size, pos, bgColor, textColor)
	local b = Instance.new("TextButton")
	b.Size = size;  b.Position = pos
	b.BackgroundColor3 = bgColor or C.border
	b.BorderSizePixel = 0
	b.Text = text;  b.TextColor3 = textColor or C.white
	b.TextSize = 13;  b.Font = Enum.Font.GothamBold
	b.Parent = parent
	return b
end

local function corner(parent, r)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, r or 6);  c.Parent = parent
end

local function stroke(parent, color, thickness)
	local s = Instance.new("UIStroke")
	s.Color = color or C.border;  s.Thickness = thickness or 1
	s.Parent = parent
end

-- ============================================================
-- ROOT ScreenGui
-- ============================================================
local gui = Instance.new("ScreenGui")
gui.Name = "WuxiaHUD";  gui.ResetOnSpawn = false
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.Parent = playerGui

-- ============================================================
-- TOP-LEFT: Cultivation Panel
-- ============================================================
local cultivPanel = makeFrame(gui,
	UDim2.new(0,280,0,115), UDim2.new(0,14,0,14), C.panel, 0.15)
corner(cultivPanel, 8);  stroke(cultivPanel, C.border)

local lblRealm = makeLabel(cultivPanel, "Mortal",
	UDim2.new(1,-10,0,22), UDim2.new(0,10,0,8), C.gold, 16)

local lblQi = makeLabel(cultivPanel, "Qi: 0",
	UDim2.new(1,-10,0,16), UDim2.new(0,10,0,32), C.dim, 12)

local barTrack = makeFrame(cultivPanel,
	UDim2.new(1,-20,0,8), UDim2.new(0,10,0,54), rgb(30,24,50), 0)
corner(barTrack, 4)

local barFill = makeFrame(barTrack,
	UDim2.new(0,0,1,0), UDim2.new(0,0,0,0), C.qi, 0)
corner(barFill, 4)

local lblNextQi = makeLabel(cultivPanel, "Next realm: ---",
	UDim2.new(1,-10,0,14), UDim2.new(0,10,0,68), C.dim, 11)

local btnMeditate = makeButton(cultivPanel, "Meditate  [M]",
	UDim2.new(1,-20,0,22), UDim2.new(0,10,0,86), C.darkBlue, C.qi)
corner(btnMeditate, 5)

-- ============================================================
-- TOP-RIGHT: Moral Panel
-- ============================================================
local moralPanel = makeFrame(gui,
	UDim2.new(0,200,0,62), UDim2.new(1,-214,0,14), C.panel, 0.15)
corner(moralPanel, 8);  stroke(moralPanel, C.border)

makeLabel(moralPanel, "ALIGNMENT",
	UDim2.new(1,-10,0,14), UDim2.new(0,10,0,6), C.dim, 10)

local lblMoralTier = makeLabel(moralPanel, "Neutral",
	UDim2.new(1,-10,0,20), UDim2.new(0,10,0,20), C.neutral, 16)

local moralTrack = makeFrame(moralPanel,
	UDim2.new(1,-20,0,6), UDim2.new(0,10,0,46), rgb(30,24,50), 0)
corner(moralTrack, 3)

local moralLeft  = makeFrame(moralTrack, UDim2.new(0,0,1,0), UDim2.new(0.5,0,0,0), C.chaotic,   0)
local moralRight = makeFrame(moralTrack, UDim2.new(0,0,1,0), UDim2.new(0.5,0,0,0), C.righteous, 0)
makeFrame(moralTrack, UDim2.new(0,2,1,0), UDim2.new(0.5,-1,0,0), C.white, 0)

-- ============================================================
-- BOTTOM-LEFT: Sect Panel
-- ============================================================
local sectPanel = makeFrame(gui,
	UDim2.new(0,260,0,56), UDim2.new(0,14,1,-70), C.panel, 0.15)
corner(sectPanel, 8);  stroke(sectPanel, C.border)

makeLabel(sectPanel, "SECT", UDim2.new(0,60,0,14), UDim2.new(0,10,0,6), C.dim, 10)

local lblSectName = makeLabel(sectPanel, "Wandering Cultivator",
	UDim2.new(0,170,0,20), UDim2.new(0,10,0,20), C.gold, 14)

local lblSectAlign = makeLabel(sectPanel, "Neutral",
	UDim2.new(0,80,0,14), UDim2.new(0,10,0,40), C.neutral, 11)

local btnLeaveSect = makeButton(sectPanel, "Leave",
	UDim2.new(0,60,0,22), UDim2.new(0,190,0,22), rgb(60,20,20), C.red)
corner(btnLeaveSect, 5)
btnLeaveSect.MouseButton1Click:Connect(function()
	reLeaveSect:FireServer()
end)

local btnOpenSects = makeButton(gui, "Sects",
	UDim2.new(0,80,0,24), UDim2.new(0,284,1,-70), C.darkBlue, C.gold)
corner(btnOpenSects, 5);  stroke(btnOpenSects, C.gold)

-- ============================================================
-- SECT SELECTION PANEL (modal)
-- ============================================================
local sectSelectPanel = makeFrame(gui,
	UDim2.new(0,300,0,340), UDim2.new(0.5,-150,0.5,-170), C.panel, 0.05)
sectSelectPanel.Visible = false
corner(sectSelectPanel, 10);  stroke(sectSelectPanel, C.gold)

local lblSelectTitle = makeLabel(sectSelectPanel, "Choose Your Sect",
	UDim2.new(1,-20,0,24), UDim2.new(0,10,0,10), C.gold, 16)
lblSelectTitle.TextXAlignment = Enum.TextXAlignment.Center

local btnClose = makeButton(sectSelectPanel, "X",
	UDim2.new(0,24,0,24), UDim2.new(1,-34,0,10), C.red, C.white)
corner(btnClose, 4)
btnClose.MouseButton1Click:Connect(function()
	sectSelectPanel.Visible = false
end)

local sectScroll = Instance.new("ScrollingFrame")
sectScroll.Size = UDim2.new(1,-20,1,-50)
sectScroll.Position = UDim2.new(0,10,0,44)
sectScroll.BackgroundTransparency = 1
sectScroll.BorderSizePixel = 0
sectScroll.ScrollBarThickness = 4
sectScroll.ScrollBarImageColor3 = C.border
sectScroll.Parent = sectSelectPanel

local listLayout = Instance.new("UIListLayout")
listLayout.SortOrder = Enum.SortOrder.LayoutOrder
listLayout.Padding = UDim.new(0, 6)
listLayout.Parent = sectScroll

for i, sect in ipairs(GameData.Sects) do
	local row = makeFrame(sectScroll, UDim2.new(1,-8,0,56), UDim2.new(0,4,0,0), C.darkPanel, 0)
	row.LayoutOrder = i
	corner(row, 6)
	stroke(row, sect.color, 1)

	makeLabel(row, sect.name, UDim2.new(1,-80,0,18), UDim2.new(0,8,0,4), sect.color, 13)

	local desc = makeLabel(row, sect.description, UDim2.new(1,-80,0,28), UDim2.new(0,8,0,22), C.dim, 10)
	desc.TextWrapped = true

	local joinBtn = makeButton(row, "Join", UDim2.new(0,60,0,24), UDim2.new(1,-68,0,16), sect.color, C.black)
	corner(joinBtn, 5)
	joinBtn.TextColor3 = C.black

	local capturedId = sect.id
	joinBtn.MouseButton1Click:Connect(function()
		reJoinSect:FireServer({ sectId = capturedId })
		sectSelectPanel.Visible = false
	end)
end

listLayout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
	sectScroll.CanvasSize = UDim2.new(0, 0, 0, listLayout.AbsoluteContentSize.Y + 10)
end)

btnOpenSects.MouseButton1Click:Connect(function()
	sectSelectPanel.Visible = not sectSelectPanel.Visible
end)

-- ============================================================
-- NOTIFICATION TOAST
-- ============================================================
local notifQueue   = {}
local notifShowing = false

local notifFrame = makeFrame(gui,
	UDim2.new(0,360,0,44), UDim2.new(0.5,-180,0,-60), C.panel, 0.1)
corner(notifFrame, 8)
stroke(notifFrame, C.border)
notifFrame.Visible = false

local notifLabel = makeLabel(notifFrame, "",
	UDim2.new(1,-20,1,0), UDim2.new(0,10,0,0), C.text, 13)
notifLabel.TextXAlignment = Enum.TextXAlignment.Center
notifLabel.TextWrapped = true

local function showNextNotif()
	if notifShowing or #notifQueue == 0 then return end
	notifShowing = true
	notifLabel.Text = table.remove(notifQueue, 1)
	notifFrame.Position = UDim2.new(0.5,-180,0,-60)
	notifFrame.Visible  = true
	TweenService:Create(notifFrame, TweenInfo.new(0.3, Enum.EasingStyle.Quint),
		{ Position = UDim2.new(0.5,-180,0,10) }):Play()
	task.delay(3.2, function()
		TweenService:Create(notifFrame, TweenInfo.new(0.3, Enum.EasingStyle.Quint),
			{ Position = UDim2.new(0.5,-180,0,-60) }):Play()
		task.wait(0.35)
		notifFrame.Visible = false
		notifShowing = false
		showNextNotif()
	end)
end

-- ============================================================
-- BREAKTHROUGH SPLASH
-- ============================================================
local splashFrame = makeFrame(gui, UDim2.new(1,0,1,0), UDim2.new(0,0,0,0), C.black, 1)
splashFrame.ZIndex = 10
splashFrame.Visible = false

local splashTitle = makeLabel(splashFrame, "BREAKTHROUGH",
	UDim2.new(1,0,0,60), UDim2.new(0,0,0.38,0), C.gold, 38)
splashTitle.TextXAlignment = Enum.TextXAlignment.Center
splashTitle.ZIndex = 11
splashTitle.Font = Enum.Font.GothamBold

local splashSub = makeLabel(splashFrame, "",
	UDim2.new(1,0,0,30), UDim2.new(0,0,0.50,0), C.text, 17)
splashSub.TextXAlignment = Enum.TextXAlignment.Center
splashSub.ZIndex = 11

-- ============================================================
-- MEDITATE TOGGLE
-- ============================================================
local meditating = false

local function setMeditating(state)
	meditating = state
	btnMeditate.Text = state and "Stop Meditating" or "Meditate  [M]"
	btnMeditate.BackgroundColor3 = state and C.darkGreen or C.darkBlue
end

btnMeditate.MouseButton1Click:Connect(function()
	setMeditating(not meditating)
	reMeditate:FireServer({ action = meditating and "start" or "stop" })
end)

UserInputService.InputBegan:Connect(function(input, processed)
	if processed then return end
	if input.KeyCode == Enum.KeyCode.M then
		setMeditating(not meditating)
		reMeditate:FireServer({ action = meditating and "start" or "stop" })
	end
end)

-- ============================================================
-- HUD UPDATE HELPERS
-- ============================================================
local function getMoralTier(moral)
	for _, tier in ipairs(GameData.MoralTiers) do
		if moral >= tier.min and moral <= tier.max then
			return tier
		end
	end
	return GameData.MoralTiers[3]
end

local function getSectById(id)
	for _, s in ipairs(GameData.Sects) do
		if s.id == id then return s end
	end
end

local function updateHUD(data)
	if not data then return end

	-- Cultivation
	local ri    = data.realmIndex or 1
	local realm = GameData.CultivationRealms[ri] or GameData.CultivationRealms[1]
	local nextR = GameData.CultivationRealms[ri + 1]
	local qi    = data.qi or 0

	lblRealm.Text       = realm.name
	lblRealm.TextColor3 = GameData.RealmAuraColor[ri] or C.text
	lblQi.Text          = "Qi: " .. tostring(qi)

	local progress = 0
	if nextR then
		local span = nextR.minQi - realm.minQi
		progress   = math.clamp((qi - realm.minQi) / span, 0, 1)
		lblNextQi.Text = "Next: " .. nextR.name .. "  (" .. tostring(nextR.minQi - qi) .. " needed)"
	else
		progress = 1
		lblNextQi.Text = "Maximum Realm Achieved"
	end

	TweenService:Create(barFill, TweenInfo.new(0.4, Enum.EasingStyle.Quad),
		{ Size = UDim2.new(progress, 0, 1, 0) }):Play()

	-- Moral
	local moral   = data.moral or 0
	local morTier = getMoralTier(moral)
	lblMoralTier.Text       = morTier.name
	lblMoralTier.TextColor3 = morTier.color

	if moral < 0 then
		local pct = math.abs(moral) / 100
		TweenService:Create(moralLeft,  TweenInfo.new(0.4),
			{ Size = UDim2.new(pct * 0.5, 0, 1, 0),
				Position = UDim2.new(0.5 - pct * 0.5, 0, 0, 0) }):Play()
		TweenService:Create(moralRight, TweenInfo.new(0.4),
			{ Size = UDim2.new(0, 0, 1, 0) }):Play()
	else
		local pct = moral / 100
		TweenService:Create(moralRight, TweenInfo.new(0.4),
			{ Size = UDim2.new(pct * 0.5, 0, 1, 0) }):Play()
		TweenService:Create(moralLeft,  TweenInfo.new(0.4),
			{ Size     = UDim2.new(0, 0, 1, 0),
				Position = UDim2.new(0.5, 0, 0, 0) }):Play()
	end

	-- Sect
	local sect = getSectById(data.sectId)
	if sect then
		lblSectName.Text        = sect.name
		lblSectName.TextColor3  = sect.color
		lblSectAlign.Text       = sect.alignment
		lblSectAlign.TextColor3 = sect.alignment == "Righteous" and C.righteous
			or sect.alignment == "Chaotic" and C.chaotic
			or C.neutral
		btnLeaveSect.Visible    = sect.id ~= "WANDERER"
	end

	if data.meditating ~= nil then
		setMeditating(data.meditating)
	end
end

-- ============================================================
-- WIRE REMOTES  (direct — no BindableEvent middleman)
-- ============================================================

reUpdateHUD.OnClientEvent:Connect(updateHUD)

reNotify.OnClientEvent:Connect(function(message)
	table.insert(notifQueue, message)
	showNextNotif()
end)

reBreakthrough.OnClientEvent:Connect(function(info)
	splashSub.Text      = "You have reached " .. (info and info.realm or "a new realm") .. "!"
	splashFrame.BackgroundTransparency = 1
	splashFrame.Visible = true
	TweenService:Create(splashFrame, TweenInfo.new(0.5),
		{ BackgroundTransparency = 0.35 }):Play()
	task.delay(3.5, function()
		TweenService:Create(splashFrame, TweenInfo.new(0.6),
			{ BackgroundTransparency = 1 }):Play()
		task.wait(0.65)
		splashFrame.Visible = false
	end)
end)
-- ============================================================
--  HudScript.lua  |  LocalScript
--  Location: StarterGui/WuxiaHUD/HudScript
--
--  FIXED: Directly connects to RemoteEvents in ReplicatedStorage.
--  No longer depends on BindableEvents from MainClient (race-condition removed).
-- ============================================================

local Players           = game:GetService("Players")
local TweenService      = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService  = game:GetService("UserInputService")

local player    = Players.LocalPlayer
local playerGui = player.PlayerGui
local GameData  = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("GameData"))

-- Wait for the Remotes folder (created by MainServer)
local remotesFolder = ReplicatedStorage:WaitForChild("Remotes", 20)
assert(remotesFolder, "[HudScript] Remotes folder missing — is MainServer running?")

local function getRemote(name)
	return remotesFolder:WaitForChild(name, 10)
end

local reUpdateHUD    = getRemote(GameData.Remotes.UpdateHUD)
local reNotify       = getRemote(GameData.Remotes.Notify)
local reBreakthrough = getRemote(GameData.Remotes.RealmBreakthrough)
local reMeditate     = getRemote(GameData.Remotes.RequestMeditate)
local reJoinSect     = getRemote(GameData.Remotes.RequestJoinSect)
local reLeaveSect    = getRemote(GameData.Remotes.RequestLeaveSect)

-- ============================================================
-- COLOR PALETTE
-- ============================================================
local function rgb(r,g,b) return Color3.fromRGB(r,g,b) end
local C = {
	bg        = rgb(10,  8, 18),
	panel     = rgb(18, 14, 32),
	border    = rgb(80, 60,120),
	text      = rgb(220,210,240),
	dim       = rgb(120,110,140),
	gold      = rgb(255,210, 60),
	righteous = rgb(100,160,255),
	chaotic   = rgb(220, 50, 50),
	neutral   = rgb(160,160,180),
	white     = rgb(255,255,255),
	black     = rgb(0,  0,  0),
	qi        = rgb(100,200,255),
	red       = rgb(200, 60, 60),
	darkBlue  = rgb(30, 20, 60),
	darkGreen = rgb(20, 40, 20),
	darkPanel = rgb(20, 16, 36),
}

-- ============================================================
-- UI FACTORY HELPERS
-- ============================================================
local function makeFrame(parent, size, pos, color, transparency)
	local f = Instance.new("Frame")
	f.Size = size;  f.Position = pos
	f.BackgroundColor3 = color or C.panel
	f.BackgroundTransparency = transparency or 0
	f.BorderSizePixel = 0;  f.Parent = parent
	return f
end

local function makeLabel(parent, text, size, pos, textColor, fontSize)
	local l = Instance.new("TextLabel")
	l.Size = size;  l.Position = pos
	l.BackgroundTransparency = 1
	l.Text = text;  l.TextColor3 = textColor or C.text
	l.TextSize = fontSize or 14
	l.Font = Enum.Font.GothamBold
	l.TextXAlignment = Enum.TextXAlignment.Left
	l.TextTruncate = Enum.TextTruncate.AtEnd
	l.Parent = parent
	return l
end

local function makeButton(parent, text, size, pos, bgColor, textColor)
	local b = Instance.new("TextButton")
	b.Size = size;  b.Position = pos
	b.BackgroundColor3 = bgColor or C.border
	b.BorderSizePixel = 0
	b.Text = text;  b.TextColor3 = textColor or C.white
	b.TextSize = 13;  b.Font = Enum.Font.GothamBold
	b.Parent = parent
	return b
end

local function corner(parent, r)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, r or 6);  c.Parent = parent
end

local function stroke(parent, color, thickness)
	local s = Instance.new("UIStroke")
	s.Color = color or C.border;  s.Thickness = thickness or 1
	s.Parent = parent
end

-- ============================================================
-- ROOT ScreenGui
-- ============================================================
local gui = Instance.new("ScreenGui")
gui.Name = "WuxiaHUD";  gui.ResetOnSpawn = false
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.Parent = playerGui

-- ============================================================
-- TOP-LEFT: Cultivation Panel
-- ============================================================
local cultivPanel = makeFrame(gui,
	UDim2.new(0,280,0,115), UDim2.new(0,14,0,14), C.panel, 0.15)
corner(cultivPanel, 8);  stroke(cultivPanel, C.border)

local lblRealm = makeLabel(cultivPanel, "Mortal",
	UDim2.new(1,-10,0,22), UDim2.new(0,10,0,8), C.gold, 16)

local lblQi = makeLabel(cultivPanel, "Qi: 0",
	UDim2.new(1,-10,0,16), UDim2.new(0,10,0,32), C.dim, 12)

local barTrack = makeFrame(cultivPanel,
	UDim2.new(1,-20,0,8), UDim2.new(0,10,0,54), rgb(30,24,50), 0)
corner(barTrack, 4)

local barFill = makeFrame(barTrack,
	UDim2.new(0,0,1,0), UDim2.new(0,0,0,0), C.qi, 0)
corner(barFill, 4)

local lblNextQi = makeLabel(cultivPanel, "Next realm: ---",
	UDim2.new(1,-10,0,14), UDim2.new(0,10,0,68), C.dim, 11)

local btnMeditate = makeButton(cultivPanel, "Meditate  [M]",
	UDim2.new(1,-20,0,22), UDim2.new(0,10,0,86), C.darkBlue, C.qi)
corner(btnMeditate, 5)

-- ============================================================
-- TOP-RIGHT: Moral Panel
-- ============================================================
local moralPanel = makeFrame(gui,
	UDim2.new(0,200,0,62), UDim2.new(1,-214,0,14), C.panel, 0.15)
corner(moralPanel, 8);  stroke(moralPanel, C.border)

makeLabel(moralPanel, "ALIGNMENT",
	UDim2.new(1,-10,0,14), UDim2.new(0,10,0,6), C.dim, 10)

local lblMoralTier = makeLabel(moralPanel, "Neutral",
	UDim2.new(1,-10,0,20), UDim2.new(0,10,0,20), C.neutral, 16)

local moralTrack = makeFrame(moralPanel,
	UDim2.new(1,-20,0,6), UDim2.new(0,10,0,46), rgb(30,24,50), 0)
corner(moralTrack, 3)

local moralLeft  = makeFrame(moralTrack, UDim2.new(0,0,1,0), UDim2.new(0.5,0,0,0), C.chaotic,   0)
local moralRight = makeFrame(moralTrack, UDim2.new(0,0,1,0), UDim2.new(0.5,0,0,0), C.righteous, 0)
makeFrame(moralTrack, UDim2.new(0,2,1,0), UDim2.new(0.5,-1,0,0), C.white, 0)

-- ============================================================
-- BOTTOM-LEFT: Sect Panel
-- ============================================================
local sectPanel = makeFrame(gui,
	UDim2.new(0,260,0,56), UDim2.new(0,14,1,-70), C.panel, 0.15)
corner(sectPanel, 8);  stroke(sectPanel, C.border)

makeLabel(sectPanel, "SECT", UDim2.new(0,60,0,14), UDim2.new(0,10,0,6), C.dim, 10)

local lblSectName = makeLabel(sectPanel, "Wandering Cultivator",
	UDim2.new(0,170,0,20), UDim2.new(0,10,0,20), C.gold, 14)

local lblSectAlign = makeLabel(sectPanel, "Neutral",
	UDim2.new(0,80,0,14), UDim2.new(0,10,0,40), C.neutral, 11)

local btnLeaveSect = makeButton(sectPanel, "Leave",
	UDim2.new(0,60,0,22), UDim2.new(0,190,0,22), rgb(60,20,20), C.red)
corner(btnLeaveSect, 5)
btnLeaveSect.MouseButton1Click:Connect(function()
	reLeaveSect:FireServer()
end)

local btnOpenSects = makeButton(gui, "Sects",
	UDim2.new(0,80,0,24), UDim2.new(0,284,1,-70), C.darkBlue, C.gold)
corner(btnOpenSects, 5);  stroke(btnOpenSects, C.gold)

-- ============================================================
-- SECT SELECTION PANEL (modal)
-- ============================================================
local sectSelectPanel = makeFrame(gui,
	UDim2.new(0,300,0,340), UDim2.new(0.5,-150,0.5,-170), C.panel, 0.05)
sectSelectPanel.Visible = false
corner(sectSelectPanel, 10);  stroke(sectSelectPanel, C.gold)

local lblSelectTitle = makeLabel(sectSelectPanel, "Choose Your Sect",
	UDim2.new(1,-20,0,24), UDim2.new(0,10,0,10), C.gold, 16)
lblSelectTitle.TextXAlignment = Enum.TextXAlignment.Center

local btnClose = makeButton(sectSelectPanel, "X",
	UDim2.new(0,24,0,24), UDim2.new(1,-34,0,10), C.red, C.white)
corner(btnClose, 4)
btnClose.MouseButton1Click:Connect(function()
	sectSelectPanel.Visible = false
end)

local sectScroll = Instance.new("ScrollingFrame")
sectScroll.Size = UDim2.new(1,-20,1,-50)
sectScroll.Position = UDim2.new(0,10,0,44)
sectScroll.BackgroundTransparency = 1
sectScroll.BorderSizePixel = 0
sectScroll.ScrollBarThickness = 4
sectScroll.ScrollBarImageColor3 = C.border
sectScroll.Parent = sectSelectPanel

local listLayout = Instance.new("UIListLayout")
listLayout.SortOrder = Enum.SortOrder.LayoutOrder
listLayout.Padding = UDim.new(0, 6)
listLayout.Parent = sectScroll

for i, sect in ipairs(GameData.Sects) do
	local row = makeFrame(sectScroll, UDim2.new(1,-8,0,56), UDim2.new(0,4,0,0), C.darkPanel, 0)
	row.LayoutOrder = i
	corner(row, 6)
	stroke(row, sect.color, 1)

	makeLabel(row, sect.name, UDim2.new(1,-80,0,18), UDim2.new(0,8,0,4), sect.color, 13)

	local desc = makeLabel(row, sect.description, UDim2.new(1,-80,0,28), UDim2.new(0,8,0,22), C.dim, 10)
	desc.TextWrapped = true

	local joinBtn = makeButton(row, "Join", UDim2.new(0,60,0,24), UDim2.new(1,-68,0,16), sect.color, C.black)
	corner(joinBtn, 5)
	joinBtn.TextColor3 = C.black

	local capturedId = sect.id
	joinBtn.MouseButton1Click:Connect(function()
		reJoinSect:FireServer({ sectId = capturedId })
		sectSelectPanel.Visible = false
	end)
end

listLayout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
	sectScroll.CanvasSize = UDim2.new(0, 0, 0, listLayout.AbsoluteContentSize.Y + 10)
end)

btnOpenSects.MouseButton1Click:Connect(function()
	sectSelectPanel.Visible = not sectSelectPanel.Visible
end)

-- ============================================================
-- NOTIFICATION TOAST
-- ============================================================
local notifQueue   = {}
local notifShowing = false

local notifFrame = makeFrame(gui,
	UDim2.new(0,360,0,44), UDim2.new(0.5,-180,0,-60), C.panel, 0.1)
corner(notifFrame, 8)
stroke(notifFrame, C.border)
notifFrame.Visible = false

local notifLabel = makeLabel(notifFrame, "",
	UDim2.new(1,-20,1,0), UDim2.new(0,10,0,0), C.text, 13)
notifLabel.TextXAlignment = Enum.TextXAlignment.Center
notifLabel.TextWrapped = true

local function showNextNotif()
	if notifShowing or #notifQueue == 0 then return end
	notifShowing = true
	notifLabel.Text = table.remove(notifQueue, 1)
	notifFrame.Position = UDim2.new(0.5,-180,0,-60)
	notifFrame.Visible  = true
	TweenService:Create(notifFrame, TweenInfo.new(0.3, Enum.EasingStyle.Quint),
		{ Position = UDim2.new(0.5,-180,0,10) }):Play()
	task.delay(3.2, function()
		TweenService:Create(notifFrame, TweenInfo.new(0.3, Enum.EasingStyle.Quint),
			{ Position = UDim2.new(0.5,-180,0,-60) }):Play()
		task.wait(0.35)
		notifFrame.Visible = false
		notifShowing = false
		showNextNotif()
	end)
end

-- ============================================================
-- BREAKTHROUGH SPLASH
-- ============================================================
local splashFrame = makeFrame(gui, UDim2.new(1,0,1,0), UDim2.new(0,0,0,0), C.black, 1)
splashFrame.ZIndex = 10
splashFrame.Visible = false

local splashTitle = makeLabel(splashFrame, "BREAKTHROUGH",
	UDim2.new(1,0,0,60), UDim2.new(0,0,0.38,0), C.gold, 38)
splashTitle.TextXAlignment = Enum.TextXAlignment.Center
splashTitle.ZIndex = 11
splashTitle.Font = Enum.Font.GothamBold

local splashSub = makeLabel(splashFrame, "",
	UDim2.new(1,0,0,30), UDim2.new(0,0,0.50,0), C.text, 17)
splashSub.TextXAlignment = Enum.TextXAlignment.Center
splashSub.ZIndex = 11

-- ============================================================
-- MEDITATE TOGGLE
-- ============================================================
local meditating = false

local function setMeditating(state)
	meditating = state
	btnMeditate.Text = state and "Stop Meditating" or "Meditate  [M]"
	btnMeditate.BackgroundColor3 = state and C.darkGreen or C.darkBlue
end

btnMeditate.MouseButton1Click:Connect(function()
	setMeditating(not meditating)
	reMeditate:FireServer({ action = meditating and "start" or "stop" })
end)

UserInputService.InputBegan:Connect(function(input, processed)
	if processed then return end
	if input.KeyCode == Enum.KeyCode.M then
		setMeditating(not meditating)
		reMeditate:FireServer({ action = meditating and "start" or "stop" })
	end
end)

-- ============================================================
-- HUD UPDATE HELPERS
-- ============================================================
local function getMoralTier(moral)
	for _, tier in ipairs(GameData.MoralTiers) do
		if moral >= tier.min and moral <= tier.max then
			return tier
		end
	end
	return GameData.MoralTiers[3]
end

local function getSectById(id)
	for _, s in ipairs(GameData.Sects) do
		if s.id == id then return s end
	end
end

local function updateHUD(data)
	if not data then return end

	-- Cultivation
	local ri    = data.realmIndex or 1
	local realm = GameData.CultivationRealms[ri] or GameData.CultivationRealms[1]
	local nextR = GameData.CultivationRealms[ri + 1]
	local qi    = data.qi or 0

	lblRealm.Text       = realm.name
	lblRealm.TextColor3 = GameData.RealmAuraColor[ri] or C.text
	lblQi.Text          = "Qi: " .. tostring(qi)

	local progress = 0
	if nextR then
		local span = nextR.minQi - realm.minQi
		progress   = math.clamp((qi - realm.minQi) / span, 0, 1)
		lblNextQi.Text = "Next: " .. nextR.name .. "  (" .. tostring(nextR.minQi - qi) .. " needed)"
	else
		progress = 1
		lblNextQi.Text = "Maximum Realm Achieved"
	end

	TweenService:Create(barFill, TweenInfo.new(0.4, Enum.EasingStyle.Quad),
		{ Size = UDim2.new(progress, 0, 1, 0) }):Play()

	-- Moral
	local moral   = data.moral or 0
	local morTier = getMoralTier(moral)
	lblMoralTier.Text       = morTier.name
	lblMoralTier.TextColor3 = morTier.color

	if moral < 0 then
		local pct = math.abs(moral) / 100
		TweenService:Create(moralLeft,  TweenInfo.new(0.4),
			{ Size = UDim2.new(pct * 0.5, 0, 1, 0),
				Position = UDim2.new(0.5 - pct * 0.5, 0, 0, 0) }):Play()
		TweenService:Create(moralRight, TweenInfo.new(0.4),
			{ Size = UDim2.new(0, 0, 1, 0) }):Play()
	else
		local pct = moral / 100
		TweenService:Create(moralRight, TweenInfo.new(0.4),
			{ Size = UDim2.new(pct * 0.5, 0, 1, 0) }):Play()
		TweenService:Create(moralLeft,  TweenInfo.new(0.4),
			{ Size     = UDim2.new(0, 0, 1, 0),
				Position = UDim2.new(0.5, 0, 0, 0) }):Play()
	end

	-- Sect
	local sect = getSectById(data.sectId)
	if sect then
		lblSectName.Text        = sect.name
		lblSectName.TextColor3  = sect.color
		lblSectAlign.Text       = sect.alignment
		lblSectAlign.TextColor3 = sect.alignment == "Righteous" and C.righteous
			or sect.alignment == "Chaotic" and C.chaotic
			or C.neutral
		btnLeaveSect.Visible    = sect.id ~= "WANDERER"
	end

	if data.meditating ~= nil then
		setMeditating(data.meditating)
	end
end

-- ============================================================
-- WIRE REMOTES  (direct — no BindableEvent middleman)
-- ============================================================

reUpdateHUD.OnClientEvent:Connect(updateHUD)

reNotify.OnClientEvent:Connect(function(message)
	table.insert(notifQueue, message)
	showNextNotif()
end)

reBreakthrough.OnClientEvent:Connect(function(info)
	splashSub.Text      = "You have reached " .. (info and info.realm or "a new realm") .. "!"
	splashFrame.BackgroundTransparency = 1
	splashFrame.Visible = true
	TweenService:Create(splashFrame, TweenInfo.new(0.5),
		{ BackgroundTransparency = 0.35 }):Play()
	task.delay(3.5, function()
		TweenService:Create(splashFrame, TweenInfo.new(0.6),
			{ BackgroundTransparency = 1 }):Play()
		task.wait(0.65)
		splashFrame.Visible = false
	end)
end)
