--!strict
--[[
	MenuConfig
	CONFIGURAÇÃO CENTRAL DA TELA INICIAL. É o único arquivo que você precisa
	abrir para trocar textos, cores, tempos, sons, logo, fundo e a cena 3D.
	Nenhum outro módulo do menu tem número mágico ou ID solto.

	>>> ONDE TROCAR CADA COISA <<<
	  LOGO .............. Brand.LogoImage        (vazio = usa o texto do título)
	  IMAGEM DE FUNDO ... Background.Image       (vazio = usa a cena 3D)
	  MÚSICA ............ Sounds.Music
	  SONS DOS BOTÕES ... Sounds.Hover / Click / Back / Start
	  MODELO DO MONSTRO . Scene.MonsterSources   (lista de caminhos tentados)
	  ANIMAÇÃO .......... Scene.MonsterAnimationId
	  CÂMERA/CENÁRIO .... Scene.Camera* e Scene.Set*

	REGRA DOS IDS: campo vazio ("") = desligado, em silêncio, sem erro. Nenhum
	ID foi inventado -- os padrões abaixo são sons embutidos da própria Roblox
	(rbxasset://), que existem em qualquer experiência. Para usar um upload
	seu, cole "rbxassetid://SEU_ID".
]]

local Config = {}

--------------------------------------------------------------------------------
-- MARCA
--------------------------------------------------------------------------------
Config.Brand = {
	Title = "NÁUFRAGOS", -- aparece grande quando não há logo
	Subtitle = "SOBREVIVA À ILHA",
	-- TROQUE AQUI PELA SUA LOGO: "rbxassetid://0000000000".
	-- Vazio = o título em texto é usado (fica bonito do mesmo jeito).
	LogoImage = "",
	LogoAspectRatio = 3.2, -- largura / altura da sua arte de logo
	LogoHeightScale = 0.17, -- fração da altura da tela
	Version = "v0.1 · pré-alpha",
}

--------------------------------------------------------------------------------
-- CARREGAMENTO -- pedido: o mais rápido possível, ~3 s
--------------------------------------------------------------------------------
Config.Loading = {
	Enabled = true,
	-- Segura a tela por no MÍNIMO isto, mesmo que o jogo carregue antes
	-- (senão a tela pisca e some, o que fica pior do que não ter).
	MinSeconds = 0.9,
	-- E solta no MÁXIMO aqui, mesmo se o jogo ainda estiver carregando.
	MaxSeconds = 3,
	Text = "PREPARANDO A ILHA",
	-- Frases que giram na tela de carregamento. Vazio = só o texto acima.
	Tips = {
		"A lanterna atrai o Monstro tanto quanto afasta o escuro.",
		"Compostura alta segura o medo por mais tempo.",
		"Em pânico você perde o mapa e o fôlego na tela.",
		"O rádio é a saída mais rápida da ilha.",
	},
	TipInterval = 1.1,
}

--------------------------------------------------------------------------------
-- FLUXO
--------------------------------------------------------------------------------
Config.Flow = {
	-- false = o menu nunca mais aparece nesta sessão depois de fechado
	-- (respawn e morte NÃO trazem ele de volta). true = volta ao morrer.
	ReopenOnRespawn = false,
	-- Trava o movimento enquanto o menu está aberto, pelo ControlModule
	-- oficial (mesmo caminho que o RoleRevealController usa).
	LockControls = true,
	-- Esconde chat/lista de jogadores enquanto o menu está aberto.
	HideCoreGui = true,
	PressAnyKeyText = "CLIQUE OU PRESSIONE QUALQUER TECLA",
	PressAnyKeyPulse = 1.4, -- segundos de um ciclo do brilho
}

--------------------------------------------------------------------------------
-- TEMPOS E CURVAS (tudo via TweenService)
--------------------------------------------------------------------------------
Config.Motion = {
	ScreenFade = 0.55, -- troca entre telas
	PanelSlide = 0.35, -- entrada dos painéis
	ButtonHover = 0.16,
	ButtonPress = 0.08,
	StartFade = 0.9, -- saída da tela "clique para começar"
	PlayFade = 0.75, -- saída do menu ao clicar em Jogar
	Easing = Enum.EasingStyle.Quint,
	Direction = Enum.EasingDirection.Out,
	-- Trava anti-clique-duplo: nenhum botão responde enquanto uma transição
	-- estiver rodando, e este é o respiro extra depois dela.
	InputLockPadding = 0.05,
}

--------------------------------------------------------------------------------
-- PALETA -- preto, cinza e vermelho escuro
--------------------------------------------------------------------------------
Config.Palette = {
	Background = Color3.fromRGB(6, 6, 8),
	Panel = Color3.fromRGB(13, 13, 16),
	PanelStroke = Color3.fromRGB(46, 46, 54),
	Text = Color3.fromRGB(226, 226, 230),
	TextDim = Color3.fromRGB(138, 138, 148),
	Accent = Color3.fromRGB(150, 26, 26), -- vermelho escuro
	AccentBright = Color3.fromRGB(206, 48, 40),
	Danger = Color3.fromRGB(120, 30, 28),
	Highlight = Color3.fromRGB(255, 255, 255),
}

Config.Fonts = {
	Display = Enum.Font.GothamBlack, -- título/logo
	Button = Enum.Font.GothamBold,
	Body = Enum.Font.GothamMedium,
}

--------------------------------------------------------------------------------
-- FUNDO 2D (opcional). Se você colar uma imagem aqui ela entra ATRÁS da
-- interface e por cima da cena 3D. Vazio = a cena 3D aparece limpa.
--------------------------------------------------------------------------------
Config.Background = {
	Image = "", -- TROQUE AQUI: "rbxassetid://0000000000"
	ImageTransparency = 0.15,
	-- Vinheta desenhada em código (não precisa de arte).
	VignetteOpacity = 0.55,
	VignetteSize = 0.34,
	-- Escurecimento geral por cima da cena, pra UI ficar legível.
	Scrim = 0.28,
}

--------------------------------------------------------------------------------
-- SONS -- todos trocáveis, vazio = silêncio
--------------------------------------------------------------------------------
Config.Sounds = {
	-- TROQUE AQUI PELA SUA TRILHA: "rbxassetid://SEU_ID".
	-- Deixado VAZIO de propósito: não invento ID de música.
	Music = "",
	MusicVolume = 0.35,
	MusicFade = 2.5,
	-- Sons embutidos da Roblox: existem sempre, e são só placeholders.
	Hover = "rbxasset://sounds/volume_slider.ogg",
	HoverVolume = 0.12,
	Click = "rbxasset://sounds/electronicpingshort.wav",
	ClickVolume = 0.22,
	Back = "rbxasset://sounds/volume_slider.ogg",
	BackVolume = 0.16,
	Start = "rbxasset://sounds/impact_water.mp3",
	StartVolume = 0.4,
	StartPlaybackSpeed = 0.7,
}

--------------------------------------------------------------------------------
-- CENA 3D DE FUNDO
-- Fica em MenuScene.lua, separada da lógica do menu: dá pra trocar modelo,
-- cenário, câmera e animação sem encostar em MenuScreens.lua.
--
-- A cena inteira é LOCAL (criada só no cliente): nenhum outro jogador vê, e
-- nada dela replica para o servidor.
--------------------------------------------------------------------------------
Config.Scene = {
	Enabled = true,
	-- Longe de tudo: a ilha ocupa |x|,|z| <= 960 e o lobby fica em z = -1500.
	Origin = Vector3.new(0, 6000, -9000),
	-- A cena é montada DENTRO de uma caixa escura fechada, então o céu e o
	-- ClockTime do jogo não a iluminam -- assim o menu fica noturno sem
	-- alterar o Lighting global (que é compartilhado com o gameplay).
	SetSize = Vector3.new(150, 60, 150),
	-- Cores mais claras que puro preto: paredes/chão/props quase pretos
	-- absorvem quase toda a luz das PointLight (não refletem quase nada),
	-- então a cena inteira ficava escura demais mesmo com as luzes acesas.
	SetColor = Color3.fromRGB(30, 32, 36),
	FloorColor = Color3.fromRGB(42, 38, 34),
	FloorMaterial = Enum.Material.Ground,
	-- Silhuetas de árvore/pedra ao fundo. Mexa à vontade.
	PropCount = 14,
	PropColor = Color3.fromRGB(28, 29, 32),

	-- MODELO DO MONSTRO ----------------------------------------------------
	-- Tenta cada caminho nesta ordem e clona o primeiro que existir. Se
	-- nenhum existir, monta uma silhueta provisória com Parts.
	-- TROQUE AQUI pelo seu modelo: basta pôr o caminho dele no topo da lista.
	MonsterSources = {
		"ReplicatedStorage/MenuMonster",
		"Workspace/R6 Monster",
	},
	-- Perto o bastante para dominar o enquadramento, como o Jason parado no
	-- menu do F13 -- mas sem entrar dentro do plano da câmera (near clip).
	MonsterOffset = Vector3.new(2, 0, -3), -- à direita do centro, bem perto
	MonsterFacing = 200, -- graus; para onde ele olha
	MonsterScale = 1.2,
	-- ANIMAÇÃO: cole o id de uma Animation sua para o monstro do menu.
	-- Vazio = usa a respiração procedural abaixo (sobe/desce + balanço),
	-- que funciona em QUALQUER modelo, inclusive sem Humanoid.
	MonsterAnimationId = "",
	BreathHeight = 0.13, -- studs de sobe e desce
	BreathSpeed = 0.42, -- ciclos por segundo
	SwayDegrees = 1.1, -- balanço lateral
	SwaySpeed = 0.17,

	-- CÂMERA ---------------------------------------------------------------
	CameraOffset = Vector3.new(-2, 3.6, 4), -- posição relativa à Origin
	CameraLookAt = Vector3.new(1.6, 2.8, -3), -- mira a altura do peito/rosto dele
	CameraFieldOfView = 58,
	-- Movimento cinematográfico lento: uma deriva suave, sem enjoar.
	CameraDriftRadius = 1.35,
	CameraDriftSpeed = 0.055,
	CameraBreath = 0.16,

	-- CLIMA ----------------------------------------------------------------
	Fog = true,
	Rain = true,
	Embers = true, -- folhas/cinzas subindo
	KeyLightColor = Color3.fromRGB(150, 170, 200), -- luz fria de lua
	KeyLightBrightness = 5,
	KeyLightRange = 140, -- cobre o baú de 150x150 studs de ponta a ponta
	RimLightColor = Color3.fromRGB(180, 40, 30), -- contraluz vermelha no monstro
	RimLightBrightness = 6,
	RimLightRange = 45,
	-- Efeitos presos à CÂMERA (não ao Lighting): somem junto com o menu.
	ColorTint = Color3.fromRGB(196, 206, 226),
	ColorContrast = 0.05, -- contraste alto esmagava as sombras pra preto puro
	ColorSaturation = -0.2,
	ColorBrightness = 0.1,
	BlurSize = 8, -- desfoque de fundo; some quando a cena entra
}

--------------------------------------------------------------------------------
-- BOTÕES DO MENU PRINCIPAL
-- id = usado pelo código; label = o que o jogador lê.
-- "soon = true" abre um painel provisório "Em breve" já navegável.
--------------------------------------------------------------------------------
Config.MainButtons = {
	{ id = "Play", label = "JOGAR", primary = true },
	{ id = "Characters", label = "PERSONAGENS", soon = true,
		blurb = "Fichas, atributos, skins e perks dos sobreviventes." },
	{ id = "Shop", label = "LOJA", soon = true,
		blurb = "Skins, perks e itens cosméticos." },
	{ id = "Inventory", label = "INVENTÁRIO", soon = true,
		blurb = "O que você carrega entre as partidas." },
	{ id = "Settings", label = "CONFIGURAÇÕES", soon = true,
		blurb = "Gráficos, áudio, sensibilidade e controles." },
	{ id = "Credits", label = "CRÉDITOS", soon = true,
		blurb = "Quem fez, e com o quê." },
	-- Sair: a Roblox não tem "fechar o jogo" pela API. O que dá para fazer é
	-- desconectar o jogador do servidor (Player:Kick). Deixe false para
	-- esconder o botão.
	{ id = "Quit", label = "SAIR", quit = true },
}

Config.ShowQuitButton = true

--------------------------------------------------------------------------------
-- ACESSO RÁPIDO (SÓ PARA VOCÊ)
-- Um botão extra que entra na fila, escolhe o papel e marca Pronto de uma vez,
-- sem andar até o pilar e sem passar pela seleção de personagem.
--
-- NÃO É UM SISTEMA NOVO: usa o Testing.DevRoleChooser que JÁ existe em
-- GameConfig, e quem valida o UserId continua sendo o servidor
-- (WaitingRoomManager.isDevRoleTester). Se o seu id não estiver em
-- GameConfig.Testing.DevRoleUserIds, o botão nem aparece -- e se alguém
-- forjar o pedido, o servidor entra na fila normalmente e ignora o papel.
--------------------------------------------------------------------------------
Config.QuickPlay = {
	Enabled = true,
	Label = "ACESSO RÁPIDO",
	Hint = "Entra na fila, escolhe o papel e marca pronto de uma vez.",
	Options = {
		{ id = "Survivor", label = "SOBREVIVENTE" },
		{ id = "Monster", label = "MONSTRO" },
		{ id = "Spy", label = "ESPIÃO" },
		{ id = "Random", label = "ALEATÓRIO" },
	},
	-- Escolhe sozinho o primeiro personagem livre do roster, para não parar
	-- na tela de seleção. false = você escolhe o personagem normalmente.
	AutoPickCharacter = true,
	-- Marca Pronto sozinho depois de entrar (dispara a contagem).
	AutoReady = true,
	-- Tempo máximo esperando o servidor confirmar cada passo.
	StepTimeout = 4,
}

--------------------------------------------------------------------------------
-- Helper de ID de asset. Espelha FearPresentationRules.AssetId, MAS é copiado
-- aqui de propósito: este módulo vive em ReplicatedFirst e roda ANTES de
-- ReplicatedStorage terminar de replicar -- não dá para depender de lá no topo.
--------------------------------------------------------------------------------
function Config.AssetId(value: unknown): string?
	if type(value) ~= "string" or value == "" then return nil end
	local text = value :: string
	if string.sub(text, 1, 11) == "rbxasset://" then return text end
	local digits = string.match(text, "^rbxassetid://(%d+)$") or string.match(text, "^(%d+)$")
	if not digits or (tonumber(digits) or 0) <= 0 then return nil end
	return "rbxassetid://" .. digits
end

return Config
