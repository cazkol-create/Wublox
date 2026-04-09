-- @ScriptType: LocalScript
-- @ScriptType: LocalScript
-- ============================================================
--  CombatClient.lua  |  LocalScript  (StarterCharacterScripts)
--
--  PIPELINE: Client input → Server logic → Client output (visuals)
--
--  This script handles:
--    • Sending player combat inputs to the server (M1, Heavy, Block)
--    • Receiving server-authorised cosmetic events via CombatFX
--      (UnreliableRemoteEvent) and playing animations/sounds/VFX
--    • Receiving gameplay-critical events via CombatFeedback
--      (reliable RemoteEvent) for state changes
--
--  What this script does NOT do:
--    • Track combo counters (server owns combos in CombatState)
--    • Track cooldown timers (server enforces via serverCD)
--    • Decide which animation track to play (server tells us via CombatFX)
--
--  Sprint/Dash/ShiftLock are handled in MovementClient.lua
-- ============================================================

local CAS     = game:GetService("ContextActionService")
local Debris  = game:GetService("Debris")
local Players = game:GetService("Players")
local RS      = game:GetService("ReplicatedStorage")

local player    = Players.LocalPlayer
local character = script.Parent
local humanoid  = character:WaitForChild("Humanoid")
local animator  = humanoid:WaitForChild("Animator")

local AnimationHandler = require(RS.Modules.AnimationHandler)
local VFXUtil          = require(RS.Modules.VFXUtil)
local CombatVFXConfig  = require(RS.Modules.CombatVFXConfig)
local HitboxVisualizer = require(RS.Modules.HitboxVisualizer)
local CombatData       = require(RS.Modules.CombatData)

-- Reliable: gameplay-critical
local Combat            = RS:WaitForChild("Combat")
local CombatFeedback    = RS:WaitForChild("CombatFeedback")
local CharacterFeedback = RS:WaitForChild("CharacterFeedback", 10)
-- Unreliable: cosmetic output (animations, sounds, VFX)
local CombatFX          = RS:WaitForChild("CombatFX", 10)

local swingSound       = script:FindFirstChild("Swing")
local parrySound       = script:FindFirstChild("ParryClash")
local animRoot         = RS:WaitForChild("Animations", 10)
local sharedAnimFolder = animRoot and animRoot:FindFirstChild("Shared")

-- ============================================================
-- DEVELOPER CONFIG
-- ============================================================
local CONFIG = {
	-- Show debug hitbox visualizer (requires server DebugMode enabled)
	SHOW_DEBUG_HITBOXES = true,

	-- Hold M1 to continue combo chaining.
	-- When true: holding LMB queues the next M1 each time the server
	-- confirms an attack via CombatFX "PlayAttackAnim".
	HOLD_M1_ENABLED = true,
}

-- ============================================================
-- ANIMATION HANDLER
-- ============================================================
local anim   = AnimationHandler.new(animator)
local tracks = {}  -- [name] = AnimationTrack

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
		if animObj then
			local ok, t = pcall(function() return animator:LoadAnimation(animObj) end)
			if ok then tracks[name] = t end
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
-- CHARACTER STATE  (UI/anim only — no cooldown tracking)
-- ============================================================
local charState  = "Idle"
local equipping  = false
local isBlocking = false
local m1ButtonHeld = false   -- for hold-M1 chain

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
local function isBlocked()         return isStunned() or isKnockedDown() or charState=="Ragdolled" end

-- ============================================================
-- VFX MARKER BINDING  (animation → VFX sync)
-- ============================================================
local function getHRP() return character:FindFirstChild("HumanoidRootPart") end

local function getCurrentWeaponStyle()
	local wt = player:FindFirstChild("Plr_WeaponType")
	local sn = player:FindFirstChild("Plr_StyleName")
	return (wt and wt.Value ~= "") and wt.Value or "Fist",
	(sn and sn.Value ~= "") and sn.Value or "Default"
end

local function bindTrackMarkers(track, wt, sn)
	local bindings = CombatVFXConfig.GetMarkers(wt, sn)
	if #bindings == 0 then return end
	local bindTable = {}
	for _, b in ipairs(bindings) do
		table.insert(bindTable, { b.marker, b.category, b.effectName, getHRP, b.options })
	end
	local conns = VFXUtil.BindAllMarkers(track, bindTable)
	track.Stopped:Once(function()
		for _, c in ipairs(conns) do c:Disconnect() end
	end)
end

local function playAttackTrack(trackName)
	local track = tracks[trackName]
	if not track then
		-- Fallback: M4 → M3, unknown finisher → M3
		local fallbacks = { M4="M3" }
		track = tracks[fallbacks[trackName] or "M1"]
	end
	if not track then return nil end
	anim:Play("Attack", track, 0.05)
	local wt, sn = getCurrentWeaponStyle()
	bindTrackMarkers(track, wt, sn)
	return track
end

