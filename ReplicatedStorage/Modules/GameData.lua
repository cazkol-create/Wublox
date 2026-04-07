-- @ScriptType: ModuleScript
-- ============================================================
--  GameData.lua  |  ModuleScript
--  Location: ReplicatedStorage/Modules/GameData
--  Shared constants for the entire game.
-- ============================================================

local GameData = {}

-- ============================================================
-- CULTIVATION REALMS
-- Each realm has a display name, qi thresholds, and a tier
-- (tier gates sect perks, ability unlocks, etc.)
-- ============================================================
GameData.CultivationRealms = {
	[1]  = { name = "Mortal",             minQi = 0,        maxQi = 99,       tier = 0 },
	[2]  = { name = "Body Tempering",     minQi = 100,      maxQi = 499,      tier = 1 },
	[3]  = { name = "Qi Condensation",    minQi = 500,      maxQi = 1999,     tier = 1 },
	[4]  = { name = "Foundation Est.",    minQi = 2000,     maxQi = 7999,     tier = 2 },
	[5]  = { name = "Core Formation",     minQi = 8000,     maxQi = 29999,    tier = 2 },
	[6]  = { name = "Nascent Soul",       minQi = 30000,    maxQi = 99999,    tier = 3 },
	[7]  = { name = "Spirit Severance",   minQi = 100000,   maxQi = 349999,   tier = 3 },
	[8]  = { name = "Void Tribulation",   minQi = 350000,   maxQi = 999999,   tier = 4 },
	[9]  = { name = "Dao Integration",    minQi = 1000000,  maxQi = 4999999,  tier = 4 },
	[10] = { name = "Immortal Ascension", minQi = 5000000,  maxQi = math.huge,tier = 5 },
}

-- BrickColor / highlight used on the player's character aura per realm
GameData.RealmAuraColor = {
	[1]  = Color3.fromRGB(180, 180, 180),   -- Mortal          (grey)
	[2]  = Color3.fromRGB(100, 220, 100),   -- Body Tempering  (green)
	[3]  = Color3.fromRGB(80,  160, 255),   -- Qi Condensation (blue)
	[4]  = Color3.fromRGB(180, 80,  255),   -- Foundation      (purple)
	[5]  = Color3.fromRGB(255, 200, 40),    -- Core Formation  (gold)
	[6]  = Color3.fromRGB(255, 120, 40),    -- Nascent Soul    (orange)
	[7]  = Color3.fromRGB(255, 50,  50),    -- Spirit Sev.     (red)
	[8]  = Color3.fromRGB(200, 50,  255),   -- Void Tribu.     (violet)
	[9]  = Color3.fromRGB(50,  220, 255),   -- Dao Integ.      (cyan)
	[10] = Color3.fromRGB(255, 255, 255),   -- Immortal        (white)
}

-- Base qi gained per meditate tick (scaled by realm tier in CultivationSystem)
GameData.BaseQiPerTick = 10

-- ============================================================
-- MORAL SYSTEM
-- Range: -100 (Pure Demonic) … 0 (Neutral) … 100 (Heavenly Saint)
-- ============================================================
GameData.MoralTiers = {
	{ name = "Heavenly Saint",    min =  81, max =  100, color = Color3.fromRGB(200, 220, 255) },
	{ name = "Righteous",         min =  31, max =   80, color = Color3.fromRGB(100, 150, 255) },
	{ name = "Neutral",           min = -30, max =   30, color = Color3.fromRGB(180, 180, 180) },
	{ name = "Unorthodox",        min = -80, max =  -31, color = Color3.fromRGB(255, 110,  50) },
	{ name = "Demonic Sovereign", min =-100, max =  -81, color = Color3.fromRGB(180,   0,   0) },
}

-- Moral delta per action (server calls MoralSystem.ApplyMoral(player, actionKey))
GameData.MoralActions = {
	KILL_INNOCENT           = -15,
	KILL_BANDIT             =   5,
	KILL_DEMON              =  10,
	KILL_RIGHTEOUS_PLAYER   = -20,
	KILL_CHAOTIC_PLAYER     =   8,
	KILL_NEUTRAL_PLAYER     =  -5,
	HELP_NPC                =   3,
	STEAL                   =  -5,
	DONATE_GOLD             =   2,
	COMPLETE_GOOD_QUEST     =   8,
	COMPLETE_EVIL_QUEST     =  -8,
	MEDITATE                =   1,   -- small virtue for disciplined cultivation
	BETRAY_SECT             = -12,
}

