--!strict
--[[
	MatchStatsTypes
	Tipos e NOMES CANÔNICOS das estatísticas de partida, compartilhados entre
	servidor (MatchStatsService / MatchRewardService / MatchResultsService) e
	cliente (MatchResultsController / XPNotificationController).

	POR QUE UM MÓDULO SÓ DE NOMES
	  Estatística é tabela indexada por string. Se cada sistema escrever a
	  string na mão, um `AddStat(player, "MonsterHits", 1)` num arquivo e um
	  `AddStat(player, "MonsterHit", 1)` em outro criam DUAS estatísticas
	  diferentes que ninguém percebe -- o relatório final só mostra metade do
	  valor e não há erro nenhum no Output. Com as constantes daqui, o typo
	  vira `nil` e estoura na hora, no arquivo errado.

	  O mesmo vale pras categorias de XP: são as chaves do XPBreakdown que a
	  tela de resultados desenha. Categoria inventada = fatia que some da UI.

	NADA AQUI DEPENDE DE ROBLOX: é só tabela e tipo. É de propósito -- assim
	os testes (tests/match_stats.luau) carregam este módulo direto, sem stub.

	Uso:
		local Types = require(ReplicatedStorage.Modules.MatchStatsTypes)
		Stats.AddStat(player, Types.Stat.MonsterHits, 1)
]]

local MatchStatsTypes = {}

--------------------------------------------------------------------------------
-- Categorias de XP (chaves do XPBreakdown)
--------------------------------------------------------------------------------

MatchStatsTypes.Category = {
	Survival = "Survival", -- ficar vivo, escapar, aguentar a partida
	Objectives = "Objectives", -- rádio, peças e itens de objetivo
	Teamwork = "Teamwork", -- curar, salvar, ajudar aliado
	Combat = "Combat", -- acertar/atordoar/cegar o Monstro
	Stealth = "Stealth", -- escapar de perseguição, passar despercebido
	Monster = "Monster", -- tudo que o Monstro faz de bom
	Bonuses = "Bonuses", -- bônus de fim de partida (último vivo, etc.)
	Penalties = "Penalties", -- SEMPRE negativo (ver MatchRewardsConfig)
}

-- Ordem em que a tela de resultados desenha as fatias. Percorra esta lista
-- em vez de `pairs(Category)`: a ordem de `pairs` não é estável e a UI
-- ficaria trocando de ordem entre uma partida e outra.
MatchStatsTypes.CategoryOrder = {
	"Survival",
	"Objectives",
	"Teamwork",
	"Combat",
	"Stealth",
	"Monster",
	"Bonuses",
	"Penalties",
}

-- Texto pronto pra UI de cada categoria.
MatchStatsTypes.CategoryLabel = {
	Survival = "Sobrevivência",
	Objectives = "Objetivos",
	Teamwork = "Equipe",
	Combat = "Combate",
	Stealth = "Furtividade",
	Monster = "Monstro",
	Bonuses = "Bônus",
	Penalties = "Penalidades",
}

--------------------------------------------------------------------------------
-- Nomes canônicos das estatísticas
--------------------------------------------------------------------------------
-- Toda estatística é NUMÉRICA (contador, soma ou segundos acumulados), exceto
-- as marcadas como booleana/texto no comentário. Quem grava usa AddStat (soma)
-- ou SetStat (substitui) -- ver MatchStatsService.

MatchStatsTypes.Stat = {
	--------------------------------------------------------------------------
	-- Comuns aos dois papéis
	--------------------------------------------------------------------------
	AliveTime = "AliveTime", -- segundos vivo dentro da partida
	DistanceWalked = "DistanceWalked", -- studs andando
	DistanceRan = "DistanceRan", -- studs correndo (sprint de verdade)
	TimeRunning = "TimeRunning", -- segundos em sprint
	DamageDealt = "DamageDealt", -- dano causado (soma do que o DamageSystem aplicou)
	DamageTaken = "DamageTaken", -- dano recebido
	Hits = "Hits", -- golpes/tiros que conectaram

	--------------------------------------------------------------------------
	-- Sobrevivente
	--------------------------------------------------------------------------
	MonsterStuns = "MonsterStuns", -- vezes que atordoou o Monstro
	MonsterBlinds = "MonsterBlinds", -- vezes que cegou o Monstro com lanterna/tocha
	HealsPerformed = "HealsPerformed", -- curas concluídas (em si ou em aliado)
	HealingDone = "HealingDone", -- HP total devolvido
	AlliesHelped = "AlliesHelped", -- aliados curados/ajudados
	AlliesSaved = "AlliesSaved", -- aliados salvos de uma situação letal
	ImportantItemsFound = "ImportantItemsFound", -- itens relevantes descobertos
	GasolineFound = "GasolineFound", -- galões de Gasolina coletados do mapa
	ItemsDelivered = "ItemsDelivered", -- itens de objetivo entregues/instalados
	RepairsCompleted = "RepairsCompleted", -- minigames de reparo concluídos
	ObjectiveStepsCompleted = "ObjectiveStepsCompleted", -- etapas de objetivo concluídas
	ObjectiveContribution = "ObjectiveContribution", -- soma abstrata de contribuição
	ChasesStarted = "ChasesStarted", -- perseguições em que entrou
	ChasesEscaped = "ChasesEscaped", -- perseguições das quais escapou
	TimeChased = "TimeChased", -- segundos sendo perseguido
	TimeNearMonsterUndetected = "TimeNearMonsterUndetected", -- segundos perto do Monstro sem virar caçada
	TimesDetected = "TimesDetected", -- vezes que o Monstro o detectou

	--------------------------------------------------------------------------
	-- Monstro
	--------------------------------------------------------------------------
	SurvivorsDowned = "SurvivorsDowned", -- derrubados (estado intermediário; ainda não existe no jogo)
	SurvivorsEliminated = "SurvivorsEliminated", -- eliminados de vez
	ChasesCompleted = "ChasesCompleted", -- perseguições fechadas com o alvo pego
	ChaseTime = "ChaseTime", -- segundos perseguindo
	ObjectivesInterrupted = "ObjectivesInterrupted",
	HealsInterrupted = "HealsInterrupted",
	BarricadesDestroyed = "BarricadesDestroyed",
	PowersUsed = "PowersUsed", -- usos de poder com resultado válido
	IdleTime = "IdleTime", -- segundos parado longe de todo mundo
}

