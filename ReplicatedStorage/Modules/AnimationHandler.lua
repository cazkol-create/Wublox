-- @ScriptType: ModuleScript
-- @ScriptType: ModuleScript
-- ============================================================
--  AnimationHandler.lua  |  ModuleScript
--  Location: ReplicatedStorage/Modules/AnimationHandler
--
--  Wraps an Animator and tracks playing tracks by "group".
--  Playing a new animation in the same group automatically stops
--  the previous one, preventing overlap without manual track
--  management in every script.
--
--  Groups used by CombatClient:
--    "Attack"   — M1, M2, M3, M4, Heavy
--    "Block"    — Block
--    "Idle"     — Idle (looping base pose)
--    "Equip"    — Drawing
--    "Knockdown"— knockdown/getup animations
--    "Skill"    — skill animations
--
--  Usage:
--    local AnimationHandler = require(RS.Modules.AnimationHandler)
--    local handler = AnimationHandler.new(animator)
--    handler:Play("Attack", track)        -- stops current "Attack" first
--    handler:Stop("Block")                -- stop the "Block" group
--    handler:StopAll()                    -- stop everything
--    handler:IsPlaying("Idle")            -- boolean
-- ============================================================

local AnimationHandler = {}
AnimationHandler.__index = AnimationHandler

function AnimationHandler.new(animator)
	local self = setmetatable({}, AnimationHandler)
	self._animator = animator
	self._tracks   = {}   -- [group] = AnimationTrack
	return self
end

-- ── Play ─────────────────────────────────────────────────────
-- Stops the current track in `group`, then plays `track`.
-- fadeTime: blend time for both stop and play (default 0.1).
-- Returns the track so callers can connect Stopped if needed.
function AnimationHandler:Play(group, track, fadeTime)
	if not track then return nil end
	fadeTime = fadeTime or 0.1

	local current = self._tracks[group]
	if current and current ~= track then
		if current.IsPlaying then current:Stop(fadeTime) end
	end

	self._tracks[group] = track
	if not track.IsPlaying then
		track:Play(fadeTime)
	end
	return track
end

-- ── Stop ─────────────────────────────────────────────────────
function AnimationHandler:Stop(group, fadeTime)
	fadeTime = fadeTime or 0.1
	local track = self._tracks[group]
	if track and track.IsPlaying then
		track:Stop(fadeTime)
	end
	self._tracks[group] = nil
end

-- ── StopAll ───────────────────────────────────────────────────
function AnimationHandler:StopAll(fadeTime)
	fadeTime = fadeTime or 0.1
	for group, track in pairs(self._tracks) do
		if track and track.IsPlaying then track:Stop(fadeTime) end
	end
	self._tracks = {}
end

-- ── IsPlaying ─────────────────────────────────────────────────
function AnimationHandler:IsPlaying(group)
	local track = self._tracks[group]
	return track ~= nil and track.IsPlaying
end

-- ── GetTrack ──────────────────────────────────────────────────
function AnimationHandler:GetTrack(group)
	return self._tracks[group]
end

-- ── SwapTracks ────────────────────────────────────────────────
-- Destroys all old tracks and loads a new set from `trackMap`.
-- trackMap: { [name] = Animation object }
-- Returns a flat table of loaded AnimationTracks.
function AnimationHandler:SwapTracks(trackMap)
	self:StopAll(0)
	-- Destroy old tracks.
	if self._loadedTracks then
		for _, t in pairs(self._loadedTracks) do pcall(t.Destroy, t) end
	end
	self._tracks = {}

	local loaded = {}
	for name, anim in pairs(trackMap) do
		if anim then
			local ok, track = pcall(function()
				return self._animator:LoadAnimation(anim)
			end)
			if ok and track then
				loaded[name] = track
			end
		end
	end
	self._loadedTracks = loaded
	return loaded
end

return AnimationHandler