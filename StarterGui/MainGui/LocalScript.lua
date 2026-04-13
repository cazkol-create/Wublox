-- @ScriptType: LocalScript
local replicatedStorage = game:GetService("ReplicatedStorage")
local runService = game:GetService("RunService")
local tweenService = game:GetService("TweenService")
local debris = game:GetService("Debris")

local gui = script.Parent
local cdList = gui.cooldowns
local template = cdList.template

local function lerp(a,b,t)
	return a + (b - a) * t
end

replicatedStorage.CooldownFeedback.OnClientEvent:Connect(function(cdName, lifetime)
	local newTemplate = template:Clone()
	newTemplate.Name = cdName
	newTemplate.Parent = cdList
	newTemplate.Visible = true
	newTemplate.nameplate.Text = cdName
	
	local timestamp = os.clock()
	local progresssBar
	
	progresssBar = runService.RenderStepped:Connect(function(dt)
		local progress = (os.clock() - timestamp) / lifetime
		if newTemplate:FindFirstChild("progressBar") then
			newTemplate.progressBar.Size = UDim2.fromOffset(lerp(150,0,progress),20)
		end
		
		if progress >= 1 then progresssBar:Disconnect() end
	end)
	
	
	debris:AddItem(newTemplate, lifetime)
end)