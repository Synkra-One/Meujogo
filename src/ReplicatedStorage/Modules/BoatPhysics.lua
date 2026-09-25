--!strict
--[[
	BoatPhysics
	Liga as regras puras (BoatRules) ao corpo físico do barco de fuga. Quem
	SIMULA o barco -- o dono de rede do conjunto barco + passageiros --
	chama Step() a cada passo:
	  - o cliente do piloto (BoatController), com acelerador e volante;
	  - o servidor (BoatSystem) quando ninguém pilota, em ponto morto: o
	    barco desacelera sozinho e fica boiando nas ondas.

	ATUADORES (criados pelo servidor em BoatBuilder, no Attachment "Impulso",
	no centro de massa do casco): um LinearVelocity com limite de força POR EIXO
	(horizontal = motor/arrasto, vertical = flutuação) e um AngularVelocity
	(giro + correção de caturro/balanço). Mudar a meta deles no cliente dono
	vale: é o dono quem roda a física do conjunto, e só a posição resultante
	replica -- o mesmo esquema de qualquer veículo do Roblox.

	O QuadroBarco fica na LINHA D'ÁGUA, com LookVector = proa. Tudo aqui é
	medido nele, não na Part raiz (que num barco do mapa pode estar virada
	pra qualquer lado).

	SONDAGEM: três pontos (proa, meio, popa), dois raios cada, só no Terrain.
	O primeiro, enxergando água, acha a superfície; o segundo, atravessando
	a água, acha o fundo. Sem água em cima do ponto = terra firme.
]]

local Workspace = game:GetService("Workspace")

local BoatRules = require(script.Parent.BoatRules)

local BoatPhysics = {}
BoatPhysics.__index = BoatPhysics

export type Env = {
	waterY: number?,
	center: number?,
	bow: number?,
	stern: number?,
	surface: BoatRules.Surface,
}

export type Telemetry = {
	speed: number,
	lateral: number,
	surface: BoatRules.Surface,
	planing: number,
	rpm: number,
	throttle: number,
	steer: number,
	waterY: number?,
}

export type Controller = typeof(setmetatable({} :: {
	model: Model,
	root: BasePart,
	frame: Attachment,
	linear: LinearVelocity,
	angular: AngularVelocity,
	cfg: any,
	sim: BoatRules.Sim,
	clock: number,
	phase: number,
	halfLength: number,
	lastEnv: Env?,
}, BoatPhysics))

-- Nomes compartilhados com BoatBuilder (servidor) e BoatController/Effects.
BoatPhysics.FrameName = "QuadroBarco"
BoatPhysics.LinearName = "ImpulsoLinear"
BoatPhysics.AngularName = "ImpulsoAngular"

-- Ganhos do controle (não são balanceamento, são a "suspensão" do casco).
local VERTICAL_GAIN = 5 -- 1/s: quão rápido o casco volta pra linha d'água
local VERTICAL_MAX = 18 -- studs/s
local ANGULAR_GAIN = 6 -- 1/s: correção de caturro/balanço
local HORIZONTAL_ACCEL = 90 -- studs/s² que o motor/arrasto conseguem impor
local GROUND_ACCEL = 60 -- atrito do casco arrastando na areia
local TORQUE_PER_MASS = 1800
local GROUND_TORQUE_PER_MASS = 40

local surfaceParams = RaycastParams.new()
surfaceParams.FilterType = Enum.RaycastFilterType.Include
surfaceParams.IgnoreWater = false

local floorParams = RaycastParams.new()
floorParams.FilterType = Enum.RaycastFilterType.Include
floorParams.IgnoreWater = true

local function refreshTerrainFilter()
	local terrain = Workspace.Terrain
	surfaceParams.FilterDescendantsInstances = { terrain }
	floorParams.FilterDescendantsInstances = { terrain }
end
refreshTerrainFilter()

--[[
	Probe(point) -> (waterY?, depth?)
	depth nil = terra firme no ponto. Profundidade limitada a 48 studs (mar
	aberto é "fundo o bastante" pra qualquer conta daqui).
]]
function BoatPhysics.Probe(point: Vector3): (number?, number?)
	local hit = Workspace:Raycast(point + Vector3.new(0, 24, 0), Vector3.new(0, -64, 0), surfaceParams)
	if not hit or hit.Material ~= Enum.Material.Water then
		return nil, nil
	end
	local waterY = hit.Position.Y
	local floor = Workspace:Raycast(Vector3.new(point.X, waterY - 0.05, point.Z), Vector3.new(0, -48, 0), floorParams)
	local depth = if floor then waterY - floor.Position.Y else 48
	return waterY, depth
end

local function flatForward(cf: CFrame): Vector3
	local look = cf.LookVector
	local flat = Vector3.new(look.X, 0, look.Z)
	if flat.Magnitude < 1e-3 then
		return Vector3.new(0, 0, -1)
	end
	return flat.Unit
end

--[[
	Bind(model, cfg) -> Controller?
	nil se o modelo ainda não tem os atuadores (no cliente, com streaming, o
	barco pode chegar aos pedaços -- quem chama tenta de novo depois).
]]
function BoatPhysics.Bind(model: Model, cfg: any): Controller?
	local root = model.PrimaryPart
	if not root then
		return nil
	end
	local frame = root:FindFirstChild(BoatPhysics.FrameName)
	local linear = root:FindFirstChild(BoatPhysics.LinearName)
	local angular = root:FindFirstChild(BoatPhysics.AngularName)
	if not frame or not frame:IsA("Attachment") or not linear or not linear:IsA("LinearVelocity")
		or not angular or not angular:IsA("AngularVelocity") then
		return nil
	end
	local length = model:GetAttribute("Comprimento")
	local self = setmetatable({
		model = model,
		root = root,
		frame = frame,
		linear = linear,
		angular = angular,
		cfg = cfg,
		sim = BoatRules.NewSim(),
		clock = 0,
		-- Fase própria de cada barco/cliente: o balanço não sincroniza com o
		-- das boias nem com o de outro barco.
		phase = (model:GetAttribute("FaseOnda") :: number?) or 0,
		halfLength = math.max(((if type(length) == "number" then length else 20) / 2) - 1.5, 2),
		lastEnv = nil,
	}, BoatPhysics)
	return self
