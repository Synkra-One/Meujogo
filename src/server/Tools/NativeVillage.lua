--!strict
-- Vila fictícia abandonada. Geometria própria, sem scripts/assets externos.
-- Build recebe a posição já salva do POI; não muda o layout da ilha.
local Workspace = game:GetService("Workspace")
local S = require(script.Parent.Structures)

local NativeVillage = {}
local WOOD = Color3.fromRGB(82, 57, 38)
local DARK = Color3.fromRGB(51, 37, 29)
local REED = Color3.fromRGB(133, 112, 74)
local STRAW = Color3.fromRGB(112, 104, 62)
local ROPE = Color3.fromRGB(155, 133, 91)
local BLOOD = Color3.fromRGB(73, 9, 13)
local TAU = math.pi * 2

local function model(parent: Instance, name: string): Model
	local m = Instance.new("Model")
	m.Name = name
	m:SetAttribute("VilaGerada", true)
	m.Parent = parent
	return m
end

local function piece(parent: Instance, name: string, size: Vector3, cf: CFrame, material: Enum.Material, color: Color3, decor: boolean?): Part
	local p = S.Part(parent, name, size, cf, material, color, { CanCollide = not decor })
	p.CanTouch = false
	if decor then
		p.CanQuery = false
	end
	return p
end

local terrainParams = RaycastParams.new()
terrainParams.FilterType = Enum.RaycastFilterType.Include
terrainParams.FilterDescendantsInstances = { Workspace.Terrain }
terrainParams.IgnoreWater = true

local function ground(x: number, z: number, fallbackY: number): CFrame
	local hit = Workspace:Raycast(Vector3.new(x, fallbackY + 150, z), Vector3.new(0, -400, 0), terrainParams)
	return CFrame.new(x, if hit then hit.Position.Y else fallbackY, z)
end

-- Pequenas manchas independentes acompanham o chão, inclusive em declives.
local function blood(parent: Instance, cf: CFrame, radius: number, rng: Random, onTerrain: boolean)
	local stains = model(parent, "Sangue")
	for i = 1, 13 do
		local a = rng:NextNumber(0, TAU)
		local d = if i == 1 then 0 else rng:NextNumber(0.15, radius)
		local pos = cf:PointToWorldSpace(Vector3.new(math.cos(a) * d, 0, math.sin(a) * d))
		local normal = cf.UpVector
		if onTerrain then
			local hit = Workspace:Raycast(pos + Vector3.new(0, 40, 0), Vector3.new(0, -80, 0), terrainParams)
			if hit then
				pos, normal = hit.Position, hit.Normal
			end
		end
		local tangent = normal:Cross(Vector3.zAxis)
		if tangent.Magnitude < 0.01 then tangent = normal:Cross(Vector3.xAxis) end
		local stainCF = CFrame.fromMatrix(pos + normal * (0.018 + i * 0.001), tangent.Unit, normal)
		local r = if i == 1 then radius * 0.9 else rng:NextNumber(0.12, radius * 0.55)
		local p = piece(stains, "Mancha", Vector3.new(r * 1.7, 0.025, r), stainCF * CFrame.Angles(0, a, 0), Enum.Material.SmoothPlastic, BLOOD:Lerp(Color3.new(0.12, 0.025, 0.02), rng:NextNumber(0, 0.4)), true)
		p.Shape = Enum.PartType.Ball
		p.CastShadow = false
	end
end

