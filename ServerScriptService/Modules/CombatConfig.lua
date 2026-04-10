-- @ScriptType: ModuleScript
-- ============================================================
--  CombatConfig.lua  |  ModuleScript
--  Location: ServerScriptService/Modules/CombatConfig
--
--  Single source of truth for all server-side constants.
--
--  CHANGES:
--    • COMBO_PRELOCK_BUFFER    — short buffer added to windupWait for the
--      synchronous pre-lock that blocks ghost M1s during windup.
--    • DEFAULT_COMBO_ENDLAG   — fallback post-hit endlag for styles that
--      don't define def.endlag, keeping combos chainable.
--    • NORMAL_DASH_IFRAMES    — invincibility window on normal dash.
--    • EVASIVE_DASH_IFRAMES   — invincibility window on evasive dash.
--    • SLIDE_FORCE / SLIDE_DURATION / SLIDE_COOLDOWN / SLIDE_SLOPE_MULTIPLIER
--      — all tunable slide constants.
--    • JUMP_COOLDOWN          — mirrors MovementClient CONFIG.JUMP_COOLDOWN.
--    • ATTACK_SPEED raised 7 → 11 (less sluggish during windup).
-- ============================================================

local CombatConfig = {}

-- ── Parry system ──────────────────────────────────────────────
CombatConfig.PARRY_WINDOW         = 0.35
CombatConfig.PARRY_PUNISH_CD      = 1.80
CombatConfig.PARRY_RECOVER_CD     = 0.50
CombatConfig.GUARD_BREAK_DURATION = 1.50
CombatConfig.PARRY_STUN_TIME      = 1.80

-- ── Damage reduction ──────────────────────────────────────────
CombatConfig.BLOCK_REDUCTION = 0.70

-- ── Movement speeds ───────────────────────────────────────────
CombatConfig.NORMAL_SPEED = 16
CombatConfig.ATTACK_SPEED = 11    -- raised from 7; reduces sluggish feel during windup
CombatConfig.BLOCK_SPEED  = 8

-- ── Dash cooldowns ────────────────────────────────────────────
CombatConfig.NORMAL_DASH_FORCE    = 65
CombatConfig.NORMAL_DASH_DURATION = 0.35
CombatConfig.NORMAL_DASH_CD       = 3.0
CombatConfig.EVASIVE_DASH_FORCE   = 50
CombatConfig.EVASIVE_DASH_CD      = 15.0

-- ── Jump cooldown ─────────────────────────────────────────────
-- Keep in sync with MovementClient CONFIG.JUMP_COOLDOWN.
CombatConfig.JUMP_COOLDOWN = 0.5

-- ── Combo system ──────────────────────────────────────────────
-- Pre-lock = def.windupWait + COMBO_PRELOCK_BUFFER + def.hitWindow.
-- This window prevents ghost M1s fired during the attack animation.
CombatConfig.COMBO_PRELOCK_BUFFER  = 0.05

-- Fallback post-hit endlag applied when a style attack has no def.endlag.
-- Keeps combos chainable without spamming.
CombatConfig.DEFAULT_COMBO_ENDLAG  = 0.10

-- ── I-frames on dashes ────────────────────────────────────────
-- Duration (seconds) the character is invincible during each dash.
CombatConfig.NORMAL_DASH_IFRAMES   = 0.35   -- matches NORMAL_DASH_DURATION
CombatConfig.EVASIVE_DASH_IFRAMES  = 0.45

-- ── Slide ─────────────────────────────────────────────────────
CombatConfig.SLIDE_FORCE           = 80     -- attachment-local forward impulse
CombatConfig.SLIDE_DURATION        = 0.8    -- seconds the slide lasts
CombatConfig.SLIDE_COOLDOWN        = 1.5    -- seconds before the player can slide again
CombatConfig.SLIDE_SLOPE_MULTIPLIER= 1.5    -- force multiplier when sliding downhill

return CombatConfig
