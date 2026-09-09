--!strict
--[[
	GameConfig
	Constantes de balanceamento do jogo "Náufragos".

	COMO AJUSTAR:
	- Todos os tempos estão em SEGUNDOS.
	- Onde existe Min/Max, o valor usado de fato é o `Default` (ou o sorteio
	  entre Min e Max, se você quiser variar por partida).
	- Este módulo é só dados: não coloque lógica de jogo aqui.

	Uso:
		local GameConfig = require(game.ReplicatedStorage.Modules.GameConfig)
		print(GameConfig.Match.DurationDefault)
]]

local GameConfig = {}

-- Atalhos de leitura (só para deixar os números abaixo legíveis)
local MINUTE = 60

--------------------------------------------------------------------------------
-- JOGADORES
--------------------------------------------------------------------------------

GameConfig.Players = {
	Min = 6, -- partida não inicia com menos que isso
	Max = 10, -- lotação máxima do servidor/partida
}

--------------------------------------------------------------------------------
-- MOVIMENTO
--------------------------------------------------------------------------------

-- ATENÇÃO: estes números NÃO valem mais. Quem manda no WalkSpeed/sprint agora
-- é o "Ultimate R6 Movement System" (StarterCharacterScripts/Crouching), e os
-- valores dele ficam DENTRO do próprio script, não aqui. Mantido só porque
-- MonsterLightWeakness/ConfrontSystem ainda leem WalkSpeed pra restaurar
-- depois de enfraquecer/amarrar. Se for ajustar velocidade, é no Crouching.
GameConfig.Movement = {
	WalkSpeed = 16,
	SprintSpeed = 24,
	AimSpeed = 10,
}

--------------------------------------------------------------------------------
-- VIDA / DANO
--------------------------------------------------------------------------------
-- DamageSystem.lua (servidor) é a porta ÚNICA de dano/cura: quem quiser tirar
-- vida chama DamageSystem.Apply em vez de mexer no Humanoid direto. A barra de
-- vida (StarterGui/Ui, do pacote de movimento) só lê Humanoid.Health/MaxHealth.

GameConfig.Health = {
	Max = 100, -- MaxHealth aplicado ao Humanoid no spawn

	-- Regeneração passiva controlada pelo DamageSystem (a do Roblox é
	-- desligada -- ver DisableRobloxDefaultRegen). 0 = sem regeneração.
	RegenPerSecond = 2,
	RegenDelayAfterDamage = 6, -- s sem tomar dano antes de começar a regenerar

	-- Remove o script "Health" que o Roblox injeta no character (regen de
	-- 1%/s fora do nosso controle). Deixe true pra o RegenPerSecond acima ser
	-- a única regeneração do jogo.
	DisableRobloxDefaultRegen = true,

	-- Cura do Chocolate. ERA cura TOTAL -- virou valor fixo pra a passiva da
	-- Sofia ("cura 40% mais eficaz") ter o que multiplicar, e pra o item ser
	-- uma decisão em vez de um reset de vida.
	ChocolateHeal = 45,
	PassivaCuraExtraMultiplier = 1.4, -- Sofia Ribeiro
}

--------------------------------------------------------------------------------
-- BANDAGEM (server/UtilityItemSystem.lua)
--------------------------------------------------------------------------------
-- Cura com CANALIZAÇÃO, no espírito de Left 4 Dead: aciona a Tool, fica
-- "usando" por ChannelTime segundos tocando a animação, e SÓ NO FIM cura.
-- Tomar dano, desequipar ou morrer no meio CANCELA (não gasta a bandagem).

GameConfig.Bandagem = {
	Heal = 40, -- HP curado ao terminar (a passiva da Sofia multiplica por cima)
	ChannelTime = 3.5, -- segundos "usando" antes de curar
	CancelOnDamage = true, -- tomou dano no meio -> cancela (fiel ao L4D)
	CancelOnMove = false, -- true = andar cancela; false = pode andar (L4D2 deixa)
	MoveCancelDistance = 6, -- se CancelOnMove: quanto pode andar antes de cancelar

	-- Animação "Healing (L4D2)" reeditada e republicada na conta do dono.
	AnimationId = "rbxassetid://87240791271451",
	AnimationFadeTime = 0.2,
}

-- FÔLEGO: os números ficam em GameConfig.Characters (StaminaDrain/Regen), e
-- dependem do atributo Stamina do personagem. Quem executa é
-- server/StaminaSystem.lua -- AUTORITATIVO NO SERVIDOR. O StaminaSystem
-- client-side que vinha no pacote de movimento foi REMOVIDO (era 100%
-- cliente, dava pra correr pra sempre editando o valor).

