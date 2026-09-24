--!strict
--[[
	CharacterPresentation mantém dois corpos deliberadamente distintos:
	avatar do usuário no lobby e rig base do jogo durante a partida.
	O StarterCharacter é global, portanto o rig de jogo fica em ServerStorage
	e só é clonado no começo da rodada. Futuras skins devem ser aplicadas nesse
	rig, nunca no avatar pessoal do jogador.
]]

local ServerStorage = game:GetService("ServerStorage")
local StarterPlayer = game:GetService("StarterPlayer")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

local Remotes = require(ReplicatedStorage.Modules.Remotes)

local CharacterPresentation = {}

local GAME_CHARACTER_ATTRIBUTE = "GameCharacter"
local LOBBY_CHARACTER_ATTRIBUTE = "LobbyAvatar"
local TEMPLATE_NAME = "GameCharacter"
local GAME_SCRIPTS_NAME = "GameCharacterScripts"
local TOKEN_ATTRIBUTE = "CharacterPresentationToken"
local READY_ATTRIBUTE = "CharacterPresentationReady"
local tokenByPlayer: { [Player]: number } = {}
local spawnGenerationByPlayer: { [Player]: number } = {}

local function nextSpawnGeneration(player: Player): number
	local generation = (spawnGenerationByPlayer[player] or 0) + 1
	spawnGenerationByPlayer[player] = generation
	return generation
end

local function getTemplate(): Model
	local template = ServerStorage:FindFirstChild(TEMPLATE_NAME)
	assert(template and template:IsA("Model"), "ServerStorage.GameCharacter não foi configurado.")
	assert(template:FindFirstChildOfClass("Humanoid"), "GameCharacter não possui Humanoid.")
	assert(template:FindFirstChild("HumanoidRootPart"), "GameCharacter não possui HumanoidRootPart.")
	return template
end

local function characterPivot(character: Model?): CFrame
	if character then
		local root = character:FindFirstChild("HumanoidRootPart")
		if root and root:IsA("BasePart") then return root.CFrame end
		return character:GetPivot()
	end
	return CFrame.new(0, 12, 0)
end

local function copyCharacterScripts(character: Model)
	-- O Animate customizado é R6. No lobby o Roblox fornece o Animate próprio
	-- do avatar (inclusive R15); no rig branco usamos exatamente o Animate que
	-- já fazia parte do antigo StarterCharacter.
	local gameScripts = ServerStorage:FindFirstChild(GAME_SCRIPTS_NAME)
	if gameScripts then
		for _, child in gameScripts:GetChildren() do
			if not character:FindFirstChild(child.Name) then child:Clone().Parent = character end
		end
	end

	local source = StarterPlayer:FindFirstChild("StarterCharacterScripts")
	if not source then return end
	for _, child in source:GetChildren() do
		if not character:FindFirstChild(child.Name) then child:Clone().Parent = character end
	end
end

local function prepareGameCharacter(character: Model, player: Player, pivot: CFrame)
	character.Name = player.Name
	character:SetAttribute(GAME_CHARACTER_ATTRIBUTE, true)
	for _, instance in character:GetDescendants() do
		if instance:IsA("BasePart") then
			instance.Anchored = false
			instance.CanTouch = true
			instance.CanQuery = true
		end
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid") :: Humanoid
	humanoid.DisplayName = player.DisplayName
	humanoid.Health = humanoid.MaxHealth
	if not humanoid:FindFirstChildOfClass("Animator") then Instance.new("Animator").Parent = humanoid end
	character.PrimaryPart = character:FindFirstChild("HumanoidRootPart") :: BasePart
	copyCharacterScripts(character)
	character:PivotTo(pivot)
end

function CharacterPresentation.IsGameCharacter(character: Model?): boolean
	return character ~= nil and character:GetAttribute(GAME_CHARACTER_ATTRIBUTE) == true
end

local function lobbyPivot(): CFrame
	local spawn = Workspace:FindFirstChild("LobbySpawn")
	if spawn and spawn:IsA("BasePart") then
		return spawn.CFrame + Vector3.new(0, 3, 0)
	end
	return CFrame.new(0, 12, -1500)
end

local function prepareLobbyAvatar(character: Model, player: Player, pivot: CFrame)
	character.Name = player.Name
	character:SetAttribute(LOBBY_CHARACTER_ATTRIBUTE, true)
	for _, instance in character:GetDescendants() do
		if instance:IsA("BasePart") then
			instance.Anchored = false
			instance.CanTouch = true
			instance.CanQuery = true
		end
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid") :: Humanoid
	humanoid.DisplayName = player.DisplayName
	humanoid.Health = humanoid.MaxHealth
	if not humanoid:FindFirstChildOfClass("Animator") then Instance.new("Animator").Parent = humanoid end
	local root = character:FindFirstChild("HumanoidRootPart")
	assert(root and root:IsA("BasePart"), "Avatar do lobby sem HumanoidRootPart.")
	character.PrimaryPart = root
	copyCharacterScripts(character)
	character:PivotTo(pivot)
