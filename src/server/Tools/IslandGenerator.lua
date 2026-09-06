--!strict
--[[
	IslandGenerator (ferramenta de editor)
	Gera o terreno e os elementos naturais da ilha de "Náufragos".

	AUTO-BOOT: init.server.luau chama Generate() sozinho ao dar Play, SE
	Workspace.Ilha ainda não existir (ver comentário lá). Isto aqui continua
	dando pra chamar manualmente também, é só mais rápido de iterar em modo
	de edição (sem esperar o Play nem o download dos assets de novo).

	USO (Command Bar do Studio, em modo de edição):
		local Gen = require(game.ServerScriptService.Server.Tools.IslandGenerator)
		Gen.Generate()            -- tudo, na ordem certa, com resumo no Output
		Gen.Generate(42)          -- mesma coisa com outra seed

	Etapas isoladas (pra ajustar sem regerar tudo):
		Gen.GenerateTerrain()           -- mar, praia, interior, montanha, limites
		Gen.GenerateRockFormations(18)  -- grupos de rochas (modelos do Roblox)
		Gen.GenerateCave()              -- a caverna do Monstro, na base da montanha
		Gen.GenerateForest(1.0)         -- densidade 0..2; também cria as Clareiras
		Gen.GenerateNativeVillage()     -- precisa de Clareiras já geradas
		Gen.GenerateRuins()             -- Ruínas Antigas + Lança Ancestral (1 por mapa)
		Gen.ClearAll()                  -- apaga Workspace.Ilha e o terreno da área
		Gen.SetSeed(123)                -- muda a seed pras próximas chamadas

	Tudo que é gerado vai pra Workspace/Ilha/{Limites, Rochas, Caverna,
	Floresta, Clareiras, VilaNativa, Ruinas}. Cada etapa limpa só a própria
	pasta. Todos os números de ajuste ficam em CONFIG, logo abaixo.

	MAR "INFINITO": a área de terreno de verdade é AreaHalf*2 (648 x 648).
	Fora dela, um BLOCO fundo de água (do fundo do mundo até SeaLevel) até
	WaterHalf*2, e a Atmosphere (default.project.json) esconde o fim dele na
	névoa. Paredes invisíveis em AreaHalf seguram o jogador -- ele vê água até
	o horizonte, mas não nada até lá.

	ÁGUA EM XADREZ (corrigido): vinha com Transparency 0.45 + Reflectance 0.5
	-> dava pra ver a Baseplate quadriculada / o void por baixo, e o reflexo
	do céu "quebrava" a superfície num padrão. Agora: apaga a Part "Baseplate"
	da template, água mais opaca (0.3) e quase sem reflexo (0.12), e o oceano
	é BLOCO fundo, não lençol raso sobre o nada. Se AINDA ficar xadrez: File >
	Studio Settings > Rendering > Quality Level -- em qualidade baixa a água
	do Terrain sempre renderiza quadriculada (limitação do engine).

	PRAIA x ÁGUA: a superfície do mar fica em SeaLevel (0). A areia na beira
	d'água fica CONFIG.ShoreHeight studs acima disso, e o fundo do mar afunda
	CONFIG.ShoreDrop studs por stud saindo da praia -- então em poucos passos
	já passa de 3-4 de profundidade e o Humanoid entra em Swimming (o
	Crouching do pacote corta a velocidade pra CONFIG.WaterSpeed lá). Sem esse
	degrau, a areia e a água ficavam na mesma altura (Y=0) -> textura piscando
	e jogador "andando em cima da água".

	MONTANHA + CAVERNA: a montanha faz parte da função de altura (é terreno,
	material Rock), num ponto fixo por seed. A caverna é ESCAVADA no terreno
	(Air) na base da montanha, virada pro centro da ilha: túnel + câmara
	esférica com piso plano de Rock. Lá dentro fica o marcador "MonstroSpawn"
	(Attribute MonstroSpawn = true) que o LobbyManager usa pra spawnar o
	Monstro.

	MODELOS (CONFIG.Assets): árvores e rochas vêm de InsertService:LoadAsset
	com os IDs configurados, sorteados por igual. Cada modelo é carregado
	UMA vez e clonado; scripts dentro dos modelos são removidos (free models
	costumam trazer script junto). Se um ID falhar, entra um placeholder
	simples no lugar e o resumo avisa.
]]

