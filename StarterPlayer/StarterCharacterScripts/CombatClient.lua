-- @ScriptType: LocalScript
-- @ScriptType: LocalScript
-- ============================================================
--  CombatClient.lua  |  LocalScript  (StarterCharacterScripts)
--
--  CHANGES IN THIS VERSION:
--
--  VFX SYSTEM REWORK
--    • VFXUtil now drives particle bursts instead of Part clones.
--    • bindTrackMarkers() connects GetMarkerReachedSignal for each
--      entry in CombatVFXConfig.AttackMarkers[wt][sn].
--      Each marker fires VFXUtil.Play(b.vfxPath, b.amounts, hrp)
--      at the attacker's HumanoidRootPart.
--    • Feedback VFX (ParrySuccess, HitConnected, etc.) now also
--      calls VFXUtil.Play using the world entry in FeedbackEffects.
--    • PlayScreenEffect stub kept for screen-shake/flash calls.
--    • Old VFXUtil.BindAllMarkers / VFXUtil.Play(category, name…)
--      calls removed; all VFX goes through the new API.
--
--  RUNNING ATTACK REMOVED (previous patch)
--    • M1 while sprinting stops the sprint and fires a normal M1.
-- ============================================================

local CAS        = game:GetService("ContextActionService")
local Players    = game:GetService("Players")
local RS         = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local player    = Players.LocalPlayer
local character = script.Parent
local humanoid  = character:WaitForChild("Humanoid")
local animator  = humanoid:WaitForChild("Animator")

local AnimationHandler = require(RS.Modules.AnimationHandler)
local VFXUtil          = require(RS.Modules.VFXUtil)
local CombatVFXConfig  = require(RS.Modules.CombatVFXConfig)
local HitboxVisualizer = require(RS.Modules.HitboxVisualizer)
local CombatData       = require(RS.Modules.CombatData)

local Combat            = RS:WaitForChild("Combat")
local CombatFeedback    = RS:WaitForChild("CombatFeedback")
local CharacterFeedback = RS:WaitForChild("CharacterFeedback", 10)
local CombatFX          = RS:WaitForChild("CombatFX", 10)

local parrySound       = script:FindFirstChild("ParryClash")
local animRoot         = RS:WaitForChild("Animations", 10)
local sharedAnimFolder = animRoot and animRoot:FindFirstChild("Shared")

-- ============================================================
-- DEVELOPER CONFIG
-- ============================================================
local CONFIG = {
	SHOW_DEBUG_HITBOXES = true,
}

-- ============================================================
-- SCREEN EFFECT STUB
-- Replace with your actual screen-flash / vignette logic.
-- ============================================================
local function PlayScreenEffect(effectName, intensity)
	-- e.g. call your CameraShake or ScreenVignette module here
	-- PlayScreenEffect("damage", 0.4)
end

-- ============================================================
-- ANIMATION HANDLER
-- ============================================================
local anim   = AnimationHandler.new(animator)
local tracks = {}

local function loadAnimFolder(wt, sn)
	if not animRoot then return nil end
	local wf = animRoot:FindFirstChild(wt)
	if not wf then warn("[CombatClient] No anim folder:", wt); return nil end
	return wf:FindFirstChild(sn) or wf:FindFirstChild("Default")
end

local function reloadTracks(wt, sn)
	anim:StopAll(0)
	for _, t in pairs(tracks) do pcall(t.Destroy, t) end
	tracks = {}

	local folder = loadAnimFolder(wt, sn)
	if not folder then return end

	for _, name in ipairs({"M1","M2","M3","M4","Heavy","Block","Idle","Drawing","Equip"}) do
		local animObj = folder:FindFirstChild(name)

		-- [[ FIX: Correct Idle Fallback and Default State Override ]]
		if name == "Idle" then
			-- If no specific idle exists, or we are in the default Fist state, use Movement/Idle
			if not animObj or (wt == "Fist" and sn == "Default") then
				local movFolder = animRoot and animRoot:FindFirstChild("Movement")
				if movFolder and movFolder:FindFirstChild("Idle") then
					animObj = movFolder:FindFirstChild("Idle")
				end
			end
		end

		if animObj then
			local ok, t = pcall(function() return animator:LoadAnimation(animObj) end)
			if ok then 
				-- [[ FIX: Prevent Idle overriding other animations & fix joint warnings ]]
				if name == "Idle" then
					t.Priority = Enum.AnimationPriority.Idle
				end
				tracks[name] = t 
			end
		elseif name ~= "Drawing" and name ~= "Equip" and name ~= "M4" then
			warn("[CombatClient] Missing animation:", name, "in", folder:GetFullName())
		end
	end

	if tracks["Idle"] then
		tracks["Idle"].Looped = true
		anim:Play("Idle", tracks["Idle"])
	end
