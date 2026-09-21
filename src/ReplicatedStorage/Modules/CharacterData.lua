--!strict
--[[
	CharacterData
	Os personagens jogáveis de "Náufragos" e seus 7 atributos.

	REGRA DO ORÇAMENTO: todo personagem soma EXATAMENTE
	CharacterData.TotalPoints (350). Ninguém é melhor que ninguém no total --
	só distribui diferente. Assert no final do arquivo garante isso: se você
	editar um número e esquecer de compensar em outro, o jogo nem carrega
	(erro claro no Output em vez de um personagem silenciosamente overpower).

	OS 7 ATRIBUTOS (0..100) e o que cada um MEXE de verdade no jogo
	(o mapeamento numérico fica em GameConfig.Characters; quem converte
	atributo -> multiplicador é Modules/StatScaling.lua):

	  Velocidade   -> WalkSpeed base (e o sprint junto, proporcional)
	  Stamina      -> quanto o sprint dura e quão rápido o fôlego volta
	  Compostura   -> vida máxima e quanto dano você ABSORVE
	  Furtividade  -> demora mais pra tensão subir fora de Zona Segura
	  Reparo       -> chance de sintonizar o Rádio
	  Força        -> dano que você CAUSA (corpo a corpo e arma de fogo)
	  Sorte        -> quantidade e raridade do loot das caixas

	PassivaUnica é texto livre (só 2 personagens têm). É mostrado no card de
	seleção. A implementação mecânica de cada passiva fica no sistema dono
	dela -- ver CharacterStatsApplier.lua.
]]

export type Stats = {
	Velocidade: number,
	Stamina: number,
	Compostura: number,
	Furtividade: number,
	Reparo: number,
	Forca: number,
	Sorte: number,
}

export type Character = {
	Id: string,
	Nome: string,
	Apelido: string,
	Stats: Stats,
	PassivaUnica: string?,
	Role: string?,
	-- Presentation only; never changes the rig used in a match.
	Description: string?,
	Icon: string?,
	PreviewModel: string?,
	Background: string?,
	IdleAnimation: string?,
	ThemeColor: Color3?,
	BodyColor: Color3?,
	ShirtColor: Color3?,
	PantsColor: Color3?,
	Availability: string?,
	PowerDescription1: string?,
	PowerDescription2: string?,
	PowerIcon1: string?,
	PowerIcon2: string?,
	-- Active survivor slots: Q / E. Cooldowns in seconds, enforced by the server.
	PowerId1: string?,
	PowerName1: string?,
	PowerCooldown1: number?,
	PowerId2: string?,
	PowerName2: string?,
	PowerCooldown2: number?,
}

local CharacterData = {}

CharacterData.TotalPoints = 350

-- Ordem canônica dos atributos (UI, logs e iteração determinística).
CharacterData.StatOrder = {
	"Velocidade",
	"Stamina",
	"Compostura",
	"Furtividade",
	"Reparo",
	"Forca",
	"Sorte",
} :: { string }

-- Rótulo bonitinho pra UI. A CHAVE é "Forca" sem cedilha de propósito (nome
-- de campo Luau, evita dor de cabeça com encoding); o rótulo é "Força".
CharacterData.StatLabels = {
	Velocidade = "Velocidade",
	Stamina = "Stamina",
	Compostura = "Compostura",
	Furtividade = "Furtividade",
	Reparo = "Reparo",
	Forca = "Força",
	Sorte = "Sorte",
} :: { [string]: string }

--------------------------------------------------------------------------------
-- Elenco
--------------------------------------------------------------------------------

