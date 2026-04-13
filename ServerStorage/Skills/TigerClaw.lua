-- @ScriptType: ModuleScript
-- @ScriptType: ModuleScript
-- ============================================================
--  TigerClaw.lua  |  ModuleScript  (EXAMPLE SKILL TEMPLATE)
--  Location: ServerStorage/Skills/TigerClaw
--
--  Fist skill: Tiger Claw.
--  Grants via SkillSystem.GrantSkill(player, "TigerClaw").
--  Compatible weapon: Fist only (set in SkillRegistry).
--
--  ── How Execute works ───────────────────────────────────────
--  Execute(player, character, helpers) is called by SkillSystem
--  in a task.spawn — it is safe to use task.wait() inside.
--  The SkillSystem has already validated:
--    • skill is equipped
--    • weapon is compatible and in hand
--    • player is not CC'd (stunned / knocked down)
--    • cooldown has expired
--
--  ── Available helpers ───────────────────────────────────────
--  helpers.applyDamage(humanoid, amount)
--  helpers.applyImpulse(root, direction, force)
--  helpers.applyStun(character, duration)
--  helpers.applyKnockdown(character, "soft"|"hard", duration)
--  helpers.ragdoll(character, duration, impulseVector)
--  helpers.castHitbox(attackerChar, def, attackerPlayer, onHitFn)
--  helpers.playHitAnim(character)
--  helpers.setEndlag(player, duration)    ← locks actions + notifies client
--  helpers.tagCombat(player)              ← pauses health regen
--  helpers.fireCombatFB(player, data)     ← reliable RemoteEvent
--  helpers.fireCombatFX(player, data)     ← unreliable VFX RemoteEvent
--  helpers.fireSoundFX(soundType, pos)    ← unreliable sound RemoteEvent
--  helpers.fireAllCombatFB(data)
--  helpers.fireCharFB(player, data)
--  helpers.KnockdownUtil                  ← module ref if needed
--  helpers.RagdollUtil                    ← module ref if needed
--  helpers.CombatState                    ← module ref if needed
--  helpers.Players                        ← game:GetService("Players")
--
--  ── Tuning fields ───────────────────────────────────────────
--  All timing/damage numbers live here, not in SkillRegistry.
--  SkillRegistry only holds UI/keybind metadata.
--  The cooldown in SkillRegistry must match COOLDOWN below so
--  the client prediction and the server agree.
-- ============================================================

-- ── Skill-local tuning ────────────────────────────────────────
local DAMAGE          = 35
local KNOCKBACK       = 150
local KNOCKUP_RATIO   = 0.25
local STUN_DURATION   = 1.50    -- seconds the target is stunned
local WINDUP_WAIT     = 0.30    -- seconds before the hitbox fires
local HIT_WINDOW      = 0.20    -- seconds the hitbox stays active
local ENDLAG_DURATION = 0.70    -- seconds attacker is locked after hitting
local COOLDOWN        = 3      -- must match SkillRegistry TigerClaw.cooldown
local SELF_IMPULSE    = 200      -- forward lunge force
local HITBOX_SIZE     = Vector3.new(5, 5, 7)
local HITBOX_FWD      = -4.0    -- offset forward from HumanoidRootPart

return {
	id = "TigerClaw",

	Execute = function(player, character, helpers)
		local root = character:FindFirstChild("HumanoidRootPart")
		if not root then return end

		-- Tag attacker as in-combat immediately (pauses their regen)
		helpers.tagCombat(player)

		-- ── Set endlag for the entire skill window ────────────
		-- This prevents the player from M1-ing or triggering
		-- another skill until the window + endlag pass.
		helpers.setEndlag(player, WINDUP_WAIT + HIT_WINDOW + ENDLAG_DURATION)

		-- ── Forward lunge ─────────────────────────────────────
		local lunge      = Instance.new("Attachment"); lunge.Parent = root
		local lv         = Instance.new("LinearVelocity")
		lv.Attachment0            = lunge
		lv.VelocityConstraintMode = Enum.VelocityConstraintMode.Vector
		lv.RelativeTo             = Enum.ActuatorRelativeTo.Attachment0
		lv.MaxForce               = 9e4
		lv.VectorVelocity         = Vector3.new(0, 0, -SELF_IMPULSE)
		lv.Parent                 = root
		game:GetService("Debris"):AddItem(lv,    WINDUP_WAIT)
		game:GetService("Debris"):AddItem(lunge, WINDUP_WAIT)

		-- ── Windup delay ──────────────────────────────────────
		task.wait(WINDUP_WAIT)
		if not character.Parent then return end

		-- Re-check CC after the wait (player could have been stunned mid-windup)
		local SEU = require(game:GetService("ServerScriptService").Modules.StatusEffectUtil)
		if SEU.BlocksAttack(character) then return end

		-- ── Play swing sound ──────────────────────────────────
		helpers.fireSoundFX("swing", root.Position)

		-- ── Hitbox ────────────────────────────────────────────
		local hitDef = {
			hitboxSize = HITBOX_SIZE,
			hitboxFwd  = HITBOX_FWD,
			hitWindow  = HIT_WINDOW,
		}

		helpers.castHitbox(character, hitDef, player, function(targetChar, humanoid)
			local targetRoot   = targetChar:FindFirstChild("HumanoidRootPart")
			if not targetRoot then return end
			local targetPlayer = helpers.Players:GetPlayerFromCharacter(targetChar)

			-- Block state check (Tiger Claw ignores block — that's the flavour)
			-- If you want it to be blockable, check CombatState here and return.

			-- ── Deal damage ───────────────────────────────────
			helpers.applyDamage(humanoid, DAMAGE)

			-- ── Knockback ─────────────────────────────────────
			local fwd    = root.CFrame.LookVector
			local kbDir  = (fwd + Vector3.new(0, KNOCKUP_RATIO, 0)).Unit
			helpers.applyImpulse(targetRoot, kbDir, KNOCKBACK)

			-- ── Stun ──────────────────────────────────────────
			helpers.applyStun(targetChar, STUN_DURATION)

			-- ── Hit animation on target ───────────────────────
			helpers.playHitAnim(targetChar)

			-- ── Sound at impact position ──────────────────────
			helpers.fireSoundFX("hit", targetRoot.Position)

			-- ── Tag defender as in-combat ─────────────────────
			helpers.tagCombat(targetPlayer)

			-- ── VFX feedback ──────────────────────────────────
			helpers.fireCombatFX(player, {
				type = "HitConnected",
				pos  = targetRoot.Position,
			})
			if targetPlayer then
				helpers.fireCombatFX(targetPlayer, {
					type = "YouWereHit",
					pos  = targetRoot.Position,
				})
			end

			-- ── Optional: soft knockdown on this skill ────────
			-- Uncomment to knock the target down instead of just stunning:
			-- helpers.applyKnockdown(targetChar, "soft", 2.0)
		end)

		-- ── Post-hit endlag correction ────────────────────────
		-- Shorten the endlag now that the hitbox window has closed.
		-- The attacker is locked for ENDLAG_DURATION more seconds.
		helpers.setEndlag(player, ENDLAG_DURATION)
	end,
}