-- @ScriptType: Script
-- @ScriptType: Script
-- ============================================================
--  CombatServer.lua  |  Script  (NOT ModuleScript)
--  Location: ServerScriptService
--
--  PIPELINE: Client input → Server logic → Client output (visuals)
--
--  CHANGES:
--    CombatFX (UnreliableRemoteEvent) — ALL cosmetic events
--      (attack animations, hit effects, sounds, VFX) are fired
--      through this unreliable channel.  These are visual flare
--      only; the game remains correct even if a packet drops.
--
--    CombatFeedback (RemoteEvent, reliable) — gameplay-critical
--      events only: ParrySuccess, GuardBroken, ParryWhiff,
--      SkillCooldown, SkillEquipResult.
--
--    MuchachoHitbox fix — hb:Stop() only; MuchachoHitbox has
--      AutoDestroy = true by default so the hitbox cleans itself
--      up on Stop.  Calling Destroy() after Stop was causing the
--      "attempt to destroy already-destroyed object" error.
--
--    Server-side combo — CombatState.GetCombo() / IncrementCombo()
--      own the combo counter.  Client sends action="M1" with no
--      index; server picks the correct comboHit def and tells the
--      client which animation to play via CombatFX.
--
--    NormalDash action — handled here; delegates to MovementUtil.
-- ============================================================

local Players    = game:GetService("Players")
local SS         = game:GetService("ServerStorage")
local Debris     = game:GetService("Debris")
local RS         = game:GetService("ReplicatedStorage")

local CombatData      = require(RS.Modules.CombatData)
local CombatState     = require(script.Parent.Modules.CombatState)
local RagdollUtil     = require(script.Parent.Modules.RagdollUtil)
local StatusEffectUtil= require(script.Parent.Modules.StatusEffectUtil)
local KnockdownUtil   = require(script.Parent.Modules.KnockdownUtil)
local MovementUtil    = require(script.Parent.Modules.MovementUtil)
local SkillSystem     = require(script.Parent.Modules.SkillSystem)
local MuchachoHitbox  = require(script.Parent.Modules.MuchachoHitbox)
local SoundUtil       = require(RS.Modules.SoundUtil)
local InventoryData   = require(RS.Modules.InventoryData)

-- ── Remote helpers ────────────────────────────────────────────
local function getOrCreate(parent, name, class)
	local e = parent:FindFirstChild(name)
	if e then return e end
	local obj = Instance.new(class); obj.Name = name; obj.Parent = parent; return obj
end

-- Reliable: gameplay-critical events
local Combat            = RS:WaitForChild("Combat")
local CombatFeedback    = RS:WaitForChild("CombatFeedback")    -- ReliableRemoteEvent
local GameSettingsRE    = RS:WaitForChild("GameSettings", 5)
local ChangeStyle       = RS:WaitForChild("ChangeStyle", 15)
local UseSkill          = getOrCreate(RS, "UseSkill",          "RemoteEvent")
local EquipSkillRE      = getOrCreate(RS, "EquipSkill",        "RemoteEvent")
local UnequipSkillRE    = getOrCreate(RS, "UnequipSkill",      "RemoteEvent")
local CharacterFeedback = getOrCreate(RS, "CharacterFeedback", "RemoteEvent")

-- Unreliable: all cosmetic output (animations, VFX, sounds)
-- UnreliableRemoteEvent — packets may drop; that is acceptable for visual flare.
local CombatFX = getOrCreate(RS, "CombatFX", "UnreliableRemoteEvent")

