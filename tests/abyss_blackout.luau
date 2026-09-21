-- Real module sources are injected by run_abyss_blackout.py; only Roblox
-- services are mocked. Cobre os 15 pontos de validação pedidos para o
-- Apagão do Abismo (registro no instante, saída da área, entrada tardia,
-- Fear uma única vez, expiração, cooldown, morte/respawn/saída).
local function near(a, b, message)
	assert(math.abs(a - b) < 1e-6, (message or "mismatch") .. ": " .. tostring(a) .. " / " .. tostring(b))
end
local function signal()
	local self = { listeners = {} }
	function self:Connect(callback)
		local connection = { Connected = true, callback = callback }
		function connection:Disconnect() self.Connected = false end
		table.insert(self.listeners, connection)
		return connection
	end
	function self:Fire(...)
		for _, c in table.clone(self.listeners) do if c.Connected then c.callback(...) end end
	end
	function self:Count()
		local n = 0
		for _, c in self.listeners do if c.Connected then n += 1 end end
		return n
	end
	return self
end
local function object(class)
	local self = { ClassName = class, attributes = {}, children = {}, Parent = nil }
	function self:GetAttribute(key) return self.attributes[key] end
	function self:SetAttribute(key, value) self.attributes[key] = value end
	function self:IsA(key) return key == class or (class == "Part" and key == "BasePart") end
	function self:FindFirstChild(key) return self.children[key] end
	function self:FindFirstChildOfClass(key)
		for _, child in self.children do if child:IsA(key) then return child end end
		return nil
	end
	function self:IsDescendantOf(ancestor) return self.ancestor == ancestor end
	return self
end
local cframeMeta = {}
cframeMeta.__mul = function(a) return a end
local function cframe() return setmetatable({}, cframeMeta) end
local vectorMeta = {}
local function vector(x, y, z) return setmetatable({ X = x, Y = y, Z = z }, vectorMeta) end
vectorMeta.__sub = function(a, b) return vector(a.X - b.X, a.Y - b.Y, a.Z - b.Z) end
vectorMeta.__add = function(a, b) return vector(a.X + b.X, a.Y + b.Y, a.Z + b.Z) end
vectorMeta.__mul = function(a, b) return vector(a.X * b, a.Y * b, a.Z * b) end
vectorMeta.__index = function(a, key)
	if key == "Magnitude" then return math.sqrt(a.X * a.X + a.Y * a.Y + a.Z * a.Z) end
	if key == "Unit" then return vector(a.X / a.Magnitude, a.Y / a.Magnitude, a.Z / a.Magnitude) end
	if key == "Dot" then return function(_, b) return a.X * b.X + a.Y * b.Y + a.Z * b.Z end end
end
local players = { PlayerAdded = signal(), PlayerRemoving = signal(), list = {} }
function players:GetPlayers() return table.clone(self.list) end
local heartbeat = signal()
local runService = { Heartbeat = heartbeat, IsServer = function() return true end }
local moduleNames = setmetatable({}, { __index = function(_, key) return key end })
local active = false
local round = { RoundPrepared = { Event = signal() }, RoundEnded = { Event = signal() },
	IsRoundActive = function() return active end }
-- Dois relógios controlados: serverTime é o Workspace:GetServerTimeNow() que
-- expira as sessões; clock é o os.clock() que mede cooldown e anti-duplicação.
local serverTime, clock = 1000, 0
local world = { children = {} }
world.DescendantAdded = signal()
world.attributes = {}
function world:SetAttribute(name, value) self.attributes[name] = value end
function world:GetAttribute(name) return self.attributes[name] end
function world:GetDescendants() return {} end
function players:GetPlayerFromCharacter(character)
	for _, p in self.list do if p.Character == character then return p end end
	return nil
end
function world:Raycast() return nil end
function world:GetServerTimeNow() return serverTime end
local services = { Players = players, RunService = runService, Workspace = world,
	ReplicatedStorage = { Modules = moduleNames } }
