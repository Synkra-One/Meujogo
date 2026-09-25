--!strict
-- Fenda do Abismo: geometria 3D, plasma violeta e detritos em órbita.
-- Local ao cliente, sem asset externo. API sincronizada com os beats do servidor.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")
local RiftVFX = {}

RiftVFX.Style = {
	Void = Color3.fromRGB(7, 3, 13),
	Rock = Color3.fromRGB(29, 23, 38),
	Violet = Color3.fromRGB(125, 45, 244),
	Plasma = Color3.fromRGB(190, 100, 255),
	Hot = Color3.fromRGB(232, 202, 255),
	Haze = Color3.fromRGB(67, 30, 105),
	RimSegments = 24,
	ShardCount = 10,
	UpdateRate = 30,
	ResidualTail = 2.4,
	HardMaxLifetime = 18,
}
local S = RiftVFX.Style
local TAU = math.pi * 2
local SMOKE = "rbxasset://textures/particles/smoke_main.dds"
local SPARK = "rbxasset://textures/particles/fire_sparks_main.dds"

export type RiftOpts = {
	cframe: CFrame, width: number, upright: boolean?, groundOffset: number?,
	extraRotDeg: { number }?, lightBrightness: number?, lightRangeFactor: number?,
}
export type Rift = {
	Core: BasePart,
	Open: (self: Rift, duration: number) -> (),
	Enter: (self: Rift) -> (),
	Emerge: (self: Rift) -> (),
	Close: (self: Rift, duration: number) -> (),
	Cancel: (self: Rift) -> (),
	Destroy: (self: Rift) -> (),
}

local function part(parent: Instance, name: string): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.CanCollide, p.CanTouch, p.CanQuery, p.CastShadow = false, false, false, false
	p.Size = Vector3.new(0.1, 0.1, 0.1)
	p.Transparency = 1
	p.Parent = parent
	return p
end

local function attachment(parent: Instance, name: string): Attachment
	local a = Instance.new("Attachment")
	a.Name, a.Parent = name, parent
	return a
end

local function beam(parent: Instance, a: Attachment, b: Attachment, name: string, color: Color3): Beam
	local v = Instance.new("Beam")
	v.Name = name
	v.Attachment0, v.Attachment1 = a, b
	v.FaceCamera = true
	v.Segments = 5
	v.LightEmission, v.LightInfluence = 1, 0
	v.Color = ColorSequence.new(color)
	v.Transparency = NumberSequence.new(1)
	v.Parent = parent
	return v
end

-- Eixo Y local = normal de emissão. Ignora personagens, VFX e vegetação,
-- como o raycast do servidor: a copa de uma árvore não é o chão do portal.
local function grounded(opts: RiftOpts): CFrame
	local ignore: { Instance } = {}
	for _, name in { "RiftVFX", "Eliminados" } do
		local node = Workspace:FindFirstChild(name)
		if node then table.insert(ignore, node) end
	end
	for _, player in Players:GetPlayers() do
		if player.Character then table.insert(ignore, player.Character) end
	end
	local island = Workspace:FindFirstChild("Ilha")
	if island then
		for _, name in { "Floresta", "Vegetacao", "Rochas" } do
			local node = island:FindFirstChild(name)
			if node then table.insert(ignore, node) end
		end
	end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = ignore
	params.IgnoreWater = true
	local hit = Workspace:Raycast(opts.cframe.Position + Vector3.yAxis * 6, -Vector3.yAxis * 40, params)
	local normal = if hit then hit.Normal else Vector3.yAxis
	local position = (if hit then hit.Position else opts.cframe.Position) + normal * (opts.groundOffset or 0.08)
	local right = opts.cframe.RightVector
	right -= normal * right:Dot(normal)
	if right.Magnitude < 0.01 then right = normal:Cross(Vector3.zAxis) end
	right = right.Unit
	local cf = CFrame.fromMatrix(position, right, normal, right:Cross(normal))
	if opts.upright then cf *= CFrame.Angles(math.pi / 2, 0, 0) end
	local rot = opts.extraRotDeg or { 0, 0, 0 }
	return cf * CFrame.Angles(math.rad(rot[1] or 0), math.rad(rot[2] or 0), math.rad(rot[3] or 0))
