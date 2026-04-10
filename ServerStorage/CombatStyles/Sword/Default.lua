-- @ScriptType: ModuleScript
-- @ScriptType: ModuleScript
-- Location: ServerStorage/CombatStyles/Sword/Default
return {
	styleName  = "Default",
	weaponType = "Sword",

	sounds = {
		hitId = "rbxassetid://0",
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
				serverCD     = 1.05,
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
				serverCD     = 1.05,
				resetTimer   = 1.50,
			},
		},

		Regular = {
			damage       = 20,
			knockback    = 30,
			knockUpRatio = 0.10,
			stunTime     = 0.90,
			hitboxSize   = Vector3.new(4, 5, 7),
			hitboxFwd    = -5.0,
			hitWindow    = 0.15,
			windupWait   = 0.90,
			breaksBlock  = false,
			selfImpulse  = 14,
			velocity     = { forward = 18, up = 0, duration = 0.20 },
			serverCD     = 1.05,
		},

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
		},

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
			serverCD     = 2.20,
			endlag       = 0.60,
		},
	},
}