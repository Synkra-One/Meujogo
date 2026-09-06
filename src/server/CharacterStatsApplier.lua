--!strict
--[[
	CharacterStatsApplier
	Dono da ESCOLHA de personagem e de aplicar os 7 atributos no jogador.

	DUAS METADES:

	1) REGISTRO DE ESCOLHA (lobby)
	   Remotes.SelectCharacter (cliente) -> valida id + exclusividade -> guarda
	   -> reemite Remotes.CharacterRoster pra todo mundo (a UI desabilita os
	   cards tomados em tempo real). Dois jogadores nunca ficam com o mesmo
	   personagem. Sair do jogo libera o personagem.

	2) APLICAÇÃO (ApplyCharacter)
	   Publica cada atributo como Attribute no Player com o prefixo "Stat_"
	   (Stat_Velocidade, Stat_Forca, ...). Attributes replicam sozinhos, então
	   cliente e servidor leem os mesmos números sem remote nenhum.
	   Depois aplica o que é "de corpo" no character atual: MaxHealth
	   (Compostura) e o Attribute "SpeedMul" (Velocidade), que o script
	   Crouching do pacote de movimento multiplica no WalkSpeed todo frame.

	QUEM CONSOME OS ATRIBUTOS (nenhum sistema foi reescrito -- todos só
	multiplicam pelo fator de Modules/StatScaling.lua):

	  Velocidade  -> Attribute "SpeedMul" no character  -> Crouching (WalkSpeed)
	  Stamina     -> server/StaminaSystem.lua           (gasto/regen do sprint)
	  Compostura  -> server/DamageSystem.lua            (MaxHealth + dano recebido)
	  Furtividade -> client/AmbientSoundController      (limiar da tensão)
	  Reparo      -> server/RaftObjective + RadioObjective (progresso/sintonia)
	  Forca       -> server/DamageSystem + WeaponSystem (dano causado + empurrão)
	  Sorte       -> server/LootCrateSystem.lua         (quantidade e raridade)

	PASSIVAS ÚNICAS (texto em CharacterData.PassivaUnica) são aplicadas aqui
	como Attributes booleanos, e o sistema dono de cada uma consulta:
	  Sofia  -> "PassivaCuraExtra"   (UtilityItemSystem: cura +40%)
	  Bruno  -> "PassivaCargaDupla"  (RaftObjective: cada material conta 2)

	Uso (uma vez no boot, ANTES de DamageSystem pra o MaxHealth já sair certo):
		require(script.CharacterStatsApplier).Init()
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CharacterData = require(ReplicatedStorage.Modules.CharacterData)
local Remotes = require(ReplicatedStorage.Modules.Remotes)
local StatScaling = require(ReplicatedStorage.Modules.StatScaling)

local RoundManager = require(script.Parent.RoundManager)

local CharacterStatsApplier = {}

-- characterId -> Player que pegou. Fonte da verdade da exclusividade.
local takenBy: { [string]: Player } = {}
-- Player -> characterId escolhido.
local choiceOf: { [Player]: string } = {}

--------------------------------------------------------------------------------
-- Roster (o que a UI usa pra desabilitar cards)
--------------------------------------------------------------------------------

local function buildRoster(): { [string]: number }
	local roster: { [string]: number } = {}
	for id, player in takenBy do
		if player.Parent then
			roster[id] = player.UserId
		end
	end
	return roster
end

local function broadcastRoster(only: Player?)
	local roster = buildRoster()
	-- O 2º argumento diz se a partida está rolando: quem entra NO MEIO de uma
	-- rodada não pode ver a tela de escolha por cima do jogo.
	local roundActive = RoundManager.IsRoundActive()
	if only then
		Remotes.CharacterRoster:FireClient(only, roster, roundActive)
	else
		Remotes.CharacterRoster:FireAllClients(roster, roundActive)
	end
end

--------------------------------------------------------------------------------
-- Aplicação
--------------------------------------------------------------------------------

-- Parte "de corpo": depende do character atual, então reaplica a cada spawn.
local function applyToCharacter(player: Player, character: Model)
	character:SetAttribute("SpeedMul", StatScaling.SpeedMultiplier(player))

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		local maxHealth = StatScaling.MaxHealth(player)
		humanoid.MaxHealth = maxHealth
		-- Só sobe a vida atual se ainda estava cheia (não cura quem já apanhou).
		if humanoid.Health >= humanoid.MaxHealth - 0.01 or humanoid.Health <= 0 then
			humanoid.Health = maxHealth
		end
	end
end

