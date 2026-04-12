-- @ScriptType: ModuleScript
-- @ScriptType: ModuleScript
-- Location: ServerScriptService/Modules/CombatHealthRegen
--
-- Replaces Roblox's default health regen.
-- Regen is completely suppressed while CombatTag.IsInCombat(player) is true.
-- Call CombatHealthRegen.Init() once from your startup Script.

local Players   = game:GetService("Players")
local CombatTag = require(script.Parent.CombatTag)

local CombatHealthRegen = {}

-- ── Tuning ────────────────────────────────────────────────────
local REGEN_RATE = 1.0   -- HP regenerated per second
local REGEN_TICK = 1.0   -- seconds between regen attempts

function CombatHealthRegen.Init()
	Players.PlayerAdded:Connect(function(player)
		player.CharacterAdded:Connect(function(character)
			-- Kill the default Health script before it starts its own loop
			local defaultHealth = character:WaitForChild("Health", 3)
			if defaultHealth then
				defaultHealth.Disabled = true
			end

			local humanoid = character:WaitForChild("Humanoid")

			task.spawn(function()
				while humanoid.Parent do
					task.wait(REGEN_TICK)
					if not humanoid.Parent then break end

					local isAlive     = humanoid.Health > 0
					local notFull     = humanoid.Health < humanoid.MaxHealth
					local outOfCombat = not CombatTag.IsInCombat(player)

					if isAlive and notFull and outOfCombat then
						humanoid.Health = math.min(
							humanoid.MaxHealth,
							humanoid.Health + (REGEN_RATE * REGEN_TICK)
						)
					end
				end
			end)
		end)
	end)
end

return CombatHealthRegen