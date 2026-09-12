--!strict
--[[
	ItemRegistry
	Registro central de todos os itens coletáveis/craftáveis de "Náufragos".
	ItemSpawner.lua usa isto pra saber ONDE e QUANTO spawnar; CraftingSystem
	usa as receitas; outros sistemas leem Function só como referência (não
	é exibido em UI ainda).

	CATEGORIAS
	  "MaterialJangada" -- Madeira/Corda/Lona: NÃO são Tools. Vivem no
	    inventário pessoal de RaftObjective.lua (contagem por tipo, não Tool
	    no Backpack) porque precisam ser entregues em LocalJangada. Corda
	    também é gasta por ConfrontSystem (amarrar) -- mesmo estoque, dois
	    usos possíveis pro jogador escolher.
	  "PecaRadio" -- Antena/Bateria/Transmissor: peças únicas criadas por
	    RadioPieces.lua. Viram Tools no inventário e caem quando o portador morre.
	  "Tool" -- FacaImprovisada/LancaDeBambu/PedraAfiada/Tocha/LancaAncestral:
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
	Madeira = {
		DisplayName = "Madeira",
		Category = "MaterialJangada",
		Rarity = "Comum",
		Zones = { Zone.Floresta },
		Function = "Estrutura da jangada. Também é o ingrediente base das receitas de craft.",
	},
	Corda = {
		DisplayName = "Corda",
		Category = "MaterialJangada",
		Rarity = "Media",
		Zones = { Zone.DestrocosMar, Zone.DestrocosPraia, Zone.DestrocosFloresta, Zone.Construcoes, Zone.Construcoes },
		Function = "Amarração da jangada OU amarrar o Espião (ConfrontSystem) -- mesmo estoque pessoal, um ou outro.",
	},
	Lona = {
		DisplayName = "Lona (Pano de Vela)",
		Category = "MaterialJangada",
		Rarity = "Rara",
		Zones = { Zone.DestrocosMar, Zone.DestrocosPraia, Zone.DestrocosFloresta, Zone.Construcoes },
		Function = "Vela da jangada. Também é o 'pano' da receita da Tocha -- concorre pelo mesmo item raro.",
	},

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

	FacaImprovisada = {
		DisplayName = "Faca Improvisada",
		Category = "Tool",
		AttributeName = "FacaImprovisada",
		Rarity = "Comum",
		Zones = { Zone.DestrocosMar, Zone.DestrocosPraia, Zone.DestrocosFloresta, Zone.Praia, Zone.Construcoes, Zone.Construcoes },
		Function = "Dano fraco, afasta o Monstro brevemente. Não mata ninguém.",
	},
	LancaDeBambu = {
		DisplayName = "Lança de Bambu",
		Category = "Tool",
		AttributeName = "LancaDeBambu",
		Rarity = "Media",
		Zones = { Zone.Floresta },
		Craft = { Ingredients = { Madeira = 1, Corda = 1 } }, -- "bambu" não existe como item -> Madeira
		Function = "Dano leve, mais alcance que a faca.",
	},
	PedraAfiada = {
		DisplayName = "Pedra Afiada",
		Category = "Tool",
		AttributeName = "PedraAfiada",
		Rarity = "Comum",
		Zones = { Zone.Rochas },
		Function = "Arma de arremesso, dano mínimo. Cria barulho num ponto -- distrai o Monstro pra lá.",
	},
	Tocha = {
		DisplayName = "Tocha",
		Category = "Tool",
		AttributeName = "Tocha", -- mesmo Attribute que MonsterLightWeakness.lua já usa
		Rarity = "Media",
		Zones = { Zone.Floresta, Zone.DestrocosMar, Zone.DestrocosPraia, Zone.DestrocosFloresta, Zone.Construcoes },
		Craft = { Ingredients = { Madeira = 1, Lona = 1 } },
		Function = "Luz + repele o Monstro (fraqueza dele). Gasta combustível com o tempo equipada.",
	},
	Lanterna = {
		DisplayName = "Lanterna",
		Category = "Tool",
		AttributeName = "Lanterna",
		Rarity = "Media",
		Zones = { Zone.DestrocosMar, Zone.DestrocosPraia, Zone.DestrocosFloresta, Zone.Construcoes, Zone.Construcoes },
		AssetId = 117648733552528,
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
	LancaAncestral = {
		DisplayName = "Lança Ancestral",
		Category = "Tool",
		AttributeName = "ArmaRara", -- MESMO Attribute que ConfrontSystem.lua (Parte 3) já usa
		Rarity = nil, -- não entra no sorteio geral: 1 por mapa, colocada nas Ruínas (IslandGenerator)
		Zones = {},
		MaxPerMap = 1,
		Function = "Única arma capaz de matar o Monstro (só se ele estiver enfraquecido pela luz) ou executar o Espião.",
	},
}

return ItemRegistry