-- Remote duplo: guarda tudo que sai do servidor e nada mais.
local sent, broadcast = {}, {}
local onServer = signal()
local remote = {
	OnServerEvent = onServer,
	FireClient = function(_, player, ...) table.insert(sent, { player = player, args = { ... } }) end,
	FireAllClients = function(_, ...) table.insert(broadcast, { ... }) end,
}
local forcedOff = {}
local flashlight = { ForceOff = function(character)
	table.insert(forcedOff, character)
	for _, tool in character.lamps or {} do tool.on = false end
	return 0
end }
local logs, warnings = {}, {}
local delayed = {}
local environment = setmetatable({
	game = { GetService = function(_, name) return assert(services[name], name) end },
	script = { Parent = moduleNames },
	print = function(message) table.insert(logs, message) end,
	warn = function(message) table.insert(warnings, message) end,
	Vector3 = { new = vector },
	CFrame = { new = function() return cframe() end, Angles = function() return cframe() end },
	Color3 = { new = function(...) return { ... } end, fromRGB = function(...) return { ... } end },
	RaycastParams = { new = function() return {} end },
	os = setmetatable({ clock = function() return clock end }, { __index = os }),
	task = { delay = function(seconds, callback) table.insert(delayed, { at = seconds, callback = callback }) end },
	typeof = function(value)
		if type(value) == "table" and value.ClassName then return "Instance" end
		return type(value)
	end,
	Enum = { RaycastFilterType = { Exclude = "Exclude" }, Material = { Air = "Air", Water = "Water" },
		HumanoidStateType = { Swimming = "Swimming" },
		KeyCode = { E = "E", R = "R", X = "X", ButtonX = "ButtonX", ButtonB = "ButtonB", ButtonR1 = "ButtonR1" } },
	Random = { new = function() return { NextNumber = function() return 0.999 end } end },
	Instance = { new = function(class)
		assert(class == "BindableEvent")
		local s = signal()
		return { Event = s, Fire = function(_, ...) s:Fire(...) end }
	end },
}, { __index = getfenv() })
local modules = {
	SurvivorPowerStatus = { RegisterStunInterruptor = function(callback)
		environment.interruptFlash = callback
	end },
	RoundManager = round,
	LoadoutData = { GetPerk = function() return nil end },
	Remotes = { AbyssBlackout = remote, SprintIntent = { OnServerEvent = signal() } },
	FlashlightSystem = flashlight,
	FlashlightConfig = { BlockingFlags = { "GrabLocked", "ShadowRushBusy", "TeleportBusy",
		"PowerStunned", "Amarrado", "AbyssBlackout" } },
}
local function loadModule(name)
	if modules[name] then return modules[name] end
	local chunk = assert(loadstring(assert(sources[name], name), name))
	setfenv(chunk, environment)
	modules[name] = chunk()
	return modules[name]
end
environment.require = loadModule
local config = loadModule("GameConfig")
local CFG = config.Monster.AbyssBlackout
local scaling = loadModule("StatScaling")
local rules = loadModule("AbyssBlackoutRules")
loadModule("FearRules")
local fear = loadModule("FearSystem")
local ability = loadModule("AbyssBlackout")

--------------------------------------------------------------------------------
-- Configuração: a habilidade tem de viver na escala real do Fear existente
--------------------------------------------------------------------------------
near(config.Fear.MaxFear, 100, "escala de Fear esperada")
assert(CFG.Radius == 150, "raio configurável de 150 studs")
assert(CFG.Duration == 12, "duração fixa de 12 s")
assert(CFG.Cooldown >= 60 and CFG.Cooldown <= 90, "cooldown entre 60 e 90 s")
near(CFG.Fear / config.Fear.MaxFear, 0.35, "aumento inicial em 35% do teto")
assert(CFG.Radius > config.Monster.Attack.Range and CFG.Radius <= config.Fear.MaxFearDistance,
	"raio grande, mas dentro da zona de perigo do Fear")

--------------------------------------------------------------------------------
-- Matemática pura
--------------------------------------------------------------------------------
near(rules.FearAmount(35, 1, 0.5, 100), 35, "Compostura neutra = pontos cheios")
near(rules.FearAmount(35, 1.5, 0.5, 100), 43.75, "Compostura 0 sofre mais")
near(rules.FearAmount(35, 0.55, 0.5, 100), 27.125, "Compostura 100 sofre um pouco menos")
assert(rules.FearAmount(35, 0.55, 0.5, 100) > 35 * 0.55 + 1e-6,
	"influence suaviza: não é o multiplicador cru do Fear por segundo")
