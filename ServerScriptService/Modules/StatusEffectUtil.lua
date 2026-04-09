-- @ScriptType: ModuleScript
-- @ScriptType: ModuleScript
-- ============================================================
--  StatusEffectUtil.lua  |  ModuleScript
--  Location: ServerScriptService/Modules/StatusEffectUtil
--
--  Modular, data-driven status effect system.
--  All effects live in the Effects table below.
--  CombatServer calls StatusEffectUtil.Apply() instead of the
--  old hardcoded applyStun() — the "Stunned" BoolValue is still
--  created for backward compatibility with CombatState checks.
--
--  ── HOW TO ADD A NEW EFFECT ─────────────────────────────────
--  Add an entry to StatusEffectUtil.Effects with:
--    name           : string   — internal key and BoolValue name
--    walkSpeed      : number   — WalkSpeed during this effect (0 = immobile)
--    blocksAttack   : bool     — server rejects attack remotes
--    blocksBlock    : bool     — server rejects block remotes
--    canEvasiveDash : bool     — evasive dash can cancel this effect
--    onApply(char, dur)         — called when effect first applies
--    onRemove(char)             — called when effect expires or is cleared
--
--  The boolValueName drives everything:
--    "Stunned"        — existing CombatState / CombatServer checks still work
--    "SoftKnockdown"  — checked by KnockdownUtil / evasive dash
--    "HardKnockdown"  — checked by KnockdownUtil
-- ============================================================

local Debris  = game:GetService("Debris")
local Players = game:GetService("Players")

local StatusEffectUtil = {}

-- Default WalkSpeed restored when any effect ends.
-- Mirrors NORMAL_SPEED in CombatServer — keep in sync.
local NORMAL_SPEED = 16

-- ============================================================
-- EFFECT DEFINITIONS
-- ============================================================
StatusEffectUtil.Effects = {

	-- ── Hitstun ───────────────────────────────────────────────
	-- Standard hit-reaction CC.  Replaces old applyStun().
	-- Creates "Stunned" BoolValue for full backward compat.
	Hitstun = {
		name           = "Hitstun",
		boolValueName  = "Stunned",
		walkSpeed      = 0,        -- fully immobilised
		blocksAttack   = true,
		blocksBlock    = true,
		canEvasiveDash = false,
		onApply = function(char, _dur)
			local hum = char:FindFirstChildOfClass("Humanoid")
			if hum then hum.WalkSpeed = 0 end
		end,
		onRemove = function(char)
			local hum = char:FindFirstChildOfClass("Humanoid")
			if hum and hum.Parent then hum.WalkSpeed = NORMAL_SPEED end
		end,
	},

	-- ── SoftKnockdown ─────────────────────────────────────────
	-- Forced grounded state.  CAN be cancelled by evasive dash.
	-- KnockdownUtil fires a CharacterFeedback remote so the client
	-- can play the fall / ground animation.
	SoftKnockdown = {
		name           = "SoftKnockdown",
		boolValueName  = "SoftKnockdown",
		walkSpeed      = 0,
		blocksAttack   = true,
		blocksBlock    = true,
		canEvasiveDash = true,   -- ← evasive dash can cancel this
		onApply = function(char, _dur)
			local hum = char:FindFirstChildOfClass("Humanoid")
			if hum then hum.WalkSpeed = 0 end
		end,
		onRemove = function(char)
			local hum = char:FindFirstChildOfClass("Humanoid")
			if hum and hum.Parent then hum.WalkSpeed = NORMAL_SPEED end
		end,
	},

	-- ── HardKnockdown ─────────────────────────────────────────
	-- Heavy grounded state.  CANNOT be cancelled by evasive dash.
	HardKnockdown = {
		name           = "HardKnockdown",
		boolValueName  = "HardKnockdown",
		walkSpeed      = 0,
		blocksAttack   = true,
		blocksBlock    = true,
		canEvasiveDash = false,  -- ← evasive dash does NOT cancel this
		onApply = function(char, _dur)
			local hum = char:FindFirstChildOfClass("Humanoid")
			if hum then hum.WalkSpeed = 0 end
		end,
		onRemove = function(char)
			local hum = char:FindFirstChildOfClass("Humanoid")
			if hum and hum.Parent then hum.WalkSpeed = NORMAL_SPEED end
		end,
	},
}