local function meat(parent: Instance, cf: CFrame, scale: number)
	local m = model(parent, "CorteDeCarne")
	local p = piece(m, "Carne", Vector3.new(1.05, 1.6, 0.85) * scale, cf, Enum.Material.SmoothPlastic, Color3.fromRGB(111, 37, 38), true)
	p.Shape = Enum.PartType.Ball
	local fat = piece(m, "Gordura", Vector3.new(0.22, 1.15, 0.72) * scale, cf * CFrame.new(0.37 * scale, 0, 0), Enum.Material.SmoothPlastic, Color3.fromRGB(180, 143, 116), true)
	fat.Shape = Enum.PartType.Ball
	local bone = piece(m, "Osso", Vector3.new(0.22, 0.9, 0.22) * scale, cf * CFrame.new(0, 0.94 * scale, 0), Enum.Material.SmoothPlastic, Color3.fromRGB(191, 179, 144), true)
	bone.Shape = Enum.PartType.Ball
end

local function shelter(parent: Instance, cf: CFrame, width: number, depth: number, communal: boolean, index: number, rng: Random)
	local m = model(parent, if communal then "CasaComunal" else "Moradia_" .. index)
	m:SetAttribute("Construcao", "CabanaNativa")
	local h = if communal then 11.5 else 9.5
	local roofRise = if communal then 7 else 5.2
	local halfW, halfD = width / 2, depth / 2
	-- Piso baixo, tábuas individuais, fundação aparente e entrada de 6 studs.
	for j = 0, math.ceil(width / 1.5) - 1 do
		local x0 = -halfW + j * 1.5
		local w = math.min(1.5, halfW - x0)
		piece(m, "TabuaPiso", Vector3.new(w - 0.025, 0.45, depth), cf * CFrame.new(x0 + w / 2, 0.075, 0), Enum.Material.WoodPlanks, WOOD:Lerp(REED, rng:NextNumber(0, 0.25)))
	end
	for _, x in { -halfW, halfW } do
		for _, z in { -halfD, 0, halfD } do
			S.Beam(m, "Pilar", cf:PointToWorldSpace(Vector3.new(x, -2, z)), cf:PointToWorldSpace(Vector3.new(x, h + 0.3, z)), 0.65, Enum.Material.Wood, DARK)
			for _, y in { 1.1, h - 0.4 } do
				piece(m, "Amarracao", Vector3.new(0.8, 0.25, 0.8), cf * CFrame.new(x, y, z), Enum.Material.Fabric, ROPE, true)
			end
		end
	end
	S.WallWithOpenings(m, cf * CFrame.new(0, 0.3, -halfD), width, h - 0.3, 0.35, { { x0 = -3, x1 = 3, y0 = 0, y1 = 8 } }, Enum.Material.WoodPlanks, REED)
	S.WallWithOpenings(m, cf * CFrame.new(0, 0.3, halfD), width, h - 0.3, 0.35, {}, Enum.Material.WoodPlanks, REED)
	for _, side in { -1, 1 } do
		S.WallWithOpenings(m, cf * CFrame.new(side * halfW, 0.3, 0) * CFrame.Angles(0, math.pi / 2, 0), depth, h - 0.3, 0.35, { { x0 = -2.8, x1 = 2.8, y0 = 4.5, y1 = 7.3 } }, Enum.Material.WoodPlanks, REED)
		-- Trama horizontal e contraventamento deixam a construção legível de perto.
		for _, y in { 1.5, 3, 8 } do
			piece(m, "Trama", Vector3.new(0.15, 0.14, depth), cf * CFrame.new(side * (halfW + 0.21), y, 0), Enum.Material.Wood, DARK, true)
		end
		for _, z in { -halfD + 0.3, halfD - 0.3 } do
			S.Beam(m, "Escora", cf:PointToWorldSpace(Vector3.new(side * halfW, 2, z)), cf:PointToWorldSpace(Vector3.new(side * halfW, h - 1, z + (if z < 0 then 3 else -3))), 0.22, Enum.Material.Wood, DARK, false)
		end
	end
	-- Telhado inclinado aberto por baixo: sem disco atravessando o interior.
	local run = halfW + 1.5
	local rise = roofRise * run / halfW
	local pitch = math.atan2(rise, run)
	local slope = math.sqrt(run * run + rise * rise)
	for _, side in { -1, 1 } do
		for layer = 1, 6 do
			local f = (layer - 0.5) / 6
			piece(m, "PalhaEmCamadas", Vector3.new(slope / 6 + 0.22, 0.5, depth + 3), cf * CFrame.new(side * run * f, h + roofRise - rise * f, 0) * CFrame.Angles(0, 0, -side * pitch), Enum.Material.Grass, STRAW:Lerp(REED, layer / 15))
		end
		for j = 0, 4 do
			local z = -halfD + j * depth / 4
			S.Beam(m, "Caibro", cf:PointToWorldSpace(Vector3.new(0, h + roofRise - 0.4, z)), cf:PointToWorldSpace(Vector3.new(side * run, h + roofRise - rise - 0.4, z)), 0.3, Enum.Material.Wood, DARK, false)
		end
	end
	S.Beam(m, "Cumeeira", cf:PointToWorldSpace(Vector3.new(0, h + roofRise, -halfD - 1.8)), cf:PointToWorldSpace(Vector3.new(0, h + roofRise, halfD + 1.8)), 0.6, Enum.Material.Wood, DARK)
	for _, z in { -halfD, halfD } do
		for row = 1, 7 do
			local f = (row - 0.5) / 7
			piece(m, "TramaEmpena", Vector3.new(width * (1 - f), roofRise / 7 + 0.02, 0.22), cf * CFrame.new(0, h + roofRise * f, z), Enum.Material.WoodPlanks, REED, true)
		end
	end
	for _, x in { -3.5, 3.5 } do
		piece(m, "PosteVaranda", Vector3.new(0.45, 8.3, 0.45), cf * CFrame.new(x, 3.9, -halfD - 3), Enum.Material.Wood, DARK)
	end
	piece(m, "CoberturaEntrada", Vector3.new(8, 0.3, 4), cf * CFrame.new(0, 8.2, -halfD - 1.5) * CFrame.Angles(math.rad(-9), 0, 0), Enum.Material.Grass, STRAW)
	-- Móveis encostados nas laterais: corredor da porta até o fundo fica livre.
	for _, side in { -1, 1 } do
		for j = 1, (if communal then 2 else 1) do
			local z = if communal then -3 + (j - 1) * 8 else 2
			piece(m, "CamaMadeira", Vector3.new(3.2, 0.65, 6), cf * CFrame.new(side * (halfW - 2.4), 0.65, z), Enum.Material.Wood, DARK)
			piece(m, "Esteira", Vector3.new(3, 0.16, 5.8), cf * CFrame.new(side * (halfW - 2.4), 1.05, z), Enum.Material.Fabric, REED, true)
			piece(m, "Manta", Vector3.new(2.9, 0.12, 2.3), cf * CFrame.new(side * (halfW - 2.4), 1.18, z + 1.4), Enum.Material.Fabric, Color3.fromRGB(76, 67, 53), true)
		end
	end
	piece(m, "Prateleira", Vector3.new(width - 3, 0.3, 1.4), cf * CFrame.new(0, 2.4, halfD - 1), Enum.Material.Wood, DARK)
	for _, x in { -3, 3 } do S.Pot(m, cf * CFrame.new(x, 2.55, halfD - 1), 1) end
	S.LootPoint(m, cf * CFrame.new(0, 2.7, halfD - 1))
	S.SpawnPoint(m, cf * CFrame.new(0, 2.5, -halfD - 5))
	if communal then blood(m, cf * CFrame.new(-2, 0.31, 3), 1.4, rng, false) end
	return m
