-- @ScriptType: ModuleScript
-- @ScriptType: ModuleScript
-- ============================================================
--  NPCBase.lua  |  ModuleScript
--  Location: ServerScriptService/Modules/NPC/NPCBase
--
--  Base OOP class for all NPC types.
--  Architecture follows the devforum approach: the server holds
--  pure data (Value objects inside a Folder in workspace) and
--  fires RemoteEvents so clients render and animate locally.
--  No physical Model lives on the server beyond a ghost Part
--  used for PathfindingService raycasting.
--
--  Subclass by doing:
--    local MobNPC = setmetatable({}, {__index = NPCBase})
--    MobNPC.__index = MobNPC
--    function MobNPC.new(id, cfg) ... end
--
--  States: Idle → Patrolling → Chasing → Attacking → Dead
-- ============================================================

local Players            = game:GetService("Players")
local PathfindingService = game:GetService("PathfindingService")
local RunService         = game:GetService("RunService")
local RS                 = game:GetService("ReplicatedStorage")

-- NPCEvent is created by NPCManager; we wait lazily.
local NPCEvent
task.spawn(function()
	NPCEvent = RS:WaitForChild("NPCEvent", 15)
end)

local NPCBase = {}
NPCBase.__index = NPCBase

-- ── ID counter ────────────────────────────────────────────────
local idCounter = 0
local function nextId()
	idCounter += 1
	return "NPC_" .. idCounter
end

-- ============================================================
-- CONSTRUCTOR
-- cfg:
--   modelName      string  — asset in ServerStorage/NPCModels/
--   maxHealth      number
--   walkSpeed      number
--   aggroRange     number  — studs before chasing
--   attackRange    number  — studs to trigger attack
--   attackCooldown number  — seconds between attacks
--   damage         number
--   isStunImmune   bool    — overridden by BossNPC
--   spawnCFrame    CFrame
-- ============================================================
function NPCBase.new(cfg)
	local self = setmetatable({}, NPCBase)

	self.id          = nextId()
	self.cfg         = cfg or {}
	self.health      = self.cfg.maxHealth or 100
	self.state       = "Idle"
	self.target      = nil   -- Player reference
	self.alive       = true
	self._lastAttack = 0
	self._path       = nil
	self._waypoints  = {}
	self._waypointIdx= 1
	self._heartbeat  = nil

	-- ── Server data folder ────────────────────────────────────
	-- Pure value objects; clients watch these.
	local npcFolder = Instance.new("Folder")
	npcFolder.Name  = self.id
	npcFolder.Parent = workspace:FindFirstChild("NPCData") or (function()
		local f=Instance.new("Folder"); f.Name="NPCData"; f.Parent=workspace; return f
	end)()
	self._folder = npcFolder

	local function val(class, name, v)
		local obj = Instance.new(class)
		obj.Name = name; obj.Value = v; obj.Parent = npcFolder
		return obj
	end

	local sp = cfg.spawnCFrame or CFrame.new(0,5,0)
	self._pos    = val("Vector3Value", "Position",    sp.Position)
	self._look   = val("NumberValue",  "LookAngle",   0)
	self._stateV = val("StringValue",  "State",       "Idle")
	self._hpV    = val("NumberValue",  "Health",      self.health)
	self._maxHpV = val("NumberValue",  "MaxHealth",   self.cfg.maxHealth or 100)
	self._typeV  = val("StringValue",  "NPCType",     "Base")
	self._modelV = val("StringValue",  "ModelName",   self.cfg.modelName or "")

	-- ── Ghost part (server-side position holder for pathfinding) ─
	local ghost = Instance.new("Part")
	ghost.Name        = "Ghost_" .. self.id
	ghost.Size        = Vector3.new(2,5,2)
	ghost.Transparency = 1
	ghost.CanCollide  = false
	ghost.CanQuery    = false
	ghost.CanTouch    = false
	ghost.Anchored    = true
	ghost.CFrame      = sp
	ghost.Parent      = workspace
	self._ghost       = ghost

	return self
end

-- ============================================================
-- DATA SETTERS  (update Value objects; clients receive changes)
-- ============================================================
function NPCBase:_setPos(cf)
	self._ghost.CFrame = cf
	self._pos.Value    = cf.Position
	local _, ay, _     = cf:ToEulerAnglesYXZ()
	self._look.Value   = ay
end

function NPCBase:_setState(newState)
	self.state       = newState
	self._stateV.Value = newState
	if NPCEvent then
		NPCEvent:FireAllClients({ type="NPCState", id=self.id, state=newState })
	end
end

function NPCBase:_setHealth(hp)
	self.health   = math.max(0, hp)
	self._hpV.Value = self.health
end

-- ============================================================
-- PATHFINDING
-- ============================================================
function NPCBase:_computePath(target)
	if not target then return end
	local path = PathfindingService:CreatePath({
		AgentRadius        = 2,
		AgentHeight        = 5,
		AgentCanJump       = true,
		WaypointSpacing    = 4,
	})
	local ok, err = pcall(function()
		path:ComputeAsync(self._ghost.Position, target)
	end)
	if not ok or path.Status ~= Enum.PathStatus.Success then return end
	self._path       = path
	self._waypoints  = path:GetWaypoints()
	self._waypointIdx = 2  -- [1] is current position
end