-- ── Active task handles ───────────────────────────────────────
-- [characterModel] = { [effectName] = taskHandle }
local activeTasks = {}

-- ============================================================
-- PUBLIC API
-- ============================================================

-- Apply (or refresh) a status effect on a character.
-- duration: seconds; pass math.huge for a permanent effect
--           (you must call Remove() manually).
function StatusEffectUtil.Apply(character, effectName, duration)
	if not character or not character.Parent then return end
	local def = StatusEffectUtil.Effects[effectName]
	if not def then
		warn("[StatusEffectUtil] Unknown effect:", effectName)
		return
	end

	-- Cancel any running expiry task for this effect.
	if not activeTasks[character] then activeTasks[character] = {} end
	local existing = activeTasks[character][effectName]
	if existing then
		task.cancel(existing)
		activeTasks[character][effectName] = nil
	end

	-- Remove any existing BoolValue before re-creating.
	local oldBool = character:FindFirstChild(def.boolValueName)
	if oldBool then oldBool:Destroy() end

	-- Create the BoolValue tag.
	local bool      = Instance.new("BoolValue")
	bool.Name       = def.boolValueName
	bool.Parent     = character
	-- We manage lifetime via task.delay, NOT Debris, so we can cancel it.

	-- Call the effect's onApply callback.
	def.onApply(character, duration)

	-- Schedule automatic removal.
	if duration and duration < math.huge then
		activeTasks[character][effectName] = task.delay(duration, function()
			StatusEffectUtil.Remove(character, effectName)
		end)
	end
end

-- Remove a status effect before its natural expiry.
-- Safe to call even if the effect isn't active.
function StatusEffectUtil.Remove(character, effectName)
	if not character then return end
	local def = StatusEffectUtil.Effects[effectName]
	if not def then return end

	-- Cancel expiry task.
	if activeTasks[character] and activeTasks[character][effectName] then
		--task.cancel(activeTasks[character][effectName])
		activeTasks[character][effectName] = nil
	end

	-- Destroy the BoolValue.
	local bool = character:FindFirstChild(def.boolValueName)
	if bool then bool:Destroy() end

	-- Restore character if it still exists.
	if character.Parent then
		def.onRemove(character)
	end
end

-- Returns true if the character currently has this effect.
function StatusEffectUtil.Has(character, effectName)
	if not character then return false end
	local def = StatusEffectUtil.Effects[effectName]
	if not def then return false end
	return character:FindFirstChild(def.boolValueName) ~= nil
end

-- Returns true if the character is blocked from attacking
-- by ANY active effect.
function StatusEffectUtil.BlocksAttack(character)
	for _, def in pairs(StatusEffectUtil.Effects) do
		if def.blocksAttack and character:FindFirstChild(def.boolValueName) then
			return true
		end
	end
	return false
end

-- Returns true if the character can be cancelled into an evasive dash
-- (i.e. they have an effect with canEvasiveDash = true, and NO effect
-- that prevents it, such as HardKnockdown).
function StatusEffectUtil.CanEvasiveDash(character)
	local hasEvasible   = false
	local hasAntiEvasive= false
	for _, def in pairs(StatusEffectUtil.Effects) do
		if character:FindFirstChild(def.boolValueName) then
			if def.canEvasiveDash     then hasEvasible    = true end
			if def.canEvasiveDash == false and def.blocksAttack then
				-- An active effect that blocks attacks and prevents dash
				hasAntiEvasive = true
			end
		end
	end
	-- Can dash only if something evasible is active AND nothing blocks it.
	return hasEvasible and not hasAntiEvasive
end

-- Remove ALL active effects from a character (called on death or respawn).
function StatusEffectUtil.ClearAll(character)
	if not character then return end
	for effectName, _ in pairs(StatusEffectUtil.Effects) do
		StatusEffectUtil.Remove(character, effectName)
	end
	activeTasks[character] = nil
end

-- Clean up state when a character is destroyed (e.g. on player leave).
function StatusEffectUtil.OnCharacterRemoving(character)
	activeTasks[character] = nil
end

-- Backward-compat alias used by CombatState.ClearBlockOnStun.
-- "Stunned" BoolValue is created by Apply("Hitstun"), so existing
-- checks for FindFirstChild("Stunned") continue to work.

return StatusEffectUtil