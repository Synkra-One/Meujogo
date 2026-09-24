--!strict
--[[
	ItemRegistry
	Registro central de todos os itens coletáveis/craftáveis de "Náufragos".
	ItemSpawner.lua usa isto pra saber ONDE e QUANTO spawnar; outros sistemas
	leem Function só como referência (não
	é exibido em UI ainda).

	CATEGORIAS
	  "PecaRadio" -- Antena/Bateria/Transmissor: peças únicas criadas por
	    RadioPieces.lua. Viram Tools no inventário e caem quando o portador morre.
	  "Tool" -- LancaDeBambu/Tocha/LancaAncestral:
	    Tools de verdade no Backpack (WeaponSystem.lua / já existentes).

	RARIDADE -> quantidade: RarityCount decide quantas cópias de cada item
	dessa raridade o ItemSpawner distribui pelo mapa inteiro (não por zona).

	AttributeName: pra "Tocha" e "LancaAncestral" (= ArmaRara), é o MESMO
	Attribute que MonsterLightWeakness.lua/ConfrontSystem.lua já verificam
	-- não são Attributes novos, é o mesmo contrato.
]]

local ItemRegistry = {}

-- Mapa grande (~1500 de diâmetro) com POIs espalhados: mais cópias, senão o
-- jogador anda 5 minutos sem achar nada.
ItemRegistry.RarityCount = {
	Comum = 22,
	Media = 12,
	Rara = 5,
}

ItemRegistry.Zone = {
	DestrocosMar = "DestrocosMar",
	DestrocosPraia = "DestrocosPraia",
	DestrocosFloresta = "DestrocosFloresta",
	VilaNativa = "VilaNativa",
	Floresta = "Floresta",
	Rochas = "Rochas",
	Praia = "Praia",
	-- Marcadores PontoLoot dentro das construções dos POIs (cabanas, lodge,
	-- celeiro, casa de barcos, torre, farol, cabanas nativas). É onde a maior
	-- parte do loot deve ficar, como nas cabanas do Friday the 13th.
	Construcoes = "Construcoes",
}

local Zone = ItemRegistry.Zone

