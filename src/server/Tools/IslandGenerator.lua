--!strict
--[[
	IslandGenerator (ferramenta de editor)
	Gera o terreno e a natureza da ilha de "Náufragos" a partir do plano de
	IslandLayout.lua (forma, relevo, biomas, POIs, trilhas), e chama
	PoiGenerator pra construir os pontos de interesse.

	USO (Command Bar do Studio, em modo de edição):
		local Gen = require(game.ServerScriptService.Server.Tools.IslandGenerator)
		Gen.Generate()            -- tudo, na ordem certa, com resumo no Output
		Gen.Generate(42)          -- outra seed (muda costa, relevo, onde cai cada POI)

	Etapas isoladas (pra ajustar sem regerar tudo):
		Gen.GenerateTerrain()           -- mar, praia, colinas, montanha, campo, lago, trilhas
		Gen.GenerateRockFormations()    -- grupos de rochas + afloramentos grandes
		Gen.GenerateCave()              -- covil do Monstro dentro da montanha (CaveInterior)
		Gen.GenerateForest(1.0)         -- árvores (densidade 0..2)
		Gen.GenerateUndergrowth()       -- arbustos e troncos caídos
		Gen.GenerateRuins()             -- Ruínas + Lança Ancestral
		PoiGenerator.Generate()         -- acampamento, cabanas, lago, campo, torre, farol, vila
		Gen.ClearAll()

	Depois de gerar: PlaneCrashGenerator.Generate() e ItemSpawner.Generate(),
	e SALVAR (Ctrl+S). A Jangada o RaftObjective monta sozinho no boot.

	TAMANHO: ver IslandLayout.CONFIG. Diâmetro jogável ~1400-1600 studs;
	terreno real 1920 x 1920 em chunks de 96. A geração do terreno leva
	alguns minutos no Studio (yield a cada 2 chunks pra não travar; o Output
	mostra o progresso).

	MAR: bloco fundo de água até WaterHalf (a Atmosphere esconde o fim), com
	paredes invisíveis em AreaHalf. O fundo já começa SeaFloorDrop studs
	abaixo da linha d'água pra nunca virar placa caminhável (ver
	IslandLayout). RepairWater() corrige um mapa salvo com água antiga.

	MODELOS (CONFIG.Assets): árvores e rochas vêm de InsertService:LoadAsset --
	só funciona em MODO DE EDIÇÃO. Se um ID falhar, entra placeholder.
	Tudo que é gerado vai pra Workspace/Ilha/{Limites, Rochas, Caverna,
	Floresta, Vegetacao, Ruinas, POIs, Trilhas, Layout}.
]]