local Workspace = game:GetService("Workspace")
local InsertService = game:GetService("InsertService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Terrain = Workspace.Terrain

local ToolFactory = require(ReplicatedStorage.Modules.ToolFactory)

local IslandGenerator = {}

--------------------------------------------------------------------------------
-- Ajustes
--------------------------------------------------------------------------------

local CONFIG = {
	Seed = 1337,

	AreaHalf = 324, -- terreno real: 648 x 648 (múltiplo de Chunk)
	Chunk = 72, -- WriteVoxels em blocos de 72 x 80 x 72 (72/4 = 18 voxels)
	VoxelRes = 4,

	WaterHalf = 1000, -- lençol visual de água: 2000 x 2000
	OceanDepth = 16, -- espessura do lençol fora da área real (fundo bem abaixo do mar)

	CoastRadius = 210, -- raio médio da costa -> diâmetro ~420
	CoastRadiusMin = 150,
	CoastRadiusMax = 250,
	BeachWidth = 35,
	SeaLevel = 0,

	-- Praia/mar: a areia na beira d'água fica ShoreHeight studs ACIMA do mar
	-- (senão a superfície da areia coincide com a da água -> textura bugando +
	-- jogador "andando em cima da água"). Saindo da praia, o fundo do mar
	-- AFUNDA ShoreDrop studs por stud, então em ~4 passos já dá pra nadar.
	ShoreHeight = 2.5,
	ShoreDrop = 1.5,

	MinY = -24,
	MaxY = 96, -- precisa caber a montanha

	Mountain = {
		Inland = 120, -- distância da costa até o centro da montanha
		Radius = 60,
		Peak = 48, -- altura extra no pico
	},

	Cave = {
		TunnelWidth = 9,
		TunnelHeight = 9,
		ChamberRadius = 13, -- diâmetro ~26
		EntranceRocks = 5,
	},

	Rocks = {
		Count = 18, -- grupos
		PerGroupMin = 1,
		PerGroupMax = 4,
		SizeMin = 3,
		SizeMax = 15,
	},

	Forest = {
		MaxTrees = 380, -- em densidade 1.0
		MinSpacing = 7,
		HeightMin = 8,
		HeightMax = 16,
		ClearingCount = 6,
		ClearingRadiusMin = 15,
		ClearingRadiusMax = 25,
	},

	Village = {
		HutsMin = 5,
		HutsMax = 8,
	},

	Ruins = {
		Inland = 90, -- distância da costa (bem diferente da montanha/vila, pra não empilhar)
		Radius = 14, -- raio do círculo de pedras
		StoneCount = 7,
		StoneHeight = 6,
	},

	Assets = {
		Trees = { 4728038922, 12196680826, 5521112313 },
		Rocks = { 4513606597, 282758654, 5496069794 },
	},

	Water = {
		Color = Color3.fromRGB(28, 105, 150),
		-- [Meujogo] antes: Transparency 0.45 / Reflectance 0.5. Transparência
		-- alta deixava ver o que tinha embaixo (Baseplate quadriculada, void)
		-- e Reflectance 0.5 fazia a superfície "quebrar" em xadrez com o céu.
		Transparency = 0.3,
		Reflectance = 0.12,
		WaveSize = 0.15,
		WaveSpeed = 10,
	},
}

local TAU = math.pi * 2

local currentSeed = CONFIG.Seed

--------------------------------------------------------------------------------
-- Forma da ilha (função analítica)
--------------------------------------------------------------------------------

local function smoothstep(t: number): number
	t = math.clamp(t, 0, 1)
	return t * t * (3 - 2 * t)
end

local function noise2(x: number, z: number, layer: number): number
	return math.noise(x, currentSeed * 0.013 + layer * 17.31, z)
end

local function coastRadiusAt(angle: number): number
	local c, s = math.cos(angle), math.sin(angle)
	local n1 = noise2(c * 1.3 + 7.1, s * 1.3 + 3.7, 1)
	local n2 = noise2(c * 3.1 + 2.2, s * 3.1 + 9.4, 2)
	return math.clamp(CONFIG.CoastRadius + n1 * 90 + n2 * 28, CONFIG.CoastRadiusMin, CONFIG.CoastRadiusMax)
end

local function islandInfo(x: number, z: number): (number, number, number)
	local d = math.sqrt(x * x + z * z)
	local coast = coastRadiusAt(math.atan2(z, x))
	return d, coast, coast - d
end

-- Centro da montanha: fixo por seed, a CONFIG.Mountain.Inland da costa.
local function mountainSite(): (number, number)
	local rng = Random.new(currentSeed + 7)
	local angle = rng:NextNumber(0, TAU)
	local dist = coastRadiusAt(angle) - CONFIG.Mountain.Inland
	return math.cos(angle) * dist, math.sin(angle) * dist
end

-- Quanto a montanha levanta o terreno em (x, z). 0 fora do raio dela.
local function mountainContribution(x: number, z: number): number
	local mx, mz = mountainSite()
	local R = CONFIG.Mountain.Radius
	local d = math.sqrt((x - mx) ^ 2 + (z - mz) ^ 2)
	if d >= R then
		return 0
	end
	local f = smoothstep(1 - d / R)
	return CONFIG.Mountain.Peak * f ^ 1.4 + noise2(x / 15, z / 15, 7) * 7 * f
end

local function analyticHeight(x: number, z: number): number
	local _, coast, inland = islandInfo(x, z)
	local shore = CONFIG.ShoreHeight

	-- Mar: da linha d'água (inland 0, altura = shore) o fundo AFUNDA rápido.
	-- Em ~(shore/ShoreDrop + 3) studs saindo da praia já passa de 3-4 de
	-- profundidade -> o Humanoid entra em Swimming em vez de andar por cima.
	if inland < 0 then
		return math.max(CONFIG.MinY + 2, shore + inland * CONFIG.ShoreDrop)
	end

	-- Praia: a areia começa em `shore` (acima do mar) e sobe até shore+4.
	local beach = CONFIG.BeachWidth
	if inland < beach then
		return shore + smoothstep(inland / beach) * 4
	end

	local t = smoothstep(math.min((inland - beach) / 25, 1))
	local h01 = math.clamp(noise2(x / 70, z / 70, 3) + 0.5, 0, 1)
	local hills = h01 * 22 + noise2(x / 22, z / 22, 4) * 4
	local dome = (inland / coast) * 12
	return shore + 4 + t * math.max(dome + hills, 0) + mountainContribution(x, z)
end

local function materialAt(x: number, z: number): Enum.Material
	local _, _, inland = islandInfo(x, z)
	if inland < CONFIG.BeachWidth then
		return Enum.Material.Sand
	end
	if inland < CONFIG.BeachWidth + 8 and noise2(x / 9, z / 9, 5) > 0 then
		return Enum.Material.Sand
	end

	local mountain = mountainContribution(x, z)
	if mountain > 9 then
		return Enum.Material.Rock
	elseif mountain > 4 then
		return Enum.Material.Ground
	end

	if noise2(x / 40, z / 40, 6) > 0.12 then
		return Enum.Material.LeafyGrass
	end
	return Enum.Material.Grass
end

--------------------------------------------------------------------------------
-- Altura real do terreno (raycast, com fallback analítico)
--------------------------------------------------------------------------------

local raycastParams = RaycastParams.new()
raycastParams.FilterType = Enum.RaycastFilterType.Include
raycastParams.FilterDescendantsInstances = { Terrain }
raycastParams.IgnoreWater = true

local function surfaceHeight(x: number, z: number): number
	local origin = Vector3.new(x, CONFIG.MaxY + 50, z)
	local direction = Vector3.new(0, -(CONFIG.MaxY - CONFIG.MinY + 100), 0)
	local result = Workspace:Raycast(origin, direction, raycastParams)
	if result then
		return result.Position.Y
	end
	return analyticHeight(x, z)
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

local function getSubFolder(name: string): Folder
	local ilha = getIlhaFolder()
	local sub = ilha:FindFirstChild(name)
	if not sub then
		sub = Instance.new("Folder")
		sub.Name = name
		sub.Parent = ilha
	end
	return sub :: Folder
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

local function newPart(
	name: string,
	size: Vector3,
	cframe: CFrame,
	material: Enum.Material,
	color: Color3,
	parent: Instance
): Part
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

-- Cilindro do Roblox tem o eixo em X; isto deixa ele em pé.
local VERTICAL = CFrame.Angles(0, 0, math.pi / 2)

local function rockColor(rng: Random): Color3
	local v = rng:NextInteger(90, 135)
	return Color3.fromRGB(v, v, v + rng:NextInteger(0, 8))
end

--------------------------------------------------------------------------------
-- Modelos do Roblox (InsertService), com cache e placeholder de reserva
--------------------------------------------------------------------------------

local templates: { [number]: Model } = {}
local failedTemplates: { [number]: boolean } = {}

local function loadTemplate(assetId: number): Model?
	if templates[assetId] then
		return templates[assetId]
	end
	if failedTemplates[assetId] then
		return nil
	end

	local ok, container = pcall(function()
		return InsertService:LoadAsset(assetId)
	end)
	if not ok or typeof(container) ~= "Instance" then
		-- Segunda tentativa pelo caminho clássico do Command Bar.
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

	-- Normaliza pra um único Model.
	local holder = container :: Instance
	local children = holder:GetChildren()
	local model: Model
	if #children == 1 and children[1]:IsA("Model") then
		model = children[1]
	else
		model = Instance.new("Model")
		model.Name = "Asset_" .. assetId
		for _, child in children do
			child.Parent = model
		end
	end
	model.Parent = nil
	holder:Destroy()

	-- Free models costumam vir com scripts. Fora.
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("LuaSourceContainer") then
			descendant:Destroy()
		end
	end
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant.Anchored = true
		end
	end
	if not model.PrimaryPart then
		local firstPart = model:FindFirstChildWhichIsA("BasePart", true)
		if firstPart then
			model.PrimaryPart = firstPart
		end
	end

	templates[assetId] = model
	return model
end

--[[
	LoadAssetModel(assetId)
	Carrega (com cache) um asset do Roblox já normalizado: um único Model,
	sem scripts, tudo Anchored. Exposto porque PlaneCrashGenerator.lua
	precisa exatamente do mesmo tratamento -- duplicar isso significaria
	dois lugares pra corrigir quando um free model vier torto.
	Devolve nil se o asset não carregar.
]]
IslandGenerator.LoadAssetModel = loadTemplate

-- Clona o template, escala pra `targetHeight`, gira e assenta no chão.
local function placeModel(
	template: Model,
	parent: Instance,
	x: number,
	z: number,
	groundY: number,
	targetHeight: number,
	yaw: number,
	sink: number,
	name: string
): Model
	local clone = template:Clone()
	clone.Name = name

	local _, size = clone:GetBoundingBox()
	if size.Y > 0.01 then
		clone:ScaleTo(clone:GetScale() * (targetHeight / size.Y))
	end

	clone:PivotTo(CFrame.new(x, groundY, z) * CFrame.Angles(0, yaw, 0))
	local boxCF, boxSize = clone:GetBoundingBox()
	local bottom = boxCF.Position.Y - boxSize.Y / 2
	clone:PivotTo(clone:GetPivot() + Vector3.new(0, (groundY - bottom) - sink, 0))

	clone.Parent = parent
	return clone
end

local function pickAsset(rng: Random, ids: { number }): Model?
	-- Tenta os IDs em ordem aleatória até um carregar.
	local order = table.clone(ids)
	for i = #order, 2, -1 do
		local j = rng:NextInteger(1, i)
		order[i], order[j] = order[j], order[i]
	end
	for _, id in order do
		local template = loadTemplate(id)
		if template then
			return template
		end
	end
	return nil
end

-- Placeholders, só se nenhum asset carregar.
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
	local trunkD = rng:NextNumber(1.0, 1.8)
	local canopyD = height * 0.6
	local trunk = newPart("Tronco", Vector3.new(trunkH, trunkD, trunkD), CFrame.new(x, groundY + trunkH / 2 - 0.5, z) * VERTICAL, Enum.Material.Wood, Color3.fromRGB(101, 67, 33), model)
	trunk.Shape = Enum.PartType.Cylinder
	local canopy = newPart("Copa", Vector3.new(canopyD, canopyD, canopyD), CFrame.new(x, groundY + trunkH + canopyD * 0.35, z), Enum.Material.LeafyGrass, Color3.fromRGB(50, 130, 45), model)
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
end

-- Paredes invisíveis no limite da área real (Ilha/Limites).
local function buildBoundary()
	local limites = resetFolder("Limites")
	local half = CONFIG.AreaHalf - 8
	local height = 140
	local centerY = CONFIG.MinY - 20 + height / 2
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
	1) aparência da água, 2) lençol de água até WaterHalf, 3) terreno real
	(mar, praia, interior, montanha) via WriteVoxels em chunks -- que
	sobrescreve o lençol dentro da área real --, 4) paredes invisíveis.
]]
function IslandGenerator.GenerateTerrain()
	applyWaterLook()

	-- Baseplate da template (Part chamada "Baseplate" em Y≈0, com textura
	-- quadriculada) fica bem na superfície da água -> xadrez visto através
	-- dela. Se existir, some com ela: o mar é o "chão" do jogo agora.
	for _, name in { "Baseplate", "BasePlate" } do
		local bp = Workspace:FindFirstChild(name)
		if bp and bp:IsA("BasePart") then
			bp:Destroy()
		end
	end

	-- Oceano de verdade: um bloco FUNDO (não um lençol fino) do fundo do mundo
	-- até a superfície. Um lençol raso sobre o void renderiza cheio de
	-- artefato; um bloco fundo não. A área real é reescrita logo abaixo.
	local waterSize = CONFIG.WaterHalf * 2
	local oceanTop = CONFIG.SeaLevel
	local oceanBottom = CONFIG.MinY - 8
	Terrain:FillBlock(
		CFrame.new(0, (oceanTop + oceanBottom) / 2, 0),
		Vector3.new(waterSize, oceanTop - oceanBottom, waterSize),
		Enum.Material.Water
	)

	local res, chunk = CONFIG.VoxelRes, CONFIG.Chunk
	local half = CONFIG.AreaHalf
	local minY, maxY = CONFIG.MinY, CONFIG.MaxY
	local ny = (maxY - minY) // res
	local n = chunk // res
	local water, air = Enum.Material.Water, Enum.Material.Air
	local seaLevel = CONFIG.SeaLevel

	local chunksDone = 0

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
					local h = analyticHeight(x, z)
					local mat = materialAt(x, z)

					for j = 1, ny do
						local yb = minY + (j - 1) * res
						local occ = math.clamp((h - yb) / res, 0, 1)

						if occ > 0.02 then
							materials[i][j][k] = mat
							occupancies[i][j][k] = occ
						elseif yb < seaLevel then
							materials[i][j][k] = water
							occupancies[i][j][k] = math.clamp((seaLevel - yb) / res, 0, 1)
						end
					end
				end
			end

			local region = Region3.new(Vector3.new(cx, minY, cz), Vector3.new(cx + chunk, maxY, cz + chunk))
			Terrain:WriteVoxels(region, res, materials, occupancies)

			chunksDone += 1
			if chunksDone % 6 == 0 then
				task.wait()
			end
		end
	end

	buildBoundary()
