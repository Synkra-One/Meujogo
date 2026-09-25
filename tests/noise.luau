-- Actual modules are injected by run_noise.py. Physics/network/rendering need Studio.
local now, active, packets, created, delayed = 0, true, {}, {}, {}
local function signal()
	local s = { listeners = {} }
	function s:Connect(fn)
		local c = { Connected = true, fn = fn }
		function c:Disconnect() self.Connected = false end
		table.insert(self.listeners, c)
		return c
	end
	function s:Fire(...)
		for _, c in table.clone(self.listeners) do if c.Connected then c.fn(...) end end
	end
	function s:Count()
		local count = 0
		for _, c in self.listeners do if c.Connected then count += 1 end end
		return count
	end
	return s
end
local function object(class)
	local o = { ClassName = class, attrs = {}, changes = {}, children = {}, ChildAdded = signal() }
	function o:IsA(c) return c == class or (class == "Part" and c == "BasePart") end
	function o:GetAttribute(k) return self.attrs[k] end
	function o:GetAttributeChangedSignal(k)
		self.changes[k] = self.changes[k] or signal()
		return self.changes[k]
	end
	function o:SetAttribute(k, v)
		if self.attrs[k] == v then return end
		self.attrs[k] = v
		self:GetAttributeChangedSignal(k):Fire()
	end
	function o:FindFirstChild(k) return self.children[k] end
	function o:WaitForChild(k) return assert(self.children[k], k) end
	function o:FindFirstChildOfClass(k)
		for _, c in self.children do if c:IsA(k) then return c end end
	end
	function o:GetChildren() local a = {}; for _, c in self.children do table.insert(a, c) end; return a end
	function o:Destroy() self.Parent = nil; self.destroyed = true end
	if class == "BindableEvent" then
		o.Event = signal()
		function o:Fire(...) self.Event:Fire(...) end
	end
	table.insert(created, o)
	return o
end
local vectorMeta = {}
local function vec(x, y, z) return setmetatable({ X = x, Y = y or 0, Z = z or 0 }, vectorMeta) end
vectorMeta.__sub = function(a, b) return vec(a.X-b.X, a.Y-b.Y, a.Z-b.Z) end
vectorMeta.__add = function(a, b) return vec(a.X+b.X, a.Y+b.Y, a.Z+b.Z) end
vectorMeta.__index = function(v, k) if k == "Magnitude" then return math.sqrt(v.X*v.X+v.Y*v.Y+v.Z*v.Z) end end
local players = { list = {}, PlayerAdded = signal(), PlayerRemoving = signal() }
function players:GetPlayers() return table.clone(self.list) end
local heartbeat, renderStepped = signal(), signal()
local names = setmetatable({}, { __index = function(_, k) return k end })
local round = { IsRoundActive = function() return active end,
	RoundPrepared = object("BindableEvent"), RoundEnded = object("BindableEvent") }
local noiseRemote = { OnClientEvent = signal() }
function noiseRemote:FireClient(player, ...)
	assert(select("#", ...) == 2, "no target or identity may be sent")
	local position, intensity = ...
	table.insert(packets, { player = player, position = position, intensity = intensity, at = now })
end
local remotes = { NoiseDetected = noiseRemote, SprintIntent = { OnServerEvent = signal() },
	RoundEnded = { OnClientEvent = signal() }, RoundStateChanged = { OnClientEvent = signal() } }
local fear = { PanicSoundTriggered = object("BindableEvent"), GetStaminaRegenMultiplier = function() return 1 end }
local weapon = { NoiseMade = object("BindableEvent") }
local modules = { RoundManager = round, FearSystem = fear, WeaponSystem = weapon, Remotes = remotes,
	MatchStateService = { IsGameplayEnabled = function() return active end },
	LoadoutData = { GetPerk = function() return nil end } }
-- math.random controlado: sem isso a chance por distancia e o embaralhamento
-- da posicao fariam o teste depender de sorte. randomRoll = 0 e "sempre ouve,
-- posicao exata", o cenario das asserts que nao estao medindo o desconto.
-- randomQueue serve os primeiros sorteios (o da chance) antes do fallback,
-- para testar o embaralhamento sem que o ruido se perca no caminho.
local randomRoll, randomQueue = 0, nil
local tweens = {}
local cameraX = 0
local world = { CurrentCamera = { ViewportSize = { X = 800, Y = 600 },
	WorldToViewportPoint = function(_, position)
		return vec(position.X - cameraX + 400, position.Y + 300, 1), true
	end } }