CharacterData.Characters = {
	{
		Id = "RafaelMonteiro",
		Description = "Velocidade e fôlego para abrir caminho e escapar do perigo.",
		Icon = "", -- asset ID or name in SelectionAssets.CharacterIcons
		PreviewModel = "RafaelMonteiro",
		Background = "", -- asset ID or name in SelectionAssets.Backgrounds
		IdleAnimation = "", -- asset ID or Animation in SelectionAssets.IdleAnimations
		ThemeColor = Color3.fromRGB(70, 196, 226),
		BodyColor = Color3.fromRGB(204, 159, 125), ShirtColor = Color3.fromRGB(35, 111, 146), PantsColor = Color3.fromRGB(25, 42, 58),
		Availability = "Available",
		PowerDescription1 = "Dobra a velocidade por 5s, restaura a stamina e suspende seu gasto.",
		PowerDescription2 = "Um salto para frente para vencer distâncias. Exige chão firme.",
		Nome = "Rafael Monteiro",
		Apelido = "O Atlético",
		Stats = {
			Velocidade = 97,
			Stamina = 93,
			Compostura = 32,
			Furtividade = 10,
			Reparo = 20,
			Forca = 40,
			Sorte = 58,
		},
		PowerId1 = "RajadaFinal",
		PowerName1 = "RajadaFinal",
		PowerCooldown1 = 90,
		PowerId2 = "SaltoLongo",
		PowerName2 = "SaltoLongo",
		PowerCooldown2 = 60,
	},
	{
		Id = "DiegoFerreira",
		Description = "Reparos e improvisação para trazer a equipe de volta para casa.",
		Icon = "", -- asset ID or name in SelectionAssets.CharacterIcons
		PreviewModel = "DiegoFerreira",
		Background = "", -- asset ID or name in SelectionAssets.Backgrounds
		IdleAnimation = "", -- asset ID or Animation in SelectionAssets.IdleAnimations
		ThemeColor = Color3.fromRGB(242, 170, 72),
		BodyColor = Color3.fromRGB(224, 187, 151), ShirtColor = Color3.fromRGB(142, 83, 38), PantsColor = Color3.fromRGB(48, 42, 38),
		Availability = "Available",
		PowerDescription1 = "Acrescenta 25% de progresso à sintonia do rádio ou ao reparo em andamento.",
		PowerDescription2 = "Prepara uma armadilha por 60s. Atordoa Monstro ou Espião por 3s.",
		Nome = "Diego Ferreira",
		Apelido = "O Engenheiro",
		Stats = {
			Velocidade = 30,
			Stamina = 20,
			Compostura = 44,
			Furtividade = 77,
			Reparo = 96,
			Forca = 30,
			Sorte = 53,
		},
		PowerId1 = "ConsertoRelampago",
		PowerName1 = "ConsertoRelampago",
		PowerCooldown1 = 240,
		PowerId2 = "ArmadilhaImprovisada",
		PowerName2 = "ArmadilhaImprovisada",
		PowerCooldown2 = 150,
	},
	{
		Id = "MarinaAlbuquerque",
		Description = "Discreta e incansável. Encontra a ameaça antes que ela se aproxime.",
		Icon = "", -- asset ID or name in SelectionAssets.CharacterIcons
		PreviewModel = "MarinaAlbuquerque",
		Background = "", -- asset ID or name in SelectionAssets.Backgrounds
		IdleAnimation = "", -- asset ID or Animation in SelectionAssets.IdleAnimations
		ThemeColor = Color3.fromRGB(221, 99, 92),
		BodyColor = Color3.fromRGB(190, 132, 103), ShirtColor = Color3.fromRGB(119, 45, 53), PantsColor = Color3.fromRGB(43, 35, 42),
		Availability = "Available",
		PowerDescription1 = "O próximo ataque em até 8s causa dano triplo e atordoa por 2s. Errar consome o efeito.",
		PowerDescription2 = "Revela a direção do monstro vivo mais próximo por 4s.",
		Nome = "Marina Albuquerque",
		Apelido = "A Caçadora",
		Stats = {
			Velocidade = 57,
			Stamina = 95,
			Compostura = 30,
			Furtividade = 95,
			Reparo = 10,
			Forca = 20,
			Sorte = 43,
		},
		PowerId1 = "TiroCerteiro",
		PowerName1 = "TiroCerteiro",
		PowerCooldown1 = 120,
		PowerId2 = "InstintoDeCacadora",
		PowerName2 = "InstintoDeCacadora",
		PowerCooldown2 = 180,
	},
	{
		Id = "KevinNakamura",
		Description = "Move-se nas sombras e mantém a calma quando tudo dá errado.",
		Icon = "", -- asset ID or name in SelectionAssets.CharacterIcons
		PreviewModel = "KevinNakamura",
		Background = "", -- asset ID or name in SelectionAssets.Backgrounds
		IdleAnimation = "", -- asset ID or Animation in SelectionAssets.IdleAnimations
		ThemeColor = Color3.fromRGB(142, 117, 212),
		BodyColor = Color3.fromRGB(229, 192, 156), ShirtColor = Color3.fromRGB(61, 49, 100), PantsColor = Color3.fromRGB(27, 27, 42),
		Availability = "Available",
		PowerDescription1 = "Suspende a detecção e os efeitos de tensão por 8s.",
		PowerDescription2 = "Avança até 15 studs para um destino seguro; obstáculos limitam o alcance.",
		Nome = "Kevin Nakamura",
		Apelido = "O Sorrateiro",
		Stats = {
			Velocidade = 40,
			Stamina = 40,
			Compostura = 75,
			Furtividade = 95,
			Reparo = 68,
			Forca = 20,
			Sorte = 12,
		},
		PowerId1 = "MantoDeSombras",
		PowerName1 = "MantoDeSombras",
		PowerCooldown1 = 150,
		PowerId2 = "PassoFantasma",
		PowerName2 = "PassoFantasma",
		PowerCooldown2 = 100,
	},
	{
		Id = "SofiaRibeiro",
		Description = "Proteção e cuidados para manter os sobreviventes de pé.",
		Icon = "", -- asset ID or name in SelectionAssets.CharacterIcons
		PreviewModel = "SofiaRibeiro",
		Background = "", -- asset ID or name in SelectionAssets.Backgrounds
		IdleAnimation = "", -- asset ID or Animation in SelectionAssets.IdleAnimations
		ThemeColor = Color3.fromRGB(89, 218, 145),
		BodyColor = Color3.fromRGB(214, 166, 132), ShirtColor = Color3.fromRGB(42, 132, 91), PantsColor = Color3.fromRGB(33, 54, 48),
		Availability = "Available",
		PowerDescription1 = "Cura 50% da vida máxima de si e dos sobreviventes a até 15 studs.",
		PowerDescription2 = "Protege o aliado visível mais próximo a até 10 studs por 4s; sem aliado, protege a si.",
		Nome = "Sofia Ribeiro",
		Apelido = "A Médica",
		Stats = {
			Velocidade = 33,
			Stamina = 50,
			Compostura = 96,
			Furtividade = 57,
			Reparo = 20,
			Forca = 10,
			Sorte = 84,
		},
		PassivaUnica = "Cura 40% mais eficaz com Chocolate e Bandagem",
		PowerId1 = "AdrenalinaDeEmergencia",
		PowerName1 = "AdrenalinaDeEmergencia",
		PowerCooldown1 = 200,
		PowerId2 = "EscudoProtetor",
		PowerName2 = "EscudoProtetor",
		PowerCooldown2 = 160,
	},
	{
		Id = "BrunoCarvalho",
		Description = "Força e resistência para enfrentar o perigo de perto.",
		Icon = "", -- asset ID or name in SelectionAssets.CharacterIcons
		PreviewModel = "BrunoCarvalho",
		Background = "", -- asset ID or name in SelectionAssets.Backgrounds
		IdleAnimation = "", -- asset ID or Animation in SelectionAssets.IdleAnimations
		ThemeColor = Color3.fromRGB(214, 145, 76),
		BodyColor = Color3.fromRGB(151, 99, 70), ShirtColor = Color3.fromRGB(116, 65, 35), PantsColor = Color3.fromRGB(47, 37, 32),
		Availability = "Available",
		PowerDescription1 = "Avança e atordoa os inimigos atingidos por 3s.",
		PowerDescription2 = "Por 5s, impede atordoamento e reduz o dano recebido pela metade.",
		Nome = "Bruno Carvalho",
		Apelido = "O Forte",
		Stats = {
			Velocidade = 77,
			Stamina = 86,
			Compostura = 43,
			Furtividade = 20,
			Reparo = 10,
			Forca = 94,
			Sorte = 20,
		},
		PassivaUnica = "Carrega o dobro de material por slot de inventário",
		PowerId1 = "InvestidaBrutal",
		PowerName1 = "InvestidaBrutal",
		PowerCooldown1 = 120,
		PowerId2 = "PosturaInabalavel",
		PowerName2 = "PosturaInabalavel",
		PowerCooldown2 = 140,
	},
	{
		Id = "CamilaDuarte",
		Description = "Instinto e velocidade para encontrar uma saída improvável.",
		Icon = "", -- asset ID or name in SelectionAssets.CharacterIcons
		PreviewModel = "CamilaDuarte",
		Background = "", -- asset ID or name in SelectionAssets.Backgrounds
		IdleAnimation = "", -- asset ID or Animation in SelectionAssets.IdleAnimations
		ThemeColor = Color3.fromRGB(236, 199, 75),
		BodyColor = Color3.fromRGB(230, 186, 150), ShirtColor = Color3.fromRGB(150, 115, 35), PantsColor = Color3.fromRGB(57, 48, 30),
		Availability = "Available",
		PowerDescription1 = "Uma chance de 50% de anular o próximo ataque em até 10s.",
		PowerDescription2 = "Indica a direção do item raro disponível mais próximo por 6s.",
		Nome = "Camila Duarte",
		Apelido = "A Sortuda",
		Stats = {
			Velocidade = 94,
			Stamina = 40,
			Compostura = 10,
			Furtividade = 57,
			Reparo = 20,
			Forca = 33,
			Sorte = 96,
		},
		PowerId1 = "GolpeDeSorte",
		PowerName1 = "GolpeDeSorte",
		PowerCooldown1 = 150,
		PowerId2 = "IntuicaoSortuda",
		PowerName2 = "IntuicaoSortuda",
		PowerCooldown2 = 200,
	},
} :: { Character }

