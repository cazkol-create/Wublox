-- @ScriptType: ModuleScript
-- @ScriptType: ModuleScript
-- Location: ServerScriptService/Modules/CombatTag
--
-- Manages a per-player "in combat" tag.
-- Any system that wants to flag combat activity calls CombatTag.Tag(player).
-- The tag expires automatically after COMBAT_EXPIRE seconds of inactivity.
--
-- The tag is also written as a BoolValue inside the CHARACTER so that
-- LocalScripts (e.g. a combat indicator UI) can read it without a remote.

local Players = game:GetService("Players")

local CombatTag = {}

-- How many seconds of no combat activity before the tag clears.
local COMBAT_EXPIRE = 8

-- [userId] = task handle for the expiry timer
local expireTasks = {}

local function getOrCreateTagValue(character)
	local existing = character:FindFirstChild("InCombat")
	if existing then return existing end
	local v = Instance.new("BoolValue")
	v.Name   = "InCombat"
	v.Value  = false
	v.Parent = character
	return v
end

-- ── Public API ────────────────────────────────────────────────

-- Mark player as in-combat and restart the expiry timer.
-- Safe to call many times per second (timer is restarted, not stacked).
function CombatTag.Tag(player)
	local character = player.Character
	if not character then return end

	local tagValue = getOrCreateTagValue(character)
	tagValue.Value = true

	local uid = player.UserId
	if expireTasks[uid] then
		task.cancel(expireTasks[uid])
	end

	expireTasks[uid] = task.delay(COMBAT_EXPIRE, function()
		expireTasks[uid] = nil
		local char = player.Character
		if char then
			local tv = char:FindFirstChild("InCombat")
			if tv then tv.Value = false end
		end
	end)
end

-- Immediately remove the tag (e.g. on death).
function CombatTag.Clear(player)
	local uid = player.UserId
	if expireTasks[uid] then
		task.cancel(expireTasks[uid])
		expireTasks[uid] = nil
	end
	local char = player.Character
	if char then
		local tv = char:FindFirstChild("InCombat")
		if tv then tv.Value = false end
	end
end

-- Returns true if the player is currently tagged as in-combat.
function CombatTag.IsInCombat(player)
	local char = player.Character
	if not char then return false end
	local tv = char:FindFirstChild("InCombat")
	return tv ~= nil and tv.Value == true
end

-- Cleanup on leave
Players.PlayerRemoving:Connect(function(player)
	local uid = player.UserId
	if expireTasks[uid] then
		task.cancel(expireTasks[uid])
		expireTasks[uid] = nil
	end
end)

-- Re-create the tag BoolValue on each respawn so LocalScripts always find it
Players.PlayerAdded:Connect(function(player)
	player.CharacterAdded:Connect(function(character)
		task.wait()
		getOrCreateTagValue(character)
	end)
end)

return CombatTag