--!strict
--[[
	PlaneCrashGenerator (ferramenta de editor)
	Espalha as peças do avião destruído (asset CONFIG.AssetId) pela ilha
	como se ele tivesse caído de verdade.

	AUTO-BOOT: init.server.luau chama Generate() sozinho ao dar Play, logo
	depois do IslandGenerator, SE Workspace.Ilha ainda não existir (ver
	comentário lá). Continua dando pra chamar manualmente também.

	USO (Command Bar do Studio, em modo de edição, DEPOIS de gerar a ilha):
		local Crash = require(game.ServerScriptService.Server.Tools.PlaneCrashGenerator)
		Crash.Generate()        -- ou Crash.Generate(99) pra outra seed
		Crash.ClearCrash()      -- apaga Workspace.Ilha.Destrocos

	A IDEIA: queda não é espalhamento aleatório, é uma TRAJETÓRIA.
	  O avião vem do mar num ângulo, toca a água, arrasta pela praia e
	  termina mata adentro. Ao longo desse rastro:
	    - t = 0.0 .. ~0.37  -> mar (primeiro impacto, peças no fundo)
	    - t ~ 0.37 .. ~0.52 -> praia (faixa de areia)
	    - t ~ 0.52 .. 1.0   -> interior/floresta
	  Peça PESADA viaja mais longe (momento), então as maiores ficam no fim
	  do rastro e as leves ficam para trás. O espalhamento lateral cresce ao
	  longo do caminho (os destroços vão abrindo em leque), e duas peças são
	  arremessadas longe do eixo, mata adentro.

	  Além das peças: um sulco é escavado no terreno ao longo da parte em
	  terra (com leito de Ground exposto), árvores no caminho são removidas
	  e as da borda ficam tombadas. Sem isso o avião parece "colocado" em
	  cima do mapa, não "caído" nele.

	NADA AQUI DEPENDE DA SEED DA ILHA. O módulo descobre onde a ilha está
	por raycast contra o Terrain (encontra a linha da costa marchando pra
	fora, lê o material do chão pra saber areia/grama/rocha). Então funciona
	mesmo se você tiver editado o terreno na mão depois de gerar.

	ORDEM INTERNA: escava o sulco ANTES de posicionar as peças, pra elas
	assentarem dentro da vala, não flutuando sobre o terreno antigo.

	Grupos: Workspace/Ilha/Destrocos/{Mar, Praia, Floresta}.
	A maior peça recebe Attribute "DestrocoPrincipal" = true.
]]

local Workspace = game:GetService("Workspace")
local Terrain = Workspace.Terrain

local IslandGenerator = require(script.Parent.IslandGenerator)
local IslandLayout = require(script.Parent.IslandLayout)

local PlaneCrashGenerator = {}

--------------------------------------------------------------------------------
-- Ajustes (escala pro mapa de ~1500 de diâmetro)
--------------------------------------------------------------------------------

local CONFIG = {
	Seed = 2024,
	AssetId = 15972190998,

	PlaneLength = 150, -- comprimento do avião inteiro (studs) depois de escalado
	SeaLevel = IslandLayout.CONFIG.SeaLevel,

	Trail = {
		WaterStart = 170, -- quanto o rastro começa ANTES da costa (dentro do mar)
		InlandEnd = 280, -- quanto o rastro termina DEPOIS da costa (mata adentro)
		Drift = 45, -- curva lateral máxima do rastro (studs)
		SpreadBase = 12, -- espalhamento lateral no começo
		SpreadEnd = 42, -- espalhamento lateral no fim (leque)
	},

	Outliers = {
		Count = 2, -- peças arremessadas pra longe do eixo, na mata
		DistanceMin = 90,
		DistanceMax = 200,
		MinT = 0.55, -- só a partir daqui (já em terra)
	},

	Debris = {
		ExtraCount = 22, -- fragmentos extras (clones reduzidos das peças)
		ScaleMin = 0.12,
		ScaleMax = 0.38,
	},

	Scar = {
		Enabled = true,
		Depth = 3.6, -- profundidade da vala
		Radius = 11, -- meia-largura
		Step = 6, -- distância entre amostras ao longo do rastro
	},

	Clearing = {
		TreeRemoveRadius = 26, -- árvores removidas (o avião passou por cima)
		TreeFellRadius = 42, -- árvores tombadas (borda do impacto)
		RockRemoveRadius = 18,
	},

	-- Distância mínima do rastro a qualquer POI (marcadores em Ilha/Layout).
	PoiAvoidRadius = 110,

	Smoke = {
		Enabled = true, -- fumaça fraca no destroço principal
	},

	-- Peças acima disso ganham colisão precisa (dá pra andar dentro do
	-- casco); o resto usa Hull, que é bem mais barato.
	PreciseCollisionMinSize = 14,
}

