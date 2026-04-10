-- @ScriptType: LocalScript
-- @ScriptType: LocalScript
-- ============================================================
--  InventoryClient.lua  |  LocalScript
--  Location: StarterGui/InventoryGui/InventoryClient
--  (ScreenGui: ResetOnSpawn = false)
--
--  CHANGES:
--    Styles tab  — added as a third tab alongside Weapons and Skills.
--    The tab rebuilds whenever Plr_WeaponType or Plr_StyleName changes.
--    Clicking a style button fires the ChangeStyle remote.
-- ============================================================

local Players    = game:GetService("Players")
local StarterGui = game:GetService("StarterGui")
local CAS        = game:GetService("ContextActionService")
local RS         = game:GetService("ReplicatedStorage")
local UIS        = game:GetService("UserInputService")

local player    = Players.LocalPlayer
local playerGui = player.PlayerGui

local InventoryData = require(RS.Modules.InventoryData)
local SkillRegistry = require(RS.Modules.SkillRegistry)

local EquipTool    = RS:WaitForChild("EquipTool",    10)
local UnequipTool  = RS:WaitForChild("UnequipTool",  10)
local InventorySync= RS:WaitForChild("InventorySync",10)
local EquipSkill   = RS:WaitForChild("EquipSkill",   15)
local UnequipSkill = RS:WaitForChild("UnequipSkill", 15)
local ChangeStyle  = RS:WaitForChild("ChangeStyle",  15)

local function hideBackpack()
	pcall(function()
		StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Backpack, false)
	end)
end
hideBackpack()
player.CharacterAdded:Connect(hideBackpack)

-- ============================================================
-- STATE
-- ============================================================
local equippedTool = nil
local selectedTool = nil
local activeTab    = "Weapons"  -- "Weapons" | "Skills" | "Styles"

-- ============================================================
-- PALETTE
-- ============================================================
local function rgb(r,g,b) return Color3.fromRGB(r,g,b) end
local C = {
	bg        = rgb(12, 10, 22),
	panel     = rgb(18, 14, 32),
	border    = rgb(80, 60,120),
	gold      = rgb(255,210, 60),
	equipped  = rgb(60, 200,100),
	selected  = rgb(100,160,255),
	empty     = rgb(60, 50, 90),
	text      = rgb(220,210,240),
	dim       = rgb(120,110,140),
	white     = rgb(255,255,255),
	red       = rgb(200, 60, 60),
	darkPanel = rgb(22, 18, 38),
	activeTab = rgb(100,160,255),
	inactTab  = rgb(50, 40, 80),
}

-- ============================================================
-- UI HELPERS
-- ============================================================
local function makeFrame(parent, size, pos, color, alpha)
	local f=Instance.new("Frame"); f.Size=size; f.Position=pos
	f.BackgroundColor3=color or C.panel; f.BackgroundTransparency=alpha or 0
	f.BorderSizePixel=0; f.Parent=parent; return f
end
local function makeLabel(parent, text, size, pos, color, fs, xa)
	local l=Instance.new("TextLabel"); l.Size=size; l.Position=pos
	l.BackgroundTransparency=1; l.Text=text; l.TextColor3=color or C.text
	l.TextSize=fs or 13; l.Font=Enum.Font.GothamBold
	l.TextXAlignment=xa or Enum.TextXAlignment.Left
	l.TextTruncate=Enum.TextTruncate.AtEnd; l.Parent=parent; return l
end
local function makeButton(parent, text, size, pos, bg, fg, fs)
	local b=Instance.new("TextButton"); b.Size=size; b.Position=pos
	b.BackgroundColor3=bg or C.border; b.BorderSizePixel=0
	b.Text=text; b.TextColor3=fg or C.white
	b.TextSize=fs or 13; b.Font=Enum.Font.GothamBold
	b.AutoButtonColor=false; b.Parent=parent; return b
end
local function corner(p, r)
	local c=Instance.new("UICorner"); c.CornerRadius=UDim.new(0,r or 6); c.Parent=p
end
local function stroke(p, color, t)
	local s=Instance.new("UIStroke"); s.Color=color or C.border; s.Thickness=t or 1; s.Parent=p
	return s
end

-- ============================================================
-- ROOT GUI
-- ============================================================
local existingGui = playerGui:FindFirstChild("InventoryGui")
if existingGui then existingGui:Destroy() end

local gui = Instance.new("ScreenGui")
gui.Name="InventoryGui"; gui.ResetOnSpawn=false
gui.ZIndexBehavior=Enum.ZIndexBehavior.Sibling; gui.Parent=playerGui

