--!strict
--[[
	RiftVFX
	Constrói / anima / limpa UMA fenda do teleporte do Monstro. Roda no
	CLIENTE (client/RiftVFXController chama; o servidor nunca toca nisto).
	O visual = asset AssetRegistry.RiftTeleport.AssetId (clonado de
	ReplicatedStorage.RiftAssets, publicado pelo servidor) + partículas /
	luz / distorção montadas aqui por cima. Se o asset não existir, uma fenda
	primitiva de reserva é montada -- a API é a mesma.

	FILOSOFIA DE HORROR (nada de magia colorida):
	  tudo é preto / cinza-chumbo / um fio de carmim MUITO apagado nas bordas.
	  A fenda "respira" escuridão e puxa poeira pra dentro. A luz é quase
	  imperceptível, só pra a fenda não sumir no breu da noite.

	API (tudo com TweenService, sem loop por frame):
		local rift = RiftVFX.new({
			template = Model?,      -- de ReplicatedStorage.RiftAssets; nil = reserva
			cframe = CFrame,         -- centro da fenda, JÁ assentado no chão
			width = number,          -- largura desejada em studs (vem do servidor)
			faceAxis = "Y"|"Z"|"X",  -- qual eixo local do asset é a "face"
			upright = boolean,       -- true = vertical; false = deitada no chão
			groundOffset = number,   -- <0 crava no chão
			extraRotDeg = {x,y,z},   -- ajuste fino de rotação
			lightBrightness = number,
			lightRangeFactor = number,
			into = Vector3,          -- direção "pra dentro da fenda" (mundo)
		})
		rift:Open(duration)     -- pequena+invisível -> aberta
		rift:Enter()            -- monstro sendo engolido: puxão de partículas
		rift:Emerge()           -- monstro saindo: jato pra fora
		rift:Close(duration)    -- aberta -> recolhida (com rastro), depois auto-Destroy
		rift:Cancel()           -- fade rápido + Destroy (abertura abortada)
		rift:Destroy()          -- cleanup imediato e total
		rift.Core               -- BasePart no centro (o controller pendura os Sons 3D aqui)

	TROCAR O LOOK: mexa em RiftVFX.Style (cores, taxas, tamanhos) ou no asset.
]]

local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")
local Workspace = game:GetService("Workspace")

local RiftVFX = {}

--------------------------------------------------------------------------------
-- ESTILO -- mexa aqui pra ajustar o visual
--------------------------------------------------------------------------------

RiftVFX.Style = {
	Void = Color3.fromRGB(4, 3, 5), -- o "buraco" em si
	Haze = Color3.fromRGB(18, 16, 20), -- fumaça escura
	Mote = Color3.fromRGB(12, 11, 13), -- fragmentos
	Edge = Color3.fromRGB(48, 10, 14), -- carmim apagado das bordas (energia discreta)
	Light = Color3.fromRGB(46, 20, 26), -- cor da PointLight (quase preta)
	Scorch = Color3.fromRGB(9, 8, 9), -- marca no chão

	StartScale = 0.05, -- fração da escala final ao começar a abrir
	OpenEasing = Enum.EasingStyle.Quart, -- abrir: desacelera no fim
	CloseEasing = Enum.EasingStyle.Quint, -- fechar: "engole" rápido no fim

	PullAccel = 34, -- studs/s^2 puxando as partículas pra dentro da fenda
	PullRateOpen = 9, -- taxa base do puxão enquanto aberta
	PullRateEnter = 26, -- taxa do puxão enquanto o monstro é engolido
	HazeRate = 4,
	MoteRate = 3.5,
	EdgeRate = 2.5,

	ResidualTail = 2.2, -- segundos de fumaça residual DEPOIS de fechar
	HardMaxLifetime = 30, -- rede de segurança: nenhuma fenda vive mais que isto
}

local S = RiftVFX.Style