local TAU = math.pi * 2
local currentSeed = CONFIG.Seed

--------------------------------------------------------------------------------
-- Leitura do mundo (raycast = verdade absoluta, não depende de seed)
--------------------------------------------------------------------------------

local raycastParams = RaycastParams.new()
raycastParams.FilterType = Enum.RaycastFilterType.Include
raycastParams.FilterDescendantsInstances = { Terrain }
raycastParams.IgnoreWater = true

-- Altura e material do chão em (x, z). y = nil quando não há terreno ali.
local function probe(x: number, z: number): (number?, Enum.Material)
	local result = Workspace:Raycast(Vector3.new(x, 400, z), Vector3.new(0, -900, 0), raycastParams)
	if result then
		return result.Position.Y, result.Material
	end
	return nil, Enum.Material.Air
end

-- Distância do centro até onde o terreno afunda abaixo do nível do mar,
-- naquele ângulo. Marcha pra fora e refina por bissecção.
local function findShoreline(angle: number): number
	local dx, dz = math.cos(angle), math.sin(angle)
	local lastLand = 0

	for r = 0, IslandLayout.AreaHalf(), 4 do
		local y = probe(dx * r, dz * r)
		if y == nil or y < CONFIG.SeaLevel then
			local lo, hi = lastLand, r
			for _ = 1, 7 do
				local mid = (lo + hi) / 2
				local my = probe(dx * mid, dz * mid)
				if my ~= nil and my >= CONFIG.SeaLevel then
					lo = mid
				else
					hi = mid
				end
			end
			return lo
		end
		lastLand = r
	end

	return IslandLayout.CONFIG.CoastRadius
end

-- AABB no espaço do mundo (GetBoundingBox segue a rotação do pivô, o que
-- quebra a conta de "assentar no chão" depois de girar a peça).
local function worldBounds(model: Model): (Vector3, Vector3)
	local minV = Vector3.new(math.huge, math.huge, math.huge)
	local maxV = Vector3.new(-math.huge, -math.huge, -math.huge)

	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			local cf, s = d.CFrame, d.Size
			local r, u, l = cf.RightVector, cf.UpVector, cf.LookVector
			local ext = Vector3.new(
				math.abs(r.X) * s.X + math.abs(u.X) * s.Y + math.abs(l.X) * s.Z,
				math.abs(r.Y) * s.X + math.abs(u.Y) * s.Y + math.abs(l.Y) * s.Z,
				math.abs(r.Z) * s.X + math.abs(u.Z) * s.Y + math.abs(l.Z) * s.Z
			) * 0.5
			local p = cf.Position
			minV = minV:Min(p - ext)
			maxV = maxV:Max(p + ext)
		end
	end

	return minV, maxV
end

--------------------------------------------------------------------------------
-- Pastas
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

local function resetDestrocos(): (Folder, Folder, Folder, Folder)
	local ilha = getIlhaFolder()
	local existing = ilha:FindFirstChild("Destrocos")
	if existing then
		existing:Destroy()
	end

	local root = Instance.new("Folder")
	root.Name = "Destrocos"
	root.Parent = ilha

	local function sub(name: string): Folder
		local f = Instance.new("Folder")
		f.Name = name
		f.Parent = root
		return f
	end

	return root, sub("Mar"), sub("Praia"), sub("Floresta")
end

