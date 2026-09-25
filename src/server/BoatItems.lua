--!strict
--[[
	BoatItems
	As peças do barco de fuga (docs/Barco.md): Hélice, Vela de ignição e
	Chave do barco -- UMA de cada por rodada -- e um Galão de Gasolina perto
	do barco. São Tools normais (ToolFactory) postas no mundo pelo
	DropItemSystem, então pegar, largar (G), guardar em gaveta e o XP de
	"item importante" funcionam como qualquer outro item.

	ONDE NASCEM (GameConfig.Boat.ItensPertoDoBarco)
	  true  (teste)  no píer/praia do lado do barco, igual as peças do
	                 rádio ao lado do gerador.
	  false (jogo)   Hélice na casa de barcos do Lago, Chave no Farol,
	                 Vela e Gasolina num PontoLoot de construção qualquer.
	                 Sem a construção no mapa, cai no lugar de teste.

	PEÇA NUNCA SOME DA PARTIDA
	  - Quem morre carregando larga as peças onde caiu.
	  - Se uma peça for destruída sem ter sido instalada (quem carregava saiu
	    do jogo, o drop expirou no chão...), ela reaparece no lugar onde
	    nasceu. Sem isso uma desconexão tornava a fuga impossível.
	  A Gasolina não reaparece: é combustível comum (o gerador do rádio
	  também aceita), e repor sempre viraria gasolina infinita.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local GameConfig = require(ReplicatedStorage.Modules.GameConfig)
local ItemRegistry = require(ReplicatedStorage.Modules.ItemRegistry)
local ToolFactory = require(ReplicatedStorage.Modules.ToolFactory)
local DropItemSystem = require(script.Parent.DropItemSystem)

local BoatItems = {}

local CFG = GameConfig.Boat
local MANAGED = "_BarcoItem"
local PIECES = { "HeliceBarco", "VelaIgnicao", "ChaveBarco" }
local RESPAWN_DELAY = 3
local PIECE_COLOR = Color3.fromRGB(96, 196, 214)

local homes: { [string]: CFrame } = {}
local consumed: { [Tool]: boolean } = {}
local watchedCharacters: { [Model]: boolean } = {}
local generation = 0
local fallbackSpots: { CFrame } = {}
local initialized = false

local function getFolder(): Instance
	local ilha = Workspace:FindFirstChild("Ilha") or Workspace
	local folder = ilha:FindFirstChild("ItensBarco")
	if folder then
		return folder
	end
	local created = Instance.new("Folder")
	created.Name = "ItensBarco"
	created.Parent = ilha
	return created
end

--[[ ItemIdOf(tool) -> "HeliceBarco" | "VelaIgnicao" | "ChaveBarco" | nil ]]
function BoatItems.ItemIdOf(tool: Instance): string?
	if not tool:IsA("Tool") then
		return nil
	end
	for _, itemId in PIECES do
		local def = ItemRegistry.Items[itemId]
		if def and def.AttributeName and tool:GetAttribute(def.AttributeName) == true then
			return itemId
		end
	end
	return nil
end

--[[
	Carried(player, itemId) -> Tool?
	A Tool do item que o jogador carrega: equipada primeiro, depois a
	mochila (mesmo padrão de RadioInstallSystem.installableTool). itemId
	"Gasolina" também vale.
]]
function BoatItems.Carried(player: Player, itemId: string): Tool?
	local def = ItemRegistry.Items[itemId]
	local attribute = def and def.AttributeName
	if not attribute then
		return nil
	end
	local character = player.Character
	if character then
		local equipped = character:FindFirstChildOfClass("Tool")
		if equipped and equipped:GetAttribute(attribute) == true then
			return equipped
		end
	end
	local backpack = player:FindFirstChildOfClass("Backpack")
	if backpack then
		for _, item in backpack:GetChildren() do
			if item:IsA("Tool") and item:GetAttribute(attribute) == true then
				return item
			end
		end
	end
	return nil
end

--[[
	Consume(tool)
	O BoatSystem instalou/usou o item: destrói sem reaparecer. Consumo e
	efeito acontecem no mesmo tique (sem yield) em quem chama.
]]
function BoatItems.Consume(tool: Tool)
	consumed[tool] = true
	tool:Destroy()
end

--------------------------------------------------------------------------------
-- Destaque no mundo
--------------------------------------------------------------------------------

local function handleOf(tool: Tool): BasePart?
	local handle = tool:FindFirstChild("Handle")
	return if handle and handle:IsA("BasePart") then handle else nil
end

local function undecorate(tool: Tool)
	local handle = handleOf(tool)
	if not handle then
		return
	end
	for _, name in { "DestaqueBarco", "NomeBarco" } do
		local child = handle:FindFirstChild(name)
		if child then
			child:Destroy()
		end
	end
end

-- Só enquanto está no chão: na mão, o destaque e a etiqueta sumiriam com o
-- jogador andando por aí brilhando.
local function refreshDecor(tool: Tool)
	local handle = handleOf(tool)
	if not handle then
		return
	end
	local onGround = tool:GetAttribute("_Dropped") == true and tool:IsDescendantOf(Workspace)
	if not onGround then
		undecorate(tool)
		return
	end
	if handle:FindFirstChild("DestaqueBarco") then
		return
	end
	local highlight = Instance.new("Highlight")
	highlight.Name = "DestaqueBarco"
	highlight.Adornee = tool
	highlight.FillColor = PIECE_COLOR
	highlight.FillTransparency = 0.7
	highlight.OutlineColor = Color3.fromRGB(230, 250, 255)
	highlight.OutlineTransparency = 0.05
	highlight.DepthMode = Enum.HighlightDepthMode.Occluded
	highlight.Parent = handle

	local billboard = Instance.new("BillboardGui")
	billboard.Name = "NomeBarco"
	billboard.Adornee = handle
	billboard.AlwaysOnTop = false
	billboard.LightInfluence = 0
	billboard.MaxDistance = 55
	billboard.Size = UDim2.fromOffset(180, 46)
	billboard.StudsOffsetWorldSpace = Vector3.new(0, 2, 0)
	billboard.Parent = handle
	local label = Instance.new("TextLabel")
	label.BackgroundColor3 = Color3.fromRGB(10, 18, 22)
	label.BackgroundTransparency = 0.15
	label.BorderSizePixel = 0
	label.Size = UDim2.fromScale(1, 1)
	label.Font = Enum.Font.GothamBold
	label.Text = "PEÇA DO BARCO\n" .. string.upper(tool.Name)
	label.TextColor3 = Color3.fromRGB(240, 250, 252)
	label.TextSize = 14
	label.TextWrapped = true
	label.Parent = billboard
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 5)
	corner.Parent = label
	local stroke = Instance.new("UIStroke")
	stroke.Color = PIECE_COLOR
	stroke.Thickness = 2
	stroke.Parent = label
end

--------------------------------------------------------------------------------
-- Onde nascem
--------------------------------------------------------------------------------

local function lootPointIn(root: Instance?): CFrame?
	if not root then
		return nil
	end
	for _, d in root:GetDescendants() do
		if d:IsA("BasePart") and d:GetAttribute("PontoLoot") == true then
			return d.CFrame
		end
	end
	return nil
end

local function findConstruction(name: string): Instance?
	local ilha = Workspace:FindFirstChild("Ilha")
	if not ilha then
		return nil
	end
	for _, d in ilha:GetDescendants() do
		if d:IsA("Model") and (d.Name == name or d:GetAttribute("Construcao") == name) then
			return d
		end
	end
	return nil
end

local function randomLootPoint(rng: Random, avoid: { CFrame }): CFrame?
	local ilha = Workspace:FindFirstChild("Ilha")
	if not ilha then
		return nil
	end
	local points: { CFrame } = {}
	for _, d in ilha:GetDescendants() do
		if d:IsA("BasePart") and d:GetAttribute("PontoLoot") == true then
			local far = true
			for _, other in avoid do
				if (other.Position - d.Position).Magnitude < 40 then
					far = false
					break
				end
			end
			if far then
				table.insert(points, d.CFrame)
			end
		end
	end
	if #points == 0 then
		return nil
	end
	return points[rng:NextInteger(1, #points)]
end

--[[
	Modo de teste: se o mapa tem um modelo "Ponte" (o píer ao lado do barco),
	os quatro itens ficam em cima dele, em fila pelo lado mais comprido.
	Devolve nil quando não há Ponte -- aí valem os lugares do BoatBuilder.
]]
local function pontePlan(order: { string }): { [string]: CFrame }?
	local reference = fallbackSpots[1]
	local best: Model? = nil
	local bestDistance = math.huge
	for _, d in Workspace:GetDescendants() do
		if d:IsA("Model") and string.lower(d.Name) == "ponte" then
			local distance = reference and (d:GetPivot().Position - reference.Position).Magnitude or 0
			if distance < bestDistance then
				best, bestDistance = d, distance
			end
		end
	end
	if not best then
		return nil
	end
	local boxCF, size = best:GetBoundingBox()
	local alongX = size.X >= size.Z
	local length = alongX and size.X or size.Z
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = { best }
	local spots: { [string]: CFrame } = {}
	for i, itemId in order do
		local t = (i - 0.5) / #order - 0.5 -- -0.375 .. 0.375 do comprimento
		local offset = alongX and Vector3.new(t * length * 0.8, 0, 0) or Vector3.new(0, 0, t * length * 0.8)
		local top = boxCF.Position + boxCF:VectorToWorldSpace(offset)
		local origin = Vector3.new(top.X, boxCF.Position.Y + size.Y / 2 + 20, top.Z)
		local hit = Workspace:Raycast(origin, Vector3.new(0, -(size.Y + 60), 0), params)
		local y = hit and hit.Position.Y or (boxCF.Position.Y + size.Y / 2)
		spots[itemId] = CFrame.new(top.X, y + 1.5, top.Z)
	end
	print(string.format("[BoatItems] Modo teste: itens em cima de '%s'.", best:GetFullName()))
	return spots
end

local function planSpots(): { [string]: CFrame }
	local spots: { [string]: CFrame } = {}
	local order = { "HeliceBarco", "VelaIgnicao", "ChaveBarco", "Gasolina" }
	local function fallback(index: number): CFrame
		local spot = fallbackSpots[((index - 1) % math.max(#fallbackSpots, 1)) + 1]
		return spot or CFrame.new(0, 20, 0)
	end
	if CFG.ItensPertoDoBarco then
		local onBridge = pontePlan(order)
		if onBridge then
			return onBridge
		end
	end
	if CFG.ItensPertoDoBarco or #fallbackSpots == 0 then
		for i, itemId in order do
			spots[itemId] = fallback(i)
		end
		return spots
	end

	local rng = Random.new()
	spots.HeliceBarco = lootPointIn(findConstruction("CasaDeBarcos")) or fallback(1)
	spots.ChaveBarco = lootPointIn(findConstruction("Farol")) or fallback(3)
	local used = { spots.HeliceBarco, spots.ChaveBarco }
	spots.VelaIgnicao = randomLootPoint(rng, used) or fallback(2)
	table.insert(used, spots.VelaIgnicao)
	spots.Gasolina = randomLootPoint(rng, used) or fallback(4)
	return spots
end

--------------------------------------------------------------------------------
-- Ciclo de vida das Tools
--------------------------------------------------------------------------------

local spawnItem: (string, CFrame, number) -> ()

local function watchTool(tool: Tool, itemId: string, token: number)
	tool:GetAttributeChangedSignal("_Dropped"):Connect(function()
		refreshDecor(tool)
	end)
	tool.AncestryChanged:Connect(function()
		refreshDecor(tool)
	end)
	if not table.find(PIECES, itemId) then
		return
	end
	tool.Destroying:Connect(function()
		if consumed[tool] or token ~= generation then
			consumed[tool] = nil
			return
		end
		local home = homes[itemId]
		if not home then
			return
		end
		task.delay(RESPAWN_DELAY, function()
			if token == generation then
				spawnItem(itemId, home, token)
				print(string.format("[BoatItems] %s voltou pro lugar de origem (a anterior sumiu sem ser instalada).", itemId))
			end
		end)
	end)
end

function spawnItem(itemId: string, cf: CFrame, token: number)
	local tool = ToolFactory.Create(itemId)
	if not tool then
		warn(string.format("[BoatItems] Não consegui criar '%s'.", itemId))
		return
	end
	tool:SetAttribute(MANAGED, true)
	tool:SetAttribute("WorldItemId", itemId)
	if table.find(PIECES, itemId) then
		tool:SetAttribute("PecaBarco", true)
	end
	watchTool(tool, itemId, token)
	DropItemSystem.PlaceInWorld(tool, cf, getFolder(), nil)
	refreshDecor(tool)
end

local function managedTools(container: Instance?): { Tool }
	local list: { Tool } = {}
	if container then
		for _, item in container:GetChildren() do
			if item:IsA("Tool") and item:GetAttribute(MANAGED) == true and item:GetAttribute("PecaBarco") == true then
				table.insert(list, item)
			end
		end
	end
	return list
end

local function dropOnDeath(player: Player, character: Model)
	local tools = managedTools(character)
	for _, tool in managedTools(player:FindFirstChildOfClass("Backpack")) do
		table.insert(tools, tool)
	end
	if #tools == 0 then
		return
	end
	local root = character:FindFirstChild("HumanoidRootPart")
	local origin = if root and root:IsA("BasePart") then root.CFrame else character:GetPivot()
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid:UnequipTools()
	end
	for index, tool in tools do
		local side = (index - (#tools + 1) / 2) * 1.8
		DropItemSystem.PlaceInWorld(tool, origin * CFrame.new(side, 1, 0), Workspace, nil)
	end
end

local function watchCharacter(player: Player, character: Model)
	if watchedCharacters[character] then
		return
	end
	watchedCharacters[character] = true
	local function onHumanoid(humanoid: Humanoid)
		humanoid.Died:Once(function()
			dropOnDeath(player, character)
		end)
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		onHumanoid(humanoid)
	else
		character.ChildAdded:Connect(function(child)
			if child:IsA("Humanoid") then
				onHumanoid(child)
			end
		end)
	end
	character.Destroying:Connect(function()
		watchedCharacters[character] = nil
	end)
end

--------------------------------------------------------------------------------
-- API
--------------------------------------------------------------------------------

--[[
	Reset(spots)
	Some com os itens da rodada anterior -- no chão, em gaveta ou na mochila
	de alguém -- e cria os da rodada nova. `spots` = lugares de teste do
	barco (píer/praia), usados também como reserva do modo espalhado.
]]
function BoatItems.Reset(spots: { CFrame })
	generation += 1
	fallbackSpots = spots
	local stale: { Tool } = {}
	for _, player in Players:GetPlayers() do
		for _, tool in managedTools(player.Character) do
			table.insert(stale, tool)
		end
		for _, tool in managedTools(player:FindFirstChildOfClass("Backpack")) do
			table.insert(stale, tool)
		end
	end
	for _, d in Workspace:GetDescendants() do
		if d:IsA("Tool") and d:GetAttribute(MANAGED) == true then
			table.insert(stale, d)
		end
	end
	for _, tool in stale do
		if tool.Parent then
			tool:Destroy()
		end
	end
	table.clear(consumed)
	table.clear(homes)

	local planned = planSpots()
	for itemId, cf in planned do
		homes[itemId] = cf
		spawnItem(itemId, cf, generation)
	end
end

function BoatItems.Init()
	if initialized then
		return
	end
	initialized = true
	local function watchPlayer(player: Player)
		if player.Character then
			watchCharacter(player, player.Character)
		end
		player.CharacterAdded:Connect(function(character)
			watchCharacter(player, character)
		end)
	end
	for _, player in Players:GetPlayers() do
		watchPlayer(player)
	end
	Players.PlayerAdded:Connect(watchPlayer)
end

return BoatItems
