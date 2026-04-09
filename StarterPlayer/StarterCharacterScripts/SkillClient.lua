-- @ScriptType: LocalScript
-- @ScriptType: LocalScript
-- ============================================================
--  SkillClient.lua  |  LocalScript
--  Location: StarterCharacterScripts
--
--  Reads the player's Plr_EquippedSkills (server-managed StringValue,
--  comma-separated skill IDs) and binds each to its default keybind
--  from SkillRegistry.  Fires UseSkill remote when activated.
--
--  Skill keybinds can be rebound via SettingsClient in the future.
--
--  ── Required remotes in ReplicatedStorage ───────────────────
--  UseSkill      RemoteEvent   (created by CombatServer)
--  EquipSkill    RemoteEvent   (created by CombatServer)
--  UnequipSkill  RemoteEvent   (created by CombatServer)
--  CombatFeedback RemoteEvent  (listens for SkillCooldown events)
-- ============================================================

local CAS          = game:GetService("ContextActionService")
local Players      = game:GetService("Players")
local RS           = game:GetService("ReplicatedStorage")

local player    = Players.LocalPlayer
local character = script.Parent
local humanoid  = character:WaitForChild("Humanoid")
local animator  = humanoid:WaitForChild("Animator")

local SkillRegistry = require(RS.Modules.SkillRegistry)
local CombatData    = require(RS.Modules.CombatData)

local UseSkill    = RS:WaitForChild("UseSkill",    15)
local EquipSkill  = RS:WaitForChild("EquipSkill",  15)
local UnequipSkill= RS:WaitForChild("UnequipSkill",15)
local CombatFB    = RS:WaitForChild("CombatFeedback")
local animRoot    = RS:WaitForChild("Animations", 10)

-- ============================================================
-- STATE HELPERS
-- ============================================================
local function isBlocked()
	return character:FindFirstChild("Stunned")       ~= nil
		or character:FindFirstChild("SoftKnockdown") ~= nil
		or character:FindFirstChild("HardKnockdown") ~= nil
end
local function hasWeapon()
	return character:FindFirstChildOfClass("Tool") ~= nil
end

-- ============================================================
-- PER-SKILL COOLDOWN (client-side prediction only)
-- Server sends authoritative "SkillCooldown" events.
-- ============================================================
local localCooldowns = {}   -- [skillId] = expiry time()
local function isOnCooldown(skillId)
	return localCooldowns[skillId] and time() < localCooldowns[skillId]
end

-- ============================================================
-- SKILL ANIMATION TRACKS
-- Per-skill animations are stored alongside combat animations:
-- RS/Animations/[weaponType]/[styleName]/[skill.animName]
-- ============================================================
local skillTracks = {}  -- [skillId] = AnimationTrack

local function loadSkillAnim(skillId)
	if skillTracks[skillId] then
		skillTracks[skillId]:Destroy()
		skillTracks[skillId] = nil
	end
	local meta = SkillRegistry.Get(skillId)
	if not meta or not meta.animName then return end

	local wt = player:FindFirstChild("Plr_WeaponType")
	local sn = player:FindFirstChild("Plr_StyleName")
	local wtv = (wt and wt.Value ~= "") and wt.Value or "Fist"
	local snv = (sn and sn.Value ~= "") and sn.Value or "Default"

	if not animRoot then return end
	local wfolder = animRoot:FindFirstChild(wtv)
	local sfolder = wfolder and (wfolder:FindFirstChild(snv) or wfolder:FindFirstChild("Default"))
	local animObj  = sfolder and sfolder:FindFirstChild(meta.animName)
	if animObj then
		skillTracks[skillId] = animator:LoadAnimation(animObj)
	end
end

-- ============================================================
-- BOUND ACTIONS  (rebuilt when equipped skills change)
-- ============================================================
local boundActions = {}

local function unbindAll()
	for actionName in pairs(boundActions) do
		CAS:UnbindAction(actionName)
	end
	boundActions = {}
	for _, t in pairs(skillTracks) do
		if t and t.IsPlaying then t:Stop(0) end
		if t then t:Destroy() end
	end
	skillTracks = {}
end

local function parseCSV(str)
	local t = {}
	if not str or str == "" then return t end
	for id in str:gmatch("[^,]+") do
		table.insert(t, id:match("^%s*(.-)%s*$"))
	end
	return t
end

