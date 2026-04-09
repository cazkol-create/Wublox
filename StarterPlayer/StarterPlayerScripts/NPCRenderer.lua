-- @ScriptType: LocalScript
-- @ScriptType: LocalScript
-- ============================================================
--  NPCRenderer.lua  |  LocalScript
--  Location: StarterPlayerScripts/NPCRenderer
--
--  Listens to NPCEvent (RemoteEvent in ReplicatedStorage).
--  Creates and destroys local NPC Models, smoothly tweens
--  their position, and drives their animations based on state.
--
--  NPC models live in ReplicatedStorage/NPCModels/ so clients
--  can access them.  (Server uses ServerStorage/NPCModels/ for
--  its own ghost-part reference, but that's optional.)
--
--  Per the devforum pattern: server holds pure value data,
--  client handles ALL rendering, animation, and tweening.
--  This avoids physics replication lag for 200+ NPCs.
-- ============================================================

local Players      = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local RunService   = game:GetService("RunService")
local RS           = game:GetService("ReplicatedStorage")

local player    = Players.LocalPlayer
local animRoot  = RS:WaitForChild("Animations", 10)
local npcModels = RS:WaitForChild("NPCModels",  10)   -- RS/NPCModels/[modelName]

local NPCEvent  = RS:WaitForChild("NPCEvent", 15)

-- ============================================================
-- ACTIVE LOCAL NPC DATA
-- [id] = {
--   model     : Model (local, in workspace)
--   root      : HumanoidRootPart
--   humanoid  : Humanoid
--   animator  : Animator
--   tracks    : { Idle, Walk, Attack, Hit, Death }
--   state     : string
--   targetPos : Vector3
-- }
-- ============================================================
local activeNPCs = {}

local NPC_MOVE_TWEEN = TweenInfo.new(0.1, Enum.EasingStyle.Linear)

-- ============================================================
-- MODEL LOADING
-- ============================================================
local function loadModel(modelName)
	if not npcModels then return nil end
	local template = npcModels:FindFirstChild(modelName)
	if not template then
		warn("[NPCRenderer] Model not found in RS/NPCModels:", modelName)
		return nil
	end
	return template:Clone()
end

local function loadAnims(npcData, npcType)
	local animFolder = animRoot and animRoot:FindFirstChild("NPC")
	animFolder = animFolder and (animFolder:FindFirstChild(npcType) or animFolder:FindFirstChild("Default"))
	if not animFolder then return end

	local animator = npcData.animator
	for _, name in ipairs({"Idle","Walk","Attack","Hit","Death"}) do
		local animObj = animFolder:FindFirstChild(name)
		if animObj then
			local ok, t = pcall(function() return animator:LoadAnimation(animObj) end)
			if ok then npcData.tracks[name] = t end
		end
	end

	if npcData.tracks.Idle then
		npcData.tracks.Idle.Looped = true
		npcData.tracks.Idle:Play()
	end
end

-- ============================================================
-- CREATE LOCAL NPC
-- ============================================================
local function spawnNPC(data)
	if activeNPCs[data.id] then return end  -- already exists

	local model = loadModel(data.modelName)
	if not model then return end

	model.Name   = data.id
	model.Parent = workspace

	local root = model:FindFirstChild("HumanoidRootPart")
	local hum  = model:FindFirstChildOfClass("Humanoid")
	if not root or not hum then model:Destroy(); return end

	-- Position model at spawn.
	root.CFrame = CFrame.new(data.position) * CFrame.Angles(0, data.lookAngle or 0, 0)

	-- Disable server-side physics on client model.
	hum.PlatformStand = false
	hum.WalkSpeed     = 0   -- client never moves it via Humanoid; we tween the root

	local animator = hum:FindFirstChildOfClass("Animator")
		or (function()
			local a=Instance.new("Animator"); a.Parent=hum; return a
		end)()

	local npcData = {
		model    = model,
		root     = root,
		humanoid = hum,
		animator = animator,
		tracks   = {},
		state    = data.state or "Idle",
		npcType  = data.npcType or "Mob",
		health   = data.health   or data.maxHealth or 100,
		maxHealth= data.maxHealth or 100,
	}

	loadAnims(npcData, data.npcType)
	activeNPCs[data.id] = npcData
end

-- ============================================================
-- STATE → ANIMATION MAPPING
-- ============================================================
local function updateAnim(npcData, newState)
	npcData.state = newState
	local tracks  = npcData.tracks

	local function stopAll()
		for _, t in pairs(tracks) do
			if t and t.IsPlaying then t:Stop(0.1) end
		end
	end

	if newState == "Idle" or newState == "Patrolling" then
		stopAll()
		if tracks.Idle then tracks.Idle:Play() end

	elseif newState == "Chasing" then
		stopAll()
		local walk = tracks.Walk or tracks.Idle
		if walk then walk.Looped=true; walk:Play() end

	elseif newState == "Attacking" then
		-- Attack anim is played on NPCAttack event, not here.
		if tracks.Walk and tracks.Walk.IsPlaying then tracks.Walk:Stop() end

	elseif newState == "Dead" then
		stopAll()
		if tracks.Death then tracks.Death:Play() end
	end
end

-- ============================================================
-- NPC EVENT HANDLER
-- ============================================================
NPCEvent.OnClientEvent:Connect(function(data)
	if not data or not data.type then return end

	if data.type == "NPCSpawn" then
		spawnNPC(data)

	elseif data.type == "NPCDespawn" then
		local d = activeNPCs[data.id]
		if d then
			d.model:Destroy()
			activeNPCs[data.id] = nil
		end

	elseif data.type == "NPCMove" then
		local d = activeNPCs[data.id]
		if not d or not d.root then return end
		-- Smoothly tween to new position.
		local targetCF = CFrame.new(data.position) * CFrame.Angles(0, data.lookAngle or 0, 0)
		TweenService:Create(d.root, NPC_MOVE_TWEEN, {CFrame = targetCF}):Play()

	elseif data.type == "NPCState" then
		local d = activeNPCs[data.id]
		if d then updateAnim(d, data.state) end

	elseif data.type == "NPCAttack" then
		local d = activeNPCs[data.id]
		if not d then return end
		local attackTrack = d.tracks.Attack
		if attackTrack then
			attackTrack:Play()
			attackTrack.Stopped:Once(function()
				-- Return to idle after attack animation.
				if d.tracks.Idle then d.tracks.Idle:Play() end
			end)
		end

	elseif data.type == "NPCHit" then
		local d = activeNPCs[data.id]
		if not d then return end
		d.health = math.max(0, (d.health or 100) - (data.damage or 0))
		if d.tracks.Hit then d.tracks.Hit:Play() end

	elseif data.type == "NPCDead" then
		local d = activeNPCs[data.id]
		if d then updateAnim(d, "Dead") end
	end
end)