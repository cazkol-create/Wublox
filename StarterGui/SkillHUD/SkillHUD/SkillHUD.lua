-- @ScriptType: LocalScript
-- @ScriptType: LocalScript
-- ============================================================
--  SkillHUD.lua  |  LocalScript
--  Location: StarterGui/SkillHUD/SkillHUD
--  (ScreenGui: ResetOnSpawn = false, Name = "SkillHUD")
--
--  Shows 6 skill slots at the bottom of the screen.
--  Each slot shows: skill name, keybind label, cooldown overlay.
--  If a decal asset ID is set in SkillRegistry, it is shown as
--  an ImageLabel in the slot background.
--  Empty slots show only the keybind number.
-- ============================================================

local Players      = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local CAS          = game:GetService("ContextActionService")
local RS           = game:GetService("ReplicatedStorage")

local player    = Players.LocalPlayer
local playerGui = player.PlayerGui

local SkillRegistry = require(RS.Modules.SkillRegistry)
local CombatFB      = RS:WaitForChild("CombatFeedback")
local UseSkill      = RS:WaitForChild("UseSkill", 15)

-- ============================================================
-- DEVELOPER CONFIG
-- Change the keybinds for skill slots here.
-- ============================================================
local CONFIG = {
	MAX_SLOTS = 6,

	-- Keybind for each slot (index = slot number).
	SLOT_KEYBINDS = {
		Enum.KeyCode.One,
		Enum.KeyCode.Two,
		Enum.KeyCode.Three,
		Enum.KeyCode.Four,
		Enum.KeyCode.Five,
		Enum.KeyCode.Six,
	},

	SLOT_SIZE    = 58,
	SLOT_GAP     = 6,
	BAR_Y_OFFSET = -160,   -- pixels above bottom edge (adjust to sit above inventory)

	-- Cooldown overlay colour
	CD_OVERLAY_COLOR = Color3.fromRGB(8, 6, 16),
	CD_OVERLAY_ALPHA = 0.35,
}

-- ============================================================
-- PALETTE
-- ============================================================
local function rgb(r,g,b) return Color3.fromRGB(r,g,b) end
local C = {
	panel    = rgb(18, 14, 32),
	border   = rgb(80, 60,120),
	gold     = rgb(255,210, 60),
	dim      = rgb(120,110,140),
	text     = rgb(220,210,240),
	ready    = rgb(60, 200,100),
	empty    = rgb(35, 28, 55),
}

-- ============================================================
-- ROOT GUI
-- ============================================================
local existingGui = playerGui:FindFirstChild("SkillHUD")
if existingGui then existingGui:Destroy() end

local gui = Instance.new("ScreenGui")
gui.Name = "SkillHUD"; gui.ResetOnSpawn = false
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.Parent = playerGui

local BAR_W = CONFIG.MAX_SLOTS * (CONFIG.SLOT_SIZE + CONFIG.SLOT_GAP) + CONFIG.SLOT_GAP

local container = Instance.new("Frame")
container.Size             = UDim2.new(0, BAR_W, 0, CONFIG.SLOT_SIZE + 12)
container.Position         = UDim2.new(0.5, -BAR_W/2, 1, CONFIG.BAR_Y_OFFSET)
container.BackgroundTransparency = 1
container.BorderSizePixel  = 0
container.Parent           = gui

-- ============================================================
-- SLOT DATA  — rebuilt when Plr_EquippedSkills changes
-- ============================================================
local slots = {}    -- [slotIndex] = { frame, cdOverlay, cdTween, cdTask }

local function makeCorner(p, r)
	local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0,r or 6); c.Parent=p
end
local function makeStroke(p, col, t)
	local s = Instance.new("UIStroke"); s.Color=col or C.border; s.Thickness=t or 1; s.Parent=p
end

local function clearSlots()
	for _, data in ipairs(slots) do
		if data.cdTask then task.cancel(data.cdTask) end
		if data.cdTween then data.cdTween:Cancel() end
		if data.frame then data.frame:Destroy() end
	end
	slots = {}
	-- Unbind old skill actions so they don't ghost.
	for i = 1, CONFIG.MAX_SLOTS do
		CAS:UnbindAction("SkillHUD_Slot_" .. i)
	end
