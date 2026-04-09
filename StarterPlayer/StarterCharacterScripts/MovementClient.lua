-- @ScriptType: LocalScript
-- @ScriptType: LocalScript
-- ============================================================
--  MovementClient.lua  |  LocalScript
--  Location: StarterCharacterScripts
--
--  Handles all movement-related client logic:
--    Sprint     — double-tap W; stops on CC, no movement, or W release
--    Normal Dash— Shift key; sends to server; 3s cooldown (server enforced)
--    Evasive Dash (get out of SoftKnockdown) — E key; 15s cooldown
--    Shift Lock — Left Alt toggle (replaces default Left Shift)
--
--  All developer-tunable values live in the CONFIG table below.
-- ============================================================

local Players       = game:GetService("Players")
local UIS           = game:GetService("UserInputService")
local CAS           = game:GetService("ContextActionService")
local RunService    = game:GetService("RunService")
local RS            = game:GetService("ReplicatedStorage")

local player    = Players.LocalPlayer
local character = script.Parent
local humanoid  = character:WaitForChild("Humanoid")
local mouse = player:GetMouse()

-- Wait for remotes
local Combat = RS:WaitForChild("Combat")
local CharacterFeedback = RS:WaitForChild("CharacterFeedback", 10)

-- ============================================================
-- DEVELOPER CONFIG  — change these freely
-- ============================================================
local CONFIG = {
	-- ── Speeds ─────────────────────────────────────────────────
	NORMAL_SPEED = 16,
	SPRINT_SPEED = 26,

	-- ── Sprint trigger ─────────────────────────────────────────
	-- Double-tap W within this window (seconds) to start sprinting.
	W_DOUBLE_TAP_WINDOW = 0.30,
	-- MoveDirection magnitude below this → consider stopped → stop sprint.
	MOVE_STOP_THRESHOLD = 0.05,

	-- ── Normal dash ────────────────────────────────────────────
	DASH_KEYBIND  = Enum.KeyCode.LeftShift,
	DASH_COOLDOWN = 3.0,   -- seconds (visual; server enforces actual CD)

	-- Automatically sprint after a normal dash.
	-- Set to false if unsure — can be changed any time.
	AUTO_SPRINT_AFTER_DASH = true,

	-- ── Evasive dash ───────────────────────────────────────────
	EVASIVE_DASH_KEYBIND  = Enum.KeyCode.E,
	EVASIVE_DASH_COOLDOWN = 15.0,  -- seconds (visual; server enforces)

	-- ── Shift lock ─────────────────────────────────────────────
	-- Set to nil to disable the custom shift lock toggle.
	SHIFT_LOCK_KEYBIND = Enum.KeyCode.LeftAlt,
	SHIFT_LOCK_OFFSET = Vector3.new(2,0,0)
}

-- ============================================================
-- STATE
-- ============================================================
local isSprinting       = false
local dashAvailable     = true
local evasiveAvailable  = true
local sprintHeartbeat   = nil

local lastWTapTime      = 0

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
local function stopSprint(reason)
	if not isSprinting then return end
	isSprinting = false
	humanoid.WalkSpeed = CONFIG.NORMAL_SPEED
	if sprintHeartbeat then
		sprintHeartbeat:Disconnect()
		sprintHeartbeat = nil
	end
end

local function startSprint()
	if isSprinting then return end
	if isCCed() then return end
	if humanoid.MoveDirection.Magnitude < CONFIG.MOVE_STOP_THRESHOLD then return end
	isSprinting = true
	humanoid.WalkSpeed = CONFIG.SPRINT_SPEED
	-- Monitor for stop conditions on every frame
	sprintHeartbeat = RunService.Heartbeat:Connect(function()
		if isCCed() then
			stopSprint("cc")
			return
		end
		if humanoid.MoveDirection.Magnitude < CONFIG.MOVE_STOP_THRESHOLD then
			stopSprint("no_movement")
		end
	end)
end

