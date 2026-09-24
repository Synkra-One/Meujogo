--!strict
--[[
	RoleAssignment
	Sorteia e consulta os papéis dos jogadores em "Náufragos".

	Papéis: 1 Monstro e pelo menos 1 Sobrevivente. Espiao a partir de 3 jogadores.
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

local function isValidRole(role: unknown): boolean
	return role == GameConfig.Roles.Survivor
		or role == GameConfig.Roles.Monster
		or role == GameConfig.Roles.Spy
end

local function devForcedRole(player: Player): string?
	if GameConfig.Testing.DevRoleChooser ~= true then
		return nil
	end
	local role = player:GetAttribute("DevForceRole")
	return if isValidRole(role) then role :: string else nil
end

local function pickRequested(shuffled: { Player }, role: string, taken: { [Player]: boolean }): Player?
	for _, player in shuffled do
		if not taken[player] and devForcedRole(player) == role then
			return player
		end
	end
	return nil
end

local function pickAny(shuffled: { Player }, taken: { [Player]: boolean }): Player?
	for _, player in shuffled do
		if not taken[player] and devForcedRole(player) == nil then
			return player
		end
	end
	for _, player in shuffled do
		if not taken[player] then
			return player
		end
	end
	return nil
end

--[[
	AssignRoles(players)
	Distribui: 1 Monstro, 1 Espiao (com 3+ jogadores), resto Sobrevivente.

	MODO DE TESTE:
	  - GameConfig.Testing.ForceRole força o papel apenas em teste solo;
	  - Player.DevForceRole, definido pela sala dev, força o papel daquele
	    jogador específico quando possível;
	  - em teste solo, DevForceRole vence a sorte.
]]
function RoleAssignment.AssignRoles(players: { Player })
	local forcedRole = GameConfig.Testing.ForceRole
	if not isValidRole(forcedRole) then
		forcedRole = nil
	end

	if #players == 1 and (GameConfig.Testing.SoloStart or devForcedRole(players[1]) ~= nil) then
		-- A escolha explicita do painel dev vence o padrao de teste. Sem ela,
		-- ForceRole pode manter o teste solo previsivel (Sobrevivente por
		-- padrao, para a tela de selecao sempre poder ser validada).
		local soloRole = devForcedRole(players[1]) or forcedRole
		if not soloRole then
			-- Espiao precisa de uma equipe para sabotar. No teste solo o sorteio
			-- alterna apenas entre os dois papéis jogáveis: humano ou Monstro.
			local roles = { GameConfig.Roles.Survivor, GameConfig.Roles.Monster }
			soloRole = roles[rng:NextInteger(1, #roles)]
		end
		players[1]:SetAttribute("Role", soloRole)
		print(string.format("[RoleAssignment] MODO DE TESTE SOLO: %s caiu como '%s'.", players[1].Name, soloRole))
		return
	end

	if forcedRole and #players >= 2 then
		warn("[RoleAssignment] ForceRole ignorado em partida multiplayer: 2+ jogadores sempre precisam de exatamente 1 Monstro.")
	end

	assert(#players >= 2, "AssignRoles precisa de pelo menos 2 jogadores (1 Monstro + 1 Sobrevivente)")

	local shuffled = shuffle(players)
	local taken: { [Player]: boolean } = {}
	local monster = pickRequested(shuffled, GameConfig.Roles.Monster, taken) or pickAny(shuffled, taken)
	if monster then
		taken[monster] = true
	end
	-- Com dois jogadores, reservar Espiao deixaria zero Sobreviventes e
	-- dispararia a vitoria do Monstro imediatamente.
	local spy: Player? = nil
	if #players >= 3 then
		spy = pickRequested(shuffled, GameConfig.Roles.Spy, taken) or pickAny(shuffled, taken)
	end
	if spy then
		taken[spy] = true
	end

	for _, player in shuffled do
		local role: string
		if player == monster then
			role = GameConfig.Roles.Monster
		elseif player == spy then
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
