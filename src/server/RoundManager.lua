--!strict
--[[
	RoundManager
	Orquestra a partida: fases, condições de vitória, resultado e reset.

	FASES
	  Percorre GameConfig.PhaseOrder (Queda -> Exploracao -> Corrida ->
	  Desfecho) usando a duração `Default` de cada uma, e dispara
	  RoundStateChanged(phase, phaseEndsAt) a cada troca. A espera de cada
	  fase é interrompida assim que a partida termina por vitória.

	CONDIÇÕES DE VITÓRIA (checadas a cada GameConfig.Round.WinCheckInterval)
	Sobreviventes: helicóptero do resgate decolou com alguém a bordo.
	  Monstro:       nº de Sobreviventes VIVOS <= MonsterWinsAtSurvivorsAlive
	                 antes do tempo acabar. Espião não conta como Sobrevivente.
	  Espião:        tempo acabou, nenhuma fuga deu certo, e ele não foi
	                 eliminado.
	  Ninguém:       tempo acabou, nenhuma fuga, e o Espião já estava morto.
	                 Esse caso não foi especificado -- escolhi empate em vez de
	                 inventar um vencedor. Fácil de trocar em resolveTimeout().

	SOBRE O RÁDIO: RadioObjective não declara vitória, ele dispara
	RescueCountdownStarted(duration) -- que aqui só CHAMA o resgate
	(ExtractionSystem.Begin). Concluir o rádio não ganha nada sozinho: nasce
	uma zona de pouso na praia, a contagem corre e os Sobreviventes têm que
	atravessar a ilha até lá. Quem entrega a vitória é
	ExtractionSystem.SurvivorsExtracted, quando o helicóptero decola com
	alguém a bordo -- até esse instante o Monstro ainda pode virar o jogo.
	Ver docs/Extracao.md.

	RESET: no começo de cada partida os objetivos são zerados, os Attributes
	de estado limpos e todo mundo recebe um character novo. No fluxo normal os
	papéis já foram sorteados antes da seleção de sobrevivente; chamadas diretas
	de StartRound continuam recebendo um sorteio de segurança.

	QUEM CHAMA StartRound(participants): WaitingRoomManager, após a contagem
	com todos prontos. A lista fica congelada durante o preparo e não inclui
	quem entra no servidor depois. A chamada bloqueia até o fim da rodada.

	HOOKS PRA QUEM PRECISA SABER DO INÍCIO/FIM (ex: LobbyManager,
	SoundManager) -- de novo, porque FireAllClients não volta pro servidor:
		RoundManager.RoundPrepared.Event -- (players) depois do LoadCharacter
			e desembarque de todo mundo, ANTES das fases começarem.
		RoundManager.RoundEnded.Event -- (winner, reason) quando a partida
			termina de vez (já com o resultado impresso no console).

	Uso (chamar uma vez no boot do servidor):
		local RoundManager = require(script.RoundManager)
		RoundManager.Init()
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local GameConfig = require(ReplicatedStorage.Modules.GameConfig)
local Remotes = require(ReplicatedStorage.Modules.Remotes)

local Elimination = require(script.Parent.Elimination)
local RadioObjective = require(script.Parent.RadioObjective)
local RadioSiteSystem = require(script.Parent.RadioSiteSystem)
local ExtractionSystem = require(script.Parent.ExtractionSystem)
local RoleAssignment = require(script.Parent.RoleAssignment)
local CharacterPresentation = require(script.Parent.CharacterPresentation)

local RoundManager = {}

-- Hook público: FireAllClients não volta pro próprio servidor, então quem
-- precisar reagir a troca de fase NO SERVIDOR (ex: SoundManager) escuta aqui
-- em vez de RoundStateChanged.
RoundManager.PhaseChanged = Instance.new("BindableEvent")

-- Notifica os sistemas depois do reset/respawn e desembarque de todo mundo.
RoundManager.RoundPrepared = Instance.new("BindableEvent")

-- Dispara quando a partida termina de vez (já com outcome resolvido).
RoundManager.RoundEnded = Instance.new("BindableEvent")

local WINNER_SURVIVORS = "Sobreviventes"
local WINNER_NOBODY = "Ninguem"

type Outcome = {
	winner: string,
	reason: string,
}

local roundActive = false
local roundBusy = false
local roundGeneration = 0
local initialSurvivors = 0
local initialMonsters = 0
local spawnHandler: (({ Player }) -> ())? = nil
local participants: { Player } = {}
local escapeSucceeded = false
local outcome: Outcome? = nil

-- WaitingRoomManager permite iniciar sozinho quando um desenvolvedor escolhe
-- explicitamente Sobrevivente ou Monstro. A mesma exceção precisa existir
-- aqui; antes, a sala aceitava o teste e o RoundManager o rejeitava por ainda
-- exigir dois participantes.
local function canStartDevSolo(player: Player): boolean
	if GameConfig.Testing.DevRoleChooser ~= true then return false end
	local role = player:GetAttribute("DevForceRole")
	if role ~= GameConfig.Roles.Survivor and role ~= GameConfig.Roles.Monster then return false end
	return RunService:IsStudio() or table.find(GameConfig.Testing.DevRoleUserIds, player.UserId) ~= nil
end

--------------------------------------------------------------------------------
-- Estado dos jogadores
--------------------------------------------------------------------------------

local function isAlive(player: Player): boolean
	return player.Parent == Players and not Elimination.IsEliminated(player)
end

local function countAlive(roleName: string): number
	local count = 0
	for _, player in participants do
		if player:GetAttribute("Role") == roleName and isAlive(player) then
			count += 1
		end
	end
	return count
end

--------------------------------------------------------------------------------
-- Encerramento
--------------------------------------------------------------------------------

-- Primeira condição a bater encerra a partida; as demais viram no-op.
local function finishRound(winner: string, reason: string)
	if not roundActive then
		return
	end

	roundActive = false
	outcome = { winner = winner, reason = reason }
end

local function resolveTimeout()
	if escapeSucceeded then
		return -- não deveria acontecer: uma fuga já teria encerrado a partida
	end

	if countAlive(GameConfig.Roles.Spy) > 0 then
		finishRound(GameConfig.Roles.Spy, "Tempo esgotado sem nenhuma fuga, e o Espião sobreviveu")
	else
		finishRound(WINNER_NOBODY, "Tempo esgotado sem nenhuma fuga, e o Espião já havia sido eliminado")
	end
end

--------------------------------------------------------------------------------
-- Hooks dos objetivos
--------------------------------------------------------------------------------

--[[
	onRescueCountdownStarted(duration)
	O rádio CHAMA o resgate; não ganha a partida sozinho. Quem entrega a
	vitória é ExtractionSystem, quando o helicóptero decola com alguém a
	bordo (ExtractionSystem.SurvivorsExtracted -> onExtracted).

	Só existe uma exceção: se a zona de extração não puder ser montada (mapa
	sem praia/ilha gerada), volta pro comportamento antigo de vitória por
	tempo -- caso contrário concluir o rádio deixaria a partida sem desfecho
	nenhum, que é pior do que um desfecho simplificado.
]]
local function onRescueCountdownStarted(duration: number)
	if not roundActive then
		return
	end

	if ExtractionSystem.Begin(duration) then
		print(string.format("[RoundManager] Rádio concluído -- helicóptero pousa em %ds na praia.", duration))
		return
	end

	warn("[RoundManager] Sem zona de extração: caindo na vitória por tempo do resgate.")
	local token = roundGeneration
	task.delay(duration, function()
		if not roundActive or roundGeneration ~= token then
			return -- partida já acabou durante a contagem
		end

		escapeSucceeded = true
		finishRound(WINNER_SURVIVORS, "Resgate pelo rádio concluído")
	end)
end

local function onExtracted(rescued: { Player })
	if not roundActive then
		return
	end

	if #rescued == 0 then
		print("[RoundManager] Helicóptero decolou vazio -- ninguém foi resgatado.")
		return
	end

	escapeSucceeded = true

	local names = {}
	for _, player in rescued do
		table.insert(names, player.Name)
	end

	finishRound(WINNER_SURVIVORS, string.format("Resgate de helicóptero: %s", table.concat(names, ", ")))
end

--------------------------------------------------------------------------------
-- Loop de checagem contínua
--------------------------------------------------------------------------------

local function startWinCheckLoop()
	local token = roundGeneration
	task.spawn(function()
		while roundActive and roundGeneration == token do
			local survivorsAlive = countAlive(GameConfig.Roles.Survivor)

			local connected = 0
			for _, player in participants do
				if player.Parent == Players then connected += 1 end
			end
			if connected == 0 then
				finishRound(WINNER_NOBODY, "Todos os participantes sairam da partida")
				return
			end

			if initialMonsters > 0 and initialSurvivors > 0 and countAlive(GameConfig.Roles.Monster) == 0 then
				finishRound(WINNER_SURVIVORS, "O Monstro foi eliminado ou saiu da partida")
				return
			end

			if initialMonsters > 0 and initialSurvivors > 0
				and survivorsAlive <= math.min(GameConfig.Round.MonsterWinsAtSurvivorsAlive, initialSurvivors - 1) then
				finishRound(
					GameConfig.Roles.Monster,
					string.format("Sobreviventes vivos: %d", survivorsAlive)
				)
				return
			end

			task.wait(GameConfig.Round.WinCheckInterval)
		end
	end)
end

--------------------------------------------------------------------------------
-- Fases
--------------------------------------------------------------------------------

-- Espera a fase inteira, mas sai na hora se a partida terminar no meio.
local function waitPhase(duration: number)
	local deadline = os.clock() + duration
	while roundActive and os.clock() < deadline do
		task.wait(GameConfig.Round.WinCheckInterval)
	end
end

local function runPhases()
	for _, phaseName in GameConfig.PhaseOrder do
		if not roundActive then
			return
		end

		local phase = GameConfig.Phases[phaseName]
		local duration = phase.Default

		for _, player in participants do
			if player.Parent == Players then
				Remotes.RoundStateChanged:FireClient(player, phaseName, os.time() + duration)
			end
		end
		RoundManager.PhaseChanged:Fire(phaseName)
		print(string.format("[RoundManager] Fase: %s (%ds)", phaseName, duration))

		waitPhase(duration)
	end
end

--------------------------------------------------------------------------------
-- Preparação e resultado
--------------------------------------------------------------------------------

local function prepareRound(players: { Player })
	RadioObjective.Reset()
	-- Zera a estacao: sem combustivel, sem fusivel, galoes cheios de novo.
	RadioSiteSystem.Reset()
	-- Some com a zona de extração e o helicóptero da rodada anterior.
	ExtractionSystem.Reset()
	local radioPiecesOk, RadioPieces = pcall(require, script.Parent.RadioPieces)
	if radioPiecesOk then
		local pieces = RadioPieces :: { Init: () -> (), Reset: () -> () }
		local resetOk, resetErr = pcall(function()
			pieces.Init()
			pieces.Reset()
		end)
		if not resetOk then
			warn("[RoundManager] RadioPieces.Reset falhou; a partida vai continuar sem resetar as pecas do radio: " .. tostring(resetErr))
		end
	else
		warn("[RoundManager] RadioPieces falhou ao carregar; a partida vai continuar sem as pecas do radio: " .. tostring(RadioPieces))
	end
	escapeSucceeded = false
	outcome = nil

	local connected = {}
	for _, player in players do
		if player.Parent == Players then table.insert(connected, player) end
	end
	local devSolo = #connected == 1 and canStartDevSolo(connected[1])
	local minimum = if GameConfig.Testing.SoloStart or devSolo then 1 else math.max(2, GameConfig.Players.Min)
	assert(#connected >= minimum, "Jogadores insuficientes após preparar a partida.")
	-- WaitingRoomManager sorteia antes da tela de selecao para que apenas os
	-- jogadores humanos a vejam. Mantemos o fallback para testes/admin que
	-- chamem StartRound diretamente.
	local rolesPrepared = true
	for _, player in connected do
		local role = player:GetAttribute("Role")
		if role ~= GameConfig.Roles.Survivor
			and role ~= GameConfig.Roles.Monster
			and role ~= GameConfig.Roles.Spy then
			rolesPrepared = false
			break
		end
	end
	if not rolesPrepared then RoleAssignment.AssignRoles(connected) end

	local spawnedCharacters: { [Player]: Model } = {}
	for _, player in connected do
		player:SetAttribute("InRound", true)
		player:SetAttribute("CharacterSelectOpen", nil)
		-- A marca de eliminado agora vive no Player (sobrevive ao respawn do
		-- DeathRespawnHandler do pacote de movimento), então precisa ser
		-- limpa aqui -- senão quem morreu na partida passada nasce eliminado.
		Elimination.Reset(player)
		local character = CharacterPresentation.SpawnGameCharacter(player)
		spawnedCharacters[player] = character
		assert(character, "Personagem nao foi criado durante a preparacao.")
		assert(character:WaitForChild("HumanoidRootPart", 10), "Personagem sem HumanoidRootPart durante a preparacao.")
		assert(character:FindFirstChildOfClass("Humanoid") or character:WaitForChild("Humanoid", 10), "Personagem sem Humanoid durante a preparacao.")
	end

	-- Todos os corpos são publicados primeiro, então os clientes preparam
	-- câmera e movimento em paralelo. Só depois liberamos física/teleporte.
	for _, player in connected do
		CharacterPresentation.AwaitGameCharacterReady(player, spawnedCharacters[player], 6)
	end

	participants = connected
	initialSurvivors = countAlive(GameConfig.Roles.Survivor)
	initialMonsters = countAlive(GameConfig.Roles.Monster)
end

local function printResult(result: Outcome)
	print("==================================================")
	print(string.format("[RoundManager] Fim de partida -- vencedor: %s", result.winner))
	print(string.format("[RoundManager] Motivo: %s", result.reason))
	print(
		string.format(
			"[RoundManager] Vivos no fim -- Sobreviventes: %d | Monstro: %d | Espião: %d",
			countAlive(GameConfig.Roles.Survivor),
			countAlive(GameConfig.Roles.Monster),
			countAlive(GameConfig.Roles.Spy)
		)
	)
	print("==================================================")
end

--------------------------------------------------------------------------------
-- API
--------------------------------------------------------------------------------

--[[
	StartRound(players)
	Roda uma partida com a lista fechada da sala. Rejeita início concorrente
	e personagens duplicados antes de qualquer operação que ceda execução.
]]
function RoundManager.StartRound(players: { Player })
	assert(not roundBusy, "Já existe uma partida em preparação ou andamento.")
	roundBusy = true
	roundGeneration += 1
	participants = table.clone(players)
	local ok, err = pcall(function()
		assert(#participants > 0, "A sala está vazia.")
		prepareRound(participants)
		local handler = spawnHandler
		assert(handler, "O transporte para a ilha nao foi inicializado.")
		handler(participants)
		for _, player in participants do
			assert(player.Parent == Players, "Um participante saiu durante a preparacao.")
		end
	end)
	if not ok then
		roundBusy = false
		participants = {}
		error(err)
	end
	roundActive = true
	local played, playError = pcall(function()
		RoundManager.RoundPrepared:Fire(participants)
		startWinCheckLoop()
		runPhases()
		if roundActive then resolveTimeout() end
	end)
	if not played then
		warn("[RoundManager] Erro durante a partida: " .. tostring(playError))
		finishRound(WINNER_NOBODY, "Partida interrompida por erro do servidor")
	end

	local result = outcome or { winner = WINNER_NOBODY, reason = "Partida encerrada sem resultado definido" }
	printResult(result)

	-- Remote pros clientes (esconder HUD etc.) + hook pro servidor
	-- (LobbyManager devolver todo mundo pro Lobby).
	for _, player in participants do
		if player.Parent == Players then
			Remotes.RoundEnded:FireClient(player, result.winner, result.reason)
		end
	end
	RoundManager.RoundEnded:Fire(result.winner, result.reason)
	roundBusy = false
end

-- O transporte pode ceder execucao para streaming; um BindableEvent nao
-- espera seus listeners e permitiria comecar a rodada antes do desembarque.
function RoundManager.SetSpawnHandler(handler: ({ Player }) -> ())
	assert(not roundBusy, "Nao e possivel trocar o transporte durante uma partida.")
	spawnHandler = handler
end

--[[
	IsRoundActive()
	Pra outros sistemas consultarem se há partida em andamento.
]]
function RoundManager.IsRoundActive(): boolean
	return roundActive
end

--[[
	Init()
	Conecta os hooks dos objetivos. NÃO inicia partidas sozinho -- isso é
	responsabilidade de WaitingRoomManager. Chame uma vez no boot do servidor.
]]
function RoundManager.Init()
	RadioObjective.RescueCountdownStarted.Event:Connect(onRescueCountdownStarted)
	ExtractionSystem.SurvivorsExtracted.Event:Connect(onExtracted)
end

return RoundManager
