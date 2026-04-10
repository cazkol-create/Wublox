-- @ScriptType: LocalScript
-- @ScriptType: LocalScript
-- ============================================================
--  MovementClient.lua  |  LocalScript
--  Location: StarterCharacterScripts
--
--  CHANGES:
--    • Directional dash — getDashDirection() reads the player's
--      current movement input and maps it to "forward", "back",
--      "left", or "right" relative to the character's facing.
--      The direction is sent alongside the NormalDash action.
--
--    • Endlag tracking — listens for CharacterFeedback "EndlagStart"
--      events fired by CombatServer after attack hitboxes resolve.
--      While in endlag, dashing is blocked locally (matches the
--      server-side block already in Combat.OnServerEvent).
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
	DASH_COOLDOWN         = 3.0,    -- client visual; server enforces actual CD
	AUTO_SPRINT_AFTER_DASH= true,

	EVASIVE_DASH_KEYBIND  = Enum.KeyCode.E,
	EVASIVE_DASH_COOLDOWN = 15.0,

	SHIFT_LOCK_KEYBIND    = Enum.KeyCode.LeftControl,
	SHIFT_LOCK_OFFSET     = Vector3.new(2, 0, 0),
}

-- ============================================================
-- STATE
-- ============================================================
local isSprinting      = false
local dashAvailable    = true
local evasiveAvailable = true
local sprintHeartbeat  = nil
local lastWTapTime     = 0

-- ── Endlag tracking ───────────────────────────────────────────
-- Updated by CharacterFeedback "EndlagStart".
-- While time() < endlagExpiry, dashing is blocked.
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
-- Maps the player's current movement input to a dash direction
-- relative to the character's facing direction.
--
-- Roblox attachment-local space: -Z = forward, +Z = back
-- humanoid.MoveDirection is in world space.
-- We project it into character-local space to determine intent.
-- ============================================================
local function getDashDirection()
	local root = character:FindFirstChild("HumanoidRootPart")
	if not root then return "forward" end

	local moveDir = humanoid.MoveDirection
	if moveDir.Magnitude < CONFIG.MOVE_STOP_THRESHOLD then
		return "forward"   -- no directional input → forward dash
	end

	-- Project world-space move direction into local space of HRP.
	-- localDir.X = right/left  (+ = right)
	-- localDir.Z = backward/forward (- = forward in Roblox)
	local localDir = root.CFrame:VectorToObjectSpace(moveDir).Unit
	local ax, az   = math.abs(localDir.X), math.abs(localDir.Z)

	if az >= ax then
		-- Predominantly forward/back
		return localDir.Z < 0 and "forward" or "back"
	else
		-- Predominantly left/right
		return localDir.X > 0 and "right" or "left"
	end
end

-- ============================================================
-- NORMAL DASH
-- ============================================================
local function doDash()
	if isInEndlag()        then return end   -- endlag blocks dashing
	if not dashAvailable   then return end
	if isCCed()            then return end

	dashAvailable = false
	task.delay(CONFIG.DASH_COOLDOWN, function() dashAvailable = true end)

	local direction = getDashDirection()
	Combat:FireServer({ action = "NormalDash", direction = direction })

	-- Auto-sprint after a forward dash
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
-- SHIFT LOCK (Left Alt toggle)
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
-- ── EndlagStart: block dashing for the specified duration ────
-- Fired by CombatServer after each attack's hitbox resolves.
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
-- DEATH / RESPAWN
-- ============================================================
player.CharacterAdded:Connect(function()
	isSprinting    = false
	dashAvailable  = true
	evasiveAvailable = true
	endlagExpiry   = 0
	if sprintHeartbeat then sprintHeartbeat:Disconnect(); sprintHeartbeat = nil end
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