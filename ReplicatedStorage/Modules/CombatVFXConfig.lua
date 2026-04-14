-- @ScriptType: ModuleScript
-- @ScriptType: ModuleScript
-- ============================================================
--  CombatVFXConfig.lua  |  ModuleScript
--  Location: ReplicatedStorage/Modules/CombatVFXConfig
--
--  Declarative map from animation markers → VFX bursts.
--  Read by CombatClient to fire VFXUtil.Play() when a
--  KeyframeMarker fires during an attack animation.
--
--  ── Marker entry fields ──────────────────────────────────────
--  marker  : string — name of the KeyframeMarker in the animation
--  vfxPath : string — path under ReplicatedStorage/VisualEffects/
--                     e.g. "Combat/Sword_Swing"
--  amounts : table  — { ["1"] = emitCount, ["2"] = emitCount, … }
--                     keys match the numbered children inside the
--                     VFX folder (see VFXUtil for folder layout)
--
--  ── Feedback event entries ───────────────────────────────────
--  Used in CombatClient's CombatFX / CombatFeedback handlers.
--  vfxPath + amounts for world effects; screen for screen-flash.
--
--  ── How to add a new weapon/style ───────────────────────────
--  1. Create the VFX folder in RS/VisualEffects/Combat/YourEffect/
--     and add numbered Part/Attachment children with ParticleEmitters.
--  2. Add an entry to AttackMarkers[weaponType][styleName].
--  3. Add a KeyframeMarker with the same name in the animation.
-- ============================================================

local CombatVFXConfig = {}

-- ============================================================
-- ATTACK ANIMATION MARKERS
-- CombatClient connects to each marker signal on the track and
-- calls VFXUtil.Play(vfxPath, amounts, attackerHRP).
-- ============================================================
CombatVFXConfig.AttackMarkers = {

	Fist = {
		Default = {
			{
				marker  = "Swing",
				vfxPath = "Combat/Fist_Swing",
				amounts = { ["1"] = 8, ["2"] = 5 },
			},
			{
				marker  = "Impact",
				vfxPath = "Combat/Fist_Impact",
				amounts = { ["1"] = 12 },
			},
			{
				marker  = "Hit",
				vfxPath = "Combat/Fist_Hit",
				amounts = { ["1"] = 15, ["2"] = 8 },
			},
		},
	},

	Sword = {
		Default = {
			{
				marker  = "Swing",
				vfxPath = "Combat/Sword_Swing",
				amounts = { ["1"] = 10, ["2"] = 6 },
			},
			{
				marker  = "Impact",
				vfxPath = "Combat/Sword_Impact",
				amounts = { ["1"] = 14 },
			},
			{
				marker  = "Hit",
				vfxPath = "Combat/Sword_Hit",
				amounts = { ["1"] = 18, ["2"] = 10 },
			},
		},
		Flowing = {
			{
				marker  = "Swing",
				vfxPath = "Combat/Sword_Swing_Light",
				amounts = { ["1"] = 7, ["2"] = 4 },
			},
			{
				marker  = "Impact",
				vfxPath = "Combat/Sword_Impact",
				amounts = { ["1"] = 10 },
			},
			{
				marker  = "Hit",
				vfxPath = "Combat/Sword_Hit",
				amounts = { ["1"] = 14, ["2"] = 8 },
			},
		},
		Storm = {
			{
				marker  = "Swing",
				vfxPath = "Combat/Sword_Swing_Heavy",
				amounts = { ["1"] = 14, ["2"] = 8 },
			},
			{
				marker  = "Impact",
				vfxPath = "Combat/Sword_Impact",
				amounts = { ["1"] = 18 },
			},
			{
				marker  = "Hit",
				vfxPath = "Combat/Sword_Hit",
				amounts = { ["1"] = 22, ["2"] = 12 },
			},
		},
	},

	Greatsword = {
		Default = {
			{
				marker  = "Swing",
				vfxPath = "Combat/Greatsword_Swing",
				amounts = { ["1"] = 14, ["2"] = 8 },
			},
			{
				marker  = "Impact",
				vfxPath = "Combat/Greatsword_Impact",
				amounts = { ["1"] = 20 },
			},
			{
				marker  = "Hit",
				vfxPath = "Combat/Greatsword_Hit",
				amounts = { ["1"] = 24, ["2"] = 14 },
			},
		},
	},

	Staff = {
		["Mad Monk"] = {
			{
				marker  = "Swing",
				vfxPath = "Combat/Staff_Swing",
				amounts = { ["1"] = 9, ["2"] = 5 },
			},
			{
				marker  = "Impact",
				vfxPath = "Combat/Staff_Impact",
				amounts = { ["1"] = 13 },
			},
			{
				marker  = "Hit",
				vfxPath = "Combat/Staff_Hit",
				amounts = { ["1"] = 16, ["2"] = 9 },
			},
		},
	},

	Qiang = {
		["Qiang Shu"] = {
			{
				marker  = "Swing",
				vfxPath = "Combat/Qiang_Swing",
				amounts = { ["1"] = 9, ["2"] = 5 },
			},
			{
				marker  = "Impact",
				vfxPath = "Combat/Qiang_Impact",
				amounts = { ["1"] = 13 },
			},
			{
				marker  = "Hit",
				vfxPath = "Combat/Qiang_Hit",
				amounts = { ["1"] = 16, ["2"] = 9 },
			},
		},
	},
}

-- ============================================================
-- FEEDBACK EVENT EFFECTS
-- Played in CombatClient when CombatFX / CombatFeedback fires.
--
-- world  : { vfxPath, amounts }  — spawned at the event position
-- screen : string                — passed to VFXUtil.PlayScreenEffect
-- ============================================================
CombatVFXConfig.FeedbackEffects = {

	ParrySuccess = {
		world  = { vfxPath = "Combat/Parry_Flash",  amounts = { ["1"] = 20, ["2"] = 10 } },
		screen = "parry",
	},

	ParriedByOpponent = {
		screen = "damage",
	},

	BlockHit = {
		world  = { vfxPath = "Combat/Block_Spark",  amounts = { ["1"] = 14 } },
	},

	GuardBroken = {
		world  = { vfxPath = "Combat/Guard_Break",  amounts = { ["1"] = 18, ["2"] = 10 } },
		screen = "guardbreak",
	},

	HitConnected = {
		world  = { vfxPath = "Combat/Generic_Hit",  amounts = { ["1"] = 16, ["2"] = 8 } },
	},

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