--------------------------------------------------------------------------------
-- Avião de reserva (100% Part) -- usado quando InsertService não carrega o
-- asset (asset privado/moderado, ou fora do modo de edição). Assim SEMPRE
-- cai um avião: fuselagem em segmentos, asas, cauda, motores, bico.
--------------------------------------------------------------------------------

local function newPlanePart(parent: Instance, name: string, size: Vector3, cf: CFrame, color: Color3, shape: Enum.PartType?): Part
	local p = Instance.new("Part")
	p.Name = name
	if shape then
		p.Shape = shape
	end
	p.Size = size
	p.CFrame = cf
	p.Anchored = true
	p.Material = Enum.Material.Metal
	p.Color = color
	p.Parent = parent
	return p
end

local function buildPlaceholderPlane(): Model
	local model = Instance.new("Model")
	model.Name = "AviaoPlaceholder"

	local hull = Color3.fromRGB(196, 198, 203)
	local trim = Color3.fromRGB(150, 40, 44)
	local dark = Color3.fromRGB(70, 72, 78)
	local ALONG_Z = CFrame.Angles(0, math.pi / 2, 0)

	-- Fuselagem: 5 segmentos ao longo de Z (comprimento total 60).
	for i = 1, 5 do
		local z = (i - 3) * 12
		newPlanePart(model, "Fuselagem_" .. i, Vector3.new(12.4, 7.5, 7.5), CFrame.new(0, 0, z) * ALONG_Z, hull, Enum.PartType.Cylinder)
	end
	-- Bico.
	for i, r in { 3.4, 2.4, 1.4, 0.7 } do
		newPlanePart(model, "Bico_" .. i, Vector3.new(2.2, r * 2, r * 2), CFrame.new(0, 0, -30 - (i - 1) * 2) * ALONG_Z, hull, Enum.PartType.Cylinder)
	end
	-- Cabine.
	newPlanePart(model, "Cabine", Vector3.new(4.5, 2.4, 5), CFrame.new(0, 3.4, -22), dark)
	-- Faixa.
	newPlanePart(model, "Faixa", Vector3.new(0.3, 1.6, 58), CFrame.new(3.85, 0.5, 0), trim)
	newPlanePart(model, "Faixa2", Vector3.new(0.3, 1.6, 58), CFrame.new(-3.85, 0.5, 0), trim)

	-- Asas (envergadura 64).
	newPlanePart(model, "AsaE", Vector3.new(30, 1.2, 13), CFrame.new(-18, -1, 2) * CFrame.Angles(0, 0, math.rad(3)), hull)
	newPlanePart(model, "AsaD", Vector3.new(30, 1.2, 13), CFrame.new(18, -1, 2) * CFrame.Angles(0, 0, math.rad(-3)), hull)
	-- Motores sob as asas.
	newPlanePart(model, "MotorE", Vector3.new(7, 4, 4), CFrame.new(-14, -3, 1) * ALONG_Z, dark, Enum.PartType.Cylinder)
	newPlanePart(model, "MotorD", Vector3.new(7, 4, 4), CFrame.new(14, -3, 1) * ALONG_Z, dark, Enum.PartType.Cylinder)

	-- Cauda.
	newPlanePart(model, "Leme", Vector3.new(1, 11, 9), CFrame.new(0, 6, 27), hull)
	newPlanePart(model, "EstabE", Vector3.new(14, 1, 6), CFrame.new(-6, 1, 28), hull)
	newPlanePart(model, "EstabD", Vector3.new(14, 1, 6), CFrame.new(6, 1, 28), hull)

	for _, d in model:GetChildren() do
		if d:IsA("BasePart") then
			d.TopSurface = Enum.SurfaceType.Smooth
			d.BottomSurface = Enum.SurfaceType.Smooth
		end
	end
	return model
end

--------------------------------------------------------------------------------
-- Peças do avião
--------------------------------------------------------------------------------

