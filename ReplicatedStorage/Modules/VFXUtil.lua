-- @ScriptType: ModuleScript
-- @ScriptType: ModuleScript
-- Location: ReplicatedStorage/Modules/CombatVFXConfig
--
-- Declarative map from combat events → (category, effectName) pairs.
--
-- Both CombatClient and any future systems read from here.
-- Adding a new effect = add a row here + add the Part to
-- ReplicatedStorage/Effects/Combat/.  No code changes needed.
--
-- ── Animation marker names ───────────────────────────────────
-- Add KeyframeMarkers in the Roblox Animation Editor with the
-- names listed in AttackMarkers[weaponType][styleName].
-- Common names used here:
--   "Swing"   — the moment the weapon starts moving (early arc)
--   "Impact"  — the exact frame the hitbox becomes active (about to hit)
--   "Hit"     — the exact frame the hitbox should fire (impact)
--   "Recover" — end of the attack recovery phase

local CombatVFXConfig = {}

-- ============================================================
-- ATTACK ANIMATION MARKERS
-- Each entry binds one KeyframeMarker name to one effect.
--
-- { marker, category, effectName, options }
--   marker      : must match the KeyframeMarker name in the animation
--   category    : subfolder of ReplicatedStorage/Effects/
--   effectName  : Part name inside that subfolder
--   options     : VFXUtil.Play options table (duration, weld, etc.)
--   getTargetFn : omit — CombatClient always passes the attacker's HRP
-- ============================================================
CombatVFXConfig.AttackMarkers = {

	Fist = {
		Default = {
			{ marker = "Swing",  category = "Combat", effectName = "Fist_Swing",
				options = { duration = 0.4, transparent = true } },
			{ marker = "Impact", category = "Combat", effectName = "Fist_Impact",
				options = { duration = 0.3, transparent = true } },
			{ marker = "Hit",    category = "Combat", effectName = "Fist_Hit",
				options = { duration = 1.2, transparent = true } },
		},
	},

	Sword = {
		Default = {
			{ marker = "Swing",  category = "Combat", effectName = "Sword_Swing",
				options = { duration = 0.5, transparent = true } },
			{ marker = "Impact", category = "Combat", effectName = "Sword_Impact",
				options = { duration = 0.3, transparent = true } },
			{ marker = "Hit",    category = "Combat", effectName = "Sword_Hit",
				options = { duration = 1.2, transparent = true } },
		},
		Flowing = {
			{ marker = "Swing",  category = "Combat", effectName = "Sword_Swing_Light",
				options = { duration = 0.4, transparent = true } },
			{ marker = "Impact", category = "Combat", effectName = "Sword_Impact",
				options = { duration = 0.3, transparent = true } },
			{ marker = "Hit",    category = "Combat", effectName = "Sword_Hit",
				options = { duration = 1.0, transparent = true } },
		},
		Storm = {
			{ marker = "Swing",  category = "Combat", effectName = "Sword_Swing_Heavy",
				options = { duration = 0.7, transparent = true } },
			{ marker = "Impact", category = "Combat", effectName = "Sword_Impact",
				options = { duration = 0.4, transparent = true } },
			{ marker = "Hit",    category = "Combat", effectName = "Sword_Hit",
				options = { duration = 1.5, transparent = true } },
		},
	},
}

-- ============================================================
-- FEEDBACK EVENT EFFECTS
-- Played in CombatClient when CombatFeedback arrives from server.
-- "screen" field means PlayScreenEffect is also called.
-- ============================================================
CombatVFXConfig.FeedbackEffects = {

	-- Received when YOU successfully parried an attack.
	ParrySuccess = {
		world  = { category = "Combat", effectName = "Parry_Flash",  options = { duration = 1.0, transparent = true } },
		screen = "parry",
	},

	-- Received when your attack was parried by the opponent.
	ParriedByOpponent = {
		screen = "damage",
	},

	-- Received when a hit landed on a blocking target.
	BlockHit = {
		world  = { category = "Combat", effectName = "Block_Spark",  options = { duration = 0.8, transparent = true } },
	},

	-- Received when your block was broken.
	GuardBroken = {
		world  = { category = "Combat", effectName = "Guard_Break",  options = { duration = 1.2, transparent = true } },
		screen = "guardbreak",
	},

	-- Received when your attack connected with a full hit on the enemy.
	HitConnected = {
		world  = { category = "Combat", effectName = "Generic_Hit",  options = { duration = 1.5, transparent = true } },
	},

	-- Received when YOU were hit (played on the target's client).
	YouWereHit = {
		screen = "damage",
	},
}

-- ============================================================
-- HELPERS
-- ============================================================

-- Returns the marker binding list for a weapon/style combo.
-- Falls back to the weapon's Default if the specific style has no entry.
function CombatVFXConfig.GetMarkers(weaponType, styleName)
	local wt = CombatVFXConfig.AttackMarkers[weaponType]
	if not wt then return {} end
	return wt[styleName] or wt["Default"] or {}
end

-- Returns the feedback VFX config for a given event type.
function CombatVFXConfig.GetFeedback(eventType)
	return CombatVFXConfig.FeedbackEffects[eventType]
end

return CombatVFXConfig