-- @ScriptType: ModuleScript
-- @ScriptType: ModuleScript
-- ============================================================
--  CombatConfig.lua  |  ModuleScript
--  Location: ServerScriptService/Modules/CombatConfig
--
--  Single source of truth for all server-side constants.
--  Replaces CombatData for anything server-related.
--
--  CHANGES:
--    • ATTACK_SPEED raised 7 → 11  (was too sluggish, especially
--      for sword styles with long windupWait values).
--    • JUMP_COOLDOWN added — controls the minimum seconds between
--      consecutive jumps.  MovementClient.lua reads a mirrored
--      constant and enforces it client-side via humanoid state.
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
CombatConfig.ATTACK_SPEED = 11             -- CHANGED: was 7; raised to reduce sluggish feel
CombatConfig.BLOCK_SPEED  = 8             -- walk speed while actively blocking

-- ── Dash cooldowns (server-enforced) ─────────────────────────
CombatConfig.NORMAL_DASH_FORCE    = 65
CombatConfig.NORMAL_DASH_DURATION = 0.35
CombatConfig.NORMAL_DASH_CD       = 3.0
CombatConfig.EVASIVE_DASH_FORCE   = 50
CombatConfig.EVASIVE_DASH_CD      = 15.0

-- ── Jump cooldown ─────────────────────────────────────────────
-- Enforced client-side in MovementClient.lua (keep both in sync).
-- Prevents bunny-hopping and gives jumps a deliberate, weighty feel.
CombatConfig.JUMP_COOLDOWN        = 1.5   -- seconds between consecutive jumps

return CombatConfig