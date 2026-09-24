--!strict
--[[
	MatchRewardsConfig
	Configuração CENTRAL de XP, pontuação de desempenho, destaques e
	notificações de fim/durante a partida. Mesma ideia do GameConfig: mexer
	em balanceamento aqui, nunca dentro dos serviços.

	OS VALORES DE XP SÃO PROVISÓRIOS -- NENHUM SERVIÇO TEM NÚMERO ESCRITO.
	Foram escolhidos pra dar ordem de grandeza (um Sobrevivente que joga bem
	e escapa fecha perto de 600-900 XP; um Monstro dominante, algo
	parecido) e calibrados junto da curva de Modules/LevelSystem, mas ainda
	NÃO passaram por playtest real de balanceamento -- só por essa conta de
	grandeza. A persistência (DataStoreManager, ver Persistence abaixo) já
	está ligada porque perder progresso é pior que reajustar um número
	depois: mudar um XP aqui muda o RITMO de progressão dali pra frente,
	nunca apaga o que o jogador já tem. Ajuste à vontade.

	COMO O XP É CONCEDIDO (e por que exploit não passa)
	  Nenhum sistema entrega uma QUANTIDADE de XP. Todo mundo chama
	    MatchRewardService.AddXP(player, actionId, context?)
	  e o valor sai DAQUI, da tabela Actions. Um script (ou um exploit que
	  conseguisse rodar no servidor) não consegue passar "+999999": o
	  actionId ou existe nesta tabela, com o valor daqui, ou a concessão é
	  recusada. Recompensa variável (ex: dano) usa XPPerUnit + MaxUnitsPerGrant,
	  então mesmo o multiplicador tem teto.

	  Os dois RemoteEvents deste sistema (MatchResults e MatchXPNotification)
	  são SÓ Server -> Client: não existe OnServerEvent em lugar nenhum. O
	  cliente não tem como pedir, criar nem alterar XP.

	CAMPOS DE UMA AÇÃO
	  Category         MatchStatsTypes.Category -- fatia do XPBreakdown.
	  Label            texto pronto pra UI e pra notificação.
	  XP               valor fixo (positivo; negativo só em Penalties).
	  XPPerUnit        valor POR UNIDADE de context.Units (dano, HP curado...).
	  MaxUnitsPerGrant teto de unidades por concessão -- o teto do exploit.
	  Roles            quem pode ganhar. Ausente = qualquer papel.
	  Cooldown         segundos entre duas concessões da MESMA ação pro MESMO
	                   jogador. É o freio principal contra farm.
	  MaxPerMatch      quantas vezes a ação pode pagar na partida inteira.
	  UniqueBy         "context.Key" vira chave de unicidade: a mesma chave
	                   nunca paga duas vezes (objetivo concluído, item X...).
	  Priority         1 (discreta) a 5 (importante). Ordena a fila de
	                   notificação no cliente.
	  Enabled          false = ação preparada mas desligada (ver TeamHarm).

	NÃO EXISTE PENALIDADE POR JOGAR MAL: morrer, errar o golpe, tomar dano ou
	falhar num objetivo não tira XP. Só tiram XP ausência prolongada e
	abandono -- comportamentos que estragam a partida dos outros.
]]

local MatchStatsTypes = require(script.Parent.MatchStatsTypes)

local Category = MatchStatsTypes.Category

-- Papéis. Repetidos aqui como string literal de propósito: este módulo é
-- carregado pelos testes sem o GameConfig inteiro junto, e as strings são
-- um contrato estável (GameConfig.Roles nunca muda de valor sem migração).
local SURVIVOR = "Sobrevivente"
local MONSTER = "Monstro"
local SPY = "Espiao"

-- O Espião joga o jogo do Sobrevivente: mesma tabela de recompensas.
local SURVIVOR_ROLES = { [SURVIVOR] = true, [SPY] = true }
local MONSTER_ROLES = { [MONSTER] = true }

local MatchRewardsConfig = {}