-- Cada peça vira seu próprio Model, pra poder usar ScaleTo/PivotTo de forma
-- uniforme (BasePart solto não tem essa API).
--
-- Tenta primeiro o 1º nível (Models/Parts direto, ou um Model único
-- embrulhando -- preserva sub-montagens tipo "asa" com várias Parts
-- soldadas juntas, se o asset vier organizado assim). Se isso não achar
-- nada (asset guarda tudo mais fundo, dentro de Folders por exemplo), cai
-- pro modo geral: cada BasePart em QUALQUER profundidade vira sua própria
-- peça -- sempre funciona, não importa como o asset está organizado por
-- dentro, ao custo de eventualmente separar uma sub-montagem que devia
-- ficar junta.
local function gatherPieces(source: Model): { Model }
	local pieces: { Model } = {}
	local index = 0

	local topLevel = source:GetChildren()
	if #topLevel == 1 and topLevel[1]:IsA("Model") then
		topLevel = topLevel[1]:GetChildren()
	end

	for _, child in topLevel do
		if child:IsA("BasePart") or child:IsA("Model") then
			index += 1
			local wrapper = Instance.new("Model")
			wrapper.Name = "Peca_" .. index
			child.Parent = wrapper
			-- PrimaryPart de propósito não definido: assim o pivô é o centro
			-- da caixa, que é o que faz a peça girar "em torno dela mesma".
			table.insert(pieces, wrapper)
		end
	end

	if #pieces > 0 then
		return pieces
	end

	for _, descendant in source:GetDescendants() do
		if descendant:IsA("BasePart") then
			index += 1
			local wrapper = Instance.new("Model")
			wrapper.Name = "Peca_" .. index
			descendant.Parent = wrapper
			table.insert(pieces, wrapper)
		end
	end

	return pieces
end

local function pieceVolume(piece: Model): number
	local minV, maxV = worldBounds(piece)
	local size = maxV - minV
	return size.X * size.Y * size.Z
end

local function applyCollisionFidelity(piece: Model)
	local minV, maxV = worldBounds(piece)
	local size = maxV - minV
	local biggest = math.max(size.X, size.Y, size.Z)
	local fidelity = if biggest >= CONFIG.PreciseCollisionMinSize
		then Enum.CollisionFidelity.PreciseConvexDecomposition
		else Enum.CollisionFidelity.Hull

	for _, d in piece:GetDescendants() do
		if d:IsA("MeshPart") then
			d.CollisionFidelity = fidelity
		end
		if d:IsA("BasePart") then
			d.Anchored = true
			d.CanCollide = true
		end
	end
end

--------------------------------------------------------------------------------
-- Posicionamento
--------------------------------------------------------------------------------

-- Assenta a peça: aplica rotação, mede a AABB já rotacionada, encosta a
-- base no chão e enterra `sink` studs.
local function seatPiece(piece: Model, x: number, z: number, groundY: number, rot: CFrame, sink: number)
	piece:PivotTo(CFrame.new(x, 0, z) * rot)
	local minV = worldBounds(piece)
	piece:PivotTo(piece:GetPivot() + Vector3.new(0, groundY - minV.Y - sink, 0))
end

-- Zona pela leitura do chão, não por fórmula: abaixo do mar = Mar, areia =
-- Praia, resto = Floresta.
local function zoneFolderFor(y: number, material: Enum.Material, mar: Folder, praia: Folder, floresta: Folder): Folder
	if y < CONFIG.SeaLevel then
		return mar
	elseif material == Enum.Material.Sand then
		return praia
	end
	return floresta
end

--------------------------------------------------------------------------------
-- Escolha do rastro
--------------------------------------------------------------------------------

-- Pontos que o rastro deve evitar: todos os POIs (marcadores em Ilha/Layout,
-- criados por PoiGenerator) e a boca da caverna.
local function collectAvoidPoints(): { Vector3 }
	local points: { Vector3 } = {}
	local ilha = Workspace:FindFirstChild("Ilha")
	if not ilha then
		return points
	end

	local layout = ilha:FindFirstChild("Layout")
	if layout then
		for _, m in layout:GetChildren() do
			if m:IsA("BasePart") and m:GetAttribute("Poi") ~= nil then
				table.insert(points, m.Position)
			end
		end
	end

	local caverna = ilha:FindFirstChild("Caverna")
	if caverna then
		for _, child in caverna:GetChildren() do
			if child:IsA("BasePart") and child:GetAttribute("MonstroSpawn") == true then
				table.insert(points, child.Position)
			end
		end
	end

	return points
