--!strict
-- One reversible client presentation per streamed character. No movement writes,
-- remotes, render connections, cloned rigs or replicated effect instances.
local Workspace = game:GetService("Workspace")
local Config = require(script.Parent.GameConfig)
local Rules = require(script.Parent.ShadowRushRules)
local AssetRules = require(script.Parent.FearPresentationRules)
local CFG = Config.Monster.ShadowRush
local S = CFG.Visual
local SMOKE = "rbxasset://textures/particles/smoke_main.dds"
local VFX = {}

local function sequence(a: number, b: number): NumberSequence
	return NumberSequence.new({ NumberSequenceKeypoint.new(0, a), NumberSequenceKeypoint.new(1, b) })
end

local function emitter(parent: Instance, name: string, color: Color3): ParticleEmitter
	local p = Instance.new("ParticleEmitter")
	p.Name, p.Texture, p.Color = name, SMOKE, ColorSequence.new(color)
	p.Rate, p.LightInfluence, p.LightEmission = 0, 0, 0
	p.Lifetime, p.Speed = NumberRange.new(0.2, 0.45), NumberRange.new(1, 3)
	p.SpreadAngle, p.Rotation, p.RotSpeed = Vector2.new(180, 180), NumberRange.new(0, 360), NumberRange.new(-65, 65)
	p.Size, p.Transparency = sequence(1.3, 3.2), sequence(0.35, 1)
	p.LockedToPart = false -- old particles stay behind as the body moves
	p.Parent = parent
	return p
end

local function anchor(parent: Instance): BasePart
	local p = Instance.new("Part")
	p.Name, p.Size, p.Transparency = "ShadowField", Vector3.new(2.7, 4.7, 1.8), 1
	p.Anchored, p.CanCollide, p.CanTouch, p.CanQuery, p.CastShadow = true, false, false, false, false
	p.Parent = parent
	return p
end

