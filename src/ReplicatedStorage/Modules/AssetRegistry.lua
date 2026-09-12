--!strict
--[[
	AssetRegistry
	Registro central: nome lógico -> asset real (ou placeholder), pro resto
	do código nunca precisar saber "o que é" cada coisa hoje.

	POR QUE ISSO EXISTE
	  Sem isto, "o Monstro é um torso preto 1.5x maior" ficaria escrito
	  dentro da lógica de AppearanceManager, e "a Tocha é reconhecida pelo
	  Attribute 'Tocha'" ficaria espalhado em cada script que precisa achar
	  uma Tocha. Trocar qualquer um desses detalhes viraria uma busca por
	  todo o código. Aqui, cada nome lógico tem UMA entrada; quem consome
	  (AppearanceManager, ConfrontSystem, MonsterLightWeakness) só pergunta
	  "o que é o Monstro_Modelo hoje" e aplica o que vier.

	MODELOS 3D (ex: Monstro_Modelo)
	  MeshId: rbxassetid de um SpecialMesh, quando você tiver um modelo
	  pronto. Vazio ("") = ainda não existe, usa o campo Placeholder.
	  Quando preencher o MeshId, NADA na lógica que consome precisa mudar.

	TOOLS (Tocha_Item, CristalAncestral_Modelo, ArmaRara_Item)
	  Essas Tools ainda são colocadas manualmente no Studio (não são
	  clonadas por script), então não têm "modelo" pra registrar -- o que
	  existe hoje é só o nome do Attribute usado pelos scripts pra
	  reconhecer qual Tool é qual. Ainda assim ficam aqui: se um dia o
	  Attribute mudar de nome, ou a Tool virar um template clonável, é uma
	  linha só pra trocar, não uma busca em ConfrontSystem/MonsterLightWeakness.

	Uso:
		local AssetRegistry = require(game.ReplicatedStorage.Modules.AssetRegistry)
		local monster = AssetRegistry.Monstro_Modelo
]]

local AssetRegistry = {}

AssetRegistry.Monstro_Modelo = {
	-- rbxassetid de um SpecialMesh pro torso, quando existir. Vazio = usa
	-- o Placeholder abaixo.
	MeshId = "",

	-- Vale nos dois casos (com ou sem MeshId real).
	-- O StarterCharacter e R6 para todos. AppearanceManager aplica este valor
	-- ao Model inteiro (parts + offsets dos joints), somente no Monstro.
	ScaleMultiplier = 1.2,

	-- Fallback enquanto MeshId estiver vazio.
	Placeholder = {
		TorsoColor = Color3.new(0, 0, 0),
	},
}

AssetRegistry.Tocha_Item = {
	-- Nome do Attribute que identifica a Tool "Tocha" no mundo.
	-- Usado por MonsterLightWeakness.lua (Parte "Tocha").
	AttributeName = "Tocha",
}

AssetRegistry.CristalAncestral_Modelo = {
	-- Usado por ConfrontSystem.lua (Parte 1 -- Detectar).
	AttributeName = "CristalAncestral",
}

AssetRegistry.ArmaRara_Item = {
	-- Usado por ConfrontSystem.lua (Parte 3 -- Executar).
	AttributeName = "ArmaRara",
}

--------------------------------------------------------------------------------
-- FENDA DO TELEPORTE DO MONSTRO
--------------------------------------------------------------------------------
-- server/MonsterTeleport.lua carrega o AssetId UMA vez no boot (InsertService,
-- só server) e publica o Model normalizado em ReplicatedStorage.RiftAssets.
-- Se o asset não carregar, entra uma fenda primitiva de reserva -- o sistema
-- funciona igual. Trocar o visual = trocar o AssetId aqui, nada mais.
AssetRegistry.RiftTeleport = {
	AssetId = 16376740571,

	-- Sons por etapa. VAZIO ("") = etapa não toca nada (o sistema funciona sem).
	-- Abertura/fechamento tocam em 3D na posição da fenda (um Sobrevivente perto
	-- do destino ouve "algo surgindo"). Cole os rbxassetid quando tiver os sons.
	Sounds = {
		TeleportCharge = "", -- ativação, nos pés do monstro
		RiftOpen = "", -- fenda começa a abrir
		RiftEnter = "", -- monstro é engolido
		RiftTravel = "", -- fenda do destino surgindo (antecipação)
		RiftExit = "", -- monstro emerge no destino
		RiftClose = "", -- fenda se recolhe (as duas usam este)
	},
}