local studio = true
local services = { Players = players, ReplicatedStorage = { Modules = names }, Workspace = world,
	RunService = { Heartbeat = heartbeat, RenderStepped = renderStepped,
		IsStudio = function() return studio end }, TweenService = { Create = function(_, target, _, props)
		table.insert(tweens, { target = target, props = props })
		return { Play = function() end }
	end } }
local logs = {}
local cframe = setmetatable({}, { __mul = function(a) return a end })
local env = setmetatable({ game = { GetService = function(_, k) return assert(services[k], k) end },
	math = setmetatable({ random = function()
		return (randomQueue and table.remove(randomQueue, 1)) or randomRoll
	end }, { __index = math }),
	script = { Parent = names }, Instance = { new = object }, Vector3 = { new = vec },
	os = { clock = function() return now end },
	typeof = function(v) return if getmetatable(v) == vectorMeta then "Vector3" elseif type(v) == "table" and v.ClassName then "Instance" else typeof(v) end,
	Enum = { KeyCode = names, HumanoidStateType = names, Material = names, EasingStyle = names,
		EasingDirection = names, ZIndexBehavior = names, ApplyStrokeMode = names },
	CFrame = { new = function() return cframe end, Angles = function() return cframe end },
	UDim2 = { fromScale = function(x,y) return { X=x, Y=y } end,
		fromOffset = function(x,y) return { X=x, Y=y } end }, UDim = { new = function(...) return {...} end },
	Vector2 = { new = function(...) return {...} end }, Color3 = { fromRGB = function(...) return {...} end },
	TweenInfo = { new = function(...) return {...} end },
	warn = function(...)
		local parts = {}
		for i = 1, select("#", ...) do parts[i] = tostring((select(i, ...))) end
		table.insert(logs, table.concat(parts, " "))
	end,
	task = { delay = function(t, fn) table.insert(delayed, { at=now+t, fn=fn }) end,
		defer = function(fn) fn() end },
}, { __index = getfenv() })
local function loadModule(name)
	if modules[name] then return modules[name] end
	local fn = assert(loadstring(assert(sources[name], name), name))
	setfenv(fn, env)
	modules[name] = fn()
	return modules[name]
end
env.require = loadModule
local config = loadModule("GameConfig")
local cfg = config.Noise
assert(cfg.MinimumIntensity == 1, "walk must be enabled by default")
assert(not cfg.Debug.SelfHear and not cfg.Debug.IgnoreRadius and not cfg.Debug.Verbose, "debug must ship off")
local function character()
	local c, h, r = object("Model"), object("Humanoid"), object("Part")
	c.children = { Humanoid = h, HumanoidRootPart = r }
	h.Health, h.FloorMaterial, h.state, h.Sit = 100, "Ground", "Running", false
	h.Died, h.StateChanged = signal(), signal()
	function h:GetState() return self.state end
	r.Position, r.AssemblyLinearVelocity, r.Anchored = vec(0), vec(0), false
	return c
