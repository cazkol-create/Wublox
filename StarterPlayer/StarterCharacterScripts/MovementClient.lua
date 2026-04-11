-- @ScriptType: LocalScript
-- @ScriptType: LocalScript
-- ============================================================
--  MovementClient.lua  |  LocalScript
--  Location: StarterCharacterScripts
--
--  CHANGES IN THIS VERSION:
--
--  1. RUN ANIMATION
--     AnimationHandler manages a "Sprint" group.
--     Run animation loaded from RS/Animations/Movement/Run.
--     Plays when sprint starts, stops when sprint ends.
--     CombatClient hooks via _G.WuxiaMovement.OnSprintChanged().
--
--  2. SLIDE SYSTEM
--     Press C while sprinting (and grounded) to slide.
--     • Client: plays Slide animation optimistically, fires server.
--     • Server: (MovementUtil.Slide) applies forward velocity,
--       handles slope detection, grants brief I-frames.
--     • CONFIG.SLIDE_DURATION / SLIDE_COOLDOWN control timing.
--
--  3. JUMP COOLDOWN
--     humanoid.Jumping listener disables jumping for JUMP_COOLDOWN
--     seconds after each jump via SetStateEnabled.
--     Mirrors CombatConfig.JUMP_COOLDOWN — keep both in sync.
--
--  4. SPRINT CALLBACK HOOK
--     _G.WuxiaMovement.OnSprintChanged(fn) lets CombatClient
--     subscribe to sprint state changes for run animation sync.
-- ============================================================

local Players       = game:GetService("Players")
local UIS           = game:GetService("UserInputService")
local CAS           = game:GetService("ContextActionService")
local RunService    = game:GetService("RunService")
local RS            = game:GetService("ReplicatedStorage")

local player    = Players.LocalPlayer
local character = script.Parent
local humanoid  = character:WaitForChild("Humanoid")
local animator  = humanoid:WaitForChild("Animator")
local mouse     = player:GetMouse()

local AnimationHandler = require(RS.Modules.AnimationHandler)
local Combat           = RS:WaitForChild("Combat")
local CharacterFeedback= RS:WaitForChild("CharacterFeedback", 10)

-- AnimationHandler instance for movement-specific animations.
-- Uses separate groups from CombatClient so there's no cross-script conflict.
local moveAnim = AnimationHandler.new(animator)

-- ============================================================
-- MOVEMENT ANIMATION LOADING
-- ============================================================
local movementTracks    = {}  -- [animName] = AnimationTrack
local animRoot          = RS:WaitForChild("Animations", 10)

task.spawn(function()
	if not animRoot then return end
	local folder = animRoot:FindFirstChild("Movement")
	if not folder then
		warn("[MovementClient] RS/Animations/Movement/ not found")
		return
	end
	for _, child in ipairs(folder:GetDescendants()) do
		if child:IsA("Animation") then
			local ok, t = pcall(function() return animator:LoadAnimation(child) end)
			if ok and t then
				movementTracks[child.Name] = t
			end
		end
	end
end)

-- ============================================================
-- DEVELOPER CONFIG
-- ============================================================
local CONFIG = {
	NORMAL_SPEED          = 16,
	SPRINT_SPEED          = 26,
	W_DOUBLE_TAP_WINDOW   = 0.30,
	MOVE_STOP_THRESHOLD   = 0.05,

	DASH_KEYBIND          = Enum.KeyCode.LeftShift,
	DASH_COOLDOWN         = 3.0,
	AUTO_SPRINT_AFTER_DASH= true,

	EVASIVE_DASH_KEYBIND  = Enum.KeyCode.E,
	EVASIVE_DASH_COOLDOWN = 15.0,

	SHIFT_LOCK_KEYBIND    = Enum.KeyCode.LeftControl,
	SHIFT_LOCK_OFFSET     = Vector3.new(2, 0, 0),

	SLIDE_KEYBIND         = Enum.KeyCode.C,
	SLIDE_DURATION        = 0.8,   -- keep in sync with CombatConfig.SLIDE_DURATION
	SLIDE_COOLDOWN        = 1.5,   -- keep in sync with CombatConfig.SLIDE_COOLDOWN

	-- Keep in sync with CombatConfig.JUMP_COOLDOWN
	JUMP_COOLDOWN         = 0.5,
}

-- ============================================================
-- STATE
-- ============================================================
local isSprinting      = false
local dashAvailable    = true
local evasiveAvailable = true
local slideAvailable   = true
local isSliding        = false
local sprintHeartbeat  = nil
local lastWTapTime     = 0
local endlagExpiry     = 0

-- Sprint change callbacks (registered by CombatClient for run anim)
local sprintCallbacks  = {}

local function fireSprintChanged(state)
	for _, fn in ipairs(sprintCallbacks) do
		task.spawn(fn, state)
	end
end

local function isInEndlag() return time() < endlagExpiry end

