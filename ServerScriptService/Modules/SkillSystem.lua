-- @ScriptType: ModuleScript
-- @ScriptType: ModuleScript
-- ============================================================
--  SkillSystem.lua  |  ModuleScript
--  Location: ServerScriptService/Modules/SkillSystem
--
--  CHANGES:
--    • DEFAULT_SKILLS table — skills listed here are automatically
--      granted (made available) to every player on join.
--      Players still need to equip them via the Inventory UI.
--      Add/remove entries freely; no other code needs changing.
--
--    • helpers now includes:
--        helpers.setEndlag(player, duration)
--            Locks the player out of all combat actions for `duration`
--            seconds and fires EndlagStart to MovementClient.
--        helpers.tagCombat(player)
--            Marks the player as in-combat, pausing health regen.
--        helpers.tagCombat(targetPlayer)  — same for the defender
--        helpers.SoundFX  — the UnreliableRemoteEvent for client sounds
--        helpers.CombatFX — the UnreliableRemoteEvent for VFX
--
--    • castHitboxHelper now uses LIVE root tracking (hb.CFrame = root)
--      matching CombatServer behaviour, so hitboxes follow the player
--      during the hit window instead of snapping to a static CFrame.
-- ============================================================

local Players        = game:GetService("Players")
local SS             = game:GetService("ServerStorage")
local RS             = game:GetService("ReplicatedStorage")

local SkillRegistry  = require(RS.Modules.SkillRegistry)
local RagdollUtil    = require(script.Parent.RagdollUtil)
local KnockdownUtil  = require(script.Parent.KnockdownUtil)
local MuchachoHitbox = require(script.Parent.MuchachoHitbox)
local CombatState    = require(script.Parent.CombatState)
local CombatConfig   = require(script.Parent.CombatConfig)
local CombatTag      = require(script.Parent.CombatTag)

local SkillSystem = {}

-- ============================================================
-- DEFAULT SKILLS
-- Every player is automatically granted these on join so they
-- show up in the Inventory "Available" tab immediately.
-- ============================================================
SkillSystem.DEFAULT_SKILLS = {
	"SwordDashSlash",
	"TigerClaw",
	"IronBody",
}

local MAX_EQUIPPED_SKILLS = 6

local skillModuleCache = {}
local skillsFolder     = SS:WaitForChild("Skills", 10)

-- ── Remote handles (lazy) ─────────────────────────────────────
local _CombatFB, _CharacterFB, _CombatFX, _SoundFX

local function getCombatFB()
	if not _CombatFB then _CombatFB = RS:FindFirstChild("CombatFeedback") end
	return _CombatFB
end
local function getCharFB()
	if not _CharacterFB then _CharacterFB = RS:FindFirstChild("CharacterFeedback") end
	return _CharacterFB
end
local function getCombatFX()
	if not _CombatFX then _CombatFX = RS:FindFirstChild("CombatFX") end
	return _CombatFX
end
local function getSoundFX()
	if not _SoundFX then _SoundFX = RS:FindFirstChild("SoundFX") end
	return _SoundFX
end

-- ── Per-player skill cooldowns ────────────────────────────────
local cooldowns = {}
Players.PlayerRemoving:Connect(function(p) cooldowns[p.UserId] = nil end)

-- ============================================================
-- INTERNAL HELPERS
-- ============================================================

local function loadSkillModule(skillId)
	if skillModuleCache[skillId] then return skillModuleCache[skillId] end
	if not skillsFolder then warn("[SkillSystem] ServerStorage/Skills/ not found"); return nil end
	local mod = skillsFolder:FindFirstChild(skillId)
	if not mod then warn("[SkillSystem] Skill not found:", skillId); return nil end
	local ok, result = pcall(require, mod)
	if not ok then warn("[SkillSystem] Load failed:", skillId, result); return nil end
	skillModuleCache[skillId] = result
	return result
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

local function applyKnockdownHelper(char, knockType, dur)
	if knockType == "soft" then
		KnockdownUtil.ApplySoftKnockdown(char, dur)
	elseif knockType == "hard" then
		KnockdownUtil.ApplyHardKnockdown(char, dur)
	end
end

