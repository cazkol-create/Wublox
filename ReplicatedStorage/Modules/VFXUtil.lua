-- @ScriptType: ModuleScript
-- @ScriptType: ModuleScript
-- ============================================================
--  VFXUtil.lua  |  ModuleScript
--  Location: ReplicatedStorage/Modules/VFXUtil
--
--  Particle-based VFX system.
--
--  ── Folder layout in ReplicatedStorage ──────────────────────
--  ReplicatedStorage
--  └─ VisualEffects
--     └─ Combat
--        └─ Sword_Swing          ← vfxPath = "Combat/Sword_Swing"
--           ├─ 1                 ← Part/Attachment containing ParticleEmitters
--           └─ 2                 ← another particle setup
--
--  Each numbered child is a Part or Attachment that holds one
--  or more ParticleEmitter objects.  The name is the index key
--  used in the `amounts` table when calling Play().
--
--  ── API ─────────────────────────────────────────────────────
--
--  VFXUtil.Play(vfxPath, amounts, cframe)
--    One-shot burst.  Clones each indexed child from the VFX
--    folder, positions it at `cframe`, emits the given particle
--    counts, then cleans up automatically after the longest
--    particle lifetime expires.
--
--    vfxPath : string — path under VisualEffects, e.g. "Combat/Sword_Swing"
--              OR an Instance reference to the folder directly.
--    amounts : table  — maps child index (string or number) → emit count
--              e.g. { ["1"] = 12, ["2"] = 6 }
--    cframe  : CFrame | BasePart | nil — where to spawn the effect.
--              If a BasePart, uses its CFrame at call time.
--
--  VFXUtil.PlayPersistent(vfxPath, attachTo)
--    Continuously-emitting effect welded to a BasePart (auras,
--    persistent buffs, etc.).  All emitters start enabled.
--    Returns a STOP function — call it when you want the effect
--    to end.  Emitters are disabled first so existing particles
--    fade out naturally, then the clones are destroyed.
--
--    vfxPath  : string | Instance
--    attachTo : BasePart — the part to parent the clones into
--    returns  : () → ()   stop function
-- ============================================================

local RS = game:GetService("ReplicatedStorage")

local VFXUtil = {}

-- ── Root folder ───────────────────────────────────────────────
local visualEffectsRoot = RS:WaitForChild("VisualEffects", 10)

-- ── Max seconds to wait for lingering particles before force-destroy ─
local CLEANUP_BUFFER = 0.5

-- ============================================================
-- INTERNAL: resolve a string path or Instance into a folder
-- ============================================================
local function resolvePath(vfxPath)
	if typeof(vfxPath) == "Instance" then
		return vfxPath
	end
	if typeof(vfxPath) == "string" and visualEffectsRoot then
		local current = visualEffectsRoot
		for segment in vfxPath:gmatch("[^/]+") do
			if not current then return nil end
			current = current:FindFirstChild(segment)
		end
		return current
	end
	return nil
end

-- ── Resolve a CFrame from various input types ─────────────────
local function resolveCFrame(cframe)
	if typeof(cframe) == "CFrame" then
		return cframe
	elseif typeof(cframe) == "Instance" and cframe:IsA("BasePart") then
		return cframe.CFrame
	end
	return CFrame.new(0, 0, 0)
end

-- ── Walk all ParticleEmitters inside a cloned object ──────────
local function iterEmitters(obj, fn)
	if obj:IsA("ParticleEmitter") then
		fn(obj)
	end
	for _, desc in ipairs(obj:GetDescendants()) do
		if desc:IsA("ParticleEmitter") then
			fn(desc)
		end
	end
end

-- ── Get the longest particle lifetime in an object ───────────
local function maxLifetime(obj)
	local max = 1
	iterEmitters(obj, function(pe)
		local lt = pe.Lifetime
		local hi = typeof(lt) == "NumberRange" and lt.Max or 1
		if hi > max then max = hi end
	end)
	return max
end

-- ============================================================
-- PUBLIC: Play  (one-shot burst)
-- ============================================================
function VFXUtil.Play(vfxPath, amounts, cframe)
	local folder = resolvePath(vfxPath)
	if not folder then
		warn("[VFXUtil] VFX path not found:", tostring(vfxPath))
		return
	end

	-- Host part: invisible anchor in the world
	local host        = Instance.new("Part")
	host.Name         = "VFX_Host"
	host.Anchored     = true
	host.CanCollide   = false
	host.CanTouch     = false
	host.CanQuery     = false
	host.CastShadow   = false
	host.Transparency = 1
	host.Size         = Vector3.new(0.05, 0.05, 0.05)
	host.CFrame       = resolveCFrame(cframe)
	host.Parent       = workspace

	local longestLife = 1

	-- Clone each indexed child specified in `amounts`
	for indexKey, emitCount in pairs(amounts) do
		local source = folder:FindFirstChild(tostring(indexKey))
		if not source then
			warn("[VFXUtil] Index", tostring(indexKey), "not found in", folder:GetFullName())
			continue
		end

		local clone  = source:Clone()
		clone.Parent = host

		-- Track max lifetime for cleanup
		local life = maxLifetime(clone)
		if life > longestLife then longestLife = life end

		-- Disable auto-emission then burst
		iterEmitters(clone, function(pe)
			pe.Enabled = false
			pe:Emit(emitCount)
		end)
	end

	-- Destroy host after particles have had time to die
	task.delay(longestLife + CLEANUP_BUFFER, function()
		if host and host.Parent then
			host:Destroy()
		end
	end)
end

-- ============================================================
-- PUBLIC: PlayPersistent  (continuous aura / buff)
-- ============================================================
-- Returns a stop() function.  Calling it disables all emitters
-- so existing particles finish their lifetime, then destroys
-- the clones after the longest lifetime has passed.
function VFXUtil.PlayPersistent(vfxPath, attachTo)
	local noOp = function() end

	local folder = resolvePath(vfxPath)
	if not folder then
		warn("[VFXUtil] VFX path not found:", tostring(vfxPath))
		return noOp
	end
	if not attachTo or not attachTo.Parent then
		return noOp
	end

	local clones     = {}
	local longestLife = 1
	local stopped    = false

	-- Clone every child of the folder so all indexed variants are active
	for _, child in ipairs(folder:GetChildren()) do
		local clone  = child:Clone()
		clone.Parent = attachTo
		table.insert(clones, clone)

		local life = maxLifetime(clone)
		if life > longestLife then longestLife = life end

		-- Enable all emitters
		iterEmitters(clone, function(pe)
			pe.Enabled = true
		end)
	end

	-- Stop function
	return function()
		if stopped then return end
		stopped = true

		for _, clone in ipairs(clones) do
			if clone and clone.Parent then
				-- Disable emitters; let existing particles die naturally
				iterEmitters(clone, function(pe)
					pe.Enabled = false
				end)
				-- Destroy after fade-out
				local capturedClone = clone
				task.delay(longestLife + CLEANUP_BUFFER, function()
					if capturedClone and capturedClone.Parent then
						capturedClone:Destroy()
					end
				end)
			end
		end

		clones = {}
	end
end

return VFXUtil