--[[
	ApplyCharacter(player, characterId)
	Aplica os 7 atributos do personagem no jogador. Devolve true se aplicou.
	Chamada pelo próprio SelectCharacter e de novo no início da partida
	(RoundManager.RoundPrepared) pra garantir que o character novo nasce com
	os números certos.
]]
function CharacterStatsApplier.ApplyCharacter(player: Player, characterId: unknown): boolean
	local character = CharacterData.GetById(characterId)
	if not character then
		return false
	end

	for _, statName in CharacterData.StatOrder do
		player:SetAttribute(StatScaling.AttributePrefix .. statName, (character.Stats :: any)[statName])
	end
	player:SetAttribute("CharacterId", character.Id)
	player:SetAttribute("CharacterNome", character.Nome)
	player:SetAttribute("CharacterApelido", character.Apelido)

	-- Passivas únicas: viram flag booleana pro sistema dono consultar.
	player:SetAttribute("PassivaCuraExtra", character.Id == "SofiaRibeiro" or nil)
	player:SetAttribute("PassivaCargaDupla", character.Id == "BrunoCarvalho" or nil)

	if player.Character then
		applyToCharacter(player, player.Character)
	end
	return true
end

--[[ GetChoice(player) -- id do personagem escolhido, ou nil. ]]
function CharacterStatsApplier.GetChoice(player: Player): string?
	return choiceOf[player]
end

--------------------------------------------------------------------------------
-- Escolha
--------------------------------------------------------------------------------

local function releaseChoice(player: Player)
	local previous = choiceOf[player]
	if previous and takenBy[previous] == player then
		takenBy[previous] = nil
	end
	choiceOf[player] = nil
end

local function setChoice(player: Player, characterId: string): boolean
	local owner = takenBy[characterId]
	if owner and owner ~= player and owner.Parent then
		return false -- já é de outro jogador
	end

	releaseChoice(player)
	takenBy[characterId] = player
	choiceOf[player] = characterId
	return CharacterStatsApplier.ApplyCharacter(player, characterId)
end

local function onSelect(player: Player, characterId: unknown)
	-- Trocar de personagem é só no lobby. Com a partida rodando, ignora.
	if RoundManager.IsRoundActive() then
		return
	end
	if not CharacterData.Exists(characterId) then
		return
	end
	if setChoice(player, characterId :: string) then
		broadcastRoster()
	end
end

--[[
	AssignMissing(players)
	Quem entrou na partida sem escolher recebe um personagem livre sorteado.
	Assim ninguém entra na ilha sem atributos. Chamado no RoundPrepared.
]]
function CharacterStatsApplier.AssignMissing(players: { Player })
	local rng = Random.new()

	for _, player in players do
		if choiceOf[player] then
			continue
		end

		local free: { string } = {}
		for _, character in CharacterData.Characters do
			local owner = takenBy[character.Id]
			if not owner or not owner.Parent then
				table.insert(free, character.Id)
			end
		end

		if #free == 0 then
			-- Mais jogadores que personagens: repete um (sem exclusividade).
			-- Não deveria acontecer dentro de GameConfig.Players.Max.
			local all = CharacterData.Characters
			CharacterStatsApplier.ApplyCharacter(player, all[rng:NextInteger(1, #all)].Id)
			warn(
				string.format(
					"[CharacterStatsApplier] Sem personagem livre pra %s (%d jogadores, %d personagens) -- repetindo um.",
					player.Name,
					#players,
					#CharacterData.Characters
				)
			)
			continue
		end

		setChoice(player, free[rng:NextInteger(1, #free)])
	end

	broadcastRoster()
end

--------------------------------------------------------------------------------
-- Ciclo de vida
--------------------------------------------------------------------------------

local function watchPlayer(player: Player)
	player.CharacterAdded:Connect(function(character)
		local chosen = choiceOf[player]
		if chosen then
			-- Reaplica o que é de corpo (MaxHealth / SpeedMul) no character novo.
			task.defer(function()
				if player.Character == character then
					applyToCharacter(player, character)
				end
			end)
		end
	end)

	-- Estado atual pra quem acabou de entrar.
	broadcastRoster(player)
end

function CharacterStatsApplier.Init()
	Remotes.SelectCharacter.OnServerEvent:Connect(onSelect)

	Players.PlayerAdded:Connect(watchPlayer)
	for _, player in Players:GetPlayers() do
		watchPlayer(player)
	end

	Players.PlayerRemoving:Connect(function(player)
		releaseChoice(player)
		broadcastRoster()
	end)

	-- Início de partida: quem não escolheu ganha um livre, e todo mundo tem os
	-- atributos reaplicados no character recém-carregado.
	RoundManager.RoundPrepared.Event:Connect(function(players: { Player })
		CharacterStatsApplier.AssignMissing(players)
		for _, player in players do
			local chosen = choiceOf[player]
			if chosen then
				CharacterStatsApplier.ApplyCharacter(player, chosen)
			end
		end
	end)

	print(
		string.format(
			"[CharacterStatsApplier] %d personagens carregados (%d pontos cada).",
			#CharacterData.Characters,
			CharacterData.TotalPoints
		)
	)
end

return CharacterStatsApplier
