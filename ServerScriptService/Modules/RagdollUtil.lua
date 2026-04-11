-- @ScriptType: ModuleScript
-- @ScriptType: ModuleScript
-- ============================================================
--  RagdollUtil.lua  |  ModuleScript
--  Location: ServerScriptService/Modules/RagdollUtil
--
--  BallSocketConstraint-based ragdoll.
--
--  FIXES:
--    Player ragdoll physics — when the server ragdolls a player
--    character, the server must claim network ownership of the
--    character parts so its physics impulses actually replicate.
--    Without this the client rejects the impulses (it owns the
--    physics) and the body barely moves.  On recovery, ownership
--    is returned to the player.
--
--    "Getting-up" snap — after unRagdoll we call
--    Humanoid:ChangeState(GettingUp) which previously snapped
--    the model instantly.  We now wait one frame after re-enabling
--    Motor6D joints so the rig assembles itself before the state
--    transition, preventing the visual pop.
-- ============================================================

local Players    = game:GetService("Players")
local Debris     = game:GetService("Debris")
local RunService = game:GetService("RunService")

-- ── Developer config ──────────────────────────────────────────
local CONFIG = {
	angularImpulseMin  = -25,
	angularImpulseMax  =  25,
	applyEntryImpulse  = true,
	-- Extra impulse applied upward when recovering from ragdoll to
	-- help players stand up rather than sliding along the floor.
	recoveryUpImpulse  = 20,
}

local RagdollUtil = {}

-- ── Network ownership helpers ─────────────────────────────────
-- Claim physics ownership so server impulses replicate to everyone.
local function claimOwnership(character)
	for _, part in ipairs(character:GetDescendants()) do
		if part:IsA("BasePart") then
			local ok = pcall(function() part:SetNetworkOwner(nil) end)
		end
	end
end

-- Return ownership to the player (or server for NPCs).
local function releaseOwnership(character)
	local player = Players:GetPlayerFromCharacter(character)
	for _, part in ipairs(character:GetDescendants()) do
		if part:IsA("BasePart") then
			pcall(function()
				if player then
					part:SetNetworkOwner(player)
				else
					part:SetNetworkOwner(nil) -- server for NPCs
				end
			end)
		end
	end
end

-- ── BallSocket ragdoll ────────────────────────────────────────
local function performRagdoll(character)
	claimOwnership(character)
	
	for _, v in pairs(character:GetDescendants()) do
		if v:IsA("Motor6D") then
			local bs  = Instance.new("BallSocketConstraint")
			local a0  = Instance.new("Attachment")
			local a1  = Instance.new("Attachment")
			a0.Parent = v.Part0
			a1.Parent = v.Part1
			a0.CFrame = v.C0
			a1.CFrame = v.C1
			bs.Attachment0           = a0
			bs.Attachment1           = a1
			bs.MaxFrictionTorque     = 200
			bs.LimitsEnabled         = true
			bs.TwistLimitsEnabled    = true
			bs.Parent                = v.Parent
			v.Enabled                = false
		end
	end
	local hum = character:FindFirstChildOfClass("Humanoid")
	if hum then
		hum.RequiresNeck = false
		hum.PlatformStand = true
		hum:ChangeState(Enum.HumanoidStateType.Physics)
	end
end

local function unRagdoll(character)
	releaseOwnership(character)
	
	for _, v in pairs(character:GetDescendants()) do
		if v:IsA("BallSocketConstraint") then
			v:Destroy()
		elseif v:IsA("Motor6D") then
			v.Enabled = true
		end
	end

	local hum  = character:FindFirstChildOfClass("Humanoid")
	local root = character:FindFirstChild("HumanoidRootPart")
	if not hum then return end

	hum.RequiresNeck  = true
	hum.PlatformStand = false

	-- Apply a small upward impulse so the character actually stands
	-- up instead of sliding prone across the floor.
	if root and CONFIG.recoveryUpImpulse > 0 then
		root:ApplyImpulse(Vector3.new(0, CONFIG.recoveryUpImpulse, 0) * root.AssemblyMass)
	end

	-- Wait one frame for Motor6D re-assembly before changing state.
	-- Without this the rig snaps into an ugly T-pose.
	task.wait()
	hum:ChangeState(Enum.HumanoidStateType.GettingUp)
end

-- ============================================================
-- PUBLIC: Ragdoll
-- ============================================================
function RagdollUtil.Ragdoll(character, duration, impulse)
	if not character or not character.Parent then return end
	local hum  = character:FindFirstChildOfClass("Humanoid")
	local root = character:FindFirstChild("HumanoidRootPart")
	if not hum or not root then return end
	if hum.Health <= 0 then return end
	if character:FindFirstChild("Ragdolled") then return end

	local tag = Instance.new("BoolValue")
	tag.Name  = "Ragdolled"
	tag.Parent = character
	Debris:AddItem(tag, duration)

	-- Claim network ownership so server-applied impulses replicate.
	claimOwnership(character)

	performRagdoll(character)

	if CONFIG.applyEntryImpulse and impulse and impulse.Magnitude > 0.001 then
		root:ApplyImpulse(impulse * root.AssemblyMass)
	end

	for _, part in ipairs(character:GetDescendants()) do
		if part:IsA("BasePart") and part ~= root then
			part:ApplyAngularImpulse(Vector3.new(
				math.random(CONFIG.angularImpulseMin, CONFIG.angularImpulseMax),
				math.random(CONFIG.angularImpulseMin, CONFIG.angularImpulseMax),
				math.random(CONFIG.angularImpulseMin, CONFIG.angularImpulseMax)
				))
		end
	end

	task.delay(duration, function()
		RagdollUtil._Recover(character, hum)
	end)
end

-- ============================================================
-- INTERNAL: _Recover
-- ============================================================
function RagdollUtil._Recover(character, hum)
	if not character or not character.Parent then return end
	if not hum or not hum.Parent then return end
	if hum.Health <= 0 then return end

	unRagdoll(character)

	-- Return network ownership to its natural owner AFTER physics settle.
	task.wait(0.1)
	releaseOwnership(character)
end

-- ============================================================
-- PUBLIC: ForceRecover
-- ============================================================
function RagdollUtil.ForceRecover(character)
	if not character then return end
	local tag = character:FindFirstChild("Ragdolled")
	if tag then tag:Destroy() end
	local hum = character:FindFirstChildOfClass("Humanoid")
	if hum and hum.Parent then
		unRagdoll(character)
		task.wait(0.1)
		releaseOwnership(character)
	end
end

-- ============================================================
-- PUBLIC: IsRagdolled
-- ============================================================
function RagdollUtil.IsRagdolled(character)
	return character ~= nil and character:FindFirstChild("Ragdolled") ~= nil
end

return RagdollUtil