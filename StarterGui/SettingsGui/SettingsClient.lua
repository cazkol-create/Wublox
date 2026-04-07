-- @ScriptType: LocalScript
-- ============================================================
--  SettingsClient.lua  |  LocalScript
--  Location: StarterGui/SettingsGui/SettingsClient
--  (Parent should be a ScreenGui named "SettingsGui",
--   ResetOnSpawn = false)
--
--  Settings:
--    1. Debug Mode       — shows hitbox visualizer (server-side per-player)
--    2. Disable Notifs   — suppresses toast notifications from MainServer
--    3. Key Rebinds      — M1, Heavy, Block keys via CAS
-- ============================================================

local Players           = game:GetService("Players")
local RS                = game:GetService("ReplicatedStorage")
local UIS               = game:GetService("UserInputService")

local player    = Players.LocalPlayer
local playerGui = player.PlayerGui

local GameSettingsRE = RS:WaitForChild("GameSettings", 10)

-- ============================================================
-- SETTINGS STATE
-- The only server-synced setting is DebugMode.
-- Everything else is purely local.
-- ============================================================
local Settings = {
	DebugMode            = false,
	DisableNotifications = false,
}

-- Push to server
local function syncSetting(settingName, value)
	if GameSettingsRE then
		GameSettingsRE:FireServer({ setting = settingName, value = value })
	end
end

-- Expose to other scripts via _G
_G.WuxiaSettings = Settings

-- ============================================================
-- COLOR PALETTE  (matches WuxiaHUD)
-- ============================================================
local function rgb(r,g,b) return Color3.fromRGB(r,g,b) end
local C = {
	panel    = rgb(18, 14, 32),
	border   = rgb(80, 60, 120),
	text     = rgb(220, 210, 240),
	dim      = rgb(120, 110, 140),
	gold     = rgb(255, 210, 60),
	red      = rgb(200, 60, 60),
	green    = rgb(60, 200, 100),
	darkBlue = rgb(30, 20, 60),
	white    = rgb(255, 255, 255),
	black    = rgb(0, 0, 0),
	active   = rgb(60, 200, 100),
	inactive = rgb(80, 60, 100),
}

-- ============================================================
-- UI HELPERS
-- ============================================================
local function makeFrame(parent, size, pos, color, alpha)
	local f = Instance.new("Frame")
	f.Size = size;  f.Position = pos
	f.BackgroundColor3 = color or C.panel
	f.BackgroundTransparency = alpha or 0
	f.BorderSizePixel = 0;  f.Parent = parent
	return f
end

local function makeLabel(parent, text, size, pos, color, fontSize)
	local l = Instance.new("TextLabel")
	l.Size = size;  l.Position = pos
	l.BackgroundTransparency = 1
	l.Text = text;  l.TextColor3 = color or C.text
	l.TextSize = fontSize or 13;  l.Font = Enum.Font.GothamBold
	l.TextXAlignment = Enum.TextXAlignment.Left
	l.Parent = parent
	return l
end

local function makeButton(parent, text, size, pos, bg, fg)
	local b = Instance.new("TextButton")
	b.Size = size;  b.Position = pos
	b.BackgroundColor3 = bg or C.border
	b.BorderSizePixel = 0
	b.Text = text;  b.TextColor3 = fg or C.white
	b.TextSize = 12;  b.Font = Enum.Font.GothamBold
	b.Parent = parent
	return b
end

local function corner(parent, r)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, r or 6)
	c.Parent = parent
end

local function stroke(parent, color, thick)
	local s = Instance.new("UIStroke")
	s.Color = color or C.border;  s.Thickness = thick or 1
	s.Parent = parent
end

-- Converts an Enum to a short display name
local function enumToDisplay(e)
	if not e then return "—" end
	local str = tostring(e)
	local name = str:match("[^.]+$") or str
	local renames = {
		MouseButton1 = "LMB",
		MouseButton2 = "RMB",
		MouseButton3 = "MMB",
	}
	return renames[name] or name
end

-- ============================================================
-- ROOT GUI
-- ============================================================
local gui = Instance.new("ScreenGui")
gui.Name = "SettingsGui";  gui.ResetOnSpawn = false
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.IgnoreGuiInset = true
gui.Parent = playerGui

