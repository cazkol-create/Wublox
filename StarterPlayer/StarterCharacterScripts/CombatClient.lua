-- @ScriptType: LocalScript
-- ============================================================
--  CombatClient.lua  |  LocalScript
--  Location: StarterCharacterScripts
--  (StarterCharacterScripts re-runs on every respawn automatically.)
--
--  ── What this script reads from the player ──────────────────
--    Plr_WeaponType  StringValue  e.g. "Sword"
--    Plr_StyleName   StringValue  e.g. "Default" | "Flowing" | "Storm"
--
--  ── Animation folder naming convention ──────────────────────
--    Style "Default" → looks for "Sword Animations" (the folder you already have)
--    Style "Flowing" → looks for "Sword Animations Flowing" first,
--                      then falls back to "Sword Animations"
--    Style "Storm"   → looks for "Sword Animations Storm" first, fallback
--
--    So adding a new style = create a new folder, add animations, done.
--    The fallback means Default works immediately with your current layout.
--
--  ── Children this script needs ──────────────────────────────
--    "Sword Animations"/  Folder
--      M1, M2, M3, Heavy, Block, Idle  (Animation objects)
--    Swing                Sound  (has a PitchShiftSoundEffect child)
--
--  ── ReplicatedStorage needed ────────────────────────────────
--    Modules/CombatData    ModuleScript
--    Combat                RemoteEvent
--    CombatFeedback        RemoteEvent
-- ============================================================

local CAS     = game:GetService("ContextActionService")
local Debris  = game:GetService("Debris")
local Players = game:GetService("Players")
local RS      = game:GetService("ReplicatedStorage")

local player    = Players.LocalPlayer
local character = script.Parent
local humanoid  = character:WaitForChild("Humanoid")
local animator  = humanoid:WaitForChild("Animator")

local CombatData = require(RS.Modules.CombatData)
local Combat     = RS:WaitForChild("Combat")
local CombatFB   = RS:WaitForChild("CombatFeedback")

local swingSound = script:WaitForChild("Swing")

-- ============================================================
-- ANIMATION TRACK MANAGEMENT
-- Tracks are stored in `active` and swapped out cleanly when
-- the player's weapon type or style changes mid-session.
-- ============================================================
local active = {}   -- { M1, M2, M3, Heavy, Block, Idle }

local function loadAnimFolder(weaponType, styleName)
	-- Try the style-specific folder first, then the base folder.
	local specificName = weaponType .. " Animations " .. styleName
	local baseName     = weaponType .. " Animations"
	local folder = script:FindFirstChild(specificName)
		or  script:FindFirstChild(baseName)

	if not folder then
		warn("[CombatClient] No animation folder found for:", weaponType, styleName,
			"— expected a folder named '" .. specificName .. "' or '" .. baseName .. "'")
		return nil
	end
	return folder
end

local function reloadTracks(weaponType, styleName)
	-- Stop and clean up whatever tracks are currently loaded.
	for _, track in pairs(active) do
		if track.IsPlaying then track:Stop(0) end
		track:Destroy()
	end
	active = {}

	local folder = loadAnimFolder(weaponType, styleName)
	if not folder then return end

	-- Load every expected track. If one is missing we warn but don't crash —
	-- the rest of the style still works.
	local names = { "M1", "M2", "M3", "Heavy", "Block", "Idle" }
	for _, name in ipairs(names) do
		local anim = folder:FindFirstChild(name)
		if anim then
			active[name] = animator:LoadAnimation(anim)
		else
			warn("[CombatClient] Missing animation:", name, "in folder:", folder.Name)
		end
	end
end

-- Watch the player's style StringValues and reload animations whenever
-- either changes. This supports in-game style switching cleanly.
local function watchStyleValues()
	local wtVal = player:WaitForChild("Plr_WeaponType", 6)
	local snVal = player:WaitForChild("Plr_StyleName",  6)

	local function doLoad()
		local wt = wtVal and wtVal.Value ~= "" and wtVal.Value or "Sword"
		local sn = snVal and snVal.Value ~= "" and snVal.Value or "Default"
		reloadTracks(wt, sn)
	end

	doLoad()  -- load immediately on spawn

	if wtVal then wtVal.Changed:Connect(doLoad) end
	if snVal then snVal.Changed:Connect(doLoad) end
end

watchStyleValues()

-- ============================================================
-- CLIENT-SIDE TIMING CONSTANTS
-- These are loaded from CombatData per style. They control LOCAL
-- cooldowns and combo reset — purely for client responsiveness.
-- The server independently validates with its own rate gates.
-- ============================================================
local timing        -- set below, updated on style changes

local function refreshTiming()
	local wt = player:FindFirstChild("Plr_WeaponType")
	local sn = player:FindFirstChild("Plr_StyleName")
	local wtv = wt and wt.Value or "Sword"
	local snv = sn and sn.Value or "Default"
	timing = CombatData.GetTiming(wtv, snv)
end

refreshTiming()

do
	local wt = player:FindFirstChild("Plr_WeaponType")
	local sn = player:FindFirstChild("Plr_StyleName")
	if wt then wt.Changed:Connect(refreshTiming) end
	if sn then sn.Changed:Connect(refreshTiming) end
end

-- ============================================================
-- COMBAT STATE
-- ============================================================
local combo        = 1
local m1Cooldown   = false
local lastCooldown = false
local heavyCooldown= false
local isBlocking   = false

-- comboResetTask: after each M1 press, we schedule a reset.
-- If the player presses again before it fires, we cancel and reschedule.
-- This prevents "stored" combos — you can't pause mid-chain and then
-- continue from where you left off after several seconds.
local comboResetTask = nil