MatchRewardsConfig.SurvivorRoles = SURVIVOR_ROLES
MatchRewardsConfig.MonsterRoles = MONSTER_ROLES

export type Action = {
	Category: string,
	Label: string,
	XP: number?,
	XPPerUnit: number?,
	MaxUnitsPerGrant: number?,
	Roles: { [string]: boolean }?,
	Cooldown: number?,
	MaxPerMatch: number?,
	UniqueBy: boolean?,
	Priority: number?,
	Enabled: boolean?,
}

--------------------------------------------------------------------------------
-- AÇÕES -- SOBREVIVENTE
--------------------------------------------------------------------------------

local Actions: { [string]: Action } = {
	-- Pulso de sobrevivência: MatchStatsService concede um a cada
	-- Timing.SurvivalTickInterval segundos enquanto o jogador está vivo.
	-- MaxPerMatch cobre a partida inteira com folga (630s / 30s = 21).
	SurvivalTick = {
		Category = Category.Survival,
		Label = "Sobreviveu mais 30s",
		XP = 5,
		Roles = SURVIVOR_ROLES,
		Cooldown = 25, -- abaixo do intervalo: o tick é quem manda o ritmo
		MaxPerMatch = 30,
		Priority = 1,
	},

	Escaped = {
		Category = Category.Survival,
		Label = "Escapou da ilha",
		XP = 200,
		Roles = SURVIVOR_ROLES,
		MaxPerMatch = 1,
		Priority = 5,
	},

	LastSurvivor = {
		Category = Category.Bonuses,
		Label = "Último sobrevivente vivo",
		XP = 75,
		Roles = SURVIVOR_ROLES,
		MaxPerMatch = 1,
		Priority = 4,
	},

	ImportantItemFound = {
		Category = Category.Objectives,
		Label = "Item importante encontrado",
		XP = 15,
		Roles = SURVIVOR_ROLES,
		Cooldown = 3,
		MaxPerMatch = 20,
		UniqueBy = true, -- a chave é a instância do item: achar o mesmo 2x não paga
		Priority = 2,
	},

	ObjectiveItemDelivered = {
		Category = Category.Objectives,
		Label = "Item de objetivo entregue",
		XP = 40,
		Roles = SURVIVOR_ROLES,
		MaxPerMatch = 12,
		UniqueBy = true, -- chave = peça/slot entregue
		Priority = 4,
	},

	ObjectiveStepCompleted = {
		Category = Category.Objectives,
		Label = "Etapa de objetivo concluída",
		XP = 50,
		Roles = SURVIVOR_ROLES,
		MaxPerMatch = 12,
		UniqueBy = true, -- chave = id da etapa: a mesma etapa nunca paga 2x
		Priority = 4,
	},

	ObjectiveCompleted = {
		Category = Category.Objectives,
		Label = "Objetivo concluído",
		XP = 120,
		Roles = SURVIVOR_ROLES,
		MaxPerMatch = 4,
		UniqueBy = true, -- chave = id do objetivo (ex.: "Radio")
		Priority = 5,
	},

	-- Contribuição contínua (reparo, sintonia, montagem). Paga por unidade de
	-- progresso, com teto por concessão pra um pulso gigante não virar XP.
	ObjectiveContribution = {
		Category = Category.Objectives,
		Label = "Progresso no objetivo",
		XPPerUnit = 0.6,
		MaxUnitsPerGrant = 25,
		Roles = SURVIVOR_ROLES,
		Cooldown = 4,
		MaxPerMatch = 40,
		Priority = 1,
	},

	AllyHealed = {
		Category = Category.Teamwork,
		Label = "Curou um aliado",
		XP = 30,
		Roles = SURVIVOR_ROLES,
		Cooldown = 10, -- trava a dupla que se cura em looping pra farmar
		MaxPerMatch = 10,
		Priority = 3,
	},

	AllySaved = {
		Category = Category.Teamwork,
		Label = "Salvou um aliado",
		XP = 60,
		Roles = SURVIVOR_ROLES,
		Cooldown = 15,
		MaxPerMatch = 8,
		Priority = 4,
	},

	MonsterHit = {
		Category = Category.Combat,
		Label = "Acertou o Monstro",
		XP = 10,
		Roles = SURVIVOR_ROLES,
		Cooldown = 1, -- um golpe por segundo: cadência real de arma corpo a corpo
		MaxPerMatch = 40,
		Priority = 2,
	},

	MonsterStunned = {
		Category = Category.Combat,
		Label = "Atordoou o Monstro",
		XP = 35,
		Roles = SURVIVOR_ROLES,
		Cooldown = 6,
		MaxPerMatch = 12,
		Priority = 3,
	},

	MonsterBlinded = {
		Category = Category.Combat,
		Label = "Cegou o Monstro com a luz",
		XP = 25,
		Roles = SURVIVOR_ROLES,
		Cooldown = 8, -- a luz fica ligada: sem isso, farm contínuo
		MaxPerMatch = 12,
		Priority = 3,
	},

	ChaseEscaped = {
		Category = Category.Stealth,
		Label = "Escapou de uma perseguição",
		XP = 45,
		Roles = SURVIVOR_ROLES,
		Cooldown = 10,
		MaxPerMatch = 12,
		Priority = 3,
	},

	MonsterKillAssist = {
		Category = Category.Combat,
		Label = "Contribuiu para derrubar o Monstro",
		XP = 80,
		Roles = SURVIVOR_ROLES,
		MaxPerMatch = 1,
		Priority = 5,
	},

	MonsterKillFinalBlow = {
		Category = Category.Combat,
		Label = "Golpe final no Monstro",
		XP = 120,
		Roles = SURVIVOR_ROLES,
		MaxPerMatch = 1,
		Priority = 5,
	},

	----------------------------------------------------------------------------
	-- AÇÕES -- MONSTRO
	----------------------------------------------------------------------------

	SurvivorFound = {
		Category = Category.Monster,
		Label = "Encontrou um sobrevivente",
		XP = 15,
		Roles = MONSTER_ROLES,
		Cooldown = 12, -- o mesmo alvo entrando e saindo do raio não paga toda hora
		MaxPerMatch = 25,
		Priority = 2,
	},

	SurvivorHit = {
		Category = Category.Monster,
		Label = "Acertou um sobrevivente",
		XP = 20,
		Roles = MONSTER_ROLES,
		Cooldown = 1,
		MaxPerMatch = 40,
		Priority = 2,
	},

	-- "Derrubado" (estado intermediário antes da morte) ainda não existe no
	-- jogo. A ação fica pronta pro dia em que existir; nada a chama hoje.
	SurvivorDowned = {
		Category = Category.Monster,
		Label = "Derrubou um sobrevivente",
		XP = 60,
		Roles = MONSTER_ROLES,
		Cooldown = 3,
		MaxPerMatch = 12,
		Priority = 4,
	},

	SurvivorEliminated = {
		Category = Category.Monster,
		Label = "Eliminou um sobrevivente",
		XP = 130,
		Roles = MONSTER_ROLES,
		MaxPerMatch = 12,
		UniqueBy = true, -- chave = UserId da vítima: cada um paga uma vez só
		Priority = 5,
	},

	ChaseCompleted = {
		Category = Category.Monster,
		Label = "Perseguição bem-sucedida",
		XP = 40,
		Roles = MONSTER_ROLES,
		Cooldown = 8,
		MaxPerMatch = 15,
		Priority = 3,
	},

	ObjectiveInterrupted = {
		Category = Category.Monster,
		Label = "Interrompeu um objetivo",
		XP = 45,
		Roles = MONSTER_ROLES,
		Cooldown = 10,
		MaxPerMatch = 12,
		Priority = 4,
	},

	HealInterrupted = {
		Category = Category.Monster,
		Label = "Interrompeu uma cura",
		XP = 35,
		Roles = MONSTER_ROLES,
		Cooldown = 8,
		MaxPerMatch = 12,
		Priority = 3,
	},

	BarricadeDestroyed = {
		Category = Category.Monster,
		Label = "Destruiu uma barricada",
		XP = 25,
		Roles = MONSTER_ROLES,
		Cooldown = 4,
		MaxPerMatch = 15,
		UniqueBy = true, -- chave = instância da barricada
		Priority = 2,
	},

	MonsterPowerUsed = {
		Category = Category.Monster,
		Label = "Usou um poder com sucesso",
		XP = 15,
		Roles = MONSTER_ROLES,
		Cooldown = 6,
		MaxPerMatch = 20,
		Priority = 1,
	},

	AllSurvivorsEliminated = {
		Category = Category.Bonuses,
		Label = "Eliminou todos os sobreviventes",
		XP = 200,
		Roles = MONSTER_ROLES,
		MaxPerMatch = 1,
		Priority = 5,
	},

	----------------------------------------------------------------------------
	-- PENALIDADES (XP negativo -- categoria Penalties)
	----------------------------------------------------------------------------

	InactivityPenalty = {
		Category = Category.Penalties,
		Label = "Penalidade por inatividade",
		XP = -10,
		Cooldown = 55, -- um pouco abaixo do intervalo de checagem
		MaxPerMatch = 6, -- teto: ninguém perde a partida inteira em penalidade
		Priority = 3,
	},

	AbandonedMatch = {
		Category = Category.Penalties,
		Label = "Abandonou a partida",
		XP = -50,
		MaxPerMatch = 1,
		Priority = 3,
	},

	-- PREPARADA E DESLIGADA: hoje não existe nenhuma forma SEGURA de separar
	-- "sabotou o time de propósito" de "errou o alvo" ou "o Espião fez o
	-- trabalho dele". Ligar isso sem essa distinção puniria jogo legítimo.
	-- Deixe Enabled = false até existir uma detecção confiável.
	TeamHarm = {
		Category = Category.Penalties,
		Label = "Prejudicou a equipe",
		XP = -40,
		Cooldown = 30,
		MaxPerMatch = 3,
		Priority = 3,
		Enabled = false,
	},
}

