-- @ScriptType: LocalScript
-- @ScriptType: LocalScript
-- ============================================================
--  SkillHUD.lua  |  LocalScript
--  Location: StarterGui/SkillHUD/SkillHUD
--  (ScreenGui: ResetOnSpawn = false, Name = "SkillHUD")
--
--  FIXES:
--    • Slot keys now check CC state and local cooldown before
--      firing — prevents ghost fires while stunned/knocked down.
--    • Optimistic cooldown starts immediately on keypress using
--      meta.cooldown, corrected by server SkillCooldown event.
--    • WaitForChild loop retries after character respawn so the
--      HUD never gets stuck if SkillSystem.InitPlayer was slow.
--    • Ready flash (green border) when cooldown expires.
--    • SkillHUD_Slot keybinds are the ONLY hotbar trigger.
--      SkillClient's defaultKeybind (E / Z) still works for
--      players who prefer it — both fire the same UseSkill remote.
-- ============================================================

local Players      = game:GetService("Players")
local CAS          = game:GetService("ContextActionService")
local RS           = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local player    = Players.LocalPlayer
local playerGui = player.PlayerGui

local SkillRegistry = require(RS.Modules.SkillRegistry)

-- Wait for remotes created by CombatServer — retry up to 30s.
local CombatFB = RS:WaitForChild("CombatFeedback", 30)
local UseSkill  = RS:WaitForChild("UseSkill",       30)

-- ============================================================
-- DEVELOPER CONFIG
-- ============================================================
local CONFIG = {
	MAX_SLOTS    = 6,
	SLOT_KEYBINDS = {
		Enum.KeyCode.One,
		Enum.KeyCode.Two,
		Enum.KeyCode.Three,
		Enum.KeyCode.Four,
		Enum.KeyCode.Five,
		Enum.KeyCode.Six,
	},
	SLOT_SIZE        = 58,
	SLOT_GAP         = 6,
	BAR_Y_OFFSET     = -160,
	CD_OVERLAY_COLOR = Color3.fromRGB(8, 6, 16),
	CD_OVERLAY_ALPHA = 0.35,
}

-- ============================================================
-- PALETTE
-- ============================================================
local function rgb(r,g,b) return Color3.fromRGB(r,g,b) end
local C = {
	panel  = rgb(18, 14, 32),
	border = rgb(80, 60, 120),
	gold   = rgb(255, 210, 60),
	dim    = rgb(120, 110, 140),
	text   = rgb(220, 210, 240),
	ready  = rgb(60, 200, 100),
	empty  = rgb(35, 28, 55),
	white  = rgb(255, 255, 255),
}

-- ============================================================
-- CC STATE  — mirrors SkillClient / CombatClient checks
-- ============================================================
local function getCharacter() return player.Character end
local function isBlocked()
	local char = getCharacter()
	if not char then return true end
	return char:FindFirstChild("Stunned")       ~= nil
		or char:FindFirstChild("SoftKnockdown") ~= nil
		or char:FindFirstChild("HardKnockdown") ~= nil
		or char:FindFirstChild("Ragdolled")     ~= nil
end
local function hasWeapon()
	local char = getCharacter()
	return char ~= nil and char:FindFirstChildOfClass("Tool") ~= nil
end

-- ============================================================
-- LOCAL COOLDOWN TRACKER
-- [skillId] = expiry tick (from time())
-- ============================================================
local localCooldowns = {}

local function isOnCooldown(skillId)
	return localCooldowns[skillId] ~= nil and time() < localCooldowns[skillId]
end

local function setCooldown(skillId, duration)
	localCooldowns[skillId] = time() + duration
end

-- ============================================================
-- ROOT GUI
-- ============================================================
local existingGui = playerGui:FindFirstChild("SkillHUD")
if existingGui then existingGui:Destroy() end

