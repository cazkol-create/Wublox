-- @ScriptType: Script
-- Server Script
game.Players.PlayerAdded:Connect(function(plr)			
	plr.CharacterAdded:Connect(function(char)		
		char.ChildAdded:Connect(function(child)
			if not child:IsA("Tool")  then return end
			
			if child:FindFirstChild("RightArmAttach") then
				local M6D = Instance.new("Motor6D") 
				M6D.Name = "Motor6D"
				M6D.Parent = char['Right Arm'] -- or the part that you have decieded
				M6D.Part0 = char['Right Arm']
				M6D.Part1 = child.RightArmAttach
			end
			
			if child:FindFirstChild("BodyAttach") then
				local M6D = Instance.new("Motor6D") 
				M6D.Name = "Motor6D"
				M6D.Parent = char['Torso'] -- or the part that you have decieded
				M6D.Part0 = char['Torso']
				M6D.Part1 = child.BodyAttach
			end
		end)
	end)
end)