-- Double-tap W detection
UIS.InputBegan:Connect(function(input, processed)
	if processed then return end
	if input.KeyCode == Enum.KeyCode.W then
		local now = time()
		if now - lastWTapTime <= CONFIG.W_DOUBLE_TAP_WINDOW then
			startSprint()
		end
		lastWTapTime = now
	end
end)

-- W released → stop sprint
UIS.InputEnded:Connect(function(input)
	if input.KeyCode == Enum.KeyCode.W then
		stopSprint("w_released")
	end
end)

-- CC → stop sprint immediately
character.ChildAdded:Connect(function(child)
	local n = child.Name
	if n=="Stunned" or n=="SoftKnockdown" or n=="HardKnockdown" or n=="Ragdolled" then
		stopSprint("cc")
	end
end)

-- ============================================================
-- NORMAL DASH  (Shift key → action="NormalDash")
-- ============================================================
local function doDash()
	if not dashAvailable then return end
	if isCCed()           then return end

	dashAvailable = false
	task.delay(CONFIG.DASH_COOLDOWN, function() dashAvailable = true end)

	Combat:FireServer({ action = "NormalDash" })

	-- Auto-sprint after dash
	if CONFIG.AUTO_SPRINT_AFTER_DASH then
		-- Small delay so the dash velocity finishes before sprint speed kicks in
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
-- EVASIVE DASH  (E key while SoftKnockdown active)
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
-- Roblox's native shift lock is bound to Left Shift by default.
-- To use this custom shift lock:
--   1. In Studio → StarterPlayer → EnableMouseLockOption = false
--   2. This script handles the lock via RotationType.
-- ============================================================
if CONFIG.SHIFT_LOCK_KEYBIND then
	local UserGameSettings = UserSettings():GetService("UserGameSettings")

	-- Explicitly disable native shift lock so Left Shift doesn't interfere
	-- (developers should also set StarterPlayer.EnableMouseLockOption = false in Studio)
	pcall(function()
		UserGameSettings.RotationType = Enum.RotationType.MovementRelative
	end)

	UIS.InputBegan:Connect(function(input, processed)
		if processed then return end
		if input.KeyCode ~= CONFIG.SHIFT_LOCK_KEYBIND then return end

		local ok = pcall(function()
			if UserGameSettings.RotationType == Enum.RotationType.CameraRelative then
				UserGameSettings.RotationType = Enum.RotationType.MovementRelative
				UIS.MouseBehavior = Enum.MouseBehavior.Default
				humanoid.CameraOffset = Vector3.zero
				mouse.Icon = ""
			else
				UserGameSettings.RotationType = Enum.RotationType.CameraRelative
				UIS.MouseBehavior = Enum.MouseBehavior.LockCenter
				humanoid.CameraOffset = CONFIG.SHIFT_LOCK_OFFSET
				mouse.Icon = "rbxassetid://10213989924"
			end
		end)
	end)
end

-- ============================================================
-- CHARACTER FEEDBACK reactions  (dash visual confirmation)
-- ============================================================
if CharacterFeedback then
	CharacterFeedback.OnClientEvent:Connect(function(data)
		if not data then return end
		-- Evasive dash confirmed by server → reset local cooldown is already done above
		-- (we used a fixed client-side timer that mirrors the server CD)
	end)
end

-- ============================================================
-- DEATH / RESPAWN
-- ============================================================
player.CharacterAdded:Connect(function()
	isSprinting      = false
	dashAvailable    = true
	evasiveAvailable = true
	if sprintHeartbeat then sprintHeartbeat:Disconnect(); sprintHeartbeat=nil end
end)

-- ============================================================
-- PUBLIC API (expose to other scripts if needed)
-- ============================================================
_G.WuxiaMovement = {
	IsSprinting    = function() return isSprinting end,
	StartSprint    = startSprint,
	StopSprint     = stopSprint,
	DashAvailable  = function() return dashAvailable end,
	EvasiveAvailable = function() return evasiveAvailable end,
}