--!strict
-- Uma sala por servidor: Lobby -> Waiting -> Starting -> Playing -> Intermission.
-- O snapshot e todas as reservas são autoritativos no servidor.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local GameConfig = require(ReplicatedStorage.Modules.GameConfig)
local CharacterData = require(ReplicatedStorage.Modules.CharacterData)
local LoadoutData = require(ReplicatedStorage.Modules.LoadoutData)
local Remotes = require(ReplicatedStorage.Modules.Remotes)
local Selection = require(script.Parent.CharacterStatsApplier)
local RoundManager = require(script.Parent.RoundManager)

local WaitingRoomManager = {}
local members: { Player } = {}
local state = "Lobby"
local endsAt = 0
local generation = 0
local capacity = math.min(GameConfig.Players.Max, #CharacterData.Characters)
-- Fora do terreno da ilha (IslandLayout.AreaHalf = 960) e ao lado do Lobby
-- (LobbyManager.LOBBY_ORIGIN).
local origin = Vector3.new(120, 10, -1500)
local lastRequest: { [Player]: number } = {}

local function setState(value: string)
	state = value
	ReplicatedStorage:SetAttribute("MatchState", value)
end

local function minimum(): number
	if GameConfig.Testing.SoloStart then
		return 1
	end
	return math.max(2, GameConfig.Players.Min)
end

local function isDevRoleTester(player: Player): boolean
	return GameConfig.Testing.DevRoleChooser == true
		and table.find(GameConfig.Testing.DevRoleUserIds, player.UserId) ~= nil
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
			userId = player.UserId, name = player.DisplayName,
			characterId = Selection.GetChoice(player),
			skinId = player:GetAttribute("SkinId"), perkId = player:GetAttribute("PerkId"),
			devRole = player:GetAttribute("DevForceRole"),
			canDevRole = isDevRoleTester(player),
			ready = player:GetAttribute("MatchReady") == true,
		})
	end
	local snapshot = {
		state = state, endsAt = endsAt, capacity = capacity, minimum = minimum(),
		members = list, roster = Selection.GetRoster(),
	}
	if only then Remotes.WaitingRoom:FireClient(only, snapshot)
	else Remotes.WaitingRoom:FireAllClients(snapshot) end
end

local function teleportToRoom(player: Player)
	local index = table.find(members, player)
	if not index or player:GetAttribute("InWaitingRoom") ~= true then return end
	local character = player.Character
	if character then
		character:PivotTo(CFrame.new(origin + Vector3.new((index - 1) % 4 * 7 - 10, 4, math.floor((index - 1) / 4) * 8)))
	end
end

local function allReady(): boolean
	if #members < minimum() then return false end
	for _, player in members do
		if player.Parent ~= Players or player:GetAttribute("MatchReady") ~= true then
			return false
		end
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
	-- A sala só reabre depois de concluir todos os respawns.
	setState("Returning")
	for _, player in previous do
		player:SetAttribute("InWaitingRoom", nil)
		player:SetAttribute("MatchReady", nil)
		player:SetAttribute("InRound", nil)
		player:SetAttribute("Role", nil)
		player:SetAttribute("DevForceRole", nil)
		Selection.ClearChoice(player)
	end
	broadcast()
	return previous
end

function WaitingRoomManager.OpenLobby()
	setState("Lobby")
	broadcast()
end

local function updateCountdown()
	resetCountdown()
	if state ~= "Waiting" then return end
	if #members == 0 then
		setState("Lobby")
		broadcast()
		return
	end
	if not allReady() then broadcast(); return end
	endsAt = Workspace:GetServerTimeNow() + GameConfig.Round.WaitingCountdown
	local token = generation
	broadcast()
	task.delay(GameConfig.Round.WaitingCountdown, function()
		if generation ~= token or state ~= "Waiting" or not allReady() then return end
		-- Congela a lista e as escolhas ANTES de qualquer LoadCharacter que ceda execução.
		setState("Starting")
		endsAt = 0
		local participants = table.clone(members)
		for _, player in participants do
			player:SetAttribute("InWaitingRoom", nil)
		end
		broadcast()
		local ok, err = pcall(RoundManager.StartRound, participants)
		if not ok then
			local reason = tostring(err)
			warn("[WaitingRoom] Não foi possível iniciar a partida: " .. reason)
			WaitingRoomManager.Reset()
			for _, player in participants do
				if player.Parent == Players then
					Remotes.LobbyMessage:FireClient(player, "Não foi possível preparar a partida: " .. string.sub(reason, 1, 160))
					pcall(function() player:LoadCharacter() end)
				end
			end
			WaitingRoomManager.OpenLobby()
		end
	end)
end