local EQ_W, EQ_H = 200, 90

-- Equipment panel (always visible)
local eqPanel = makeFrame(gui, UDim2.new(0,EQ_W,0,EQ_H),
	UDim2.new(0,14,1,-(EQ_H+14)), C.panel, 0.1)
corner(eqPanel,8); stroke(eqPanel,C.border)
makeLabel(eqPanel,"EQUIPMENT", UDim2.new(1,-12,0,14), UDim2.new(0,8,0,6), C.dim,10)

local weaponSlot = makeFrame(eqPanel, UDim2.new(1,-16,0,52), UDim2.new(0,8,0,24), C.darkPanel,0)
corner(weaponSlot,6); stroke(weaponSlot,C.border)
makeLabel(weaponSlot,"WEAPON", UDim2.new(0,52,1,0), UDim2.new(0,8,0,0), C.dim,9)

local iconBox = makeFrame(weaponSlot, UDim2.new(0,36,0,36), UDim2.new(0,6,0,8), C.empty,0)
corner(iconBox,4); stroke(iconBox,C.border)
local iconLabel = makeLabel(iconBox,"⚔", UDim2.new(1,0,1,0), UDim2.new(0,0,0,0), C.dim,18, Enum.TextXAlignment.Center)

local weaponNameLabel = makeLabel(weaponSlot,"[ Sheathed ]", UDim2.new(1,-52,0,20), UDim2.new(0,50,0,8), C.dim,12)
local weaponStyleLabel= makeLabel(weaponSlot,"", UDim2.new(1,-52,0,14), UDim2.new(0,50,0,28), C.dim,10)

local unequipBtn = makeButton(weaponSlot,"▼ Sheath", UDim2.new(0,58,0,16), UDim2.new(1,-66,0,18), rgb(40,30,60),C.dim,10)
corner(unequipBtn,3); stroke(unequipBtn,C.border,1); unequipBtn.Visible=false
unequipBtn.MouseButton1Click:Connect(function() UnequipTool:FireServer() end)

-- TAB + Select panel
local SEL_W = 240
local selectPanel = makeFrame(gui, UDim2.new(0,SEL_W,0,340),
	UDim2.new(0,14,1,-(EQ_H+14+8+340)), C.panel, 0.06)
selectPanel.ClipsDescendants=true; selectPanel.Visible=false
corner(selectPanel,8); stroke(selectPanel,C.gold)

-- Tab row
local tabRow = makeFrame(selectPanel, UDim2.new(1,0,0,30), UDim2.new(0,0,0,0), C.darkPanel,0)
corner(tabRow,8)