--------------------------------------------------------------------------------
-- FEAR -- gameplay no servidor e apresentação local (partes 1, 2 e 3)
--------------------------------------------------------------------------------
GameConfig.Fear = {
	MaxFear = 100,
	MaxFearDistance = 300,
	MinFearDistance = 20,
	MaxProximityFearPerSecond = 10,
	ProximityCurveExponent = 2, -- smoothstep(t ^ expoente); maior = menos medo à distância
	FearRecoveryDelay = 4,
	BaseFearRecoveryPerSecond = 3.5,
	FearUpdateInterval = 0.2,
	-- Usa a Compostura EXISTENTE (0..100). Min/Max são os extremos do atributo.
	ComposureGain = { Min = 1.5, Max = 0.55 },
	ComposureGainExponent = 0.93, -- Compostura 50 fica em aproximadamente 1x
	ComposureRecovery = { Min = 0.65, Max = 1.35 },
	ComposureRecoveryExponent = 1,
	DebugMode = false, -- ative para ver [Fear] no Output do servidor
	DebugPrintInterval = 2, -- segundos; independente da frequência do cálculo
	LineOfSightMultiplier = 1.35,
	LineOfSightUpdateInterval = 0.4,
	ChaseDistance = 80,
	ChaseFearMultiplier = 1.4,
	ChaseMinSpeed = 2, -- velocidade horizontal real, studs/s, de ambos
	ChaseTowardDot = 0.35, -- monstro deve avançar na direção da vítima
	ChaseAwayDot = 0, -- vítima não pode estar avançando contra o monstro
	ChaseRequiresLineOfSight = true,
	ChaseConfirmTime = 0.6, -- evita classificar um movimento passageiro como perseguição
	MaxFearGainPerSecond = 20, -- teto DEPOIS de Compostura, LOS e Chase
	FearStates = { Nervous = 25, Scared = 50, Panicked = 75, ExtremePanic = 90 },
	StaminaPenaltyStartFear = 25,
	MinStaminaRegenMultiplier = 0.5,
	StaminaRegenCurveExponent = 1.5,
	TripMinFear = 75,
	TripCheckInterval = 3,
	TripCooldown = 8,
	TripChanceMin = 0.03,
	TripChanceMax = 0.12,
	TripDuration = 0.65,
	TripSpeedMultiplier = 0.55, -- limite temporário relativo ao ANDAR normal
	PanicSoundMinFear = 75,
	PanicSoundCheckInterval = 5,
	PanicSoundCooldown = 12,
	PanicSoundChanceMin = 0.02,
	PanicSoundChanceMax = 0.08,
	PanicSoundRadius = 100, -- alcance entregue ao SoundManager pelo hook existente
	PanicSounds = { "", "", "" }, -- apenas IDs reais; vazios não tocam
	PanicSoundVolume = 0.7,
	PanicSoundMaxDuration = 6,
	-- Parte 3: apresentação. Não altera as regras/valores de Fear do servidor.
	HeartbeatSoundId = "",
	HeartbeatStartFear = 30,
	HeartbeatMaxVolume = 0.45,
	HeartbeatMinPlaybackSpeed = 0.9,
	HeartbeatMaxPlaybackSpeed = 1.25,
	BreathingSoundId = "",
	BreathingStartFear = 45,
	BreathingMaxVolume = 0.35,
	BreathingMinPlaybackSpeed = 0.95,
	BreathingMaxPlaybackSpeed = 1.15,
	VignetteStartFear = 50,
	VignetteMaxFear = 100,
	VignetteMaxOpacity = 0.22,
	VignetteEdgeSize = 0.2, -- centro livre; fração da largura/altura de cada borda
	BlurStartFear = 75,
	BlurMaxSize = 4,
	EnableFearFOV = false, -- reservado: movimento/mira já controlam o tween de FOV
	FearFOVStart = 75,
	FearFOVMaxOffset = 3,
	PresentationUpdateInterval = 0.05,
	PresentationSmoothTime = 0.35,
	FearAnimations = { FearIdle = "", FearWalk = "", FearRun = "", LookAround = "", Trip = "" },
	FearLocomotionStart = 75,
	FearAnimationFadeTime = 0.15,
	FearAnimationLoadTimeout = 8,
	FearIdleSpeedThreshold = 0.75,
	FearInteractionGrace = 0.4, -- reserva curta para ações disparadas por ProximityPrompt
	LookAroundMinFear = 60,
	LookAroundCheckInterval = 6,
	LookAroundCooldown = 20,
	LookAroundChance = 0.06,
	LookAroundMaxDuration = 3,
}

