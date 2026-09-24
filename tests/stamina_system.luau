--!nocheck
-- StaminaSystem, StatScaling, GameConfig e LoadoutData REAIS (via
-- run_stamina_system.py); jogador, personagem, Heartbeat e rede são dublês.
-- Prova o fluxo que o anel da HUD desenha:
--   correndo -> "Stamina" cai até EXATAMENTE 0 (e fica 0 enquanto exausto);
--   parou -> depois do RegenDelay sobe até EXATAMENTE "StaminaMax";
--   curva/ladeira (velocidade abaixo de 1,35x) com o pacote em corrida
--   continua gastando -- era aqui que a barra "descolava" do jogo.

local stub = loadstring(sources.RobloxStub, "RobloxStub")()

local function Signal()
	local handlers = {}
	return {
		Connect = function(_, fn) table.insert(handlers, fn) return { Disconnect = function() end } end,
		Fire = function(_, ...) for _, fn in table.clone(handlers) do fn(...) end end,
	}
end

local heartbeat = Signal()
stub.Services.RunService = { Heartbeat = heartbeat, IsRunning = function() return true end }

local player = Instance.new("Folder")
player.Name = "Ana"
rawget(player, "_props").CharacterAdded = Signal()
local players = { player }
stub.Services.Players = {
	GetPlayers = function() return players end,
	PlayerAdded = Signal(),
	PlayerRemoving = Signal(),
	GetPlayerFromCharacter = function() return player end,
}

local character = Instance.new("Model")
local humanoid = Instance.new("Humanoid")
humanoid.Health = 100
local humanoidState = Enum.HumanoidStateType.Running
rawget(humanoid, "_props").GetState = function() return humanoidState end
humanoid.Parent = character
local root = Instance.new("Part")
root.Name = "HumanoidRootPart"
root.AssemblyLinearVelocity = Vector3.new(0, 0, 0)
root.Parent = character
player.Character = character

local intentSignal = Signal()
local modules = {}
local tokens
tokens = setmetatable({}, { __index = function(t, key)
	local token = setmetatable({ __module = key }, { __index = function(_, k) return tokens[k] end })
	rawset(t, key, token)
	return token
end })
local env
local function loadModule(name)
	if modules[name] then return modules[name] end
	local fn = assert(loadstring(assert(sources[name], name), name))
	setfenv(fn, env)
	modules[name] = fn()
	return modules[name]
end
env = setmetatable({
	script = { Parent = tokens },
	require = function(token) return loadModule(token.__module) end,
}, { __index = getfenv() })
game:GetService("ReplicatedStorage").Modules = {
	GameConfig = tokens.GameConfig, Remotes = tokens.Remotes, StatScaling = tokens.StatScaling, LoadoutData = tokens.LoadoutData,
}
modules.Remotes = { SprintIntent = { OnServerEvent = intentSignal } }
modules.FearSystem = { GetStaminaRegenMultiplier = function() return 1 end }
local gameplay = true
modules.MatchStateService = { IsGameplayEnabled = function() return gameplay end }

local checks = 0
local function check(c, m, ...) checks += 1 if not c then error(string.format(m, ...), 0) end end

local GameConfig = loadModule("GameConfig")
local StatScaling = loadModule("StatScaling")
local Stamina = loadModule("StaminaSystem")
Stamina.MovementSampled = Signal() -- BindableEvent do stub não tem :Fire
Stamina.Init()

local walk = StatScaling.WalkSpeed(player)
local function setSpeed(multiple) root.AssemblyLinearVelocity = Vector3.new(walk * multiple, 0, 0) end
local function intent(value) intentSignal:Fire(player, value) end
local function tick(seconds)
	for _ = 1, math.floor(seconds / 0.05 + 0.5) do heartbeat:Fire(0.05) end
end
local function value() return player:GetAttribute("Stamina") end

check(player:GetAttribute("StaminaMax") == Stamina.Max() and Stamina.Max() > 0, "o servidor publica o teto real")
check(value() == Stamina.Max(), "começa cheio")

-- 1) Correndo em linha reta: desce e zera EXATAMENTE.
intent(true)
setSpeed(1.92)
local samples = {}
for _ = 1, 400 do
	tick(0.05)
	table.insert(samples, value())
	if value() == 0 then break end
end
check(value() == 0, "correndo até o fim o fôlego zera (veio %s)", tostring(value()))
for i = 2, #samples do
	check(samples[i] <= samples[i - 1], "correndo o fôlego nunca sobe")
end
check(player:GetAttribute("StaminaExausto") == true, "zerou = exausto")
check(root:GetAttribute("CanSprint") == false and root:GetAttribute("ForceStopSprint") == true, "zerou: portão da corrida fecha")

-- Exausto (o portão fechou, corrida parou): fica em 0 durante todo o
-- RegenDelay, contado a partir do momento em que parou de gastar.
setSpeed(1.0)
tick(GameConfig.Characters.StaminaRegenDelay - 0.1)
check(value() == 0, "dentro do RegenDelay o fôlego esgotado continua 0")

-- 2) Parou: sobe até EXATAMENTE o teto.
intent(false)
setSpeed(0)
local rising = {}
for _ = 1, 600 do
	tick(0.05)
	table.insert(rising, value())
	if value() == Stamina.Max() then break end
end
check(value() == Stamina.Max(), "recuperou até o teto exato (veio %s)", tostring(value()))
for i = 2, #rising do
	check(rising[i] >= rising[i - 1], "recuperando o fôlego nunca desce")
end
check(player:GetAttribute("StaminaExausto") == nil and root:GetAttribute("CanSprint") == true, "recuperado: pode correr de novo")

-- 3) O BUG: pacote em corrida numa curva/ladeira (1,1x o andar, abaixo do
--    limiar 1,35x) continuava "não correndo" pro servidor e chegava a
--    RECUPERAR com o personagem correndo. Agora gasta.
intent(true)
setSpeed(1.1)
local before = value()
tick(3)
check(value() < before - 20, "correndo em curva/ladeira tem que gastar (foi de %s pra %s)", tostring(before), tostring(value()))

-- 4) Parado com Shift/intenção: não gasta. Andando sem intenção: não gasta.
local drained = value()
setSpeed(0)
tick(3)
check(value() >= drained, "parado não gasta, mesmo com a intenção ligada")
intent(false)
setSpeed(1.0)
local walking = value()
tick(3)
check(value() >= walking, "andando sem correr não gasta")

-- 5) Fora da partida o fôlego fica cheio (e a HUD some); de volta, segue igual.
gameplay = false
tick(0.1)
check(value() == Stamina.Max(), "fora da partida o fôlego fica cheio")
gameplay = true

-- 6) Pulo custa na hora (é o que faz a barra "pular" um pedaço).
local beforeJump = value()
humanoidState = Enum.HumanoidStateType.Jumping
tick(0.05)
humanoidState = Enum.HumanoidStateType.Running
check(value() <= beforeJump - 29, "pulo gasta o custo fixo de uma vez")

print(string.format("PASS: StaminaSystem; %d verificações", checks))
