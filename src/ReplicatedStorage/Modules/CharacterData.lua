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
	  Reparo       -> progresso da Jangada e chance de sintonizar o Rádio
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
	},
	{
		Id = "DiegoFerreira",
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
	},
	{
		Id = "MarinaAlbuquerque",
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
	},
	{
		Id = "KevinNakamura",
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
	},
	{
		Id = "SofiaRibeiro",
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
	},
	{
		Id = "BrunoCarvalho",
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
	},
	{
		Id = "CamilaDuarte",
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
	},
} :: { Character }

--------------------------------------------------------------------------------
-- API
--------------------------------------------------------------------------------

local byId: { [string]: Character } = {}
for _, character in CharacterData.Characters do
	byId[character.Id] = character
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

for _, character in CharacterData.Characters do
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
