-- @ScriptType: Script
-- ============================================================
--  MainServer.lua  |  Script (NOT a ModuleScript)
--  Location: ServerScriptService/MainServer
--  Boots every system and wires remote events.
-- ============================================================

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- ── Module paths (adjust if you rename folders) ──────────────
local Modules           = script.Parent.Modules
local GameData          = require(ReplicatedStorage.Modules.GameData)
local RemoteManager     = require(Modules.RemoteManager)
local DataManager       = require(Modules.DataManager)
local CultivationSystem = require(Modules.CultivationSystem)
local MoralSystem       = require(Modules.MoralSystem)
local SectSystem        = require(Modules.SectSystem)

-- ── 1. Initialise Remotes first so all systems can use them ──
RemoteManager.Init()

-- ── 2. Auto-save every 90 seconds ────────────────────────────
DataManager.StartAutoSave(90)

-- ============================================================
-- PLAYER ADDED
-- ============================================================
local function onPlayerAdded(player)
	-- Load / create save data
	local data = DataManager.LoadData(player)

	-- Register player in sect roster
	SectSystem.OnPlayerAdded(player, data)

	-- Wait for character to fully load, then push initial HUD
	player.CharacterAdded:Connect(function(_char)
		task.wait(1)   -- let the client LocalScript initialise
		RemoteManager.FireClient(player, GameData.Remotes.UpdateHUD, data)
	end)

	-- Also push immediately in case character already exists
	if player.Character then
		task.wait(1)
		RemoteManager.FireClient(player, GameData.Remotes.UpdateHUD, data)
	end
end

-- Handle players who join before this script runs
for _, p in ipairs(Players:GetPlayers()) do
	task.spawn(onPlayerAdded, p)
end
Players.PlayerAdded:Connect(onPlayerAdded)

-- ============================================================
-- PLAYER REMOVING
-- ============================================================
Players.PlayerRemoving:Connect(function(player)
	CultivationSystem.OnPlayerRemoving(player)
	SectSystem.OnPlayerRemoving(player)
	DataManager.OnPlayerRemoving(player)
end)

-- ============================================================
-- REMOTE: RequestMeditate  (client asks to start/stop)
-- Payload: { action = "start" | "stop" }
-- ============================================================
RemoteManager.OnServerEvent(GameData.Remotes.RequestMeditate, function(player, payload)
	if not payload then return end
	if payload.action == "start" then
		CultivationSystem.StartMeditation(player)
		RemoteManager.FireClient(player, GameData.Remotes.Notify,
			"🧘 You begin to meditate… qi flows inward.")
	elseif payload.action == "stop" then
		CultivationSystem.StopMeditation(player)
		RemoteManager.FireClient(player, GameData.Remotes.Notify,
			"🌿 You cease meditation.")
	end
end)

-- ============================================================
-- REMOTE: RequestJoinSect
-- Payload: { sectId = "BLOOD_SECT" }
-- ============================================================
RemoteManager.OnServerEvent(GameData.Remotes.RequestJoinSect, function(player, payload)
	if not payload or not payload.sectId then return end
	local success, msg = SectSystem.JoinSect(player, payload.sectId)
	RemoteManager.FireClient(player, GameData.Remotes.Notify,
		success and ("✅ " .. msg) or ("❌ " .. msg))
end)

-- ============================================================
-- REMOTE: RequestLeaveSect
-- ============================================================
RemoteManager.OnServerEvent(GameData.Remotes.RequestLeaveSect, function(player)
	SectSystem.LeaveSect(player, false)
end)

-- ============================================================
-- REMOTE: RequestMoralAction  (server-authoritative)
-- Payload: { actionKey = "KILL_BANDIT" }
-- NOTE: In production, validate this server-side — never trust
--       the client to report its own moral actions for PvP kills.
-- ============================================================
RemoteManager.OnServerEvent(GameData.Remotes.RequestMoralAction, function(player, payload)
	if not payload or not payload.actionKey then return end
	-- Whitelist of actions clients may self-report
	local allowed = {
		HELP_NPC       = true,
		DONATE_GOLD    = true,
		MEDITATE       = true,
	}
	if allowed[payload.actionKey] then
		MoralSystem.ApplyMoral(player, payload.actionKey)
	end
end)