ItemRegistry.Items = {
	Antena = {
		DisplayName = "Antena",
		Category = "PecaRadio",
		Rarity = "Media",
		Zones = { Zone.DestrocosMar, Zone.DestrocosPraia, Zone.DestrocosFloresta, Zone.Construcoes },
		Function = "Peça de reparo do rádio.",
	},
	Bateria = {
		DisplayName = "Bateria",
		Category = "PecaRadio",
		Rarity = "Media",
		Zones = { Zone.DestrocosMar, Zone.DestrocosPraia, Zone.DestrocosFloresta, Zone.Construcoes },
		Function = "Peça de reparo do rádio.",
	},
	Transmissor = {
		DisplayName = "Transmissor",
		Category = "PecaRadio",
		Rarity = "Rara",
		-- "parte central, mais escondida" -> só no destroço mata adentro,
		-- não no impacto inicial do mar/praia.
		Zones = { Zone.DestrocosFloresta },
		Function = "Peça de reparo do rádio.",
	},

	LancaDeBambu = {
		DisplayName = "Pé de cabra",
		Category = "Tool",
		AttributeName = "LancaDeBambu",
		Rarity = "Media",
		Zones = { Zone.Floresta },
		AssetId = 81510444,
		Function = "Golpe curto: 15 de dano e breve atordoamento no Monstro.",
	},
	Sinalizador = {
		DisplayName = "Sinalizador",
		Category = "Tool",
		AttributeName = "Sinalizador",
		Zones = {}, -- sem distribuição automática nesta etapa
		Function = "Sinal de alcance médio; revelar/afastar o Monstro será implementado depois.",
	},
	Tocha = {
		DisplayName = "Tocha",
		Category = "Tool",
		AttributeName = "Tocha", -- mesmo Attribute que MonsterLightWeakness.lua já usa
		Rarity = "Media",
		Zones = { Zone.Floresta, Zone.DestrocosMar, Zone.DestrocosPraia, Zone.DestrocosFloresta, Zone.Construcoes },
		Function = "Luz + repele o Monstro (fraqueza dele). Gasta combustível com o tempo equipada.",
	},
	Lanterna = {
		DisplayName = "Lanterna",
		Category = "Tool",
		AttributeName = "Lanterna",
		Rarity = "Media",
		Zones = { Zone.DestrocosMar, Zone.DestrocosPraia, Zone.DestrocosFloresta, Zone.Construcoes, Zone.Construcoes },
		AssetId = 6715358554, -- modelo unico da lanterna: "Flashlight", por MikesDSL
		Function = "Feixe direcional com bateria de 60s. Exposicao continua incomoda e desacelera o Monstro, com dano leve e resistencia temporaria.",
	},
	Chocolate = {
		DisplayName = "Chocolate",
		Category = "Tool",
		AttributeName = "Chocolate",
		Rarity = "Comum",
		Zones = { Zone.DestrocosMar, Zone.DestrocosPraia, Zone.DestrocosFloresta, Zone.Construcoes, Zone.Construcoes },
		AssetId = 77169687128921, -- modelo REAL do Toolbox
		Function = "Consumível: cura toda a vida do Humanoid ao usar e se destrói. Sem sistema de dano no jogo ainda, então hoje não tem efeito visível -- fica pronto pra quando houver dano de verdade.",
	},
	Bandagem = {
		DisplayName = "Bandagem",
		Category = "Tool",
		AttributeName = "Bandagem",
		Rarity = "Media",
		Zones = { Zone.DestrocosMar, Zone.DestrocosPraia, Zone.DestrocosFloresta, Zone.Construcoes, Zone.Construcoes },
		Function = "Cura com canalização (estilo Left 4 Dead): usa por ~3,5s tocando a animação e só então cura GameConfig.Bandagem.Heal. Tomar dano, desequipar ou morrer no meio cancela sem gastar. A passiva da Sofia deixa a cura 40% melhor.",
	},
	Gasolina = {
		DisplayName = "Galão de Gasolina",
		Category = "Tool",
		AttributeName = "Gasolina",
		Rarity = "Media",
		Zones = { Zone.DestrocosMar, Zone.DestrocosPraia, Zone.DestrocosFloresta, Zone.Construcoes, Zone.Construcoes },
		AssetId = 8679995948, -- modelo REAL do Toolbox (ver ToolFactory.lua)
		Function = "Combustível portátil pro gerador da Estação de Rádio (server/RadioSiteSystem.lua). Levar até o bocal e segurar 'Abastecer': soma GameConfig.RadioSite.CombustivelPorGalao segundos e se destrói -- concorre com os galões fixos já presentes no local, mas vale carregar porque não depende de estar perto da estação pra achar.",
	},
	TacoBeisebol = {
		DisplayName = "Taco de Beisebol",
		Category = "Tool",
		AttributeName = "TacoBeisebol",
		-- Rara = RarityCount.Rara cópias no mapa (5), só dentro de construções e
		-- na vila -- "alguns lugares", não espalhado pela ilha toda.
		Rarity = "Rara",
		Zones = { Zone.Construcoes, Zone.Construcoes, Zone.Construcoes, Zone.VilaNativa },
		Function = "Corpo a corpo: clique = golpe leve (12 de dano); segurar o clique = golpe pesado (26 de dano, empurra e atordoa o Monstro, mas demora mais pra golpear de novo). Segura o taco com a animação Idle por cima da locomoção.",
	},
	LancaAncestral = {
		DisplayName = "Crowbar Ancestral",
		Category = "Tool",
		AttributeName = "ArmaRara", -- MESMO Attribute que ConfrontSystem.lua (Parte 3) já usa
		Rarity = nil, -- não entra no sorteio geral: 1 por mapa, colocada nas Ruínas (IslandGenerator)
		Zones = {},
		MaxPerMap = 1,
		AssetId = 81510444,
		Function = "Única arma capaz de matar o Monstro (só se ele estiver enfraquecido pela luz) ou executar o Espião.",
	},
}

return ItemRegistry
