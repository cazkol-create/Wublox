-- @ScriptType: ModuleScript
-- ============================================================
--  InventoryData.lua  |  ModuleScript
--  Location: ReplicatedStorage/Modules/InventoryData
--
--  Single source of truth for:
--    • What weapons exist and their display names
--    • Which combat styles each weapon has
--    • Which style is the default when a weapon is first equipped
--    • The mapping from ServerStorage/Tools/ names → Plr_WeaponType value
--
--  Readable by both client (InventoryClient, StyleSwitchClient)
--  and server (InventoryServer).
-- ============================================================

local InventoryData = {}

-- ── Weapon definitions ────────────────────────────────────────
-- toolName   : must match the exact name of the Tool in ServerStorage/Tools/
-- weaponType : written to Plr_WeaponType when the tool is equipped
-- styles     : ordered list shown in the Style Switch panel
-- defaultStyle : Plr_StyleName is reset to this on every equip
-- ─────────────────────────────────────────────────────────────
InventoryData.Weapons = {
	{
		toolName     = "Fist",
		weaponType   = "Fist",
		displayName  = "Iron Fist",
		styles       = { "Default" },
		defaultStyle = "Default",
	},
	{
		toolName     = "Sword",
		weaponType   = "Sword",
		displayName  = "Sword",
		styles       = { "Default", "Flowing", "Storm" },
		defaultStyle = "Default",
	},
	{
		toolName     = "Staff",
		weaponType   = "Staff",
		displayName  = "Bo Staff",
		styles       = { "Mad Monk"},
		defaultStyle = "Mad Monk",
	},
	{
		toolName     = "Qiang",
		weaponType   = "Qiang",
		displayName  = "Qiang",
		styles       = { "Qiang Shu"},
		defaultStyle = "Qiang Shu",
	},

}

-- ── Lookup helpers ────────────────────────────────────────────

-- Returns the weapon definition table for a given tool name.
function InventoryData.GetByToolName(toolName)
	for _, w in ipairs(InventoryData.Weapons) do
		if w.toolName == toolName then return w end
	end
	return nil
end

-- Returns the weapon definition table for a given Plr_WeaponType string.
function InventoryData.GetByWeaponType(weaponType)
	for _, w in ipairs(InventoryData.Weapons) do
		if w.weaponType == weaponType then return w end
	end
	return nil
end

-- Returns an ordered list of style names for the given Plr_WeaponType.
function InventoryData.GetStyles(weaponType)
	local w = InventoryData.GetByWeaponType(weaponType)
	return w and w.styles or { "Default" }
end

-- Display names for individual styles — used by StyleSwitchClient.
-- Add entries here as new styles are created.
InventoryData.StyleDisplayNames = {
	Default = "Default",
	Flowing = "Flowing River",
	Storm   = "Raging Storm",
}

return InventoryData