-- ============================================================
-- CC CHECKS
-- ============================================================
local function isStunned()         return character:FindFirstChild("Stunned")       ~= nil end
local function isSoftKnockedDown() return character:FindFirstChild("SoftKnockdown") ~= nil end
local function isHardKnockedDown() return character:FindFirstChild("HardKnockdown") ~= nil end
local function isKnockedDown()     return isSoftKnockedDown() or isHardKnockedDown() end
local function isRagdolled()       return character:FindFirstChild("Ragdolled")     ~= nil end
local function isCCed()            return isStunned() or isKnockedDown() or isRagdolled() end

-- ============================================================
-- SPRINT
-- ============================================================
local function stopSprint(skipAnim)
	if not isSprinting then return end
	isSprinting = false
	humanoid.WalkSpeed = CONFIG.NORMAL_SPEED
	if sprintHeartbeat then sprintHeartbeat:Disconnect(); sprintHeartbeat = nil end
	if not skipAnim then
		moveAnim:Stop("Sprint", 0.2)
		fireSprintChanged(false)
	end
end

local function startSprint()
	if isSprinting then return end
	if isCCed() then return end
	if humanoid.MoveDirection.Magnitude < CONFIG.MOVE_STOP_THRESHOLD then return end
	isSprinting = true
	humanoid.WalkSpeed = CONFIG.SPRINT_SPEED

	-- Run animation
	local runTrack = movementTracks["Run"]
	if runTrack then
		moveAnim:Play("Sprint", runTrack, 0.2)
	end
	fireSprintChanged(true)

	sprintHeartbeat = RunService.Heartbeat:Connect(function()
		if isCCed() then stopSprint(); return end
		if humanoid.MoveDirection.Magnitude < CONFIG.MOVE_STOP_THRESHOLD then stopSprint() end
	end)
end

UIS.InputBegan:Connect(function(input, processed)
	if processed then return end
	if input.KeyCode == Enum.KeyCode.W then
		local now = time()
		if now - lastWTapTime <= CONFIG.W_DOUBLE_TAP_WINDOW then startSprint() end
		lastWTapTime = now
	end
end)
UIS.InputEnded:Connect(function(input)
	if input.KeyCode == Enum.KeyCode.W then stopSprint() end
end)

character.ChildAdded:Connect(function(child)
	local n = child.Name
	if n == "Stunned" or n == "SoftKnockdown" or n == "HardKnockdown" or n == "Ragdolled" then
		stopSprint()
		if isSliding then
			isSliding = false
			moveAnim:Stop("Slide", 0.2)
		end
	end
end)

-- ============================================================
-- DIRECTION DETECTION
-- ============================================================
local function getDashDirection()
	local root = character:FindFirstChild("HumanoidRootPart")
	if not root then return "forward" end
	local moveDir = humanoid.MoveDirection
	if moveDir.Magnitude < CONFIG.MOVE_STOP_THRESHOLD then return "forward" end
	local localDir = root.CFrame:VectorToObjectSpace(moveDir).Unit
	local ax, az   = math.abs(localDir.X), math.abs(localDir.Z)
	if az >= ax then
		return localDir.Z < 0 and "forward" or "back"
	else
		return localDir.X > 0 and "right" or "left"
	end
end

-- ============================================================
-- NORMAL DASH
-- ============================================================
local function doDash()
	if isInEndlag()      then return end
	if not dashAvailable then return end
	if isCCed()          then return end

	dashAvailable = false
	task.delay(CONFIG.DASH_COOLDOWN, function() dashAvailable = true end)

	local direction = getDashDirection()
	Combat:FireServer({ action = "NormalDash", direction = direction })

	if CONFIG.AUTO_SPRINT_AFTER_DASH and direction == "forward" then
		task.delay(0.4, function()
			if not isCCed() then startSprint() end
		end)
	end
end

CAS:BindAction("Movement_Dash", function(_, state, _)
	if state ~= Enum.UserInputState.Begin then return Enum.ContextActionResult.Pass end
	doDash()
	return Enum.ContextActionResult.Sink
end, false, CONFIG.DASH_KEYBIND)

-- ============================================================
-- EVASIVE DASH
-- ============================================================
local function doEvasiveDash()
	if not evasiveAvailable   then return end
	if not isSoftKnockedDown() then return end
	evasiveAvailable = false
	task.delay(CONFIG.EVASIVE_DASH_COOLDOWN, function() evasiveAvailable = true end)
	Combat:FireServer({ action = "EvasiveDash" })
end

CAS:BindAction("Movement_EvasiveDash", function(_, state, _)
	if state ~= Enum.UserInputState.Begin then return Enum.ContextActionResult.Pass end
	doEvasiveDash()
	return Enum.ContextActionResult.Sink
end, false, CONFIG.EVASIVE_DASH_KEYBIND)