end

-- Um rastro serve se, na parte em terra, não cruza rocha (montanha), não
-- sobe/desce degrau grande e passa longe da vila e da caverna.
local function trailIsClear(angle: number, shore: number, avoid: { Vector3 }): boolean
	local dx, dz = math.cos(angle), math.sin(angle)

	for r = shore, math.max(shore - CONFIG.Trail.InlandEnd, 10), -8 do
		local x, z = dx * r, dz * r
		local y, material = probe(x, z)

		if y == nil then
			return false
		end
		if material == Enum.Material.Rock then
			return false -- montanha
		end

		local yAhead = probe(dx * (r - 8), dz * (r - 8))
		if yAhead and math.abs(yAhead - y) > 9 then
			return false -- degrau/penhasco
		end

		for _, p in avoid do
			if (x - p.X) ^ 2 + (z - p.Z) ^ 2 < CONFIG.PoiAvoidRadius ^ 2 then
				return false
			end
		end
	end

	return true
end

--------------------------------------------------------------------------------
-- Sulco no terreno e árvores derrubadas
--------------------------------------------------------------------------------

local function carveScar(trailPoint: (number) -> Vector3, length: number)
	if not CONFIG.Scar.Enabled then
		return
	end

	local steps = math.max(math.floor(length / CONFIG.Scar.Step), 1)
	local depth, radius = CONFIG.Scar.Depth, CONFIG.Scar.Radius

	for i = 0, steps do
		local t = i / steps
		local p = trailPoint(t)
		local y = probe(p.X, p.Z)

		if y and y >= CONFIG.SeaLevel then
			-- O sulco fica mais fundo e largo no fim (onde o avião arrastou mais).
			local f = 0.5 + t * 0.5
			local d, rr = depth * f, radius * f

			-- Leito de terra exposta primeiro...
			Terrain:FillCylinder(CFrame.new(p.X, y - d - 0.5, p.Z), 3, rr, Enum.Material.Ground)
			-- ...e só então remove o topo, deixando a vala aberta.
			Terrain:FillBall(Vector3.new(p.X, y + rr - d, p.Z), rr, Enum.Material.Air)
		end
	end
end

-- Distância (no plano XZ) de um ponto até a polilinha do rastro.
local function distanceToTrail(x: number, z: number, samples: { Vector3 }): number
	local best = math.huge
	for _, p in samples do
		local d2 = (x - p.X) ^ 2 + (z - p.Z) ^ 2
		if d2 < best then
			best = d2
		end
	end
	return math.sqrt(best)
end

-- Gira o modelo inteiro em torno de um ponto do mundo (a base do tronco),
-- pra tombar a árvore sem ela afundar no chão.
local function rotateAround(model: Model, pivotPoint: Vector3, rotation: CFrame)
	local old = model:GetPivot()
	model:PivotTo(CFrame.new(pivotPoint) * rotation * CFrame.new(-pivotPoint) * old)
end

local function clearVegetation(samples: { Vector3 }, rng: Random): (number, number)
	local ilha = Workspace:FindFirstChild("Ilha")
	if not ilha then
		return 0, 0
	end

	local removed, felled = 0, 0
	local floresta = ilha:FindFirstChild("Floresta")

	if floresta then
		for _, tree in floresta:GetChildren() do
			if tree:IsA("Model") then
				local pos = tree:GetPivot().Position
				local d = distanceToTrail(pos.X, pos.Z, samples)

				if d < CONFIG.Clearing.TreeRemoveRadius then
					tree:Destroy()
					removed += 1
				elseif d < CONFIG.Clearing.TreeFellRadius then
					local minV = worldBounds(tree)
					local base = Vector3.new(pos.X, minV.Y, pos.Z)
					-- Tomba pra fora do rastro, como se empurrada pelo impacto.
					local away = math.atan2(pos.Z, pos.X) + rng:NextNumber(-0.6, 0.6)
					local rot = CFrame.Angles(0, away, 0)
						* CFrame.Angles(math.rad(rng:NextNumber(62, 85)), 0, 0)
					rotateAround(tree, base, rot)
					felled += 1
				end
			end
		end
	end

	local rochas = ilha:FindFirstChild("Rochas")
	if rochas then
		for _, group in rochas:GetChildren() do
			if group:IsA("Model") then
				local pos = group:GetPivot().Position
				if distanceToTrail(pos.X, pos.Z, samples) < CONFIG.Clearing.RockRemoveRadius then
					group:Destroy()
				end
			end
		end
	end

	return removed, felled