-- ============================================================
-- DEVELOPER CONFIG
-- ============================================================
local CONFIG = {
	NORMAL_SPEED    = 16,
	ATTACK_SPEED    = 7,
	PARRY_STUN_TIME = 1.80,
	BLOCK_REDUCTION = 0.70,
	RATE_LIGHT      = 0.45,   -- fallback when def.serverCD absent
	RATE_HEAVY      = 2.00,
	RATE_FLOURISH   = 2.20,
	DEFAULT_HIT_WINDOW      = 0.15,
	VELOCITY_PREDICTION     = true,
	VELOCITY_PREDICTION_TIME= 0.15,
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

Players.PlayerAdded:Connect(function(player)
	local function sv(name, val)
		if not player:FindFirstChild(name) then
			local v=Instance.new("StringValue"); v.Name=name; v.Value=val; v.Parent=player
		end
	end
	sv("Plr_WeaponType", ""); sv("Plr_StyleName", "")
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

local function playHitSound(root, style)
	if style and style.sounds and style.sounds.hitId
		and style.sounds.hitId ~= "" and style.sounds.hitId ~= "rbxassetid://0"
	then SoundUtil.Play(style.sounds.hitId, root); return end
	local sounds = CombatData.GetSounds(
		style and style.weaponType or "Fist",
		style and style.styleName  or "Default"
	)
	if sounds.hitId and sounds.hitId ~= "" and sounds.hitId ~= "rbxassetid://0" then
		SoundUtil.Play(sounds.hitId, root); return
	end
	local tpl = script:FindFirstChild("Punch Hit")
	if tpl then local s=tpl:Clone(); s.Parent=root; s:Play(); Debris:AddItem(s,s.TimeLength+0.5) end
end

local function playParrySound(root)
	local tpl = script:FindFirstChild("Parry Clash")
	if tpl then local s=tpl:Clone(); s.Parent=root; s:Play(); Debris:AddItem(s,s.TimeLength+0.5) end
end

-- ============================================================
-- HITBOX  — MuchachoHitbox
-- NOTE: hb:Stop() only — AutoDestroy handles cleanup.
--       Calling hb:Destroy() after hb:Stop() was causing errors.
-- ============================================================
local function castHitbox(attackerChar, def, attackerPlayer, onHitFn)
	local root = attackerChar:FindFirstChild("HumanoidRootPart")
	if not root then return CONFIG.DEFAULT_HIT_WINDOW end

	local hitWindow = def.hitWindow or CONFIG.DEFAULT_HIT_WINDOW

	-- Fire debug event to attacker's client for visualizer (no server-side viz)
	if attackerPlayer and debugPlayers[attackerPlayer.UserId] then
		CombatFX:FireClient(attackerPlayer, {
			type               = "DebugHitbox",
			cf                 = root.CFrame * CFrame.new(0, 0, def.hitboxFwd or -4),
			size               = def.hitboxSize or Vector3.new(5,5,5),
			velocityPrediction = CONFIG.VELOCITY_PREDICTION,
			vpTime             = CONFIG.VELOCITY_PREDICTION_TIME,
			rootVelocity       = root.AssemblyLinearVelocity,
		})
	end

	local hb = MuchachoHitbox.CreateHitbox()
	hb.Size               = def.hitboxSize or Vector3.new(5,5,5)
	hb.CFrame             = root
	hb.Offset             = CFrame.new(0, 0, def.hitboxFwd or -4)
	hb.VelocityPrediction     = CONFIG.VELOCITY_PREDICTION
	hb.VelocityPredictionTime = CONFIG.VELOCITY_PREDICTION_TIME
	hb.Visualizer         = false   -- client-side visualizer only

	hb.Touched:Connect(function(hit, humanoid)
		if not humanoid then return end
		local targetChar = humanoid.Parent
		if not targetChar or targetChar == attackerChar then return end
		if humanoid.Health <= 0 then return end
		local targetRoot = targetChar:FindFirstChild("HumanoidRootPart")
		if not targetRoot then return end
		if RagdollUtil.IsRagdolled(targetChar) then return end
		onHitFn(targetChar, humanoid)
	end)

	hb:Start()
	-- Stop after hitWindow; AutoDestroy = true means MuchachoHitbox cleans itself up.
	-- DO NOT call hb:Destroy() — it is already destroyed by hb:Stop().
	task.delay(hitWindow, function() hb:Stop() end)

	return hitWindow
end

-- ============================================================
-- CORE ATTACK HANDLER
-- ============================================================
local function handleAttack(attackerPlayer, def, style)
	local attackerChar = attackerPlayer.Character; if not attackerChar then return end
	local attackerRoot = attackerChar:FindFirstChild("HumanoidRootPart"); if not attackerRoot then return end
	local attackerHum  = attackerChar:FindFirstChildOfClass("Humanoid")

	CombatState.IncrementAttackCount(attackerPlayer)
	if attackerHum then attackerHum.WalkSpeed = CONFIG.ATTACK_SPEED end

	local function finalize()
		local remaining = CombatState.DecrementAttackCount(attackerPlayer)
		if remaining == 0 and attackerHum and attackerHum.Parent
			and not StatusEffectUtil.BlocksAttack(attackerChar)
		then
			attackerHum.WalkSpeed = CONFIG.NORMAL_SPEED
		end
	end

	-- Velocity at start
	local velDef = def.velocity
	if velDef and (velDef.timing == "start" or velDef.timing == nil) then
		MovementUtil.ApplyVelocity(attackerRoot, velDef)
	end
	if def.selfImpulse and def.selfImpulse > 0 then
		applyImpulse(attackerRoot, attackerRoot.CFrame.LookVector, def.selfImpulse)
	end

	-- Interrupt flag: catches stun applied DURING windup
	local interrupted = false
	local interruptConn = attackerChar.ChildAdded:Connect(function(child)
		if child.Name=="Stunned" or child.Name=="SoftKnockdown"
			or child.Name=="HardKnockdown" or child.Name=="Ragdolled" then
			interrupted = true
		end
	end)

	task.wait(def.windupWait)
	interruptConn:Disconnect()

	if velDef and velDef.timing == "hit" then
		MovementUtil.ApplyVelocity(attackerRoot, velDef)
	end

	CombatState.SetAttacking(attackerPlayer, 0)

	if not attackerChar.Parent              then finalize(); return end
	if interrupted                          then finalize(); return end
	if StatusEffectUtil.BlocksAttack(attackerChar) then finalize(); return end

	local attackDir = attackerRoot.CFrame.LookVector

	local hitWindow = castHitbox(attackerChar, def, attackerPlayer, function(targetChar, humanoid)
		local targetHum  = humanoid
		local targetRoot = targetChar:FindFirstChild("HumanoidRootPart")
		local hitPos     = targetRoot and targetRoot.Position or Vector3.zero
		local targetPlayer = Players:GetPlayerFromCharacter(targetChar)
		local blockState   = CombatState.GetBlockState(targetChar)

		if blockState == "parrying" then
			applyStun(attackerChar, CONFIG.PARRY_STUN_TIME)
			applyImpulse(attackerRoot, -attackDir, 22)
			playParrySound(targetRoot)
			if targetPlayer then
				CombatState.OnParrySuccess(targetPlayer)
				-- Parry success is gameplay-critical → reliable
				CombatFeedback:FireClient(targetPlayer, {type="ParrySuccess", pos=hitPos})
			end
			-- Attacker feedback → cosmetic (unreliable)
			CombatFX:FireClient(attackerPlayer, {type="ParriedByOpponent", pos=hitPos})
			return

		elseif blockState == "blocking" and not def.breaksBlock then
			local reduced = math.max(1, math.floor(def.damage*(1-CONFIG.BLOCK_REDUCTION)))
			targetHum:TakeDamage(reduced)
			applyImpulse(targetRoot, attackDir, 8)
			playHitSound(targetRoot, style)
			if targetPlayer then
				-- BlockHit is cosmetic → unreliable
				CombatFX:FireClient(targetPlayer, {type="BlockHit", pos=hitPos})
			end
			return

		elseif blockState == "blocking" and def.breaksBlock then
			CombatState.BreakGuard(targetChar)
			if targetPlayer then
				-- GuardBroken is gameplay-critical (client must stop blocking) → reliable
				CombatFeedback:FireClient(targetPlayer, {type="GuardBroken", pos=hitPos})
			end
		end

		-- Full hit
		targetHum:TakeDamage(def.damage)
		local kbDir = (attackDir + Vector3.new(0, def.knockUpRatio or 0.1, 0)).Unit
		applyImpulse(targetRoot, kbDir, def.knockback)
		applyStun(targetChar, def.stunTime)
		playHitAnim(targetChar)
		playHitSound(targetRoot, style)

		-- Hit VFX → cosmetic (unreliable)
		CombatFX:FireClient(attackerPlayer, {type="HitConnected", pos=hitPos})
		if targetPlayer then
			CombatFX:FireClient(targetPlayer, {type="YouWereHit", pos=hitPos})
		end

		-- Knockdown / ragdoll
		if def.canSoftKnockdown then
			applyKnockdown(targetChar, "soft", def.knockdownDuration)
		elseif def.canHardKnockdown then
			applyKnockdown(targetChar, "hard", def.knockdownDuration)
		elseif def.ragdoll then
			RagdollUtil.Ragdoll(targetChar, def.ragdollDuration or 2.5, kbDir*(def.knockback*0.4))
		end
	end)

	task.wait(hitWindow or CONFIG.DEFAULT_HIT_WINDOW)

	if def.endlag and def.endlag > 0 then
		CombatState.SetEndlag(attackerPlayer, def.endlag)
	end

	finalize()
end

-- ============================================================
-- REMOTE: Combat
-- Client input → Server logic → Client output (via CombatFX)
-- ============================================================
Combat.OnServerEvent:Connect(function(player, data)
	if typeof(data) ~= "table" or not data.action then return end
	local character = player.Character; if not character then return end
	if StatusEffectUtil.BlocksAttack(character)  then return end
	if CombatState.IsInEndlag(player)            then return end
	if not getEquippedTool(character)            then return end

	local state = CombatState.Get(player)
	local now   = os.clock()
	local style = getPlayerStyle(player); if not style then return end

	-- ── M1 ─────────────────────────────────────────────────────
	if data.action == "M1" then
		if CombatState.IsAttacking(player) then return end

		local timing = CombatData.GetTiming(
			(player:FindFirstChild("Plr_WeaponType") and player.Plr_WeaponType.Value ~= "" and player.Plr_WeaponType.Value) or "Fist",
			(player:FindFirstChild("Plr_StyleName")  and player.Plr_StyleName.Value  ~= "" and player.Plr_StyleName.Value)  or "Default"
		)
		local maxCombo = style.comboLength or timing.comboLength or 3
		local comboIdx = CombatState.GetCombo(player)

		local def, trackName

		if comboIdx >= maxCombo then
			-- Finisher
			def       = style.attacks["Last"]
			trackName = "M" .. maxCombo
			if not def then return end
			local serverCD = def.serverCD or CONFIG.RATE_FLOURISH
			if now - state.lastFlourishTime < serverCD then return end
			state.lastFlourishTime = now; state.lastLightTime = now
			CombatState.ResetCombo(player)
			CombatState.SetAttacking(player, def.windupWait + 0.05)
		else
			-- Regular combo hit
			def = (style.attacks.comboHits and style.attacks.comboHits[comboIdx])
				or style.attacks["Regular"]
			trackName = "M" .. comboIdx
			if not def then return end
			local serverCD  = def.serverCD or CONFIG.RATE_LIGHT
			if now - state.lastLightTime < serverCD then return end
			state.lastLightTime = now
			local resetTime = def.resetTimer or timing.comboReset or 1.5
			CombatState.IncrementCombo(player, resetTime)
			CombatState.SetAttacking(player, def.windupWait + 0.05)
		end

		-- Tell client which animation to play + which sound to play → unreliable
		CombatFX:FireClient(player, {
			type      = "PlayAttackAnim",
			track     = trackName,
			soundType = "swing",
		})
		task.spawn(handleAttack, player, def, style)

		-- ── Heavy ──────────────────────────────────────────────────
	elseif data.action == "Heavy" then
		local def = style.attacks["Heavy"]; if not def then return end
		local serverCD = def.serverCD or CONFIG.RATE_HEAVY
		if now - state.lastHeavyTime < serverCD then return end
		if CombatState.IsAttacking(player) then return end
		state.lastHeavyTime = now; state.lastLightTime = now
		CombatState.SetAttacking(player, def.windupWait + 0.05)

		CombatFX:FireClient(player, {
			type      = "PlayAttackAnim",
			track     = "Heavy",
			soundType = "swing",
		})
		task.spawn(handleAttack, player, def, style)

		-- ── Block ──────────────────────────────────────────────────
	elseif data.action == "BlockStart" then
		if not CombatState.CanBlock(player) then return end
		if state.parryExpireTask then task.cancel(state.parryExpireTask); state.parryExpireTask=nil end
		if state.parryReady then
			state.blockState = "parrying"
			state.parryExpireTask = task.delay(CombatData.PARRY_WINDOW, function()
				if state.blockState == "parrying" then
					CombatState.OnParryWhiff(player)
					-- ParryWhiff is gameplay-critical → reliable
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

		-- ── EvasiveDash ────────────────────────────────────────────
	elseif data.action == "EvasiveDash" then
		if not StatusEffectUtil.CanEvasiveDash(character) then return end
		if not CombatState.CanEvasiveDash(player) then return end
		task.spawn(MovementUtil.EvasiveDash, player, character)

		-- ── NormalDash ─────────────────────────────────────────────
	elseif data.action == "NormalDash" then
		-- Normal dash has no CC requirement, just a cooldown.
		if not CombatState.CanNormalDash(player) then return end
		task.spawn(MovementUtil.NormalDash, player, character)

		-- ── DashAttack ─────────────────────────────────────────────
	elseif data.action == "DashAttack" then
		if CombatState.IsAttacking(player) then return end
		local dashDef = style.attacks.dashAttack; if not dashDef then return end
		local helpers = {
			applyStun=applyStun, applyImpulse=applyImpulse,
			castHitbox=castHitbox, playHitAnim=playHitAnim,
			playHitVFX=function() end, playHitSound=playHitSound,
			CombatFB=CombatFX, applyKnockdown=applyKnockdown,
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
	SkillSystem.ExecuteSkill(player, data.skillId)
end)

EquipSkillRE.OnServerEvent:Connect(function(player, data)
	if typeof(data) ~= "table" or not data.skillId then return end
	local ok, reason = SkillSystem.EquipSkill(player, data.skillId)
	CombatFeedback:FireClient(player, {type="SkillEquipResult", skillId=data.skillId, success=ok, reason=reason or ""})
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
		if data.setting == "DebugMode" then debugPlayers[player.UserId]=data.value==true end
	end)
end

Players.PlayerRemoving:Connect(function(player)
	debugPlayers[player.UserId] = nil
	if player.Character then StatusEffectUtil.ClearAll(player.Character) end
end)