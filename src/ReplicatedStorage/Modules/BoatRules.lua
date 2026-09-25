--!strict
--[[
	BoatRules
	Regras PURAS do barco de fuga (docs/Barco.md): física na água, ondas,
	encalhe, conserto, limite do mapa, validação de movimento e a trajetória
	da cena de fuga. Nenhuma Instance -- só números --, então roda igual no
	servidor (barco sem piloto), no cliente do piloto (dono da física) e nos
	testes (tests/boat.luau). `cfg` é sempre GameConfig.Boat.

	CONVENÇÕES (as mesmas do CFrame do Roblox)
	  speed    velocidade ao longo da proa, studs/s; + = pra frente
	  lateral  deslize de lado, studs/s; + = pra direita
	  yawRate  rad/s em volta do Y do mundo; + = virando pra ESQUERDA
	           (CFrame.Angles(0, +a, 0) leva a LookVector pra -X)
	  steer    -1..1; + = pra DIREITA (igual VehicleSeat.SteerFloat)
	  pitch    graus; + = proa pra cima
	  roll     graus; + = deita pra ESQUERDA (CFrame.Angles(0, 0, +a))

	O QUE FAZ UM BARCO PARECER BARCO (e não um carro sem rodas)
	  - Nada é instantâneo: acelera com empuxo que cai perto do máximo,
	    desacelera pelo arrasto da água (base + proporcional à velocidade) e o leme leva um
	    instante pra responder.
	  - Curva DESLIZA: a proa gira antes do casco mudar de rumo. A velocidade
	    medida é reprojetada na proa nova a cada passo, então parte dela vira
	    deslize lateral, que a aderência do casco vai matando.
	  - Parado quase não gira (só o empuxo do motor de popa vira o barco);
	    muito rápido, o raio de curva abre.
	  - Arrancada levanta a proa, o casco sobe quando plana, deita pra dentro
	    da curva e bate nas ondas em alta.
]]

local BoatRules = {}

export type Surface = "Agua" | "Raso" | "Encalhado"

export type Sim = {
	speed: number,
	lateral: number,
	yawRate: number,
	planing: number, -- 0..1, suavizado
	pitch: number, -- graus, sem as ondas
	roll: number, -- graus, sem as ondas
	rpm: number, -- 0..1, carga do motor (som)
	lift: number, -- studs que o casco sobe planando
}

export type Input = {
	throttle: number, -- -1..1
	steer: number, -- -1..1
	engineOn: boolean,
	surface: Surface,
}

export type Requirements = {
	HeliceInstalada: boolean,
	VelaInstalada: boolean,
	Abastecido: boolean,
	ChaveInserida: boolean,
}

-- Ordem em que a HUD e as mensagens listam o que falta.
BoatRules.Steps = {
	{ key = "HeliceInstalada", label = "Hélice" },
	{ key = "VelaInstalada", label = "Vela de ignição" },
	{ key = "Abastecido", label = "Gasolina" },
	{ key = "ChaveInserida", label = "Chave" },
}

local function smoothstep(t: number): number
	t = math.clamp(t, 0, 1)
	return t * t * (3 - 2 * t)
end

-- Aproximação exponencial independente de frame rate.
local function follow(current: number, target: number, rate: number, dt: number): number
	return target + (current - target) * math.exp(-rate * dt)
end

local function approach(current: number, target: number, step: number): number
	if current < target then
		return math.min(target, current + step)
	end
	return math.max(target, current - step)
end

local function finite(value: number, fallback: number): number
	if value ~= value or value == math.huge or value == -math.huge then
		return fallback
	end
	return value
end

function BoatRules.NewSim(): Sim
	return { speed = 0, lateral = 0, yawRate = 0, planing = 0, pitch = 0, roll = 0, rpm = 0, lift = 0 }
end

--------------------------------------------------------------------------------
-- Física na água
--------------------------------------------------------------------------------

