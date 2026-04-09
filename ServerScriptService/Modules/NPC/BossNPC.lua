-- @ScriptType: ModuleScript
-- @ScriptType: ModuleScript
-- ============================================================
--  MobNPC.lua  |  ModuleScript
--  Location: ServerScriptService/Modules/NPC/MobNPC
--
--  Standard mob — affected by stun, knockdown, and all CC.
--  Placeholder values; tune cfg to suit your enemy design.
--
--  Usage (from NPCManager or a test Script):
--    local MobNPC = require(script.Parent.MobNPC)
--    local mob = MobNPC.new({ spawnCFrame = CFrame.new(0,5,0) })
--    mob:Start()
-- ============================================================

local NPCBase = require(script.Parent.NPCBase)

local MobNPC = setmetatable({}, {__index = NPCBase})
MobNPC.__index = MobNPC

-- Default config for a standard mob.
local MOB_DEFAULTS = {
	modelName      = "Mob_Default",   -- ServerStorage/NPCModels/Mob_Default
	maxHealth      = 80,
	walkSpeed      = 12,
	aggroRange     = 40,
	attackRange    = 5,
	attackCooldown = 2.5,
	damage         = 8,
	isStunImmune   = false,
}

function MobNPC.new(cfg)
	cfg = cfg or {}
	-- Merge defaults with caller-provided config.
	for k, v in pairs(MOB_DEFAULTS) do
		if cfg[k] == nil then cfg[k] = v end
	end

	local self = NPCBase.new(cfg)
	setmetatable(self, MobNPC)
	self._typeV.Value = "Mob"
	return self
end

-- Mobs CAN be stunned — default NPCBase behaviour applies.
function MobNPC:IsStunImmune()
	return false
end

return MobNPC