-- ============================================================
-- SLIDE SYSTEM
-- Press C while sprinting + grounded → server-authoritative velocity boost.
-- Client plays animation optimistically; server confirms and applies force.
-- ============================================================
local function doSlide()
	if not isSprinting          then return end
	if not slideAvailable       then return end
	if isCCed()                 then return end
	if isSliding                then return end
	-- Require grounded state
	if humanoid.FloorMaterial == Enum.Material.Air then return end

	isSliding      = true
	slideAvailable = false

	-- Update sprint state without triggering the run anim stop
	if sprintHeartbeat then sprintHeartbeat:Disconnect(); sprintHeartbeat = nil end
	isSprinting = false
	fireSprintChanged(false)

	-- Optimistic animation
	local slideTrack = movementTracks["Slide"]
	if slideTrack then
		moveAnim:Stop("Sprint", 0.05)
		moveAnim:Play("Slide", slideTrack, 0.1)
	end

	-- Fire to server for velocity + I-frames
	Combat:FireServer({ action = "Slide" })

	-- Restore after slide duration
	task.delay(CONFIG.SLIDE_DURATION, function()
		isSliding = false
		if slideTrack then moveAnim:Stop("Slide", 0.3) end
	end)

	task.delay(CONFIG.SLIDE_COOLDOWN, function()
		slideAvailable = true
	end)
end

CAS:BindAction("Movement_Slide", function(_, state, _)
	if state ~= Enum.UserInputState.Begin then return Enum.ContextActionResult.Pass end
	doSlide()
	return Enum.ContextActionResult.Sink
end, false, CONFIG.SLIDE_KEYBIND)

-- ============================================================
-- SHIFT LOCK
-- ============================================================
if CONFIG.SHIFT_LOCK_KEYBIND then
	local UserGameSettings = UserSettings():GetService("UserGameSettings")
	pcall(function()
		UserGameSettings.RotationType = Enum.RotationType.MovementRelative
	end)
	UIS.InputBegan:Connect(function(input, processed)
		if processed or input.KeyCode ~= CONFIG.SHIFT_LOCK_KEYBIND then return end
		pcall(function()
			if UserGameSettings.RotationType == Enum.RotationType.CameraRelative then
				UserGameSettings.RotationType = Enum.RotationType.MovementRelative
				UIS.MouseBehavior             = Enum.MouseBehavior.Default
				humanoid.CameraOffset         = Vector3.zero
				mouse.Icon                    = ""
			else
				UserGameSettings.RotationType = Enum.RotationType.CameraRelative
				UIS.MouseBehavior             = Enum.MouseBehavior.LockCenter
				humanoid.CameraOffset         = CONFIG.SHIFT_LOCK_OFFSET
				mouse.Icon                    = "rbxassetid://10213989924"
			end
		end)
	end)
end

-- ============================================================
-- CHARACTER FEEDBACK  (endlag from server)
-- ============================================================
if CharacterFeedback then
	CharacterFeedback.OnClientEvent:Connect(function(data)
		if not data then return end
		if data.type == "EndlagStart" and data.duration and data.duration > 0 then
			endlagExpiry = time() + data.duration
		end
	end)
end

-- ============================================================
-- JUMP COOLDOWN
-- Disables jumping via SetStateEnabled for JUMP_COOLDOWN seconds
-- after each jump fires.  The current jump physics proceed normally.
-- Keep CONFIG.JUMP_COOLDOWN in sync with CombatConfig.JUMP_COOLDOWN.
-- ============================================================
humanoid.Jumping:Connect(function(active)
	if not active then return end
	humanoid:SetStateEnabled(Enum.HumanoidStateType.Jumping, false)
	task.delay(CONFIG.JUMP_COOLDOWN, function()
		if humanoid and humanoid.Parent then
			humanoid:SetStateEnabled(Enum.HumanoidStateType.Jumping, true)
		end
	end)
end)

-- ============================================================
-- DEATH / RESPAWN
-- ============================================================
player.CharacterAdded:Connect(function()
	isSprinting      = false
	dashAvailable    = true
	evasiveAvailable = true
	slideAvailable   = true
	isSliding        = false
	endlagExpiry     = 0
	if sprintHeartbeat then sprintHeartbeat:Disconnect(); sprintHeartbeat = nil end
	-- Re-enable jumping in case character died mid-jump-cooldown
	if humanoid then
		humanoid:SetStateEnabled(Enum.HumanoidStateType.Jumping, true)
	end
end)

-- ============================================================
-- PUBLIC API
-- ============================================================
_G.WuxiaMovement = {
	IsSprinting      = function() return isSprinting end,
	IsSliding        = function() return isSliding end,
	StartSprint      = startSprint,
	StopSprint       = stopSprint,
	DashAvailable    = function() return dashAvailable end,
	EvasiveAvailable = function() return evasiveAvailable end,
	IsInEndlag       = isInEndlag,

	-- CombatClient hooks this to sync the Run animation.
	OnSprintChanged  = function(fn)
		table.insert(sprintCallbacks, fn)
	end,
}