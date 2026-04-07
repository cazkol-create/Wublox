-- @ScriptType: ModuleScript
-- ============================================================
--  CombatData.lua  |  ModuleScript
--  Location: ReplicatedStorage/Modules/CombatData
--
--  Single source of truth for constants that BOTH the client
--  and server need to agree on.  Damage and hitbox values
--  live in the style files (ServerStorage/CombatStyles/...).
--  This file only holds what the client legitimately needs:
--  timing windows for local feedback and per-style cooldowns.
-- ============================================================

local CombatData = {}

-- How long the parry window stays open after BlockStart.
-- Client uses this to time the parry flash VFX.
-- Server uses this in CombatState to schedule the whiff timer.
CombatData.PARRY_WINDOW        = 0.35   -- seconds

-- Punishment cooldown after the parry window expires unused.
CombatData.PARRY_PUNISH_CD     = 1.80   -- seconds

-- Short cooldown after a SUCCESSFUL parry before the next parry is available.
CombatData.PARRY_RECOVER_CD    = 0.50   -- seconds

-- How long after a guard break the player cannot re-guard.
CombatData.GUARD_BREAK_DURATION = 1.50  -- seconds

-- ── Per-style client timing hints ────────────────────────────
-- These control LOCAL client cooldowns and combo reset.
-- They should be set slightly above the server's windupWait so
-- the next combo input fires AFTER the previous hitbox, keeping
-- the visuals and physics in sync.
--
-- m1CD       : minimum seconds between M1 presses
-- lastRecovery: lock after the flourish (M3)
-- heavyCD    : minimum seconds between Heavy presses
-- comboReset : seconds of inactivity before combo resets to 1
-- ─────────────────────────────────────────────────────────────
CombatData.StyleTiming = {
	Sword = {
		Default = { m1CD = 0.95, lastRecovery = 1.50, heavyCD = 3.00, comboReset = 1.50 },
		Flowing = { m1CD = 0.85, lastRecovery = 1.40, heavyCD = 2.80, comboReset = 1.40 },
		Storm   = { m1CD = 0.80, lastRecovery = 1.30, heavyCD = 2.60, comboReset = 1.30 },
	},
	-- Add more weapon families here as they are built.
}

-- Fallback timing used when a style has no entry in StyleTiming.
CombatData.DefaultTiming = {
	m1CD = 0.5, lastRecovery = 1.50, heavyCD = 3.00, comboReset = 1.00,
}

-- Returns the timing table for the given weapon + style name.
function CombatData.GetTiming(weaponType, styleName)
	local wt = CombatData.StyleTiming[weaponType]
	if wt and wt[styleName] then return wt[styleName] end
	return CombatData.DefaultTiming
end

return CombatData