local gui = Instance.new("ScreenGui")
gui.Name             = "SkillHUD"
gui.ResetOnSpawn     = false
gui.ZIndexBehavior   = Enum.ZIndexBehavior.Sibling
gui.Parent           = playerGui

local BAR_W = CONFIG.MAX_SLOTS * (CONFIG.SLOT_SIZE + CONFIG.SLOT_GAP) + CONFIG.SLOT_GAP

local container = Instance.new("Frame")
container.Size                   = UDim2.new(0, BAR_W, 0, CONFIG.SLOT_SIZE + 12)
container.Position               = UDim2.new(0.5, -BAR_W/2, 1, CONFIG.BAR_Y_OFFSET)
container.BackgroundTransparency = 1
container.BorderSizePixel        = 0
container.Parent                 = gui

-- ============================================================
-- SLOT TABLE
-- [i] = { frame, stroke, cdOverlay, cdLbl, cdTask, skillId }
-- ============================================================
local slots = {}

local function makeCorner(p, r)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, r or 6)
	c.Parent = p
end
local function makeStroke(p, col, t)
	local s = Instance.new("UIStroke")
	s.Color = col or C.border
	s.Thickness = t or 1
	s.Parent = p
	return s
end

-- ============================================================
-- COOLDOWN ANIMATION
-- ============================================================
local function startCooldown(slotIndex, duration)
	local data = slots[slotIndex]
	if not data or not data.cdOverlay then return end

	if data.cdTask then task.cancel(data.cdTask); data.cdTask = nil end

	-- Full overlay immediately
	data.cdOverlay.Size     = UDim2.new(1, 0, 1, 0)
	data.cdOverlay.Position = UDim2.new(0, 0, 0, 0)
	if data.cdLbl then data.cdLbl.Text = "" end

	-- Reset stroke to dim while on CD
	if data.stroke then data.stroke.Color = C.border end

	local startTime = time()
	data.cdTask = task.spawn(function()
		while true do
			task.wait(0.05)
			local remaining = duration - (time() - startTime)
			if remaining <= 0 then
				data.cdOverlay.Size = UDim2.new(1, 0, 0, 0)
				if data.cdLbl then data.cdLbl.Text = "" end
				-- Flash green border on ready
				if data.stroke then
					data.stroke.Color = C.ready
					task.delay(0.4, function()
						if data.stroke then data.stroke.Color = C.border end
					end)
				end
				data.cdTask = nil
				break
			end
			local frac = remaining / duration
			data.cdOverlay.Size = UDim2.new(1, 0, frac, 0)
			if data.cdLbl then
				data.cdLbl.Text = remaining >= 1
					and tostring(math.ceil(remaining))
					or  string.format("%.1f", remaining)
			end
		end
	end)
end

local function findSlot(skillId)
	for i, data in ipairs(slots) do
		if data.skillId == skillId then return i end
	end
	return nil
end

-- ============================================================
-- BUILD SLOTS
-- Called each time Plr_EquippedSkills changes.
-- ============================================================
local function clearSlots()
	for _, data in ipairs(slots) do
		if data.cdTask then task.cancel(data.cdTask) end
		if data.frame  then data.frame:Destroy() end
	end
	slots = {}
	for i = 1, CONFIG.MAX_SLOTS do
		CAS:UnbindAction("SkillHUD_Slot_" .. i)
	end
end