end

local function watchStyleValues()
	local wtVal = player:WaitForChild("Plr_WeaponType", 6)
	local snVal = player:WaitForChild("Plr_StyleName",  6)
	local function doLoad()
		reloadTracks(
			(wtVal and wtVal.Value ~= "") and wtVal.Value or "Fist",
			(snVal and snVal.Value ~= "") and snVal.Value or "Default"
		)
	end
	doLoad()
	if wtVal then wtVal.Changed:Connect(doLoad) end
	if snVal then snVal.Changed:Connect(doLoad) end
end
watchStyleValues()

-- ============================================================
-- MOVEMENT ANIMATIONS
-- ============================================================
local movementAnims = {}

local function loadMovementAnims()
	if not animRoot then return end
	local folder = animRoot:FindFirstChild("Movement")
	if not folder then
		warn("[CombatClient] RS/Animations/Movement/ not found")
		return
	end
	for _, child in ipairs(folder:GetDescendants()) do
		if child:IsA("Animation") then
			local ok, t = pcall(function() return animator:LoadAnimation(child) end)
			if ok and t then movementAnims[child.Name] = t end
		end
	end
end
loadMovementAnims()

-- ============================================================
-- CHARACTER STATE
-- ============================================================
local charState  = "Idle"
local equipping  = false
local isBlocking = false

local function ensureIdle()
	if tracks["Idle"] and not anim:IsPlaying("Idle") then
		anim:Play("Idle", tracks["Idle"])
	end
end

local function isStunned()         return character:FindFirstChild("Stunned")       ~= nil end
local function hasWeapon()         return character:FindFirstChildOfClass("Tool")   ~= nil end
local function isSoftKnockedDown() return character:FindFirstChild("SoftKnockdown") ~= nil end
local function isHardKnockedDown() return character:FindFirstChild("HardKnockdown") ~= nil end
local function isKnockedDown()     return isSoftKnockedDown() or isHardKnockedDown() end
local function isBlocked()         return isStunned() or isKnockedDown() or charState == "Ragdolled" end

-- ============================================================
-- VFX HELPERS
-- ============================================================
local function getHRP()
	return character:FindFirstChild("HumanoidRootPart")
end

local function getCurrentWeaponStyle()
	local wt = player:FindFirstChild("Plr_WeaponType")
	local sn = player:FindFirstChild("Plr_StyleName")
	return (wt and wt.Value ~= "") and wt.Value or "Fist",
	(sn and sn.Value ~= "") and sn.Value or "Default"
end

-- ============================================================
-- VFX MARKER BINDING
-- ============================================================
-- Connects GetMarkerReachedSignal for every entry in
-- CombatVFXConfig.AttackMarkers[wt][sn].
-- When a marker fires, VFXUtil.Play() bursts particles at the
-- attacker's HumanoidRootPart.
-- All connections are cleaned up in track.Stopped.
local function bindTrackMarkers(track, wt, sn)
	local bindings = CombatVFXConfig.GetMarkers(wt, sn)
	if #bindings == 0 then return end

	local conns = {}

	for _, b in ipairs(bindings) do
		-- Capture loop variables
		local capturedPath    = b.vfxPath
		local capturedAmounts = b.amounts

		local conn = track:GetMarkerReachedSignal(b.marker):Connect(function()
			local hrp = getHRP()
			if hrp then
				VFXUtil.Play(capturedPath, capturedAmounts, hrp)
			end
		end)
		table.insert(conns, conn)
	end

	-- Impact screen flash (kept from original)
	local impactConn = track:GetMarkerReachedSignal("Impact"):Connect(function()
		PlayScreenEffect("impact", 0.08)
	end)
	table.insert(conns, impactConn)

	-- Disconnect all when the track finishes
	track.Stopped:Once(function()
		for _, c in ipairs(conns) do
			c:Disconnect()
		end
	end)
