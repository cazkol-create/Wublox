-- @ScriptType: Script
-- @ScriptType: Script
-- ============================================================
--  CombatServer.lua  |  Script (NOT ModuleScript)
--  Location: ServerScriptService
--
--  CHANGES IN THIS VERSION (Patch 2):
--
--  1. COMBAT TAG INTEGRATION
--     • CombatTag.Tag(attackerPlayer) called at the top of handleAttack.
--     • CombatTag.Tag(targetPlayer) called after TakeDamage in the full-hit
--       branch so the defender's regen is also paused.
--
--  2. RUNNING ATTACK
--     • New "RunAttack" action received from CombatClient when player M1s
--       while sprinting.  Uses style.attacks.runAttack def.
--     • Does NOT touch combo counter — completely separate from M1 chain.
--
--  3. SLIDE GROUND CHECK
--     • Server now rejects Slide actions when the character is airborne
--       (FloorMaterial == Air).
--
--  Previous patch notes (Patch 1) retained below:
--
--  COMBO FIX — "ghost M1" and sluggish linking resolved
--  CLIENT-SIDE SOUNDS — SoundFX UnreliableRemoteEvent
--  I-FRAMES ON DASHES
--  SLIDE ACTION
-- ============================================================

local Players    = game:GetService("Players")
local SS         = game:GetService("ServerStorage")
local Debris     = game:GetService("Debris")
local RS         = game:GetService("ReplicatedStorage")

local CombatConfig     = require(script.Parent.Modules.CombatConfig)
local CombatState      = require(script.Parent.Modules.CombatState)
local CombatTag        = require(script.Parent.Modules.CombatTag)
local RagdollUtil      = require(script.Parent.Modules.RagdollUtil)
local StatusEffectUtil = require(script.Parent.Modules.StatusEffectUtil)
local KnockdownUtil    = require(script.Parent.Modules.KnockdownUtil)
local MovementUtil     = require(script.Parent.Modules.MovementUtil)
local SkillSystem      = require(script.Parent.Modules.SkillSystem)
local MuchachoHitbox   = require(script.Parent.Modules.MuchachoHitbox)
local InventoryData    = require(RS.Modules.InventoryData)

-- ── Remotes ───────────────────────────────────────────────────
local function getOrCreate(parent, name, class)
	local e = parent:FindFirstChild(name)
	if e then return e end
	local obj = Instance.new(class); obj.Name = name; obj.Parent = parent; return obj
end

local Combat            = RS:WaitForChild("Combat")
local CombatFeedback    = RS:WaitForChild("CombatFeedback")
local GameSettingsRE    = RS:WaitForChild("GameSettings", 5)
local ChangeStyle       = RS:WaitForChild("ChangeStyle", 15)
local UseSkill          = getOrCreate(RS, "UseSkill",          "RemoteEvent")
local EquipSkillRE      = getOrCreate(RS, "EquipSkill",        "RemoteEvent")
local UnequipSkillRE    = getOrCreate(RS, "UnequipSkill",      "RemoteEvent")
local CharacterFeedback = getOrCreate(RS, "CharacterFeedback", "RemoteEvent")
local CombatFX          = getOrCreate(RS, "CombatFX",          "UnreliableRemoteEvent")
local SoundFX           = getOrCreate(RS, "SoundFX",           "UnreliableRemoteEvent")

-- ============================================================
-- DEVELOPER CONFIG
-- ============================================================
local CONFIG = {
	RATE_FLOURISH            = 2.20,
	RATE_HEAVY               = 2.00,
	DEFAULT_HIT_WINDOW       = 0.15,
	VELOCITY_PREDICTION      = true,
	VELOCITY_PREDICTION_TIME = 0.15,
}

local debugPlayers = {}

-- ============================================================
-- STYLE LOADER
-- ============================================================
local styleCache   = {}
local stylesFolder = SS:WaitForChild("CombatStyles", 10)

