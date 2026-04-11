local RS = game:GetService("ReplicatedStorage")
local SoundFX = RS:WaitForChild("SoundFX")
local SoundsFolder = RS:WaitForChild("Sounds")

SoundFX.OnClientEvent:Connect(function(data)
	if not data then return end

	local soundType = data.type
	local position = data.position

	local soundTemplate = SoundsFolder:FindFirstChild(soundType)
	if not soundTemplate then
		warn("Missing sound:", soundType)
		return
	end

	local sound = soundTemplate:Clone()
	sound.Parent = workspace
	sound.Position = position

	sound:Play()
	game:GetService("Debris"):AddItem(sound, sound.TimeLength + 1)
end)