MatchRewardsConfig.Actions = Actions

--------------------------------------------------------------------------------
-- TETOS POR CATEGORIA
--------------------------------------------------------------------------------
-- Última rede contra farm: mesmo que cooldown e MaxPerMatch de uma ação
-- estejam frouxos, a categoria inteira para de pagar ao bater o teto. O XP
-- excedente é simplesmente não concedido (a ação nem entra no histórico).
-- Penalties não tem teto positivo -- ele vive no MaxPerMatch de cada uma.

MatchRewardsConfig.CategoryCaps = {
	Survival = 250,
	Objectives = 700,
	Teamwork = 400,
	Combat = 600,
	Stealth = 350,
	Monster = 1200,
	Bonuses = 400,
}

--------------------------------------------------------------------------------
-- PROTEÇÃO CONTRA FARM (regras gerais, além do cooldown de cada ação)
--------------------------------------------------------------------------------

MatchRewardsConfig.AntiFarm = {
	-- Dano abaixo disso não conta como "acerto" pra XP nem pra estatística.
	-- Existe pra um sistema que aplique dano em tiquinhos não virar 50 hits.
	MinDamageForHit = 1,

	-- Cura abaixo disso não conta como cura de aliado (evita "curar" alguém
	-- que estava com a vida quase cheia repetidamente só pra pagar XP).
	MinHealForReward = 5,

	-- O MESMO par (curador, alvo) só paga de novo depois deste intervalo,
	-- mesmo que o cooldown da ação já tenha passado. É o freio específico
	-- contra duas pessoas se curando em looping.
	SameTargetHealCooldown = 25,

	-- O MESMO par (atacante, vítima) só paga XP de acerto neste intervalo.
	SameTargetHitCooldown = 0.8,

	-- Teto de registros no histórico. Passando disso, ações novas ainda somam
	-- XP e estatística, mas param de virar linha nova -- o agrupamento da tela
	-- final já junta repetição, e uma partida travada não pode inflar a tabela
	-- até estourar a memória.
	MaxActionHistory = 400,
}

