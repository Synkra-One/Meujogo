--!strict
--[[
	CharacterStatsApplier
	Fonte autoritativa da escolha de sobrevivente e da aplicacao dos atributos.

	A escolha acontece numa etapa propria, antes do spawn da partida:
	  BeginSelection -> SelectCharacter("Select", id) -> "Confirm"
	  -> FinishSelection -> RoundManager.StartRound.

	O cliente nunca decide disponibilidade, exclusividade, prazo ou personagem
	final. Uma escolha apenas fica reservada de verdade ao confirmar. No fim do
	tempo, o servidor confirma a escolha atual e resolve qualquer conflito com o
	primeiro sobrevivente livre. O primeiro disponivel ja vem pre-selecionado.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local GameConfig = require(ReplicatedStorage.Modules.GameConfig)
local CharacterData = require(ReplicatedStorage.Modules.CharacterData)
local Remotes = require(ReplicatedStorage.Modules.Remotes)
local StatScaling = require(ReplicatedStorage.Modules.StatScaling)
local SelectionConfig = require(ReplicatedStorage.Modules.SurvivorSelectionConfig)

local RoundManager = require(script.Parent.RoundManager)

local CharacterStatsApplier = {}
CharacterStatsApplier.SelectionChanged = Instance.new("BindableEvent")

local MONSTER_CHARACTER_ID = "Jason"

-- Escolhas em foco (confirmadas ou nao).
local choiceOf: { [Player]: string } = {}
-- Exclusividade definitiva: so entra aqui ao confirmar.
local takenBy: { [string]: Player } = {}
local confirmedOf: { [Player]: boolean } = {}
local selectionParticipants: { [Player]: boolean } = {}
local selectionActive = false
local selectionEndsAt = 0
local lastRequest: { [Player]: number } = {}

--------------------------------------------------------------------------------
-- Snapshot da selecao
--------------------------------------------------------------------------------

local function buildRoster(): { [string]: number }
	local roster: { [string]: number } = {}
	for id, player in takenBy do
		if player.Parent == Players then roster[id] = player.UserId end
	end
	return roster
end

CharacterStatsApplier.GetRoster = buildRoster

local function buildSelectionSnapshot(): { [string]: any }
	local choices: { [number]: string } = {}
	local confirmed: { [number]: boolean } = {}
	for player in selectionParticipants do
		if player.Parent == Players then
			local choice = choiceOf[player]
			if choice then choices[player.UserId] = choice end
			if confirmedOf[player] then confirmed[player.UserId] = true end
		end
	end

	local availability: { [string]: string } = {}
	for _, character in CharacterData.Characters do
		availability[character.Id] = SelectionConfig.GetAvailability(character.Id)
	end

	return {
		state = if selectionActive then "Selecting" else "Closed",
		endsAt = selectionEndsAt,
		roster = buildRoster(),
		choices = choices,
		confirmed = confirmed,
		availability = availability,
	}
end

local function broadcastSelection(only: Player?)
	local snapshot = buildSelectionSnapshot()
	if only then
		Remotes.CharacterRoster:FireClient(only, snapshot)
	else
		Remotes.CharacterRoster:FireAllClients(snapshot)
	end
end

CharacterStatsApplier.GetSelectionSnapshot = buildSelectionSnapshot

--------------------------------------------------------------------------------
-- Aplicacao de atributos
--------------------------------------------------------------------------------

local function applyToCharacter(player: Player, character: Model)
	character:SetAttribute("SpeedMul", StatScaling.SpeedMultiplier(player))
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		local wasFull = humanoid.Health >= humanoid.MaxHealth - 0.01
		local maxHealth = StatScaling.MaxHealth(player)
		humanoid.MaxHealth = maxHealth
		if wasFull then humanoid.Health = maxHealth end
	end
end

function CharacterStatsApplier.ApplyCharacter(player: Player, characterId: unknown): boolean
	local character = CharacterData.GetById(characterId)
	if not character then return false end
	for _, statName in CharacterData.StatOrder do
		player:SetAttribute(StatScaling.AttributePrefix .. statName, (character.Stats :: any)[statName])
	end
	player:SetAttribute("CharacterId", character.Id)
	player:SetAttribute("CharacterNome", character.Nome)
	player:SetAttribute("CharacterApelido", character.Apelido)
	player:SetAttribute("PassivaCuraExtra", character.Id == "SofiaRibeiro" or nil)
	player:SetAttribute("PassivaCargaDupla", character.Id == "BrunoCarvalho" or nil)
	if player.Character then applyToCharacter(player, player.Character) end
	return true
end

function CharacterStatsApplier.GetChoice(player: Player): string?
	return choiceOf[player]
end

function CharacterStatsApplier.IsConfirmed(player: Player): boolean
	return confirmedOf[player] == true
end

--------------------------------------------------------------------------------
-- Reserva, validacao e ciclo da selecao
--------------------------------------------------------------------------------

local function releaseChoice(player: Player)
	local previous = choiceOf[player]
	if previous and takenBy[previous] == player then takenBy[previous] = nil end
	choiceOf[player] = nil
	confirmedOf[player] = nil
	player:SetAttribute("CharacterSelectionConfirmed", nil)
end

local function clearAppliedCharacter(player: Player)
	for _, statName in CharacterData.StatOrder do
		player:SetAttribute(StatScaling.AttributePrefix .. statName, nil)
	end
	for _, name in {
		"CharacterId", "CharacterNome", "CharacterApelido",
		"PassivaCuraExtra", "PassivaCargaDupla", "SkinId", "PerkId",
	} do
		player:SetAttribute(name, nil)
	end
	if player.Character then applyToCharacter(player, player.Character) end
end

function CharacterStatsApplier.ClearChoice(player: Player)
	releaseChoice(player)
	clearAppliedCharacter(player)
	broadcastSelection()
end

local function canUseSelection(player: Player): boolean
	return selectionActive
		and selectionParticipants[player] == true
		and player.Parent == Players
		and player:GetAttribute("CharacterSelectOpen") == true
		and player:GetAttribute("Role") ~= GameConfig.Roles.Monster
		and ReplicatedStorage:GetAttribute("MatchState") == "CharacterSelection"
		and Workspace:GetServerTimeNow() < selectionEndsAt
end

local function selectTentative(player: Player, characterId: string): boolean
	if not SelectionConfig.IsSelectable(characterId) then return false end
	local owner = takenBy[characterId]
	if owner and owner ~= player and owner.Parent == Players then return false end
	-- Selection is data only. Applying attributes here changed the lobby
	-- Humanoid's MaxHealth/SpeedMul while the player was still standing in the
	-- waiting area, which could look exactly like damage or an early spawn.
	-- RoundPrepared applies the final confirmed choice to the game character.
	choiceOf[player] = characterId
	return true
end

local function firstFreeCharacter(alsoAvoid: { [string]: boolean }?): string?
	local preferred = SelectionConfig.DefaultCharacterId
	local preferredOwner = takenBy[preferred]
	if SelectionConfig.IsSelectable(preferred)
		and (not preferredOwner or preferredOwner.Parent ~= Players)
		and (not alsoAvoid or not alsoAvoid[preferred]) then
		return preferred
	end
	for _, character in CharacterData.Characters do
		local id = character.Id
		local owner = takenBy[id]
		if SelectionConfig.IsSelectable(id)
			and (not owner or owner.Parent ~= Players)
			and (not alsoAvoid or not alsoAvoid[id]) then
			return id
		end
	end
	return nil
end

local function confirmCurrent(player: Player): boolean
	if confirmedOf[player] then return true end
	local characterId = choiceOf[player]
	if not characterId or not SelectionConfig.IsSelectable(characterId) then return false end
	local owner = takenBy[characterId]
	if owner and owner ~= player and owner.Parent == Players then return false end
	takenBy[characterId] = player
	confirmedOf[player] = true
	player:SetAttribute("CharacterSelectionConfirmed", true)
	player:SetAttribute("CharacterSelectOpen", nil)
	return true
end

function CharacterStatsApplier.BeginSelection(players: { Player }, endsAt: number): boolean
	selectionParticipants = {}
	selectionActive = true
	selectionEndsAt = endsAt

	for _, player in players do
		if player.Parent ~= Players then continue end
		releaseChoice(player)
		selectionParticipants[player] = true
		player:SetAttribute("CharacterSelectOpen", nil)
		if player:GetAttribute("Role") == GameConfig.Roles.Monster then
			choiceOf[player] = MONSTER_CHARACTER_ID
			takenBy[MONSTER_CHARACTER_ID] = player
			confirmedOf[player] = true
			player:SetAttribute("CharacterSelectionConfirmed", true)
		else
			-- Nao reserve Rafael (ou qualquer outro) automaticamente. O card
			-- so fica disponivel ate o jogador clicar; o fallback e resolvido
			-- pelo servidor em FinishSelection se o tempo acabar sem escolha.
			choiceOf[player] = nil
			confirmedOf[player] = nil
			player:SetAttribute("CharacterSelectionConfirmed", nil)
			player:SetAttribute("CharacterSelectOpen", true)
		end
	end
	broadcastSelection()
	return true
end

function CharacterStatsApplier.EveryoneConfirmed(players: { Player }): boolean
	for _, player in players do
		if player.Parent == Players and selectionParticipants[player] and not confirmedOf[player] then
			return false
		end
	end
	return true
end

-- Confirma automaticamente quem ainda nao confirmou. Conflitos de escolhas
-- tentativas sao resolvidos de forma deterministica pelo primeiro livre.
function CharacterStatsApplier.FinishSelection(players: { Player }): boolean
	if not selectionActive then return false end
	for _, player in players do
		if player.Parent ~= Players or not selectionParticipants[player] or confirmedOf[player] then continue end
		if not confirmCurrent(player) then
			local fallback = firstFreeCharacter()
			if not fallback or not selectTentative(player, fallback) or not confirmCurrent(player) then
				return false
			end
		end
	end
	selectionActive = false
	selectionEndsAt = 0
	for player in selectionParticipants do
		if player.Parent == Players then player:SetAttribute("CharacterSelectOpen", nil) end
	end
	-- Nao publique "Closed" neste ponto. WaitingRoomManager ainda precisa
	-- publicar a transicao Selecting -> Starting e preparar os personagens.
	-- O broadcast prematuro fazia a UI desaparecer antes de a partida puxar.
	return true
end

function CharacterStatsApplier.CancelSelection(players: { Player }?)
	selectionActive = false
	selectionEndsAt = 0
	for player in selectionParticipants do
		if not players or table.find(players, player) then
			player:SetAttribute("CharacterSelectOpen", nil)
			releaseChoice(player)
			clearAppliedCharacter(player)
		end
	end
	selectionParticipants = {}
	broadcastSelection()
end

function CharacterStatsApplier.RemoveParticipant(player: Player)
	selectionParticipants[player] = nil
	player:SetAttribute("CharacterSelectOpen", nil)
	releaseChoice(player)
	broadcastSelection()
	CharacterStatsApplier.SelectionChanged:Fire(player, "Left")
end

local function reject(player: Player, message: string)
	Remotes.LobbyMessage:FireClient(player, message)
	broadcastSelection(player)
end

local function onSelect(player: Player, actionOrId: unknown, value: unknown)
	local now = os.clock()
	if actionOrId == "Sync" then broadcastSelection(player); return end

	-- Compatibilidade com o contrato antigo FireServer(characterId).
	local action = actionOrId
	local characterId = value
	if CharacterData.Exists(actionOrId) and value == nil then
		action = "Select"
		characterId = actionOrId
	end
	-- Confirmar pode acontecer imediatamente depois do clique no card. O
	-- limite anti-spam vale para trocas de personagem, mas nunca pode engolir
	-- o comando final de pronto.
	if action ~= "Confirm" and now - (lastRequest[player] or -math.huge) < 0.08 then return end
	lastRequest[player] = now
	if not canUseSelection(player) then return end

	if action == "Select" then
		if type(characterId) ~= "string" or not SelectionConfig.IsSelectable(characterId) then
			reject(player, "Esse sobrevivente está bloqueado ou indisponível.")
			return
		end
		if not selectTentative(player, characterId) then
			reject(player, "Esse sobrevivente já foi confirmado por outro jogador.")
			return
		end
		player:SetAttribute("CharacterSelectionConfirmed", nil)
		CharacterStatsApplier.SelectionChanged:Fire(player, "Selected")
		broadcastSelection()
	elseif action == "Confirm" then
		if not confirmCurrent(player) then
			reject(player, "Esse sobrevivente acabou de ser escolhido. Selecione outro disponível.")
			return
		end
		CharacterStatsApplier.SelectionChanged:Fire(player, "Confirmed")
		-- SelectionChanged is synchronous. When this was the last player,
		-- WaitingRoomManager finishes the selection immediately and advances
		-- to Starting. Do not publish a stale `Closed` roster afterwards: the
		-- client would hide the ready UI before the round was prepared.
		if selectionActive then
			broadcastSelection()
		end
	end
end

--------------------------------------------------------------------------------
-- Fallback e ciclo de vida
--------------------------------------------------------------------------------

function CharacterStatsApplier.AssignMissing(players: { Player }): boolean
	-- Valida capacidade antes de alterar qualquer jogador; uma falha nunca
	-- deixa metade da lista atribuida e metade sem personagem.
	local humansMissing = 0
	local freeCount = 0
	for _, player in players do
		if not choiceOf[player] and player:GetAttribute("Role") ~= GameConfig.Roles.Monster then
			humansMissing += 1
		end
	end
	for _, character in CharacterData.Characters do
		local owner = takenBy[character.Id]
		if SelectionConfig.IsSelectable(character.Id) and (not owner or owner.Parent ~= Players) then
			freeCount += 1
		end
	end
	if humansMissing > freeCount then return false end

	for _, player in players do
		if choiceOf[player] then continue end
		if player:GetAttribute("Role") == GameConfig.Roles.Monster then
			choiceOf[player] = MONSTER_CHARACTER_ID
			takenBy[MONSTER_CHARACTER_ID] = player
			confirmedOf[player] = true
			if player:GetAttribute("InRound") == true then
				CharacterStatsApplier.ApplyCharacter(player, MONSTER_CHARACTER_ID)
			end
		else
			local free = firstFreeCharacter()
			if not free then return false end
			choiceOf[player] = free
			takenBy[free] = player
			confirmedOf[player] = true
			player:SetAttribute("CharacterSelectionConfirmed", true)
			if player:GetAttribute("InRound") == true then
				CharacterStatsApplier.ApplyCharacter(player, free)
			end
		end
	end
	broadcastSelection()
	return true
end

local function watchPlayer(player: Player)
	player.CharacterAdded:Connect(function(character)
		if choiceOf[player] and player:GetAttribute("InRound") == true then
			task.defer(function()
				if player.Character == character then applyToCharacter(player, character) end
			end)
		end
	end)
	broadcastSelection(player)
end

function CharacterStatsApplier.Init()
	Remotes.SelectCharacter.OnServerEvent:Connect(onSelect)
	Players.PlayerAdded:Connect(watchPlayer)
	for _, player in Players:GetPlayers() do watchPlayer(player) end
	Players.PlayerRemoving:Connect(function(player)
		selectionParticipants[player] = nil
		releaseChoice(player)
		lastRequest[player] = nil
		broadcastSelection()
	end)

	-- Rede de seguranca para chamadas diretas de StartRound (testes/admin): o
	-- fluxo normal ja chega aqui com todos confirmados antes do spawn.
	RoundManager.RoundPrepared.Event:Connect(function(players: { Player })
		local missing = {}
		for _, player in players do
			player:SetAttribute("CharacterSelectOpen", nil)
			if choiceOf[player] then
				CharacterStatsApplier.ApplyCharacter(player, choiceOf[player])
			else
				table.insert(missing, player)
			end
		end
		if #missing > 0 and not CharacterStatsApplier.AssignMissing(missing) then
			warn("[CharacterStatsApplier] Nao foi possivel atribuir fallback a todos os participantes.")
		end
		-- Agora o cliente pode fechar a tela de escolha com seguranca: o corpo
		-- real ja foi criado e RoundPrepared significa que a partida comecou.
		broadcastSelection()
	end)

	print(string.format(
		"[CharacterStatsApplier] %d sobreviventes carregados (%d pontos cada).",
		#CharacterData.Characters,
		CharacterData.TotalPoints
	))
end

return CharacterStatsApplier
