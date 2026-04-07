-- @ScriptType: Script
-- ============================================================
--  CombatServer.lua  |  Script  (NOT ModuleScript)
--  Location: ServerScriptService
--
--  Authoritative server for all combat. Clients fire actions,
--  server validates, resolves block/parry, applies damage.
--
--  ── Children this Script needs ──────────────────────────────
--    Hit           Animation   hit-react played on any struck target
--    "Punch Hit"   Sound       impact thud
--    "Parry Clash" Sound       metallic ring on a successful parry
--
--  ── ReplicatedStorage ───────────────────────────────────────
--    Modules/CombatData    ModuleScript
--    Combat                RemoteEvent   (client → server)
--    CombatFeedback        RemoteEvent   (server → client)
--    GameSettings          RemoteEvent   (client → server, settings)
--    "Punch-01"/Main/Hit1  VFX folder
--
--  ── ServerStorage ───────────────────────────────────────────
--    CombatStyles/Sword/Default   ModuleScript
--    CombatStyles/Sword/Flowing   ModuleScript
--    CombatStyles/Sword/Storm     ModuleScript
--
--  ── ServerScriptService/Modules ─────────────────────────────
--    CombatState   ModuleScript
--    RagdollUtil   ModuleScript
-- ============================================================

local Players    = game:GetService("Players")
local SS         = game:GetService("ServerStorage")
local Debris     = game:GetService("Debris")
local RS         = game:GetService("ReplicatedStorage")

-- ── Module imports ───────────────────────────────────────────
-- CombatData is in ReplicatedStorage so the client can also read it.
local CombatData  = require(RS.Modules.CombatData)
local CombatState = require(script.Parent.Modules.CombatState)
local RagdollUtil = require(script.Parent.Modules.RagdollUtil)

-- ── Remotes ──────────────────────────────────────────────────
local Combat         = RS:WaitForChild("Combat")
local CombatFB       = RS:WaitForChild("CombatFeedback")
local GameSettingsRE = RS:WaitForChild("GameSettings", 5)

-- ============================================================
-- STYLE LOADER
-- Reads Plr_WeaponType and Plr_StyleName StringValues from the
-- player object and returns the matching ModuleScript data table.
-- Hierarchy: ServerStorage/CombatStyles/[WeaponType]/[StyleName]
-- Falls back to Default if StyleName is missing or fails to load.
-- ============================================================
local styleCache   = {}
local stylesFolder = SS:WaitForChild("CombatStyles", 10)

local function loadStyleModule(weaponType, styleName)
	local cacheKey = weaponType .. "/" .. styleName
	if styleCache[cacheKey] then return styleCache[cacheKey] end

	local weaponFolder = stylesFolder and stylesFolder:FindFirstChild(weaponType)
	local mod          = weaponFolder  and (
		weaponFolder:FindFirstChild(styleName) or
			weaponFolder:FindFirstChild("Default")
	)

	if not mod then
		warn("[CombatServer] Style not found:", cacheKey, "— check ServerStorage/CombatStyles/")
		return nil
	end

	local ok, result = pcall(require, mod)
	if not ok then
		warn("[CombatServer] Failed to load style:", cacheKey, "\n", result)
		return nil
	end

	styleCache[cacheKey] = result
	return result
end

local function getPlayerStyle(player)
	local wt  = player:FindFirstChild("Plr_WeaponType")
	local sn  = player:FindFirstChild("Plr_StyleName")
	local weaponType = (wt and wt.Value ~= "") and wt.Value or "Sword"
	local styleName  = (sn and sn.Value ~= "") and sn.Value or "Default"
	return loadStyleModule(weaponType, styleName)
end

-- Create Plr_WeaponType and Plr_StyleName for every player on join
-- if they don't already exist (set by another script).
Players.PlayerAdded:Connect(function(player)
	if not player:FindFirstChild("Plr_WeaponType") then
		local v = Instance.new("StringValue")
		v.Name = "Plr_WeaponType"; v.Value = "Default"; v.Parent = player
	end
	if not player:FindFirstChild("Plr_StyleName") then
		local v = Instance.new("StringValue")
		v.Name = "Plr_StyleName"; v.Value = "Default"; v.Parent = player
	end
end)