end

local function buildSlots(equippedCSV)
	clearSlots()

	local ids = {}
	if equippedCSV and equippedCSV ~= "" then
		for id in equippedCSV:gmatch("[^,]+") do
			table.insert(ids, id:match("^%s*(.-)%s*$"))
		end
	end

	for i = 1, CONFIG.MAX_SLOTS do
		local skillId = ids[i]
		local meta    = skillId and SkillRegistry.Get(skillId)

		local x = CONFIG.SLOT_GAP + (i-1) * (CONFIG.SLOT_SIZE + CONFIG.SLOT_GAP)

		local frame = Instance.new("Frame")
		frame.Size             = UDim2.new(0, CONFIG.SLOT_SIZE, 0, CONFIG.SLOT_SIZE)
		frame.Position         = UDim2.new(0, x, 0, 6)
		frame.BackgroundColor3 = meta and C.panel or C.empty
		frame.BackgroundTransparency = 0.15
		frame.BorderSizePixel  = 0
		frame.Parent           = container
		makeCorner(frame, 7)
		makeStroke(frame, meta and C.border or rgb(50,40,75))

		-- Slot number badge (top-left).
		local numLbl = Instance.new("TextLabel")
		numLbl.Size = UDim2.new(0,16,0,16)
		numLbl.Position = UDim2.new(0,3,0,3)
		numLbl.BackgroundTransparency = 1
		numLbl.Text = tostring(i)
		numLbl.TextColor3 = meta and C.gold or C.dim
		numLbl.TextSize = 10
		numLbl.Font = Enum.Font.GothamBold
		numLbl.Parent = frame

		if meta then
			-- Decal / icon (full-frame background image).
			if meta.icon and meta.icon ~= "" then
				local img = Instance.new("ImageLabel")
				img.Size = UDim2.new(1,-6,1,-6)
				img.Position = UDim2.new(0,3,0,3)
				img.BackgroundTransparency = 1
				img.Image = meta.icon
				img.ScaleType = Enum.ScaleType.Fit
				img.Parent = frame
			end

			-- Skill name (centre).
			local nameLbl = Instance.new("TextLabel")
			nameLbl.Size = UDim2.new(1,-4, 0.55, 0)
			nameLbl.Position = UDim2.new(0,2, 0.2, 0)
			nameLbl.BackgroundTransparency = 1
			nameLbl.Text = meta.displayName
			nameLbl.TextColor3 = C.text
			nameLbl.TextSize = 10
			nameLbl.Font = Enum.Font.GothamBold
			nameLbl.TextWrapped = true
			nameLbl.TextXAlignment = Enum.TextXAlignment.Center
			nameLbl.Parent = frame

			-- Keybind label (bottom-centre).
			local kbLbl = Instance.new("TextLabel")
			kbLbl.Size = UDim2.new(1,-4, 0, 14)
			kbLbl.Position = UDim2.new(0,2, 1,-16)
			kbLbl.BackgroundTransparency = 1
			local kb = CONFIG.SLOT_KEYBINDS[i]
			kbLbl.Text = kb and ("[" .. tostring(kb):match("[^.]+$") .. "]") or ""
			kbLbl.TextColor3 = C.gold
			kbLbl.TextSize = 9
			kbLbl.Font = Enum.Font.Gotham
			kbLbl.TextXAlignment = Enum.TextXAlignment.Center
			kbLbl.Parent = frame

			-- Cooldown overlay sweeps from top to bottom.
			local cdOverlay = Instance.new("Frame")
			cdOverlay.Size = UDim2.new(1,0,0,0)
			cdOverlay.Position = UDim2.new(0,0,0,0)
			cdOverlay.BackgroundColor3 = CONFIG.CD_OVERLAY_COLOR
			cdOverlay.BackgroundTransparency = CONFIG.CD_OVERLAY_ALPHA
			cdOverlay.BorderSizePixel = 0
			cdOverlay.ZIndex = frame.ZIndex + 2
			makeCorner(cdOverlay, 7)
			cdOverlay.Parent = frame

			-- Cooldown timer label (shown on the overlay when active).
			local cdLbl = Instance.new("TextLabel")
			cdLbl.Size = UDim2.new(1,0,1,0)
			cdLbl.BackgroundTransparency = 1
			cdLbl.Text = ""
			cdLbl.TextColor3 = rgb(255,255,255)
			cdLbl.TextSize = 15
			cdLbl.Font = Enum.Font.GothamBold
			cdLbl.TextXAlignment = Enum.TextXAlignment.Center
			cdLbl.ZIndex = frame.ZIndex + 3
			cdLbl.Parent = cdOverlay

			slots[i] = {
				frame     = frame,
				cdOverlay = cdOverlay,
				cdLbl     = cdLbl,
				cdTween   = nil,
				cdTask    = nil,
				skillId   = skillId,
			}

			-- Bind the keybind to this slot.
			local kb = CONFIG.SLOT_KEYBINDS[i]
			if kb then
				local capturedId   = skillId
				local capturedSlot = i
				CAS:BindAction("SkillHUD_Slot_" .. i, function(_, inputState, _)
					if inputState ~= Enum.UserInputState.Begin then
						return Enum.ContextActionResult.Pass
					end
					UseSkill:FireServer({ skillId = capturedId })
					return Enum.ContextActionResult.Sink
				end, false, kb)
			end
		else
			slots[i] = { frame=frame, skillId=nil }
		end
	end
