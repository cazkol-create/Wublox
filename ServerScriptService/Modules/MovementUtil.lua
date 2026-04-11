-- @ScriptType: ModuleScript
-- @ScriptType: ModuleScript
-- ============================================================
--  MovementUtil.lua  |  ModuleScript
--  Location: ServerScriptService/Modules/MovementUtil
--
--  CHANGES:
--    • NormalDash now accepts a `direction` parameter
--      ("forward" | "back" | "left" | "right").
--      Sent by MovementClient based on held WASD keys.
--
--    • NORMAL_DASH_CD, EVASIVE_DASH_CD, NORMAL_SPEED,
--      NORMAL_DASH_FORCE, NORMAL_DASH_DURATION, EVASIVE_DASH_FORCE
--      are now read from CombatConfig so there is a single source.
--
--    • All velocity (ApplyVelocity, dashes) still uses
--      attachment-relative LinearVelocity (RelativeTo = Attachment0).
-- ============================================================

local Players  = game:GetService("Players")
local Debris   = game:GetService("Debris")
local RS       = game:GetService("ReplicatedStorage")

local CombatConfig = require(script.Parent.CombatConfig)

-- Lazy-loaded to avoid circular requires
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
-- 1.  ApplyVelocity  — attachment-relative
-- ============================================================
-- velocityDef:
--   forward  : studs/s along the character's look direction
--   up       : studs/s upward
--   duration : seconds the LinearVelocity constraint is active
--   timing   : "start" (default) | "hit" — caller decides when to invoke
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
	-- attachment-local space: -Z = forward, +Y = up
	lv.VectorVelocity         = Vector3.new(0, up, -fwd)
	lv.Parent                 = root

	Debris:AddItem(lv,  dur)
	Debris:AddItem(att, dur)
end

-- ============================================================
-- 2.  NormalDash  — called when action="NormalDash"
--     direction: "forward" | "back" | "left" | "right"
--     Falls back to "forward" if direction is absent or unrecognised.
-- ============================================================
-- Velocity vectors in attachment-local space:
--   forward → -Z, back → +Z, left → -X, right → +X
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

	-- Stamp cooldown
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

	-- Notify client: play dash animation (direction included for anims)
	local charFB = RS:FindFirstChild("CharacterFeedback")
	if charFB then
		charFB:FireClient(player, { type = "NormalDash", direction = direction or "forward" })
	end
end

-- ============================================================
-- 3.  DashAttack  — sustained forward dash for skill use
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
		local hits = helpers.castHitbox(char, dashDef, attackerPlayer, function(targetChar, targetHum)
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
-- 4.  EvasiveDash  — cancels SoftKnockdown
-- ============================================================
function MovementUtil.EvasiveDash(player, character)
	mods()
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root then return end

	KnockdownUtil.CancelSoftKnockdown(character)

	-- Backwards roll impulse (world-space — no rotation issue since it's instantaneous)
	local backDir = -root.CFrame.LookVector + Vector3.new(0, 0.15, 0)
	root:ApplyImpulse(backDir.Unit * CombatConfig.EVASIVE_DASH_FORCE * root.AssemblyMass)

	local state = CombatState.Get(player)
	state.evasiveDashCooldownUntil = os.clock() + CombatConfig.EVASIVE_DASH_CD

	local charFB = RS:FindFirstChild("CharacterFeedback")
	if charFB then charFB:FireClient(player, { type = "EvasiveDash" }) end
end

-- ============================================================
-- New MovementUtil.Slide Function
-- ============================================================

function MovementUtil.Slide(player, character)
	mods()

	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root then return end

	local att = Instance.new("Attachment")
	att.Parent = root

	local lv = Instance.new("LinearVelocity")
	lv.Attachment0 = att
	lv.VelocityConstraintMode = Enum.VelocityConstraintMode.Vector
	lv.RelativeTo = Enum.ActuatorRelativeTo.Attachment0
	lv.MaxForce = 1.2e5
	lv.VectorVelocity = Vector3.new(0, 0, -50)
	lv.Parent = root

	Debris:AddItem(lv, 0.8)
	Debris:AddItem(att, 0.8)

	--[[ I-frames
	local tag = Instance.new("BoolValue")
	tag.Name = "IFrames"
	tag.Parent = character
	Debris:AddItem(tag, 0.5)
	]]

	-- Notify client
	local charFB = RS:FindFirstChild("CharacterFeedback")
	if charFB then
		charFB:FireClient(player, { type = "Slide" })
	end
end

return MovementUtil