local function scheduleComboReset()
	if comboResetTask then task.cancel(comboResetTask) end
	comboResetTask = task.delay(timing.comboReset, function()
		combo = 1
		comboResetTask = nil
	end)
end

local function cancelComboReset()
	if comboResetTask then task.cancel(comboResetTask); comboResetTask = nil end
end

-- ── Input Lock (the simultaneous-press fix) ─────────────────
-- When any combat action fires, we set inputLocked for a very
-- short window. If two keys are pressed in the same frame (e.g.
-- Q + M1), the second one sees inputLocked = true and silently
-- drops. 0.12 seconds is imperceptible to a human but longer
-- than the time between two simultaneous key-down events.
local inputLocked     = false
local INPUT_LOCK_TIME = 0.12

local function lockInput()
	inputLocked = true
	task.delay(INPUT_LOCK_TIME, function() inputLocked = false end)
end

-- ── Animation Active Window ──────────────────────────────────
-- While an attack animation is in its commitment window, blocking
-- is prevented. This is separate from inputLocked (which prevents
-- simultaneous presses) — this enforces "you committed to an attack,
-- you can't immediately switch to guarding."
local attackCommitted = false

local function isStunned()
	return character:FindFirstChild("Stunned") ~= nil
end

-- When stunned: stop all animations, release block, reset combo.
-- The server already knows about the stun — we don't fire BlockEnd
-- here because CombatState.ClearBlockOnStun handles the server side.
character.ChildAdded:Connect(function(child)
	if child.Name ~= "Stunned" then return end
	for _, t in pairs(active) do
		if t.IsPlaying then t:Stop(0.1) end
	end
	isBlocking    = false
	attackCommitted = false
	combo         = 1
	cancelComboReset()
end)

-- ============================================================
-- ACTION NAME CONSTANTS  (used by CAS and the rebind API)
-- ============================================================
local A_M1    = "Combat_M1"
local A_HEAVY = "Combat_Heavy"
local A_BLOCK = "Combat_Block"

-- ============================================================
-- KEYBIND TABLE
-- Stored as arrays so CAS:BindAction receives them via table.unpack.
-- Changed by the settings panel through _G.WuxiaClient.RebindCombatAction.
-- ============================================================
local activeBinds = {
	[A_M1]    = { Enum.UserInputType.MouseButton1 },
	[A_HEAVY] = { Enum.KeyCode.Q },
	[A_BLOCK] = { Enum.KeyCode.F },
	-- MouseButton2 was removed per dev note: interfered with camera rotation.
}

-- ============================================================
-- HANDLERS
-- Each function is named so the rebind API can re-register the
-- same function under a different key without redefining it.
-- ============================================================

local rng = Random.new()

local function handleM1(_, inputState, _)
	if inputState ~= Enum.UserInputState.Begin then
		return Enum.ContextActionResult.Pass
	end
	if isStunned()  then return Enum.ContextActionResult.Sink end
	if isBlocking   then return Enum.ContextActionResult.Sink end
	if m1Cooldown or lastCooldown then return Enum.ContextActionResult.Sink end
	if inputLocked  then return Enum.ContextActionResult.Sink end

	-- Lock input and mark attack as committed.
	lockInput()
	attackCommitted = true
	cancelComboReset()

	m1Cooldown = true
	task.delay(timing.m1CD, function() m1Cooldown = false end)

	-- Slight pitch variation on the swing sound for feel.
	local ps = swingSound:FindFirstChildOfClass("PitchShiftSoundEffect")
	if ps then ps.Octave = rng:NextNumber(0.93, 1.07) end
	swingSound:Play()

	if combo == 3 then
		if active.M3 then active.M3:Play() end
		Combat:FireServer({ action = "Last" })
		lastCooldown = true
		task.delay(timing.lastRecovery, function()
			lastCooldown    = false
			attackCommitted = false
		end)
		task.delay(0.05, function() combo = 1 end)

	elseif combo == 2 then
		if active.M2 then active.M2:Play() end
		Combat:FireServer({ action = "Regular" })
		combo += 1
		scheduleComboReset()
		task.delay(timing.m1CD, function() attackCommitted = false end)

	else
		if active.M1 then active.M1:Play() end
		Combat:FireServer({ action = "Regular" })
		combo += 1
		scheduleComboReset()
		task.delay(timing.m1CD, function() attackCommitted = false end)
	end

	return Enum.ContextActionResult.Sink
end

local function handleHeavy(_, inputState, _)
	if inputState ~= Enum.UserInputState.Begin then
		return Enum.ContextActionResult.Pass
	end
	if isStunned()  then return Enum.ContextActionResult.Sink end
	if isBlocking   then return Enum.ContextActionResult.Sink end
	if heavyCooldown or m1Cooldown or lastCooldown then
		return Enum.ContextActionResult.Sink
	end
	if inputLocked  then return Enum.ContextActionResult.Sink end

	lockInput()
	attackCommitted = true

	heavyCooldown = true
	task.delay(timing.heavyCD, function() heavyCooldown = false end)

	if active.Heavy then active.Heavy:Play() end
	swingSound:Play()
	Combat:FireServer({ action = "Heavy" })

	task.delay(timing.heavyCD * 0.5, function() attackCommitted = false end)

	return Enum.ContextActionResult.Sink
end

