-- @ScriptType: ModuleScript
-- @ScriptType: ModuleScript
-- ============================================================
--  SoundUtil.lua  |  ModuleScript
--  Location: ReplicatedStorage/Modules/SoundUtil
--
--  CHANGES:
--    Added FALLBACK_SOUNDS — centralised fallback IDs for every
--    generic combat sound.  Fill these in with your actual asset
--    IDs; leave as "rbxassetid://0" to silence that slot.
--
--    Added helper functions that check the style module's
--    optional sounds table first, then fall back to FALLBACK_SOUNDS:
--      SoundUtil.PlayHit(root, style?)
--      SoundUtil.PlaySwing(root, style?)
--      SoundUtil.PlayParryClash(root)
--      SoundUtil.PlayBlockHit(root)
--
--    Style modules may now include an optional `sounds` table:
--      sounds = {
--        hitId   = "rbxassetid://XXXX",   -- overrides generic hit
--        swingId = "rbxassetid://XXXX",   -- overrides generic swing
--      }
--    Any field that is absent or "rbxassetid://0" falls back to
--    the centralized FALLBACK_SOUNDS below.
--
--  CombatData.GetSounds() is no longer needed and can be removed.
-- ============================================================

local Debris = game:GetService("Debris")
local SoundUtil = {}

-- ============================================================
-- FALLBACK SOUNDS
-- Replace each "rbxassetid://0" with your actual sound asset ID.
-- These are played whenever a style module does not provide its own.
-- ============================================================
local FALLBACK = {
	hitId        = "rbxassetid://0",   -- generic melee impact
	swingId      = "rbxassetid://0",   -- generic weapon whoosh
	parryClashId = "rbxassetid://0",   -- metallic ring on successful parry
	blockHitId   = "rbxassetid://0",   -- thud when a blocked hit lands
}

-- ── Default playback properties ───────────────────────────────
local DEFAULTS = {
	Volume             = 0.85,
	RollOffMaxDistance = 60,
	RollOffMode        = Enum.RollOffMode.Linear,
}

-- ============================================================
-- INTERNAL: play a single sound ID at a BasePart or Attachment
-- ============================================================
local function _play(assetId, parent, overrides)
	if not assetId or assetId == "" or assetId == "rbxassetid://0" then return end
	if not parent  or not parent.Parent then return end
	local snd = Instance.new("Sound")
	snd.SoundId = assetId
	for k, v in pairs(DEFAULTS) do snd[k] = v end
	if overrides then for k, v in pairs(overrides) do snd[k] = v end end
	snd.Parent = parent
	snd:Play()
	Debris:AddItem(snd, math.max(snd.TimeLength + 0.5, 5))
end

-- ============================================================
-- PUBLIC: generic one-shot play (unchanged from original)
-- ============================================================
function SoundUtil.Play(assetId, parent, overrides)
	_play(assetId, parent, overrides)
end

-- ============================================================
-- PUBLIC: PlayHit
-- Plays the hit/impact sound.
-- style is optional — if it has sounds.hitId we use that first.
-- ============================================================
function SoundUtil.PlayHit(root, style)
	local id = (style and style.sounds
		and style.sounds.hitId
		and style.sounds.hitId ~= ""
		and style.sounds.hitId ~= "rbxassetid://0"
		and style.sounds.hitId)
		or FALLBACK.hitId
	_play(id, root)
end

-- ============================================================
-- PUBLIC: PlaySwing
-- Plays the weapon swing / whoosh sound.
-- style is optional.
-- ============================================================
function SoundUtil.PlaySwing(root, style)
	local id = (style and style.sounds
		and style.sounds.swingId
		and style.sounds.swingId ~= ""
		and style.sounds.swingId ~= "rbxassetid://0"
		and style.sounds.swingId)
		or FALLBACK.swingId
	_play(id, root)
end

-- ============================================================
-- PUBLIC: PlayParryClash
-- Metallic ring played when a parry succeeds.
-- ============================================================
function SoundUtil.PlayParryClash(root)
	_play(FALLBACK.parryClashId, root)
end

-- ============================================================
-- PUBLIC: PlayBlockHit
-- Thud when an attack is blocked.
-- ============================================================
function SoundUtil.PlayBlockHit(root)
	_play(FALLBACK.blockHitId, root)
end

return SoundUtil