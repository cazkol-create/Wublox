-- @ScriptType: ModuleScript
-- ============================================================
--  CombatState.lua  |  ModuleScript
--  Location: ServerScriptService/Modules/CombatState
--
--  Owns all per-player combat state on the server.
--  Required by CombatServer AND TestDummies so both can read
--  blockState on any character (player or NPC) through one API.
-- ============================================================

local Players    = game:GetService("Players")
local CombatData = require(game.ReplicatedStorage.Modules.CombatData)

local CombatState = {}

-- Internal table indexed by UserId.
-- Cleaned up in PlayerRemoving — never leaks.
local pState = {}

-- ── State Schema ─────────────────────────────────────────────
-- blockState       nil | "parrying" | "blocking"
-- parryReady       bool   — false while on either parry cooldown
-- parryExpireTask  task   — fires when parry window expires unused
-- parryCoolTask    task   — fires when parry cooldown ends
-- guardBrokenUntil number — os.clock() timestamp; can't re-guard before this
-- lastLightTime    number — os.clock() of last light attack (server rate gate)
-- lastHeavyTime    number — os.clock() of last heavy attack
-- ─────────────────────────────────────────────────────────────

local function newState()
	return {
		blockState        = nil,
		parryReady        = true,
		parryExpireTask   = nil,
		parryCoolTask     = nil,
		guardBrokenUntil  = 0,
		lastLightTime     = 0,
		lastHeavyTime     = 0,
	}
end

-- ── PUBLIC: Get ───────────────────────────────────────────────
function CombatState.Get(player)
	local id = player.UserId
	if not pState[id] then
		pState[id] = newState()
	end
	return pState[id]
end

-- ── PUBLIC: GetBlockState ─────────────────────────────────────
-- Returns the block state for ANY character — player or NPC.
-- Players: reads from pState.
-- NPCs:    reads a "BlockState" StringValue on the character.
--          TestDummies.lua creates and manages this value.
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

-- ── PUBLIC: CanBlock ──────────────────────────────────────────
-- Returns false if the player is inside a guard-break window.
function CombatState.CanBlock(player)
	local s = pState[player.UserId]
	if not s then return true end
	return os.clock() >= s.guardBrokenUntil
end

-- ── PUBLIC: OnParrySuccess ────────────────────────────────────
-- Called when the player SUCCESSFULLY parries an incoming attack.
-- Clears the block state and starts the SHORT recovery cooldown.
function CombatState.OnParrySuccess(player)
	local s = CombatState.Get(player)

	-- Cancel the expire task so the whiff branch never fires.
	if s.parryExpireTask then
		task.cancel(s.parryExpireTask)
		s.parryExpireTask = nil
	end

	s.blockState  = nil

	-- Apply short recovery cooldown.
	s.parryReady  = false
	if s.parryCoolTask then task.cancel(s.parryCoolTask) end
	s.parryCoolTask = task.delay(CombatData.PARRY_RECOVER_CD, function()
		s.parryReady    = true
		s.parryCoolTask = nil
	end)
end

-- ── PUBLIC: OnParryWhiff ──────────────────────────────────────
-- Called internally when the parry window expires without an attack landing.
-- Applies the longer PUNISHMENT cooldown.
function CombatState.OnParryWhiff(player)
	local s = CombatState.Get(player)
	s.parryReady = false
	-- Transition to regular blocking — player is still protected but
	-- cannot attempt another parry until the punishment expires.
	s.blockState = "blocking"
	if s.parryCoolTask then task.cancel(s.parryCoolTask) end
	s.parryCoolTask = task.delay(CombatData.PARRY_PUNISH_CD, function()
		s.parryReady    = true
		s.parryCoolTask = nil
	end)
end

-- ── PUBLIC: BreakGuard ────────────────────────────────────────
-- Called when a guard-breaking attack connects on a blocking character.
-- Clears their block state, stamps a guardBrokenUntil time, and
-- cancels any running parry tasks to prevent phantom state.
--
-- Returns the CombatFeedback table so CombatServer can fire it
-- without needing to import the remote directly here.
function CombatState.BreakGuard(character)
	local player = Players:GetPlayerFromCharacter(character)

	if player then
		local s = CombatState.Get(player)
		if s.parryExpireTask then
			task.cancel(s.parryExpireTask)
			s.parryExpireTask = nil
		end
		if s.parryCoolTask then
			task.cancel(s.parryCoolTask)
			s.parryCoolTask = nil
		end
		s.blockState       = nil
		s.parryReady       = false
		-- Guard broken window: can't re-block until this time passes.
		s.guardBrokenUntil = os.clock() + CombatData.GUARD_BREAK_DURATION
		-- After the window, parry becomes available again.
		s.parryCoolTask = task.delay(CombatData.GUARD_BREAK_DURATION, function()
			s.parryReady    = true
			s.parryCoolTask = nil
		end)
	else
		-- NPC: clear the StringValue so subsequent attacks register normally.
		local val = character:FindFirstChild("BlockState")
		if val then val.Value = "" end
	end
end

-- ── PUBLIC: ClearBlockOnStun ──────────────────────────────────
-- Whenever a character is stunned (from any source), their block
-- state must be cleared. Otherwise the server still thinks they are
-- blocking even after the client has stopped the guard animation.
function CombatState.ClearBlockOnStun(character)
	local player = Players:GetPlayerFromCharacter(character)
	if not player then
		local val = character:FindFirstChild("BlockState")
		if val then val.Value = "" end
		return
	end
	local s = pState[player.UserId]
	if not s then return end
	if s.parryExpireTask then
		task.cancel(s.parryExpireTask)
		s.parryExpireTask = nil
	end
	s.blockState = nil
end

-- ── Cleanup ───────────────────────────────────────────────────
function CombatState.Cleanup(player)
	local s = pState[player.UserId]
	if s then
		if s.parryExpireTask then task.cancel(s.parryExpireTask) end
		if s.parryCoolTask   then task.cancel(s.parryCoolTask)   end
	end
	pState[player.UserId] = nil
end

Players.PlayerRemoving:Connect(CombatState.Cleanup)

return CombatState