function WaitingRoomManager.Join(player: Player)
	if player.Parent ~= Players or player:GetAttribute("InRound") == true then return end
	if table.find(members, player) then broadcast(player); return end
	if state ~= "Lobby" and state ~= "Waiting" then
		Remotes.LobbyMessage:FireClient(player, "Partida em andamento. Aguarde a próxima sala.")
		return
	end
	if #members >= capacity then
		Remotes.LobbyMessage:FireClient(player, string.format("Sala cheia: %d vagas, um personagem diferente por jogador.", capacity))
		return
	end
	Selection.ClearChoice(player)
	table.insert(members, player)
	player:SetAttribute("Role", nil)
	player:SetAttribute("MatchReady", false)
	player:SetAttribute("SkinId", "Padrao")
	player:SetAttribute("PerkId", "Nenhum")
	player:SetAttribute("DevForceRole", nil)
	setState("Waiting")
	player:SetAttribute("InWaitingRoom", true)
	teleportToRoom(player)
	updateCountdown()
end

local function leave(player: Player, disconnecting: boolean)
	local index = table.find(members, player)
	if not index or state ~= "Waiting" then return end
	table.remove(members, index)
	player:SetAttribute("InWaitingRoom", nil)
	player:SetAttribute("MatchReady", nil)
	player:SetAttribute("DevForceRole", nil)
	Selection.ClearChoice(player)
	updateCountdown()
	if not disconnecting and player.Character then
		local spawn = Workspace:FindFirstChild("LobbySpawn")
		if spawn and spawn:IsA("BasePart") then
			player.Character:PivotTo(spawn.CFrame + Vector3.new(0, 4, 0))
		end
	end
end

local function makeRoom()
	local folder = Workspace:FindFirstChild("MatchWaitingRoom")
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = "MatchWaitingRoom"
		folder.Parent = Workspace
	end
	local function part(name: string, size: Vector3, offset: Vector3, color: Color3): Part
		local item = folder:FindFirstChild(name) :: Part?
		if not item then item = Instance.new("Part"); item.Name = name; item.Parent = folder end
		item.Anchored = true
		item.Size = size
		item.Position = origin + offset
		item.Color = color
		item.Material = Enum.Material.WoodPlanks
		return item
	end
	part("Floor", Vector3.new(52, 2, 44), Vector3.new(0, -1, 0), Color3.fromRGB(64, 53, 44))
	part("BackWall", Vector3.new(52, 12, 1), Vector3.new(0, 6, -22), Color3.fromRGB(37, 43, 40))
	part("LeftRail", Vector3.new(1, 5, 44), Vector3.new(-26, 2.5, 0), Color3.fromRGB(49, 56, 49))
	part("RightRail", Vector3.new(1, 5, 44), Vector3.new(26, 2.5, 0), Color3.fromRGB(49, 56, 49))
	part("FrontRail", Vector3.new(52, 5, 1), Vector3.new(0, 2.5, 22), Color3.fromRGB(49, 56, 49))
	for i = 1, 3 do
		part("Bench" .. i, Vector3.new(12, 2, 3), Vector3.new((i - 2) * 16, 1, -15), Color3.fromRGB(97, 70, 46))
	end
	local sign = part("Sign", Vector3.new(28, 4, 0.5), Vector3.new(0, 8, -21), Color3.fromRGB(25, 29, 28))
	if not sign:FindFirstChild("Label") then
		local gui = Instance.new("SurfaceGui")
		gui.Name = "Label"
		gui.Face = Enum.NormalId.Back
		gui.Parent = sign
		local label = Instance.new("TextLabel")
		label.Size = UDim2.fromScale(1, 1)
		label.BackgroundTransparency = 1
		label.Text = "NÁUFRAGOS\nSALA DE ESPERA"
		label.Font = Enum.Font.GothamBold
		label.TextScaled = true
		label.TextColor3 = Color3.fromRGB(228, 213, 178)
		label.Parent = gui
	end
end

local function watchPlayer(player: Player)
	player.CharacterAdded:Connect(function(character)
		task.spawn(function()
			if character:WaitForChild("HumanoidRootPart", 10) and player.Character == character then
				teleportToRoom(player)
			end
		end)
	end)
end

function WaitingRoomManager.Init()
	setState("Lobby")
	makeRoom()
	Players.PlayerAdded:Connect(watchPlayer)
	for _, player in Players:GetPlayers() do watchPlayer(player) end
	Players.PlayerRemoving:Connect(function(player)
		leave(player, true)
		lastRequest[player] = nil
	end)
	Selection.SelectionChanged.Event:Connect(function(player: Player)
		if state == "Waiting" and table.find(members, player) then
			player:SetAttribute("MatchReady", false)
			updateCountdown()
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
		if state ~= "Waiting" or not table.find(members, player) then return end
		if action == "Leave" then leave(player, false); return end
		if action == "Ready" then
			player:SetAttribute("MatchReady", player:GetAttribute("MatchReady") ~= true)
		elseif action == "DevRole" and isDevRoleTester(player) then
			if value == nil or value == "Random" then
				player:SetAttribute("DevForceRole", nil)
			elseif isRole(value) then
				player:SetAttribute("DevForceRole", value)
			else
				return
			end
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
		updateCountdown()
	end)
end

return WaitingRoomManager