--------------------------------------------------------------------------------
-- Campos não numéricos da sessão (não passam por AddStat/SetStat)
--------------------------------------------------------------------------------

export type ActionRecord = {
	ActionId: string, -- id estável (chave de MatchRewardsConfig.Actions)
	Category: string, -- MatchStatsTypes.Category
	Label: string, -- texto pronto pra UI ("Curou um aliado")
	XP: number, -- positivo (ganho) ou negativo (penalidade)
	MatchTime: number, -- segundos desde o início da partida
	Count: number, -- quantas ocorrências este registro representa (agrupamento)
	Detail: string?, -- informação extra opcional já segura pra exibir
}

export type XPBreakdown = { [string]: number }

export type Session = {
	UserId: number,
	Name: string, -- Player.Name no início da partida (sobrevive à saída)
	DisplayName: string,
	Role: string, -- GameConfig.Roles.*
	MatchXP: number,
	PerformanceScore: number,
	XPBreakdown: XPBreakdown,
	ActionHistory: { ActionRecord },
	Stats: { [string]: number },
	Highlights: { string }, -- ids dos destaques vencidos (preenchido na finalização)
	JoinedAt: number, -- os.clock() de quando a sessão começou
	AliveTime: number, -- espelho de Stats.AliveTime, congelado na morte
	IsAlive: boolean,
	Escaped: boolean,
	EscapeMethod: string?, -- "Helicoptero" | nil (o barco novo será adicionado depois)
	Eliminated: boolean,
	Left: boolean, -- saiu do servidor no meio da partida
	ResultFinalized: boolean,
}

export type Highlight = {
	Id: string,
	Name: string,
	Description: string,
	UserId: number,
	PlayerName: string,
	Value: number,
}

-- Progresso da CONTA (persistente, entre partidas) depois de creditar o
-- MatchXP desta partida. nil quando a persistência está desligada
-- (MatchRewardsConfig.Persistence.CommitMatchXP) ou DataStoreManager falhou
-- ao carregar o perfil -- a tela de resultados simplesmente omite a seção.
export type AccountProgress = {
	CommittedXP: number, -- quanto desta partida foi de fato gravado (após CommitMultiplier)
	TotalXP: number, -- XP persistente total, DEPOIS de creditar esta partida
	Level: number,
	PreviousLevel: number, -- nível ANTES de creditar esta partida
	LeveledUp: boolean,
	XPIntoLevel: number,
	XPForNextLevel: number, -- 0 quando AtMaxLevel
	AtMaxLevel: boolean,
}

-- Payload que o servidor manda pro DONO da sessão (Remotes.MatchResults).
-- É construído em MatchResultsService; nenhuma tabela interna vai crua.
export type ResultsPayload = {
	Winner: string,
	Reason: string,
	Role: string,
	MatchXP: number,
	PerformanceScore: number,
	XPBreakdown: XPBreakdown,
	Actions: { ActionRecord }, -- já agrupadas por ActionId
	Stats: { { Key: string, Label: string, Value: string } }, -- prontas pra desenhar
	Highlights: { Highlight }, -- destaques da partida inteira (públicos)
	MVPUserId: number?,
	Escaped: boolean,
	EscapeMethod: string?,
	Eliminated: boolean,
	IsMVP: boolean,
	Account: AccountProgress?,
}

-- Payload da notificação discreta durante a partida (Remotes.MatchXPNotification).
export type NotificationPayload = {
	Id: string, -- identificador único; o cliente descarta repetição
	ActionId: string,
	Label: string,
	XP: number,
	Category: string,
	Priority: number,
}

