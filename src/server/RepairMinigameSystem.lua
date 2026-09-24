--!strict
--[[
	RepairMinigameSystem
	Substitui o "segure E por alguns segundos" dos pontos reparáveis por um
	reparo de PRECISÃO. É AUTORITATIVO: o cliente só desenha a interface e diz
	"apertei no instante t do teste N"; quem classifica o acerto, conta a
	sequência, pune o erro e produz ruído é aqui.

	COMO CONCLUI: NÃO existe progresso passivo. O reparo só termina quando o
	jogador acerta o teste (verde ou azul) `Streak.Required` vezes SEGUIDAS
	(3, por padrão). Erro, amarelo ou teste ignorado zera a sequência. Segurar
	a tecla sem fazer nada nunca conclui -- só gera testes que expiram, e cada
	um faz barulho pro Monstro.

	DIFICULDADE = atributo Reparo (RepairMinigameConfig.Tuning): personagem sem
	Reparo enfrenta área verde estreita, marcador rápido e travada longa depois
	de errar; quem tem Reparo alto, o oposto. A regra (3 seguidas) é a mesma
	pra todos.

	COMO SE LIGA A UM OBJETIVO (não substitui a lógica de ninguém):
		RepairMinigameSystem.Bind(prompt, {
			taskId = "RadioPainel",   -- agrupa o reparo (Reset/ResetTask)
			configId = "RadioPainel", -- chave de RepairMinigameConfig.Tasks
			part = hosts.Painel,      -- ponto físico (alcance + ruído)
			range = CFG.AlcanceInteracao,
			canStart = function(player) ... end,   -- revalidado a cada tique
			onComplete = function(player) ... end,  -- o ANTIGO handler do prompt
		})
	Bind zera o HoldDuration do prompt (quem segura agora é o minigame) e passa
	a tratar Triggered como "começar o reparo". Tudo o que o objetivo já fazia
	continua no onComplete, sem cópia de regra nenhuma pra cá.

	A SEQUÊNCIA É DA SESSÃO: cancelar (soltar, afastar, levar dano...) zera.
	Dois jogadores no mesmo ponto têm uma sequência cada um.

	CANCELAMENTO: soltar a tecla, sair do alcance, perder linha de visão,
		tomar dano, ser atordoado/agarrado, morrer, o canStart do
	objetivo passar a recusar, ou o cliente parar de confirmar que ainda está
	segurando. Em todos os casos a sessão some por um caminho só (stop).

	RUÍDO: só o ERRO (vermelho ou teste expirado) chama o NoiseService, com o
	alcance escalado pela Furtividade do personagem. Começar, continuar ou
	terminar um reparo não entrega ninguém.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Modules.RepairMinigameConfig)
local GameConfig = require(ReplicatedStorage.Modules.GameConfig)
local Remotes = require(ReplicatedStorage.Modules.Remotes)
local StatScaling = require(ReplicatedStorage.Modules.StatScaling)
local InteractionGuard = require(script.Parent.InteractionGuard)
local GeneratorErrorSound = require(script.Parent.GeneratorErrorSound)

local RepairMinigameSystem = {}

-- Hook público: (player, taskId) sempre que um reparo é concluído. Existe pra
-- XP/estatística poderem escutar sem que este módulo conheça quem são.
RepairMinigameSystem.RepairCompleted = Instance.new("BindableEvent")

local KEEPALIVE_TIMEOUT = 1.6 -- sem confirmação do cliente, a sessão cai
local RESTART_COOLDOWN = 0.35 -- evita reabrir no mesmo toque de tecla

type Spec = {
	-- Agrupa o reparo de um ponto (ResetTask). Pontos independentes (ex: cada
	-- fio cortado do mapa) recebem um id próprio.
	taskId: string,
	-- Chave em RepairMinigameConfig.Tasks (rótulo, liga/desliga, acertos).
	-- Vários taskId diferentes podem apontar pro mesmo configId.
	configId: string,
	part: BasePart,
	range: number,
	canStart: (Player) -> (boolean, string?),
	onComplete: (Player) -> (),
}

type Session = {
	player: Player,
	spec: Spec,
	token: number,
	rng: Random,
	tuning: { greenScale: number, periodScale: number, stallScale: number, wobbleAmp: number },
	streak: number, -- acertos seguidos até agora
	required: number, -- acertos seguidos pra concluir
	testsResolved: number,
	scoreSum: number,
	nextTestId: number,
	nextTestAt: number,
	test: Config.Test?,
	lastKeepalive: number,
}

local sessions: { [Player]: Session } = {}
local blockedUntil: { [Player]: number } = {}
local initialized = false
local nextToken = 0

--------------------------------------------------------------------------------
-- Estado do jogador
--------------------------------------------------------------------------------

-- Mesmo contrato das outras interações do jogo (ver RadioSiteSystem.canAct):
-- sobrevivente vivo, na partida, sem estar atordoado/agarrado.
local function canChannel(player: Player): (boolean, string?)
	if player.Parent ~= Players then
		return false, nil
	end
	if player:GetAttribute("InRound") ~= true then
		return false, nil
	end
	if player:GetAttribute("Role") ~= GameConfig.Roles.Survivor then
		return false, "Só os Sobreviventes reparam."
	end
	if player:GetAttribute("Eliminado") == true then
		return false, nil
	end
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not character or not humanoid or humanoid.Health <= 0 then
		return false, nil
	end
	if character:GetAttribute("PowerStunned") == true or character:GetAttribute("GrabLocked") == true
		or character:GetAttribute("FearTripping") == true then
		return false, "Você não consegue se firmar agora."
	end
	return true, nil
end

--------------------------------------------------------------------------------
-- Ciclo de vida da sessão
--------------------------------------------------------------------------------

local function stop(session: Session, reason: string, completed: boolean)
	if sessions[session.player] ~= session then
		return
	end
	sessions[session.player] = nil
	blockedUntil[session.player] = os.clock() + RESTART_COOLDOWN

	local character = session.player.Character
	if character then
		character:SetAttribute("Reparando", nil)
	end

	if session.player.Parent == Players then
		Remotes.RepairMinigame:FireClient(
			session.player,
			"Stop",
			session.token,
			reason,
			completed,
			session.streak,
			session.required
		)
	end
end

local function stopFor(player: Player, reason: string)
	local session = sessions[player]
	if session then
		stop(session, reason, false)
	end
end

--[[
	Cancel(player, reason?)
	Derruba o reparo em andamento de um jogador. Serve pra qualquer sistema
	externo que precise interromper (dano, execução, fim de rodada).
]]
function RepairMinigameSystem.Cancel(player: Player, reason: string?)
	stopFor(player, reason or "Reparo interrompido.")
end

--[[ IsRepairing(player) -- true enquanto existe sessão ativa. ]]
function RepairMinigameSystem.IsRepairing(player: Player): boolean
	return sessions[player] ~= nil
end

--[[
	ApplyPowerBoost(player)
	Gancho do "Conserto Relâmpago": dá `Streak.PowerBoostSteps` acertos de
	graça na sequência do reparo que o jogador ESTÁ fazendo agora e adianta o
	próximo teste. Nunca completa sozinho: sobra sempre pelo menos um acerto
	de verdade. Devolve a Part do ponto, ou nil se não havia reparo em
	andamento ou se ele já estava a um acerto de concluir (o poder não é
	gasto à toa).
]]
function RepairMinigameSystem.ApplyPowerBoost(player: Player): BasePart?
	local session = sessions[player]
	if not session or session.streak >= session.required - 1 then
		return nil
	end
	session.streak = math.min(session.required - 1, session.streak + Config.Streak.PowerBoostSteps)
	if not session.test then
		session.nextTestAt = math.min(session.nextTestAt, Workspace:GetServerTimeNow() + 0.4)
	end
	Remotes.RepairMinigame:FireClient(player, "Streak", session.token, session.streak, session.required)
	return session.spec.part
end

--------------------------------------------------------------------------------
-- Testes de precisão
--------------------------------------------------------------------------------

local function scheduleNextTest(session: Session, first: boolean, extraDelay: number?)
	local bar = Config.Bar
	local gap = if first then bar.FirstGap else bar.Gap
	session.test = nil
	session.nextTestAt = Workspace:GetServerTimeNow() + (extraDelay or 0) + session.rng:NextNumber(gap.Min, gap.Max)
end

local function buildTest(session: Session): Config.Test
	local bar = Config.Bar
	local rng = session.rng
	local tuning = session.tuning

	local greenHalf = math.clamp(
		rng:NextNumber(bar.GreenHalfWidth.Min, bar.GreenHalfWidth.Max) * tuning.greenScale,
		bar.GreenHalfWidthClamp.Min,
		bar.GreenHalfWidthClamp.Max
	)
	local yellowHalf = greenHalf + rng:NextNumber(bar.YellowPad.Min, bar.YellowPad.Max)
	local low = yellowHalf + bar.EdgeMargin
	local high = 1 - low
	-- Barra muito estreita pra sortear: centraliza em vez de inverter a faixa.
	local center = if high > low then rng:NextNumber(low, high) else 0.5
	local perfectHalf = if rng:NextNumber() <= bar.PerfectChance then greenHalf * bar.PerfectFraction else 0

	session.nextTestId += 1
	return {
		id = session.nextTestId,
		startsAt = Workspace:GetServerTimeNow() + bar.LeadIn,
		period = rng:NextNumber(bar.SweepPeriod.Min, bar.SweepPeriod.Max) * tuning.periodScale,
		sweeps = rng:NextInteger(bar.Sweeps.Min, bar.Sweeps.Max),
		center = center,
		greenHalf = greenHalf,
		yellowHalf = yellowHalf,
		perfectHalf = perfectHalf,
		style = rng:NextInteger(1, 3),
		wobbleAmp = tuning.wobbleAmp,
		wobbleFreq = rng:NextNumber(Config.WobbleFreq.Min, Config.WobbleFreq.Max),
		wobblePhase = rng:NextNumber(0, 2 * math.pi),
	}
end

-- Peso do acerto pro indicador de "Precisão" na tela.
local GRADE_SCORE: { [string]: number } = { Perfect = 1, Green = 0.85, Yellow = 0.4, Red = 0, Miss = 0 }

local function emitFailureNoise(session: Session)
	-- Lazy: NoiseService -> RoundManager -> RadioSiteSystem -> este módulo.
	-- Carregar aqui dentro quebra o ciclo sem esconder a dependência.
	local loaded, service = pcall(require, script.Parent.NoiseService)
	if not loaded or type(service) ~= "table" then
		return
	end
	-- FAIXA INVERTIDA (ver StatScaling): Furtividade alta encolhe o alcance.
	local radius = StatScaling.Lerp(StatScaling.Of(session.player, "Furtividade"), Config.Noise.FailRadius)
	-- Posição do OBJETIVO, não do jogador: o Monstro vê onde a ferramenta
	-- caiu. O NoiseService ainda aplica alcance, chance por distância e o
	-- embaralhamento de posição dele -- nada aqui fura aquelas regras.
	local emit = (service :: any).EmitNoise
	emit(service, session.player, session.spec.part.Position, Config.Noise.FailIntensity, radius)
end

-- Choque 3D NO GERADOR, em qualquer erro de qualquer reparo. É ADICIONAL ao
-- ruído de posição acima: aquele é o ping da super audição (sujeito a
-- Furtividade); este é um som de verdade no mundo. Cooldown, destinatários
-- (quem errou + Monstro) e alcance ficam em GeneratorErrorSound.
-- Uma tarefa opta por sair com `GeneratorShock = false` em
-- RepairMinigameConfig.Tasks.
local function playErrorSound(session: Session)
	local task = Config.Tasks[session.spec.configId]
	if task and (task :: any).GeneratorShock == false then
		return
	end
	GeneratorErrorSound.Play(nil, session.player)
end

-- A sequência fechou: encerra a sessão e roda o handler que o objetivo já tinha.
local function finish(session: Session)
	local spec = session.spec
	stop(session, "Reparo concluído.", true)
	local completed, err = pcall(spec.onComplete, session.player)
	if not completed then
		warn(string.format("[RepairMinigame] onComplete de '%s' falhou: %s", spec.taskId, tostring(err)))
		return
	end
	RepairMinigameSystem.RepairCompleted:Fire(session.player, spec.taskId)
end

local function resolveTest(session: Session, test: Config.Test, grade: string)
	local scoring = Config.Scoring
	session.test = nil
	session.testsResolved += 1
	session.scoreSum += GRADE_SCORE[grade] or 0

	local stall = 0
	if grade == "Perfect" or grade == "Green" then
		session.streak += 1
	elseif grade == "Yellow" then
		-- Quase: sem barulho e sem travar, mas não conta como acerto.
		if Config.Streak.YellowBreaks then
			session.streak = 0
		end
	else
		-- Vermelho ou teste ignorado: perde a sequência, faz barulho e trava.
		session.streak = 0
		stall = (if grade == "Miss" then scoring.MissStall else scoring.RedStall) * session.tuning.stallScale
		emitFailureNoise(session)
		playErrorSound(session)
	end

	local accuracy = session.scoreSum / session.testsResolved
	Remotes.RepairMinigame:FireClient(
		session.player,
		"Result",
		session.token,
		test.id,
		grade,
		session.streak,
		session.required,
		stall,
		math.floor(accuracy * 100)
	)

	if session.streak >= session.required then
		finish(session)
	else
		scheduleNextTest(session, false, stall)
	end
end

local function onHit(session: Session, testId: number, claimedAt: number)
	local test = session.test
	if not test or test.id ~= testId then
		return
	end
	local now = Workspace:GetServerTimeNow()
	local arrival = now - test.startsAt
	-- O cliente diz QUANDO apertou; o servidor só aceita se isso bate com a
	-- hora de chegada dentro da latência tolerada. Fora disso vale a chegada.
	-- É o que impede um cliente alterado de alegar o instante perfeito.
	local elapsed = arrival
	if type(claimedAt) == "number" and claimedAt == claimedAt then
		local lag = arrival - claimedAt -- > 0: o pedido demorou a chegar
		-- Aceita atraso de rede até MaxInputLag; um instante no FUTURO (o
		-- cliente alegando um momento que ainda nem chegou) é mentira.
		if lag <= Config.Scoring.MaxInputLag and lag >= -Config.Scoring.FutureSlack then
			elapsed = claimedAt
		end
	end
	elapsed = math.clamp(elapsed, 0, Config.TestWindow(test))

	resolveTest(session, test, Config.Grade(test, Config.MarkerAt(test, elapsed)))
end

--------------------------------------------------------------------------------
-- Laço do reparo
--------------------------------------------------------------------------------

local function stepSession(session: Session)
	local player = session.player
	local spec = session.spec

	local alive, reason = canChannel(player)
	if not alive then
		stop(session, reason or "Reparo interrompido.", false)
		return
	end
	if not spec.part:IsDescendantOf(Workspace) then
		stop(session, "O ponto de reparo sumiu.", false)
		return
	end
	if not InteractionGuard.CanReach(player, spec.part, spec.range) then
		stop(session, "Você se afastou do reparo.", false)
		return
	end
	local ok, refuseReason = spec.canStart(player)
	if not ok then
		stop(session, refuseReason or "Esse reparo não é mais necessário.", false)
		return
	end
	if os.clock() - session.lastKeepalive > KEEPALIVE_TIMEOUT then
		stop(session, "Reparo interrompido.", false)
		return
	end

	local now = Workspace:GetServerTimeNow()

	-- Teste em andamento: expirou sem o jogador apertar?
	local test = session.test
	if test then
		if now - test.startsAt > Config.TestWindow(test) then
			resolveTest(session, test, "Miss")
		end
	elseif now >= session.nextTestAt then
		local newTest = buildTest(session)
		session.test = newTest
		Remotes.RepairMinigame:FireClient(player, "Test", session.token, newTest)
	end
end

--------------------------------------------------------------------------------
-- Abertura
--------------------------------------------------------------------------------

local function begin(player: Player, spec: Spec)
	if sessions[player] then
		return
	end
	if os.clock() < (blockedUntil[player] or 0) then
		return
	end

	-- Validar ANTES de olhar a config: com o minigame desligado o reparo
	-- resolve na hora, e resolver na hora não pode ser um caminho que pula
	-- as checagens de papel, vida, alcance e estado do objetivo.
	local alive, reason = canChannel(player)
	if not alive then
		if reason then
			Remotes.LobbyMessage:FireClient(player, reason)
		end
		return
	end
	if not InteractionGuard.CanReach(player, spec.part, spec.range) then
		return
	end
	local ok, refuseReason = spec.canStart(player)
	if not ok then
		if refuseReason then
			Remotes.LobbyMessage:FireClient(player, refuseReason)
		end
		return
	end

	local task = Config.Tasks[spec.configId]
	if not task or not task.Enabled then
		-- Minigame desligado pra esta tarefa: o objetivo resolve na hora,
		-- como fazia antes de existir minigame nenhum.
		spec.onComplete(player)
		RepairMinigameSystem.RepairCompleted:Fire(player, spec.taskId)
		return
	end

	nextToken += 1
	local session: Session = {
		player = player,
		spec = spec,
		token = nextToken,
		rng = Random.new(),
		tuning = Config.Tuning(player),
		streak = 0,
		required = math.max(1, (task :: any).Required or Config.Streak.Required),
		testsResolved = 0,
		scoreSum = 0,
		nextTestId = 0,
		nextTestAt = 0,
		test = nil,
		lastKeepalive = os.clock(),
	}
	scheduleNextTest(session, true)
	sessions[player] = session

	local character = player.Character
	if character then
		character:SetAttribute("Reparando", true)
	end

	Remotes.RepairMinigame:FireClient(
		player,
		"Start",
		session.token,
		spec.part,
		task.Label,
		session.streak,
		session.required
	)
end

--------------------------------------------------------------------------------
-- API pros objetivos
--------------------------------------------------------------------------------

--[[
	Start(player, spec)
	Abre o minigame pra este jogador nesta tarefa. Serve pra quem precisa
	decidir ANTES se o toque vira minigame ou ação imediata (a estação de
	rádio usa isso: ligar o gerador é reparo, desligar é só um botão).
	Com a tarefa desligada na config, o onComplete roda na hora.
]]
function RepairMinigameSystem.Start(player: Player, spec: Spec)
	begin(player, spec)
end

--[[
	Bind(prompt, spec)
	Converte um ProximityPrompt de "segurar pra reparar" em "apertar pra abrir
	o minigame". O objetivo dono do prompt continua com toda a lógica dele em
	canStart/onComplete.
]]
function RepairMinigameSystem.Bind(prompt: ProximityPrompt, spec: Spec)
	-- Quem segura agora é o minigame; o anel do prompt sairia do lugar.
	prompt.HoldDuration = 0
	prompt.Triggered:Connect(function(player)
		begin(player, spec)
	end)
end

--[[
	ResetTask(taskId)
	Derruba quem está fazendo o reparo desse ponto (o objetivo dono decidiu
	que o ponto voltou ao estado original). A sequência é da sessão, então
	não há progresso guardado pra zerar.
]]
function RepairMinigameSystem.ResetTask(taskId: string)
	for _, session in table.clone(sessions) do
		if session.spec.taskId == taskId then
			stop(session, "Reparo interrompido.", false)
		end
	end
end

--[[ ResetAll() -- derruba tudo (preparo/fim de rodada). ]]
function RepairMinigameSystem.ResetAll()
	for _, session in table.clone(sessions) do
		stop(session, "Reparo interrompido.", false)
	end
	table.clear(sessions)
	table.clear(blockedUntil)
end

--------------------------------------------------------------------------------
-- Init
--------------------------------------------------------------------------------

function RepairMinigameSystem.Init()
	if initialized then
		return
	end
	initialized = true

	Remotes.RepairMinigame.OnServerEvent:Connect(function(player: Player, action: unknown, token: unknown, a: unknown, b: unknown)
		local session = sessions[player]
		-- Token da sessão: mensagem atrasada de um reparo anterior não mexe
		-- no atual. O cliente nunca manda progresso, alvo, dano ou nota.
		if not session or token ~= session.token then
			return
		end
		if action == "Hold" then
			session.lastKeepalive = os.clock()
		elseif action == "Release" then
			stop(session, "Reparo interrompido.", false)
		elseif action == "Hit" then
			session.lastKeepalive = os.clock()
			if type(a) == "number" and type(b) == "number" then
				onHit(session, a, b)
			end
		end
	end)

	Players.PlayerRemoving:Connect(function(player)
		sessions[player] = nil
		blockedUntil[player] = nil
	end)

	-- Requires tardios: RoundManager e DamageSystem fecham ciclo com este
	-- módulo se forem carregados no topo (RoundManager -> RadioSiteSystem ->
	-- RepairMinigameSystem). Aqui dentro o corpo deste módulo já terminou.
	local RoundManager = require(script.Parent.RoundManager)
	local DamageSystem = require(script.Parent.DamageSystem)

	RoundManager.RoundPrepared.Event:Connect(RepairMinigameSystem.ResetAll)
	RoundManager.RoundEnded.Event:Connect(RepairMinigameSystem.ResetAll)

	-- Tomar dano derruba o reparo (requisito 9). Só dano de verdade dispara
	-- DamageApplied, então cura e guardas não cancelam nada.
	DamageSystem.DamageApplied.Event:Connect(function(_attacker: Player?, victim: Player?)
		if victim then
			stopFor(victim, "Você levou um golpe e soltou a ferramenta.")
		end
	end)

	Players.PlayerAdded:Connect(function(player)
		player.CharacterRemoving:Connect(function()
			stopFor(player, "Reparo interrompido.")
		end)
	end)
	for _, player in Players:GetPlayers() do
		player.CharacterRemoving:Connect(function()
			stopFor(player, "Reparo interrompido.")
		end)
	end

	RunService.Heartbeat:Connect(function()
		-- Cópia: um reparo concluído chama o onComplete do objetivo, que pode
		-- derrubar OUTRAS sessões no mesmo tique (ex: o fio consertado por um
		-- cancela quem ajudava). Remover uma chave que não é a atual no meio
		-- de um `for ... in` é indefinido em Lua; a guarda descarta quem já
		-- caiu neste frame.
		for _, session in table.clone(sessions) do
			if sessions[session.player] == session then
				stepSession(session)
			end
		end
	end)

	print("[RepairMinigameSystem] Reparo de precisão pronto (sequência de acertos, testes e ruído validados no servidor).")
end

return RepairMinigameSystem
