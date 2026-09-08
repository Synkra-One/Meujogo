--!strict
--[[
	RaftGenerator
	Constrói a Jangada do objetivo de fuga e a zona de entrega "LocalJangada",
	no MEIO DA AREIA, virada para o mar aberto.

	DIFERENTE dos outros geradores da pasta Tools/: este NÃO usa
	InsertService/game:GetObjects -- é 100% Part primitiva. Por isso pode
	rodar em runtime sem cair em placeholder. server/RaftObjective.lua chama
	RaftGenerator.Build() sozinho no boot se a Jangada ainda não existir no
	Workspace; continua dando pra chamar na mão em modo de edição pra
	inspecionar/reposicionar e salvar.

		local Raft = require(game.ServerScriptService.Server.Tools.RaftGenerator)
		Raft.Build()          -- acha a praia, constrói e devolve o Model
		Raft.Build(seed)      -- outra seed muda qual trecho de praia é usado
		Raft.Clear()          -- remove a Jangada e a zona

	COMO A MONTAGEM FUNCIONA (quem toca nisso de verdade é RaftObjective):
	  Cada Part estrutural nasce com aparência de "planta baixa" (azul,
	  translúcida, sem colisão) e carrega nos Attributes o estado "construído"
	  de verdade:
	    EtapaConstrucao        number  -- 1..EtapasTotais; ordem de montagem
	    CorConstruida          Color3
	    MaterialConstruido     string  -- nome de Enum.Material
	    TransparenciaConstruida number
	    ColidivelConstruido    boolean
	  RaftObjective revela as peças conforme o progresso do objetivo sobe, e
	  volta todas pro estado de planta no Reset da rodada.

	ATRIBUTOS DO MODEL "Jangada":
	  DirecaoMar   Vector3  -- unit, aponta da praia pro mar (direção do empurrão)
	  EtapasTotais number
	  JangadaPronta boolean -- RaftObjective liga em 100%
	  PrimaryPart  = "Root" (Part invisível no centro do convés)

	A zona "LocalJangada" e a decoração do canteiro de obras ficam FORA do
	Model (numa Folder irmã), pra não viajarem junto quando a jangada é
	empurrada ao mar.
]]

local Workspace = game:GetService("Workspace")

local RaftGenerator = {}

local TAU = math.pi * 2

local FOLDER_NAME = "PraiaJangada"

local BP_COLOR = Color3.fromRGB(96, 172, 235)
local BP_TRANSPARENCY = 0.72

local COL = {
	WoodLight = Color3.fromRGB(126, 90, 54),
	WoodMid = Color3.fromRGB(104, 72, 43),
	WoodDark = Color3.fromRGB(78, 53, 33),
	Rope = Color3.fromRGB(196, 170, 120),
	Sail = Color3.fromRGB(226, 218, 198),
	Metal = Color3.fromRGB(70, 66, 62),
	Sand = Color3.fromRGB(214, 197, 156),
}

local currentSeed = 8123

--------------------------------------------------------------------------------
-- Achar o ponto de praia (meio da faixa de areia, com mar livre à frente)
--------------------------------------------------------------------------------

local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Include
rayParams.FilterDescendantsInstances = { Workspace.Terrain }
rayParams.IgnoreWater = true

local function groundAt(x: number, z: number): (number?, Enum.Material?)
	local result = Workspace:Raycast(Vector3.new(x, 400, z), Vector3.new(0, -900, 0), rayParams)
	if result then
		return result.Position.Y, result.Material
	end
	return nil, nil
end

type BeachSpot = { pos: Vector3, seaDir: Vector3 }

