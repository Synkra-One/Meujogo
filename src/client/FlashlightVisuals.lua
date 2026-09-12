--!strict
local Config = require(game:GetService("ReplicatedStorage").Modules.FlashlightConfig)
local Visuals = {}
local entries: { [Tool]: any } = {}

function Visuals.Remove(tool: Tool)
	local entry = entries[tool]
	if not entry then return end
	if entry.grip and entry.grip.Parent then entry.grip.C0 = entry.originalC0 end
	if entry.light.Parent then entry.light.Enabled = false end
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
	local beam = emitter and emitter:FindFirstChild("FlashlightBeam")
	if not handle or not handle:IsA("BasePart") or not origin or not emitter or not endpoint or not light or not beam then return nil end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local entry = { handle = handle, origin = origin, emitter = emitter, endpoint = endpoint,
		light = light, beam = beam, rayAt = 0, distance = 0, blocked = false, params = params }
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
	-- Aim the held object through RightGrip only; body animation joints stay
	-- owned by the movement pack. Every viewer applies the same replicated aim.
	if not entry.grip then
		local grip = character:FindFirstChild("RightGrip", true)
		if grip and grip:IsA("JointInstance") and grip.Part1 == entry.handle then
			entry.grip, entry.originalC0 = grip, grip.C0
		end
	end
	entry.direction = if entry.direction then entry.direction:Lerp(direction, 1 - math.exp(-20 * dt)) else direction
	if entry.direction.Magnitude < 0.01 then entry.direction = direction end
	local aim = entry.direction.Unit
	local grip = entry.grip
	if grip and grip.Part0 then
		local rotation = CFrame.lookAt(Vector3.zero, aim).Rotation * entry.origin.CFrame.Rotation:Inverse()
		grip.C0 = CFrame.new(entry.originalC0.Position) * grip.Part0.CFrame.Rotation:Inverse() * rotation * grip.C1.Rotation
	end
	local position = entry.origin.WorldPosition
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
	entry.light.Enabled, entry.beam.Enabled = not entry.blocked, not entry.blocked and entry.distance > 0.2
end

return Visuals
