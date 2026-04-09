-- @ScriptType: ModuleScript
-- @ScriptType: ModuleScript
-- Location: ServerStorage/CombatStyles/Sword/Default
return {
	styleName  = "Mad Monk",
	weaponType = "Staff",

	sounds = {
		hitId = "rbxassetid://0",
	},

	attacks = {

		comboHits = {
			[1] = {
				damage       = 8,
				knockback    = 28,
				knockUpRatio = 0.08,
				stunTime     = 0.6,
				hitboxSize   = Vector3.new(4, 3, 6),
				hitboxFwd    = -3.0,
				hitWindow    = 0.13,
				windupWait   = 0.4,
				breaksBlock  = false,
				selfImpulse  = 14,
				velocity     = { forward = 18, up = 0, duration = 0.20 },
				serverCD     = 0.67,
				resetTimer   = 1.1,
			},
			[2] = {
				damage       = 12,
				knockback    = 30,
				knockUpRatio = 0.09,
				stunTime     = 0.43,
				hitboxSize   = Vector3.new(14, 3, 7),
				hitboxFwd    = -3.5,
				hitWindow    = 0.13,
				windupWait   = 0.7,
				breaksBlock  = false,
				selfImpulse  = 14,
				velocity     = { forward = 18, up = 0, duration = 0.20 },
				serverCD     = 1.05,
				resetTimer   = 1.1,
			},
		},

		Regular = {
			damage       = 10,
			knockback    = 30,
			knockUpRatio = 0.10,
			stunTime     = 0.90,
			hitboxSize   = Vector3.new(14, 3, 12),
			hitboxFwd    = -6.0,
			hitWindow    = 0.15,
			windupWait   = 0.53,
			breaksBlock  = false,
			selfImpulse  = 14,
			velocity     = { forward = 18, up = 0, duration = 0.20 },
			serverCD     = 0.6,
		},

		Last = {
			damage            = 10,
			knockback         = 60,
			knockUpRatio      = 0.28,
			stunTime          = 1.20,
			hitboxSize        = Vector3.new(14, 3, 12),
			hitboxFwd         = -4.0,
			hitWindow         = 0.24,
			windupWait        = 0.53,
			breaksBlock       = false,
			selfImpulse       = 18,
			ragdoll           = true,
			ragdollDuration   = 2.0,
			canSoftKnockdown  = false,
			knockdownDuration = 2.5,
			velocity          = { forward = 22, up = 2, duration = 0.30 },
			serverCD          = 2.70,
		},

		Heavy = {
			damage      	= 25,
			knockback    	= 80,
			knockUpRatio 	= 0.12,
			stunTime     	= 1.90,
			hitboxSize   	= Vector3.new(20, 5, 20),
			hitboxFwd    	= 0.00,
			hitWindow    	= 0.19,
			windupWait   	= 1.28,
			breaksBlock  	= true,
			selfImpulse  	= 24,
			ragdoll        	= true,
			ragdollDuration	= 2.5,
			velocity     	= { forward = 7, up = 0, duration = 1.38 },
			serverCD     	= 2.20,
			endlag       	= 0.50,
		},
	},
}