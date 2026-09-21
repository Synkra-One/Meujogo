--!strict
-- Regras compartilhadas da Glock17 do Digital's OTS.
-- Munição, raycast, cadência e dano continuam autoritativos no servidor.
local GameConfig = require(game:GetService("ReplicatedStorage").Modules.GameConfig)
local Pistol = GameConfig.Weapons.Definitions.Glock17
local Rules = {}

function Rules.IsFoundation(tool: Tool): boolean
	return tool:GetAttribute("LobbyTestWeapon") ~= true
end

function Rules.AttackRange(tool: Tool): number
	return if Rules.IsFoundation(tool) then Pistol.Range else Rules.Range
end

function Rules.AnimationsEnabled(tool: Tool): boolean
	return not Rules.IsFoundation(tool) or Pistol.AnimationsEnabled == true
end

function Rules.ReloadEnabled(tool: Tool): boolean
	return not Rules.IsFoundation(tool) or Pistol.ReloadEnabled == true
end
Rules.Range = 600
Rules.ReloadDuration = 2.2

function Rules.IsFinite(value: unknown): boolean
	return type(value) == "number" and value == value and math.abs(value) < math.huge
end

function Rules.CanShoot(now: number, previous: number?, magazine: number, reloading: boolean, tool: Tool): boolean
	return Rules.IsFinite(magazine) and magazine >= 1 and not reloading
		and (previous == nil or now - previous >= Rules.ShotInterval(tool))
end

function Rules.ReloadAmount(magazine: number, capacity: number, reserve: number): number
	if not Rules.IsFinite(magazine) or not Rules.IsFinite(capacity) or not Rules.IsFinite(reserve) then return 0 end
	return math.max(0, math.floor(math.min(capacity - magazine, reserve)))
end

function Rules.IsWeapon(instance: Instance): boolean
	if not instance:IsA("Tool") or instance.Name ~= "Glock17" then return false end
	local flag = instance:FindFirstChild("Weapon")
	return flag ~= nil and flag:IsA("BoolValue") and flag.Value
end

function Rules.Value(tool: Tool, group: string, name: string): Instance?
	local settings = tool:FindFirstChild("Settings")
	local folder = settings and settings:FindFirstChild(group)
	return folder and folder:FindFirstChild(name)
end

function Rules.Number(tool: Tool, group: string, name: string, fallback: number): number
	local value = Rules.Value(tool, group, name)
	if value and (value:IsA("NumberValue") or value:IsA("IntValue")) and Rules.IsFinite(value.Value) then return value.Value end
	return fallback
end

function Rules.Boolean(tool: Tool, group: string, name: string, fallback: boolean): boolean
	local value = Rules.Value(tool, group, name)
	if value and value:IsA("BoolValue") then return value.Value end
	return fallback
end

function Rules.ShotInterval(tool: Tool): number
	if Rules.IsFoundation(tool) then return Pistol.Cooldown end
	return math.clamp(Rules.Number(tool, "Config", "Delay", 0.06), 0.05, 2)
end

function Rules.Spread(tool: Tool): number
	if Rules.IsFoundation(tool) then return Pistol.Spread end
	return math.clamp(Rules.Number(tool, "Config", "Spread", 3), 0, 15)
end

function Rules.Recoil(tool: Tool): number
	if Rules.IsFoundation(tool) then return Pistol.Recoil end
	return math.clamp(Rules.Number(tool, "Config", "Recoil", 0.4), 0, 5)
end

function Rules.AimFOV(tool: Tool): number
	return math.clamp(Rules.Number(tool, "Config", "AimFOV", 62), 35, 90)
end

function Rules.Muzzle(tool: Tool): BasePart?
	local components = tool:FindFirstChild("Components")
	local muzzle = components and components:FindFirstChild("Muzzle")
	return if muzzle and muzzle:IsA("BasePart") then muzzle else nil
end

return table.freeze(Rules)
