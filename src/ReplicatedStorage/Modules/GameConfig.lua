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
	Min = 2, -- 1 Monstro + 1 Sobrevivente; Espiao entra a partir de 3 jogadores
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
-- Os TRÊS estados de solo (andar / trotar / correr) são do script Crouching:
-- CONFIG.WalkSpeed, CONFIG.NormalSpeed e CONFIG.SprintSpeed. Aqui só ficam as
-- proporções que o servidor usa para reconhecê-los (Characters.MovementBands).

-- Super audição: raios em studs, intervalos em segundos.
--
-- COMO UM PASSO VIRA (OU NÃO VIRA) UM PING -- ver server/NoiseService.lua.
-- Não é "entrou no raio = aparece ping". São quatro camadas:
--
--   1. ESTADO DE MOVIMENTO. A velocidade horizontal REAL, dividida pela base
--      de caminhada do personagem, cai em uma das faixas de
--      GameConfig.Characters.MovementBands: Agachado < Andar < Trotar <
--      Correr. É medição física, não Attribute do cliente.
--
--   2. FURTIVIDADE. O atributo do personagem (0..100) escolhe ONDE, dentro
--      da faixa daquele estado, ficam o ALCANCE e o INTERVALO entre ruídos.
--      As faixas de States são INVERTIDAS de propósito (Min = o que vale com
--      Furtividade 0, Max = com Furtividade 100): quanto mais furtivo, MENOR
--      o alcance e MAIOR o intervalo. É isso que faz Furtividade valer de
--      verdade, e não ser número de vitrine.
--
--   3. SILÊNCIO. Alcance calculado abaixo de MinAudibleRadius = o ruído nem
--      é gerado (ver o comentário lá embaixo).
--
--   4. DISTÂNCIA. Mesmo dentro do alcance o ping pode não chegar, e a posição
--      chega embaralhada quanto mais longe o Monstro estiver (DistanceFalloff).
GameConfig.Noise = {
	Enabled = true,
	MinimumIntensity = 1,

	-- Se o alcance que a Furtividade produziu for menor que isto, o ruído é
	-- descartado na origem: ninguém ouve, nem um Monstro colado. É o que
	-- deixa Marina/Kevin (Furtividade 95) andarem de fato em silêncio, em
	-- vez de emitirem um ping de 8 studs que só apareceria num encontro que
	-- já aconteceu. Abaixe para tornar todo mundo um pouco mais audível.
	MinAudibleRadius = 10,

	-- UM ESTADO POR ENTRADA.
	--   Intensity = "altura" do som. Só ordena o quão grosso é o som e
	--               dimensiona a onda no visualizador; NÃO é o que a
	--               Furtividade mexe.
	--   Radius    = alcance máximo em studs {Furtividade 0, Furtividade 100}.
	--   Interval  = segundos entre um ruído e o próximo, do mesmo estado
	--               {Furtividade 0, Furtividade 100}.
	-- Referência de balanceamento (ilha de raio 560-820 studs): andando,
	-- 60-120 studs para quem é pouco furtivo; trotando, 180-280; correndo,
	-- 400-500, passando disso para Furtividade muito baixa.
	States = {
		-- Agachado e rastejando. Praticamente mudo já na metade da escala.
		Crouch = {
			Intensity = 1,
			Radius = { Min = 26, Max = 0 },
			Interval = { Min = 2.6, Max = 5 },
		},
		-- Andar: lento e de baixo risco. Furtividade alta anda em silêncio.
		Walk = {
			Intensity = 1,
			Radius = { Min = 120, Max = 2 },
			Interval = { Min = 1.6, Max = 4 },
		},
		-- Trotar: o movimento normal do personagem. Denuncia de longe quem
		-- não é furtivo e quase nada quem é.
		Jog = {
			Intensity = 2,
			Radius = { Min = 280, Max = 25 },
			Interval = { Min = 1, Max = 2.6 },
		},
		-- Correr: gasta fôlego E entrega a posição. Furtividade reduz muito,
		-- mas nunca zera -- correr sempre é um risco.
		Sprint = {
			Intensity = 3,
			Radius = { Min = 560, Max = 120 },
			Interval = { Min = 0.7, Max = 1.8 },
		},
	},

	-- DISTÂNCIA: quanto mais longe, menos frequente E menos confiável.
	-- t = distância do Monstro dividida pelo alcance daquele ruído (0 na
	-- origem, 1 na borda).
	DistanceFalloff = {
		-- Até esta fração do alcance o Monstro ouve sempre, na posição certa.
		ClearFraction = 0.35,
		-- Na borda do alcance, só esta fração dos ruídos chega.
		EdgeChance = 0.22,
		-- > 1 faz a perda acelerar perto da borda em vez de cair reto.
		Exponent = 1.6,
		-- Erro de posição do ping, em studs: o círculo marca a REGIÃO do
		-- barulho, não o jogador. Perto é quase exato; na borda é um palpite.
		NearSpread = 2,
		EdgeSpread = 34,
	},

	JumpIntensity = 2,
	LandingIntensity = 3,
	StoneIntensity = 4,
	PanicIntensity = 3,
	JumpNoiseRadius = 50,
	LandingNoiseRadius = 70,
	RadiusPerIntensity = 25, -- API genérica: intensidade * raio, limitado abaixo
	MaxNoiseRadius = 700, -- teto de tudo; precisa caber o alcance de corrida acima
	ActionPingInterval = 0.35, -- limite por fonte para ações, separado dos passos
	JumpPingInterval = 0.5,
	LandingPingInterval = 0.5,
	MinMovingSpeed = 0.75,
	MinLandingDrop = 4,
	MinAirTime = 0.2,
	MinJumpVerticalSpeed = 5,
	SpawnGrace = 0.5,

	-- Diagnóstico. Só serve pra DESENVOLVIMENTO -- deixe os dois false no jogo.
	Debug = {
		-- SÓ VALE NO STUDIO. O próprio sobrevivente que fez o barulho também
		-- recebe o ping. Existe porque teste solo cai em UM papel só
		-- (GameConfig.Testing.SoloStart + RoleAssignment): como Monstro não há
		-- sobrevivente pra fazer barulho, como Sobrevivente não há Monstro pra
		-- receber -- então com um cliente só NADA aparece, e o sistema parece
		-- quebrado mesmo estando certo. Com isto ligado dá pra validar a
		-- cadeia inteira correndo sozinho pela ilha.
		SelfHear = false,
		-- SÓ VALE NO STUDIO. Ignora o raio: todo Monstro ativo recebe o ping
		-- não importa a distância. A ilha tem 560-820 studs de raio de costa
		-- e o Monstro nasce sozinho numa caverna na montanha -- longe de
		-- qualquer ponto de spawn de Sobrevivente (POIs espalhados pelo
		-- mapa). Em teste com 2 jogadores soltos no mapa, a distância real
		-- passa fácil de 500+ studs: nenhum raio configurado (25 a 80 studs)
		-- alcança isso, e o Monstro nunca vê nada mesmo com tudo funcionando
		-- certo. Ligue isto pra validar o efeito sem perseguir o outro
		-- personagem pelo mapa inteiro primeiro.
		IgnoreRadius = false,
		-- Loga no Output cada ping entregue E cada descarte, com o motivo
		-- (sem partida, fora de alcance, intensidade baixa, sem Monstro vivo).
		Verbose = false,
	},

	Visual = {
		Duration = 0.9,
		SecondWaveDelay = 0.12,
		StartScale = 0.3,
		EndScale = 1.8,
		BaseSizePixels = 54,
		StartTransparency = 0.05,
		SecondWaveTransparency = 0.35,
		StrokeThickness = 3,
		HaloTransparency = 0.88, -- preenchimento: dá volume sem virar mancha
		-- Contorno escuro ATRÁS do claro. Sem ele um anel fino quase branco
		-- some em céu/areia/névoa -- era possível o efeito estar tocando e
		-- simplesmente não dar pra ver.
		ShadowThickness = 2,
		ShadowTransparency = 0.35,
		Color = { 195, 230, 238 },
		ShadowColor = { 8, 14, 20 },
		-- Margem em pixels fora da tela em que a onda ainda é desenhada, pra
		-- ela não sumir de uma vez quando o ponto passa pouquinho da borda.
		EdgeMarginPixels = 120,
		DisplayOrder = 80,
		ZIndex = 10,
		MaxActivePings = 24,
	},
}

