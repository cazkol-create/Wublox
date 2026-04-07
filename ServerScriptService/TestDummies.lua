-- @ScriptType: Script
-- ============================================================
--  TestDummies.lua  |  Script  (NOT ModuleScript)
--  Location: ServerScriptService
--
--  Spawns three training NPCs.
--  Uses CombatState.GetBlockState() so block/parry resolution
--  is identical to player-vs-player combat.
--
--  ── What you need to create in Studio ───────────────────────
--    ServerStorage/Models/Dummies/
--      BlockingDummy     Model  (Humanoid + HumanoidRootPart + rig)
--      ParryingDummy     Model  (Humanoid + HumanoidRootPart + rig)
--      AttackingDummy    Model  (Humanoid + HumanoidRootPart + rig)
--
--    ServerScriptService/CombatServer
--      Hit               Animation  (also needed here for target hit-react)
--
--  ── Animation IDs ───────────────────────────────────────────
--  Fill in the ANIM_IDS table below with your animation asset IDs.
--  Leave a field as "" to skip that animation for now — the dummy
--  will still function, it just won't play that animation.
-- ============================================================

local Players     = game:GetService("Players")
local SS          = game:GetService("ServerStorage")
local Debris      = game:GetService("Debris")
local RS          = game:GetService("ReplicatedStorage")

local CombatState = require(script.Parent.Modules.CombatState)

-- ============================================================
-- ANIMATION ID CONFIG
-- Replace "" with "rbxassetid://YOUR_ID" for each animation.
-- These are the NPC dummy animations — distinct from player anims.
-- ============================================================
local ANIM_IDS = {
	BlockingDummy = {
		idle  = "rbxassetid://3389561930",   -- looping idle while standing
		block = "rbxassetid://111106576412237",   -- looping guard stance
	},
	ParryingDummy = {
		idle  = "rbxassetid://3389561930",   -- looping idle
		parry = "rbxassetid://111106576412237",   -- played during the parry window flash
	},
	AttackingDummy = {
		idle   = "rbxassetid://3389561930",  -- looping idle when no player nearby
		attack = "rbxassetid://2854269987",  -- played when the dummy swings at you
		hit    = "rbxassetid://95892744565362",  -- played when the dummy takes damage (optional override)
	},
}

-- ============================================================
-- TUNING
-- ============================================================
local RESPAWN_DELAY  = 5      -- seconds before a dead dummy respawns
local PARRY_WINDOW   = 1.00   -- keep in sync with CombatData.PARRY_WINDOW
local ATK_RANGE      = 6      -- studs — attacker dummy's melee range
local ATK_INTERVAL   = 2.20   -- seconds between attacker dummy swings
local ATK_DAMAGE     = 12
local ATK_KNOCKBACK  = 20
local ATK_STUN_TIME  = 0.70
local BLOCK_REDUCTION= 0.70

-- ============================================================
-- SPAWN POSITIONS  (edit to place dummies in your map)
-- ============================================================
local SPAWNS = {
	BlockingDummy  = CFrame.new( 10, 3, 20),
	ParryingDummy  = CFrame.new(  0, 3, 20),
	AttackingDummy = CFrame.new(-10, 3, 20),
}

-- ============================================================
-- UTILITY
-- ============================================================
local function applyImpulse(root, dir, force)
	if not root or not root.Parent then return end
	if dir.Magnitude < 0.001 then return end
	root:ApplyImpulse(dir.Unit * force * root.AssemblyMass)
end

local function applyStun(character, duration)
	if not character then return end
	CombatState.ClearBlockOnStun(character)
	local existing = character:FindFirstChild("Stunned")
	if existing then Debris:AddItem(existing, duration); return end
	local b = Instance.new("BoolValue")
	b.Name = "Stunned"; b.Parent = character
	Debris:AddItem(b, duration)
end

-- Shared reference to the Hit animation on CombatServer.
-- Returns the Animation object, or nil if not present.
local function getHitAnimObject()
	local cs = script.Parent:FindFirstChild("CombatServer")
	return cs and cs:FindFirstChild("Hit")
end

local function playHitAnim(character)
	local hum   = character:FindFirstChildOfClass("Humanoid")
	local anim  = hum and hum:FindFirstChildOfClass("Animator")
	local hitAO = getHitAnimObject()
	if not anim or not hitAO then return end
	local track = anim:LoadAnimation(hitAO)
	track:Play()
	track.Stopped:Once(function() track:Destroy() end)
end

-- Loads an animation onto an NPC's Animator from an asset ID string.
-- Returns the AnimationTrack, or nil if the ID is empty or loading fails.
local function loadNPCAnim(humanoid, animId)
	if not animId or animId == "" then return nil end
	local anim = Instance.new("Animation")
	anim.AnimationId = animId
	local animator = humanoid:FindFirstChildOfClass("Animator")
	if not animator then return nil end
	local ok, track = pcall(function() return animator:LoadAnimation(anim) end)
	if not ok then
		warn("[TestDummies] Failed to load animation:", animId, track)
		return nil
	end
	return track
end