end

-- ============================================================
-- PLAY ATTACK TRACK
-- ============================================================
local function playAttackTrack(trackName)
	local track = tracks[trackName]
	if not track then
		local fallbacks = { M4 = "M3" }
		track = tracks[fallbacks[trackName] or "M1"]
	end
	if not track then return nil end

	local currentAttackTrack = anim:GetTrack("Attack")
	if currentAttackTrack and currentAttackTrack.IsPlaying then
		currentAttackTrack:Stop(0.05)
	end

	anim:Play("Attack", track, 0.05)

	local wt, sn = getCurrentWeaponStyle()
	bindTrackMarkers(track, wt, sn)

	local capturedTrack = track
	track.Stopped:Once(function()
		if charState == "Attacking" and anim:GetTrack("Attack") == capturedTrack then
			charState = "Idle"
			ensureIdle()
		end
	end)

	return track
end

-- ============================================================
-- FEEDBACK VFX HELPER
-- Plays world + screen VFX for server-confirmed combat events.
-- ============================================================
local function playFeedbackVFX(eventType, worldPos)
	local cfg = CombatVFXConfig.GetFeedback(eventType)
	if not cfg then return end

	if cfg.world then
		-- Prefer the exact position from the server; fall back to local HRP
		local cf
		if worldPos then
			cf = CFrame.new(worldPos)
		else
			local hrp = getHRP()
			cf = hrp and hrp.CFrame or CFrame.new(0, 0, 0)
		end
		VFXUtil.Play(cfg.world.vfxPath, cfg.world.amounts, cf)
	end

	if cfg.screen then
		PlayScreenEffect(cfg.screen)
	end
end

-- ============================================================
-- DRAWING ANIMATION
-- ============================================================
local function onToolEquipped()
	if equipping then return end
	equipping = true; charState = "Attacking"
	anim:Stop("Attack", 0)
	task.wait(0)

	local wt = player:FindFirstChild("Plr_WeaponType")
	local sn = player:FindFirstChild("Plr_StyleName")
	reloadTracks(
		(wt and wt.Value ~= "") and wt.Value or "Fist",
		(sn and sn.Value ~= "") and sn.Value or "Default"
	)

	local drawTrack = tracks["Drawing"] or tracks["Equip"]
	if drawTrack then
		anim:Play("Equip", drawTrack)
		local done = false
		drawTrack.Stopped:Once(function() done = true end)
		task.delay(3, function() done = true end)
		repeat task.wait() until done
		anim:Stop("Equip", 0.2)
	else
		task.wait(0.4)
	end

	equipping = false; charState = "Idle"
	ensureIdle()
end

local function onToolRemoved()
	anim:Stop("Idle", 0.3)
end

character.ChildAdded:Connect(function(child)
	if child:IsA("Tool") then onToolEquipped() end
end)
character.ChildRemoved:Connect(function(child)
	if child:IsA("Tool") then onToolRemoved() end
end)

-- ============================================================
-- CC REACTIONS
-- ============================================================
character.ChildAdded:Connect(function(child)
	local n = child.Name
	if n == "Stunned" or n == "SoftKnockdown" or n == "HardKnockdown" then
		anim:StopAll(0.1)
		isBlocking = false; equipping = false
		charState = "Idle"; ensureIdle()
	elseif n == "Ragdolled" then
		charState = "Ragdolled"; anim:StopAll(0.1)
	end
end)
character.ChildRemoved:Connect(function(child)
	if child.Name == "Ragdolled" and charState == "Ragdolled" then
		charState = "Idle"; ensureIdle()
	end
end)

-- ============================================================
-- ACTION NAMES & KEYBINDS
-- ============================================================
local A_M1    = "Combat_M1"
local A_HEAVY = "Combat_Heavy"
local A_BLOCK = "Combat_Block"