--------------------------------------------------------------------------------
-- TEMPOS E DISTÂNCIA
--------------------------------------------------------------------------------

MatchRewardsConfig.Timing = {
	-- De quanto em quanto tempo o pulso de sobrevivência paga.
	SurvivalTickInterval = 30,

	-- Amostragem de posição/perseguição. O servidor NÃO mede por frame: ele
	-- aproveita a amostra que o StaminaSystem já calcula (MovementSampled,
	-- 20 Hz) e só processa a cada TrackInterval segundos.
	TrackInterval = 0.5,

	-- Distância percorrida entre duas amostras acima de
	--   velocidadeMáximaPlausível * intervalo * TeleportTolerance
	-- é descartada como teleporte/desync. O teleporte do Monstro e o
	-- ShadowRush caem exatamente aqui.
	TeleportTolerance = 1.6,

	-- Piso de velocidade plausível (studs/s) usado no limite acima, pra um
	-- WalkSpeed baixo não tornar o filtro apertado demais.
	MinPlausibleSpeed = 40,

	-- Deslocamento por amostra abaixo disso é ruído de física em pé parado.
	MinDistancePerSample = 0.15,

	-- Perseguição: começa quando o Monstro chega a ChaseStartRadius de um
	-- Sobrevivente vivo com linha de visada plausível; termina depois de
	-- ChaseEndGrace segundos seguidos além de ChaseEndRadius.
	ChaseStartRadius = 45,
	ChaseEndRadius = 75,
	ChaseEndGrace = 5,
	-- Perseguição mais curta que isso não conta como perseguição de verdade
	-- (o Monstro só passou perto). Não paga XP nem entra na estatística.
	ChaseMinDuration = 3,

	-- Furtividade: Sobrevivente entre StealthRadius e ChaseStartRadius do
	-- Monstro, sem estar em perseguição, acumula TimeNearMonsterUndetected.
	StealthRadius = 90,

	-- Inatividade: sem se deslocar mais que IdleDistance studs por
	-- IdleCheckInterval segundos conta como ocioso. Só passa a PENALIZAR
	-- depois de IdlePenaltyAfter segundos acumulados.
	IdleCheckInterval = 5,
	IdleDistance = 6,
	IdlePenaltyAfter = 60,
}

