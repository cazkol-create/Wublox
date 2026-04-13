-- @ScriptType: ModuleScript
-- @ScriptType: ModuleScript
-- @ScriptType: ModuleScript
-- ============================================================
--  MovementUtil.lua  |  ModuleScript
--  Location: ServerScriptService/Modules/MovementUtil
--
--  CHANGES:
--    • Slide now uses a Heartbeat loop to smoothly decelerate the
--      LinearVelocity from SLIDE_INITIAL_SPEED down to 0 over
--      SLIDE_DURATION seconds (ease-out cubic curve), instead of
--      maintaining a constant velocity for the whole duration.
--      This makes the slide feel natural — fast launch, gradual stop.
--    • NormalDash direction parameter support (unchanged).
--    • All CombatConfig constants still used as the source of truth.
-- ============================================================

local Players  = game:GetService("Players")
local Debris   = game:GetService("Debris")
local RS       = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local CombatConfig = require(script.Parent.CombatConfig)

local StatusEffectUtil, KnockdownUtil, CombatState
local function mods()
	if not CombatState then
		StatusEffectUtil = require(script.Parent.StatusEffectUtil)
		KnockdownUtil    = require(script.Parent.KnockdownUtil)
		CombatState      = require(script.Parent.CombatState)
	end
end

local MovementUtil = {}

-- ============================================================
-- 1.  ApplyVelocity
-- ============================================================
function MovementUtil.ApplyVelocity(root, velocityDef)
	if not velocityDef then return end
	if not root or not root.Parent then return end

	local fwd = velocityDef.forward or 0
	local up  = velocityDef.up      or 0
	local dur = velocityDef.duration or 0.2

	if math.abs(fwd) < 0.001 and math.abs(up) < 0.001 then return end

	local att = Instance.new("Attachment"); att.Parent = root

	local lv = Instance.new("LinearVelocity")
	lv.Attachment0            = att
	lv.VelocityConstraintMode = Enum.VelocityConstraintMode.Vector
	lv.RelativeTo             = Enum.ActuatorRelativeTo.Attachment0
	lv.MaxForce               = 9e4
	lv.VectorVelocity         = Vector3.new(0, up, -fwd)
	lv.Parent                 = root

	Debris:AddItem(lv,  dur)
	Debris:AddItem(att, dur)
end

-- ============================================================
-- 2.  NormalDash
-- ============================================================
local DASH_VECTORS = {
	forward = Vector3.new( 0,  0, -1),
	back    = Vector3.new( 0,  0,  1),
	left    = Vector3.new(-1,  0,  0),
	right   = Vector3.new( 1,  0,  0),
}

function MovementUtil.NormalDash(player, character, direction)
	mods()
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root then return end

	local state = CombatState.Get(player)
	state.normalDashCooldownUntil = os.clock() + CombatConfig.NORMAL_DASH_CD

	local dir = DASH_VECTORS[direction or "forward"] or DASH_VECTORS.forward
	local vel = dir * CombatConfig.NORMAL_DASH_FORCE

	local att = Instance.new("Attachment"); att.Parent = root
	local lv  = Instance.new("LinearVelocity")
	lv.Attachment0            = att
	lv.VelocityConstraintMode = Enum.VelocityConstraintMode.Vector
	lv.RelativeTo             = Enum.ActuatorRelativeTo.Attachment0
	lv.MaxForce               = 1.4e5
	lv.VectorVelocity         = vel
	lv.Parent                 = root

	Debris:AddItem(lv,  CombatConfig.NORMAL_DASH_DURATION)
	Debris:AddItem(att, CombatConfig.NORMAL_DASH_DURATION)

	local charFB = RS:FindFirstChild("CharacterFeedback")
	if charFB then
		charFB:FireClient(player, { type = "NormalDash", direction = direction or "forward" })
	end
end

