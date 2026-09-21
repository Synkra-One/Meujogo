-- Modules injected by runner (ver tests/run_repair_minigame.py).
-- Testa autoridade, sequencia de acertos, notas, punicao, ruido e limpeza do reparo de
-- precisao com servicos deterministicos. NAO simula fisica nem renderizacao.

local function signal()
	local s = { listeners = {} }
	function s:Connect(fn)
		local c = { active = true, fn = fn }
		function c:Disconnect() self.active = false end
		table.insert(self.listeners, c); return c
	end
	function s:Once(fn)
		local c
		c = self:Connect(function(...) c:Disconnect(); fn(...) end)
		return c
	end
	function s:Fire(...) for _, c in table.clone(self.listeners) do if c.active then c.fn(...) end end end
	return s
end

local vm = {}
local function vec(x, y, z) return setmetatable({ X = x, Y = y, Z = z, kind = "Vector3" }, vm) end
vm.__add = function(a, b) return vec(a.X + b.X, a.Y + b.Y, a.Z + b.Z) end
vm.__sub = function(a, b) return vec(a.X - b.X, a.Y - b.Y, a.Z - b.Z) end
vm.__mul = function(a, b) return vec(a.X * b, a.Y * b, a.Z * b) end
vm.__index = function(v, k)
	if k == "Magnitude" then return math.sqrt(v.X * v.X + v.Y * v.Y + v.Z * v.Z) end
	if k == "Unit" then return v * (1 / v.Magnitude) end
end

local function object(class)
	local methods = {}
	local fields = { ClassName = class, Name = class, children = {}, attributes = {}, changed = {}, _instance = true,
		Destroying = signal(), ChildAdded = signal(), DescendantAdded = signal(),
		CharacterAdded = signal(), CharacterRemoving = signal(), PlayerAdded = signal(), PlayerRemoving = signal(),
		Triggered = signal() }
	function methods:IsA(c) return c == class or (class == "Part" and c == "BasePart") end
	function methods:GetAttribute(k) return fields.attributes[k] end
	function methods:SetAttribute(k, v)
		local old = fields.attributes[k]; fields.attributes[k] = v
		if old ~= v and fields.changed[k] then fields.changed[k]:Fire() end
	end
	function methods:GetAttributeChangedSignal(k)
		fields.changed[k] = fields.changed[k] or signal(); return fields.changed[k]
	end
	function methods:GetChildren() return table.clone(fields.children) end
	function methods:GetDescendants()
		local out = {}
		for _, child in fields.children do
			table.insert(out, child)
			for _, d in child:GetDescendants() do table.insert(out, d) end
		end
		return out
	end
	function methods:FindFirstChild(k) for _, c in fields.children do if c.Name == k then return c end end return nil end
	function methods:FindFirstChildOfClass(k) for _, c in fields.children do if c:IsA(k) then return c end end return nil end
	function methods:FindFirstAncestorOfClass(k)
		local p = self.Parent
		while p do if p:IsA(k) then return p end; p = p.Parent end
		return nil
	end
	function methods:IsDescendantOf(parent)
		local p = self.Parent
		while p do if p == parent then return true end; p = p.Parent end
		return false
	end
	function methods:Destroy() self.Destroying:Fire(); self.Parent = nil end
	return setmetatable({}, {
		__index = function(_, k) return methods[k] or fields[k] end,
		__newindex = function(self, k, v)
			if k == "Parent" then
				local old = fields.Parent
				if old then local i = table.find(old.children, self); if i then table.remove(old.children, i) end end
				fields.Parent = v
				if v then table.insert(v.children, self) end
			else fields[k] = v end
		end,
	})
end

--------------------------------------------------------------------------------
-- Servicos deterministicos
--------------------------------------------------------------------------------

local serverTime, wallClock = 1000, 500
local blocked = false -- raycast: obstaculo entre jogador e alvo

local world = object("Workspace")
function world:GetServerTimeNow() return serverTime end
function world:Raycast() return if blocked then { Position = vec(0, 0, 0) } else nil end

local players = object("Players")
local roster = {}
function players:GetPlayers() return table.clone(roster) end

local heartbeat = signal()
local sent = {} -- mensagens Server -> Client

local remotes = setmetatable({}, { __index = function(t, k)
	local r = { OnServerEvent = signal(), OnClientEvent = signal() }
	function r:FireClient(player, ...) table.insert(sent, { remote = k, player = player, args = { ... } }) end
	function r:FireAllClients(...) table.insert(sent, { remote = k, args = { ... } }) end
	rawset(t, k, r); return r
end })

local function bindable() local s = signal(); return { Event = s, Fire = function(_, ...) s:Fire(...) end } end
local roundManager = { RoundPrepared = bindable(), RoundEnded = bindable(), IsRoundActive = function() return true end }
local damageSystem = { DamageApplied = bindable(), Healed = bindable() }

local noiseCalls = {}
local noiseService = {}
function noiseService:EmitNoise(player, position, intensity, radius)
	table.insert(noiseCalls, { player = player, position = position, intensity = intensity, radius = radius })
	return true
