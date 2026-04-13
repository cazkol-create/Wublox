-- @ScriptType: ModuleScript
	-- @ScriptType: ModuleScript
-- ============================================================
--  CombatState.lua  |  ModuleScript
--  Location: ServerScriptService/Modules/CombatState
--
--  CHANGES:
--    • slideCooldownUntil — server-side slide cooldown timestamp.
--      Checked by CombatServer before accepting a Slide action.
-- ============================================================

local Players      = game:GetService("Players")
local CombatConfig = require(script.Parent.CombatConfig)

local CombatState = {}
local pState      = {}

local function newState()
	return {
		blockState               = nil,
		parryReady               = true,
		parryExpireTask          = nil,
		parryCoolTask            = nil,
		guardBrokenUntil         = 0,
		lastLightTime            = 0,
		lastHeavyTime            = 0,
		lastFlourishTime         = 0,
		isAttacking              = false,
		attackingClearTask       = nil,
		activeAttackCount        = 0,
		evasiveDashCooldownUntil = 0,
		normalDashCooldownUntil  = 0,
		slideCooldownUntil       = 0,   -- NEW: slide cooldown
		endlagUntil              = 0,
		comboCount               = 1,
		comboResetTask           = nil,
	}
end

function CombatState.Get(player)
	local id = player.UserId
	if not pState[id] then pState[id] = newState() end
	return pState[id]
end

-- ── Combo ─────────────────────────────────────────────────────
function CombatState.GetCombo(player)
	return CombatState.Get(player).comboCount
end

function CombatState.IncrementCombo(player, resetTime)
	local s = CombatState.Get(player)
	s.comboCount = (s.comboCount or 1) + 1
	if s.comboResetTask then task.cancel(s.comboResetTask) end
	s.comboResetTask = task.delay(resetTime or 1.5, function()
		s.comboCount = 1; s.comboResetTask = nil
	end)
end

function CombatState.ResetCombo(player)
	local s = CombatState.Get(player)
	if s.comboResetTask then task.cancel(s.comboResetTask); s.comboResetTask = nil end
	s.comboCount = 1
end

-- ── Block state ───────────────────────────────────────────────
function CombatState.GetBlockState(character)
	local player = Players:GetPlayerFromCharacter(character)
	if player then
		local s = pState[player.UserId]
		return s and s.blockState or nil
	else
		local val = character:FindFirstChild("BlockState")
		if val and val.Value ~= "" then return val.Value end
		return nil
	end
end

function CombatState.CanBlock(player)
	local s = pState[player.UserId]; if not s then return true end
	return os.clock() >= s.guardBrokenUntil
end

-- ── Dash / slide gates ────────────────────────────────────────
function CombatState.CanEvasiveDash(player)
	local s = pState[player.UserId]; if not s then return true end
	return os.clock() >= s.evasiveDashCooldownUntil
end

function CombatState.CanNormalDash(player)
	local s = pState[player.UserId]; if not s then return true end
	return os.clock() >= s.normalDashCooldownUntil
end

function CombatState.CanSlide(player)
	local s = pState[player.UserId]; if not s then return true end
	return os.clock() >= s.slideCooldownUntil
end

-- ── Endlag ────────────────────────────────────────────────────
function CombatState.SetEndlag(player, duration)
	local s = CombatState.Get(player)
	s.endlagUntil = (duration and duration > 0) and (os.clock() + duration) or 0
end

function CombatState.IsInEndlag(player)
	local s = pState[player.UserId]; if not s then return false end
	return os.clock() < s.endlagUntil
end

-- ── Parry ─────────────────────────────────────────────────────
function CombatState.OnParrySuccess(player)
	local s = CombatState.Get(player)
	if s.parryExpireTask then task.cancel(s.parryExpireTask); s.parryExpireTask = nil end
	s.blockState = nil; s.parryReady = false
	if s.parryCoolTask then task.cancel(s.parryCoolTask) end
	s.parryCoolTask = task.delay(CombatConfig.PARRY_RECOVER_CD, function()
		s.parryReady = true; s.parryCoolTask = nil
	end)
end

function CombatState.OnParryWhiff(player)
	local s = CombatState.Get(player)
	s.parryReady = false; s.blockState = "blocking"
	if s.parryCoolTask then task.cancel(s.parryCoolTask) end
	s.parryCoolTask = task.delay(CombatConfig.PARRY_PUNISH_CD, function()
		s.parryReady = true; s.parryCoolTask = nil
	end)
end

function CombatState.BreakGuard(character)
	local player = Players:GetPlayerFromCharacter(character)
	if player then
		local s = CombatState.Get(player)
		if s.parryExpireTask then task.cancel(s.parryExpireTask); s.parryExpireTask = nil end
		if s.parryCoolTask   then task.cancel(s.parryCoolTask);   s.parryCoolTask   = nil end
		s.blockState = nil; s.parryReady = false
		s.guardBrokenUntil = os.clock() + CombatConfig.GUARD_BREAK_DURATION
		s.parryCoolTask = task.delay(CombatConfig.GUARD_BREAK_DURATION, function()
			s.parryReady = true; s.parryCoolTask = nil
		end)
	else
		local val = character:FindFirstChild("BlockState")
		if val then val.Value = "" end
	end
end

-- ── Attack lock ───────────────────────────────────────────────
function CombatState.SetAttacking(player, duration)
	local s = CombatState.Get(player)
	if s.attackingClearTask then task.cancel(s.attackingClearTask); s.attackingClearTask = nil end
	s.isAttacking = (duration > 0)
	if duration > 0 then
		s.attackingClearTask = task.delay(duration, function()
			s.isAttacking = false; s.attackingClearTask = nil
		end)
	end
end

function CombatState.IsAttacking(player)
	local s = pState[player.UserId]
	return s and s.isAttacking or false
end

function CombatState.IncrementAttackCount(player)
	local s = CombatState.Get(player)
	s.activeAttackCount = (s.activeAttackCount or 0) + 1
end

function CombatState.DecrementAttackCount(player)
	local s = CombatState.Get(player)
	s.activeAttackCount = math.max(0, (s.activeAttackCount or 0) - 1)
	return s.activeAttackCount
end

function CombatState.ClearBlockOnStun(character)
	local player = Players:GetPlayerFromCharacter(character)
	if not player then
		local val = character:FindFirstChild("BlockState")
		if val then val.Value = "" end
		return
	end
	local s = pState[player.UserId]; if not s then return end
	if s.parryExpireTask    then task.cancel(s.parryExpireTask);    s.parryExpireTask    = nil end
	if s.attackingClearTask then task.cancel(s.attackingClearTask); s.attackingClearTask = nil end
	s.blockState = nil; s.isAttacking = false; s.activeAttackCount = 0
	CombatState.ResetCombo(player)
end

-- ── Cleanup ───────────────────────────────────────────────────
function CombatState.Cleanup(player)
	local s = pState[player.UserId]
	if s then
		if s.parryExpireTask    then task.cancel(s.parryExpireTask)    end
		if s.parryCoolTask      then task.cancel(s.parryCoolTask)      end
		if s.attackingClearTask then task.cancel(s.attackingClearTask) end
		if s.comboResetTask     then task.cancel(s.comboResetTask)     end
	end
	pState[player.UserId] = nil
end

Players.PlayerRemoving:Connect(CombatState.Cleanup)

return CombatState