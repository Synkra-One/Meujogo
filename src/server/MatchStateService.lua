--!strict
--[[
    Autoridade única do estado de preparação/jogo.

    O estado público fica em ReplicatedStorage.MatchState para a apresentação
    do cliente, enquanto GameplayEnabled/MovementLocked ficam no Player para
    que cada ação do servidor também tenha uma trava local e autoritativa.

    Importante: a trava não usa Anchor no HumanoidRootPart. Durante a
    preparação o servidor assume a propriedade da raiz e zera velocidade,
    enquanto o cliente desliga os controles e silencia a apresentação.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local MatchStateService = {}

export type State = "Lobby" | "CharacterSelection" | "Loading" | "InMatch" | "RoundEnd"

local state: State = "Lobby"
local initialized = false
local savedHumanoidValues: { [Humanoid]: {
	walkSpeed: number,
	jumpPower: number,
	jumpHeight: number,
	useJumpPower: boolean,
	autoRotate: boolean,
	jumpingEnabled: boolean,
} } = {}
local savedToolEnabled: { [Tool]: boolean } = {}
local savedPromptEnabled: { [ProximityPrompt]: boolean } = {}

local BLOCKED: { [State]: boolean } = {
	-- O Lobby e o RoundEnd continuam jogaveis para que o jogador possa
	-- circular normalmente. A trava so existe durante a transicao que inicia
	-- a partida.
	Lobby = false,
	CharacterSelection = true,
	Loading = true,
	InMatch = false,
	RoundEnd = false,
}

local function isParticipantGameplayEnabled(player: Player): boolean
	return state == "InMatch"
		and player:GetAttribute("InRound") == true
		and player:GetAttribute("InWaitingRoom") ~= true
		and player.Parent == Players
end

local function setIfChanged(instance: Instance, name: string, value: unknown)
	if instance:GetAttribute(name) ~= value then
		instance:SetAttribute(name, value)
	end
end

local function saveHumanoid(humanoid: Humanoid)
	if savedHumanoidValues[humanoid] then return end
	savedHumanoidValues[humanoid] = {
		walkSpeed = humanoid.WalkSpeed,
		jumpPower = humanoid.JumpPower,
		jumpHeight = humanoid.JumpHeight,
		useJumpPower = humanoid.UseJumpPower,
		autoRotate = humanoid.AutoRotate,
		jumpingEnabled = humanoid:GetStateEnabled(Enum.HumanoidStateType.Jumping),
	}
	end

local function setNetworkOwner(root: BasePart, player: Player?, movementAllowed: boolean)
	if not root:CanSetNetworkOwnership() then return end
	local ok = pcall(function()
		if movementAllowed and player then root:SetNetworkOwner(player) else root:SetNetworkOwner(nil) end
	end)
	if not ok then
		-- A character can be replaced between the ownership check and the write.
		-- The next heartbeat will reconcile it without breaking the state loop.
	end
end

local function applyTools(player: Player, gameplayEnabled: boolean)
	local containers = { player:FindFirstChildOfClass("Backpack"), player.Character }
	for _, container in containers do
		if not container then continue end
		for _, child in container:GetChildren() do
			if not child:IsA("Tool") then continue end
			if gameplayEnabled then
				local previous = savedToolEnabled[child]
				if previous ~= nil then child.Enabled = previous; savedToolEnabled[child] = nil end
			else
				if savedToolEnabled[child] == nil then savedToolEnabled[child] = child.Enabled end
				child.Enabled = false
			end
		end
	end
	if not gameplayEnabled then
		local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
		if humanoid then humanoid:UnequipTools() end
	end
end

local function isLobbyStartPrompt(prompt: ProximityPrompt): boolean
	if prompt.Name == "StartPrompt" then return true end
	local parent = prompt.Parent
	return parent ~= nil and parent.Name == "IniciarPartida"
end

local function applyPrompt(prompt: ProximityPrompt)
	if isLobbyStartPrompt(prompt) then
		prompt.Enabled = state == "Lobby"
		return
	end
	if state == "InMatch" then
		local previous = savedPromptEnabled[prompt]
		if previous ~= nil then
			prompt.Enabled = previous
			savedPromptEnabled[prompt] = nil
		end
		return
	end
	if savedPromptEnabled[prompt] == nil then savedPromptEnabled[prompt] = prompt.Enabled end
	prompt.Enabled = false
end

local function applyPrompts()
	for _, descendant in Workspace:GetDescendants() do
		if descendant:IsA("ProximityPrompt") then applyPrompt(descendant) end
	end
end

local function applyToCharacter(player: Player, character: Model, gameplayEnabled: boolean, movementBlocked: boolean)
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local root = character:FindFirstChild("HumanoidRootPart")
	if not humanoid or not root or not root:IsA("BasePart") then return end

	if not movementBlocked then
		local saved = savedHumanoidValues[humanoid]
		if saved then
			humanoid.WalkSpeed = saved.walkSpeed
			humanoid.UseJumpPower = saved.useJumpPower
			humanoid.JumpPower = saved.jumpPower
			humanoid.JumpHeight = saved.jumpHeight
			humanoid.AutoRotate = saved.autoRotate
			humanoid:SetStateEnabled(Enum.HumanoidStateType.Jumping, saved.jumpingEnabled)
			savedHumanoidValues[humanoid] = nil
		end
		setIfChanged(character, "MatchStateMovementLocked", nil)
		setNetworkOwner(root, player, true)
		return
	end

	saveHumanoid(humanoid)
	humanoid.WalkSpeed = 0
	humanoid.JumpPower = 0
	humanoid.JumpHeight = 0
	humanoid.Jump = false
	humanoid.AutoRotate = false
	humanoid:SetStateEnabled(Enum.HumanoidStateType.Jumping, false)
	humanoid:Move(Vector3.zero, false)
	root.AssemblyLinearVelocity = Vector3.zero
	root.AssemblyAngularVelocity = Vector3.zero
	setIfChanged(character, "MatchStateMovementLocked", true)
	setNetworkOwner(root, player, false)
end

local function applyToPlayer(player: Player)
	local gameplayEnabled = isParticipantGameplayEnabled(player)
	local movementBlocked = BLOCKED[state]
	setIfChanged(player, "GameplayEnabled", gameplayEnabled)
	setIfChanged(player, "MovementLocked", movementBlocked)
	setIfChanged(player, "MatchState", state)
	applyTools(player, gameplayEnabled)
	local character = player.Character
	if character then applyToCharacter(player, character, gameplayEnabled, movementBlocked) end
end

function MatchStateService.Get(): State
	return state
end

function MatchStateService.IsGameplayEnabled(player: Player): boolean
	return player:GetAttribute("GameplayEnabled") == true and isParticipantGameplayEnabled(player)
end

function MatchStateService.IsBlocked(player: Player): boolean
	return player:GetAttribute("MovementLocked") == true
end

function MatchStateService.Set(nextState: State)
	if state == nextState then
		for _, player in Players:GetPlayers() do applyToPlayer(player) end
		return
	end
	state = nextState
	ReplicatedStorage:SetAttribute("MatchState", state)
	ReplicatedStorage:SetAttribute("MatchStateMovementBlocked", BLOCKED[state])
	applyPrompts()
	for _, player in Players:GetPlayers() do applyToPlayer(player) end
end

function MatchStateService.ApplyPlayer(player: Player)
	applyToPlayer(player)
end

function MatchStateService.Init()
	if initialized then return end
	initialized = true
	ReplicatedStorage:SetAttribute("MatchState", state)
	ReplicatedStorage:SetAttribute("MatchStateMovementBlocked", BLOCKED[state])
	Workspace.DescendantAdded:Connect(function(descendant)
		if descendant:IsA("ProximityPrompt") then
			task.defer(function()
				if descendant.Parent then applyPrompt(descendant) end
			end)
		end
	end)
	applyPrompts()

	local function watch(player: Player)
		applyToPlayer(player)
		player.CharacterAdded:Connect(function(character)
			task.defer(function()
				if player.Parent == Players and player.Character == character then
					applyToPlayer(player)
				end
			end)
		end)
		player:GetAttributeChangedSignal("InRound"):Connect(function() applyToPlayer(player) end)
		player:GetAttributeChangedSignal("InWaitingRoom"):Connect(function() applyToPlayer(player) end)
	end

	for _, player in Players:GetPlayers() do watch(player) end
	Players.PlayerAdded:Connect(watch)
	Players.PlayerRemoving:Connect(function(player)
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if humanoid then savedHumanoidValues[humanoid] = nil end
	end)

	RunService.Heartbeat:Connect(function()
		for _, player in Players:GetPlayers() do
			local gameplayEnabled = isParticipantGameplayEnabled(player)
			local movementBlocked = BLOCKED[state]
			if player:GetAttribute("GameplayEnabled") ~= gameplayEnabled
				or player:GetAttribute("MovementLocked") ~= movementBlocked then
				applyToPlayer(player)
			elseif movementBlocked then
				local character = player.Character
				if character then applyToCharacter(player, character, gameplayEnabled, true) end
			end
		end
	end)
end

return MatchStateService