--[[
	Drive(sim, input, measuredSpeed, measuredLateral, dt, cfg) -> Sim
	Um passo de física. Começa SEMPRE da velocidade medida no corpo (depois
	das colisões): bateu numa pedra, a velocidade que sobrou é a de verdade,
	e o motor só volta a empurrar a partir dela. Devolve um Sim novo; quem
	chama converte speed/lateral/yawRate em velocidade de mundo e pitch/roll
	em orientação alvo.
]]
function BoatRules.Drive(sim: Sim, input: Input, measuredSpeed: number, measuredLateral: number, dt: number, cfg: any): Sim
	dt = math.clamp(finite(dt, 0), 0, 0.1)
	local surface = input.surface
	local grounded = surface == "Encalhado"
	local running = input.engineOn and not grounded
	local throttle = if running then math.clamp(finite(input.throttle, 0), -1, 1) else 0
	local steer = math.clamp(finite(input.steer, 0), -1, 1)

	local speed = finite(measuredSpeed, 0)
	local lateral = finite(measuredLateral, 0)
	local maxSpeed = cfg.VelocidadeMax * (if surface == "Raso" then cfg.FatorRaso else 1)

	if throttle > 0.02 then
		local target = maxSpeed * throttle
		if speed < -0.5 then
			-- Ainda indo de ré: o motor primeiro freia o barco.
			speed = math.min(0, speed + cfg.Frenagem * throttle * dt)
		elseif speed < target then
			-- Empuxo cai perto do máximo: arranca forte, chega devagar no topo.
			local ratio = math.clamp(speed / math.max(maxSpeed, 1), 0, 1)
			local taper = 1 - 0.7 * ratio * ratio
			speed = math.min(target, speed + cfg.Aceleracao * throttle * taper * dt)
		else
			-- Acima do pedido (soltou um pouco o acelerador ou entrou no raso).
			local drag = (cfg.ArrastoBase + cfg.ArrastoProporcional * speed) * dt
			speed = math.max(target, speed - drag)
		end
	elseif throttle < -0.02 then
		local amount = -throttle
		if speed > 0.5 then
			speed = math.max(0, speed - cfg.Frenagem * amount * dt)
		else
			speed = math.max(-cfg.VelocidadeRe * amount, speed - cfg.AceleracaoRe * amount * dt)
		end
	else
		local drag = (cfg.ArrastoBase + cfg.ArrastoProporcional * math.abs(speed)) * dt
		speed = approach(speed, 0, drag)
	end

	if surface == "Raso" then
		speed *= math.exp(-cfg.ArrastoRaso * dt)
	elseif grounded then
		speed *= math.exp(-cfg.ArrastoAreia * dt)
		lateral *= math.exp(-cfg.ArrastoAreia * dt)
	end

	-- Aderência do casco: o deslize lateral morre sozinho.
	lateral *= math.exp(-cfg.Aderencia * dt)

	-- Leme / empuxo vetorizado do motor de popa.
	local absSpeed = math.abs(speed)
	local authority = 0
	if not grounded then
		local ideal = math.max(cfg.VelocidadeGiroIdeal, 1)
		authority = cfg.GiroParado + (1 - cfg.GiroParado) * math.clamp(absSpeed / ideal, 0, 1)
		local high = math.clamp((absSpeed - ideal) / math.max(cfg.VelocidadeMax - ideal, 1), 0, 1)
		authority *= 1 - cfg.PerdaGiroAlta * high
		if not running then
			-- Motor desligado: sem empuxo pra vetorizar, só o leme com o
			-- barco ainda andando.
			authority *= math.clamp(absSpeed / 12, 0, 1)
		end
	end
	local direction = if speed < -0.5 then -1 else 1 -- de ré o volante inverte
	local targetYaw = -steer * math.rad(cfg.GiroMax) * authority * direction
	local yawRate = approach(sim.yawRate, targetYaw, cfg.RespostaGiro * dt)
	if grounded then
		yawRate = follow(yawRate, 0, 8, dt)
	end

	-- Planeio e atitude.
	local planeSpan = math.max(cfg.PlaneioCompleto - cfg.InicioPlaneio, 1)
	local planingTarget = if grounded then 0 else smoothstep((absSpeed - cfg.InicioPlaneio) / planeSpan)
	local planing = follow(sim.planing, planingTarget, 1.8, dt)

	local accel = if dt > 0 then (speed - measuredSpeed) / dt else 0
	local pitchTarget = 0
	if not grounded then
		-- Arrancada: a proa sobe enquanto o casco ainda não planou.
		if throttle > 0.15 and speed > 0 then
			local hump = math.sin(math.clamp((speed - 2) / math.max(cfg.PlaneioCompleto - 2, 1), 0, 1) * math.pi)
			pitchTarget += cfg.ProaArrancada * throttle * hump
		end
		pitchTarget += cfg.TrimPlaneio * planing
		-- Frear/cortar o motor afunda a proa (a onda de popa alcança o barco).
		pitchTarget += math.clamp(accel * 0.12, -3.5, 1.5)
		if surface == "Raso" then
			pitchTarget += 2 -- proa subindo no banco de areia
		end
	end
	local pitch = follow(sim.pitch, pitchTarget, 2.6, dt)

	local bank = -steer * cfg.InclinacaoCurva * math.clamp(absSpeed / 30, 0, 1)
	local roll = follow(sim.roll, if grounded then 0 else bank, 2.2, dt)

	local rpmTarget = 0
	if input.engineOn then
		rpmTarget = 0.18 + 0.82 * math.max(math.abs(throttle), 0.9 * absSpeed / math.max(cfg.VelocidadeMax, 1))
		if surface == "Raso" and throttle > 0 then
			rpmTarget *= 0.75 -- hélice mordendo areia
		end
	end
	local rpm = follow(sim.rpm, math.clamp(rpmTarget, 0, 1), 4.5, dt)

	return {
		speed = speed,
		lateral = lateral,
		yawRate = yawRate,
		planing = planing,
		pitch = pitch,
		roll = roll,
		rpm = rpm,
		lift = cfg.ElevacaoPlaneio * planing,
	}