--------------------------------------------------------------------------------
-- Reserva (sem asset): fenda primitiva -- disco preto + aro brilhante + rachas
--------------------------------------------------------------------------------

local function buildFallbackTemplate(): Model
	local model = Instance.new("Model")
	model.Name = "FendaReserva"

	local UP = CFrame.Angles(0, 0, math.pi / 2)

	local void = Instance.new("Part")
	void.Name = "Vazio"
	void.Shape = Enum.PartType.Cylinder
	void.Size = Vector3.new(0.3, 8, 5.2)
	void.CFrame = UP
	void.Anchored = true
	void.CanCollide = false
	void.CanQuery = false
	void.CastShadow = false
	void.Material = Enum.Material.Slate
	void.Color = S.Void
	void.Parent = model

	local rim = Instance.new("Part")
	rim.Name = "Aro"
	rim.Shape = Enum.PartType.Cylinder
	rim.Size = Vector3.new(0.18, 9.4, 6.4)
	rim.CFrame = UP * CFrame.new(0, 0, 0)
	rim.Anchored = true
	rim.CanCollide = false
	rim.CanQuery = false
	rim.CastShadow = false
	rim.Material = Enum.Material.Neon
	rim.Color = S.Edge
	rim.Transparency = 0.55
	rim.Parent = model

	for i = 1, 6 do
		local a = (i - 1) / 6 * math.pi * 2 + (i % 2) * 0.3
		local len = 1.6 + (i % 3) * 0.9
		local crack = Instance.new("Part")
		crack.Name = "Racha_" .. i
		crack.Size = Vector3.new(len, 0.12, 0.22 + (i % 2) * 0.1)
		crack.CFrame = CFrame.new(0, 0.06, 0)
			* CFrame.Angles(0, a, 0)
			* CFrame.new(3.4 + len / 2, 0, 0)
		crack.Anchored = true
		crack.CanCollide = false
		crack.CanQuery = false
		crack.CastShadow = false
		crack.Material = Enum.Material.Neon
		crack.Color = S.Edge
		crack.Transparency = 0.7
		crack.Parent = model
	end

	model.PrimaryPart = void
	return model
end

--------------------------------------------------------------------------------
-- Helpers
--------------------------------------------------------------------------------

local function largestFace(size: Vector3, faceAxis: string): number
	if faceAxis == "Y" then
		return math.max(size.X, size.Z)
	elseif faceAxis == "Z" then
		return math.max(size.X, size.Y)
	else
		return math.max(size.Y, size.Z)
	end
end

-- Deita a fenda no chão: o eixo `faceAxis` do asset fica ao longo da normal
-- da superfície; giro aleatório em torno dela pra variedade.
local function flatCFrame(pos: Vector3, normal: Vector3, faceAxis: string, yaw: number): CFrame
	local up = normal.Magnitude > 0.001 and normal.Unit or Vector3.yAxis
	local ref = math.abs(up:Dot(Vector3.yAxis)) > 0.99 and Vector3.xAxis or Vector3.yAxis
	local right = up:Cross(ref)
	right = right.Magnitude > 0.001 and right.Unit or Vector3.xAxis
	local look = right:Cross(up).Unit
	local base = CFrame.fromMatrix(pos, right, up, -look) * CFrame.Angles(0, yaw, 0)

	if faceAxis == "Y" then
		return base
	elseif faceAxis == "Z" then
		return base * CFrame.Angles(math.pi / 2, 0, 0)
	else
		return base * CFrame.Angles(0, 0, math.pi / 2)
	end
end

local raycastParams = RaycastParams.new()
raycastParams.FilterType = Enum.RaycastFilterType.Exclude
raycastParams.IgnoreWater = true

