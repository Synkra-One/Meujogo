--!strict
local Config = require(game:GetService("ReplicatedStorage").Modules.FlashlightConfig)
local Visuals = {}
local entries: { [Tool]: any } = {}

function Visuals.Remove(tool: Tool)
	local entry = entries[tool]
	if not entry then return end
	if entry.light.Parent then entry.light.Enabled = false end
	if entry.spill and entry.spill.Parent then entry.spill.Enabled = false end
	if entry.fill and entry.fill.Parent then entry.fill.Enabled = false end
	if entry.beam.Parent then entry.beam.Enabled = false end
	entries[tool] = nil
end

local function get(tool: Tool): any
	if entries[tool] then return entries[tool] end
	local handle = tool:FindFirstChild("Handle")
	local origin = handle and handle:FindFirstChild("FlashlightOrigin")
	local emitter = handle and handle:FindFirstChild("FlashlightEmitter")
	local endpoint = handle and handle:FindFirstChild("FlashlightEnd")
	local light = emitter and emitter:FindFirstChild("LanternaLuz")
	local spill = emitter and emitter:FindFirstChild("LanternaSpill")
	local fill = emitter and emitter:FindFirstChild("LanternaFill")
	local beam = emitter and emitter:FindFirstChild("FlashlightBeam")
	if not handle or not handle:IsA("BasePart") or not origin or not emitter or not endpoint or not light or not beam then return nil end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local entry = { handle = handle, origin = origin, emitter = emitter, endpoint = endpoint,
		light = light, spill = spill, fill = fill, beam = beam, rayAt = 0, distance = 0,
		blocked = false, params = params,
		flickerSeed = (#tool.Name * 7 + math.floor(handle.Size.Magnitude * 10)) }
	entries[tool] = entry
	return entry
end

function Visuals.Update(tool: Tool, direction: Vector3, enabled: boolean, dt: number)
	if not enabled then Visuals.Remove(tool); return end
	local entry = get(tool)
	local character = tool.Parent
	if not entry or not character or not character:IsA("Model") then return end
	local camera = workspace.CurrentCamera
	if not camera or (entry.handle.Position - camera.CFrame.Position).Magnitude > Config.VisualDistance then
		Visuals.Remove(tool)
		return
	end
	-- Keep the real SpotLights and the visible Beam on the exact same axis.
	-- The hand animation already supplies motion; adding independent sway here
	-- makes the beam look loose or crooked relative to the flashlight.
	local position = entry.origin.WorldPosition
	local aim = if direction.Magnitude > 0.01 then direction.Unit else entry.origin.WorldCFrame.LookVector
	entry.emitter.CFrame = entry.handle.CFrame:ToObjectSpace(CFrame.lookAt(position, position + aim))
	local now = os.clock()
	if now >= entry.rayAt then
		entry.rayAt = now + Config.VisualRayInterval
		entry.params.FilterDescendantsInstances = { character }
		local head = character:FindFirstChild("Head")
		entry.blocked = head and head:IsA("BasePart")
			and workspace:Raycast(head.Position, position - head.Position, entry.params) ~= nil
		local result = workspace:Raycast(position, aim * Config.FlashlightRange, entry.params)
		entry.distance = if result then (result.Position - position).Magnitude else Config.FlashlightRange
	end
	entry.endpoint.CFrame = entry.handle.CFrame:ToObjectSpace(CFrame.new(position + aim * entry.distance))
	entry.beam.Width1 = math.min(4, entry.distance * 0.16)
	local battery = tool:GetAttribute("Battery")
	local low = if type(battery) == "number"
		then 1 - math.clamp(battery / Config.LowBatteryThreshold, 0, 1) else 0
	local flicker = 1 - low * Config.LowBatteryFlicker
		* (0.5 + 0.5 * math.abs(math.sin(now * 31 + entry.flickerSeed)))
	entry.light.Brightness = Config.Brightness * flicker
	if entry.spill then entry.spill.Brightness = Config.SpillBrightness * flicker end
	if entry.fill then entry.fill.Brightness = Config.FillBrightness * flicker end
	local visible = not entry.blocked
	entry.light.Enabled, entry.beam.Enabled = visible, visible and entry.distance > 0.2
	if entry.spill then entry.spill.Enabled = visible end
	if entry.fill then entry.fill.Enabled = visible end
end

return Visuals
