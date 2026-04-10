-- @ScriptType: ModuleScript
-- @ScriptType: ModuleScript
-- Location: ServerStorage/CombatStyles/Qiang/Default
return {
	styleName  = "Qiang Shu",
	weaponType = "Qiang",
	comboLength = 3,

	sounds = {
		hitId = "rbxassetid://0",
		swingId = "rbxassetid://0",
	},

	attacks = {

		comboHits = {
			[1] = {
				damage       = 8,
				knockback    = 28,
				knockUpRatio = 0.08,
				stunTime     = 0.7,
				hitboxSize   = Vector3.new(4, 4, 5),
				hitboxFwd    = -6,
				hitWindow    = 0.4,
				windupWait   = 0.97,
				breaksBlock  = false,
				selfImpulse  = 14,
				velocity     = { forward = 15, up = 0, duration = 0.35 },
				endlag       = 0.8,
				resetTimer   = 0.97,
			},
			[2] = {
				damage       = 10,
				knockback    = 30,
				knockUpRatio = 0.09,
				stunTime     = 1.1,
				hitboxSize   = Vector3.new(15.5, 4, 8),
				hitboxFwd    = -6,
				hitWindow    = 0.13,
				windupWait   = 1.15,
				breaksBlock  = false,
				selfImpulse  = 14,
				velocity     = { forward = 20, up = 0, duration = 0.20 },
				endlag       = 1.0,
				resetTimer   = 1.2,
			},
		},
--[[
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
			endlag     = 0.6,
		},]]

		Last = {
			damage            = 12,
			knockback         = 10,
			knockUpRatio      = 10,
			stunTime          = 0.5,
			hitboxSize        = Vector3.new(2.5, 9.5, 10.5),
			hitboxFwd         = -6.0,
			hitWindow         = 0.24,
			windupWait        = 1.30,
			breaksBlock       = false,
			selfImpulse       = 18,
			ragdoll           = true,
			ragdollDuration   = .5,
			canSoftKnockdown  = false,
			knockdownDuration = 2.5,
			velocity          = { forward = 22, up = 2, duration = 0.30 },
			serverCD          = 2.0,
			endlag            = 0.8,
		},

		Heavy = {
			damage      	= 11,
			knockback    	= 25,
			knockUpRatio 	= 5,
			stunTime     	= 1.90,
			hitboxSize   	= Vector3.new(17, 4, 11),
			hitboxFwd    	= 0.00,
			hitWindow    	= 0.19,
			windupWait   	= 0.83,
			breaksBlock  	= true,
			selfImpulse  	= 24,
			ragdoll         = true,
			ragdollDuration=  1.5,
			velocity     	= { forward = 7, up = 0, duration = 1.38 },
			serverCD     	= 2.20,
			endlag       	= 0.50,
		},
	},
}