--!strict
--[[
	MatchResultsService
	Fecha a partida: congela os dados, calcula PerformanceScore e destaques,
	e manda pra CADA jogador só o relatório dele.

	FINALIZAÇÃO ACONTECE UMA VEZ SÓ
	  `finalized` é uma trava de módulo e `session.ResultFinalized` é uma
	  trava por jogador. Chamar FinalizeMatch() duas vezes (ou o RoundEnded
	  disparar de novo por qualquer motivo) não recalcula bônus, não duplica
	  XP e não reenvia relatório. Isso é testado em tests/match_stats.luau.

	ORDEM DA FINALIZAÇÃO -- importa
	  1. Bônus de fim (último vivo, todos eliminados). Precisa acontecer ANTES
	     do congelamento, senão o ApplyReward recusaria.
	  2. Congela (MatchStatsService.FreezeMatch): dali em diante nada mais
	     entra em nenhuma sessão.
	  3. PerformanceScore de todo mundo -- os destaques comparam esse número,
	     então ele tem que existir pra todos antes do passo 4.
	  4. Destaques (inclui o Melhor da Partida).
	  5. Envio individual.

	O QUE CADA JOGADOR RECEBE
	  O SEU XP, o SEU detalhamento, o SEU histórico e as SUAS estatísticas --
	  mais a lista de destaques, que é pública por natureza (é o placar da
	  partida). Nenhuma tabela interna sai crua: o payload é montado campo a
	  campo em buildPayload(), e estatística de outro jogador nunca entra nele.

	MELHOR DA PARTIDA NÃO É "QUEM FEZ MAIS XP"
	  De propósito. XP cresce com tempo de jogo e vai virar progressão de
	  nível; quem sobreviveu 10 minutos parado acumularia pulso de
	  sobrevivência sem contribuir com nada. O MVP sai da PerformanceScore,
	  que pesa contribuição (objetivos, ajuda, combate, caçada) e não tempo.

	PERSISTÊNCIA: cada jogador tem o MatchXP creditado em DataStoreManager
	(gravação por delta, nunca perde progresso -- ver o cabeçalho de
	DataStoreManager.lua) e recebe de volta o nível ANTES/DEPOIS da conta
	em payload.Account, pra tela de resultados mostrar progresso/level-up.
	Controlado por MatchRewardsConfig.Persistence.CommitMatchXP.

	Uso (uma vez no boot, DEPOIS de MatchStatsService, MatchRewardService e
	DataStoreManager -- os três já estão nessa ordem em init.server.luau):
		require(script.MatchResultsService).Init()
]]

local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local MatchRewardsConfig = require(ReplicatedStorage.Modules.MatchRewardsConfig)
local Remotes = require(ReplicatedStorage.Modules.Remotes)
local Types = require(ReplicatedStorage.Modules.MatchStatsTypes)

local MatchRewardService = require(script.Parent.MatchRewardService)
local MatchStatsService = require(script.Parent.MatchStatsService)
local RoundManager = require(script.Parent.RoundManager)
local DataStoreManager = require(script.Parent.DataStoreManager)
local LevelSystem = require(ReplicatedStorage.Modules.LevelSystem)

local MatchResultsService = {}

local Performance = MatchRewardsConfig.Performance

local finalized = false
local initialized = false
local lastHighlights: { Types.Highlight } = {}
local lastMVPUserId: number? = nil

local verbose = RunService:IsStudio() and MatchRewardsConfig.Debug.VerboseInStudio

--------------------------------------------------------------------------------
-- Formatação (feita no SERVIDOR, pro cliente só desenhar)
--------------------------------------------------------------------------------