-- ============================================================
-- 3.  DashAttack
-- ============================================================
function MovementUtil.DashAttack(attackerPlayer, dashDef, style, helpers)
	mods()
	local char = attackerPlayer.Character; if not char then return end
	local root = char:FindFirstChild("HumanoidRootPart"); if not root then return end
	local hum  = char:FindFirstChildOfClass("Humanoid")

	if hum then hum.WalkSpeed = 4 end

	local att = Instance.new("Attachment"); att.Parent = root
	local lv  = Instance.new("LinearVelocity")
	lv.Attachment0            = att
	lv.VelocityConstraintMode = Enum.VelocityConstraintMode.Vector
	lv.RelativeTo             = Enum.ActuatorRelativeTo.Attachment0
	lv.MaxForce               = 1.2e5
	lv.VectorVelocity         = Vector3.new(0, 0, -(dashDef.dashForce or 60))
	lv.Parent                 = root

	local elapsed  = 0
	local hitFired = false
	local active   = true

	local function stopDash()
		if not active then return end
		active = false
		lv:Destroy(); att:Destroy()
		if hum and hum.Parent then hum.WalkSpeed = CombatConfig.NORMAL_SPEED end
	end

	local function fireStrike()
		if not char.Parent then return end
		if StatusEffectUtil.BlocksAttack(char) then return end
		helpers.castHitbox(char, dashDef, attackerPlayer, function(targetChar, targetHum)
			local targetRoot = targetChar:FindFirstChild("HumanoidRootPart")
			if not targetRoot then return end
			local fwd   = root.CFrame.LookVector
			local kbDir = (fwd + Vector3.new(0, dashDef.knockUpRatio or 0.1, 0)).Unit
			targetHum:TakeDamage(dashDef.damage or 30)
			helpers.applyImpulse(targetRoot, kbDir, dashDef.knockback or 50)
			helpers.applyStun(targetChar, dashDef.stunTime or 1.2)
			helpers.playHitAnim(targetChar)
			helpers.playHitSound(targetRoot, style)
			local tp = Players:GetPlayerFromCharacter(targetChar)
			helpers.CombatFB:FireClient(attackerPlayer, {type="HitConnected", pos=targetRoot.Position})
			if tp then helpers.CombatFB:FireClient(tp, {type="YouWereHit", pos=targetRoot.Position}) end
			if dashDef.canSoftKnockdown then
				helpers.applyKnockdown(targetChar, "soft", dashDef.knockdownDuration)
			elseif dashDef.canHardKnockdown then
				helpers.applyKnockdown(targetChar, "hard", dashDef.knockdownDuration)
			end
		end)
	end

	local STEP     = 0.05
	local maxDur   = dashDef.dashDuration or 0.9
	local minStrike= dashDef.strikeDelay  or 0.3

	while active and elapsed < maxDur do
		task.wait(STEP); elapsed += STEP
		if not char.Parent then stopDash(); return end
		if StatusEffectUtil.BlocksAttack(char) then stopDash(); return end
		if not hitFired and dashDef.strikeOnContact and elapsed >= minStrike then
			local testHits = helpers.castHitbox(char, {
				hitboxSize = dashDef.hitboxSize or Vector3.new(4,4,4),
				hitboxFwd  = dashDef.hitboxFwd  or -3,
			}, attackerPlayer, function() end)
			if testHits and #testHits > 0 then
				hitFired = true; stopDash(); fireStrike(); return
			end
		end
	end

	if not hitFired then stopDash(); fireStrike() end
end

-- ============================================================
-- 4.  EvasiveDash
-- ============================================================
function MovementUtil.EvasiveDash(player, character)
	mods()
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root then return end

	KnockdownUtil.CancelSoftKnockdown(character)

	local backDir = -root.CFrame.LookVector + Vector3.new(0, 0.15, 0)
	root:ApplyImpulse(backDir.Unit * CombatConfig.EVASIVE_DASH_FORCE * root.AssemblyMass)

	local state = CombatState.Get(player)
	state.evasiveDashCooldownUntil = os.clock() + CombatConfig.EVASIVE_DASH_CD

	local charFB = RS:FindFirstChild("CharacterFeedback")
	if charFB then charFB:FireClient(player, { type = "EvasiveDash" }) end
end

-- ============================================================
-- 5.  Slide  — smooth deceleration via Heartbeat loop
--
--  The LinearVelocity starts at SLIDE_INITIAL_SPEED and is
--  eased out (cubic) to 0 over SLIDE_DURATION seconds.
--  This gives a punchy launch that naturally bleeds off,
--  rather than an abrupt stop at a fixed duration.
-- ============================================================
local SLIDE_INITIAL_SPEED = 65   -- studs/s at the start of the slide

local function easeOutCubic(t)
	-- t in [0, 1] → returns value in [1, 0] (starts fast, ends slow)
	local inv = 1 - t
	return inv * inv * inv
end

function MovementUtil.Slide(player, character)
	mods()

	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root then return end

	local hum = character:FindFirstChildOfClass("Humanoid")

	-- Lower WalkSpeed during slide so the player can't steer out of it
	if hum then hum.WalkSpeed = 4 end

	local att = Instance.new("Attachment")
	att.Parent = root

	local lv = Instance.new("LinearVelocity")
	lv.Attachment0            = att
	lv.VelocityConstraintMode = Enum.VelocityConstraintMode.Vector
	lv.RelativeTo             = Enum.ActuatorRelativeTo.Attachment0
	lv.MaxForce               = 1.4e5
	lv.VectorVelocity         = Vector3.new(0, 0, -SLIDE_INITIAL_SPEED)
	lv.Parent                 = root

	local duration = CombatConfig.SLIDE_DURATION  -- 0.8 s
	local elapsed  = 0
	local conn

	conn = RunService.Heartbeat:Connect(function(dt)
		elapsed += dt

		-- If character is gone or CC'd mid-slide, abort immediately
		if not root.Parent or not character.Parent then
			conn:Disconnect()
			pcall(function() lv:Destroy() end)
			pcall(function() att:Destroy() end)
			return
		end

		if elapsed >= duration then
			conn:Disconnect()
			lv:Destroy()
			att:Destroy()
			-- Restore WalkSpeed once the slide ends
			if hum and hum.Parent then
				hum.WalkSpeed = CombatConfig.NORMAL_SPEED
			end
			return
		end

		-- Ease out: t = 0 → full speed, t = 1 → zero speed
		local t     = elapsed / duration
		local speed = SLIDE_INITIAL_SPEED * easeOutCubic(t)
		lv.VectorVelocity = Vector3.new(0, 0, -speed)
	end)

	-- Stamp server-side slide cooldown
	local state = CombatState.Get(player)
	state.slideCooldownUntil = os.clock() + CombatConfig.SLIDE_COOLDOWN

	-- Notify client to play slide animation
	local charFB = RS:FindFirstChild("CharacterFeedback")
	if charFB then
		charFB:FireClient(player, { type = "Slide" })
	end
end

return MovementUtil