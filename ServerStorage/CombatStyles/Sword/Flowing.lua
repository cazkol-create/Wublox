-- @ScriptType: ModuleScript
-- ============================================================
--  Flowing.lua  |  ModuleScript
--  Location: ServerStorage/CombatStyles/Sword/Flowing
--
--  Sword Style 2: Flowing River — fast, fluid slashes with
--  less raw power but faster hit-frames. Suits an agile fighter.
--
--  STATUS: STUB — tune damage/hitbox/windupWait once animations
--  are finalised. windupWait values below are PLACEHOLDERS.
--
--  Animation folder: CombatClient > "Sword Animations Flowing"
--  (create this folder in CombatClient when animations are ready)
-- ============================================================

return {
	styleName  = "Flowing",
	weaponType = "Sword",

	attacks = {

		Regular = {
			damage       = 17,
			selfImpulse  = 16,
			knockback    = 26,
			knockUpRatio = 0.08,
			stunTime     = 0.75,
			hitboxSize   = Vector3.new(4, 5, 7),
			hitboxFwd    = -5.0,
			windupWait   = 0.80,    -- PLACEHOLDER — update to match animation
			breaksBlock  = false,
		},

		Last = {
			damage       = 24,
			selfImpulse  = 20,
			knockback    = 54,
			knockUpRatio = 0.24,
			stunTime     = 1.10,
			hitboxSize   = Vector3.new(5, 5, 8),
			hitboxFwd    = -5.5,
			windupWait   = 1.10,    -- PLACEHOLDER
			breaksBlock  = false,
		},

		Heavy = {
			damage       = 38,
			selfImpulse  = 22,
			knockback    = 72,
			knockUpRatio = 0.10,
			stunTime     = 1.70,
			hitboxSize   = Vector3.new(3.5, 5, 10),
			hitboxFwd    = -6.0,
			windupWait   = 1.50,    -- PLACEHOLDER
			breaksBlock  = true,
		},
	},
}