--!strict
--[[
	HotbarController
	Hotbar própria de "Náufragos": 3 slots no canto inferior ESQUERDO, cada um
	mostrando o ícone da Tool (ItemIcons.Resolve). Substitui a mochila padrão
	do Roblox (desligada via SetCoreGuiEnabled) -- por isso as 3 primeiras
	Tools do Backpack/Character viram os 3 slots, em ordem alfabética de nome
	(estável: o mesmo item cai sempre no mesmo slot).

	CONTROLES
	  - Teclas 1 / 2 / 3: equipam o slot correspondente (toggle).
	  - Tecla G: LARGA a Tool no chão (Remotes.DropItem -> DropItemSystem.lua
	    no servidor). Larga a Tool equipada; se nenhuma estiver equipada,
	    larga a do slot 1.
	  - Mouse: clicar no slot equipa; o botão ⤓ larga. Funciona normalmente --
	    o cursor não fica mais travado no centro (o CameraWeapon, que travava,
	    foi removido junto com o sistema OTS).

	IMAGEM DO SLOT (renderToolModel / ItemIcons.Resolve), nessa ordem:
	  1. rbxassetid de ItemIcons.Map[itemId], se você tiver colado a arte.
	  2. miniatura (rbxthumb) do AssetId do item (Lanterna/Chocolate).
	  3. render 3D da geometria REAL da Tool dentro de um ViewportFrame --
	     serve pra qualquer item, sem precisar de arte.
	  4. ícone-letra (2 primeiras letras) -- só se a Tool nem BasePart tiver
	     ainda (replicação atrasada); o refresh de 1s tenta de novo.
	Slot equipado ganha borda azul. O slot nunca fica vazio.

	LIMITE: só 3 slots. Se o jogador tiver mais de 3 Tools, as extras (ordem
	alfabética) não aparecem -- e a mochila padrão está desligada.

	Este ScreenGui vive sozinho (não depende da MainHUD nem do estado da
	partida): aparece assim que o jogador tem Tools, some quando não tem.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local StarterGui = game:GetService("StarterGui")

local Remotes = require(ReplicatedStorage.Modules.Remotes)
local ItemIcons = require(ReplicatedStorage.Modules.ItemIcons)

local SLOT_COUNT = 3
local SLOT_SIZE = 64
local SLOT_GAP = 8
local DROP_KEY = Enum.KeyCode.G -- G pra não colidir com C/Ctrl (agachar) nem R (recarregar)

local LocalPlayer = Players.LocalPlayer
local playerGui = LocalPlayer:WaitForChild("PlayerGui")

-- Desliga a mochila/hotbar padrão do Roblox (tenta em loop: nos primeiros
-- frames o CoreGui às vezes ainda não aceita).
task.spawn(function()
	for _ = 1, 10 do
		local ok = pcall(function()
			StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Backpack, false)
		end)
		if ok then
			break
		end
		task.wait(0.5)
	end
end)

--------------------------------------------------------------------------------
-- UI
--------------------------------------------------------------------------------

type Slot = {
	button: TextButton,
	icon: ImageLabel,
	viewport: ViewportFrame,
	viewportCam: Camera,
	letter: TextLabel,
	drop: TextButton,
	stroke: UIStroke,
	tool: Tool?,
	renderedFor: Tool?, -- qual Tool já está no ViewportFrame (evita re-render)
}

local gui = Instance.new("ScreenGui")
gui.Name = "Hotbar"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = false
gui.DisplayOrder = 5
gui.Enabled = false
gui.Parent = playerGui

local holder = Instance.new("Frame")
holder.Name = "Slots"
holder.AnchorPoint = Vector2.new(0, 1)
holder.Position = UDim2.new(0, 14, 1, -14)
holder.Size = UDim2.fromOffset(
	SLOT_COUNT * SLOT_SIZE + (SLOT_COUNT - 1) * SLOT_GAP,
	SLOT_SIZE
)
holder.BackgroundTransparency = 1
holder.Parent = gui

local layout = Instance.new("UIListLayout")
layout.FillDirection = Enum.FillDirection.Horizontal
layout.Padding = UDim.new(0, SLOT_GAP)
layout.SortOrder = Enum.SortOrder.LayoutOrder
layout.VerticalAlignment = Enum.VerticalAlignment.Bottom
layout.Parent = holder

local function buildSlot(index: number): Slot
	local button = Instance.new("TextButton")
	button.Name = "Slot" .. index
	button.LayoutOrder = index
	button.Size = UDim2.fromOffset(SLOT_SIZE, SLOT_SIZE)
	button.BackgroundColor3 = Color3.fromRGB(18, 18, 22)
	button.BackgroundTransparency = 0.3
	button.BorderSizePixel = 0
	button.AutoButtonColor = false
	button.Text = ""
	button.Parent = holder

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 8)
	corner.Parent = button

	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(255, 255, 255)
	stroke.Transparency = 0.8
	stroke.Thickness = 2
	stroke.Parent = button

	local icon = Instance.new("ImageLabel")
	icon.Name = "Icon"
	icon.AnchorPoint = Vector2.new(0.5, 0.5)
	icon.Position = UDim2.fromScale(0.5, 0.5)
	icon.Size = UDim2.fromScale(0.78, 0.78)
	icon.BackgroundTransparency = 1
	icon.ScaleType = Enum.ScaleType.Fit
	icon.Visible = false
	icon.Parent = button

	-- Fallback quando não há ícone (rbxassetid): renderiza o modelo 3D real
	-- da Tool aqui dentro -- funciona pra qualquer item, sem arte extra.
	local viewport = Instance.new("ViewportFrame")
	viewport.Name = "Viewport"
	viewport.AnchorPoint = Vector2.new(0.5, 0.5)
	viewport.Position = UDim2.fromScale(0.5, 0.5)
	viewport.Size = UDim2.fromScale(0.92, 0.92)
	viewport.BackgroundTransparency = 1
	viewport.Ambient = Color3.fromRGB(200, 200, 200)
	viewport.LightColor = Color3.fromRGB(255, 255, 255)
	viewport.LightDirection = Vector3.new(-0.4, -1, -0.6)
	viewport.Visible = false
	viewport.Parent = button

	local viewportCam = Instance.new("Camera")
	viewportCam.FieldOfView = 40
	viewportCam.Parent = viewport
	viewport.CurrentCamera = viewportCam

	local letter = Instance.new("TextLabel")
	letter.Name = "Letter"
	letter.Size = UDim2.fromScale(1, 1)
	letter.BackgroundTransparency = 1
	letter.Font = Enum.Font.GothamBold
	letter.TextSize = 22
	letter.TextColor3 = Color3.fromRGB(230, 230, 236)
	letter.Text = ""
	letter.Parent = button

	local number = Instance.new("TextLabel")
	number.Name = "Number"
	number.Size = UDim2.fromOffset(16, 16)
	number.Position = UDim2.fromOffset(4, 2)
	number.BackgroundTransparency = 1
	number.Font = Enum.Font.GothamBold
	number.TextSize = 13
	number.TextColor3 = Color3.fromRGB(255, 255, 255)
	number.TextXAlignment = Enum.TextXAlignment.Left
	number.TextYAlignment = Enum.TextYAlignment.Top
	number.Text = tostring(index)
	number.Parent = button

	local drop = Instance.new("TextButton")
	drop.Name = "Drop"
	drop.AnchorPoint = Vector2.new(1, 0)
	drop.Position = UDim2.fromOffset(SLOT_SIZE - 3, 3)
	drop.Size = UDim2.fromOffset(18, 18)
	drop.BackgroundColor3 = Color3.fromRGB(150, 42, 42)
	drop.BorderSizePixel = 0
	drop.AutoButtonColor = true
	drop.Font = Enum.Font.GothamBold
	drop.TextSize = 12
	drop.TextColor3 = Color3.fromRGB(255, 255, 255)
	drop.Text = "\u{2913}" -- ⤓ (seta pra baixo)
	drop.Visible = false
	drop.Parent = button

	local dropCorner = Instance.new("UICorner")
	dropCorner.CornerRadius = UDim.new(1, 0)
	dropCorner.Parent = drop

	return {
		button = button,
		icon = icon,
		viewport = viewport,
		viewportCam = viewportCam,
		letter = letter,
		drop = drop,
		stroke = stroke,
		tool = nil,
		renderedFor = nil,
	}
