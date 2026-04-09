-- @ScriptType: ModuleScript
-- @ScriptType: ModuleScript
-- ============================================================
--  VFXUtil.lua  |  ModuleScript
--  Location: ReplicatedStorage/Modules/VFXUtil
--
--  Client-side modular VFX system.  Require from LocalScripts only.
--
--  ── Effects folder layout ───────────────────────────────────
--    ReplicatedStorage/
--      Effects/
--        Combat/
--          Fist_Hit        Part  (with ParticleEmitter children)
--          Fist_Swing      Part
--          Sword_Hit       Part
--          Sword_Swing     Part
--          Parry_Flash     Part
--          Guard_Break     Part
--          Block_Spark     Part
--        Environment/
--          ...
--
--  Each effect template is a BasePart.
--    • ParticleEmitter children are used for burst / loop emission.
--    • Optional SpecialMesh, BillboardGui, Beam can also live here.
--    • Per-emitter `EmitCount` NumberAttribute overrides the default.
--
--  ── API ─────────────────────────────────────────────────────
--
--  VFXUtil.Play(category, effectName, target, options?)
--    Clones the effect and plays it at / on the target.
--    target  : BasePart  → positioned at that part's CFrame
--              CFrame    → positioned at that CFrame
--              Vector3   → positioned at that world position
--    options : {
--      duration  = 2,          -- seconds before destroying the clone
--      weld      = false,      -- weld clone to a BasePart target (moves with it)
--      offset    = CFrame.new(), -- local CFrame offset from target
--      loop      = false,      -- enable emitters continuously (instead of burst)
--      emitCount = nil,        -- override per-emitter EmitCount
--      transparent = false,    -- set clone transparency to 1 (invisible base part)
--    }
--    Returns: the cloned Part (or nil if template not found).
--
--  VFXUtil.BindMarker(track, markerName, category, effectName, getTargetFn, options?)
--    Connects an AnimationTrack KeyframeMarker signal to a VFX play.
--    track       : AnimationTrack
--    markerName  : the KeyframeMarker name added in the Animation Editor
--    getTargetFn : function() → BasePart | CFrame | Vector3
--    Returns: RBXScriptConnection (disconnect to stop listening).
--
--  VFXUtil.BindAllMarkers(track, bindings)
--    Convenience wrapper for multiple BindMarker calls.
--    bindings: { { markerName, category, effectName, getTargetFn, options }, ... }
--    Returns: table of connections.
--
--  VFXUtil.PlayScreenEffect(effectType, duration?)
--    Plays a quick full-screen ColorCorrection flash.
--    effectType: "parry" | "damage" | "guardbreak"
--    Useful for local hit-feedback that doesn't need a world position.
-- ============================================================

local Debris     = game:GetService("Debris")
local TweenService = game:GetService("TweenService")
local Players    = game:GetService("Players")
local RS         = game:GetService("ReplicatedStorage")

local VFXUtil    = {}
local player     = Players.LocalPlayer
local camera     = workspace.CurrentCamera

-- Wait for the effects root (non-blocking wait avoids deadlocks).
local effectsRoot
local function getEffectsRoot()
	if effectsRoot then return effectsRoot end
	effectsRoot = RS:WaitForChild("Effects", 10)
	return effectsRoot
end

-- ============================================================
-- INTERNAL: Locate a template
-- ============================================================
local function getTemplate(category, effectName)
	local root = getEffectsRoot()
	if not root then
		warn("[VFXUtil] ReplicatedStorage/Effects/ folder not found.")
		return nil
	end
	local cat = root:FindFirstChild(category)
	if not cat then
		warn("[VFXUtil] Category not found:", category,
			"— expected Effects/" .. category .. "/")
		return nil
	end
	local template = cat:FindFirstChild(effectName)
	if not template then
		warn("[VFXUtil] Effect not found:", effectName,
			"— expected Effects/" .. category .. "/" .. effectName)
		return nil
	end
	return template
end

-- ============================================================
-- INTERNAL: Position a clone
-- ============================================================
local function positionClone(clone, target, options)
	local cf
	if typeof(target) == "Instance" and target:IsA("BasePart") then
		cf = target.CFrame
	elseif typeof(target) == "CFrame" then
		cf = target
	elseif typeof(target) == "Vector3" then
		cf = CFrame.new(target)
	else
		cf = CFrame.new(0, 0, 0)
	end

	if options and options.offset then
		cf = cf * options.offset
	end

	if clone:IsA("BasePart") then
		clone.CFrame = cf
	elseif clone:IsA("Model") and clone.PrimaryPart then
		clone:PivotTo(cf)
	end
end

