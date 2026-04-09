-- @ScriptType: ModuleScript
-- @ScriptType: ModuleScript
-- ============================================================
--  TomatoHitbox.lua  |  ModuleScript
--  Location: ServerScriptService/Modules/TomatoHitbox
--
--  MuchachoHitbox (SushiMaster) — adapted for server-side combat.
--  Original: https://devforum.roblox.com/t/muchachohitbox-an-easy-to-use-spatialquery-based-hitbox-system/3682320
--
--  Changes from original:
--    • Visualizer is disabled by default on the server.
--      Debug rendering is handled client-side via CombatFeedback
--      "DebugHitbox" events so only the attacker sees their own hitbox.
--    • FilterCharacter: set to the attacker's character so the owner
--      is never returned as a hit target.
--    • HitOnce: if true (default), each humanoid can only trigger
--      onTouch once per hitbox lifetime regardless of Heartbeat rate.
--    • Hitbox.CFrame accepts a BasePart instance (live-tracking) or
--      a CFrame value (static position). See examples below.
--
--  ── Usage ───────────────────────────────────────────────────
--
--    local TomatoHitbox = require(ServerScriptService.Modules.TomatoHitbox)
--
--    local hb = TomatoHitbox.new()
--    hb.Size            = Vector3.new(5, 5, 7)
--    hb.CFrame          = attackerRoot         -- BasePart: live-tracks it
--    hb.Offset          = CFrame.new(0, 0, -3) -- forward offset
--    hb.FilterCharacter = attackerChar         -- self-exclude
--    hb.HitOnce         = true                 -- default, recommended
--
--    hb.onTouch = function(humanoid)
--        -- called once per unique humanoid while active
--        humanoid:TakeDamage(15)
--    end
--
--    hb:Start()
--    task.wait(0.15)   -- hit window
--    hb:Stop()
--    hb:Destroy()
-- ============================================================

local RunService = game:GetService("RunService")

local TomatoHitbox = {}
TomatoHitbox.__index = TomatoHitbox

-- ── Constructor ───────────────────────────────────────────────
function TomatoHitbox.new()
	local self = setmetatable({}, TomatoHitbox)
	self.Size            = Vector3.new(5, 5, 5)
	self.CFrame          = CFrame.new(0, 5, 0)   -- BasePart or CFrame
	self.Offset          = CFrame.new()
	self.FilterCharacter = nil    -- Model to exclude from hits
	self.HitOnce         = true   -- each humanoid only triggers once
	self.Visualizer      = false  -- disabled on server; handled client-side

	self.Humanoids       = {}     -- deduplicated hit list
	self._connection     = nil
	self._box            = nil    -- BoxHandleAdornment (only if Visualizer=true)
	return self
end

-- ── Resolve CFrame from BasePart or CFrame value ─────────────
local function resolveCF(cfValue)
	local t = typeof(cfValue)
	if t == "Instance" and cfValue:IsA("BasePart") then
		return cfValue.CFrame
	elseif t == "CFrame" then
		return cfValue
	else
		return CFrame.new()
	end
end

-- ── Visualizer (server-side BoxHandleAdornment) ───────────────
function TomatoHitbox:_UpdateVisualizer(cf)
	if not self.Visualizer then
		if self._box then self._box:Destroy(); self._box = nil end
		return
	end
	if not self._box then
		self._box = Instance.new("BoxHandleAdornment")
		self._box.Adornee     = workspace.Terrain
		self._box.Color3      = Color3.fromRGB(255, 0, 0)
		self._box.Transparency= 0.5
		self._box.AlwaysOnTop = true
		self._box.Parent      = workspace.Terrain
	end
	self._box.CFrame = cf * self.Offset
	self._box.Size   = self.Size
end

-- ── Spatial cast ─────────────────────────────────────────────
function TomatoHitbox:_Cast()
	local realCF = resolveCF(self.CFrame) * self.Offset

	self:_UpdateVisualizer(resolveCF(self.CFrame))

	local params = OverlapParams.new()
	if self.FilterCharacter then
		params.FilterDescendantsInstances = { self.FilterCharacter }
		params.FilterType = Enum.RaycastFilterType.Exclude
	end

	local parts = workspace:GetPartBoundsInBox(realCF, self.Size, params)

	for _, part in ipairs(parts) do
		local humanoid = part.Parent:FindFirstChildOfClass("Humanoid")
		if humanoid then
			local alreadyHit = table.find(self.Humanoids, humanoid)
			if self.HitOnce and alreadyHit then continue end
			if not alreadyHit then
				table.insert(self.Humanoids, humanoid)
			end
			self.onTouch(humanoid)
		end
	end
end

-- ── Start ─────────────────────────────────────────────────────
function TomatoHitbox:Start()
	if self._connection then return end  -- already running
	task.spawn(function()
		self._connection = RunService.Heartbeat:Connect(function()
			self:_Cast()
		end)
	end)
end

-- ── Stop ──────────────────────────────────────────────────────
function TomatoHitbox:Stop()
	if self._connection then
		self._connection:Disconnect()
		self._connection = nil
	end
	if self._box then
		self._box:Destroy()
		self._box = nil
	end
end

-- ── Destroy ───────────────────────────────────────────────────
function TomatoHitbox:Destroy()
	self:Stop()
	self.Humanoids = {}
	setmetatable(self, nil)
end

-- ── Default onTouch callback ──────────────────────────────────
TomatoHitbox.onTouch = function(humanoid)
	-- Override this before calling Start().
end

return TomatoHitbox