-- ── Gear Button ───────────────────────────────────────────────
local gearBtn = makeButton(gui, "⚙",
	UDim2.new(0, 36, 0, 36), UDim2.new(1, -50, 1, -50),
	C.panel, C.gold)
gearBtn.TextSize = 18
corner(gearBtn, 8);  stroke(gearBtn, C.border)

-- ── Settings Panel ────────────────────────────────────────────
local panel = makeFrame(gui,
	UDim2.new(0, 320, 0, 380),
	UDim2.new(1, -370, 1, -440),
	C.panel, 0.05)
panel.Visible = false
corner(panel, 10);  stroke(panel, C.gold)

makeLabel(panel, "⚙  Settings",
	UDim2.new(1, -20, 0, 28), UDim2.new(0, 14, 0, 10),
	C.gold, 16)

local divider = makeFrame(panel,
	UDim2.new(1, -28, 0, 1), UDim2.new(0, 14, 0, 42),
	C.border, 0)

gearBtn.MouseButton1Click:Connect(function()
	panel.Visible = not panel.Visible
end)

-- ============================================================
-- SECTION 1: TOGGLES
-- ============================================================

makeLabel(panel, "DISPLAY",
	UDim2.new(1, -20, 0, 16), UDim2.new(0, 14, 0, 52),
	C.dim, 10)

-- ── Toggle helper ─────────────────────────────────────────────
local function makeToggle(parent, labelText, description, yPos, getter, setter)
	local row = makeFrame(parent,
		UDim2.new(1, -28, 0, 48), UDim2.new(0, 14, 0, yPos),
		rgb(25, 20, 42), 0)
	corner(row, 6);  stroke(row, C.border)

	makeLabel(row, labelText,
		UDim2.new(1, -80, 0, 18), UDim2.new(0, 10, 0, 6),
		C.text, 13)

	makeLabel(row, description,
		UDim2.new(1, -80, 0, 16), UDim2.new(0, 10, 0, 26),
		C.dim, 10)

	local toggleBtn = makeButton(row, getter() and "ON" or "OFF",
		UDim2.new(0, 50, 0, 24), UDim2.new(1, -62, 0, 12),
		getter() and C.green or C.inactive, C.white)
	corner(toggleBtn, 5)

	toggleBtn.MouseButton1Click:Connect(function()
		local newVal = not getter()
		setter(newVal)
		toggleBtn.Text             = newVal and "ON" or "OFF"
		toggleBtn.BackgroundColor3 = newVal and C.green or C.inactive
	end)
end

makeToggle(panel, "Debug Mode",
	"Shows hitbox visualizer",
	72,
	function() return Settings.DebugMode end,
	function(v)
		Settings.DebugMode = v
		syncSetting("DebugMode", v)
	end
)

makeToggle(panel, "Disable Notifications",
	"Hides meditation / system toasts",
	128,
	function() return Settings.DisableNotifications end,
	function(v)
		Settings.DisableNotifications = v
		-- No server sync needed — HudScript checks _G.WuxiaSettings locally
	end
)

-- ============================================================
-- SECTION 2: KEY REBINDS
-- ============================================================

makeLabel(panel, "KEY BINDS",
	UDim2.new(1, -20, 0, 16), UDim2.new(0, 14, 0, 186),
	C.dim, 10)

-- Current listening state — only one bind active at a time
local listeningAction = nil
local bindButtons     = {}   -- [actionName] = TextButton

local function getActionDisplayName(actionName)
	local names = {
		Combat_M1    = "Light Attack (M1)",
		Combat_Heavy = "Heavy Attack",
		Combat_Block = "Block / Parry",
	}
	return names[actionName] or actionName
end

local function getCurrentBindDisplay(actionName)
	if not _G.WuxiaClient then return "—" end
	local binds = _G.WuxiaClient.GetCombatBinds and _G.WuxiaClient.GetCombatBinds()
	if not binds or not binds[actionName] then return "—" end
	local parts = {}
	for _, k in ipairs(binds[actionName]) do
		table.insert(parts, enumToDisplay(k))
	end
	return table.concat(parts, " / ")
end

local function stopListening()
	if not listeningAction then return end
	local btn = bindButtons[listeningAction]
	if btn then
		btn.Text             = getCurrentBindDisplay(listeningAction)
		btn.BackgroundColor3 = C.darkBlue
	end
	listeningAction = nil
end