print("[WuxiaGame] Server booted successfully. All systems online.")
-- ============================================================
--  MainServer.lua  |  Script (NOT a ModuleScript)
--  Location: ServerScriptService/MainServer
--  Boots every system and wires remote events.
-- ============================================================

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- ── Module paths (adjust if you rename folders) ──────────────
local Modules           = script.Parent.Modules
local GameData          = require(ReplicatedStorage.Modules.GameData)
local RemoteManager     = require(Modules.RemoteManager)
local DataManager       = require(Modules.DataManager)
local CultivationSystem = require(Modules.CultivationSystem)
local MoralSystem       = require(Modules.MoralSystem)
local SectSystem        = require(Modules.SectSystem)

-- ── 1. Initialise Remotes first so all systems can use them ──
RemoteManager.Init()

-- ── 2. Auto-save every 90 seconds ────────────────────────────
DataManager.StartAutoSave(90)

-- ============================================================
-- PLAYER ADDED
-- ============================================================
local function onPlayerAdded(player)
	-- Load / create save data
	local data = DataManager.LoadData(player)

	-- Register player in sect roster
	SectSystem.OnPlayerAdded(player, data)

	-- Wait for character to fully load, then push initial HUD
	player.CharacterAdded:Connect(function(_char)
		task.wait(1)   -- let the client LocalScript initialise
		RemoteManager.FireClient(player, GameData.Remotes.UpdateHUD, data)
	end)

	-- Also push immediately in case character already exists
	if player.Character then
		task.wait(1)
		RemoteManager.FireClient(player, GameData.Remotes.UpdateHUD, data)
	end
end

-- Handle players who join before this script runs
for _, p in ipairs(Players:GetPlayers()) do
	task.spawn(onPlayerAdded, p)
end
Players.PlayerAdded:Connect(onPlayerAdded)

-- ============================================================
-- PLAYER REMOVING
-- ============================================================
Players.PlayerRemoving:Connect(function(player)
	CultivationSystem.OnPlayerRemoving(player)
	SectSystem.OnPlayerRemoving(player)
	DataManager.OnPlayerRemoving(player)
end)

-- ============================================================
-- REMOTE: RequestMeditate  (client asks to start/stop)
-- Payload: { action = "start" | "stop" }
-- ============================================================
RemoteManager.OnServerEvent(GameData.Remotes.RequestMeditate, function(player, payload)
	if not payload then return end
	if payload.action == "start" then
		CultivationSystem.StartMeditation(player)
		RemoteManager.FireClient(player, GameData.Remotes.Notify,
			"🧘 You begin to meditate… qi flows inward.")
	elseif payload.action == "stop" then
		CultivationSystem.StopMeditation(player)
		RemoteManager.FireClient(player, GameData.Remotes.Notify,
			"🌿 You cease meditation.")
	end
end)

-- ============================================================
-- REMOTE: RequestJoinSect
-- Payload: { sectId = "BLOOD_SECT" }
-- ============================================================
RemoteManager.OnServerEvent(GameData.Remotes.RequestJoinSect, function(player, payload)
	if not payload or not payload.sectId then return end
	local success, msg = SectSystem.JoinSect(player, payload.sectId)
	RemoteManager.FireClient(player, GameData.Remotes.Notify,
		success and ("✅ " .. msg) or ("❌ " .. msg))
end)

-- ============================================================
-- REMOTE: RequestLeaveSect
-- ============================================================
RemoteManager.OnServerEvent(GameData.Remotes.RequestLeaveSect, function(player)
	SectSystem.LeaveSect(player, false)
end)

-- ============================================================
-- REMOTE: RequestMoralAction  (server-authoritative)
-- Payload: { actionKey = "KILL_BANDIT" }
-- NOTE: In production, validate this server-side — never trust
--       the client to report its own moral actions for PvP kills.
-- ============================================================
RemoteManager.OnServerEvent(GameData.Remotes.RequestMoralAction, function(player, payload)
	if not payload or not payload.actionKey then return end
	-- Whitelist of actions clients may self-report
	local allowed = {
		HELP_NPC       = true,
		DONATE_GOLD    = true,
		MEDITATE       = true,
	}
	if allowed[payload.actionKey] then
		MoralSystem.ApplyMoral(player, payload.actionKey)
	end
end)