end

local repairStat = {}
local statScaling = {
	AttributePrefix = "Stat_",
	Of = function(player, name)
		local v = player and player:GetAttribute("Stat_" .. name)
		return if type(v) == "number" then v else nil
	end,
	Lerp = function(stat, range)
		local t = math.clamp((stat or 50) / 100, 0, 1)
		return range.Min + (range.Max - range.Min) * t
	end,
	RepairMultiplier = function(player) return repairStat[player] or 1 end,
}

local gameConfig = {
	Roles = { Survivor = "Sobrevivente", Spy = "Espiao", Monster = "Monstro" },
	Characters = { RepairSpeed = { Min = 0.55, Max = 1.6 } },
	Noise = { Debug = { SelfHear = false } },
	RadioSite = { ErroGerador = { Enabled = true, Cooldown = 3, RollOffMaxDistance = 100 } },
}

-- Random controlavel: randomT escolhe onde cair dentro de cada faixa.
local randomT, randomInt = 0.5, 0.0
local randomStub = { new = function()
	return {
		NextNumber = function(_, a, b)
			if a == nil then return randomT end
			return a + (b - a) * randomT
		end,
		NextInteger = function(_, a, b) return a + math.floor((b - a) * randomInt + 0.5) end,
	}
end }

local moduleNames = setmetatable({}, { __index = function(_, k) return k end })
local services = {
	Players = players, Workspace = world, RunService = { Heartbeat = heartbeat },
	ReplicatedStorage = { Modules = moduleNames },
}
local modules = {
	Remotes = remotes, RoundManager = roundManager, DamageSystem = damageSystem,
	NoiseService = noiseService, StatScaling = statScaling, GameConfig = gameConfig,
}
local enum = setmetatable({}, { __index = function(t, k)
	local v = setmetatable({}, { __index = function(_, n) return n end }); rawset(t, k, v); return v
end })
local environment = setmetatable({
	game = { GetService = function(_, name) return assert(services[name], name) end },
	workspace = world, script = { Parent = moduleNames },
	Vector3 = { new = vec, zero = vec(0, 0, 0) },
	Enum = enum, Color3 = { fromRGB = function(...) return { ... } end },
	RaycastParams = { new = function() return {} end },
	Random = randomStub,
	os = { clock = function() return wallClock end, time = os.time },
	typeof = function(v)
		return if type(v) == "table" then (if v._instance then "Instance" else v.kind or "table") else type(v)
	end,
	Instance = { new = function(class) return if class == "BindableEvent" then bindable() else object(class) end },
	task = { defer = function(fn, ...) fn(...) end, delay = function(_, fn, ...) fn(...) end },
}, { __index = getfenv() })
local function load(name)
	if modules[name] then return modules[name] end
	local chunk = assert(loadstring(assert(sources[name], name), name))
	setfenv(chunk, environment)
	modules[name] = chunk()
	return modules[name]
end
environment.require = load

--------------------------------------------------------------------------------
-- Cenario
--------------------------------------------------------------------------------

local function newPlayer(name, x)
	local p = object("Player"); p.Name = name; p.UserId = #roster + 1; p.Parent = players
	p:SetAttribute("Role", "Sobrevivente"); p:SetAttribute("InRound", true)
	local c = object("Model"); c.Parent = world; p.Character = c
	local h = object("Humanoid"); h.Parent = c; h.Health = 100
	local root = object("Part"); root.Name = "HumanoidRootPart"; root.Parent = c; root.Position = vec(x or 0, 3, 0)
	local head = object("Part"); head.Name = "Head"; head.Parent = c; head.Position = vec(x or 0, 4, 0)
	table.insert(roster, p)
	return p, c, h, root
end

local Config = load("RepairMinigameConfig")
local System = load("RepairMinigameSystem")

local panel = object("Part"); panel.Name = "Painel"; panel.Position = vec(0, 3, 0); panel.Parent = world
local prompt = object("ProximityPrompt"); prompt.Name = "AtivarPainel"; prompt.HoldDuration = 4; prompt.Parent = panel

local alice, aliceChar, aliceHum, aliceRoot = newPlayer("Alice", 2)
local bruno = newPlayer("Bruno", 3)
local monster = newPlayer("Jason", 4)
monster:SetAttribute("Role", "Monstro")

local completions = {}
local allow = true
System.Bind(prompt, {
	taskId = "RadioPainel",
	configId = "RadioPainel",
	part = panel,
	range = 12,
	canStart = function() return allow, (if allow then nil else "Bloqueado.") end,
	onComplete = function(player) table.insert(completions, player.Name) end,
})
-- O GERADOR: um segundo ponto de reparo, afastado do painel.
local generator = object("Part"); generator.Name = "Gerador"; generator.Position = vec(0, 3, 10); generator.Parent = world
local generatorPrompt = object("ProximityPrompt"); generatorPrompt.Name = "LigarGerador"; generatorPrompt.Parent = generator
System.Bind(generatorPrompt, {
	taskId = "RadioPartida",
	configId = "RadioPartida",
	part = generator,
	range = 30,
	canStart = function() return true, nil end,
	onComplete = function() end,
})
System.Init()
-- Onde o choque 3D toca (o RadioSiteSystem registra isso no jogo de verdade).
local GeneratorSound = load("GeneratorErrorSound")
GeneratorSound.SetGenerator(generator)