-- Block is hold-to-guard. The first 0.35 s (PARRY_WINDOW) the server
-- treats input as a parry attempt. After that it degrades to regular
-- block — the client doesn't need to track this distinction locally
-- because the server manages it. The client just plays the animation.
local function handleBlock(_, inputState, _)
	if inputState == Enum.UserInputState.Begin then
		if isStunned() then return Enum.ContextActionResult.Sink end
		if isBlocking  then return Enum.ContextActionResult.Sink end
		-- Prevent blocking during the attack commitment window.
		if attackCommitted then return Enum.ContextActionResult.Sink end
		if inputLocked then return Enum.ContextActionResult.Sink end

		isBlocking = true
		if active.Block then active.Block:Play() end
		Combat:FireServer({ action = "BlockStart" })

	elseif inputState == Enum.UserInputState.End then
		if not isBlocking then return Enum.ContextActionResult.Sink end
		isBlocking = false
		if active.Block then active.Block:Stop(0.15) end
		Combat:FireServer({ action = "BlockEnd" })
	end

	return Enum.ContextActionResult.Sink
end

local handlers = {
	[A_M1]    = handleM1,
	[A_HEAVY] = handleHeavy,
	[A_BLOCK] = handleBlock,
}

local function bindAll()
	for name, keys in pairs(activeBinds) do
		CAS:BindAction(name, handlers[name], false, table.unpack(keys))
	end
end

bindAll()

-- ============================================================
-- COMBAT FEEDBACK — Server → Client
-- ============================================================
CombatFB.OnClientEvent:Connect(function(data)
	if not data then return end
	
	if data.type == "DebugHitbox" then
		-- Render the hitbox as a LOCAL Part only this client can see.
		-- The server sent us the CFrame and size — we create the Part here.
		-- No other client's server creates this Part, so it is invisible to them.
		local v = Instance.new("Part")
		v.Anchored    = true
		v.CanCollide  = false
		v.CanTouch    = false
		v.CanQuery    = false
		v.Material    = Enum.Material.Neon
		v.Transparency= 0.65
		v.BrickColor  = BrickColor.Red()
		v.Size        = data.size
		v.CFrame      = data.cf
		v.Parent      = workspace
		Debris:AddItem(v, 0.3)

	elseif data.type == "ParrySuccess" then
		-- You parried successfully. Add a visual flash here when ready.
		-- e.g.: trigger a white particle burst, play a camera jolt.

	elseif data.type == "ParriedByOpponent" then
		-- Your attack was parried. Add a screen-edge flash or shake here.

	elseif data.type == "BlockHit" then
		-- Your guard absorbed damage. Optional guard-flash VFX.

	elseif data.type == "GuardBroken" then
		-- Your guard was broken. Force-release block state on the client.
		-- The server has already cleared blockState — this just keeps the
		-- client visuals in sync so the Block animation stops playing.
		if isBlocking then
			isBlocking = false
			if active.Block then active.Block:Stop(0.1) end
		end
		-- Add a screen-shake or red flash here to signal the guard break.

	elseif data.type == "ParryWhiff" then
		-- Your parry attempt missed. Show a visual punishment indicator.
		-- e.g.: brief red vignette, small camera shake.
	end
end)

-- ============================================================
-- PUBLIC API  (_G.WuxiaClient)
-- Used by SettingsClient to rebind keys and read current binds.
-- ============================================================
_G.WuxiaClient                     = _G.WuxiaClient or {}
_G.WuxiaClient.CombatActions       = { M1 = A_M1, Heavy = A_HEAVY, Block = A_BLOCK }

_G.WuxiaClient.RebindCombatAction  = function(actionName, ...)
	local newKeys = { ... }
	if #newKeys == 0 or not handlers[actionName] then return end
	activeBinds[actionName] = newKeys
	CAS:UnbindAction(actionName)
	CAS:BindAction(actionName, handlers[actionName], false, table.unpack(newKeys))
end

_G.WuxiaClient.GetCombatBinds      = function()
	local copy = {}
	for k, v in pairs(activeBinds) do copy[k] = v end
	return copy
end-- ============================================================
--  CombatClient.lua  |  LocalScript
--  Location: StarterCharacterScripts
--  (StarterCharacterScripts re-runs on every respawn automatically.)
--
--  ── What this script reads from the player ──────────────────
--    Plr_WeaponType  StringValue  e.g. "Sword"
--    Plr_StyleName   StringValue  e.g. "Default" | "Flowing" | "Storm"
--
--  ── Animation folder naming convention ──────────────────────
--    Style "Default" → looks for "Sword Animations" (the folder you already have)
--    Style "Flowing" → looks for "Sword Animations Flowing" first,
--                      then falls back to "Sword Animations"
--    Style "Storm"   → looks for "Sword Animations Storm" first, fallback
--
--    So adding a new style = create a new folder, add animations, done.
--    The fallback means Default works immediately with your current layout.
--
--  ── Children this script needs ──────────────────────────────
--    "Sword Animations"/  Folder
--      M1, M2, M3, Heavy, Block, Idle  (Animation objects)
--    Swing                Sound  (has a PitchShiftSoundEffect child)
--
--  ── ReplicatedStorage needed ────────────────────────────────
--    Modules/CombatData    ModuleScript
--    Combat                RemoteEvent
--    CombatFeedback        RemoteEvent
-- ============================================================

local CAS     = game:GetService("ContextActionService")
local Debris  = game:GetService("Debris")
local Players = game:GetService("Players")
local RS      = game:GetService("ReplicatedStorage")

local player    = Players.LocalPlayer
local character = script.Parent
local humanoid  = character:WaitForChild("Humanoid")
local animator  = humanoid:WaitForChild("Animator")

local CombatData = require(RS.Modules.CombatData)
local Combat     = RS:WaitForChild("Combat")
local CombatFB   = RS:WaitForChild("CombatFeedback")