-- ============================================================
-- INTERNAL: Emit all ParticleEmitters in a clone (burst mode)
-- ============================================================
local function burstEmit(clone, emitCountOverride)
	-- Disable first so auto-emission doesn't fire on reparent.
	for _, pe in ipairs(clone:GetDescendants()) do
		if pe:IsA("ParticleEmitter") then
			pe.Enabled = false
		end
	end
	-- Then emit a controlled burst.
	for _, pe in ipairs(clone:GetDescendants()) do
		if pe:IsA("ParticleEmitter") then
			local count = emitCountOverride
				or pe:GetAttribute("EmitCount")
				or 12
			pe:Emit(count)
		end
	end
end

-- ============================================================
-- VFXUtil.Play
-- ============================================================
function VFXUtil.Play(category, effectName, target, options)
	local template = getTemplate(category, effectName)
	if not template then return nil end

	options = options or {}
	local duration     = options.duration    or 2
	local doWeld       = options.weld        == true
	local doLoop       = options.loop        == true
	local transparent  = options.transparent == true

	local clone = template:Clone()

	-- Make the base part invisible if requested.
	if transparent and clone:IsA("BasePart") then
		clone.Transparency = 1
	end

	-- Ensure the part doesn't collide with anything.
	if clone:IsA("BasePart") then
		clone.Anchored    = not doWeld  -- anchored unless welding
		clone.CanCollide  = false
		clone.CanTouch    = false
		clone.CanQuery    = false
	end

	positionClone(clone, target, options)

	-- Weld to a moving BasePart target.
	if doWeld and typeof(target) == "Instance" and target:IsA("BasePart") then
		clone.Anchored = false
		local w = Instance.new("WeldConstraint")
		w.Part0 = clone
		w.Part1 = target
		w.Parent = clone
	end

	clone.Parent = workspace

	if doLoop then
		-- Loop mode: enable emitters and let them run.
		for _, pe in ipairs(clone:GetDescendants()) do
			if pe:IsA("ParticleEmitter") then pe.Enabled = true end
		end
		-- After duration, disable emitters and wait for particles to die.
		task.delay(duration, function()
			if not clone or not clone.Parent then return end
			for _, pe in ipairs(clone:GetDescendants()) do
				if pe:IsA("ParticleEmitter") then pe.Enabled = false end
			end
			Debris:AddItem(clone, 2)   -- 2 s for in-flight particles to vanish
		end)
	else
		-- Burst mode: one-shot emission.
		burstEmit(clone, options.emitCount)
		Debris:AddItem(clone, duration)
	end

	return clone
end

-- ============================================================
-- VFXUtil.BindMarker
-- ============================================================
function VFXUtil.BindMarker(track, markerName, category, effectName, getTargetFn, options)
	return track:GetMarkerReachedSignal(markerName):Connect(function()
		local target = getTargetFn and getTargetFn()
		VFXUtil.Play(category, effectName, target, options)
	end)
end

-- ============================================================
-- VFXUtil.BindAllMarkers
-- ============================================================
function VFXUtil.BindAllMarkers(track, bindings)
	local connections = {}
	for _, b in ipairs(bindings) do
		-- b = { markerName, category, effectName, getTargetFn, options }
		local conn = VFXUtil.BindMarker(
			track, b[1], b[2], b[3], b[4], b[5]
		)
		table.insert(connections, conn)
	end
	return connections
end

-- ============================================================
-- VFXUtil.PlayScreenEffect
-- A lightweight full-screen color flash — no world position needed.
-- effectType: "parry" | "damage" | "guardbreak" | "heal"
-- ============================================================
local screenEffectConfigs = {
	parry      = { Color = Color3.fromRGB(180, 220, 255), Brightness = 0.6,  Saturation = 0.2  },
	damage     = { Color = Color3.fromRGB(255,  60,  60), Brightness = -0.1, Saturation = 0.4  },
	guardbreak = { Color = Color3.fromRGB(255, 160,  40), Brightness = 0.4,  Saturation = 0.3  },
	heal       = { Color = Color3.fromRGB( 60, 200, 100), Brightness = 0.3,  Saturation = 0.2  },
}

function VFXUtil.PlayScreenEffect(effectType, duration)
	local cfg = screenEffectConfigs[effectType]
	if not cfg then return end
	duration = duration or 0.3

	-- Create a ColorCorrection in Lighting (or camera).
	local cc = Instance.new("ColorCorrectionEffect")
	cc.TintColor  = cfg.Color
	cc.Brightness = cfg.Brightness
	cc.Saturation = cfg.Saturation
	cc.Parent      = camera

	-- Fade out.
	TweenService:Create(cc, TweenInfo.new(duration, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Brightness = 0,
		Saturation = 0,
		TintColor  = Color3.new(1, 1, 1),
	}):Play()

	Debris:AddItem(cc, duration + 0.1)
end

return VFXUtil