--------------------------------------------------------------------------------
-- SONS (placeholder -- troque cada rbxassetid quando tiver o som real)
--------------------------------------------------------------------------------

AssetRegistry.Sounds = {
	-- SoundManager.lua: música/ambiente por fase.
	PhaseMusic = {
		Queda = "rbxassetid://0",
		Exploracao = "rbxassetid://0",
		Corrida = "rbxassetid://0",
		Desfecho = "rbxassetid://0",
	},

	-- SoundManager.lua: efeitos curtos posicionais.
	PlayerKilled = "rbxassetid://0",
	PlayerRestrained = "rbxassetid://0",
	ItemThrow = "rbxassetid://0", -- impacto da Pedra Afiada (WeaponSystem.lua)

	-- AmbientSoundController.client.luau: tensão por ficar fora de zona segura.
	HeartbeatTension = "rbxassetid://0",

	-- server/RadioSiteSystem.lua: a estação de rádio.
	RadioSite = {
		-- Loop do motor enquanto o gerador roda. É o som mais importante do
		-- objetivo: com RollOffMaxDistance 320, é ele que denuncia a estação
		-- de longe e transforma "ligar o gerador" numa decisão de risco.
		-- AINDA PLACEHOLDER -- falta o id.
		Gerador = "rbxassetid://0",

		-- Rádio energizado: loop no console a partir de "Ativar painel".
		RadioLigado = "rbxassetid://4860560167",

		-- Pedido de socorro indo ao ar: toca no console durante a
		-- canalização e para junto se a transmissão for cancelada.
		PedidoSocorro = "rbxassetid://6985678040",
	},

	-- server/ExtractionSystem.lua: o helicóptero do resgate.
	Extracao = {
		-- Loop do rotor, do momento que ele aparece no céu até sumir no
		-- horizonte. Alcance grande de propósito: ouvir o helicóptero
		-- chegando é metade da tensão da corrida final.
		Helicoptero = "rbxassetid://99103708154004",
	},
}

-- Survivor powers: replace each icon/sound/optional animation independently.
-- AnimationId stays empty until an animation owned by the experience is supplied.
AssetRegistry.SurvivorPowers = {
	RajadaFinal = { Label = "Rajada Final", Color = Color3.fromRGB(169, 221, 238), Style = "Trail" },
	SaltoLongo = { Label = "Salto Longo", Color = Color3.fromRGB(193, 177, 148), Style = "Dust" },
	ConsertoRelampago = { Label = "Conserto Relâmpago", Color = Color3.fromRGB(150, 210, 242), Style = "Sparks" },
	ArmadilhaImprovisada = { Label = "Armadilha Improvisada", Color = Color3.fromRGB(127, 188, 241), Style = "Electric" },
	TiroCerteiro = { Label = "Tiro Certeiro", Color = Color3.fromRGB(213, 82, 72), Style = "Weapon" },
	InstintoDeCacadora = { Label = "Instinto de Caçadora", Color = Color3.fromRGB(208, 116, 95), Style = "Sense" },
	MantoDeSombras = { Label = "Manto de Sombras", Color = Color3.fromRGB(100, 91, 123), Style = "Shadow" },
	PassoFantasma = { Label = "Passo Fantasma", Color = Color3.fromRGB(151, 150, 176), Style = "Smoke" },
	AdrenalinaDeEmergencia = { Label = "Adrenalina de Emergência", Color = Color3.fromRGB(102, 220, 150), Style = "Heal" },
	EscudoProtetor = { Label = "Escudo Protetor", Color = Color3.fromRGB(160, 217, 242), Style = "Shield" },
	InvestidaBrutal = { Label = "Investida Brutal", Color = Color3.fromRGB(196, 164, 130), Style = "Charge" },
	PosturaInabalavel = { Label = "Postura Inabalável", Color = Color3.fromRGB(165, 175, 176), Style = "Stone" },
	GolpeDeSorte = { Label = "Golpe de Sorte", Color = Color3.fromRGB(233, 193, 99), Style = "Gold" },
	IntuicaoSortuda = { Label = "Intuição Sortuda", Color = Color3.fromRGB(233, 193, 99), Style = "Sense" },
} :: { [string]: { Label: string, Color: Color3, Style: string, Icon: string?, SoundId: string?, AnimationId: string? } }
for _, power in AssetRegistry.SurvivorPowers do
	power.Icon = power.Icon or "rbxassetid://0" -- generic placeholder; HUD shows a glyph until replaced
	power.SoundId = power.SoundId or "rbxasset://sounds/impact_generic.mp3"
	power.AnimationId = power.AnimationId or ""
end

return AssetRegistry