-- Personagens exclusivos do papel Monstro. Ficam fora de `Characters` para
-- não aparecerem na escolha dos Sobreviventes/Espião, mas entram no índice
-- geral (`GetById`) para aplicar atributos/nome normalmente.
CharacterData.MonsterCharacters = {
	{
		Id = "Jason",
		Nome = "Jason",
		Apelido = "O Predador da Caverna",
		Role = "Monstro",
		Stats = {
			Velocidade = 75,
			Stamina = 65,
			Compostura = 85,
			Furtividade = 10,
			Reparo = 0,
			Forca = 100,
			Sorte = 15,
		},
		PassivaUnica = "Nasce na caverna e caça os sobreviventes.",
	},
} :: { Character }

--------------------------------------------------------------------------------
-- API
--------------------------------------------------------------------------------

local byId: { [string]: Character } = {}
local directIndex = CharacterData :: any
for _, character in CharacterData.Characters do
	byId[character.Id] = character
	directIndex[character.Id] = character
end
for _, character in CharacterData.MonsterCharacters do
	byId[character.Id] = character
	directIndex[character.Id] = character
end

function CharacterData.IsMonsterCharacter(id: unknown): boolean
	local character = CharacterData.GetById(id)
	return character ~= nil and character.Role == "Monstro"
