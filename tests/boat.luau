--!nocheck
-- Regras puras do barco de fuga (Modules/BoatRules.lua) contra a GameConfig
-- real. Física do engine, render e rede ficam pro playtest do docs/Barco.md.
for name, source in sources do assert(loadstring(source, name)) end
loadstring(sources.Stub, "Stub")()
local Config = loadstring(sources.GameConfig, "GameConfig")()
local Rules = loadstring(sources.BoatRules, "BoatRules")()
local CFG = Config.Boat

local checks = 0
local function check(condition, message)
	checks += 1
	if not condition then
		error("FAIL: " .. message, 2)
	end
end
local function near(a, b, tolerance)
	return math.abs(a - b) <= tolerance
end

-- Simula `seconds` com passo fixo; o corpo obedece a velocidade pedida
-- (o LinearVelocity tem força de sobra), então a medida é o próprio sim.
local function run(sim, input, seconds, dt)
	local t = 0
	while t < seconds - 1e-9 do
		sim = Rules.Drive(sim, input, sim.speed, sim.lateral, dt, CFG)
		t += dt
	end
	return sim
end
local function water(throttle, steer, engineOn)
	return { throttle = throttle, steer = steer or 0, engineOn = engineOn ~= false, surface = "Agua" }
end

-- Arrancada: sobe rápido, chega perto do máximo e nunca passa dele.
do
	local sim = run(Rules.NewSim(), water(1), 2, 1 / 60)
	check(sim.speed > CFG.VelocidadeMax * 0.35, "acelera forte saindo da inércia")
	local peakPitch = 0
	local s = Rules.NewSim()
	for _ = 1, 60 * 12 do
		s = Rules.Drive(s, water(1), s.speed, s.lateral, 1 / 60, CFG)
		peakPitch = math.max(peakPitch, s.pitch)
		check(s.speed <= CFG.VelocidadeMax + 1e-6, "nunca passa da velocidade máxima")
	end
	check(s.speed > CFG.VelocidadeMax * 0.93, "chega perto do máximo em 12s")
	check(peakPitch > CFG.TrimPlaneio + 2, "proa sobe na arrancada (hole shot)")
	check(near(s.pitch, CFG.TrimPlaneio * s.planing, 1.2), "planando, a proa assenta no trim")
	check(s.planing > 0.95 and near(s.lift, CFG.ElevacaoPlaneio, 0.03), "casco plana e sobe")
	check(s.rpm > 0.9, "rotação alta em aceleração total")
end

-- Sem acelerador: o arrasto da água desacelera sem inverter o sentido.
do
	local sim = Rules.NewSim()
	sim.speed = CFG.VelocidadeMax
	local after = run(sim, water(0), 6, 1 / 60)
	check(after.speed >= 0 and after.speed < CFG.VelocidadeMax * 0.35, "desacelera sozinho sem ir pra ré")
	local stopped = run(after, water(0), 40, 1 / 60)
	check(stopped.speed == 0, "acaba parando")
end

-- Ré puxada com o barco andando freia primeiro; parado, dá ré até o limite.
do
	local sim = Rules.NewSim()
	sim.speed = 40
	local braking = Rules.Drive(sim, water(-1), 40, 0, 0.1, CFG)
	check(braking.speed < 40 and braking.speed >= 0, "ré com o barco andando é freio")
	local reverse = run(Rules.NewSim(), water(-1), 8, 1 / 60)
	check(near(reverse.speed, -CFG.VelocidadeRe, 0.01), "ré limitada a VelocidadeRe")
end

-- Motor desligado: acelerador não faz nada.
do
	local sim = run(Rules.NewSim(), water(1, 0, false), 3, 1 / 60)
	check(sim.speed == 0 and sim.rpm < 0.01, "sem motor não anda")
end

