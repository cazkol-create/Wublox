-- @ScriptType: Script
-- Server Script
game.Players.PlayerAdded:Connect(function(plr)			
	plr.CharacterAdded:Connect(function(char)		
		char.ChildAdded:Connect(function(child)
			if not child:IsA("Tool") then return end

			-- Handle Right Arm Attachment
			if child:FindFirstChild("RightArmAttach") then
				-- Check if joint exists, otherwise create it
				local M6D = char['Right Arm']:FindFirstChild("WeaponRightArmJoint") or Instance.new("Motor6D")
				M6D.Name = "WeaponRightArmJoint"
				M6D.Part0 = char['Right Arm']
				M6D.Part1 = child.RightArmAttach
				M6D.Parent = char['Right Arm']
			end

			-- Handle Body Attachment
			if child:FindFirstChild("BodyAttach") then
				-- Check if joint exists, otherwise create it
				local M6D = char['Torso']:FindFirstChild("WeaponBodyJoint") or Instance.new("Motor6D")
				M6D.Name = "WeaponBodyJoint"
				M6D.Part0 = char['Torso']
				M6D.Part1 = child.BodyAttach
				M6D.Parent = char['Torso']
			end
		end)

		-- Optional: Clean up joints when the tool is removed (Unequipped)
		char.ChildRemoved:Connect(function(child)
			if child:IsA("Tool") then
				local rightJoint = char['Right Arm']:FindFirstChild("WeaponRightArmJoint")
				local bodyJoint = char['Torso']:FindFirstChild("WeaponBodyJoint")

				if rightJoint then rightJoint:Destroy() end
				if bodyJoint then bodyJoint:Destroy() end
			end
		end)
	end)
end)