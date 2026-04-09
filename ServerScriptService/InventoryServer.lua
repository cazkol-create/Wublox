-- @ScriptType: Script
-- @ScriptType: Script
-- ============================================================
--  InventoryServer.lua  |  Script  (NOT ModuleScript)
--  Location: ServerScriptService
--
--  CHANGES:
--    Sheathed state — UnequipTool no longer auto-equips the Fist.
--                     The character is left with NOTHING equipped.
--                     CombatServer's getEquippedTool() check already
--                     blocks all combat while nothing is equipped.
--    CharacterAdded — no longer force-equips Fist on spawn.
--                     The player starts in the sheathed state and
--                     must press R / click a slot to equip.
--    ChangeStyle    — moved here (from CombatServer) so all
--                     inventory-related remotes live in one place.
--                     CombatServer also keeps its handler as a
--                     validation fallback.
--    InventorySync  — payload now includes `equippedTool: string|nil`
--                     where nil means "sheathed / nothing equipped".
-- ============================================================

local Players       = game:GetService("Players")
local SS            = game:GetService("ServerStorage")
local RS            = game:GetService("ReplicatedStorage")

local InventoryData = require(RS.Modules.InventoryData)

-- ── Remote creation ───────────────────────────────────────────
local function getOrCreate(parent, name, class)
	local existing = parent:FindFirstChild(name)
	if existing then return existing end
	local obj = Instance.new(class)
	obj.Name = name; obj.Parent = parent
	return obj
end

local EquipTool     = getOrCreate(RS, "EquipTool",     "RemoteEvent")
local UnequipTool   = getOrCreate(RS, "UnequipTool",   "RemoteEvent")
local InventorySync = getOrCreate(RS, "InventorySync", "RemoteEvent")
-- ChangeStyle is also created here so StyleSwitchClient can always find it
-- regardless of whether CombatServer has loaded yet.
local ChangeStyle   = getOrCreate(RS, "ChangeStyle",   "RemoteEvent")

local toolsFolder = SS:WaitForChild("Tools", 10)

-- ============================================================
-- UTILITY
-- ============================================================

local function getWeaponDef(toolName)
	return InventoryData.GetByToolName(toolName)
end

local function getEquippedTool(character)
	if not character then return nil end
	return character:FindFirstChildOfClass("Tool")
end

local function findInBackpack(player, toolName)
	return player.Backpack:FindFirstChild(toolName)
end

-- Sets Plr_WeaponType and Plr_StyleName on the player object.
-- Pass empty string for weaponType to signal "sheathed / no weapon".
local function setWeaponValues(player, weaponType, styleName)
	local wt = player:FindFirstChild("Plr_WeaponType")
	local sn = player:FindFirstChild("Plr_StyleName")
	if wt then wt.Value = weaponType or "" end
	if sn then sn.Value = styleName  or "" end
end

-- ============================================================
-- SETUP PLAYER
-- Creates StringValues and clones tools into Backpack.
-- Does NOT auto-equip anything — player starts sheathed.
-- ============================================================
local function setupPlayer(player)
	if not player:FindFirstChild("Plr_WeaponType") then
		local v = Instance.new("StringValue")
		v.Name = "Plr_WeaponType"; v.Value = ""; v.Parent = player
	end
	if not player:FindFirstChild("Plr_StyleName") then
		local v = Instance.new("StringValue")
		v.Name = "Plr_StyleName"; v.Value = ""; v.Parent = player
	end

	local backpack = player:WaitForChild("Backpack", 5)
	if not backpack then
		warn("[InventoryServer] Backpack not found for", player.Name)
		return
	end

	-- Clone every weapon from ServerStorage/Tools into the Backpack.
	if toolsFolder then
		for _, weapon in ipairs(InventoryData.Weapons) do
			local template = toolsFolder:FindFirstChild(weapon.toolName)
			if template then
				if not backpack:FindFirstChild(weapon.toolName) then
					template:Clone().Parent = backpack
				end
			else
				warn("[InventoryServer] Tool not in ServerStorage/Tools:", weapon.toolName)
			end
		end
	end

	-- On each respawn: return equipped tool to backpack (death unequips).
	-- The player remains sheathed; the client UI reflects this via InventorySync.
	player.CharacterAdded:Connect(function(_char)
		task.wait(0.3)   -- let backpack repopulate

		-- Re-clone tools that went missing (Roblox destroys Backpack contents on death).
		if toolsFolder then
			local bp = player:FindFirstChild("Backpack")
			if bp then
				for _, weapon in ipairs(InventoryData.Weapons) do
					if not bp:FindFirstChild(weapon.toolName) then
						local tpl = toolsFolder:FindFirstChild(weapon.toolName)
						if tpl then tpl:Clone().Parent = bp end
					end
				end
			end
		end

		-- Reset to sheathed state.
		setWeaponValues(player, "", "")
		InventorySync:FireClient(player, { equippedTool = nil })
	end)
