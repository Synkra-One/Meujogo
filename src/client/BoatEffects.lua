--!strict
--[[
	BoatEffects
	Tudo que faz o barco de fuga PARECER barco, em qualquer cliente que
	esteja perto dele (docs/Barco.md). Nada aqui é regra: é criado no próprio
	cliente (não replica, não custa rede) e lê só o que já replica sozinho --
	a velocidade do corpo e os Attributes do Model.

	  Esteira     fita de espuma (Trail) entre os cantos da popa, abrindo pra
	              trás, + espuma que fica na água por onde o barco passou
	  Hélice      água revolta atrás do motor, pela rotação
	  Spray       leque de água dos dois lados da proa quando planando, mais
	              forte do lado de fora da curva
	  Batidas     o casco batendo nas ondas em alta velocidade (spray + som)
	  Escapamento fumaça fina com o motor ligado, baforada na partida
	  Som         motor com pitch e volume pela rotação (RPM), casco
	              cortando a água, raspando no raso, partida e motor morrendo
	  Limite      as boias do anel de chegada balançam e piscam (só as perto)

	O piloto passa a telemetria exata (acelerador/RPM) pro Update; nos outros
	clientes ela é estimada pela velocidade replicada.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local AssetRegistry = require(ReplicatedStorage.Modules.AssetRegistry)
local BoatPhysics = require(ReplicatedStorage.Modules.BoatPhysics)
local GameConfig = require(ReplicatedStorage.Modules.GameConfig)

local CFG = GameConfig.Boat
local SOUNDS = AssetRegistry.Sounds.Barco
local SMOKE = "rbxasset://textures/particles/smoke_main.dds"
local FOAM = Color3.fromRGB(236, 244, 246)
local ACTIVE_DISTANCE = 520 -- longe disso nada é atualizado
local BUOY_DISTANCE = 360

local BoatEffects = {}
BoatEffects.__index = BoatEffects

export type Telemetry = {
	speed: number,
	planing: number,
	rpm: number,
	throttle: number,
	steer: number,
	surface: string,
}

export type Handle = typeof(setmetatable({} :: {
	model: Model,
	root: BasePart,
	frame: Attachment,
	emitters: { [string]: ParticleEmitter },
	trail: Trail?,
	sounds: { [string]: Sound },
	instances: { Instance },
	connections: { RBXScriptConnection },
	lastSlam: number,
	lastSpeed: number,
	chopClock: number,
	engineWasOn: boolean,
}, BoatEffects))

local function smoothstep(t: number): number
	t = math.clamp(t, 0, 1)
	return t * t * (3 - 2 * t)
end

local function flat(v: Vector3): Vector3
	local f = Vector3.new(v.X, 0, v.Z)
	return if f.Magnitude > 1e-3 then f.Unit else Vector3.new(0, 0, -1)
end

local function emitter(parent: Instance, props: { [string]: any }): ParticleEmitter
	local e = Instance.new("ParticleEmitter")
	e.Texture = SMOKE
	e.Rate = 0
	e.Enabled = true
	e.LightInfluence = 0.6
	for key, value in props do
		(e :: any)[key] = value
	end
	e.Parent = parent
	return e
end

local function loopSound(parent: Instance, id: string, maxDistance: number): Sound?
	if id == "" then
		return nil
	end
	local sound = Instance.new("Sound")
	sound.SoundId = id
	sound.Looped = true
	sound.Volume = 0
	sound.RollOffMode = Enum.RollOffMode.InverseTapered
	sound.RollOffMinDistance = 12
	sound.RollOffMaxDistance = maxDistance
	sound.Parent = parent
	sound:Play()
	return sound
end

local function oneShot(parent: Instance, id: string, volume: number, speed: number)
	if id == "" then
		return
	end
	local sound = Instance.new("Sound")
	sound.SoundId = id
	sound.Volume = volume
	sound.PlaybackSpeed = speed
	sound.RollOffMode = Enum.RollOffMode.InverseTapered
	sound.RollOffMinDistance = 10
	sound.RollOffMaxDistance = 160
	sound.PlayOnRemove = false
	sound.Parent = parent
	sound:Play()
	sound.Ended:Once(function()
		sound:Destroy()
	end)
	task.delay(8, function()
		if sound.Parent then
			sound:Destroy()
		end
	end)
end

--[[
	Attach(model) -> Handle?
	nil se o barco ainda não chegou inteiro (streaming): quem chama tenta de
	novo no próximo frame.
]]
function BoatEffects.Attach(model: Model): Handle?
	local root = model.PrimaryPart
	local frame = root and root:FindFirstChild(BoatPhysics.FrameName)
	if not root or not frame or not frame:IsA("Attachment") then
		return nil
	end
	local function point(name: string): Attachment?
		local a = root:FindFirstChild(name)
		return if a and a:IsA("Attachment") then a else nil
	end

	local self = setmetatable({
		model = model,
		root = root,
		frame = frame,
		emitters = {},
		trail = nil,
		sounds = {},
		instances = {},
		connections = {},
		lastSlam = 0,
		lastSpeed = 0,
		chopClock = 0,
		engineWasOn = model:GetAttribute("MotorLigado") == true,
	}, BoatEffects)

	local left, right = point("EsteiraBB"), point("EsteiraBE")
	if left and right then
		local trail = Instance.new("Trail")
		trail.Attachment0 = left
		trail.Attachment1 = right
		trail.FaceCamera = false
		trail.Lifetime = 2.4
		trail.MinLength = 0.2
		trail.Color = ColorSequence.new(FOAM)
		trail.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.3),
			NumberSequenceKeypoint.new(0.35, 0.55),
			NumberSequenceKeypoint.new(1, 1),
		})
		trail.WidthScale = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1),
			NumberSequenceKeypoint.new(1, 2.6),
		})
		trail.LightEmission = 0.15
		trail.LightInfluence = 0.7
		trail.Texture = SMOKE
		trail.TextureMode = Enum.TextureMode.Wrap
		trail.TextureLength = 7
		trail.Enabled = false
		trail.Parent = root
		self.trail = trail
		table.insert(self.instances, trail)

		for key, a in { EsteiraBB = left, EsteiraBE = right } do
			-- Espuma deitada na água (VelocityPerpendicular com velocidade pra
			-- cima = disco horizontal), que fica pra trás no mundo.
			self.emitters[key] = emitter(a, {
				Color = ColorSequence.new(FOAM),
				Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1.2), NumberSequenceKeypoint.new(1, 5.5) }),
				Transparency = NumberSequence.new({
					NumberSequenceKeypoint.new(0, 0.45),
					NumberSequenceKeypoint.new(0.6, 0.75),
					NumberSequenceKeypoint.new(1, 1),
				}),
				Lifetime = NumberRange.new(1.6, 2.6),
				Speed = NumberRange.new(0.05),
				EmissionDirection = Enum.NormalId.Top,
				Orientation = Enum.ParticleOrientation.VelocityPerpendicular,
				Rotation = NumberRange.new(0, 360),
				RotSpeed = NumberRange.new(-15, 15),
				-- Sem arrasto: a velocidade (mínima, pra cima) é o que mantém
				-- o disco deitado; zerar faria a orientação girar à toa.
				Drag = 0,
			})
		end
	end

	local wash = point("Helice")
	if wash then
		self.emitters.Helice = emitter(wash, {
			Color = ColorSequence.new(FOAM, Color3.fromRGB(196, 222, 228)),
			Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.8), NumberSequenceKeypoint.new(1, 3.6) }),
			Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.25), NumberSequenceKeypoint.new(1, 1) }),
			Lifetime = NumberRange.new(0.7, 1.3),
			Speed = NumberRange.new(2, 6),
			SpreadAngle = Vector2.new(35, 35),
			EmissionDirection = Enum.NormalId.Top,
			Acceleration = Vector3.new(0, -14, 0),
			Drag = 2,
			Rotation = NumberRange.new(0, 360),
		})
	end

	for _, name in { "SprayBB", "SprayBE" } do
		local a = point(name)
		if a then
			self.emitters[name] = emitter(a, {
				Color = ColorSequence.new(Color3.fromRGB(244, 250, 252)),
				Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.35), NumberSequenceKeypoint.new(0.5, 1.1), NumberSequenceKeypoint.new(1, 1.8) }),
				Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.2), NumberSequenceKeypoint.new(1, 1) }),
				Lifetime = NumberRange.new(0.45, 0.9),
				Speed = NumberRange.new(9, 17),
				SpreadAngle = Vector2.new(12, 22),
				EmissionDirection = Enum.NormalId.Front,
				Acceleration = Vector3.new(0, -48, 0),
				Drag = 1.2,
				Rotation = NumberRange.new(0, 360),
			})
		end
	end

	local bow = point("Proa")
	if bow then
		self.emitters.Proa = emitter(bow, {
			Color = ColorSequence.new(Color3.fromRGB(244, 250, 252)),
			Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.6), NumberSequenceKeypoint.new(1, 3) }),
			Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.15), NumberSequenceKeypoint.new(1, 1) }),
			Lifetime = NumberRange.new(0.5, 1),
			Speed = NumberRange.new(6, 14),
			SpreadAngle = Vector2.new(70, 30),
			EmissionDirection = Enum.NormalId.Top,
			Acceleration = Vector3.new(0, -40, 0),
			Drag = 1.5,
		})
		self.emitters.Areia = emitter(bow, {
			Color = ColorSequence.new(Color3.fromRGB(196, 178, 140)),
			Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.5), NumberSequenceKeypoint.new(1, 2.2) }),
			Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.3), NumberSequenceKeypoint.new(1, 1) }),
			Lifetime = NumberRange.new(0.5, 1.1),
			Speed = NumberRange.new(3, 8),
			SpreadAngle = Vector2.new(80, 40),
			EmissionDirection = Enum.NormalId.Top,
			Acceleration = Vector3.new(0, -30, 0),
		})
	end

	local exhaust = point("Escapamento")
	if exhaust then
		self.emitters.Escapamento = emitter(exhaust, {
			Color = ColorSequence.new(Color3.fromRGB(150, 150, 150), Color3.fromRGB(95, 95, 98)),
			Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.4), NumberSequenceKeypoint.new(1, 2.4) }),
			Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.7), NumberSequenceKeypoint.new(1, 1) }),
			Lifetime = NumberRange.new(1, 1.8),
			Speed = NumberRange.new(1, 2.5),
			SpreadAngle = Vector2.new(20, 20),
			EmissionDirection = Enum.NormalId.Top,
			Acceleration = Vector3.new(0, 2, 0),
			Drag = 1,
		})
	end

	local soundPoint = point("SomMotor") or frame
	local engine = loopSound(soundPoint, SOUNDS.Motor, 260)
	if engine then
		self.sounds.Motor = engine
	end
	local water = loopSound(frame, SOUNDS.Agua, 120)
	if water then
		self.sounds.Agua = water
	end
	local scrape = loopSound(frame, SOUNDS.Raspando, 80)
	if scrape then
		self.sounds.Raspando = scrape
	end
	for _, s in self.sounds do
		table.insert(self.instances, s)
	end
	for _, e in self.emitters do
		table.insert(self.instances, e)
	end

	-- Partida (motor de arranque) e motor morrendo, pelos Attributes que o
	-- servidor controla.
	table.insert(self.connections, model:GetAttributeChangedSignal("DandoPartida"):Connect(function()
		if model:GetAttribute("DandoPartida") == true then
			oneShot(soundPoint, SOUNDS.Partida, 0.9, 1)
			local smoke = self.emitters.Escapamento
			if smoke then
				smoke:Emit(6)
			end
		end
	end))
	table.insert(self.connections, model:GetAttributeChangedSignal("MotorLigado"):Connect(function()
		local on = model:GetAttribute("MotorLigado") == true
		local smoke = self.emitters.Escapamento
		if on and smoke then
			smoke:Emit(14) -- baforada do motor pegando
		elseif not on and self.engineWasOn then
			oneShot(soundPoint, SOUNDS.Morreu, 0.9, 1)
		end
		self.engineWasOn = on
	end))
	table.insert(self.connections, model:GetAttributeChangedSignal("Encalhado"):Connect(function()
		if model:GetAttribute("Encalhado") == true then
			local sand = self.emitters.Areia
			if sand then
				sand:Emit(28)
			end
			oneShot(frame, SOUNDS.Batida, 0.7, 0.6)
		end
	end))
	return self