-- Reassenta a fenda na superfície real embaixo dela (Terrain, chão,
-- construção, rampa). O servidor já validou; aqui é só a precisão visual.
local function groundedCFrame(cf: CFrame, faceAxis: string, groundOffset: number, upright: boolean, extraRot: { number }): CFrame
	local ignore = { Workspace:FindFirstChild("RiftVFX") }
	local chars = Workspace:FindFirstChild("Eliminados")
	if chars then
		table.insert(ignore, chars)
	end
	for _, plr in game:GetService("Players"):GetPlayers() do
		if plr.Character then
			table.insert(ignore, plr.Character)
		end
	end
	raycastParams.FilterDescendantsInstances = ignore

	local origin = cf.Position + Vector3.new(0, 6, 0)
	local hit = Workspace:Raycast(origin, Vector3.new(0, -40, 0), raycastParams)
	local pos = hit and hit.Position or cf.Position
	local normal = hit and hit.Normal or Vector3.yAxis
	local rx, ry, rz = extraRot[1] or 0, extraRot[2] or 0, extraRot[3] or 0

	if upright then
		-- vertical: mantém a rotação do servidor (já vira pro monstro), só
		-- cola a base no chão.
		return (cf - cf.Position + (pos + normal * groundOffset))
			* CFrame.Angles(math.rad(rx), math.rad(ry), math.rad(rz))
	end

	local yaw = math.rad(math.random(0, 359))
	return flatCFrame(pos + normal * groundOffset, normal, faceAxis, yaw)
		* CFrame.Angles(math.rad(rx), math.rad(ry), math.rad(rz))
end

local function forEachPart(model: Instance, fn: (BasePart) -> ())
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			fn(d)
		end
	end
end

local function emitter(parent: Instance, name: string): ParticleEmitter
	local e = Instance.new("ParticleEmitter")
	e.Name = name
	e.Enabled = true
	e.Rate = 0
	e.LightEmission = 0
	e.LightInfluence = 1
	e.Speed = NumberRange.new(0)
	e.Rotation = NumberRange.new(0, 360)
	e.RotSpeed = NumberRange.new(-40, 40)
	e.Parent = parent
	return e
end

--------------------------------------------------------------------------------
-- Rift
--------------------------------------------------------------------------------

export type RiftOpts = {
	template: Model?,
	cframe: CFrame,
	width: number,
	faceAxis: string?,
	upright: boolean?,
	groundOffset: number?,
	extraRotDeg: { number }?,
	lightBrightness: number?,
	lightRangeFactor: number?,
	into: Vector3?,
}

type Rift = {
	Core: BasePart,
	Open: (self: Rift, duration: number) -> (),
	Enter: (self: Rift) -> (),
	Emerge: (self: Rift) -> (),
	Close: (self: Rift, duration: number) -> (),
	Cancel: (self: Rift) -> (),
	Destroy: (self: Rift) -> (),
}