-- ============================================================
-- GLOBAL TUNING CONSTANTS
-- ============================================================
local NORMAL_SPEED    = 16
local ATTACK_SPEED    = 7
local PARRY_STUN_TIME = 1.80    -- attacker frozen when parried
local BLOCK_REDUCTION = 0.70    -- fraction of damage absorbed by block
local RATE_LIGHT      = 0.45    -- server minimum seconds between light attacks
local RATE_HEAVY      = 2.00    -- server minimum seconds between heavy attacks

-- ============================================================
-- PER-PLAYER DEBUG FLAGS
-- Toggled by the client via GameSettings remote.
-- When true: the server fires CombatFeedback "DebugHitbox" to
-- ONLY that player's client, which then creates a local Part
-- only they can see. The server NEVER creates the Part itself.
-- This is why the old code showed hitboxes for everyone — it was
-- creating a workspace Part replicated to all clients.
-- ============================================================
local debugPlayers = {}   -- [userId] = true/false

-- ============================================================
-- UTILITY FUNCTIONS
-- ============================================================

local function getAnimator(character)
	local hum = character:FindFirstChildOfClass("Humanoid")
	return hum and hum:FindFirstChildOfClass("Animator")
end

-- Applies (or refreshes) a "Stunned" BoolValue.
-- Also clears the character's block state so the server never
-- thinks a stunned character is still blocking.
local function applyStun(character, duration)
	if not character then return end

	-- Always clear block state when stunned — this is the core
	-- fix for "subsequent attacks bypass guard after heavy."
	-- A stunned character cannot be blocking on the server anymore.
	CombatState.ClearBlockOnStun(character)

	local existing = character:FindFirstChild("Stunned")
	if existing then
		Debris:AddItem(existing, duration)   -- refresh timer
		return
	end
	local bool  = Instance.new("BoolValue")
	bool.Name   = "Stunned"
	bool.Parent = character
	Debris:AddItem(bool, duration)
end

-- Scales impulse by AssemblyMass so knockback feels the same
-- regardless of how heavy the character rig is.
local function applyImpulse(rootPart, direction, force)
	if not rootPart or not rootPart.Parent then return end
	if direction.Magnitude < 0.001 then return end
	rootPart:ApplyImpulse(direction.Unit * force * rootPart.AssemblyMass)
end

-- Plays the Hit animation child on the target's Animator.
-- Using track.Stopped to destroy ensures the anim finishes fully
-- before being cleaned up — the old Debris:AddItem(track, 0.3)
-- was destroying the track while it was still playing.
local function playHitAnim(character)
	local anim = getAnimator(character)
	if not anim or not script:FindFirstChild("Hit") then return end
	local track = anim:LoadAnimation(script.Hit)
	track:Play()
	track.Stopped:Once(function() track:Destroy() end)
end

-- Clones a Sound child from this Script and plays it at a location.
local function playSound(soundName, parent)
	local template = script:FindFirstChild(soundName)
	if not template then return end
	local snd = template:Clone()
	snd.Parent = parent
	snd:Play()
	Debris:AddItem(snd, snd.TimeLength + 0.5)
end

-- ============================================================
-- VFX — single burst, no double-play
-- The fix: disable all ParticleEmitters BEFORE parenting the
-- clone (preventing the automatic emission that happens when a
-- particle emitter is first replicated), then call Emit() once.
-- GetDescendants instead of GetChildren catches nested emitters.
-- ============================================================
local function playHitVFX(targetRoot)
	local punch01  = RS:FindFirstChild("Punch-01")
	if not punch01 then return end
	local main     = punch01:FindFirstChild("Main")
	if not main then return end
	local template = main:FindFirstChild("Hit1")
	if not template then return end

	local vfx = template:Clone()

	for _, obj in ipairs(vfx:GetDescendants()) do
		if obj:IsA("ParticleEmitter") then obj.Enabled = false end
	end

	vfx.Parent = targetRoot

	for _, obj in ipairs(vfx:GetDescendants()) do
		if obj:IsA("ParticleEmitter") then
			obj:Emit(obj:GetAttribute("EmitCount") or 12)
		end
	end

	Debris:AddItem(vfx, 2)
end