local activeBinds = {
	[A_M1]    = { Enum.UserInputType.MouseButton1, Enum.KeyCode.ButtonX },
	[A_HEAVY] = { Enum.KeyCode.R, Enum.KeyCode.ButtonR2 },
	[A_BLOCK] = { Enum.KeyCode.F, Enum.KeyCode.ButtonL2 },
}

-- ============================================================
-- INPUT HANDLERS
-- ============================================================
local function handleM1(_, state, _)
	if state == Enum.UserInputState.Begin then return Enum.ContextActionResult.Pass end
	if equipping or not hasWeapon() then return Enum.ContextActionResult.Sink end
	if isBlocked() or isBlocking    then return Enum.ContextActionResult.Sink end

	-- Stop sprint then fire a normal M1
	local isSprinting = _G.WuxiaMovement and _G.WuxiaMovement.IsSprinting and _G.WuxiaMovement.IsSprinting()
	if isSprinting and _G.WuxiaMovement and _G.WuxiaMovement.StopSprint then
		_G.WuxiaMovement.StopSprint()
	end

	Combat:FireServer({ action = "M1" })
	return Enum.ContextActionResult.Sink
end

local function handleHeavy(_, state, _)
	if state ~= Enum.UserInputState.Begin then return Enum.ContextActionResult.Pass end
	if equipping or not hasWeapon() then return Enum.ContextActionResult.Sink end
	if isBlocked() or isBlocking    then return Enum.ContextActionResult.Sink end
	Combat:FireServer({ action = "Heavy" })
	return Enum.ContextActionResult.Sink
end

local function handleBlock(_, state, _)
	if state == Enum.UserInputState.Begin then
		if equipping or not hasWeapon()   then return Enum.ContextActionResult.Sink end
		if isBlocked() or isBlocking      then return Enum.ContextActionResult.Sink end
		if charState == "Attacking"       then return Enum.ContextActionResult.Sink end
		isBlocking = true; charState = "Blocking"
		if tracks.Block then anim:Play("Block", tracks.Block) end
		Combat:FireServer({ action = "BlockStart" })

	elseif state == Enum.UserInputState.End then
		if not isBlocking then return Enum.ContextActionResult.Sink end
		isBlocking = false; charState = "Idle"
		anim:Stop("Block", 0.15)
		Combat:FireServer({ action = "BlockEnd" })
		ensureIdle()
	end
	return Enum.ContextActionResult.Sink
end

local handlers = { [A_M1]=handleM1, [A_HEAVY]=handleHeavy, [A_BLOCK]=handleBlock }
for name, keys in pairs(activeBinds) do
	CAS:BindAction(name, handlers[name], false, table.unpack(keys))
end

-- ============================================================
-- SHARED ANIMATION HELPER
-- ============================================================
local function playSharedAnim(animName)
	if not sharedAnimFolder then return end
	local animObj = sharedAnimFolder:FindFirstChild(animName)
	if not animObj then return end
	local track = animator:LoadAnimation(animObj)
	anim:Play("Knockdown", track)
	track.Stopped:Once(function()
		track:Destroy()
		if charState ~= "Ragdolled" then ensureIdle() end
	end)
end

-- ============================================================
-- COMBATFX HANDLER  (unreliable, position-specific events)
-- ============================================================
if CombatFX then
	CombatFX.OnClientEvent:Connect(function(data)
		if not data then return end

		if data.type == "DebugHitbox" then
			if CONFIG.SHOW_DEBUG_HITBOXES then HitboxVisualizer.Render(data) end

		elseif data.type == "HitConnected" then
			playFeedbackVFX("HitConnected", data.pos)

		elseif data.type == "YouWereHit" then
			charState = "Idle"
			playFeedbackVFX("YouWereHit", nil)

		elseif data.type == "BlockHit" then
			playFeedbackVFX("BlockHit", data.pos)

		elseif data.type == "ParriedByOpponent" then
			playFeedbackVFX("ParriedByOpponent", nil)
		end
	end)
end