-- Varre radiais a partir do centro da ilha (origem). Numa radial, a faixa de
-- areia vai do "primeiro Sand" achado vindo de fora (borda d'água) até o
-- "último Sand" antes de virar grama (borda de terra). O ponto ideal é o
-- meio dessa faixa, se logo depois da borda d'água já for fundo (mar).
-- Ângulo do Acampamento (marcador Ilha/Layout/Acampamento, gravado por
-- PoiGenerator): a jangada prefere a praia mais perto dele, pra ficar a uma
-- trilha de distância e não "no meio do nada".
local function preferredAngle(): number
	local ilha = Workspace:FindFirstChild("Ilha")
	local layout = ilha and ilha:FindFirstChild("Layout")
	local camp = layout and layout:FindFirstChild("Acampamento")
	if camp and camp:IsA("BasePart") then
		local a = camp:GetAttribute("Angulo")
		if type(a) == "number" then
			return a
		end
		return math.atan2(camp.Position.Z, camp.Position.X)
	end
	return (currentSeed % 360) * math.pi / 180
end

local function findBeachSpot(): BeachSpot?
	local ANG_STEPS = 240
	local phase = preferredAngle()
	local STEP = 3
	local scanFrom = 960 -- >= IslandLayout.AreaHalf (sem require: este módulo roda em runtime)

	for i = 0, ANG_STEPS - 1 do
		-- Alterna +/- em volta do ângulo preferido: a primeira praia válida é a
		-- mais perto do acampamento.
		local k = (i + 1) // 2
		local sign = if i % 2 == 0 then 1 else -1
		local ang = phase + sign * (k / ANG_STEPS) * TAU
		local dx, dz = math.cos(ang), math.sin(ang)

		local firstSand: number? = nil
		local lastSand: number? = nil
		for r = scanFrom, 60, -STEP do
			local y, mat = groundAt(dx * r, dz * r)
			local isSand = y ~= nil and mat == Enum.Material.Sand and y > 0.4 and y < 10
			if isSand then
				firstSand = firstSand or r
				lastSand = r
			elseif firstSand and lastSand and (firstSand - r) > 6 then
				break -- já passou da faixa de areia indo pra terra
			end
		end

		if firstSand and lastSand and (firstSand - lastSand) >= 8 then
			-- Mar livre logo à frente da borda d'água?
			local aheadY = groundAt(dx * (firstSand + 12), dz * (firstSand + 12))
			if aheadY == nil or aheadY < 0.4 then
				local rMid = (firstSand + lastSand) * 0.5
				local px, pz = dx * rMid, dz * rMid
				local py = groundAt(px, pz) or 4
				return {
					pos = Vector3.new(px, py, pz),
					seaDir = Vector3.new(dx, 0, dz).Unit,
				}
			end
		end
	end

	return nil
end

--------------------------------------------------------------------------------
-- Parts
--------------------------------------------------------------------------------

type BuiltSpec = {
	Color: Color3,
	Material: string,
	Transparency: number?,
	CanCollide: boolean?,
	Shape: Enum.PartType?,
}

local function newPart(parent: Instance, name: string, size: Vector3, cframe: CFrame, step: number?, built: BuiltSpec?): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.CFrame = cframe
	p.Anchored = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth

	if built and built.Shape then
		p.Shape = built.Shape
	end

	if step and built then
		-- Nasce como planta baixa; RaftObjective revela.
		p.Transparency = BP_TRANSPARENCY
		p.Material = Enum.Material.SmoothPlastic
		p.Color = BP_COLOR
		p.CanCollide = false
		p.CastShadow = false
		p:SetAttribute("EtapaConstrucao", step)
		p:SetAttribute("CorConstruida", built.Color)
		p:SetAttribute("MaterialConstruido", built.Material)
		p:SetAttribute("TransparenciaConstruida", built.Transparency or 0)
		p:SetAttribute("ColidivelConstruido", built.CanCollide == true)
	elseif built then
		-- Decoração fixa (canteiro de obras): já nasce pronta.
		p.Color = built.Color
		p.Material = (Enum.Material :: any)[built.Material] or Enum.Material.Wood
		p.Transparency = built.Transparency or 0
		p.CanCollide = built.CanCollide == true
	end

	p.Parent = parent
	return p
end

-- Cilindro deitado ao longo do eixo local Z (troncos do convés).
local ALONG_Z = CFrame.Angles(0, math.pi / 2, 0)
-- Cilindro em pé (mastro, barril).
local UPRIGHT = CFrame.Angles(0, 0, math.pi / 2)

local function ropeBetween(parent: Instance, name: string, aWorld: Vector3, bWorld: Vector3, step: number?)
	local mid = (aWorld + bWorld) * 0.5
	local delta = bWorld - aWorld
	local len = delta.Magnitude
	if len < 0.05 then
		return
	end
	local right = delta.Unit
	local up = right:Cross(Vector3.new(0, 1, 0))
	if up.Magnitude < 1e-3 then
		up = Vector3.new(1, 0, 0)
	end
	up = up.Unit
	local cf = CFrame.fromMatrix(mid, right, up)
	newPart(parent, name, Vector3.new(len, 0.12, 0.12), cf, step, {
		Color = COL.Rope,
		Material = "SmoothPlastic",
		CanCollide = false,
		Shape = Enum.PartType.Cylinder,
	})
end

--------------------------------------------------------------------------------
-- Montagem da Jangada (espaço local: -Z aponta pro mar, +Z pra praia)
--------------------------------------------------------------------------------

local TOTAL_STEPS = 12

local function buildRaftModel(spot: BeachSpot, parent: Instance): Model
	local model = Instance.new("Model")
	model.Name = "Jangada"

	local origin = spot.pos + Vector3.new(0, 0.75, 0)
	local baseCF = CFrame.lookAt(origin, origin + spot.seaDir)

	local function L(x: number, y: number, z: number): CFrame
		return baseCF * CFrame.new(x, y, z)
	end
	local function worldOf(x: number, y: number, z: number): Vector3
		return (baseCF * CFrame.new(x, y, z)).Position
	end

	-- Root invisível: PrimaryPart e âncora do empurrão.
	local root = newPart(model, "Root", Vector3.new(7.6, 0.4, 13.2), L(0, 0.2, 0))
	root.Transparency = 1
	root.CanCollide = false
	root.CanQuery = false
	model.PrimaryPart = root

	-- 1..5 -- troncos do convés (do centro pra fora)
	local deckLogs = {
		{ x = 0, step = 1 },
		{ x = -1.5, step = 2 },
		{ x = 1.5, step = 3 },
		{ x = -3.0, step = 4 },
		{ x = 3.0, step = 5 },
	}
	for _, log in deckLogs do
		newPart(model, "ConvesTronco_" .. log.step, Vector3.new(13, 1.5, 1.5), L(log.x, 0, 0) * ALONG_Z, log.step, {
			Color = if log.step % 2 == 0 then COL.WoodMid else COL.WoodLight,
			Material = "Wood",
			CanCollide = true,
			Shape = Enum.PartType.Cylinder,
		})
	end

	-- 6 -- travessas amarradas
	for i, z in { -4.5, 0, 4.5 } do
		newPart(model, "Travessa_" .. i, Vector3.new(8.4, 0.28, 0.55), L(0, 0.9, z), 6, {
			Color = COL.Rope,
			Material = "WoodPlanks",
			CanCollide = false,
		})
	end

	-- 7 -- proa erguida
	for _, x in { -1.6, 1.6 } do
		newPart(
			model,
			"Proa_" .. (x < 0 and "E" or "D"),
			Vector3.new(5.5, 1.4, 1.4),
			L(x, 0.35, -6.4) * ALONG_Z * CFrame.Angles(0, 0, math.rad(18)),
			7,
			{ Color = COL.WoodDark, Material = "Wood", CanCollide = true, Shape = Enum.PartType.Cylinder }
		)
	end

	-- 8 -- popa: plataforma + leme
	newPart(model, "PopaPlataforma", Vector3.new(4.2, 0.35, 2.6), L(0, 0.95, 5.8), 8, {
		Color = COL.WoodMid,
		Material = "WoodPlanks",
		CanCollide = true,
	})
	newPart(model, "Leme", Vector3.new(2.6, 0.45, 0.45), L(0, 1.7, 6.4) * UPRIGHT, 8, {
		Color = COL.WoodDark,
		Material = "Wood",
		CanCollide = true,
		Shape = Enum.PartType.Cylinder,
	})
	newPart(model, "LemePa", Vector3.new(0.25, 1.8, 1.9), L(0, -0.2, 7.1) * CFrame.Angles(math.rad(-25), 0, 0), 8, {
		Color = COL.WoodDark,
		Material = "Wood",
		CanCollide = false,
	})

	-- 9 -- mastro
	newPart(model, "Mastro", Vector3.new(9.4, 0.7, 0.7), L(0, 4.7, -0.3) * UPRIGHT, 9, {
		Color = COL.WoodLight,
		Material = "Wood",
		CanCollide = true,
		Shape = Enum.PartType.Cylinder,
	})

	-- 10 -- verga + vela (dois panos levemente estufados)
	newPart(model, "Verga", Vector3.new(7.2, 0.34, 0.34), L(0, 8.7, -0.3), 10, {
		Color = COL.WoodLight,
		Material = "Wood",
		CanCollide = false,
		Shape = Enum.PartType.Cylinder,
	})
	newPart(model, "VelaCima", Vector3.new(6.6, 3.0, 0.12), L(0, 7.4, 0.05) * CFrame.Angles(math.rad(8), 0, 0), 10, {
		Color = COL.Sail,
		Material = "Fabric",
		Transparency = 0.03,
		CanCollide = false,
	})
	newPart(model, "VelaBaixo", Vector3.new(6.6, 3.0, 0.12), L(0, 4.7, -0.15) * CFrame.Angles(math.rad(-6), 0, 0), 10, {
		Color = COL.Sail,
		Material = "Fabric",
		Transparency = 0.03,
		CanCollide = false,
	})

	-- 11 -- cordame
	local mastTop = worldOf(0, 9.1, -0.3)
	ropeBetween(model, "Estai_Proa", mastTop, worldOf(0, 1.2, -7.4), 11)
	ropeBetween(model, "Estai_Popa", mastTop, worldOf(0, 2.6, 6.4), 11)
	ropeBetween(model, "Estai_Bombordo", mastTop, worldOf(-3.4, 0.9, 0), 11)
	ropeBetween(model, "Estai_Estibordo", mastTop, worldOf(3.4, 0.9, 0), 11)

	-- 12 -- suprimentos
	newPart(model, "Barril", Vector3.new(2.0, 1.5, 1.5), L(-2.2, 1.1, 3.2) * UPRIGHT, 12, {
		Color = COL.WoodDark,
		Material = "Wood",
		CanCollide = true,
		Shape = Enum.PartType.Cylinder,
	})
	newPart(model, "Caixa", Vector3.new(1.7, 1.6, 1.7), L(2.3, 1.0, 3.8) * CFrame.Angles(0, math.rad(20), 0), 12, {
		Color = COL.WoodMid,
		Material = "WoodPlanks",
		CanCollide = true,
	})
	newPart(model, "RoloCorda", Vector3.new(0.45, 1.4, 1.4), L(2.6, 0.95, -1.2) * UPRIGHT, 12, {
		Color = COL.Rope,
		Material = "SmoothPlastic",
		CanCollide = false,
		Shape = Enum.PartType.Cylinder,
	})
	local lantern = newPart(model, "Lampiao", Vector3.new(0.5, 0.75, 0.5), L(0, 1.5, -7.0), 12, {
		Color = COL.Metal,
		Material = "Metal",
		CanCollide = false,
	})
	local glow = Instance.new("PointLight")
	glow.Color = Color3.fromRGB(255, 170, 90)
	glow.Range = 15
	glow.Brightness = 1.4
	glow.Shadows = false
	glow.Enabled = false -- RaftObjective liga junto com a etapa 12
	glow.Parent = lantern

	model:SetAttribute("DirecaoMar", spot.seaDir)
	model:SetAttribute("EtapasTotais", TOTAL_STEPS)
	model:SetAttribute("JangadaPronta", false)

	model.Parent = parent
	return model
end

--------------------------------------------------------------------------------
-- Zona de entrega + canteiro de obras (fixos na praia, fora do Model)
--------------------------------------------------------------------------------

local function buildSite(spot: BeachSpot, parent: Instance)
	local origin = spot.pos + Vector3.new(0, 0.75, 0)
	local baseCF = CFrame.lookAt(origin, origin + spot.seaDir)
	local function L(x: number, y: number, z: number): CFrame
		return baseCF * CFrame.new(x, y, z)
	end

	-- Zona de entrega: atrás da popa, do lado da terra. RaftObjective conecta
	-- o .Touched dela.
	local zone = Instance.new("Part")
	zone.Name = "LocalJangada"
	zone.Size = Vector3.new(13, 3.5, 7)
	zone.CFrame = L(0, 1.0, 8.5)
	zone.Anchored = true
	zone.CanCollide = false
	zone.CanQuery = false
	zone.Transparency = 0.86
	zone.Material = Enum.Material.Sand
	zone.Color = COL.Sand
	zone.Parent = parent

	-- Estacas de canto + corda de perímetro.
	local corners = {
		L(-6.2, 0.3, 5.2),
		L(6.2, 0.3, 5.2),
		L(-6.2, 0.3, 11.6),
		L(6.2, 0.3, 11.6),
	}
	local stakeTops: { Vector3 } = {}
	for i, cf in corners do
		local stake = Instance.new("Part")
		stake.Name = "Estaca_" .. i
		stake.Shape = Enum.PartType.Cylinder
		stake.Size = Vector3.new(1.7, 0.3, 0.3)
		stake.CFrame = cf * UPRIGHT
		stake.Anchored = true
		stake.CanCollide = false
		stake.Material = Enum.Material.Wood
		stake.Color = COL.WoodDark
		stake.Parent = parent
		table.insert(stakeTops, cf.Position + Vector3.new(0, 0.7, 0))
	end
	for i = 1, #stakeTops do
		local a = stakeTops[i]
		local b = stakeTops[i % #stakeTops + 1]
		ropeBetween(parent, "CordaObra_" .. i, a, b, nil)
	end

	-- Pilha de tábuas (dá o "material bruto" ao lado da obra).
	for i = 1, 3 do
		local plank = Instance.new("Part")
		plank.Name = "TabuaBruta_" .. i
		plank.Size = Vector3.new(4.5, 0.4, 1.1)
		plank.CFrame = L(4.6, 0.2 + (i - 1) * 0.42, 9.6) * CFrame.Angles(0, math.rad(6 * i), 0)
		plank.Anchored = true
		plank.CanCollide = true
		plank.Material = Enum.Material.WoodPlanks
		plank.Color = COL.WoodLight
		plank.Parent = parent
	end

	-- Placa da obra.
	local post = Instance.new("Part")
	post.Name = "PlacaPoste"
	post.Size = Vector3.new(0.35, 4.5, 0.35)
	post.CFrame = L(-5.6, 1.6, 10.2)
	post.Anchored = true
	post.CanCollide = false
	post.Material = Enum.Material.Wood
	post.Color = COL.WoodDark
	post.Parent = parent

	local board = Instance.new("Part")
	board.Name = "PlacaTabua"
	board.Size = Vector3.new(4.6, 1.8, 0.2)
	board.CFrame = L(-5.6, 3.6, 10.2) * CFrame.Angles(0, math.rad(18), 0)
	board.Anchored = true
	board.CanCollide = false
	board.Material = Enum.Material.WoodPlanks
	board.Color = COL.WoodLight
	board.Parent = parent

	local surface = Instance.new("SurfaceGui")
	surface.Face = Enum.NormalId.Front
	surface.CanvasSize = Vector2.new(460, 180)
	surface.Parent = board
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamBold
	label.TextScaled = true
	label.TextColor3 = Color3.fromRGB(40, 28, 16)
	label.Text = "JANGADA\nMadeira \u{2022} Corda \u{2022} Lona"
	label.Parent = surface
end

--------------------------------------------------------------------------------
-- API
--------------------------------------------------------------------------------

local function getParentFolder(): Instance
	local ilha = Workspace:FindFirstChild("Ilha")
	local host: Instance = ilha or Workspace
	local existing = host:FindFirstChild(FOLDER_NAME)
	if existing then
		existing:Destroy()
	end
	local folder = Instance.new("Folder")
	folder.Name = FOLDER_NAME
	folder.Parent = host
	return folder
end

function RaftGenerator.SetSeed(seed: number)
	currentSeed = seed
end

--[[
	Clear()
	Remove a Folder PraiaJangada (Jangada + zona + canteiro) e qualquer
	instância solta "Jangada"/"LocalJangada" fora dela.
]]
function RaftGenerator.Clear()
	for _, host in { Workspace, Workspace:FindFirstChild("Ilha") } do
		if host then
			for _, name in { FOLDER_NAME, "Jangada", "LocalJangada" } do
				local found = host:FindFirstChild(name)
				if found then
					found:Destroy()
				end
			end
		end
	end
end

--[[
	Build(seed?)
	Acha o meio de uma faixa de praia, constrói a Jangada (estado de planta
	baixa) + a zona LocalJangada + o canteiro de obras. Devolve o Model
	"Jangada", ou nil se não achou praia nenhuma.
]]
function RaftGenerator.Build(seed: number?): Model?
	if seed then
		currentSeed = seed
	end

	local spot = findBeachSpot()
	if not spot then
		warn("[RaftGenerator] Não achei nenhuma faixa de areia com mar livre à frente -- gere a ilha primeiro (IslandGenerator.Generate()).")
		return nil
	end

	RaftGenerator.Clear()
	local folder = getParentFolder()

	local model = buildRaftModel(spot, folder)
	buildSite(spot, folder)

	print(string.format(
		"[RaftGenerator] Jangada montada em (%.0f, %.0f, %.0f), proa pro mar em (%.2f, %.2f).",
		spot.pos.X, spot.pos.Y, spot.pos.Z, spot.seaDir.X, spot.seaDir.Z
	))

	return model
end

return RaftGenerator