near(rules.FearAmount(35, 1, 0.5, 20), 20, "nunca passa do teto informado")
near(rules.FearAmount(0, 1, 0.5, 100), 0)
near(rules.FearAmount(35, 0 / 0, 0.5, 100), 35, "NaN cai no neutro")
assert(rules.InRadius(vector(0, 0, 0), vector(149, 0, 0), 150))
assert(not rules.InRadius(vector(0, 0, 0), vector(151, 0, 0), 150))
assert(rules.InRadius(vector(0, 0, 0), vector(0, 150, 0), 150), "distância é 3D")
near(rules.Remaining(1012, 1000), 12)
near(rules.Remaining(1000, 1012), 0, "nunca negativo")
local peak = rules.Presentation(CFG.PulseAttack, CFG.Duration, CFG)
assert(peak.Opacity > CFG.SustainOpacity, "pulso inicial forte")
local mid = rules.Presentation(CFG.Duration / 2, CFG.Duration, CFG)
assert(mid.Opacity > 0 and mid.Opacity < peak.Opacity, "escuridão sustentada abaixo do pico")
near(rules.Presentation(CFG.Duration, CFG.Duration, CFG).Opacity, 0, "zero no fim: nada permanente")
near(rules.Presentation(CFG.Duration + 5, CFG.Duration, CFG).Opacity, 0)
near(rules.Presentation(-1, CFG.Duration, CFG).Opacity, 0)

--------------------------------------------------------------------------------
-- Cenário
--------------------------------------------------------------------------------
local function character(x)
	local c, h, root = object("Model"), object("Humanoid"), object("Part")
	c.ancestor, c.Parent = world, world
	c.ChildAdded = signal()
	c.lamps = { { on = true } } -- "lanterna ligada" só pro duplo do ForceOff
	h.Health, h.Died, h.Parent = 100, signal(), c
	h.WalkSpeed, h.FloorMaterial, h.Sit = 12, "Ground", false
	function h:GetState() return "Running" end
	root.Position, root.Parent, root.Anchored = vector(x, 0, 0), c, false
	root.AssemblyLinearVelocity = vector(0, 0, 0)
	function root:CanSetNetworkOwnership() return true end
	function root:GetNetworkOwnershipAuto() return true end
	function root:GetNetworkOwner() return nil end
	function root:SetNetworkOwner() end
	function root:SetNetworkOwnershipAuto() end
	c.children.Humanoid, c.children.HumanoidRootPart = h, root
	return c, h, root
end
local function player(name, role, x, composure)
	local p = object("Player")
	p.Name, p.Parent = name, players
	p.CharacterAdded, p.CharacterRemoving = signal(), signal()
	p.Character = character(x)
	p:SetAttribute("Role", role)
	p:SetAttribute("InRound", true)
	p:SetAttribute("Stat_Compostura", composure)
	table.insert(players.list, p)
	players.PlayerAdded:Fire(p)
	return p
end
local function move(p, x) p.Character.children.HumanoidRootPart.Position = vector(x, 0, 0) end
-- use() respeita o limitador de entrada (um pedido por CFG.InputInterval);
-- spam() é o duplo-clique de verdade, no mesmo instante.
local function spam(p) onServer:Fire(p, "Use") end
local function use(p) clock += CFG.InputInterval + 0.001; spam(p) end
local function tick(seconds)
	local step = config.Fear.FearUpdateInterval
	for _ = 1, math.max(1, math.floor(seconds / step + 0.5)) do
		serverTime += step
		clock += step
		heartbeat:Fire(step)
	end
end
local function messages(p, kind)
	local found = {}
	for _, entry in sent do
		if entry.player == p and entry.args[1] == kind then table.insert(found, entry) end
	end
	return found
end
local function blocked(p)
	return p.Character:GetAttribute("AbyssBlackout") == true
end

local monster = player("Monster", config.Roles.Monster, 0, 85)
local inside = player("Inside", config.Roles.Survivor, 40, 50) -- sai da área depois
local stays = player("Stays", config.Roles.Survivor, -60, 50)
local outside = player("Outside", config.Roles.Survivor, 400, 50) -- entra depois
local dead = player("Dead", config.Roles.Survivor, 20, 50)
local lobby = player("Lobby", config.Roles.Survivor, 10, 50)
lobby:SetAttribute("InRound", false)