--------------------------------------------------------------------------------
-- MONSTRO -- combate e locomoção
--------------------------------------------------------------------------------
-- MonsterCombat.lua valida o golpe, roteia dano pelo DamageSystem e publica
-- MonsterSpeedMul, lido pelo Crouching do pacote de movimento.
GameConfig.Monster = {
	-- Velocidade: multiplicador sobre a do Sobrevivente (andar 12 / sprint 23).
	SpeedMultiplier = 1.16, -- Monstro ~16% mais rápido -> alcança quem foge
	WeakenedSpeedMultiplier = 0.7, -- enquanto fraco pela luz (Zona Segura / Tocha)

	Attack = {
		Damage = 34, -- 3 golpes limpos matam um Sobrevivente de 100 HP
		Range = 9, -- alcance do golpe (studs, centro a centro)
		ConeCos = 0.35, -- cosseno do meio-ângulo (~69°): precisa MIRAR, não só estar perto
		Cooldown = 1.1, -- segundos entre golpes
		Knockback = 26, -- empurrão horizontal na vítima
		KnockbackUp = 8, -- componente vertical (tira o pé do chão de leve)
		LungeForce = 20, -- dash pra frente do PRÓPRIO Monstro ao golpear (0 = sem dash)
		WeakenedDamageMul = 0.45, -- golpe enfraquecido enquanto fraco pela luz
		MaxHitsPerSwing = 3, -- teto de vítimas por golpe (anti-abuso em aglomeração)
	},

	-- Animação de golpe (R6). 129967390 = "tool slash" padrão da Roblox,
	-- pública. Trocar por uma sua depois é só mudar aqui.
	SwingAnimationId = "rbxassetid://129967390",

	-- Shadow Rush: F / L1 / botão touch. Segundo toque inicia materialização.
	ShadowRush = {
		ShadowRushEnterDuration = 0.16,
		ShadowRushDuration = 5,
		ShadowRushMaxSpeed = 75,
		ShadowRushAcceleration = 0.28, -- aceleração, direção usa o controle normal
		ShadowRushExitDeceleration = 0.24,
		ShadowRushMaterializeDuration = 0.24,
		ShadowRushRecovery = 0.12, -- apenas combate; pode continuar andando
		ShadowRushCooldown = 25, -- contado a partir da ativação aceita
		ShadowRushSafetyTimeout = 10,
		ShadowPassDistance = 12,
		ShadowPassFear = 8, -- pontos finais; FearSystem.AddFear aplica o teto
		ShadowPassCooldown = 6, -- por vítima por ativação (padrão: uma vez)
		ShadowRushEnterSoundId = "",
		ShadowRushLoopSoundId = "",
		ShadowRushExitSoundId = "",
		ShadowPassSoundId = "",
		SoundMaxDistance = 90,
		SoundVolume = 0.65,
		FOVOffset = 24, -- 70 -> 94 (sprint normal já usa 90); mesmo dono de FOV
		InputInterval = 0.05,
		ServerInterval = 1 / 30,
		ReplicationSlack = 0.5, -- tolerância de rajadas na replicação física
		ValidationSpeedMargin = 1.2,
		CollisionRadius = 0.8, -- somente margem da borda da ilha
		MinGroundNormalY = 0.65,
		BoundsMargin = 6,
	},

	----------------------------------------------------------------------------
	-- TELEPORTE ("Fenda") -- server/MonsterTeleport.lua + client/MonsterTeleport
	-- Controller + Modules/RiftVFX.lua. Poder sobrenatural: abre uma fenda nos
	-- pés, é engolido, e emerge de uma segunda fenda no destino. TODOS os
	-- números de timing/escala/alcance/cooldown vivem aqui.
	----------------------------------------------------------------------------
	Teleport = {
		-- ALCANCE / DESTINO (servidor é autoridade -- o cliente só sugere um ponto)
		-- O destino é escolhido no MAPA (tecla Q), então o alcance cobre a ilha
		-- inteira: o limite real é o próprio mapa + as checagens de chão/rampa/
		-- água/limites/espaço livre. Baixe isto se quiser um teleporte curto.
		MaxRange = 2200, -- studs; distância máxima do salto
		MinRange = 18, -- não vale teleportar "em cima de si mesmo"
		GroundSnapUp = 60, -- raycast começa a esta altura acima do ponto mirado
		GroundSnapDown = 140, -- ...e desce até isto procurando chão
		MaxSlopeCos = 0.55, -- cos do ângulo máx. da rampa no destino (~57°)
		BoundsMargin = 30, -- fica pelo menos isto pra dentro da borda do mapa
		-- Medidas-base para escala 1. MonsterTeleport multiplica ambas pelo
		-- Model:GetScale() real (1.2 para o Monstro atual).
		ClearanceRadius = 2.6, -- meia-largura da checagem de "cabe o rig?"
		ClearanceHeight = 6.5, -- altura da checagem (rig R6 ~5.5)

		-- TIMINGS (segundos) -- ver a sequência no cabeçalho de MonsterTeleport.lua
		RiftOpenDuration = 1.1, -- fenda: pequena+invisível -> aberta
		EnterDuration = 0.85, -- monstro afunda + some
		TravelDuration = 0.55, -- "vazio" entre uma fenda e outra
		DestRiftLeadTime = 0.45, -- quanto a fenda do DESTINO abre ANTES do monstro sair
		ExitDuration = 1.0, -- monstro emerge + reaparece
		RiftCloseDuration = 0.85, -- fenda: aberta -> recolhida
		PostTeleportRecovery = 0.55, -- tonto: sem atacar/reativar logo após sair
		TeleportCooldown = 30, -- segundos até poder de novo
		FailureCooldown = 2.5, -- cooldown curto quando o destino é inválido (anti-spam)
		SafetyTimeout = 14, -- se algo travar, restaura tudo à força depois disto

		-- ESCALA (a fenda combina com o TAMANHO REAL do rig -- medido em runtime)
		RiftScale = 1.0, -- multiplicador extra por cima do automático
		RiftWidthFactor = 1.7, -- fenda ~1.7x a altura do monstro de largura
		SinkDepth = 7.0, -- quanto o monstro afunda ao ser engolido

		-- ORIENTAÇÃO DO ASSET (ver AssetRegistry.RiftTeleport.AssetId)
		-- "auto" mede o asset e deita a menor dimensão no chão. Se a fenda
		-- renderizar de lado/em pé, force "Y" | "Z" | "X" (qual eixo local é a
		-- "face" da fenda), ou mexa em RiftExtraRotationDeg.
		RiftAssetFaceAxis = "auto",
		RiftExtraRotationDeg = { 0, 0, 0 }, -- ajuste fino da rotação, em graus (X, Y, Z)
		RiftGroundOffset = -0.2, -- <0 crava a fenda um pouco no chão (nunca flutua)
		RiftUpright = false, -- true = fenda vertical virada pro monstro, em vez de deitada

		-- ANIMAÇÕES (opcionais). VAZIO = usa só o afundar+fade, que funciona em
		-- qualquer rig. Se tiver animações R6 próprias, cole o rbxassetid aqui.
		TeleportEnterAnimationId = "",
		TeleportExitAnimationId = "",

		-- REDE / PERFORMANCE
		VFXBroadcastRadius = 190, -- só clientes a até isto recebem os VFX da fenda
		RiftLightBrightness = 0.55, -- PointLight MUITO sutil (0 = sem luz)
		RiftLightRangeFactor = 1.6, -- Range da luz = largura da fenda * isto
	},
}

