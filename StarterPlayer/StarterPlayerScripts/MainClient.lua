-- @ScriptType: LocalScript
 -- ============================================================
--  MainClient.lua  |  LocalScript
--  Location: StarterPlayer/StarterPlayerScripts/MainClient
--
--  SIMPLIFIED: HudScript now wires remotes directly.
--  This script only exposes _G.WuxiaClient for any scripts
--  that want to call server actions programmatically.
-- ============================================================

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player   = Players.LocalPlayer
local GameData = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("GameData"))

local remotesFolder = ReplicatedStorage:WaitForChild("Remotes", 20)
if not remotesFolder then
	warn("[MainClient] Remotes folder not found — is MainServer running?")
	return
end

local function getRemote(name)
	return remotesFolder:WaitForChild(name, 10)
end

local reJoinSect    = getRemote(GameData.Remotes.RequestJoinSect)
local reLeaveSect   = getRemote(GameData.Remotes.RequestLeaveSect)
local reMoralAction = getRemote(GameData.Remotes.RequestMoralAction)

-- ============================================================
-- Public API for other LocalScripts / GUI scripts to use
-- ============================================================
_G.WuxiaClient = {

	JoinSect = function(sectId)
		reJoinSect:FireServer({ sectId = sectId })
	end,

	LeaveSect = function()
		reLeaveSect:FireServer()
	end,

	-- Only whitelisted non-combat actions are accepted server-side
	ReportMoralAction = function(actionKey)
		reMoralAction:FireServer({ actionKey = actionKey })
	end,
}