--------------------------------------------------------------------------------
-- PONTUAÇÃO DE DESEMPENHO (PerformanceScore)
--------------------------------------------------------------------------------
-- SEPARADA DO XP de propósito. O XP vai virar progressão de nível (quanto
-- mais você joga, mais acumula). A PerformanceScore compara jogadores DENTRO
-- de uma partida, então ela pesa contribuição, não tempo de jogo.
--
-- Fórmula: soma de (estatística * peso) + bônus de resultado, por papel.

MatchRewardsConfig.Performance = {
	Survivor = {
		Weights = {
			ObjectiveContribution = 1.2,
			ObjectiveStepsCompleted = 25,
			ItemsDelivered = 18,
			ImportantItemsFound = 4,
			HealingDone = 0.5,
			AlliesHelped = 20,
			AlliesSaved = 35,
			DamageDealt = 0.35,
			MonsterStuns = 15,
			MonsterBlinds = 10,
			ChasesEscaped = 18,
			TimeNearMonsterUndetected = 0.35,
			AliveTime = 0.12,
		},
		EscapedBonus = 120,
		SurvivedToEndBonus = 40,
	},

	Monster = {
		Weights = {
			SurvivorsEliminated = 90,
			SurvivorsDowned = 35,
			ChasesCompleted = 25,
			ChaseTime = 0.25,
			DamageDealt = 0.35,
			ObjectivesInterrupted = 30,
			HealsInterrupted = 20,
			PowersUsed = 5,
		},
		AllEliminatedBonus = 150,
		-- Ocioso derruba a pontuação de desempenho (mas NÃO tira XP -- quem
		-- faz isso é a penalidade de inatividade, que é outra coisa).
		IdlePenaltyPerSecond = 0.4,
	},
}