--------------------------------------------------------------------------------
-- PERSONAGENS JOGÁVEIS -- onde cada atributo VIRA número de jogo
--------------------------------------------------------------------------------
-- Os 7 atributos (0..100) de Modules/CharacterData.lua não fazem nada sozinhos:
-- Modules/StatScaling.lua converte cada um num multiplicador usando as faixas
-- abaixo, e CharacterStatsApplier.lua publica o resultado como Attribute no
-- Player. Os sistemas antigos só multiplicam pelo fator -- ninguém foi
-- reescrito.
--
-- COMO LER UMA FAIXA: {Min, Max} = o que o atributo 0 e o atributo 100 valem.
-- 50 cai no meio. Ex: DamageDealt = {0.6, 1.5} -> Força 10 causa 0.69x de
-- dano, Força 94 causa 1.45x.

GameConfig.Characters = {
	-- Velocidade -> WalkSpeed base (studs/s). O sprint do pacote de movimento
	-- escala junto, proporcional (é multiplicador, não valor fixo).
	-- Referência: o WalkSpeed "normal" do pacote é 12.
	WalkSpeed = { Min = 10, Max = 17 },
	ReferenceWalkSpeed = 12, -- CONFIG.NormalSpeed do script Crouching
	SprintSpeedRatio = 1.35, -- limiar real compartilhado por StaminaSystem e Fear (tropeço)

	-- Stamina -> duração do sprint. Gasto por segundo e recuperação por
	-- segundo (o valor de fôlego vai de 0 a 100).
	StaminaDrain = { Min = 26, Max = 11 }, -- INVERTIDO: Stamina alta gasta MENOS
	StaminaRegen = { Min = 9, Max = 22 },
	StaminaRegenDelay = 1.2, -- s parado de correr antes de começar a recuperar
	StaminaMinToSprint = 15, -- precisa disso pra (re)começar a correr depois de zerar

	-- Compostura -> vida máxima e dano ABSORVIDO.
	MaxHealth = { Min = 75, Max = 130 },
	DamageTaken = { Min = 1.35, Max = 0.7 }, -- INVERTIDO: Compostura alta toma menos

	-- Furtividade -> demora mais pra tensão subir fora de Zona Segura
	-- (multiplica GameConfig.Tension.TimeOutsideSafeZoneThreshold).
	StealthThreshold = { Min = 0.6, Max = 2.2 },

	-- Reparo -> progresso da Jangada e chance de sintonizar o Rádio.
	RepairSpeed = { Min = 0.55, Max = 1.6 },

	-- Força -> dano CAUSADO (corpo a corpo, arma de fogo) e empurrão.
	DamageDealt = { Min = 0.6, Max = 1.5 },

	-- Sorte -> loot das caixas (ver LootCrateSystem.lua): quantos itens saem
	-- e o peso da raridade.
	LootQuantity = { Min = 0.7, Max = 1.8 }, -- multiplica a qtd de rolagens
	LootRarity = { Min = 0.5, Max = 2.4 }, -- multiplica o peso dos itens raros
}