end

function RiftVFX.new(opts: RiftOpts): Rift
	local width = math.clamp(opts.width, 3, 32)
	local cf = grounded(opts)
	local rng = Random.new()
	local seed = rng:NextNumber(0, 100)
	local folder = Workspace:FindFirstChild("RiftVFX")
	if not folder then
		folder = Instance.new("Folder")
		folder.Name, folder.Parent = "RiftVFX", Workspace
	end
	local model = Instance.new("Model")
	model.Name = "FendaDoAbismo"
	local core = part(model, "Core")
	core.CFrame = cf
	model.PrimaryPart = core
	local progress = Instance.new("NumberValue")
	progress.Name, progress.Parent = "Aperture", model

	-- Boca arredondada opaca mascara o chão; a borda e o volume se movem
	-- acima dela. Sem decal, SurfaceGui ou cilindro neon preenchido.
	local mouth = part(model, "VoidMouth")
	mouth.Color, mouth.Material = S.Void, Enum.Material.SmoothPlastic
	local mouthMesh = Instance.new("SpecialMesh")
	mouthMesh.MeshType, mouthMesh.Parent = Enum.MeshType.Sphere, mouth
	local rimNodes: { Attachment } = {}
	local rimBeams: { Beam } = {}
	local glowBeams: { Beam } = {}
	local rimEmitters: { ParticleEmitter } = {}
	local emitters: { ParticleEmitter } = {}
	local rates: { [ParticleEmitter]: number } = {}
	local function emitter(parent: Instance, name: string, texture: string, rate: number): ParticleEmitter
		local e = Instance.new("ParticleEmitter")
		e.Name, e.Texture = name, texture
		e.Enabled, e.Rate = false, 0
		e.EmissionDirection = Enum.NormalId.Top
		e.LightInfluence, e.LightEmission, e.Brightness = 0, 0.8, 1.5
		e.Rotation, e.RotSpeed = NumberRange.new(0, 360), NumberRange.new(-55, 55)
		e.Color = ColorSequence.new(S.Plasma, S.Violet)
		e.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.12, 0.2),
			NumberSequenceKeypoint.new(0.65, 0.55), NumberSequenceKeypoint.new(1, 1),
		})
		e.Parent = parent
		table.insert(emitters, e)
		rates[e] = rate
		return e
	end
	for i = 1, S.RimSegments do
		rimNodes[i] = attachment(core, "RimNode" .. i)
	end
	for i, a in rimNodes do
		local b = rimNodes[i % #rimNodes + 1]
		rimBeams[i] = beam(core, a, b, "PlasmaEdge", if i % 4 == 0 then S.Hot else S.Plasma)
		local glow = beam(core, a, b, "SoftCorona", S.Violet)
		glow.Texture, glow.TextureSpeed = SMOKE, 0.6
		glow.TextureMode = Enum.TextureMode.Wrap
		glow.TextureLength = width * 0.24
		glowBeams[i] = glow
		if i % 3 == 0 then
			local e = emitter(a, "VioletEmbers", SPARK, 5)
			e.Lifetime = NumberRange.new(0.55, 1.3)
			e.Speed = NumberRange.new(width * 0.18, width * 0.5)
			e.SpreadAngle = Vector2.new(42, 42)
			e.Acceleration, e.Drag = cf.UpVector * width * 0.12, 1.8
			e.Size = NumberSequence.new({NumberSequenceKeypoint.new(0, width * 0.022), NumberSequenceKeypoint.new(1, 0)})
			table.insert(rimEmitters, e)
		end
	end

	-- Três espirais em alturas diferentes: parallax real visto de lado.
	local strands: { { nodes: { Attachment }, beams: { Beam } } } = {}
	for _ = 1, 3 do
		local strand = { nodes = {} :: { Attachment }, beams = {} :: { Beam } }
		for j = 1, 7 do
			strand.nodes[j] = attachment(core, "VortexNode")
			if j > 1 then
				local v = beam(core, strand.nodes[j - 1], strand.nodes[j], "VortexFilament", S.Violet)
				v.Texture, v.TextureSpeed, v.TextureLength = SMOKE, -1.2, width * 0.18
				table.insert(strand.beams, v)
			end
		end
		table.insert(strands, strand)
	end

	local field = part(model, "MistVolume")
	field.CFrame = cf * CFrame.new(0, width * 0.06, 0)
	field.Size = Vector3.new(width * 0.78, width * 0.12, width * 0.78)
	local haze = emitter(field, "AmethystMist", SMOKE, 14)
	haze.Color = ColorSequence.new(S.Haze, S.Violet)
	haze.LightEmission, haze.Brightness = 0.25, 1
	haze.Lifetime, haze.Speed = NumberRange.new(1.1, 2.2), NumberRange.new(0.6, 1.6)
	haze.SpreadAngle, haze.Drag = Vector2.new(35, 35), 2
	haze.Acceleration = cf.UpVector * 0.65
	haze.Size = NumberSequence.new({NumberSequenceKeypoint.new(0, width * 0.12), NumberSequenceKeypoint.new(1, width * 0.34)})
	haze.Transparency = NumberSequence.new({NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.18, 0.78), NumberSequenceKeypoint.new(1, 1)})
	local burst = emitter(core, "Eruption", SPARK, 0)
	burst.Color = ColorSequence.new(S.Hot, S.Violet)
	burst.Lifetime = NumberRange.new(0.45, 1.1)
	burst.Speed = NumberRange.new(width * 0.6, width * 1.2)
	burst.SpreadAngle = Vector2.new(65, 65)
	burst.Acceleration, burst.Drag = -cf.UpVector * width * 0.7, 2.5
	burst.Size = NumberSequence.new({NumberSequenceKeypoint.new(0, width * 0.035), NumberSequenceKeypoint.new(1, 0)})
	burst.Orientation = Enum.ParticleOrientation.VelocityParallel
	local suction = emitter(field, "Infall", SPARK, 0)
	suction.Lifetime = NumberRange.new(0.25, 0.5)
	suction.EmissionDirection = Enum.NormalId.Bottom
	suction.Speed = NumberRange.new(width * 0.3, width * 0.6)
	suction.Acceleration = -cf.UpVector * width * 2
	suction.SpreadAngle = Vector2.new(15, 15)
	suction.Size = NumberSequence.new({NumberSequenceKeypoint.new(0, width * 0.024), NumberSequenceKeypoint.new(1, 0)})

	local shards: { { part: Part, mesh: SpecialMesh, size: Vector3, angle: number, radius: number, height: number, trail: Trail } } = {}
	for i = 1, S.ShardCount do
		local rock = part(model, "OrbitingObsidian")
		rock.Material, rock.Color = Enum.Material.Slate, S.Rock
		local mesh = Instance.new("SpecialMesh")
		mesh.MeshType, mesh.Parent = Enum.MeshType.Wedge, rock
		local a, b = attachment(rock, "TrailA"), attachment(rock, "TrailB")
		a.Position, b.Position = Vector3.new(0, 0.07, 0), Vector3.new(0, -0.07, 0)
		local trail = Instance.new("Trail")
		trail.Name = "VioletWake"
		trail.Attachment0, trail.Attachment1 = a, b
		trail.Lifetime, trail.MinLength, trail.LightEmission = 0.22, 0.03, 1
		trail.Color = ColorSequence.new(S.Plasma, S.Violet)
		trail.Transparency = NumberSequence.new(0.4, 1)
		trail.WidthScale = NumberSequence.new(1, 0)
		trail.Enabled, trail.Parent = false, rock
		table.insert(shards, {
			part = rock, mesh = mesh, trail = trail,
			size = Vector3.new(rng:NextNumber(0.018, 0.045), rng:NextNumber(0.022, 0.05), rng:NextNumber(0.035, 0.07)) * width,
			angle = i / S.ShardCount * TAU, radius = rng:NextNumber(0.47, 0.63), height = rng:NextNumber(0.06, 0.25),
		})
	end
	local lightOrigin = attachment(core, "LightOrigin")
	lightOrigin.Position = Vector3.yAxis * width * 0.18
	local light = Instance.new("PointLight")
	light.Name, light.Color = "VioletBounce", S.Plasma
	light.Range = math.clamp(width * (opts.lightRangeFactor or 2.2), 0, 60)
	light.Brightness, light.Shadows, light.Parent = 0, false, lightOrigin
	local maxBrightness = opts.lightBrightness or 2.2

	local born = os.clock()
	local stage = "ready"
	local beatAt, closeAt = -100, math.huge
	local destroyed = false
	local tween: Tween? = nil
	local heartbeat: RBXScriptConnection? = nil
	local ancestry: RBXScriptConnection? = nil
	local accumulated, lastOpacity, rotation = 0, -1, 0
	local lastFrame = born
	local rift = {} :: Rift
	rift.Core = core

	local function tweenTo(value: number, duration: number, direction: Enum.EasingDirection)
		if tween then tween:Cancel() end
		tween = TweenService:Create(progress, TweenInfo.new(math.max(duration, 0.05), Enum.EasingStyle.Quart, direction), { Value = value })
		tween:Play()
	end
	local function disableEmission()
		for _, e in emitters do e.Enabled = false; e.Rate = 0 end
		for _, shard in shards do shard.trail.Enabled = false end
	end
	function rift:Destroy()
		if destroyed then return end
		destroyed = true
		if heartbeat then heartbeat:Disconnect(); heartbeat = nil end
		if ancestry then ancestry:Disconnect(); ancestry = nil end
		if tween then tween:Cancel(); tween = nil end
		model:Destroy()
	end
	function rift:Open(duration: number)
		if destroyed or stage ~= "ready" then return end
		stage = "open"
		for _, e in emitters do e.Enabled = true end
		tweenTo(1, duration, Enum.EasingDirection.Out)
	end
	function rift:Enter()
		if destroyed or stage == "closing" or stage == "ready" then return end
		stage, beatAt = "enter", os.clock()
		suction:Emit(32)
		haze:Emit(8)
	end
	function rift:Emerge()
		if destroyed or stage == "closing" or stage == "ready" then return end
		stage, beatAt = "emerge", os.clock()
		burst:Emit(56)
		for _, e in rimEmitters do e:Emit(6) end
		haze:Emit(12)
	end
	function rift:Close(duration: number)
		if destroyed or stage == "closing" then return end
		stage = "closing"
		closeAt = os.clock() + math.max(duration, 0.05)
		disableEmission()
		tweenTo(0, duration, Enum.EasingDirection.In)
	end
	function rift:Cancel()
		if destroyed then return end
		-- Cancel pode interromper inclusive um Close em curso.
		stage, closeAt = "closing", os.clock() + 0.2
		disableEmission()
		tweenTo(0, 0.2, Enum.EasingDirection.Out)
	end

	local function animate(now: number)
		local p, time = progress.Value, now - born
		local kick = math.exp(-math.max(now - beatAt, 0) * 4)
		local entering = stage == "enter"
		rotation += (now - lastFrame) * (if entering then -1.8 else 0.72)
		lastFrame = now
		local size = math.max(0.025, p) * width
		local pulse = 1 + math.sin(time * 3.4) * 0.018
		mouth.CFrame = cf * CFrame.new(0, size * 0.013, 0)
		mouthMesh.Scale = Vector3.new(size * 0.94, size * 0.065, size * 0.9) / 0.1
		mouth.Transparency = 1 - math.min(p * 2, 1)
		field.Size = Vector3.new(math.max(size * 0.78, 0.05), math.max(size * 0.12, 0.05), math.max(size * 0.78, 0.05))
		field.CFrame = cf * CFrame.new(0, size * (if entering then 0.18 else 0.06), 0)
		for i, a in rimNodes do
			local angle = (i - 1) / #rimNodes * TAU
			local irregular = math.noise(math.cos(angle) * 1.8 + seed, math.sin(angle) * 1.8, time * 0.55)
			local radius = size * (0.48 + irregular * 0.035) * pulse
			local theta = angle + rotation
			local height = size * (0.045 + 0.012 * math.sin(angle * 3 + time * 2))
			a.CFrame = CFrame.fromMatrix(Vector3.new(math.cos(theta) * radius, height, math.sin(theta) * radius), Vector3.new(-math.sin(theta), 0, math.cos(theta)), Vector3.yAxis)
			local curve = radius * (4 / 3) * math.tan(math.pi / (#rimNodes * 2))
			local edge, glow = rimBeams[i], glowBeams[i]
			edge.CurveSize0, edge.CurveSize1 = curve, curve
			glow.CurveSize0, glow.CurveSize1 = curve, curve
			edge.Width0 = size * (0.008 + 0.005 * (0.5 + 0.5 * math.sin(angle * 5 - time * 6)))
			edge.Width1 = edge.Width0 * 0.7
			glow.Width0, glow.Width1 = size * 0.12, size * 0.09
		end
		for s, strand in strands do
			for j, a in strand.nodes do
				local u = (j - 1) / (#strand.nodes - 1)
				local angle = s / #strands * TAU + u * TAU * 0.76 - rotation * 1.4
				local radius = size * (0.08 + u * 0.36)
				local height = size * (0.045 + (1 - u) * (0.16 + kick * 0.12))
				local position = Vector3.new(math.cos(angle) * radius, height, math.sin(angle) * radius)
				local turn = TAU * 0.76
				local tangent = Vector3.new(
					size * 0.36 * math.cos(angle) - radius * turn * math.sin(angle),
					-size * (0.16 + kick * 0.12),
					size * 0.36 * math.sin(angle) + radius * turn * math.cos(angle)
				).Unit
				local back = tangent:Cross(Vector3.yAxis).Unit
				a.CFrame = CFrame.fromMatrix(position, tangent, back:Cross(tangent), back)
				if j > 1 then
					local v = strand.beams[j - 1]
					local curve = (position - strand.nodes[j - 1].Position).Magnitude / 3
					v.CurveSize0, v.CurveSize1 = curve, curve
					v.Width0, v.Width1 = size * 0.05, size * 0.075
				end
			end
		end
		for i, shard in shards do
			local angle = shard.angle + rotation * (0.6 + i * 0.035)
			local radius = size * shard.radius * (if entering then 1 - kick * 0.2 else 1 + kick * 0.18)
			local height = size * (shard.height + math.sin(time * 2.4 + i) * 0.025 + kick * 0.12)
			shard.part.CFrame = cf * CFrame.new(math.cos(angle) * radius, height, math.sin(angle) * radius) * CFrame.Angles(time * 0.8 + i, angle, time * 0.4)
			shard.mesh.Scale = shard.size * math.max(p, 0.01) / 0.1
			shard.part.Transparency = 1 - p * 0.95
			shard.trail.Enabled = p > 0.35 and stage ~= "closing"
		end
		light.Brightness = maxBrightness * p * (1 + kick * 1.4 + math.sin(time * 7) * 0.06)
		-- Reutiliza as sequências entre beams; só recalcula a cada 1/40 do fade.
		local opacity = math.floor(p * 40) / 40
		if opacity ~= lastOpacity then
			lastOpacity = opacity
			local edgeAlpha = NumberSequence.new(1 - opacity * 0.9)
			local glowAlpha = NumberSequence.new(1 - opacity * 0.36)
			local filamentAlpha = NumberSequence.new(1 - opacity * 0.48)
			for _, v in rimBeams do v.Transparency = edgeAlpha end
			for _, v in glowBeams do v.Transparency = glowAlpha end
			for _, strand in strands do
				for _, v in strand.beams do v.Transparency = filamentAlpha end
			end
		end
		if stage ~= "closing" then
			for _, e in emitters do e.Rate = rates[e] * p end
		end
	end

	model.Parent = folder
	ancestry = model.AncestryChanged:Connect(function()
		if not model:IsDescendantOf(Workspace) then rift:Destroy() end
	end)
	heartbeat = RunService.Heartbeat:Connect(function(dt: number)
		local now = os.clock()
		if now - born >= S.HardMaxLifetime or now >= closeAt + S.ResidualTail then
			rift:Destroy()
			return
		end
		accumulated += dt
		if accumulated < 1 / S.UpdateRate then return end
		accumulated %= 1 / S.UpdateRate
		animate(now)
	end)
	animate(born)
	return rift
end
return RiftVFX