-- Details are allocated only inside the observer's detail radius. A far observer
-- still sees the translucent dark rig, without emitters, beams, trails or light.
local function details(folder: Instance, character: Model, root: BasePart, low: boolean): any
	local model = Instance.new("Model")
	model.Name, model.Parent = "ShadowDetails", folder
	local core = anchor(model)
	core.CFrame = root.CFrame
	local haze = emitter(core, "UnboundShadow", S.ShadowColor)
	haze.Shape, haze.ShapeStyle, haze.ShapeInOut = Enum.ParticleEmitterShape.Box,
		Enum.ParticleEmitterShapeStyle.Volume, Enum.ParticleEmitterShapeInOut.Outward
	haze.Lifetime, haze.Speed, haze.Drag = NumberRange.new(0.55, 1.05), NumberRange.new(0.45, 1.8), S.SmokeDrag
	haze.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1.7),
		NumberSequenceKeypoint.new(0.38, 3.3),
		NumberSequenceKeypoint.new(1, 5.8),
	})
	haze.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.18),
		NumberSequenceKeypoint.new(0.45, 0.42),
		NumberSequenceKeypoint.new(1, 1),
	})
	haze.Color = ColorSequence.new(Color3.fromRGB(3, 3, 4), Color3.fromRGB(66, 64, 70))
	local shroud = emitter(core, "DenseBodySmoke", Color3.fromRGB(18, 18, 21))
	shroud.Shape, shroud.ShapeStyle, shroud.ShapeInOut = Enum.ParticleEmitterShape.Box,
		Enum.ParticleEmitterShapeStyle.Volume, Enum.ParticleEmitterShapeInOut.Outward
	shroud.Lifetime, shroud.Speed, shroud.Drag = NumberRange.new(0.42, 0.82), NumberRange.new(0.25, 1.15), S.SmokeDrag * 0.82
	shroud.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1.25),
		NumberSequenceKeypoint.new(0.5, 2.8),
		NumberSequenceKeypoint.new(1, 4.2),
	})
	shroud.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.06),
		NumberSequenceKeypoint.new(0.55, 0.38),
		NumberSequenceKeypoint.new(1, 1),
	})
	shroud.Color = ColorSequence.new(Color3.fromRGB(4, 4, 5), Color3.fromRGB(48, 47, 52))
	local crown = Instance.new("Attachment")
	crown.Name, crown.Position, crown.Parent = "SmokeCrown", Vector3.new(0, 1.25, 0), core
	local plume = emitter(crown, "LivingPlume", Color3.fromRGB(5, 5, 9))
	plume.EmissionDirection, plume.SpreadAngle = Enum.NormalId.Top, Vector2.new(42, 42)
	plume.Lifetime, plume.Speed, plume.Drag = NumberRange.new(0.7, 1.3), NumberRange.new(0.8, 3.1), S.SmokeDrag * 0.7
	plume.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1.05),
		NumberSequenceKeypoint.new(0.35, 3.1),
		NumberSequenceKeypoint.new(1, 6.2),
	})
	plume.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.12),
		NumberSequenceKeypoint.new(0.6, 0.5),
		NumberSequenceKeypoint.new(1, 1),
	})
	plume.Color = ColorSequence.new(Color3.fromRGB(5, 5, 6), Color3.fromRGB(74, 72, 78))
	local lower = Instance.new("Attachment")
	lower.Name, lower.Position, lower.Parent = "SmokeWake", Vector3.new(0, -1.45, 0.35), core
	local wake = emitter(lower, "DraggingSmoke", Color3.fromRGB(2, 2, 5))
	wake.EmissionDirection, wake.SpreadAngle = Enum.NormalId.Back, Vector2.new(34, 34)
	wake.Lifetime, wake.Speed, wake.Drag = NumberRange.new(0.42, 0.86), NumberRange.new(2, 8), S.SmokeDrag
	wake.Size, wake.Transparency = sequence(0.75, 3.8), NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.1),
		NumberSequenceKeypoint.new(0.55, 0.48),
		NumberSequenceKeypoint.new(1, 1),
	})
	wake.Color = ColorSequence.new(Color3.fromRGB(3, 3, 4), Color3.fromRGB(55, 53, 60))
	local burst = emitter(core, "Rupture", Color3.fromRGB(29, 12, 20))
	burst.Speed, burst.Drag = NumberRange.new(10, 19), 8
	burst.Shape, burst.ShapeStyle = Enum.ParticleEmitterShape.Sphere, Enum.ParticleEmitterShapeStyle.Surface
	burst.Size = sequence(1.4, 4)
	local energy = emitter(core, "EnergyResidue", S.EnergyColor)
	energy.Texture, energy.LightEmission = "rbxasset://textures/particles/sparkles_main.dds", 0.65
	energy.Size, energy.Speed = sequence(0.16, 0), NumberRange.new(9, 24)
	energy.Lifetime, energy.Drag = NumberRange.new(0.15, 0.35), 6
	local light = Instance.new("PointLight")
	light.Name, light.Color, light.Range, light.Brightness = "RuptureLight", S.EnergyColor, S.LightRange, 0
	light.Shadows, light.Parent = false, core
	local silhouette = Instance.new("Highlight")
	silhouette.Name, silhouette.Adornee = "OccludedShadow", character
	silhouette.DepthMode = Enum.HighlightDepthMode.Occluded
	silhouette.FillColor, silhouette.OutlineColor = S.ShadowColor, Color3.fromRGB(54, 43, 64)
	silhouette.FillTransparency, silhouette.OutlineTransparency = 1, 1
	silhouette.Parent = model
	local trails = {}
	for i = 1, 2 do
		local a, b = Instance.new("Attachment"), Instance.new("Attachment")
		a.Position, b.Position = Vector3.new((i * 2 - 3) * 0.65, 0.9, 0), Vector3.new((i * 2 - 3) * 0.85, -1.3, 0)
		a.Parent, b.Parent = core, core
		local trail = Instance.new("Trail")
		trail.Name, trail.Attachment0, trail.Attachment1 = "TornShadow", a, b
		trail.Texture, trail.Color = SMOKE, ColorSequence.new(S.ShadowColor)
		trail.Lifetime, trail.MinLength, trail.FaceCamera = S.TrailLifetime, 0.15, true
		trail.Transparency, trail.WidthScale = sequence(0.62, 1), sequence(1, 0)
		trail.Enabled, trail.Parent = false, core
		table.insert(trails, trail)
	end
	local arcs = {}
	local count = if low then 8 else 12
	for i = 1, count do
		local a, b = Instance.new("Attachment"), Instance.new("Attachment")
		a.Parent, b.Parent = core, core
		local beam = Instance.new("Beam")
		beam.Name, beam.Attachment0, beam.Attachment1 = "BrokenWave", a, b
		beam.Texture, beam.TextureSpeed, beam.Segments = SMOKE, 0.5, 2
		beam.FaceCamera, beam.LightEmission, beam.Color = true, 0.8, ColorSequence.new(S.EnergyColor)
		beam.Transparency, beam.Enabled, beam.Parent = NumberSequence.new(1), false, core
		table.insert(arcs, { a = a, b = b, beam = beam, angle = (i - 1) * math.pi * 2 / count, span = math.pi * 2 / count * 0.87 })
	end
	-- Texture wisps shear around the animated silhouette without touching joints.
	local wisps = {}
	for i = 1, (if low then 2 else 3) do
		local a, b = Instance.new("Attachment"), Instance.new("Attachment")
		a.Parent, b.Parent = core, core
		local beam = Instance.new("Beam")
		beam.Name, beam.Attachment0, beam.Attachment1 = "ShadowWisp", a, b
		beam.Texture, beam.TextureSpeed, beam.Segments = SMOKE, -0.8, 4
		beam.Color, beam.FaceCamera = ColorSequence.new(S.ShadowColor), true
		beam.Width0, beam.Width1, beam.Transparency = 1.1, 0.15, NumberSequence.new(1)
		beam.Parent = core
		table.insert(wisps, { a = a, b = b, beam = beam })
	end
	return { model = model, core = core, haze = haze, shroud = shroud, plume = plume, wake = wake, burst = burst, energy = energy,
		light = light, silhouette = silhouette, trails = trails, arcs = arcs, wisps = wisps }
