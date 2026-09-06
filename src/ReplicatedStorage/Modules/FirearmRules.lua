--!strict
-- Regras compartilhadas. Munição, raycast e cadência são do servidor.
local Rules = {}
Rules.Range = 600
Rules.ShotInterval = 0.18
Rules.ReloadDuration = 2.2
Rules.AimFOV = 62
Rules.HipSpread = 1.05
Rules.AimSpread = 0.25
Rules.RecoilDegrees = 1.15

function Rules.IsFinite(value: unknown): boolean
	return type(value) == "number" and value == value and math.abs(value) < math.huge
end

function Rules.CanShoot(now: number, previous: number?, magazine: number, reloading: boolean): boolean
	return Rules.IsFinite(magazine) and magazine >= 1 and not reloading
		and (previous == nil or now - previous >= Rules.ShotInterval)
end

function Rules.ReloadAmount(magazine: number, capacity: number, reserve: number): number
	if not Rules.IsFinite(magazine) or not Rules.IsFinite(capacity) or not Rules.IsFinite(reserve) then return 0 end
	return math.max(0, math.floor(math.min(capacity - magazine, reserve)))
end

function Rules.IsPistol(instance: Instance): boolean
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

function Rules.Muzzle(tool: Tool): BasePart?
	local components = tool:FindFirstChild("Components")
	local muzzle = components and components:FindFirstChild("Muzzle")
	return if muzzle and muzzle:IsA("BasePart") then muzzle else nil
end

return table.freeze(Rules)