end

--[[ GetById(id) -- devolve o personagem, ou nil se o id não existir. ]]
function CharacterData.GetById(id: unknown): Character?
	if type(id) ~= "string" then
		return nil
	end
	return byId[id]
end

--[[ Exists(id) -- atalho de validação pros remotes (o cliente manda o id). ]]
function CharacterData.Exists(id: unknown): boolean
	return CharacterData.GetById(id) ~= nil
end

--[[
	SumStats(character)
	Soma os 7 atributos. Deve dar sempre CharacterData.TotalPoints.
]]
function CharacterData.SumStats(character: Character): number
	local total = 0
	for _, statName in CharacterData.StatOrder do
		total += (character.Stats :: any)[statName] or 0
	end
	return total
end

--------------------------------------------------------------------------------
-- Validação do orçamento (roda no require -- falha cedo e com mensagem clara)
--------------------------------------------------------------------------------

local allCharacters = table.clone(CharacterData.Characters)
for _, character in CharacterData.MonsterCharacters do
	table.insert(allCharacters, character)
end

for _, character in allCharacters do
	local total = CharacterData.SumStats(character)
	if total ~= CharacterData.TotalPoints then
		error(
			string.format(
				"[CharacterData] '%s' soma %d pontos, mas todo personagem tem que somar %d. "
					.. "Ajuste os atributos até fechar a conta.",
				character.Nome,
				total,
				CharacterData.TotalPoints
			),
			0
		)
	end
	for _, statName in CharacterData.StatOrder do
		local value = (character.Stats :: any)[statName]
		if type(value) ~= "number" or value < 0 or value > 100 then
			error(
				string.format(
					"[CharacterData] '%s' tem %s = %s -- atributo precisa ser número de 0 a 100.",
					character.Nome,
					statName,
					tostring(value)
				),
				0
			)
		end
	end
end

return CharacterData