local function formatSeconds(value: number): string
	local total = math.max(0, math.floor(value + 0.5))
	if total < 60 then
		return string.format("%ds", total)
	end
	return string.format("%dm %02ds", total // 60, total % 60)
end

local function formatStat(statName: string, value: number): string
	local format = Types.StatFormat[statName]
	if format == "seconds" then
		return formatSeconds(value)
	elseif format == "studs" then
		-- Studs viram "metros" arredondados: número redondo é mais legível
		-- na tela do que "1837.42 studs".
		return string.format("%d m", math.floor(value + 0.5))
	elseif format == "decimal" then
		return string.format("%.1f", value)
	end
	return tostring(math.floor(value + 0.5))
end

--------------------------------------------------------------------------------
-- PerformanceScore
--------------------------------------------------------------------------------

--[[
	computePerformance(session)
	Soma (estatística * peso) da tabela do papel + bônus de resultado.
	Pesos em MatchRewardsConfig.Performance -- nenhum número aqui.
]]
local function computePerformance(session: Types.Session): number
	local isMonster = MatchRewardsConfig.MonsterRoles[session.Role] == true
	local profile = if isMonster then Performance.Monster else Performance.Survivor

	local score = 0
	for statName, weight in profile.Weights do
		score += (session.Stats[statName] or 0) * weight
	end

	if isMonster then
		local monsterProfile = Performance.Monster
		score -= (session.Stats[Types.Stat.IdleTime] or 0) * monsterProfile.IdlePenaltyPerSecond
		-- O bônus de "eliminou todos" já entrou como XP; aqui ele entra de novo
		-- na pontuação de DESEMPENHO, que é outra escala e outro propósito.
		if session.Stats[Types.Stat.SurvivorsEliminated] > 0 then
			local allEliminated = true
			for _, other in MatchStatsService.GetAllSessions() do
				if MatchRewardsConfig.SurvivorRoles[other.Role] and not other.Eliminated then
					allEliminated = false
					break
				end
			end
			if allEliminated then
				score += monsterProfile.AllEliminatedBonus
			end
		end
	else
		local survivorProfile = Performance.Survivor
		if session.Escaped then
			score += survivorProfile.EscapedBonus
		elseif not session.Eliminated and not session.Left then
			score += survivorProfile.SurvivedToEndBonus
		end
	end

	return math.max(0, math.floor(score + 0.5))
end

--------------------------------------------------------------------------------
-- Destaques
--------------------------------------------------------------------------------

--[[
	resolveHighlights()
	Um vencedor por regra. Regra sem ninguém acima do Minimum simplesmente
	NÃO gera destaque -- prêmio vazio ("Médico da Equipe" pra quem curou 1 HP
	numa partida sem cura nenhuma) faz o placar parecer quebrado.

	DESEMPATE, na ordem: maior valor -> quem entrou na partida primeiro
	(JoinedAt) -> menor UserId. A última é arbitrária mas DETERMINÍSTICA: sem
	ela o vencedor dependeria da ordem de `pairs`, que muda entre execuções, e
	dois jogadores empatados receberiam o destaque alternadamente sem motivo.
]]
local function resolveHighlights(): ({ Types.Highlight }, number?)
	local sessions = MatchStatsService.GetAllSessions()
	local highlights: { Types.Highlight } = {}
	local mvpUserId: number? = nil

	for _, rule in MatchRewardsConfig.Highlights do
		local bestSession: Types.Session? = nil
		local bestValue = -math.huge

		for _, session in sessions do
			if rule.Roles and not rule.Roles[session.Role] then
				continue
			end

			local value: number
			if rule.UsePerformance then
				value = session.PerformanceScore
			elseif rule.Stat then
				value = session.Stats[rule.Stat] or 0
			else
				continue
			end

			if value < rule.Minimum then
				continue
			end

			local best = bestSession
			local wins = false
			if not best then
				wins = true
			elseif value > bestValue then
				wins = true
			elseif value == bestValue then
				if session.JoinedAt < best.JoinedAt then
					wins = true
				elseif session.JoinedAt == best.JoinedAt and session.UserId < best.UserId then
					wins = true
				end
			end

			if wins then
				bestSession = session
				bestValue = value
			end
		end

		if bestSession then
			local winner = bestSession :: Types.Session
			table.insert(highlights, {
				Id = rule.Id,
				Name = rule.Name,
				Description = rule.Description,
				UserId = winner.UserId,
				PlayerName = winner.DisplayName,
				-- Valor já arredondado: a tela não precisa saber formatar.
				Value = math.floor(bestValue * 10 + 0.5) / 10,
			})
			table.insert(winner.Highlights, rule.Id)
			if rule.Id == "MVP" then
				mvpUserId = winner.UserId
			end
		end
	end

	return highlights, mvpUserId
end

--------------------------------------------------------------------------------
-- Progressão persistente da conta
--------------------------------------------------------------------------------

--[[
	creditAccountXP(player, matchXP)
	Credita o XP da partida em DataStoreManager (gravação por delta -- ver o
	cabeçalho de DataStoreManager.lua) e devolve o antes/depois pra tela de
	resultados anunciar progresso e level-up. nil quando a persistência está
	desligada, o jogador não ganhou XP nesta partida, ou DataStoreManager
	falha (nunca derruba o fim de partida por causa disso).
]]
local function creditAccountXP(player: Player, matchXP: number): Types.AccountProgress?
	if not MatchRewardsConfig.Persistence.CommitMatchXP or matchXP <= 0 then
		return nil
	end

	local ok, result = pcall(function(): Types.AccountProgress
		local committedXP = math.floor(matchXP * MatchRewardsConfig.Persistence.CommitMultiplier + 0.5)
		local previousXP = DataStoreManager.GetXP(player)
		local previousLevel = LevelSystem.GetLevel(previousXP)

		DataStoreManager.AddXP(player, committedXP)

		local totalXP = previousXP + committedXP
		local level, xpIntoLevel, xpForNextLevel, atMaxLevel = LevelSystem.GetProgress(totalXP)

		return {
			CommittedXP = committedXP,
			TotalXP = totalXP,
			Level = level,
			PreviousLevel = previousLevel,
			LeveledUp = level > previousLevel,
			XPIntoLevel = xpIntoLevel,
			XPForNextLevel = xpForNextLevel,
			AtMaxLevel = atMaxLevel,
		}
	end)

	if not ok then
		warn(string.format("[MatchResults] Falha ao creditar XP persistente de %s: %s", player.Name, tostring(result)))
		return nil
	end

	return result :: Types.AccountProgress
end

--------------------------------------------------------------------------------
-- Payload individual
--------------------------------------------------------------------------------

--[[
	groupActions(history)
	Agrupa o histórico por ActionId, somando XP e contagem. Sem isso, uma
	partida normal produziria 40 linhas de "Acertou o Monstro" na tela.
	A ordem de saída é a da PRIMEIRA ocorrência de cada ação -- estável e
	cronológica, em vez da ordem aleatória de `pairs`.
]]
local function groupActions(history: { Types.ActionRecord }): { Types.ActionRecord }
	local grouped: { Types.ActionRecord } = {}
	local indexById: { [string]: number } = {}

	for _, record in history do
		local existingIndex = indexById[record.ActionId]
		if existingIndex then
			local existing = grouped[existingIndex]
			existing.XP += record.XP
			existing.Count += record.Count
		else
			local copy = table.clone(record)
			-- O Detail de uma linha agrupada seria o da primeira ocorrência e
			-- enganaria ("Acertou o Monstro ×4 -- Faca" quando 3 foram de
			-- pedra). Só sobrevive quando a ação aconteceu uma vez só.
			table.insert(grouped, copy)
			indexById[record.ActionId] = #grouped
		end
	end

	for _, record in grouped do
		if record.Count > 1 then
			record.Detail = nil
		end
	end

	-- Maior XP primeiro: o que mais rendeu aparece no topo da lista.
	table.sort(grouped, function(a, b)
		if a.XP ~= b.XP then
			return a.XP > b.XP
		end
		return a.ActionId < b.ActionId -- desempate estável
	end)

	return grouped
end

local function buildStatRows(session: Types.Session): { { Key: string, Label: string, Value: string } }
	local rows = {}
	local shown = Types.StatsShownFor[session.Role] or Types.StatsShownFor.Sobrevivente
	for _, statName in shown do
		local label = Types.StatLabel[statName]
		if not label then
			continue
		end
		table.insert(rows, {
			Key = statName,
			Label = label,
			Value = formatStat(statName, session.Stats[statName] or 0),
		})
	end
	return rows
end

local function buildPayload(session: Types.Session, winner: string, reason: string, account: Types.AccountProgress?): Types.ResultsPayload
	local breakdown: Types.XPBreakdown = {}
	for _, category in Types.CategoryOrder do
		breakdown[category] = math.floor((session.XPBreakdown[category] or 0) + 0.5)
	end

	local actions = groupActions(session.ActionHistory)
	if #actions > MatchRewardsConfig.Results.MaxActionRows then
		-- Corta a cauda, mas o XP dela NÃO some do total: MatchXP continua
		-- sendo a soma de tudo. A tela mostra o resto como uma linha só.
		local trimmed = {}
		local restXP, restCount = 0, 0
		for index, record in actions do
			if index <= MatchRewardsConfig.Results.MaxActionRows - 1 then
				table.insert(trimmed, record)
			else
				restXP += record.XP
				restCount += record.Count
			end
		end
		table.insert(trimmed, {
			ActionId = "__Others",
			Category = Types.Category.Bonuses,
			Label = string.format("Outras %d ações", restCount),
			XP = restXP,
			MatchTime = 0,
			Count = restCount,
		})
		actions = trimmed
	end

	return {
		Winner = winner,
		Reason = reason,
		Role = session.Role,
		MatchXP = math.floor(session.MatchXP + 0.5),
		PerformanceScore = session.PerformanceScore,
		XPBreakdown = breakdown,
		Actions = actions,
		Stats = buildStatRows(session),
		Highlights = lastHighlights,
		MVPUserId = lastMVPUserId,
		IsMVP = lastMVPUserId == session.UserId,
		Account = account,
	}
end

--------------------------------------------------------------------------------
-- API
--------------------------------------------------------------------------------

--[[
	FinalizePlayerResult(player)
	Congela o resultado de UM jogador e devolve o payload dele. Idempotente
	por jogador (ResultFinalized). Usada pelo FinalizeMatch e disponível
	avulsa pra depuração.
]]
function MatchResultsService.FinalizePlayerResult(
	target: Player | number,
	winner: string,
	reason: string
): Types.ResultsPayload?
	local session = MatchStatsService.GetSession(target)
	if not session then
		return nil
	end
	if session.ResultFinalized then
		return buildPayload(session, winner, reason)
	end

	session.ResultFinalized = true
	return buildPayload(session, winner, reason)
end

--[[
	FinalizeMatch(winner, reason)
	Fecha a partida inteira. Chamar duas vezes é no-op: a segunda chamada não
	recalcula bônus nem reenvia nada.
]]
function MatchResultsService.FinalizeMatch(winner: string, reason: string)
	if finalized then
		return
	end
	finalized = true

	-- (1) Bônus de fim -- ANTES do congelamento, senão seriam recusados.
	local bonusOk, bonusErr = pcall(function()
		MatchRewardService.ApplyEndOfMatchBonuses(winner)
	end)
	if not bonusOk then
		warn("[MatchResults] bônus de fim de partida falharam: " .. tostring(bonusErr))
	end

	-- (2) Congela: nada mais entra em nenhuma sessão.
	MatchStatsService.FreezeMatch()

	local sessions = MatchStatsService.GetAllSessions()

	-- (3) PerformanceScore de todo mundo antes dos destaques.
	for _, session in sessions do
		session.PerformanceScore = computePerformance(session)
	end

	-- (4) Destaques (inclui o MVP).
	local highlights, mvpUserId = resolveHighlights()
	lastHighlights = highlights
	lastMVPUserId = mvpUserId

	-- (5) Envio individual. Quem saiu do servidor não recebe nada (não há pra
	-- quem mandar), mas a sessão dele continua existindo e contou pros
	-- destaques -- é o que faz o placar da partida ficar completo.
	for userId, session in sessions do
		session.ResultFinalized = true

		local player = MatchStatsService.GetPlayer(userId)
		if not player then
			continue
		end

		-- Credita ANTES de montar o payload final: a tela de resultados
		-- mostra o nível novo/antigo da conta na mesma tela do XP da partida.
		local matchXP = math.floor(session.MatchXP + 0.5)
		local account = creditAccountXP(player, matchXP)

		local payload = buildPayload(session, winner, reason, account)
		Remotes.MatchResults:FireClient(player, payload)
	end

	-- (6) Fecha a janela de medição. Só AGORA: fazer isso antes do passo (1)
	-- faria os bônus de fim de partida serem recusados por "fora da janela".
	-- As sessões continuam existindo (o relatório já foi enviado, mas elas
	-- ainda são consultáveis durante a intermissão); quem as zera é o
	-- StartMatch da partida seguinte.
	MatchStatsService.EndMatch()

	if verbose then
		print(string.format("[MatchResults] %d destaque(s); MVP: %s", #highlights, tostring(mvpUserId)))
		for _, session in sessions do
			print(string.format(
				"[MatchResults]   %s (%s) -- %d XP | desempenho %d",
				session.Name,
				session.Role,
				math.floor(session.MatchXP + 0.5),
				session.PerformanceScore
			))
		end
	end
end

--[[ GetLastHighlights() -- destaques da última partida finalizada. ]]
function MatchResultsService.GetLastHighlights(): { Types.Highlight }
	return lastHighlights
end

--[[
	ResetForNewMatch()
	Destrava a finalização pra próxima partida. As SESSÕES em si são zeradas
	por MatchStatsService.StartMatch -- aqui só o estado deste serviço.
]]
function MatchResultsService.ResetForNewMatch()
	finalized = false
	lastHighlights = {}
	lastMVPUserId = nil
end

--------------------------------------------------------------------------------
-- Init
--------------------------------------------------------------------------------

function MatchResultsService.Init()
	if initialized then
		return
	end
	initialized = true

	RoundManager.RoundPrepared.Event:Connect(function()
		MatchResultsService.ResetForNewMatch()
	end)

	-- Quem trata a SAÍDA de um jogador é o MatchStatsService (MarkLeft) e o
	-- MatchRewardService (penalidade de abandono). Aqui não há nada a fazer:
	-- depois do fim, a sessão já está congelada e o relatório já foi enviado.
	RoundManager.RoundEnded.Event:Connect(function(winner: string, reason: string)
		MatchResultsService.FinalizeMatch(winner, reason)
	end)
end

return MatchResultsService