-- Floating label above the dummy's head.
local function addLabel(dummy, title, subtitle)
	local root = dummy:FindFirstChild("HumanoidRootPart") or dummy:FindFirstChild("Head")
	if not root then return end
	local bb           = Instance.new("BillboardGui")
	bb.Size            = UDim2.new(0, 200, 0, 54)
	bb.StudsOffset     = Vector3.new(0, 3.5, 0)
	bb.AlwaysOnTop     = true
	bb.Parent          = root

	local t1           = Instance.new("TextLabel", bb)
	t1.Size            = UDim2.new(1, 0, 0.55, 0)
	t1.BackgroundTransparency = 1
	t1.Text            = title
	t1.TextColor3      = Color3.fromRGB(255, 210, 60)
	t1.TextScaled      = true
	t1.Font            = Enum.Font.GothamBold

	local t2           = Instance.new("TextLabel", bb)
	t2.Size            = UDim2.new(1, 0, 0.45, 0)
	t2.Position        = UDim2.new(0, 0, 0.55, 0)
	t2.BackgroundTransparency = 1
	t2.Text            = subtitle
	t2.TextColor3      = Color3.fromRGB(200, 200, 200)
	t2.TextScaled      = true
	t2.Font            = Enum.Font.Gotham
end

-- Secondary floating label returned as a TextLabel for dynamic updates.
local function addIndicator(dummy, yOffset)
	local root = dummy:FindFirstChild("HumanoidRootPart") or dummy:FindFirstChild("Head")
	if not root then return nil end
	local bb       = Instance.new("BillboardGui")
	bb.Size        = UDim2.new(0, 170, 0, 32)
	bb.StudsOffset = Vector3.new(0, yOffset or 5.5, 0)
	bb.AlwaysOnTop = true
	bb.Parent      = root
	local lbl      = Instance.new("TextLabel", bb)
	lbl.Size       = UDim2.new(1, 0, 1, 0)
	lbl.BackgroundTransparency = 1
	lbl.Text       = ""
	lbl.TextColor3 = Color3.fromRGB(255, 80, 80)
	lbl.TextScaled = true
	lbl.Font       = Enum.Font.GothamBold
	return lbl
end

-- Finds the nearest player within maxDist studs of `origin`.
-- Returns (player, playerRoot) or (nil, nil).
local function nearestPlayer(origin, maxDist)
	local best, bestRoot, bestDist = nil, nil, maxDist
	for _, p in ipairs(Players:GetPlayers()) do
		local ch   = p.Character
		local root = ch and ch:FindFirstChild("HumanoidRootPart")
		if root then
			local d = (origin - root.Position).Magnitude
			if d < bestDist then
				best = p; bestRoot = root; bestDist = d
			end
		end
	end
	return best, bestRoot
end

-- ============================================================
-- SPAWN DRIVER
-- ============================================================
local dummyModels = (SS:FindFirstChild("Models") and SS.Models:FindFirstChild("Dummies"))

local function spawnDummy(name, spawnCF, setupFn)
	if not dummyModels then
		warn("[TestDummies] ServerStorage/Models/Dummies/ not found — skipping", name)
		return
	end
	local template = dummyModels:FindFirstChild(name)
	if not template then
		warn("[TestDummies] Model not found in Dummies/:", name)
		return
	end

	local function doSpawn()
		local dummy = template:Clone()
		dummy.Name  = name
		dummy.Parent = workspace

		local root = dummy:FindFirstChild("HumanoidRootPart")
		if root then root.CFrame = spawnCF end

		local hum = dummy:FindFirstChildOfClass("Humanoid")
		if hum then
			hum.MaxHealth = 500
			hum.Health    = 500
			hum.BreakJointsOnDeath = false
		end

		setupFn(dummy, hum, root)

		if hum then
			hum.Died:Connect(function()
				task.delay(RESPAWN_DELAY, doSpawn)
				task.delay(3, function()
					if dummy.Parent then dummy:Destroy() end
				end)
			end)
		end
	end

	doSpawn()
end

-- ============================================================
-- DUMMY 1: BLOCKING DUMMY
-- Always in block state. Normal attacks do reduced damage.
-- Only Heavy (Q) breaks the guard.
-- ============================================================
spawnDummy("BlockingDummy", SPAWNS.BlockingDummy, function(dummy, hum, root)
	-- "BlockState" StringValue — CombatState.GetBlockState() reads this for NPCs.
	local bs     = Instance.new("StringValue")
	bs.Name      = "BlockState"
	bs.Value     = "blocking"
	bs.Parent    = dummy

	addLabel(dummy, "Blocking Dummy", "Use Heavy [Q] to break guard")

	local idleTrack  = hum and loadNPCAnim(hum, ANIM_IDS.BlockingDummy.idle)
	local blockTrack = hum and loadNPCAnim(hum, ANIM_IDS.BlockingDummy.block)

	-- Play idle then block animations if available.
	if idleTrack  then idleTrack:Play() end
	if blockTrack then
		-- Wait a beat then switch to block pose.
		task.delay(0.3, function()
			if idleTrack and idleTrack.IsPlaying then idleTrack:Stop(0.2) end
			blockTrack:Play()
		end)
	end

	-- Slowly rotate to face the nearest player.
	task.spawn(function()
		while dummy.Parent and hum.Health > 0 do
			task.wait(0.5)
			if not root or not root.Parent then break end
			local _, pRoot = nearestPlayer(root.Position, 40)
			if pRoot then
				local dir = (pRoot.Position - root.Position) * Vector3.new(1, 0, 1)
				if dir.Magnitude > 0.1 then
					root.CFrame = CFrame.lookAt(root.Position, root.Position + dir)
				end
			end
		end
	end)
end)

