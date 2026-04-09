-- @ScriptType: Script
-- @ScriptType: Script  (NOT ModuleScript)
-- ============================================================
--  NPCManager.lua  |  Script
--  Location: ServerScriptService/NPCManager
--
--  Singleton server script that owns all NPC lifecycle.
--  Creates the NPCEvent RemoteEvent that clients listen to.
--
--  To spawn an NPC from another server script:
--    local NPCManager = require(game.ServerScriptService.NPCManager)
--    NPCManager.SpawnMob({ spawnCFrame = CFrame.new(0,5,0) })
--    NPCManager.SpawnBoss({ spawnCFrame = CFrame.new(10,5,0) })
--
--  NOTE: This script requires MobNPC and BossNPC which require
--  NPCBase.  All three live in ServerScriptService/Modules/NPC/.
-- ============================================================

local Players = game:GetService("Players")
local SS      = game:GetService("ServerStorage")
local RS      = game:GetService("ReplicatedStorage")

-- Create NPCEvent remote (listened to by NPCRenderer on clients).
local NPCEvent = Instance.new("RemoteEvent")
NPCEvent.Name   = "NPCEvent"
NPCEvent.Parent = RS

-- Ensure NPCData folder exists in workspace for value objects.
if not workspace:FindFirstChild("NPCData") then
	local f = Instance.new("Folder")
	f.Name = "NPCData"; f.Parent = workspace
end

-- Load NPC classes.
local NPC_MODULE_PATH = script.Parent.Modules.NPC
local MobNPC  = require(NPC_MODULE_PATH.MobNPC)
local BossNPC = require(NPC_MODULE_PATH.BossNPC)

local activeNPCs = {}   -- [id] = NPC instance

local NPCManager = {}

-- ============================================================
-- SPAWN
-- ============================================================
function NPCManager.SpawnMob(cfg)
	local npc = MobNPC.new(cfg)
	activeNPCs[npc.id] = npc
	npc:Start()
	return npc
end

function NPCManager.SpawnBoss(cfg)
	local npc = BossNPC.new(cfg)
	activeNPCs[npc.id] = npc
	npc:Start()
	return npc
end

-- ============================================================
-- REMOVE
-- ============================================================
function NPCManager.Remove(id)
	local npc = activeNPCs[id]
	if npc then npc:Destroy(); activeNPCs[id]=nil end
end

-- ============================================================
-- GET
-- ============================================================
function NPCManager.Get(id)
	return activeNPCs[id]
end

-- ============================================================
-- HANDLE HIT ON NPC
-- CombatServer calls this when a hitbox overlaps an NPC ghost.
-- ============================================================
function NPCManager.OnHit(npcId, damage, attacker)
	local npc = activeNPCs[npcId]
	if not npc then return end
	npc:TakeDamage(damage, attacker)
end

-- ============================================================
-- NEW PLAYER: send current NPC state
-- ============================================================
Players.PlayerAdded:Connect(function(player)
	player.CharacterAdded:Connect(function()
		task.wait(1)  -- let client scripts initialise
		for _, npc in pairs(activeNPCs) do
			if npc.alive then
				NPCEvent:FireClient(player, {
					type      = "NPCSpawn",
					id        = npc.id,
					modelName = npc._modelV.Value,
					npcType   = npc._typeV.Value,
					position  = npc._pos.Value,
					lookAngle = npc._look.Value,
					maxHealth = npc._maxHpV.Value,
					health    = npc._hpV.Value,
				})
			end
		end
	end)
end)

-- ============================================================
-- EXAMPLE: Spawn two placeholder NPCs on server start
-- Remove or replace these with real spawn logic.
-- ============================================================
task.wait(2)   -- wait for other scripts to initialise

NPCManager.SpawnMob({
	spawnCFrame    = CFrame.new(20, 3, 0),
	modelName      = "Mob_Default",
})

NPCManager.SpawnBoss({
	spawnCFrame    = CFrame.new(-20, 3, 0),
	modelName      = "Boss_Default",
})

return NPCManager