--!strict
--[[
	BoatSystem
	O barco de fuga (docs/Barco.md) -- segunda rota de fuga, independente do
	rádio/helicóptero.

	LINHA DO TEMPO
	  1. MONTAR    achar Hélice e Vela de ignição e instalar no motor
	               (reparo de precisão, igual ao rack do rádio);
	  2. ABASTECER segurar E no bocal com um Galão de Gasolina;
	  3. CHAVE     pôr a chave na ignição (ou dar partida carregando ela);
	  4. PARTIDA   sentado no timão, F / Y / botão na tela: o motor de
	               arranque gira TempoPartida e o motor pega. As amarras
	               soltam e as luzes de navegação acendem;
	  5. PILOTAR   o cliente do piloto vira dono de rede do barco e roda a
	               física (BoatPhysics) com o acelerador e o volante dele;
	  6. LIMITE    cruzou o anel de boias com alguém sentado a bordo: o
	               servidor ancora o barco, TODO cliente anima ele seguindo
	               pro mar e quem estava a bordo ganha a câmera de cinema.
	               No fim da cena, SurvivorsEscaped -> RoundManager encerra.

	ENCALHE (igual na vida real): o servidor sonda a profundidade debaixo do
	casco a 10 Hz. Sem água no meio do casco, o hélice sai da água e o MOTOR
	MORRE -- nada de "dirigir" na areia. Pra voltar, alguém a pé segura
	"Empurrar pra água": o barco desliza pra água funda mais próxima e aí dá
	pra dar partida de novo.

	AUTORIDADE
	  - Toda regra é daqui: quem senta, quem instala, quando o motor liga,
	    quando encalha, quando cruza o limite. O cliente só manda "Motor".
	  - O piloto simula a física (sem isso o barco teria o atraso da rede),
	    mas o servidor confere o deslocamento a cada tique: andou mais do
	    que o motor consegue = barco de volta pra última posição válida.
	  - Estado em Attributes do Model do barco (Persistent: existe em todo
	    cliente): HeliceInstalada, VelaInstalada, Abastecido, ChaveInserida,
	    MotorLigado, DandoPartida, Encalhado, Superficie, PilotoId, Escapando.

	QUEM PODE: Sobrevivente vivo monta/abastece/põe a chave (como no
	rádio). Sobrevivente ou Espião embarca e pilota (como no helicóptero).
	O Monstro nunca embarca. O Espião sabota a fiação do motor pelo
	SabotageSystem (o motor morre e não liga até alguém reparar).

	Uso (boot do servidor, DEPOIS de DropItemSystem/RepairMinigameSystem):
		require(script.BoatSystem).Init()
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local GameConfig = require(ReplicatedStorage.Modules.GameConfig)
local Remotes = require(ReplicatedStorage.Modules.Remotes)
local BoatRules = require(ReplicatedStorage.Modules.BoatRules)
local BoatPhysics = require(ReplicatedStorage.Modules.BoatPhysics)
local BoatBuilder = require(script.Parent.BoatBuilder)
local BoatItems = require(script.Parent.BoatItems)
local InteractionGuard = require(script.Parent.InteractionGuard)
local MatchStateService = require(script.Parent.MatchStateService)
local RepairMinigameSystem = require(script.Parent.RepairMinigameSystem)

local BoatSystem = {}

--[[
	SurvivorsEscaped:Fire(rescued)  -- fim da cena; RoundManager encerra.
	StepCompleted:Fire(player, key) -- etapa de montagem (XP por etapa).
	EngineStarted:Fire(player)      -- primeira partida da rodada (XP do objetivo).
]]
BoatSystem.SurvivorsEscaped = Instance.new("BindableEvent")
BoatSystem.StepCompleted = Instance.new("BindableEvent")
BoatSystem.EngineStarted = Instance.new("BindableEvent")

local CFG = GameConfig.Boat
local PROMPT_REFRESH = 0.25
local SETTLE_GROUNDED = 0.25 -- encalhado por tanto tempo seguido = motor morre
local SETTLE_WATER = 0.6

type Role = "Piloto" | "Passageiro"
type Seated = { character: Model, humanoid: Humanoid, seat: BasePart, role: Role }
type State = "Inativo" | "Pronto" | "Escapando"

local layout: BoatBuilder.Layout? = nil
local physics: BoatPhysics.Controller? = nil
local prompts: { [string]: ProximityPrompt } = {}
local seated: { [Player]: Seated } = {}
local driver: Player? = nil
local state: State = "Inativo"
local escapeRescued: { Player } = {}
local roundToken = 0
local crankToken = 0
local startedOnce = false
local pushing = false
local surface: BoatRules.Surface = "Agua"
local lastEnv: BoatPhysics.Env? = nil
local groundedSince = 0
local waterSince = 0
local lastValid: CFrame? = nil
local lastValidAt = 0
local correctingUntil = 0
local refuelStarted: { [Player]: number } = {}
local pushStarted: { [Player]: number } = {}
local lastEngineNoise = 0
-- Carregados no Init (NoiseService e RoundManager dão require um no outro
-- e no BoatSystem: no topo do arquivo isso fecharia um ciclo de require).
local noiseService: any = nil
local initialized = false

--------------------------------------------------------------------------------
-- Estado
--------------------------------------------------------------------------------

local function boatModel(): Model?
	return if layout then layout.model else nil
end

local function getFlag(name: string): boolean
	local model = boatModel()
	return model ~= nil and model:GetAttribute(name) == true
end

local function setAttr(name: string, value: any)
	local model = boatModel()
	if model and model:GetAttribute(name) ~= value then
		model:SetAttribute(name, value)
	end
end

local function requirements(): BoatRules.Requirements
	return {
		HeliceInstalada = getFlag("HeliceInstalada"),
		VelaInstalada = getFlag("VelaInstalada"),
		Abastecido = getFlag("Abastecido"),
		ChaveInserida = getFlag("ChaveInserida"),
	}
end

local function isSabotaged(): boolean
	return layout ~= nil and layout.wiring:GetAttribute("Sabotado") == true
end

local function tell(player: Player, message: string)
	if player.Parent == Players then
		Remotes.LobbyMessage:FireClient(player, message)
	end
end

local function tellAboard(message: string)
	for player in seated do
		tell(player, message)
	end
end

local function tellEveryone(message: string)
	for _, player in Players:GetPlayers() do
		tell(player, message)
	end
end

local function tellMonster(message: string)
	for _, player in Players:GetPlayers() do
		if player:GetAttribute("Role") == GameConfig.Roles.Monster then
			tell(player, message)
		end
	end
end

--------------------------------------------------------------------------------
-- Quem pode o quê
--------------------------------------------------------------------------------

local function aliveCharacter(player: Player): (Model?, Humanoid?)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not character or not humanoid or humanoid.Health <= 0 then
		return nil, nil
	end
	return character, humanoid
end

-- Embarcar/pilotar: mesmo contrato do helicóptero (Sobrevivente ou Espião).
local function canBoard(player: Player): boolean
	if player.Parent ~= Players or player:GetAttribute("InRound") ~= true
		or player:GetAttribute("InWaitingRoom") == true or MatchStateService.Get() ~= "InMatch" then
		return false
	end
	local role = player:GetAttribute("Role")
	if role ~= GameConfig.Roles.Survivor and role ~= GameConfig.Roles.Spy then
		return false
	end
	if player:GetAttribute("Eliminado") == true then
		return false
	end
	local character = aliveCharacter(player)
	return character ~= nil and character:GetAttribute("GrabLocked") ~= true
		and character:GetAttribute("PowerStunned") ~= true
end

-- Montar/abastecer/chave: só Sobrevivente, igual a estação de rádio.
local function canWork(player: Player, target: BasePart?, quiet: boolean?): boolean
	if not target or state == "Escapando" or not MatchStateService.IsGameplayEnabled(player) then
		return false
	end
	if player:GetAttribute("Role") ~= GameConfig.Roles.Survivor then
		if not quiet then
			tell(player, "Só os Sobreviventes mexem no motor do barco.")
		end
		return false
	end
	local character = aliveCharacter(player)
	if not character or character:GetAttribute("GrabLocked") == true or character:GetAttribute("PowerStunned") == true then
		return false
	end
	local model = boatModel()
	-- O próprio casco nunca bloqueia os pontos de interação dele.
	return InteractionGuard.CanReach(player, target, CFG.AlcanceInteracao, if model then { model } else nil)
end

local function reachBoat(player: Player, target: BasePart): boolean
	local model = boatModel()
	return InteractionGuard.CanReach(player, target, CFG.AlcanceInteracao, if model then { model } else nil)
end

--------------------------------------------------------------------------------
-- Visual (luzes, peças instaladas, amarras)
--------------------------------------------------------------------------------

local function setLights(on: boolean)
	local current = layout
	if not current then
		return
	end
	for _, light in current.lights do
		light.Enabled = on
	end
	for _, glow in current.glow do
		glow.Material = if on then Enum.Material.Neon else Enum.Material.SmoothPlastic
	end
end

local function showVisual(key: string, visible: boolean)
	local current = layout
	local parts = current and current.visuals[key]
	if not parts then
		return
	end
	for _, p in parts do
		p.Transparency = if visible then 0 else 1
	end
end

local function setMoored(moored: boolean)
	local current = layout
	if not current then
		return
	end
	for _, rope in current.moorings do
		rope.Enabled = moored
	end
end

--------------------------------------------------------------------------------
-- Dono da física
--------------------------------------------------------------------------------

local function setOwner(player: Player?)
	local current = layout
	if not current or current.root.Anchored or not current.root:IsDescendantOf(Workspace) then
		return
	end
	pcall(function()
		current.root:SetNetworkOwner(player)
	end)
end

local function resetPhysics()
	local controller = physics
	if controller then
		BoatPhysics.Reset(controller)
	end
end

--------------------------------------------------------------------------------
-- Motor
--------------------------------------------------------------------------------

-- Ruído do motor pra super audição. A fonte tem que ser um Sobrevivente
-- (é assim que o NoiseService valida): o piloto, ou quem estiver a bordo.
local function engineNoise(radius: number)
	local current = layout
	local service = noiseService
	if not current or not service then
		return
	end
	local source: Player? = nil
	if driver and driver:GetAttribute("Role") == GameConfig.Roles.Survivor then
		source = driver
	else
		for player in seated do
			if player:GetAttribute("Role") == GameConfig.Roles.Survivor then
				source = player
				break
			end
		end
	end
	if source then
		service:EmitNoise(source, current.frame.WorldPosition, CFG.RuidoIntensidade, radius)
	end
end

local function stallEngine(reason: string?)
	crankToken += 1
	local wasRunning = getFlag("MotorLigado") or getFlag("DandoPartida")
	setAttr("DandoPartida", false)
	setAttr("MotorLigado", false)
	setLights(false)
	if wasRunning and reason then
		tellAboard(reason)
	end
end

local function startBlocked(player: Player?): string?
	return BoatRules.StartBlocked(requirements(), {
		hasKey = getFlag("ChaveInserida") or (player ~= nil and BoatItems.Carried(player, "ChaveBarco") ~= nil),
		sabotaged = isSabotaged(),
		surface = if getFlag("Encalhado") then "Encalhado" else surface,
		escaping = state == "Escapando",
	})
end

local function insertKey(player: Player, key: Tool)
	BoatItems.Consume(key)
	setAttr("ChaveInserida", true)
	showVisual("Chave", true)
	BoatSystem.StepCompleted:Fire(player, "ChaveInserida")
end

local function onEngineRequest(player: Player)
	local info = seated[player]
	if not layout or driver ~= player or not info or info.role ~= "Piloto" or state == "Escapando" then
		return
	end
	if getFlag("MotorLigado") then
		stallEngine(nil)
		tell(player, "Motor desligado.")
		return
	end
	if getFlag("DandoPartida") then
		return
	end
	local blocked = startBlocked(player)
	if blocked then
		tell(player, blocked)
		return
	end
	if not getFlag("ChaveInserida") then
		local key = BoatItems.Carried(player, "ChaveBarco")
		if not key then
			tell(player, "Sem a chave do barco, o motor não liga.")
			return
		end
		insertKey(player, key)
	end

	crankToken += 1
	local token = crankToken
	setAttr("DandoPartida", true)
	task.delay(CFG.TempoPartida, function()
		if token ~= crankToken or not layout then
			return
		end
		setAttr("DandoPartida", false)
		local blockedNow = startBlocked(nil)
		if blockedNow then
			tellAboard(blockedNow)
			return
		end
		setAttr("MotorLigado", true)
		setLights(true)
		setMoored(false)
		lastEngineNoise = os.clock()
		engineNoise(CFG.RuidoPartida)
		tellMonster("Um motor de barco acabou de pegar, lá pro lado do mar.")
		if not startedOnce then
			startedOnce = true
			BoatSystem.EngineStarted:Fire(player)
			Remotes.ObjectiveProgress:FireAllClients("BarcoLigado", 1, 1)
		end
		tellAboard("Motor ligado! Acelere pro mar aberto e passe das boias do limite.")
		print(string.format("[Barco] Motor ligado por %s.", player.Name))
	end)
end

--------------------------------------------------------------------------------
-- Montagem, combustível e chave
--------------------------------------------------------------------------------

local PIECES = {
	{ itemId = "HeliceBarco", key = "HeliceInstalada", visual = "Helice", label = "Hélice" },
	{ itemId = "VelaIgnicao", key = "VelaInstalada", visual = "Vela", label = "Vela de ignição" },
}

local function nextPiece(player: Player): (Tool?, { itemId: string, key: string, visual: string, label: string }?)
	for _, piece in PIECES do
		if not getFlag(piece.key) then
			local tool = BoatItems.Carried(player, piece.itemId)
			if tool then
				return tool, piece
			end
		end
	end
	return nil, nil
end

local function announceRepairedIfDone()
	if BoatRules.IsRepaired(requirements()) and getFlag("ChaveInserida") then
		Remotes.ObjectiveProgress:FireAllClients("BarcoPronto", 1, 1)
	end
end

local function installPiece(player: Player)
	local current = layout
	if not current or not canWork(player, current.anchors.Motor) then
		return
	end
	local tool, piece = nextPiece(player)
	if not tool or not piece then
		return
	end
	-- Consumo e efeito no mesmo tique: a mesma Tool nunca instala duas vezes.
	BoatItems.Consume(tool)
	setAttr(piece.key, true)
	showVisual(piece.visual, true)
	tell(player, piece.label .. " instalada no motor.")
	BoatSystem.StepCompleted:Fire(player, piece.key)
	announceRepairedIfDone()
	print(string.format("[Barco] %s instalou %s.", player.Name, piece.label))
end

local function refuelBlocked(player: Player): string?
	if getFlag("Abastecido") then
		return "O tanque do barco já está cheio."
	end
	if not BoatItems.Carried(player, "Gasolina") then
		return "Traga um Galão de Gasolina no inventário pra abastecer o barco."
	end
	return nil
end

local function onRefuel(player: Player)
	local started = refuelStarted[player]
	refuelStarted[player] = nil
	local current = layout
	if not current or not started or Workspace:GetServerTimeNow() - started < CFG.HoldAbastecer - 0.15 then
		return
	end
	if not canWork(player, current.anchors.Tanque) then
		return
	end
	local blocked = refuelBlocked(player)
	if blocked then
		tell(player, blocked)
		return
	end
	local gasoline = BoatItems.Carried(player, "Gasolina")
	if gasoline then
		BoatItems.Consume(gasoline)
		setAttr("Abastecido", true)
		tell(player, "Tanque do barco cheio.")
		BoatSystem.StepCompleted:Fire(player, "Abastecido")
		announceRepairedIfDone()
	end
end

local function onInsertKey(player: Player)
	local current = layout
	if not current or getFlag("ChaveInserida") or not canWork(player, current.anchors.Ignicao) then
		return
	end
	local key = BoatItems.Carried(player, "ChaveBarco")
	if not key then
		tell(player, "Você não está com a chave do barco.")
		return
	end
	insertKey(player, key)
	tell(player, "Chave na ignição. Sente no timão e dê a partida.")
	announceRepairedIfDone()
end

--------------------------------------------------------------------------------
-- Assentos
--------------------------------------------------------------------------------

local function kick(seat: BasePart)
	local weld = seat:FindFirstChild("SeatWeld")
	if weld then
		weld:Destroy()
	end
	local occupant = (seat :: any).Occupant :: Humanoid?
	if occupant then
		occupant.Sit = false
	end
end

local function leave(player: Player)
	local info = seated[player]
	if not info then
		return
	end
	seated[player] = nil
	if info.character.Parent then
		info.character:SetAttribute("BarcoAssento", nil)
	end
	player:SetAttribute("NoBarco", nil)
	if driver == player then
		driver = nil
		setAttr("PilotoId", 0)
		resetPhysics()
		setOwner(nil)
	end
	if player.Parent == Players then
		Remotes.BoatControl:FireClient(player, "Saiu")
	end
end

local function enter(player: Player, character: Model, humanoid: Humanoid, seat: BasePart)
	local current = layout
	if not current then
		return
	end
	local previous = seated[player]
	if previous and previous.seat ~= seat then
		leave(player)
	end
	local role: Role = if seat == current.helm then "Piloto" else "Passageiro"
	seated[player] = { character = character, humanoid = humanoid, seat = seat, role = role }
	character:SetAttribute("BarcoAssento", role)
	player:SetAttribute("NoBarco", true)
	if role == "Piloto" then
		driver = player
		setAttr("PilotoId", player.UserId)
		resetPhysics()
		setOwner(player)
	end
	Remotes.BoatControl:FireClient(player, "Assento", current.model, role)
end

local function onOccupantChanged(seat: Seat | VehicleSeat)
	local humanoid = seat.Occupant
	for player, info in table.clone(seated) do
		if info.seat == seat and info.humanoid ~= humanoid then
			leave(player)
		end
	end
	if not humanoid then
		return
	end
	local character = humanoid.Parent
	local player = if character and character:IsA("Model") then Players:GetPlayerFromCharacter(character) else nil
	if not player or not character or not canBoard(player) or state == "Escapando" then
		kick(seat)
		return
	end
	enter(player, character :: Model, humanoid, seat)
end

local function freeSeat(near: Vector3?): Seat?
	local current = layout
	if not current then
		return nil
	end
	local best: Seat? = nil
	local bestDistance = math.huge
	for _, seat in current.seats do
		if not seat.Occupant and not seat.Disabled then
			local distance = if near then (seat.Position - near).Magnitude else 0
			if distance < bestDistance then
				best, bestDistance = seat, distance
			end
		end
	end
	return best
end

local function sitIn(player: Player, seat: Seat | VehicleSeat)
	local character, humanoid = aliveCharacter(player)
	if not character or not humanoid then
		return
	end
	if humanoid.Sit then
		local current = humanoid.SeatPart
		if current then
			kick(current)
		end
	end
	-- A Tool equipada continua na mão (a hotbar mostra "equipado" normalmente).
	seat:Sit(humanoid)
end

local function onPilot(player: Player)
	local current = layout
	if not current or state == "Escapando" or pushing or not canBoard(player) then
		return
	end
	if current.helm.Occupant then
		tell(player, "Alguém já está no timão.")
		return
	end
	if not reachBoat(player, current.helm) then
		return
	end
	sitIn(player, current.helm)
end

local function onBoard(player: Player, anchor: BasePart)
	local current = layout
	if not current or state == "Escapando" or pushing or not canBoard(player) or not reachBoat(player, anchor) then
		return
	end
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	local seat = freeSeat(if root and root:IsA("BasePart") then root.Position else nil)
	if not seat then
		tell(player, "O barco está lotado.")
		return
	end
	sitIn(player, seat)
end

--------------------------------------------------------------------------------
-- Encalhe e empurrão
--------------------------------------------------------------------------------

local function frameCF(): CFrame
	local current = layout :: BoatBuilder.Layout
	return current.frame.WorldCFrame
end

local function updateSurface(env: BoatPhysics.Env)
	surface = env.surface
	setAttr("Superficie", surface)
	local now = os.clock()
	if surface == "Encalhado" then
		waterSince = 0
		if groundedSince == 0 then
			groundedSince = now
		end
		if not getFlag("Encalhado") and now - groundedSince >= SETTLE_GROUNDED then
			setAttr("Encalhado", true)
			if getFlag("MotorLigado") or getFlag("DandoPartida") then
				stallEngine("O barco encalhou! O hélice saiu da água e o motor morreu. Empurrem de volta pra água funda.")
			else
				tellAboard("O barco encalhou. Empurrem de volta pra água funda.")
			end
			print("[Barco] Encalhou -- motor desligado.")
		end
	else
		groundedSince = 0
		if getFlag("Encalhado") then
			if waterSince == 0 then
				waterSince = now
			end
			if now - waterSince >= SETTLE_WATER then
				setAttr("Encalhado", false)
			end
		end
	end
end

-- Água funda mais perto, com o casco inteiro boiando. A proa sai virada pro
-- lado da água (o barco é empurrado "de frente" pro mar).
local function findPushTarget(): CFrame?
	local current = layout
	if not current then
		return nil
	end
	local origin = frameCF().Position
	local half = current.length / 2
	local best: CFrame? = nil
	local bestDistance = math.huge
	for i = 0, 23 do
		local angle = i / 24 * math.pi * 2
		local dir = Vector3.new(math.cos(angle), 0, math.sin(angle))
		for distance = 6, 72, 3 do
			local p = origin + dir * distance
			local waterY, depth = BoatPhysics.Probe(p)
			if waterY and depth and depth >= CFG.Calado * 2.5 then
				local _, ahead = BoatPhysics.Probe(p + dir * half)
				local _, behind = BoatPhysics.Probe(p - dir * half)
				if ahead and behind and ahead >= CFG.Calado * 1.5 and behind >= CFG.Calado * 1.2 then
					if distance < bestDistance then
						local at = Vector3.new(p.X, waterY, p.Z)
						best, bestDistance = CFrame.lookAt(at, at + dir), distance
					end
					break
				end
			end
		end
	end
	return best
end

local function pushBack(player: Player, target: CFrame)
	local current = layout
	if not current then
		return
	end
	pushing = true
	local root = current.root
	setOwner(nil)
	root.Anchored = true
	local from = frameCF()
	local frameToPivot = from:ToObjectSpace(current.model:GetPivot())
	local duration = 1.6
	local started = os.clock()
	local token = roundToken
	local connection: RBXScriptConnection? = nil
	connection = RunService.Heartbeat:Connect(function()
		local alpha = math.clamp((os.clock() - started) / duration, 0, 1)
		if token ~= roundToken or not layout then
			if connection then
				connection:Disconnect()
			end
			return
		end
		local eased = 1 - (1 - alpha) ^ 3
		-- Arco baixo: o casco sai da areia e desce pra água, não atravessa o
		-- degrau da praia.
		local position = from.Position:Lerp(target.Position, eased) + Vector3.new(0, math.sin(alpha * math.pi) * 1.4, 0)
		local rotation = from.Rotation:Lerp(target.Rotation, eased)
		current.model:PivotTo(CFrame.new(position) * rotation * frameToPivot)
		if alpha >= 1 then
			if connection then
				connection:Disconnect()
			end
			root.Anchored = false
			root.AssemblyLinearVelocity = Vector3.zero
			root.AssemblyAngularVelocity = Vector3.zero
			pushing = false
			groundedSince = 0
			waterSince = 0
			surface = "Agua" -- sem esperar o próximo tique: F já pode dar partida
			setAttr("Encalhado", false)
			setAttr("Superficie", "Agua")
			lastValid, lastValidAt = frameCF(), os.clock()
			resetPhysics()
			if driver then
				setOwner(driver)
			end
			tell(player, "O barco voltou pra água.")
			tellAboard("O barco voltou pra água. Dê a partida de novo.")
		end
	end)
end

local function onPushTriggered(player: Player, anchor: BasePart)
	local started = pushStarted[player]
	pushStarted[player] = nil
	if not started or Workspace:GetServerTimeNow() - started < CFG.HoldEmpurrar - 0.15 then
		return
	end
	if not getFlag("Encalhado") or pushing or state == "Escapando" or seated[player] or not canBoard(player)
		or not reachBoat(player, anchor) then
		return
	end
	local target = findPushTarget()
	if not target then
		tell(player, "Não tem água funda por perto pra empurrar o barco.")
		return
	end
	pushBack(player, target)
end

--------------------------------------------------------------------------------
-- Anti-teleporte e limite do mapa
--------------------------------------------------------------------------------

local function correctPosition()
	local current = layout
	local target = lastValid
	if not current or not target then
		return
	end
	correctingUntil = os.clock() + 0.6
	setOwner(nil)
	local frameToPivot = frameCF():ToObjectSpace(current.model:GetPivot())
	current.model:PivotTo(target * frameToPivot)
	current.root.AssemblyLinearVelocity = Vector3.zero
	current.root.AssemblyAngularVelocity = Vector3.zero
	resetPhysics()
	task.delay(0.6, function()
		if driver and layout then
			setOwner(driver)
		end
	end)
end

-- Compara com a última posição VÁLIDA e o tempo desde ela (até 1s), não
-- com o tique anterior: se a rede do piloto engasga e a posição chega toda
-- de uma vez, o salto é legítimo. Parado não renova o relógio (a folga fica
-- guardada pro próximo pacote), e o teto de 1s impede que ficar parado muito
-- tempo libere um teleporte.
local function validateMovement()
	local current = frameCF()
	local previous = lastValid
	local clock = os.clock()
	if not previous or clock < correctingUntil then
		lastValid, lastValidAt = current, clock
		return
	end
	local elapsed = math.clamp(clock - lastValidAt, CFG.IntervaloChecagem, 1)
	local delta = current.Position - previous.Position
	local horizontal = Vector3.new(delta.X, 0, delta.Z).Magnitude
	if BoatRules.MoveIsPlausible(horizontal, delta.Y, elapsed, CFG) then
		if horizontal > 0.2 or math.abs(delta.Y) > 0.2 then
			lastValid, lastValidAt = current, clock
		end
		return
	end
	warn(string.format("[Barco] Deslocamento impossível (%.0f studs em %.2fs, piloto %s) -- barco devolvido.",
		horizontal, elapsed, if driver then driver.Name else "nenhum"))
	correctPosition()
end

local function beginEscape(rescued: { Player })
	local current = layout
	if not current or state == "Escapando" then
		return
	end
	state = "Escapando"
	escapeRescued = rescued
	local frame = frameCF()
	local look = frame.LookVector
	local forward = Vector3.new(look.X, 0, look.Z)
	forward = if forward.Magnitude > 1e-3 then forward.Unit else Vector3.new(0, 0, -1)
	local speed = math.max(current.root.AssemblyLinearVelocity:Dot(forward), 0)
	local start = CFrame.lookAt(frame.Position, frame.Position + forward)

	-- Congela a física no servidor: daqui pra frente o barco é cena. Cada
	-- cliente anima o próprio (suave, sem esperar a rede).
	crankToken += 1
	current.root.Anchored = true
	setAttr("DandoPartida", false)
	setAttr("Escapando", true)
	for _, prompt in prompts do
		prompt.Enabled = false
	end

	local ids: { number } = {}
	local names: { string } = {}
	for _, player in rescued do
		table.insert(ids, player.UserId)
		table.insert(names, player.Name)
		local character = player.Character
		if character then
			character:SetAttribute("Invulneravel", true)
		end
	end
	Remotes.BoatControl:FireAllClients("Fuga", current.model, start, speed, CFG.DuracaoCinematica, ids)
	tellEveryone(string.format("O barco cruzou o limite do mapa com %d a bordo!", #rescued))
	print(string.format("[Barco] Fuga pelo limite: %s", table.concat(names, ", ")))

	local token = roundToken
	task.delay(CFG.DuracaoCinematica, function()
		if token ~= roundToken or state ~= "Escapando" then
			return
		end
		local final: { Player } = {}
		for _, player in escapeRescued do
			if player.Parent == Players then
				table.insert(final, player)
			end
		end
		Remotes.ObjectiveProgress:FireAllClients("BarcoFugiu", #final, #Players:GetPlayers(), final)
		BoatSystem.SurvivorsEscaped:Fire(final)
	end)
end

local function checkFinish()
	if state ~= "Pronto" or pushing or os.clock() < correctingUntil then
		return
	end
	local position = frameCF().Position
	if BoatRules.DistanceToFinish(position.X, position.Z, CFG.RaioChegada) > 0 then
		return
	end
	local rescued: { Player } = {}
	for player, info in seated do
		if canBoard(player) and player.Character == info.character then
			table.insert(rescued, player)
		end
	end
	if #rescued > 0 then
		beginEscape(rescued)
	end
end

--------------------------------------------------------------------------------
-- Prompts
--------------------------------------------------------------------------------

local function newPrompt(host: BasePart, name: string, action: string, object: string, hold: number): ProximityPrompt
	local old = host:FindFirstChild(name)
	if old then
		old:Destroy()
	end
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = name
	prompt.ActionText = action
	prompt.ObjectText = object
	prompt.HoldDuration = hold
	prompt.MaxActivationDistance = 9
	-- O casco esconde metade dos pontos de quem está na água ou no píer; o
	-- servidor revalida alcance/linha de visão ignorando o próprio barco.
	prompt.RequiresLineOfSight = false
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.GamepadKeyCode = Enum.KeyCode.ButtonX
	prompt.ClickablePrompt = true
	prompt.Enabled = false
	prompt.Parent = host
	return prompt
end

local function trackHold(prompt: ProximityPrompt, store: { [Player]: number }, blocked: ((Player) -> string?)?)
	prompt.PromptButtonHoldBegan:Connect(function(player: Player)
		local reason = if blocked then blocked(player) else nil
		if reason then
			store[player] = nil
			tell(player, reason)
			return
		end
		store[player] = Workspace:GetServerTimeNow()
	end)
	prompt.PromptButtonHoldEnded:Connect(function(player: Player)
		local started = store[player]
		-- Triggered e HoldEnded podem chegar no mesmo frame.
		task.defer(function()
			if store[player] == started then
				store[player] = nil
			end
		end)
	end)
end

local function setupPrompts(current: BoatBuilder.Layout)
	local anchors = current.anchors

	local install = newPrompt(anchors.Motor, "InstalarPecaBarco", "Instalar peça", "Motor do barco", 0)
	local installSpec = {
		taskId = "BarcoMotor",
		configId = "BarcoMotor",
		part = anchors.Motor,
		range = CFG.AlcanceInteracao,
		ignore = { current.model } :: { Instance },
		canStart = function(player: Player): (boolean, string?)
			if state == "Escapando" then
				return false, nil
			end
			if getFlag("HeliceInstalada") and getFlag("VelaInstalada") then
				return false, "O motor já está montado."
			end
			if not nextPiece(player) then
				return false, "Você não está carregando a hélice nem a vela de ignição."
			end
			return true, nil
		end,
		onComplete = installPiece,
	}
	install.Triggered:Connect(function(player: Player)
		if canWork(player, anchors.Motor) then
			RepairMinigameSystem.Start(player, installSpec)
		end
	end)
	prompts.Instalar = install

	local refuel = newPrompt(anchors.Tanque, "AbastecerBarco", "Abastecer", "Tanque do barco", CFG.HoldAbastecer)
	trackHold(refuel, refuelStarted, function(player: Player): string?
		if not canWork(player, anchors.Tanque, true) then
			return nil -- o Triggered revalida e explica
		end
		return refuelBlocked(player)
	end)
	refuel.Triggered:Connect(onRefuel)
	prompts.Abastecer = refuel

	local key = newPrompt(anchors.Ignicao, "ChaveBarco", "Colocar chave", "Ignição", 0)
	key.Triggered:Connect(onInsertKey)
	prompts.Chave = key

	local pilot = newPrompt(current.helm, "PilotarBarco", "Pilotar", "Barco", 0)
	pilot.Triggered:Connect(onPilot)
	prompts.Pilotar = pilot

	for _, name in { "EmbarqueBB", "EmbarqueBE" } do
		local anchor = anchors[name]
		local board = newPrompt(anchor, "EmbarcarBarco", "Embarcar", "Barco", 0)
		board.Triggered:Connect(function(player: Player)
			onBoard(player, anchor)
		end)
		prompts[name] = board
	end

	for _, name in { "Proa", "Popa" } do
		local anchor = anchors[name]
		local push = newPrompt(anchor, "EmpurrarBarco", "Empurrar pra água", "Barco encalhado", CFG.HoldEmpurrar)
		trackHold(push, pushStarted, nil)
		push.Triggered:Connect(function(player: Player)
			onPushTriggered(player, anchor)
		end)
		prompts["Empurrar" .. name] = push
	end
end

local function refreshPrompts()
	local current = layout
	if not current then
		return
	end
	local live = MatchStateService.Get() == "InMatch" and state ~= "Escapando" and not pushing
	local function set(key: string, enabled: boolean)
		local prompt = prompts[key]
		if prompt and prompt.Enabled ~= enabled then
			prompt.Enabled = enabled
		end
	end
	set("Instalar", live and not (getFlag("HeliceInstalada") and getFlag("VelaInstalada")))
	set("Abastecer", live and not getFlag("Abastecido"))
	set("Chave", live and not getFlag("ChaveInserida"))
	set("Pilotar", live and current.helm.Occupant == nil)
	local anySeat = freeSeat(nil) ~= nil
	set("EmbarqueBB", live and anySeat)
	set("EmbarqueBE", live and anySeat)
	set("EmpurrarProa", live and getFlag("Encalhado"))
	set("EmpurrarPopa", live and getFlag("Encalhado"))
end

--------------------------------------------------------------------------------
-- Tique do servidor
--------------------------------------------------------------------------------

local function checkSeats()
	for player, info in table.clone(seated) do
		local alive = info.humanoid.Parent ~= nil and info.humanoid.Health > 0
		if player.Parent ~= Players or player.Character ~= info.character or not alive
			or (info.seat :: any).Occupant ~= info.humanoid then
			leave(player)
			if not alive and (info.seat :: any).Occupant == info.humanoid then
				kick(info.seat) -- o corpo não fica pilotando
			end
		end
	end
end

local promptElapsed = 0

local function tick(dt: number)
	local current = layout
	local controller = physics
	if not current or not controller then
		return
	end
	checkSeats()
	promptElapsed += dt
	if promptElapsed >= PROMPT_REFRESH then
		promptElapsed = 0
		refreshPrompts()
	end
	if state == "Escapando" then
		return
	end

	if driver and not current.root.Anchored and os.clock() >= correctingUntil then
		local ok, owner = pcall(function()
			return current.root:GetNetworkOwner()
		end)
		if ok and owner ~= driver then
			setOwner(driver)
		end
	end

	if not pushing then
		local env = BoatPhysics.Sample(controller)
		lastEnv = env
		updateSurface(env)
		validateMovement()
		checkFinish()
	end

	if isSabotaged() and (getFlag("MotorLigado") or getFlag("DandoPartida")) then
		stallEngine("O motor apagou do nada... alguém cortou a fiação! Repare antes de dar partida.")
	end

	if getFlag("MotorLigado") and os.clock() - lastEngineNoise >= CFG.RuidoIntervalo then
		lastEngineNoise = os.clock()
		local velocity = current.root.AssemblyLinearVelocity
		local speed = Vector3.new(velocity.X, 0, velocity.Z).Magnitude
		engineNoise(BoatRules.EngineNoiseRadius(speed / CFG.VelocidadeMax, CFG))
	end
end

local idleElapsed = 0
local checkElapsed = 0

local function onHeartbeat(dt: number)
	local current = layout
	local controller = physics
	if not current or not controller then
		return
	end
	-- Sem piloto, o servidor é dono do barco e roda a física em ponto morto.
	-- Parado, 10 Hz bastam pra boiar; andando (piloto pulou fora), todo frame.
	if not driver and state ~= "Escapando" and not pushing and not current.root.Anchored then
		idleElapsed += dt
		local moving = current.root.AssemblyLinearVelocity.Magnitude > 1.5
		if moving or idleElapsed >= 0.1 then
			BoatPhysics.Step(controller, idleElapsed, 0, 0, getFlag("MotorLigado"), if moving then nil else lastEnv)
			idleElapsed = 0
		end
	end
	checkElapsed += dt
	if checkElapsed >= CFG.IntervaloChecagem then
		tick(checkElapsed)
		checkElapsed = 0
	end
end

--------------------------------------------------------------------------------
-- API
--------------------------------------------------------------------------------

--[[
	announceOnMap(players)
	Marca o barco no mapa (M), no minimapa e no mapa do Monstro, pelo mesmo
	canal dos itens descobertos (Remotes.MapDiscovery). Onde o barco nasce é
	informação pública, como a estação de rádio.
]]
local function announceOnMap(players: { Player })
	local current = layout
	if not current then
		return
	end
	local position = current.frame.WorldPosition
	local entry = {
		key = "barco-fuga",
		x = math.floor(position.X * 10) / 10,
		z = math.floor(position.Z * 10) / 10,
		category = "Escape",
		label = "Barco de fuga",
	}
	for _, player in players do
		if player.Parent == Players then
			Remotes.MapDiscovery:FireClient(player, entry)
		end
	end
end

--[[
	Reset()
	Barco de volta ao cais, desmontado, sem ninguém a bordo, e peças novas
	espalhadas. RoundManager chama no preparo de cada rodada.
]]
function BoatSystem.Reset()
	local current = layout
	if not current then
		return
	end
	roundToken += 1
	crankToken += 1
	state = "Pronto"
	table.clear(escapeRescued)
	for player, info in table.clone(seated) do
		leave(player)
		kick(info.seat)
	end
	kick(current.helm)
	for _, seat in current.seats do
		kick(seat)
	end
	driver = nil
	pushing = false
	startedOnce = false
	for _, step in BoatRules.Steps do
		setAttr(step.key, false)
	end
	setAttr("MotorLigado", false)
	setAttr("DandoPartida", false)
	setAttr("Encalhado", false)
	setAttr("Escapando", false)
	setAttr("Superficie", "Agua")
	setAttr("PilotoId", 0)
	setAttr("RaioChegada", CFG.RaioChegada)
	current.wiring:SetAttribute("Sabotado", false)
	for key in current.visuals do
		showVisual(key, false)
	end
	setLights(false)
	setMoored(true)

	local root = current.root
	root.Anchored = true
	current.model:PivotTo(current.home)
	root.Anchored = false
	root.AssemblyLinearVelocity = Vector3.zero
	root.AssemblyAngularVelocity = Vector3.zero
	setOwner(nil)
	resetPhysics()
	-- Metas de flutuação já no primeiro frame solto (sem isso ele afunda um
	-- instante até o próximo passo em ponto morto).
	local controller = physics
	if controller then
		BoatPhysics.Step(controller, 0.05, 0, 0, false)
	end
	lastValid = nil
	lastEnv = nil
	groundedSince, waterSince, correctingUntil = 0, 0, 0
	table.clear(refuelStarted)
	table.clear(pushStarted)
	lastEngineNoise = 0
	RepairMinigameSystem.ResetTask("BarcoMotor")
	BoatItems.Reset(current.itemSpots)
	refreshPrompts()
end

--[[
	EndRound()
	Fim da partida: ninguém fica sentado (o LobbyManager recarrega os
	personagens) e o barco para onde estiver até o próximo Reset.
]]
function BoatSystem.EndRound()
	if not layout then
		return
	end
	roundToken += 1
	crankToken += 1
	state = "Inativo"
	for player, info in table.clone(seated) do
		leave(player)
		kick(info.seat)
	end
	refreshPrompts()
end

function BoatSystem.IsEscaping(): boolean
	return state == "Escapando"
end

function BoatSystem.EscapingPlayers(): { Player }
	return table.clone(escapeRescued)
end

function BoatSystem.Init()
	if initialized then
		return
	end
	initialized = true
	BoatItems.Init()

	local built = BoatBuilder.Build(CFG)
	if not built then
		warn("[Barco] Não achei praia pra montar o barco -- a fuga de barco fica desligada neste mapa.")
		return
	end
	layout = built
	physics = BoatPhysics.Bind(built.model, CFG)
	-- Referência pros clientes acharem o barco sem varrer o Workspace (e sem
	-- depender do nome: o barco do mapa pode se chamar qualquer coisa).
	local ref = ReplicatedStorage:FindFirstChild("BarcoFuga")
	if not ref or not ref:IsA("ObjectValue") then
		if ref then
			ref:Destroy()
		end
		ref = Instance.new("ObjectValue")
		ref.Name = "BarcoFuga"
		ref.Parent = ReplicatedStorage
	end
	(ref :: ObjectValue).Value = built.model
	BoatBuilder.BuildFinishRing(CFG)
	setupPrompts(built)

	built.helm:GetPropertyChangedSignal("Occupant"):Connect(function()
		onOccupantChanged(built.helm)
	end)
	for _, seat in built.seats do
		seat:GetPropertyChangedSignal("Occupant"):Connect(function()
			onOccupantChanged(seat)
		end)
	end
	built.wiring:GetAttributeChangedSignal("Sabotado"):Connect(function()
		if built.wiring:GetAttribute("Sabotado") == true then
			stallEngine("O motor apagou do nada... alguém cortou a fiação! Repare antes de dar partida.")
		end
	end)

	-- Requires tardios (ver noiseService lá em cima): aqui os dois módulos já
	-- terminaram de carregar.
	noiseService = require(script.Parent.NoiseService)
	local RoundManager = require(script.Parent.RoundManager)
	RoundManager.RoundPrepared.Event:Connect(function(players: { Player })
		-- O Reset do preparo já pôs o barco no cais: é essa a posição marcada.
		announceOnMap(players)
	end)

	Remotes.BoatControl.OnServerEvent:Connect(function(player: Player, action: unknown)
		if action == "Motor" then
			onEngineRequest(player)
		end
	end)
	Players.PlayerRemoving:Connect(function(player)
		leave(player)
		refuelStarted[player] = nil
		pushStarted[player] = nil
	end)
	RunService.Heartbeat:Connect(onHeartbeat)

	BoatSystem.Reset()
	print(string.format("[Barco] Pronto -- limite do mapa a %d studs do centro da ilha.", CFG.RaioChegada))
end

return BoatSystem