-- ENCALHADO: igual na vida real, o motor não empurra e a areia segura.
do
	local sim = Rules.NewSim()
	sim.speed, sim.yawRate, sim.pitch, sim.roll = 45, -0.8, 6, -7
	local beached = run(sim, { throttle = 1, steer = 1, engineOn = true, surface = "Encalhado" }, 1.5, 1 / 60)
	check(beached.speed < 45 * 0.05, "arrastando na areia para em ~1s mesmo acelerando")
	check(math.abs(beached.yawRate) < 0.01, "encalhado não gira")
	-- Na areia a física ignora caturro/balanço (a gravidade assenta o casco);
	-- aqui só confere que a memória deles zera e não fica "planando".
	check(math.abs(beached.pitch) < 0.5 and math.abs(beached.roll) < 0.5, "sem atitude de navegação na areia")
	check(beached.planing < 0.1, "não plana fora d'água")
	local stuck = run(Rules.NewSim(), { throttle = 1, steer = 0, engineOn = true, surface = "Encalhado" }, 5, 1 / 60)
	check(stuck.speed == 0, "parado na areia não sai do lugar com o acelerador")
end

-- Raso: raspando o fundo anda bem devagar.
do
	local shallow = run(Rules.NewSim(), { throttle = 1, steer = 0, engineOn = true, surface = "Raso" }, 15, 1 / 60)
	check(shallow.speed <= CFG.VelocidadeMax * CFG.FatorRaso + 1e-6, "raso limita a velocidade")
	check(shallow.pitch > 1, "proa sobe no banco de areia")
end

-- Leme: direita = yaw negativo; parado só o empuxo gira; de ré inverte.
do
	local sim = Rules.NewSim()
	sim.speed = CFG.VelocidadeGiroIdeal
	local turning = run(sim, water(0.5, 1), 2, 1 / 60)
	check(turning.yawRate < 0, "volante pra direita vira pra direita (yaw negativo)")
	check(near(turning.yawRate, -math.rad(CFG.GiroMax), 0.12), "giro máximo na velocidade ideal")
	check(turning.roll < -CFG.InclinacaoCurva * 0.5, "deita pra dentro da curva")

	local still = run(Rules.NewSim(), water(0, 1), 2, 1 / 60)
	check(near(math.abs(still.yawRate), math.rad(CFG.GiroMax) * CFG.GiroParado, 0.02), "parado gira pouco (empuxo do motor)")
	local dead = run(Rules.NewSim(), water(0, 1, false), 2, 1 / 60)
	check(math.abs(dead.yawRate) < 1e-6, "parado e sem motor não gira")

	local back = Rules.NewSim()
	back.speed = -8
	local reversing = Rules.Drive(back, water(-0.2, 1), -8, 0, 0.1, CFG)
	check(reversing.yawRate > 0, "de ré o volante inverte")

	local fast = Rules.NewSim()
	fast.speed = CFG.VelocidadeMax
	local wide = run(fast, water(1, 1), 2, 1 / 60)
	check(math.abs(wide.yawRate) < math.abs(turning.yawRate), "muito rápido o raio de curva abre")
end

-- Deslize lateral: morre pela aderência do casco.
do
	local sim = Rules.NewSim()
	sim.lateral = 10
	local after = Rules.Drive(sim, water(0), 0, 10, 0.5, CFG)
	-- dt é limitado a 0,1 por passo (um tranco de frame não teleporta o barco).
	check(near(after.lateral, 10 * math.exp(-CFG.Aderencia * 0.1), 1e-6), "aderência com dt limitado")
	local settled = run(sim, water(0), 3, 1 / 60)
	check(math.abs(settled.lateral) < 0.1, "deslize some em 3s")
end

-- Independente do frame rate.
do
	local slow = run(Rules.NewSim(), water(1, 0.3), 5, 1 / 30)
	local fastRate = run(Rules.NewSim(), water(1, 0.3), 5, 1 / 240)
	check(near(slow.speed, fastRate.speed, CFG.VelocidadeMax * 0.03), "velocidade não depende do FPS")
	check(near(slow.yawRate, fastRate.yawRate, 0.05), "giro não depende do FPS")
end

-- Entrada inválida não vira NaN.
do
	local sim = Rules.Drive(Rules.NewSim(), { throttle = 0 / 0, steer = math.huge, engineOn = true, surface = "Agua" }, 0 / 0, 0, 1 / 60, CFG)
	check(sim.speed == sim.speed and sim.yawRate == sim.yawRate, "NaN/inf na entrada viram zero/limite")