end

local function butcher(parent: Instance, cf: CFrame, rng: Random)
	local m = model(parent, "AreaPreparo")
	for _, x in { -4.5, 4.5 } do
		piece(m, "PosteSecador", Vector3.new(0.45, 7.5, 0.45), cf * CFrame.new(x, 3.6, 2.5), Enum.Material.Wood, DARK)
	end
	S.Beam(m, "VaraSecador", cf:PointToWorldSpace(Vector3.new(-5, 7, 2.5)), cf:PointToWorldSpace(Vector3.new(5, 7, 2.5)), 0.4, Enum.Material.Wood, WOOD)
	for i = 1, 5 do
		local x = -3.4 + (i - 1) * 1.7
		S.Beam(m, "Corda", cf:PointToWorldSpace(Vector3.new(x, 7, 2.5)), cf:PointToWorldSpace(Vector3.new(x, 5.5, 2.5)), 0.06, Enum.Material.Fabric, ROPE, false)
		meat(m, cf * CFrame.new(x, 4.5, 2.5) * CFrame.Angles(0, i * 0.7, 0.1), rng:NextNumber(0.75, 1.1))
	end
	piece(m, "MesaCorte", Vector3.new(7, 0.5, 3), cf * CFrame.new(0, 2.8, -1.5), Enum.Material.WoodPlanks, WOOD)
	for _, x in { -2.8, 2.8 } do
		for _, z in { -2.5, -0.5 } do piece(m, "PeMesa", Vector3.new(0.45, 2.7, 0.45), cf * CFrame.new(x, 1.35, z), Enum.Material.Wood, DARK) end
	end
	blood(m, cf * CFrame.new(-1, 3.07, -1.5), 1.1, rng, false)
	meat(m, cf * CFrame.new(1.5, 3.45, -1.4) * CFrame.Angles(0, 0, math.pi / 2), 0.65)
	S.LootPoint(m, cf * CFrame.new(2.6, 3.2, -1.5))
	blood(m, cf * CFrame.new(-1, 0, 1), 2.4, rng, true)
