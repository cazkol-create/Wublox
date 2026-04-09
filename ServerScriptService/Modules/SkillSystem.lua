-- @ScriptType: ModuleScript
-- @ScriptType: ModuleScript
-- Location: ServerScriptService/Modules/SkillSystem
-- CHANGE: MAX_EQUIPPED_SKILLS raised to 6 to match the new 6-slot SkillHUD.
-- Everything else unchanged from the previous version.

local Players       = game:GetService("Players")
local SS            = game:GetService("ServerStorage")
local RS            = game:GetService("ReplicatedStorage")

local SkillRegistry = require(RS.Modules.SkillRegistry)
local RagdollUtil   = require(script.Parent.RagdollUtil)
local KnockdownUtil = require(script.Parent.KnockdownUtil)
local TomatoHitbox  = require(script.Parent.TomatoHitbox)
local CombatState   = require(script.Parent.CombatState)

local SkillSystem = {}

-- ── CHANGE: 6 equipped skill slots ───────────────────────────
local MAX_EQUIPPED_SKILLS = 6
local NORMAL_SPEED        = 16

local skillModuleCache = {}
local skillsFolder     = SS:WaitForChild("Skills", 10)

local _CombatFB, _CharacterFB
local function getCombatFB()
	if not _CombatFB then _CombatFB = RS:FindFirstChild("CombatFeedback") end
	return _CombatFB
end
local function getCharFB()
	if not _CharacterFB then _CharacterFB = RS:FindFirstChild("CharacterFeedback") end
	return _CharacterFB
end

local cooldowns = {}
Players.PlayerRemoving:Connect(function(p) cooldowns[p.UserId]=nil end)

local function loadSkillModule(skillId)
	if skillModuleCache[skillId] then return skillModuleCache[skillId] end
	if not skillsFolder then warn("[SkillSystem] ServerStorage/Skills/ not found"); return nil end
	local mod = skillsFolder:FindFirstChild(skillId)
	if not mod then warn("[SkillSystem] Skill not found:", skillId); return nil end
	local ok, result = pcall(require, mod)
	if not ok then warn("[SkillSystem] Load failed:", skillId, result); return nil end
	skillModuleCache[skillId] = result; return result
end

local function applyImpulse(root, dir, force)
	if not root or not root.Parent then return end
	if dir.Magnitude < 0.001 then return end
	root:ApplyImpulse(dir.Unit * force * root.AssemblyMass)
end

local function applyStunHelper(char, dur)
	if not char then return end
	local SEU = require(script.Parent.StatusEffectUtil)
	SEU.Apply(char, "Hitstun", dur)
	CombatState.ClearBlockOnStun(char)
end

local function applyKnockdown(char, knockType, dur)
	if knockType=="soft" then KnockdownUtil.ApplySoftKnockdown(char, dur)
	elseif knockType=="hard" then KnockdownUtil.ApplyHardKnockdown(char, dur) end
end

local function castHitboxHelper(attackerChar, def, attackerPlayer, onHitFn)
	local root = attackerChar and attackerChar:FindFirstChild("HumanoidRootPart")
	if not root then return end
	local hb = TomatoHitbox.new()
	hb.Size=def.hitboxSize or Vector3.new(5,5,5)
	hb.CFrame=root; hb.Offset=CFrame.new(0,0,def.hitboxFwd or -4)
	hb.FilterCharacter=attackerChar; hb.HitOnce=true; hb.Visualizer=false
	hb.onTouch = function(humanoid)
		local targetChar = humanoid.Parent
		if not targetChar or targetChar==attackerChar then return end
		if humanoid.Health<=0 then return end
		local targetRoot = targetChar:FindFirstChild("HumanoidRootPart")
		if not targetRoot then return end
		if RagdollUtil.IsRagdolled(targetChar) then return end
		onHitFn(targetChar, humanoid)
	end
	hb:Start()
	local hw = def.hitWindow or 0.15
	task.delay(hw, function() hb:Stop(); hb:Destroy() end)
end

local function playHitAnimHelper(char)
	local hum  = char and char:FindFirstChildOfClass("Humanoid")
	local anim = hum and hum:FindFirstChildOfClass("Animator")
	local cs   = game:GetService("ServerScriptService"):FindFirstChild("CombatServer")
	local hitAnim = cs and cs:FindFirstChild("Hit")
	if not anim or not hitAnim then return end
	local track = anim:LoadAnimation(hitAnim); track:Play()
	track.Stopped:Once(function() track:Destroy() end)
end

local _helpers = nil
local function getHelpers()
	if _helpers then return _helpers end
	_helpers = {
		applyDamage = function(hum, amt)
			if hum and hum.Parent then hum:TakeDamage(amt) end
		end,
		applyImpulse   = applyImpulse,
		applyStun      = applyStunHelper,
		applyKnockdown = applyKnockdown,
		ragdoll        = function(char, dur, impulse) RagdollUtil.Ragdoll(char,dur,impulse) end,
		castHitbox     = castHitboxHelper,
		playHitAnim    = playHitAnimHelper,
		fireCombatFB = function(player, data)
			local fb = getCombatFB(); if fb then fb:FireClient(player, data) end
		end,
		fireAllCombatFB = function(data)
			local fb = getCombatFB(); if fb then fb:FireAllClients(data) end
		end,
		fireCharFB = function(player, data)
			local fb = getCharFB(); if fb then fb:FireClient(player, data) end
		end,
		KnockdownUtil = KnockdownUtil,
		RagdollUtil   = RagdollUtil,
	}
	return _helpers