local tabNames = {"Weapons","Skills","Styles"}
local tabBtns = {}
for i, name in ipairs(tabNames) do
	local btn = makeButton(tabRow, name,
		UDim2.new(1/#tabNames,-4,0,26),
		UDim2.new((i-1)/#tabNames + 2/SEL_W, 0, 0, 2),
		C.inactTab, C.dim, 11)
	corner(btn,4)
	tabBtns[name] = btn
end

-- Scroll area below tab row
local scroll = Instance.new("ScrollingFrame")
scroll.Size=UDim2.new(1,-10,1,-36); scroll.Position=UDim2.new(0,5,0,32)
scroll.BackgroundTransparency=1; scroll.BorderSizePixel=0
scroll.ScrollBarThickness=3; scroll.ScrollBarImageColor3=C.border; scroll.Parent=selectPanel

local listLayout = Instance.new("UIListLayout")
listLayout.SortOrder=Enum.SortOrder.LayoutOrder; listLayout.Padding=UDim.new(0,6); listLayout.Parent=scroll
listLayout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
	scroll.CanvasSize=UDim2.new(0,0,0,listLayout.AbsoluteContentSize.Y+8)
end)

-- ============================================================
-- TAB SWITCHING
-- ============================================================
local function setActiveTab(name)
	activeTab = name
	for _, n in ipairs(tabNames) do
		tabBtns[n].BackgroundColor3 = n == name and C.activeTab or C.inactTab
		tabBtns[n].TextColor3       = n == name and C.white    or C.dim
	end
	-- Clear scroll and rebuild content.
	for _, child in ipairs(scroll:GetChildren()) do
		if not child:IsA("UIListLayout") then child:Destroy() end
	end
	if name == "Weapons" then buildWeaponsTab()
	elseif name == "Skills" then buildSkillsTab()
	elseif name == "Styles" then buildStylesTab()
	end
end

for _, name in ipairs(tabNames) do
	tabBtns[name].MouseButton1Click:Connect(function() setActiveTab(name) end)
end

-- ============================================================
-- TAB TOGGLE BUTTON
-- ============================================================
local tabBtn = makeButton(gui,"[ TAB ]",
	UDim2.new(0,EQ_W,0,24), UDim2.new(0,14,1,-(EQ_H+14+32)),
	C.darkPanel, C.gold, 11)
corner(tabBtn,5); stroke(tabBtn,C.border)

local panelOpen = false
tabBtn.MouseButton1Click:Connect(function()
	panelOpen = not panelOpen
	selectPanel.Visible = panelOpen
	if panelOpen then setActiveTab(activeTab) end
end)
UIS.InputBegan:Connect(function(input, processed)
	if processed then return end
	if input.KeyCode == Enum.KeyCode.Tab then
		panelOpen = not panelOpen
		selectPanel.Visible = panelOpen
		if panelOpen then setActiveTab(activeTab) end
	end
end)

-- ============================================================
-- WEAPONS TAB
-- ============================================================
local weaponRows = {}

function buildWeaponsTab()
	weaponRows = {}
	local ROW_H = 50
	for i, weapon in ipairs(InventoryData.Weapons) do
		local row = makeFrame(scroll, UDim2.new(1,-4,0,ROW_H), UDim2.new(0,2,0,0), C.darkPanel,0)
		row.LayoutOrder=i; corner(row,6)
		local rowStroke = stroke(row, C.border, 1)

		makeLabel(row, weapon.displayName, UDim2.new(1,-50,0,20), UDim2.new(0,10,0,8), C.text,13)
		local statusLabel = makeLabel(row, weapon.weaponType, UDim2.new(1,-50,0,14), UDim2.new(0,10,0,28), C.dim,10)

		local btn = makeButton(row,"", UDim2.new(1,0,1,0), UDim2.new(0,0,0,0), C.darkPanel,C.white,1)
		btn.BackgroundTransparency=1
		local captured = weapon.toolName
		btn.MouseButton1Click:Connect(function()
			selectedTool = captured; refreshSelectVisuals()
		end)
		weaponRows[weapon.toolName] = { frame=row, statusLabel=statusLabel, rowStroke=rowStroke }
	end
end

-- ============================================================
-- SKILLS TAB
-- ============================================================
function buildSkillsTab()
	local wt = player:FindFirstChild("Plr_WeaponType")
	local currentWT = (wt and wt.Value ~= "") and wt.Value or ""

	local equippedVal = player:FindFirstChild("Plr_EquippedSkills")
	local availVal    = player:FindFirstChild("Plr_AvailableSkills")
	local equippedIds = {}; local availIds = {}

	if equippedVal and equippedVal.Value ~= "" then
		for id in equippedVal.Value:gmatch("[^,]+") do table.insert(equippedIds, id) end
	end
	if availVal and availVal.Value ~= "" then
		for id in availVal.Value:gmatch("[^,]+") do table.insert(availIds, id) end
	end

	local row = makeFrame(scroll, UDim2.new(1,-4,0,16), UDim2.new(0,2,0,0), C.panel,1)
	row.LayoutOrder=0
	makeLabel(row,"EQUIPPED", UDim2.new(1,0,1,0), UDim2.new(0,0,0,0), C.dim,10)

	for i, skillId in ipairs(equippedIds) do
		local meta = SkillRegistry.Get(skillId); if not meta then continue end
		local skillRow = makeFrame(scroll, UDim2.new(1,-4,0,44), UDim2.new(0,2,0,0), C.darkPanel,0)
		skillRow.LayoutOrder=i; corner(skillRow,6); stroke(skillRow, C.equipped,1)
		makeLabel(skillRow, meta.displayName, UDim2.new(1,-70,0,20), UDim2.new(0,8,0,4), C.text,12)
		makeLabel(skillRow, meta.description or "", UDim2.new(1,-70,0,16), UDim2.new(0,8,0,24), C.dim,10)
		local unBtn = makeButton(skillRow,"Unequip", UDim2.new(0,60,0,22), UDim2.new(1,-68,0,11), rgb(60,20,20),C.red,11)
		corner(unBtn,4)
		local capturedId=skillId
		unBtn.MouseButton1Click:Connect(function()
			UnequipSkill:FireServer({skillId=capturedId}); setActiveTab("Skills")
		end)
	end

	local div = makeFrame(scroll, UDim2.new(1,-4,0,16), UDim2.new(0,2,0,0), C.panel,1)
	div.LayoutOrder=100
	makeLabel(div,"AVAILABLE", UDim2.new(1,0,1,0), UDim2.new(0,0,0,0), C.dim,10)

	local idx = 101
	for _, skillId in ipairs(availIds) do
		local equipped = false
		for _, eid in ipairs(equippedIds) do if eid==skillId then equipped=true; break end end
		if equipped then continue end
		local meta = SkillRegistry.Get(skillId); if not meta then continue end
		local compatible = SkillRegistry.IsCompatible(skillId, currentWT)

		local skillRow = makeFrame(scroll, UDim2.new(1,-4,0,44), UDim2.new(0,2,0,0), C.darkPanel,0)
		skillRow.LayoutOrder=idx; idx+=1; corner(skillRow,6)
		stroke(skillRow, compatible and C.border or rgb(50,40,55),1)
		makeLabel(skillRow, meta.displayName, UDim2.new(1,-70,0,20), UDim2.new(0,8,0,4),
			compatible and C.text or C.dim, 12)
		makeLabel(skillRow, meta.description or "", UDim2.new(1,-70,0,16), UDim2.new(0,8,0,24), C.dim,10)

		if compatible then
			local eqBtn = makeButton(skillRow,"Equip", UDim2.new(0,50,0,22), UDim2.new(1,-58,0,11), C.border,C.gold,11)
			corner(eqBtn,4)
			local capturedId=skillId
			eqBtn.MouseButton1Click:Connect(function()
				EquipSkill:FireServer({skillId=capturedId}); setActiveTab("Skills")
			end)
		else
			makeLabel(skillRow,"Wrong weapon", UDim2.new(0,60,0,14), UDim2.new(1,-68,0,15), C.dim,9)
		end
	end
end

-- ============================================================
-- STYLES TAB  [NEW]
-- ============================================================
function buildStylesTab()
	local wt = player:FindFirstChild("Plr_WeaponType")
	local sn = player:FindFirstChild("Plr_StyleName")
	local currentWT    = (wt and wt.Value ~= "") and wt.Value or ""
	local currentStyle = (sn and sn.Value ~= "") and sn.Value or "Default"

	if currentWT == "" then
		local noWeapon = makeFrame(scroll, UDim2.new(1,-4,0,40), UDim2.new(0,2,0,0), C.darkPanel,0)
		noWeapon.LayoutOrder=1; corner(noWeapon,6)
		makeLabel(noWeapon,"No weapon equipped", UDim2.new(1,0,1,0), UDim2.new(0,8,0,0), C.dim,12)
		return
	end

	local styles = InventoryData.GetStyles(currentWT)
	local styleNames = InventoryData.StyleDisplayNames or {}

	makeLabel(scroll:FindFirstChildOfClass("Frame") or scroll,
		"Styles for: " .. currentWT,
		UDim2.new(1,-4,0,16), UDim2.new(0,2,0,0), C.dim,10)

	for i, styleName in ipairs(styles) do
		local isActive = styleName == currentStyle
		local displayName = styleNames[styleName] or styleName

		local row = makeFrame(scroll, UDim2.new(1,-4,0,44), UDim2.new(0,2,0,0), C.darkPanel,0)
		row.LayoutOrder=i; corner(row,6)
		stroke(row, isActive and C.gold or C.border, isActive and 2 or 1)

		makeLabel(row, displayName, UDim2.new(1,-70,0,24), UDim2.new(0,10,0,10),
			isActive and C.gold or C.text, 13)

		if not isActive then
			local selBtn = makeButton(row,"Select", UDim2.new(0,55,0,24), UDim2.new(1,-63,0,10), C.border,C.gold,11)
			corner(selBtn,4)
			local capturedStyle = styleName
			selBtn.MouseButton1Click:Connect(function()
				ChangeStyle:FireServer({styleName=capturedStyle})
				task.wait(0.1)
				setActiveTab("Styles")
			end)
		else
			makeLabel(row,"✔ Active", UDim2.new(0,60,0,24), UDim2.new(1,-68,0,10), C.equipped,11, Enum.TextXAlignment.Right)
		end
	end
end

-- ============================================================
-- VISUAL REFRESH
-- ============================================================
function refreshEquipPanel()
	local wt = player:FindFirstChild("Plr_WeaponType")
	local sn = player:FindFirstChild("Plr_StyleName")
	local styleName = (sn and sn.Value ~= "") and sn.Value or ""
	if equippedTool then
		local def = InventoryData.GetByToolName(equippedTool)
		weaponNameLabel.Text       = def and def.displayName or equippedTool
		weaponNameLabel.TextColor3 = C.gold
		weaponStyleLabel.Text      = styleName ~= "" and styleName or "Default"
		iconLabel.TextColor3       = C.gold; iconBox.BackgroundColor3 = rgb(30,45,30)
		stroke(weaponSlot, C.equipped, 2); unequipBtn.Visible = true
	else
		weaponNameLabel.Text       = "[ Sheathed ]"
		weaponNameLabel.TextColor3 = C.dim
		weaponStyleLabel.Text      = ""
		iconLabel.TextColor3       = C.dim; iconBox.BackgroundColor3 = C.empty
		stroke(weaponSlot, C.border, 1); unequipBtn.Visible = false
	end
end

function refreshSelectVisuals()
	if activeTab ~= "Weapons" then return end
	for toolName, row in pairs(weaponRows) do
		local isEquipped = toolName == equippedTool
		local isSelected = toolName == selectedTool
		if isEquipped then
			row.rowStroke.Color=C.equipped; row.rowStroke.Thickness=2
			row.statusLabel.Text="✔ Equipped"; row.statusLabel.TextColor3=C.equipped
		elseif isSelected then
			row.rowStroke.Color=C.selected; row.rowStroke.Thickness=2
			row.statusLabel.Text="Press Z to equip"; row.statusLabel.TextColor3=C.selected
		else
			local def = InventoryData.GetByToolName(toolName)
			row.rowStroke.Color=C.border; row.rowStroke.Thickness=1
			row.statusLabel.Text=def and def.weaponType or ""
			row.statusLabel.TextColor3=C.dim
		end
	end
end

-- Watch for style changes to refresh the Styles tab if open.
task.spawn(function()
	local sn = player:WaitForChild("Plr_StyleName", 10)
	if sn then sn.Changed:Connect(function() refreshEquipPanel(); if activeTab=="Styles" then setActiveTab("Styles") end end) end
	local wt = player:WaitForChild("Plr_WeaponType", 10)
	if wt then wt.Changed:Connect(function() if activeTab=="Styles" then setActiveTab("Styles") end end) end
	local eq = player:WaitForChild("Plr_EquippedSkills", 10)
	if eq then eq.Changed:Connect(function() if activeTab=="Skills" then setActiveTab("Skills") end end) end
	local av = player:WaitForChild("Plr_AvailableSkills", 10)
	if av then av.Changed:Connect(function() if activeTab=="Skills" then setActiveTab("Skills") end end) end
end)

-- ============================================================
-- EQUIP / UNEQUIP
-- ============================================================
local function doEquipSelected()
	if not selectedTool then return end
	if selectedTool == equippedTool then UnequipTool:FireServer()
	else EquipTool:FireServer({toolName=selectedTool}) end
end

CAS:BindAction("Inventory_Equip", function(_, inputState, _)
	if inputState ~= Enum.UserInputState.Begin then return Enum.ContextActionResult.Pass end
	doEquipSelected(); return Enum.ContextActionResult.Sink
end, false, Enum.KeyCode.Z)

local numKeys = {
	Enum.KeyCode.One,Enum.KeyCode.Two,Enum.KeyCode.Three,Enum.KeyCode.Four,Enum.KeyCode.Five,
}
for i, weapon in ipairs(InventoryData.Weapons) do
	if numKeys[i] then
		local captured = weapon.toolName
		CAS:BindAction("Inventory_Slot_"..i, function(_, state, _)
			if state ~= Enum.UserInputState.Begin then return Enum.ContextActionResult.Pass end
			selectedTool=captured; refreshSelectVisuals(); return Enum.ContextActionResult.Sink
		end, false, numKeys[i])
	end
end

-- ============================================================
-- SERVER → CLIENT SYNC
-- ============================================================
InventorySync.OnClientEvent:Connect(function(data)
	if not data then return end
	equippedTool = data.equippedTool or nil
	if equippedTool then selectedTool=equippedTool end
	refreshEquipPanel(); refreshSelectVisuals()
end)

player.CharacterAdded:Connect(function()
	equippedTool=nil; selectedTool=nil
	task.wait(0.5); refreshEquipPanel(); refreshSelectVisuals()
end)

refreshEquipPanel(); refreshSelectVisuals()