end

-- Telemetria de quem não pilota: estimada pelo corpo replicado.
local function estimate(self: Handle): Telemetry
	local velocity = self.root.AssemblyLinearVelocity
	local forward = flat(self.frame.WorldCFrame.LookVector)
	local speed = velocity:Dot(forward)
	local absSpeed = math.abs(speed)
	local engineOn = self.model:GetAttribute("MotorLigado") == true
	local span = math.max(CFG.PlaneioCompleto - CFG.InicioPlaneio, 1)
	return {
		speed = speed,
		planing = smoothstep((absSpeed - CFG.InicioPlaneio) / span),
		rpm = if engineOn then 0.2 + 0.8 * math.clamp(absSpeed / CFG.VelocidadeMax, 0, 1) else 0,
		throttle = if engineOn then math.clamp(absSpeed / CFG.VelocidadeMax, 0, 1) else 0,
		steer = 0,
		surface = (self.model:GetAttribute("Superficie") :: string?) or "Agua",
	}
end

function BoatEffects.Splash(self: Handle, strength: number)
	local bow = self.emitters.Proa
	if bow then
		bow:Emit(math.floor(10 + 22 * strength))
	end
	oneShot(self.frame, SOUNDS.Batida, 0.35 + 0.5 * strength, 0.85 + 0.3 * math.random())