local function buildSlots(equippedCSV)
	clearSlots()

	local ids = {}
	if equippedCSV and equippedCSV ~= "" then
		for id in equippedCSV:gmatch("[^,]+") do
			table.insert(ids, id:match("^%s*(.-)%s*$"))
		end
	end

	for i = 1, CONFIG.MAX_SLOTS do
		local skillId = ids[i]
		local meta    = skillId and SkillRegistry.Get(skillId)

		local x = CONFIG.SLOT_GAP + (i - 1) * (CONFIG.SLOT_SIZE + CONFIG.SLOT_GAP)

		-- ── Slot frame ────────────────────────────────────────
		local frame = Instance.new("Frame")
		frame.Size                   = UDim2.new(0, CONFIG.SLOT_SIZE, 0, CONFIG.SLOT_SIZE)
		frame.Position               = UDim2.new(0, x, 0, 6)
		frame.BackgroundColor3       = meta and C.panel or C.empty
		frame.BackgroundTransparency = 0.15
		frame.BorderSizePixel        = 0
		frame.Parent                 = container
		makeCorner(frame, 7)
		local stroke = makeStroke(frame, meta and C.border or rgb(50, 40, 75))

		-- ── Slot number badge ─────────────────────────────────
		local numLbl = Instance.new("TextLabel")
		numLbl.Size                   = UDim2.new(0, 16, 0, 16)
		numLbl.Position               = UDim2.new(0, 3, 0, 3)
		numLbl.BackgroundTransparency = 1
		numLbl.Text                   = tostring(i)
		numLbl.TextColor3             = meta and C.gold or C.dim
		numLbl.TextSize               = 10
		numLbl.Font                   = Enum.Font.GothamBold
		numLbl.ZIndex                 = frame.ZIndex + 1
		numLbl.Parent                 = frame

		local cdOverlay, cdLbl

		if meta then
			-- ── Icon ──────────────────────────────────────────
			if meta.icon and meta.icon ~= "" then
				local img = Instance.new("ImageLabel")
				img.Size                   = UDim2.new(1, -6, 1, -6)
				img.Position               = UDim2.new(0, 3, 0, 3)
				img.BackgroundTransparency = 1
				img.Image                  = meta.icon
				img.ScaleType              = Enum.ScaleType.Fit
				img.ZIndex                 = frame.ZIndex + 1
				img.Parent                 = frame
			end

			-- ── Skill name ────────────────────────────────────
			local nameLbl = Instance.new("TextLabel")
			nameLbl.Size                   = UDim2.new(1, -4, 0.55, 0)
			nameLbl.Position               = UDim2.new(0, 2, 0.2, 0)
			nameLbl.BackgroundTransparency = 1
			nameLbl.Text                   = meta.displayName
			nameLbl.TextColor3             = C.text
			nameLbl.TextSize               = 10
			nameLbl.Font                   = Enum.Font.GothamBold
			nameLbl.TextWrapped            = true
			nameLbl.TextXAlignment         = Enum.TextXAlignment.Center
			nameLbl.ZIndex                 = frame.ZIndex + 1
			nameLbl.Parent                 = frame

			-- ── Keybind label ─────────────────────────────────
			local kbLbl = Instance.new("TextLabel")
			kbLbl.Size                   = UDim2.new(1, -4, 0, 14)
			kbLbl.Position               = UDim2.new(0, 2, 1, -16)
			kbLbl.BackgroundTransparency = 1
			local kb = CONFIG.SLOT_KEYBINDS[i]
			kbLbl.Text         = kb and ("[" .. tostring(kb):match("[^.]+$") .. "]") or ""
			kbLbl.TextColor3   = C.gold
			kbLbl.TextSize     = 9
			kbLbl.Font         = Enum.Font.Gotham
			kbLbl.TextXAlignment = Enum.TextXAlignment.Center
			kbLbl.ZIndex         = frame.ZIndex + 1
			kbLbl.Parent         = frame

			-- ── Cooldown overlay ──────────────────────────────
			cdOverlay = Instance.new("Frame")
			cdOverlay.Size                   = UDim2.new(1, 0, 0, 0)
			cdOverlay.Position               = UDim2.new(0, 0, 0, 0)
			cdOverlay.BackgroundColor3       = CONFIG.CD_OVERLAY_COLOR
			cdOverlay.BackgroundTransparency = CONFIG.CD_OVERLAY_ALPHA
			cdOverlay.BorderSizePixel        = 0
			cdOverlay.ZIndex                 = frame.ZIndex + 2
			makeCorner(cdOverlay, 7)
			cdOverlay.Parent = frame

			cdLbl = Instance.new("TextLabel")
			cdLbl.Size                   = UDim2.new(1, 0, 1, 0)
			cdLbl.BackgroundTransparency = 1
			cdLbl.Text                   = ""
			cdLbl.TextColor3             = C.white
			cdLbl.TextSize               = 15
			cdLbl.Font                   = Enum.Font.GothamBold
			cdLbl.TextXAlignment         = Enum.TextXAlignment.Center
			cdLbl.ZIndex                 = frame.ZIndex + 3
			cdLbl.Parent                 = cdOverlay

			-- ── Slot keybind ──────────────────────────────────
			-- Checks CC state and local cooldown before firing.
			if kb then
				local capturedId   = skillId
				local capturedMeta = meta
				local capturedSlot = i
				CAS:BindAction("SkillHUD_Slot_" .. i, function(_, inputState, _)
					if inputState ~= Enum.UserInputState.Begin then
						return Enum.ContextActionResult.Pass
					end

					-- Client-side gates (server validates again)
					if isBlocked()                                                then return Enum.ContextActionResult.Sink end
					if capturedMeta.requiresWeapon ~= false and not hasWeapon()  then return Enum.ContextActionResult.Sink end
					if isOnCooldown(capturedId)                                   then return Enum.ContextActionResult.Sink end

					-- Optimistic cooldown starts immediately
					local cd = capturedMeta.cooldown or 0
					if cd > 0 then
						setCooldown(capturedId, cd)
						startCooldown(capturedSlot, cd)
					end

					UseSkill:FireServer({ skillId = capturedId })
					return Enum.ContextActionResult.Sink
				end, false, kb)
			end
		end

		slots[i] = {
			frame     = frame,
			stroke    = stroke,
			cdOverlay = cdOverlay,
			cdLbl     = cdLbl,
			cdTask    = nil,
			skillId   = skillId,
		}

		-- If already on cooldown from a previous session / respawn, restore it
		if skillId and isOnCooldown(skillId) then
			local remaining = localCooldowns[skillId] - time()
			if remaining > 0 then
				startCooldown(i, remaining)
			end
		end
	end
