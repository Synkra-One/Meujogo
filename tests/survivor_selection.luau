-- Roblox service doubles. The runner injects the real module sources above.
local function signal()
	local listeners = {}
	return {
		Connect = function(_, callback) table.insert(listeners, callback) end,
		Fire = function(_, ...) for _, callback in listeners do callback(...) end end,
	}
end

local function object(class)
	local attributes, children = {}, {}
	local result = { ClassName = class, Name = class }
	function result:SetAttribute(key, value) attributes[key] = value end
	function result:GetAttribute(key) return attributes[key] end
	function result:FindFirstChild(name) return children[name] end
	function result:WaitForChild(name) return children[name] end
	function result:FindFirstChildOfClass(name)
		for _, child in children do if child.ClassName == name then return child end end
		return nil
	end
	function result:IsA(name) return name == class or (name == "BasePart" and class == "Part") end
	function result:PivotTo(cf) self.LastPivot = cf end
	result._children = children
	return setmetatable(result, { __newindex = function(t, key, value)
		rawset(t, key, value)
		if key == "Parent" and value and value._children then value._children[t.Name] = t end
	end })
end

local vectorMeta = { __add = function(a, b) return { X = a.X + b.X, Y = a.Y + b.Y, Z = a.Z + b.Z } end }
local Vector3Mock = { new = function(x, y, z) return setmetatable({ X = x, Y = y, Z = z }, vectorMeta) end }
local Color3Mock = { fromRGB = function(...) return { ... } end, new = function(...) return { ... } end }
local clock = 100
local delayed = {}
local spawned = {}
local Tasks = {
	delay = function(seconds, callback) table.insert(delayed, { at = clock + seconds, callback = callback }) end,
	defer = function(callback) callback() end,
	spawn = function(callback) table.insert(spawned, callback) end,
	wait = function(seconds) clock += seconds or 0 end,
}

local function advance(seconds)
	clock += seconds
	local previous = delayed
	delayed = {}
	for _, pending in previous do
		if pending.at <= clock then pending.callback() else table.insert(delayed, pending) end
	end
end

local function flushSpawned()
	while #spawned > 0 do
		local pending = spawned
		spawned = {}
		for _, callback in pending do callback() end
	end
end

local players = object("Players")
players.PlayerAdded = signal()
players.PlayerRemoving = signal()
local playerList = {}
function players:GetPlayers() return table.clone(playerList) end

local storage = object("ReplicatedStorage")
storage.Modules = setmetatable({}, { __index = function(_, key) return key end })
local workspaceMock = object("Workspace")
function workspaceMock:GetServerTimeNow() return clock end
local runService = { IsStudio = function() return true end }
local services = { Players = players, ReplicatedStorage = storage, Workspace = workspaceMock, RunService = runService }

local remotes = setmetatable({}, { __index = function(t, key)
	local remote = { OnServerEvent = signal(), events = {} }
	function remote:FireClient(player, ...) table.insert(self.events, { player = player, args = { ... } }) end
	function remote:FireAllClients(...) table.insert(self.events, { args = { ... } }) end
	rawset(t, key, remote)
	return remote
end })

local started = {}
local roundStub = { RoundPrepared = { Event = signal() }, RoundEnded = { Event = signal() } }
function roundStub.IsRoundActive() return #started > 0 end
function roundStub.StartRound(participants)
	table.insert(started, table.clone(participants))
	for _, p in participants do p:SetAttribute("InRound", true) end
	roundStub.RoundPrepared.Event:Fire(participants)
end

local modules = {
	Remotes = remotes,
	RoundManager = roundStub,
	CharacterPresentation = { SpawnLobbyAvatar = function() end },
}
local cframeMeta = { __mul = function(a) return a end }
local environment = setmetatable({
	game = { GetService = function(_, name) return assert(services[name], name) end },
	script = { Parent = storage.Modules },
	Instance = { new = function(class)
		if class == "BindableEvent" then
			local event = signal()
			return { Event = event, Fire = function(_, ...) event:Fire(...) end }
		end
		return object(class)
	end },
	Color3 = Color3Mock,
	Vector3 = Vector3Mock,
	UDim2 = { fromScale = function(...) return { ... } end },
	CFrame = {
		new = function(...) return setmetatable({ ... }, cframeMeta) end,
		Angles = function(...) return setmetatable({ ... }, cframeMeta) end,
	},
	Enum = {
		Material = { WoodPlanks = "Wood" },
		NormalId = { Back = "Back" },
		Font = { GothamBold = "Bold" },
		KeyCode = { E = "E", X = "X", ButtonX = "ButtonX", ButtonB = "ButtonB" },
	},
	Random = { new = function() return { NextInteger = function(_, min) return min end } end },
	task = Tasks,
	os = { clock = function() return clock end, time = function() return clock end },
	warn = function(...) print("WARN", ...) end,
}, { __index = getfenv() })