end

-- Filhos de uma BasePart que IMPORTAM pro visual dentro do ViewportFrame.
-- O resto (WeldConstraint, Sound, Script, ParticleEmitter, Attachment, Light,
-- ProximityPrompt...) é jogado fora no clone: não renderiza e só pesa.
local KEEP_IN_VIEWPORT = { "SurfaceAppearance", "Texture", "Decal", "SpecialMesh", "BlockMesh", "CylinderMesh" }

local function stripToVisual(part: BasePart)
	for _, child in part:GetChildren() do
		local keep = false
		for _, className in KEEP_IN_VIEWPORT do
			if child:IsA(className) then
				keep = true
				break
			end
		end
		if not keep then
			child:Destroy()
		end
	end
end

-- Clona a geometria da Tool num ViewportFrame e enquadra a câmera. Devolve
-- false se a Tool não tiver nenhuma BasePart visível (aí cai no ícone-letra).
local function renderToolModel(slot: Slot, tool: Tool): boolean
	local cam = slot.viewportCam
	for _, child in slot.viewport:GetChildren() do
		if child ~= cam then
			child:Destroy()
		end
	end

	local model = Instance.new("Model")
	for _, descendant in tool:GetDescendants() do
		-- Partes invisíveis (Muzzle/Ejector das armas são só âncoras de
		-- efeito) ficam de fora: elas não aparecem e só esticariam a bounding
		-- box, desenquadrando a câmera.
		if descendant:IsA("BasePart") and descendant.Transparency < 1 then
			local clone = descendant:Clone()
			stripToVisual(clone) -- mantém textura/mesh, tira o resto
			clone.Anchored = true
			clone.CanCollide = false
			clone.CanQuery = false
			clone.CanTouch = false
			clone.Parent = model
		end
	end

	if #model:GetChildren() == 0 then
		model:Destroy()
		return false
	end

	-- Centraliza a geometria na origem.
	local worldCF, size = model:GetBoundingBox()
	for _, part in model:GetChildren() do
		if part:IsA("BasePart") then
			part.CFrame = worldCF:Inverse() * part.CFrame
		end
	end

	model.Parent = slot.viewport

	local reach = math.max(size.X, size.Y, size.Z, 1)
	local dist = reach * 2.2 + 1.5
	cam.CFrame = CFrame.lookAt(Vector3.new(dist * 0.55, dist * 0.45, dist), Vector3.zero)

	return true
