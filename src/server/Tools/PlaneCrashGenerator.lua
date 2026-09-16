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

	-- Wide-body internacional: grande o bastante para a fuselagem parecer uma
	-- estrutura explorável ao lado do personagem, sem dominar a ilha inteira.
	PlaneLength = 260, -- comprimento do avião inteiro (studs) depois de escalado
	SeaLevel = IslandLayout.CONFIG.SeaLevel,

	Trail = {
		WaterStart = 240, -- quanto o rastro começa ANTES da costa (dentro do mar)
		InlandEnd = 390, -- quanto o rastro termina DEPOIS da costa (mata adentro)
		Drift = 62, -- curva lateral máxima do rastro (studs)
		SpreadBase = 16, -- espalhamento lateral no começo
		SpreadEnd = 58, -- espalhamento lateral no fim (leque)
	},

	CrashSite = {
		NearbyCount = 2, -- grandes seções ainda perto da fuselagem principal
		Length = 125, -- extensão do conjunto principal ao longo do sulco
		Spread = 34, -- abertura lateral do local de impacto
	},

	Outliers = {
		Count = 3, -- asa/motor/cauda arremessados longe do conjunto principal
		DistanceMin = 125,
		DistanceMax = 310,
		MinT = 0.5,
	},

	Debris = {
		ExtraCount = 34, -- fragmentos menores conectam visualmente os locais
		ScaleMin = 0.12,
		ScaleMax = 0.38,
	},

	Scar = {
		Enabled = true,
		Depth = 5.2, -- profundidade da vala
		Radius = 17, -- meia-largura
		Step = 6, -- distância entre amostras ao longo do rastro
	},

	Clearing = {
		TreeRemoveRadius = 36, -- árvores removidas (o avião passou por cima)
		TreeFellRadius = 58, -- árvores tombadas (borda do impacto)
		RockRemoveRadius = 27,
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

	local function group(name: string): Model
		local result = Instance.new("Model")
		result.Name = name
		result.Parent = model
		return result
	end

	local front = group("FuselagemDianteira")
	local rear = group("FuselagemTraseiraCauda")
	local leftWing = group("AsaEsquerda")
	local rightWing = group("AsaDireita")
	local leftEngine = group("MotorEsquerdo")
	local rightEngine = group("MotorDireito")

	-- A fuselagem fica em duas seções reconhecíveis. Isso preserva a escala e
	-- evita que cada anel do casco seja espalhado como uma peça independente.
	for i = 1, 5 do
		local z = (i - 3) * 12
		local section = if i <= 3 then front else rear
		newPlanePart(section, "Fuselagem_" .. i, Vector3.new(12.4, 7.5, 7.5), CFrame.new(0, 0, z) * ALONG_Z, hull, Enum.PartType.Cylinder)
		newPlanePart(section, "FaixaE_" .. i, Vector3.new(0.3, 1.6, 11.2), CFrame.new(3.85, 0.5, z), trim)
		newPlanePart(section, "FaixaD_" .. i, Vector3.new(0.3, 1.6, 11.2), CFrame.new(-3.85, 0.5, z), trim)
	end
	-- Bico.
	for i, r in { 3.4, 2.4, 1.4, 0.7 } do
		newPlanePart(front, "Bico_" .. i, Vector3.new(2.2, r * 2, r * 2), CFrame.new(0, 0, -30 - (i - 1) * 2) * ALONG_Z, hull, Enum.PartType.Cylinder)
	end
	-- Cabine.
	newPlanePart(front, "Cabine", Vector3.new(4.5, 2.4, 5), CFrame.new(0, 3.4, -22), dark)

	-- Asas (envergadura 64).
	newPlanePart(leftWing, "AsaE", Vector3.new(30, 1.2, 13), CFrame.new(-18, -1, 2) * CFrame.Angles(0, 0, math.rad(3)), hull)
	newPlanePart(rightWing, "AsaD", Vector3.new(30, 1.2, 13), CFrame.new(18, -1, 2) * CFrame.Angles(0, 0, math.rad(-3)), hull)
	-- Motores sob as asas.
	newPlanePart(leftEngine, "MotorE", Vector3.new(7, 4, 4), CFrame.new(-14, -3, 1) * ALONG_Z, dark, Enum.PartType.Cylinder)
	newPlanePart(rightEngine, "MotorD", Vector3.new(7, 4, 4), CFrame.new(14, -3, 1) * ALONG_Z, dark, Enum.PartType.Cylinder)

	-- Cauda.
	newPlanePart(rear, "Leme", Vector3.new(1, 11, 9), CFrame.new(0, 6, 27), hull)
	newPlanePart(rear, "EstabE", Vector3.new(14, 1, 6), CFrame.new(-6, 1, 28), hull)
	newPlanePart(rear, "EstabD", Vector3.new(14, 1, 6), CFrame.new(6, 1, 28), hull)

	for _, d in model:GetDescendants() do
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
			wrapper.Name = child.Name
			wrapper:SetAttribute("NomeOriginal", child.Name)
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
			wrapper.Name = descendant.Name
			wrapper:SetAttribute("NomeOriginal", descendant.Name)
			descendant.Parent = wrapper
			table.insert(pieces, wrapper)
		end
	end

	return pieces
end

local function pieceRole(piece: Model): string
	local names = string.lower(piece.Name)
	for _, descendant in piece:GetDescendants() do
		names ..= " " .. string.lower(descendant.Name)
	end

	if string.find(names, "fusel") or string.find(names, "body") or string.find(names, "hull")
		or string.find(names, "cabine") or string.find(names, "cockpit") or string.find(names, "bico")
		or string.find(names, "nose") then
		return "Fuselagem"
	elseif string.find(names, "asa") or string.find(names, "wing") then
		return "Asa"
	elseif string.find(names, "motor") or string.find(names, "engine") or string.find(names, "turbina") then
		return "Motor"
	elseif string.find(names, "cauda") or string.find(names, "tail") or string.find(names, "leme")
		or string.find(names, "estab") then
		return "Cauda"
	end
	return "Fragmento"
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
		piece:SetAttribute("DestrocoTipo", pieceRole(piece))
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

	local function place(
		piece: Model,
		x: number,
		z: number,
		yaw: number,
		tumble: number,
		sinkFrac: number,
		isMain: boolean,
		cluster: string
	)
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
		piece:SetAttribute("GrupoAcidente", cluster)
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
					smoke.Size = 18
					smoke.Opacity = 0.24
					smoke.RiseVelocity = 8
					smoke.Parent = anchor

					local glow = Instance.new("PointLight")
					glow.Color = Color3.fromRGB(255, 130, 50)
					glow.Brightness = 0.6
					glow.Range = 26
					glow.Shadows = false
					glow.Parent = anchor
				end
			end
		end
	end

	-- Separa as peças por função. O nome vem do asset quando ele é bem
	-- organizado; no fallback, os grupos acima garantem essa classificação.
	local unplaced = table.clone(pieces)
	local function takePreferred(preferred: { string }): Model?
		local bestIndex, bestScore = nil, -math.huge
		for index, candidate in unplaced do
			local role = pieceRole(candidate)
			local preference = 0
			for rank, wanted in preferred do
				if role == wanted then
					preference = (#preferred - rank + 1) * 1e12
					break
				end
			end
			local score = preference + pieceVolume(candidate)
			if score > bestScore then
				bestIndex, bestScore = index, score
			end
		end
		if not bestIndex then
			return nil
		end
		return table.remove(unplaced, bestIndex)
	end

	-- 4a) Local principal: a maior seção da fuselagem termina o sulco. Outras
	-- seções grandes ficam perto o bastante para o jogador ler um único avião.
	local mainT = rng:NextNumber(0.9, 0.96)
	local mainP = trailPoint(mainT)
	local mainPiece = takePreferred({ "Fuselagem" })
	assert(mainPiece, "avião sem peça principal")
	place(mainPiece, mainP.X, mainP.Z, trailYaw(mainT) + rng:NextNumber(-0.18, 0.18), 0.12, 0.18, true, "ImpactoPrincipal")

	-- Manchas escuras largas tornam o ponto final legível mesmo à noite e
	-- escondem a transição geométrica entre a fuselagem e o sulco de Terrain.
	local impactGroundY, impactMaterial = probe(mainP.X, mainP.Z)
	if impactGroundY then
		local impactMarks = Instance.new("Model")
		impactMarks.Name = "LocalDoImpacto"
		impactMarks:SetAttribute("LocalDoImpacto", true)
		impactMarks:SetAttribute("GrupoAcidente", "ImpactoPrincipal")
		impactMarks.Parent = zoneFolderFor(impactGroundY, impactMaterial, mar, praia, floresta)

		for i = 1, 4 do
			local offset = side * rng:NextNumber(-22, 22) + outward * rng:NextNumber(-48, 34)
			local markY = probe(mainP.X + offset.X, mainP.Z + offset.Z)
			if markY then
				local radius = rng:NextNumber(18, 34)
				local mark = Instance.new("Part")
				mark.Name = "SoloQueimado_" .. i
				mark.Shape = Enum.PartType.Cylinder
				mark.Size = Vector3.new(0.18, radius * 2, radius * rng:NextNumber(1.3, 2))
				mark.CFrame = CFrame.new(mainP.X + offset.X, markY + 0.08, mainP.Z + offset.Z)
					* CFrame.Angles(0, trailYaw(mainT) + rng:NextNumber(-0.3, 0.3), math.pi / 2)
				mark.Anchored = true
				mark.CanCollide = false
				mark.CanQuery = false
				mark.CanTouch = false
				mark.CastShadow = false
				mark.Material = Enum.Material.Slate
				mark.Color = Color3.fromRGB(31, 29, 28)
				mark.Transparency = 0.12
				mark.Parent = impactMarks
			end
		end
	end

	local nearbyCount = math.min(CONFIG.CrashSite.NearbyCount, #unplaced)
	for i = 1, nearbyCount do
		local nearby = takePreferred(if i == 1 then { "Fuselagem", "Cauda" } else { "Asa", "Fuselagem" })
		if nearby then
			local distanceBehind = CONFIG.CrashSite.Length * i / (nearbyCount + 1)
			local t = math.clamp(mainT - distanceBehind / trailLength, 0.65, 0.94)
			local dir = if i % 2 == 0 then 1 else -1
			local base = trailPoint(t)
			local p = base + side * dir * rng:NextNumber(12, CONFIG.CrashSite.Spread)
			place(nearby, p.X, p.Z, trailYaw(t) + rng:NextNumber(-0.5, 0.5), 0.28, 0.16, false, "ImpactoPrincipal")
		end
	end

	-- 4b) Grandes destroços secundários. Priorizamos asa e motor para que os
	-- pontos distantes continuem imediatamente reconhecíveis como avião.
	local outlierCount = math.min(CONFIG.Outliers.Count, #unplaced)
	for i = 1, outlierCount do
		local wanted = if i == 1 then { "Asa", "Cauda" } elseif i == 2 then { "Motor", "Asa" } else { "Cauda", "Motor", "Asa" }
		local piece = takePreferred(wanted)
		if not piece then
			break
		end
		local t = rng:NextNumber(CONFIG.Outliers.MinT, 0.95)
		local base = trailPoint(t)
		local dir = if i % 2 == 0 then 1 else -1
		local dist = rng:NextNumber(CONFIG.Outliers.DistanceMin, CONFIG.Outliers.DistanceMax)
		local longitudinal = outward * rng:NextNumber(-25, 25)
		local p = base + side * (dir * dist) + longitudinal
		local foundLand = false
		-- Costas muito recortadas podem deixar o primeiro ponto no oceano.
		-- Recolhe a distância aos poucos, preservando o lado do arremesso.
		for shrink = 0, 6 do
			local factor = 1 - shrink * 0.12
			local candidate = base + side * (dir * dist * factor) + longitudinal
			local candidateY, candidateMaterial = probe(candidate.X, candidate.Z)
			if candidateY and candidateY >= CONFIG.SeaLevel and candidateMaterial ~= Enum.Material.Rock then
				p = candidate
				foundLand = true
				break
			end
		end
		if not foundLand then
			p = base + side * (dir * 35)
		end
		place(piece, p.X, p.Z, rng:NextNumber(0, TAU), 0.55, 0.14, false, "DestrocoDistante")
	end

	-- 4c) O restante forma a ligação visual entre o primeiro contato no mar,
	-- a praia e o local principal mata adentro.
	local remaining = #unplaced
	local slot = 0
	while #unplaced > 0 do
		local piece = table.remove(unplaced, 1)
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
			false,
			"Rastro"
		)
		slot += 1
	end

	-- 4d) Fragmentos extras: clones reduzidos, pra o campo de destroços não
	--     parecer só "N peças espaçadas".
	local placedPieces = root:GetDescendants()
	local sourcesForDebris: { Model } = {}
	for _, d in placedPieces do
		if d:IsA("Model") and d.Parent and d.Parent:IsA("Folder") and d:GetAttribute("DestrocoTipo") ~= nil then
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
			fragment:SetAttribute("DestrocoTipo", "Fragmento")
			place(fragment, p.X, p.Z, rng:NextNumber(0, TAU), 0.9, rng:NextNumber(0.05, 0.35), false, "Fragmento")
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
