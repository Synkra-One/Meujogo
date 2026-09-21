--!strict
--[[
	MatchStatsService
	DONO DOS DADOS individuais de cada jogador durante uma partida. Ninguém
	mais guarda estatística de partida: os outros sistemas chamam a API daqui.

	TRÊS SERVIÇOS, TRÊS RESPONSABILIDADES
	  MatchStatsService   (aqui) -- guarda a sessão de cada jogador, mede o
	    que dá pra medir sozinho (tempo vivo, distância, perseguição,
	    ociosidade) e é o único lugar que escreve nas tabelas internas.
	  MatchRewardService  -- decide QUANTO XP cada ação vale (consultando
	    MatchRewardsConfig), aplica cooldown/teto/limite e chama ApplyReward
	    aqui. É quem os outros sistemas do jogo chamam.
	  MatchResultsService -- congela tudo no fim, calcula PerformanceScore e
	    destaques, e manda pra cada jogador SÓ o relatório dele.

	SESSÃO POR UserId, NÃO POR Player
	  A tabela é indexada pelo UserId (número), não pelo Instance do Player.
	  Isso é o que faz o relatório de quem SAIU no meio da partida continuar
	  existindo: o Instance vira nil no PlayerRemoving, o UserId não. Também
	  garante que dois jogadores nunca compartilhem dados -- não existe
	  estado "do jogador atual" em lugar nenhum deste arquivo.

	CICLO DE VIDA (zero alteração no RoundManager)
	  RoundManager já publica dois BindableEvents que servem exatamente pra
	  isso, então este módulo só escuta:
	    RoundPrepared(players) -- papéis já sorteados e corpos já criados:
	      abre uma sessão por jogador e liga a medição.
	    RoundEnded(winner, reason) -- congela e entrega pro MatchResultsService.
	  Nenhuma medição acontece fora dessa janela: movimento no Lobby, antes
	  do começo ou depois do fim, não conta pra nada.

	POR QUE NÃO EXISTE LOOP DE MEDIÇÃO NOVO
	  A distância percorrida NÃO é medida por frame nem por um segundo
	  Heartbeat só pra isso. O StaminaSystem já amostra posição e velocidade
	  reais de todo mundo a 20 Hz (ele precisa disso pro fôlego) e publica em
	  StaminaSystem.MovementSampled. Aqui a gente só consome essa amostra e
	  processa a cada Timing.TrackInterval (0.5s). O único Heartbeat próprio
	  é o de perseguição/ociosidade, que roda no mesmo intervalo e SÓ enquanto
	  há partida -- fora dela ele retorna na primeira linha.

	TELEPORTE NÃO VIRA DISTÂNCIA
	  Entre duas amostras, um deslocamento maior que
	  velocidadePlausível * intervalo * TeleportTolerance é descartado inteiro.
	  É o que impede o teleporte do Monstro, o ShadowRush e qualquer desync de
	  rede de virarem quilômetros no relatório.

	Uso (uma vez no boot, DEPOIS de RoundManager e StaminaSystem):
		require(script.MatchStatsService).Init()
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage.Modules.GameConfig)
local MatchRewardsConfig = require(ReplicatedStorage.Modules.MatchRewardsConfig)
local Types = require(ReplicatedStorage.Modules.MatchStatsTypes)

local Elimination = require(script.Parent.Elimination)
local RoundManager = require(script.Parent.RoundManager)
local StaminaSystem = require(script.Parent.StaminaSystem)

local MatchStatsService = {}

local Stat = Types.Stat
local Timing = MatchRewardsConfig.Timing

type Session = Types.Session

--------------------------------------------------------------------------------
-- Estado
--------------------------------------------------------------------------------

-- UserId -> sessão. Única fonte de verdade dos dados de partida.
local sessions: { [number]: Session } = {}

-- UserId -> Player, só enquanto ele está no servidor. Separado da sessão de
-- propósito: a sessão sobrevive à saída, esta referência não.
local livePlayers: { [number]: Player } = {}

-- Estado de medição, também por UserId. Fora da sessão porque é ferramenta
-- interna (nada disso vai pro relatório).
type Tracking = {
	lastPosition: Vector3?,
	lastSampleAt: number,
	lastIdleAnchor: Vector3?,
	lastIdleCheckAt: number,
	idleAccumulated: number,
	lastSurvivalTickAt: number,
}
local tracking: { [number]: Tracking } = {}

-- Perseguições abertas: "monsterUserId:survivorUserId" -> estado.
type Chase = {
	MonsterUserId: number,
	SurvivorUserId: number,
	StartedAt: number,
	LastCloseAt: number,
}
local chases: { [string]: Chase } = {}

local matchActive = false
local frozen = false
local matchStartedAt = 0
local initialized = false
local heartbeatAccumulator = 0

-- Preenchido por MatchRewardService.SetRewardHook. É assim que este módulo
-- concede XP (pulso de sobrevivência, fim de perseguição, inatividade) sem
-- dar require no MatchRewardService -- que dá require AQUI. Sem o gancho,
-- os dois módulos se exigiriam em círculo e nenhum dos dois carregaria.
local rewardHook: ((Player, string, { [string]: any }?) -> boolean)? = nil

local verbose = RunService:IsStudio() and MatchRewardsConfig.Debug.VerboseInStudio

local function log(format: string, ...: any)
	if verbose then
		print("[MatchStats] " .. string.format(format, ...))
	end
end

--------------------------------------------------------------------------------
-- Helpers
--------------------------------------------------------------------------------

local function isSurvivorRole(role: string): boolean
	return MatchRewardsConfig.SurvivorRoles[role] == true
end

local function isMonsterRole(role: string): boolean
	return MatchRewardsConfig.MonsterRoles[role] == true
end

local function livingRoot(player: Player): BasePart?
	local character = player.Character
	if not character or Elimination.IsEliminated(player) then
		return nil
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then
		return nil
	end
	local root = character:FindFirstChild("HumanoidRootPart")
	return if root and root:IsA("BasePart") then root else nil
end

local function grant(player: Player, actionId: string, context: { [string]: any }?)
	local hook = rewardHook
	if hook then
		hook(player, actionId, context)
	end
end

--------------------------------------------------------------------------------
-- API -- ciclo de vida da sessão
--------------------------------------------------------------------------------

--[[
	StartPlayerSession(player, role)
	Abre (ou reabre) a sessão do jogador. Idempotente: chamar de novo com o
	mesmo papel não zera nada -- é o que permite o RoleAssignment definir o
	papel depois da sessão já existir sem perder o que já foi medido.
]]
function MatchStatsService.StartPlayerSession(player: Player, role: string?): Types.Session
	local userId = player.UserId
	local resolvedRole = role or (player:GetAttribute("Role") :: string?) or GameConfig.Roles.Survivor

	local existing = sessions[userId]
	if existing then
		if role and existing.Role ~= role then
			existing.Role = role
			log("%s trocou de papel para %s", player.Name, role)
		end
		livePlayers[userId] = player
		return existing
	end

	local session: Session = {
		UserId = userId,
		Name = player.Name,
		DisplayName = player.DisplayName,
		Role = resolvedRole,
		MatchXP = 0,
		PerformanceScore = 0,
		XPBreakdown = {},
		ActionHistory = {},
		Stats = Types.NewStats(),
		Highlights = {},
		JoinedAt = os.clock(),
		AliveTime = 0,
		IsAlive = true,
		Escaped = false,
		EscapeMethod = nil,
		Eliminated = false,
		Left = false,
		ResultFinalized = false,
	}
	for _, category in Types.CategoryOrder do
		session.XPBreakdown[category] = 0
	end

	sessions[userId] = session
	livePlayers[userId] = player
	tracking[userId] = {
		lastPosition = nil,
		lastSampleAt = 0,
		lastIdleAnchor = nil,
		lastIdleCheckAt = os.clock(),
		idleAccumulated = 0,
		lastSurvivalTickAt = os.clock(),
	}

	log("sessão aberta: %s (%s)", player.Name, session.Role)
	return session
end

--[[
	GetSession(player | userId)
	Sessão CRUA (referência viva). Uso interno dos três serviços de partida.
	Nenhum outro sistema deve escrever nela direto -- use AddStat/SetStat.
]]
function MatchStatsService.GetSession(target: Player | number): Session?
	local userId = if type(target) == "number" then target else target.UserId
	return sessions[userId]
end

--[[
	GetPlayerMatchData(player)
	CÓPIA profunda da sessão, segura pra ler/logar sem risco de alguém
	alterar o dado de verdade por engano.
]]
function MatchStatsService.GetPlayerMatchData(player: Player | number): Session?
	local session = MatchStatsService.GetSession(player)
	if not session then
		return nil
	end

	local copy: any = table.clone(session :: any)
	copy.XPBreakdown = table.clone(session.XPBreakdown)
	copy.Stats = table.clone(session.Stats)
	copy.Highlights = table.clone(session.Highlights)
	copy.ActionHistory = table.create(#session.ActionHistory)
	for index, record in session.ActionHistory do
		copy.ActionHistory[index] = table.clone(record)
	end
	return copy
end

--[[ GetAllSessions() -- referências vivas, indexadas por UserId. ]]
function MatchStatsService.GetAllSessions(): { [number]: Session }
	return sessions
end

--[[ GetPlayer(userId) -- Player ainda conectado dono da sessão, se houver. ]]
function MatchStatsService.GetPlayer(userId: number): Player?
	local player = livePlayers[userId]
	return if player and player.Parent == Players then player else nil
end

--[[
	IsAccepting(player?)
	true quando há partida rolando, os resultados ainda não foram congelados
	e (se o jogador foi passado) ele tem sessão aberta. É a guarda que impede
	qualquer registro antes do começo ou depois do fim da partida.
]]
function MatchStatsService.IsAccepting(player: (Player | number)?): boolean
	if not matchActive or frozen then
		return false
	end
	if player == nil then
		return true
	end
	return MatchStatsService.GetSession(player) ~= nil
end

function MatchStatsService.IsMatchActive(): boolean
	return matchActive
end

function MatchStatsService.IsFrozen(): boolean
	return frozen
end

--[[ MatchTime() -- segundos desde o início da partida (0 fora de partida). ]]
function MatchStatsService.MatchTime(): number
	return if matchActive then os.clock() - matchStartedAt else 0
end

--------------------------------------------------------------------------------
-- API -- estatísticas
--------------------------------------------------------------------------------

--[[
	AddStat(player, statName, amount)
	Soma em uma estatística. statName TEM que ser um nome canônico de
	MatchStatsTypes.Stat -- um typo estoura aqui em vez de criar uma
	estatística fantasma que ninguém vê.
]]
function MatchStatsService.AddStat(player: Player | number, statName: string, amount: number?): boolean
	local value = amount or 1
	if type(value) ~= "number" or value ~= value or math.abs(value) == math.huge then
		return false
	end
	if not Types.IsStat(statName) then
		warn(string.format("[MatchStats] estatística desconhecida '%s' -- ignorada.", tostring(statName)))
		return false
	end
	local session = MatchStatsService.GetSession(player)
	if not session or session.ResultFinalized or frozen then
		return false
	end

	session.Stats[statName] += value
	return true
end

--[[ SetStat(player, statName, value) -- substitui (ex: método de fuga, picos). ]]
function MatchStatsService.SetStat(player: Player | number, statName: string, value: number): boolean
	if type(value) ~= "number" or value ~= value or math.abs(value) == math.huge then
		return false
	end
	if not Types.IsStat(statName) then
		warn(string.format("[MatchStats] estatística desconhecida '%s' -- ignorada.", tostring(statName)))
		return false
	end
	local session = MatchStatsService.GetSession(player)
	if not session or session.ResultFinalized or frozen then
		return false
	end

	session.Stats[statName] = value
	return true
end

--[[ GetStat(player, statName) -- 0 quando não há sessão. ]]
function MatchStatsService.GetStat(player: Player | number, statName: string): number
	local session = MatchStatsService.GetSession(player)
	if not session or not Types.IsStat(statName) then
		return 0
	end
	return session.Stats[statName] or 0
end

--------------------------------------------------------------------------------
-- API -- aplicação de XP (chamada SÓ pelo MatchRewardService)
--------------------------------------------------------------------------------

--[[
	ApplyReward(player, record)
	Escreve o XP já VALIDADO na sessão: soma no total, na categoria e
	registra no histórico. Não valida nada -- quem valida (cooldown, teto,
	papel, alvo) é o MatchRewardService, que é o único que deve chamar isto.

	Devolve o registro guardado, ou nil se a sessão não aceita mais.
]]
function MatchStatsService.ApplyReward(player: Player | number, record: Types.ActionRecord): Types.ActionRecord?
	local session = MatchStatsService.GetSession(player)
	if not session or session.ResultFinalized or frozen then
		return nil
	end

	session.MatchXP += record.XP
	local category = record.Category
	session.XPBreakdown[category] = (session.XPBreakdown[category] or 0) + record.XP

	-- Teto do histórico: XP e estatística continuam somando, só a LINHA nova
	-- para de ser criada. Uma partida travada não pode inflar essa tabela
	-- indefinidamente (ela é copiada inteira na finalização).
	if #session.ActionHistory < MatchRewardsConfig.AntiFarm.MaxActionHistory then
		table.insert(session.ActionHistory, record)
	end

	return record
end

--------------------------------------------------------------------------------
-- API -- marcadores de estado
--------------------------------------------------------------------------------

--[[
	MarkEliminated(player)
	Congela o tempo vivo e marca a sessão. NÃO apaga nada: o relatório do
	morto tem que continuar existindo até o fim da partida.
]]
function MatchStatsService.MarkEliminated(player: Player | number): boolean
	local session = MatchStatsService.GetSession(player)
	if not session or session.Eliminated then
		return false
	end
	session.Eliminated = true
	session.IsAlive = false
	session.AliveTime = session.Stats[Stat.AliveTime]
	log("%s eliminado aos %.0fs (tempo vivo).", session.Name, session.AliveTime)
	return true
end

--[[
	MarkEscaped(player, method)
	Marca a fuga sem encerrar nem apagar a sessão. O jogador que escapou
	continua "vivo" pro relatório -- ele não morreu, ele saiu por cima.
]]
function MatchStatsService.MarkEscaped(player: Player | number, method: string?): boolean
	local session = MatchStatsService.GetSession(player)
	if not session or session.Escaped then
		return false
	end
	session.Escaped = true
	session.EscapeMethod = method
	session.AliveTime = session.Stats[Stat.AliveTime]
	log("%s escapou (%s).", session.Name, tostring(method))
	return true
end

--[[ MarkLeft(player) -- saiu do servidor no meio da partida. ]]
function MatchStatsService.MarkLeft(player: Player | number): boolean
	local session = MatchStatsService.GetSession(player)
	if not session then
		return false
	end
	session.Left = true
	session.IsAlive = false
	return true
end

--------------------------------------------------------------------------------
-- Medição: distância percorrida
--------------------------------------------------------------------------------

--[[
	onMovementSampled
	Consome a amostra que o StaminaSystem JÁ calculou (posição real do
	HumanoidRootPart + velocidade horizontal + WalkSpeed base do personagem).
	Não existe Heartbeat nem raycast próprio pra isso.

	Andar x correr usa exatamente o mesmo critério do fôlego
	(speed > walkBase * SprintSpeedRatio), então o relatório nunca discorda
	do que o jogo considerou sprint.
]]
local function onMovementSampled(
	player: Player,
	_character: Model,
	_humanoid: Humanoid,
	root: BasePart,
	speed: number,
	walkBase: number
)
	if not matchActive or frozen then
		return
	end

	local state = tracking[player.UserId]
	local session = sessions[player.UserId]
	if not state or not session or session.ResultFinalized then
		return
	end

	local now = os.clock()
	local position = root.Position
	local previous = state.lastPosition

	-- Primeira amostra da sessão: só ancora, não mede. (Depois de um respawn
	-- em outro canto do mapa, quem descarta o salto é o filtro de teleporte
	-- lá embaixo -- a âncora antiga não gera distância falsa.)
	if not previous then
		state.lastPosition = position
		state.lastSampleAt = now
		state.lastIdleAnchor = position
		return
	end

	local elapsed = now - state.lastSampleAt
	if elapsed < Timing.TrackInterval then
		return
	end
	state.lastSampleAt = now
	state.lastPosition = position

	-- Horizontal: subir/descer uma encosta não deve inflar a distância.
	local delta = position - previous
	local distance = Vector3.new(delta.X, 0, delta.Z).Magnitude

	if distance < Timing.MinDistancePerSample then
		return -- tremida de física parado em pé
	end

	-- FILTRO DE TELEPORTE. Sprint real fica bem abaixo deste limite; o
	-- teleporte do Monstro e o ShadowRush ficam muito acima.
	local plausible = math.max(walkBase * 2, Timing.MinPlausibleSpeed)
	if distance > plausible * elapsed * Timing.TeleportTolerance then
		log("%s: %.0f studs descartados (teleporte/desync).", player.Name, distance)
		return
	end

	if speed > walkBase * GameConfig.Characters.SprintSpeedRatio then
		session.Stats[Stat.DistanceRan] += distance
		session.Stats[Stat.TimeRunning] += elapsed
	else
		session.Stats[Stat.DistanceWalked] += distance
	end
end

--------------------------------------------------------------------------------
-- Medição: perseguição, furtividade, tempo vivo e ociosidade
--------------------------------------------------------------------------------

local function chaseKey(monsterUserId: number, survivorUserId: number): string
	return string.format("%d:%d", monsterUserId, survivorUserId)
end

local function endChase(key: string, chase: Chase, caught: boolean)
	chases[key] = nil

	local duration = os.clock() - chase.StartedAt
	if duration < Timing.ChaseMinDuration then
		return -- o Monstro só passou perto; não foi perseguição
	end

	local monster = MatchStatsService.GetPlayer(chase.MonsterUserId)
	local survivor = MatchStatsService.GetPlayer(chase.SurvivorUserId)

	if monster then
		MatchStatsService.AddStat(monster, Stat.ChaseTime, duration)
		if caught then
			MatchStatsService.AddStat(monster, Stat.ChasesCompleted, 1)
			grant(monster, "ChaseCompleted", { TargetUserId = chase.SurvivorUserId })
		end
	end

	if survivor and not caught then
		MatchStatsService.AddStat(survivor, Stat.ChasesEscaped, 1)
		grant(survivor, "ChaseEscaped", { TargetUserId = chase.MonsterUserId })
	end

	log("perseguição encerrada (%s) em %.1fs -- pego: %s", key, duration, tostring(caught))
end

--[[
	step(dt)
	Passo único de medição contínua, a cada Timing.TrackInterval. Faz, numa
	varredura só de Players:GetPlayers() (no máximo ~10 jogadores):
	  1) tempo vivo + pulso de XP de sobrevivência;
	  2) ociosidade (e a penalidade, quando passa do limite);
	  3) perseguição Monstro <-> Sobrevivente e tempo furtivo.

	Roda em um Heartbeat só, com acumulador -- e sai na primeira linha quando
	não há partida, então fora de rodada o custo é uma comparação booleana.
]]
local function step(dt: number)
	local now = os.clock()

	-- Posições vivas desta passada, calculadas UMA vez e reaproveitadas pelo
	-- laço de perseguição (senão seria O(n²) de FindFirstChild).
	local monsterPositions: { { UserId: number, Position: Vector3 } } = {}
	local survivorPositions: { { UserId: number, Position: Vector3 } } = {}

	for userId, session in sessions do
		local player = MatchStatsService.GetPlayer(userId)
		if not player or session.ResultFinalized then
			continue
		end

		local root = livingRoot(player)
		local state = tracking[userId]

		if not root then
			-- Morto/sem corpo: nada acumula. O tempo vivo já foi congelado
			-- em MarkEliminated (ou congela aqui na primeira passada).
			if session.IsAlive and Elimination.IsEliminated(player) then
				MatchStatsService.MarkEliminated(player)
			end
			continue
		end

		------------------------------------------------------------------------
		-- 1) Tempo vivo + pulso de sobrevivência
		------------------------------------------------------------------------
		session.Stats[Stat.AliveTime] += dt
		session.AliveTime = session.Stats[Stat.AliveTime]

		if state and isSurvivorRole(session.Role)
			and now - state.lastSurvivalTickAt >= Timing.SurvivalTickInterval then
			state.lastSurvivalTickAt = now
			grant(player, "SurvivalTick", nil)
		end

		------------------------------------------------------------------------
		-- 2) Ociosidade
		------------------------------------------------------------------------
		if state then
			if now - state.lastIdleCheckAt >= Timing.IdleCheckInterval then
				local anchor = state.lastIdleAnchor
				local window = now - state.lastIdleCheckAt
				if anchor and (root.Position - anchor).Magnitude <= Timing.IdleDistance then
					state.idleAccumulated += window
					session.Stats[Stat.IdleTime] += window
					if state.idleAccumulated >= Timing.IdlePenaltyAfter then
						-- O cooldown da ação (config) é quem impede isto de
						-- virar uma penalidade por segundo.
						grant(player, "InactivityPenalty", nil)
					end
				else
					state.idleAccumulated = 0
				end
				state.lastIdleAnchor = root.Position
				state.lastIdleCheckAt = now
			end
		end

		------------------------------------------------------------------------
		-- 3) Índice de posições pro laço de perseguição
		------------------------------------------------------------------------
		if isMonsterRole(session.Role) then
			table.insert(monsterPositions, { UserId = userId, Position = root.Position })
		elseif isSurvivorRole(session.Role) then
			table.insert(survivorPositions, { UserId = userId, Position = root.Position })
		end
	end

	----------------------------------------------------------------------------
	-- Perseguição e furtividade
	----------------------------------------------------------------------------
	local closeThisPass: { [string]: boolean } = {}

	for _, monster in monsterPositions do
		for _, survivor in survivorPositions do
			local distance = (monster.Position - survivor.Position).Magnitude
			local key = chaseKey(monster.UserId, survivor.UserId)
			local chase = chases[key]

			if distance <= Timing.ChaseStartRadius then
				closeThisPass[key] = true
				if chase then
					chase.LastCloseAt = now
				else
					chases[key] = {
						MonsterUserId = monster.UserId,
						SurvivorUserId = survivor.UserId,
						StartedAt = now,
						LastCloseAt = now,
					}
					local monsterPlayer = MatchStatsService.GetPlayer(monster.UserId)
					local survivorPlayer = MatchStatsService.GetPlayer(survivor.UserId)
					if monsterPlayer then
						MatchStatsService.AddStat(monsterPlayer, Stat.ChasesStarted, 1)
						grant(monsterPlayer, "SurvivorFound", { TargetUserId = survivor.UserId })
					end
					if survivorPlayer then
						MatchStatsService.AddStat(survivorPlayer, Stat.ChasesStarted, 1)
						MatchStatsService.AddStat(survivorPlayer, Stat.TimesDetected, 1)
					end
					-- Reapanha a perseguição recém-criada pra ela já contar
					-- tempo NESTA passada (senão o primeiro meio segundo de
					-- toda caçada não entraria no TimeChased).
					chase = chases[key]
					log("perseguição iniciada (%s)", key)
				end
			elseif not chase and distance <= Timing.StealthRadius then
				-- Perto, mas ainda não virou caçada: isso é furtividade.
				local survivorPlayer = MatchStatsService.GetPlayer(survivor.UserId)
				if survivorPlayer then
					MatchStatsService.AddStat(survivorPlayer, Stat.TimeNearMonsterUndetected, dt)
				end
			end

			if chase and distance <= Timing.ChaseEndRadius then
				-- Ainda dentro do raio de fuga: a perseguição segue correndo.
				chase.LastCloseAt = now
				closeThisPass[key] = true
				local survivorPlayer = MatchStatsService.GetPlayer(survivor.UserId)
				if survivorPlayer then
					MatchStatsService.AddStat(survivorPlayer, Stat.TimeChased, dt)
				end
			end
		end
	end

	-- Fecha o que não está mais perto (ou cujo alvo morreu/saiu).
	for key, chase in chases do
		local survivorSession = sessions[chase.SurvivorUserId]
		local caught = survivorSession ~= nil and (survivorSession.Eliminated or survivorSession.Left)
		if caught then
			endChase(key, chase, true)
		elseif not closeThisPass[key] and now - chase.LastCloseAt >= Timing.ChaseEndGrace then
			endChase(key, chase, false)
		end
	end
