--!strict
--[[
	CharacterStatsApplier
	Dono da ESCOLHA de personagem e de aplicar os 7 atributos no jogador.

	DUAS METADES:

	1) REGISTRO DE ESCOLHA (sala de espera)
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

local GameConfig = require(ReplicatedStorage.Modules.GameConfig)
local CharacterData = require(ReplicatedStorage.Modules.CharacterData)
local Remotes = require(ReplicatedStorage.Modules.Remotes)
local StatScaling = require(ReplicatedStorage.Modules.StatScaling)

local RoundManager = require(script.Parent.RoundManager)

local CharacterStatsApplier = {}
CharacterStatsApplier.SelectionChanged = Instance.new("BindableEvent")

local MONSTER_CHARACTER_ID = "Jason"

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

CharacterStatsApplier.GetRoster = buildRoster

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
		local wasFull = humanoid.Health >= humanoid.MaxHealth - 0.01
		local maxHealth = StatScaling.MaxHealth(player)
		humanoid.MaxHealth = maxHealth
		-- Só sobe a vida atual se ainda estava cheia (não cura quem já apanhou).
		if wasFull then
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

function CharacterStatsApplier.ClearChoice(player: Player)
	releaseChoice(player)
	for _, statName in CharacterData.StatOrder do
		player:SetAttribute(StatScaling.AttributePrefix .. statName, nil)
	end
	for _, name in { "CharacterId", "CharacterNome", "CharacterApelido", "PassivaCuraExtra", "PassivaCargaDupla", "SkinId", "PerkId" } do
		player:SetAttribute(name, nil)
	end
	if player.Character then applyToCharacter(player, player.Character) end
	broadcastRoster()
end

local function canSelectDuringRound(player: Player, characterId: unknown): boolean
	if player:GetAttribute("InRound") ~= true
		or player:GetAttribute("CharacterSelectOpen") ~= true
		or ReplicatedStorage:GetAttribute("MatchState") ~= "Playing"
		or RoundManager.IsRoundActive() ~= true then
		return false
	end
	if player:GetAttribute("Role") == GameConfig.Roles.Monster then
		return false
	end
	if CharacterData.IsMonsterCharacter(characterId) then
		return false
	end
	return true
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
	-- A escolha de personagem agora acontece DEPOIS do sorteio do papel. Antes
	-- da partida, a sala só prepara skin/perk/pronto.
	if not canSelectDuringRound(player, characterId) then
		return
	end
	if not CharacterData.Exists(characterId) then
		return
	end
	if choiceOf[player] == characterId then return end
	if setChoice(player, characterId :: string) then
		player:SetAttribute("CharacterSelectOpen", nil)
		CharacterStatsApplier.SelectionChanged:Fire(player)
		broadcastRoster()
	else
		Remotes.LobbyMessage:FireClient(player, "Esse personagem acabou de ser escolhido por outro jogador.")
		broadcastRoster(player)
	end
end

--[[
	AssignMissing(players)
	Quem entrou na partida sem escolher recebe um personagem livre sorteado.
	API auxiliar: falha sem atribuir se não houver opções livres suficientes.
]]
function CharacterStatsApplier.AssignMissing(players: { Player }): boolean
	-- Nunca repetir personagens, mesmo se esta API for chamada fora da sala.
	local missing = 0
	local available = 0
	for _, player in players do
		if not choiceOf[player] then missing += 1 end
	end
	for _, character in CharacterData.Characters do
		local owner = takenBy[character.Id]
		if not owner or not owner.Parent then available += 1 end
	end
	if missing > available then return false end
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

		setChoice(player, free[rng:NextInteger(1, #free)])
	end

	broadcastRoster()
	return true
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

	-- Depois do sorteio: Jason automático para Monstro; humanos escolhem
	-- personagem quando a partida já está em Playing.
	RoundManager.RoundPrepared.Event:Connect(function(players: { Player })
		for _, player in players do
			if player:GetAttribute("Role") == GameConfig.Roles.Monster then
				if setChoice(player, MONSTER_CHARACTER_ID) then
					player:SetAttribute("CharacterSelectOpen", nil)
				end
			else
				local chosen = choiceOf[player]
				if chosen then
					CharacterStatsApplier.ApplyCharacter(player, chosen)
					player:SetAttribute("CharacterSelectOpen", nil)
				else
					player:SetAttribute("CharacterSelectOpen", true)
					if player.Character then
						applyToCharacter(player, player.Character)
					end
				end
			end
		end
		broadcastRoster()
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
