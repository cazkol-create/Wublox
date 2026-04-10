-- @ScriptType: ModuleScript
-- @ScriptType: ModuleScript
-- ============================================================
--  CombatConfig.lua  |  ModuleScript
--  Location: ServerScriptService/Modules/CombatConfig
--
--  Single source of truth for all server-side constants.
--  Replaces CombatData for anything server-related.
--
--  Required by CombatServer and CombatState.
--  NOT accessible to clients directly — timing data that the
--  client needs is delivered via CharacterFeedback or CombatFX.
-- ============================================================

local CombatConfig = {}

-- ── Parry system ──────────────────────────────────────────────
CombatConfig.PARRY_WINDOW         = 0.35   -- seconds the parry frame stays open
CombatConfig.PARRY_PUNISH_CD      = 1.80   -- punishment after a missed parry
CombatConfig.PARRY_RECOVER_CD     = 0.50   -- short CD after a successful parry
CombatConfig.GUARD_BREAK_DURATION = 1.50   -- window where re-guarding is impossible
CombatConfig.PARRY_STUN_TIME      = 1.80   -- attacker stun duration when parried

-- ── Damage reduction ──────────────────────────────────────────
CombatConfig.BLOCK_REDUCTION = 0.70        -- 70 % of damage absorbed by block

-- ── Movement speeds ──────────────────────────────────────────
CombatConfig.NORMAL_SPEED = 16
CombatConfig.ATTACK_SPEED = 7
CombatConfig.BLOCK_SPEED  = 8              -- walk speed while actively blocking

-- ── Dash cooldowns (server-enforced) ─────────────────────────
CombatConfig.NORMAL_DASH_FORCE    = 65
CombatConfig.NORMAL_DASH_DURATION = 0.35
CombatConfig.NORMAL_DASH_CD       = 3.0
CombatConfig.EVASIVE_DASH_FORCE   = 50
CombatConfig.EVASIVE_DASH_CD      = 15.0

return CombatConfig