-- @ScriptType: ModuleScript
-- @ScriptType: ModuleScript
-- ============================================================
--  MovementUtil.lua  |  ModuleScript
--  Location: ServerScriptService/Modules/MovementUtil
--
--  CHANGES:
--    ApplyVelocity   — velocity is now attachment-relative (local
--                      space) rather than world-space.  Velocity
--                      follows the character's facing direction even
--                      if it rotates mid-attack.
--    NormalDash      — forward dash for Shift key.  Configurable
--                      force, duration, and cooldown in CONFIG.
--    EVASIVE_DASH_CD — updated to 15 seconds (was 6).
--    NORMAL_DASH_CD  — 3 seconds.
-- ============================================================

local Players     = game:GetService("Players")
local Debris      = game:GetService("Debris")
local RS          = game:GetService("ReplicatedStorage")

-- ── Developer config ──────────────────────────────────────────
local CONFIG = {
	NORMAL_SPEED       = 16,

	-- Normal dash (Shift key)
	NORMAL_DASH_FORCE    = 65,     -- LinearVelocity magnitude
	NORMAL_DASH_DURATION = 0.35,   -- seconds the dash velocity lasts
	NORMAL_DASH_CD       = 3.0,    -- seconds cooldown

	-- Evasive dash (E key, from SoftKnockdown)
	EVASIVE_DASH_FORCE   = 50,
	EVASIVE_DASH_CD      = 15.0,   -- seconds cooldown (was 6)
}

-- Lazy module refs to avoid circular requires
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
--   timing   : "start" (default) | "hit"  — caller decides when to call
--
-- Using RelativeTo = Attachment0 means VectorVelocity is expressed
-- in the attachment's local space.  The attachment has the same
-- orientation as HumanoidRootPart, so:
--   local X = character Right
--   local Y = character Up
--   local Z = character Backward  (Roblox -Z = LookVector)
-- To push "forward" we therefore use  Z = -(forward).
-- ============================================================
function MovementUtil.ApplyVelocity(root, velocityDef)
	if not velocityDef then return end
	if not root or not root.Parent then return end

	local fwd = velocityDef.forward or 0
	local up  = velocityDef.up      or 0
	local dur = velocityDef.duration or 0.2

	if math.abs(fwd) < 0.001 and math.abs(up) < 0.001 then return end

	local att = Instance.new("Attachment")
	att.Parent = root   -- identity CFrame → matches HRP orientation

	local lv = Instance.new("LinearVelocity")
	lv.Attachment0           = att
	lv.VelocityConstraintMode= Enum.VelocityConstraintMode.Vector
	lv.RelativeTo            = Enum.ActuatorRelativeTo.Attachment0  -- KEY: local space
	lv.MaxForce              = 9e4
	-- In attachment local space: -Z is forward, +Y is up
	lv.VectorVelocity        = Vector3.new(0, up, -fwd)
	lv.Parent                = root

	Debris:AddItem(lv,  dur)
	Debris:AddItem(att, dur)
end

-- ============================================================
-- 2.  NormalDash  — called by CombatServer on action="NormalDash"
-- ============================================================
function MovementUtil.NormalDash(player, character)
	mods()

	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root then return end

	-- Stamp cooldown
	local state = CombatState.Get(player)
	state.normalDashCooldownUntil = os.clock() + CONFIG.NORMAL_DASH_CD

	-- Forward dash using attachment-relative LinearVelocity
	local att = Instance.new("Attachment")
	att.Parent = root

	local lv = Instance.new("LinearVelocity")
	lv.Attachment0            = att
	lv.VelocityConstraintMode = Enum.VelocityConstraintMode.Vector
	lv.RelativeTo             = Enum.ActuatorRelativeTo.Attachment0
	lv.MaxForce               = 1.4e5
	lv.VectorVelocity         = Vector3.new(0, 0, -CONFIG.NORMAL_DASH_FORCE)
	lv.Parent                 = root

	Debris:AddItem(lv,  CONFIG.NORMAL_DASH_DURATION)
	Debris:AddItem(att, CONFIG.NORMAL_DASH_DURATION)

	-- Notify client: play dash VFX/anim
	local charFB = RS:FindFirstChild("CharacterFeedback")
	if charFB then charFB:FireClient(player, { type = "NormalDash" }) end
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
		if hum and hum.Parent then hum.WalkSpeed = CONFIG.NORMAL_SPEED end
	end

	local function fireStrike()
		if not char.Parent then return end
		if StatusEffectUtil.BlocksAttack(char) then return end
		local hits = helpers.castHitbox(char, dashDef, attackerPlayer)
		for _, targetChar in ipairs(hits) do
			local targetHum  = targetChar:FindFirstChildOfClass("Humanoid")
			if not targetHum or targetHum.Health <= 0 then continue end
			local targetRoot = targetChar:FindFirstChild("HumanoidRootPart")
			if not targetRoot then continue end
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
		end
	end

	local STEP      = 0.05
	local maxDur    = dashDef.dashDuration or 0.9
	local minStrike = dashDef.strikeDelay  or 0.3

	while active and elapsed < maxDur do
		task.wait(STEP); elapsed += STEP
		if not char.Parent then stopDash(); return end
		if StatusEffectUtil.BlocksAttack(char) then stopDash(); return end
		if not hitFired and dashDef.strikeOnContact and elapsed >= minStrike then
			local testHits = helpers.castHitbox(char, {
				hitboxSize = dashDef.hitboxSize or Vector3.new(4,4,4),
				hitboxFwd  = dashDef.hitboxFwd  or -3,
			}, attackerPlayer)
			if #testHits > 0 then
				hitFired = true; stopDash(); fireStrike(); return
			end
		end
	end

	if not hitFired then hitFired = true; stopDash(); fireStrike() end
end

-- ============================================================
-- 4.  EvasiveDash  — cancels SoftKnockdown (15s CD)
-- ============================================================
function MovementUtil.EvasiveDash(player, character)
	mods()

	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root then return end

	KnockdownUtil.CancelSoftKnockdown(character)

	-- Backward roll impulse (world-space; instant = no rotation issue)
	local backDir = -root.CFrame.LookVector + Vector3.new(0, 0.15, 0)
	root:ApplyImpulse(backDir.Unit * CONFIG.EVASIVE_DASH_FORCE * root.AssemblyMass)

	-- Stamp cooldown
	local state = CombatState.Get(player)
	state.evasiveDashCooldownUntil = os.clock() + CONFIG.EVASIVE_DASH_CD

	-- Notify client
	local charFB = RS:FindFirstChild("CharacterFeedback")
	if charFB then charFB:FireClient(player, { type = "EvasiveDash" }) end
end

return MovementUtil