--------------------------------------------------------------------------------
-- CAIXAS DE LOOT (server/LootCrateSystem.lua)
--------------------------------------------------------------------------------
-- Caixas espalhadas pela ilha. Abrir sorteia itens; a SORTE do personagem
-- mexe em quantos saem (LootQuantity) e no peso dos raros (LootRarity).
-- Camila (Sorte 96) tira ~1.8x mais itens e ~2.3x mais chance de raro que
-- Kevin (Sorte 12).

GameConfig.LootCrates = {
	Count = 14, -- quantas caixas o sistema espalha pelo mapa
	SpreadRadius = 22, -- studs de dispersão ao redor de cada ponto sorteado
	BaseRolls = 2, -- rolagens base por caixa (antes do multiplicador de Sorte)
	OpenRange = 12, -- distância máxima pra abrir (validada no servidor)

	-- Peso base de cada raridade no sorteio. Sorte multiplica Media e Rara.
	RarityWeights = {
		Comum = 70,
		Media = 25,
		Rara = 5,
	},
}

--------------------------------------------------------------------------------
-- PAPÉIS (usar SEMPRE estas strings, nunca texto solto no código)
--------------------------------------------------------------------------------

GameConfig.Roles = {
	Survivor = "Sobrevivente",
	Monster = "Monstro",
	Spy = "Espiao", -- sem acento de propósito: evita dor de cabeça com encoding
}

--------------------------------------------------------------------------------
-- DURAÇÃO TOTAL DA PARTIDA
--------------------------------------------------------------------------------
-- Alvo de design: 8 a 12 minutos por partida.

GameConfig.Match = {
	DurationMin = 8 * MINUTE, -- 480s
	DurationMax = 12 * MINUTE, -- 720s
	DurationDefault = 10 * MINUTE + 30, -- 630s (soma das fases padrão abaixo)
}

--------------------------------------------------------------------------------
-- FASES DA PARTIDA
--------------------------------------------------------------------------------
-- ATENÇÃO: a soma dos `Default` das 4 fases deve ficar dentro da janela
-- Match.DurationMin .. Match.DurationMax.
--   Soma atual: 30 + 210 + 300 + 90 = 630s  (10min30s) -> OK
--   Se você usar todos os Max: 30 + 240 + 360 + 120 = 750s (12min30s) -> estoura
--   a janela. Nesse caso, aumente Match.DurationMax ou reduza algum Max.