-- ============================================================
-- DUMMY 2: PARRYING DUMMY
-- Randomly opens a parry window. "PARRY!" indicator flashes.
-- Hit it during the flash to get parried and learn the timing.
-- ============================================================
spawnDummy("ParryingDummy", SPAWNS.ParryingDummy, function(dummy, hum, root)
	local bs    = Instance.new("StringValue")
	bs.Name     = "BlockState"
	bs.Value    = ""
	bs.Parent   = dummy

	addLabel(dummy, "Parrying Dummy", "Attack on the flash!")
	local indicator = addIndicator(dummy, 5.5)

	local idleTrack  = hum and loadNPCAnim(hum, ANIM_IDS.ParryingDummy.idle)
	local parryTrack = hum and loadNPCAnim(hum, ANIM_IDS.ParryingDummy.parry)

	if idleTrack then idleTrack:Play() end

	-- Repeatedly open and close the parry window at random intervals.
	task.spawn(function()
		while dummy.Parent and hum.Health > 0 do
			task.wait(math.random(200, 400) / 100)   -- 2.0 – 4.0 s idle gap
			if not dummy.Parent then break end

			-- Open parry window.
			bs.Value = "parrying"
			if indicator then indicator.Text = "⚡  PARRY!" end
			if idleTrack  and idleTrack.IsPlaying  then idleTrack:Stop(0.1) end
			if parryTrack then parryTrack:Play() end

			task.wait(PARRY_WINDOW)

			-- Close parry window regardless of whether it was triggered.
			if bs.Value == "parrying" then bs.Value = "" end
			if indicator then indicator.Text = "" end
			if parryTrack and parryTrack.IsPlaying then parryTrack:Stop(0.1) end
			if idleTrack  then idleTrack:Play() end
		end
	end)
end)

-- ============================================================
-- DUMMY 3: ATTACKING DUMMY
-- Finds the nearest player and swings at them periodically.
-- Fully respects the player's block and parry state via
-- CombatState.GetBlockState(), making it a proper test target.
-- ============================================================
spawnDummy("AttackingDummy", SPAWNS.AttackingDummy, function(dummy, hum, root)
	addLabel(dummy, "Attacking Dummy", "Practice blocking & parrying")

	local idleTrack  = hum and loadNPCAnim(hum, ANIM_IDS.AttackingDummy.idle)
	local atkTrack   = hum and loadNPCAnim(hum, ANIM_IDS.AttackingDummy.attack)

	if idleTrack then idleTrack:Play() end

	task.spawn(function()
		while dummy.Parent and hum.Health > 0 do
			task.wait(ATK_INTERVAL)
			if not dummy.Parent or not root or not root.Parent then break end
			if dummy:FindFirstChild("Stunned") then continue end

			local targetPlayer, targetRoot = nearestPlayer(root.Position, ATK_RANGE)
			if not targetPlayer then continue end

			local targetChar = targetPlayer.Character
			local targetHum  = targetChar and targetChar:FindFirstChildOfClass("Humanoid")
			if not targetHum or targetHum.Health <= 0 then continue end

			-- Face the target.
			local dir = (targetRoot.Position - root.Position) * Vector3.new(1, 0, 1)
			if dir.Magnitude > 0.1 then
				root.CFrame = CFrame.lookAt(root.Position, root.Position + dir)
			end

			-- Play attack animation (if configured).
			if atkTrack then
				if idleTrack and idleTrack.IsPlaying then idleTrack:Stop(0.1) end
				atkTrack:Play()
				atkTrack.Stopped:Once(function()
					if idleTrack then idleTrack:Play() end
				end)
			end

			-- Resolve block/parry using the shared CombatState API.
			local blockState = CombatState.GetBlockState(targetChar)
			local fwd        = root.CFrame.LookVector

			if blockState == "parrying" then
				-- The player parried the dummy — dummy gets briefly staggered.
				applyStun(dummy, 0.8)
				applyImpulse(root, -root.CFrame.LookVector, 14)

			elseif blockState == "blocking" then
				local reduced = math.max(1, math.floor(ATK_DAMAGE * (1 - BLOCK_REDUCTION)))
				targetHum:TakeDamage(reduced)
				applyImpulse(targetRoot, fwd, 7)

			else
				-- Full hit.
				targetHum:TakeDamage(ATK_DAMAGE)
				applyImpulse(targetRoot, fwd + Vector3.new(0, 0.08, 0), ATK_KNOCKBACK)
				applyStun(targetChar, ATK_STUN_TIME)
				playHitAnim(targetChar)
			end
		end
	end)
end)