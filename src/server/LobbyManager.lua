--!strict
--[[
	LobbyManager
	Dono do ciclo "Lobby -> Ilha -> Lobby".

	SPAWN INICIAL: "LobbySpawn" é a ÚNICA SpawnLocation do jogo -- os pontos
	da ilha (IlhaSpawns) são Parts comuns, não SpawnLocations. O próprio
	Roblox manda todo jogador que entra (e qualquer LoadCharacter() sem
	CFrame explícito) pra a única SpawnLocation que existir. Por isso "voltar
	pro Lobby" também não precisa de teleporte manual: é só LoadCharacter().

	O Lobby (piso + spawn + botão) é declarado em default.project.json, mas
	ensureLobbyExists() abaixo FORÇA a posição (LOBBY_ORIGIN) toda vez que o
	servidor sobe, mesmo se a peça já existir. De propósito, não só "cria se
	faltar": um Workspace salvo pode ter uma versão desatualizada de
	LobbySpawn/IniciarPartida (ex: você gerou a ilha e salvou antes do Rojo
	sincronizar uma mudança de posição feita aqui no código) -- "só cria se
	faltar" nunca corrigiria isso, porque a peça TECNICAMENTE já existe, só
	que no lugar errado. Isso já aconteceu uma vez nesta conversa.

	CONSEQUÊNCIA: se você mover o Lobby no Studio manualmente, essa mudança
	é desfeita no próximo boot -- a fonte da verdade da posição é
	LOBBY_ORIGIN aqui, não o que está no Workspace. Pra mudar de lugar,
	edite LOBBY_ORIGIN (e o resto do Lobby some junto, relativo a ele).

	FLUXO
	  1) Jogador interage com o Part "IniciarPartida" (ProximityPrompt).
	  2) Validam-se, nesta ordem: autorização (modo de teste, ver abaixo),
	     partida já em andamento, jogadores de menos, jogadores de mais.
	     Qualquer falha manda uma LobbyMessage só pra quem interagiu.
	  3) Se passou: task.spawn(RoundManager.StartRound) -- StartRound
	     BLOQUEIA até a partida acabar, por isso o task.spawn.
	  4) RoundManager.RoundPrepared dispara logo depois do LoadCharacter de
	     todo mundo (ainda no Lobby, já que LoadCharacter manda pra
	     LobbySpawn) -- aí sim teleportamos: Monstro pro marcador
	     MonstroSpawn dentro da Caverna, todo o resto pra um ponto de praia
	     achado NA HORA por raycast (material Sand do Terrain -- não
	     depende de nenhuma Part fixa, então funciona não importa onde a
	     ilha procedural, seed variável, tenha ficado). "IlhaSpawns"
	     (default.project.json) só entra como fallback, se não achar praia
	     nenhuma (ex: ilha ainda não foi gerada).
	  5) RoundManager.RoundEnded dispara com o resultado; depois de
	     GameConfig.Round.IntermissionDuration segundos, todo mundo recebe
	     LoadCharacter() de novo, o que já os manda de volta pro Lobby.

	MODO DE TESTE (TEMPORÁRIO): só quem estiver em ALLOWED_STARTER_USER_IDS
	pode acionar "IniciarPartida". Lista vazia = NINGUÉM inicia (mais seguro
	como padrão do que liberar geral por acidente). Preencha com seu
	Roblox UserId antes de testar sozinho, e esvazie a lista (ou remova a
	checagem) quando quiser liberar pra qualquer jogador.

	Uso (chamar uma vez no boot do servidor, depois de RoundManager.Init()):
		local LobbyManager = require(script.LobbyManager)
		LobbyManager.Init()
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local GameConfig = require(ReplicatedStorage.Modules.GameConfig)
local Remotes = require(ReplicatedStorage.Modules.Remotes)
local RoundManager = require(script.Parent.RoundManager)

local LobbyManager = {}

-- TEMPORÁRIO: só mathm1311 (UserId 11555748600) pode iniciar a partida.
-- Esvazie esta lista (ou remova a checagem) quando quiser liberar geral.
local ALLOWED_STARTER_USER_IDS: { number } = { 11555748600 }