-- ============================================================
-- SWING SOUND  (played only after server confirms via CombatFX)
-- ============================================================
local rng = Random.new()
local function playSwingSound()
	local wt = player:FindFirstChild("Plr_WeaponType")
	local sn = player:FindFirstChild("Plr_StyleName")
	local sounds = CombatData.GetSounds(
		(wt and wt.Value ~= "") and wt.Value or "Fist",
		(sn and sn.Value ~= "") and sn.Value or "Default"
	)
	if sounds.swingId and sounds.swingId ~= "" and sounds.swingId ~= "rbxassetid://0" then
		local root = character:FindFirstChild("HumanoidRootPart")
		if root then
			local s=Instance.new("Sound"); s.SoundId=sounds.swingId; s.Volume=0.8
			s.Parent=root; s:Play(); Debris:AddItem(s, math.max(s.TimeLength+0.5, 3))
		end
	elseif swingSound then
		local ps = swingSound:FindFirstChildOfClass("PitchShiftSoundEffect")
		if ps then ps.Octave=rng:NextNumber(0.93,1.07) end
		swingSound:Play()
	end
end

-- ============================================================
-- DRAWING ANIMATION  ("Drawing" preferred, "Equip" fallback)
-- ============================================================
local function onToolEquipped()
	if equipping then return end
	equipping=true; charState="Attacking"
	anim:Stop("Attack", 0)
	task.wait(0)  -- one frame for WeaponType replication

	local wt = player:FindFirstChild("Plr_WeaponType")
	local sn = player:FindFirstChild("Plr_StyleName")
	reloadTracks(
		(wt and wt.Value ~= "") and wt.Value or "Fist",
		(sn and sn.Value ~= "") and sn.Value or "Default"
	)

	local drawTrack = tracks["Drawing"] or tracks["Equip"]
	if drawTrack then
		anim:Play("Equip", drawTrack)
		local done=false
		drawTrack.Stopped:Once(function() done=true end)
		task.delay(3, function() done=true end)
		repeat task.wait() until done
		anim:Stop("Equip", 0.2)
	else
		task.wait(0.4)
	end

	equipping=false; charState="Idle"
	ensureIdle()
end

local function onToolRemoved()
	anim:Stop("Idle", 0.3)   -- stop idle when weapon sheathed
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
	if n=="Stunned" or n=="SoftKnockdown" or n=="HardKnockdown" then
		anim:StopAll(0.1)
		isBlocking=false; equipping=false; m1ButtonHeld=false
		charState="Idle"; ensureIdle()
	elseif n=="Ragdolled" then
		charState="Ragdolled"; anim:StopAll(0.1); m1ButtonHeld=false
	end
end)
character.ChildRemoved:Connect(function(child)
	if child.Name=="Ragdolled" and charState=="Ragdolled" then
		charState="Idle"; ensureIdle()
	end
end)

-- ============================================================
-- ACTION NAMES & KEYBINDS
-- ============================================================
local A_M1    = "Combat_M1"
local A_HEAVY = "Combat_Heavy"
local A_BLOCK = "Combat_Block"

local activeBinds = {
	[A_M1]    = { Enum.UserInputType.MouseButton1 },
	[A_HEAVY] = { Enum.KeyCode.Q },
	[A_BLOCK] = { Enum.KeyCode.F },
}

-- ============================================================
-- INPUT HANDLERS  (send to server; server will respond via CombatFX)
-- No cooldown checks — server is authoritative.
-- ============================================================

local function handleM1(_, state, _)
	if state == Enum.UserInputState.Begin then
		m1ButtonHeld = true
		if equipping or not hasWeapon() then return Enum.ContextActionResult.Sink end
		if isBlocked() or isBlocking    then return Enum.ContextActionResult.Sink end
		-- Send to server; server validates and responds with PlayAttackAnim
		Combat:FireServer({action="M1"})

	elseif state == Enum.UserInputState.End then
		m1ButtonHeld = false
	end
	return Enum.ContextActionResult.Sink
end

local function handleHeavy(_, state, _)
	if state ~= Enum.UserInputState.Begin then return Enum.ContextActionResult.Pass end
	if equipping or not hasWeapon() then return Enum.ContextActionResult.Sink end
	if isBlocked() or isBlocking    then return Enum.ContextActionResult.Sink end
	Combat:FireServer({action="Heavy"})
	return Enum.ContextActionResult.Sink
end