end

-- ============================================================
-- WATCH Plr_EquippedSkills
-- Retries every 0.5 s for 30 s so a slow server start never
-- leaves the HUD permanently empty.
-- ============================================================
task.spawn(function()
	local val
	local waited = 0
	repeat
		val = player:FindFirstChild("Plr_EquippedSkills")
		if not val then task.wait(0.5); waited += 0.5 end
	until val or waited >= 30

	if not val then
		warn("[SkillHUD] Plr_EquippedSkills never appeared — skills will not show.")
		return
	end

	buildSlots(val.Value)
	val.Changed:Connect(buildSlots)
end)

-- ============================================================
-- SERVER COOLDOWN CORRECTION
-- Overrides the optimistic CD with the authoritative remaining time.
-- ============================================================
if CombatFB then
	CombatFB.OnClientEvent:Connect(function(data)
		if not data then return end
		if data.type == "SkillCooldown" and data.skillId and data.remaining then
			-- Authoritative correction
			localCooldowns[data.skillId] = time() + data.remaining
			local idx = findSlot(data.skillId)
			if idx then startCooldown(idx, data.remaining) end
		end
	end)
end

-- ============================================================
-- DEATH / RESPAWN  — visual reset only; server holds true CDs
-- ============================================================
player.CharacterAdded:Connect(function()
	for _, data in ipairs(slots) do
		if data.cdOverlay then data.cdOverlay.Size = UDim2.new(1, 0, 0, 0) end
		if data.cdLbl     then data.cdLbl.Text = "" end
		if data.cdTask    then task.cancel(data.cdTask); data.cdTask = nil end
		if data.stroke    then data.stroke.Color = C.border end
	end
	-- localCooldowns intentionally kept — server will correct on next fire.
end)