end

function NativeVillage.Build(parent: Instance, center: Vector3, seed: number)
	local rng = Random.new(seed + 557)
	parent:SetAttribute("VillageVersion", 2)
	parent:SetAttribute("CentroX", center.X)
	parent:SetAttribute("CentroZ", center.Z)
	-- Mesmo raio de clareira (50): amplia as casas sem deslocar outros POIs.
	local inward = math.atan2(-center.Z, -center.X)
	for i = 1, 6 do
		local a = inward + (i - 1) / 6 * TAU
		local pos = ground(center.X + math.cos(a) * 32, center.Z + math.sin(a) * 32, center.Y).Position
		local cf = CFrame.lookAt(pos, Vector3.new(center.X, pos.Y, center.Z))
		shelter(parent, cf, if i == 4 then 22 else 18, if i == 4 then 24 else 20, i == 4, i, rng)
	end
	local base = ground(center.X, center.Z, center.Y) * CFrame.Angles(0, -inward - math.pi / 2, 0)
	S.Totem(parent, base * CFrame.new(0, 0, 3), rng):SetAttribute("VilaGerada", true)
	S.FireCircle(parent, base * CFrame.new(-8, 0, -3), rng, false):SetAttribute("VilaGerada", true)
	butcher(parent, base * CFrame.new(7, 0, 4), rng)
	S.Canoe(parent, base * CFrame.new(-10, 0, 9) * CFrame.Angles(0, 0.4, 0)):SetAttribute("VilaGerada", true)
	for _, p in { Vector3.new(-10, 0, -8), Vector3.new(12, 0, -4), Vector3.new(-4, 0, 10) } do
		local cf = base * CFrame.new(p)
		S.Pot(parent, cf, rng:NextNumber(1, 1.5)):SetAttribute("VilaGerada", true)
	end
	-- Rastro descontínuo ao redor do preparo; sem bloquear passagem ou raycasts.
	for i = 1, 8 do blood(parent, base * CFrame.new(7 - i * 0.8, 0, 1 - i * 1.35), rng:NextNumber(0.25, 0.65), rng, true) end
	S.SpawnPoint(parent, base * CFrame.new(0, 2.5, -8)):SetAttribute("VilaGerada", true)
end

return NativeVillage
