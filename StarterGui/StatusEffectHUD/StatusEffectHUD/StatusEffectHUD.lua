-- @ScriptType: LocalScript
-- @ScriptType: LocalScript

local Players      = game:GetService("Players")
local RunService   = game:GetService("RunService")

local player    = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- ============================================================
-- EFFECT DISPLAY CONFIG
-- ============================================================
local EFFECT_DISPLAY_DATA = {
	Stunned = {
		displayName = "Stunned",
		icon        = "rbxassetid://8508980536",
		color       = Color3.fromRGB(255, 200, 40),
	},
	SoftKnockdown = {
		displayName = "Knocked Down",
		icon        = "rbxassetid://8508980536",
		color       = Color3.fromRGB(200, 100, 40),
	},
	HardKnockdown = {
		displayName = "Hard Knockdown",
		icon        = "rbxassetid://8508980536",
		color       = Color3.fromRGB(200, 40, 40),
	},
	Ragdolled = {
		displayName = "Ragdolled",
		icon        = "rbxassetid://8508980536",
		color       = Color3.fromRGB(140, 60, 200),
	},
}

-- ============================================================
-- LAYOUT CONFIG
-- ============================================================
local CONFIG = {
	ICON_SIZE    = 40,
	ICON_GAP     = 6,
	BAR_X_OFFSET = 10,
	BAR_Y_OFFSET = -80,
}

-- ============================================================
-- GUI SETUP
-- ============================================================
local existingGui = playerGui:FindFirstChild("StatusEffectHUD")
if existingGui then existingGui:Destroy() end

local gui = Instance.new("ScreenGui")
gui.Name = "StatusEffectHUD"
gui.ResetOnSpawn = false
gui.Parent = playerGui

local container = Instance.new("Frame")
container.Size  = UDim2.new(0, 300, 0, CONFIG.ICON_SIZE + 4)
container.Position = UDim2.new(0, CONFIG.BAR_X_OFFSET, 1, CONFIG.BAR_Y_OFFSET)
container.BackgroundTransparency = 1
container.Parent = gui

local listLayout = Instance.new("UIListLayout")
listLayout.FillDirection  = Enum.FillDirection.Horizontal
listLayout.SortOrder      = Enum.SortOrder.LayoutOrder -- ✅ upgrade 3
listLayout.Padding        = UDim.new(0, CONFIG.ICON_GAP)
listLayout.VerticalAlignment = Enum.VerticalAlignment.Center
listLayout.Parent = container

-- ============================================================
-- STORAGE
-- ============================================================
local activeFrames = {}
local watchConnections = {}

local function makeCorner(p, r)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, r or 4)
	c.Parent = p
end