local function loadStyleModule(wt, sn)
	local key = wt .. "/" .. sn
	if styleCache[key] then return styleCache[key] end
	local wf  = stylesFolder and stylesFolder:FindFirstChild(wt)
	local mod = wf and (wf:FindFirstChild(sn) or wf:FindFirstChild("Default"))
	if not mod then warn("[CombatServer] Style not found:", key); return nil end
	local ok, result = pcall(require, mod)
	if not ok then warn("[CombatServer] Failed:", key, result); return nil end
	styleCache[key] = result; return result
end

local function getPlayerStyle(player)
	local wt = player:FindFirstChild("Plr_WeaponType")
	local sn = player:FindFirstChild("Plr_StyleName")
	return loadStyleModule(
		(wt and wt.Value ~= "") and wt.Value or "Fist",
		(sn and sn.Value ~= "") and sn.Value or "Default"
	)
end

local function getMaxCombo(style)
	if style.comboLength then return style.comboLength end
	if style.attacks and style.attacks.comboHits then
		local n = 0; for _ in pairs(style.attacks.comboHits) do n += 1 end
		if n > 0 then return n end
	end
	return 3
end

Players.PlayerAdded:Connect(function(player)
	local function sv(name, val)
		if not player:FindFirstChild(name) then
			local v = Instance.new("StringValue"); v.Name=name; v.Value=val; v.Parent=player
		end
	end
	sv("Plr_WeaponType",""); sv("Plr_StyleName","")
	SkillSystem.InitPlayer(player)
end)

-- ============================================================
-- UTILITY
-- ============================================================
local function getEquippedTool(char)
	if not char then return nil end
	for _, obj in ipairs(char:GetChildren()) do
		if obj:IsA("Tool") then return obj end
	end
end

local function getAnimator(char)
	local hum = char:FindFirstChildOfClass("Humanoid")
	return hum and hum:FindFirstChildOfClass("Animator")
end

local function applyStun(char, dur)
	if not char then return end
	StatusEffectUtil.Apply(char, "Hitstun", dur)
	CombatState.ClearBlockOnStun(char)
end

local function applyImpulse(root, dir, force)
	if not root or not root.Parent then return end
	if dir.Magnitude < 0.001 then return end
	root:ApplyImpulse(dir.Unit * force * root.AssemblyMass)
end

local function applyKnockdown(char, knockType, dur)
	if knockType == "soft" then KnockdownUtil.ApplySoftKnockdown(char, dur)
	elseif knockType == "hard" then KnockdownUtil.ApplyHardKnockdown(char, dur) end
end

local function playHitAnim(char)
	local anim = getAnimator(char)
	if not anim or not script:FindFirstChild("Hit") then return end
	local track = anim:LoadAnimation(script.Hit); track:Play()
	track.Stopped:Once(function() track:Destroy() end)
end

-- ============================================================
-- SOUND HELPER
-- ============================================================
local function fireSound(soundType, position)
	SoundFX:FireAllClients({ type = soundType, position = position })
end

