--!strict
--[[
	ToolFactory
	Constrói as Tools placeholder dos itens novos desta leva (Faca
	Improvisada, Lança de Bambu, Pedra Afiada, Tocha, Lança Ancestral) --
	forma/cor simples, até você ter os modelos 3D finais. Trocar o visual é
	editar só o CONSTRUCTORS[itemId] correspondente, aqui.

	Um lugar só porque ItemSpawner.lua (pickups no mapa), CraftingSystem.lua
	(resultado do craft) e IslandGenerator.lua (Lança Ancestral nas Ruínas)
	precisam exatamente da mesma Tool -- duplicar a forma em 3 lugares
	significaria 3 lugares pra corrigir quando trocar por um modelo real.

	Cristal Ancestral, Corda/Madeira/Lona e as peças do rádio NÃO têm
	construtor aqui. RadioPieces.lua transforma a própria Part do rádio no
	Handle da Tool; o Cristal continua Studio-placed.

	LANTERNA, CHOCOLATE e GASOLINA são diferentes dos outros: usam um modelo
	REAL do Toolbox (AssetLoader.lua), não a forma placeholder das demais. O
	Model carregado é desmontado em Parts soltas -- a maior vira "Handle"
	(nome exigido por Tool.RequiresHandle), as outras são soldadas nela --
	porque não dá pra saber de antemão como o asset organiza suas próprias
	Parts por dentro (pode vir com 1 Part só ou várias).
]]

local ItemRegistry = require(script.Parent.ItemRegistry)
local AssetLoader = require(script.Parent.AssetLoader)
local ItemIcons = require(script.Parent.ItemIcons)
local FlashlightRig = require(script.Parent.FlashlightRig)

local ToolFactory = {}

local function makeHandle(size: Vector3, color: Color3, material: Enum.Material): Part
	local handle = Instance.new("Part")
	handle.Name = "Handle"
	handle.Size = size
	handle.Color = color
	handle.Material = material
	handle.CanCollide = false
	handle.TopSurface = Enum.SurfaceType.Smooth
	handle.BottomSurface = Enum.SurfaceType.Smooth
	return handle
end

-- Normaliza o tamanho de um asset carregado (Toolbox não segue nenhuma
-- escala consistente) pro maior lado bater com `targetLength` studs.
local function scaleModelToLength(model: Model, targetLength: number)
	local _, size = model:GetBoundingBox()
	local longest = math.max(size.X, size.Y, size.Z, 0.01)
	model:ScaleTo(model:GetScale() * (targetLength / longest))
end

-- Desmonta um Model carregado (AssetLoader) numa Tool: a maior Part vira
-- "Handle" (nome que Tool.RequiresHandle exige), as demais são soldadas
-- nela. Devolve nil se o asset não tiver nenhuma BasePart utilizável.
local function buildToolFromAssetModel(model: Model, toolName: string): Tool?
	local parts: { BasePart } = {}
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BasePart") then
			table.insert(parts, descendant)
		end
	end

	if #parts == 0 then
		model:Destroy()
		return nil
	end

	table.sort(parts, function(a, b)
		return a.Size.Magnitude > b.Size.Magnitude
	end)

	local tool = Instance.new("Tool")
	tool.Name = toolName
	tool.RequiresHandle = true

	local handle = parts[1]
	handle.Name = "Handle"
	handle.Parent = tool

	for i = 2, #parts do
		local part = parts[i]
		part.Parent = handle
		local weld = Instance.new("WeldConstraint")
		weld.Part0 = handle
		weld.Part1 = part
		weld.Parent = part
	end

	model:Destroy() -- já esvaziado: as Parts foram todas reparentadas acima
	return tool
end