end

--[[
	Update(dt, telemetry?) -> boolean
	true quando houve uma "batida" de onda neste frame (a câmera do piloto
	usa pra dar o tranco).
]]
function BoatEffects.Update(self: Handle, dt: number, telemetry: Telemetry?): boolean
	if not self.root.Parent then
		return false
	end
	local camera = Workspace.CurrentCamera
	if camera and (camera.CFrame.Position - self.root.Position).Magnitude > ACTIVE_DISTANCE then
		for _, e in self.emitters do
			e.Rate = 0
		end
		if self.trail then
			self.trail.Enabled = false
		end
		for _, s in self.sounds do
			s.Volume = 0
		end
		return false
	end

	local t = telemetry or estimate(self)
	local absSpeed = math.abs(t.speed)
	local speedRatio = math.clamp(absSpeed / CFG.VelocidadeMax, 0, 1)
	local anchoredScene = self.root.Anchored and self.model:GetAttribute("Escapando") == true
	local onWater = t.surface ~= "Encalhado"
	local engineOn = self.model:GetAttribute("MotorLigado") == true

	if self.trail then
		self.trail.Enabled = onWater and absSpeed > 2.5
	end
	local foam = if onWater then math.clamp((absSpeed - 1.5) / 20, 0, 1) else 0
	for _, key in { "EsteiraBB", "EsteiraBE" } do
		local e = self.emitters[key]
		if e then
			e.Rate = 26 * foam
		end
	end
	local wash = self.emitters.Helice
	if wash then
		wash.Rate = if onWater and engineOn then 4 + 38 * math.max(t.throttle, speedRatio * 0.6) else 0
	end

	-- Spray: só planando; o lado de fora da curva joga mais água.
	local spray = if onWater then t.planing * speedRatio else 0
	local sprayLeft, sprayRight = self.emitters.SprayBB, self.emitters.SprayBE
	if sprayLeft then
		sprayLeft.Rate = 70 * spray * (1 + 0.6 * math.max(t.steer, 0))
	end
	if sprayRight then
		sprayRight.Rate = 70 * spray * (1 + 0.6 * math.max(-t.steer, 0))
	end

	local exhaust = self.emitters.Escapamento
	if exhaust then
		exhaust.Rate = if engineOn then 3 + 10 * t.rpm else 0
	end
	local sand = self.emitters.Areia
	if sand then
		sand.Rate = if t.surface ~= "Agua" and absSpeed > 4 then 30 * speedRatio else 0
	end

	-- Batidas no picado: aleatório, mais frequente quanto mais rápido. Na
	-- cena de fuga também (o barco segue batendo nas ondas).
	local slammed = false
	self.chopClock += dt
	if onWater and speedRatio > 0.45 and self.chopClock - self.lastSlam > 0.55 then
		local chance = (speedRatio - 0.45) * 2.2 * dt * 3
		if math.random() < chance then
			self.lastSlam = self.chopClock
			BoatEffects.Splash(self, speedRatio)
			slammed = true
		end
	end
	if not anchoredScene and self.lastSpeed > 20 and absSpeed < self.lastSpeed - 12 then
		-- Freada brusca / batida em algo: esguicho na proa.
		BoatEffects.Splash(self, 1)
		slammed = true
	end
	self.lastSpeed = absSpeed

	local engine = self.sounds.Motor
	if engine then
		engine.Volume = if engineOn then 0.35 + 0.55 * t.rpm else 0
		engine.PlaybackSpeed = 0.72 + 0.95 * t.rpm
	end
	local water = self.sounds.Agua
	if water then
		water.Volume = if onWater then 0.08 + 0.7 * speedRatio else 0
		water.PlaybackSpeed = 0.7 + 0.5 * speedRatio
	end
	local scrape = self.sounds.Raspando
	if scrape then
		scrape.Volume = if t.surface ~= "Agua" and absSpeed > 3 then 0.6 * speedRatio + 0.2 else 0
	end
	return slammed