local function handleBlock(_, state, _)
	if state == Enum.UserInputState.Begin then
		if equipping or not hasWeapon()   then return Enum.ContextActionResult.Sink end
		if isBlocked() or isBlocking      then return Enum.ContextActionResult.Sink end
		if charState == "Attacking"       then return Enum.ContextActionResult.Sink end
		isBlocking=true; charState="Blocking"
		if tracks.Block then anim:Play("Block", tracks.Block) end
		Combat:FireServer({action="BlockStart"})

	elseif state == Enum.UserInputState.End then
		if not isBlocking then return Enum.ContextActionResult.Sink end
		isBlocking=false; charState="Idle"
		anim:Stop("Block", 0.15)
		Combat:FireServer({action="BlockEnd"})
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
-- VFX FEEDBACK HELPER
-- ============================================================
local function playFeedbackVFX(eventType, worldPos)
	local cfg = CombatVFXConfig.GetFeedback(eventType)
	if not cfg then return end
	if cfg.world then
		local target = worldPos and CFrame.new(worldPos) or getHRP()
		VFXUtil.Play(cfg.world.category, cfg.world.effectName, target, cfg.world.options)
	end
	if cfg.screen then VFXUtil.PlayScreenEffect(cfg.screen) end
end

-- ============================================================
-- COMBATFX HANDLER  (UnreliableRemoteEvent → cosmetic output)
-- All visual/audio flare lives here.
-- ============================================================
if CombatFX then
	CombatFX.OnClientEvent:Connect(function(data)
		if not data then return end

		-- ── Server confirmed our attack; play animation + sound ──
		if data.type == "PlayAttackAnim" then
			charState = "Attacking"
			playAttackTrack(data.track)

			-- Sound plays AFTER server validates (not on client keypress)
			if data.soundType == "swing" then
				playSwingSound()
			end

			-- Hold-M1: if button still held, queue next press
			if CONFIG.HOLD_M1_ENABLED and m1ButtonHeld then
				task.wait()   -- one frame before next fire
				if m1ButtonHeld and hasWeapon() and not isBlocked() and not isBlocking then
					Combat:FireServer({action="M1"})
				end
			end

			-- ── Debug hitbox visualizer ──────────────────────────────
		elseif data.type == "DebugHitbox" then
			if CONFIG.SHOW_DEBUG_HITBOXES then
				HitboxVisualizer.Render(data)
			end

			-- ── Hit landed on a target we attacked ──────────────────
		elseif data.type == "HitConnected" then
			playFeedbackVFX("HitConnected", data.pos)

			-- ── We were hit ──────────────────────────────────────────
		elseif data.type == "YouWereHit" then
			charState = "Idle"
			playFeedbackVFX("YouWereHit", nil)

			-- ── Block absorbed a hit ─────────────────────────────────
		elseif data.type == "BlockHit" then
			playFeedbackVFX("BlockHit", data.pos)

			-- ── Our attack was parried ───────────────────────────────
		elseif data.type == "ParriedByOpponent" then
			playFeedbackVFX("ParriedByOpponent", nil)
		end
	end)
end

-- ============================================================
-- COMBATFEEDBACK HANDLER  (ReliableRemoteEvent → gameplay events)
-- ============================================================
CombatFeedback.OnClientEvent:Connect(function(data)
	if not data then return end

	if data.type == "ParrySuccess" then
		if parrySound then parrySound:Play() end
		playFeedbackVFX("ParrySuccess", data.pos)

	elseif data.type == "GuardBroken" then
		-- Must reliably stop blocking (gameplay-critical)
		if isBlocking then
			isBlocking=false; charState="Idle"
			anim:Stop("Block", 0.1); ensureIdle()
		end
		playFeedbackVFX("GuardBroken", data.pos)

	elseif data.type == "ParryWhiff" then
		VFXUtil.PlayScreenEffect("damage", 0.2)
	end
end)

-- ============================================================
-- CHARACTER FEEDBACK  (knockdown anims, dash confirmations)
-- ============================================================
if CharacterFeedback then
	CharacterFeedback.OnClientEvent:Connect(function(data)
		if not data then return end
		if data.type == "PlayAnimation" then
			local parts={}
			for p in data.animPath:gmatch("[^/]+") do table.insert(parts,p) end
			if parts[1]=="Shared" then playSharedAnim(parts[2]) end
		elseif data.type == "EvasiveDash" then
			anim:StopAll(0.1); charState="Idle"
			playSharedAnim("EvasiveDash_Roll"); ensureIdle()
		elseif data.type == "NormalDash" then
			-- Play dash animation if available
			local dashTrack = tracks["Dash"] or nil
			if dashTrack then anim:Play("Attack", dashTrack, 0.05) end
		end
	end)
end

-- ============================================================
-- PUBLIC API
-- ============================================================
_G.WuxiaClient                    = _G.WuxiaClient or {}
_G.WuxiaClient.CombatActions      = {M1=A_M1, Heavy=A_HEAVY, Block=A_BLOCK}
_G.WuxiaClient.GetCharState       = function() return charState end

_G.WuxiaClient.RebindCombatAction = function(actionName, ...)
	local newKeys={...}
	if #newKeys==0 or not handlers[actionName] then return end
	activeBinds[actionName]=newKeys
	CAS:UnbindAction(actionName)
	CAS:BindAction(actionName, handlers[actionName], false, table.unpack(newKeys))
end
_G.WuxiaClient.GetCombatBinds = function()
	local copy={}; for k,v in pairs(activeBinds) do copy[k]=v end; return copy
end