--------------------------------------------------------------------------------
-- Utilidades de teste
--------------------------------------------------------------------------------

local failures = 0
local function check(label, condition, detail)
	if condition then
		print("ok   " .. label)
	else
		failures += 1
		print("FAIL " .. label .. (if detail ~= nil then "  -- " .. tostring(detail) else ""))
	end
end

local function lastOf(action, who)
	for i = #sent, 1, -1 do
		local m = sent[i]
		if m.remote == "RepairMinigame" and m.args[1] == action and (who == nil or m.player == who) then
			return m
		end
	end
	return nil
end
local function countOf(action, who)
	local n = 0
	for _, m in sent do
		if m.remote == "RepairMinigame" and m.args[1] == action and (who == nil or m.player == who) then n += 1 end
	end
	return n
end
local function tokenOf(who) local m = lastOf("Start", who); return m and m.args[2] end

-- Um cliente de verdade confirma ~4x por segundo que ainda segura. Sem isso
-- qualquer avanco de relogio maior que o timeout derrubaria a sessao e
-- mascararia o comportamento sob teste.
local autoKeepAlive = true
local function tick(seconds, slices)
	slices = slices or 1
	for _ = 1, slices do
		serverTime += seconds / slices
		wallClock += seconds / slices
		heartbeat:Fire(seconds / slices)
		if autoKeepAlive then
			for _, p in roster do
				if System.IsRepairing(p) then
					remotes.RepairMinigame.OnServerEvent:Fire(p, "Hold", tokenOf(p))
				end
			end
		end
	end
end

-- Espera o proximo teste (ainda nao consumido) de `who` chegar.
local function nextTest(who)
	for _ = 1, 800 do
		local m = lastOf("Test", who)
		if m and not m.consumed then
			m.consumed = true
			return m.args[3], m
		end
		tick(0.05)
	end
	error("nenhum teste de precisao apareceu", 0)
end

local function open(who)
	-- Testes de sessoes anteriores que ninguem consumiu nao podem ser
	-- confundidos com o primeiro teste desta.
	for _, m in sent do
		if m.remote == "RepairMinigame" and m.args[1] == "Test" then m.consumed = true end
	end
	wallClock += 1
	prompt.Triggered:Fire(who)
	assert(System.IsRepairing(who), "a sessao de teste nao abriu")
end

-- Abre uma sessao limpa pra `who` (alice por padrao) e devolve o 1o teste.
local function freshTest(who)
	who = who or alice
	System.ResetAll()
	open(who)
	return (nextTest(who))
end

-- Espera o marcador entrar numa nota (o marcador oscila de velocidade, entao
-- nao da pra calcular o instante em linha reta) e aperta nesse instante. O
-- relogio anda de verdade: o servidor confere o instante alegado contra a
-- hora de chegada, entao trapacear aqui seria trapacear o proprio teste.
local function hitWhen(test, wanted, who)
	who = who or alice
	local window = Config.TestWindow(test)
	while true do
		local elapsed = serverTime - test.startsAt
		if elapsed > window then return nil end
		if elapsed >= 0 and wanted(Config.Grade(test, Config.MarkerAt(test, elapsed))) then break end
		tick(0.002)
	end
	remotes.RepairMinigame.OnServerEvent:Fire(who, "Hit", tokenOf(who), test.id, serverTime - test.startsAt)
	return lastOf("Result", who)
end
local function isHit(grade) return grade == "Perfect" or grade == "Green" end
local function hitCenter(test, who) return hitWhen(test, isHit, who) end
local function hitYellow(test, who) return hitWhen(test, function(g) return g == "Yellow" end, who) end
local function hitRed(test, who) return hitWhen(test, function(g) return g == "Red" end, who) end

-- Primeiro instante do teste em que o marcador esta numa nota (sem avancar o relogio).
local function firstTimeIn(test, wanted)
	local t = 0
	while t <= Config.TestWindow(test) do
		if wanted(Config.Grade(test, Config.MarkerAt(test, t))) then return t end
		t += 0.001
	end
	return nil
end

-- Resultado: args = { "Result", token, testId, grade, streak, required, stall, accuracy }
local function gradeOf(m) return m.args[4] end
local function streakOf(m) return m.args[5] end

--------------------------------------------------------------------------------
-- 1. Autoridade na abertura
--------------------------------------------------------------------------------

prompt.Triggered:Fire(monster)
check("monstro nao abre reparo de sobrevivente", not System.IsRepairing(monster))

alice:SetAttribute("InRound", false)
prompt.Triggered:Fire(alice)
check("fora da partida nao abre", not System.IsRepairing(alice))
alice:SetAttribute("InRound", true)

