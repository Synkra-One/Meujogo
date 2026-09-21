--!strict
--[[
	RadioInstallSystem
	Instala, uma por interação, as Tools criadas por RadioPieces.lua no rack
	de Workspace.Ilha.TorreDeRadio (a estação inteira é construída por
	Tools/RadioTowerGenerator.lua; este módulo só cuida do prompt de
	instalação). Termina ao emitir o progresso "TodasPecasInstaladas";
	server/RadioSiteSystem.lua cuida de tudo depois disso (combustível,
	fusível, gerador, painel e o pedido de socorro).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local GameConfig = require(ReplicatedStorage.Modules.GameConfig)
local Remotes = require(ReplicatedStorage.Modules.Remotes)
local RadioObjective = require(script.Parent.RadioObjective)
local RadioTowerGenerator = require(script.Parent.Tools.RadioTowerGenerator)
local RepairMinigameSystem = require(script.Parent.RepairMinigameSystem)

local RadioInstallSystem = {}

--[[
	PieceInstalled:Fire(player, pieceType)
	Uma peça foi instalada com sucesso no rack da torre.

	AllInstalled:Fire(player)
	As três peças ficaram instaladas -- `player` é quem instalou a última.
	Dispara UMA vez por partida (a mesma trava completionSent que já existe
	pra não repetir Remotes.ObjectiveProgress).

	server/MatchRewardService escuta os dois pra RecordObjectiveStep (por
	peça) e RecordObjectiveCompleted (rádio inteiro).
]]
RadioInstallSystem.PieceInstalled = Instance.new("BindableEvent")
RadioInstallSystem.AllInstalled = Instance.new("BindableEvent")

local PROMPT_NAME = "InstalarPeca"
local UPDATE_INTERVAL = 0.15
local DEFAULT_RANGE = 10
local InteractionGuard = require(script.Parent.InteractionGuard)

local PIECE_ORDER = { "Antena", "Bateria", "Transmissor" }
local PIECE_COLORS: { [string]: Color3 } = {
	Antena = Color3.fromRGB(105, 190, 255),
	Bateria = Color3.fromRGB(125, 255, 115),
	Transmissor = Color3.fromRGB(255, 195, 75),
}

local tower: Instance? = nil
local prompt: ProximityPrompt? = nil
local promptHost: BasePart? = nil
local lights: { [string]: PointLight } = {}
local indicators: { [string]: BasePart } = {}
local installing = false
local completionSent = false

local function installedAttribute(pieceType: string): string
	return pieceType .. "Instalada"
end

local function isInstalled(pieceType: string): boolean
	return tower ~= nil and tower:GetAttribute(installedAttribute(pieceType)) == true
end

local function allInstalled(): boolean
	for _, pieceType in PIECE_ORDER do
		if not isInstalled(pieceType) then return false end
	end
	return true
end

local function pieceTypeOf(tool: Tool): string?
	if tool:GetAttribute("PecaRadio") ~= true then return nil end
	local pieceType = tool:GetAttribute("TipoPeca")
	if type(pieceType) ~= "string" or table.find(PIECE_ORDER, pieceType) == nil then
		return nil
	end
	return pieceType
end

local function installableTool(player: Player): (Tool?, string?)
	local character = player.Character
	if character then
		local equipped = character:FindFirstChildOfClass("Tool")
		if equipped then
			local pieceType = pieceTypeOf(equipped)
			if pieceType and not isInstalled(pieceType) then return equipped, pieceType end
		end
	end

	local backpack = player:FindFirstChildOfClass("Backpack")
	if not backpack then return nil, nil end
	for _, wantedType in PIECE_ORDER do
		if not isInstalled(wantedType) then
			for _, item in backpack:GetChildren() do
				if item:IsA("Tool") and pieceTypeOf(item) == wantedType then
					return item, wantedType
				end
			end
		end
	end
	return nil, nil
end

local function rootAndHumanoid(player: Player): (BasePart?, Humanoid?)
	local character = player.Character
	if not character then return nil, nil end
	local root = character:FindFirstChild("HumanoidRootPart")
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local validRoot: BasePart? = if root and root:IsA("BasePart") then root else nil
	return validRoot, humanoid
end

local function inPromptRange(player: Player): boolean
	local host = promptHost
	local currentPrompt = prompt
	if not host or not currentPrompt then return false end
	local root, humanoid = rootAndHumanoid(player)
	if not root or not humanoid or humanoid.Health <= 0 then return false end
	local range = if currentPrompt.MaxActivationDistance > 0
		then currentPrompt.MaxActivationDistance
		else DEFAULT_RANGE
	return InteractionGuard.CanReach(player, host, range + 2)
end

local function isEligible(player: Player): boolean
	if player:GetAttribute("Role") ~= GameConfig.Roles.Survivor then
		return false
	end
	local tool = installableTool(player)
	return tool ~= nil
end

local function updateVisuals()
	for _, pieceType in PIECE_ORDER do
		local installed = isInstalled(pieceType)
		local light = lights[pieceType]
		if light then light.Enabled = installed end
		local indicator = indicators[pieceType]
		if indicator then
			indicator.Color = if installed then PIECE_COLORS[pieceType] else Color3.fromRGB(55, 60, 63)
			indicator.Material = if installed then Enum.Material.Neon else Enum.Material.Metal
		end
	end
end

local function emitCompletionIfNeeded()
	local completed = allInstalled()
	if completed and not completionSent then
		completionSent = true
		Remotes.ObjectiveProgress:FireAllClients("TodasPecasInstaladas", #PIECE_ORDER, #PIECE_ORDER)
	elseif not completed then
		completionSent = false
	end
end

local function refreshPrompt()
	local currentPrompt = prompt
	if not currentPrompt then return end
	updateVisuals()
	emitCompletionIfNeeded()
	if allInstalled() or installing then
		currentPrompt.Enabled = false
		return
	end

	local enabled = false
	for _, player in Players:GetPlayers() do
		if isEligible(player) then
			enabled = true
			break
		end
	end
	currentPrompt.Enabled = enabled
end

local function createStatusLights(host: BasePart)
	local currentTower = tower
	for index, pieceType in PIECE_ORDER do
		local old = host:FindFirstChild(pieceType .. "Indicator")
		if old then old:Destroy() end
		local attachment = Instance.new("Attachment")
		attachment.Name = pieceType .. "Indicator"
		attachment.Position = Vector3.new((index - 2) * 1.1, host.Size.Y / 2, 0)
		attachment.Parent = host

		local light = Instance.new("PointLight")
		light.Name = pieceType .. "InstaladaLight"
		light.Color = PIECE_COLORS[pieceType]
		light.Brightness = 1.5
		light.Range = 9
		light.Shadows = false
		light.Enabled = isInstalled(pieceType)
		light.Parent = attachment
		lights[pieceType] = light

		if currentTower then
			local oldIndicator = currentTower:FindFirstChild(pieceType .. "Status")
			if oldIndicator then oldIndicator:Destroy() end
			local indicator = Instance.new("Part")
			indicator.Name = pieceType .. "Status"
			indicator.Anchored = true
			indicator.CanCollide = false
			indicator.CanQuery = false
			indicator.CanTouch = false
			indicator.Shape = Enum.PartType.Ball
			indicator.Size = Vector3.new(0.55, 0.55, 0.55)
			indicator.CFrame = host.CFrame * CFrame.new((index - 2) * 0.85, host.Size.Y / 2 + 0.38, -host.Size.Z / 2 - 0.1)
			indicator.Parent = currentTower
			indicators[pieceType] = indicator
		end
	end
	updateVisuals()
end

local function findPromptHost(foundPrompt: ProximityPrompt): BasePart?
	local current: Instance? = foundPrompt.Parent
	while current and current ~= Workspace do
		if current:IsA("BasePart") then return current end
		current = current.Parent
	end
	local currentTower = tower
	return currentTower and currentTower:FindFirstChildWhichIsA("BasePart", true) or nil
end

local function firstBasePart(root: Instance?): BasePart?
	if not root then return nil end
	if root:IsA("BasePart") then return root end
	return root:FindFirstChildWhichIsA("BasePart", true)
end

local function getOrCreateIlha(): Instance
	local ilha = Workspace:FindFirstChild("Ilha")
	if ilha then return ilha end
	local folder = Instance.new("Folder")
	folder.Name = "Ilha"
	folder.Parent = Workspace
	return folder
end

-- A construção em si (torre, abrigo, gerador, cerca...) vem de
-- Tools/RadioTowerGenerator.lua -- ver a chamada em Init(). Este módulo só
-- garante que o prompt "InstalarPeca" existe em cima do que foi construído.

local function ensureInstallPrompt(foundTower: Instance): ProximityPrompt?
	local foundPrompt = foundTower:FindFirstChild(PROMPT_NAME, true)
	if foundPrompt and foundPrompt:IsA("ProximityPrompt") then
		return foundPrompt
	end

	local host = firstBasePart(foundTower)
	if not host then return nil end
	local promptInstance = Instance.new("ProximityPrompt")
	promptInstance.Name = PROMPT_NAME
	promptInstance.ActionText = "Instalar peca"
	promptInstance.ObjectText = "Torre de Radio"
	promptInstance.Enabled = false
	promptInstance.RequiresLineOfSight = true
	promptInstance.MaxActivationDistance = DEFAULT_RANGE
	promptInstance.HoldDuration = 0
	promptInstance.KeyboardKeyCode = Enum.KeyCode.E
	promptInstance.GamepadKeyCode = Enum.KeyCode.ButtonX
	promptInstance.ClickablePrompt = true
	promptInstance.Parent = host
	return promptInstance
end

local function installFromPlayer(player: Player)
	if installing or allInstalled() or player:GetAttribute("Role") ~= GameConfig.Roles.Survivor
		or not inPromptRange(player) then return end

	local tool, pieceType = installableTool(player)
	if not tool or not pieceType or isInstalled(pieceType) then return end
	local backpack = player:FindFirstChildOfClass("Backpack")
	local character = player.Character
	if tool.Parent ~= backpack and tool.Parent ~= character then return end

	installing = true
	if prompt then prompt.Enabled = false end
	tool:Destroy()
	if tower then tower:SetAttribute(installedAttribute(pieceType), true) end
	Remotes.LobbyMessage:FireClient(player, pieceType .. " instalada na Torre de Radio.")
	RadioObjective.RefreshPieceProgress()
	updateVisuals()
	RadioInstallSystem.PieceInstalled:Fire(player, pieceType)
	local wasCompleted = completionSent
	emitCompletionIfNeeded()
	if completionSent and not wasCompleted then
		RadioInstallSystem.AllInstalled:Fire(player)
	end
	installing = false
	refreshPrompt()
	print(string.format("[RadioInstallSystem] %s instalou %s.", player.Name, pieceType))
end

function RadioInstallSystem.Init()
	local ilha = getOrCreateIlha()
	local foundTower = ilha and ilha:FindFirstChild("TorreDeRadio")
	if not foundTower then
		foundTower = RadioTowerGenerator.Build()
	end

	local foundPrompt = ensureInstallPrompt(foundTower)
	if not foundPrompt then
		warn("[RadioInstallSystem] ProximityPrompt 'InstalarPeca' não encontrado na TorreDeRadio.")
		return
	end

	tower = foundTower
	prompt = foundPrompt
	promptHost = findPromptHost(foundPrompt)
	if not promptHost then
		warn("[RadioInstallSystem] A TorreDeRadio não possui BasePart para alcance e feedback visual.")
		return
	end

	foundPrompt.Enabled = false
	foundPrompt.ActionText = "Instalar peca"
	foundPrompt.ObjectText = "Torre de Radio"
	foundPrompt.KeyboardKeyCode = Enum.KeyCode.E
	foundPrompt.GamepadKeyCode = Enum.KeyCode.ButtonX
	foundPrompt.ClickablePrompt = true
	foundPrompt.RequiresLineOfSight = true
	foundPrompt.MaxActivationDistance = DEFAULT_RANGE
	foundPrompt.HoldDuration = 0
	createStatusLights(promptHost :: BasePart)
	for _, pieceType in PIECE_ORDER do
		foundTower:GetAttributeChangedSignal(installedAttribute(pieceType)):Connect(refreshPrompt)
	end

	-- Instalar peça agora é o reparo de precisão (RepairMinigameSystem). O
	-- onComplete é o MESMO installFromPlayer de antes, que revalida papel,
	-- alcance e posse da peça na hora de consumir a Tool -- o minigame só
	-- decide QUANDO ele roda. Uma barra compartilhada ("RadioInstalar"): as
	-- peças entram uma por vez e a barra zera ao concluir cada uma.
	local installSpec = {
		taskId = "RadioInstalar",
		configId = "RadioInstalar",
		part = promptHost :: BasePart,
		range = DEFAULT_RANGE + 2,
		canStart = function(player: Player): (boolean, string?)
			if installing or allInstalled() then
				return false, "Todas as peças já estão instaladas."
			end
			if not isEligible(player) then
				return false, "Você não está carregando nenhuma peça para instalar."
			end
			return true, nil
		end,
		onComplete = installFromPlayer,
	}
	foundPrompt.Triggered:Connect(function(player: Player)
		RepairMinigameSystem.Start(player, installSpec)
	end)

	local elapsed = 0
	RunService.Heartbeat:Connect(function(deltaTime)
		elapsed += deltaTime
		if elapsed < UPDATE_INTERVAL then return end
		elapsed = 0
		refreshPrompt()
	end)
	refreshPrompt()
end

return RadioInstallSystem