end

--------------------------------------------------------------------------------
-- 2. ROCHAS
--------------------------------------------------------------------------------

-- Ponto da boca da caverna (pra rochas/árvores não taparem a entrada).
local function caveEntrance(): (number, number)
	local mx, mz = mountainSite()
	local len = math.sqrt(mx * mx + mz * mz)
	local dx, dz = 1, 0
	if len > 0.01 then
		dx, dz = -mx / len, -mz / len
	end
	local e = CONFIG.Mountain.Radius * 0.75
	return mx + dx * e, mz + dz * e
end

--[[
	GenerateRockFormations(count)
	`count` grupos (padrão CONFIG.Rocks.Count) de 1-4 rochas dos modelos em
	CONFIG.Assets.Rocks, tamanhos SizeMin-SizeMax, espalhados da praia pra
	dentro (evitando a boca da caverna). Limpa Rochas. Devolve grupos criados.
]]
function IslandGenerator.GenerateRockFormations(count: number?): number
	local total = count or CONFIG.Rocks.Count
	local rochas = resetFolder("Rochas")
	local rng = Random.new(currentSeed + 2)
	local limit = CONFIG.CoastRadiusMax
	local ex, ez = caveEntrance()

	local placed: { { x: number, z: number, r: number } } = {}
	local built = 0

	for i = 1, total do
		local site: Vector3? = nil
		local spread = rng:NextNumber(4, 9)

		for _ = 1, 40 do
			local x, z = rng:NextNumber(-limit, limit), rng:NextNumber(-limit, limit)
			local _, _, inland = islandInfo(x, z)
			if inland >= 12 and (x - ex) ^ 2 + (z - ez) ^ 2 > 25 ^ 2 then
				local ok = true
				for _, p in placed do
					if (x - p.x) ^ 2 + (z - p.z) ^ 2 < (p.r + spread + 12) ^ 2 then
						ok = false
						break
					end
				end
				if ok then
					site = Vector3.new(x, 0, z)
					break
				end
			end
		end

		if site then
			local model = Instance.new("Model")
			model.Name = "Rochas_" .. i

			local rocksInGroup = rng:NextInteger(CONFIG.Rocks.PerGroupMin, CONFIG.Rocks.PerGroupMax)
			for r = 1, rocksInGroup do
				local gx = site.X + rng:NextNumber(-spread, spread)
				local gz = site.Z + rng:NextNumber(-spread, spread)
				local groundY = surfaceHeight(gx, gz)
				local size = rng:NextNumber(CONFIG.Rocks.SizeMin, CONFIG.Rocks.SizeMax)
				local template = pickAsset(rng, CONFIG.Assets.Rocks)
				if template then
					placeModel(template, model, gx, gz, groundY, size, rng:NextNumber(0, TAU), size * 0.25, "Pedra_" .. r)
				else
					placeholderRock(model, Vector3.new(gx, groundY, gz), size, rng, "Pedra_" .. r)
				end
			end

			model:SetAttribute("CentroX", site.X)
			model:SetAttribute("CentroZ", site.Z)
			model:SetAttribute("Raio", spread + CONFIG.Rocks.SizeMax * 0.5)
			model.Parent = rochas

			table.insert(placed, { x = site.X, z = site.Z, r = spread })
			built += 1
		end
	end

	return built