local function bindEquippedSkills(equippedCSV)
	unbindAll()
	local ids = parseCSV(equippedCSV)
	for _, skillId in ipairs(ids) do
		local meta = SkillRegistry.Get(skillId)
		if not meta then continue end

		-- Load the animation for this skill
		loadSkillAnim(skillId)

		-- Bind the keybind
		local actionName = "Skill_" .. skillId
		local capturedId = skillId
		local keybind    = meta.defaultKeybind or Enum.KeyCode.E

		CAS:BindAction(actionName, function(_, inputState, _)
			if inputState ~= Enum.UserInputState.Begin then
				return Enum.ContextActionResult.Pass
			end
			if isBlocked()                                       then return Enum.ContextActionResult.Sink end
			if meta.requiresWeapon ~= false and not hasWeapon() then return Enum.ContextActionResult.Sink end
			if isOnCooldown(capturedId)                          then return Enum.ContextActionResult.Sink end

			-- Optimistic cooldown (server will authoritative-correct if wrong)
			if meta.cooldown and meta.cooldown > 0 then
				localCooldowns[capturedId] = time() + meta.cooldown
			end

			-- Play animation optimistically
			local t = skillTracks[capturedId]
			if t then
				t:Stop(0); t:Play()
				t.Stopped:Once(function() end)
			end

			-- Fire to server
			UseSkill:FireServer({ skillId = capturedId })

			return Enum.ContextActionResult.Sink
		end, false, keybind)

		boundActions[actionName] = keybind
	end
end

-- ============================================================
-- WATCH Plr_EquippedSkills  (StringValue on the player object)
-- ============================================================
task.spawn(function()
	local equippedVal = player:WaitForChild("Plr_EquippedSkills", 10)
	if not equippedVal then return end

	bindEquippedSkills(equippedVal.Value)
	equippedVal.Changed:Connect(bindEquippedSkills)

	-- Reload anims if weapon/style changes
	local wt = player:WaitForChild("Plr_WeaponType", 6)
	local sn = player:WaitForChild("Plr_StyleName",  6)
	local function reloadAnims()
		local ids = parseCSV(equippedVal.Value)
		for _, id in ipairs(ids) do loadSkillAnim(id) end
	end
	if wt then wt.Changed:Connect(reloadAnims) end
	if sn then sn.Changed:Connect(reloadAnims) end
end)

-- ============================================================
-- STUN / KNOCKDOWN: cancel skill animations
-- ============================================================
character.ChildAdded:Connect(function(child)
	local n = child.Name
	if n == "Stunned" or n == "SoftKnockdown" or n == "HardKnockdown" then
		for _, t in pairs(skillTracks) do
			if t and t.IsPlaying then t:Stop(0.1) end
		end
	end
end)

-- ============================================================
-- SERVER AUTHORITATIVE COOLDOWN UPDATE
-- ============================================================
CombatFB.OnClientEvent:Connect(function(data)
	if not data then return end

	if data.type == "SkillCooldown" and data.skillId then
		-- Server says we're still on cooldown
		localCooldowns[data.skillId] = time() + (data.remaining or 0)

	elseif data.type == "SkillEquipResult" and data.skillId then
		-- Equip/unequip confirmation (currently no UI feedback here;
		-- SkillHUD and InventoryClient react to Plr_EquippedSkills.Changed)
		if not data.success then
			warn("[SkillClient] Equip failed for", data.skillId, ":", data.reason)
		end
	end
end)

-- ============================================================
-- PUBLIC API  (_G.WuxiaClient)
-- ============================================================
_G.WuxiaClient = _G.WuxiaClient or {}

-- Called from InventoryClient (skills tab) to equip/unequip.
_G.WuxiaClient.EquipSkill = function(skillId)
	EquipSkill:FireServer({ skillId = skillId })
end

_G.WuxiaClient.UnequipSkill = function(skillId)
	UnequipSkill:FireServer({ skillId = skillId })
end

-- Returns current client-side cooldown (seconds remaining).
_G.WuxiaClient.GetSkillCooldown = function(skillId)
	if not isOnCooldown(skillId) then return 0 end
	return math.max(0, localCooldowns[skillId] - time())
end

-- Expose the action name for SettingsClient rebinding.
_G.WuxiaClient.GetSkillBinds = function()
	local result = {}
	for actionName, keybind in pairs(boundActions) do
		result[actionName] = keybind
	end
	return result
end