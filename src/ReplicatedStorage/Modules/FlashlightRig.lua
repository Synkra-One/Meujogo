--!strict
local Config = require(script.Parent.FlashlightConfig)
local Rig = {}

local function attachment(handle: BasePart, name: string, cf: CFrame): Attachment
	local current = handle:FindFirstChild(name)
	if current and current:IsA("Attachment") then
		current.CFrame = cf
		return current
	end
	if current then current:Destroy() end
	local created = Instance.new("Attachment")
	created.Name, created.CFrame, created.Parent = name, cf, handle
	return created
end

local function light(parent: Attachment, className: string, name: string): Light
	local current = parent:FindFirstChild(name)
	if current and current.ClassName == className then return current :: any end
	if current then current:Destroy() end
	local created = Instance.new(className) :: Light
	created.Name, created.Parent = name, parent
	return created
end

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
	local cf = if existing and existing:IsA("Attachment") then existing.CFrame else sourceFrame(tool, handle)
	if not existing then
		for _, item in tool:GetDescendants() do
			if item:IsA("Light") or item:IsA("Beam") or item:IsA("ParticleEmitter") then item:Destroy() end
		end
	end
	local origin = attachment(handle, "FlashlightOrigin", cf)
	local emitter = attachment(handle, "FlashlightEmitter", cf)
	local endpoint = attachment(handle, "FlashlightEnd", CFrame.identity)
	local color = Color3.fromRGB(Config.LightColor[1], Config.LightColor[2], Config.LightColor[3])
	local hotspot = light(emitter, "SpotLight", "LanternaLuz") :: SpotLight
	hotspot.Face, hotspot.Range, hotspot.Angle = Enum.NormalId.Front, Config.LightRange, Config.LightAngle
	hotspot.Brightness, hotspot.Color = Config.Brightness, color
	hotspot.Shadows, hotspot.Enabled = true, false
	local spill = light(emitter, "SpotLight", "LanternaSpill") :: SpotLight
	spill.Face, spill.Range, spill.Angle = Enum.NormalId.Front, Config.LightRange * 0.82, Config.SpillAngle
	spill.Brightness, spill.Color = Config.SpillBrightness, color
	spill.Shadows, spill.Enabled = false, false
	local fill = light(emitter, "PointLight", "LanternaFill") :: PointLight
	fill.Range, fill.Brightness, fill.Color = Config.FillRange, Config.FillBrightness, color
	fill.Shadows, fill.Enabled = false, false
	local oldBeam = emitter:FindFirstChild("FlashlightBeam")
	if oldBeam and not oldBeam:IsA("Beam") then
		oldBeam:Destroy()
		oldBeam = nil
	end
	local beam = if oldBeam then oldBeam :: Beam else Instance.new("Beam")
	beam.Name, beam.Attachment0, beam.Attachment1 = "FlashlightBeam", emitter, endpoint
	beam.FaceCamera, beam.LightEmission, beam.LightInfluence = true, 1, 0
	beam.CurveSize0, beam.CurveSize1 = 0, 0
	beam.Width0, beam.Width1 = 0.16, 3
	beam.Color = ColorSequence.new(hotspot.Color)
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
	local namedHandle = model:FindFirstChild("Handle", true)
	local handle = if originalHandle and originalHandle:IsA("BasePart") then originalHandle
		elseif namedHandle and namedHandle:IsA("BasePart") then namedHandle
		else parts[1]
	local tool = Instance.new("Tool")
	tool.Name, tool.RequiresHandle, tool.CanBeDropped = "Lanterna", true, false
	if originalTool then tool.Grip = originalTool.Grip end
	for _, item in model:GetDescendants() do
		if item:IsA("JointInstance") or item:IsA("WeldConstraint") or item:IsA("Constraint") then item:Destroy() end
	end
	handle.Name, handle.Parent = "Handle", tool
	for _, part in parts do
		part.Anchored, part.CanCollide, part.CanTouch, part.CanQuery, part.Massless = false, false, false, false, true
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
