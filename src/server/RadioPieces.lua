--!strict
--[[
	RadioPieces
	Cria Antena, Bateria e Transmissor ao lado do gerador da Estação de Rádio
	para testes rápidos da corrente de fuga (docs/Radio.md). Cada peça começa
	como uma Part coletável e vira uma Tool de um único Handle quando entra no
	inventário, ocupando um dos três slots da hotbar.

	Ao morrer, o jogador larga as peças na posição da morte através de
	DropItemSystem.PlaceInWorld. O pickup do drop continua validado pelo
	servidor e só aceita Sobreviventes com espaço no inventário.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local GameConfig = require(ReplicatedStorage.Modules.GameConfig)
local DropItemSystem = require(script.Parent.DropItemSystem)
local RadioObjective = require(script.Parent.RadioObjective)
local Remotes = require(ReplicatedStorage.Modules.Remotes)
local InteractionGuard = require(script.Parent.InteractionGuard)

local RadioPieces = {}

--[[
	PiecePickedUp:Fire(player, pieceType)
	Gancho de observação: `player` acabou de guardar a peça `pieceType`
	("Antena" | "Bateria" | "Transmissor") no inventário -- pelo toque OU
	pelo ProximityPrompt, os dois caem em partToInventoryTool, único lugar
	que dispara isto. server/MatchRewardService escuta pra conceder o XP de
	"item importante encontrado" (com UniqueBy: cada peça só existe uma vez
	por partida, então só paga uma vez mesmo se ela for largada e pega nas
	mãos de outro sobrevivente depois).
]]
RadioPieces.PiecePickedUp = Instance.new("BindableEvent")

local MANAGED_ATTRIBUTE = "_RadioPiecesManaged"
local PICKUP_PROMPT_NAME = "PegarPecaRadio"
local PICKUP_DISTANCE = 10

type PieceDefinition = {
	name: string,
	size: Vector3,
	color: Color3,
	material: Enum.Material,
	orientation: Vector3?,
}

local DEFINITIONS: { PieceDefinition } = {
	{
		name = "Antena",
		size = Vector3.new(3.4, 0.35, 0.35),
		color = Color3.fromRGB(175, 184, 194),
		material = Enum.Material.Metal,
		orientation = Vector3.new(0, 0, 90),
	},
	{
		name = "Bateria",
		size = Vector3.new(1.2, 0.7, 0.85),
		color = Color3.fromRGB(68, 82, 64),
		material = Enum.Material.Metal,
	},
	{
		name = "Transmissor",
		size = Vector3.new(1.7, 0.85, 1.2),
		color = Color3.fromRGB(83, 92, 105),
		material = Enum.Material.Metal,
	},
}

local collecting: { [BasePart]: boolean } = {}
local watchedTools: { [Tool]: boolean } = {}
local watchedCharacters: { [Model]: boolean } = {}
local initialized = false

local function getOrCreateFolder(parent: Instance, name: string): Instance
	local existing = parent:FindFirstChild(name)
	if existing then return existing end
	local folder = Instance.new("Folder")
	folder.Name = name
	folder.Parent = parent
	return folder
end

local function firstBasePart(root: Instance?, preferLootPoint: boolean?): BasePart?
	if not root then return nil end
	if root:IsA("BasePart") and root:GetAttribute("PecaRadio") ~= true then return root end
	if preferLootPoint then
		for _, descendant in root:GetDescendants() do
			if descendant:IsA("BasePart") and descendant:GetAttribute("PontoLoot") == true
				and descendant:GetAttribute("PecaRadio") ~= true then
				return descendant
			end
		end
	end
	for _, descendant in root:GetDescendants() do
		if descendant:IsA("BasePart") and descendant:GetAttribute("PecaRadio") ~= true then
			return descendant
		end
	end
	return nil
end

local function findNamed(root: Instance, names: { string }): Instance?
	for _, name in names do
		local found = root:FindFirstChild(name, true)
		if found then return found end
	end
	return nil
end

local function towerTestAnchor(ilha: Instance): BasePart?
	local tower = ilha:FindFirstChild("TorreDeRadio")
	if not tower then return nil end
	return firstBasePart(tower)
end

local function generatorTestAnchor(ilha: Instance): BasePart?
	local tower = ilha:FindFirstChild("TorreDeRadio")
	if not tower then return nil end
	local engine = tower:FindFirstChild("CorpoGerador", true)
	if engine and engine:IsA("BasePart") then
		return engine
	end
	for _, descendant in tower:GetDescendants() do
		if descendant:IsA("BasePart") and descendant:GetAttribute("MotorGerador") == true then
			return descendant
		end
	end
	return towerTestAnchor(ilha)
end

local function makeCrashPlaceholder(ilha: Instance): Part
	local reference = firstBasePart(ilha)
	local placeholder = Instance.new("Part")
	placeholder.Name = "Destroços do Avião"
	placeholder.Size = Vector3.new(12, 1.2, 6)
	placeholder.Anchored = true
	placeholder.CanCollide = true
	placeholder.Material = Enum.Material.CorrodedMetal
	placeholder.Color = Color3.fromRGB(91, 99, 104)
	placeholder.Position = (reference and reference.Position or Vector3.zero) + Vector3.new(0, 4, 0)
	placeholder.Parent = ilha
	return placeholder
end

local function configureWorldPart(part: Part, definition: PieceDefinition, cframe: CFrame)
	part.Name = definition.name
	part.Size = definition.size
	part.Color = definition.color
	part.Material = definition.material
	part.CFrame = cframe
	if definition.orientation then part.Orientation = definition.orientation :: Vector3 end
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = true
	part.CanTouch = true
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part:SetAttribute("PecaRadio", true)
	part:SetAttribute("TipoPeca", definition.name)
	part:SetAttribute(MANAGED_ATTRIBUTE, true)
end

local function addWorldPresentation(part: Part, definition: PieceDefinition)
	local oldPrompt = part:FindFirstChild(PICKUP_PROMPT_NAME)
	if oldPrompt then oldPrompt:Destroy() end
	local oldHighlight = part:FindFirstChild("DestaquePecaRadio")
	if oldHighlight then oldHighlight:Destroy() end
	local oldLabel = part:FindFirstChild("NomePecaRadio")
	if oldLabel then oldLabel:Destroy() end

	local highlight = Instance.new("Highlight")
	highlight.Name = "DestaquePecaRadio"
	highlight.Adornee = part
	highlight.FillColor = definition.color
	highlight.FillTransparency = 0.72
	highlight.OutlineColor = Color3.fromRGB(235, 245, 255)
	highlight.OutlineTransparency = 0.05
	highlight.DepthMode = Enum.HighlightDepthMode.Occluded
	highlight.Parent = part

	local billboard = Instance.new("BillboardGui")
	billboard.Name = "NomePecaRadio"
	billboard.Adornee = part
	billboard.AlwaysOnTop = false
	billboard.LightInfluence = 0
	billboard.MaxDistance = 55
	billboard.Size = UDim2.fromOffset(180, 48)
	billboard.StudsOffsetWorldSpace = Vector3.new(0, math.max(1.5, part.Size.Y / 2 + 1), 0)
	billboard.Parent = part

	local label = Instance.new("TextLabel")
	label.Name = "Label"
	label.BackgroundColor3 = Color3.fromRGB(12, 18, 22)
	label.BackgroundTransparency = 0.15
	label.BorderSizePixel = 0
	label.Size = UDim2.fromScale(1, 1)
	label.Font = Enum.Font.GothamBold
	label.Text = "PECA DO RADIO\n" .. string.upper(definition.name)
	label.TextColor3 = Color3.fromRGB(245, 248, 250)
	label.TextSize = 14
	label.TextWrapped = true
	label.Parent = billboard

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 5)
	corner.Parent = label

	local stroke = Instance.new("UIStroke")
	stroke.Color = definition.color
	stroke.Thickness = 2
	stroke.Parent = label

	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = PICKUP_PROMPT_NAME
	prompt.ActionText = "Pegar"
	prompt.ObjectText = definition.name .. " do Radio"
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.GamepadKeyCode = Enum.KeyCode.ButtonX
	prompt.ClickablePrompt = true
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = PICKUP_DISTANCE
	prompt.RequiresLineOfSight = true
	prompt.Parent = part
	return prompt
end

local function watchInventoryTool(tool: Tool)
	if watchedTools[tool] then return end
	watchedTools[tool] = true
	tool.AncestryChanged:Connect(function()
		task.defer(RadioObjective.RefreshPieceProgress)
		if tool.Parent == nil then watchedTools[tool] = nil end
	end)
end

local function partToInventoryTool(part: BasePart, player: Player): boolean
	local backpack = player:FindFirstChildOfClass("Backpack")
	if not backpack or not DropItemSystem.HasInventorySpace(player) then return false end

	local tipo = part:GetAttribute("TipoPeca")
	if type(tipo) ~= "string" then return false end

	local tool = Instance.new("Tool")
	tool.Name = tipo
	tool.RequiresHandle = true
	tool.CanBeDropped = false
	tool:SetAttribute("PecaRadio", true)
	tool:SetAttribute("TipoPeca", tipo)
	tool:SetAttribute(MANAGED_ATTRIBUTE, true)

	for _, childName in { PICKUP_PROMPT_NAME, "DestaquePecaRadio", "NomePecaRadio" } do
		local child = part:FindFirstChild(childName)
		if child then child:Destroy() end
	end
	part.Name = "Handle"
	part.Anchored = false
	part.CanCollide = false
	part.CanTouch = false
	part.Parent = tool
	watchInventoryTool(tool)
	tool.Parent = backpack
	RadioObjective.RefreshPieceProgress()
	RadioPieces.PiecePickedUp:Fire(player, tipo)
	return true
end

local function tryCollect(part: BasePart, hit: BasePart)
	if collecting[part] or not part:IsDescendantOf(Workspace) then return end
	local character = hit:FindFirstAncestorOfClass("Model")
	local player = character and Players:GetPlayerFromCharacter(character)
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not player or player:GetAttribute("Role") ~= GameConfig.Roles.Survivor
		or not humanoid or humanoid.Health <= 0 or not DropItemSystem.HasInventorySpace(player) then
		return
	end
	if not InteractionGuard.CanReach(player, part, PICKUP_DISTANCE + 2) then return end

	collecting[part] = true
	if not partToInventoryTool(part, player) then
		collecting[part] = nil
		return
	end
	print(string.format("[RadioPieces] %s coletou %s.", player.Name, tostring(part:GetAttribute("TipoPeca"))))
end

local function tryCollectForPlayer(part: BasePart, player: Player)
	if collecting[part] or not part:IsDescendantOf(Workspace) then return end
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if player:GetAttribute("Role") ~= GameConfig.Roles.Survivor then
		Remotes.LobbyMessage:FireClient(player, "Somente Sobreviventes podem carregar pecas do radio.")
		return
	end
	if not humanoid or humanoid.Health <= 0 or not root or not root:IsA("BasePart")
		or not InteractionGuard.CanReach(player, part, PICKUP_DISTANCE + 2) then
		return
	end
	if not DropItemSystem.HasInventorySpace(player) then
		Remotes.LobbyMessage:FireClient(player, "Inventario cheio. Libere um dos 3 espacos para pegar esta peca.")
		return
	end

	collecting[part] = true
	if not partToInventoryTool(part, player) then
		collecting[part] = nil
		return
	end
	Remotes.LobbyMessage:FireClient(player, tostring(part:GetAttribute("TipoPeca")) .. " coletada.")
end

local function connectWorldPart(part: Part, prompt: ProximityPrompt)
	part.Touched:Connect(function(hit: BasePart)
		tryCollect(part, hit)
	end)
	prompt.Triggered:Connect(function(player: Player)
		tryCollectForPlayer(part, player)
	end)
end

local function createPiece(definition: PieceDefinition, parent: Instance, cframe: CFrame): Part
	local existing = parent:FindFirstChild(definition.name)
	-- O cast fica na declaração: com ele na linha de baixo, "(part :: Part)"
	-- logo depois de uma chamada vira sintaxe ambígua e o módulo INTEIRO
	-- deixa de compilar (RoundManager engolia isso num pcall e a rodada
	-- rodava sem peça nenhuma de rádio).
	local part = (if existing and existing:IsA("Part") then existing else Instance.new("Part")) :: Part
	configureWorldPart(part, definition, cframe)
	part.Parent = parent
	local prompt = addWorldPresentation(part, definition)
	connectWorldPart(part, prompt)
	return part
end

local function isRadioTool(item: Instance): boolean
	return item:IsA("Tool") and item:GetAttribute("PecaRadio") == true
end

local function ownedRadioTools(player: Player, character: Model): { Tool }
	local tools: { Tool } = {}
	local seen: { [Tool]: boolean } = {}
	local backpack = player:FindFirstChildOfClass("Backpack")
	local containers: { Instance? } = { backpack, character }
	for _, container in containers do
		if container then
			for _, item in container:GetChildren() do
				if isRadioTool(item) and not seen[item :: Tool] then
					seen[item :: Tool] = true
					table.insert(tools, item :: Tool)
				end
			end
		end
	end
	return tools
end

local function dropPiecesOnDeath(player: Player, character: Model)
	local tools = ownedRadioTools(player, character)
	if #tools == 0 then return end

	local root = character:FindFirstChild("HumanoidRootPart")
	local origin = if root and root:IsA("BasePart") then root.CFrame else character:GetPivot()
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid then humanoid:UnequipTools() end
	for index, tool in tools do
		watchInventoryTool(tool)
		local sideOffset = (index - (#tools + 1) / 2) * 1.75
		DropItemSystem.PlaceInWorld(tool, origin * CFrame.new(sideOffset, 1, 0), Workspace, nil)
	end
	RadioObjective.RefreshPieceProgress()
end

local function watchCharacter(player: Player, character: Model)
	if watchedCharacters[character] then return end
	watchedCharacters[character] = true
	local function connectHumanoid(humanoid: Humanoid)
		humanoid.Died:Once(function()
			dropPiecesOnDeath(player, character)
			watchedCharacters[character] = nil
		end)
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		connectHumanoid(humanoid)
	else
		character.ChildAdded:Connect(function(child)
			if child:IsA("Humanoid") then connectHumanoid(child) end
		end)
	end
end

local function watchPlayer(player: Player)
	if player.Character then watchCharacter(player, player.Character) end
	player.CharacterAdded:Connect(function(character)
		watchCharacter(player, character)
	end)
end

local function buildWorldPieces()
	local ilha = Workspace:FindFirstChild("Ilha") or getOrCreateFolder(Workspace, "Ilha")
	-- O ItemSpawner antigo espalhava várias cópias aleatórias. Remove somente
	-- essas cópias da pasta gerada; as três peças fixas abaixo são as válidas.
	local generatedItems = ilha:FindFirstChild("Itens")
	if generatedItems then
		for _, item in generatedItems:GetDescendants() do
			if item:IsA("BasePart") and item:GetAttribute("PecaRadio") == true then
				item:Destroy()
			end
		end
	end

	-- Modo de teste: as três peças ficam no pátio da estação, ao lado do
	-- gerador, para validar rápido coleta -> instalar no rack -> energia ->
	-- transmissão. Quando voltar o fluxo longo, restaure a distribuição por
	-- avião/caverna/vila abaixo.
	local generatorAnchor = generatorTestAnchor(ilha)
	if generatorAnchor then
		local folder = getOrCreateFolder(ilha, "PecasRadioTeste")
		createPiece(DEFINITIONS[1], folder, generatorAnchor.CFrame * CFrame.new(-4, 2.2, -3))
		createPiece(DEFINITIONS[2], folder, generatorAnchor.CFrame * CFrame.new(-4, 1.8, 0))
		createPiece(DEFINITIONS[3], folder, generatorAnchor.CFrame * CFrame.new(-4, 1.9, 3))
		warn("[RadioPieces] Modo de teste ativo -- Antena, Bateria e Transmissor ao lado do gerador.")
		return
	end

	-- Fallback para mapas antigos sem estação de rádio montada: mantém a
	-- distribuição longa, assim a rodada ainda tem peças coletáveis.
	local crash = findNamed(ilha, { "Destroços do Avião", "DestrocosDoAviao", "Destrocos" })
	local crashAnchor = firstBasePart(crash)
	if not crashAnchor then
		crashAnchor = makeCrashPlaceholder(ilha)
	end
	createPiece(DEFINITIONS[1], ilha, crashAnchor.CFrame * CFrame.new(crashAnchor.Size.X / 2 + 3, 2, 0))

	local cavernas = getOrCreateFolder(ilha, "Cavernas")
	local caveAnchor = firstBasePart(cavernas) or firstBasePart(ilha:FindFirstChild("Caverna"))
	local cavePosition = (caveAnchor and caveAnchor.Position or crashAnchor.Position) + Vector3.new(3, 1.25, 0)
	createPiece(DEFINITIONS[2], cavernas, CFrame.new(cavePosition))

	local villageSource = ilha:FindFirstChild("VilaNativa")
	local villageAnchor = firstBasePart(villageSource, true)
	if not villageAnchor then
		local pois = ilha:FindFirstChild("POIs")
		villageSource = pois and findNamed(pois, { "VilaNativa", "Vila Nativa" })
		villageAnchor = firstBasePart(villageSource, true)
	end
	local vilaNativa = getOrCreateFolder(ilha, "VilaNativa")
	local villagePosition = (villageAnchor and villageAnchor.Position or crashAnchor.Position) + Vector3.new(0, 1, 0)
	createPiece(DEFINITIONS[3], vilaNativa, CFrame.new(villagePosition))
end

function RadioPieces.Reset()
	for _, player in Players:GetPlayers() do
		local containers: { Instance? } = { player.Character, player:FindFirstChildOfClass("Backpack") }
		for _, container in containers do
			if container then
				for _, item in container:GetChildren() do
					if item:IsA("Tool") and item:GetAttribute(MANAGED_ATTRIBUTE) == true then
						item:Destroy()
					end
				end
			end
		end
	end
	for _, item in Workspace:GetDescendants() do
		if item:IsA("Tool") and item:GetAttribute(MANAGED_ATTRIBUTE) == true then
			item:Destroy()
		end
	end
	for _, item in Workspace:GetDescendants() do
		if item:IsA("BasePart") and item:GetAttribute(MANAGED_ATTRIBUTE) == true
			and not item:FindFirstAncestorOfClass("Tool") then
			item:Destroy()
		end
	end
	table.clear(collecting)
	buildWorldPieces()
	RadioObjective.RefreshPieceProgress()
end

function RadioPieces.Init()
	if initialized then return end
	initialized = true
	buildWorldPieces()
	for _, player in Players:GetPlayers() do watchPlayer(player) end
	Players.PlayerAdded:Connect(watchPlayer)
	RadioObjective.RefreshPieceProgress()
end

return RadioPieces