aliceRoot.Position = vec(90, 3, 0)
prompt.Triggered:Fire(alice)
check("fora de alcance nao abre", not System.IsRepairing(alice))
aliceRoot.Position = vec(2, 3, 0)

blocked = true
prompt.Triggered:Fire(alice)
check("sem linha de visao nao abre", not System.IsRepairing(alice))
blocked = false

allow = false
prompt.Triggered:Fire(alice)
check("canStart do objetivo recusa", not System.IsRepairing(alice))
allow = true

aliceChar:SetAttribute("PowerStunned", true)
prompt.Triggered:Fire(alice)
check("atordoado nao abre", not System.IsRepairing(alice))
aliceChar:SetAttribute("PowerStunned", nil)

check("Bind zerou o HoldDuration do prompt", prompt.HoldDuration == 0, prompt.HoldDuration)

System.ResetAll()
open(alice)
local start = lastOf("Start", alice)
check("Start carrega a Part e o rotulo", start.args[3] == panel and start.args[4] == "Painel de controle")
check("Start comeca com sequencia 0 de 3", start.args[5] == 0 and start.args[6] == Config.Streak.Required)
check("personagem marcado como Reparando", aliceChar:GetAttribute("Reparando") == true)
remotes.RepairMinigame.OnServerEvent:Fire(alice, "Release", tokenOf(alice) + 999)
check("token invalido e ignorado", System.IsRepairing(alice))

--------------------------------------------------------------------------------
-- 2. O BUG: ficar sem fazer nada NUNCA conclui
--------------------------------------------------------------------------------

local function idleForever(seconds)
	local noisesBefore, completionsBefore = #noiseCalls, #completions
	System.ResetAll()
	open(alice)
	tick(seconds, seconds * 20) -- segura a tecla e nao aperta NADA
	local results, allZero = 0, true
	for _, m in sent do
		if m.remote == "RepairMinigame" and m.args[1] == "Result" and m.player == alice then
			results += 1
			if streakOf(m) ~= 0 or gradeOf(m) ~= "Miss" then allZero = false end
		end
	end
	return #completions - completionsBefore, #noiseCalls - noisesBefore, results, allZero
end

repairStat[alice] = 0.76 -- Rafael Monteiro (Reparo 20)
local done, noises, misses, allZero = idleForever(90)
check("Rafael parado 90s NAO conclui o reparo", done == 0, done)
check("cada teste ignorado vira Miss com sequencia 0", misses >= 5 and allZero, string.format("%d misses", misses))
check("cada teste ignorado faz barulho", noises == misses, string.format("%d ruidos / %d misses", noises, misses))
check("a sessao segue aberta (so nao progride)", System.IsRepairing(alice))

repairStat[alice] = 1.6 -- Diego (Reparo 96)
done = idleForever(90)
check("nem o melhor reparador conclui parado", done == 0, done)
repairStat[alice] = 1
check("nao existe mais mensagem de progresso passivo", countOf("Progress") == 0)

--------------------------------------------------------------------------------
-- 3. Tres acertos SEGUIDOS concluem
--------------------------------------------------------------------------------