--------------------------------------------------------------------------------
-- VIDA / DANO
--------------------------------------------------------------------------------
-- DamageSystem.lua (servidor) é a porta ÚNICA de dano/cura: quem quiser tirar
-- vida chama DamageSystem.Apply em vez de mexer no Humanoid direto. A barra de
-- vida (StarterGui/Ui, do pacote de movimento) só lê Humanoid.Health/MaxHealth.

GameConfig.Health = {
	Max = 100, -- MaxHealth aplicado ao Humanoid no spawn

	-- Reações de combate são tocadas pelo SERVIDOR. Assim vítima, Monstro e
	-- espectadores veem a mesma animação, sem depender do HealthChanged local.
	HurtIdleAnimationId = "rbxassetid://96462680767143",
	HurtWalkAnimationId = "rbxassetid://123093322235597",
	DeathAnimationId = "rbxassetid://136002279138060",
	HurtAnimationDuration = 0.55,

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

	-- Grab: E / ButtonX. O servidor escolhe a vitima, alinha os rigs e usa os
	-- markers da animacao para matar, soltar e encerrar a execucao.
	Grab = {
		InputKey = Enum.KeyCode.E,
		GamepadKey = Enum.KeyCode.ButtonX,
		GrabRange = 8,
		GrabAngle = 80, -- abertura total do cone, em graus
		GrabCooldown = 8,
		MaxVerticalDifference = 6,

		-- CFrame da HumanoidRootPart da vitima no espaco local da HRP do
		-- monstro. Este e o unico ajuste necessario para casar os dois rigs com
		-- a posicao usada no Moon Animator.
		VictimOffset = CFrame.new(0, -0.600012, -3.099976) * CFrame.Angles(0, math.rad(180), 0),
		AlignDuration = 0.14,
		AnimationFadeTime = 0.08,
		AttemptFallbackDuration = 1.1,
		SafetyTimeout = 15,

		AnimationIds = {
			GrabAttempt = "",
			Grab = "rbxassetid://92358246972820",
			VictimGrab = "", -- opcional; deixe vazio se ainda nao exportou
		},
	},

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
	ReferenceWalkSpeed = 12, -- CONFIG.NormalSpeed do script Crouching (= ANDAR, o padrão)
	SprintSpeedRatio = 1.35, -- limiar real compartilhado por StaminaSystem e Fear (tropeço)

	-- CLASSIFICAÇÃO ACÚSTICA DO MOVIMENTO (server/NoiseService).
	-- A velocidade horizontal real dividida pela base de caminhada do
	-- personagem cai em uma destas faixas. Os números saem das velocidades do
	-- script Crouching divididas por NormalSpeed = 12:
	--     rastejar  3/12 = 0,25 | agachar 6/12 = 0,50
	--     ANDAR    12/12 = 1,00 | TROTAR 15/12 = 1,25 | CORRER 23/12 = 1,92
	-- ANDAR é o padrão (ninguém segura nada); TROTAR liga segurando Control;
	-- CORRER segurando Shift. Por serem proporções, valem igual para quem tem
	-- SpeedMul alto ou baixo. Exemplo real: Rafael trotando faz ~21 studs/s,
	-- o que já passa do limiar de CORRIDA de Diego (12,1 x 1,35 = 16,3) --
	-- e ainda assim é trote, porque cada personagem é medido pela própria
	-- base. Analógico meio inclinado cai numa faixa mais baixa e fica mais
	-- silencioso; isso é proposital.
	-- Se mudar as velocidades do Crouching, revise estes dois limiares.
	MovementBands = {
		Crouch = 0.58, -- até aqui: agachado ou rastejando
		Walk = 1.15, -- até aqui: ANDAR (padrão, ratio 1,00 cabe com folga)
		-- O teto do trote é o próprio SprintSpeedRatio acima (1,35): TROTAR
		-- (ratio 1,25) cabe com folga antes dele -- um único limiar de
		-- corrida, compartilhado com a stamina e com o tropeço do medo.
	},

	-- Stamina -> duração do sprint. Gasto por segundo e recuperação por
	-- segundo (o valor de fôlego vai de 0 a 100).
	-- Dura aproximadamente 24% mais que antes (sem mudar a velocidade da corrida).
	StaminaDrain = { Min = 21, Max = 9 }, -- INVERTIDO: Stamina alta gasta MENOS
	StaminaRegen = { Min = 9, Max = 22 },
	StaminaRegenDelay = 1.2, -- s parado de correr antes de começar a recuperar
	StaminaMinToSprint = 15, -- precisa disso pra (re)começar a correr depois de zerar

	-- Compostura -> vida máxima e dano ABSORVIDO.
	MaxHealth = { Min = 75, Max = 130 },
	DamageTaken = { Min = 1.35, Max = 0.7 }, -- INVERTIDO: Compostura alta toma menos

	-- Furtividade -> demora mais pra tensão subir fora de Zona Segura
	-- (multiplica GameConfig.Tension.TimeOutsideSafeZoneThreshold).
	StealthThreshold = { Min = 0.6, Max = 2.2 },
	-- Furtividade também decide o ALCANCE e a FREQUÊNCIA de cada ruído de
	-- passo que o Monstro escuta. Os números ficam por estado de movimento em
	-- GameConfig.Noise.States, e a conta é StatScaling.NoiseRadius /
	-- StatScaling.NoisePingInterval.

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
-- DESCOBERTA DE ITENS NO MAPA (server/ItemDiscovery.lua)
--------------------------------------------------------------------------------
-- Passar perto de um item do mundo (arma, material, caixa de loot...) marca
-- ele PARA SEMPRE no mapa (Q do Monstro / M do Sobrevivente-Espião) daquele
-- jogador -- é por partida, não persiste entre rodadas (o mapa de itens muda
-- a cada sorteio). Sem exigir linha de visão: só distância.

GameConfig.MapDiscovery = {
	Enabled = true,
	Radius = 14, -- studs; ItemSpawner/WeaponSpawner/LootCrateSystem usam raios parecidos pra pickup
	ScanInterval = 0.5, -- segundos entre varreduras de proximidade
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

	-- Tempo entre o pedido de socorro sair e o helicóptero POUSAR na praia.
	-- Não é mais "espere X e ganhe": é o tempo que os Sobreviventes têm pra
	-- atravessar a ilha até a zona de extração (server/ExtractionSystem.lua).
	-- 120s dá pra cruzar o mapa (diâmetro jogável ~1400-1600) correndo, com
	-- o Monstro sabendo exatamente pra onde todo mundo está indo.
	RescueCountdownDuration = 120,
}

--------------------------------------------------------------------------------
-- EXTRAÇÃO (helicóptero na praia)
--------------------------------------------------------------------------------
-- Fim da linha do objetivo do Rádio. Quando o pedido de socorro é enviado,
-- server/ExtractionSystem.lua acende uma zona na praia com fumaça vermelha e
-- começa a contagem. Chegar lá ANTES do pouso não vale nada -- o Monstro
-- ainda mata. Só depois que o helicóptero pousa é que entrar na zona salva.

GameConfig.Extraction = {
	-- Raio da zona de pouso (studs). Generoso: é pra caber o helicóptero e
	-- alguém correndo em pânico, não pra exigir precisão.
	Raio = 18,

	-- MODELO do helicóptero (Toolbox). Se não carregar, entra a versão em
	-- Parts primitivas -- o sistema funciona igual nos dois casos.
	ModeloId = 8915950341,

	-- Comprimento alvo do modelo em studs (o Toolbox não segue escala
	-- nenhuma, então normalizo pelo maior lado).
	ComprimentoModelo = 34,

	-- Correção de guinada do modelo, em GRAUS. Todo asset decide sozinho pra
	-- que lado é "frente"; o voo orienta o modelo com CFrame.lookAt, que
	-- assume frente = -Z. Se o helicóptero voar de lado ou de ré, ajuste
	-- aqui (90 / 180 / 270) -- é o único lugar que precisa mudar.
	GuinadaModelo = 0,

	-- VOO DE CHEGADA (segundos). O tempo é dividido entre aproximação,
	-- flare (levantar o nariz pra frear) e descida vertical.
	DuracaoChegada = 11,
	DuracaoPartida = 9,

	-- De onde ele vem: distância horizontal e altura do ponto de entrada.
	DistanciaEntrada = 420,
	AlturaEntrada = 210,

	-- Altura em que ele para de avançar e passa a descer reto (o "flare").
	AlturaFlare = 34,

	-- Altura do ponto de pouso acima do chão da pista (patins tocando).
	AlturaPouso = 0.6,

	-- Inclinações do voo, em graus: nariz baixo acelerando, nariz alto
	-- freando, e o quanto inclina na curva de aproximação.
	PicoNarizBaixo = 12,
	PicoNarizAlto = 16,
	PicoRolagem = 14,

	-- Rotor: voltas por segundo. Alto o bastante pra virar borrão.
	RotorRPS = 4.5,

	-- Com que frequência o servidor confere quem está dentro da zona.
	-- (O VOO é atualizado todo frame, à parte -- senão fica travado.)
	IntervaloChecagem = 0.25,
}

--------------------------------------------------------------------------------
-- OBJETIVO: ESTAÇÃO DE RÁDIO (o local físico)
--------------------------------------------------------------------------------
-- A corrente de interações do sítio da torre, na ordem em que o jogador faz:
--   peças -> combustível -> fusível -> ligar gerador -> painel -> socorro.
-- Quem executa é server/RadioSiteSystem.lua; quem constrói o local é
-- Tools/RadioTowerGenerator.lua. Ver docs/Radio.md.

GameConfig.RadioSite = {
	-- Segurar o prompt (segundos). Quanto maior, mais tempo parado = mais
	-- exposto. É o principal botão de tensão do objetivo.
	HoldAbastecer = 4,
	HoldFusivel = 3,
	HoldPartida = 2.5,
	HoldPainel = 4,

	-- Chamado de socorro: canalização longa, cancelada se sair de perto,
	-- morrer, o gerador parar ou alguém sabotar.
	SinalDuracao = 14,
	SinalRaio = 9, -- distância máxima do console durante a canalização
	SinalDecaimento = 6, -- % por segundo que o progresso cai se interromper

	-- Gerador: cada galão rende este tanto de tempo ligado (segundos).
	-- 3 galões fixos no local = ~4,5 min de energia se ninguém desperdiçar.
	-- MESMO valor vale pro item "Gasolina" (ItemRegistry) achado pelo mapa e
	-- carregado como Tool -- RadioSiteSystem.onRefuel aceita as duas fontes,
	-- preferindo a Gasolina carregada.
	CombustivelPorGalao = 90,
	CombustivelMaximo = 270,

	-- Enquanto roda, o gerador faz barulho: dispara WeaponSystem.NoiseMade
	-- neste intervalo (segundos) pra quem quiser reagir ao ruído, e avisa o
	-- Monstro por mensagem.
	IntervaloRuido = 12,

	-- Distância máxima do jogador até o ponto de interação (o prompt já
	-- limita, isto é a checagem do servidor).
	AlcanceInteracao = 12,

	-- "Conserto Relâmpago" (SurvivorPowerSystem): empurrão instantâneo, em
	-- pontos percentuais, no chamado de socorro -- só funciona em quem ESTÁ
	-- transmitindo agora. É o único passo da corrente com barra contínua;
	-- os outros (abastecer, fusível, partida, painel) são "segurou o prompt
	-- ou não", não tem o que acelerar.
	PowerBoostPercent = 25,
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

	-- Amarrar: ação cooperativa. Usa X / ButtonB para não disputar E /
	-- ButtonX com o Grab do Monstro quando ele está perto de outro jogador.
	TieInputKey = Enum.KeyCode.X,
	TieGamepadKey = Enum.KeyCode.ButtonB,
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
-- DIGITAL'S OTS PATCH2 (somente Glock17)
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

	-- Força o papel apenas em teste solo. Em partida com 2+ jogadores,
	-- RoleAssignment sempre sorteia exatamente 1 Monstro.
	-- nil = sorteio normal.
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

	-- Armas do OTS entregues no Backpack a cada spawn (OTSFirearmService).
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
