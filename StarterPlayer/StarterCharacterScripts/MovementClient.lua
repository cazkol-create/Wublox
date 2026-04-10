-- @ScriptType: LocalScript
-- @ScriptType: LocalScript
-- ============================================================
--  MovementClient.lua  |  LocalScript
--  Location: StarterCharacterScripts
--
--  CHANGES:
--    • Directional dash — getDashDirection() reads current WASD input.
--    • Endlag tracking — CharacterFeedback "EndlagStart" blocks dashing.
--    • JUMP COOLDOWN — humanoid.Jumping listener immediately disables
--      jumping via SetStateEnabled for JUMP_COOLDOWN_SEC seconds after
--      each jump.  This prevents bunny-hopping and gives jumps a more
--      deliberate, wuxia-weighted feel.
--      KEEP IN SYNC with CombatConfig.JUMP_COOLDOWN (server-side).
-- ============================================================

local Players       = game:GetService("Players")
local UIS           = game:GetService("UserInputService")
local CAS           = game:GetService("ContextActionService")
local RunService    = game:GetService("RunService")
local RS            = game:GetService("ReplicatedStorage")

local player    = Players.LocalPlayer
local character = script.Parent
local humanoid  = character:WaitForChild("Humanoid")
local mouse     = player:GetMouse()

local Combat            = RS:WaitForChild("Combat")
local CharacterFeedback = RS:WaitForChild("CharacterFeedback", 10)

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

	-- ── Jump cooldown ─────────────────────────────────────────
	-- Mirror of CombatConfig.JUMP_COOLDOWN on the server.
	-- Both values must be kept in sync manually.
	JUMP_COOLDOWN         = 0.5,
}

-- ============================================================
-- STATE
-- ============================================================
local isSprinting      = false
local dashAvailable    = true
local evasiveAvailable = true
local sprintHeartbeat  = nil
local lastWTapTime     = 0

-- Endlag tracking (updated by CharacterFeedback "EndlagStart")
local endlagExpiry = 0
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
local function stopSprint()
	if not isSprinting then return end
	isSprinting = false
	humanoid.WalkSpeed = CONFIG.NORMAL_SPEED
	if sprintHeartbeat then sprintHeartbeat:Disconnect(); sprintHeartbeat = nil end
end

local function startSprint()
	if isSprinting then return end
	if isCCed() then return end
	if humanoid.MoveDirection.Magnitude < CONFIG.MOVE_STOP_THRESHOLD then return end
	isSprinting = true
	humanoid.WalkSpeed = CONFIG.SPRINT_SPEED
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
	if n=="Stunned" or n=="SoftKnockdown" or n=="HardKnockdown" or n=="Ragdolled" then
		stopSprint()
	end
end)

-- ============================================================
-- DIRECTION DETECTION
-- ============================================================
local function getDashDirection()
	local root = character:FindFirstChild("HumanoidRootPart")
	if not root then return "forward" end

	local moveDir = humanoid.MoveDirection
	if moveDir.Magnitude < CONFIG.MOVE_STOP_THRESHOLD then
		return "forward"
	end

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
-- EVASIVE DASH (out of SoftKnockdown)
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
-- CHARACTER FEEDBACK
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
-- ============================================================
-- When the humanoid starts a jump, disable jumping for JUMP_COOLDOWN seconds.
-- The current jump still completes normally (physics are already applied),
-- but the player cannot immediately jump again until the cooldown expires.
-- This mirrors CombatConfig.JUMP_COOLDOWN — keep both values in sync.
do
	humanoid.Jumping:Connect(function(active)
		if not active then return end
		-- Immediately lock out the next jump.
		humanoid:SetStateEnabled(Enum.HumanoidStateType.Jumping, false)
		task.delay(CONFIG.JUMP_COOLDOWN, function()
			if humanoid and humanoid.Parent then
				humanoid:SetStateEnabled(Enum.HumanoidStateType.Jumping, true)
			end
		end)
	end)
end

-- ============================================================
-- DEATH / RESPAWN
-- ============================================================
player.CharacterAdded:Connect(function()
	isSprinting      = false
	dashAvailable    = true
	evasiveAvailable = true
	endlagExpiry     = 0
	if sprintHeartbeat then sprintHeartbeat:Disconnect(); sprintHeartbeat = nil end
	-- Re-enable jumping in case the character died mid-cooldown.
	if humanoid then
		humanoid:SetStateEnabled(Enum.HumanoidStateType.Jumping, true)
	end
end)

-- ============================================================
-- PUBLIC API
-- ============================================================
_G.WuxiaMovement = {
	IsSprinting      = function() return isSprinting end,
	StartSprint      = startSprint,
	StopSprint       = stopSprint,
	DashAvailable    = function() return dashAvailable end,
	EvasiveAvailable = function() return evasiveAvailable end,
	IsInEndlag       = isInEndlag,
}