-- ============================================================
-- HITBOX CAST — workspace:GetPartBoundsInBox
-- Instantaneous, synchronous, deduplicated.
-- Debug visualisation is now client-side only:
--   server fires CombatFeedback "DebugHitbox" to ONLY the
--   attacker if their debug flag is on. The client creates a
--   local Part that replicates to nobody else.
-- ============================================================
local function castHitbox(attackerChar, def, attackerPlayer)
	local root = attackerChar:FindFirstChild("HumanoidRootPart")
	if not root then return {} end

	local params = OverlapParams.new()
	params.FilterDescendantsInstances = { attackerChar }
	params.FilterType = Enum.RaycastFilterType.Exclude

	local boxCF    = root.CFrame * CFrame.new(0, 0, def.hitboxFwd)
	local rawParts = workspace:GetPartBoundsInBox(boxCF, def.hitboxSize, params)

	-- Fire hitbox data to ONLY the attacker's client for local rendering.
	-- The server never touches workspace for this — that was the old bug.
	if attackerPlayer and debugPlayers[attackerPlayer.UserId] then
		CombatFB:FireClient(attackerPlayer, {
			type = "DebugHitbox",
			cf   = boxCF,
			size = def.hitboxSize,
		})
	end

	local results, seen = {}, {}
	for _, part in ipairs(rawParts) do
		local model = part.Parent
		if model
			and not seen[model]
			and model ~= attackerChar
			and model:FindFirstChildOfClass("Humanoid")
		then
			seen[model] = true
			table.insert(results, model)
		end
	end
	return results
end

-- ============================================================
-- CORE ATTACK HANDLER
-- Spawned via task.spawn so windupWait can yield freely without
-- blocking the OnServerEvent handler for other players.
-- ============================================================
local function handleAttack(attackerPlayer, def)
	local attackerChar = attackerPlayer.Character
	if not attackerChar then return end
	local attackerRoot = attackerChar:FindFirstChild("HumanoidRootPart")
	if not attackerRoot then return end
	local attackerHum  = attackerChar:FindFirstChildOfClass("Humanoid")

	-- Slow the attacker during their swing commitment window.
	if attackerHum then
		attackerHum.WalkSpeed = ATTACK_SPEED
		task.delay(def.windupWait + 0.40, function()
			if attackerHum and attackerHum.Parent then
				attackerHum.WalkSpeed = NORMAL_SPEED
			end
		end)
	end

	-- Small forward lunge on the attacker.
	applyImpulse(attackerRoot, attackerRoot.CFrame.LookVector, def.selfImpulse)

	-- Wait until the animation hit-frame before casting the hitbox.
	-- Re-validate after the yield — the attacker may have been stunned
	-- or disconnected during the windup.
	task.wait(def.windupWait)
	if not attackerChar.Parent then return end
	if attackerChar:FindFirstChild("Stunned") then return end

	local hitChars = castHitbox(attackerChar, def, attackerPlayer)

	for _, targetChar in ipairs(hitChars) do
		local targetHum = targetChar:FindFirstChildOfClass("Humanoid")
		if not targetHum or targetHum.Health <= 0 then continue end

		local targetRoot   = targetChar:FindFirstChild("HumanoidRootPart")
		if not targetRoot then continue end

		if RagdollUtil.IsRagdolled(targetChar) then continue end

		local targetPlayer = Players:GetPlayerFromCharacter(targetChar)
		local blockState   = CombatState.GetBlockState(targetChar)

		-- ── Branch 1: PARRY ───────────────────────────────────
		if blockState == "parrying" then
			-- Perfect parry: zero damage, attacker stunned and pushed back.
			applyStun(attackerChar, PARRY_STUN_TIME)
			applyImpulse(attackerRoot, -attackerRoot.CFrame.LookVector, 22)
			playSound("Parry Clash", targetRoot)

			if targetPlayer then
				CombatState.OnParrySuccess(targetPlayer)
				CombatFB:FireClient(targetPlayer, { type = "ParrySuccess" })
			end
			CombatFB:FireClient(attackerPlayer, { type = "ParriedByOpponent" })
			continue

			-- ── Branch 2: BLOCK (regular attacks only) ────────────
			-- Heavy attacks have breaksBlock = true and skip this branch.
		elseif blockState == "blocking" and not def.breaksBlock then
			local reduced = math.max(1, math.floor(def.damage * (1 - BLOCK_REDUCTION)))
			targetHum:TakeDamage(reduced)
			applyImpulse(targetRoot, attackerRoot.CFrame.LookVector, 8)
			playSound("Punch Hit", targetRoot)

			if targetPlayer then
				CombatFB:FireClient(targetPlayer, { type = "BlockHit" })
			end
			continue

			-- ── Branch 3: GUARD BREAK ─────────────────────────────
			-- Only reached when blockState == "blocking" AND breaksBlock == true.
			-- Previously this fell through to full damage but never cleared
			-- blockState — so every subsequent attack also "bypassed" guard.
			-- Now we explicitly break the guard before applying damage.
		elseif blockState == "blocking" and def.breaksBlock then
			-- Clear blockState and stamp a guard-broken window.
			-- After this, the target cannot re-guard for GUARD_BREAK_DURATION.
			CombatState.BreakGuard(targetChar)

			if targetPlayer then
				CombatFB:FireClient(targetPlayer, { type = "GuardBroken" })
			end
			-- Fall through: apply full damage below.
		end

		-- ── Branch 4: FULL HIT ────────────────────────────────
		targetHum:TakeDamage(def.damage)

		local fwd   = attackerRoot.CFrame.LookVector
		local kbDir = (fwd + Vector3.new(0, def.knockUpRatio, 0)).Unit
		applyImpulse(targetRoot, kbDir, def.knockback)

		applyStun(targetChar, def.stunTime)
		playHitAnim(targetChar)
		playHitVFX(targetRoot)
		playSound("Punch Hit", targetRoot)

		-- Special moves can call RagdollUtil here.
		-- Example (for a command grab finisher once grabs are added):
		--   if def.ragdoll then
		--       RagdollUtil.Ragdoll(targetChar, def.ragdollDuration, kbDir * def.knockback * 0.5)
		--   end
	end
