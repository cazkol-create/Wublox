-- @ScriptType: ModuleScript
-- @ScriptType: ModuleScript
-- Location: ServerStorage/CombatStyles/Sword/Default
return {
	styleName  = "Flowing",
	weaponType = "Sword",

	sounds = {
		hitId = "rbxassetid://0",
	},

	attacks = {

		Regular = {
			damage       = 17,
			knockback    = 26,
			knockUpRatio = 0.08,
			stunTime     = 0.75,
			hitboxSize   = Vector3.new(4, 5, 7),
			hitboxFwd    = -5.0,
			hitWindow    = 0.15,
			windupWait   = 0.80,
			breaksBlock  = false,
			selfImpulse  = 16,
			velocity     = { forward = 18, up = 0, duration = 0.20 },
			serverCD     = 1.05,
		},

		Last = {
			damage            = 24,
			knockback         = 54,
			knockUpRatio      = 0.24,
			stunTime          = 1.10,
			hitboxSize        = Vector3.new(5, 5, 8),
			hitboxFwd         = -5.5,
			hitWindow         = 0.20,
			windupWait        = 1.10,
			breaksBlock       = false,
			selfImpulse       = 20,
			ragdoll           = true,
			ragdollDuration   = 2.5,
			canSoftKnockdown  = false,
			knockdownDuration = 2.5,
			velocity          = { forward = 22, up = 2, duration = 0.30 },
			serverCD          = 2.70,
		},

		Heavy = {
			damage       = 38,
			knockback    = 72,
			knockUpRatio = 0.10,
			stunTime     = 1.70,
			hitboxSize   = Vector3.new(3.5, 5, 10),
			hitboxFwd    = -6.0,
			hitWindow    = 0.20,
			windupWait   = 1.50,
			breaksBlock  = true,
			selfImpulse  = 24,
			velocity     = { forward = 26, up = 0, duration = 0.35 },
			serverCD     = 2.20,
			endlag       = 0.60,
		},
	},
}