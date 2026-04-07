-- @ScriptType: ModuleScript
-- ============================================================
--  DataManager.lua  |  ModuleScript
--  Location: ServerScriptService/Modules/DataManager
--  Handles all DataStore read/write for player profiles.
-- ============================================================

local DataStoreService = game:GetService("DataStoreService")
local Players          = game:GetService("Players")
local GameData         = require(game.ReplicatedStorage.Modules.GameData)

local DataManager = {}

local DATASTORE_KEY = "WuxiaPlayer_v1"
local playerStore   = DataStoreService:GetDataStore(DATASTORE_KEY)

-- In-memory cache so we don't hammer DataStore every frame
local cache = {}   -- [userId] = data table

-- ============================================================
-- Deep-copy a table (prevents reference bugs on default data)
-- ============================================================
local function deepCopy(t)
	local copy = {}
	for k, v in pairs(t) do
		copy[k] = type(v) == "table" and deepCopy(v) or v
	end
	return copy
end

-- ============================================================
-- Merge saved data with default (adds missing keys on updates)
-- ============================================================
local function mergeDefaults(saved, defaults)
	for k, v in pairs(defaults) do
		if saved[k] == nil then
			saved[k] = type(v) == "table" and deepCopy(v) or v
		end
	end
	return saved
end

-- ============================================================
-- PUBLIC: LoadData(player)
-- Called when a player joins.  Returns the player data table.
-- ============================================================
function DataManager.LoadData(player)
	local userId = tostring(player.UserId)
	local data

	local success, result = pcall(function()
		return playerStore:GetAsync(userId)
	end)

	if success and result then
		data = mergeDefaults(result, deepCopy(GameData.DefaultPlayerData))
	else
		if not success then
			warn("[DataManager] Failed to load data for", player.Name, ":", result)
		end
		data = deepCopy(GameData.DefaultPlayerData)
		data.joinDate = os.time()
	end

	cache[userId] = data
	return data
end

-- ============================================================
-- PUBLIC: SaveData(player)
-- Called on PlayerRemoving and periodically by AutoSave.
-- ============================================================
function DataManager.SaveData(player)
	local userId = tostring(player.UserId)
	local data   = cache[userId]
	if not data then return end

	local success, err = pcall(function()
		playerStore:SetAsync(userId, data)
	end)

	if not success then
		warn("[DataManager] Failed to save data for", player.Name, ":", err)
	end
end

-- ============================================================
-- PUBLIC: GetData(player)  →  returns live cache table
-- ============================================================
function DataManager.GetData(player)
	return cache[tostring(player.UserId)]
end

-- ============================================================
-- PUBLIC: AutoSave loop  (call once from MainServer)
-- ============================================================
function DataManager.StartAutoSave(intervalSeconds)
	intervalSeconds = intervalSeconds or 60
	task.spawn(function()
		while true do
			task.wait(intervalSeconds)
			for _, player in ipairs(Players:GetPlayers()) do
				DataManager.SaveData(player)
			end
		end
	end)
end

-- ============================================================
-- PUBLIC: Cleanup on player leave
-- ============================================================
function DataManager.OnPlayerRemoving(player)
	DataManager.SaveData(player)
	cache[tostring(player.UserId)] = nil
end

return DataManager
