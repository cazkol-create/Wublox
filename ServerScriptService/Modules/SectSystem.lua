-- @ScriptType: ModuleScript
-- ============================================================
--  SectSystem.lua  |  ModuleScript
--  Location: ServerScriptService/Modules/SectSystem
--  Manages sect membership, benefits, and roster tracking.
-- ============================================================

local GameData = require(game.ReplicatedStorage.Modules.GameData)

local DataManager, RemoteManager, MoralSystem

local SectSystem = {}

-- Server-side roster: [sectId] = { [userId] = playerName }
local roster = {}
for _, sect in ipairs(GameData.Sects) do
	roster[sect.id] = {}
end

-- ============================================================
-- HELPERS
-- ============================================================
local function getSectById(id)
	for _, s in ipairs(GameData.Sects) do
		if s.id == id then return s end
	end
	return nil
end

-- ============================================================
-- PUBLIC: JoinSect(player, sectId)
-- Returns success (bool), message (string).
-- ============================================================
function SectSystem.JoinSect(player, sectId)
	DataManager  = DataManager  or require(script.Parent.DataManager)
	RemoteManager= RemoteManager or require(script.Parent.RemoteManager)
	MoralSystem  = MoralSystem  or require(script.Parent.MoralSystem)

	local data = DataManager.GetData(player)
	if not data then return false, "Data not loaded" end

	-- Can't join sect you're already in
	if data.sectId == sectId then
		return false, "You are already a member of this sect."
	end

	-- Leave current sect first (silent)
	SectSystem.LeaveSect(player, true)

	-- Validate via MoralSystem
	local canJoin, reason = MoralSystem.CanJoinSect(player, sectId)
	if not canJoin then
		return false, reason
	end

	local sect = getSectById(sectId)
	if not sect then return false, "Unknown sect." end

	-- Commit
	data.sectId = sectId
	roster[sectId][tostring(player.UserId)] = player.Name

	RemoteManager.FireClient(player, GameData.Remotes.UpdateHUD, data)
	RemoteManager.FireClient(player, GameData.Remotes.Notify,
		"🏯 You have joined the " .. sect.name .. "!")

	return true, "Joined " .. sect.name
end

-- ============================================================
-- PUBLIC: LeaveSect(player, silent)
-- ============================================================
function SectSystem.LeaveSect(player, silent)
	DataManager  = DataManager  or require(script.Parent.DataManager)
	RemoteManager= RemoteManager or require(script.Parent.RemoteManager)

	local data   = DataManager.GetData(player)
	if not data  then return end

	local prevId = data.sectId
	if prevId == "WANDERER" then return end   -- already wanderer

	-- Remove from roster
	if roster[prevId] then
		roster[prevId][tostring(player.UserId)] = nil
	end

	-- Moral penalty for leaving a sect (betrayal)
	MoralSystem = MoralSystem or require(script.Parent.MoralSystem)
	MoralSystem.ApplyMoralDirect(player, GameData.MoralActions.BETRAY_SECT or -12)

	local prevSect = getSectById(prevId)
	data.sectId    = "WANDERER"
	roster["WANDERER"][tostring(player.UserId)] = player.Name

	if not silent then
		RemoteManager.FireClient(player, GameData.Remotes.UpdateHUD, data)
		RemoteManager.FireClient(player, GameData.Remotes.Notify,
			"🚪 You have left " .. (prevSect and prevSect.name or prevId) ..
				". You wander alone now.")
	end
end

-- ============================================================
-- PUBLIC: GetSectRoster(sectId)  →  { name, ... }
-- ============================================================
function SectSystem.GetSectRoster(sectId)
	local result = {}
	if roster[sectId] then
		for _, name in pairs(roster[sectId]) do
			table.insert(result, name)
		end
	end
	return result
end

-- ============================================================
-- PUBLIC: GetQiBonusForPlayer(player)  →  multiplier (e.g. 1.10)
-- ============================================================
function SectSystem.GetQiBonusForPlayer(player)
	DataManager = DataManager or require(script.Parent.DataManager)
	local data  = DataManager.GetData(player)
	if not data then return 1 end

	local sect = getSectById(data.sectId)
	if not sect then return 1 end
	return 1 + (sect.benefits.qiGainBonus or 0)
end

-- ============================================================
-- PUBLIC: GetSectTag(player)  →  e.g. "[Blood]"
-- ============================================================
function SectSystem.GetSectTag(player)
	DataManager = DataManager or require(script.Parent.DataManager)
	local data  = DataManager.GetData(player)
	if not data then return "" end
	local sect = getSectById(data.sectId)
	return sect and (sect.tag or "") or ""
end

-- ============================================================
-- On player join: add to roster
-- On player leave: remove from roster
-- ============================================================
function SectSystem.OnPlayerAdded(player, data)
	local sectId = data and data.sectId or "WANDERER"
	if roster[sectId] then
		roster[sectId][tostring(player.UserId)] = player.Name
	end
end

function SectSystem.OnPlayerRemoving(player)
	DataManager = DataManager or require(script.Parent.DataManager)
	local data  = DataManager.GetData(player)
	if not data then return end
	local sectId = data.sectId or "WANDERER"
	if roster[sectId] then
		roster[sectId][tostring(player.UserId)] = nil
	end
end

return SectSystem