-- ============================================================
-- HITBOX  — MuchachoHitbox  (DO NOT MODIFY THIS SECTION)
-- ============================================================
local function castHitbox(attackerChar, def, attackerPlayer, onHitFn)
	local root = attackerChar:FindFirstChild("HumanoidRootPart")
	if not root then return CONFIG.DEFAULT_HIT_WINDOW end

	local hitWindow = def.hitWindow or CONFIG.DEFAULT_HIT_WINDOW

	if attackerPlayer and debugPlayers[attackerPlayer.UserId] then
		CombatFX:FireClient(attackerPlayer, {
			type               = "DebugHitbox",
			cf                 = root.CFrame * CFrame.new(0, 0, def.hitboxFwd or -4),
			size               = def.hitboxSize or Vector3.new(5,5,5),
			velocityPrediction = CONFIG.VELOCITY_PREDICTION,
			vpTime             = CONFIG.VELOCITY_PREDICTION_TIME,
		})
	end

	local hb = MuchachoHitbox.CreateHitbox()
	hb.Size            = def.hitboxSize or Vector3.new(5,5,5)
	hb.CFrame          = root
	hb.Offset          = CFrame.new(0, 0, def.hitboxFwd or -4)
	hb.FilterCharacter = attackerChar
	hb.HitOnce         = true
	hb.Visualizer      = false

	hb.Touched:Connect(function(hit, humanoid)
		if not humanoid then return end
		local targetChar = humanoid.Parent
		if not targetChar or targetChar == attackerChar then return end
		if humanoid.Health <= 0 then return end
		local targetRoot = targetChar:FindFirstChild("HumanoidRootPart")
		if not targetRoot then return end
		if RagdollUtil.IsRagdolled(targetChar) then return end
		if targetChar:FindFirstChild("IFrames") then return end
		onHitFn(targetChar, humanoid)
	end)

	hb:Start()
	task.delay(hitWindow, function() hb:Stop() end)
	return hitWindow
end

-- ============================================================
-- CORE ATTACK HANDLER
-- ============================================================
local function handleAttack(attackerPlayer, def, style)
	-- Tag attacker as in-combat; pauses their health regen
	CombatTag.Tag(attackerPlayer)

	local attackerChar = attackerPlayer.Character; if not attackerChar then return end
	local attackerRoot = attackerChar:FindFirstChild("HumanoidRootPart"); if not attackerRoot then return end
	local attackerHum  = attackerChar:FindFirstChildOfClass("Humanoid")

	local postHitEndlag = (def.endlag and def.endlag > 0) and def.endlag
		or CombatConfig.DEFAULT_COMBO_ENDLAG
	CombatState.SetEndlag(attackerPlayer, postHitEndlag)
	CharacterFeedback:FireClient(attackerPlayer, {
		type     = "EndlagStart",
		duration = postHitEndlag,
	})

	local function finalize()
		local remaining = CombatState.DecrementAttackCount(attackerPlayer)
		if remaining == 0 and attackerHum and attackerHum.Parent then
			if StatusEffectUtil.BlocksAttack(attackerChar) then return end
			local state = CombatState.Get(attackerPlayer)
			attackerHum.WalkSpeed = state.blockState
				and CombatConfig.BLOCK_SPEED
				or  CombatConfig.NORMAL_SPEED
		end
	end

	if attackerHum then attackerHum.WalkSpeed = CombatConfig.ATTACK_SPEED end

	local velDef = def.velocity
	if velDef and (velDef.timing == "start" or velDef.timing == nil) then
		MovementUtil.ApplyVelocity(attackerRoot, velDef)
	end

	task.wait(def.windupWait or 0)

	if velDef and velDef.timing == "hit" then
		MovementUtil.ApplyVelocity(attackerRoot, velDef)
	end

	CombatState.SetAttacking(attackerPlayer, 0)

	if not attackerChar.Parent then finalize(); return end
	if StatusEffectUtil.BlocksAttack(attackerChar) then finalize(); return end

	local attackDir = attackerRoot.CFrame.LookVector

	fireSound("swing", attackerRoot.Position)

	local hitWindow = castHitbox(attackerChar, def, attackerPlayer, function(targetChar, humanoid)
		local targetHum    = humanoid
		local targetRoot   = targetChar:FindFirstChild("HumanoidRootPart")
		if not targetRoot then return end
		local hitPos       = targetRoot.Position
		local targetPlayer = Players:GetPlayerFromCharacter(targetChar)
		local blockState   = CombatState.GetBlockState(targetChar)

		-- ── Parry ──────────────────────────────────────────────
		if blockState == "parrying" then
			applyStun(attackerChar, CombatConfig.PARRY_STUN_TIME)
			applyImpulse(attackerRoot, -attackDir, 22)
			fireSound("parryClash", hitPos)
			if targetPlayer then
				CombatState.OnParrySuccess(targetPlayer)
				CombatFeedback:FireClient(targetPlayer, {type="ParrySuccess", pos=hitPos})
			end
			CombatFeedback:FireClient(attackerPlayer, {type="ParriedByOpponent", pos=hitPos})
			return

				-- ── Block ──────────────────────────────────────────────
		elseif blockState == "blocking" and not def.breaksBlock then
			local reduced = math.max(1, math.floor(def.damage*(1-CombatConfig.BLOCK_REDUCTION)))
			targetHum:TakeDamage(reduced)
			applyImpulse(targetRoot, attackDir, 8)
			fireSound("blockHit", hitPos)
			if targetPlayer then CombatFX:FireClient(targetPlayer, {type="BlockHit", pos=hitPos}) end
			return

				-- ── Guard Break ────────────────────────────────────────
		elseif blockState == "blocking" and def.breaksBlock then
			CombatState.BreakGuard(targetChar)
			if targetPlayer then
				CombatFeedback:FireClient(targetPlayer, {type="GuardBroken", pos=hitPos})
			end
		end

		-- ── Full Hit ───────────────────────────────────────────
		targetHum:TakeDamage(def.damage)
		-- Tag the defender as in-combat so their regen is also paused
		if targetPlayer then CombatTag.Tag(targetPlayer) end

		local kbDir = (attackDir + Vector3.new(0, def.knockUpRatio or 0.1, 0)).Unit
		applyImpulse(targetRoot, kbDir, def.knockback)
		applyStun(targetChar, def.stunTime)
		playHitAnim(targetChar)
		fireSound("hit", hitPos)

		CombatFX:FireClient(attackerPlayer, {type="HitConnected", pos=hitPos})
		if targetPlayer then CombatFX:FireClient(targetPlayer, {type="YouWereHit", pos=hitPos}) end

		if def.canSoftKnockdown then
			applyKnockdown(targetChar, "soft", def.knockdownDuration)
		elseif def.canHardKnockdown then
			applyKnockdown(targetChar, "hard", def.knockdownDuration)
		elseif def.ragdoll then
			RagdollUtil.Ragdoll(targetChar, def.ragdollDuration or 2.5, kbDir*(def.knockback*0.4))
		end
	end)

	task.wait(hitWindow or CONFIG.DEFAULT_HIT_WINDOW)
	finalize()