local swingSound = script:WaitForChild("Swing")

-- ============================================================
-- ANIMATION TRACK MANAGEMENT
-- Tracks are stored in `active` and swapped out cleanly when
-- the player's weapon type or style changes mid-session.
-- ============================================================
local active = {}   -- { M1, M2, M3, Heavy, Block, Idle }

local function loadAnimFolder(weaponType, styleName)
	-- Try the style-specific folder first, then the base folder.
	local specificName = weaponType .. " Animations " .. styleName
	local baseName     = weaponType .. " Animations"
	local folder = script:FindFirstChild(specificName)
		or  script:FindFirstChild(baseName)

	if not folder then
		warn("[CombatClient] No animation folder found for:", weaponType, styleName,
			"— expected a folder named '" .. specificName .. "' or '" .. baseName .. "'")
		return nil
	end
	return folder
end

local function reloadTracks(weaponType, styleName)
	-- Stop and clean up whatever tracks are currently loaded.
	for _, track in pairs(active) do
		if track.IsPlaying then track:Stop(0) end
		track:Destroy()
	end
	active = {}

	local folder = loadAnimFolder(weaponType, styleName)
	if not folder then return end

	-- Load every expected track. If one is missing we warn but don't crash —
	-- the rest of the style still works.
	local names = { "M1", "M2", "M3", "Heavy", "Block", "Idle" }
	for _, name in ipairs(names) do
		local anim = folder:FindFirstChild(name)
		if anim then
			active[name] = animator:LoadAnimation(anim)
		else
			warn("[CombatClient] Missing animation:", name, "in folder:", folder.Name)
		end
	end
end

-- Watch the player's style StringValues and reload animations whenever
-- either changes. This supports in-game style switching cleanly.
local function watchStyleValues()
	local wtVal = player:WaitForChild("Plr_WeaponType", 6)
	local snVal = player:WaitForChild("Plr_StyleName",  6)

	local function doLoad()
		local wt = wtVal and wtVal.Value ~= "" and wtVal.Value or "Sword"
		local sn = snVal and snVal.Value ~= "" and snVal.Value or "Default"
		reloadTracks(wt, sn)
	end

	doLoad()  -- load immediately on spawn

	if wtVal then wtVal.Changed:Connect(doLoad) end
	if snVal then snVal.Changed:Connect(doLoad) end
end

watchStyleValues()

-- ============================================================
-- CLIENT-SIDE TIMING CONSTANTS
-- These are loaded from CombatData per style. They control LOCAL
-- cooldowns and combo reset — purely for client responsiveness.
-- The server independently validates with its own rate gates.
-- ============================================================
local timing        -- set below, updated on style changes

local function refreshTiming()
	local wt = player:FindFirstChild("Plr_WeaponType")
	local sn = player:FindFirstChild("Plr_StyleName")
	local wtv = wt and wt.Value or "Sword"
	local snv = sn and sn.Value or "Default"
	timing = CombatData.GetTiming(wtv, snv)
end

refreshTiming()

do
	local wt = player:FindFirstChild("Plr_WeaponType")
	local sn = player:FindFirstChild("Plr_StyleName")
	if wt then wt.Changed:Connect(refreshTiming) end
	if sn then sn.Changed:Connect(refreshTiming) end
end

-- ============================================================
-- COMBAT STATE
-- ============================================================
local combo        = 1
local m1Cooldown   = false
local lastCooldown = false
local heavyCooldown= false
local isBlocking   = false

-- comboResetTask: after each M1 press, we schedule a reset.
-- If the player presses again before it fires, we cancel and reschedule.
-- This prevents "stored" combos — you can't pause mid-chain and then
-- continue from where you left off after several seconds.
local comboResetTask = nil

local function scheduleComboReset()
	if comboResetTask then task.cancel(comboResetTask) end
	comboResetTask = task.delay(timing.comboReset, function()
		combo = 1
		comboResetTask = nil
	end)
end

local function cancelComboReset()
	if comboResetTask then task.cancel(comboResetTask); comboResetTask = nil end
end

-- ── Input Lock (the simultaneous-press fix) ─────────────────
-- When any combat action fires, we set inputLocked for a very
-- short window. If two keys are pressed in the same frame (e.g.
-- Q + M1), the second one sees inputLocked = true and silently
-- drops. 0.12 seconds is imperceptible to a human but longer
-- than the time between two simultaneous key-down events.
local inputLocked     = false
local INPUT_LOCK_TIME = 0.12

local function lockInput()
	inputLocked = true
	task.delay(INPUT_LOCK_TIME, function() inputLocked = false end)
end

-- ── Animation Active Window ──────────────────────────────────
-- While an attack animation is in its commitment window, blocking
-- is prevented. This is separate from inputLocked (which prevents
-- simultaneous presses) — this enforces "you committed to an attack,
-- you can't immediately switch to guarding."
local attackCommitted = false

local function isStunned()
	return character:FindFirstChild("Stunned") ~= nil
end

-- When stunned: stop all animations, release block, reset combo.
-- The server already knows about the stun — we don't fire BlockEnd
-- here because CombatState.ClearBlockOnStun handles the server side.
character.ChildAdded:Connect(function(child)
	if child.Name ~= "Stunned" then return end
	for _, t in pairs(active) do
		if t.IsPlaying then t:Stop(0.1) end
	end
	isBlocking    = false
	attackCommitted = false
	combo         = 1
	cancelComboReset()
end)

