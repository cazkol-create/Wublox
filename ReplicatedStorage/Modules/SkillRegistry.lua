-- @ScriptType: ModuleScript
-- @ScriptType: ModuleScript
-- ============================================================
--  SkillRegistry.lua  |  ModuleScript
--  Location: ReplicatedStorage/Modules/SkillRegistry
--
--  Client-visible metadata for every skill in the game.
--  Both SkillSystem (server) and SkillClient/SkillHUD (client)
--  read from here for display info, keybinds, and filtering.
--
--  ── Fields ──────────────────────────────────────────────────
--  id           : string  — must match ServerStorage/Skills/[id].lua
--  displayName  : string  — shown in UI
--  description  : string  — tooltip text
--  icon         : string  — rbxassetid:// (leave "" for text fallback)
--  universal    : bool    — if true, works with ANY weapon
--  weaponTypes  : table   — list of weapon types if not universal
--  cooldown     : number  — seconds (also in server skill module)
--  defaultKeybind: Enum.KeyCode — default hotkey for this skill
--  animName     : string  — animation name inside RS/Animations/[wt]/[style]/
--                           (optional; skill module may handle animation itself)
--
--  ── How to add a new skill ───────────────────────────────────
--  1. Add an entry to this table.
--  2. Create ServerStorage/Skills/[id].lua with an Execute function.
--  3. Optionally create ReplicatedStorage/Animations/[wt]/[style]/[animName].
--  4. Grant the skill to a player via SkillSystem.GrantSkill(player, id).
-- ============================================================

local SkillRegistry = {}

-- ── Master skill list ────────────────────────────────────────
SkillRegistry.Skills = {

	SwordDashSlash = {
		id             = "SwordDashSlash",
		displayName    = "Dash Slash",
		description    = "Lunge forward and cut through enemies.",
		icon           = "",
		universal      = false,
		weaponTypes    = { "Sword" },
		cooldown       = 8,
		defaultKeybind = Enum.KeyCode.E,
		animName       = "Skill_DashSlash",
	},

	TigerClaw = {
		id             = "TigerClaw",
		displayName    = "Tiger Claw",
		description    = "A devastating claw strike that ignores block.",
		icon           = "",
		universal      = false,
		weaponTypes    = { "Fist" },
		cooldown       = 10,
		defaultKeybind = Enum.KeyCode.E,
		animName       = "Skill_TigerClaw",
	},

	-- Example universal skill (works with any weapon)
	IronBody = {
		id             = "IronBody",
		displayName    = "Iron Body",
		description    = "Harden your qi for 5 seconds, reducing all damage by 50%.",
		icon           = "",
		universal      = true,
		weaponTypes    = nil,   -- nil when universal = true
		cooldown       = 20,
		defaultKeybind = Enum.KeyCode.Z,
		animName       = "Skill_IronBody",
	},
}

-- ── Helpers ──────────────────────────────────────────────────

-- Returns a skill definition by ID, or nil.
function SkillRegistry.Get(skillId)
	return SkillRegistry.Skills[skillId]
end

-- Returns all skills compatible with the given weaponType.
-- If weaponType is nil or "", returns only universal skills.
function SkillRegistry.GetForWeapon(weaponType)
	local result = {}
	for _, skill in pairs(SkillRegistry.Skills) do
		if skill.universal then
			table.insert(result, skill)
		elseif weaponType and weaponType ~= "" and skill.weaponTypes then
			for _, wt in ipairs(skill.weaponTypes) do
				if wt == weaponType then
					table.insert(result, skill)
					break
				end
			end
		end
	end
	-- Sort alphabetically for stable ordering in UI.
	table.sort(result, function(a, b) return a.displayName < b.displayName end)
	return result
end

-- Returns true if skillId is compatible with the given weaponType.
function SkillRegistry.IsCompatible(skillId, weaponType)
	local skill = SkillRegistry.Skills[skillId]
	if not skill then return false end
	if skill.universal then return true end
	if not skill.weaponTypes then return false end
	if not weaponType or weaponType == "" then return false end
	for _, wt in ipairs(skill.weaponTypes) do
		if wt == weaponType then return true end
	end
	return false
end

return SkillRegistry