end

-- ============================================================
-- REMOTE: Combat
-- ============================================================
Combat.OnServerEvent:Connect(function(player, data)
	if not data.action then return end

	local character = player.Character; if not character then return end
	local hum = character:FindFirstChildOfClass("Humanoid")
	if not hum or hum.Health <= 0 then return end

	if StatusEffectUtil.BlocksAttack(character) then return end
	if CombatState.IsInEndlag(player)           then return end

	local state = CombatState.Get(player)
	local now   = os.clock()

	-- ── M1 ────────────────────────────────────────────────────
	if data.action == "M1" then
		if not getEquippedTool(character) then return end
		local style = getPlayerStyle(player); if not style then return end

		local flourishCD = (style.attacks.Last and style.attacks.Last.serverCD) or CONFIG.RATE_FLOURISH
		if now - state.lastFlourishTime < flourishCD then return end

		local maxCombo = getMaxCombo(style)
		local comboIdx = CombatState.GetCombo(player)
		local def, trackName

		if comboIdx >= maxCombo then
			def       = style.attacks["Last"]
			trackName = "M" .. maxCombo
			if not def then return end
			state.lastFlourishTime = now
			state.lastLightTime    = now
			CombatState.ResetCombo(player)
			CombatState.SetAttacking(player, (def.windupWait or 0) + (def.hitWindow or CONFIG.DEFAULT_HIT_WINDOW) + 0.05)
		else
			def = (style.attacks.comboHits and style.attacks.comboHits[comboIdx]) or style.attacks["Regular"]
			trackName = "M" .. comboIdx
			if not def then return end
			state.lastLightTime = now
			local resetTime = def.resetTimer or 1.5
			CombatState.IncrementCombo(player, resetTime)
			CombatState.SetAttacking(player, (def.windupWait or 0) + (def.hitWindow or CONFIG.DEFAULT_HIT_WINDOW) + 0.05)
		end

		local preLockDur = (def.windupWait or 0) + (def.hitWindow or CONFIG.DEFAULT_HIT_WINDOW) + CombatConfig.COMBO_PRELOCK_BUFFER
		CombatState.SetEndlag(player, preLockDur)

		CombatFeedback:FireClient(player, {
			type      = "PlayAttackAnim",
			track     = trackName,
			soundType = "swing",
		})

		task.spawn(handleAttack, player, def, style)

		-- ── Heavy ─────────────────────────────────────────────────
	elseif data.action == "Heavy" then
		if not getEquippedTool(character) then return end
		local style = getPlayerStyle(player); if not style then return end
		local def = style.attacks["Heavy"]; if not def then return end

		local serverCD = def.serverCD or CONFIG.RATE_HEAVY
		if now - state.lastHeavyTime < serverCD then return end
		if CombatState.IsAttacking(player) then return end

		state.lastHeavyTime = now; state.lastLightTime = now
		CombatState.SetAttacking(player, (def.windupWait or 0) + 0.05)

		local preLockDur = (def.windupWait or 0) + (def.hitWindow or CONFIG.DEFAULT_HIT_WINDOW) + CombatConfig.COMBO_PRELOCK_BUFFER
		CombatState.SetEndlag(player, preLockDur)

		CombatFeedback:FireClient(player, {
			type      = "PlayAttackAnim",
			track     = "Heavy",
			soundType = "swing",
		})
		task.spawn(handleAttack, player, def, style)

		-- ── Running Attack ────────────────────────────────────────
	elseif data.action == "RunAttack" then
		if not getEquippedTool(character) then return end
		if CombatState.IsAttacking(player) then return end

		local style = getPlayerStyle(player); if not style then return end
		local def   = style.attacks and style.attacks.runAttack
		if not def then return end

		local serverCD = def.serverCD or 0.6
		if now - (state.lastRunAttackTime or 0) < serverCD then return end
		state.lastRunAttackTime = now

		local preLockDur = (def.windupWait or 0) + (def.hitWindow or CONFIG.DEFAULT_HIT_WINDOW) + CombatConfig.COMBO_PRELOCK_BUFFER
		CombatState.SetEndlag(player, preLockDur)
		CombatState.SetAttacking(player, preLockDur)

		CombatFeedback:FireClient(player, {
			type  = "PlayRunAttackAnim",
			track = "RunAttack",
		})
		task.spawn(handleAttack, player, def, style)

		-- ── Block ─────────────────────────────────────────────────
	elseif data.action == "BlockStart" then
		if not getEquippedTool(character) then return end
		if not CombatState.CanBlock(player) then return end
		if state.parryExpireTask then task.cancel(state.parryExpireTask); state.parryExpireTask=nil end

		if hum then hum.WalkSpeed = CombatConfig.BLOCK_SPEED end

		if state.parryReady then
			state.blockState = "parrying"
			state.parryExpireTask = task.delay(CombatConfig.PARRY_WINDOW, function()
				if state.blockState == "parrying" then
					CombatState.OnParryWhiff(player)
					CombatFeedback:FireClient(player, {type="ParryWhiff"})
				end
				state.parryExpireTask = nil
			end)
		else
			state.blockState = "blocking"
		end

	elseif data.action == "BlockEnd" then
		if state.parryExpireTask then task.cancel(state.parryExpireTask); state.parryExpireTask=nil end
		if state.blockState == "parrying" then
			CombatState.OnParryWhiff(player)
			CombatFeedback:FireClient(player, {type="ParryWhiff"})
		end
		state.blockState = nil
		if hum then hum.WalkSpeed = CombatConfig.NORMAL_SPEED end

		-- ── Evasive Dash ──────────────────────────────────────────
	elseif data.action == "EvasiveDash" then
		if not StatusEffectUtil.CanEvasiveDash(character) then return end
		if not CombatState.CanEvasiveDash(player) then return end
		task.spawn(MovementUtil.EvasiveDash, player, character)

		-- ── Normal Dash ───────────────────────────────────────────
	elseif data.action == "NormalDash" then
		if not CombatState.CanNormalDash(player) then return end
		task.spawn(MovementUtil.NormalDash, player, character, data.direction)

		-- ── Slide ─────────────────────────────────────────────────
	elseif data.action == "Slide" then
		if StatusEffectUtil.BlocksAttack(character) then return end
		if RagdollUtil.IsRagdolled(character) then return end
		if not CombatState.CanSlide(player) then return end
		-- Reject slides while airborne
		if hum and hum.FloorMaterial == Enum.Material.Air then return end

		state.slideCooldownUntil = now + CombatConfig.SLIDE_COOLDOWN
		if MovementUtil.Slide then
			task.spawn(MovementUtil.Slide, player, character)
		else
			warn("Slide function missing in MovementUtil")
		end

		-- ── Dash Attack ───────────────────────────────────────────
	elseif data.action == "DashAttack" then
		if not getEquippedTool(character) then return end
		if CombatState.IsAttacking(player) then return end
		local style   = getPlayerStyle(player); if not style then return end
		local dashDef = style.attacks.dashAttack; if not dashDef then return end
		local helpers = {
			applyStun      = applyStun,
			applyImpulse   = applyImpulse,
			castHitbox     = castHitbox,
			playHitAnim    = playHitAnim,
			playHitVFX     = function() end,
			playHitSound   = function(r) fireSound("hit", r.Position) end,
			CombatFB       = CombatFX,
			applyKnockdown = applyKnockdown,
		}
		CombatState.SetAttacking(player, dashDef.dashDuration + 0.5)
		task.spawn(MovementUtil.DashAttack, player, dashDef, style, helpers)
	end
end)

