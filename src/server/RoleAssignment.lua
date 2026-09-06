--!strict
--[[
	RoleAssignment
	Sorteia e consulta os papéis dos jogadores em "Náufragos".

	Papéis (ver GameConfig.Roles): 1 Monstro, 1 Espiao, o resto Sobrevivente.
	O papel de cada jogador fica salvo como Attribute "Role" no próprio
	Instance do Player (player:GetAttribute("Role")), então qualquer script
	(server ou client) pode ler sem precisar deste módulo.

	Uso:
		local RoleAssignment = require(game.ServerScriptService.Server.RoleAssignment)
		RoleAssignment.AssignRoles(Players:GetPlayers())
		local monstros = RoleAssignment.GetPlayersByRole(GameConfig.Roles.Monster)
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage.Modules.GameConfig)

local RoleAssignment = {}

-- RNG isolado: não consome nem é afetado pela sequência do math.random global.
local rng = Random.new()

-- Fisher-Yates: toda permutação da lista tem a mesma probabilidade.
-- (sortear índice em loop e re-sortear em caso de colisão tende a distorcer
-- a distribuição e pode degenerar em listas pequenas, como as de 6-10 jogadores).
local function shuffle(list: { Player }): { Player }
	local shuffled = table.clone(list)
	for i = #shuffled, 2, -1 do
		local j = rng:NextInteger(1, i)
		shuffled[i], shuffled[j] = shuffled[j], shuffled[i]
	end
	return shuffled
end

--[[
	AssignRoles(players)
	Embaralha `players` e distribui: posição 1 -> Monstro, posição 2 -> Espiao,
	demais -> Sobrevivente. Funciona com qualquer lista de tamanho >= 2,
	cobrindo a faixa de partida (GameConfig.Players.Min..Max = 6..10).

	MODO DE TESTE: com GameConfig.Testing.ForceRole preenchido, todo mundo
	recebe esse papel e o sorteio (e a exigência de 2+ jogadores) é pulado
	-- é o que permite testar a partida sozinho. Ver GameConfig.Testing.
]]
function RoleAssignment.AssignRoles(players: { Player })
	local forcedRole = GameConfig.Testing.ForceRole
	if forcedRole then
		for _, player in players do
			player:SetAttribute("Role", forcedRole)
		end
		print(string.format("[RoleAssignment] MODO DE TESTE: %d jogador(es) forçado(s) em '%s'.", #players, forcedRole))
		return
	end

	assert(#players >= 2, "AssignRoles precisa de pelo menos 2 jogadores (1 Monstro + 1 Espiao)")

	local shuffled = shuffle(players)

	for index, player in shuffled do
		local role: string
		if index == 1 then
			role = GameConfig.Roles.Monster
		elseif index == 2 then
			role = GameConfig.Roles.Spy
		else
			role = GameConfig.Roles.Survivor
		end

		player:SetAttribute("Role", role)
	end
end

--[[
	GetPlayersByRole(roleName)
	Retorna todos os jogadores atualmente no jogo cujo Attribute "Role"
	seja igual a `roleName` (ex: GameConfig.Roles.Monster).
]]
function RoleAssignment.GetPlayersByRole(roleName: string): { Player }
	local result = {}

	for _, player in Players:GetPlayers() do
		if player:GetAttribute("Role") == roleName then
			table.insert(result, player)
		end
	end

	return result
end

return RoleAssignment
