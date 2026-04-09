-- @ScriptType: ModuleScript
-- @ScriptType: ModuleScript
-- ============================================================
--  KnockdownUtil.lua  |  ModuleScript
--  Location: ServerScriptService/Modules/KnockdownUtil
--
--  Applies soft or hard knockdown to a character.
--  Soft knockdown:  can be cancelled by evasive dash.
--  Hard knockdown:  must wait out the full duration.
--
--  Both types:
--    • Apply a StatusEffect (SoftKnockdown / HardKnockdown)
--    • Set WalkSpeed = 0 during knockdown
--    • Fire CharacterFeedback remote to the affected client
--      so it can play the appropriate fall/stand animation.
--
--  ── Required animations in RS/Animations/Shared/ ────────────
--    SoftKnockdown_Fall   — triggered when soft knockdown starts
--    SoftKnockdown_Getup  — played when soft knockdown ends
--    HardKnockdown_Fall   — triggered when hard knockdown starts
--    HardKnockdown_Getup  — played when hard knockdown ends
--
--  ── How to use in a combat style ────────────────────────────
--  In an attack definition inside ServerStorage/CombatStyles/…:
--    canSoftKnockdown = true,
--    knockdownDuration = 2.5,
--  OR:
--    canHardKnockdown = true,
--    knockdownDuration = 3.5,
--  CombatServer reads these flags after a full hit lands.
-- ============================================================

local Players         = game:GetService("Players")
local RS              = game:GetService("ReplicatedStorage")
local StatusEffectUtil= require(script.Parent.StatusEffectUtil)

local KnockdownUtil = {}

-- ── CharacterFeedback remote ──────────────────────────────────
-- Created by InventoryServer.  Wait for it.
local CharacterFeedback
task.spawn(function()
	CharacterFeedback = RS:WaitForChild("CharacterFeedback", 15)
end)

-- Default durations if not specified in the attack definition.
local DEFAULT_SOFT_DURATION = 2.5
local DEFAULT_HARD_DURATION = 3.5

-- ── Internal helpers ──────────────────────────────────────────

local function fireKnockdownAnim(character, animName)
	local player = Players:GetPlayerFromCharacter(character)
	if player and CharacterFeedback then
		CharacterFeedback:FireClient(player, {
			type     = "PlayAnimation",
			animPath = "Shared/" .. animName,  -- RS/Animations/Shared/[name]
		})
	end
end

-- ============================================================
-- PUBLIC: ApplySoftKnockdown
-- ============================================================
function KnockdownUtil.ApplySoftKnockdown(character, duration)
	duration = duration or DEFAULT_SOFT_DURATION
	if not character or not character.Parent then return end
	local hum = character:FindFirstChildOfClass("Humanoid")
	if not hum or hum.Health <= 0 then return end

	-- Apply the status effect (sets WalkSpeed=0, tags BoolValue).
	StatusEffectUtil.Apply(character, "SoftKnockdown", duration)

	-- Tell the client to play the fall animation.
	fireKnockdownAnim(character, "SoftKnockdown_Fall")

	-- After duration: remove effect and play get-up animation.
	task.delay(duration, function()
		if not character.Parent then return end
		-- StatusEffectUtil.Apply schedules its own removal, but we still
		-- want to fire the get-up animation at exactly the right time.
		fireKnockdownAnim(character, "SoftKnockdown_Getup")
	end)
end

-- ============================================================
-- PUBLIC: ApplyHardKnockdown
-- ============================================================
function KnockdownUtil.ApplyHardKnockdown(character, duration)
	duration = duration or DEFAULT_HARD_DURATION
	if not character or not character.Parent then return end
	local hum = character:FindFirstChildOfClass("Humanoid")
	if not hum or hum.Health <= 0 then return end

	StatusEffectUtil.Apply(character, "HardKnockdown", duration)
	fireKnockdownAnim(character, "HardKnockdown_Fall")

	task.delay(duration, function()
		if not character.Parent then return end
		fireKnockdownAnim(character, "HardKnockdown_Getup")
	end)
end

-- ============================================================
-- PUBLIC: CancelSoftKnockdown
-- Called by the evasive dash system when the player dashes out.
-- ============================================================
function KnockdownUtil.CancelSoftKnockdown(character)
	StatusEffectUtil.Remove(character, "SoftKnockdown")
	-- No get-up animation — the evasive dash visuals replace it.
end

-- ============================================================
-- PUBLIC: IsKnockedDown
-- Returns true if the character is in any knockdown state.
-- ============================================================
function KnockdownUtil.IsKnockedDown(character)
	return StatusEffectUtil.Has(character, "SoftKnockdown")
		or StatusEffectUtil.Has(character, "HardKnockdown")
end

return KnockdownUtil