-- ============================================================
-- REMOTE: UseSkill
-- ============================================================
UseSkill.OnServerEvent:Connect(function(player, data)
	if typeof(data) ~= "table" or not data.skillId then return end
	if CombatState.IsInEndlag(player) then return end
	CombatTag.Tag(player)
	SkillSystem.ExecuteSkill(player, data.skillId)
end)

EquipSkillRE.OnServerEvent:Connect(function(player, data)
	if typeof(data) ~= "table" or not data.skillId then return end
	local ok, reason = SkillSystem.EquipSkill(player, data.skillId)
	CombatFeedback:FireClient(player, {
		type    = "SkillEquipResult",
		skillId = data.skillId,
		success = ok,
		reason  = reason or "",
	})
end)

UnequipSkillRE.OnServerEvent:Connect(function(player, data)
	if typeof(data) ~= "table" or not data.skillId then return end
	SkillSystem.UnequipSkill(player, data.skillId)
end)

-- ============================================================
-- REMOTE: ChangeStyle
-- ============================================================
if ChangeStyle then
	ChangeStyle.OnServerEvent:Connect(function(player, data)
		if typeof(data) ~= "table" or not data.styleName then return end
		local char = player.Character; if not char then return end
		if not char:FindFirstChildOfClass("Tool") then return end
		local wt = player:FindFirstChild("Plr_WeaponType")
		local sn = player:FindFirstChild("Plr_StyleName")
		if not wt or not sn then return end
		local allowed = InventoryData.GetStyles(wt.Value)
		for _, s in ipairs(allowed) do
			if s == data.styleName then sn.Value = data.styleName; return end
		end
	end)
end

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
	if player.Character then StatusEffectUtil.ClearAll(player.Character) end
end)