end

--------------------------------------------------------------------------------
-- 3. CAVERNA (uma só, na base da montanha)
--------------------------------------------------------------------------------

--[[
	GenerateCave()
	Escava no terreno da montanha: boca arredondada, túnel reto e câmara
	esférica com piso plano de Rock. Luz fraca dentro, rochas na entrada e o
	marcador "MonstroSpawn" no fundo. Limpa Caverna. Devolve 1 (ou 0).
]]
function IslandGenerator.GenerateCave(): number
	local caverna = resetFolder("Caverna")
	local rng = Random.new(currentSeed + 3)

	local mx, mz = mountainSite()
	local R = CONFIG.Mountain.Radius
	local len = math.sqrt(mx * mx + mz * mz)
	local dir = if len > 0.01 then Vector3.new(-mx / len, 0, -mz / len) else Vector3.new(1, 0, 0)
	local side = Vector3.new(-dir.Z, 0, dir.X)

	local mountainCenter = Vector3.new(mx, 0, mz)
	local entrance = mountainCenter + dir * (R * 0.75)
	local chamber = mountainCenter + dir * (R * 0.3)

	local floorY = surfaceHeight(entrance.X, entrance.Z) - 1
	local W, H = CONFIG.Cave.TunnelWidth, CONFIG.Cave.TunnelHeight
	local CR = CONFIG.Cave.ChamberRadius

	-- Túnel: da frente da boca (um pouco pra fora) até o centro da câmara.
	local tunnelStart = entrance + dir * 8
	local tunnelVec = chamber - tunnelStart
	local tunnelLen = tunnelVec.Magnitude
	local tunnelCenter = (tunnelStart + chamber) / 2
	local tunnelCF = CFrame.lookAt(
		Vector3.new(tunnelCenter.X, floorY + H / 2, tunnelCenter.Z),
		Vector3.new(chamber.X, floorY + H / 2, chamber.Z)
	)

	-- Piso de Rock por baixo (túnel + câmara) ANTES de escavar, pra o chão
	-- ficar plano e sólido mesmo onde o terreno era irregular.
	Terrain:FillBlock(tunnelCF * CFrame.new(0, -H / 2 - 3, 0), Vector3.new(W + 4, 6, tunnelLen + 4), Enum.Material.Rock)
	Terrain:FillCylinder(CFrame.new(chamber.X, floorY - 3, chamber.Z), 6, CR + 2, Enum.Material.Rock)

	-- Escavação.
	Terrain:FillBlock(tunnelCF, Vector3.new(W, H, tunnelLen), Enum.Material.Air)
	Terrain:FillBall(Vector3.new(entrance.X, floorY + 4, entrance.Z), 6, Enum.Material.Air) -- boca arredondada
	Terrain:FillBall(Vector3.new(chamber.X, floorY + CR * 0.55, chamber.Z), CR, Enum.Material.Air)
	-- Achata o chão da câmara (a esfera deixaria uma bacia).
	Terrain:FillCylinder(CFrame.new(chamber.X, floorY - 3, chamber.Z), 6, CR + 1, Enum.Material.Rock)
	Terrain:FillBlock(tunnelCF * CFrame.new(0, -H / 2 - 3, 0), Vector3.new(W + 2, 6, tunnelLen + 2), Enum.Material.Rock)

	-- Marcador de spawn do Monstro, no fundo da câmara.
	local spawnPos = chamber + dir * (CR * 0.35)
	local marker = newPart("MonstroSpawn", Vector3.new(2, 1, 2), CFrame.new(spawnPos.X, floorY + 0.5, spawnPos.Z), Enum.Material.SmoothPlastic, Color3.fromRGB(200, 40, 40), caverna)
	marker.Transparency = 1
	marker.CanCollide = false
	marker:SetAttribute("MonstroSpawn", true)

	-- Luz fraca, esverdeada/azulada.
	local lightSpots = {
		Vector3.new(chamber.X, floorY + CR * 0.6, chamber.Z),
		Vector3.new(chamber.X + side.X * CR * 0.5, floorY + CR * 0.35, chamber.Z + side.Z * CR * 0.5),
		Vector3.new(tunnelCenter.X, floorY + H * 0.7, tunnelCenter.Z),
	}
	for i, pos in lightSpots do
		local anchor = newPart("Luz_" .. i, Vector3.new(1, 1, 1), CFrame.new(pos), Enum.Material.SmoothPlastic, Color3.new(0, 0, 0), caverna)
		anchor.Transparency = 1
		anchor.CanCollide = false
		local light = Instance.new("PointLight")
		light.Color = if i == 2 then Color3.fromRGB(120, 200, 160) else Color3.fromRGB(120, 180, 200)
		light.Brightness = 0.55
		light.Range = CR * 1.8
		light.Shadows = false
		light.Parent = anchor
	end

	-- Rochas flanqueando a boca.
	for i = 1, CONFIG.Cave.EntranceRocks do
		local s = if i % 2 == 0 then 1 else -1
		local p = entrance + dir * rng:NextNumber(-2, 8) + side * (s * rng:NextNumber(W / 2 + 4, W / 2 + 10))
		local groundY = surfaceHeight(p.X, p.Z)
		local size = rng:NextNumber(6, 12)
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
	for _, child in getSubFolder("Rochas"):GetChildren() do
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
	density 0..2 (padrão 1) escala CONFIG.Forest.MaxTrees. Sorteia as
	Clareiras (marcadores invisíveis em Ilha/Clareiras com Attribute Raio) e
	espalha árvores dos modelos em CONFIG.Assets.Trees no interior, evitando
	praia, montanha, boca da caverna, rochas, clareiras e umas às outras.
	Limpa Floresta e Clareiras. Devolve o número de árvores.
]]
function IslandGenerator.GenerateForest(density: number?): number
	local dens = math.clamp(density or 1, 0, 2)
	local floresta = resetFolder("Floresta")
	local clareiras = resetFolder("Clareiras")
	local rng = Random.new(currentSeed + 4)
	local rocks = collectRockCircles()
	local limit = CONFIG.CoastRadiusMax
	local ex, ez = caveEntrance()
	local mx, mz = mountainSite()
	local mountainR = CONFIG.Mountain.Radius

	-- Clareiras (fora da montanha).
	local clearings: { { x: number, z: number, r: number } } = {}
	local tries = 0
	while #clearings < CONFIG.Forest.ClearingCount and tries < 400 do
		tries += 1
		local x, z = rng:NextNumber(-limit, limit), rng:NextNumber(-limit, limit)
		local _, _, inland = islandInfo(x, z)
		local r = rng:NextNumber(CONFIG.Forest.ClearingRadiusMin, CONFIG.Forest.ClearingRadiusMax)

		if inland >= CONFIG.BeachWidth + r + 10 and (x - mx) ^ 2 + (z - mz) ^ 2 > (mountainR + r) ^ 2 then
			local ok = true
			for _, c in clearings do
				if (x - c.x) ^ 2 + (z - c.z) ^ 2 < (c.r + r + 40) ^ 2 then
					ok = false
					break
				end
			end
			if ok then
				for _, rk in rocks do
					if (x - rk.x) ^ 2 + (z - rk.z) ^ 2 < (rk.r + r + 5) ^ 2 then
						ok = false
						break
					end
				end
			end

			if ok then
				table.insert(clearings, { x = x, z = z, r = r })
				local marker = newPart("Clareira_" .. #clearings, Vector3.new(1, 1, 1), CFrame.new(x, surfaceHeight(x, z) + 0.5, z), Enum.Material.SmoothPlastic, Color3.new(1, 1, 1), clareiras)
				marker.Transparency = 1
				marker.CanCollide = false
				marker:SetAttribute("Raio", r)
				marker:SetAttribute("Uso", "")
			end
		end
	end

	-- Árvores.
	local minSpacing = CONFIG.Forest.MinSpacing
	local target = math.floor(CONFIG.Forest.MaxTrees * dens)
	local attempts = math.min(target * 12, 8000)

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

	local trees = 0
	for _ = 1, attempts do
		if trees >= target then
			break
		end

		local x, z = rng:NextNumber(-limit, limit), rng:NextNumber(-limit, limit)
		local _, _, inland = islandInfo(x, z)

		if inland >= CONFIG.BeachWidth + 3 and not tooClose(x, z) then
			local blocked = mountainContribution(x, z) > 5 or (x - ex) ^ 2 + (z - ez) ^ 2 < 18 ^ 2

			if not blocked then
				for _, c in clearings do
					if (x - c.x) ^ 2 + (z - c.z) ^ 2 < (c.r + 3) ^ 2 then
						blocked = true
						break
					end
				end
			end
			if not blocked then
				for _, rk in rocks do
					if (x - rk.x) ^ 2 + (z - rk.z) ^ 2 < (rk.r + 4) ^ 2 then
						blocked = true
						break
					end
				end
			end

			if not blocked then
				trees += 1
				local groundY = surfaceHeight(x, z)
				local height = rng:NextNumber(CONFIG.Forest.HeightMin, CONFIG.Forest.HeightMax)
				local template = pickAsset(rng, CONFIG.Assets.Trees)
				if template then
					placeModel(template, floresta, x, z, groundY, height, rng:NextNumber(0, TAU), 0.3, "Arvore_" .. trees)
				else
					placeholderTree(floresta, x, z, groundY, height, rng, "Arvore_" .. trees)
				end

				local key = cellKey(math.floor(x / minSpacing), math.floor(z / minSpacing))
				local bucket = grid[key]
				if not bucket then
					bucket = {}
					grid[key] = bucket
				end
				table.insert(bucket, Vector2.new(x, z))

				if trees % 40 == 0 then
					task.wait()
				end
			end
		end
	end

	return trees
end

--------------------------------------------------------------------------------
-- 5. VILA NATIVA (Kalanoa)
--------------------------------------------------------------------------------

local function buildHut(folder: Folder, x: number, z: number, doorAngle: number, rng: Random, index: number)
	local r = rng:NextNumber(3.5, 5)
	local wallH = rng:NextNumber(5, 7)
	local groundY = surfaceHeight(x, z)

	local model = Instance.new("Model")
	model.Name = "Cabana_" .. index

	local logD = 0.9
	local logCount = math.ceil((TAU * r) / (logD * 0.95))
	local doorHalf = 1.4 / r

	for i = 1, logCount do
		local a = (i - 1) / logCount * TAU
		local diff = math.atan2(math.sin(a - doorAngle), math.cos(a - doorAngle))
		if math.abs(diff) > doorHalf then
			local lx, lz = x + math.cos(a) * r, z + math.sin(a) * r
			local lh = wallH + rng:NextNumber(-0.4, 0.4)
			local shade = rng:NextInteger(-12, 12)
			local log = newPart("Tronco_" .. i, Vector3.new(lh, logD, logD), CFrame.new(lx, groundY + lh / 2 - 0.3, lz) * VERTICAL, Enum.Material.Wood, Color3.fromRGB(110 + shade, 75 + shade, 40 + shade), model)
			log.Shape = Enum.PartType.Cylinder
		end
	end

	-- Teto "cônico": pilha de cilindros de palha (não existe Part em cone).
	local tiers = 5
	local roofH = r * 0.9
	for t = 0, tiers - 1 do
		local frac = t / tiers
		local tierR = (r + 1.3) * (1 - frac) + 0.5
		local tierH = roofH / tiers + 0.3
		local y = groundY + wallH - 0.2 + frac * roofH + tierH / 2
		local tier = newPart("Telhado_" .. t, Vector3.new(tierH, tierR * 2, tierR * 2), CFrame.new(x, y, z) * VERTICAL, Enum.Material.Grass, Color3.fromRGB(196, 164, 91), model)
		tier.Shape = Enum.PartType.Cylinder
	end

	model.Parent = folder
end

local function buildTotem(folder: Folder, x: number, z: number, rng: Random)
	local model = Instance.new("Model")
	model.Name = "Totem"
	local groundY = surfaceHeight(x, z)

	local segments = {
		{ r = 1.5, h = 2.5, c = Color3.fromRGB(80, 50, 30) },
		{ r = 1.25, h = 2.5, c = Color3.fromRGB(150, 60, 40) },
		{ r = 1.05, h = 2.2, c = Color3.fromRGB(190, 140, 60) },
		{ r = 0.85, h = 2.0, c = Color3.fromRGB(60, 40, 30) },
	}

	local y = groundY
	for i, seg in segments do
		local part = newPart("Segmento_" .. i, Vector3.new(seg.h, seg.r * 2, seg.r * 2), CFrame.new(x, y + seg.h / 2, z) * CFrame.Angles(0, rng:NextNumber(0, TAU), 0) * VERTICAL, Enum.Material.Wood, seg.c, model)
		part.Shape = Enum.PartType.Cylinder
		y += seg.h
	end

	local head = newPart("Topo", Vector3.new(1.8, 1.8, 1.8), CFrame.new(x, y + 0.8, z), Enum.Material.Wood, Color3.fromRGB(120, 40, 40), model)
	head.Shape = Enum.PartType.Ball
	model.Parent = folder
end

-- Fogueira APAGADA: cinzas, lenha carbonizada, fumaça fraca e brasa quase
-- morta. Fogo aceso diria "tem alguém aqui"; fumaça diz "saíram há pouco".
local function buildFirePit(folder: Folder, x: number, z: number, rng: Random)
	local model = Instance.new("Model")
	model.Name = "Fogueira"
	local groundY = surfaceHeight(x, z)

	local ash = newPart("Cinzas", Vector3.new(0.4, 4.4, 4.4), CFrame.new(x, groundY + 0.2, z) * VERTICAL, Enum.Material.Slate, Color3.fromRGB(35, 33, 32), model)
	ash.Shape = Enum.PartType.Cylinder

	for i = 1, 9 do
		local a = (i - 1) / 9 * TAU + rng:NextNumber(-0.15, 0.15)
		local s = rng:NextNumber(0.9, 1.4)
		local stone = newPart("Pedra_" .. i, Vector3.new(s, s, s), CFrame.new(x + math.cos(a) * 2.6, groundY + s * 0.35, z + math.sin(a) * 2.6), Enum.Material.Slate, rockColor(rng), model)
		stone.Shape = Enum.PartType.Ball
	end

	for i = 1, 3 do
		local log = newPart("Lenha_" .. i, Vector3.new(2.6, 0.5, 0.5), CFrame.new(x, groundY + 0.55, z) * CFrame.Angles(0, (i - 1) / 3 * math.pi + rng:NextNumber(-0.2, 0.2), 0), Enum.Material.Wood, Color3.fromRGB(40, 30, 25), model)
		log.Shape = Enum.PartType.Cylinder
	end

	local smoke = Instance.new("Smoke")
	smoke.Color = Color3.fromRGB(120, 120, 120)
	smoke.Size = 1.5
	smoke.Opacity = 0.12
	smoke.RiseVelocity = 1.5
	smoke.Parent = ash

	local ember = Instance.new("PointLight")
	ember.Color = Color3.fromRGB(255, 120, 40)
	ember.Brightness = 0.25
	ember.Range = 7
	ember.Shadows = false
	ember.Parent = ash

	model.Parent = folder
end

--[[
	GenerateNativeVillage()
	Usa a clareira mais perto da costa (borda da floresta): 5-8 cabanas em
	anel, totem no centro, fogueira apagada e uns potes. Marca a clareira
	com Uso = "Vila". Limpa só VilaNativa. Devolve o número de cabanas.
]]
function IslandGenerator.GenerateNativeVillage(): number
	local vila = resetFolder("VilaNativa")
	local clareiras = getSubFolder("Clareiras")

	local chosen: BasePart? = nil
	local chosenInland = math.huge
	for _, marker in clareiras:GetChildren() do
		if marker:IsA("BasePart") then
			local _, _, inland = islandInfo(marker.Position.X, marker.Position.Z)
			if inland < chosenInland then
				chosenInland = inland
				chosen = marker
			end
		end
	end

	if not chosen then
		warn("[IslandGenerator] Nenhuma clareira encontrada -- rode GenerateForest() antes.")
		return 0
	end

	chosen:SetAttribute("Uso", "Vila")
	local cx, cz = chosen.Position.X, chosen.Position.Z
	local clearingR = chosen:GetAttribute("Raio") :: number

	local rng = Random.new(currentSeed + 5)
	local huts = rng:NextInteger(CONFIG.Village.HutsMin, CONFIG.Village.HutsMax)
	local ring = math.max(clearingR * 0.55, 9)
	local startAngle = rng:NextNumber(0, TAU)

	for i = 1, huts do
		local a = startAngle + (i - 1) / huts * TAU + rng:NextNumber(-0.15, 0.15)
		local rr = ring + rng:NextNumber(-1.5, 1.5)
		buildHut(vila, cx + math.cos(a) * rr, cz + math.sin(a) * rr, a + math.pi, rng, i)
	end

	buildTotem(vila, cx, cz, rng)

	local fireAngle = rng:NextNumber(0, TAU)
	buildFirePit(vila, cx + math.cos(fireAngle) * 6.5, cz + math.sin(fireAngle) * 6.5, rng)

	for i = 1, 3 do
		local a = rng:NextNumber(0, TAU)
		local d = rng:NextNumber(3, ring * 0.8)
		local px, pz = cx + math.cos(a) * d, cz + math.sin(a) * d
		local s = rng:NextNumber(1.0, 1.4)
		local pot = newPart("Pote_" .. i, Vector3.new(s, s * 0.9, s * 0.9), CFrame.new(px, surfaceHeight(px, pz) + s / 2, pz) * VERTICAL, Enum.Material.Sand, Color3.fromRGB(150, 90, 60), vila)
		pot.Shape = Enum.PartType.Cylinder
	end

	return huts
end

--------------------------------------------------------------------------------
-- RUÍNAS ANTIGAS (Lança Ancestral -- 1 por mapa)
--------------------------------------------------------------------------------

-- Ponto fixo por seed, a CONFIG.Ruins.Inland da costa, evitando a montanha
-- e (se já existir) a Vila Nativa.
local function ruinsSite(avoid: { Vector3 }): (number, number)
	local rng = Random.new(currentSeed + 9)

	for _ = 1, 40 do
		local angle = rng:NextNumber(0, TAU)
		local dist = coastRadiusAt(angle) - CONFIG.Ruins.Inland
		local x, z = math.cos(angle) * dist, math.sin(angle) * dist

		local ok = true
		for _, p in avoid do
			if (x - p.X) ^ 2 + (z - p.Z) ^ 2 < 60 ^ 2 then
				ok = false
				break
			end
		end
		if ok then
			return x, z
		end
	end

	local angle = rng:NextNumber(0, TAU)
	local dist = coastRadiusAt(angle) - CONFIG.Ruins.Inland
	return math.cos(angle) * dist, math.sin(angle) * dist
end

--[[
	GenerateRuins()
	Círculo de pedras + pedestal central, num ponto fixo por seed (evita a
	montanha e a Vila, se já gerada). A Lança Ancestral fica em cima do
	pedestal como uma Tool solta no Workspace -- Roblox já pega
	automaticamente sozinho ao tocar (igual "espada largada no chão"),
	sem precisar de ProximityPrompt. Limpa só Ruinas. Devolve 1.
]]
function IslandGenerator.GenerateRuins(): number
	local ruinas = resetFolder("Ruinas")

	local avoid = {}
	local mx, mz = mountainSite()
	table.insert(avoid, Vector3.new(mx, 0, mz))

	local clareiras = getIlhaFolder():FindFirstChild("Clareiras")
	if clareiras then
		for _, marker in clareiras:GetChildren() do
			if marker:IsA("BasePart") and marker:GetAttribute("Uso") == "Vila" then
				table.insert(avoid, marker.Position)
			end
		end
	end

	local rx, rz = ruinsSite(avoid)
	local groundY = surfaceHeight(rx, rz)
	local rng = Random.new(currentSeed + 9)
	local R = CONFIG.Ruins.Radius

	for i = 1, CONFIG.Ruins.StoneCount do
		local a = (i - 1) / CONFIG.Ruins.StoneCount * TAU + rng:NextNumber(-0.1, 0.1)
		local sx, sz = rx + math.cos(a) * R, rz + math.sin(a) * R
		local h = CONFIG.Ruins.StoneHeight * rng:NextNumber(0.7, 1)
		local sy = surfaceHeight(sx, sz)
		local facing = math.atan2(sz - rz, sx - rx)

		newPart(
			"Pedra_" .. i,
			Vector3.new(1.6, h, 2.2),
			CFrame.new(sx, sy + h / 2 - 0.5, sz) * CFrame.Angles(0, facing, 0) * CFrame.Angles(rng:NextNumber(-0.05, 0.05), 0, rng:NextNumber(-0.05, 0.05)),
			Enum.Material.Slate,
			rockColor(rng),
			ruinas
		)
	end

	newPart("Pedestal", Vector3.new(3, 3, 3), CFrame.new(rx, groundY + 1.5, rz), Enum.Material.Slate, Color3.fromRGB(95, 92, 85), ruinas)

	local tool = ToolFactory.Create("LancaAncestral")
	if tool then
		local handle = tool:FindFirstChild("Handle")
		if handle and handle:IsA("BasePart") then
			handle.CFrame = CFrame.new(rx, groundY + 3.2, rz) * CFrame.Angles(math.pi / 2, 0, 0)
			handle.Anchored = true -- solta sozinho quando equipada (comportamento padrão do Tool)
		end
		tool.Parent = ruinas
	else
		warn("[IslandGenerator] ToolFactory não criou a Lança Ancestral.")
	end

	return 1
end

--------------------------------------------------------------------------------
-- Orquestração
--------------------------------------------------------------------------------

function IslandGenerator.SetSeed(seed: number)
	currentSeed = seed
end

--[[
	ClearAll()
	Apaga Workspace.Ilha, o terreno da área real e o lençol de água.
]]
function IslandGenerator.ClearAll()
	local ilha = Workspace:FindFirstChild("Ilha")
	if ilha then
		ilha:Destroy()
	end

	-- Limpa o oceano (bloco fundo -- mesma faixa que GenerateTerrain preenche)
	-- e a coluna de terreno da área real.
	local waterSize = CONFIG.WaterHalf * 2
	local oceanTop, oceanBottom = CONFIG.SeaLevel + 8, CONFIG.MinY - 16
	Terrain:FillBlock(
		CFrame.new(0, (oceanTop + oceanBottom) / 2, 0),
		Vector3.new(waterSize, oceanTop - oceanBottom, waterSize),
		Enum.Material.Air
	)

	local half = CONFIG.AreaHalf
	local height = CONFIG.MaxY - CONFIG.MinY
	Terrain:FillBlock(CFrame.new(0, CONFIG.MinY + height / 2, 0), Vector3.new(half * 2, height, half * 2), Enum.Material.Air)
end

--[[
	Generate(seed?)
	Terreno -> Rochas -> Caverna -> Floresta -> Vila, e imprime o resumo.
]]
function IslandGenerator.Generate(seed: number?)
	if seed then
		IslandGenerator.SetSeed(seed)
	end

	local t0 = os.clock()
	print(string.format("[IslandGenerator] Gerando ilha (seed %d)...", currentSeed))

	IslandGenerator.GenerateTerrain()
	task.wait()

	local rocks = IslandGenerator.GenerateRockFormations()
	local caves = IslandGenerator.GenerateCave()
	local trees = IslandGenerator.GenerateForest()
	local huts = IslandGenerator.GenerateNativeVillage()
	local ruins = IslandGenerator.GenerateRuins()

	local failed = {}
	for id in failedTemplates do
		table.insert(failed, tostring(id))
	end

	print(
		string.format(
			"[IslandGenerator] Concluído em %.1fs -- árvores: %d | grupos de rochas: %d | cavernas: %d | cabanas: %d | ruínas: %d",
			os.clock() - t0,
			trees,
			rocks,
			caves,
			huts,
			ruins
		)
	)
	if #failed > 0 then
		warn("[IslandGenerator] Assets que não carregaram (usado placeholder): " .. table.concat(failed, ", "))
	end
end

return IslandGenerator