fear.Init()
ability.Init(); ability.Init() -- idempotente: nenhuma conexão duplicada
assert(heartbeat:Count() == 2, "uma conexão de Heartbeat por sistema: " .. heartbeat:Count())
assert(onServer:Count() == 1, "um único listener do remote")
assert(players.PlayerRemoving:Count() == 2, "um PlayerRemoving por sistema")

-- Fora da rodada não ativa.
use(monster)
assert(not blocked(inside) and #broadcast == 0, "sem rodada ativa não faz nada")
active = true
round.RoundPrepared.Event:Fire()
for _, flag in { "FlashPowerBlocked", "PowerStunned" } do
	monster.Character:SetAttribute(flag, true)
	use(monster)
	assert(not blocked(inside) and monster:GetAttribute("AbyssBlackoutReadyAt") == nil,
		"blocked monster cannot cast R through the remote")
	monster.Character:SetAttribute(flag, nil)
end

-- (1) (2) (3) Dois sobreviventes dentro; só eles são registrados.
local before = { inside = fear.GetFear(inside), stays = fear.GetFear(stays), outside = fear.GetFear(outside) }
use(monster)
assert(blocked(inside) and blocked(stays), "quem estava dentro foi registrado")
assert(not blocked(outside), "quem estava fora não foi tocado")
assert(not blocked(lobby), "quem não está na rodada não é alvo")
assert(not blocked(monster), "o próprio Monstro nunca é alvo")
near(#messages(monster, "Result"), 1)
assert(messages(monster, "Result")[1].args[2] == 3, "registrou os 3 de dentro (inside, stays, dead)")
assert(#broadcast == 1 and broadcast[1][1] == "Cast", "um único aviso de mundo")
assert(#forcedOff == 3 and inside.Character.lamps[1].on == false, "lanterna apagada na hora")
assert(#messages(inside, "Hit") == 1 and messages(inside, "Hit")[1].args[2] == CFG.Duration,
	"o cliente recebe só duração/fim")

-- Duplo-clique no MESMO instante: o limitador de entrada e o lockout de
-- ativação seguram; nada de segunda fotografia da área nem de Fear dobrado.
spam(monster); spam(monster)
near(#messages(monster, "Result"), 1, "ativação duplicada ignorada")
assert(#broadcast == 1, "e nenhum segundo aviso de mundo")

-- (8) Fear subiu UMA vez, no valor esperado pela Compostura de cada um.
local expected = rules.FearAmount(CFG.Fear, scaling.FearGainMultiplier(inside),
	CFG.ComposureInfluence, config.Fear.MaxFear)
-- Compostura 50 fica em ~1x pela curva existente (ComposureGainExponent 0.93).
assert(math.abs(expected - 35) < 0.05, "Compostura média recebe ~35 pontos: " .. tostring(expected))
near(fear.GetFear(inside) - before.inside, expected, "aplicado uma única vez")
near(fear.GetFear(outside), before.outside, "quem estava fora não ganhou Fear")

-- (4) (5) Sair da área NÃO remove o efeito, e não soma mais Fear.
move(inside, 5000)
local afterHit = fear.GetFear(inside)
tick(4)
assert(blocked(inside), "saiu da área e continua com a lanterna bloqueada")
-- (9) Nada de Fear por frame: longe do monstro o Fear só CAI pela regra normal.
assert(fear.GetFear(inside) <= afterHit + 1e-9, "não sobe a cada frame")
assert(fear.GetFear(inside) < afterHit, "a recuperação passiva normal continua valendo")
near(#messages(inside, "Hit"), 1, "nenhuma segunda aplicação")

-- (6) (7) Quem entra na área DEPOIS da ativação não é afetado.
local beforeEntering = fear.GetFear(outside)
move(outside, 0) -- entra no centro da área DEPOIS da ativação
tick(1)
assert(not blocked(outside), "entrar depois não pega o efeito")
assert(#messages(outside, "Hit") == 0, "e não recebe nada do Apagão")
-- O Fear dele sobe só pela proximidade normal do FearSystem: o ganho tem de
-- caber no teto por segundo do próprio Fear, o que o salto de 35 estouraria.
local entryGain = fear.GetFear(outside) - beforeEntering
assert(entryGain > 0 and entryGain <= config.Fear.MaxFearGainPerSecond * 1.0 + 1e-6,
	"sem salto de Fear da habilidade: " .. tostring(entryGain))
assert(entryGain < expected, "o ganho é o de proximidade, não o do Apagão")

-- (14) Morte limpa o efeito na hora.
assert(blocked(dead))
dead.Character.children.Humanoid.Health = 0
dead.Character.children.Humanoid.Died:Fire()
assert(not blocked(dead), "morte limpa o bloqueio")
assert(#messages(dead, "End") == 1, "e avisa o cliente")

-- (13) Cooldown: reativar antes do tempo é recusado, sem tocar em ninguém.
local caught = #messages(monster, "Result")
move(stays, -10)
local stayFear = fear.GetFear(stays)
use(monster)
near(#messages(monster, "Result"), caught, "segunda ativação recusada")
assert(#messages(monster, "Rejected") == 1, "e o Monstro é avisado")
near(fear.GetFear(stays), stayFear, "recusa não aplica Fear")

-- (10) (11) (12) Fim do tempo: lanterna volta, Fear NÃO é resetado.
serverTime += CFG.Duration
tick(0.4)
assert(not blocked(inside) and not blocked(stays), "o efeito expira sozinho")
assert(inside.Character:GetAttribute("AbyssBlackoutUntil") == nil, "nenhum resíduo de Attribute")
assert(#messages(inside, "End") == 1, "o cliente recebe o fim uma única vez")
assert(fear.GetFear(stays) > 0, "o Fear permanece pelas regras normais do sistema")
assert(not ability.IsBlinded(inside) and not ability.IsBlinded(stays))

-- Respawn (mudança de character) durante o efeito.
local ready = monster:GetAttribute("AbyssBlackoutReadyAt")
assert(ready and ready > serverTime - CFG.Duration, "cooldown publicado em atributo do servidor")
round.RoundEnded.Event:Fire()
round.RoundPrepared.Event:Fire()
assert(monster:GetAttribute("AbyssBlackoutReadyAt") == nil, "rodada nova limpa o cooldown")
move(inside, 30) -- de volta pra dentro: nova ativação, novo registro
use(monster)
assert(blocked(stays) and blocked(inside), "cooldown zerado pela rodada nova")
local oldCharacter = stays.Character
stays.Character = character(-60)
stays.CharacterRemoving:Fire(oldCharacter)
assert(oldCharacter:GetAttribute("AbyssBlackout") == nil, "respawn limpa o corpo antigo")
assert(not blocked(stays), "e o corpo novo nasce livre")

-- Saída do jogador durante o efeito.
assert(blocked(inside))
players.PlayerRemoving:Fire(inside)
assert(not ability.IsBlinded(inside), "sair da partida limpa a sessão")
assert(inside:GetAttribute("AbyssBlackoutReadyAt") == nil)

-- Fim de rodada limpa todo mundo.
use(monster)
active = false
round.RoundEnded.Event:Fire()
for _, p in players.list do assert(not blocked(p), "fim de rodada não deixa ninguém cego") end

-- (15) Nenhum warn/erro no Output em todo o roteiro.
assert(#warnings == 0, "Output limpo, sem avisos: " .. tostring(warnings[1]))
-- Entrada inválida vinda do cliente é ignorada em silêncio.
onServer:Fire(monster, "Hack")
onServer:Fire(monster, nil)
onServer:Fire(monster, "Use", 999, vector(0, 0, 0))
assert(#warnings == 0, "argumento inesperado não quebra o servidor")

print("[AbyssBlackout] todos os testes passaram")
active = true
round.RoundPrepared.Event:Fire()
use(monster)
assert(blocked(outside), "new cast still works after clearing power block")
environment.interruptFlash(monster.Character)
assert(not blocked(outside) and not monster.Character:GetAttribute("AbyssBlackoutCasting"),
	"flash interruption cancels existing blackout through cleanup")
for _, callback in delayed do callback.callback() end
assert(world:GetAttribute("AbyssWorldBlackout") ~= true, "cancelled delayed cast cannot turn world lights off")
print("PASS: real R gate, cast interruption, survivor cleanup and delayed blackout cancellation")
for _, message in logs do print(message) end