end

--------------------------------------------------------------------------------
-- Ciclo de vida da partida
--------------------------------------------------------------------------------

--[[
	StartMatch(players)
	Zera TUDO da partida anterior e abre uma sessão por participante. O
	`table.clear` aqui é o que garante que nenhum dado passe de uma partida
	pra próxima -- inclusive de quem já tinha saído.
]]
function MatchStatsService.StartMatch(players: { Player })
	table.clear(sessions)
	table.clear(livePlayers)
	table.clear(tracking)
	table.clear(chases)

	frozen = false
	matchActive = true
	matchStartedAt = os.clock()

	for _, player in players do
		if player.Parent == Players then
			MatchStatsService.StartPlayerSession(player, player:GetAttribute("Role") :: string?)
		end
	end

	print(string.format("[MatchStats] Partida iniciada com %d sessões.", #players))
end

--[[
	FreezeMatch()
	Congela os resultados. Depois disto NADA mais entra: AddStat, SetStat e
	ApplyReward passam a recusar. Idempotente.
]]
function MatchStatsService.FreezeMatch()
	if frozen then
		return
	end
	frozen = true

	-- Fecha as perseguições abertas antes do congelamento, senão o tempo
	-- perseguido da última caçada da partida sumiria do relatório.
	for key, chase in chases do
		local survivorSession = sessions[chase.SurvivorUserId]
		endChase(key, chase, survivorSession ~= nil and survivorSession.Eliminated)
	end
	table.clear(chases)

	for _, session in sessions do
		session.AliveTime = session.Stats[Stat.AliveTime]
	end
end

--[[
	EndMatch()
	Encerra a janela de medição. NÃO apaga as sessões -- quem faz isso é
	ClearSessions(), chamado pelo MatchResultsService depois que os
	relatórios já foram enviados.
]]
function MatchStatsService.EndMatch()
	MatchStatsService.FreezeMatch()
	matchActive = false
end

--[[ ClearSessions() -- descarta tudo. Só depois dos relatórios enviados. ]]
function MatchStatsService.ClearSessions()
	table.clear(sessions)
	table.clear(livePlayers)
	table.clear(tracking)
	table.clear(chases)
	frozen = false
	matchActive = false
end

--[[
	SetRewardHook(fn)
	MatchRewardService se registra aqui no Init dele. Ver a nota em
	`rewardHook`, lá em cima: é o que evita o require circular.
]]
function MatchStatsService.SetRewardHook(fn: (Player, string, { [string]: any }?) -> boolean)
	rewardHook = fn
end

--------------------------------------------------------------------------------
-- Init
--------------------------------------------------------------------------------

function MatchStatsService.Init()
	if initialized then
		return
	end
	initialized = true

	RoundManager.RoundPrepared.Event:Connect(function(players: { Player })
		MatchStatsService.StartMatch(players)
	end)

	RoundManager.RoundEnded.Event:Connect(function()
		-- REDE DE SEGURANÇA, com task.defer de propósito.
		--
		-- Quem fecha a partida DE VERDADE é MatchResultsService.FinalizeMatch,
		-- que escuta o mesmo RoundEnded: ele precisa aplicar os bônus de fim
		-- (último sobrevivente, todos eliminados) ANTES do congelamento --
		-- depois de congelado, ApplyReward recusa tudo.
		--
		-- Se congelássemos aqui, direto, este listener rodaria primeiro (foi
		-- conectado primeiro, no boot) e os bônus de fim de partida seriam
		-- silenciosamente recusados em TODA partida. O defer garante que isto
		-- só rode depois dos listeners síncronos do RoundEnded.
		--
		-- Então este caminho normalmente é um no-op (EndMatch é idempotente e
		-- o MatchResultsService já terá chamado). Ele existe pro caso de o
		-- MatchResultsService ter falhado ao ligar: sem ele, a medição
		-- continuaria rodando pela intermissão inteira e entraria na partida
		-- seguinte.
		task.defer(function()
			MatchStatsService.EndMatch()
		end)
	end)

	StaminaSystem.MovementSampled.Event:Connect(onMovementSampled)

	Players.PlayerRemoving:Connect(function(player)
		local userId = player.UserId
		livePlayers[userId] = nil
		if sessions[userId] then
			MatchStatsService.MarkLeft(player)
		end
	end)

	-- Um Heartbeat só, com acumulador (mesmo padrão do StaminaSystem). Sai na
	-- primeira linha fora de partida: nada roda no Lobby.
	RunService.Heartbeat:Connect(function(dt)
		if not matchActive or frozen then
			heartbeatAccumulator = 0
			return
		end
		heartbeatAccumulator += dt
		if heartbeatAccumulator < Timing.TrackInterval then
			return
		end
		local elapsed = heartbeatAccumulator
		heartbeatAccumulator = 0
		step(elapsed)
	end)
end

return MatchStatsService