end

function VFX.new(character: Model, root: BasePart, folder: Instance, owner: boolean?, lowQuality: boolean?)
	local transparency: { [Instance]: number } = {}
	local colors: { [BasePart]: Color3 } = {}
	local shadows: { [BasePart]: boolean } = {}
	local enabled: { [Instance]: boolean } = {}
	local volumes: { [Sound]: number } = {}
	local jointTransforms: { [Motor6D]: CFrame } = {}
	local sounds: { Sound } = {}
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local display = if humanoid then humanoid.DisplayDistanceType else nil
	local destroyed, currentPhase, hidden = false, "", 0
	local finishing, finishAt, finishFrom = false, 0, 0
	local waveAt, waveIn, tickAt, lodAt = -100, false, 0, 1
	local detail: any = nil
	local quality = 0
	local loop: Sound? = nil
	local function captureJoint(d: Instance)
		-- Só a articulação raiz sobe: transformar cada junta separaria os membros.
		if d:IsA("Motor6D") and d.Part0 == root and jointTransforms[d] == nil then
			jointTransforms[d] = d.Transform
		end
	end

	local function capture(d: Instance)
		if d:GetAttribute("ShadowRushAudio") == true then return end
		if d:IsA("BasePart") or d:IsA("Decal") or d:IsA("Texture") then
			if transparency[d] == nil then transparency[d] = d.Transparency end
			if d:IsA("BasePart") then
				if colors[d] == nil then colors[d], shadows[d] = d.Color, d.CastShadow end
			end
		elseif d:IsA("ParticleEmitter") or d:IsA("Trail") or d:IsA("Beam")
			or d:IsA("Light") or d:IsA("Highlight") or d:IsA("BillboardGui") or d:IsA("SurfaceGui") then
			if enabled[d] == nil then enabled[d] = (d :: any).Enabled end
			(d :: any).Enabled = false
			if d:IsA("ParticleEmitter") or d:IsA("Trail") then d:Clear() end
		elseif d:IsA("Sound") then
			if volumes[d] == nil then volumes[d] = d.Volume end
		end
	end
	for _, d in character:GetDescendants() do capture(d); captureJoint(d) end
	local connection = character.DescendantAdded:Connect(capture)
	local jointConnection = character.DescendantAdded:Connect(captureJoint)
	local removing = character.DescendantRemoving:Connect(function(d)
		-- Streaming/reparented accessories must not retain our local appearance.
		if transparency[d] ~= nil then (d :: any).Transparency = transparency[d]; transparency[d] = nil end
		if colors[d :: any] then
			local p = d :: BasePart
			p.Color, p.CastShadow = colors[p], shadows[p]
			colors[p], shadows[p] = nil, nil
		end
		if enabled[d] ~= nil then (d :: any).Enabled = enabled[d]; enabled[d] = nil end
		if volumes[d :: any] ~= nil then (d :: Sound).Volume = volumes[d :: any]; volumes[d :: any] = nil end
		if jointTransforms[d :: any] ~= nil then jointTransforms[d :: Motor6D] = nil end
	end)

	local function playSound(value: string, looped: boolean, bass: boolean?): Sound?
		local id = AssetRules.AssetId(value)
		if not id then return nil end
		local sound = Instance.new("Sound")
		sound.Name, sound.SoundId, sound.Volume = "ShadowRushAudio", id, CFG.SoundVolume
		sound.Looped, sound.RollOffMaxDistance, sound.RollOffMinDistance = looped, CFG.SoundMaxDistance, 7
		sound.RollOffMode = Enum.RollOffMode.InverseTapered
		sound:SetAttribute("ShadowRushAudio", true)
		if bass then
			sound.PlaybackSpeed = CFG.EnterSoundPlaybackSpeed
			local eq = Instance.new("EqualizerSoundEffect")
			eq.LowGain, eq.MidGain, eq.HighGain, eq.Parent = 4, -2, -9, sound
		end
		sound.Parent = root
		table.insert(sounds, sound)
		sound:Play()
		return sound
	end

	local function wave(inward: boolean, now: number)
		waveAt, waveIn = now, inward
		if detail then
			detail.burst.ShapeInOut = if inward then Enum.ParticleEmitterShapeInOut.Inward else Enum.ParticleEmitterShapeInOut.Outward
			detail.burst:Emit(if quality == 2 then 18 else 8)
			detail.energy:Emit(if inward then 5 elseif quality == 2 then 18 else 8)
			for _, arc in detail.arcs do
				arc.beam.Color = ColorSequence.new(if inward then Color3.fromRGB(122, 32, 28) else S.EnergyColor)
			end
		end
	end

	local function stopLoop()
		if loop then
			loop:Stop()
			loop:Destroy()
			loop = nil
		end
	end

	local handle = {}
	function handle.Finish()
		if finishing or destroyed then return end
		finishing, finishAt, finishFrom = true, Workspace:GetServerTimeNow(), hidden
		stopLoop()
		if hidden > 0.01 then
			wave(true, finishAt)
			playSound(CFG.ShadowRushExitSoundId, false)
		end
	end
	function handle.Update(dt: number, distance: number?): boolean
		if destroyed then return true end
		local now = Workspace:GetServerTimeNow()
		lodAt += dt
		if lodAt >= 0.2 then
			lodAt = 0
			local d = if owner then 0 else distance or math.huge
			quality = if d > S.DetailDistance then 0 elseif d > S.NearDistance or lowQuality then 1 else 2
			if quality > 0 and not detail then detail = details(folder, character, root, quality == 1)
			elseif quality == 0 and detail then detail.model:Destroy(); detail = nil end
		end
		local state = character:GetAttribute("ShadowRushState") or "Idle"
		local elapsed = math.max(0, now - (character:GetAttribute("ShadowRushPhaseAt") or now))
		-- State and Busy can arrive on different frames during an interruption.
		if state == "Idle" and hidden > 0.01 and not finishing then handle.Finish() end
		if not finishing and state ~= currentPhase then
			currentPhase = state
			tickAt = math.huge
			if state == "EnteringShadow" then
				-- Late streams do not replay a stale blast or activation sound.
				if elapsed < CFG.ShadowRushEnterDuration then
					wave(false, now - elapsed); playSound(CFG.ShadowRushEnterSoundId, false, true)
				end
			elseif state == "ShadowRush" then
				stopLoop()
				loop = playSound(CFG.ShadowRushLoopSoundId, true)
			elseif state == "Materializing" and elapsed < CFG.ShadowRushMaterializeDuration then
				stopLoop()
				wave(true, now - elapsed); playSound(CFG.ShadowRushExitSoundId, false)
			else
				stopLoop()
			end
		end
		if finishing then
			hidden = finishFrom * (1 - math.clamp((now - finishAt) / S.CancelFadeDuration, 0, 1))
		else
			hidden = Rules.Hidden(state, elapsed, character:GetAttribute("ShadowRushExitHidden") or hidden, CFG)
		end
		tickAt += dt
		if detail then
			-- O volume nunca fica perfeitamente rígido: ele oscila de lado enquanto
			-- acompanha a raiz. As partículas antigas não são movidas e formam a cauda.
			local drift = math.sin(now * 5.7) * 0.11
			detail.core.CFrame = root.CFrame * CFrame.new(drift, 0.28 + math.sin(now * 7.1) * 0.08, 0)
		end
		local interval = if quality == 0 then S.FarUpdateInterval elseif quality == 1 then 1 / 20 else 1 / 30
		if tickAt < interval then return false end
		tickAt = 0
		local velocity = root.AssemblyLinearVelocity * Vector3.new(1, 0, 1)
		local speed = math.clamp(velocity.Magnitude / CFG.ShadowRushMaxSpeed, 0, 1)
		-- Sem partículas no LOD distante, preserve uma silhueta escura legível.
		-- Perto/médio, o volume de fumaça assume completamente a apresentação.
		local smokeForm = state == "ShadowRush" and not finishing
		for d, original in transparency do
			if d.Parent then
				-- Durante a corrida o corpo material desaparece por completo. A forma
				-- visível é somente a fumaça local; hitbox e física não são alteradas.
				local amount = if smokeForm then 1 else hidden * 0.82
				if d:IsA("BasePart") and not smokeForm then
					amount *= 0.92 + math.sin(now * 13 + d.Size.Y * 3) * 0.035
				end
				(d :: any).Transparency = original + (1 - original) * amount
			end
		end
		for d, original in colors do
			if d.Parent then d.Color = original:Lerp(S.ShadowColor, hidden); d.CastShadow = shadows[d] and hidden < 0.5 end
		end
		for d, original in enabled do if d.Parent then (d :: any).Enabled = original and hidden < 0.01 end end
		for sound, original in volumes do if sound.Parent then sound.Volume = original * (1 - hidden) end end
		-- Eleva só a malha localmente, em todos os clientes que enxergam o VFX.
		-- A HumanoidRootPart física continua no chão para preservar colisão e regras.
		local floating = (state == "EnteringShadow" or state == "ShadowRush") and hidden > 0.05 and not finishing
		for joint, original in jointTransforms do
			if joint.Parent then
				if floating then
					local bob = S.FloatHeight + math.sin(now * S.FloatFrequency * math.pi * 2) * S.FloatAmplitude
					local lean = math.sin(now * S.FloatFrequency * math.pi) * math.rad(S.FloatLeanDegrees)
					joint.Transform = original * CFrame.new(0, bob, 0) * CFrame.Angles(lean * 0.35, 0, lean)
				else
					joint.Transform = original
				end
			end
		end
		if humanoid then humanoid.DisplayDistanceType = if hidden > 0.01 then Enum.HumanoidDisplayDistanceType.None else display end
		if loop then loop.Volume = CFG.SoundVolume * hidden * 0.6 end
		if detail then
			local smokeStrength = hidden * (if smokeForm then 1 else 0.45)
			local lod = if quality == 2 then 1 else 0.42
			detail.silhouette.Enabled = false
			detail.silhouette.FillTransparency, detail.silhouette.OutlineTransparency = 1, 1
			detail.haze.Rate = S.ParticleRate * S.SmokeDensity * smokeStrength * (0.72 + speed * 0.75) * lod
			detail.shroud.Rate = S.ParticleRate * 0.95 * S.SmokeDensity * smokeStrength * lod
			detail.plume.Rate = S.ParticleRate * 0.58 * S.SmokeDensity * smokeStrength * lod
			detail.wake.Rate = S.ParticleRate * 0.9 * S.SmokeDensity * smokeStrength * speed * lod
			local drag = Vector3.new(-velocity.X * 0.32, S.SmokeLift, -velocity.Z * 0.32)
			detail.haze.Acceleration = drag
			detail.shroud.Acceleration = Vector3.new(drag.X * 0.7, S.SmokeLift * 0.8, drag.Z * 0.7)
			detail.plume.Acceleration = Vector3.new(drag.X * 0.35, S.SmokeLift * 1.25, drag.Z * 0.35)
			detail.wake.Acceleration = Vector3.new(drag.X * 0.55, S.SmokeLift * 0.35, drag.Z * 0.55)
			detail.wake.Speed = NumberRange.new(2 + speed * 4, 5 + speed * 10)
			for _, trail in detail.trails do trail.Enabled = quality == 2 and hidden > 0.4 and speed > 0.12 and not finishing end
			local duration = if waveIn then CFG.ShadowRushMaterializeDuration else S.WaveDuration
			local t = math.clamp((now - waveAt) / duration, 0, 1)
			local radius = if waveIn then 0.5 + S.WaveRadius * (1 - t) ^ 2 else 0.5 + S.WaveRadius * (1 - (1 - t) ^ 3)
			detail.light.Brightness = (if quality == 2 then S.LightBrightness else S.LightBrightness * 0.4) * (1 - t) ^ 3
			for _, arc in detail.arcs do
				local a, b = arc.angle, arc.angle + arc.span
				arc.a.Position = Vector3.new(math.cos(a) * radius, -0.6 + math.sin(a * 3) * 0.3, math.sin(a) * radius)
				arc.b.Position = Vector3.new(math.cos(b) * radius, -0.6 + math.sin(b * 3) * 0.3, math.sin(b) * radius)
				arc.beam.Enabled = t < 1
				arc.beam.Width0, arc.beam.Width1 = 0.12 + (1 - t) * 0.7, 0.08 + (1 - t) * 0.45
				arc.beam.Transparency = NumberSequence.new(0.2 + t * 0.8)
			end
			for i, wisp in detail.wisps do
				local sway = math.sin(now * 8 + i * 2) * 0.35
				local spread = if waveIn and t < 1 then 1 + (1 - t) * 2 else 1
				wisp.a.Position = Vector3.new((i - 2) * 0.65 * spread + sway, 1.8, 0.2)
				wisp.b.Position = Vector3.new((i - 2) * spread - sway, -1.5, 0.3 + speed * 1.8)
				wisp.beam.CurveSize0, wisp.beam.CurveSize1 = sway * 2, -sway * 3
				wisp.beam.Transparency = NumberSequence.new(1 - hidden * 0.42)
			end
		end
		return finishing and now - finishAt >= S.CancelFadeDuration
	end
	function handle.Destroy()
		if destroyed then return end
		destroyed = true
		connection:Disconnect(); jointConnection:Disconnect(); removing:Disconnect()
		if detail then detail.model:Destroy(); detail = nil end
		for _, sound in sounds do sound:Destroy() end
		for d, original in transparency do if d.Parent then (d :: any).Transparency = original end end
		for d, original in colors do if d.Parent then d.Color, d.CastShadow = original, shadows[d] end end
		for d, original in enabled do if d.Parent then (d :: any).Enabled = original end end
		for sound, original in volumes do if sound.Parent then sound.Volume = original end end
		for joint, original in jointTransforms do if joint.Parent then joint.Transform = original end end
		if humanoid and humanoid.Parent and display then humanoid.DisplayDistanceType = display end
	end
	return handle