print("[WuxiaGame] Server booted successfully. All systems online.")
-- ============================================================
--  MainServer.lua  |  Script (NOT a ModuleScript)
--  Location: ServerScriptService/MainServer
--  Boots every system and wires remote events.
-- ============================================================

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- ── Module paths (adjust if you rename folders) ──────────────
local Modules           = script.Parent.Modules
local GameData          = require(ReplicatedStorage.Modules.GameData)
local RemoteManager     = require(Modules.RemoteManager)
local DataManager       = require(Modules.DataManager)
local CultivationSystem = require(Modules.CultivationSystem)
local MoralSystem       = require(Modules.MoralSystem)
local SectSystem        = require(Modules.SectSystem)

-- ── 1. Initialise Remotes first so all systems can use them ──
RemoteManager.Init()

-- ── 2. Auto-save every 90 seconds ────────────────────────────
DataManager.StartAutoSave(90)

-- ============================================================
-- PLAYER ADDED
-- ============================================================
local function onPlayerAdded(player)
	-- Load / create save data
	local data = DataManager.LoadData(player)

	-- Register player in sect roster
	SectSystem.OnPlayerAdded(player, data)

	-- Wait for character to fully load, then push initial HUD
	player.CharacterAdded:Connect(function(_char)
		task.wait(1)   -- let the client LocalScript initialise
		RemoteManager.FireClient(player, GameData.Remotes.UpdateHUD, data)
	end)

	-- Also push immediately in case character already exists
	if player.Character then
		task.wait(1)
		RemoteManager.FireClient(player, GameData.Remotes.UpdateHUD, data)
	end
end

-- Handle players who join before this script runs
for _, p in ipairs(Players:GetPlayers()) do
	task.spawn(onPlayerAdded, p)
end
Players.PlayerAdded:Connect(onPlayerAdded)

-- ============================================================
-- PLAYER REMOVING
-- ============================================================
Players.PlayerRemoving:Connect(function(player)
	CultivationSystem.OnPlayerRemoving(player)
	SectSystem.OnPlayerRemoving(player)
	DataManager.OnPlayerRemoving(player)
end)

-- ============================================================
-- REMOTE: RequestMeditate  (client asks to start/stop)
-- Payload: { action = "start" | "stop" }
-- ============================================================
RemoteManager.OnServerEvent(GameData.Remotes.RequestMeditate, function(player, payload)
	if not payload then return end
	if payload.action == "start" then
		CultivationSystem.StartMeditation(player)
		RemoteManager.FireClient(player, GameData.Remotes.Notify,
			"🧘 You begin to meditate… qi flows inward.")
	elseif payload.action == "stop" then
		CultivationSystem.StopMeditation(player)
		RemoteManager.FireClient(player, GameData.Remotes.Notify,
			"🌿 You cease meditation.")
	end
end)

-- ============================================================
-- REMOTE: RequestJoinSect
-- Payload: { sectId = "BLOOD_SECT" }
-- ============================================================
RemoteManager.OnServerEvent(GameData.Remotes.RequestJoinSect, function(player, payload)
	if not payload or not payload.sectId then return end
	local success, msg = SectSystem.JoinSect(player, payload.sectId)
	RemoteManager.FireClient(player, GameData.Remotes.Notify,
		success and ("✅ " .. msg) or ("❌ " .. msg))
end)

-- ============================================================
-- REMOTE: RequestLeaveSect
-- ============================================================
RemoteManager.OnServerEvent(GameData.Remotes.RequestLeaveSect, function(player)
	SectSystem.LeaveSect(player, false)
end)

-- ============================================================
-- REMOTE: RequestMoralAction  (server-authoritative)
-- Payload: { actionKey = "KILL_BANDIT" }
-- NOTE: In production, validate this server-side — never trust
--       the client to report its own moral actions for PvP kills.
-- ============================================================
RemoteManager.OnServerEvent(GameData.Remotes.RequestMoralAction, function(player, payload)
	if not payload or not payload.actionKey then return end
	-- Whitelist of actions clients may self-report
	local allowed = {
		HELP_NPC       = true,
		DONATE_GOLD    = true,
		MEDITATE       = true,
	}
	if allowed[payload.actionKey] then
		MoralSystem.ApplyMoral(player, payload.actionKey)
	end
end)

print("[WuxiaGame] Server booted successfully. All systems online.")