-- ============================================================
-- ACTION NAME CONSTANTS  (used by CAS and the rebind API)
-- ============================================================
local A_M1    = "Combat_M1"
local A_HEAVY = "Combat_Heavy"
local A_BLOCK = "Combat_Block"

-- ============================================================
-- KEYBIND TABLE
-- Stored as arrays so CAS:BindAction receives them via table.unpack.
-- Changed by the settings panel through _G.WuxiaClient.RebindCombatAction.
-- ============================================================
local activeBinds = {
	[A_M1]    = { Enum.UserInputType.MouseButton1 },
	[A_HEAVY] = { Enum.KeyCode.Q },
	[A_BLOCK] = { Enum.KeyCode.F },
	-- MouseButton2 was removed per dev note: interfered with camera rotation.
}

-- ============================================================
-- HANDLERS
-- Each function is named so the rebind API can re-register the
-- same function under a different key without redefining it.
-- ============================================================

local rng = Random.new()

local function handleM1(_, inputState, _)
	if inputState ~= Enum.UserInputState.Begin then
		return Enum.ContextActionResult.Pass
	end
	if isStunned()  then return Enum.ContextActionResult.Sink end
	if isBlocking   then return Enum.ContextActionResult.Sink end
	if m1Cooldown or lastCooldown then return Enum.ContextActionResult.Sink end
	if inputLocked  then return Enum.ContextActionResult.Sink end

	-- Lock input and mark attack as committed.
	lockInput()
	attackCommitted = true
	cancelComboReset()

	m1Cooldown = true
	task.delay(timing.m1CD, function() m1Cooldown = false end)

	-- Slight pitch variation on the swing sound for feel.
	local ps = swingSound:FindFirstChildOfClass("PitchShiftSoundEffect")
	if ps then ps.Octave = rng:NextNumber(0.93, 1.07) end
	swingSound:Play()

	if combo == 3 then
		if active.M3 then active.M3:Play() end
		Combat:FireServer({ action = "Last" })
		lastCooldown = true
		task.delay(timing.lastRecovery, function()
			lastCooldown    = false
			attackCommitted = false
		end)
		task.delay(0.05, function() combo = 1 end)

	elseif combo == 2 then
		if active.M2 then active.M2:Play() end
		Combat:FireServer({ action = "Regular" })
		combo += 1
		scheduleComboReset()
		task.delay(timing.m1CD, function() attackCommitted = false end)

	else
		if active.M1 then active.M1:Play() end
		Combat:FireServer({ action = "Regular" })
		combo += 1
		scheduleComboReset()
		task.delay(timing.m1CD, function() attackCommitted = false end)
	end

	return Enum.ContextActionResult.Sink
end

local function handleHeavy(_, inputState, _)
	if inputState ~= Enum.UserInputState.Begin then
		return Enum.ContextActionResult.Pass
	end
	if isStunned()  then return Enum.ContextActionResult.Sink end
	if isBlocking   then return Enum.ContextActionResult.Sink end
	if heavyCooldown or m1Cooldown or lastCooldown then
		return Enum.ContextActionResult.Sink
	end
	if inputLocked  then return Enum.ContextActionResult.Sink end

	lockInput()
	attackCommitted = true

	heavyCooldown = true
	task.delay(timing.heavyCD, function() heavyCooldown = false end)

	if active.Heavy then active.Heavy:Play() end
	swingSound:Play()
	Combat:FireServer({ action = "Heavy" })

	task.delay(timing.heavyCD * 0.5, function() attackCommitted = false end)

	return Enum.ContextActionResult.Sink
end

-- Block is hold-to-guard. The first 0.35 s (PARRY_WINDOW) the server
-- treats input as a parry attempt. After that it degrades to regular
-- block — the client doesn't need to track this distinction locally
-- because the server manages it. The client just plays the animation.
local function handleBlock(_, inputState, _)
	if inputState == Enum.UserInputState.Begin then
		if isStunned() then return Enum.ContextActionResult.Sink end
		if isBlocking  then return Enum.ContextActionResult.Sink end
		-- Prevent blocking during the attack commitment window.
		if attackCommitted then return Enum.ContextActionResult.Sink end
		if inputLocked then return Enum.ContextActionResult.Sink end

		isBlocking = true
		if active.Block then active.Block:Play() end
		Combat:FireServer({ action = "BlockStart" })

	elseif inputState == Enum.UserInputState.End then
		if not isBlocking then return Enum.ContextActionResult.Sink end
		isBlocking = false
		if active.Block then active.Block:Stop(0.15) end
		Combat:FireServer({ action = "BlockEnd" })
	end

	return Enum.ContextActionResult.Sink
end

local handlers = {
	[A_M1]    = handleM1,
	[A_HEAVY] = handleHeavy,
	[A_BLOCK] = handleBlock,
}

local function bindAll()
	for name, keys in pairs(activeBinds) do
		CAS:BindAction(name, handlers[name], false, table.unpack(keys))
	end
end

bindAll()

