--!strict
--[[
	LobbyManager
	Cuida do lobby e dos teleportes: Lobby -> Ilha -> Lobby.

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
	  2) WaitingRoomManager valida a fase e as vagas para qualquer jogador;
	     a fila permanece no lobby, sem criar uma sala física.
	  3) Cada participante escolhe skin/perk e marca Pronto. Com o mínimo e
	     todos prontos, os papéis são sorteados e abre a seleção autoritativa
	     de 30s. Humanos escolhem um sobrevivente; Monstro recebe Jason. Todos
	     confirmando encerra a etapa antes do prazo.
	  4) Só depois da seleção RoundManager cria os corpos e aguarda o spawn
	     handler depois do LoadCharacter de
	     todo mundo, antes de emitir RoundPrepared e iniciar as fases.
	     Teleportamos: Monstro pro marcador
	     MonstroSpawn dentro da Caverna, todo o resto pra um ponto de praia
	     achado NA HORA por raycast (material Sand do Terrain -- não
	     depende de nenhuma Part fixa, então funciona não importa onde a
	     ilha procedural, seed variável, tenha ficado). "IlhaSpawns"
	     (default.project.json) só entra como fallback, se não achar praia
	     nenhuma (ex: ilha ainda não foi gerada).
	  5) RoundManager.RoundEnded dispara com o resultado; depois de
	     GameConfig.Round.IntermissionDuration segundos, os participantes recebem
	     LoadCharacter() de novo, o que já os manda de volta pro Lobby.

	Uso (chamar uma vez no boot do servidor, depois de RoundManager.Init()):
		local LobbyManager = require(script.LobbyManager)
		LobbyManager.Init()
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local GameConfig = require(ReplicatedStorage.Modules.GameConfig)
local RoundManager = require(script.Parent.RoundManager)
local WaitingRoomManager = require(script.Parent.WaitingRoomManager)
local IslandLayout = require(script.Parent.Tools.IslandLayout)
local CharacterPresentation = require(script.Parent.CharacterPresentation)

local LobbyManager = {}
local initialized = false

--------------------------------------------------------------------------------
-- Lobby (posição sempre FORÇADA aqui -- ver nota no cabeçalho)
--------------------------------------------------------------------------------

-- Fica longe da área que o IslandGenerator escreve terreno (IslandLayout
-- AreaHalf = 960 -> terreno até z = -960) e do raio máximo da ilha, pra nada
-- da geração encostar no Lobby. Precisa bater com default.project.json e
-- com uma sala de espera separada (que não existe mais).
local LOBBY_ORIGIN = Vector3.new(0, 40, -1500)

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
	local prompt = startPart:FindFirstChildOfClass("ProximityPrompt") :: ProximityPrompt
	prompt.ActionText = "Iniciar partida"
	prompt.ObjectText = "Preparação da partida"
	prompt.Enabled = true
	prompt.MaxActivationDistance = 10
	prompt.HoldDuration = 0
	prompt.RequiresLineOfSight = false

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

local function getEmergencyIslandSpawn(): BasePart
	local spawn = Workspace:FindFirstChild("IlhaSpawnEmergencia")
	if spawn and spawn:IsA("BasePart") then
		return spawn
	end
	local part = Instance.new("Part")
	part.Name = "IlhaSpawnEmergencia"
	part.Anchored = true
	part.CanCollide = true
	part.Size = Vector3.new(24, 1, 24)
	part.Position = Vector3.new(60, 2, 0)
	part.Color = Color3.fromRGB(88, 92, 78)
	part.Material = Enum.Material.WoodPlanks
	part.Parent = Workspace
	return part
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

-- Raio de busca = raio máximo da costa (IslandLayout), o mesmo que
-- ItemSpawner/WeaponSpawner/LootCrateSystem usam.
local BEACH_SEARCH_RADIUS = IslandLayout.CoastRadiusMax()

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

-- Marcadores "SpawnPOI" (Structures.SpawnPoint) espalhados pelos pontos de
-- interesse: porta de cada cabana, lodge, celeiro, torre, farol, vila,
-- ruínas. Embaralhados, um por sobrevivente -- é o "todo mundo começa num
-- canto diferente do acampamento" do Friday the 13th.
local function collectPoiSpawns(): { Vector3 }
	local points: { Vector3 } = {}
	local ilha = Workspace:FindFirstChild("Ilha")
	if not ilha then
		return points
	end
	for _, d in ilha:GetDescendants() do
		if d:IsA("BasePart") and d:GetAttribute("SpawnPOI") == true then
			table.insert(points, d.Position)
		end
	end
	-- Fisher-Yates.
	for i = #points, 2, -1 do
		local j = math.random(1, i)
		points[i], points[j] = points[j], points[i]
	end
	return points
end

-- Com StreamingEnabled o cliente ainda não carregou o pedaço do mapa onde
-- ele vai cair; pedir o stream antes evita cair no void por um instante.
local function prepareStream(player: Player, position: Vector3)
	pcall(function()
		player:RequestStreamAroundAsync(position, 3)
	end)
end