end

function BoatPhysics.IsValid(self: Controller): boolean
	return self.root.Parent ~= nil and self.frame.Parent ~= nil and self.linear.Parent ~= nil
		and self.angular.Parent ~= nil and self.model:IsDescendantOf(Workspace)
end

--[[
	Sample() -> Env
	Profundidade na proa, no meio e na popa + a superfície (classificação de
	BoatRules.Classify com o calado configurado).
]]
function BoatPhysics.Sample(self: Controller): Env
	local frameCF = self.frame.WorldCFrame
	local pos = frameCF.Position
	local forward = flatForward(frameCF)
	local waterY, center = BoatPhysics.Probe(pos)
	local _, bow = BoatPhysics.Probe(pos + forward * self.halfLength)
	local _, stern = BoatPhysics.Probe(pos - forward * self.halfLength)
	local env: Env = {
		waterY = waterY,
		center = center,
		bow = bow,
		stern = stern,
		surface = BoatRules.Classify(center, bow, stern, self.cfg.Calado),
	}
	self.lastEnv = env
	return env
end

-- Reinicia a memória do passo (velocidade suavizada, giro, planeio). Usado
-- quando o dono da física muda: o novo dono começa do que o corpo faz agora.
function BoatPhysics.Reset(self: Controller)
	self.sim = BoatRules.NewSim()
end

--[[
	Step(dt, throttle, steer, engineOn, env?) -> Telemetry
	Um passo completo: lê o corpo, roda BoatRules.Drive/Waves e escreve as
	metas nos atuadores. `env` opcional reaproveita uma amostra recente
	(o servidor amostra a 10 Hz pra decidir encalhe; não precisa de outra).
]]
function BoatPhysics.Step(self: Controller, dt: number, throttle: number, steer: number, engineOn: boolean, env: Env?): Telemetry
	local cfg = self.cfg
	local sample = env or BoatPhysics.Sample(self)
	local frameCF = self.frame.WorldCFrame
	local pos = frameCF.Position
	local forward = flatForward(frameCF)
	local right = Vector3.new(-forward.Z, 0, forward.X)
	local velocity = self.root.AssemblyLinearVelocity

	local sim = BoatRules.Drive(self.sim, {
		throttle = throttle,
		steer = steer,
		engineOn = engineOn,
		surface = sample.surface,
	}, velocity:Dot(forward), velocity:Dot(right), dt, cfg)
	self.sim = sim
	self.clock += dt

	local mass = math.max(self.root.AssemblyMass, 1)
	local horizontal = forward * sim.speed + right * sim.lateral

	if self.root.Anchored then
		-- Cena de fuga / empurrão: quem move é o script, não a física.
	elseif sample.surface == "Encalhado" then
		-- Fora d'água: sem flutuação (a gravidade assenta o casco na areia),
		-- sem empuxo, só o atrito arrastando até parar.
		self.linear.MaxAxesForce = Vector3.new(mass * GROUND_ACCEL, 0, mass * GROUND_ACCEL)
		self.linear.VectorVelocity = horizontal
		self.angular.MaxTorque = mass * GROUND_TORQUE_PER_MASS
		self.angular.AngularVelocity = Vector3.new(0, sim.yawRate, 0)
	else
		local heave, wavePitch, waveRoll = BoatRules.Waves(self.clock, self.phase, sim.speed, cfg)
		local waterY = sample.waterY or pos.Y
		local targetY = waterY + sim.lift + heave
		local vy = math.clamp((targetY - pos.Y) * VERTICAL_GAIN, -VERTICAL_MAX, VERTICAL_MAX)
		self.linear.MaxAxesForce = Vector3.new(
			mass * HORIZONTAL_ACCEL,
			mass * (Workspace.Gravity * 2.2 + 160),
			mass * HORIZONTAL_ACCEL
		)
		self.linear.VectorVelocity = horizontal + Vector3.new(0, vy, 0)

		-- Orientação alvo: o rumo ATUAL (o giro vem só do yawRate, então uma
		-- batida que gira o barco não é desfeita) + caturro e balanço.
		local yaw = math.atan2(-forward.X, -forward.Z)
		local target = CFrame.Angles(0, yaw, 0)
			* CFrame.Angles(math.rad(sim.pitch + wavePitch), 0, math.rad(sim.roll + waveRoll))
		local axis, angle = (target * frameCF.Rotation:Inverse()):ToAxisAngle()
		if angle ~= angle or axis.X ~= axis.X then
			angle = 0
		elseif angle > math.pi then
			angle -= 2 * math.pi
		end
		local correction = axis * (angle * ANGULAR_GAIN)
		self.angular.MaxTorque = mass * TORQUE_PER_MASS
		self.angular.AngularVelocity = correction + Vector3.new(0, sim.yawRate, 0)
	end

	return {
		speed = sim.speed,
		lateral = sim.lateral,
		surface = sample.surface,
		planing = sim.planing,
		rpm = sim.rpm,
		throttle = throttle,
		steer = steer,
		waterY = sample.waterY,
	}
end

return BoatPhysics