end

--------------------------------------------------------------------------------
-- API
--------------------------------------------------------------------------------

function PlaneCrashGenerator.SetSeed(seed: number)
	currentSeed = seed
end

--[[
	ClearCrash()
	Apaga Workspace.Ilha.Destrocos. NÃO desfaz o sulco no terreno nem
	devolve as árvores removidas -- pra isso, rode IslandGenerator de novo.
]]
function PlaneCrashGenerator.ClearCrash()
	local ilha = Workspace:FindFirstChild("Ilha")
	local destrocos = ilha and ilha:FindFirstChild("Destrocos")
	if destrocos then
		destrocos:Destroy()
	end
end

--[[
	Generate(seed?)
	Escolhe a trajetória, escava o sulco, derruba a vegetação no caminho e
	espalha as peças. Imprime o resumo no Output.
]]
function PlaneCrashGenerator.Generate(seed: number?)
	if seed then
		PlaneCrashGenerator.SetSeed(seed)
	end

	local t0 = os.clock()

	-- Precisa de terreno: sem ilha, não há onde cair.
	local centerY = probe(0, 0)
	if centerY == nil then
		warn("[PlaneCrash] Não achei terreno no centro do mapa. Rode IslandGenerator.Generate() primeiro.")
		return
	end

	local template = IslandGenerator.LoadAssetModel(CONFIG.AssetId)
	local usingPlaceholder = false
	if not template then
		warn(string.format("[PlaneCrash] Asset %d não carregou (privado/moderado, ou fora do modo de edição). Usando avião de reserva em Part.", CONFIG.AssetId))
		template = buildPlaceholderPlane()
		usingPlaceholder = true
	end

	local rng = Random.new(currentSeed)

	-- 1) Trajetória: testa ângulos até achar um que não cruze montanha,
	--    penhasco, vila nem caverna.
	local avoid = collectAvoidPoints()
	local angle, shore
	for attempt = 1, 64 do
		local candidate = rng:NextNumber(0, TAU)
		local candidateShore = findShoreline(candidate)
		if trailIsClear(candidate, candidateShore, avoid) then
			angle, shore = candidate, candidateShore
			break
		end
		if attempt == 64 then
			angle, shore = candidate, candidateShore
			warn("[PlaneCrash] Nenhuma trajetória totalmente limpa; usando a última tentativa.")
		end
	end
	assert(angle and shore, "trajetória não definida")

	local outward = Vector3.new(math.cos(angle), 0, math.sin(angle))
	local entry = outward * (shore + CONFIG.Trail.WaterStart)
	local terminus = outward * math.max(shore - CONFIG.Trail.InlandEnd, 15)
	local side = Vector3.new(-outward.Z, 0, outward.X)
	local drift = rng:NextNumber(-CONFIG.Trail.Drift, CONFIG.Trail.Drift)

	local function trailPoint(t: number): Vector3
		return entry:Lerp(terminus, t) + side * (math.sin(t * math.pi) * drift)
	end

	local function trailYaw(t: number): number
		local a = trailPoint(math.max(t - 0.02, 0))
		local b = trailPoint(math.min(t + 0.02, 1))
		local d = b - a
		return math.atan2(d.X, d.Z)
	end

	local trailLength = (terminus - entry).Magnitude

	-- 2) Sulco ANTES das peças, pra elas assentarem dentro da vala.
	carveScar(trailPoint, trailLength)

	-- 3) Vegetação no caminho.
	local samples: { Vector3 } = {}
	for i = 0, 40 do
		table.insert(samples, trailPoint(i / 40))
	end
	local treesRemoved, treesFelled = clearVegetation(samples, rng)

	-- 4) Peças.
	local root, mar, praia, floresta = resetDestrocos()

	local source = template:Clone()

	-- Mede o avião INTEIRO antes de fatiar em peças -- gatherPieces reparenta
	-- cada pedaço pra fora de `source`, que ficaria vazio (bounds sem
	-- sentido) se a medição rodasse depois.
	local minV, maxV = worldBounds(source)
	local rawSize = maxV - minV
	local rawLength = math.max(rawSize.X, rawSize.Z, rawSize.Y, 0.01)
	local scaleFactor = CONFIG.PlaneLength / rawLength

	local pieces = gatherPieces(source)
	if #pieces == 0 then
		warn("[PlaneCrash] O asset não tem peças utilizáveis.")
		source:Destroy()
		return
	end
	for _, piece in pieces do
		piece:ScaleTo(piece:GetScale() * scaleFactor)
	end

	-- Maior primeiro: peça pesada viaja mais longe.
	table.sort(pieces, function(a, b)
		return pieceVolume(a) > pieceVolume(b)
	end)

	-- Acha um chão aceitável perto de (x, z): evita rocha e ladeira forte.
	local function findGround(x: number, z: number): (number?, Enum.Material, number, number)
		for _ = 1, 8 do
			local y, material = probe(x, z)
			if y and material ~= Enum.Material.Rock then
				return y, material, x, z
			end
			x += rng:NextNumber(-9, 9)
			z += rng:NextNumber(-9, 9)
		end
		local y, material = probe(x, z)
		return y, material, x, z
	end

	local placed = 0
	local counts = { Mar = 0, Praia = 0, Floresta = 0 }

	local function place(piece: Model, x: number, z: number, yaw: number, tumble: number, sinkFrac: number, isMain: boolean)
		local y, material, gx, gz = findGround(x, z)
		if y == nil then
			piece:Destroy()
			return
		end

		local rot = CFrame.Angles(0, yaw, 0)
			* CFrame.Angles(rng:NextNumber(-tumble, tumble), 0, rng:NextNumber(-tumble, tumble))

		local pieceMin, pieceMax = worldBounds(piece)
		local height = pieceMax.Y - pieceMin.Y
		seatPiece(piece, gx, gz, y, rot, height * sinkFrac)

		applyCollisionFidelity(piece)

		local folder = zoneFolderFor(y, material, mar, praia, floresta)
		piece.Parent = folder
		counts[folder.Name] += 1
		placed += 1

		if isMain then
			piece.Name = "DestrocoPrincipal"
			piece:SetAttribute("DestrocoPrincipal", true)

			if CONFIG.Smoke.Enabled then
				local anchor = piece:FindFirstChildWhichIsA("BasePart", true)
				if anchor then
					local smoke = Instance.new("Smoke")
					smoke.Color = Color3.fromRGB(90, 90, 95)
					smoke.Size = 8
					smoke.Opacity = 0.18
					smoke.RiseVelocity = 6
					smoke.Parent = anchor

					local glow = Instance.new("PointLight")
					glow.Color = Color3.fromRGB(255, 130, 50)
					glow.Brightness = 0.35
					glow.Range = 14
					glow.Shadows = false
					glow.Parent = anchor
				end
			end
		end
	end

	-- 4a) Destroço principal: fim do rastro, alinhado com a trajetória,
	--     nariz enterrado.
	local mainT = rng:NextNumber(0.9, 0.96)
	local mainP = trailPoint(mainT)
	place(pieces[1], mainP.X, mainP.Z, trailYaw(mainT) + rng:NextNumber(-0.25, 0.25), 0.14, 0.22, true)

	-- 4b) Peças arremessadas pra fora do eixo, mata adentro.
	local outlierCount = math.min(CONFIG.Outliers.Count, math.max(#pieces - 2, 0))
	local nextIndex = 2
	for i = 1, outlierCount do
		local piece = pieces[nextIndex]
		nextIndex += 1
		local t = rng:NextNumber(CONFIG.Outliers.MinT, 0.95)
		local base = trailPoint(t)
		local dir = if i % 2 == 0 then 1 else -1
		local dist = rng:NextNumber(CONFIG.Outliers.DistanceMin, CONFIG.Outliers.DistanceMax)
		local p = base + side * (dir * dist) + outward * rng:NextNumber(-25, 25)
		place(piece, p.X, p.Z, rng:NextNumber(0, TAU), 0.5, 0.15, false)
	end

	-- 4c) O resto ao longo do rastro. Peça maior = t maior (viajou mais);
	--     leque lateral cresce com t.
	local remaining = #pieces - nextIndex + 1
	local slot = 0
	for i = nextIndex, #pieces do
		local piece = pieces[i]
		-- pieces está ordenado do maior pro menor, então invertemos: os
		-- últimos (menores) ficam com t baixo, perto do primeiro impacto.
		local frac = if remaining > 1 then 1 - (slot / (remaining - 1)) else 0.5
		local t = math.clamp(0.06 + frac * 0.78 + rng:NextNumber(-0.05, 0.05), 0.02, 0.9)
		local spread = CONFIG.Trail.SpreadBase + (CONFIG.Trail.SpreadEnd - CONFIG.Trail.SpreadBase) * t
		local base = trailPoint(t)
		local p = base + side * rng:NextNumber(-spread, spread) + outward * rng:NextNumber(-6, 6)

		-- Fragmento pequeno tomba mais; peça grande tende a ficar deitada.
		local big = pieceVolume(piece) > 300
		place(
			piece,
			p.X,
			p.Z,
			if big then trailYaw(t) + rng:NextNumber(-0.9, 0.9) else rng:NextNumber(0, TAU),
			if big then 0.25 else 0.7,
			rng:NextNumber(0.1, 0.3),
			false
		)
		slot += 1
	end

	-- 4d) Fragmentos extras: clones reduzidos, pra o campo de destroços não
	--     parecer só "N peças espaçadas".
	local placedPieces = root:GetDescendants()
	local sourcesForDebris: { Model } = {}
	for _, d in placedPieces do
		if d:IsA("Model") and d.Parent and d.Parent:IsA("Folder") then
			table.insert(sourcesForDebris, d)
		end
	end

	if #sourcesForDebris > 0 then
		for i = 1, CONFIG.Debris.ExtraCount do
			local original = sourcesForDebris[rng:NextInteger(1, #sourcesForDebris)]
			local fragment = original:Clone()
			fragment.Name = "Fragmento_" .. i
			fragment:SetAttribute("DestrocoPrincipal", nil)
			for _, d in fragment:GetDescendants() do
				if d:IsA("Smoke") or d:IsA("PointLight") or d:IsA("Fire") then
					d:Destroy()
				end
			end
			fragment:ScaleTo(fragment:GetScale() * rng:NextNumber(CONFIG.Debris.ScaleMin, CONFIG.Debris.ScaleMax))

			local t = math.clamp(rng:NextNumber(0.02, 1.0), 0, 1)
			local spread = (CONFIG.Trail.SpreadBase + (CONFIG.Trail.SpreadEnd - CONFIG.Trail.SpreadBase) * t) * 1.8
			local base = trailPoint(t)
			local p = base + side * rng:NextNumber(-spread, spread) + outward * rng:NextNumber(-10, 10)
			place(fragment, p.X, p.Z, rng:NextNumber(0, TAU), 0.9, rng:NextNumber(0.05, 0.35), false)
		end
	end

	source:Destroy()

	print(
		string.format(
			"[PlaneCrash] Concluído em %.1fs (seed %d)%s -- peças: %d (mar %d | praia %d | floresta %d) | árvores removidas: %d, tombadas: %d | destroço principal em (%.0f, %.0f)",
			os.clock() - t0,
			currentSeed,
			if usingPlaceholder then " [avião de reserva]" else "",
			placed,
			counts.Mar,
			counts.Praia,
			counts.Floresta,
			treesRemoved,
			treesFelled,
			mainP.X,
			mainP.Z
		)
	)
end

return PlaneCrashGenerator
