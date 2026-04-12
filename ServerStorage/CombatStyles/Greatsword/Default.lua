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
	weaponType  = "Greatsword",
	comboLength = 3,   -- 2 regular hits + 1 finisher

	sounds = {
		-- Leave as "rbxassetid://0" to use SoundUtil fallback sounds.
		hitId   = "rbxassetid://138293953015099",
		swingId = "rbxassetid://0",
	},

	attacks = {

		comboHits = {
			[1] = {
				damage       = 20,
				knockback    = 28,
				knockUpRatio = 0.08,
				stunTime     = 0.90,
				hitboxSize   = Vector3.new(4, 5, 7),
				hitboxFwd    = -5.0,
				hitWindow    = 0.15,
				windupWait   = 0.90,
				breaksBlock  = false,
				selfImpulse  = 14,
				velocity     = { forward = 18, up = 0, duration = 0.20 },
				endlag       = 1.05,
				resetTimer   = 1.50,
			},
			[2] = {
				damage       = 22,
				knockback    = 30,
				knockUpRatio = 0.09,
				stunTime     = 0.90,
				hitboxSize   = Vector3.new(4, 5, 7),
				hitboxFwd    = -5.0,
				hitWindow    = 0.15,
				windupWait   = 0.90,
				breaksBlock  = false,
				selfImpulse  = 14,
				velocity     = { forward = 18, up = 0, duration = 0.20 },
				endlag	     = 1.05,
				resetTimer   = 1.50,
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
			damage            = 28,
			knockback         = 60,
			knockUpRatio      = 0.28,
			stunTime          = 1.20,
			hitboxSize        = Vector3.new(5, 5, 8),
			hitboxFwd         = -5.5,
			hitWindow         = 0.20,
			windupWait        = 1.20,
			breaksBlock       = false,
			selfImpulse       = 18,
			ragdoll           = true,
			ragdollDuration   = 2.5,
			canSoftKnockdown  = true,
			knockdownDuration = 2.5,
			velocity          = { forward = 22, up = 2, duration = 0.30 },
			serverCD          = 2.70,
			endlag 			  = 1.5
		},

		-- Heavy: has serverCD (prevents spamming heavy).
		Heavy = {
			damage       = 42,
			knockback    = 80,
			knockUpRatio = 0.12,
			stunTime     = 1.90,
			hitboxSize   = Vector3.new(3.5, 5, 10),
			hitboxFwd    = -6.0,
			hitWindow    = 0.20,
			windupWait   = 1.67,
			breaksBlock  = true,
			selfImpulse  = 24,
			velocity     = { forward = 26, up = 0, duration = 0.35 },
			serverCD     = 2.40,
			endlag       = 1.80,
		},
	},
}