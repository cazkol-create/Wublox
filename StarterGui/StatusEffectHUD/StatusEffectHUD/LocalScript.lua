-- @ScriptType: LocalScript
-- @ScriptType: LocalScript
-- ============================================================
--  StatusEffectHUD.lua  |  LocalScript
--  Location: StarterGui/StatusEffectHUD/StatusEffectHUD
--  (ScreenGui: ResetOnSpawn = false, Name = "StatusEffectHUD")
--
--  Terraria-style status effect strip.
--  Shows a small icon + timer for every active status effect
--  on the local player's character.
--
--  To add a new status effect to the HUD:
--    1. Add an entry to EFFECT_DISPLAY_DATA below with:
--         boolValueName — the BoolValue tag name on the character
--         displayName   — tooltip / label
--         icon          — rbxassetid:// (leave "" for a text fallback)
--         color         — tint colour for the background
--    2. The StatusEffectUtil on the server creates/destroys the
--       BoolValue automatically.  The HUD just watches the character.
-- ============================================================

local Players      = game:GetService("Players")
local RunService   = game:GetService("RunService")
local RS           = game:GetService("ReplicatedStorage")

local player    = Players.LocalPlayer
local playerGui = player.PlayerGui

-- ============================================================
-- DEVELOPER CONFIG: add / edit status effect display data here.
-- ============================================================
local EFFECT_DISPLAY_DATA = {
	Stunned = {
		displayName = "Stunned",
		icon        = "",            -- replace with rbxassetid://
		color       = Color3.fromRGB(255, 200, 40),
	},
	SoftKnockdown = {
		displayName = "Knocked Down",
		icon        = "",
		color       = Color3.fromRGB(200, 100, 40),
	},
	HardKnockdown = {
		displayName = "Hard Knockdown",
		icon        = "",
		color       = Color3.fromRGB(200, 40, 40),
	},
	Ragdolled = {
		displayName = "Ragdolled",
		icon        = "",
		color       = Color3.fromRGB(140, 60, 200),
	},
	-- Add more as needed:
	-- Poisoned = { displayName = "Poisoned", icon = "rbxassetid://...", color = Color3.fromRGB(60,200,60) },
}

-- ============================================================
-- LAYOUT CONFIG
-- ============================================================
local CONFIG = {
	ICON_SIZE    = 40,
	ICON_GAP     = 6,
	BAR_X_OFFSET = 10,   -- pixels from left edge
	BAR_Y_OFFSET = -80,  -- pixels from bottom edge
}

-- ============================================================
-- ROOT GUI
-- ============================================================
local existingGui = playerGui:FindFirstChild("StatusEffectHUD")
if existingGui then existingGui:Destroy() end

local gui = Instance.new("ScreenGui")
gui.Name = "StatusEffectHUD"; gui.ResetOnSpawn = false
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.Parent = playerGui

local container = Instance.new("Frame")
container.Size  = UDim2.new(0, 300, 0, CONFIG.ICON_SIZE + 4)
container.Position = UDim2.new(0, CONFIG.BAR_X_OFFSET, 1, CONFIG.BAR_Y_OFFSET)
container.BackgroundTransparency = 1
container.BorderSizePixel = 0
container.Parent = gui

local listLayout = Instance.new("UIListLayout")
listLayout.FillDirection  = Enum.FillDirection.Horizontal
listLayout.SortOrder      = Enum.SortOrder.Name
listLayout.Padding        = UDim.new(0, CONFIG.ICON_GAP)
listLayout.VerticalAlignment = Enum.VerticalAlignment.Center
listLayout.Parent = container

-- ============================================================
-- ACTIVE EFFECT FRAMES  [effectName] = frame
-- ============================================================
local activeFrames = {}

local function makeCorner(p, r)
	local c = Instance.new("UICorner"); c.CornerRadius=UDim.new(0,r or 4); c.Parent=p
end