GameConfig.Phases = {
	-- 1) Queda: jogadores caem/aterrissam na ilha. Tempo fixo, sem variação.
	Queda = {
		Min = 30,
		Max = 30,
		Default = 30,
	},

	-- 2) Exploração: procurar recursos, descobrir o mapa. (3 a 4 min)
	Exploracao = {
		Min = 3 * MINUTE, -- 180s
		Max = 4 * MINUTE, -- 240s
		Default = 210, -- 3min30s
	},

	-- 3) Corrida: correr para o objetivo/extração, pressão máxima. (4 a 6 min)
	Corrida = {
		Min = 4 * MINUTE, -- 240s
		Max = 6 * MINUTE, -- 360s
		Default = 5 * MINUTE, -- 300s
	},

	-- 4) Desfecho: resolução, revelação de papéis, placar. (1 a 2 min)
	Desfecho = {
		Min = 1 * MINUTE, -- 60s
		Max = 2 * MINUTE, -- 120s
		Default = 90, -- 1min30s
	},
}

-- Ordem em que as fases acontecem. Percorra esta lista no loop da partida
-- em vez de escrever a sequência na mão.
GameConfig.PhaseOrder = {
	"Queda",
	"Exploracao",
	"Corrida",
	"Desfecho",
}

--------------------------------------------------------------------------------
-- ESPIÃO
--------------------------------------------------------------------------------

GameConfig.Spy = {
	-- Sabotagem: habilidade de uso frequente (portas, luzes, geradores...).
	SabotageCooldownMin = 20,
	SabotageCooldownMax = 30,
	SabotageCooldownDefault = 25,

	-- Habilidade letal: uso raro, decide a partida. Cooldown fixo.
	LethalCooldown = 180, -- 3 min

	-- Reparo de sabotagem ("Fio Cortado"): tempo segurando o prompt
	-- "Reparar" -- é o que força o Sobrevivente a ficar parado ali (a
	-- "revisita" que a sabotagem existe pra causar).
	RepairHoldDuration = 3,
}

--------------------------------------------------------------------------------
-- EFEITOS DE STATUS
--------------------------------------------------------------------------------

GameConfig.Effects = {
	-- "Amarrado": jogador imobilizado até ser solto ou o tempo acabar.
	AmarradoDuration = 90, -- 1min30s
}

--------------------------------------------------------------------------------
-- FRAQUEZA DO MONSTRO À LUZ
--------------------------------------------------------------------------------
-- Aplicado quando o Monstro toca uma Zona Segura (Part com Attribute
-- "ZonaSegura" == true) ou chega perto de uma Tocha equipada por alguém.

GameConfig.MonsterWeakness = {
	-- Empurrão pra fora, aplicado a cada contato com a fonte de luz/zona.
	PushForce = 50, -- studs/s na direção horizontal, afastando da fonte
	PushUpwardForce = 10, -- pequeno impulso vertical, evita "grudar" no chão/parede

	-- Redução de velocidade enquanto fraco (soma-se durante a duração; não
	-- empilha se o Monstro continuar sendo tocado, só renova o tempo).
	WalkSpeedReduction = 10, -- quanto subtrair do WalkSpeed normal do Monstro
	WeakenDuration = 3, -- segundos que o efeito dura após o último contato

	-- Tocha (Tool): área de luz ao redor de quem a equipa.
	TorchRadius = 10, -- studs; distância pra também fraquejar o Monstro
	TorchLightRange = 10, -- Range do PointLight (visual; normalmente = TorchRadius)
	TorchLightBrightness = 2,
	TorchCheckInterval = 0.2, -- segundos entre verificações de proximidade da tocha
	TorchFuelDuration = 120, -- segundos de luz por Tocha (só drena equipada)

	-- Intervalo mínimo entre reforços do efeito de Zona Segura, pra não
	-- reaplicar o empurrão a cada frame enquanto o Monstro fica encostado.
	ZoneRetriggerInterval = 0.5,
}

--------------------------------------------------------------------------------
-- OBJETIVO: RÁDIO DE RESGATE
--------------------------------------------------------------------------------

GameConfig.RadioObjective = {
	-- Minigame de sintonia é só um sorteio por enquanto (sem UI ainda).
	SuccessChance = 0.6, -- 60% de chance de sucesso por tentativa

	-- Tempo de "aguentar" depois da sintonia bem-sucedida até vencer por
	-- resgate. A lógica de vitória em si (cancelar se alguém morrer, etc.)
	-- fica pra um futuro gerenciador de partida; aqui é só a duração base.
	RescueCountdownDuration = 15,
}

--------------------------------------------------------------------------------
-- OBJETIVO: JANGADA
--------------------------------------------------------------------------------

GameConfig.RaftObjective = {
	-- % de progresso ganho por material entregue em LocalJangada. Ajuste
	-- pra bater ~100% com a quantidade de materiais que você colocar no mapa.
	ProgressPerMaterial = 12,

	-- % extra de progresso por cada ajudante entregando material AO MESMO
	-- TEMPO (além de quem está entregando agora). Ex: 3 jogadores entregando
	-- juntos rendem mais progresso por entrega do que 1 sozinho.
	SimultaneousHelperBonus = 3,
}