end

function BoatEffects.Destroy(self: Handle)
	for _, c in self.connections do
		c:Disconnect()
	end
	for _, i in self.instances do
		i:Destroy()
	end
	table.clear(self.connections)
	table.clear(self.instances)
end

--------------------------------------------------------------------------------
-- Boias do limite
--------------------------------------------------------------------------------

local buoyBase: { [Model]: CFrame } = setmetatable({}, { __mode = "k" }) :: any
local buoyClock = 0

--[[
	UpdateBuoys(dt)
	Balanço e pisca das boias perto da câmera. Ancoradas no servidor; o
	movimento é só local (PivotTo em cima da pose original).
]]
function BoatEffects.UpdateBuoys(dt: number)
	buoyClock += dt
	local camera = Workspace.CurrentCamera
	local ilha = Workspace:FindFirstChild("Ilha")
	local ring = ilha and ilha:FindFirstChild("LimiteFuga")
	if not camera or not ring then
		return
	end
	local eye = camera.CFrame.Position
	for _, buoy in ring:GetChildren() do
		if not buoy:IsA("Model") or not buoy.PrimaryPart then
			continue
		end
		local base = buoyBase[buoy]
		if not base then
			base = buoy:GetPivot()
			buoyBase[buoy] = base
		end
		if (base.Position - eye).Magnitude > BUOY_DISTANCE then
			continue
		end
		local phase = (buoy:GetAttribute("Fase") :: number?) or 0
		local heave = 0.28 * math.sin(buoyClock * 1.35 + phase)
		local tiltX = math.rad(4) * math.sin(buoyClock * 1.1 + phase * 1.3)
		local tiltZ = math.rad(4) * math.cos(buoyClock * 0.9 + phase)
		buoy:PivotTo(base * CFrame.new(0, heave, 0) * CFrame.Angles(tiltX, 0, tiltZ))
		local lamp = buoy:FindFirstChild("Lanterna")
		if lamp and lamp:IsA("BasePart") then
			-- Pisca rápido a cada 1,6s, fora de fase entre vizinhas.
			local on = ((buoyClock + phase * 0.13) % 1.6) < 0.35
			lamp.Material = if on then Enum.Material.Neon else Enum.Material.SmoothPlastic
			local light = lamp:FindFirstChildOfClass("PointLight")
			if light then
				light.Enabled = on
			end
		end
	end
end

--[[
	InScene(model) -> boolean
	O barco está na cena de fuga (servidor ancorou + Escapando).
]]
function BoatEffects.InScene(model: Model): boolean
	local root = model.PrimaryPart
	return root ~= nil and root.Anchored and model:GetAttribute("Escapando") == true
end

return BoatEffects