-- Creates one rebind row
local function makeRebindRow(actionName, yPos)
	local row = makeFrame(panel,
		UDim2.new(1, -28, 0, 40), UDim2.new(0, 14, 0, yPos),
		rgb(25, 20, 42), 0)
	corner(row, 6);  stroke(row, C.border)

	makeLabel(row, getActionDisplayName(actionName),
		UDim2.new(1, -130, 0, 24), UDim2.new(0, 10, 0, 8),
		C.text, 12)

	local keyBtn = makeButton(row, getCurrentBindDisplay(actionName),
		UDim2.new(0, 100, 0, 24), UDim2.new(1, -112, 0, 8),
		C.darkBlue, C.gold)
	corner(keyBtn, 5);  stroke(keyBtn, C.border)
	bindButtons[actionName] = keyBtn

	keyBtn.MouseButton1Click:Connect(function()
		if listeningAction == actionName then
			stopListening()
			return
		end
		stopListening()
		listeningAction      = actionName
		keyBtn.Text          = "Press a key..."
		keyBtn.BackgroundColor3 = rgb(60, 40, 20)
	end)
end

local actions = { "Combat_M1", "Combat_Heavy", "Combat_Block" }
local startY  = 206
for i, name in ipairs(actions) do
	makeRebindRow(name, startY + (i - 1) * 48)
end

-- ── Listen for input when in rebind mode ─────────────────────
UIS.InputBegan:Connect(function(input, processed)
	if not listeningAction then return end
	-- Ignore Escape — cancel rebind
	if input.KeyCode == Enum.KeyCode.Escape then
		stopListening()
		return
	end

	-- Resolve to a bindable Enum
	local newKey
	if input.UserInputType == Enum.UserInputType.Keyboard then
		newKey = input.KeyCode
	elseif input.UserInputType == Enum.UserInputType.MouseButton1
		or input.UserInputType == Enum.UserInputType.MouseButton2 then
		newKey = input.UserInputType
	else
		return   -- gamepad / touch handled by CAS automatically
	end

	-- Don't let the player bind a key that's already used by another action
	local conflict = false
	if _G.WuxiaClient and _G.WuxiaClient.GetCombatBinds then
		for name, keys in pairs(_G.WuxiaClient.GetCombatBinds()) do
			if name ~= listeningAction then
				for _, k in ipairs(keys) do
					if k == newKey then conflict = true; break end
				end
			end
			if conflict then break end
		end
	end

	if conflict then
		local btn = bindButtons[listeningAction]
		if btn then
			btn.Text = "⚠ Already bound!"
			task.delay(1.2, function()
				if listeningAction then
					btn.Text = "Press a key..."
				else
					btn.Text = getCurrentBindDisplay(listeningAction or "")
				end
			end)
		end
		return
	end

	-- Apply the new bind
	if _G.WuxiaClient and _G.WuxiaClient.RebindCombatAction then
		_G.WuxiaClient.RebindCombatAction(listeningAction, newKey)
	end

	stopListening()
end)

-- ── Close panel if clicking outside ──────────────────────────
UIS.InputBegan:Connect(function(input, _processed)
	if not panel.Visible then return end
	if input.UserInputType == Enum.UserInputType.MouseButton1 then
		-- Very small delay so the gear button click doesn't immediately close it
		task.wait(0.05)
		local mousePos = UIS:GetMouseLocation()
		local absPos   = panel.AbsolutePosition
		local absSize  = panel.AbsoluteSize
		local inPanel  = mousePos.X >= absPos.X and mousePos.X <= absPos.X + absSize.X
			and mousePos.Y >= absPos.Y and mousePos.Y <= absPos.Y + absSize.Y
		if not inPanel then
			stopListening()
			panel.Visible = false
		end
	end
end)

-- ============================================================
-- INTEGRATION: Suppress notifications when setting is on
-- Patch into the existing notify queue used by HudScript.
-- HudScript already checks _G.WuxiaSettings.DisableNotifications
-- before adding to the queue — no changes to HudScript needed
-- as long as you add this check in HudScript's reNotify.OnClientEvent:
--
--   reNotify.OnClientEvent:Connect(function(message)
--       if _G.WuxiaSettings and _G.WuxiaSettings.DisableNotifications then
--           return   -- ← add this line
--       end
--       table.insert(notifQueue, message)
--       showNextNotif()
--   end)
-- ============================================================