end

local slots: { Slot } = {}
for i = 1, SLOT_COUNT do
	slots[i] = buildSlot(i)
end

--------------------------------------------------------------------------------
-- Estado: quais Tools ocupam os slots
--------------------------------------------------------------------------------

local function currentCharacter(): Model?
	return LocalPlayer.Character
end

local function isEquipped(tool: Tool): boolean
	local character = currentCharacter()
	return character ~= nil and tool.Parent == character
end

-- Todas as Tools do jogador (Backpack + a equipada), ordenadas por nome.
local function collectTools(): { Tool }
	local list: { Tool } = {}

	local backpack = LocalPlayer:FindFirstChildOfClass("Backpack")
	if backpack then
		for _, child in backpack:GetChildren() do
			if child:IsA("Tool") then
				table.insert(list, child)
			end
		end
	end

	local character = currentCharacter()
	if character then
		for _, child in character:GetChildren() do
			if child:IsA("Tool") then
				table.insert(list, child)
			end
		end
	end

	table.sort(list, function(a, b)
		return a.Name < b.Name
	end)
	return list
end

local function paintSlot(slot: Slot, tool: Tool?)
	slot.tool = tool

	if not tool then
		slot.icon.Visible = false
		slot.icon.Image = ""
		slot.viewport.Visible = false
		slot.letter.Text = ""
		slot.drop.Visible = false
		slot.stroke.Transparency = 0.88
		slot.stroke.Color = Color3.fromRGB(255, 255, 255)
		slot.button.BackgroundTransparency = 0.55
		slot.renderedFor = nil
		return
	end

	local image = ItemIcons.Resolve(tool)
	if image ~= "" then
		slot.icon.Image = image
		slot.icon.Visible = true
		slot.viewport.Visible = false
		slot.letter.Text = ""
		slot.renderedFor = nil
	else
		slot.icon.Visible = false
		slot.icon.Image = ""

		-- Sem ícone: tenta o modelo 3D real da Tool; se nem isso, ícone-letra.
		local rendered = slot.renderedFor == tool
		if not rendered then
			rendered = renderToolModel(slot, tool)
			slot.renderedFor = if rendered then tool else nil
		end

		slot.viewport.Visible = rendered
		slot.letter.Text = if rendered then "" else string.upper(string.sub(tool.Name, 1, 2))
	end

	slot.drop.Visible = true
	slot.button.BackgroundTransparency = 0.3

	if isEquipped(tool) then
		slot.stroke.Transparency = 0
		slot.stroke.Color = Color3.fromRGB(120, 200, 255)
	else
		slot.stroke.Transparency = 0.75
		slot.stroke.Color = Color3.fromRGB(255, 255, 255)
	end
