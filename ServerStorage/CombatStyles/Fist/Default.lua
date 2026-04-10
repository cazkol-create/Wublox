-- @ScriptType: ModuleScript
-- @ScriptType: ModuleScript
-- ============================================================
--  Default.lua  |  ModuleScript
--  Location: ServerStorage/CombatStyles/Fist/Default
--
--  CHANGES:
--    • comboHits now use `endlag` instead of `serverCD` for
--      the post-hit window.  Regular M1s NO LONGER have serverCD;
--      endlag is the only gate between consecutive hits.
--    • serverCD is kept on Last and Heavy only (per new design).
--    • comboLength field added so CombatServer can read it
--      directly without needing CombatData.GetTiming().
-- ============================================================

return {
	styleName   = "Default",
	weaponType  = "Fist",
	comboLength = 3,   -- 2 regular hits + 1 finisher

	sounds = {
		-- Leave as "rbxassetid://0" to use SoundUtil fallback sounds.
		hitId   = "rbxassetid://0",
		swingId = "rbxassetid://0",
	},

	attacks = {

		comboHits = {
			[1] = {
				damage       = 8,
				knockback    = 26,
				knockUpRatio = 0.08,
				stunTime     = 0.4,
				hitboxSize   = Vector3.new(5, 5, 5),
				hitboxFwd    = -3.5,
				hitWindow    = 0.12,
				windupWait   = 0.22,
				breaksBlock  = false,
				selfImpulse  = 10,
				velocity     = { forward = 12, up = 0, duration = 0.22 },
				-- endlag: blocks ALL actions for this long after the hitbox.
				-- No serverCD — endlag is the only gate for regular M1s.
				endlag       = 0.5,
				resetTimer   = 1,
			},
			[2] = {
				damage       = 10,
				knockback    = 27,
				knockUpRatio = 0.08,
				stunTime     = 0.14,
				hitboxSize   = Vector3.new(5, 5, 5),
				hitboxFwd    = -3.5,
				hitWindow    = 0.12,
				windupWait   = 0.22,
				breaksBlock  = false,
				selfImpulse  = 10,
				velocity     = { forward = 12, up = 0, duration = 0.22 },
				endlag       = 0.67,
				resetTimer   = 1.17,
			},
		},
--[[
		-- Fallback Regular (used if comboHits is absent).
		Regular = {
			damage       = 15,
			knockback    = 26,
			knockUpRatio = 0.08,
			stunTime     = 0.85,
			hitboxSize   = Vector3.new(5, 5, 5),
			hitboxFwd    = -3.5,
			hitWindow    = 0.12,
			windupWait   = 0.22,
			breaksBlock  = false,
			selfImpulse  = 10,
			velocity     = { forward = 12, up = 0, duration = 0.22 },
			endlag       = 0.18,
		},]]

		-- Finisher: has serverCD (prevents spamming the flourish).
		Last = {
			damage            = 16,
			knockback         = 55,
			knockUpRatio      = 0.28,
			stunTime          = 1.20,
			hitboxSize        = Vector3.new(6, 6, 6),
			hitboxFwd         = -4.0,
			hitWindow         = 0.18,
			windupWait        = 0.32,
			breaksBlock       = false,
			selfImpulse       = 14,
			ragdoll           = true,
			ragdollDuration   = 1,
			canSoftKnockdown  = false,
			knockdownDuration = 2.2,
			velocity          = { forward = 24, up = 3, duration = 0.10 },
			-- serverCD: reuse cooldown for the flourish itself.
			-- endlag: blocks ALL actions after the flourish lands.
			serverCD          = 1.20,
			endlag            = 0.80,
		},

		-- Heavy: has serverCD (prevents spamming heavy).
		Heavy = {
			damage       = 32,
			knockback    = 65,
			knockUpRatio = 0.14,
			stunTime     = 1.70,
			hitboxSize   = Vector3.new(6, 6, 7),
			hitboxFwd    = -4.5,
			hitWindow    = 0.18,
			windupWait   = 0.45,
			breaksBlock  = true,
			selfImpulse  = 9,
			velocity     = { forward = 14, up = 0, duration = 0.25 },
			serverCD     = 1.00,
			endlag       = 0.50,
		},
	},
}