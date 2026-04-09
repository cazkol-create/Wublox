-- @ScriptType: ModuleScript
-- @ScriptType: ModuleScript
-- ============================================================
--  CombatData.lua  |  ModuleScript
--  Location: ReplicatedStorage/Modules/CombatData
--
--  CHANGES:
--    • comboLength added per style (3 or 4).
--      CombatClient uses this to know when to play the finisher
--      and send action="Last".
--    • evasiveDashCD added (mirrors MovementUtil.EVASIVE_DASH_CD).
--      CombatClient uses this for the local cooldown display.
-- ============================================================

local CombatData = {}

-- ── Parry / block / guard constants ──────────────────────────
CombatData.PARRY_WINDOW         = 0.35
CombatData.PARRY_PUNISH_CD      = 1.80
CombatData.PARRY_RECOVER_CD     = 0.50
CombatData.GUARD_BREAK_DURATION = 1.50
CombatData.EVASIVE_DASH_CD      = 6.0   -- must match MovementUtil constant

-- ── Per-style client timing ───────────────────────────────────
-- m1CD         : minimum seconds between M1 presses
-- lastRecovery : post-finisher lock time
-- heavyCD      : minimum seconds between Heavy presses
-- comboReset   : inactivity before combo counter resets to 1
-- comboLength  : how many hits in the M1 chain (3 or 4)
--                The last hit in the chain is always the "finisher".
-- ─────────────────────────────────────────────────────────────
CombatData.StyleTiming = {

	Fist = {
		Default = {
			m1CD         = 0.52,
			lastRecovery = 1.20,
			heavyCD      = 2.50,
			comboReset   = 1.20,
			comboLength  = 3,
		},
	},

	Sword = {
		Default = {
			m1CD         = 0.95,
			lastRecovery = 1.50,
			heavyCD      = 3.00,
			comboReset   = 1.50,
			comboLength  = 3,
		},
		Flowing = {
			m1CD         = 0.85,
			lastRecovery = 1.40,
			heavyCD      = 2.80,
			comboReset   = 1.40,
			comboLength  = 3,
		},
		Storm = {
			m1CD         = 1.05,
			lastRecovery = 1.60,
			heavyCD      = 3.20,
			comboReset   = 1.60,
			comboLength  = 3,
		},
	},
	
	Staff = {
		['Mad Monk'] = {
			m1CD         = 0.67,
			lastRecovery = 1.50,
			heavyCD      = 2.70,
			comboReset   = 1.1,
			comboLength  = 3,
		},
	}
}

CombatData.DefaultTiming = {
	m1CD = 0.60, lastRecovery = 1.20, heavyCD = 2.50, comboReset = 1.20, comboLength = 3,
}

function CombatData.GetTiming(weaponType, styleName)
	local wt = CombatData.StyleTiming[weaponType]
	if wt and wt[styleName] then return wt[styleName] end
	return CombatData.DefaultTiming
end

-- ── Sound asset IDs ───────────────────────────────────────────
CombatData.StyleSounds = {
	Fist  = { Default = { swingId = "rbxassetid://0", hitId = "rbxassetid://0" } },
	Sword = {
		Default = { swingId = "rbxassetid://0", hitId = "rbxassetid://0" },
		Flowing = { swingId = "rbxassetid://0", hitId = "rbxassetid://0" },
		Storm   = { swingId = "rbxassetid://0", hitId = "rbxassetid://0" },
	},
}

function CombatData.GetSounds(weaponType, styleName)
	local wt = CombatData.StyleSounds[weaponType]
	if not wt then return { swingId = "", hitId = "" } end
	return wt[styleName] or wt["Default"] or { swingId = "", hitId = "" }
end

return CombatData