--!nocheck
-- BoatSystem REAL (servidor do barco de fuga) com dublês determinísticos:
-- jogadores, assentos, prompts, remotes e relógio virtual. BoatRules e a
-- GameConfig são os de produção; construção, física do engine e itens são
-- dublês (a física de verdade está em tests/boat.studio.luau).
for name, source in sources do assert(loadstring(source, name)) end
loadstring(sources.Stub, "Stub")()
local Config = loadstring(sources.GameConfig, "GameConfig")()
local CFG = Config.Boat

local checks = 0
local function check(condition, message)
	checks += 1
	if not condition then
		error("FAIL: " .. message, 2)
	end
end

--------------------------------------------------------------------------------
-- Matemática que falta no stub (CFrame:Inverse/ToObjectSpace/Lerp, Rotation)
--------------------------------------------------------------------------------

local CFrameM = getmetatable(CFrame.identity)
local oldIndex = CFrameM.__index
function CFrameM.Inverse(self)
	local r, u, b = self.RightVector, self.UpVector, -self.LookVector
	local p = self.Position
	return CFrame.fromMatrix(Vector3.new(-p:Dot(r), -p:Dot(u), -p:Dot(b)),
		Vector3.new(r.X, u.X, b.X), Vector3.new(r.Y, u.Y, b.Y), Vector3.new(r.Z, u.Z, b.Z))
end
function CFrameM.ToObjectSpace(self, other)
	return self:Inverse() * other
end
function CFrameM.Lerp(self, other, t)
	local base = if t < 0.5 then self else other
	return CFrame.new(self.Position + (other.Position - self.Position) * t) * base.Rotation
end
CFrameM.__index = function(self, key)
	if key == "Rotation" then
		return CFrame.fromMatrix(Vector3.zero, self.RightVector, self.UpVector, -self.LookVector)
	end
	return oldIndex(self, key)
end
local Vector3M = getmetatable(Vector3.zero)
function Vector3M.Lerp(a, b, t)
	return a + (b - a) * t
end

--------------------------------------------------------------------------------
-- Relógio virtual, sinais e objetos falsos
--------------------------------------------------------------------------------

local now = 0
local scheduled = {}
local function signal()
	local s = { listeners = {} }
	function s:Connect(fn)
		local c = { Connected = true, fn = fn }
		function c:Disconnect() self.Connected = false end
		table.insert(self.listeners, c)
		return c
	end
	function s:Once(fn)
		local c
		c = self:Connect(function(...) c:Disconnect(); fn(...) end)
		return c
	end
	function s:Fire(...)
		for _, c in table.clone(self.listeners) do
			if c.Connected then c.fn(...) end
		end
	end
	return s
end

local CLASSES = {
	Part = { Part = true, BasePart = true },
	Seat = { Seat = true, BasePart = true },
	VehicleSeat = { VehicleSeat = true, BasePart = true },
	Model = { Model = true },
	Humanoid = { Humanoid = true },
	Player = { Player = true },
}

