-- @ScriptType: ModuleScript
-- ============================================================
--  RagdollUtil.lua  |  ModuleScript
--  Location: ServerScriptService/Modules/RagdollUtil
--
--  Provides ragdoll and un-ragdoll for any character.
--  Called by special moves (command grabs, launch finishers, etc.)
--  Currently no grabs exist, so this acts as the framework
--  placeholder — any new special move just calls Ragdoll().
--
--  How it works:
--    1. PlatformStand disables Humanoid control so the physics
--       engine takes over the whole rig.
--    2. Disabling Motor6D joints un-welds limbs from the
--       HumanoidRootPart, letting them fall independently.
--    3. Small random angular impulses make the fall look alive.
--    4. After `duration` seconds, Motor6D is re-enabled and
--       PlatformStand is cleared — the character stands back up.
-- ============================================================

local Debris = game:GetService("Debris")

local RagdollUtil = {}

-- ── Ragdoll ───────────────────────────────────────────────────
-- character : Model with Humanoid + Motor6D-based rig
-- duration  : seconds before the character recovers
-- impulse   : optional extra Vector3 applied to the root on entry
function RagdollUtil.Ragdoll(character, duration, impulse)
	if not character or not character.Parent then return end

	local hum  = character:FindFirstChildOfClass("Humanoid")
	local root = character:FindFirstChild("HumanoidRootPart")
	if not hum or not root then return end

	-- Prevent multiple simultaneous ragdolls
	if character:FindFirstChild("Ragdolled") then return end

	local tag      = Instance.new("BoolValue")
	tag.Name       = "Ragdolled"
	tag.Parent     = character
	Debris:AddItem(tag, duration)

	-- Disable Humanoid so the physics engine takes full control
	hum.PlatformStand = true

	-- Optional launch impulse (e.g. for grab finishers)
	if impulse and impulse.Magnitude > 0.001 then
		root:ApplyImpulse(impulse * root.AssemblyMass)
	end

	-- Collect every Motor6D in the rig and disable it
	local motors = {}
	for _, v in ipairs(character:GetDescendants()) do
		if v:IsA("Motor6D") then
			v.Enabled = false
			table.insert(motors, v)
		end
	end

	-- Apply small random angular impulses to limbs for a natural tumble
	for _, part in ipairs(character:GetDescendants()) do
		if part:IsA("BasePart") and part ~= root then
			part.CanCollide = true
			part:ApplyAngularImpulse(Vector3.new(
				math.random(-30, 30),
				math.random(-30, 30),
				math.random(-30, 30)
				))
		end
	end

	-- Recover after duration
	task.delay(duration, function()
		if not character.Parent then return end
		if not hum or not hum.Parent then return end

		-- Re-enable all joints to reassemble the rig
		for _, motor in ipairs(motors) do
			if motor.Parent then
				motor.Enabled = true
			end
		end

		-- Turn limb collision back off (Roblox characters have it off by default)
		for _, part in ipairs(character:GetDescendants()) do
			if part:IsA("BasePart") and part ~= root then
				part.CanCollide = false
			end
		end

		hum.PlatformStand = false
	end)
end

-- ── IsRagdolled ───────────────────────────────────────────────
-- Quick check used by other systems to skip attacking downed targets.
function RagdollUtil.IsRagdolled(character)
	return character:FindFirstChild("Ragdolled") ~= nil
end

return RagdollUtil