end

-- Ondas: limitadas e vivas.
do
	local maxHeave, maxPitch, maxRoll, moved = 0, 0, 0, false
	local first = nil
	for i = 0, 600 do
		local h, p, r = Rules.Waves(i * 0.05, 1.3, 50, CFG)
		maxHeave = math.max(maxHeave, math.abs(h))
		maxPitch = math.max(maxPitch, math.abs(p))
		maxRoll = math.max(maxRoll, math.abs(r))
		first = first or h
		if math.abs(h - first) > 0.05 then moved = true end
	end
	check(moved, "o mar mexe")
	check(maxHeave <= CFG.OndaAltura + 0.12 + 1e-6, "arfagem limitada")
	check(maxPitch <= CFG.OndaCaturro + CFG.OndaPicado + 1e-6, "caturro limitado")
	check(maxRoll <= CFG.OndaBalanco + 1e-6, "balanço limitado")
end

-- Encalhe: classificação pela profundidade (proa, meio, popa).
do
	local d = CFG.Calado
	check(Rules.Classify(nil, 5, 5, d) == "Encalhado", "sem água no meio = encalhado")
	check(Rules.Classify(d * 0.3, 5, 5, d) == "Encalhado", "casco assentado no fundo = encalhado")
	check(Rules.Classify(5, nil, 5, d) == "Raso", "proa na areia = raso")
	check(Rules.Classify(5, d * 0.5, 5, d) == "Raso", "proa raspando = raso")
	check(Rules.Classify(5, 5, d * 0.5, d) == "Raso", "popa raspando = raso")
	check(Rules.Classify(20, 20, 20, d) == "Agua", "água funda = navegando")
end