function RiftVFX.new(opts: RiftOpts): Rift
	local folder = Workspace:FindFirstChild("RiftVFX")
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = "RiftVFX"
		folder.Parent = Workspace
	end

	local faceAxis = opts.faceAxis or "Y"
	local template = opts.template
	local model: Model = template and template:Clone() or buildFallbackTemplate()
	model.Name = "Fenda"

	-- Normaliza: tudo âncorado, sem colisão/consulta, sem script.
	forEachPart(model, function(p)
		p.Anchored = true
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
		p.CastShadow = false
	end)
	for _, d in model:GetDescendants() do
		if d:IsA("LuaSourceContainer") then
			d:Destroy()
		end
	end
	if not model.PrimaryPart then
		model.PrimaryPart = model:FindFirstChildWhichIsA("BasePart", true)
	end

	-- Escala: largura desejada / largura natural do asset.
	local _, natSize = model:GetBoundingBox()
	local natWidth = math.max(largestFace(natSize, faceAxis), 0.1)
	local scaleMul = math.clamp(opts.width / natWidth, 0.05, 40)
	model:ScaleTo(model:GetScale() * scaleMul)

	local width = opts.width
	local baseScale = model:GetScale()

	-- Assenta no chão.
	local placedCF = groundedCFrame(
		opts.cframe,
		faceAxis,
		opts.groundOffset or 0,
		opts.upright == true,
		opts.extraRotDeg or { 0, 0, 0 }
	)
	model:PivotTo(placedCF)
	model.Parent = folder

	-- Núcleo invisível: âncora de sons, luz e partículas.
	local core = Instance.new("Part")
	core.Name = "Core"
	core.Size = Vector3.new(0.2, 0.2, 0.2)
	core.CFrame = placedCF
	core.Anchored = true
	core.CanCollide = false
	core.CanQuery = false
	core.CanTouch = false
	core.CastShadow = false
	core.Transparency = 1
	core.Parent = model

	-- "pra dentro da fenda" = contra a normal da superfície onde ela assentou
	-- (funciona em rampa). Só usa opts.into se a fenda for vertical.
	local into: Vector3
	if opts.upright and opts.into and opts.into.Magnitude > 0.01 then
		into = opts.into.Unit
	else
		into = -placedCF.UpVector
	end

	-- Campo de partículas: uma chapa fina do tamanho da fenda, ALINHADA à
	-- superfície (Top = pra fora da fenda, Bottom = pra dentro).
	local field = Instance.new("Part")
	field.Name = "Field"
	field.Size = Vector3.new(width, 0.2, width)
	field.CFrame = placedCF
	field.Anchored = true
	field.CanCollide = false
	field.CanQuery = false
	field.CanTouch = false
	field.CastShadow = false
	field.Transparency = 1
	field.Parent = model

	-- Puxão pra dentro (converge + suga).
	local pull = emitter(field, "Pull")
	pull.Texture = "rbxasset://textures/particles/smoke_main.dds"
	pull.Color = ColorSequence.new(S.Mote)
	pull.Lifetime = NumberRange.new(0.5, 1.0)
	pull.Speed = NumberRange.new(1, 3)
	pull.EmissionDirection = Enum.NormalId.Bottom -- pra dentro da fenda
	pull.SpreadAngle = Vector2.new(140, 140)
	pull.Acceleration = into * S.PullAccel
	pull.Drag = 1.5
	pull.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, width * 0.06),
		NumberSequenceKeypoint.new(1, 0),
	})
	pull.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.45),
		NumberSequenceKeypoint.new(1, 1),
	})

	-- Fumaça escura subindo devagar.
	local haze = emitter(field, "Haze")
	haze.Texture = "rbxasset://textures/particles/smoke_main.dds"
	haze.Color = ColorSequence.new(S.Haze)
	haze.Lifetime = NumberRange.new(1.4, 2.6)
	haze.Speed = NumberRange.new(0.6, 1.4)
	haze.EmissionDirection = Enum.NormalId.Top -- pra fora da fenda (sobe)
	haze.SpreadAngle = Vector2.new(24, 24)
	haze.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, width * 0.14),
		NumberSequenceKeypoint.new(1, width * 0.34),
	})
	haze.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.78),
		NumberSequenceKeypoint.new(0.4, 0.9),
		NumberSequenceKeypoint.new(1, 1),
	})

	-- Fragmentos flutuando ao redor + fio de energia carmim na borda.
	local rim = Instance.new("Attachment")
	rim.Name = "Rim"
	rim.Parent = core

	local motes = emitter(rim, "Motes")
	motes.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	motes.Color = ColorSequence.new(S.Mote)
	motes.Lifetime = NumberRange.new(1.0, 2.2)
	motes.Speed = NumberRange.new(0.5, 1.6)
	motes.SpreadAngle = Vector2.new(180, 180)
	motes.Acceleration = into * (S.PullAccel * 0.35)
	motes.Size = NumberSequence.new(width * 0.02)
	motes.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.35),
		NumberSequenceKeypoint.new(1, 1),
	})

	local edge = emitter(rim, "Edge")
	edge.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	edge.Color = ColorSequence.new(S.Edge)
	edge.LightEmission = 0.25
	edge.Lifetime = NumberRange.new(0.25, 0.6)
	edge.Speed = NumberRange.new(2, 5)
	edge.SpreadAngle = Vector2.new(160, 160)
	edge.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, width * 0.03),
		NumberSequenceKeypoint.new(1, 0),
	})
	edge.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.4),
		NumberSequenceKeypoint.new(1, 1),
	})

	-- Luz MUITO sutil (só pra a fenda não sumir no breu).
	local light = Instance.new("PointLight")
	light.Name = "RiftLight"
	light.Color = S.Light
	light.Range = width * (opts.lightRangeFactor or 1.6)
	light.Brightness = 0
	light.Shadows = false
	light.Parent = core
	local maxBrightness = opts.lightBrightness or 0.5

	-- Distorção barata: um Beam escuro atravessando a fenda com textura rolando.
	local a0 = Instance.new("Attachment")
	a0.Name = "BeamA"
	a0.CFrame = CFrame.new(-width / 2, 0, 0)
	a0.Parent = core
	local a1 = Instance.new("Attachment")
	a1.Name = "BeamB"
	a1.CFrame = CFrame.new(width / 2, 0, 0)
	a1.Parent = core
	local beam = Instance.new("Beam")
	beam.Name = "Distortion"
	beam.Attachment0 = a0
	beam.Attachment1 = a1
	beam.Width0 = width * 0.5
	beam.Width1 = width * 0.5
	beam.Segments = 6
	beam.Texture = "rbxasset://textures/particles/smoke_main.dds"
	beam.TextureMode = Enum.TextureMode.Stretch
	beam.TextureSpeed = 0.35
	beam.TextureLength = width
	beam.LightInfluence = 1
	beam.Color = ColorSequence.new(S.Void)
	beam.Transparency = NumberSequence.new(1)
	beam.Parent = core

	-- Marca no chão (fica um pouco depois que a fenda fecha).
	local scorch = Instance.new("Part")
	scorch.Name = "Scorch"
	scorch.Size = Vector3.new(width * 1.3, 0.08, width * 1.3)
	scorch.CFrame = placedCF * CFrame.new(0, -0.04, 0)
	scorch.Anchored = true
	scorch.CanCollide = false
	scorch.CanQuery = false
	scorch.CanTouch = false
	scorch.CastShadow = false
	scorch.Material = Enum.Material.Slate
	scorch.Color = S.Scorch
	scorch.Transparency = 1
	scorch.Parent = model

	--------------------------------------------------------------------------
	-- Estado interno
	--------------------------------------------------------------------------

	-- Só as partes VISUAIS do asset entram no fade (core/field/scorch têm
	-- controle próprio em applyProgress).
	local origTransparency: { [BasePart]: number } = {}
	forEachPart(model, function(p)
		if p ~= core and p ~= field and p ~= scorch then
			origTransparency[p] = p.Transparency
			p.Transparency = 1
		end
	end)

	local progress = Instance.new("NumberValue")
	progress.Value = 0
	progress.Parent = model

	local activeTween: Tween? = nil
	local conn: RBXScriptConnection? = nil
	local destroyed = false
	local hardTimer: thread? = nil

	local lastScale = -1
	local function applyProgress()
		local t = progress.Value
		local eased = t
		local wantScale = baseScale * (S.StartScale + (1 - S.StartScale) * eased)
		if math.abs(wantScale - lastScale) > baseScale * 0.004 then
			model:ScaleTo(wantScale)
			lastScale = wantScale
		end
		for part, orig in origTransparency do
			part.Transparency = 1 - (1 - orig) * eased
		end
		light.Brightness = maxBrightness * eased
		beam.Transparency = NumberSequence.new(1 - 0.22 * eased)
		scorch.Transparency = 1 - 0.55 * eased
		pull.Rate = S.PullRateOpen * eased
		haze.Rate = S.HazeRate * eased
		motes.Rate = S.MoteRate * eased
		edge.Rate = S.EdgeRate * eased
	end

	conn = progress:GetPropertyChangedSignal("Value"):Connect(applyProgress)

	local function tweenTo(target: number, duration: number, style: Enum.EasingStyle, dir: Enum.EasingDirection)
		if activeTween then
			activeTween:Cancel()
		end
		local info = TweenInfo.new(math.max(duration, 0.05), style, dir)
		activeTween = TweenService:Create(progress, info, { Value = target })
		activeTween:Play()
	end

	local rift = {} :: any
	rift.Core = core

	function rift:Open(duration: number)
		if destroyed then
			return
		end
		tweenTo(1, duration, S.OpenEasing, Enum.EasingDirection.Out)
		hardTimer = task.delay(S.HardMaxLifetime, function()
			rift:Destroy()
		end)
	end

	function rift:Enter()
		if destroyed then
			return
		end
		pull.Rate = S.PullRateEnter
		pull.Acceleration = into * (S.PullAccel * 1.8)
		pull:Emit(math.floor(width * 2))
		haze:Emit(6)
	end

	function rift:Emerge()
		if destroyed then
			return
		end
		-- jato pra fora: inverte a aceleração por um instante + emite um monte.
		pull.Acceleration = -into * (S.PullAccel * 1.3)
		pull.Speed = NumberRange.new(4, 9)
		pull:Emit(math.floor(width * 2.2))
		edge:Emit(math.floor(width))
		local flash = TweenService:Create(light, TweenInfo.new(0.5, Enum.EasingStyle.Quad), { Brightness = maxBrightness * 1.8 })
		flash:Play()
		flash.Completed:Once(function()
			if not destroyed then
				TweenService:Create(light, TweenInfo.new(0.4), { Brightness = maxBrightness }):Play()
			end
		end)
		task.delay(0.5, function()
			if not destroyed then
				pull.Acceleration = into * S.PullAccel
				pull.Speed = NumberRange.new(1, 3)
			end
		end)
	end

	function rift:Close(duration: number)
		if destroyed then
			return
		end
		-- corta a maior parte das partículas na metade do fechamento.
		task.delay(duration * 0.5, function()
			if destroyed then
				return
			end
			pull.Rate = 0
			motes.Rate = 0
			edge.Rate = 0
			haze.Rate = math.min(haze.Rate, 1.5) -- deixa um fio de fumaça residual
		end)
		tweenTo(0, duration, S.CloseEasing, Enum.EasingDirection.In)
		task.delay(duration, function()
			if destroyed then
				return
			end
			-- fenda fechada, mas mantém o Core + fumaça residual por um tempo.
			model:ScaleTo(baseScale * S.StartScale)
			for part in origTransparency do
				part.Transparency = 1
			end
			light.Brightness = 0
			haze.Rate = 1.2
			scorch.Transparency = 0.6
			task.delay(S.ResidualTail, function()
				if destroyed then
					return
				end
				haze.Rate = 0
				TweenService:Create(scorch, TweenInfo.new(1.2), { Transparency = 1 }):Play()
				task.delay(1.4, function()
					rift:Destroy()
				end)
			end)
		end)
	end

	function rift:Cancel()
		if destroyed then
			return
		end
		pull.Rate = 0
		motes.Rate = 0
		edge.Rate = 0
		haze.Rate = 0
		tweenTo(0, 0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		task.delay(0.3, function()
			rift:Destroy()
		end)
	end

	function rift:Destroy()
		if destroyed then
			return
		end
		destroyed = true
		if conn then
			conn:Disconnect()
			conn = nil
		end
		if activeTween then
			activeTween:Cancel()
			activeTween = nil
		end
		if hardTimer then
			task.cancel(hardTimer)
			hardTimer = nil
		end
		model:Destroy()
	end

	return rift
end

return RiftVFX