-- ============================================================
-- COMBATFEEDBACK HANDLER  (reliable, animation / state events)
-- ============================================================
CombatFeedback.OnClientEvent:Connect(function(data)
	if not data then return end

	if data.type == "PlayAttackAnim" then
		charState = "Attacking"
		playAttackTrack(data.track)

	elseif data.type == "ParrySuccess" then
		if parrySound then parrySound:Play() end
		playFeedbackVFX("ParrySuccess", data.pos)

	elseif data.type == "GuardBroken" then
		if isBlocking then
			isBlocking = false; charState = "Idle"
			anim:Stop("Block", 0.1); ensureIdle()
		end
		playFeedbackVFX("GuardBroken", data.pos)

	elseif data.type == "ParryWhiff" then
		PlayScreenEffect("damage", 0.2)
	end
end)

-- ============================================================
-- CHARACTER FEEDBACK
-- ============================================================
if CharacterFeedback then
	CharacterFeedback.OnClientEvent:Connect(function(data)
		if not data then return end

		if data.type == "PlayAnimation" then
			local parts = {}
			for p in data.animPath:gmatch("[^/]+") do table.insert(parts, p) end
			if parts[1] == "Shared" then playSharedAnim(parts[2]) end

		elseif data.type == "EvasiveDash" then
			anim:StopAll(0.1); charState = "Idle"
			local t = movementAnims["EvasiveDash"] or movementAnims["EvasiveDash_Roll"]
			if t then
				anim:Play("Movement", t, 0.05)
				t.Stopped:Once(function()
					if charState ~= "Ragdolled" then ensureIdle() end
				end)
			else
				playSharedAnim("EvasiveDash_Roll")
			end

		elseif data.type == "NormalDash" then
			local dir = data.direction or "forward"
			local key = "Dash_" .. dir:sub(1,1):upper() .. dir:sub(2)
			local t   = movementAnims[key] or movementAnims["Dash_Forward"]
			if t then
				anim:Play("Movement", t, 0.1)
				t.Stopped:Once(function()
					if charState ~= "Ragdolled" then ensureIdle() end
				end)
			end

		elseif data.type == "Slide" then
			local t = movementAnims["Slide"]
			if t then
				anim:StopAll(0.1)
				anim:Stop("Movement", 0.1)
				anim:Play("Slide", t, 0.1)
				t.Stopped:Once(function()
					if charState ~= "Ragdolled" then ensureIdle() end
				end)
			end

		elseif data.type == "EndlagStart" then
			-- Handled by MovementClient
		end
	end)
end

-- ============================================================
-- SPRINT / RUN ANIMATION SYNC
-- ============================================================
task.spawn(function()
	local waited = 0
	while not (_G.WuxiaMovement and _G.WuxiaMovement.OnSprintChanged) and waited < 5 do
		task.wait(0.1); waited += 0.1
	end
	if not (_G.WuxiaMovement and _G.WuxiaMovement.OnSprintChanged) then return end

	_G.WuxiaMovement.OnSprintChanged(function(sprinting)
		local runTrack = movementAnims["Run"]
		if sprinting and runTrack then
			anim:Play("Movement", runTrack, 0.2)
		else
			local current = anim:GetTrack("Movement")
			if current == runTrack then
				anim:Stop("Movement", 0.2)
			end
		end
	end)
end)

-- ============================================================
-- PUBLIC API
-- ============================================================
_G.WuxiaClient                    = _G.WuxiaClient or {}
_G.WuxiaClient.CombatActions      = { M1=A_M1, Heavy=A_HEAVY, Block=A_BLOCK }
_G.WuxiaClient.GetCharState       = function() return charState end

_G.WuxiaClient.RebindCombatAction = function(actionName, ...)
	local newKeys = {...}
	if #newKeys == 0 or not handlers[actionName] then return end
	activeBinds[actionName] = newKeys
	CAS:UnbindAction(actionName)
	CAS:BindAction(actionName, handlers[actionName], false, table.unpack(newKeys))
end
_G.WuxiaClient.GetCombatBinds = function()
	local copy = {}; for k,v in pairs(activeBinds) do copy[k]=v end; return copy
end