local function moveToIsland(player: Player, character: Model, target: Vector3)
	local root = character:WaitForChild("HumanoidRootPart", 10)
	assert(root and root:IsA("BasePart"), "Personagem sem HumanoidRootPart durante o desembarque.")
	local wasAnchored = root.Anchored
	root.Anchored = true
	local ok, err = pcall(function()
		prepareStream(player, target)
		local humanoid = character:FindFirstChildOfClass("Humanoid")
		assert(player.Parent == Players and player.Character == character
			and humanoid and humanoid.Health > 0, "Participante indisponivel durante o desembarque.")
		root.AssemblyLinearVelocity = Vector3.zero
		root.AssemblyAngularVelocity = Vector3.zero
		character:PivotTo(CFrame.new(target))
	end)
	if root.Parent then root.Anchored = wasAnchored end
	if not ok then error(err) end
end

local function teleportToIsland(players: { Player })
	local monsterSpawn = findMonsterSpawn()
	if not monsterSpawn then
		warn("[LobbyManager] Sem marcador MonstroSpawn (gere a caverna) -- Monstro nasce com os outros.")
	end

	local poiSpawns = collectPoiSpawns()
	local beachAnchor: Vector3? = nil
	local fallbackSpawns: { BasePart } = {}
	if #poiSpawns == 0 then
		-- Mapa sem POIs (versão antiga salva): todo mundo numa praia.
		beachAnchor = findBeachAnchor()
		if not beachAnchor then
			fallbackSpawns = getIslandSpawns()
			if #fallbackSpawns == 0 then
				warn("[LobbyManager] Não achei POIs, praia nem IlhaSpawns -- usando spawn provisório de emergência.")
				fallbackSpawns = { getEmergencyIslandSpawn() }
			end
			warn("[LobbyManager] Não achei POIs nem praia por raycast -- usando IlhaSpawns como fallback.")
		end
	end

	local poiIndex = 0
	local fallbackIndex = 0
	for _, player in players do
		local character = player.Character
		assert(character, "Participante sem personagem durante o desembarque.")
		if character then
			if monsterSpawn and player:GetAttribute("Role") == GameConfig.Roles.Monster then
				-- Dentro da caverna o raycast de cima bateria no topo da
				-- montanha, então usa a posição do marcador direto.
				local target = monsterSpawn.Position + Vector3.new(0, 3, 0)
				moveToIsland(player, character, target)
			elseif #poiSpawns > 0 then
				poiIndex += 1
				local p = poiSpawns[((poiIndex - 1) % #poiSpawns) + 1]
				local groundY = findGroundY(p.X, p.Z, p.Y)
				local target = Vector3.new(p.X, groundY + 4, p.Z)
				moveToIsland(player, character, target)
			elseif beachAnchor then
				local x = beachAnchor.X + math.random(-12, 12)
				local z = beachAnchor.Z + math.random(-12, 12)
				local groundY = findGroundY(x, z, beachAnchor.Y)
				local target = Vector3.new(x, groundY + 4, z)
				moveToIsland(player, character, target)
			else
				-- Distribui em sequência; com mais jogadores que pontos, repete
				-- os pontos (não deveria acontecer dentro de Players.Max).
				fallbackIndex += 1
				local spawnPart = fallbackSpawns[((fallbackIndex - 1) % #fallbackSpawns) + 1]
				local groundY = findGroundY(spawnPart.Position.X, spawnPart.Position.Z, spawnPart.Position.Y)
				moveToIsland(player, character, Vector3.new(spawnPart.Position.X, groundY + 4, spawnPart.Position.Z))
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
	if GameConfig.Testing.ItemsNearSpawn then
		local anchor = beachAnchor or poiSpawns[1]
		if anchor then
			task.spawn(function()
				local ItemSpawner = require(script.Parent.Tools.ItemSpawner)
				ItemSpawner.SpawnSampleNear(anchor)
			end)
		end
	end
end

local function returnEveryoneToLobby()
	local participants = WaitingRoomManager.Reset()
	for _, player in participants do
		if player.Parent == Players then
			local ok, err = pcall(function() CharacterPresentation.SpawnLobbyAvatar(player) end)
			if not ok then warn("[LobbyManager] Falha ao retornar ao lobby: " .. tostring(err)) end
		end
	end
	WaitingRoomManager.OpenLobby()
end

--------------------------------------------------------------------------------
-- Prompt "IniciarPartida"
--------------------------------------------------------------------------------

local function onIniciarPartidaTriggered(player: Player)
	WaitingRoomManager.Join(player)
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

-- Registra no carregamento do módulo. Assim o transporte já existe mesmo se
-- alguma etapa visual do Init do lobby falhar; StartRound nunca troca o corpo
-- e o deixa abandonado na fila.
RoundManager.SetSpawnHandler(teleportToIsland)

--------------------------------------------------------------------------------
-- Init
--------------------------------------------------------------------------------

--[[
	Init()
	Liga o prompt do Lobby e os hooks de início/fim de partida do
	RoundManager. Chame uma vez no boot do servidor.
]]
function LobbyManager.Init()
	if initialized then return end
	initialized = true
	ensureLobbyExists()
	setupIniciarPartidaPrompt()

	RoundManager.RoundEnded.Event:Connect(function(_winner: string, _reason: string)
		task.delay(GameConfig.Round.IntermissionDuration, returnEveryoneToLobby)
	end)
end

return LobbyManager