-- Conserto: ordem, mensagens e a chave no inventário.
do
	local none = { HeliceInstalada = false, VelaInstalada = false, Abastecido = false, ChaveInserida = false }
	local missing = Rules.Missing(none)
	check(#missing == 4 and missing[1] == "Hélice" and missing[4] == "Chave", "lista o que falta na ordem")
	local context = { hasKey = false, sabotaged = false, surface = "Agua", escaping = false }
	check(string.find(Rules.StartBlocked(none, context), "hélice", 1, true) ~= nil, "sem hélice não liga")
	local parts = { HeliceInstalada = true, VelaInstalada = true, Abastecido = false, ChaveInserida = false }
	check(string.find(Rules.StartBlocked(parts, context), "Gasolina", 1, true) ~= nil, "sem gasolina não liga")
	local fueled = { HeliceInstalada = true, VelaInstalada = true, Abastecido = true, ChaveInserida = false }
	check(string.find(Rules.StartBlocked(fueled, context), "chave", 1, true) ~= nil, "sem chave não liga")
	check(Rules.StartBlocked(fueled, { hasKey = true, sabotaged = false, surface = "Agua", escaping = false }) == nil,
		"chave no bolso do piloto basta")
	check(Rules.IsRepaired(fueled) and not Rules.IsRepaired(parts), "montado = hélice + vela + gasolina")
	local ready = { HeliceInstalada = true, VelaInstalada = true, Abastecido = true, ChaveInserida = true }
	check(string.find(Rules.StartBlocked(ready, { hasKey = false, sabotaged = true, surface = "Agua", escaping = false }), "fiação", 1, true) ~= nil,
		"fiação sabotada não liga")
	check(string.find(Rules.StartBlocked(ready, { hasKey = false, sabotaged = false, surface = "Encalhado", escaping = false }), "empurre", 1, true) ~= nil,
		"encalhado não liga")
	check(Rules.StartBlocked(ready, { hasKey = false, sabotaged = false, surface = "Agua", escaping = true }) ~= nil, "saindo não religa")
	check(Rules.StartBlocked(ready, { hasKey = false, sabotaged = false, surface = "Raso", escaping = false }) == nil,
		"raspando o fundo ainda liga")
end

-- Ruído do motor: marcha lenta já é ouvida; acelerando, mais longe.
do
	check(Rules.EngineNoiseRadius(0, CFG) == CFG.RuidoRaioLento, "motor em marcha lenta faz barulho")
	check(Rules.EngineNoiseRadius(1, CFG) == CFG.RuidoRaioMaximo, "acelerando tudo, alcance máximo")
	check(Rules.EngineNoiseRadius(0.5, CFG) > CFG.RuidoRaioLento and Rules.EngineNoiseRadius(0.5, CFG) < CFG.RuidoRaioMaximo, "meio acelerador, meio alcance")
	check(Rules.EngineNoiseRadius(9, CFG) == CFG.RuidoRaioMaximo and Rules.EngineNoiseRadius(0 / 0, CFG) == CFG.RuidoRaioLento, "entrada absurda fica nos limites")
	check(CFG.RuidoRaioMaximo <= Config.Noise.MaxNoiseRadius and CFG.RuidoPartida <= Config.Noise.MaxNoiseRadius, "dentro do teto do NoiseService")
	check(CFG.RuidoIntervalo >= Config.Noise.ActionPingInterval, "intervalo maior que o limite por fonte do NoiseService")
end

-- Limite do mapa e anti-teleporte.
do
	check(Rules.DistanceToFinish(0, 700, CFG.RaioChegada) > 0, "perto da costa ainda falta")
	check(Rules.DistanceToFinish(CFG.RaioChegada * 0.8, CFG.RaioChegada * 0.61, CFG.RaioChegada) <= 0, "fora do anel = cruzou")
	check(CFG.RaioChegada < 952, "anel dentro das paredes invisíveis do mapa")
	local dt = CFG.IntervaloChecagem
	check(Rules.MoveIsPlausible(CFG.VelocidadeMax * dt, 0.5, dt, CFG), "movimento normal passa")
	check(not Rules.MoveIsPlausible(300, 0, dt, CFG), "teleporte até o limite é recusado")
	check(not Rules.MoveIsPlausible(0, 60, dt, CFG), "voar é recusado")
	check(not Rules.MoveIsPlausible(0 / 0, 0, dt, CFG), "NaN é recusado")
end

-- Cena de fuga: o barco segue em frente, sem tranco, e a câmera sobe e se afasta.
do
	local previous, previousStep = -1, nil
	for i = 0, 200 do
		local t = i * 0.05
		local d = Rules.EscapeTravel(t, 30, CFG)
		check(d > previous or (i == 0 and d == 0), "o barco sempre avança")
		if previousStep then
			check(d - previous <= CFG.VelocidadeMax * 0.05 + 1e-6, "nunca acima da velocidade máxima")
		end
		previousStep = d - previous
		previous = d
	end
	local justBefore = Rules.EscapeTravel(2.5 - 1e-4, 30, CFG)
	local justAfter = Rules.EscapeTravel(2.5 + 1e-4, 30, CFG)
	check(near(justBefore, justAfter, 0.02), "sem salto quando a rampa termina")
	check(near(Rules.EscapeTravel(1, 0, CFG), Rules.EscapeTravel(1, CFG.VelocidadeMax * 0.55, CFG), 1e-6),
		"cruzou quase parado: sai com velocidade mínima de cena")

	local duration = CFG.DuracaoCinematica
	local a0, b0, h0 = Rules.EscapeCamera(0, duration)
	local aEnd, bEnd, hEnd = Rules.EscapeCamera(duration, duration)
	check(near(a0, 1, 1e-6) and h0 < 10 and b0 < 30, "começa como câmera de perseguição")
	check(hEnd > 90 and bEnd > b0 and aEnd < 0.3, "termina alta, longe, e o barco seguindo sozinho")
	local lastHeight = -1
	for i = 0, 100 do
		local _, _, h = Rules.EscapeCamera(i / 100 * duration, duration)
		check(h >= lastHeight - 1e-6, "a câmera só sobe")
		lastHeight = h
	end
end

print(string.format("PASS boat: %d checks (física na água, encalhe, conserto, limite e cena de fuga)", checks))
