-- @ScriptType: ModuleScript
-- ============================================================
--  SoundUtil.lua  |  ModuleScript
--  Location: ReplicatedStorage/Modules/SoundUtil
--
--  Plays a sound at a BasePart by asset ID without requiring
--  pre-baked Sound children in every script.
--  Works on both the server and any LocalScript.
--
--  Usage:
--    local SoundUtil = require(RS.Modules.SoundUtil)
--    SoundUtil.Play("rbxassetid://12345", somePart)
--    SoundUtil.Play("rbxassetid://12345", somePart, { Volume = 0.8, RollOffMaxDistance = 40 })
-- ============================================================

local Debris  = game:GetService("Debris")

local SoundUtil = {}

-- Default properties applied to every sound unless overridden.
local DEFAULTS = {
	Volume              = 0.85,
	RollOffMaxDistance  = 60,
	RollOffMode         = Enum.RollOffMode.Linear,
}

-- Plays a sound at `parent` (must be a BasePart or Attachment).
-- `overrides` is an optional table of Sound property overrides.
-- The Sound is destroyed as soon as it finishes playing (or after maxLife
-- seconds as a safety cap so orphaned sounds never linger).
function SoundUtil.Play(assetId, parent, overrides)
	if not assetId or assetId == "" then return end
	if not parent  or not parent.Parent then return end

	local snd = Instance.new("Sound")
	snd.SoundId = assetId

	-- Apply defaults then any caller overrides.
	for k, v in pairs(DEFAULTS) do snd[k] = v end
	if overrides then
		for k, v in pairs(overrides) do snd[k] = v end
	end

	snd.Parent = parent
	snd:Play()

	-- Destroy after playback. TimeLength is 0 until the sound has loaded;
	-- give it a moment then check, falling back to a 5-second cap.
	local maxLife = math.max(snd.TimeLength + 0.5, 5)
	Debris:AddItem(snd, maxLife)
end


return SoundUtil