local function isAuthorizedToStart(player: Player): boolean
	return table.find(ALLOWED_STARTER_USER_IDS, player.UserId) ~= nil
end

--------------------------------------------------------------------------------
-- Lobby (posição sempre FORÇADA aqui -- ver nota no cabeçalho)
--------------------------------------------------------------------------------

-- Fica longe da área que o IslandGenerator escreve terreno (AreaHalf = 324)
-- e do raio máximo da ilha, pra nada da geração encostar no Lobby.
-- Precisa bater com default.project.json.
local LOBBY_ORIGIN = Vector3.new(0, 10, -400)

-- Acha a instância pelo nome (recriando com a classe certa se existir com
-- outra, ou não existir) e devolve pronta pra configurar.
local function getOrRecreate(name: string, className: string): Instance
	local existing = Workspace:FindFirstChild(name)
	if existing and existing.ClassName == className then
		return existing
	end
	if existing then
		existing:Destroy()
	end

	local instance = Instance.new(className)
	instance.Name = name
	instance.Parent = Workspace
	return instance
end

local function ensureLobbyExists()
	-- Reaplica Position/Size/etc. INCONDICIONALMENTE, mesmo se a instância já
	-- existir -- não só quando falta. Sem isso, uma peça que já existe mas
	-- ficou com a posição antiga (ex: um save feito antes do Rojo sincronizar
	-- uma mudança de posição) nunca seria corrigida, e o jogador continuaria
	-- nascendo no lugar errado silenciosamente. Foi exatamente isso que
	-- aconteceu: gerar a ilha e salvar congelou um LobbySpawn desatualizado.
	local floor = getOrRecreate("LobbyFloor", "Part") :: Part
	floor.Anchored = true
	floor.CanCollide = true
	floor.Size = Vector3.new(60, 2, 60)
	floor.Position = LOBBY_ORIGIN - Vector3.new(0, 1, 0)
	floor.Color = Color3.fromRGB(90, 90, 102)

	local spawnLocation = getOrRecreate("LobbySpawn", "SpawnLocation") :: SpawnLocation
	spawnLocation.Anchored = true
	spawnLocation.Neutral = true
	spawnLocation.Size = Vector3.new(8, 1, 8)
	spawnLocation.Position = LOBBY_ORIGIN + Vector3.new(0, 0.5, 0)

	local startPart = getOrRecreate("IniciarPartida", "Part") :: Part
	startPart.Anchored = true
	startPart.CanCollide = true
	startPart.Size = Vector3.new(4, 1, 4)
	startPart.Position = LOBBY_ORIGIN + Vector3.new(0, 0.5, 20)
	startPart.Color = Color3.fromRGB(51, 102, 204)
	startPart.Material = Enum.Material.Neon

	if not startPart:FindFirstChildOfClass("ProximityPrompt") then
		local prompt = Instance.new("ProximityPrompt")
		prompt.Name = "StartPrompt"
		prompt.ActionText = "Iniciar Partida"
		prompt.ObjectText = "Lobby"
		prompt.MaxActivationDistance = 10
		prompt.RequiresLineOfSight = false
		prompt.Parent = startPart
	end

	print(string.format("[LobbyManager] Lobby confirmado em (%.0f, %.0f, %.0f).", LOBBY_ORIGIN.X, LOBBY_ORIGIN.Y, LOBBY_ORIGIN.Z))
end

--------------------------------------------------------------------------------
-- Pontos de spawn da ilha
--------------------------------------------------------------------------------

local function getIslandSpawns(): { BasePart }
	local folder = Workspace:FindFirstChild("IlhaSpawns")
	local spawns: { BasePart } = {}

	if not folder then
		warn("[LobbyManager] Folder 'IlhaSpawns' não encontrado no Workspace.")
		return spawns
	end

	for _, child in folder:GetChildren() do
		if child:IsA("BasePart") and child:GetAttribute("IlhaSpawn") == true then
			table.insert(spawns, child)
		end
	end

	return spawns
end