--------------------------------------------------------------------------------
-- CONFRONTO (detectar / amarrar / executar)
--------------------------------------------------------------------------------

GameConfig.Confront = {
	-- Cristal Ancestral: alcance da leitura de suspeito.
	DetectRange = 12,

	-- Amarrar: ação cooperativa.
	TieRange = 10, -- alcance do ProximityPrompt "Amarrar"
	TieHelpersRequired = 2, -- quantos jogadores precisam agir juntos
	TieHoldDuration = 5, -- segundos de ação simultânea pra completar
	-- Por quanto tempo o "estou ajudando" de um jogador continua valendo
	-- depois que ele aciona o prompt. Precisa ser MAIOR que TieHoldDuration,
	-- senão a ajuda expira antes de a amarração completar.
	TieAssistWindow = 8,

	-- Arma Rara: alcance da execução.
	KillRange = 8,
}

-- Duração do efeito "amarrado" em si: GameConfig.Effects.AmarradoDuration.

--------------------------------------------------------------------------------
-- GERENCIAMENTO DE RODADA
--------------------------------------------------------------------------------

GameConfig.Round = {
	-- A contagem só corre com o mínimo de participantes e todos prontos.
	WaitingCountdown = 10,
	-- Monstro vence quando a quantidade de Sobreviventes VIVOS chega a este
	-- número (0 = precisa eliminar todos). Espião não conta como Sobrevivente.
	MonsterWinsAtSurvivorsAlive = 0,

	-- De quanto em quanto tempo o RoundManager checa as condições de vitória.
	WinCheckInterval = 1,

	-- Depois que a partida termina, quanto tempo esperar antes de
	-- teleportar todo mundo de volta pro Lobby (LobbyManager.lua).
	IntermissionDuration = 10,
}

--------------------------------------------------------------------------------
-- TENSÃO AMBIENTE (fora de Zona Segura)
--------------------------------------------------------------------------------

GameConfig.Tension = {
	-- Sobrevivente fora de qualquer Part "ZonaSegura" por mais que isso
	-- (segundos) começa a ouvir a tensão/batimento.
	TimeOutsideSafeZoneThreshold = 20,

	-- Depois de passar do limite acima, quanto tempo (segundos) até o
	-- volume ir de 0 até MaxVolume.
	RampUpDuration = 15,

	MaxVolume = 0.6,

	-- De quanto em quanto tempo o cliente reavalia a distância da zona.
	CheckInterval = 1,
}

--------------------------------------------------------------------------------
-- ARMAS FRACAS (Faca Improvisada, Lança de Bambu, Pedra Afiada)
--------------------------------------------------------------------------------
-- O empurrão no Monstro continua (juice). Além dele, se o *Damage abaixo for
-- > 0, a arma também tira vida de verdade pelo DamageSystem. Deixei tudo em 0
-- pra não mudar o balanço atual sem você pedir -- suba os números quando
-- quiser que essas armas machuquem/matem.

GameConfig.Weapons = {
	KnifeRange = 6, -- Faca Improvisada
	SpearRange = 10, -- Lança de Bambu (mais alcance que a faca)
	MeleePushForce = 35,

	KnifeDamage = 0, -- dano da Faca Improvisada por acerto (0 = só empurra)
	SpearDamage = 0, -- dano da Lança de Bambu por acerto
	RockDamage = 0, -- dano da Pedra Afiada no ponto de impacto (hoje nem mira alvo)

	-- Cosseno do meio-ângulo do cone de acerto à frente do jogador
	-- (0.5 = 60°, ou seja, cone total de 120°). Precisa mirar, não só
	-- estar perto de qualquer jeito.
	MeleeConeCos = 0.5,

	-- Pedra Afiada: distância do arremesso (na direção que o jogador olha).
	ThrowDistance = 25,
}

--------------------------------------------------------------------------------
-- ARMAS DE FOGO (hoje só a pistola)
--------------------------------------------------------------------------------
-- Os fuzis/shotgun foram REMOVIDOS de ReplicatedStorage/WeaponAssets/Tools --
-- o arquivo original com as 9 armas está em WeaponAssets_backup/ (fora da
-- árvore do Rojo), se um dia você quiser alguma de volta.
--
-- MUNIÇÃO: cada arma tem o PENTE (Settings/Config/Ammo, gasto a cada tiro) e
-- o jogador tem uma RESERVA por tipo de munição (AmmoSystem.lua no servidor,
-- guardada num Attribute do Player pra HUD ler). Recarregar puxa da reserva;
-- reserva zerada = não recarrega. Reserva só enche pegando caixas de munição
-- no chão.