--------------------------------------------------------------------------------
-- DESTAQUES DO FIM DA PARTIDA
--------------------------------------------------------------------------------
-- Cada destaque compara UMA estatística (ou a PerformanceScore) entre os
-- jogadores elegíveis e premia o maior valor.
--
-- Minimum: ninguém abaixo disso ganha o destaque. Sem esse piso, "Médico da
-- Equipe" iria pra quem curou 1 HP numa partida em que ninguém curou nada --
-- um prêmio vazio que só faz o placar parecer quebrado.
--
-- EMPATE: vence quem atingiu o valor PRIMEIRO na partida (menor JoinedAt e,
-- persistindo o empate, menor UserId). É determinístico e não depende da
-- ordem em que a tabela foi percorrida -- ver MatchResultsService.

export type HighlightRule = {
	Id: string,
	Name: string,
	Description: string,
	Stat: string?, -- nome canônico em MatchStatsTypes.Stat
	UsePerformance: boolean?, -- compara PerformanceScore em vez de uma estatística
	Roles: { [string]: boolean }?, -- ausente = todos os papéis concorrem
	Minimum: number,
}

MatchRewardsConfig.Highlights = {
	{
		Id = "MVP",
		Name = "Melhor da Partida",
		Description = "Maior pontuação de desempenho",
		UsePerformance = true,
		Minimum = 1,
	},
	{
		Id = "Marathoner",
		Name = "Maratonista",
		Description = "Maior distância percorrida",
		Stat = "DistanceRan",
		Minimum = 400,
	},
	{
		Id = "Medic",
		Name = "Médico da Equipe",
		Description = "Mais cura realizada",
		Stat = "HealingDone",
		Roles = SURVIVOR_ROLES,
		Minimum = 30,
	},
	{
		Id = "Fighter",
		Name = "Lutador",
		Description = "Maior dano causado ao Monstro",
		Stat = "DamageDealt",
		Roles = SURVIVOR_ROLES,
		Minimum = 25,
	},
	{
		Id = "Mechanic",
		Name = "Mecânico",
		Description = "Maior contribuição em objetivos",
		Stat = "ObjectiveContribution",
		Roles = SURVIVOR_ROLES,
		Minimum = 20,
	},
	{
		Id = "RepairExpert",
		Name = "Especialista em Reparos",
		Description = "Mais reparos concluídos",
		Stat = "RepairsCompleted",
		Roles = SURVIVOR_ROLES,
		Minimum = 1,
	},
	{
		Id = "FuelFinder",
		Name = "Caçador de Combustível",
		Description = "Mais galões de gasolina encontrados",
		Stat = "GasolineFound",
		Roles = SURVIVOR_ROLES,
		Minimum = 1,
	},
	{
		Id = "Supplier",
		Name = "Fornecedor da Equipe",
		Description = "Mais itens importantes encontrados",
		Stat = "ImportantItemsFound",
		Roles = SURVIVOR_ROLES,
		Minimum = 2,
	},
	{
		Id = "Guardian",
		Name = "Protetor da Equipe",
		Description = "Mais aliados salvos",
		Stat = "AlliesSaved",
		Roles = SURVIVOR_ROLES,
		Minimum = 1,
	},
	{
		Id = "StealthMaster",
		Name = "Mestre da Furtividade",
		Description = "Mais tempo perto do Monstro sem ser detectado",
		Stat = "TimeNearMonsterUndetected",
		Roles = SURVIVOR_ROLES,
		Minimum = 30,
	},
	{
		Id = "PerfectBait",
		Name = "Isca Perfeita",
		Description = "Mais tempo sendo perseguido",
		Stat = "TimeChased",
		Roles = SURVIVOR_ROLES,
		Minimum = 25,
	},
	{
		Id = "BornSurvivor",
		Name = "Sobrevivente Nato",
		Description = "Mais tempo vivo",
		Stat = "AliveTime",
		Roles = SURVIVOR_ROLES,
		Minimum = 60,
	},
	{
		Id = "RelentlessHunter",
		Name = "Caçador Implacável",
		Description = "Melhor desempenho do Monstro",
		UsePerformance = true,
		Roles = MONSTER_ROLES,
		Minimum = 100,
	},
	{
		Id = "Hunter",
		Name = "Predador",
		Description = "Mais sobreviventes eliminados",
		Stat = "SurvivorsEliminated",
		Roles = MONSTER_ROLES,
		Minimum = 1,
	},
} :: { HighlightRule }

