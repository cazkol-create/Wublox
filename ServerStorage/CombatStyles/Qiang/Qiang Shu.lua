-- @ScriptType: ModuleScript
-- @ScriptType: ModuleScript
-- Location: ServerStorage/CombatStyles/Fist/Default
return {
	styleName  = "Qiang Shu",
	weaponType = "Qiang",

	sounds = {
		hitId = "rbxassetid://0",
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
				velocity     = { forward = 12, up = 0, duration = 0.18 },
				serverCD     = 0.52,
				resetTimer   = 1.20,
			},
			[2] = {
				damage       = 8,
				knockback    = 27,
				knockUpRatio = 0.08,
				stunTime     = 0.22,
				hitboxSize   = Vector3.new(5, 5, 5),
				hitboxFwd    = -3.5,
				hitWindow    = 0.12,
				windupWait   = 0.22,
				breaksBlock  = false,
				selfImpulse  = 10,
				velocity     = { forward = 12, up = 0, duration = 0.18 },
				serverCD     = 0.52,
				resetTimer   = 1.20,
			},
		},

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
			velocity     = { forward = 12, up = 0, duration = 0.18 },
			serverCD     = 0.52,
		},

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
			ragdoll           = false,
			ragdollDuration   = 2.2,
			canSoftKnockdown  = false,
			knockdownDuration = 2.2,
			velocity          = { forward = 24, up = 3, duration = 0.1 },
			serverCD          = 1.42,
		},

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