-- ============================================================
-- COMBAT FEEDBACK — Server → Client
-- ============================================================
CombatFB.OnClientEvent:Connect(function(data)
	if not data then return end

	if data.type == "DebugHitbox" then
		-- Render the hitbox as a LOCAL Part only this client can see.
		-- The server sent us the CFrame and size — we create the Part here.
		-- No other client's server creates this Part, so it is invisible to them.
		local v = Instance.new("Part")
		v.Anchored    = true
		v.CanCollide  = false
		v.CanTouch    = false
		v.CanQuery    = false
		v.Material    = Enum.Material.Neon
		v.Transparency= 0.65
		v.BrickColor  = BrickColor.Red()
		v.Size        = data.size
		v.CFrame      = data.cf
		v.Parent      = workspace
		Debris:AddItem(v, 0.3)

	elseif data.type == "ParrySuccess" then
		-- You parried successfully. Add a visual flash here when ready.
		-- e.g.: trigger a white particle burst, play a camera jolt.

	elseif data.type == "ParriedByOpponent" then
		-- Your attack was parried. Add a screen-edge flash or shake here.

	elseif data.type == "BlockHit" then
		-- Your guard absorbed damage. Optional guard-flash VFX.

	elseif data.type == "GuardBroken" then
		-- Your guard was broken. Force-release block state on the client.
		-- The server has already cleared blockState — this just keeps the
		-- client visuals in sync so the Block animation stops playing.
		if isBlocking then
			isBlocking = false
			if active.Block then active.Block:Stop(0.1) end
		end
		-- Add a screen-shake or red flash here to signal the guard break.

	elseif data.type == "ParryWhiff" then
		-- Your parry attempt missed. Show a visual punishment indicator.
		-- e.g.: brief red vignette, small camera shake.
	end
end)

-- ============================================================
-- PUBLIC API  (_G.WuxiaClient)
-- Used by SettingsClient to rebind keys and read current binds.
-- ============================================================
_G.WuxiaClient                     = _G.WuxiaClient or {}
_G.WuxiaClient.CombatActions       = { M1 = A_M1, Heavy = A_HEAVY, Block = A_BLOCK }

_G.WuxiaClient.RebindCombatAction  = function(actionName, ...)
	local newKeys = { ... }
	if #newKeys == 0 or not handlers[actionName] then return end
	activeBinds[actionName] = newKeys
	CAS:UnbindAction(actionName)
	CAS:BindAction(actionName, handlers[actionName], false, table.unpack(newKeys))
end

_G.WuxiaClient.GetCombatBinds      = function()
	local copy = {}
	for k, v in pairs(activeBinds) do copy[k] = v end
	return copy
end-- ============================================================
--  CombatClient.lua  |  LocalScript
--  Location: StarterCharacterScripts
--  (StarterCharacterScripts re-runs on every respawn automatically.)
--
--  ── What this script reads from the player ──────────────────
--    Plr_WeaponType  StringValue  e.g. "Sword"
--    Plr_StyleName   StringValue  e.g. "Default" | "Flowing" | "Storm"
--
--  ── Animation folder naming convention ──────────────────────
--    Style "Default" → looks for "Sword Animations" (the folder you already have)
--    Style "Flowing" → looks for "Sword Animations Flowing" first,
--                      then falls back to "Sword Animations"
--    Style "Storm"   → looks for "Sword Animations Storm" first, fallback
--
--    So adding a new style = create a new folder, add animations, done.
--    The fallback means Default works immediately with your current layout.
--
--  ── Children this script needs ──────────────────────────────
--    "Sword Animations"/  Folder
--      M1, M2, M3, Heavy, Block, Idle  (Animation objects)
--    Swing                Sound  (has a PitchShiftSoundEffect child)
--
--  ── ReplicatedStorage needed ────────────────────────────────
--    Modules/CombatData    ModuleScript
--    Combat                RemoteEvent
--    CombatFeedback        RemoteEvent
-- ============================================================

local CAS     = game:GetService("ContextActionService")
local Debris  = game:GetService("Debris")
local Players = game:GetService("Players")
local RS      = game:GetService("ReplicatedStorage")

local player    = Players.LocalPlayer
local character = script.Parent
local humanoid  = character:WaitForChild("Humanoid")
local animator  = humanoid:WaitForChild("Animator")

local CombatData = require(RS.Modules.CombatData)
local Combat     = RS:WaitForChild("Combat")
local CombatFB   = RS:WaitForChild("CombatFeedback")

local swingSound = script:WaitForChild("Swing")

-- ============================================================
-- ANIMATION TRACK MANAGEMENT
-- Tracks are stored in `active` and swapped out cleanly when
-- the player's weapon type or style changes mid-session.
-- ============================================================
local active = {}   -- { M1, M2, M3, Heavy, Block, Idle }

local function loadAnimFolder(weaponType, styleName)
	-- Try the style-specific folder first, then the base folder.
	local specificName = weaponType .. " Animations " .. styleName
	local baseName     = weaponType .. " Animations"
	local folder = script:FindFirstChild(specificName)
		or  script:FindFirstChild(baseName)

	if not folder then
		warn("[CombatClient] No animation folder found for:", weaponType, styleName,
			"— expected a folder named '" .. specificName .. "' or '" .. baseName .. "'")
		return nil
	end
	return folder
end

local function reloadTracks(weaponType, styleName)
	-- Stop and clean up whatever tracks are currently loaded.
	for _, track in pairs(active) do
		if track.IsPlaying then track:Stop(0) end
		track:Destroy()
	end
	active = {}

	local folder = loadAnimFolder(weaponType, styleName)
	if not folder then return end

	-- Load every expected track. If one is missing we warn but don't crash —
	-- the rest of the style still works.
	local names = { "M1", "M2", "M3", "Heavy", "Block", "Idle" }
	for _, name in ipairs(names) do
		local anim = folder:FindFirstChild(name)
		if anim then
			active[name] = animator:LoadAnimation(anim)
		else
			warn("[CombatClient] Missing animation:", name, "in folder:", folder.Name)
		end
	end
end

