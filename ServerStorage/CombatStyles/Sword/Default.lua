-- @ScriptType: ModuleScript
-- ============================================================
--  Default.lua  |  ModuleScript
--  Location: ServerStorage/CombatStyles/Sword/Default
--
--  The default sword style. Used when Plr_StyleName = "Default"
--  and Plr_WeaponType = "Sword".
--
--  To create Flowing or Storm:
--    1. Duplicate this file into ServerStorage/CombatStyles/Sword/
--    2. Rename it to "Flowing" or "Storm".
--    3. Tune the values below.
--    4. Set the player's Plr_StyleName StringValue to the new name.
--
--  windupWait: seconds from attack start to hitbox cast.
--              These MUST match the animation's hit-frame timing.
--              Dev-confirmed impact times for Sword Default:
--                M1/M2   → 0.9 s
--                M3 (Last) → 1.2 s
--                Heavy   → 1.67 s
-- ============================================================

return {
	styleName  = "Default",
	weaponType = "Sword",

	attacks = {

		Regular = {
			damage       = 20,
			selfImpulse  = 14,      -- attacker lunge force
			knockback    = 30,      -- force applied to target
			knockUpRatio = 0.10,    -- small upward pop on every hit
			stunTime     = 0.90,
			hitboxSize   = Vector3.new(4, 5, 7),   -- narrow + long reach
			hitboxFwd    = -5.0,    -- how far in front of HRP the box sits
			windupWait   = 0.90,    -- must match animation hit-frame
			breaksBlock  = false,
		},

		Last = {
			-- The flourish finisher — more damage, more launch.
			damage       = 28,
			selfImpulse  = 18,
			knockback    = 60,
			knockUpRatio = 0.28,    -- visible upward launcher pop
			stunTime     = 1.20,
			hitboxSize   = Vector3.new(5, 5, 8),
			hitboxFwd    = -5.5,
			windupWait   = 1.20,    -- must match animation hit-frame
			breaksBlock  = false,
		},

		Heavy = {
			-- Charged lunge thrust — breaks guard, can still be parried.
			damage       = 42,
			selfImpulse  = 24,      -- aggressive forward lunge
			knockback    = 80,
			knockUpRatio = 0.12,
			stunTime     = 1.90,
			hitboxSize   = Vector3.new(3.5, 5, 10),  -- long spear-like reach
			hitboxFwd    = -6.0,
			windupWait   = 1.67,    -- must match animation hit-frame
			breaksBlock  = true,    -- bypasses block; parry still works
		},
	},
}