function NPCBase:_followPath(dt)
	if not self._waypoints or #self._waypoints == 0 then return end
	local wp = self._waypoints[self._waypointIdx]
	if not wp then return end

	local speed  = self.cfg.walkSpeed or 14
	local origin = self._ghost.Position
	local dest   = wp.Position
	local dir    = (dest - origin)
	local dist   = dir.Magnitude

	if dist < 1.5 then
		self._waypointIdx += 1
		return
	end

	local move = dir.Unit * speed * dt
	if move.Magnitude > dist then move = dir end
	local newPos = origin + move
	local newCF  = CFrame.lookAt(newPos, newPos + dir.Unit)
	self:_setPos(newCF)

	-- Broadcast position update to all clients (throttled by Heartbeat).
	if NPCEvent then
		NPCEvent:FireAllClients({
			type     = "NPCMove",
			id       = self.id,
			position = self._pos.Value,
			lookAngle= self._look.Value,
		})
	end
end

-- ============================================================
-- COMBAT
-- ============================================================
function NPCBase:_canAttack()
	return os.clock() - self._lastAttack >= (self.cfg.attackCooldown or 3)
end

function NPCBase:TakeDamage(amount, attacker)
	if not self.alive then return end
	-- Stun immunity is checked in subclasses via :IsStunImmune()
	self:_setHealth(self.health - amount)
	if NPCEvent then
		NPCEvent:FireAllClients({ type="NPCHit", id=self.id, damage=amount })
	end
	if self.health <= 0 then
		self:Die()
	end
end

function NPCBase:IsStunImmune()
	return false  -- overridden by BossNPC
end

-- ============================================================
-- AI LOOP (called each Heartbeat)
-- ============================================================
function NPCBase:_findNearestPlayer()
	local nearest, nearestDist = nil, self.cfg.aggroRange or 50
	for _, p in ipairs(Players:GetPlayers()) do
		local char = p.Character
		local root = char and char:FindFirstChild("HumanoidRootPart")
		if root then
			local d = (root.Position - self._ghost.Position).Magnitude
			if d < nearestDist then nearest = p; nearestDist = d end
		end
	end
	return nearest
end

function NPCBase:_tick(dt)
	if not self.alive then return end

	if self.state == "Idle" or self.state == "Patrolling" then
		self.target = self:_findNearestPlayer()
		if self.target then
			self:_setState("Chasing")
			self:_computePath(self.target.Character and
				self.target.Character:FindFirstChild("HumanoidRootPart") and
				self.target.Character.HumanoidRootPart.Position)
		end

	elseif self.state == "Chasing" then
		if not self.target or not self.target.Character then
			self.target = nil
			self:_setState("Idle")
			return
		end
		local tRoot = self.target.Character:FindFirstChild("HumanoidRootPart")
		if not tRoot then self.target=nil; self:_setState("Idle"); return end

		local dist = (tRoot.Position - self._ghost.Position).Magnitude
		if dist > (self.cfg.aggroRange or 50) + 10 then
			self.target = nil
			self:_setState("Idle")
			return
		end

		if dist <= (self.cfg.attackRange or 5) then
			self:_setState("Attacking")
		else
			-- Recompute path periodically.
			self:_computePath(tRoot.Position)
			self:_followPath(dt)
		end

	elseif self.state == "Attacking" then
		if not self.target or not self.target.Character then
			self:_setState("Idle"); return
		end
		local tRoot = self.target.Character:FindFirstChild("HumanoidRootPart")
		if not tRoot then self:_setState("Idle"); return end

		local dist = (tRoot.Position - self._ghost.Position).Magnitude
		if dist > (self.cfg.attackRange or 5) + 2 then
			self:_setState("Chasing")
			return
		end

		if self:_canAttack() then
			self._lastAttack = os.clock()
			self:_doAttack()
		end
	end
end

function NPCBase:_doAttack()
	if not self.target or not self.target.Character then return end
	local tHum = self.target.Character:FindFirstChildOfClass("Humanoid")
	if not tHum or tHum.Health <= 0 then return end

	tHum:TakeDamage(self.cfg.damage or 10)

	if NPCEvent then
		NPCEvent:FireAllClients({ type="NPCAttack", id=self.id,
			targetPlayer=self.target.UserId })
	end
end

-- ============================================================
-- LIFECYCLE
-- ============================================================
function NPCBase:Start()
	if self._heartbeat then return end
	self:_setState("Patrolling")

	if NPCEvent then
		NPCEvent:FireAllClients({
			type      = "NPCSpawn",
			id        = self.id,
			modelName = self._modelV.Value,
			npcType   = self._typeV.Value,
			position  = self._pos.Value,
			lookAngle = self._look.Value,
			maxHealth = self._maxHpV.Value,
			health    = self._hpV.Value,
		})
	end

	self._heartbeat = RunService.Heartbeat:Connect(function(dt)
		self:_tick(dt)
	end)
end

function NPCBase:Die()
	if not self.alive then return end
	self.alive = false
	self:_setState("Dead")
	if self._heartbeat then self._heartbeat:Disconnect(); self._heartbeat=nil end
	if NPCEvent then
		NPCEvent:FireAllClients({ type="NPCDead", id=self.id })
	end
	task.delay(3, function() self:Destroy() end)
end

function NPCBase:Destroy()
	if self._heartbeat then self._heartbeat:Disconnect() end
	if self._ghost and self._ghost.Parent then self._ghost:Destroy() end
	if self._folder and self._folder.Parent then self._folder:Destroy() end
	if NPCEvent then
		NPCEvent:FireAllClients({ type="NPCDespawn", id=self.id })
	end
end

return NPCBase