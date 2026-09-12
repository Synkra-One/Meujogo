--!strict
local Config = require(script.Parent.FlashlightConfig)
local Rig = {}

local function sourceFrame(tool: Tool, handle: BasePart): CFrame
	for _, name in { "FlashlightMuzzle", "Muzzle", "LightAttachment" } do
		local attachment = tool:FindFirstChild(name, true)
		if attachment and attachment:IsA("Attachment") then
			return handle.CFrame:ToObjectSpace(attachment.WorldCFrame)
		end
	end
	-- Preserve the uploaded model's light position/orientation when available.
	local light = tool:FindFirstChildWhichIsA("SpotLight", true)
	local parent = light and light.Parent
	if light and parent then
		local normal = Vector3.FromNormalId(light.Face)
		if parent:IsA("Attachment") then
			local cf = parent.WorldCFrame
			return handle.CFrame:ToObjectSpace(CFrame.lookAt(cf.Position, cf.Position + cf:VectorToWorldSpace(normal)))
		elseif parent:IsA("BasePart") then
			local position = parent.CFrame:PointToWorldSpace(normal * parent.Size / 2)
			return handle.CFrame:ToObjectSpace(CFrame.lookAt(position, position + parent.CFrame:VectorToWorldSpace(normal)))
		end
	end
	local offset = tool:GetAttribute("FlashlightMuzzleOffset")
	if typeof(offset) == "Vector3" then return CFrame.new(offset) end
	-- A bare mesh has no emitter metadata. Use its long axis; this offset can
	-- be calibrated on the Tool without changing gameplay or aiming scripts.
	local size = handle.Size
	local axis = if size.Y > size.X and size.Y > size.Z then Vector3.yAxis
		elseif size.X > size.Z then Vector3.xAxis else -Vector3.zAxis
	local position = axis * size / 2
	return CFrame.lookAt(position, position + axis)
end

function Rig.Prepare(tool: Tool): Attachment?
	local handle = tool:FindFirstChild("Handle")
	if not handle or not handle:IsA("BasePart") then return nil end
	local existing = handle:FindFirstChild("FlashlightOrigin")
	if existing and existing:IsA("Attachment") then return existing end
	local cf = sourceFrame(tool, handle)
	for _, item in tool:GetDescendants() do
		if item:IsA("Light") or item:IsA("Beam") or item:IsA("ParticleEmitter") then item:Destroy() end
	end
	local origin = Instance.new("Attachment")
	origin.Name, origin.CFrame, origin.Parent = "FlashlightOrigin", cf, handle
	local emitter = Instance.new("Attachment")
	emitter.Name, emitter.CFrame, emitter.Parent = "FlashlightEmitter", cf, handle
	local endpoint = Instance.new("Attachment")
	endpoint.Name, endpoint.Parent = "FlashlightEnd", handle
	local light = Instance.new("SpotLight")
	light.Name = "LanternaLuz"
	light.Face, light.Range, light.Angle = Enum.NormalId.Front, Config.FlashlightRange, Config.BeamAngle
	light.Brightness, light.Color = Config.Brightness, Color3.fromRGB(240, 247, 226)
	light.Shadows, light.Enabled, light.Parent = true, false, emitter
	local beam = Instance.new("Beam")
	beam.Name, beam.Attachment0, beam.Attachment1 = "FlashlightBeam", emitter, endpoint
	beam.FaceCamera, beam.LightEmission, beam.LightInfluence = true, 1, 0
	beam.Width0, beam.Width1 = 0.16, 3
	beam.Color = ColorSequence.new(light.Color)
	beam.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.94),
		NumberSequenceKeypoint.new(0.6, 0.985), NumberSequenceKeypoint.new(1, 1) })
	beam.Enabled, beam.Parent = false, emitter
	return origin
end

function Rig.Build(model: Model): Tool?
	local originalTool = model:FindFirstChildWhichIsA("Tool", true)
	local originalHandle = originalTool and originalTool:FindFirstChild("Handle")
	local parts: { BasePart } = {}
	for _, item in model:GetDescendants() do
		if item:IsA("BasePart") then table.insert(parts, item) end
	end
	if #parts == 0 then model:Destroy(); return nil end
	table.sort(parts, function(a, b) return a.Size.Magnitude > b.Size.Magnitude end)
	local handle = if originalHandle and originalHandle:IsA("BasePart") then originalHandle else parts[1]
	local tool = Instance.new("Tool")
	tool.Name, tool.RequiresHandle, tool.CanBeDropped = "Lanterna", true, false
	if originalTool then tool.Grip = originalTool.Grip end
	for _, item in model:GetDescendants() do
		if item:IsA("JointInstance") or item:IsA("WeldConstraint") or item:IsA("Constraint") then item:Destroy() end
	end
	handle.Name, handle.Parent = "Handle", tool
	for _, part in parts do
		part.Anchored, part.CanCollide, part.Massless = false, false, true
		if part ~= handle then
			part.Parent = handle
			local weld = Instance.new("WeldConstraint")
			weld.Part0, weld.Part1, weld.Parent = handle, part, part
		end
	end
	model:Destroy()
	tool:SetAttribute("Lanterna", true)
	tool:SetAttribute("Battery", Config.BatteryMax)
	tool:SetAttribute("FlashlightOn", false)
	Rig.Prepare(tool)
	return tool
end

return Rig