local function loadModule(name)
	if modules[name] then return modules[name] end
	local chunk = assert(loadstring(sources[name], name))
	setfenv(chunk, environment)
	local module = chunk()
	modules[name] = module
	return module
end
environment.require = loadModule

local function player(id)
	local p = object("Player")
	p.UserId, p.Name, p.DisplayName = id, "Player" .. id, "Jogador " .. id
	p.CharacterAdded = signal()
	p.Parent = players
	p.Character = object("Model")
	table.insert(playerList, p)
	players.PlayerAdded:Fire(p)
	return p
end

local function roomRequest(p, action, value)
	clock += 0.2
	remotes.WaitingRoom.OnServerEvent:Fire(p, action, value)
end

local function pick(p, id)
	clock += 0.1
	remotes.SelectCharacter.OnServerEvent:Fire(p, "Select", id)
end

local function confirm(p)
	clock += 0.1
	remotes.SelectCharacter.OnServerEvent:Fire(p, "Confirm")
end

local function roomSnapshot()
	return remotes.WaitingRoom.events[#remotes.WaitingRoom.events].args[1]
end

local config = loadModule("GameConfig")
-- Este spec cobre também o fluxo solo; o produto mantém SoloStart desligado.
config.Testing.SoloStart = true
local data = loadModule("CharacterData")
local selectionConfig = loadModule("SurvivorSelectionConfig")
local selection = loadModule("CharacterStatsApplier")
local room = loadModule("WaitingRoomManager")
selection.Init()
room.Init()

local first = data.Characters[1].Id
local second = data.Characters[2].Id
local third = data.Characters[3].Id
local alice, bob, monster = player(1), player(2), player(3)

-- Lobby nao aceita escolha antecipada.
pick(alice, first)
assert(selection.GetChoice(alice) == nil, "lobby must reject survivor selection")

room.Join(alice)
room.Join(bob)
room.Join(monster)
roomRequest(alice, "DevRole", config.Roles.Survivor)
roomRequest(bob, "DevRole", config.Roles.Spy)
roomRequest(monster, "DevRole", config.Roles.Monster)
roomRequest(alice, "Skin", "Explorador")
roomRequest(alice, "Perk", "Folego")

roomRequest(alice, "Ready")
roomRequest(bob, "Ready")
roomRequest(monster, "Ready")

local countdown = roomSnapshot()
assert(countdown.state == "Countdown" and countdown.endsAt > clock,
	"all ready must open the five-second queue countdown")
advance(config.WaitingRoom.StartCountdownDuration)
local revealing = roomSnapshot()
assert(revealing.state == "Revealing", "countdown must reveal roles before selection")
advance(selectionConfig.RoleRevealDuration)
local opened = roomSnapshot()
assert(opened.state == "Selecting", "reveal must open the selection phase")
assert(math.abs((opened.endsAt - clock) - selectionConfig.Duration) < 0.01, "selection must use one server 30s deadline")
assert(alice:GetAttribute("CharacterSelectOpen") == true and bob:GetAttribute("CharacterSelectOpen") == true)
assert(monster:GetAttribute("CharacterSelectOpen") == nil and selection.GetChoice(monster) == "Jason")
assert(selection.GetChoice(alice) == nil and selection.GetChoice(bob) == nil, "humans start without an automatic character")

-- Tentativas podem coincidir; o primeiro Confirmar ganha a reserva definitiva.
pick(alice, second)
assert(selection.GetChoice(alice) == second and selection.GetChoice(bob) == nil)
assert(alice:GetAttribute("CharacterId") == nil,
	"selecting in the waiting area must not apply stats or alter the lobby character")
pick(bob, second)
assert(selection.GetChoice(bob) == second, "tentative choices may coincide before confirmation")
confirm(alice)
assert(selection.IsConfirmed(alice) and alice:GetAttribute("CharacterSelectOpen") == nil)
assert(alice:GetAttribute("CharacterId") == nil,
	"ready confirmation must wait for the round character before applying stats")
pick(alice, third)
assert(selection.GetChoice(alice) == second, "confirmed players cannot change their survivor")
confirm(bob)
assert(not selection.IsConfirmed(bob) and bob:GetAttribute("CharacterSelectOpen") == true,
	"server must reject a character already confirmed by another player")
pick(bob, third)
confirm(bob)
assert(roomSnapshot().state == "Starting", "all human confirmations must end selection early")
local finalRoster = remotes.CharacterRoster.events[#remotes.CharacterRoster.events]
assert(finalRoster and finalRoster.args[1].state == "Selecting",
	"final Confirm must not publish a stale Closed roster before the round starts")
flushSpawned()
assert(#started == 1 and #started[1] == 3 and roomSnapshot().state == "Playing")
assert(alice:GetAttribute("CharacterId") == second and bob:GetAttribute("CharacterId") == third,
	"confirmed survivor must already be applied before the round")

local late = player(4)
room.Join(late)
assert(late:GetAttribute("InWaitingRoom") == nil, "late joins stay outside an active match")

-- Sem clique, o fallback curto confirma automaticamente o default e inicia a partida.
room.Reset()
room.OpenLobby()
room.Join(alice)
roomRequest(alice, "DevRole", config.Roles.Survivor)
roomRequest(alice, "Ready")
advance(config.WaitingRoom.StartCountdownDuration)
assert(roomSnapshot().state == "Revealing")
advance(selectionConfig.RoleRevealDuration)
assert(roomSnapshot().state == "Selecting" and selection.GetChoice(alice) == nil)
advance(selectionConfig.AutoConfirmDelay + 0.1)
flushSpawned()
assert(#started == 2 and selection.IsConfirmed(alice), "client fallback must auto-confirm and start")
assert(alice:GetAttribute("CharacterId") == first)

-- Estados futuros bloqueados tambem sao validados pelo servidor, nao so pela UI.
room.Reset()
room.OpenLobby()
selectionConfig.Availability[first] = "Locked"
room.Join(bob)
roomRequest(bob, "DevRole", config.Roles.Survivor)
roomRequest(bob, "Ready")
advance(config.WaitingRoom.StartCountdownDuration)
advance(selectionConfig.RoleRevealDuration)
assert(selection.GetChoice(bob) == nil, "locked survivor must not be auto-selected")
pick(bob, first)
assert(selection.GetChoice(bob) == nil, "server must reject locked survivor")
pick(bob, "PersonagemInventado")
assert(selection.GetChoice(bob) == nil, "server must reject unknown survivor")
pick(bob, "Jason")
assert(selection.GetChoice(bob) == nil, "human selection must reject monster characters")
pick(bob, second)
confirm(bob)
flushSpawned()
assert(#started == 3)
selectionConfig.Availability[first] = nil

-- Uma escolha explícita permanece sendo a escolha confirmada no prazo.
room.Reset()
room.OpenLobby()
room.Join(alice)
roomRequest(alice, "DevRole", config.Roles.Survivor)
roomRequest(alice, "Ready")
advance(config.WaitingRoom.StartCountdownDuration)
advance(selectionConfig.RoleRevealDuration)
pick(alice, third)
advance(selectionConfig.Duration + 0.1)
flushSpawned()
assert(#started == 4 and selection.IsConfirmed(alice) and alice:GetAttribute("CharacterId") == third,
	"timeout must confirm the selected survivor, not replace it with the default")

-- O painel Dev pode liberar um teste solo sem alterar o modo de producao.
room.Reset()
room.OpenLobby()
config.Testing.SoloStart = false
room.Join(monster)
roomRequest(monster, "DevRole", config.Roles.Survivor)
assert(roomSnapshot().minimum == 1, "Dev role selection must allow a solo test")
roomRequest(monster, "Ready")
advance(config.WaitingRoom.StartCountdownDuration)
advance(selectionConfig.RoleRevealDuration)
assert(roomSnapshot().state == "Selecting")
advance(selectionConfig.AutoConfirmDelay + 0.1)
flushSpawned()
assert(#started == 5 and monster:GetAttribute("InRound") == true, "Dev solo test must enter the match")

-- Monstro solo pula a seleção humana, mas percorre o mesmo Starting e deve
-- chegar à partida sem o RoundManager exigir um segundo jogador.
room.Reset()
room.OpenLobby()
room.Join(monster)
roomRequest(monster, "DevRole", config.Roles.Monster)
assert(roomSnapshot().minimum == 1, "Dev monster role must allow a solo test")
roomRequest(monster, "Ready")
advance(config.WaitingRoom.StartCountdownDuration)
advance(selectionConfig.RoleRevealDuration)
flushSpawned()
assert(#started == 6 and started[6][1]:GetAttribute("Role") == config.Roles.Monster,
	"Dev monster solo test must skip human selection and enter the match")

-- Fora do modo solo e sem um papel Dev selecionado, um unico jogador nao abre a selecao.
room.Reset()
room.OpenLobby()
room.Join(monster)
roomRequest(monster, "Ready")
assert(roomSnapshot().state == "Waiting" and roomSnapshot().endsAt == 0 and roomSnapshot().minimum == 2)

-- Perks continuam mecanicos apenas durante a rodada.
local scaling = loadModule("StatScaling")
monster:SetAttribute("PerkId", "Folego")
local base = scaling.StaminaRegen(monster)
monster:SetAttribute("InRound", true)
assert(math.abs(scaling.StaminaRegen(monster) - base * 1.1) < 0.0001)

print("PASS: 30s server selection, defaults, server validation, confirmation conflicts, early start, timeout fallback, solo test, lobby and loadout integration")