-- Altura real do chão em (x, z), via raycast contra Terrain + Parts. As
-- IlhaSpawns ficam dentro da área onde o IslandGenerator escreve terreno
-- (Ferramentas/IslandGenerator.lua) -- se a ilha for gerada/regerada depois
-- de definir a posição Y da Part, essa Y fixa pode ficar errada (enterrada
-- ou flutuando). Raycast garante que o teleporte sempre acerta a superfície
-- de verdade, não importa o que exista no terreno naquele momento.
local function findGroundY(x: number, z: number, fallbackY: number): number
	local origin = Vector3.new(x, 1000, z)
	local result = Workspace:Raycast(origin, Vector3.new(0, -2000, 0))
	if result then
		return result.Position.Y
	end
	return fallbackY
end

-- Marcador "MonstroSpawn" dentro da caverna (Workspace/Ilha/Caverna, criado
-- pelo IslandGenerator). Attribute MonstroSpawn == true.
local function findMonsterSpawn(): BasePart?
	local ilha = Workspace:FindFirstChild("Ilha")
	local caverna = ilha and ilha:FindFirstChild("Caverna")
	if not caverna then
		return nil
	end
	for _, child in caverna:GetChildren() do
		if child:IsA("BasePart") and child:GetAttribute("MonstroSpawn") == true then
			return child
		end
	end
	return nil
end

local beachRaycastParams = RaycastParams.new()
beachRaycastParams.FilterType = Enum.RaycastFilterType.Include
beachRaycastParams.FilterDescendantsInstances = { Workspace.Terrain }
beachRaycastParams.IgnoreWater = true

-- Mesmo raio de busca que ItemSpawner.lua usa pra amostrar a zona "Praia".
local BEACH_SEARCH_RADIUS = 260

-- Acha UM ponto de areia real (Terrain, material Sand) via raycast --
-- não depende de nenhuma Part fixa, então funciona não importa onde a
-- ilha procedural (seed variável) tenha ficado.
local function findBeachAnchor(): Vector3?
	for _ = 1, 60 do
		local x = (math.random() * 2 - 1) * BEACH_SEARCH_RADIUS
		local z = (math.random() * 2 - 1) * BEACH_SEARCH_RADIUS
		local result = Workspace:Raycast(Vector3.new(x, 400, z), Vector3.new(0, -900, 0), beachRaycastParams)
		if result and result.Material == Enum.Material.Sand then
			return result.Position
		end
	end
	return nil
end