end

-- ============================================================
-- REMOTE: Combat  (client → server)
-- Payload must be a table with an "action" string field.
-- ============================================================
Combat.OnServerEvent:Connect(function(player, data)
	if typeof(data) ~= "table" or not data.action then return end

	local character = player.Character
	if not character then return end
	if character:FindFirstChild("Stunned") then return end

	local state  = CombatState.Get(player)
	local now    = os.clock()
	local action = data.action

	-- Load the player's current style module.
	local style = getPlayerStyle(player)
	if not style then return end

	if action == "Regular" or action == "Last" then
		if now - state.lastLightTime < RATE_LIGHT then return end
		state.lastLightTime = now
		local def = style.attacks[action]
		if def then task.spawn(handleAttack, player, def) end

	elseif action == "Heavy" then
		if now - state.lastHeavyTime < RATE_HEAVY then return end
		state.lastHeavyTime = now
		state.lastLightTime = now   -- share the slot so you can't chain light after heavy
		local def = style.attacks.Heavy
		if def then task.spawn(handleAttack, player, def) end

	elseif action == "BlockStart" then
		-- Refuse if still inside a guard-break window.
		if not CombatState.CanBlock(player) then return end

		if state.parryExpireTask then
			task.cancel(state.parryExpireTask)
			state.parryExpireTask = nil
		end

		if state.parryReady then
			-- Open parry window. If nothing hits before it expires,
			-- OnParryWhiff fires the punishment cooldown.
			state.blockState = "parrying"
			state.parryExpireTask = task.delay(CombatData.PARRY_WINDOW, function()
				if state.blockState == "parrying" then
					CombatState.OnParryWhiff(player)
					CombatFB:FireClient(player, { type = "ParryWhiff" })
				end
				state.parryExpireTask = nil
			end)
		else
			-- Parry on cooldown: go straight to regular block, no parry window.
			state.blockState = "blocking"
		end

	elseif action == "BlockEnd" then
		if state.parryExpireTask then
			task.cancel(state.parryExpireTask)
			state.parryExpireTask = nil
		end
		-- If player releases block while still in parry state,
		-- the parry attempt was a quick tap that hit nothing — whiff.
		if state.blockState == "parrying" then
			CombatState.OnParryWhiff(player)
			CombatFB:FireClient(player, { type = "ParryWhiff" })
		end
		state.blockState = nil
	end
end)

-- ============================================================
-- REMOTE: GameSettings  (client → server)
-- Only DebugMode is server-relevant. Everything else in the
-- settings panel is handled purely on the client.
-- ============================================================
if GameSettingsRE then
	GameSettingsRE.OnServerEvent:Connect(function(player, data)
		if typeof(data) ~= "table" then return end
		if data.setting == "DebugMode" then
			debugPlayers[player.UserId] = data.value == true
		end
	end)
end

Players.PlayerRemoving:Connect(function(player)
	debugPlayers[player.UserId] = nil
end)