end

local function getOrCreateValue(player, name, default)
	local v = player:FindFirstChild(name)
	if not v then
		v=Instance.new("StringValue"); v.Name=name; v.Value=default or ""; v.Parent=player
	end
	return v
end

local function parseCSV(str)
	local t={}; if not str or str=="" then return t end
	for id in str:gmatch("[^,]+") do table.insert(t, id:match("^%s*(.-)%s*$")) end
	return t
end

local function toCSV(t) return table.concat(t,",") end

function SkillSystem.InitPlayer(player)
	getOrCreateValue(player,"Plr_AvailableSkills","")
	getOrCreateValue(player,"Plr_EquippedSkills","")
end

function SkillSystem.GrantSkill(player, skillId)
	if not SkillRegistry.Get(skillId) then warn("[SkillSystem] Unknown skill:",skillId); return end
	local val = getOrCreateValue(player,"Plr_AvailableSkills","")
	local list = parseCSV(val.Value)
	for _, id in ipairs(list) do if id==skillId then return end end
	table.insert(list, skillId); val.Value=toCSV(list)
end

function SkillSystem.RevokeSkill(player, skillId)
	local avail = getOrCreateValue(player,"Plr_AvailableSkills","")
	local list  = parseCSV(avail.Value)
	for i, id in ipairs(list) do if id==skillId then table.remove(list,i); break end end
	avail.Value=toCSV(list); SkillSystem.UnequipSkill(player,skillId)
end

function SkillSystem.EquipSkill(player, skillId)
	local avail    = getOrCreateValue(player,"Plr_AvailableSkills","")
	local equipped = getOrCreateValue(player,"Plr_EquippedSkills","")
	local availList = parseCSV(avail.Value)
	local hasSkill = false
	for _, id in ipairs(availList) do if id==skillId then hasSkill=true; break end end
	if not hasSkill then return false,"Skill not available" end
	local meta = SkillRegistry.Get(skillId)
	if not meta then return false,"Unknown skill" end
	local wt = player:FindFirstChild("Plr_WeaponType")
	local currentWT = wt and wt.Value or ""
	if not SkillRegistry.IsCompatible(skillId, currentWT) then return false,"Incompatible with current weapon" end
	local equippedList = parseCSV(equipped.Value)
	for _, id in ipairs(equippedList) do if id==skillId then return false,"Already equipped" end end
	if #equippedList >= MAX_EQUIPPED_SKILLS then return false,"No free skill slots (max "..MAX_EQUIPPED_SKILLS..")" end
	table.insert(equippedList, skillId); equipped.Value=toCSV(equippedList)
	return true,"Equipped"
end

function SkillSystem.UnequipSkill(player, skillId)
	local equipped = getOrCreateValue(player,"Plr_EquippedSkills","")
	local list = parseCSV(equipped.Value)
	for i, id in ipairs(list) do if id==skillId then table.remove(list,i); break end end
	equipped.Value=toCSV(list)
end

function SkillSystem.GetCooldown(player, skillId)
	local uid = player.UserId
	if not cooldowns[uid] or not cooldowns[uid][skillId] then return 0 end
	return math.max(0, cooldowns[uid][skillId]-os.clock())
end

function SkillSystem.ExecuteSkill(player, skillId)
	local char = player.Character; if not char or not char.Parent then return end
	local meta = SkillRegistry.Get(skillId); if not meta then return end
	local equipped = getOrCreateValue(player,"Plr_EquippedSkills","")
	local equippedList = parseCSV(equipped.Value)
	local isEquipped = false
	for _, id in ipairs(equippedList) do if id==skillId then isEquipped=true; break end end
	if not isEquipped then return end
	local wt = player:FindFirstChild("Plr_WeaponType")
	if not SkillRegistry.IsCompatible(skillId, wt and wt.Value or "") then return end
	if not char:FindFirstChildOfClass("Tool") then return end
	local SEU = require(script.Parent.StatusEffectUtil)
	if SEU.BlocksAttack(char) then return end
	local uid = player.UserId
	if not cooldowns[uid] then cooldowns[uid]={} end
	local remaining = SkillSystem.GetCooldown(player, skillId)
	if remaining > 0 then
		local fb = getCombatFB()
		if fb then fb:FireClient(player,{type="SkillCooldown",skillId=skillId,remaining=remaining}) end
		return
	end
	cooldowns[uid][skillId] = os.clock()+(meta.cooldown or 0)
	local skillMod = loadSkillModule(skillId)
	if not skillMod or not skillMod.Execute then warn("[SkillSystem] No Execute:",skillId); return end
	task.spawn(function()
		local helpers = getHelpers()
		local ok, err = pcall(skillMod.Execute, player, char, helpers)
		if not ok then warn("[SkillSystem] Error in:",skillId, err) end
	end)
end

return SkillSystem