end

local function refresh()
	local tools = collectTools()
	for i = 1, SLOT_COUNT do
		paintSlot(slots[i], tools[i])
	end
	gui.Enabled = #tools > 0
end

--------------------------------------------------------------------------------
-- Ações
--------------------------------------------------------------------------------

local function toggleEquip(tool: Tool)
	local character = currentCharacter()
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return
	end

	if tool.Parent == character then
		humanoid:UnequipTools()
	else
		humanoid:EquipTool(tool)
	end
end

local function dropTool(tool: Tool?)
	if tool then
		Remotes.DropItem:FireServer(tool)
	end
end

local function equippedTool(): Tool?
	for i = 1, SLOT_COUNT do
		local tool = slots[i].tool
		if tool and isEquipped(tool) then
			return tool
		end
	end
	return nil
end

for i = 1, SLOT_COUNT do
	local slot = slots[i]
	slot.button.Activated:Connect(function()
		if slot.tool then
			toggleEquip(slot.tool)
		end
	end)
	slot.drop.Activated:Connect(function()
		dropTool(slot.tool)
	end)
end

UserInputService.InputBegan:Connect(function(input: InputObject, gameProcessed: boolean)
	if gameProcessed then
		return
	end

	if input.KeyCode == Enum.KeyCode.One then
		if slots[1].tool then
			toggleEquip(slots[1].tool)
		end
	elseif input.KeyCode == Enum.KeyCode.Two then
		if slots[2].tool then
			toggleEquip(slots[2].tool)
		end
	elseif input.KeyCode == Enum.KeyCode.Three then
		if slots[3].tool then
			toggleEquip(slots[3].tool)
		end
	elseif input.KeyCode == DROP_KEY then
		dropTool(equippedTool() or slots[1].tool)
	end
end)

--------------------------------------------------------------------------------
-- Reagir a mudanças de inventário
--------------------------------------------------------------------------------

local function hookContainer(container: Instance)
	container.ChildAdded:Connect(refresh)
	container.ChildRemoved:Connect(refresh)
end

local function onCharacter(character: Model)
	hookContainer(character)
	task.defer(refresh)
end

local backpack = LocalPlayer:WaitForChild("Backpack", 10)
if backpack then
	hookContainer(backpack)
end
-- O Backpack é recriado a cada respawn -- reengancha o novo.
LocalPlayer.ChildAdded:Connect(function(child)
	if child:IsA("Backpack") then
		hookContainer(child)
		task.defer(refresh)
	end
end)

if LocalPlayer.Character then
	onCharacter(LocalPlayer.Character)
end
LocalPlayer.CharacterAdded:Connect(onCharacter)

-- Rede de segurança: reidrata periodicamente (o slot "equipado" pode mudar
-- por vias que não passam por ChildAdded/Removed no timing esperado).
task.spawn(function()
	while true do
		task.wait(1)
		refresh()
	end
end)

refresh()