end

Players.PlayerAdded:Connect(setupPlayer)
for _, p in ipairs(Players:GetPlayers()) do
	task.spawn(setupPlayer, p)
end

-- ============================================================
-- REMOTE: EquipTool  (client → server)
-- Payload: { toolName = "Sword" }
-- ============================================================
EquipTool.OnServerEvent:Connect(function(player, data)
	if typeof(data) ~= "table" or not data.toolName then return end

	local character = player.Character
	if not character then return end
	local hum = character:FindFirstChildOfClass("Humanoid")
	if not hum or hum.Health <= 0 then return end

	-- Reject if the character is stunned (don't allow mid-combat swaps).
	if character:FindFirstChild("Stunned") then return end

	local toolName = data.toolName
	local weapDef  = getWeaponDef(toolName)
	if not weapDef then
		warn("[InventoryServer] Unknown tool:", toolName)
		return
	end

	-- Unequip whatever is currently equipped.
	local current = getEquippedTool(character)
	if current then
		current.Parent = player.Backpack
	end

	-- Find the requested tool.
	local tool = findInBackpack(player, toolName)
	if not tool then
		local template = toolsFolder and toolsFolder:FindFirstChild(toolName)
		if template then
			tool = template:Clone()
			tool.Parent = player.Backpack
		end
	end

	if not tool then
		warn("[InventoryServer] Could not find tool to equip:", toolName)
		return
	end

	-- Equip it.
	tool.Parent = character

	-- Reset style to the weapon's default on every fresh equip.
	setWeaponValues(player, weapDef.weaponType, weapDef.defaultStyle)

	-- Notify client.
	InventorySync:FireClient(player, { equippedTool = toolName })
end)

-- ============================================================
-- REMOTE: UnequipTool  (client → server)
-- No payload. Puts the current tool back in Backpack.
-- The character is left with NOTHING — true sheathed state.
-- ============================================================
UnequipTool.OnServerEvent:Connect(function(player)
	local character = player.Character
	if not character then return end

	-- Reject mid-combat unequip.
	if character:FindFirstChild("Stunned") then return end

	local current = getEquippedTool(character)
	if not current then return end   -- already sheathed

	current.Parent = player.Backpack

	-- Clear weapon state — CombatServer will reject all combat actions
	-- because getEquippedTool(character) returns nil.
	setWeaponValues(player, "", "")

	-- Notify client: equippedTool = nil means sheathed.
	InventorySync:FireClient(player, { equippedTool = nil })
end)

-- ============================================================
-- REMOTE: ChangeStyle  (StyleSwitchClient → server)
-- Payload: { styleName = "Flowing" }
-- Validates that the style exists for the current weapon.
-- Writing Plr_StyleName replicates to CombatClient → reloadTracks().
-- ============================================================
ChangeStyle.OnServerEvent:Connect(function(player, data)
	if typeof(data) ~= "table" or not data.styleName then return end

	-- Only allow style changes when a weapon is equipped.
	local character = player.Character
	if not character then return end
	local hasWeapon = character:FindFirstChildOfClass("Tool") ~= nil
	if not hasWeapon then return end

	local wt = player:FindFirstChild("Plr_WeaponType")
	local sn = player:FindFirstChild("Plr_StyleName")
	if not wt or not sn then return end

	local weaponType = wt.Value
	local newStyle   = data.styleName

	local allowedStyles = InventoryData.GetStyles(weaponType)
	local valid = false
	for _, s in ipairs(allowedStyles) do
		if s == newStyle then valid = true; break end
	end

	if not valid then
		warn("[InventoryServer] Invalid style:", newStyle, "for weapon:", weaponType)
		return
	end

	sn.Value = newStyle
end)