end

-- Personal view: own effects under CurrentCamera, never edit shared Lighting.
function VFX.newView()
	local camera: Camera? = nil
	local correction: ColorCorrectionEffect? = nil
	local bloom: BloomEffect? = nil
	local blur: BlurEffect? = nil
	local strength, kickAt = 0, -100
	local applied: CFrame? = nil
	local base: CFrame? = nil
	local handle = {}
	function handle.Unshake()
		if camera and applied and base and camera.CFrame == applied then camera.CFrame = base end
		applied, base = nil, nil
	end
	local function clear()
		handle.Unshake()
		if correction then correction:Destroy(); correction = nil end
		if bloom then bloom:Destroy(); bloom = nil end
		if blur then blur:Destroy(); blur = nil end
	end
	function handle.Update(dt: number, target: number, speed: number, enter: boolean): number
		local current = Workspace.CurrentCamera
		if current ~= camera then clear(); camera = current end
		strength = AssetRules.Smooth(strength, target, dt, if target > strength then 0.06 else 0.12)
		if enter then kickAt = os.clock() end
		if not camera then return strength end
		if target == 0 and strength < 0.002 then strength = 0; clear(); return 0 end
		if not correction then
			correction = Instance.new("ColorCorrectionEffect")
			correction.Name, correction.Parent = "ShadowRushVision", camera
			bloom = Instance.new("BloomEffect")
			bloom.Name, bloom.Size, bloom.Threshold, bloom.Parent = "ShadowRushBloom", 16, 1.1, camera
			blur = Instance.new("BlurEffect")
			blur.Name, blur.Parent = "ShadowRushBlur", camera
		end
		local age = os.clock() - kickAt
		local kick = math.max(0, 1 - age / S.ShakeDuration) ^ 2
		correction.Brightness = S.VisionBrightness * strength
		correction.Contrast, correction.Saturation = S.VisionContrast * strength, S.VisionSaturation * strength
		correction.TintColor = Color3.new(1, 1, 1):Lerp(S.VisionTint, strength)
		if bloom then bloom.Intensity = strength * 0.12 + kick * 0.16 end
		if blur then blur.Size = S.BlurSize * strength * speed + kick * 0.65 end
		if kick > 0 then
			base = camera.CFrame
			local angle = math.rad(S.ShakeDegrees) * kick
			applied = base * CFrame.Angles(math.sin(age * 73) * angle, math.sin(age * 91) * angle * 0.6, math.sin(age * 57) * angle * 0.3)
			camera.CFrame = applied
		end
		return strength
	end
	function handle.Destroy() clear(); strength, camera = 0, nil end
	return handle
end

return VFX
