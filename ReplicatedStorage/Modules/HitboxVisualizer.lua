-- @ScriptType: ModuleScript
-- @ScriptType: ModuleScript
-- ============================================================
--  HitboxVisualizer.lua  |  ModuleScript
--  Location: ReplicatedStorage/Modules/HitboxVisualizer
--  (LocalScript context only — never require from server)
--
--  Renders debug hitbox overlays locally on the client.
--  Does NOT use MuchachoHitbox's built-in visualizer (which runs
--  on the server and is visible to all clients).
--
--  Two overlapping boxes are shown per hitbox event:
--    Black (low alpha) — raw hitbox exactly where the server cast
--    Red   (low alpha) — velocity-predicted hitbox
--
--  Server sends "DebugHitbox" via CombatFeedback with fields:
--    cf               CFrame   — hitbox centre
--    size             Vector3  — hitbox dimensions
--    rootVelocity     Vector3  — attacker's linear velocity
--    velocityPrediction bool   — prediction enabled?
--    vpTime           number   — prediction lookahead seconds
--
--  Call HitboxVisualizer.Enable(true/false) to toggle at runtime.
-- ============================================================

local Debris = game:GetService("Debris")

-- ── Developer config ──────────────────────────────────────────
local CONFIG = {
	-- Duration (seconds) each debug box stays visible.
	BOX_LIFETIME   = 0.25,

	-- Raw hitbox: black neon, slightly transparent.
	RAW_COLOR      = Color3.fromRGB(0, 0, 0),
	RAW_ALPHA      = 0.55,

	-- Predicted hitbox: red neon, more transparent.
	PRED_COLOR     = Color3.fromRGB(255, 30, 30),
	PRED_ALPHA     = 0.70,
}

local HitboxVisualizer = {}

local enabled = true   -- toggled by Enable()

function HitboxVisualizer.Enable(state)
	enabled = state
end

function HitboxVisualizer.IsEnabled()
	return enabled
end

-- ── Internal box factory ──────────────────────────────────────
local function makePart(color, alpha, size, cf)
	local p = Instance.new("Part")
	p.Anchored          = true
	p.CanCollide        = false
	p.CanTouch          = false
	p.CanQuery          = false
	p.CastShadow        = false
	p.Material          = Enum.Material.Neon
	p.Color             = color
	p.Transparency      = alpha
	p.Size              = size
	p.CFrame            = cf
	p.Parent            = workspace
	Debris:AddItem(p, CONFIG.BOX_LIFETIME)
	return p
end

-- ── Render ───────────────────────────────────────────────────
-- Call this from CombatClient's CombatFeedback handler.
-- data: the payload received from the server DebugHitbox event.
function HitboxVisualizer.Render(data)
	if not enabled then return end
	if not data then return end

	local cf   = data.cf
	local size = data.size
	if not cf or not size then return end

	-- Black = raw hitbox
	makePart(CONFIG.RAW_COLOR, CONFIG.RAW_ALPHA, size, cf)

	-- Red = velocity-predicted hitbox
	if data.velocityPrediction and data.rootVelocity and data.vpTime then
		local shift    = data.rootVelocity * data.vpTime
		local predCF   = cf * CFrame.new(shift)
		makePart(CONFIG.PRED_COLOR, CONFIG.PRED_ALPHA, size, predCF)
	end
end

return HitboxVisualizer