-- @ScriptType: ModuleScript
-- ============================================================
--  MoralSystem.lua  |  ModuleScript
--  Location: ServerScriptService/Modules/MoralSystem
--  Governs the Righteous ↔ Chaotic alignment of every player.
-- ============================================================

local GameData = require(game.ReplicatedStorage.Modules.GameData)

local DataManager, RemoteManager

local MoralSystem = {}

-- ============================================================
-- HELPERS
-- ============================================================

-- Returns the MoralTier entry matching the current moral value
local function getTier(moral)
	for _, tier in ipairs(GameData.MoralTiers) do
		if moral >= tier.min and moral <= tier.max then
			return tier
		end
	end
	return GameData.MoralTiers[3]   -- fallback: Neutral
end

-- Clamp moral to [-100, 100]
local function clampMoral(v)
	return math.clamp(v, -100, 100)
end

-- ============================================================
-- PUBLIC: ApplyMoral(player, actionKey)
-- actionKey must exist in GameData.MoralActions.
-- ============================================================
function MoralSystem.ApplyMoral(player, actionKey)
	DataManager  = DataManager  or require(script.Parent.DataManager)
	RemoteManager= RemoteManager or require(script.Parent.RemoteManager)

	local delta = GameData.MoralActions[actionKey]
	if not delta then
		warn("[MoralSystem] Unknown action key:", actionKey)
		return
	end

	local data = DataManager.GetData(player)
	if not data then return end

	local prevTier = getTier(data.moral)
	data.moral     = clampMoral(data.moral + delta)
	local newTier  = getTier(data.moral)

	-- Notify if alignment tier changed
	if newTier.name ~= prevTier.name then
		RemoteManager.FireClient(player, GameData.Remotes.Notify,
			"⚖ Your alignment has shifted: " .. newTier.name)

		-- Auto-eject player from sect if they no longer qualify
		MoralSystem.EnforceSectAlignment(player, data)
	end

	-- Always push HUD refresh
	RemoteManager.FireClient(player, GameData.Remotes.UpdateHUD, data)
end

-- ============================================================
-- PUBLIC: ApplyMoralDirect(player, delta)
-- For custom quest/event deltas not covered by action keys.
-- ============================================================
function MoralSystem.ApplyMoralDirect(player, delta)
	DataManager  = DataManager  or require(script.Parent.DataManager)
	RemoteManager= RemoteManager or require(script.Parent.RemoteManager)

	local data = DataManager.GetData(player)
	if not data then return end

	data.moral = clampMoral(data.moral + delta)
	RemoteManager.FireClient(player, GameData.Remotes.UpdateHUD, data)
end

-- ============================================================
-- PUBLIC: GetMoralTier(player)  →  MoralTier table or nil
-- ============================================================
function MoralSystem.GetMoralTier(player)
	DataManager = DataManager or require(script.Parent.DataManager)
	local data  = DataManager.GetData(player)
	if not data then return nil end
	return getTier(data.moral)
end

-- ============================================================
-- PUBLIC: EnforceSectAlignment(player, data)
-- Removes player from their sect if moral is now out of range.
-- ============================================================
function MoralSystem.EnforceSectAlignment(player, data)
	if not data then return end

	for _, sect in ipairs(GameData.Sects) do
		if sect.id == data.sectId then
			local moral = data.moral
			local ok    = moral >= sect.allowedMoral.min and moral <= sect.allowedMoral.max
			if not ok and sect.id ~= "WANDERER" then
				data.sectId = "WANDERER"
				RemoteManager = RemoteManager or require(script.Parent.RemoteManager)
				RemoteManager.FireClient(player, GameData.Remotes.Notify,
					"⚠ Your alignment no longer fits " .. sect.name ..
						". You have been cast out and become a Wandering Cultivator.")
			end
			return
		end
	end
end

-- ============================================================
-- PUBLIC: CanJoinSect(player, sectId)  →  bool, reason string
-- ============================================================
function MoralSystem.CanJoinSect(player, sectId)
	DataManager = DataManager or require(script.Parent.DataManager)
	local data  = DataManager.GetData(player)
	if not data then return false, "No data" end

	for _, sect in ipairs(GameData.Sects) do
		if sect.id == sectId then
			-- Moral range
			if data.moral < sect.allowedMoral.min then
				return false, "Your alignment is too chaotic for " .. sect.name
			end
			if data.moral > sect.allowedMoral.max then
				return false, "Your alignment is too righteous for " .. sect.name
			end
			-- Realm requirement
			local minRealm = sect.requirements.minRealm or 1
			if data.realmIndex < minRealm then
				local realmName = GameData.CultivationRealms[minRealm].name
				return false, "You must reach " .. realmName .. " to join " .. sect.name
			end
			return true, "OK"
		end
	end
	return false, "Sect not found"
end

return MoralSystem