local function createEffectFrame(effectName)
	local data = EFFECT_DISPLAY_DATA[effectName]
	if not data then return end
	if activeFrames[effectName] then return end

	local frame = Instance.new("Frame")
	frame.Name = effectName
	frame.Size = UDim2.new(0, CONFIG.ICON_SIZE, 0, CONFIG.ICON_SIZE)
	frame.BackgroundColor3 = data.color
	frame.BackgroundTransparency = 0.2
	frame.BorderSizePixel = 0
	frame.Parent = container
	makeCorner(frame, 5)

	if data.icon ~= "" then
		local img = Instance.new("ImageLabel")
		img.Size = UDim2.new(1,-4,1,-18)
		img.Position = UDim2.new(0,2,0,2)
		img.BackgroundTransparency = 1
		img.Image = data.icon
		img.ScaleType = Enum.ScaleType.Fit
		img.Parent = frame
	else
		local abbrevLbl = Instance.new("TextLabel")
		abbrevLbl.Size = UDim2.new(1,0,0,CONFIG.ICON_SIZE - 18)
		abbrevLbl.Position = UDim2.new(0,0,0,2)
		abbrevLbl.BackgroundTransparency = 1
		abbrevLbl.Text = data.displayName:sub(1,2):upper()
		abbrevLbl.TextColor3 = Color3.new(1,1,1)
		abbrevLbl.TextSize = 13
		abbrevLbl.Font = Enum.Font.GothamBold
		abbrevLbl.TextXAlignment = Enum.TextXAlignment.Center
		abbrevLbl.Parent = frame
	end

	local timerLbl = Instance.new("TextLabel")
	timerLbl.Name = "Timer"
	timerLbl.Size = UDim2.new(1,0,0,14)
	timerLbl.Position = UDim2.new(0,0,1,-15)
	timerLbl.BackgroundTransparency = 1
	timerLbl.Text = ""
	timerLbl.TextColor3 = Color3.new(1,1,1)
	timerLbl.TextSize = 10
	timerLbl.Font = Enum.Font.GothamBold
	timerLbl.TextXAlignment = Enum.TextXAlignment.Center
	timerLbl.Parent = frame

	activeFrames[effectName] = { frame=frame, timerLbl=timerLbl, appliedAt=time() }
end

local function removeEffectFrame(effectName)
	local data = activeFrames[effectName]
	if not data then return end
	data.frame:Destroy()
	activeFrames[effectName] = nil
end

-- ============================================================
-- WATCH CHARACTER'S CHILDREN
-- ============================================================
local watchConnections = {}

local function watchCharacter(char)
	for _, conn in pairs(watchConnections) do conn:Disconnect() end
	watchConnections = {}
	for effectName in pairs(activeFrames) do removeEffectFrame(effectName) end

	if not char then return end

	-- Scan existing children (in case status effects were applied before this ran).
	for _, child in ipairs(char:GetChildren()) do
		if EFFECT_DISPLAY_DATA[child.Name] then
			createEffectFrame(child.Name)
		end
	end

	local addConn = char.ChildAdded:Connect(function(child)
		if EFFECT_DISPLAY_DATA[child.Name] then
			createEffectFrame(child.Name)
		end
	end)
	local removeConn = char.ChildRemoved:Connect(function(child)
		removeEffectFrame(child.Name)
	end)

	table.insert(watchConnections, addConn)
	table.insert(watchConnections, removeConn)
end

player.CharacterAdded:Connect(watchCharacter)
if player.Character then watchCharacter(player.Character) end

-- ============================================================
-- HEARTBEAT: update timer labels
-- ============================================================
RunService.Heartbeat:Connect(function()
	local char = player.Character
	if not char then return end

	for effectName, data in pairs(activeFrames) do
		local tag = char:FindFirstChild(effectName)
		if tag and data.timerLbl then
			-- BoolValue tags created by Debris don't expose their remaining time,
			-- so we can only show elapsed time.  For a proper countdown, the server
			-- would need to send the duration via CharacterFeedback.
			-- Show elapsed seconds for now.
			local elapsed = time() - data.appliedAt
			data.timerLbl.Text = string.format("%.1f", elapsed) .. "s"
		end
	end
end)