end

function CharacterPresentation.SpawnGameCharacter(player: Player): Model
	nextSpawnGeneration(player)
	local oldCharacter = player.Character
	local oldHumanoid = oldCharacter and oldCharacter:FindFirstChildOfClass("Humanoid")
	if oldHumanoid then oldHumanoid:UnequipTools() end
	local template = getTemplate()
	local previousArchivable = template.Archivable
	template.Archivable = true
	local character = template:Clone()
	template.Archivable = previousArchivable
	prepareGameCharacter(character, player, characterPivot(oldCharacter))
	local token = (tokenByPlayer[player] or 0) + 1
	tokenByPlayer[player] = token
	character:SetAttribute(TOKEN_ATTRIBUTE, token)
	character:SetAttribute(READY_ATTRIBUTE, nil)
	local root = character:FindFirstChild("HumanoidRootPart") :: BasePart
	-- O carregamento não usa Anchor: a trava de MatchStateService assume a
	-- propriedade da raiz e zera o movimento sem criar conflito com sistemas
	-- de transporte, ragdoll ou câmera.
	if root:CanSetNetworkOwnership() then root:SetNetworkOwner(nil) end
	character.Parent = Workspace
	player.Character = character
	if oldCharacter and oldCharacter.Parent then oldCharacter:Destroy() end
	return character
end

function CharacterPresentation.AwaitGameCharacterReady(player: Player, character: Model, timeout: number?): boolean
	local token = character:GetAttribute(TOKEN_ATTRIBUTE)
	local deadline = os.clock() + (timeout or 6)
	while player.Parent and player.Character == character
		and character:GetAttribute(READY_ATTRIBUTE) ~= token and os.clock() < deadline do
		task.wait()
	end
	local ready = character:GetAttribute(READY_ATTRIBUTE) == token
	local root = character:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") and root:CanSetNetworkOwnership() then
		-- O MatchStateService libera a propriedade somente ao entrar em InMatch.
		root:SetNetworkOwner(nil)
	end
	if not ready then
		warn(string.format("[CharacterPresentation] Cliente de %s não confirmou o corpo em tempo; continuando com fallback.", player.Name))
	end
	return ready
end

function CharacterPresentation.SpawnLobbyAvatar(player: Player)
	-- Não usamos LoadCharacterAsync aqui. Quando existe um StarterCharacter/R6
	-- customizado, o Roblox pode publicar esse rig primeiro e aplicar o avatar
	-- pessoal depois, em outra operação. Durante essa janela as partes podem ser
	-- misturadas (o sintoma clássico são pernas do rig do jogo no avatar).
	-- Criar o Model a partir de HumanoidDescription monta um corpo completo
	-- antes de ele ser atribuído a Player.Character.
	local generation = nextSpawnGeneration(player)
	local oldCharacter = player.Character
	local pivot = lobbyPivot()
	local okDescription, description = pcall(function()
		return Players:GetHumanoidDescriptionFromUserIdAsync(player.UserId)
	end)
	if okDescription and description then
		local okModel, model = pcall(function()
			return Players:CreateHumanoidModelFromDescriptionAsync(
				description :: HumanoidDescription,
				Enum.HumanoidRigType.R15
			)
		end)
		if okModel and model and model:IsA("Model") then
			if spawnGenerationByPlayer[player] ~= generation or not player.Parent then
				model:Destroy()
				return
			end
			prepareLobbyAvatar(model, player, pivot)
			model.Parent = Workspace
			player.Character = model
			if oldCharacter and oldCharacter.Parent then oldCharacter:Destroy() end
			return
		end
		warn("[CharacterPresentation] Não foi possível criar o modelo completo do avatar: " .. tostring(model))
	else
		warn("[CharacterPresentation] Não foi possível obter a descrição do avatar: " .. tostring(description))
	end

	-- Fallback apenas para indisponibilidade temporária do serviço de avatar.
	-- O caminho normal acima continua sendo o único que publica o avatar no
	-- Workspace, já completamente montado.
	if spawnGenerationByPlayer[player] ~= generation or not player.Parent then return end
	player.CanLoadCharacterAppearance = true
	player:LoadCharacterAsync()
end

Remotes.CharacterPresentationReady.OnServerEvent:Connect(function(player: Player, token: unknown)
	if type(token) ~= "number" then return end
	local character = player.Character
	if not character or character:GetAttribute(TOKEN_ATTRIBUTE) ~= token then return end
	character:SetAttribute(READY_ATTRIBUTE, token)
end)

Players.PlayerRemoving:Connect(function(player)
	tokenByPlayer[player] = nil
	spawnGenerationByPlayer[player] = nil
end)

return CharacterPresentation