end

--[[
	Waves(t, phase, speed, cfg) -> (heave, pitchDeg, rollDeg)
	Mar calmo: duas ondulações longas somadas (arfagem, caturro e balanço
	fora de fase, pra nunca repetir o mesmo movimento) + o "picado" do casco
	batendo nas ondas quando anda rápido.
]]
function BoatRules.Waves(t: number, phase: number, speed: number, cfg: any): (number, number, number)
	local period = math.max(cfg.OndaPeriodo, 0.5)
	local w1 = 2 * math.pi / period
	local w2 = w1 * 1.63
	local a = t * w1 + phase
	local b = t * w2 + phase * 1.7
	local heave = cfg.OndaAltura * (0.65 * math.sin(a) + 0.35 * math.sin(b))
	local pitch = cfg.OndaCaturro * (0.7 * math.cos(a) + 0.3 * math.sin(b * 1.1))
	local roll = cfg.OndaBalanco * (0.6 * math.sin(a * 0.83 + 1.3) + 0.4 * math.cos(b * 0.71))

	-- Frequência de encontro com as ondas sobe com a velocidade.
	local fast = math.clamp((math.abs(speed) - 18) / 30, 0, 1)
	if fast > 0 then
		local f = 2 * math.pi * (0.9 + math.abs(speed) / 26)
		local chop = math.sin(t * f + phase) * math.sin(t * f * 0.37 + 0.6)
		pitch += cfg.OndaPicado * fast * chop
		heave += 0.12 * fast * chop
	end
	-- Em velocidade o balanço longo some (o casco corta a onda).
	roll *= 1 - 0.5 * fast
	return heave, pitch, roll
end

--------------------------------------------------------------------------------
-- Encalhe
--------------------------------------------------------------------------------

--[[
	Classify(center, bow, stern, draft) -> Surface
	Profundidade da água (studs) no meio, na proa e na popa; nil = terra
	firme nesse ponto (sem água em cima). Meio sem água, ou tão raso que o
	casco assenta, é ENCALHADO: igual na vida real, o hélice sai da água e o
	motor morre. Só a proa ou a popa raspando é RASO: anda, mas devagar.
]]
function BoatRules.Classify(center: number?, bow: number?, stern: number?, draft: number): Surface
	if center == nil or center < draft * 0.55 then
		return "Encalhado"
	end
	if bow == nil or bow < draft or stern == nil or stern < draft * 0.8 then
		return "Raso"
	end
	return "Agua"
end

--------------------------------------------------------------------------------
-- Conserto
--------------------------------------------------------------------------------

function BoatRules.Missing(state: Requirements): { string }
	local missing = {}
	for _, step in BoatRules.Steps do
		if (state :: any)[step.key] ~= true then
			table.insert(missing, step.label)
		end
	end
	return missing
end

function BoatRules.IsRepaired(state: Requirements): boolean
	return state.HeliceInstalada == true and state.VelaInstalada == true and state.Abastecido == true
end

