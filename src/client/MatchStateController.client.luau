--!strict
-- Controle visual/local do estado autoritativo publicado pelo servidor.
-- A segurança continua no servidor; este script só impede previsão local,
-- animações e sons de denunciarem movimento durante a preparação.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ContextActionService = game:GetService("ContextActionService")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer
local LOCK_ACTION = "MatchStateMovementLock"

local curtain = Instance.new("ScreenGui")
curtain.Name = "MatchStateCurtain"
curtain.IgnoreGuiInset = true
curtain.ResetOnSpawn = false
curtain.DisplayOrder = 21
curtain.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
curtain.Enabled = false
curtain.Parent = player:WaitForChild("PlayerGui")
local curtainFrame = Instance.new("Frame")
curtainFrame.Name = "NoLobbyDuringTransition"
curtainFrame.Size = UDim2.fromScale(1, 1)
curtainFrame.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
curtainFrame.BackgroundTransparency = 0
curtainFrame.BorderSizePixel = 0
curtainFrame.Active = true
curtainFrame.Parent = curtain

local blockedStates: { [string]: boolean } = {
	Lobby = true,
	CharacterSelection = true,
	Loading = true,
	RoundEnd = true,
}

local savedVolumes: { [Sound]: number } = {}
local soundConnections: { RBXScriptConnection } = {}
local controls: any = nil
local character: Model? = nil
local humanoid: Humanoid? = nil
local locked = true

local function currentState(): string
	local value = ReplicatedStorage:GetAttribute("MatchState")
	return if type(value) == "string" then value else "Lobby"
end

local function movementBlocked(): boolean
	local state = currentState()
	return state == "CharacterSelection" or state == "Loading"
		or player:GetAttribute("MovementLocked") == true
end

local function getControls(): any
	if controls then return controls end
	local ok, result = pcall(function()
		local scripts = player:WaitForChild("PlayerScripts", 5)
		local module = scripts and scripts:WaitForChild("PlayerModule", 5)
		return module and require(module :: ModuleScript):GetControls()
	end)
	if ok then controls = result end
	return controls
end

local function setControls(enabled: boolean)
	local value = getControls()
	if not value then return end
	pcall(function()
		if enabled then value:Enable() else value:Disable() end
	end)
end

local function sinkMovement(_name: string, _state: Enum.UserInputState, _input: InputObject)
	return Enum.ContextActionResult.Sink
end

local function bindInputLock()
	ContextActionService:BindActionAtPriority(
		LOCK_ACTION,
		sinkMovement,
		false,
		Enum.ContextActionPriority.High.Value + 1000,
		Enum.KeyCode.W, Enum.KeyCode.A, Enum.KeyCode.S, Enum.KeyCode.D,
		Enum.KeyCode.Space, Enum.KeyCode.ButtonL3
	)
end

local function unbindInputLock()
	ContextActionService:UnbindAction(LOCK_ACTION)
end

local function isMovementSound(sound: Sound): boolean
	local name = sound.Name:lower()
	if name:find("foot", 1, true) or name:find("step", 1, true)
		or name:find("land", 1, true) or name:find("jump", 1, true)
		or name:find("run", 1, true) or name:find("walk", 1, true)
		or name:find("climb", 1, true) then
		return true
	end
	local group = sound.SoundGroup
	if group then
		local groupName = group.Name:lower()
		return groupName:find("foot", 1, true) ~= nil
			or groupName:find("land", 1, true) ~= nil
			or groupName:find("jump", 1, true) ~= nil
	end
	return false
end

local function silenceSound(sound: Sound)
	if not isMovementSound(sound) then return end
	if savedVolumes[sound] == nil then savedVolumes[sound] = sound.Volume end
	sound.Volume = 0
	if sound.IsPlaying then sound:Stop() end
end

local function restoreSounds()
	for sound, volume in savedVolumes do
		if sound.Parent then sound.Volume = volume end
		savedVolumes[sound] = nil
	end
end