-- Live-tracking hitbox (matches CombatServer behaviour).
-- hb.CFrame is set to the BasePart (root) so it follows the attacker.
local function castHitboxHelper(attackerChar, def, attackerPlayer, onHitFn)
	local root = attackerChar and attackerChar:FindFirstChild("HumanoidRootPart")
	if not root then return end

	local params = OverlapParams.new()
	params.FilterType                 = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { attackerChar }

	local hb = MuchachoHitbox.CreateHitbox()
	hb.Size          = def.hitboxSize or Vector3.new(5, 5, 5)
	hb.CFrame        = root                                    -- ← LIVE tracking
	hb.Offset        = CFrame.new(0, 0, def.hitboxFwd or -4)
	hb.OverlapParams = params
	hb.HitOnce       = true
	hb.Visualizer    = false

	hb.Touched:Connect(function(_, humanoid)
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
	local hw = def.hitWindow or 0.15
	task.delay(hw, function() hb:Stop() end)
end

local function playHitAnimHelper(char)
	local hum  = char and char:FindFirstChildOfClass("Humanoid")
	local anim = hum  and hum:FindFirstChildOfClass("Animator")
	local cs   = game:GetService("ServerScriptService"):FindFirstChild("CombatServer")
	local hitAnim = cs and cs:FindFirstChild("Hit")
	if not anim or not hitAnim then return end
	local track = anim:LoadAnimation(hitAnim)
	track:Play()
	track.Stopped:Once(function() track:Destroy() end)
end

-- ── setEndlag: locks the player out of actions + notifies client ──
local function setEndlagHelper(player, duration)
	if not duration or duration <= 0 then return end
	CombatState.SetEndlag(player, duration)
	local charFB = getCharFB()
	if charFB then
		charFB:FireClient(player, { type = "EndlagStart", duration = duration })
	end
end

-- ============================================================
-- SHARED HELPERS TABLE  (passed into every skill Execute)
-- ============================================================
local _helpers = nil
local function getHelpers()
	if _helpers then return _helpers end

	_helpers = {
		-- ── Damage / physics ──────────────────────────────────
		applyDamage = function(hum, amt)
			if hum and hum.Parent then hum:TakeDamage(amt) end
		end,
		applyImpulse   = applyImpulse,
		applyStun      = applyStunHelper,
		applyKnockdown = applyKnockdownHelper,
		ragdoll        = function(char, dur, impulse)
			RagdollUtil.Ragdoll(char, dur, impulse)
		end,

		-- ── Hit detection ─────────────────────────────────────
		castHitbox  = castHitboxHelper,
		playHitAnim = playHitAnimHelper,

		-- ── Endlag integration ────────────────────────────────
		-- setEndlag(player, duration)
		--   Blocks all combat actions for `duration` seconds and
		--   fires EndlagStart to MovementClient for UI.
		setEndlag = setEndlagHelper,

		-- ── Combat tag ────────────────────────────────────────
		-- tagCombat(player)
		--   Marks a player as in-combat (pauses regen).
		--   Call for both attacker and any defender you hit.
		tagCombat = function(player)
			if player then CombatTag.Tag(player) end
		end,

		-- ── Remote fire helpers ───────────────────────────────
		fireCombatFB = function(player, data)
			local fb = getCombatFB()
			if fb then fb:FireClient(player, data) end
		end,
		fireAllCombatFB = function(data)
			local fb = getCombatFB()
			if fb then fb:FireAllClients(data) end
		end,
		fireCharFB = function(player, data)
			local fb = getCharFB()
			if fb then fb:FireClient(player, data) end
		end,
		fireCombatFX = function(player, data)
			local fb = getCombatFX()
			if fb then fb:FireClient(player, data) end
		end,
		fireSoundFX = function(soundType, position)
			local fb = getSoundFX()
			if fb then fb:FireAllClients({ type = soundType, position = position }) end
		end,

		-- ── Module references (for advanced skills) ───────────
		KnockdownUtil = KnockdownUtil,
		RagdollUtil   = RagdollUtil,
		CombatState   = CombatState,
		Players       = Players,
	}

	return _helpers
end

-- ============================================================
-- StringValue helpers
-- ============================================================
local function getOrCreateValue(player, name, default)
	local v = player:FindFirstChild(name)
	if not v then
		v = Instance.new("StringValue")
		v.Name   = name
		v.Value  = default or ""
		v.Parent = player
	end
	return v
end

local function parseCSV(str)
	local t = {}
	if not str or str == "" then return t end
	for id in str:gmatch("[^,]+") do
		table.insert(t, id:match("^%s*(.-)%s*$"))
	end
	return t
end

local function toCSV(t) return table.concat(t, ",") end

-- ============================================================
-- PUBLIC API
-- ============================================================

-- Called from CombatServer's PlayerAdded.
-- Creates StringValues AND grants all DEFAULT_SKILLS.
function SkillSystem.InitPlayer(player)
	getOrCreateValue(player, "Plr_AvailableSkills", "")
	getOrCreateValue(player, "Plr_EquippedSkills",  "")

	-- Grant every default skill (safe to call repeatedly — deduplicates)
	for _, skillId in ipairs(SkillSystem.DEFAULT_SKILLS) do
		SkillSystem.GrantSkill(player, skillId)
	end
end

function SkillSystem.GrantSkill(player, skillId)
	if not SkillRegistry.Get(skillId) then
		warn("[SkillSystem] Unknown skill:", skillId)
		return
	end
	local val  = getOrCreateValue(player, "Plr_AvailableSkills", "")
	local list = parseCSV(val.Value)
	for _, id in ipairs(list) do if id == skillId then return end end
	table.insert(list, skillId)
	val.Value = toCSV(list)
end

function SkillSystem.RevokeSkill(player, skillId)
	local avail = getOrCreateValue(player, "Plr_AvailableSkills", "")
	local list  = parseCSV(avail.Value)
	for i, id in ipairs(list) do
		if id == skillId then table.remove(list, i); break end
	end
	avail.Value = toCSV(list)
	SkillSystem.UnequipSkill(player, skillId)
end

function SkillSystem.EquipSkill(player, skillId)
	local avail    = getOrCreateValue(player, "Plr_AvailableSkills", "")
	local equipped = getOrCreateValue(player, "Plr_EquippedSkills",  "")

	local availList = parseCSV(avail.Value)
	local hasSkill  = false
	for _, id in ipairs(availList) do if id == skillId then hasSkill = true; break end end
	if not hasSkill then return false, "Skill not available" end

	local meta = SkillRegistry.Get(skillId)
	if not meta then return false, "Unknown skill" end

	local wt        = player:FindFirstChild("Plr_WeaponType")
	local currentWT = wt and wt.Value or ""
	if not SkillRegistry.IsCompatible(skillId, currentWT) then
		return false, "Incompatible with current weapon"
	end

	local equippedList = parseCSV(equipped.Value)
	for _, id in ipairs(equippedList) do if id == skillId then return false, "Already equipped" end end
	if #equippedList >= MAX_EQUIPPED_SKILLS then
		return false, "No free skill slots (max " .. MAX_EQUIPPED_SKILLS .. ")"
	end

	table.insert(equippedList, skillId)
	equipped.Value = toCSV(equippedList)
	return true, "Equipped"
end

function SkillSystem.UnequipSkill(player, skillId)
	local equipped = getOrCreateValue(player, "Plr_EquippedSkills", "")
	local list     = parseCSV(equipped.Value)
	for i, id in ipairs(list) do
		if id == skillId then table.remove(list, i); break end
	end
	equipped.Value = toCSV(list)
end

function SkillSystem.GetCooldown(player, skillId)
	local uid = player.UserId
	if not cooldowns[uid] or not cooldowns[uid][skillId] then return 0 end
	return math.max(0, cooldowns[uid][skillId] - os.clock())
end

function SkillSystem.ExecuteSkill(player, skillId)
	local char = player.Character
	if not char or not char.Parent then return end

	local meta = SkillRegistry.Get(skillId)
	if not meta then return end

	-- Equipped check
	local equipped     = getOrCreateValue(player, "Plr_EquippedSkills", "")
	local isEquipped   = false
	for _, id in ipairs(parseCSV(equipped.Value)) do
		if id == skillId then isEquipped = true; break end
	end
	if not isEquipped then return end

	-- Weapon compatibility
	local wt = player:FindFirstChild("Plr_WeaponType")
	if not SkillRegistry.IsCompatible(skillId, wt and wt.Value or "") then return end

	-- Weapon equipped in hand
	if not char:FindFirstChildOfClass("Tool") then return end

	-- CC check
	local SEU = require(script.Parent.StatusEffectUtil)
	if SEU.BlocksAttack(char) then return end

	-- Cooldown check
	local uid = player.UserId
	if not cooldowns[uid] then cooldowns[uid] = {} end
	local remaining = SkillSystem.GetCooldown(player, skillId)
	if remaining > 0 then
		local fb = getCombatFB()
		if fb then
			fb:FireClient(player, {
				type      = "SkillCooldown",
				skillId   = skillId,
				remaining = remaining,
			})
		end
		return
	end

	-- Start cooldown
	cooldowns[uid][skillId] = os.clock() + (meta.cooldown or 0)

	local skillMod = loadSkillModule(skillId)
	if not skillMod or not skillMod.Execute then
		warn("[SkillSystem] No Execute for:", skillId)
		return
	end

	task.spawn(function()
		local helpers = getHelpers()
		local ok, err = pcall(skillMod.Execute, player, char, helpers)
		if not ok then warn("[SkillSystem] Error in:", skillId, err) end
	end)
end

return SkillSystem