-- ============================================================
-- CREATE FRAME
-- ============================================================
local function createEffectFrame(effectName)
	if activeFrames[effectName] then return end
	local data = EFFECT_DISPLAY_DATA[effectName]
	if not data then return end

	local frame = Instance.new("Frame")
	frame.Name = effectName
	frame.Size = UDim2.new(0, CONFIG.ICON_SIZE, 0, CONFIG.ICON_SIZE)
	frame.BackgroundColor3 = data.color
	frame.BackgroundTransparency = 0.2
	frame.Parent = container
	makeCorner(frame, 5)

	-- Icon
	if data.icon ~= "" then
		local img = Instance.new("ImageLabel")
		img.Size = UDim2.new(1,-4,1,-18)
		img.Position = UDim2.new(0,2,0,2)
		img.BackgroundTransparency = 1
		img.Image = data.icon
		img.Parent = frame
	end

	-- Timer
	local timerLbl = Instance.new("TextLabel")
	timerLbl.Name = "Timer"
	timerLbl.Size = UDim2.new(1,0,0,14)
	timerLbl.Position = UDim2.new(0,0,1,-15)
	timerLbl.BackgroundTransparency = 1
	timerLbl.TextColor3 = Color3.new(1,1,1)
	timerLbl.TextSize = 10
	timerLbl.Font = Enum.Font.GothamBold
	timerLbl.Parent = frame

	-- Stack label (upgrade 5)
	local stackLbl = Instance.new("TextLabel")
	stackLbl.Name = "Stack"
	stackLbl.Size = UDim2.new(0,16,0,16)
	stackLbl.Position = UDim2.new(1,-16,0,0)
	stackLbl.BackgroundTransparency = 1
	stackLbl.TextColor3 = Color3.new(1,1,1)
	stackLbl.TextSize = 12
	stackLbl.Font = Enum.Font.GothamBold
	stackLbl.Parent = frame

	-- Tooltip (upgrade 4)
	local tooltip = Instance.new("TextLabel")
	tooltip.Visible = false
	tooltip.Size = UDim2.new(0,120,0,20)
	tooltip.Position = UDim2.new(0,0,-1,0)
	tooltip.BackgroundColor3 = Color3.fromRGB(30,30,30)
	tooltip.TextColor3 = Color3.new(1,1,1)
	tooltip.TextSize = 12
	tooltip.Text = data.displayName
	tooltip.Parent = frame
	makeCorner(tooltip, 4)

	frame.MouseEnter:Connect(function()
		tooltip.Visible = true
	end)

	frame.MouseLeave:Connect(function()
		tooltip.Visible = false
	end)

	activeFrames[effectName] = {
		frame = frame,
		timerLbl = timerLbl,
		stackLbl = stackLbl,
	}
end

local function removeEffectFrame(effectName)
	local data = activeFrames[effectName]
	if not data then return end
	data.frame:Destroy()
	activeFrames[effectName] = nil
end

-- ============================================================
-- WATCH CHARACTER
-- ============================================================
local function watchCharacter(char)
	for _, conn in pairs(watchConnections) do
		conn:Disconnect()
	end
	watchConnections = {}

	for effectName in pairs(activeFrames) do
		removeEffectFrame(effectName)
	end

	if not char then return end

	for _, child in ipairs(char:GetChildren()) do
		if EFFECT_DISPLAY_DATA[child.Name] then
			createEffectFrame(child.Name)
		end
	end

	table.insert(watchConnections,
		char.ChildAdded:Connect(function(child)
			if EFFECT_DISPLAY_DATA[child.Name] then
				createEffectFrame(child.Name)
			end
		end)
	)

	table.insert(watchConnections,
		char.ChildRemoved:Connect(function(child)
			removeEffectFrame(child.Name)
		end)
	)
end

player.CharacterAdded:Connect(watchCharacter)
if player.Character then watchCharacter(player.Character) end

-- ============================================================
-- HEARTBEAT LOOP
-- ============================================================
RunService.Heartbeat:Connect(function()
	local char = player.Character
	if not char then return end

	for effectName, data in pairs(activeFrames) do
		local tag = char:FindFirstChild(effectName)
		if not tag then continue end

		-- Duration system (recommended server attributes)
		local duration = tag:GetAttribute("Duration")
		local appliedAt = tag:GetAttribute("AppliedAt")

		local remaining = nil

		if duration and appliedAt then
			remaining = duration - (time() - appliedAt)
			remaining = math.max(0, remaining)

			data.timerLbl.Text = string.format("%.1f", remaining) .. "s"

			-- Flash when low (upgrade 2)
			if remaining <= 1 then
				data.frame.BackgroundTransparency = 0.5 + math.sin(time()*10)*0.3
			else
				data.frame.BackgroundTransparency = 0.2
			end

			-- Sorting (upgrade 3)
			data.frame.LayoutOrder = math.floor(remaining * 100)
		else
			data.timerLbl.Text = ""
		end

		-- Stack support (upgrade 5)
		local stacks = tag:GetAttribute("Stacks")
			or (tag:IsA("IntValue") and tag.Value)

		if stacks and stacks > 1 then
			data.stackLbl.Text = tostring(stacks)
		else
			data.stackLbl.Text = ""
		end
	end
end)