local function stopLocomotionAnimations()
	local current = character
	local currentHumanoid = humanoid
	if not current or not currentHumanoid then return end
	local animator = currentHumanoid:FindFirstChildOfClass("Animator")
	if not animator then return end
	for _, track in animator:GetPlayingAnimationTracks() do
		track:Stop(0)
	end
end

local function watchCharacterSounds(newCharacter: Model)
	for _, connection in soundConnections do connection:Disconnect() end
	table.clear(soundConnections)
	for _, descendant in newCharacter:GetDescendants() do
		if descendant:IsA("Sound") and locked then silenceSound(descendant) end
	end
	table.insert(soundConnections, newCharacter.DescendantAdded:Connect(function(descendant)
		if locked and descendant:IsA("Sound") then silenceSound(descendant) end
	end))
end

local function applyToCharacter()
	local currentHumanoid = humanoid
	local currentCharacter = character
	if not currentHumanoid or not currentCharacter then return end
	locked = movementBlocked()
	if locked then
		setControls(false)
		player:SetAttribute("CursorLivre", true)
		currentHumanoid.WalkSpeed = 0
		currentHumanoid.JumpPower = 0
		currentHumanoid.JumpHeight = 0
		currentHumanoid.Jump = false
		currentHumanoid.AutoRotate = false
		currentHumanoid:SetStateEnabled(Enum.HumanoidStateType.Jumping, false)
		currentHumanoid:Move(Vector3.zero, false)
		local root = currentCharacter:FindFirstChild("HumanoidRootPart")
		if root and root:IsA("BasePart") then
			root.AssemblyLinearVelocity = Vector3.zero
			root.AssemblyAngularVelocity = Vector3.zero
		end
		stopLocomotionAnimations()
		for _, descendant in currentCharacter:GetDescendants() do
			if descendant:IsA("Sound") then silenceSound(descendant) end
		end
		return
	end

	unbindInputLock()
	setControls(true)
	player:SetAttribute("CursorLivre", nil)
	currentHumanoid:SetStateEnabled(Enum.HumanoidStateType.Jumping, true)
	currentHumanoid.AutoRotate = true
	restoreSounds()
	-- Reacorda a máquina do Animate sem forçar uma velocidade: o sistema de
	-- movimento atualiza WalkSpeed/atributos no próximo heartbeat.
	pcall(function() currentHumanoid:ChangeState(Enum.HumanoidStateType.Running) end)
end

local function reconcile()
	local shouldLock = movementBlocked()
	local state = currentState()
	curtain.Enabled = state == "CharacterSelection" or state == "Loading"
	if shouldLock then bindInputLock() else unbindInputLock() end
	applyToCharacter()
end

local function bindCharacter(newCharacter: Model)
	character = newCharacter
	humanoid = newCharacter:FindFirstChildOfClass("Humanoid")
		or newCharacter:WaitForChild("Humanoid", 10) :: Humanoid?
	watchCharacterSounds(newCharacter)
	reconcile()
end

player.CharacterAdded:Connect(bindCharacter)
player.CharacterRemoving:Connect(function(oldCharacter)
	if oldCharacter == character then
		character, humanoid = nil, nil
		for _, connection in soundConnections do connection:Disconnect() end
		table.clear(soundConnections)
	end
end)

ReplicatedStorage:GetAttributeChangedSignal("MatchState"):Connect(reconcile)
player:GetAttributeChangedSignal("GameplayEnabled"):Connect(reconcile)
player:GetAttributeChangedSignal("MovementLocked"):Connect(reconcile)

RunService.Heartbeat:Connect(function()
	-- Respawn, CharacterPresentationController e Crouching podem escrever
	-- depois desta rotina; reaplicar apenas nos estados bloqueados torna a
	-- trava determinística sem disputar a velocidade durante InMatch.
	if movementBlocked() then
		if not locked then reconcile() else applyToCharacter() end
	end
end)

if player.Character then task.defer(bindCharacter, player.Character) end
reconcile()
