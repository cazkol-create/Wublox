-- @ScriptType: LocalScript
local SoundService = game:GetService("SoundService")
local Players = game:GetService("Players")

local player = Players.LocalPlayer
local char = player.Character or player.CharacterAdded:Wait()
local humanoid = char:WaitForChild("Humanoid")

local SoundService = game:GetService("SoundService")

local materialsFolder = SoundService:WaitForChild("FootstepSounds", 5)
if not materialsFolder then
	warn("Missing FootstepSounds in SoundService")
	return
end

local materialSounds = {}
for _, sound in ipairs(materialsFolder:GetChildren()) do
	materialSounds[sound.Name] = sound
end

-- Disable default footsteps properly by waiting for them to exist
local function disableDefaultFootsteps(character)
	-- The Running sound lives inside the Animate LocalScript
	local animate = character:WaitForChild("Animate", 5)
	if animate then
		local runSound = animate:FindFirstChild("run")
		if runSound then
			local running = runSound:FindFirstChild("RunAnim")
			if running and running:IsA("Sound") then
				running.Volume = 0
			end
		end
	end

	-- Also catch any sounds named "Running" that appear later
	character.DescendantAdded:Connect(function(obj)
		if obj:IsA("Sound") and obj.Name == "Running" then
			obj.Volume = 0
		end
	end)

	-- Mute any that already exist
	for _, obj in ipairs(character:GetDescendants()) do
		if obj:IsA("Sound") and obj.Name == "Running" then
			obj.Volume = 0
		end
	end
end

disableDefaultFootsteps(char)

-- Handle respawns
player.CharacterAdded:Connect(function(newChar)
	char = newChar
	humanoid = newChar:WaitForChild("Humanoid")
	disableDefaultFootsteps(newChar)
end)

local currentSound = nil
local walking = false

humanoid.Running:Connect(function(speed)
	walking = speed > humanoid.WalkSpeed * 0.5
end)

local function getMaterial()
	local mat = humanoid.FloorMaterial
	if mat == Enum.Material.Air then
		return "Air"
	end
	return tostring(mat):match("Enum.Material.(%w+)")
end

task.spawn(function()
	while true do
		if walking then
			local material = getMaterial()
			local sound = materialSounds[material]

			if sound and sound ~= currentSound then
				if currentSound then
					currentSound.Playing = false
				end
				currentSound = sound
				currentSound.PlaybackSpeed = humanoid.WalkSpeed / 12
				currentSound.Playing = true
			end
		else
			if currentSound then
				currentSound.Playing = false
				currentSound = nil
			end
		end
		task.wait(0.1)
	end
end)