-- Watch the player's style StringValues and reload animations whenever
-- either changes. This supports in-game style switching cleanly.
local function watchStyleValues()
	local wtVal = player:WaitForChild("Plr_WeaponType", 6)
	local snVal = player:WaitForChild("Plr_StyleName",  6)

	local function doLoad()
		local wt = wtVal and wtVal.Value ~= "" and wtVal.Value or "Sword"
		local sn = snVal and snVal.Value ~= "" and snVal.Value or "Default"
		reloadTracks(wt, sn)
	end

	doLoad()  -- load immediately on spawn

	if wtVal then wtVal.Changed:Connect(doLoad) end
	if snVal then snVal.Changed:Connect(doLoad) end
end

watchStyleValues()

-- ============================================================
-- CLIENT-SIDE TIMING CONSTANTS
-- These are loaded from CombatData per style. They control LOCAL
-- cooldowns and combo reset — purely for client responsiveness.
-- The server independently validates with its own rate gates.
-- ============================================================
local timing        -- set below, updated on style changes

local function refreshTiming()
	local wt = player:FindFirstChild("Plr_WeaponType")
	local sn = player:FindFirstChild("Plr_StyleName")
	local wtv = wt and wt.Value or "Sword"
	local snv = sn and sn.Value or "Default"
	timing = CombatData.GetTiming(wtv, snv)
end

refreshTiming()

do
	local wt = player:FindFirstChild("Plr_WeaponType")
	local sn = player:FindFirstChild("Plr_StyleName")
	if wt then wt.Changed:Connect(refreshTiming) end
	if sn then sn.Changed:Connect(refreshTiming) end
end

-- ============================================================
-- COMBAT STATE
-- ============================================================
local combo        = 1
local m1Cooldown   = false
local lastCooldown = false
local heavyCooldown= false
local isBlocking   = false

-- comboResetTask: after each M1 press, we schedule a reset.
-- If the player presses again before it fires, we cancel and reschedule.
-- This prevents "stored" combos — you can't pause mid-chain and then
-- continue from where you left off after several seconds.
local comboResetTask = nil

local function scheduleComboReset()
	if comboResetTask then task.cancel(comboResetTask) end
	comboResetTask = task.delay(timing.comboReset, function()
		combo = 1
		comboResetTask = nil
	end)
end

local function cancelComboReset()
	if comboResetTask then task.cancel(comboResetTask); comboResetTask = nil end
end

-- ── Input Lock (the simultaneous-press fix) ─────────────────
-- When any combat action fires, we set inputLocked for a very
-- short window. If two keys are pressed in the same frame (e.g.
-- Q + M1), the second one sees inputLocked = true and silently
-- drops. 0.12 seconds is imperceptible to a human but longer
-- than the time between two simultaneous key-down events.
local inputLocked     = false
local INPUT_LOCK_TIME = 0.12

local function lockInput()
	inputLocked = true
	task.delay(INPUT_LOCK_TIME, function() inputLocked = false end)
end

-- ── Animation Active Window ──────────────────────────────────
-- While an attack animation is in its commitment window, blocking
-- is prevented. This is separate from inputLocked (which prevents
-- simultaneous presses) — this enforces "you committed to an attack,
-- you can't immediately switch to guarding."
local attackCommitted = false

local function isStunned()
	return character:FindFirstChild("Stunned") ~= nil
end

-- When stunned: stop all animations, release block, reset combo.
-- The server already knows about the stun — we don't fire BlockEnd
-- here because CombatState.ClearBlockOnStun handles the server side.
character.ChildAdded:Connect(function(child)
	if child.Name ~= "Stunned" then return end
	for _, t in pairs(active) do
		if t.IsPlaying then t:Stop(0.1) end
	end
	isBlocking    = false
	attackCommitted = false
	combo         = 1
	cancelComboReset()
end)

-- ============================================================
-- ACTION NAME CONSTANTS  (used by CAS and the rebind API)
-- ============================================================
local A_M1    = "Combat_M1"
local A_HEAVY = "Combat_Heavy"
local A_BLOCK = "Combat_Block"

-- ============================================================
-- KEYBIND TABLE
-- Stored as arrays so CAS:BindAction receives them via table.unpack.
-- Changed by the settings panel through _G.WuxiaClient.RebindCombatAction.
-- ============================================================
local activeBinds = {
	[A_M1]    = { Enum.UserInputType.MouseButton1 },
	[A_HEAVY] = { Enum.KeyCode.Q },
	[A_BLOCK] = { Enum.KeyCode.F },
	-- MouseButton2 was removed per dev note: interfered with camera rotation.
}

-- ============================================================
-- HANDLERS
-- Each function is named so the rebind API can re-register the
-- same function under a different key without redefining it.
-- ============================================================

local rng = Random.new()

local function handleM1(_, inputState, _)
	if inputState ~= Enum.UserInputState.Begin then
		return Enum.ContextActionResult.Pass
	end
	if isStunned()  then return Enum.ContextActionResult.Sink end
	if isBlocking   then return Enum.ContextActionResult.Sink end
	if m1Cooldown or lastCooldown then return Enum.ContextActionResult.Sink end
	if inputLocked  then return Enum.ContextActionResult.Sink end

	-- Lock input and mark attack as committed.
	lockInput()
	attackCommitted = true
	cancelComboReset()

	m1Cooldown = true
	task.delay(timing.m1CD, function() m1Cooldown = false end)

	-- Slight pitch variation on the swing sound for feel.
	local ps = swingSound:FindFirstChildOfClass("PitchShiftSoundEffect")
	if ps then ps.Octave = rng:NextNumber(0.93, 1.07) end
	swingSound:Play()

	if combo == 3 then
		if active.M3 then active.M3:Play() end
		Combat:FireServer({ action = "Last" })
		lastCooldown = true
		task.delay(timing.lastRecovery, function()
			lastCooldown    = false
			attackCommitted = false
		end)
		task.delay(0.05, function() combo = 1 end)

	elseif combo == 2 then
		if active.M2 then active.M2:Play() end
		Combat:FireServer({ action = "Regular" })
		combo += 1
		scheduleComboReset()
		task.delay(timing.m1CD, function() attackCommitted = false end)

	else
		if active.M1 then active.M1:Play() end
		Combat:FireServer({ action = "Regular" })
		combo += 1
		scheduleComboReset()
		task.delay(timing.m1CD, function() attackCommitted = false end)
	end

	return Enum.ContextActionResult.Sink