--------------------------------------------------------------------------------
-- Rótulos das estatísticas na tela de resultados
--------------------------------------------------------------------------------
-- Estatística sem rótulo aqui simplesmente não é desenhada. É de propósito:
-- campos preparados mas ainda sem sistema por trás (ex: SurvivorsDowned) não
-- devem aparecer zerados na tela e parecer bug.

MatchStatsTypes.StatLabel = {
	AliveTime = "Tempo vivo",
	DistanceWalked = "Distância andando",
	DistanceRan = "Distância correndo",
	TimeRunning = "Tempo correndo",
	DamageDealt = "Dano causado",
	DamageTaken = "Dano recebido",
	Hits = "Acertos",
	MonsterStuns = "Atordoou o Monstro",
	MonsterBlinds = "Cegou o Monstro",
	HealsPerformed = "Curas realizadas",
	HealingDone = "HP recuperado",
	AlliesHelped = "Aliados ajudados",
	AlliesSaved = "Aliados salvos",
	ImportantItemsFound = "Itens importantes",
	GasolineFound = "Galões de gasolina encontrados",
	ItemsDelivered = "Itens entregues",
	RepairsCompleted = "Reparos concluídos",
	ObjectiveStepsCompleted = "Etapas de objetivo",
	ObjectiveContribution = "Contribuição em objetivos",
	ChasesStarted = "Perseguições sofridas",
	ChasesEscaped = "Perseguições escapadas",
	TimeChased = "Tempo perseguido",
	TimeNearMonsterUndetected = "Tempo escondido perto do Monstro",
	TimesDetected = "Vezes detectado",
	SurvivorsDowned = "Sobreviventes derrubados",
	SurvivorsEliminated = "Sobreviventes eliminados",
	ChasesCompleted = "Perseguições concluídas",
	ChaseTime = "Tempo perseguindo",
	ObjectivesInterrupted = "Objetivos interrompidos",
	HealsInterrupted = "Curas interrompidas",
	BarricadesDestroyed = "Barricadas destruídas",
	PowersUsed = "Poderes usados",
	IdleTime = "Tempo ocioso",
}

-- Como formatar cada estatística na tela. Faltando aqui = número inteiro.
--   "seconds" -> "3m 20s"  |  "studs" -> "412 m"  |  "decimal" -> "87.5"
MatchStatsTypes.StatFormat = {
	AliveTime = "seconds",
	TimeRunning = "seconds",
	TimeChased = "seconds",
	TimeNearMonsterUndetected = "seconds",
	ChaseTime = "seconds",
	IdleTime = "seconds",
	DistanceWalked = "studs",
	DistanceRan = "studs",
	DamageDealt = "decimal",
	DamageTaken = "decimal",
	HealingDone = "decimal",
	ObjectiveContribution = "decimal",
}

-- Quais estatísticas cada papel vê na tela final, e em que ordem.
-- Sobrevivente não precisa ver "Sobreviventes eliminados" zerado.
MatchStatsTypes.StatsShownFor = {
	Sobrevivente = {
		"AliveTime",
		"DistanceWalked",
		"DistanceRan",
		"TimeRunning",
		"DamageDealt",
		"DamageTaken",
		"Hits",
		"MonsterStuns",
		"MonsterBlinds",
		"HealsPerformed",
		"HealingDone",
		"AlliesHelped",
		"ImportantItemsFound",
		"GasolineFound",
		"ItemsDelivered",
		"RepairsCompleted",
		"ObjectiveStepsCompleted",
		"ObjectiveContribution",
		"ChasesStarted",
		"ChasesEscaped",
		"TimeChased",
		"TimeNearMonsterUndetected",
		"TimesDetected",
	},
	Monstro = {
		"AliveTime",
		"DistanceWalked",
		"DistanceRan",
		"DamageDealt",
		"DamageTaken",
		"Hits",
		"SurvivorsEliminated",
		"ChasesStarted",
		"ChasesCompleted",
		"ChaseTime",
		"ObjectivesInterrupted",
		"HealsInterrupted",
		"PowersUsed",
	},
}
-- O Espião joga como Sobrevivente pro relatório: mesma lista de estatísticas.
MatchStatsTypes.StatsShownFor.Espiao = MatchStatsTypes.StatsShownFor.Sobrevivente

--[[
	NewStats()
	Tabela de estatísticas zerada com TODOS os nomes canônicos presentes.
	Começar com todas em 0 (em vez de criar a chave no primeiro AddStat)
	deixa a comparação dos destaques simples: não existe `nil` pra tratar.
]]
function MatchStatsTypes.NewStats(): { [string]: number }
	local stats = {}
	for _, name in MatchStatsTypes.Stat do
		stats[name] = 0
	end
	return stats
end

--[[
	IsStat(name)
	true se `name` é um nome canônico. MatchStatsService rejeita o resto --
	é o que transforma um typo em erro visível em vez de estatística fantasma.
]]
function MatchStatsTypes.IsStat(name: unknown): boolean
	return type(name) == "string" and MatchStatsTypes.Stat[name] ~= nil
end

function MatchStatsTypes.IsCategory(name: unknown): boolean
	return type(name) == "string" and MatchStatsTypes.Category[name] ~= nil
end

return MatchStatsTypes
