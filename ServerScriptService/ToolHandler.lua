-- @ScriptType: Script
-- Server Script
game.Players.PlayerAdded:Connect(function(plr)			
	plr.CharacterAdded:Connect(function(char)		
		local M6D = Instance.new("Motor6D") 
		M6D.Name = "Motor6D"
		M6D.Parent = char['Right Arm'] -- or the part that you have decieded
		M6D.Part0 = char['Right Arm']

		char.ChildAdded:Connect(function(child)
			if child:IsA("Tool") and child:FindFirstChild("RightArmAttach") then
				M6D.Part1 = child.RightArmAttach
			end
		end)
	end)
end)