local function teleportToIsland(players: { Player })
	local monsterSpawn = findMonsterSpawn()
	if not monsterSpawn then
		warn("[LobbyManager] Sem marcador MonstroSpawn (gere a caverna) -- Monstro nasce na praia com os outros.")
	end

	-- Um ponto de praia só por rodada -- todo mundo desembarca perto, não
	-- espalhado em pontos fixos de antes da ilha existir.
	local beachAnchor = findBeachAnchor()
	local fallbackSpawns: { BasePart } = {}
	if not beachAnchor then
		fallbackSpawns = getIslandSpawns()
		if #fallbackSpawns == 0 then
			warn("[LobbyManager] Não achei praia (Terrain Sand) nem IlhaSpawns -- gere a ilha primeiro (IslandGenerator.Generate()).")
			return
		end
		warn("[LobbyManager] Não achei praia por raycast -- usando IlhaSpawns como fallback.")
	end

	local fallbackIndex = 0
	for _, player in players do
		local character = player.Character
		if character then
			if monsterSpawn and player:GetAttribute("Role") == GameConfig.Roles.Monster then
				-- Dentro da caverna o raycast de cima bateria no topo da
				-- montanha, então usa a posição do marcador direto.
				character:PivotTo(CFrame.new(monsterSpawn.Position + Vector3.new(0, 3, 0)))
			elseif beachAnchor then
				local x = beachAnchor.X + math.random(-12, 12)
				local z = beachAnchor.Z + math.random(-12, 12)
				local groundY = findGroundY(x, z, beachAnchor.Y)
				character:PivotTo(CFrame.new(x, groundY + 4, z))
			else
				-- Distribui em sequência; com mais jogadores que pontos, repete
				-- os pontos (não deveria acontecer dentro de Players.Max).
				fallbackIndex += 1
				local spawnPart = fallbackSpawns[((fallbackIndex - 1) % #fallbackSpawns) + 1]
				local groundY = findGroundY(spawnPart.Position.X, spawnPart.Position.Z, spawnPart.Position.Y)
				character:PivotTo(CFrame.new(spawnPart.Position.X, groundY + 4, spawnPart.Position.Z))
			end
		end
	end

	-- MODO DE TESTE (GameConfig.Testing.ItemsNearSpawn): larga uma amostra
	-- de itens do lado do desembarque, pra testar pegar/usar sem procurar
	-- pela ilha inteira.
	--
	-- Em background e DEPOIS do teleporte de propósito: criar a Lanterna e o
	-- Chocolate baixa os modelos do Toolbox (InsertService:LoadAsset yielda,
	-- pode levar segundos na primeira vez), e isso não pode segurar o
	-- desembarque de ninguém. Os itens simplesmente aparecem um instante
	-- depois, ao lado de quem já chegou.
	--
	-- O require é preguiçoso: fora do modo de teste, o gameplay não passa a
	-- depender de um módulo de Tools/.
	if beachAnchor and GameConfig.Testing.ItemsNearSpawn then
		local anchor = beachAnchor :: Vector3
		task.spawn(function()
			local ItemSpawner = require(script.Parent.Tools.ItemSpawner)
			ItemSpawner.SpawnSampleNear(anchor)
		end)
	end
end

local function returnEveryoneToLobby()
	for _, player in Players:GetPlayers() do
		player:LoadCharacter() -- única SpawnLocation do jogo é a do Lobby
	end
end

--------------------------------------------------------------------------------
-- Prompt "IniciarPartida"
--------------------------------------------------------------------------------

local function onIniciarPartidaTriggered(player: Player)
	if not isAuthorizedToStart(player) then
		Remotes.LobbyMessage:FireClient(player, "Só o host pode iniciar a partida (modo de teste).")
		return
	end

	if RoundManager.IsRoundActive() then
		Remotes.LobbyMessage:FireClient(player, "Já tem uma partida em andamento.")
		return
	end

	local playerCount = #Players:GetPlayers()

	-- GameConfig.Testing.SoloStart (temporário) deixa começar sozinho.
	if not GameConfig.Testing.SoloStart and playerCount < GameConfig.Players.Min then
		local missing = GameConfig.Players.Min - playerCount
		Remotes.LobbyMessage:FireClient(
			player,
			string.format("Faltam %d jogador(es) para iniciar (mínimo %d).", missing, GameConfig.Players.Min)
		)
		return
	end

	if playerCount > GameConfig.Players.Max then
		local excess = playerCount - GameConfig.Players.Max
		Remotes.LobbyMessage:FireClient(
			player,
			string.format("Jogadores demais: tire %d (máximo %d).", excess, GameConfig.Players.Max)
		)
		return
	end

	task.spawn(RoundManager.StartRound)
end

local function setupIniciarPartidaPrompt()
	local part = Workspace:FindFirstChild("IniciarPartida")
	if not part then
		warn("[LobbyManager] Part 'IniciarPartida' não encontrada no Workspace.")
		return
	end

	local prompt = part:FindFirstChildOfClass("ProximityPrompt")
	if not prompt then
		warn("[LobbyManager] Part 'IniciarPartida' não tem ProximityPrompt.")
		return
	end

	prompt.Triggered:Connect(onIniciarPartidaTriggered)
end

--------------------------------------------------------------------------------
-- Init
--------------------------------------------------------------------------------

--[[
	Init()
	Liga o prompt do Lobby e os hooks de início/fim de partida do
	RoundManager. Chame uma vez no boot do servidor.
]]
function LobbyManager.Init()
	ensureLobbyExists()
	setupIniciarPartidaPrompt()

	RoundManager.RoundPrepared.Event:Connect(teleportToIsland)

	RoundManager.RoundEnded.Event:Connect(function(_winner: string, _reason: string)
		task.delay(GameConfig.Round.IntermissionDuration, returnEveryoneToLobby)
	end)
end

return LobbyManager
