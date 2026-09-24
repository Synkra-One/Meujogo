--!strict
--[[
	ToolFactory
	Constrói as Tools funcionais dos itens novos desta leva (Crowbar, Tocha e
	Crowbar Ancestral). O id interno dos itens é mantido nos Attributes usados
	pelos sistemas de coleta e combate.

	Um lugar só porque ItemSpawner.lua (pickups no mapa) e IslandGenerator.lua
	(Lança Ancestral nas Ruínas)
	precisam exatamente da mesma Tool -- duplicar a forma em 3 lugares
	significaria 3 lugares pra corrigir quando trocar por um modelo real.

	Cristal Ancestral e as peças do rádio NÃO têm
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
local FlashlightConfig = require(script.Parent.FlashlightConfig)
local FlashlightRig = require(script.Parent.FlashlightRig)
local BatConfig = require(script.Parent.BaseballBatConfig)
local ServerStorage = game:GetService("ServerStorage")
local AssetService = game:GetService("AssetService")

local ToolFactory = {}

type AssetToolOptions = {
	Length: number,
	Fallback: () -> Tool?,
}

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

local function sanitizeToolPart(part: BasePart)
	part.Anchored = false
	part.CanCollide = false
	part.CanTouch = true
	part.CanQuery = false
	part.Massless = true
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
	sanitizeToolPart(handle)
	handle.Parent = tool

	for i = 2, #parts do
		local part = parts[i]
		sanitizeToolPart(part)
		part.Parent = handle
		local weld = Instance.new("WeldConstraint")
		weld.Part0 = handle
		weld.Part1 = part
		weld.Parent = part
	end

	model:Destroy() -- já esvaziado: as Parts foram todas reparentadas acima
	return tool
end

local function buildAssetTool(itemId: string, options: AssetToolOptions): Tool?
	local def = ItemRegistry.Items[itemId]
	local assetId = def and def.AssetId
	if type(assetId) == "number" and assetId > 0 then
		local template = AssetLoader.Load(assetId)
		if template then
			local model = template:Clone()
			scaleModelToLength(model, options.Length)
			local tool = buildToolFromAssetModel(model, def.DisplayName)
			if tool then
				tool:SetAttribute("ModelAssetId", assetId)
				return tool
			end
			warn(string.format("[ToolFactory] O asset %d de '%s' nao possui BaseParts validas; usando fallback.", assetId, itemId))
		else
			warn(string.format("[ToolFactory] Nao consegui carregar o asset %s de '%s'; usando fallback.", tostring(assetId), itemId))
		end
	end

	local fallback = options.Fallback()
	if fallback then
		fallback.Name = def and def.DisplayName or fallback.Name
	end
	return fallback
end

local function sanitizeTool(tool: Tool)
	tool.Name = "Lanterna"
	tool.RequiresHandle = true
	tool.CanBeDropped = false
	for _, descendant in tool:GetDescendants() do
		if descendant:IsA("Script") or descendant:IsA("LocalScript") or descendant:IsA("ModuleScript") then
			descendant:Destroy()
		elseif descendant:IsA("BasePart") then
			descendant.Anchored = false
			descendant.CanCollide = false
			descendant.CanTouch = false
			descendant.CanQuery = false
			descendant.Massless = true
		end
	end
	tool:SetAttribute("Lanterna", true)
	tool:SetAttribute("Battery", FlashlightConfig.BatteryMax)
	tool:SetAttribute("FlashlightOn", false)
end

local function arczisFlashlightTemplate(): Tool?
	local package = ServerStorage:FindFirstChild("ArczisRealisticFlashlight")
	if not package then return nil end
	local template = package:FindFirstChild("Flashlight", true)
	return if template and template:IsA("Tool") then template else nil
end

local function fallbackFlashlight(): Tool?
	-- O modelo visual externo pode falhar por permissão ou indisponibilidade
	-- temporária do Toolbox. Ainda assim a ferramenta precisa existir:
	-- FlashlightRig monta o feixe, a bateria e os atributos funcionais a partir
	-- deste corpo simples.
	local model = Instance.new("Model")
	local handle = makeHandle(Vector3.new(0.32, 0.32, 1.6), Color3.fromRGB(38, 40, 44), Enum.Material.Metal)
	handle.Parent = model
	local tool = FlashlightRig.Build(model)
	if not tool then
		model:Destroy()
		return nil
	end
	tool:SetAttribute("FlashlightModelAssetId", ItemRegistry.Items.Lanterna.AssetId)
	return tool
end

--------------------------------------------------------------------------------
-- Taco de Beisebol
--------------------------------------------------------------------------------

-- Grip que segura o taco por uma ponta, com o corpo estendido ao longo do braco
-- (-Z do Handle = direcao dos dedos). O maior eixo do mesh e descoberto pelo
-- tamanho, ja que a orientacao do asset original nao e conhecida.
local function batGrip(size: Vector3): CFrame
	local override = BatConfig.GripOverride
	if override then
		return override
	end
	local sign = BatConfig.HandleEndSign
	local offset = BatConfig.Length * BatConfig.HandleEndFraction * sign
	if size.Y >= size.X and size.Y >= size.Z then
		return CFrame.fromMatrix(Vector3.new(0, offset, 0), Vector3.xAxis, Vector3.zAxis * -sign, Vector3.yAxis * sign)
	elseif size.X >= size.Z then
		return CFrame.fromMatrix(Vector3.new(offset, 0, 0), Vector3.zAxis * -sign, Vector3.yAxis, Vector3.xAxis * sign)
	end
	return CFrame.fromMatrix(Vector3.new(0, 0, offset), Vector3.xAxis * sign, Vector3.yAxis, Vector3.zAxis * sign)
end

-- CreateMeshPartAsync espera (yield) so na primeira chamada; depois clona.
local batMeshTemplate: MeshPart? = nil
local batMeshFailed = false

local function loadBatMesh(): MeshPart?
	if batMeshTemplate then
		return batMeshTemplate
	end
	if batMeshFailed then
		return nil
	end
	local ok, result = pcall(function()
		return AssetService:CreateMeshPartAsync(BatConfig.MeshId :: any)
	end)
	if ok and typeof(result) == "Instance" and result:IsA("MeshPart") then
		batMeshTemplate = result
		return result
	end
	batMeshFailed = true
	warn(string.format("[ToolFactory] Nao consegui carregar o mesh do Taco (%s): %s", BatConfig.MeshId, tostring(result)))
	return nil
end

-- Tool exportada do Explorer (ServerStorage.<TemplateName>): mantem o Grip, a
-- textura e a escala originais. Scripts embutidos sao removidos.
local function buildBatFromTemplate(): Tool?
	local found = ServerStorage:FindFirstChild(BatConfig.TemplateName)
	if not found then
		return nil
	end
	local template = if found:IsA("Tool") then found else found:FindFirstChildWhichIsA("Tool", true)
	if not template then
		return nil
	end
	if not template:FindFirstChild("Handle") then
		warn("[ToolFactory] A Tool do Taco em ServerStorage nao tem um Handle; ignorando o template.")
		return nil
	end

	local tool = template:Clone()
	tool.RequiresHandle = true
	for _, descendant in tool:GetDescendants() do
		if descendant:IsA("LuaSourceContainer") then
			descendant:Destroy()
		elseif descendant:IsA("BasePart") then
			sanitizeToolPart(descendant)
		end
	end
	return tool
end

local function buildBatFromMesh(): Tool?
	local template = loadBatMesh()
	if not template then
		return nil
	end
	local handle = template:Clone()
	handle.Name = "Handle"
	local size = handle.Size
	handle.Size = size * (BatConfig.Length / math.max(size.X, size.Y, size.Z, 0.01))
	if BatConfig.TextureId ~= "" then
		handle.TextureID = BatConfig.TextureId
	end
	handle.Color = BatConfig.Color
	handle.Material = BatConfig.Material
	sanitizeToolPart(handle)

	local tool = Instance.new("Tool")
	tool.RequiresHandle = true
	tool.Grip = batGrip(handle.Size)
	handle.Parent = tool
	return tool
end

local function buildBatFallback(): Tool
	local tool = Instance.new("Tool")
	tool.RequiresHandle = true
	local handle = makeHandle(Vector3.new(0.45, 0.45, BatConfig.Length), BatConfig.Color, BatConfig.Material)
	tool.Grip = batGrip(handle.Size)
	handle.Parent = tool
	return tool
end

local CONSTRUCTORS: { [string]: () -> Tool? } = {
	TacoBeisebol = function()
		local tool = buildBatFromTemplate() or buildBatFromMesh() or buildBatFallback()
		tool.Name = ItemRegistry.Items.TacoBeisebol.DisplayName
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
		return buildAssetTool("LancaDeBambu", {
			Length = 4.2,
			Fallback = function()
				local tool = Instance.new("Tool")
				tool.Name = "Crowbar"
				tool.RequiresHandle = true
				local handle = makeHandle(Vector3.new(0.25, 0.25, 4.2), Color3.fromRGB(95, 100, 110), Enum.Material.Metal)
				handle.Parent = tool
				return tool
			end,
		})
	end,

	Sinalizador = function()
		local tool = Instance.new("Tool")
		tool.Name = "Sinalizador"
		tool.RequiresHandle = true
		tool.CanBeDropped = false
		local handle = makeHandle(Vector3.new(0.4, 1.4, 0.4), Color3.fromRGB(190, 55, 35), Enum.Material.Metal)
		sanitizeToolPart(handle)
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
		local arczisTemplate = arczisFlashlightTemplate()
		if arczisTemplate then
			local tool = arczisTemplate:Clone()
			sanitizeTool(tool)
			if not FlashlightRig.Prepare(tool) then
				warn("[ToolFactory] A Tool Flashlight do pacote Arczis nao possui Handle valido.")
				tool:Destroy()
				return nil
			end
			tool:SetAttribute("FlashlightModelAssetId", ItemRegistry.Items.Lanterna.AssetId)
			return tool
		end

		local assetId = ItemRegistry.Items.Lanterna.AssetId
		local template = if type(assetId) == "number" and assetId > 0
			then AssetLoader.Load(assetId) else nil
		if not template then
			warn(string.format("[ToolFactory] O modelo visual da Lanterna (%s) nao carregou; usando corpo funcional de reserva.", tostring(assetId)))
			return fallbackFlashlight()
		end

		local model = template:Clone()
		scaleModelToLength(model, FlashlightConfig.ModelLength)
		local tool = FlashlightRig.Build(model)
		if not tool then
			warn(string.format("[ToolFactory] O asset %s nao possui uma estrutura valida de lanterna; usando corpo funcional de reserva.", tostring(assetId)))
			return fallbackFlashlight()
		end
		tool:SetAttribute("FlashlightModelAssetId", assetId)
		return tool
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
		return buildAssetTool("LancaAncestral", {
			Length = 4.8,
			Fallback = function()
				local tool = Instance.new("Tool")
				tool.Name = "Crowbar Ancestral"
				tool.RequiresHandle = true
				local handle = makeHandle(Vector3.new(0.35, 0.3, 4.8), Color3.fromRGB(140, 45, 35), Enum.Material.Metal)
				handle.Parent = tool
				return tool
			end,
		})
	end,
}

--[[
	Create(itemId)
	Cria uma nova instância da Tool, já com o Attribute correto marcado
	(ItemRegistry.Items[itemId].AttributeName). nil se não houver construtor
	pra esse id, OU se o construtor existir mas falhar. A Lanterna usa somente
	o modelo configurado; falhas de permissao/carregamento nao criam outro visual.
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
