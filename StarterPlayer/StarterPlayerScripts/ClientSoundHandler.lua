-- @ScriptType: LocalScript
local RS = game:GetService("ReplicatedStorage")
local Debris = game:GetService("Debris")

local SoundFX = RS:WaitForChild("SoundFX")
local SoundsFolder = RS:WaitForChild("Sounds")

SoundFX.OnClientEvent:Connect(function(data)
	if not data then return end

	local soundType = data.type
	local position = data.position

	local template = SoundsFolder:FindFirstChild(soundType)
	if not template then
		warn("Missing sound:", soundType)
		return
	end

	local part = Instance.new("Part")
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.Transparency = 1
	part.Size = Vector3.new(1, 1, 1)
	part.Position = position
	part.Parent = workspace

	local sound = template:Clone()
	sound.Parent = part
	sound:Play()

	Debris:AddItem(part, math.max(sound.TimeLength + 1, 2))
end)