local Workspace = game:GetService("Workspace")
local InsertService = game:GetService("InsertService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Terrain = Workspace.Terrain

local ToolFactory = require(ReplicatedStorage.Modules.ToolFactory)
local Layout = require(script.Parent.IslandLayout)
local PoiGenerator = require(script.Parent.PoiGenerator)
local CaveInterior = require(script.Parent.CaveInterior)
local S = require(script.Parent.Structures)
local TreeCollisionFix = require(script.Parent.Parent.TreeCollisionFix)

local IslandGenerator = {}

--------------------------------------------------------------------------------
-- Ajustes (tamanho/forma ficam em IslandLayout.CONFIG)
--------------------------------------------------------------------------------

local CONFIG = {
	Cave = {
		-- Forma do covil (túnel, salão, níveis) fica em CaveInterior.CONFIG.
		EntranceRocks = 8,
	},

	Rocks = {
		Count = 46, -- grupos
		PerGroupMin = 1,
		PerGroupMax = 4,
		SizeMin = 8,
		SizeMax = 28,
		Outcrops = 7, -- afloramentos grandes
		OutcropSizeMin = 30,
		OutcropSizeMax = 52,
	},

	Forest = {
		MaxTrees = 1500, -- em densidade 1.0 (2600 deixava pesado e grudado)
		MinSpacing = 24, -- dá pra andar entre os troncos
		HeightMin = 36, -- personagem R6 ~5 studs; copa alta o bastante pra passar por baixo
		HeightMax = 62,
		LoneTreesInMeadow = 3,
		-- Fração das árvores que vem de Assets.TreesFavoritas (o resto sorteia
		-- de Assets.Trees). 0.85 = ~85% das árvores são dos 2 modelos favoritos.
		FavoriteChance = 0.85,
	},

	Undergrowth = {
		Bushes = 900,
		FallenLogs = 140,
		BushSpacing = 11,
	},

	Ruins = {
		Radius = 20,
		StoneCount = 8,
		StoneHeight = 9,
	},

	Assets = {
		-- Modelos preferidos: ~FavoriteChance das árvores saem daqui.
		TreesFavoritas = { 3256343670, 8310527548 },
		-- Variedade (os ~15% restantes).
		Trees = { 4728038922, 12196680826, 5521112313 },
		Rocks = { 4513606597, 282758654, 5496069794 },
	},

	Water = {
		Color = Color3.fromRGB(18, 74, 112),
		Transparency = 0.03,
		Reflectance = 0.04,
		WaveSize = 0.08,
		WaveSpeed = 4,
	},
}

local TAU = math.pi * 2
local LC = Layout.CONFIG

--------------------------------------------------------------------------------
-- Altura real do terreno (raycast, com fallback analítico)
--------------------------------------------------------------------------------

local raycastParams = RaycastParams.new()
raycastParams.FilterType = Enum.RaycastFilterType.Include
raycastParams.FilterDescendantsInstances = { Terrain }
raycastParams.IgnoreWater = true

local function surfaceHeight(x: number, z: number): number
	local origin = Vector3.new(x, LC.MaxY + 60, z)
	local direction = Vector3.new(0, -(LC.MaxY - LC.MinY + 140), 0)
	local result = Workspace:Raycast(origin, direction, raycastParams)
	if result then
		return result.Position.Y
	end
	return Layout.Height(x, z)
end

IslandGenerator.GetSurfaceHeight = surfaceHeight

--------------------------------------------------------------------------------
-- Pastas e Parts
--------------------------------------------------------------------------------

local function getIlhaFolder(): Folder
	local ilha = Workspace:FindFirstChild("Ilha")
	if not ilha then
		ilha = Instance.new("Folder")
		ilha.Name = "Ilha"
		ilha.Parent = Workspace
	end
	return ilha :: Folder
end

local function resetFolder(name: string): Folder
	local ilha = getIlhaFolder()
	local existing = ilha:FindFirstChild(name)
	if existing then
		existing:Destroy()
	end
	local folder = Instance.new("Folder")
	folder.Name = name
	folder.Parent = ilha
	return folder
end

local function newPart(name: string, size: Vector3, cframe: CFrame, material: Enum.Material, color: Color3, parent: Instance): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Size = size
	part.CFrame = cframe
	part.Material = material
	part.Color = color
	part.Anchored = true
	part.CanCollide = true
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Parent = parent
	return part
end

local VERTICAL = CFrame.Angles(0, 0, math.pi / 2)

local function rockColor(rng: Random): Color3
	local v = rng:NextInteger(88, 132)
	return Color3.fromRGB(v, v, v + rng:NextInteger(0, 8))
end

--------------------------------------------------------------------------------
-- Modelos do Roblox (InsertService), com cache e placeholder de reserva
--------------------------------------------------------------------------------
-- MUITOS assets de árvore/rocha são "PACOTES": um asset só com 5-30 modelos
-- dentro. loadTemplate junta tudo num Model só (o avião precisa disso). Mas
-- pra floresta a gente quer UMA árvore por vez -- senão cada "árvore" plantada
-- é o pacote inteiro amassado num ponto (foi o que deixou o mapa "lotado de
-- árvores grudadas e baixas"). loadVariants separa o pacote em modelos
-- individuais; pickTreeVariant/pickRockVariant sorteiam um.

local containerCache: { [number]: Instance? } = {} -- container normalizado (não parenteado)
local templates: { [number]: Model } = {} -- versão "tudo junto" (loadTemplate)
local variantCache: { [number]: { Model } } = {} -- versão separada (loadVariants)
local failedTemplates: { [number]: boolean } = {}

-- Baixa o asset e devolve um Instance "holder" com o conteúdo cru (ou nil).
local function fetchContainer(assetId: number): Instance?
	if containerCache[assetId] ~= nil then
		return containerCache[assetId]
	end
	if failedTemplates[assetId] then
		return nil
	end

	local ok, container = pcall(function()
		return InsertService:LoadAsset(assetId)
	end)
	if not ok or typeof(container) ~= "Instance" then
		ok, container = pcall(function()
			local objects = game:GetObjects("rbxassetid://" .. assetId)
			local holder = Instance.new("Model")
			for _, obj in objects do
				obj.Parent = holder
			end
			return holder
		end)
	end
	if not ok or typeof(container) ~= "Instance" then
		failedTemplates[assetId] = true
		warn(string.format("[IslandGenerator] Não consegui carregar o asset %d: %s", assetId, tostring(container)))
		return nil
	end

	local holder = container :: Instance
	holder.Parent = nil
	for _, descendant in holder:GetDescendants() do
		if descendant:IsA("LuaSourceContainer") then
			descendant:Destroy()
		elseif descendant:IsA("BasePart") then
			descendant.Anchored = true
		end
	end
	containerCache[assetId] = holder
	return holder
end

local function normalizeModel(model: Model)
	if not model.PrimaryPart then
		local firstPart = model:FindFirstChildWhichIsA("BasePart", true)
		if firstPart then
			model.PrimaryPart = firstPart
		end
	end
end

local function loadTemplate(assetId: number): Model?
	if templates[assetId] then
		return templates[assetId]
	end
	local holder = fetchContainer(assetId)
	if not holder then
		return nil
	end

	local children = holder:GetChildren()
	local model: Model
	if #children == 1 and children[1]:IsA("Model") then
		model = (children[1]:Clone() :: Model)
	else
		model = Instance.new("Model")
		model.Name = "Asset_" .. assetId
		for _, child in children do
			child:Clone().Parent = model
		end
	end
	model.Parent = nil
	normalizeModel(model)
	templates[assetId] = model
	return model
end

-- Um modelo tem "corpo" se contém pelo menos uma BasePart.
local function hasBodyPart(inst: Instance): boolean
	if inst:IsA("BasePart") then
		return true
	end
	return inst:FindFirstChildWhichIsA("BasePart", true) ~= nil
end

--[[
	loadVariants(assetId)
	Separa o asset em modelos individuais (uma árvore/rocha por Model). Se o
	asset for um único objeto, devolve uma lista com ele só. Cada variante é
	um template CLONÁVEL, não parenteado.
]]
local function loadVariants(assetId: number): { Model }
	if variantCache[assetId] then
		return variantCache[assetId]
	end
	local holder = fetchContainer(assetId)
	if not holder then
		variantCache[assetId] = {}
		return {}
	end

	-- Camada de "objetos": desce por Models/Folders que só EMBRULHAM outros
	-- Models/Folders (pacotes costumam vir com 1-2 camadas de wrapper). Para
	-- de descer quando a camada tem vários objetos, ou quando o objeto único
	-- já é uma árvore (filhos = BaseParts, não sub-modelos).
	local function isGrouper(inst: Instance): boolean
		if not (inst:IsA("Model") or inst:IsA("Folder")) then
			return false
		end
		for _, c in inst:GetChildren() do
			if c:IsA("Model") or c:IsA("Folder") then
				return true
			end
		end
		return false
	end

	local layer: { Instance } = holder:GetChildren()
	while #layer == 1 and isGrouper(layer[1]) do
		layer = layer[1]:GetChildren()
	end

	local variants: { Model } = {}
	for _, obj in layer do
		if (obj:IsA("Model") or obj:IsA("Folder")) and hasBodyPart(obj) then
			local m: Model
			if obj:IsA("Model") then
				m = (obj:Clone() :: Model)
			else
				m = Instance.new("Model")
				for _, c in obj:GetChildren() do
					c:Clone().Parent = m
				end
			end
			m.Name = "Variante"
			m.Parent = nil
			normalizeModel(m)
			table.insert(variants, m)
		end
	end

	-- Nada separável -> usa o asset inteiro como uma variante só.
	if #variants == 0 then
		local whole = loadTemplate(assetId)
		if whole then
			variants = { whole }
		end
	end

	variantCache[assetId] = variants
	return variants
end

--[[
	LoadAssetModel(assetId)
	Carrega (com cache) um asset do Roblox já normalizado: um único Model,
	sem scripts, tudo Anchored. PlaneCrashGenerator usa o mesmo.
]]
IslandGenerator.LoadAssetModel = loadTemplate

-- Y do ponto mais BAIXO do modelo, no mundo, calculado a partir das BaseParts
-- de verdade (não do GetBoundingBox, que segue a orientação do pivô e às
-- vezes inclui partes decorativas que bagunçam a conta). É isto que
-- garante que a base da árvore encosta no chão.
local function modelBottomY(model: Model): number?
	local minY = math.huge
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			local cf, s = d.CFrame, d.Size
			local r, u, l = cf.RightVector, cf.UpVector, cf.LookVector
			local extY = math.abs(r.Y) * s.X + math.abs(u.Y) * s.Y + math.abs(l.Y) * s.Z
			local partBottom = cf.Position.Y - extY * 0.5
			if partBottom < minY then
				minY = partBottom
			end
		end
	end
	return if minY < math.huge then minY else nil
end

local function placeModel(template: Model, parent: Instance, x: number, z: number, groundY: number, targetHeight: number, yaw: number, sink: number, name: string): Model
	local clone = template:Clone()
	clone.Name = name

	local _, size = clone:GetBoundingBox()
	if size.Y > 0.01 then
		clone:ScaleTo(clone:GetScale() * (targetHeight / size.Y))
	end

	clone:PivotTo(CFrame.new(x, groundY, z) * CFrame.Angles(0, yaw, 0))
	local bottom = modelBottomY(clone) or clone:GetPivot().Position.Y
	-- Assenta a base em (groundY - sink): sink > 0 crava um pouco no chão,
	-- então nunca fica flutuando, nem em ladeira.
	clone:PivotTo(clone:GetPivot() + Vector3.new(0, (groundY - bottom) - sink, 0))

	clone.Parent = parent
	return clone
end

-- Sorteia UMA variante (um modelo individual) de um conjunto de IDs de
-- asset -- cada ID pode ser um pacote com vários modelos dentro.
local function pickVariant(rng: Random, ids: { number }): Model?
	local order = table.clone(ids)
	for i = #order, 2, -1 do
		local j = rng:NextInteger(1, i)
		order[i], order[j] = order[j], order[i]
	end
	local pool: { Model } = {}
	for _, id in order do
		for _, v in loadVariants(id) do
			table.insert(pool, v)
		end
		if #pool > 0 then
			break -- primeiro ID que carregou alguma coisa
		end
	end
	if #pool == 0 then
		return nil
	end
	return pool[rng:NextInteger(1, #pool)]
end

local function pickAsset(rng: Random, ids: { number }): Model?
	return pickVariant(rng, ids)
end

-- Árvore: FavoriteChance das vezes sorteia dos pacotes favoritos; se nenhum
-- favorito carregar, cai nos outros (e vice-versa).
local function pickTree(rng: Random): Model?
	local favoritesFirst = rng:NextNumber() < CONFIG.Forest.FavoriteChance
	local first = if favoritesFirst then CONFIG.Assets.TreesFavoritas else CONFIG.Assets.Trees
	local second = if favoritesFirst then CONFIG.Assets.Trees else CONFIG.Assets.TreesFavoritas
	return pickVariant(rng, first) or pickVariant(rng, second)
end

local function placeholderRock(parent: Instance, groundPos: Vector3, size: number, rng: Random, name: string)
	local isBall = rng:NextNumber() < 0.4
	local dims = if isBall
		then Vector3.new(size, size, size)
		else Vector3.new(size * rng:NextNumber(0.7, 1.3), size * rng:NextNumber(0.5, 1.0), size * rng:NextNumber(0.7, 1.3))
	local cf = CFrame.new(groundPos + Vector3.new(0, dims.Y * 0.3, 0))
		* CFrame.Angles(rng:NextNumber(-0.4, 0.4), rng:NextNumber(0, TAU), rng:NextNumber(-0.4, 0.4))
	local part = newPart(name, dims, cf, Enum.Material.Rock, rockColor(rng), parent)
	if isBall then
		part.Shape = Enum.PartType.Ball
	end
end

local function placeholderTree(parent: Instance, x: number, z: number, groundY: number, height: number, rng: Random, name: string)
	local model = Instance.new("Model")
	model.Name = name
	local trunkH = height * 0.55
	local trunkD = rng:NextNumber(2.2, 3.6)
	local canopyD = height * 0.62
	local trunk = newPart("Tronco", Vector3.new(trunkH, trunkD, trunkD), CFrame.new(x, groundY + trunkH / 2 - 0.5, z) * VERTICAL, Enum.Material.Wood, Color3.fromRGB(96, 64, 34), model)
	trunk.Shape = Enum.PartType.Cylinder
	local canopy = newPart("Copa", Vector3.new(canopyD, canopyD, canopyD), CFrame.new(x, groundY + trunkH + canopyD * 0.32, z), Enum.Material.LeafyGrass, Color3.fromRGB(44, 110, 40), model)
	canopy.Shape = Enum.PartType.Ball
	canopy.CanCollide = false
	model.PrimaryPart = trunk
	model.Parent = parent
end

--------------------------------------------------------------------------------
-- 1. TERRENO
--------------------------------------------------------------------------------

local function applyWaterLook()
	Terrain.WaterColor = CONFIG.Water.Color
	Terrain.WaterTransparency = CONFIG.Water.Transparency
	Terrain.WaterReflectance = CONFIG.Water.Reflectance
	Terrain.WaterWaveSize = CONFIG.Water.WaveSize
	Terrain.WaterWaveSpeed = CONFIG.Water.WaveSpeed
	pcall(function()
		(Terrain :: any).Decoration = true -- grama animada em Grass/LeafyGrass
	end)
end

local function containsAny(value: string, fragments: { string }): boolean
	for _, fragment in fragments do
		if string.find(value, fragment, 1, true) then
			return true
		end
	end
	return false
end

local function looksLikeWaterPlane(part: BasePart): boolean
	local size = part.Size
	local footprint = size.X * size.Z
	local largeFlat = footprint >= 20000 and math.max(size.X, size.Z) >= 150 and size.Y <= 8
	local nearSea = math.abs(part.Position.Y - LC.SeaLevel) <= 12
	if not largeFlat or not nearSea then
		return false
	end
	local lowerName = string.lower(part.Name)
	local namedWater = containsAny(lowerName, { "baseplate", "base plate", "water", "agua", "mar", "ocean", "oceano", "sea" })
	local color = part.Color
	local bluePlane = color.B > color.R * 1.25 and color.B > color.G * 0.8
	local grayHugePlane = footprint >= 100000 and math.abs(color.R - color.G) < 0.08 and math.abs(color.G - color.B) < 0.08
	return namedWater or bluePlane or grayHugePlane
end

local function removeLegacyWaterPlanes(): number
	local removed = 0
	for _, descendant in Workspace:GetDescendants() do
		if descendant:IsA("BasePart") and looksLikeWaterPlane(descendant) then
			descendant:Destroy()
			removed += 1
		end
	end
	return removed
end

local function fillOceanShell()
	local waterHalf, areaHalf = LC.WaterHalf, LC.AreaHalf
	local side = waterHalf - areaHalf
	if side <= 0 then
		return
	end
	local top = LC.SeaLevel
	local bottom = LC.MinY - LC.OceanDepth
	local height = top - bottom
	local centerY = (top + bottom) / 2
	local areaSize = areaHalf * 2
	Terrain:FillBlock(CFrame.new(0, centerY, areaHalf + side / 2), Vector3.new(areaSize, height, side), Enum.Material.Water)
	Terrain:FillBlock(CFrame.new(0, centerY, -areaHalf - side / 2), Vector3.new(areaSize, height, side), Enum.Material.Water)
	Terrain:FillBlock(CFrame.new(areaHalf + side / 2, centerY, 0), Vector3.new(side, height, waterHalf * 2), Enum.Material.Water)
	Terrain:FillBlock(CFrame.new(-areaHalf - side / 2, centerY, 0), Vector3.new(side, height, waterHalf * 2), Enum.Material.Water)
end

-- Garante água de verdade (e nada de placa) em toda a faixa de mar dentro
-- da área real: acima do mar vira Air, entre o fundo e o mar vira Water.
local function repairOceanTerrain(): number
	Layout.Plan()
	local res, chunk = LC.VoxelRes, LC.Chunk
	local half = LC.AreaHalf
	local minY, maxY = LC.MinY, LC.SeaLevel + res * 2
	local changed = 0
	local chunksDone = 0

	for cx = -half, half - chunk, chunk do
		for cz = -half, half - chunk, chunk do
			local region = Region3.new(Vector3.new(cx, minY, cz), Vector3.new(cx + chunk, maxY, cz + chunk))
			local materials, occupancies = Terrain:ReadVoxels(region, res)
			local chunkChanged = false

			for i = 1, #materials do
				local x = cx + (i - 0.5) * res
				for k = 1, #materials[i][1] do
					local z = cz + (k - 0.5) * res
					local _, _, inland = Layout.IslandInfo(x, z)
					if inland < -1 then
						local floorY = math.min(LC.SeaLevel - 6, Layout.RawHeight(x, z))
						for j = 1, #materials[i] do
							local yb = minY + (j - 1) * res
							local desiredMaterial = materials[i][j][k]
							local desiredOccupancy = occupancies[i][j][k]

							if yb >= LC.SeaLevel then
								desiredMaterial = Enum.Material.Air
								desiredOccupancy = 0
							elseif yb >= floorY then
								desiredMaterial = Enum.Material.Water
								desiredOccupancy = math.clamp((LC.SeaLevel - yb) / res, 0, 1)
							end

							if materials[i][j][k] ~= desiredMaterial or math.abs(occupancies[i][j][k] - desiredOccupancy) > 0.001 then
								materials[i][j][k] = desiredMaterial
								occupancies[i][j][k] = desiredOccupancy
								chunkChanged = true
								changed += 1
							end
						end
					end
				end
			end

			if chunkChanged then
				Terrain:WriteVoxels(region, res, materials, occupancies)
			end
			chunksDone += 1
			if chunksDone % 4 == 0 then
				task.wait()
			end
		end
	end

	return changed
end

function IslandGenerator.RepairWater(): (number, number)
	applyWaterLook()
	local removed = removeLegacyWaterPlanes()
	fillOceanShell()
	local filled = repairOceanTerrain()
	if removed > 0 or filled > 0 then
		print(string.format("[IslandGenerator] Água reparada -- pisos falsos removidos: %d | voxels de oceano corrigidos: %d", removed, filled))
	end
	return removed, filled
end

local function buildBoundary()
	local limites = resetFolder("Limites")
	local half = LC.AreaHalf - 8
	local height = 220
	local centerY = LC.MinY - 20 + height / 2
	local thickness = 4
	local length = half * 2 + thickness * 2

	local walls = {
		{ pos = Vector3.new(half + thickness / 2, centerY, 0), size = Vector3.new(thickness, height, length) },
		{ pos = Vector3.new(-half - thickness / 2, centerY, 0), size = Vector3.new(thickness, height, length) },
		{ pos = Vector3.new(0, centerY, half + thickness / 2), size = Vector3.new(length, height, thickness) },
		{ pos = Vector3.new(0, centerY, -half - thickness / 2), size = Vector3.new(length, height, thickness) },
	}
	for i, wall in walls do
		local part = newPart("Limite_" .. i, wall.size, CFrame.new(wall.pos), Enum.Material.SmoothPlastic, Color3.new(1, 1, 1), limites)
		part.Transparency = 1
		part.CanQuery = false
	end
end

--[[
	GenerateTerrain()
	Escreve o terreno inteiro por chunks a partir de Layout.Height/Material/
	WaterLevel (mar, praia, colinas, montanha, campo plano, bacia do lago com
	água, trilhas rebaixadas de terra).
]]
function IslandGenerator.GenerateTerrain()
	Layout.Plan()
	applyWaterLook()
	removeLegacyWaterPlanes()

	for _, name in { "Baseplate", "BasePlate" } do
		local bp = Workspace:FindFirstChild(name)
		if bp and bp:IsA("BasePart") then
			bp:Destroy()
		end
	end

	local waterSize = LC.WaterHalf * 2
	local oceanTop, oceanBottom = LC.SeaLevel, LC.MinY - LC.OceanDepth
	Terrain:FillBlock(CFrame.new(0, (oceanTop + oceanBottom) / 2, 0), Vector3.new(waterSize, oceanTop - oceanBottom, waterSize), Enum.Material.Water)

	local res, chunk = LC.VoxelRes, LC.Chunk
	local half = LC.AreaHalf
	local minY, maxY = LC.MinY, LC.MaxY
	local ny = (maxY - minY) // res
	local n = chunk // res
	local water, air = Enum.Material.Water, Enum.Material.Air

	local chunksDone = 0
	local totalChunks = ((half * 2) // chunk) ^ 2
	local t0 = os.clock()

	for cx = -half, half - chunk, chunk do
		for cz = -half, half - chunk, chunk do
			local materials: { { { Enum.Material } } } = table.create(n)
			local occupancies: { { { number } } } = table.create(n)
			for i = 1, n do
				local colM = table.create(ny)
				local colO = table.create(ny)
				for j = 1, ny do
					colM[j] = table.create(n, air)
					colO[j] = table.create(n, 0)
				end
				materials[i] = colM
				occupancies[i] = colO
			end

			for i = 1, n do
				local x = cx + (i - 0.5) * res
				for k = 1, n do
					local z = cz + (k - 0.5) * res
					local h = Layout.Height(x, z)
					local mat = Layout.Material(x, z)
					local waterLevel = Layout.WaterLevel(x, z)

					for j = 1, ny do
						local yb = minY + (j - 1) * res
						local occ = math.clamp((h - yb) / res, 0, 1)

						if occ > 0.02 then
							materials[i][j][k] = mat
							occupancies[i][j][k] = occ
						elseif yb < waterLevel then
							materials[i][j][k] = water
							occupancies[i][j][k] = math.clamp((waterLevel - yb) / res, 0, 1)
						end
					end
				end
			end

			local region = Region3.new(Vector3.new(cx, minY, cz), Vector3.new(cx + chunk, maxY, cz + chunk))
			Terrain:WriteVoxels(region, res, materials, occupancies)

			chunksDone += 1
			if chunksDone % 2 == 0 then
				task.wait()
			end
			if chunksDone % 50 == 0 then
				print(string.format("[IslandGenerator] terreno %d/%d chunks (%.0fs)", chunksDone, totalChunks, os.clock() - t0))
			end
		end
	end

	buildBoundary()
end

--------------------------------------------------------------------------------
-- 2. ROCHAS
--------------------------------------------------------------------------------

function IslandGenerator.GenerateRockFormations(count: number?): number
	Layout.Plan()
	local total = count or CONFIG.Rocks.Count
	local rochas = resetFolder("Rochas")
	local rng = Random.new(Layout.Seed() + 2)
	local limit = LC.CoastRadiusMax

	local placed: { { x: number, z: number, r: number } } = {}
	local built = 0

	local function trySite(minInland: number, spread: number, avoidMargin: number): Vector3?
		for _ = 1, 60 do
			local x, z = rng:NextNumber(-limit, limit), rng:NextNumber(-limit, limit)
			local _, _, inland = Layout.IslandInfo(x, z)
			if inland >= minInland and not Layout.IsClearAt(x, z, avoidMargin) then
				local ok = true
				for _, p in placed do
					if (x - p.x) ^ 2 + (z - p.z) ^ 2 < (p.r + spread + 14) ^ 2 then
						ok = false
						break
					end
				end
				if ok then
					return Vector3.new(x, 0, z)
				end
			end
		end
		return nil
	end

	local function buildGroup(name: string, site: Vector3, spread: number, minRocks: number, maxRocks: number, sizeMin: number, sizeMax: number, keepRadius: number)
		local model = Instance.new("Model")
		model.Name = name
		for r = 1, rng:NextInteger(minRocks, maxRocks) do
			local gx = site.X + rng:NextNumber(-spread, spread)
			local gz = site.Z + rng:NextNumber(-spread, spread)
			local groundY = surfaceHeight(gx, gz)
			local size = rng:NextNumber(sizeMin, sizeMax)
			local template = pickAsset(rng, CONFIG.Assets.Rocks)
			if template then
				placeModel(template, model, gx, gz, groundY, size, rng:NextNumber(0, TAU), size * 0.28, "Pedra_" .. r)
			else
				placeholderRock(model, Vector3.new(gx, groundY, gz), size, rng, "Pedra_" .. r)
			end
		end
		model:SetAttribute("CentroX", site.X)
		model:SetAttribute("CentroZ", site.Z)
		model:SetAttribute("Raio", keepRadius)
		model.Parent = rochas
		table.insert(placed, { x = site.X, z = site.Z, r = spread })
		built += 1
	end

	-- Afloramentos grandes primeiro (mais difíceis de encaixar).
	for i = 1, CONFIG.Rocks.Outcrops do
		local spread = rng:NextNumber(10, 18)
		local site = trySite(20, spread, 12)
		if site then
			buildGroup("Afloramento_" .. i, site, spread, 2, 4, CONFIG.Rocks.OutcropSizeMin, CONFIG.Rocks.OutcropSizeMax, spread + CONFIG.Rocks.OutcropSizeMax * 0.5)
		end
	end

	for i = 1, total do
		local spread = rng:NextNumber(5, 12)
		local site = trySite(12, spread, 4)
		if site then
			buildGroup("Rochas_" .. i, site, spread, CONFIG.Rocks.PerGroupMin, CONFIG.Rocks.PerGroupMax, CONFIG.Rocks.SizeMin, CONFIG.Rocks.SizeMax, spread + CONFIG.Rocks.SizeMax * 0.5)
		end
		if i % 10 == 0 then
			task.wait()
		end
	end

	return built
end

--------------------------------------------------------------------------------
-- 3. CAVERNA
--------------------------------------------------------------------------------

function IslandGenerator.GenerateCave(): number
	Layout.Plan()
	local caverna = resetFolder("Caverna")
	local seed = Layout.Seed() + 3
	local rng = Random.new(seed)

	local mx, mz = Layout.MountainSite()
	local R = LC.Mountain.Radius
	local len = math.sqrt(mx * mx + mz * mz)
	local dir = if len > 0.01 then Vector3.new(-mx / len, 0, -mz / len) else Vector3.new(1, 0, 0)
	local side = Vector3.new(-dir.Z, 0, dir.X)

	local mouthDist = R * 0.72
	local entrance = Vector3.new(mx, 0, mz) + dir * mouthDist
	-- A boca fica na encosta; o salão fica MAIS FUNDO (o túnel desce Drop
	-- studs), o que deixa o covil abaixo do nível da ilha lá fora.
	local mouthY = surfaceHeight(entrance.X, entrance.Z) - 1
	local floorY = mouthY - CaveInterior.CONFIG.Tunnel.Drop

	local frame: CaveInterior.Frame = {
		Center = Vector3.new(mx, 0, mz),
		Dir = dir,
		Side = side,
		FloorY = floorY,
		MouthY = mouthY,
		MouthDist = mouthDist,
		SurfaceY = surfaceHeight,
		PlanY = Layout.Height,
	}

	local spawnPos = CaveInterior.Build(caverna, frame, seed)

	-- Marcador lido por LobbyManager (spawn do Monstro) e por
	-- PlaneCrashGenerator (pra desviar os rastros da caverna).
	local marker = newPart("MonstroSpawn", Vector3.new(2, 1, 2), CFrame.new(spawnPos), Enum.Material.SmoothPlastic, Color3.fromRGB(200, 40, 40), caverna)
	marker.Transparency = 1
	marker.CanCollide = false
	marker:SetAttribute("MonstroSpawn", true)

	-- Rochas soltas escondendo a boca de quem passa pela trilha.
	local W = CaveInterior.CONFIG.Tunnel.Width
	for i = 1, CONFIG.Cave.EntranceRocks do
		local s = if i % 2 == 0 then 1 else -1
		local p = entrance + dir * rng:NextNumber(-2, 12) + side * (s * rng:NextNumber(W / 2 + 6, W / 2 + 16))
		local groundY = surfaceHeight(p.X, p.Z)
		local size = rng:NextNumber(10, 20)
		local template = pickAsset(rng, CONFIG.Assets.Rocks)
		if template then
			placeModel(template, caverna, p.X, p.Z, groundY, size, rng:NextNumber(0, TAU), size * 0.25, "RochaEntrada_" .. i)
		else
			placeholderRock(caverna, Vector3.new(p.X, groundY, p.Z), size, rng, "RochaEntrada_" .. i)
		end
	end

	return 1
end

--------------------------------------------------------------------------------
-- 4. FLORESTA
--------------------------------------------------------------------------------

local function collectRockCircles(): { { x: number, z: number, r: number } }
	local circles = {}
	local rochas = getIlhaFolder():FindFirstChild("Rochas")
	if not rochas then
		return circles
	end
	for _, child in rochas:GetChildren() do
		if child:IsA("Model") then
			local x = child:GetAttribute("CentroX")
			local z = child:GetAttribute("CentroZ")
			local r = child:GetAttribute("Raio")
			if type(x) == "number" and type(z) == "number" and type(r) == "number" then
				table.insert(circles, { x = x, z = z, r = r })
			end
		end
	end
	return circles
end

--[[
	GenerateForest(density)
	Árvores grandes (30-56 studs) com espaçamento, evitando praia, montanha,
	trilhas, clareiras de POI, campo, lago e rochas. Umas poucas solitárias
	no campo aberto.
]]
function IslandGenerator.GenerateForest(density: number?): number
	Layout.Plan()
	local dens = math.clamp(density or 1, 0, 2)
	local floresta = resetFolder("Floresta")
	local rng = Random.new(Layout.Seed() + 4)
	local rocks = collectRockCircles()
	local limit = LC.CoastRadiusMax

	local minSpacing = CONFIG.Forest.MinSpacing
	local target = math.floor(CONFIG.Forest.MaxTrees * dens)
	local attempts = math.min(target * 25, 90000)

	-- Diagnóstico: quantos modelos individuais cada pacote rendeu.
	for _, id in CONFIG.Assets.TreesFavoritas do
		print(string.format("[IslandGenerator] pacote de árvore %d -> %d modelo(s)", id, #loadVariants(id)))
	end

	local grid: { [string]: { Vector2 } } = {}
	local function cellKey(cxI: number, czI: number): string
		return cxI .. ":" .. czI
	end
	local function tooClose(x: number, z: number): boolean
		local cxI, czI = math.floor(x / minSpacing), math.floor(z / minSpacing)
		for i = -1, 1 do
			for j = -1, 1 do
				local bucket = grid[cellKey(cxI + i, czI + j)]
				if bucket then
					for _, p in bucket do
						if (p.X - x) ^ 2 + (p.Y - z) ^ 2 < minSpacing ^ 2 then
							return true
						end
					end
				end
			end
		end
		return false
	end
	local function remember(x: number, z: number)
		local key = cellKey(math.floor(x / minSpacing), math.floor(z / minSpacing))
		local bucket = grid[key]
		if not bucket then
			bucket = {}
			grid[key] = bucket
		end
		table.insert(bucket, Vector2.new(x, z))
	end

	local function plant(x: number, z: number, height: number, name: string)
		local groundY = surfaceHeight(x, z)
		local template = pickTree(rng)
		if template then
			-- Sink generoso (~2.5 studs + fração da altura): tronco sempre
			-- cravado, nunca flutua -- inclusive em ladeira.
			local sink = 2.5 + height * 0.04
			placeModel(template, floresta, x, z, groundY, height, rng:NextNumber(0, TAU), sink, name)
		else
			placeholderTree(floresta, x, z, groundY, height, rng, name)
		end
		remember(x, z)
	end

	local trees = 0
	for _ = 1, attempts do
		if trees >= target then
			break
		end
		local x, z = rng:NextNumber(-limit, limit), rng:NextNumber(-limit, limit)
		local _, _, inland = Layout.IslandInfo(x, z)
		if inland < LC.BeachWidth + 4 or tooClose(x, z) then
			continue
		end
		if Layout.MountainContribution(x, z) > 6 or Layout.IsClearAt(x, z, 6) then
			continue
		end
		local blocked = false
		for _, rk in rocks do
			if (x - rk.x) ^ 2 + (z - rk.z) ^ 2 < (rk.r + 5) ^ 2 then
				blocked = true
				break
			end
		end
		if blocked then
			continue
		end

		trees += 1
		plant(x, z, rng:NextNumber(CONFIG.Forest.HeightMin, CONFIG.Forest.HeightMax), "Arvore_" .. trees)
		if trees % 40 == 0 then
			task.wait()
		end
	end

	-- Árvores solitárias grandes no campo aberto.
	local campo = Layout.Site("Campo")
	if campo then
		for i = 1, CONFIG.Forest.LoneTreesInMeadow do
			local a = rng:NextNumber(0, TAU)
			local d = rng:NextNumber(campo.r * 0.35, campo.r * 0.75)
			local x, z = campo.x + math.cos(a) * d, campo.z + math.sin(a) * d
			if Layout.DistToTrail(x, z) > 12 then
				trees += 1
				plant(x, z, CONFIG.Forest.HeightMax + 8, "ArvoreSolitaria_" .. i)
			end
		end
	end

	-- Arvore_597 e Arvore_428 identificam duas variantes cuja colisao de mesh
	-- vira uma parede invisivel. Usa essas referencias para corrigir todas as
	-- copias imediatamente, inclusive ao regenerar e salvar a floresta.
	local fixedTrees, fixedParts, trunkColliders = TreeCollisionFix.Apply(floresta)
	print(string.format(
		"[IslandGenerator] colisao corrigida em %d arvore(s): %d mesh(es), %d tronco(s)",
		fixedTrees,
		fixedParts,
		trunkColliders
	))

	return trees
end

--------------------------------------------------------------------------------
-- 5. VEGETAÇÃO RASTEIRA
--------------------------------------------------------------------------------

function IslandGenerator.GenerateUndergrowth(): (number, number)
	Layout.Plan()
	local folder = resetFolder("Vegetacao")
	local rng = Random.new(Layout.Seed() + 6)
	local limit = LC.CoastRadiusMax
	local spacing = CONFIG.Undergrowth.BushSpacing

	local bushes, logs = 0, 0
	local grid: { [string]: boolean } = {}

	local function claim(x: number, z: number): boolean
		local key = math.floor(x / spacing) .. ":" .. math.floor(z / spacing)
		if grid[key] then
			return false
		end
		grid[key] = true
		return true
	end

	local tries = 0
	while bushes < CONFIG.Undergrowth.Bushes and tries < CONFIG.Undergrowth.Bushes * 12 do
		tries += 1
		local x, z = rng:NextNumber(-limit, limit), rng:NextNumber(-limit, limit)
		local _, _, inland = Layout.IslandInfo(x, z)
		if inland < LC.BeachWidth + 2 or Layout.MountainContribution(x, z) > 8 or Layout.IsClearAt(x, z, 2) then
			continue
		end
		if not claim(x, z) then
			continue
		end
		S.Bush(folder, Vector3.new(x, surfaceHeight(x, z), z), rng)
		bushes += 1
		if bushes % 80 == 0 then
			task.wait()
		end
	end

	tries = 0
	while logs < CONFIG.Undergrowth.FallenLogs and tries < CONFIG.Undergrowth.FallenLogs * 12 do
		tries += 1
		local x, z = rng:NextNumber(-limit, limit), rng:NextNumber(-limit, limit)
		local _, _, inland = Layout.IslandInfo(x, z)
		if inland < LC.BeachWidth + 6 or Layout.MountainContribution(x, z) > 6 or Layout.IsClearAt(x, z, 8) then
			continue
		end
		S.FallenLog(folder, Vector3.new(x, surfaceHeight(x, z), z), rng)
		logs += 1
	end

	return bushes, logs
end

--------------------------------------------------------------------------------
-- 6. RUÍNAS (Lança Ancestral -- 1 por mapa)
--------------------------------------------------------------------------------

function IslandGenerator.GenerateRuins(): number
	Layout.Plan()
	local ruinas = resetFolder("Ruinas")
	local site = Layout.Site("Ruinas")
	if not site then
		warn("[IslandGenerator] Layout não tem site 'Ruinas' nesta seed.")
		return 0
	end

	local rx, rz = site.x, site.z
	local groundY = surfaceHeight(rx, rz)
	local rng = Random.new(Layout.Seed() + 9)
	local R = CONFIG.Ruins.Radius

	for i = 1, CONFIG.Ruins.StoneCount do
		local a = (i - 1) / CONFIG.Ruins.StoneCount * TAU + rng:NextNumber(-0.1, 0.1)
		local sx, sz = rx + math.cos(a) * R, rz + math.sin(a) * R
		local h = CONFIG.Ruins.StoneHeight * rng:NextNumber(0.65, 1)
		local sy = surfaceHeight(sx, sz)
		local facing = math.atan2(sz - rz, sx - rx)
		newPart("Pedra_" .. i, Vector3.new(2.2, h, 3.2), CFrame.new(sx, sy + h / 2 - 0.7, sz) * CFrame.Angles(0, facing, 0) * CFrame.Angles(rng:NextNumber(-0.06, 0.06), 0, rng:NextNumber(-0.06, 0.06)), Enum.Material.Slate, rockColor(rng), ruinas)
	end
	for i = 1, 4 do
		local a = rng:NextNumber(0, TAU)
		local d = rng:NextNumber(R * 0.3, R * 0.9)
		local sx, sz = rx + math.cos(a) * d, rz + math.sin(a) * d
		newPart("PedraCaida_" .. i, Vector3.new(4, 1.6, 2.4), CFrame.new(sx, surfaceHeight(sx, sz) + 0.6, sz) * CFrame.Angles(0, rng:NextNumber(0, TAU), rng:NextNumber(-0.15, 0.15)), Enum.Material.Slate, rockColor(rng), ruinas)
	end

	newPart("Pedestal", Vector3.new(4, 4, 4), CFrame.new(rx, groundY + 2, rz), Enum.Material.Slate, Color3.fromRGB(95, 92, 85), ruinas)

	local tool = ToolFactory.Create("LancaAncestral")
	if tool then
		local handle = tool:FindFirstChild("Handle")
		if handle and handle:IsA("BasePart") then
			handle.CFrame = CFrame.new(rx, groundY + 4.3, rz) * CFrame.Angles(math.pi / 2, 0, 0)
			handle.Anchored = true
		end
		tool.Parent = ruinas
	else
		warn("[IslandGenerator] ToolFactory não criou a Lança Ancestral.")
	end

	S.Marker(ruinas, "SpawnPOI", CFrame.new(rx + R + 6, groundY + 2, rz), { SpawnPOI = true })
	return 1
end

--------------------------------------------------------------------------------
-- Reassentar (consertar mapa já gerado sem regerar)
--------------------------------------------------------------------------------

--[[
	RegroundNature(sink?)
	Passa por Workspace/Ilha/{Floresta, Vegetacao, Rochas} e baixa/sobe cada
	Model pra base dele encostar no chão real (raycast contra Terrain),
	cravando `sink` studs. Conserta as árvores flutuantes que sobraram de
	quando cada "árvore" era um pacote inteiro. Devolve quantos moveu.
]]
function IslandGenerator.RegroundNature(sink: number?): number
	local ilha = Workspace:FindFirstChild("Ilha")
	if not ilha then
		warn("[IslandGenerator] Sem Workspace.Ilha.")
		return 0
	end

	local s = sink or 2.0
	local moved = 0
	local seen = 0

	for _, folderName in { "Floresta", "Vegetacao", "Rochas" } do
		local folder = ilha:FindFirstChild(folderName)
		if not folder then
			continue
		end
		for _, obj in folder:GetChildren() do
			if obj:IsA("Model") then
				seen += 1
				local pivot = obj:GetPivot().Position
				local groundY = surfaceHeight(pivot.X, pivot.Z)
				local bottom = modelBottomY(obj)
				if bottom then
					local delta = (groundY - bottom) - s
					if math.abs(delta) > 0.1 then
						obj:PivotTo(obj:GetPivot() + Vector3.new(0, delta, 0))
						moved += 1
					end
				end
				if seen % 150 == 0 then
					task.wait()
				end
			end
		end
	end

	print(string.format("[IslandGenerator] Reassentado: %d de %d modelo(s) movidos pro chão.", moved, seen))
	return moved
end

--------------------------------------------------------------------------------
-- Orquestração
--------------------------------------------------------------------------------

function IslandGenerator.SetSeed(seed: number)
	Layout.SetSeed(seed)
end

function IslandGenerator.ClearAll()
	local ilha = Workspace:FindFirstChild("Ilha")
	if ilha then
		ilha:Destroy()
	end
	removeLegacyWaterPlanes()

	local waterSize = LC.WaterHalf * 2
	local oceanTop, oceanBottom = LC.SeaLevel + 8, LC.MinY - LC.OceanDepth
	Terrain:FillBlock(CFrame.new(0, (oceanTop + oceanBottom) / 2, 0), Vector3.new(waterSize, oceanTop - oceanBottom, waterSize), Enum.Material.Air)

	local half = LC.AreaHalf
	local height = LC.MaxY - LC.MinY
	Terrain:FillBlock(CFrame.new(0, LC.MinY + height / 2, 0), Vector3.new(half * 2, height, half * 2), Enum.Material.Air)
end

--[[
	Generate(seed?)
	Layout -> Terreno -> Rochas -> Caverna -> Floresta -> Vegetação -> Ruínas
	-> POIs, e imprime o resumo.
]]
function IslandGenerator.Generate(seed: number?)
	if seed then
		IslandGenerator.SetSeed(seed)
	end
	Layout.Plan()

	local t0 = os.clock()
	print(string.format("[IslandGenerator] Gerando ilha (seed %d, área %dx%d)...", Layout.Seed(), LC.AreaHalf * 2, LC.AreaHalf * 2))

	IslandGenerator.GenerateTerrain()
	print(string.format("[IslandGenerator] terreno pronto (%.0fs)", os.clock() - t0))
	task.wait()

	local rocks = IslandGenerator.GenerateRockFormations()
	local caves = IslandGenerator.GenerateCave()
	local trees = IslandGenerator.GenerateForest()
	print(string.format("[IslandGenerator] floresta pronta: %d árvores (%.0fs)", trees, os.clock() - t0))
	local bushes, logs = IslandGenerator.GenerateUndergrowth()
	local ruins = IslandGenerator.GenerateRuins()
	local pois = PoiGenerator.Generate()

	local failed = {}
	for id in failedTemplates do
		table.insert(failed, tostring(id))
	end

	print(string.format(
		"[IslandGenerator] Concluído em %.1fs -- árvores: %d | arbustos: %d | troncos: %d | rochas: %d | cavernas: %d | ruínas: %d | POIs: %d",
		os.clock() - t0, trees, bushes, logs, rocks, caves, ruins, pois
	))
	if #failed > 0 then
		warn("[IslandGenerator] Assets que não carregaram (usado placeholder): " .. table.concat(failed, ", "))
	end
	print("[IslandGenerator] Agora: PlaneCrashGenerator.Generate() e ItemSpawner.Generate(), depois SALVE (Ctrl+S).")
end

return IslandGenerator
