-- @ScriptType: ModuleScript
-- ============================================================
--  Storm.lua  |  ModuleScript
--  Location: ServerStorage/CombatStyles/Sword/Storm
--
--  Sword Style 3: Raging Storm — slow, heavy blows with
--  devastating knockback and high stun. High risk, high reward.
--
--  STATUS: STUB — tune values once animations are finalised.
--  windupWait values below are PLACEHOLDERS.
--
--  Animation folder: CombatClient > "Sword Animations Storm"
--  (create this folder in CombatClient when animations are ready)
-- ============================================================

return {
	styleName  = "Storm",
	weaponType = "Sword",

	attacks = {

		Regular = {
			damage       = 24,
			selfImpulse  = 12,
			knockback    = 40,
			knockUpRatio = 0.12,
			stunTime     = 1.00,
			hitboxSize   = Vector3.new(6, 6, 8),    -- wider arc
			hitboxFwd    = -5.0,
			windupWait   = 1.00,    -- PLACEHOLDER
			breaksBlock  = false,
		},

		Last = {
			damage       = 34,
			selfImpulse  = 16,
			knockback    = 70,
			knockUpRatio = 0.32,
			stunTime     = 1.40,
			hitboxSize   = Vector3.new(7, 6, 8),
			hitboxFwd    = -5.5,
			windupWait   = 1.30,    -- PLACEHOLDER
			breaksBlock  = false,
		},

		Heavy = {
			damage       = 50,
			selfImpulse  = 20,
			knockback    = 95,
			knockUpRatio = 0.15,
			stunTime     = 2.10,
			hitboxSize   = Vector3.new(6, 6, 11),
			hitboxFwd    = -6.0,
			windupWait   = 1.80,    -- PLACEHOLDER
			breaksBlock  = true,
		},
	},
}