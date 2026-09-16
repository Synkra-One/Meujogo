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
local TEMPLATE_NAME = "GameCharacter"
local GAME_SCRIPTS_NAME = "GameCharacterScripts"
local TOKEN_ATTRIBUTE = "CharacterPresentationToken"
local READY_ATTRIBUTE = "CharacterPresentationReady"
local tokenByPlayer: { [Player]: number } = {}

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

function CharacterPresentation.SpawnGameCharacter(player: Player): Model
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
	root.Anchored = true
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
	if root and root:IsA("BasePart") then
		root.Anchored = false
		pcall(function() root:SetNetworkOwner(player) end)
	end
	if not ready then
		warn(string.format("[CharacterPresentation] Cliente de %s não confirmou o corpo em tempo; continuando com fallback.", player.Name))
	end
	return ready
end

function CharacterPresentation.SpawnLobbyAvatar(player: Player)
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
end)

return CharacterPresentation