end

-- ============================================================
-- COOLDOWN ANIMATION
-- ============================================================
local function startCooldown(slotIndex, duration)
	local data = slots[slotIndex]
	if not data or not data.cdOverlay then return end

	if data.cdTween then data.cdTween:Cancel() end
	if data.cdTask  then task.cancel(data.cdTask) end

	data.cdOverlay.Size     = UDim2.new(1,0,1,0)
	data.cdOverlay.Position = UDim2.new(0,0,0,0)

	local startTime = time()
	data.cdTask = task.spawn(function()
		while true do
			task.wait(0.05)
			local remaining = duration - (time() - startTime)
			if remaining <= 0 then
				data.cdOverlay.Size = UDim2.new(1,0,0,0)
				if data.cdLbl then data.cdLbl.Text = "" end
				break
			end
			local frac = remaining / duration
			data.cdOverlay.Size = UDim2.new(1,0, frac, 0)
			if data.cdLbl then
				data.cdLbl.Text = remaining >= 1
					and tostring(math.ceil(remaining))
					or  string.format("%.1f", remaining)
			end
		end
	end)
end

-- ============================================================
-- FIND SLOT INDEX BY SKILL ID
-- ============================================================
local function findSlot(skillId)
	for i, data in ipairs(slots) do
		if data.skillId == skillId then return i end
	end
	return nil
end

-- ============================================================
-- WATCH Plr_EquippedSkills
-- ============================================================
task.spawn(function()
	local val = player:WaitForChild("Plr_EquippedSkills", 10)
	if not val then return end
	buildSlots(val.Value)
	val.Changed:Connect(buildSlots)
end)

-- ============================================================
-- SERVER COOLDOWN EVENTS
-- ============================================================
CombatFB.OnClientEvent:Connect(function(data)
	if not data then return end
	if data.type == "SkillCooldown" and data.skillId and data.remaining then
		local idx = findSlot(data.skillId)
		if idx then startCooldown(idx, data.remaining) end
	end
end)

-- ============================================================
-- DEATH / RESPAWN
-- ============================================================
player.CharacterAdded:Connect(function()
	-- Cooldowns visually reset on respawn (server is authoritative).
	for _, data in ipairs(slots) do
		if data.cdOverlay then
			data.cdOverlay.Size = UDim2.new(1,0,0,0)
		end
		if data.cdLbl then data.cdLbl.Text = "" end
	end
end)