local completionsBefore = #completions
local test = freshTest()
local r = hitCenter(test)
check("acerto no centro e perfeito ou verde", gradeOf(r) == "Perfect" or gradeOf(r) == "Green", gradeOf(r))
check("1o acerto: sequencia 1 de 3", streakOf(r) == 1 and r.args[6] == 3, streakOf(r))
check("1 acerto nao conclui", #completions == completionsBefore and System.IsRepairing(alice))

r = hitCenter((nextTest()))
check("2o acerto: sequencia 2 de 3", streakOf(r) == 2, streakOf(r))
check("2 acertos nao concluem", #completions == completionsBefore and System.IsRepairing(alice))

r = hitCenter((nextTest()))
check("3o acerto seguido chama o onComplete do objetivo", #completions == completionsBefore + 1, #completions - completionsBefore)
check("concluir encerra a sessao", not System.IsRepairing(alice))
local stop = lastOf("Stop", alice)
check("Stop marca completed com 3 de 3", stop.args[4] == true and stop.args[5] == 3 and stop.args[6] == 3)
check("concluir limpa a marca no personagem", aliceChar:GetAttribute("Reparando") == nil)

--------------------------------------------------------------------------------
-- 4. Erro zera a sequencia, faz barulho e trava
--------------------------------------------------------------------------------

completionsBefore = #completions
local noisesBefore = #noiseCalls
test = freshTest()
hitCenter(test)
r = hitCenter((nextTest()))
check("duas seguidas antes de errar", streakOf(r) == 2)

local errorAt = serverTime
r = hitRed((nextTest()))
check("fora das faixas e erro", gradeOf(r) == "Red", gradeOf(r))
check("erro ZERA a sequencia", streakOf(r) == 0, streakOf(r))
check("erro gera UM ruido", #noiseCalls == noisesBefore + 1, #noiseCalls - noisesBefore)
local noise = noiseCalls[#noiseCalls]
check("ruido sai na posicao do objetivo", noise.position == panel.Position)
check("ruido e creditado a quem errou", noise.player == alice)
check("ruido usa a intensidade configurada", noise.intensity == Config.Noise.FailIntensity)
check("ruido usa alcance escalado pela furtividade",
	noise.radius >= Config.Noise.FailRadius.Max and noise.radius <= Config.Noise.FailRadius.Min, noise.radius)
check("erro informa quanto tempo trava", r.args[7] > 0, r.args[7])

local nextAfterError, msg = nextTest()
local waited = serverTime - errorAt
check("o proximo teste so vem depois do tranco", waited >= r.args[7], string.format("esperou %.2fs, tranco %.2fs", waited, r.args[7]))
r = hitCenter(nextAfterError)
check("depois do erro recomeca do 1: 3 acertos seguidos de novo", streakOf(r) == 1 and #completions == completionsBefore, streakOf(r))

--------------------------------------------------------------------------------
-- 5. Amarelo NAO conta como acerto
--------------------------------------------------------------------------------

noisesBefore = #noiseCalls
test = freshTest()
hitCenter(test)
r = hitYellow((nextTest()))
check("faixa amarela e amarela", gradeOf(r) == "Yellow", gradeOf(r))
check("amarelo zera a sequencia (nao e acerto)", streakOf(r) == 0, streakOf(r))
check("amarelo nao faz barulho", #noiseCalls == noisesBefore)
check("amarelo nao trava", r.args[7] == 0, r.args[7])

Config.Streak.YellowBreaks = false
test = freshTest()
hitCenter(test)
r = hitYellow((nextTest()))
check("com YellowBreaks=false amarelo so nao avanca", streakOf(r) == 1, streakOf(r))
Config.Streak.YellowBreaks = true

--------------------------------------------------------------------------------
-- 6. Teste ignorado tambem zera
--------------------------------------------------------------------------------

noisesBefore = #noiseCalls
test = freshTest()
hitCenter(test)
test = nextTest()
while serverTime - test.startsAt <= Config.TestWindow(test) do tick(0.1) end
tick(0.1)
r = lastOf("Result", alice)
check("teste expirado vira Miss e zera a sequencia", gradeOf(r) == "Miss" and streakOf(r) == 0 and r.args[3] == test.id,
	string.format("%s streak %s", tostring(gradeOf(r)), tostring(streakOf(r))))
check("teste expirado tambem faz barulho", #noiseCalls > noisesBefore)

--------------------------------------------------------------------------------
-- 7. Instante mentido pelo cliente cai na hora de chegada
--------------------------------------------------------------------------------

test = freshTest()
-- O cliente alega o instante em que o marcador estaria no verde, mas o pedido
-- chega bem depois da latencia tolerada. O servidor descarta a alegacao e usa
-- a hora de chegada.
local claimed = assert(firstTimeIn(test, isHit), "o teste nao tem instante de acerto")
tick(claimed + Config.Scoring.MaxInputLag + 0.2 - (serverTime - test.startsAt), 40)
local arrivalElapsed = serverTime - test.startsAt
local honestGrade = Config.Grade(test, Config.MarkerAt(test, arrivalElapsed))
check("(pre-condicao) a alegacao seria melhor que a nota honesta", not isHit(honestGrade), honestGrade)
check("(pre-condicao) o atraso passa da tolerancia", arrivalElapsed - claimed > Config.Scoring.MaxInputLag)
remotes.RepairMinigame.OnServerEvent:Fire(alice, "Hit", tokenOf(alice), test.id, claimed)
r = lastOf("Result", alice)
check("instante fora da latencia usa a hora de chegada", gradeOf(r) == honestGrade,
	string.format("alegou acerto, recebeu %s (honesto: %s)", tostring(gradeOf(r)), honestGrade))

-- Instante no FUTURO tambem e mentira: o cliente nao pode alegar um momento
-- que ainda nem chegou pra "apertar" no instante perfeito.
test = freshTest()
tick(0.05 - (serverTime - test.startsAt), 20) -- logo depois do inicio: marcador ainda na ponta
local honestNow = Config.Grade(test, Config.MarkerAt(test, serverTime - test.startsAt))
local future = assert(firstTimeIn(test, isHit))
check("(pre-condicao) o instante de acerto esta no futuro", future - (serverTime - test.startsAt) > Config.Scoring.FutureSlack)
remotes.RepairMinigame.OnServerEvent:Fire(alice, "Hit", tokenOf(alice), test.id, future)
r = lastOf("Result", alice)
check("alegar um instante no futuro vale a hora de chegada", gradeOf(r) == honestNow and not isHit(gradeOf(r)),
	string.format("%s (honesto: %s)", tostring(gradeOf(r)), honestNow))

--------------------------------------------------------------------------------
-- 8. Cancelamento: a sequencia se perde
--------------------------------------------------------------------------------

test = freshTest()
hitCenter(test)
r = hitCenter((nextTest()))
check("duas seguidas antes de cancelar", streakOf(r) == 2)
remotes.RepairMinigame.OnServerEvent:Fire(alice, "Release", tokenOf(alice))
check("soltar cancela", not System.IsRepairing(alice))
check("Stop diz que nao completou", lastOf("Stop", alice).args[4] == false)
check("cancelar limpa a marca no personagem", aliceChar:GetAttribute("Reparando") == nil)
open(alice)
check("reabrir comeca do zero", lastOf("Start", alice).args[5] == 0, lastOf("Start", alice).args[5])

System.ResetAll()
open(alice)
aliceRoot.Position = vec(90, 3, 0)
tick(0.1)
check("afastar cancela", not System.IsRepairing(alice))
check("afastar avisa o motivo", lastOf("Stop", alice).args[3] == "Você se afastou do reparo.", lastOf("Stop", alice).args[3])
aliceRoot.Position = vec(2, 3, 0)

open(alice)
damageSystem.DamageApplied:Fire(monster, alice, 15, false, "Monstro")
check("tomar dano cancela", not System.IsRepairing(alice))

open(alice)
aliceHum.Health = 0
tick(0.1)
check("morrer cancela", not System.IsRepairing(alice))
aliceHum.Health = 100

open(alice)
allow = false
tick(0.1)
check("objetivo que deixa de precisar de reparo cancela", not System.IsRepairing(alice))
allow = true

open(alice)
aliceChar:SetAttribute("PowerStunned", true)
tick(0.1)
check("stun durante o reparo cancela", not System.IsRepairing(alice))
aliceChar:SetAttribute("PowerStunned", nil)

--------------------------------------------------------------------------------
-- 9. Conserto Relampago: um acerto de graca, nunca o ultimo
--------------------------------------------------------------------------------

System.ResetAll()
check("poder sem reparo em andamento devolve nil", System.ApplyPowerBoost(alice) == nil)
open(alice)
local boosted = System.ApplyPowerBoost(alice)
check("poder devolve a Part do ponto", boosted == panel)
check("poder da 1 acerto de graca", lastOf("Streak", alice).args[3] == 1, lastOf("Streak", alice).args[3])
check("poder NAO conclui sozinho", #completions == completionsBefore or System.IsRepairing(alice))
System.ApplyPowerBoost(alice)
check("com 2 de 3 o poder e recusado (nao gasta cooldown)", System.ApplyPowerBoost(alice) == nil)
check("sobra sempre um acerto de verdade", System.IsRepairing(alice) and lastOf("Streak", alice).args[3] == 2)

-- Vale igual pra qualquer Reparo: o poder do Diego nao multiplica a vantagem dele.
local function boostSteps(multiplier)
	repairStat[alice] = multiplier
	System.ResetAll()
	open(alice)
	System.ApplyPowerBoost(alice)
	return lastOf("Streak", alice).args[3]
end
check("o poder da os mesmos acertos com Reparo baixo e alto", boostSteps(0.55) == boostSteps(1.6))
repairStat[alice] = 1

--------------------------------------------------------------------------------
-- 10. Dois jogadores no mesmo ponto: uma sequencia cada um
--------------------------------------------------------------------------------

System.ResetAll()
open(alice)
open(bruno)
check("dois sobreviventes reparam juntos", System.IsRepairing(alice) and System.IsRepairing(bruno))
local aliceTest = nextTest(alice)
local brunoTest = nextTest(bruno)
r = hitCenter(aliceTest, alice)
check("o acerto de um nao conta pro outro", streakOf(r) == 1 and lastOf("Result", bruno) == nil)
r = hitRed(brunoTest, bruno)
check("o erro de um nao zera a sequencia do outro", gradeOf(r) == "Red" and streakOf(lastOf("Result", alice)) == 1)

--------------------------------------------------------------------------------
-- 11. Reparo alto e MUITO mais facil, mas nunca automatico
--------------------------------------------------------------------------------

local function tuningFor(multiplier)
	repairStat[alice] = multiplier
	local t = Config.Tuning(alice)
	repairStat[alice] = 1
	return t
end
local marina, rafael, kevin, diego = tuningFor(0.55), tuningFor(0.76), tuningFor(1.3), tuningFor(1.6)

check("Reparo alto tem area verde maior", diego.greenScale > kevin.greenScale and kevin.greenScale > rafael.greenScale
	and rafael.greenScale > marina.greenScale)
check("Reparo alto tem marcador MAIS LENTO (periodo maior)",
	diego.periodScale > rafael.periodScale and rafael.periodScale > marina.periodScale,
	string.format("Diego %.2f, Rafael %.2f, Marina %.2f", diego.periodScale, rafael.periodScale, marina.periodScale))
check("Reparo alto trava menos ao errar", diego.stallScale < rafael.stallScale and rafael.stallScale < marina.stallScale)
check("Reparo baixo tem marcador que oscila de velocidade; alto quase constante",
	marina.wobbleAmp > rafael.wobbleAmp and rafael.wobbleAmp > diego.wobbleAmp and diego.wobbleAmp < 0.05)

-- Janela real (segundos) em que o marcador esta dentro do verde, nos testes que
-- o servidor de fato gera. E o numero que o jogador sente.
local function greenWindow(multiplier)
	repairStat[alice] = multiplier
	local t = freshTest()
	repairStat[alice] = 1
	System.ResetAll()
	return 2 * t.greenHalf * t.period, t
end
local marinaWindow = greenWindow(0.55)
local weakWindow, weakTest = greenWindow(0.76)
local strongWindow, strongTest = greenWindow(1.56)
print(string.format("     janelas: Marina %.0f ms | Rafael %.0f ms | Diego %.0f ms",
	marinaWindow * 1000, weakWindow * 1000, strongWindow * 1000))
check("Rafael (Reparo 20) tem uma janela MUITO apertada (<= 55 ms)", weakWindow <= 0.055, weakWindow)
check("Marina/Bruno (Reparo 10) ainda mais apertada (<= 40 ms)", marinaWindow <= 0.040, marinaWindow)
check("Diego continua jogavel (>= 100 ms)", strongWindow >= 0.100, strongWindow)
check("teste do Rafael e ~3x mais apertado que o do Diego", strongWindow >= weakWindow * 2.5,
	string.format("Rafael %.0fms, Diego %.0fms", weakWindow * 1000, strongWindow * 1000))
check("o marcador do Diego e mais lento que o do Rafael", strongTest.period > weakTest.period)
check("o teste do Rafael leva oscilacao de velocidade", (weakTest.wobbleAmp or 0) > 0.08 and weakTest.wobbleFreq ~= nil)
check("nem o Diego ganha a barra inteira", strongTest.greenHalf * 2 <= 0.35, strongTest.greenHalf * 2)

-- Com oscilacao o marcador continua nascendo na ponta e dentro da barra.
local inBounds = true
for step = 0, 400 do
	local x = Config.MarkerAt(weakTest, step * 0.01)
	if x < 0 or x > 1 then inBounds = false end
end
check("marcador oscilante nasce na ponta esquerda", Config.MarkerAt(weakTest, 0) == 0
	and Config.MarkerAt(weakTest, 0.0001) < 0.05)
check("marcador oscilante nunca sai da barra", inBounds)

-- A matematica do marcador e a mesma dos dois lados.
local sample = { id = 1, startsAt = 0, period = 1, sweeps = 3, center = 0.5,
	greenHalf = 0.08, yellowHalf = 0.14, perfectHalf = 0.03, style = 1 }
check("marcador comeca na esquerda", Config.MarkerAt(sample, 0) == 0)
check("marcador chega na direita no fim da travessia", math.abs(Config.MarkerAt(sample, 1) - 1) < 1e-6)
check("marcador volta (vai e vem)", math.abs(Config.MarkerAt(sample, 2)) < 1e-6)
check("centro e perfeito", Config.Grade(sample, 0.5) == "Perfect")
check("borda do verde e verde", Config.Grade(sample, 0.57) == "Green")
check("faixa amarela e amarela", Config.Grade(sample, 0.62) == "Yellow")
check("fora de tudo e vermelho", Config.Grade(sample, 0.9) == "Red")

--------------------------------------------------------------------------------
-- 12. Choque 3D no gerador: qualquer erro de reparo, quem errou + Monstro, com cooldown
--------------------------------------------------------------------------------

local function shocksTo(who)
	local n = 0
	for _, m in sent do
		if m.remote == "GeneratorErrorSound" and (who == nil or m.player == who) then n += 1 end
	end
	return n
end
local function openGenerator()
	for _, m in sent do
		if m.remote == "RepairMinigame" and m.args[1] == "Test" then m.consumed = true end
	end
	wallClock += 1
	generatorPrompt.Triggered:Fire(alice)
	assert(System.IsRepairing(alice), "a sessao no gerador nao abriu")
	return (nextTest(alice))
end
-- O ritmo natural entre dois erros (tranco + intervalo) ja fica perto dos 3s do
-- cooldown real, entao aqui o cooldown e longo pra testar a supressao sem
-- depender de sorte; resetShockCooldown "passa o tempo" entre os cenarios.
gameConfig.RadioSite.ErroGerador.Cooldown = 30
local function resetShockCooldown() wallClock += 40; serverTime += 40 end

-- Os erros das secoes anteriores tambem tocam o choque agora (qualquer erro de
-- reparo toca), entao esta secao conta a partir de uma linha de base.
local base = { [alice] = shocksTo(alice), [bruno] = shocksTo(bruno), [monster] = shocksTo(monster) }
local function since(who) return shocksTo(who) - base[who] end

System.ResetAll()
resetShockCooldown()

-- Erro no gerador -> quem errou E o Monstro recebem, apontando pra Part do gerador.
local before = shocksTo()
test = openGenerator()
hitRed(test)
check("quem errou OUVE o choque", since(alice) == 1, since(alice))
check("o Monstro tambem ouve", since(monster) == 1, since(monster))
check("o choque aponta pra Part do gerador", (function()
	for i = #sent, 1, -1 do
		if sent[i].remote == "GeneratorErrorSound" then return sent[i].args[1] == generator end
	end
	return false
end)())
check("os outros sobreviventes NAO ouvem (nada e tocado globalmente)", since(bruno) == 0, since(bruno))
check("so duas mensagens no total (quem errou + Monstro)", shocksTo() == before + 2, shocksTo() - before)

-- Erros seguidos dentro do cooldown nao empilham (nem pra quem errou).
tick(0.5, 10)
test = nextTest(alice)
hitRed(test)
check("segundo erro dentro do cooldown NAO toca de novo", since(alice) == 1 and since(monster) == 1,
	string.format("alice %d, monstro %d", since(alice), since(monster)))

-- Teste ignorado (Miss) tambem conta, depois do cooldown.
System.ResetAll()
resetShockCooldown()
test = openGenerator()
while serverTime - test.startsAt <= Config.TestWindow(test) do tick(0.1) end
tick(0.1)
check("teste ignorado no gerador tambem toca o choque (quem errou + Monstro)",
	since(alice) == 2 and since(monster) == 2, string.format("alice %d, monstro %d", since(alice), since(monster)))

-- Passado o cooldown, um novo erro toca de novo.
System.ResetAll()
resetShockCooldown()
test = openGenerator()
hitRed(test)
check("apos o cooldown o choque toca de novo", since(alice) == 3 and since(monster) == 3,
	string.format("alice %d, monstro %d", since(alice), since(monster)))

-- Monstro alem da distancia maxima: o servidor nem envia pra ele (fica mudo
-- de qualquer jeito), mas quem errou continua ouvindo.
System.ResetAll()
resetShockCooldown()
local monsterRoot = monster.Character:FindFirstChild("HumanoidRootPart")
monsterRoot.Position = vec(500, 3, 10)
test = openGenerator()
hitRed(test)
check("Monstro alem da distancia maxima nao recebe", since(monster) == 3, since(monster))
check("...mas quem errou continua ouvindo", since(alice) == 4, since(alice))
monsterRoot.Position = vec(4, 3, 10)

-- Monstro morto nao recebe; quem errou ouve.
System.ResetAll()
resetShockCooldown()
monster.Character:FindFirstChildOfClass("Humanoid").Health = 0
test = openGenerator()
hitRed(test)
check("Monstro morto nao recebe", since(monster) == 3, since(monster))
check("...e quem errou ouve", since(alice) == 5, since(alice))
monster.Character:FindFirstChildOfClass("Humanoid").Health = 100

-- Erro em QUALQUER ponto de reparo (aqui o painel, longe do gerador) toca o
-- choque, e ele toca na posicao do GERADOR -- nao na de quem errou.
System.ResetAll()
resetShockCooldown()
before = shocksTo()
test = freshTest()
hitRed(test)
check("erro no painel tambem toca o choque", shocksTo() == before + 2, shocksTo() - before)
check("...e ele aponta pro GERADOR, nao pro painel", (function()
	for i = #sent, 1, -1 do
		if sent[i].remote == "GeneratorErrorSound" then return sent[i].args[1] == generator end
	end
	return false
end)())

-- Uma tarefa pode ficar de fora do choque.
Config.Tasks.RadioPainel.GeneratorShock = false
System.ResetAll()
resetShockCooldown()
before = shocksTo()
test = freshTest()
hitRed(test)
check("GeneratorShock = false tira a tarefa do choque", shocksTo() == before)
Config.Tasks.RadioPainel.GeneratorShock = nil

-- Sem gerador registrado (mapa antigo): nada toca, e nada quebra.
GeneratorSound.SetGenerator(nil)
System.ResetAll()
resetShockCooldown()
before = shocksTo()
test = freshTest()
hitRed(test)
check("sem gerador registrado nao toca nada (e o reparo segue normal)", shocksTo() == before and System.IsRepairing(alice))
GeneratorSound.SetGenerator(generator)

-- Desligado na config: nada.
gameConfig.RadioSite.ErroGerador.Enabled = false
System.ResetAll()
resetShockCooldown()
test = openGenerator()
hitRed(test)
check("Enabled = false desliga o choque", shocksTo() == before)
gameConfig.RadioSite.ErroGerador.Enabled = true
gameConfig.RadioSite.ErroGerador.Cooldown = 3

--------------------------------------------------------------------------------
-- 13. Limpeza
--------------------------------------------------------------------------------

System.ResetAll()
open(alice)
check("sessao aberta para o teste de fim de rodada", System.IsRepairing(alice))
roundManager.RoundEnded:Fire()
check("fim de rodada derruba tudo", not System.IsRepairing(alice))
check("fim de rodada limpa a marca no personagem", aliceChar:GetAttribute("Reparando") == nil)

open(alice)
check("sessao aberta para o teste de keep-alive", System.IsRepairing(alice))
autoKeepAlive = false -- o cliente travou/desconectou: para de confirmar
wallClock += 5
tick(0.1)
check("cliente que para de confirmar perde a sessao", not System.IsRepairing(alice))

if failures > 0 then
	error(string.format("%d verificacao(oes) falharam", failures), 0)
end
print(string.format("\nrepair_minigame: todas as verificacoes passaram (%d mensagens de servidor).", #sent))