GameConfig.Firearms = {
	-- Únicas armas que o jogo entrega/spawna. Precisa existir em
	-- ReplicatedStorage/WeaponAssets/Tools com o mesmo nome.
	Allowed = { "Glock17" },

	-- Nome da arma -> tipo de munição (a reserva é POR TIPO, não por arma).
	-- Uma Tool também pode trazer o Attribute "AmmoType" e ganhar deste mapa.
	AmmoTypes = {
		Glock17 = "Pistola",
	},
	DefaultAmmoType = "Pistola",

	-- Reserva por tipo de munição.
	StartingReserve = { Pistola = 34 }, -- teste: reserva inicial enquanto a pistola do lobby esta ativa
	MaxReserve = { Pistola = 68 }, -- teto que dá pra carregar (~4 pentes)
	PickupAmount = { Pistola = 17 }, -- quanto cada caixa no chão dá (1 pente)

	-- Quantas armas / caixas de munição o WeaponSpawner espalha pelo mapa.
	WorldSpawns = {
		Weapons = 5,
		AmmoBoxes = 10,
		SpreadRadius = 18, -- studs de dispersão ao redor de cada ponto-âncora
	},
}

--------------------------------------------------------------------------------
-- AMBIENTE / CLIMA
--------------------------------------------------------------------------------
-- Ver ReplicatedStorage/Modules/LightingPresets.lua pros valores de cada um.
-- "Night" fica salvo para voltar ao clima de jogo depois. "CloudyMorning"
-- está ativo agora para o Play nascer de dia enquanto depuramos mapa/gameplay.

GameConfig.Environment = {
	LightingPreset = "CloudyMorning",
}

--------------------------------------------------------------------------------
-- MODO DE TESTE (TEMPORÁRIO -- apagar quando for pra valer)
--------------------------------------------------------------------------------
-- Atalhos pra conseguir testar a partida sozinho no Studio. Nada disso
-- deveria sobreviver ao lançamento: com os três desligados, o jogo volta ao
-- comportamento de projeto (6-10 jogadores, papéis sorteados, mapa sem
-- itens de brinde no desembarque).

GameConfig.Testing = {
	-- Ignora o mínimo de GameConfig.Players.Min no prompt "IniciarPartida",
	-- deixando começar com 1 jogador só. O máximo continua valendo.
	SoloStart = true,

	-- Força TODO MUNDO nesse papel, em vez do sorteio normal
	-- (RoleAssignment.lua). nil = sorteio normal.
	--
	-- Em teste solo, nil sorteia entre Sobrevivente/Monstro/Espião para
	-- facilitar testar todos os fluxos sem abrir múltiplos clients.
	-- Troque pra "Monstro" ou "Espiao" se quiser forçar um papel específico.
	-- Atualmente fica nil para você testar o sorteio real, inclusive podendo
	-- cair como Jason/Monstro.
	ForceRole = nil,

	-- Painel dev dentro da sala de espera para escolher o papel da próxima
	-- partida sem depender da sorte. O servidor valida por UserId.
	DevRoleChooser = true,
	DevRoleUserIds = { 11555748600 } :: { number },

	-- Larga uma amostra de itens do lado de onde os jogadores desembarcam,
	-- pra dar pra testar pegar/usar item sem procurar pela ilha inteira.
	ItemsNearSpawn = true,

	-- Armas de fogo entregues no Backpack a cada spawn (FirearmServer).
	-- VAZIO = ninguém nasce armado, que é o certo: as armas ficam no CHÃO
	-- (WeaponSpawner.lua / GameConfig.Firearms.WorldSpawns).
	-- Pra depurar sem procurar arma no mapa, ponha { "Glock17" } aqui.
	GiveTestWeapons = { "Glock17" } :: { string },

	-- Bancada à direita do LobbySpawn: uma Glock17 e caixa de 34 cartuchos.
	-- Arma de treino só causa dano no alvo. false remove a bancada no próximo Play.
	LobbyPistol = true,

	-- Larga material de jangada suficiente pra fechar 100% ao lado da própria
	-- LocalJangada (RaftObjective.lua). Pra testar montar/empurrar a jangada
	-- sem catar Madeira/Corda/Lona pela ilha. false = tira o kit.
	RaftKit = true,
}

return GameConfig