--------------------------------------------------------------------------------
-- NOTIFICAÇÃO DE XP DURANTE A PARTIDA
--------------------------------------------------------------------------------
-- Lida pelo cliente (client/XPNotificationController). O servidor só usa
-- MergeWindow/Priority pra decidir o que mandar; o resto é apresentação.
--
-- POSIÇÃO: canto SUPERIOR DIREITO. Foi escolhido depois de olhar o que já
-- ocupa a tela:
--   topo-esquerda    ObjectivesHUD (barra do rádio)
--   topo-centro      MainHUD.PhaseFrame (fase + tempo)
--   baixo-esquerda   MainHUD.RoleFrame (papel)
--   baixo-centro     OTSHUD (munição)
--   baixo-direita    SurvivalMinimapHUD (minimapa) + StaminaHUD
--   centro           FearPresentation / DamageScreen (vinheta)
-- O canto superior direito é o único livre. Se algum dia algo for pra lá,
-- troque Position aqui -- nenhum número de posição está escrito no cliente.

MatchRewardsConfig.Notification = {
	Enabled = true,

	-- Quanto tempo cada notificação fica na tela (sem contar fade).
	Duration = 2,
	FadeInTime = 0.18,
	FadeOutTime = 0.35,

	-- Deslocamento de entrada, em fração da largura do card (entra da direita).
	SlideFraction = 0.35,

	-- Âncora e posição da pilha. Scale nos dois eixos + offset pequeno, pra
	-- funcionar igual em monitor e celular.
	Position = {
		AnchorPoint = { 1, 0 },
		-- O offset Y cobre a barra superior do celular; o X afasta da borda.
		Scale = { 1, 0 },
		Offset = { -14, 14 },
	},
	-- Tamanho do card: largura em Scale (responsivo) com teto/piso em pixels.
	CardWidthScale = 0.24,
	CardMinWidth = 190,
	CardMaxWidth = 300,
	CardHeight = 46,
	CardSpacing = 6,

	DisplayOrder = 22, -- acima da HUD (5..20), abaixo da tela de morte (1000)

	-- Quantas notificações podem estar VISÍVEIS ao mesmo tempo. 1 mantém o
	-- efeito discreto; 2 evita que uma rajada de ações fique muito atrasada.
	MaxVisible = 2,
	-- Teto da fila. Passando disso, a de MENOR prioridade é descartada.
	MaxQueue = 12,

	-- Ações IGUAIS recebidas dentro desta janela viram uma linha só
	-- ("Acertou o Monstro ×3 -- +30 XP"), tanto na fila quanto já na tela.
	MergeWindow = 2.5,

	-- Cores (estilo de terror: fundo escuro translúcido, texto quente).
	Colors = {
		Background = { 0.04, 0.04, 0.05 },
		BackgroundTransparency = 0.25,
		Stroke = { 0.22, 0.2, 0.18 },
		Label = { 0.88, 0.86, 0.82 },
		-- XP positivo comum.
		Positive = { 0.63, 0.92, 0.6 },
		-- XP positivo de ação importante (Priority >= 4): dourado.
		Highlight = { 0.95, 0.82, 0.42 },
		-- Penalidade: vermelho suave, nunca saturado.
		Negative = { 0.85, 0.42, 0.4 },
	},

	Sound = {
		Enabled = true,
		Volume = 0.35,
		-- Intervalo mínimo entre dois sons. Sem isso, uma rajada de acertos
		-- viraria uma metralhadora de bipes.
		MinInterval = 0.45,

		-- !! SEM ID AINDA !! Não existe som de XP no projeto (SoundManager só
		-- tem morte/arremesso, ambos ainda são placeholder
		-- "rbxassetid://0"). Cole aqui o id do som escolhido -- string vazia
		-- simplesmente não toca nada, o resto da notificação funciona igual.
		-- Procure algo CURTO (< 0.4s) e seco: um "tick"/"clink" abafado.
		GainId = "", -- ex: "rbxassetid://0000000000"
		PenaltyId = "", -- tom mais grave/abafado, nunca um alarme
	},

	-- Gancho pra uma opção futura de "desligar sons" nas configurações do
	-- jogador: o cliente checa este Attribute no Player antes de tocar. Como
	-- nada escreve nele hoje, o som fica ligado por padrão.
	MuteAttribute = "MatchXPSoundMuted",
}