--[[
	StartBlocked(state, context) -> string?
	"Por que o motor não pega", em uma frase, ou nil se pode dar partida.
	`hasKey` = a chave está na ignição OU no inventário de quem pilota (ao
	dar partida ela vai pra ignição).
]]
function BoatRules.StartBlocked(state: Requirements, context: {
	hasKey: boolean,
	sabotaged: boolean,
	surface: Surface,
	escaping: boolean,
}): string?
	if context.escaping then
		return "O barco já está saindo."
	end
	if state.HeliceInstalada ~= true or state.VelaInstalada ~= true then
		local missing = {}
		if state.HeliceInstalada ~= true then table.insert(missing, "a hélice") end
		if state.VelaInstalada ~= true then table.insert(missing, "a vela de ignição") end
		return "Falta instalar " .. table.concat(missing, " e ") .. " no motor."
	end
	if state.Abastecido ~= true then
		return "Tanque vazio. Abasteça com Gasolina."
	end
	if state.ChaveInserida ~= true and not context.hasKey then
		return "Sem a chave do barco, o motor não liga."
	end
	if context.sabotaged then
		return "A fiação do motor foi cortada. Repare antes de dar partida."
	end
	if context.surface == "Encalhado" then
		return "Encalhado: empurre o barco de volta pra água funda."
	end
	return nil
end

--[[
	EngineNoiseRadius(speedRatio, cfg) -> studs
	Alcance do ping do motor pra super audição do Monstro: marcha lenta já é
	ouvida longe; acelerando tudo, bem mais. `speedRatio` = velocidade / máx.
]]
function BoatRules.EngineNoiseRadius(speedRatio: number, cfg: any): number
	local ratio = math.clamp(finite(speedRatio, 0), 0, 1)
	return cfg.RuidoRaioLento + (cfg.RuidoRaioMaximo - cfg.RuidoRaioLento) * ratio
end

--------------------------------------------------------------------------------
-- Limite do mapa e validação
--------------------------------------------------------------------------------

-- Studs que faltam até o anel de chegada (<= 0 = cruzou).
function BoatRules.DistanceToFinish(x: number, z: number, radius: number): number
	return radius - math.sqrt(x * x + z * z)
end

--[[
	MoveIsPlausible(horizontal, vertical, dt, cfg) -> boolean
	O dono da física é o cliente do piloto: o servidor confere que o barco
	não andou mais do que o motor consegue no intervalo. A folga cobre rajada
	de replicação (vários pacotes chegando juntos).
]]
function BoatRules.MoveIsPlausible(horizontal: number, vertical: number, dt: number, cfg: any): boolean
	if horizontal ~= horizontal or vertical ~= vertical then
		return false
	end
	local limit = cfg.VelocidadeMax * cfg.ValidacaoFolga * math.max(dt, 0) + cfg.FolgaReplicacao
	return horizontal <= limit and math.abs(vertical) <= limit
end

--------------------------------------------------------------------------------
-- Cena de fuga
--------------------------------------------------------------------------------

local function easeInOutSine(t: number): number
	t = math.clamp(t, 0, 1)
	return -(math.cos(math.pi * t) - 1) / 2
end

--[[
	EscapeTravel(t, startSpeed, cfg) -> studs percorridos
	O barco continua reto pro mar aberto: mantém a velocidade que tinha ao
	cruzar o limite e acelera até o máximo (piloto "abrindo tudo" na saída).
]]
function BoatRules.EscapeTravel(t: number, startSpeed: number, cfg: any): number
	t = math.max(t, 0)
	local top = cfg.VelocidadeMax
	local v0 = math.clamp(startSpeed, top * 0.55, top)
	local rampTime = 2.5
	if t <= rampTime then
		return v0 * t + 0.5 * ((top - v0) / rampTime) * t * t
	end
	return v0 * rampTime + 0.5 * (top - v0) * rampTime + top * (t - rampTime)
end

--[[
	EscapeCamera(t, duration) -> (anchor, back, height, side)
	Enquadramento da câmera, em frações e studs, no referencial da proa no
	instante em que o barco cruzou o limite:
	  anchor  fração da distância do BARCO que a câmera acompanha (1 = colada
	          atrás dele; cai pra deixar o barco ir embora)
	  back    studs atrás desse ponto
	  height  studs acima da água
	  side    deslocamento lateral (paralaxe da grua)
	Começa como a câmera de perseguição e vira uma grua que sobe e se afasta
	enquanto o barco segue sozinho pro horizonte.
]]
function BoatRules.EscapeCamera(t: number, duration: number): (number, number, number, number)
	local span = math.max(duration, 1)
	local lift = easeInOutSine((t - 0.6) / (span - 1.4))
	local anchor = 1 - 0.78 * easeInOutSine((t - 0.9) / (span - 1.8))
	local back = 24 + 34 * lift
	local height = 8 + 92 * lift
	local side = 9 * math.sin(math.clamp(t / span, 0, 1) * math.pi * 0.85)
	return anchor, back, height, side
end

return BoatRules
