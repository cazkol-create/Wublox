-- @ScriptType: ModuleScript
-- ============================================================
--  CultivationSystem.lua  |  ModuleScript
--  Location: ServerScriptService/Modules/CultivationSystem
--  Handles qi accumulation, meditation, and realm breakthroughs.
-- ============================================================

local Players  = game:GetService("Players")
local GameData = require(game.ReplicatedStorage.Modules.GameData)

-- lazy-loaded to avoid circular requires
local DataManager, RemoteManager

local CultivationSystem = {}

-- Seconds between each meditation tick
local MEDITATE_TICK = 2

-- Active meditation coroutines  [userId] = thread
local meditationThreads = {}

-- ============================================================
-- HELPERS
-- ============================================================

-- Returns the realm entry for a given qi total
local function getRealmForQi(qi)
	for i = #GameData.CultivationRealms, 1, -1 do
		local r = GameData.CultivationRealms[i]
		if qi >= r.minQi then
			return i, r
		end
	end
	return 1, GameData.CultivationRealms[1]
end

-- Qi gain per tick: base * (1 + 0.5 * tier) * sect bonus
local function calcQiPerTick(data)
	local _, realm  = getRealmForQi(data.qi)
	local tierBonus = 1 + (realm.tier * 0.5)
	local base      = GameData.BaseQiPerTick * tierBonus

	-- Apply sect qi bonus
	local sectBonus = 0
	for _, s in ipairs(GameData.Sects) do
		if s.id == data.sectId then
			sectBonus = s.benefits.qiGainBonus or 0
			break
		end
	end

	return math.floor(base * (1 + sectBonus))
end

-- ============================================================
-- PUBLIC: AddQi(player, amount)
-- Called by meditation tick or external events (quests, pills…)
-- Returns true if a breakthrough happened.
-- ============================================================
function CultivationSystem.AddQi(player, amount)
	DataManager = DataManager or require(script.Parent.DataManager)
	local data  = DataManager.GetData(player)
	if not data then return false end

	local prevRealm = data.realmIndex
	data.qi         = data.qi + amount

	-- Check for realm breakthrough
	local newRealmIdx, newRealm = getRealmForQi(data.qi)
	if newRealmIdx > prevRealm then
		data.realmIndex = newRealmIdx
		-- Notify client
		RemoteManager = RemoteManager or require(script.Parent.RemoteManager)
		RemoteManager.FireClient(player, GameData.Remotes.RealmBreakthrough, {
			realm = newRealm.name,
			index = newRealmIdx,
		})
		RemoteManager.FireClient(player, GameData.Remotes.Notify,
			"🌟 Breakthrough! You have reached the " .. newRealm.name .. " realm!")
		return true
	end
	return false
end

-- ============================================================
-- PUBLIC: StartMeditation(player)
-- Begins the qi-tick coroutine for this player.
-- ============================================================
function CultivationSystem.StartMeditation(player)
	DataManager = DataManager or require(script.Parent.DataManager)
	RemoteManager = RemoteManager or require(script.Parent.RemoteManager)

	local userId = tostring(player.UserId)
	if meditationThreads[userId] then return end   -- already meditating

	local data = DataManager.GetData(player)
	if not data then return end
	data.meditating = true

	meditationThreads[userId] = task.spawn(function()
		while data.meditating and Players:GetPlayerByUserId(player.UserId) do
			task.wait(MEDITATE_TICK)
			if not data.meditating then break end

			local gain = calcQiPerTick(data)
			CultivationSystem.AddQi(player, gain)

			-- Push HUD update
			RemoteManager.FireClient(player, GameData.Remotes.UpdateHUD, data)
		end
	end)
end

-- ============================================================
-- PUBLIC: StopMeditation(player)
-- ============================================================
function CultivationSystem.StopMeditation(player)
	DataManager = DataManager or require(script.Parent.DataManager)
	local userId = tostring(player.UserId)
	local data   = DataManager.GetData(player)
	if data then data.meditating = false end

	if meditationThreads[userId] then
		task.cancel(meditationThreads[userId])
		meditationThreads[userId] = nil
	end
end

-- ============================================================
-- PUBLIC: GetRealmInfo(player)
-- Returns { index, name, tier, qi, nextQi, progress }
-- ============================================================
function CultivationSystem.GetRealmInfo(player)
	DataManager = DataManager or require(script.Parent.DataManager)
	local data   = DataManager.GetData(player)
	if not data then return nil end

	local idx, realm = getRealmForQi(data.qi)
	local nextRealm  = GameData.CultivationRealms[idx + 1]
	local progress   = 0
	if nextRealm then
		local span = nextRealm.minQi - realm.minQi
		progress   = math.clamp((data.qi - realm.minQi) / span, 0, 1)
	else
		progress = 1
	end

	return {
		index    = idx,
		name     = realm.name,
		tier     = realm.tier,
		qi       = data.qi,
		nextQi   = nextRealm and nextRealm.minQi or math.huge,
		progress = progress,
	}
end

-- ============================================================
-- Cleanup when player leaves
-- ============================================================
function CultivationSystem.OnPlayerRemoving(player)
	CultivationSystem.StopMeditation(player)
end

return CultivationSystem