local function obj(className, props)
	local fields = { Name = className, children = {}, attrs = {}, attrSignals = {}, propSignals = {} }
	for k, v in props or {} do fields[k] = v end
	local methods = {}
	local self
	self = setmetatable({}, {
		__index = function(_, key)
			if methods[key] then return methods[key] end
			return fields[key]
		end,
		__newindex = function(_, key, value)
			if key == "Parent" then
				local old = fields.Parent
				if old then
					local list = old.children
					local i = table.find(list, self)
					if i then table.remove(list, i) end
				end
				if value then table.insert(value.children, self) end
			end
			local changed = fields[key] ~= value
			fields[key] = value
			if changed and fields.propSignals[key] then fields.propSignals[key]:Fire() end
		end,
	})
	function methods:IsA(name)
		local classes = CLASSES[className]
		return name == className or name == "Instance" or (classes ~= nil and classes[name] == true)
	end
	function methods:GetAttribute(key) return fields.attrs[key] end
	function methods:SetAttribute(key, value)
		local old = fields.attrs[key]
		fields.attrs[key] = value
		if old ~= value and fields.attrSignals[key] then fields.attrSignals[key]:Fire() end
	end
	function methods:GetAttributeChangedSignal(key)
		fields.attrSignals[key] = fields.attrSignals[key] or signal()
		return fields.attrSignals[key]
	end
	function methods:GetPropertyChangedSignal(key)
		fields.propSignals[key] = fields.propSignals[key] or signal()
		return fields.propSignals[key]
	end
	function methods:GetChildren() return table.clone(fields.children) end
	function methods:GetDescendants()
		local out = {}
		for _, c in fields.children do
			table.insert(out, c)
			for _, d in c:GetDescendants() do table.insert(out, d) end
		end
		return out
	end
	function methods:FindFirstChild(name, recursive)
		for _, c in (if recursive then self:GetDescendants() else fields.children) do
			if c.Name == name then return c end
		end
		return nil
	end
	function methods:FindFirstChildOfClass(name)
		for _, c in fields.children do
			if c:IsA(name) then return c end
		end
		return nil
	end
	function methods:IsDescendantOf(ancestor)
		local p = fields.Parent
		while p do
			if p == ancestor then return true end
			p = p.Parent
		end
		return false
	end
	function methods:Destroy()
		for _, c in table.clone(fields.children) do c:Destroy() end
		self.Parent = nil
		fields.destroyed = true
	end
	return self, methods, fields
end

--------------------------------------------------------------------------------
-- Serviços
--------------------------------------------------------------------------------

local Workspace = obj("Workspace")
function Workspace:GetServerTimeNow() return now end
local ReplicatedStorage = obj("ReplicatedStorage")
ReplicatedStorage.Modules = setmetatable({}, { __index = function(_, name) return name end })

local Players = obj("Players")
Players.PlayerRemoving = signal()
Players.PlayerAdded = signal()
function Players:GetPlayers() return self:GetChildren() end
function Players:GetPlayerFromCharacter(character)
	for _, p in self:GetPlayers() do
		if p.Character == character then return p end
	end
	return nil
end

local Heartbeat = signal()
local RunService = { Heartbeat = Heartbeat, IsStudio = function() return false end }

local sent = {}
local function remote(name)
	local r = { OnServerEvent = signal(), OnClientEvent = signal() }
	function r:FireClient(player, ...)
		table.insert(sent, { remote = name, player = player, args = { ... } })
	end
	function r:FireAllClients(...)
		table.insert(sent, { remote = name, all = true, args = { ... } })
	end
	return r
end
local Remotes = setmetatable({}, { __index = function(t, name)
	local r = remote(name)
	rawset(t, name, r)
	return r
end })
local function lastSent(remoteName, player, action)
	for i = #sent, 1, -1 do
		local s = sent[i]
		if s.remote == remoteName and (player == nil or s.player == player or s.all)
			and (action == nil or s.args[1] == action) then
			return s
		end
	end
	return nil
end
local function messagesFor(player)
	local out = {}
	for _, s in sent do
		if s.remote == "LobbyMessage" and s.player == player then table.insert(out, s.args[1]) end
	end
	return out
