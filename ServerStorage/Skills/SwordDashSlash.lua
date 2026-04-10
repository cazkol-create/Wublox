-- @ScriptType: ModuleScript
-- @ScriptType: ModuleScript
-- ============================================================
--  SwordDashSlash.lua  |  ModuleScript
--  Location: ServerStorage/Skills/SwordDashSlash
--
--  Sword skill: Dash Slash.
--  Assigns via SkillSystem.GrantSkill(player, "SwordDashSlash").
--  Compatible weapon: Sword only (set in SkillRegistry).
--
--  Execute receives (player, character, helpers) — no requires needed.
-- ============================================================

return {
	id = "SwordDashSlash",

	Execute = function(player, character, helpers)
		local root = character:FindFirstChild("HumanoidRootPart")
		if not root then return end

		-- Short forward dash using LinearVelocity
		local dashDir = root.CFrame.LookVector
		local att = Instance.new("Attachment"); att.Parent = root
		local lv  = Instance.new("LinearVelocity")
		lv.Attachment0            = att
		lv.VelocityConstraintMode = Enum.VelocityConstraintMode.Vector
		lv.MaxForce               = 1.2e5
		lv.VectorVelocity         = dashDir * 55
		lv.Parent                 = root
		game:GetService("Debris"):AddItem(lv,  0.45)
		game:GetService("Debris"):AddItem(att, 0.45)

		-- Windup before strike
		task.wait(0.35)

		if not character.Parent then return end

		-- Sword slash hitbox
		local hitDef = {
			hitboxSize = Vector3.new(4, 5, 9),
			hitboxFwd  = -5.5,
			hitWindow  = 0.20,
		}

		helpers.castHitbox(character, hitDef, player, function(targetChar, humanoid)
			helpers.applyDamage(humanoid, 40)
			helpers.applyImpulse(
				targetChar:FindFirstChild("HumanoidRootPart"),
				(dashDir + Vector3.new(0, 0.15, 0)).Unit,
				65
			)
			helpers.applyStun(targetChar, 1.60)
			helpers.playHitAnim(targetChar)
			helpers.fireCombatFB(player, {
				type = "HitConnected",
				pos  = targetChar:FindFirstChild("HumanoidRootPart") and
					targetChar.HumanoidRootPart.Position,
			})
			local tp = game:GetService("Players"):GetPlayerFromCharacter(targetChar)
			if tp then
				helpers.fireCombatFB(tp, { type = "YouWereHit", pos = nil })
			end
		end)
	end,
}