local CONSTRUCTORS: { [string]: () -> Tool? } = {
	FacaImprovisada = function()
		local tool = Instance.new("Tool")
		tool.Name = "Faca Improvisada"
		tool.RequiresHandle = true
		tool.Grip = CFrame.new(0, 0, -0.3)
		local handle = makeHandle(Vector3.new(0.3, 0.15, 1.4), Color3.fromRGB(170, 170, 175), Enum.Material.Metal)
		handle.Parent = tool
		return tool
	end,

	Bandagem = function()
		-- Fallback: um rolinho de bandagem branco. Se você já tem uma Tool
		-- "Bandagem" própria no jogo, o UtilityItemSystem reage a ela do mesmo
		-- jeito (é pelo Attribute "Bandagem", não por esta construção) -- este
		-- construtor só entra quando o loot das caixas precisa CRIAR uma.
		local tool = Instance.new("Tool")
		tool.Name = "Bandagem"
		tool.RequiresHandle = true
		tool.Grip = CFrame.new(0, 0, -0.2)

		local handle = makeHandle(Vector3.new(0.7, 0.5, 0.5), Color3.fromRGB(238, 232, 220), Enum.Material.Fabric)
		handle.Parent = tool

		local mesh = Instance.new("SpecialMesh")
		mesh.MeshType = Enum.MeshType.Cylinder
		mesh.Scale = Vector3.new(0.6, 1, 1)
		mesh.Parent = handle

		return tool
	end,

	LancaDeBambu = function()
		local tool = Instance.new("Tool")
		tool.Name = "Lança de Bambu"
		tool.RequiresHandle = true
		local handle = makeHandle(Vector3.new(0.25, 0.25, 5), Color3.fromRGB(196, 178, 110), Enum.Material.Wood)
		handle.Parent = tool
		return tool
	end,

	PedraAfiada = function()
		local tool = Instance.new("Tool")
		tool.Name = "Pedra Afiada"
		tool.RequiresHandle = true
		local handle = makeHandle(Vector3.new(0.6, 0.5, 0.6), Color3.fromRGB(110, 108, 100), Enum.Material.Slate)
		handle.Shape = Enum.PartType.Ball
		handle.Parent = tool
		return tool
	end,

	Tocha = function()
		local tool = Instance.new("Tool")
		tool.Name = "Tocha"
		tool.RequiresHandle = true
		local handle = makeHandle(Vector3.new(0.25, 0.25, 2), Color3.fromRGB(120, 80, 40), Enum.Material.Wood)
		handle.Parent = tool

		local tip = Instance.new("Part")
		tip.Name = "Ponta"
		tip.Shape = Enum.PartType.Ball
		tip.Size = Vector3.new(0.5, 0.5, 0.5)
		tip.Color = Color3.fromRGB(90, 60, 30)
		tip.Material = Enum.Material.Fabric
		tip.CanCollide = false
		tip.CFrame = handle.CFrame * CFrame.new(0, 0, -1.1)
		tip.Parent = handle

		local weld = Instance.new("WeldConstraint")
		weld.Part0 = handle
		weld.Part1 = tip
		weld.Parent = tip

		return tool
	end,

	Lanterna = function()
		local template = AssetLoader.Load(ItemRegistry.Items.Lanterna.AssetId)
		if not template then
			return nil
		end

		local model = template:Clone()
		scaleModelToLength(model, 1.8)
		return FlashlightRig.Build(model)
	end,

	Chocolate = function()
		local template = AssetLoader.Load(ItemRegistry.Items.Chocolate.AssetId)
		if not template then
			return nil
		end

		local model = template:Clone()
		scaleModelToLength(model, 1)
		return buildToolFromAssetModel(model, "Chocolate")
	end,

	Gasolina = function()
		local template = AssetLoader.Load(ItemRegistry.Items.Gasolina.AssetId)
		if not template then
			return nil
		end

		local model = template:Clone()
		scaleModelToLength(model, 1.8) -- galão portátil; menor que os fixos da Estação de Rádio (2,4)
		return buildToolFromAssetModel(model, "Gasolina")
	end,

	LancaAncestral = function()
		local tool = Instance.new("Tool")
		tool.Name = "Lança Ancestral"
		tool.RequiresHandle = true
		local handle = makeHandle(Vector3.new(0.3, 0.3, 6.5), Color3.fromRGB(180, 60, 40), Enum.Material.Wood)
		handle.Parent = tool

		local tip = Instance.new("Part")
		tip.Name = "Ponta"
		tip.Size = Vector3.new(0.5, 0.5, 1.2)
		tip.Color = Color3.fromRGB(220, 220, 200)
		tip.Material = Enum.Material.Slate
		tip.CanCollide = false
		tip.CFrame = handle.CFrame * CFrame.new(0, 0, -3.6)
		tip.Parent = handle

		local weld = Instance.new("WeldConstraint")
		weld.Part0 = handle
		weld.Part1 = tip
		weld.Parent = tip

		return tool
	end,
}

--[[
	Create(itemId)
	Cria uma nova instância da Tool, já com o Attribute correto marcado
	(ItemRegistry.Items[itemId].AttributeName). nil se não houver construtor
	pra esse id, OU se o construtor existir mas falhar (ex: Lanterna/
	Chocolate quando o asset do Toolbox não carrega).
]]
function ToolFactory.Create(itemId: string): Tool?
	local constructor = CONSTRUCTORS[itemId]
	if not constructor then
		return nil
	end

	local tool = constructor()
	if not tool then
		return nil
	end

	local def = ItemRegistry.Items[itemId]
	if def and def.AttributeName then
		tool:SetAttribute(def.AttributeName, true)
	end

	-- Ícone da mochila/hotbar. Vazio enquanto ItemIcons.Map[itemId] não tiver
	-- um rbxassetid real -- aí a hotbar usa o ícone-letra de fallback.
	if tool.TextureId == "" then
		tool.TextureId = ItemIcons.IconForItemId(itemId)
	end

	return tool
end

return ToolFactory