end

local function handleHeavy(_, inputState, _)
	if inputState ~= Enum.UserInputState.Begin then
		return Enum.ContextActionResult.Pass
	end
	if isStunned()  then return Enum.ContextActionResult.Sink end
	if isBlocking   then return Enum.ContextActionResult.Sink end
	if heavyCooldown or m1Cooldown or lastCooldown then
		return Enum.ContextActionResult.Sink
	end
	if inputLocked  then return Enum.ContextActionResult.Sink end

	lockInput()
	attackCommitted = true

	heavyCooldown = true
	task.delay(timing.heavyCD, function() heavyCooldown = false end)

	if active.Heavy then active.Heavy:Play() end
	swingSound:Play()
	Combat:FireServer({ action = "Heavy" })

	task.delay(timing.heavyCD * 0.5, function() attackCommitted = false end)

	return Enum.ContextActionResult.Sink
end

-- Block is hold-to-guard. The first 0.35 s (PARRY_WINDOW) the server
-- treats input as a parry attempt. After that it degrades to regular
-- block — the client doesn't need to track this distinction locally
-- because the server manages it. The client just plays the animation.
local function handleBlock(_, inputState, _)
	if inputState == Enum.UserInputState.Begin then
		if isStunned() then return Enum.ContextActionResult.Sink end
		if isBlocking  then return Enum.ContextActionResult.Sink end
		-- Prevent blocking during the attack commitment window.
		if attackCommitted then return Enum.ContextActionResult.Sink end
		if inputLocked then return Enum.ContextActionResult.Sink end

		isBlocking = true
		if active.Block then active.Block:Play() end
		Combat:FireServer({ action = "BlockStart" })

	elseif inputState == Enum.UserInputState.End then
		if not isBlocking then return Enum.ContextActionResult.Sink end
		isBlocking = false
		if active.Block then active.Block:Stop(0.15) end
		Combat:FireServer({ action = "BlockEnd" })
	end

	return Enum.ContextActionResult.Sink
end

local handlers = {
	[A_M1]    = handleM1,
	[A_HEAVY] = handleHeavy,
	[A_BLOCK] = handleBlock,
}

local function bindAll()
	for name, keys in pairs(activeBinds) do
		CAS:BindAction(name, handlers[name], false, table.unpack(keys))
	end
end

bindAll()

-- ============================================================
-- COMBAT FEEDBACK — Server → Client
-- ============================================================
CombatFB.OnClientEvent:Connect(function(data)
	if not data then return end

	if data.type == "DebugHitbox" then
		-- Render the hitbox as a LOCAL Part only this client can see.
		-- The server sent us the CFrame and size — we create the Part here.
		-- No other client's server creates this Part, so it is invisible to them.
		local v = Instance.new("Part")
		v.Anchored    = true
		v.CanCollide  = false
		v.CanTouch    = false
		v.CanQuery    = false
		v.Material    = Enum.Material.Neon
		v.Transparency= 0.65
		v.BrickColor  = BrickColor.Red()
		v.Size        = data.size
		v.CFrame      = data.cf
		v.Parent      = workspace
		Debris:AddItem(v, 0.3)

	elseif data.type == "ParrySuccess" then
		-- You parried successfully. Add a visual flash here when ready.
		-- e.g.: trigger a white particle burst, play a camera jolt.

	elseif data.type == "ParriedByOpponent" then
		-- Your attack was parried. Add a screen-edge flash or shake here.

	elseif data.type == "BlockHit" then
		-- Your guard absorbed damage. Optional guard-flash VFX.

	elseif data.type == "GuardBroken" then
		-- Your guard was broken. Force-release block state on the client.
		-- The server has already cleared blockState — this just keeps the
		-- client visuals in sync so the Block animation stops playing.
		if isBlocking then
			isBlocking = false
			if active.Block then active.Block:Stop(0.1) end
		end
		-- Add a screen-shake or red flash here to signal the guard break.

	elseif data.type == "ParryWhiff" then
		-- Your parry attempt missed. Show a visual punishment indicator.
		-- e.g.: brief red vignette, small camera shake.
	end
end)

-- ============================================================
-- PUBLIC API  (_G.WuxiaClient)
-- Used by SettingsClient to rebind keys and read current binds.
-- ============================================================
_G.WuxiaClient                     = _G.WuxiaClient or {}
_G.WuxiaClient.CombatActions       = { M1 = A_M1, Heavy = A_HEAVY, Block = A_BLOCK }

_G.WuxiaClient.RebindCombatAction  = function(actionName, ...)
	local newKeys = { ... }
	if #newKeys == 0 or not handlers[actionName] then return end
	activeBinds[actionName] = newKeys
	CAS:UnbindAction(actionName)
	CAS:BindAction(actionName, handlers[actionName], false, table.unpack(newKeys))
end

_G.WuxiaClient.GetCombatBinds      = function()
	local copy = {}
	for k, v in pairs(activeBinds) do copy[k] = v end
	return copy
end