-- ============================================================
-- SECTS
-- alignment: "Righteous" | "Neutral" | "Chaotic"
-- allowedMoral: the moral range a player must be in to JOIN
-- benefits: flat multiplier bonuses applied on the server
-- requirements.minRealm: realmIndex gate
-- ============================================================
GameData.Sects = {
	{
		id          = "WANDERER",
		name        = "Wandering Cultivator",
		description = "No master, no shackles. Freedom is its own Dao.",
		alignment   = "Neutral",
		allowedMoral= { min = -100, max = 100 },
		color       = Color3.fromRGB(140, 140, 140),
		benefits    = { qiGainBonus = 0.00, goldBonus = 0.00 },
		requirements= { minRealm = 1 },
		tag         = "[Wanderer]",
	},
	{
		id          = "BEGGAR_SECT",
		name        = "Beggar Sect",
		description = "The largest sect in the land — no wealth, only brotherhood and iron fists.",
		alignment   = "Neutral",
		allowedMoral= { min = -20, max = 100 },
		color       = Color3.fromRGB(160, 120, 60),
		benefits    = { qiGainBonus = 0.05, socialBonus = 0.15 },
		requirements= { minRealm = 1, minMoral = -20 },
		tag         = "[Beggar]",
	},
	{
		id          = "ORTHODOX_SWORD",
		name        = "Orthodox Sword Sect",
		description = "Ancient swordsmen who uphold virtue above all. Qi flows like a pure river.",
		alignment   = "Righteous",
		allowedMoral= { min = 30, max = 100 },
		color       = Color3.fromRGB(80, 160, 255),
		benefits    = { qiGainBonus = 0.10, swordDamageBonus = 0.20 },
		requirements= { minRealm = 2, minMoral = 30 },
		tag         = "[Orthodox]",
	},
	{
		id          = "MURIM_ALLIANCE",
		name        = "Murim Alliance",
		description = "Governing body of all righteous cultivators. Wealthy, organised, and powerful.",
		alignment   = "Righteous",
		allowedMoral= { min = 20, max = 100 },
		color       = Color3.fromRGB(220, 200, 80),
		benefits    = { qiGainBonus = 0.08, resourceBonus = 0.25 },
		requirements= { minRealm = 3, minMoral = 20 },
		tag         = "[Murim]",
	},
	{
		id          = "BLOOD_SECT",
		name        = "Unorthodox Blood Sect",
		description = "Forbidden blood arts. Power through sacrifice. The righteous hunt you on sight.",
		alignment   = "Chaotic",
		allowedMoral= { min = -100, max = -20 },
		color       = Color3.fromRGB(180, 0, 0),
		benefits    = { qiGainBonus = 0.20, bloodArtBonus = 0.30 },
		requirements= { minRealm = 2, maxMoral = -20 },
		tag         = "[Blood]",
	},
	{
		id          = "SHADOW_GUILD",
		name        = "Shadow Assassin's Guild",
		description = "Killers for coin. No principles — only precision and profit.",
		alignment   = "Chaotic",
		allowedMoral= { min = -100, max = 10 },
		color       = Color3.fromRGB(50, 50, 70),
		benefits    = { qiGainBonus = 0.07, stealthBonus = 0.35 },
		requirements= { minRealm = 2, maxMoral = 10 },
		tag         = "[Shadow]",
	},
}

-- ============================================================
-- DEFAULT PLAYER SAVE DATA
-- ============================================================
GameData.DefaultPlayerData = {
	qi           = 0,
	realmIndex   = 1,
	moral        = 0,
	sectId       = "WANDERER",
	kills        = 0,
	deaths       = 0,
	gold         = 50,
	reputation   = 0,
	title        = "Mortal",
	meditating   = false,
	joinDate     = 0,
}

-- ============================================================
-- REMOTE EVENT / FUNCTION NAMES  (created at runtime)
-- ============================================================
GameData.Remotes = {
	-- FireServer (client → server)
	RequestMeditate     = "RequestMeditate",
	RequestJoinSect     = "RequestJoinSect",
	RequestLeaveSect    = "RequestLeaveSect",
	RequestMoralAction  = "RequestMoralAction",

	-- FireClient (server → client)
	UpdateHUD           = "UpdateHUD",
	Notify              = "Notify",
	RealmBreakthrough   = "RealmBreakthrough",
}

return GameData
