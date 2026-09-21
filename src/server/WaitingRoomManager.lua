--!strict
-- Uma fila por servidor: Lobby -> Waiting -> Selecting -> Starting -> Playing.
-- A etapa Selecting reutiliza o mesmo fluxo autoritativo; nao existe uma
-- segunda contagem local capaz de iniciar a partida por conta propria.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local GameConfig = require(ReplicatedStorage.Modules.GameConfig)
local LoadoutData = require(ReplicatedStorage.Modules.LoadoutData)
local Remotes = require(ReplicatedStorage.Modules.Remotes)
local SelectionConfig = require(ReplicatedStorage.Modules.SurvivorSelectionConfig)
local Selection = require(script.Parent.CharacterStatsApplier)
local RoleAssignment = require(script.Parent.RoleAssignment)
local RoundManager = require(script.Parent.RoundManager)
local CharacterPresentation = require(script.Parent.CharacterPresentation)

local WaitingRoomManager = {}
local members: { Player } = {}
local state = "Lobby"
local endsAt = 0
local generation = 0
local capacity = math.min(GameConfig.Players.Max, #SelectionConfig.GetSelectableCharacters())
local lastRequest: { [Player]: number } = {}

local function setState(value: string)
	state = value
	ReplicatedStorage:SetAttribute("MatchState", value)
end

local function minimum(): number
	if GameConfig.Testing.SoloStart then return 1 end
	return math.max(2, GameConfig.Players.Min)
end

local function isDevRoleTester(player: Player): boolean
	if GameConfig.Testing.DevRoleChooser ~= true then return false end
	if RunService:IsStudio() then return true end
	return table.find(GameConfig.Testing.DevRoleUserIds, player.UserId) ~= nil
end

local function isRole(value: unknown): boolean
	return value == GameConfig.Roles.Survivor
		or value == GameConfig.Roles.Monster
		or value == GameConfig.Roles.Spy
end

local function broadcast(only: Player?)
	local list = {}
	for _, player in members do
		table.insert(list, {
			userId = player.UserId,
			name = player.DisplayName,
			characterId = Selection.GetChoice(player),
			skinId = player:GetAttribute("SkinId"),
			perkId = player:GetAttribute("PerkId"),
			devRole = player:GetAttribute("DevForceRole"),
			canDevRole = isDevRoleTester(player),
			ready = player:GetAttribute("MatchReady") == true,
			selectionConfirmed = Selection.IsConfirmed(player),
		})
	end
	local snapshot = {
		state = state,
		endsAt = endsAt,
		capacity = capacity,
		minimum = minimum(),
		members = list,
		roster = Selection.GetRoster(),
	}
	if only then Remotes.WaitingRoom:FireClient(only, snapshot)
	else Remotes.WaitingRoom:FireAllClients(snapshot) end
end

local function allLobbyReady(): boolean
	if #members < minimum() then return false end
	for _, player in members do
		if player.Parent ~= Players or player:GetAttribute("MatchReady") ~= true then return false end
	end
	return true
end

local function resetCountdown()
	generation += 1
	endsAt = 0
end

function WaitingRoomManager.Reset()
	resetCountdown()
	local previous = members
	members = {}
	Selection.CancelSelection(previous)
	setState("Returning")
	for _, player in previous do
		player:SetAttribute("InWaitingRoom", nil)
		player:SetAttribute("MatchReady", nil)
		player:SetAttribute("InRound", nil)
		player:SetAttribute("Role", nil)
		player:SetAttribute("RoleRevealOpen", nil)
		player:SetAttribute("DevForceRole", nil)
		player:SetAttribute("CharacterSelectionConfirmed", nil)
		Selection.ClearChoice(player)
	end
	broadcast()
	return previous
end

function WaitingRoomManager.OpenLobby()
	setState("Lobby")
	broadcast()
end

local function startFrozenRound(token: number, participants: { Player })
	if generation ~= token or state ~= "Starting" then return end
	local ok, err = pcall(RoundManager.StartRound, participants)
	if ok then return end

	local reason = tostring(err)
	warn("[WaitingRoom] Não foi possível iniciar a partida: " .. reason)
	WaitingRoomManager.Reset()
	for _, player in participants do
		if player.Parent == Players then
			Remotes.LobbyMessage:FireClient(player, "Não foi possível preparar a partida: " .. string.sub(reason, 1, 160))
			pcall(function() CharacterPresentation.SpawnLobbyAvatar(player) end)
		end
	end
	WaitingRoomManager.OpenLobby()
end

local function finishSelection(token: number)
	if generation ~= token or state ~= "Selecting" then return end
	local participants = table.clone(members)
	if not Selection.FinishSelection(participants) then
		warn("[WaitingRoom] A selecao terminou sem sobreviventes livres suficientes.")
		Selection.CancelSelection(participants)
		setState("Waiting")
		endsAt = 0
		for _, player in participants do
			player:SetAttribute("Role", nil)
			player:SetAttribute("MatchReady", false)
		end
		broadcast()
		return
	end

	setState("Starting")
	endsAt = 0
	for _, player in participants do player:SetAttribute("InWaitingRoom", nil) end
	broadcast()
	-- StartRound bloqueia ate o fim da partida; nunca prender a thread do
	-- RemoteEvent que recebeu o ultimo botao Confirmar.
	task.spawn(function() startFrozenRound(token, participants) end)
end

local function beginSelection()
	if state ~= "Waiting" or not allLobbyReady() then return end
	resetCountdown()
	local token = generation
	local participants = table.clone(members)
	local revealDuration = SelectionConfig.RoleRevealDuration or 0
	setState("Revealing")
	endsAt = 0

	local ok, err = pcall(function()
		RoleAssignment.AssignRoles(participants)
		for _, player in participants do
			player:SetAttribute("RoleRevealOpen", true)
		end
	end)
	if not ok then
		warn("[WaitingRoom] Falha ao abrir selecao: " .. tostring(err))
		Selection.CancelSelection(participants)
		setState("Waiting")
		endsAt = 0
		for _, player in participants do
			player:SetAttribute("Role", nil)
			player:SetAttribute("MatchReady", false)
		end
		broadcast()
		return
	end

	broadcast()
	task.delay(revealDuration, function()
		if generation ~= token or state ~= "Revealing" then return end
		for _, player in participants do
			if player.Parent == Players then player:SetAttribute("RoleRevealOpen", nil) end
		end

		setState("Selecting")
		endsAt = Workspace:GetServerTimeNow() + SelectionConfig.Duration
		local selectionOk, selectionErr = pcall(function()
			assert(Selection.BeginSelection(participants, endsAt), "Nao ha sobreviventes disponiveis para todos.")
		end)
		if not selectionOk then
			warn("[WaitingRoom] Falha ao abrir selecao: " .. tostring(selectionErr))
			Selection.CancelSelection(participants)
			setState("Waiting")
			endsAt = 0
			for _, player in participants do
				player:SetAttribute("Role", nil)
				player:SetAttribute("MatchReady", false)
			end
			broadcast()
			return
		end

		broadcast()
		if Selection.EveryoneConfirmed(participants) then
			finishSelection(token)
			return
		end
		task.delay(SelectionConfig.Duration, function() finishSelection(token) end)
	end)
end

local function updateWaitingState()
	resetCountdown()
	if state ~= "Waiting" then return end
	if #members == 0 then
		setState("Lobby")
		broadcast()
		return
	end
	broadcast()
	if allLobbyReady() then beginSelection() end
end

function WaitingRoomManager.Join(player: Player)
	if player.Parent ~= Players or player:GetAttribute("InRound") == true then return end
	if table.find(members, player) then broadcast(player); return end
	if state ~= "Lobby" and state ~= "Waiting" then
		Remotes.LobbyMessage:FireClient(player, "Partida em andamento. Aguarde a próxima sala.")
		return
	end
	if #members >= capacity then
		Remotes.LobbyMessage:FireClient(player, string.format("Sala cheia: %d vagas, um sobrevivente por jogador.", capacity))
		return
	end
	Selection.ClearChoice(player)
	table.insert(members, player)
	player:SetAttribute("Role", nil)
	player:SetAttribute("MatchReady", false)
	player:SetAttribute("SkinId", "Padrao")
	player:SetAttribute("PerkId", "Nenhum")
	player:SetAttribute("DevForceRole", nil)
	player:SetAttribute("CharacterSelectionConfirmed", nil)
	setState("Waiting")
	player:SetAttribute("InWaitingRoom", true)
	updateWaitingState()
end

local function leaveWaiting(player: Player)
	local index = table.find(members, player)
	if not index or state ~= "Waiting" then return end
	table.remove(members, index)
	player:SetAttribute("InWaitingRoom", nil)
	player:SetAttribute("MatchReady", nil)
	player:SetAttribute("DevForceRole", nil)
	Selection.ClearChoice(player)
	updateWaitingState()
end

local function abortSelectionAfterDeparture(player: Player)
	local index = table.find(members, player)
	if not index or (state ~= "Selecting" and state ~= "Revealing") then return end
	table.remove(members, index)
	resetCountdown()
	Selection.RemoveParticipant(player)
	Selection.CancelSelection(members)
	player:SetAttribute("InWaitingRoom", nil)
	player:SetAttribute("RoleRevealOpen", nil)
	player:SetAttribute("MatchReady", nil)
	for _, member in members do
		member:SetAttribute("Role", nil)
		member:SetAttribute("MatchReady", false)
		member:SetAttribute("InWaitingRoom", true)
	end
	setState(if #members > 0 then "Waiting" else "Lobby")
	broadcast()
end

function WaitingRoomManager.Init()
	setState("Lobby")
	local oldRoom = Workspace:FindFirstChild("MatchWaitingRoom")
	if oldRoom then oldRoom:Destroy() end

	Players.PlayerRemoving:Connect(function(player)
		if state == "Selecting" or state == "Revealing" then abortSelectionAfterDeparture(player)
		else leaveWaiting(player) end
		lastRequest[player] = nil
	end)

	Selection.SelectionChanged.Event:Connect(function(_player: Player, action: string)
		if state ~= "Selecting" then return end
		broadcast()
		if action == "Confirmed" and Selection.EveryoneConfirmed(members) then
			finishSelection(generation)
		end
	end)

	RoundManager.RoundPrepared.Event:Connect(function()
		setState("Playing")
		broadcast()
	end)
	RoundManager.RoundEnded.Event:Connect(function()
		setState("Intermission")
		broadcast()
	end)

	Remotes.WaitingRoom.OnServerEvent:Connect(function(player: Player, action: unknown, value: unknown)
		local now = os.clock()
		if now - (lastRequest[player] or -math.huge) < 0.15 then return end
		lastRequest[player] = now
		if action == "Sync" then broadcast(player); return end
		if action == "Join" then
			if not table.find(members, player) then WaitingRoomManager.Join(player) end
			return
		end
		if state ~= "Waiting" or not table.find(members, player) then return end
		if action == "Leave" then leaveWaiting(player); return end
		if action == "Ready" then
			player:SetAttribute("MatchReady", player:GetAttribute("MatchReady") ~= true)
		elseif action == "DevRole" and isDevRoleTester(player) then
			if value == nil or value == "Random" then player:SetAttribute("DevForceRole", nil)
			elseif isRole(value) then player:SetAttribute("DevForceRole", value)
			else return end
			player:SetAttribute("MatchReady", false)
		elseif action == "Skin" and LoadoutData.GetSkin(value) then
			if player:GetAttribute("SkinId") == value then return end
			player:SetAttribute("SkinId", value)
			player:SetAttribute("MatchReady", false)
		elseif action == "Perk" and LoadoutData.GetPerk(value) then
			if player:GetAttribute("PerkId") == value then return end
			player:SetAttribute("PerkId", value)
			player:SetAttribute("MatchReady", false)
		else return end
		updateWaitingState()
	end)
end

return WaitingRoomManager