end
local function lastMessage(player)
	local list = messagesFor(player)
	return list[#list] or ""
end

--------------------------------------------------------------------------------
-- Jogadores
--------------------------------------------------------------------------------

local nextUserId = 100
local function newPlayer(name, role)
	nextUserId += 1
	local player = obj("Player", { Name = name, UserId = nextUserId })
	player:SetAttribute("Role", role)
	player:SetAttribute("InRound", true)
	local character = obj("Model", { Name = name })
	local humanoid, hm = obj("Humanoid", { Health = 100, Sit = false })
	function hm:UnequipTools() end
	humanoid.Parent = character
	local root = obj("Part", { Name = "HumanoidRootPart", Position = Vector3.new(0, 5, 0) })
	root.Parent = character
	character.Parent = Workspace
	player.Character = character
	player.Parent = Players
	return player, character, humanoid
end

--------------------------------------------------------------------------------
-- O barco falso (Layout) e os dublês dos módulos vizinhos
--------------------------------------------------------------------------------

local SEA = CFG.RaioChegada - 150
local home = CFrame.lookAt(Vector3.new(SEA, 4, 0), Vector3.new(SEA + 10, 4, 0))
local boatCF = home
local model, modelMethods = obj("Model", { Name = "BarcoFuga" })
model.Parent = Workspace
function modelMethods:GetPivot() return boatCF end
function modelMethods:PivotTo(cf) boatCF = cf end
local owner = "server"
local root, rootMethods = obj("Part", { Name = "Fundo", Anchored = false,
	AssemblyLinearVelocity = Vector3.zero, AssemblyAngularVelocity = Vector3.zero })
root.Parent = model
function rootMethods:SetNetworkOwner(player) owner = player or "server" end
function rootMethods:GetNetworkOwner() return if owner == "server" then nil else owner end
local frame = setmetatable({}, { __index = function(_, key)
	if key == "WorldCFrame" then return boatCF end
	if key == "WorldPosition" then return boatCF.Position end
	return nil
end })

local function makeSeat(className, name, offset)
	local seat, seatMethods = obj(className, { Name = name, Disabled = false, Occupant = nil })
	seat.Position = (home * CFrame.new(offset)).Position
	seat.Parent = model
	function seatMethods:Sit(humanoid)
		local weld, weldMethods = obj("Weld", { Name = "SeatWeld" })
		weld.Parent = seat
		function weldMethods:Destroy()
			weld.Parent = nil
			if seat.Occupant == humanoid then
				humanoid.Sit = false
				humanoid.SeatPart = nil
				seat.Occupant = nil
			end
		end
		humanoid.Sit = true
		humanoid.SeatPart = seat
		seat.Occupant = humanoid
	end
	return seat
end
local helm = makeSeat("VehicleSeat", "AssentoPiloto", Vector3.new(0, 1.4, 2.9))
local seats = {}
for i = 1, CFG.Assentos - 1 do
	table.insert(seats, makeSeat("Seat", "Assento" .. i, Vector3.new(0, 1.4, -2 + i)))
end
local anchors = {}
for _, key in { "Motor", "Tanque", "Ignicao", "EmbarqueBB", "EmbarqueBE", "Proa", "Popa" } do
	local a = obj("Part", { Name = key })
	a.Parent = model
	anchors[key] = a
end
local light = obj("PointLight", { Enabled = false })
local glow = obj("Part", { Material = Enum.Material.SmoothPlastic })
local visuals = {}
for _, key in { "Helice", "Vela", "Chave" } do
	visuals[key] = { obj("Part", { Name = key, Transparency = 1 }) }
end
local mooring = obj("Beam", { Enabled = true })
local wiring = obj("Model", { Name = "FiacaoMotor" })
wiring:SetAttribute("Sabotavel", true)
wiring:SetAttribute("Sabotado", false)
wiring.Parent = model

local layout = {
	model = model, root = root, frame = frame, helm = helm, seats = seats, anchors = anchors,
	lights = { light }, glow = { glow }, visuals = visuals, moorings = { mooring }, wiring = wiring,
	home = home, length = 21.5, width = 7, isDefault = true, itemSpots = { home },
}

local surface = "Agua"
local probe = function(_) return 4, 30 end
local steps = 0
local BoatPhysicsFake = {
	FrameName = "QuadroBarco",
	Bind = function() return { fake = true } end,
	Sample = function() return { waterY = 4, center = 20, bow = 20, stern = 20, surface = surface } end,
	Step = function() steps += 1; return {} end,
	Reset = function() end,
	Probe = function(point) return probe(point) end,
}

local carried = {}
local consumed = {}
local itemResets = 0
local BoatItemsFake = {
	Init = function() end,
	Reset = function() itemResets += 1 end,
	Carried = function(player, itemId)
		return carried[player] and carried[player][itemId] or nil
	end,
	Consume = function(tool)
		consumed[tool] = true
		for _, bag in carried do
			for itemId, t in bag do
				if t == tool then bag[itemId] = nil end
			end
		end
	end,
}
local function give(player, itemId)
	carried[player] = carried[player] or {}
	local tool = { itemId = itemId }
	carried[player][itemId] = tool
	return tool
end

local repairStarts = {}
local RepairFake = {
	Start = function(player, spec) table.insert(repairStarts, { player = player, spec = spec }) end,
	ResetTask = function() end,
}
local reachable = true
local noiseCalls = {}
local roundPrepared = signal()
local matchState = "InMatch"
local modules = {
	Stub = true,
	GameConfig = Config,
	Remotes = Remotes,
	BoatRules = nil, -- carregado de verdade
	BoatPhysics = BoatPhysicsFake,
	BoatBuilder = {
		Build = function() return layout end,
		BuildFinishRing = function() return obj("Folder") end,
	},
	BoatItems = BoatItemsFake,
	InteractionGuard = { CanReach = function() return reachable end },
	MatchStateService = {
		Get = function() return matchState end,
		IsGameplayEnabled = function(p) return p:GetAttribute("InRound") == true end,
	},
	RepairMinigameSystem = RepairFake,
	NoiseService = {
		EmitNoise = function(_, player, position, intensity, radius)
			table.insert(noiseCalls, { player = player, position = position, intensity = intensity, radius = radius })
			return true
		end,
	},
	RoundManager = { RoundPrepared = { Event = roundPrepared } },
}

local env = setmetatable({
	game = { GetService = function(_, name)
		return ({ Players = Players, ReplicatedStorage = ReplicatedStorage, RunService = RunService, Workspace = Workspace })[name]
	end },
	script = { Parent = setmetatable({}, { __index = function(_, name) return name end }) },
	task = {
		delay = function(t, fn, ...) table.insert(scheduled, { at = now + t, fn = fn, args = { ... } }) end,
		defer = function(fn, ...) table.insert(scheduled, { at = now, fn = fn, args = { ... } }) end,
		spawn = function(fn, ...) fn(...) end,
	},
	os = { clock = function() return now end, time = function() return now end },
	print = function() end,
	warn = function() end,
	Instance = { new = function(className)
		if className == "BindableEvent" then
			local event = signal()
			return { Event = event, Fire = function(_, ...) event:Fire(...) end }
		end
		local o = obj(className)
		if className == "ProximityPrompt" then
			o.Triggered = signal()
			o.PromptButtonHoldBegan = signal()
			o.PromptButtonHoldEnded = signal()
			o.Enabled = true
		end
		return o
	end },
}, { __index = getfenv() })
env.require = function(name)
	if modules[name] == nil then
		local fn = assert(loadstring(sources[name], name))
		setfenv(fn, env)
		modules[name] = fn()
	end
	return modules[name]
end

local function advance(seconds, dt)
	dt = dt or 1 / 30
	local target = now + seconds
	while now < target - 1e-9 do
		now = math.min(target, now + dt)
		for _, item in table.clone(scheduled) do
			if item.at <= now then
				table.remove(scheduled, table.find(scheduled, item))
				item.fn(table.unpack(item.args))
			end
		end
		Heartbeat:Fire(dt)
	end
end

--------------------------------------------------------------------------------
-- Cenários
--------------------------------------------------------------------------------

local Boat = env.require("BoatSystem")
Boat.Init()
local function prompt(host, name)
	return host:FindFirstChild(name)
end
local install = prompt(anchors.Motor, "InstalarPecaBarco")
local refuel = prompt(anchors.Tanque, "AbastecerBarco")
local keyPrompt = prompt(anchors.Ignicao, "ChaveBarco")
local pilot = prompt(helm, "PilotarBarco")
local boardBB = prompt(anchors.EmbarqueBB, "EmbarcarBarco")
local pushBow = prompt(anchors.Proa, "EmpurrarBarco")
check(install and refuel and keyPrompt and pilot and boardBB and pushBow and prompt(anchors.EmbarqueBE, "EmbarcarBarco")
	and prompt(anchors.Popa, "EmpurrarBarco"), "Init cria todos os prompts nos pontos do barco")
local boatRef = ReplicatedStorage:FindFirstChild("BarcoFuga")
check(boatRef and boatRef.Value == model, "referência do barco publicada")
check(itemResets == 1 and model:GetAttribute("HeliceInstalada") == false and model:GetAttribute("MotorLigado") == false,
	"Init zera o barco e espalha as peças")
check(mooring.Enabled and light.Enabled == false, "amarrado e apagado")

advance(0.5)
check(install.Enabled and refuel.Enabled and keyPrompt.Enabled and pilot.Enabled and boardBB.Enabled and not pushBow.Enabled,
	"na partida os prompts de montar/abastecer/chave/pilotar/embarcar ligam; empurrar não")
matchState = "Lobby"
advance(0.5)
check(not install.Enabled and not pilot.Enabled, "fora da partida nenhum prompt do barco fica ligado")
matchState = "InMatch"
advance(0.5)

local ana, anaChar, anaHum = newPlayer("Ana", Config.Roles.Survivor)
local bia, _, biaHum = newPlayer("Bia", Config.Roles.Survivor)
local spy, _, spyHum = newPlayer("Espiao", Config.Roles.Spy)
local monster, _, monsterHum = newPlayer("Monstro", Config.Roles.Monster)

-- Mapa: o barco vira marcador pra quem está na partida.
roundPrepared:Fire({ ana, bia, spy, monster })
local mapEntry = lastSent("MapDiscovery", monster)
check(mapEntry and mapEntry.args[1].key == "barco-fuga" and mapEntry.args[1].category == "Escape", "barco marcado no mapa de todos")

-- Monstro não embarca nem pilota.
pilot.Triggered:Fire(monster)
boardBB.Triggered:Fire(monster)
check(helm.Occupant == nil and monsterHum.Sit == false, "Monstro não senta no barco")

-- Ana pilota: vira dona da física, com os Attributes do assento.
pilot.Triggered:Fire(ana)
check(helm.Occupant == anaHum and model:GetAttribute("PilotoId") == ana.UserId, "Ana no timão, PilotoId publicado")
check(anaChar:GetAttribute("BarcoAssento") == "Piloto" and ana:GetAttribute("NoBarco") == true, "Attributes do piloto")
check(owner == ana, "o piloto vira dono de rede do barco")
check(lastSent("BoatControl", ana, "Assento").args[3] == "Piloto", "cliente avisado do assento")
pilot.Triggered:Fire(bia)
check(helm.Occupant == anaHum and string.find(lastMessage(bia), "timão", 1, true), "timão ocupado recusa o segundo")

-- Motor sem nada montado não liga e explica.
Remotes.BoatControl.OnServerEvent:Fire(ana, "Motor")
check(not model:GetAttribute("DandoPartida") and string.find(lastMessage(ana), "hélice", 1, true), "sem peças o motor não liga")
Remotes.BoatControl.OnServerEvent:Fire(bia, "Motor")
check(not model:GetAttribute("DandoPartida"), "só o piloto dá partida")

-- Montar: o prompt abre o minigame; o onComplete instala a peça que a pessoa tem.
local helice = give(bia, "HeliceBarco")
local vela = give(bia, "VelaIgnicao")
install.Triggered:Fire(spy)
check(#repairStarts == 0 and string.find(lastMessage(spy), "Sobreviventes", 1, true), "Espião não mexe no motor")
install.Triggered:Fire(bia)
local session = repairStarts[#repairStarts]
check(session and session.player == bia and session.spec.configId == "BarcoMotor", "instalar abre o reparo de precisão")
local canStart = session.spec.canStart(bia)
check(canStart == true, "com peça na mão o reparo pode começar")
local okAna, whyAna = session.spec.canStart(ana)
check(okAna == false and string.find(whyAna, "hélice", 1, true), "sem peça o reparo recusa com o motivo")
session.spec.onComplete(bia)
check(model:GetAttribute("HeliceInstalada") == true and consumed[helice] and visuals.Helice[1].Transparency == 0,
	"hélice instalada, consumida e visível")
check(model:GetAttribute("VelaInstalada") ~= true, "uma peça por vez")
session.spec.onComplete(bia)
check(model:GetAttribute("VelaInstalada") == true and consumed[vela] and visuals.Vela[1].Transparency == 0, "vela instalada")
session.spec.onComplete(bia)
check(true, "instalar de novo sem peça não quebra")

-- Abastecer: só vale segurando o tempo todo, e consome a Gasolina.
local gas = give(bia, "Gasolina")
refuel.Triggered:Fire(bia)
check(model:GetAttribute("Abastecido") ~= true and not consumed[gas], "sem segurar não abastece")
refuel.PromptButtonHoldBegan:Fire(bia)
advance(1)
refuel.Triggered:Fire(bia)
check(model:GetAttribute("Abastecido") ~= true, "soltou antes do tempo não abastece")
refuel.PromptButtonHoldBegan:Fire(bia)
advance(CFG.HoldAbastecer)
refuel.Triggered:Fire(bia)
check(model:GetAttribute("Abastecido") == true and consumed[gas], "segurou o tempo todo: tanque cheio, galão consumido")

-- Sem a chave o motor não liga; com a chave no bolso do piloto, liga.
Remotes.BoatControl.OnServerEvent:Fire(ana, "Motor")
check(not model:GetAttribute("DandoPartida") and string.find(lastMessage(ana), "chave", 1, true), "sem chave não liga")
local key = give(ana, "ChaveBarco")
local startedBy
Boat.EngineStarted.Event:Connect(function(player) startedBy = player end)
Remotes.BoatControl.OnServerEvent:Fire(ana, "Motor")
check(model:GetAttribute("ChaveInserida") == true and consumed[key] and model:GetAttribute("DandoPartida") == true,
	"a chave do bolso vai pra ignição e o motor de arranque gira")
check(model:GetAttribute("MotorLigado") ~= true, "ainda não pegou durante a partida")
advance(CFG.TempoPartida + 0.1)
check(model:GetAttribute("MotorLigado") == true and not model:GetAttribute("DandoPartida"), "motor pega depois do arranque")
check(light.Enabled and glow.Material == Enum.Material.Neon and not mooring.Enabled, "luzes acendem e as amarras soltam")
check(startedBy == ana, "primeira partida conta como objetivo concluído")
local startNoise = noiseCalls[#noiseCalls]
check(startNoise and startNoise.player == ana and startNoise.radius == CFG.RuidoPartida, "motor pegando faz barulho pro Monstro")
check(string.find(lastMessage(monster), "motor de barco", 1, true), "Monstro é avisado do motor")
check(lastSent("ObjectiveProgress", nil, "BarcoLigado"), "aviso de motor ligado pra todos")

-- Motor ligado continua fazendo barulho a cada intervalo.
local before = #noiseCalls
advance(CFG.RuidoIntervalo + 0.2)
check(#noiseCalls > before and noiseCalls[#noiseCalls].radius == CFG.RuidoRaioLento, "motor ligado parado ronca em marcha lenta")

-- Passageira embarca pelo costado; o Espião também pode.
boardBB.Triggered:Fire(bia)
check(biaHum.Sit and biaHum.SeatPart ~= helm and bia:GetAttribute("NoBarco") == true, "Bia embarca como passageira")
check(lastSent("BoatControl", bia, "Assento").args[3] == "Passageiro", "passageira avisada")
boardBB.Triggered:Fire(spy)
check(spyHum.Sit, "Espião embarca")

-- Sabotagem: motor apaga e não religa até consertar.
wiring:SetAttribute("Sabotado", true)
check(model:GetAttribute("MotorLigado") == false, "fiação cortada apaga o motor")
check(string.find(lastMessage(bia), "fiação", 1, true), "quem está a bordo é avisado")
Remotes.BoatControl.OnServerEvent:Fire(ana, "Motor")
check(not model:GetAttribute("DandoPartida") and string.find(lastMessage(ana), "fiação", 1, true), "sabotado não dá partida")
wiring:SetAttribute("Sabotado", false)
Remotes.BoatControl.OnServerEvent:Fire(ana, "Motor")
advance(CFG.TempoPartida + 0.1)
check(model:GetAttribute("MotorLigado") == true, "consertado, liga de novo")

-- F de novo desliga.
Remotes.BoatControl.OnServerEvent:Fire(ana, "Motor")
check(model:GetAttribute("MotorLigado") == false, "F desliga o motor")
Remotes.BoatControl.OnServerEvent:Fire(ana, "Motor")
advance(CFG.TempoPartida + 0.1)
check(model:GetAttribute("MotorLigado") == true, "e liga de novo")

-- Anti-teleporte: um salto impossível volta pra última posição válida.
advance(0.3)
local safe = boatCF
boatCF = boatCF + Vector3.new(300, 0, 0)
advance(0.15)
check((boatCF.Position - safe.Position).Magnitude < 1, "teleporte de 300 studs é desfeito")
check(owner ~= ana, "durante a correção o servidor segura o barco")
advance(0.8)
check(owner == ana, "depois da correção o piloto volta a ser dono")

-- Rede engasgada: parado 0,6s e depois um salto de ~30 studs é legítimo.
advance(0.6)
local beforeBurst = boatCF
boatCF = boatCF + Vector3.new(30, 0, 0)
advance(0.15)
check((boatCF.Position - beforeBurst.Position).Magnitude > 29, "rajada de rede depois de engasgo não é punida")

-- ENCALHE: sonda sem água no meio do casco -> motor morre.
surface = "Encalhado"
advance(0.6)
check(model:GetAttribute("Encalhado") == true and model:GetAttribute("MotorLigado") == false, "encalhou: motor morre")
check(string.find(lastMessage(ana), "encalhou", 1, true), "piloto avisado do encalhe")
Remotes.BoatControl.OnServerEvent:Fire(ana, "Motor")
check(not model:GetAttribute("DandoPartida") and string.find(lastMessage(ana), "empurre", 1, true), "encalhado não liga")
advance(0.3) -- prompts são reavaliados a cada 0,25s
check(pushBow.Enabled, "prompt de empurrar aparece")

-- Quem está sentado não empurra; alguém a pé empurra pra água funda.
local cara = newPlayer("Cara", Config.Roles.Survivor)
pushBow.PromptButtonHoldBegan:Fire(bia)
advance(CFG.HoldEmpurrar)
pushBow.Triggered:Fire(bia)
check(model:GetAttribute("Encalhado") == true and not root.Anchored, "sentado não empurra")
probe = function(point)
	-- Terra perto da proa atual, água funda a mais de 10 studs.
	local d = (Vector3.new(point.X, 0, point.Z) - Vector3.new(boatCF.Position.X, 0, boatCF.Position.Z)).Magnitude
	return 4, if d > 10 then 30 else nil
end
pushBow.PromptButtonHoldBegan:Fire(cara)
advance(CFG.HoldEmpurrar)
pushBow.Triggered:Fire(cara)
check(root.Anchored, "empurrando: o script move o barco")
surface = "Agua"
local frames = 0
while root.Anchored and frames < 200 do
	advance(1 / 30)
	frames += 1
end
check(not root.Anchored and model:GetAttribute("Encalhado") == false, "voltou pra água, desencalhado")
check(owner == ana, "o piloto retoma a física depois do empurrão")
-- No MESMO frame em que o empurrão acabou (antes de qualquer tique): F já vale.
Remotes.BoatControl.OnServerEvent:Fire(ana, "Motor")
check(model:GetAttribute("DandoPartida") == true, "logo depois do empurrão, F já dá partida")
advance(CFG.TempoPartida + 0.1)
check(model:GetAttribute("MotorLigado") == true, "depois de empurrado, liga de novo")

-- Levantar do timão devolve o barco ao servidor.
advance(0.3)
helm:FindFirstChild("SeatWeld"):Destroy()
advance(0.2)
check(model:GetAttribute("PilotoId") == 0 and owner ~= ana and ana:GetAttribute("NoBarco") == nil, "saiu do timão: servidor assume")
check(lastSent("BoatControl", ana, "Saiu"), "cliente avisado que saiu")
check(steps > 0, "sem piloto o servidor roda a física em ponto morto")
pilot.Triggered:Fire(ana)
check(helm.Occupant == anaHum and owner == ana, "voltou pro timão")

-- LIMITE: cruzar o anel com gente a bordo começa a cena e depois dá a vitória.
local escaped
Boat.SurvivorsEscaped.Event:Connect(function(list) escaped = list end)
local pos = boatCF.Position
local dir = Vector3.new(pos.X, 0, pos.Z).Unit
while (Vector3.new(boatCF.Position.X, 0, boatCF.Position.Z)).Magnitude < CFG.RaioChegada + 2 do
	boatCF = boatCF + dir * 4
	advance(0.1)
end
advance(0.2)
check(Boat.IsEscaping() and root.Anchored, "cruzou o limite: cena de fuga, barco ancorado")
local fuga = lastSent("BoatControl", nil, "Fuga")
check(fuga and fuga.all and fuga.args[2] == model and getmetatable(fuga.args[3]) == CFrameM
	and fuga.args[5] == CFG.DuracaoCinematica, "todos os clientes recebem a cena")
local ids = fuga.args[6]
check(table.find(ids, ana.UserId) and table.find(ids, bia.UserId) and table.find(ids, spy.UserId)
	and not table.find(ids, cara.UserId), "só quem estava sentado a bordo entra na cena")
check(anaChar:GetAttribute("Invulneravel") == true, "a bordo ficam invulneráveis na cena")
check(not pilot.Enabled and not boardBB.Enabled, "prompts desligados na cena")
check(escaped == nil, "a vitória espera a cena acabar")
advance(CFG.DuracaoCinematica + 0.2)
check(escaped and #escaped == 3, "fim da cena: SurvivorsEscaped com quem estava a bordo")
check(lastSent("ObjectiveProgress", nil, "BarcoFugiu"), "aviso de fuga pra todos")

-- Fim da rodada e reset.
Boat.EndRound()
check(helm.Occupant == nil and not anaHum.Sit and not biaHum.Sit, "fim da rodada: ninguém fica sentado")
Boat.Reset()
check(not Boat.IsEscaping() and not root.Anchored and (boatCF.Position - home.Position).Magnitude < 1e-6, "reset: barco de volta ao cais")
for _, step in { "HeliceInstalada", "VelaInstalada", "Abastecido", "ChaveInserida", "MotorLigado", "Encalhado", "Escapando" } do
	check(model:GetAttribute(step) == false, "reset zera " .. step)
end
check(visuals.Helice[1].Transparency == 1 and mooring.Enabled and not light.Enabled, "reset desmonta, amarra e apaga")
check(itemResets == 2, "reset espalha peças novas")

-- Morrer sentado libera o assento.
advance(0.3)
boardBB.Triggered:Fire(bia)
check(biaHum.Sit, "Bia embarca de novo")
biaHum.Health = 0
advance(0.3)
check(not biaHum.Sit and bia:GetAttribute("NoBarco") == nil, "morreu sentada: assento liberado")

-- Lotação.
local extra = {}
for i = 1, CFG.Assentos do
	local p = newPlayer("Extra" .. i, Config.Roles.Survivor)
	boardBB.Triggered:Fire(p)
	table.insert(extra, p)
end
check(string.find(lastMessage(extra[#extra]), "lotado", 1, true), "barco lotado recusa")

print(string.format("PASS boat_system: %d checks (assentos, motor, montagem, gasolina, chave, sabotagem, encalhe, empurrão, anti-teleporte, limite, cena e reset)", checks))