--------------------------------------------------------------------------------
-- TELA DE RESULTADOS
--------------------------------------------------------------------------------

MatchRewardsConfig.Results = {
	DisplayOrder = 30, -- acima da HUD e da notificação, abaixo da tela de morte
	-- Quantas linhas de ação a tela lista (já agrupadas por ação). O resto
	-- vira "+N outras ações".
	MaxActionRows = 14,
	-- Segundos entre o fim da partida e a tela aparecer, pro jogador ver o
	-- desfecho antes de levar um painel na cara.
	OpenDelay = 1.5,
}

--------------------------------------------------------------------------------
-- PROGRESSÃO PERSISTENTE
--------------------------------------------------------------------------------
-- MatchResultsService credita o MatchXP de cada jogador em
-- DataStoreManager.AddXP no fim da partida (gravação por delta -- nunca
-- sobrescreve o que já está salvo, ver o cabeçalho de DataStoreManager.lua).
-- O nível da CONTA é derivado desse total por Modules/LevelSystem; este
-- módulo só decide QUANTO XP cada ação vale, nunca o nível em si.
--
-- Os valores de XP acima já não são um chute qualquer: as ordens de
-- grandeza (pulso de sobrevivência pequeno, objetivo médio, eliminação/fuga
-- grande) foram calibradas junto da curva de LevelSystem pra uma partida
-- "boa" render entre meio e um nível inteiro nos primeiros níveis. Ainda
-- assim, NENHUM número aqui passou por playtest real -- continue ajustando
-- à vontade; CommitMultiplier abaixo existe exatamente pra poder reajustar
-- a economia persistente sem tocar no que a tela de resultados mostra.

MatchRewardsConfig.Persistence = {
	CommitMatchXP = true,
	-- Multiplicador aplicado ao XP da partida ao gravar. Deixa ajustar a
	-- economia persistente sem mexer no XP mostrado na tela de resultados.
	CommitMultiplier = 1,
}

--------------------------------------------------------------------------------
-- DEPURAÇÃO
--------------------------------------------------------------------------------

MatchRewardsConfig.Debug = {
	-- Loga cada concessão e cada RECUSA de XP (com o motivo: cooldown, teto,
	-- papel errado, alvo inválido...). Essencial pra testar no Studio e ver
	-- POR QUE uma ação não pagou -- sem isso a recusa é silenciosa.
	--
	-- Os serviços só olham pra isto quando RunService:IsStudio() é true, então
	-- deixar ligado não polui o Output do jogo publicado.
	VerboseInStudio = false,
}

return MatchRewardsConfig
