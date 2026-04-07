-- @ScriptType: ModuleScript
-- ============================================================
--  RemoteManager.lua  |  ModuleScript
--  Location: ServerScriptService/Modules/RemoteManager
--  Creates and manages all RemoteEvents in ReplicatedStorage.
-- ============================================================

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local GameData          = require(game.ReplicatedStorage.Modules.GameData)

local RemoteManager = {}

-- Folder that holds all remotes
local remotesFolder

-- Cache of created remotes
local remotes = {}

-- ============================================================
-- PUBLIC: Init()  —  call ONCE from MainServer before anything else
-- ============================================================
function RemoteManager.Init()
	-- Create (or reuse) the Remotes folder
	remotesFolder = ReplicatedStorage:FindFirstChild("Remotes")
	if not remotesFolder then
		remotesFolder      = Instance.new("Folder")
		remotesFolder.Name = "Remotes"
		remotesFolder.Parent = ReplicatedStorage
	end

	-- Create a RemoteEvent for every key in GameData.Remotes
	for _, eventName in pairs(GameData.Remotes) do
		local existing = remotesFolder:FindFirstChild(eventName)
		if not existing then
			local re      = Instance.new("RemoteEvent")
			re.Name       = eventName
			re.Parent     = remotesFolder
			remotes[eventName] = re
		else
			remotes[eventName] = existing
		end
	end
end

-- ============================================================
-- PUBLIC: Get(name)  →  RemoteEvent
-- ============================================================
function RemoteManager.Get(name)
	return remotes[name]
end

-- ============================================================
-- PUBLIC: FireClient(player, name, ...)
-- ============================================================
function RemoteManager.FireClient(player, name, ...)
	local re = remotes[name]
	if re then
		re:FireClient(player, ...)
	else
		warn("[RemoteManager] Remote not found:", name)
	end
end

-- ============================================================
-- PUBLIC: FireAllClients(name, ...)
-- ============================================================
function RemoteManager.FireAllClients(name, ...)
	local re = remotes[name]
	if re then re:FireAllClients(...) end
end

-- ============================================================
-- PUBLIC: OnServerEvent(name, callback)
-- Binds a server-side listener to a RemoteEvent.
-- ============================================================
function RemoteManager.OnServerEvent(name, callback)
	local re = remotes[name]
	if re then
		re.OnServerEvent:Connect(callback)
	else
		warn("[RemoteManager] Cannot bind — remote not found:", name)
	end
end

return RemoteManager