end
local function player(role, x)
	local p = object("Player")
	p.Name = role .. tostring(#players.list + 1)
	p.Parent, p.Character = players, character()
	p.children.PlayerGui = object("PlayerGui")
	p.CharacterAdded, p.CharacterRemoving = signal(), signal()
	p:SetAttribute("Role", role); p:SetAttribute("InRound", true)
	p.Character.children.HumanoidRootPart.Position = vec(x or 0)
	table.insert(players.list, p); players.PlayerAdded:Fire(p)
	return p
end
local survivor = player(config.Roles.Survivor)
local monster = player(config.Roles.Monster, 80)
local far = player(config.Roles.Monster, 800) -- fora de qualquer alcance de passo
local spy = player(config.Roles.Spy)
local spectator = player(config.Roles.Monster)
spectator:SetAttribute("InRound", false)
local noise, stamina = loadModule("NoiseService"), loadModule("StaminaSystem")
noise.Init(); noise.Init(); stamina.Init()
assert(heartbeat:Count() == 1, "noise must not create another polling loop")
assert(stamina.MovementSampled.Event:Count() == 1)
assert(not noiseRemote.OnServerEvent, "no noise requests from clients")
local scaling = loadModule("StatScaling")
local root = survivor.Character.children.HumanoidRootPart
local hum = survivor.Character.children.Humanoid
local monsterRoot = monster.Character.children.HumanoidRootPart
-- Velocidade como PROPORCAO da base de caminhada do personagem, que e como o
-- servidor classifica: 0,5 agachado, 0,67 andando, 1 trotando, 1,92 correndo.
local function speedOf(ratio) return scaling.WalkSpeed(survivor) * ratio end
local function tick(dt)
	now += dt or 0.1; heartbeat:Fire(dt or 0.1)
	for i = #delayed, 1, -1 do
		if delayed[i].at <= now then local job = table.remove(delayed, i); job.fn() end
	end
end
local function reset() table.clear(packets) end
local function state(s, y, vy)
	local old = hum.state; hum.state = s
	hum.FloorMaterial = if s == "Running" or s == "Landed" then "Ground" else "Air"
	root.Position = vec(0,y); root.AssemblyLinearVelocity = vec(0,vy)
	hum.StateChanged:Fire(old,s)
end
tick(); tick(0.6)
-- Sem personagem escolhido a Furtividade vale 50 (meio da faixa), igual a
-- qualquer outro atributo. Todos os alcances abaixo saem dai.
local sprintRadius = scaling.NoiseRadius(survivor, "Sprint")
local sprintInterval = scaling.NoisePingInterval(survivor, "Sprint")
assert(sprintRadius > 80 and sprintRadius < 800, "o cenario supoe monster dentro e far fora do alcance de corrida")
root.AssemblyLinearVelocity = vec(speedOf(1.92))
tick()
assert(#packets == 1 and packets[1].player == monster and packets[1].intensity == cfg.States.Sprint.Intensity,
	"corrida chega so a quem esta no alcance; Espiao e quem esta fora da partida nunca recebem")
local origin = packets[1].position
root.Position = vec(0,0,2)
assert(origin.Z == 0, "snapshot must not move with survivor")
root.Position = vec(0)
-- 0,3 s fica abaixo do menor intervalo de corrida possivel (Furtividade 0).
for _ = 1, 3 do tick() end
assert(#packets == 1, "no burst while sprinting")
local guard = 0
while #packets < 2 and guard < 100 do tick(); guard += 1 end
assert(#packets == 2 and packets[2].at - packets[1].at >= sprintInterval, "a cadencia da corrida sai da Furtividade")
root.AssemblyLinearVelocity = vec(0); tick(1); tick(3)
assert(#packets == 2, "stopping must stop pings")

-- AGACHADO < ANDAR < TROTAR < CORRER, em alcance e em frequencia, para
-- qualquer Furtividade. E a promessa central do sistema.
for _, stealth in { 0, 10, 50, 95 } do
	survivor:SetAttribute("Stat_Furtividade", stealth)
	local lastRadius, lastInterval = -1, math.huge
	for _, state in { "Crouch", "Walk", "Jog", "Sprint" } do
		local radius = scaling.NoiseRadius(survivor, state)
		local interval = scaling.NoisePingInterval(survivor, state)
		assert(radius > lastRadius, state .. " tem de alcancar mais longe que o estado anterior")
		assert(interval < lastInterval, state .. " tem de pingar mais vezes que o estado anterior")
		lastRadius, lastInterval = radius, interval
	end
end
survivor:SetAttribute("Stat_Furtividade", nil)

reset()
-- Agachado: alcance minusculo, nao chega aos 80 studs do Monstro.
root.AssemblyLinearVelocity = vec(speedOf(0.5)); tick(6)
assert(#packets == 0, "agachado nao alcanca 80 studs")

-- ANDAR (padrao, ratio 1,00): o alcance e o que a Furtividade produziu, nao
-- um numero fixo.
local walkRadius = scaling.NoiseRadius(survivor, "Walk")
monsterRoot.Position = vec(walkRadius - 0.5)
hum.state = "RunningNoPhysics"
root.AssemblyLinearVelocity = vec(speedOf(1)); tick(6)
assert(#packets == 1 and packets[1].intensity == cfg.States.Walk.Intensity,
	"andar vale tambem nos estados de chao customizados do pacote de movimento")
reset(); monsterRoot.Position = vec(walkRadius + 0.5); tick(6)
assert(#packets == 0, "passou do alcance de andar, ninguem ouve")

-- TROTAR (Control, ratio 1,25): mesmo ponto, mesma Furtividade -- so o ritmo
-- mudou, e agora ouve.
reset(); root.AssemblyLinearVelocity = vec(speedOf(1.25)); tick(6)
assert(#packets == 1 and packets[1].intensity == cfg.States.Jog.Intensity,
	"trote alcanca mais longe que andar de onde andar ja nao alcancava")

-- FURTIVIDADE MUDA O RESULTADO -- nao e numero de vitrine.
survivor:SetAttribute("Stat_Furtividade", 10)
local loudWalk = scaling.NoiseRadius(survivor, "Walk")
local loudJog = scaling.NoiseRadius(survivor, "Jog")
local loudSprint = scaling.NoiseRadius(survivor, "Sprint")
-- Referencia de balanceamento pedida para o tamanho atual da ilha.
assert(loudWalk >= 60 and loudWalk <= 120, "andar de quem e pouco furtivo: 60-120 studs")
assert(loudJog >= 180 and loudJog <= 280, "trote de quem e pouco furtivo: 180-280 studs")
assert(loudSprint >= 400, "corrida de quem e pouco furtivo passa dos 400 studs")
survivor:SetAttribute("Stat_Furtividade", 90)
assert(loudSprint > scaling.NoiseRadius(survivor, "Sprint") * 2.5,
	"Furtividade 10 correndo tem de ser ouvido de MUITO mais longe que Furtividade 90")

-- Furtividade muito alta anda em silencio de verdade: o ruido nem e gerado.
survivor:SetAttribute("Stat_Furtividade", 95)
assert(scaling.NoiseRadius(survivor, "Walk") < cfg.MinAudibleRadius, "Furtividade 95 anda em silencio")
assert(scaling.NoiseRadius(survivor, "Sprint") >= cfg.MinAudibleRadius, "mas correr sempre denuncia alguem")
reset(); monsterRoot.Position = vec(1) -- Monstro colado
root.AssemblyLinearVelocity = vec(speedOf(1)); tick(9)
assert(#packets == 0, "Furtividade alta anda em silencio mesmo com o Monstro colado")
root.AssemblyLinearVelocity = vec(speedOf(1.92)); tick(9)
assert(#packets == 1, "mas correr entrega ate quem e muito furtivo")
survivor:SetAttribute("Stat_Furtividade", nil)

-- DISTANCIA: estar no alcance nao e ping garantido, e a posicao piora.
state("Running", 0, 0)
local function sprintFrom(distance, roll)
	reset(); randomRoll = roll
	monsterRoot.Position = vec(distance)
	root.Position = vec(0)
	root.AssemblyLinearVelocity = vec(speedOf(1.92))
	tick(9)
	return #packets
end
assert(sprintFrom(sprintRadius * 0.2, 0.9) == 1, "perto da origem ate um sorteio ruim ouve")
assert(sprintFrom(sprintRadius * 0.98, 0.9) == 0, "na borda a maior parte do ruido se perde")
assert(sprintFrom(sprintRadius * 0.98, 0) == 1, "na borda ainda pode chegar -- so nao sempre")

-- O ping marca a REGIAO do barulho. Longe, erra bastante; colado, quase nada.
local function driftFrom(distance)
	randomQueue = { 0 } -- o sorteio da CHANCE passa; o resto vira embaralhamento
	sprintFrom(distance, 0.5)
	randomQueue = nil
	local heard = packets[1].position
	return math.sqrt(heard.X * heard.X + heard.Z * heard.Z), heard.Y
end
local farDrift, farY = driftFrom(sprintRadius * 0.9)
assert(farDrift > 5, "longe, o circulo marca a regiao e nao o jogador")
assert(farY == 0, "o erro fica no plano do chao, a onda nao afunda nem flutua")
assert(driftFrom(sprintRadius * 0.05) < farDrift, "colado, a posicao e quase exata")
randomRoll = 0

reset()
monsterRoot.Position = vec(50)
state("Jumping", 0, 35)
assert(#packets == 1 and packets[1].intensity == 2)
state("Freefall", 8, 0); tick(0.3); state("Landed", 0, 0)
assert(#packets == 2 and packets[2].intensity == 3, "peak-based fall landing")
hum.StateChanged:Fire("Freefall","Landed"); tick()
assert(#packets == 2, "landing only once")
tick(0.6); reset()
state("Freefall", 0, 0); tick(0.3); state("Landed", -2, 0)
assert(#packets == 0, "small drop is quiet")
state("Swimming",0,0); tick(0.5); state("Landed",-10,0)
assert(#packets == 0, "swimming is not a fall")
state("Running",0,0); tick(0.6)
-- Personagem rapido: as faixas sao PROPORCAO da base dele, entao o trote de
-- quem tem Velocidade 100 continua trote mesmo sendo mais rapido que a
-- corrida de um personagem lento.
survivor:SetAttribute("Stat_Velocidade", 100)
local fastBase = scaling.WalkSpeed(survivor)
assert(fastBase > scaling.Lerp(50, config.Characters.WalkSpeed), "Velocidade 100 anda mais rapido que o padrao")
reset(); monsterRoot.Position = vec(1)
root.AssemblyLinearVelocity = vec(fastBase * 1.25); tick(6)
assert(#packets == 1 and packets[1].intensity == cfg.States.Jog.Intensity,
	"o trote do personagem rapido nao pode ser classificado como corrida")
reset(); root.AssemblyLinearVelocity = vec(fastBase * 1.92); tick(6)
assert(#packets == 1 and packets[1].intensity == cfg.States.Sprint.Intensity,
	"corrida deduzida da velocidade real, sem SprintIntent")
local count = #packets
root.AssemblyLinearVelocity = vec(0); tick(0.1); root.AssemblyLinearVelocity = vec(fastBase * 1.92); tick(0.1)
assert(#packets == count, "sprint toggle cannot reset cooldown")
survivor.Character:SetAttribute("PowerInfiniteStamina", true)
tick(3); assert(#packets > count, "infinite stamina still makes noise")
survivor.Character:SetAttribute("PowerInfiniteStamina", nil)
survivor:SetAttribute("Stat_Velocidade", nil)
root.AssemblyLinearVelocity = vec(0)
monsterRoot.Position = vec(50)
reset()
local source = vec(0)
assert(not noise:EmitNoise(spy, source, 4))
assert(not noise:EmitNoise(monster, source, 4))
assert(not noise:EmitNoise(survivor, vec(0/0), 4))
assert(not noise:EmitNoise(survivor, source, math.huge))
assert(not noise:EmitNoise(survivor, source, 0))
assert(not noise:EmitNoise(survivor, source, 4, -1))
weapon.NoiseMade:Fire(source)
assert(#packets == 0, "generator without survivor attribution is ignored")
weapon.NoiseMade:Fire(source, survivor, 4)
assert(#packets == 1, "stone reuses NoiseMade and checks radius")
assert(not noise:EmitNoise(survivor, source, 4), "actions are rate limited")
tick(0.4); reset(); fear.PanicSoundTriggered:Fire(survivor, source, 50)
assert(#packets == 1 and packets[1].player == monster)
tick(0.4); reset(); monster.Character.children.Humanoid.Health = 0
assert(not noise:EmitNoise(survivor, source, 3, 50))
monster.Character.children.Humanoid.Health = 100
survivor:SetAttribute("Eliminado", true)
assert(not noise:EmitNoise(survivor, source, 4))
survivor:SetAttribute("Eliminado", nil)
survivor.Character:SetAttribute("Eliminado", true)
assert(not noise:EmitNoise(survivor, source, 4))
survivor.Character:SetAttribute("Eliminado", nil)
survivor:SetAttribute("InRound", false)
assert(not noise:EmitNoise(survivor, source, 4))
survivor:SetAttribute("InRound", true)
active = false; assert(not noise:EmitNoise(survivor, source, 4))
round.RoundEnded:Fire(); assert(hum.StateChanged:Count() == 0)
active = true; tick(); assert(hum.StateChanged:Count() == 1)
local oldHum = hum
survivor.CharacterRemoving:Fire(survivor.Character)
survivor.Character = character(); survivor.CharacterAdded:Fire(survivor.Character)
root, hum = survivor.Character.children.HumanoidRootPart, survivor.Character.children.Humanoid
assert(oldHum.StateChanged:Count() == 0)
tick(); reset(); state("Freefall",20,-20); tick(0.3); state("Landed",0,0)
assert(#packets == 0, "spawn settling must not emit landing")
local second = player(config.Roles.Survivor)
tick(0.6); tick(0.6); reset()
root.AssemblyLinearVelocity = vec(40)
second.Character.children.HumanoidRootPart.AssemblyLinearVelocity = vec(23)
tick(); assert(#packets == 2, "individual survivor cooldowns")
players.PlayerRemoving:Fire(second); second.Parent = nil
assert(second.Character.children.Humanoid.StateChanged:Count() == 0)

-- Teste solo: com um cliente so nao existe Monstro E Sobrevivente ao mesmo
-- tempo, entao nada chegava -- e o sistema PARECIA quebrado estando certo.
tick(0.6); reset()
monster:SetAttribute("Role", config.Roles.Survivor)
far:SetAttribute("Role", config.Roles.Survivor)
assert(not noise:EmitNoise(survivor, source, 4), "sem Monstro, nenhum ouvinte")
assert(#packets == 0)
cfg.Debug.SelfHear = true
root.AssemblyLinearVelocity = vec(0)
tick(0.4); reset()
assert(noise:EmitNoise(survivor, source, 4), "SelfHear entrega ao proprio emissor")
assert(#packets == 1 and packets[1].player == survivor, "eco vai so para quem fez o barulho")
studio = false
tick(0.4); reset()
assert(not noise:EmitNoise(survivor, source, 4), "SelfHear nunca vale fora do Studio")
studio = true
tick(0.4); reset()
survivor:SetAttribute("Eliminado", true)
assert(not noise:EmitNoise(survivor, source, 4), "eco ainda respeita os filtros")
survivor:SetAttribute("Eliminado", nil)
cfg.Debug.SelfHear = false
monster:SetAttribute("Role", config.Roles.Monster)
far:SetAttribute("Role", config.Roles.Monster)
tick(0.4); reset()

-- Verbose diz POR QUE nada chegou. Era o que faltava para diagnosticar sem
-- adivinhar: sem ele todo descarte e silencioso.
table.clear(logs)
assert(not noise:EmitNoise(spy, source, 4) and #logs == 0, "quieto por padrao")
cfg.Debug.Verbose = true
tick(0.4)
assert(not noise:EmitNoise(spy, source, 4), "Espiao nao produz ping")
assert(#logs == 1 and string.find(logs[1], "Sobrevivente", 1, true), logs[1] or "sem motivo")
table.clear(logs)
tick(0.4)
assert(not noise:EmitNoise(survivor, source, 1, 5), "monstros fora de alcance")
assert(#logs >= 1 and string.find(logs[1], "studs", 1, true), logs[1] or "sem distancia")
table.clear(logs)
active = false; tick(0.4)
assert(not noise:EmitNoise(survivor, source, 4))
assert(#logs == 1 and string.find(logs[1], "partida", 1, true), logs[1] or "sem fase")
active = true
cfg.Debug.Verbose = false

-- Ilha gigante (raio 560-820 studs) + Monstro sozinho na caverna: em teste
-- normal a distância real passa fácil de qualquer raio configurado, e o
-- Monstro nunca recebe nada mesmo com tudo certo. IgnoreRadius entrega
-- de qualquer distância; só vale no Studio, igual ao SelfHear.
-- "monster" está a 50 studs e "far" a 800 (ver as posições fixadas no início
-- do arquivo); um raio de 10 deixa os DOIS fora de alcance.
tick(0.4); reset()
assert(not noise:EmitNoise(survivor, source, 4, 10), "fora de alcance sem IgnoreRadius")
assert(#packets == 0)
cfg.Debug.IgnoreRadius = true
tick(0.4)
assert(noise:EmitNoise(survivor, source, 4, 10), "IgnoreRadius entrega mesmo fora do raio configurado")
assert(#packets == 2, "todo Monstro ativo recebe, nao so o mais perto")
local heard = {}
for _, packet in packets do heard[packet.player] = true end
assert(heard[monster] and heard[far], "monster e far, os dois ativos, recebem com IgnoreRadius")
studio = false
tick(0.4); reset()
assert(not noise:EmitNoise(survivor, source, 4, 10), "IgnoreRadius nunca vale fora do Studio")
studio = true
cfg.Debug.IgnoreRadius = false
tick(0.4); reset()

table.clear(logs)
tick(0.4); reset()
noise.Diagnose()
assert(#logs == 0, "Diagnose nao usa warn")
print("PASS: server routing, movement, cadence, hooks, round/respawn cleanup; one shared Heartbeat")

-- Client uses real visualizer against instance/tween/camera/timer doubles.
players.LocalPlayer = monster
loadModule("NoiseVisualizer")
local function liveWaves()
	local result = {}
	for _, o in created do if o.Name == "SoundWave" and o.Parent then table.insert(result, o) end end
	return result
end
noiseRemote.OnClientEvent:Fire(vec(12,3,4), 3)
local wave = liveWaves()[1]
assert(wave and wave.Parent.Name == "NoiseVisualizer" and wave.Parent.Parent == monster.children.PlayerGui)
assert(wave.Visible and wave.Position.X == 412 and wave.Position.Y == 303)
assert(#tweens == 4 and tweens[1].props.Scale > tweens[1].target.Scale)
assert(tweens[2].props.BackgroundTransparency == 1, "halo fades out")
assert(tweens[3].props.Transparency == 1 and tweens[4].props.Transparency == 1, "both strokes fade")
-- Sombra mais grossa que o nucleo: e o que faz o anel ler em cenario claro.
assert(tweens[3].target.Thickness > tweens[4].target.Thickness, "contrast ring behind the light one")
assert(tweens[3].target.Parent.ZIndex < tweens[4].target.Parent.ZIndex)
tick(cfg.Visual.SecondWaveDelay)
assert(#tweens == 8 and #liveWaves() == 2, "delayed second wave")
monster.Character.children.HumanoidRootPart.Position = vec(150)
renderStepped:Fire()
assert(wave.Position.X == 412, "projection does not follow any character")
cameraX = 10; renderStepped:Fire()
assert(wave.Position.X == 402, "fixed world point follows camera projection")
tick(cfg.Visual.Duration + 0.01)
assert(#liveWaves() == 0 and renderStepped:Count() == 0, "automatic expiry stops projection")
for _ = 1, cfg.Visual.MaxActivePings + 10 do noiseRemote.OnClientEvent:Fire(vec(0),3) end
assert(#liveWaves() == cfg.Visual.MaxActivePings, "bounded visuals")
monster.Character.children.Humanoid.Died:Fire()
assert(#liveWaves() == 0, "death cleanup")
noiseRemote.OnClientEvent:Fire(vec(0),3)
remotes.RoundEnded.OnClientEvent:Fire()
assert(#liveWaves() == 0)
noiseRemote.OnClientEvent:Fire(vec(0),3); assert(#liveWaves() == 0)
remotes.RoundStateChanged.OnClientEvent:Fire()
noiseRemote.OnClientEvent:Fire(vec(0),3); assert(#liveWaves() == 1)
-- Ponto pouco fora da tela: a onda ainda cobre a borda, entao continua
-- desenhada. Passando da margem ela some -- sem virar seta de borda.
cameraX = 0
local edge = cfg.Visual.EdgeMarginPixels
local inside = liveWaves()[1]
noiseRemote.OnClientEvent:Fire(vec(400 + edge - 10, -300, 0), 3)
local edgeWave = liveWaves()[#liveWaves()]
renderStepped:Fire()
assert(edgeWave.Visible, "onda encostando na borda continua visivel")
noiseRemote.OnClientEvent:Fire(vec(400 + edge + 10, -300, 0), 3)
local outWave = liveWaves()[#liveWaves()]
renderStepped:Fire()
assert(not outWave.Visible, "passou da margem, some")
assert(inside == nil or inside.Visible ~= nil)
tick(cfg.Visual.Duration + cfg.Visual.SecondWaveDelay + 0.01)
monster:SetAttribute("Role",config.Roles.Survivor)
assert(#liveWaves() == 0)
noiseRemote.OnClientEvent:Fire(vec(0),3); assert(#liveWaves() == 0)
-- O mesmo eco de teste do servidor precisa ser aceito aqui, e so no Studio.
cfg.Debug.SelfHear = true
noiseRemote.OnClientEvent:Fire(vec(0),3); assert(#liveWaves() == 1, "eco solo renderiza")
tick(cfg.Visual.Duration + cfg.Visual.SecondWaveDelay + 0.01)
studio = false
noiseRemote.OnClientEvent:Fire(vec(0),3); assert(#liveWaves() == 0, "fora do Studio, nunca")
studio = true
cfg.Debug.SelfHear = false
noiseRemote.OnClientEvent:Fire(vec(0),3); assert(#liveWaves() == 0)
tick(2); assert(#liveWaves() == 0, "delayed waves cannot resurrect cleared pings")
for _, o in created do
	assert(o.ClassName ~= "TextLabel" and o.ClassName ~= "Highlight", "no identity, distance or outline")
end
print("PASS: client wave tweens, contrast ring, edge margin, solo echo, expiry, cap, cleanup")
