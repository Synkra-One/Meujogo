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
	  Sobreviventes: rádio concluído (fim da contagem de resgate) OU jangada
	                 empurrada ao mar com alguém a bordo.
	  Monstro:       nº de Sobreviventes VIVOS <= MonsterWinsAtSurvivorsAlive
	                 antes do tempo acabar. Espião não conta como Sobrevivente.
	  Espião:        tempo acabou, nenhuma fuga deu certo, e ele não foi
	                 eliminado.
	  Ninguém:       tempo acabou, nenhuma fuga, e o Espião já estava morto.
	                 Esse caso não foi especificado -- escolhi empate em vez de
	                 inventar um vencedor. Fácil de trocar em resolveTimeout().

	SOBRE O RÁDIO: RadioObjective não declara vitória, ele dispara
	RescueCountdownStarted(duration). Aqui a contagem é executada e, se a
	partida ainda estiver rodando quando ela terminar, os Sobreviventes
	vencem. Ou seja: o Monstro ainda tem essa janela pra virar o jogo. Se
	você quiser vitória instantânea no RadioCompleto, é só declarar direto
	em onRescueCountdownStarted, sem esperar.

	RESET: no começo de cada partida os objetivos são zerados, os Attributes
	de estado limpos, todo mundo recebe um character novo (LoadCharacter) e
	os papéis são sorteados de novo.

	QUEM CHAMA StartRound(): este módulo NÃO inicia partidas sozinho -- isso
	mudou quando o LobbyManager passou a existir. StartRound() é pública e
	fica esperando ser chamada (hoje, pelo prompt "IniciarPartida" do
	Lobby). Ela BLOQUEIA até a partida inteira acabar, então quem chama
	deve usar task.spawn(RoundManager.StartRound).

	HOOKS PRA QUEM PRECISA SABER DO INÍCIO/FIM (ex: LobbyManager,
	SoundManager) -- de novo, porque FireAllClients não volta pro servidor:
		RoundManager.RoundPrepared.Event -- (players) depois do LoadCharacter
			de todo mundo, ANTES das fases começarem. É o momento certo pra
			teleportar todo mundo pra onde a partida deve acontecer.
		RoundManager.RoundEnded.Event -- (winner, reason) quando a partida
			termina de vez (já com o resultado impresso no console).

	Uso (chamar uma vez no boot do servidor):
		local RoundManager = require(script.RoundManager)
		RoundManager.Init()
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage.Modules.GameConfig)
local Remotes = require(ReplicatedStorage.Modules.Remotes)

local Elimination = require(script.Parent.Elimination)
local RadioObjective = require(script.Parent.RadioObjective)
local RaftObjective = require(script.Parent.RaftObjective)
local RoleAssignment = require(script.Parent.RoleAssignment)

local RoundManager = {}

-- Hook público: FireAllClients não volta pro próprio servidor, então quem
-- precisar reagir a troca de fase NO SERVIDOR (ex: SoundManager) escuta aqui
-- em vez de RoundStateChanged.
RoundManager.PhaseChanged = Instance.new("BindableEvent")

-- Fica logo depois do reset/respawn de todo mundo, antes das fases
-- começarem -- o momento certo de teleportar os jogadores pro mapa da rodada.
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
local escapeSucceeded = false
local outcome: Outcome? = nil

--------------------------------------------------------------------------------
-- Estado dos jogadores
--------------------------------------------------------------------------------

local function isAlive(player: Player): boolean
	return player.Parent ~= nil and not Elimination.IsEliminated(player)
end

local function countAlive(roleName: string): number
	local count = 0
	for _, player in Players:GetPlayers() do
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

local function onRescueCountdownStarted(duration: number)
	if not roundActive then
		return
	end

	print(string.format("[RoundManager] Rádio concluído -- resgate chega em %ds.", duration))

	task.delay(duration, function()
		if not roundActive then
			return -- partida já acabou durante a contagem
		end

		escapeSucceeded = true
		finishRound(WINNER_SURVIVORS, "Resgate pelo rádio concluído")
	end)
end

local function onRaftEscaped(escapedPlayers: { Player })
	if not roundActive then
		return
	end

	if #escapedPlayers == 0 then
		print("[RoundManager] Jangada partiu vazia -- ninguém escapou.")
		return
	end

	escapeSucceeded = true

	local names = {}
	for _, player in escapedPlayers do
		table.insert(names, player.Name)
	end

	finishRound(WINNER_SURVIVORS, string.format("Fuga na jangada: %s", table.concat(names, ", ")))
end

--------------------------------------------------------------------------------
-- Loop de checagem contínua
--------------------------------------------------------------------------------

local function startWinCheckLoop()
	task.spawn(function()
		while roundActive do
			local survivorsAlive = countAlive(GameConfig.Roles.Survivor)

			if survivorsAlive <= GameConfig.Round.MonsterWinsAtSurvivorsAlive then
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

		Remotes.RoundStateChanged:FireAllClients(phaseName, os.time() + duration)
		RoundManager.PhaseChanged:Fire(phaseName)
		print(string.format("[RoundManager] Fase: %s (%ds)", phaseName, duration))

		waitPhase(duration)
	end
end

--------------------------------------------------------------------------------
-- Preparação e resultado
--------------------------------------------------------------------------------

local function prepareRound()
	RadioObjective.Reset()
	RaftObjective.Reset()

	escapeSucceeded = false
	outcome = nil

	local players = Players:GetPlayers()

	for _, player in players do
		player:SetAttribute("Amarrado", false)
		-- A marca de eliminado agora vive no Player (sobrevive ao respawn do
		-- DeathRespawnHandler do pacote de movimento), então precisa ser
		-- limpa aqui -- senão quem morreu na partida passada nasce eliminado.
		Elimination.Reset(player)
		player:LoadCharacter()
	end

	RoleAssignment.AssignRoles(players)
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
	StartRound()
	Roda uma partida inteira e só retorna quando ela termina. Ignora a
	chamada se já houver partida em andamento.
]]
function RoundManager.StartRound()
	if roundActive then
		return
	end

	prepareRound()
	RoundManager.RoundPrepared:Fire(Players:GetPlayers())

	roundActive = true
	startWinCheckLoop()
	runPhases()

	-- Chegou aqui com a partida ainda ativa = as fases acabaram sem vitória.
	if roundActive then
		resolveTimeout()
	end

	local result = outcome or { winner = WINNER_NOBODY, reason = "Partida encerrada sem resultado definido" }
	printResult(result)

	-- Remote pros clientes (esconder HUD etc.) + hook pro servidor
	-- (LobbyManager devolver todo mundo pro Lobby).
	Remotes.RoundEnded:FireAllClients(result.winner, result.reason)
	RoundManager.RoundEnded:Fire(result.winner, result.reason)
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
	responsabilidade de quem chamar StartRound() (hoje, LobbyManager, pelo
	prompt "IniciarPartida"). Chame uma vez no boot do servidor.
]]
function RoundManager.Init()
	RadioObjective.RescueCountdownStarted.Event:Connect(onRescueCountdownStarted)
	RaftObjective.RaftEscaped.Event:Connect(onRaftEscaped)
end

return RoundManager
