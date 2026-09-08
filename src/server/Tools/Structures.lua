--!strict
--[[
	Structures
	Construções e props em Part primitiva pros POIs da ilha (estilo
	acampamento do Friday the 13th): cabana, lodge, celeiro, casa de barcos,
	píer, barco, torre de vigia, farol, fogueira, mesa de piquenique, lampião
	de trilha, alvo de arco, fardo de feno, secador de peixe, canoa, cabana
	nativa, totem, e vegetação rasteira (arbusto, tronco caído).

	CONVENÇÃO DE ESPAÇO: toda função recebe `cf` = centro da construção NO
	CHÃO, com LookVector = FRENTE (-Z local). +X = direita, +Y = cima.
	Tudo Anchored. Nada aqui depende de asset -- roda em runtime.

	MARCADORES (Parts invisíveis com Attribute, lidos pelos sistemas):
	  PontoLoot = true   -- ItemSpawner/LootCrateSystem: loot nasce aqui
	  SpawnArma = true   -- WeaponSpawner: arma de fogo/munição nasce aqui
	  SpawnPOI  = true   -- LobbyManager: sobrevivente pode começar aqui
	  Porta     = true   -- DoorSystem: porta que abre/fecha (CFrameFechada,
	                        LarguraPorta gravados junto)

	Uso:
		local S = require(script.Parent.Structures)
		S.Cabin(folder, CFrame.new(x, y, z), { Name = "Cabana_1" })
]]

local Structures = {}

local TAU = math.pi * 2

local COL = {
	Plank = Color3.fromRGB(122, 88, 54),
	PlankDark = Color3.fromRGB(92, 64, 38),
	Log = Color3.fromRGB(104, 72, 43),
	LogDark = Color3.fromRGB(70, 48, 30),
	Roof = Color3.fromRGB(64, 52, 44),
	Stone = Color3.fromRGB(112, 110, 104),
	StoneDark = Color3.fromRGB(80, 78, 74),
	Rope = Color3.fromRGB(196, 170, 120),
	Fabric = Color3.fromRGB(150, 130, 100),
	Mattress = Color3.fromRGB(196, 190, 170),
	Metal = Color3.fromRGB(70, 66, 62),
	Straw = Color3.fromRGB(205, 172, 92),
	Thatch = Color3.fromRGB(176, 146, 80),
	Leaf = Color3.fromRGB(48, 96, 40),
	LeafDark = Color3.fromRGB(34, 74, 30),
	White = Color3.fromRGB(226, 222, 212),
	Red = Color3.fromRGB(150, 44, 38),
	Blue = Color3.fromRGB(52, 88, 150),
	Gold = Color3.fromRGB(230, 190, 60),
	Glass = Color3.fromRGB(190, 220, 235),
}
Structures.Colors = COL

local UPRIGHT = CFrame.Angles(0, 0, math.pi / 2) -- cilindro em pé
local ALONG_Z = CFrame.Angles(0, math.pi / 2, 0) -- cilindro deitado no eixo Z

--------------------------------------------------------------------------------
-- Primitivas
--------------------------------------------------------------------------------

type PartOpts = {
	Shape: Enum.PartType?,
	CanCollide: boolean?,
	Transparency: number?,
	CastShadow: boolean?,
}

local function part(parent: Instance, name: string, size: Vector3, cf: CFrame, material: Enum.Material, color: Color3, opts: PartOpts?): Part
	local p = Instance.new("Part")
	p.Name = name
	if opts and opts.Shape then
		p.Shape = opts.Shape
	end
	p.Size = size
	p.CFrame = cf
	p.Anchored = true
	p.Material = material
	p.Color = color
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	if opts then
		if opts.CanCollide ~= nil then
			p.CanCollide = opts.CanCollide
		end
		if opts.Transparency then
			p.Transparency = opts.Transparency
		end
		if opts.CastShadow ~= nil then
			p.CastShadow = opts.CastShadow
		end
	end
	p.Parent = parent
	return p
end
Structures.Part = part

local function wedge(parent: Instance, name: string, size: Vector3, cf: CFrame, material: Enum.Material, color: Color3): WedgePart
	local w = Instance.new("WedgePart")
	w.Name = name
	w.Size = size
	w.CFrame = cf
	w.Anchored = true
	w.Material = material
	w.Color = color
	w.TopSurface = Enum.SurfaceType.Smooth
	w.BottomSurface = Enum.SurfaceType.Smooth
	w.Parent = parent
	return w
end

-- Viga cilíndrica entre dois pontos do mundo.
local function beam(parent: Instance, name: string, a: Vector3, b: Vector3, dia: number, material: Enum.Material, color: Color3, collide: boolean?): Part?
	local delta = b - a
	local len = delta.Magnitude
	if len < 0.05 then
		return nil
	end
	local right = delta.Unit
	local up = right:Cross(Vector3.new(0, 1, 0))
	if up.Magnitude < 1e-3 then
		up = Vector3.new(1, 0, 0)
	end
	up = up.Unit
	local cf = CFrame.fromMatrix((a + b) * 0.5, right, up)
	return part(parent, name, Vector3.new(len, dia, dia), cf, material, color, { Shape = Enum.PartType.Cylinder, CanCollide = collide ~= false })
end
Structures.Beam = beam

local function marker(parent: Instance, name: string, cf: CFrame, attrs: { [string]: any }): Part
	local m = part(parent, name, Vector3.new(1, 1, 1), cf, Enum.Material.SmoothPlastic, Color3.new(1, 1, 1), { CanCollide = false, Transparency = 1, CastShadow = false })
	m.CanQuery = false
	m.CanTouch = false
	for k, v in attrs do
		m:SetAttribute(k, v)
	end
	return m
end
Structures.Marker = marker

function Structures.LootPoint(parent: Instance, cf: CFrame, weapon: boolean?): Part
	local attrs: { [string]: any } = { PontoLoot = true }
	if weapon then
		attrs.SpawnArma = true
	end
	return marker(parent, "PontoLoot", cf, attrs)
end

function Structures.SpawnPoint(parent: Instance, cf: CFrame): Part
	return marker(parent, "SpawnPOI", cf, { SpawnPOI = true })
end

local function pointLight(parentPart: BasePart, color: Color3, range: number, brightness: number, enabled: boolean): PointLight
	local light = Instance.new("PointLight")
	light.Color = color
	light.Range = range
	light.Brightness = brightness
	light.Shadows = false
	light.Enabled = enabled
	light.Parent = parentPart
	return light
end

local function newModel(parent: Instance, name: string): Model
	local m = Instance.new("Model")
	m.Name = name
	m.Parent = parent
	return m
end

--------------------------------------------------------------------------------
-- Paredes com aberturas
--------------------------------------------------------------------------------

export type Opening = { x0: number, x1: number, y0: number, y1: number }

--[[
	WallWithOpenings(parent, baseCF, length, height, thickness, openings, material, color)
	baseCF = centro da BASE da parede (chão), X local = ao longo da parede,
	Z local = espessura. Aberturas em coordenadas locais da parede (x de
	-length/2 a length/2, y de 0 a height). Gera o mínimo de Parts: cheias
	entre aberturas, e "abaixo"/"acima" de cada abertura.
]]
local function wallWithOpenings(
	parent: Instance,
	baseCF: CFrame,
	length: number,
	height: number,
	thickness: number,
	openings: { Opening },
	material: Enum.Material,
	color: Color3
)
	local function strip(x0: number, x1: number, y0: number, y1: number)
		local w, h = x1 - x0, y1 - y0
		if w <= 0.02 or h <= 0.02 then
			return
		end
		part(parent, "Parede", Vector3.new(w, h, thickness), baseCF * CFrame.new((x0 + x1) / 2, (y0 + y1) / 2, 0), material, color)
	end

	local sorted = table.clone(openings)
	table.sort(sorted, function(a, b)
		return a.x0 < b.x0
	end)

	local cursor = -length / 2
	for _, o in sorted do
		local x0 = math.max(o.x0, cursor)
		local x1 = math.min(o.x1, length / 2)
		if x1 <= x0 then
			continue
		end
		strip(cursor, x0, 0, height)
		strip(x0, x1, 0, o.y0)
		strip(x0, x1, o.y1, height)
		cursor = x1
	end
	strip(cursor, length / 2, 0, height)
end
Structures.WallWithOpenings = wallWithOpenings

--------------------------------------------------------------------------------
-- Telhado de duas águas + empenas
--------------------------------------------------------------------------------

local function gableRoof(parent: Instance, cf: CFrame, width: number, depth: number, wallTop: number, pitchDeg: number, overhang: number, color: Color3?)
	local p = math.rad(pitchDeg)
	local rise = (width / 2) * math.tan(p)
	local runOut = width / 2 + overhang
	local slabLen = runOut / math.cos(p)
	local drop = overhang * math.tan(p)
	local roofColor = color or COL.Roof

	local cy = wallTop + rise / 2 - drop / 2
	-- Esquerda: sobe do beiral (x negativo) até a cumeeira.
	part(parent, "TelhadoE", Vector3.new(slabLen, 0.45, depth + overhang * 2), cf * CFrame.new(-runOut / 2, cy, 0) * CFrame.Angles(0, 0, p), Enum.Material.WoodPlanks, roofColor)
	part(parent, "TelhadoD", Vector3.new(slabLen, 0.45, depth + overhang * 2), cf * CFrame.new(runOut / 2, cy, 0) * CFrame.Angles(0, 0, -p), Enum.Material.WoodPlanks, roofColor)
	-- Cumeeira.
	part(parent, "Cumeeira", Vector3.new(0.7, 0.5, depth + overhang * 2), cf * CFrame.new(0, wallTop + rise + 0.1, 0), Enum.Material.Wood, COL.LogDark)

	-- Empenas (WedgePart: face vertical em +Z local; a rampa desce pra -Z).
	-- Metade direita quer o lado alto no centro -> +Z local aponta pra -X.
	for _, zSide in { -1, 1 } do
		local z = zSide * (depth / 2 - 0.3)
		wedge(parent, "Empena", Vector3.new(0.6, rise, width / 2), cf * CFrame.new(width / 4, wallTop + rise / 2, z) * CFrame.Angles(0, -math.pi / 2, 0), Enum.Material.WoodPlanks, COL.PlankDark)
		wedge(parent, "Empena", Vector3.new(0.6, rise, width / 2), cf * CFrame.new(-width / 4, wallTop + rise / 2, z) * CFrame.Angles(0, math.pi / 2, 0), Enum.Material.WoodPlanks, COL.PlankDark)
	end
end
Structures.GableRoof = gableRoof

--------------------------------------------------------------------------------
-- Porta (DoorSystem cuida de abrir/fechar)
--------------------------------------------------------------------------------

local function door(parent: Instance, cf: CFrame, width: number, height: number)
	local d = part(parent, "Porta", Vector3.new(width, height, 0.3), cf, Enum.Material.WoodPlanks, COL.PlankDark)
	d:SetAttribute("Porta", true)
	d:SetAttribute("PortaAberta", false)
	d:SetAttribute("CFrameFechada", cf)
	d:SetAttribute("LarguraPorta", width)
	-- Maçaneta.
	part(parent, "Macaneta", Vector3.new(0.25, 0.25, 0.5), cf * CFrame.new(width / 2 - 0.6, 0, 0), Enum.Material.Metal, COL.Metal, { CanCollide = false })
	return d
end
Structures.Door = door

--------------------------------------------------------------------------------
-- Móveis
--------------------------------------------------------------------------------

local function bed(parent: Instance, cf: CFrame)
	part(parent, "CamaEstrutura", Vector3.new(4, 1.1, 7), cf * CFrame.new(0, 0.55, 0), Enum.Material.Wood, COL.PlankDark)
	part(parent, "CamaColchao", Vector3.new(3.6, 0.5, 6.4), cf * CFrame.new(0, 1.35, 0), Enum.Material.Fabric, COL.Mattress, { CanCollide = false })
	part(parent, "CamaTravesseiro", Vector3.new(2.4, 0.4, 1.2), cf * CFrame.new(0, 1.8, -2.3), Enum.Material.Fabric, Color3.fromRGB(220, 216, 205), { CanCollide = false })
	part(parent, "CamaCobertor", Vector3.new(3.6, 0.2, 3.6), cf * CFrame.new(0, 1.7, 1.4), Enum.Material.Fabric, COL.Fabric, { CanCollide = false })
end

local function wardrobe(parent: Instance, cf: CFrame)
	part(parent, "Armario", Vector3.new(3.4, 6.6, 1.7), cf * CFrame.new(0, 3.3, 0), Enum.Material.WoodPlanks, COL.PlankDark)
	part(parent, "ArmarioPortaE", Vector3.new(1.55, 6.2, 0.12), cf * CFrame.new(-0.85, 3.3, -0.92), Enum.Material.WoodPlanks, COL.Plank, { CanCollide = false })
	part(parent, "ArmarioPortaD", Vector3.new(1.55, 6.2, 0.12), cf * CFrame.new(0.85, 3.3, -0.92), Enum.Material.WoodPlanks, COL.Plank, { CanCollide = false })
	Structures.LootPoint(parent, cf * CFrame.new(0, 3, 0))
end

local function table_(parent: Instance, cf: CFrame, len: number, lit: boolean)
	part(parent, "MesaTampo", Vector3.new(len, 0.3, 2.8), cf * CFrame.new(0, 2.75, 0), Enum.Material.WoodPlanks, COL.Plank)
	for _, sx in { -1, 1 } do
		for _, sz in { -1, 1 } do
			part(parent, "MesaPe", Vector3.new(0.35, 2.6, 0.35), cf * CFrame.new(sx * (len / 2 - 0.5), 1.3, sz * 1.1), Enum.Material.Wood, COL.PlankDark, { CanCollide = false })
		end
	end
	local lantern = part(parent, "Lampiao", Vector3.new(0.6, 0.9, 0.6), cf * CFrame.new(len / 4, 3.35, 0.4), Enum.Material.Metal, COL.Metal, { CanCollide = false })
	local glass = part(parent, "LampiaoVidro", Vector3.new(0.4, 0.5, 0.4), cf * CFrame.new(len / 4, 3.35, 0.4), if lit then Enum.Material.Neon else Enum.Material.Glass, if lit then Color3.fromRGB(255, 190, 110) else COL.Glass, { CanCollide = false })
	glass.Transparency = if lit then 0 else 0.4
	pointLight(lantern, Color3.fromRGB(255, 170, 90), 18, 0.8, lit)
	Structures.LootPoint(parent, cf * CFrame.new(-len / 4, 3.2, 0))
end

local function bench(parent: Instance, cf: CFrame, len: number)
	part(parent, "Banco", Vector3.new(len, 0.3, 1.1), cf * CFrame.new(0, 1.45, 0), Enum.Material.WoodPlanks, COL.Plank)
	part(parent, "BancoPe", Vector3.new(0.3, 1.3, 1.0), cf * CFrame.new(-len / 2 + 0.5, 0.65, 0), Enum.Material.Wood, COL.PlankDark, { CanCollide = false })
	part(parent, "BancoPe", Vector3.new(0.3, 1.3, 1.0), cf * CFrame.new(len / 2 - 0.5, 0.65, 0), Enum.Material.Wood, COL.PlankDark, { CanCollide = false })
end

local function shelf(parent: Instance, cf: CFrame)
	part(parent, "Prateleira", Vector3.new(0.4, 0.25, 4.2), cf * CFrame.new(0, 5.0, 0), Enum.Material.WoodPlanks, COL.Plank, { CanCollide = false })
	part(parent, "Prateleira", Vector3.new(0.4, 0.25, 4.2), cf * CFrame.new(0, 3.4, 0), Enum.Material.WoodPlanks, COL.Plank, { CanCollide = false })
	part(parent, "PrateleiraCaixa", Vector3.new(0.9, 0.8, 1.0), cf * CFrame.new(0.3, 3.95, -1.0), Enum.Material.WoodPlanks, COL.PlankDark, { CanCollide = false })
	part(parent, "PrateleiraGarrafa", Vector3.new(0.3, 0.9, 0.3), cf * CFrame.new(0.3, 5.6, 0.8), Enum.Material.Glass, Color3.fromRGB(90, 130, 90), { CanCollide = false, Shape = Enum.PartType.Cylinder })
	Structures.LootPoint(parent, cf * CFrame.new(0.8, 4.4, 0))
end

local function crate(parent: Instance, cf: CFrame, s: number)
	part(parent, "Caixote", Vector3.new(s, s * 0.9, s), cf * CFrame.new(0, s * 0.45, 0), Enum.Material.WoodPlanks, COL.Plank)
end

--------------------------------------------------------------------------------
-- CABANA
--------------------------------------------------------------------------------

export type CabinOpts = {
	Name: string?,
	Width: number?,
	Depth: number?,
	WallHeight: number?,
	Windows: boolean?,
	Furniture: boolean?,
	OpenFront: boolean?,
	Door: boolean?,
	Lit: boolean?,
	Weapon: boolean?,
	Spawn: boolean?,
	Pitch: number?,
}

--[[
	Cabin(parent, cf, opts) -> Model
	Cabana de madeira em escala real: piso sobre pilares de pedra, paredes
	de tábua com troncos nos cantos, porta na frente (abre via DoorSystem),
	janelas vazadas, telhado de duas águas. Com Furniture: cama, armário
	(PontoLoot), mesa com lampião (PontoLoot), banco, prateleira (PontoLoot),
	caixote. SpawnPOI na frente da porta.
]]
function Structures.Cabin(parent: Instance, cf: CFrame, opts: CabinOpts?): Model
	local o = opts or {}
	local W = o.Width or 16
	local D = o.Depth or 14
	local H = o.WallHeight or 8.5
	local windows = o.Windows ~= false
	local furniture = o.Furniture ~= false
	local hasDoor = o.Door ~= false and not o.OpenFront
	local lit = o.Lit == true
	local pitch = o.Pitch or 30
	local thickness = 0.6
	local floorY = 1.0

	local model = newModel(parent, o.Name or "Cabana")

	-- Pilares + piso.
	for _, sx in { -1, 1 } do
		for _, sz in { -1, 1 } do
			part(model, "Pilar", Vector3.new(1.3, floorY, 1.3), cf * CFrame.new(sx * (W / 2 - 1), floorY / 2, sz * (D / 2 - 1)), Enum.Material.Slate, COL.StoneDark)
		end
	end
	part(model, "Piso", Vector3.new(W + 0.4, 0.5, D + 0.4), cf * CFrame.new(0, floorY - 0.25, 0), Enum.Material.WoodPlanks, COL.PlankDark)

	-- Degrau da porta.
	if hasDoor then
		part(model, "Degrau", Vector3.new(5, 0.5, 1.6), cf * CFrame.new(0, 0.25, -D / 2 - 0.9), Enum.Material.WoodPlanks, COL.PlankDark)
	end

	-- Paredes.
	local doorW, doorH = 4.4, 7
	local winY0, winY1, winHalf = 3.4, 6.2, 1.5

	local front: { Opening } = {}
	if o.OpenFront then
		table.insert(front, { x0 = -W / 2 + 1.2, x1 = W / 2 - 1.2, y0 = 0, y1 = H - 1.4 })
	else
		if hasDoor then
			table.insert(front, { x0 = -doorW / 2, x1 = doorW / 2, y0 = 0, y1 = doorH })
		end
		if windows then
			table.insert(front, { x0 = W / 4 + 0.6 - winHalf, x1 = W / 4 + 0.6 + winHalf, y0 = winY0, y1 = winY1 })
		end
	end
	wallWithOpenings(model, cf * CFrame.new(0, floorY, -D / 2), W, H, thickness, front, Enum.Material.WoodPlanks, COL.Plank)

	local back: { Opening } = {}
	if windows then
		table.insert(back, { x0 = -winHalf, x1 = winHalf, y0 = winY0, y1 = winY1 })
	end
	wallWithOpenings(model, cf * CFrame.new(0, floorY, D / 2), W, H, thickness, back, Enum.Material.WoodPlanks, COL.Plank)

	local side: { Opening } = {}
	if windows then
		table.insert(side, { x0 = -D / 6 - winHalf, x1 = -D / 6 + winHalf, y0 = winY0, y1 = winY1 })
	end
	wallWithOpenings(model, cf * CFrame.new(-W / 2, floorY, 0) * CFrame.Angles(0, math.pi / 2, 0), D, H, thickness, side, Enum.Material.WoodPlanks, COL.Plank)
	wallWithOpenings(model, cf * CFrame.new(W / 2, floorY, 0) * CFrame.Angles(0, math.pi / 2, 0), D, H, thickness, side, Enum.Material.WoodPlanks, COL.Plank)

	-- Troncos nos cantos.
	for _, sx in { -1, 1 } do
		for _, sz in { -1, 1 } do
			part(model, "Canto", Vector3.new(H + 0.4, 1.1, 1.1), cf * CFrame.new(sx * W / 2, floorY + H / 2, sz * D / 2) * UPRIGHT, Enum.Material.Wood, COL.LogDark, { Shape = Enum.PartType.Cylinder, CanCollide = false })
		end
	end

	-- Telhado.
	gableRoof(model, cf, W, D, floorY + H, pitch, 1.3)

	-- Porta.
	if hasDoor then
		door(model, cf * CFrame.new(0, floorY + doorH / 2, -D / 2), doorW - 0.2, doorH - 0.15)
	end

	-- Móveis.
	if furniture then
		bed(model, cf * CFrame.new(-W / 2 + 2.6, floorY, D / 2 - 4.2))
		wardrobe(model, cf * CFrame.new(W / 2 - 2.2, floorY, D / 2 - 1.2) * CFrame.Angles(0, math.pi, 0))
		table_(model, cf * CFrame.new(W / 4 - 0.5, floorY, -1.0), 4.5, lit)
		bench(model, cf * CFrame.new(W / 4 - 0.5, floorY, 1.2), 4.5)
		shelf(model, cf * CFrame.new(-W / 2 + 0.6, floorY, -D / 4))
		crate(model, cf * CFrame.new(-W / 2 + 1.6, floorY, -D / 2 + 1.6), 1.6)
	end

	if o.Weapon then
		Structures.LootPoint(model, cf * CFrame.new(0, floorY + 1.5, 0), true)
	end
	if o.Spawn ~= false then
		Structures.SpawnPoint(model, cf * CFrame.new(0, 2, -D / 2 - 5))
	end

	model:SetAttribute("Construcao", "Cabana")
	return model
end

--------------------------------------------------------------------------------
-- LODGE (a construção grande do acampamento)
--------------------------------------------------------------------------------

function Structures.Lodge(parent: Instance, cf: CFrame): Model
	local W, D, H = 34, 24, 10.5
	local floorY = 1.0
	local model = Structures.Cabin(parent, cf, {
		Name = "Lodge",
		Width = W,
		Depth = D,
		WallHeight = H,
		Furniture = false,
		Lit = true,
		Pitch = 28,
		Spawn = false,
	})

	-- Varanda na frente.
	part(model, "Varanda", Vector3.new(W + 4, 0.5, 7), cf * CFrame.new(0, floorY - 0.25, -D / 2 - 3.5), Enum.Material.WoodPlanks, COL.PlankDark)
	part(model, "VarandaDegrau", Vector3.new(8, 0.5, 1.6), cf * CFrame.new(0, 0.25, -D / 2 - 7.8), Enum.Material.WoodPlanks, COL.PlankDark)
	for _, x in { -W / 2 - 1, -W / 6, W / 6, W / 2 + 1 } do
		part(model, "VarandaPoste", Vector3.new(0.7, H - 1, 0.7), cf * CFrame.new(x, floorY + (H - 1) / 2, -D / 2 - 6.5), Enum.Material.Wood, COL.LogDark)
	end
	part(model, "VarandaTelhado", Vector3.new(W + 6, 0.4, 8.5), cf * CFrame.new(0, floorY + H - 0.9, -D / 2 - 3.8) * CFrame.Angles(math.rad(-10), 0, 0), Enum.Material.WoodPlanks, COL.Roof)
	-- Corrimão.
	for _, sx in { -1, 1 } do
		part(model, "Corrimao", Vector3.new(0.3, 0.3, 6.6), cf * CFrame.new(sx * (W / 2 + 1.7), floorY + 2.6, -D / 2 - 3.5), Enum.Material.Wood, COL.PlankDark, { CanCollide = false })
	end

	-- Divisórias internas: parede com duas passagens separando os quartos
	-- do salão, e uma divisória entre os dois quartos.
	local partitionZ = D / 2 - 9
	wallWithOpenings(model, cf * CFrame.new(0, floorY, partitionZ), W - 1.2, H - 0.5, 0.5, {
		{ x0 = -W / 4 - 2.2, x1 = -W / 4 + 2.2, y0 = 0, y1 = 7 },
		{ x0 = W / 4 - 2.2, x1 = W / 4 + 2.2, y0 = 0, y1 = 7 },
	}, Enum.Material.WoodPlanks, COL.PlankDark)
	part(model, "Divisoria", Vector3.new(0.5, H - 0.5, 9 - 0.6), cf * CFrame.new(0, floorY + (H - 0.5) / 2, partitionZ + 4.5), Enum.Material.WoodPlanks, COL.PlankDark)

	-- Quartos.
	for _, sx in { -1, 1 } do
		bed(model, cf * CFrame.new(sx * (W / 2 - 3.2), floorY, D / 2 - 4.4))
		wardrobe(model, cf * CFrame.new(sx * (W / 4 - 5.5), floorY, D / 2 - 1.2) * CFrame.Angles(0, math.pi, 0))
		Structures.SpawnPoint(model, cf * CFrame.new(sx * W / 4, 2, partitionZ - 3))
	end

	-- Salão: lareira na parede esquerda, mesa comprida no centro.
	local fireCF = cf * CFrame.new(-W / 2 + 1.0, floorY, -D / 4)
	part(model, "Lareira", Vector3.new(1.8, 6.5, 6), fireCF * CFrame.new(0, 3.25, 0), Enum.Material.Cobblestone, COL.Stone)
	part(model, "LareiraBoca", Vector3.new(0.6, 3, 3.4), fireCF * CFrame.new(0.7, 1.7, 0), Enum.Material.Slate, Color3.fromRGB(30, 28, 28), { CanCollide = false })
	local ember = part(model, "LareiraBrasa", Vector3.new(0.3, 0.4, 2.4), fireCF * CFrame.new(0.9, 0.5, 0), Enum.Material.Neon, Color3.fromRGB(255, 110, 40), { CanCollide = false })
	pointLight(ember, Color3.fromRGB(255, 130, 50), 16, 0.6, true)
	part(model, "Chamine", Vector3.new(2.2, H + 9, 2.4), cf * CFrame.new(-W / 2 - 0.6, floorY + (H + 9) / 2, -D / 4), Enum.Material.Cobblestone, COL.StoneDark)

	table_(model, cf * CFrame.new(3, floorY, -D / 4 + 1), 10, true)
	bench(model, cf * CFrame.new(3, floorY, -D / 4 - 1.3), 9)
	bench(model, cf * CFrame.new(3, floorY, -D / 4 + 3.3), 9)
	shelf(model, cf * CFrame.new(W / 2 - 0.6, floorY, -D / 4) * CFrame.Angles(0, math.pi, 0))
	shelf(model, cf * CFrame.new(W / 2 - 0.6, floorY, -D / 4 + 5) * CFrame.Angles(0, math.pi, 0))
	crate(model, cf * CFrame.new(W / 2 - 2, floorY, -D / 2 + 2), 1.8)
	crate(model, cf * CFrame.new(W / 2 - 4, floorY, -D / 2 + 2), 1.3)

	Structures.LootPoint(model, cf * CFrame.new(-W / 4, floorY + 1.5, -D / 4 + 3), true)
	Structures.SpawnPoint(model, cf * CFrame.new(0, 2, -D / 2 - 11))

	model:SetAttribute("Construcao", "Lodge")
	return model
end

--------------------------------------------------------------------------------
-- CASA DE BARCOS (frente aberta, virada pra água)
--------------------------------------------------------------------------------

function Structures.Boathouse(parent: Instance, cf: CFrame): Model
	local model = Structures.Cabin(parent, cf, {
		Name = "CasaDeBarcos",
		Width = 14,
		Depth = 16,
		WallHeight = 9,
		OpenFront = true,
		Furniture = false,
		Windows = true,
		Pitch = 26,
		Spawn = false,
	})
	local floorY = 1.0
	-- Prateleiras, remos, corda, um barco pendurado de lado.
	shelf(model, cf * CFrame.new(-6.4, floorY, 2))
	shelf(model, cf * CFrame.new(6.4, floorY, 2) * CFrame.Angles(0, math.pi, 0))
	crate(model, cf * CFrame.new(-4.5, floorY, 6), 1.7)
	crate(model, cf * CFrame.new(4.2, floorY, 6.4), 1.3)
	for i = 1, 3 do
		part(model, "Remo", Vector3.new(0.3, 7, 0.3), cf * CFrame.new(-6.3 + i * 0.6, floorY + 3.5, -5) * CFrame.Angles(0, 0, math.rad(8)), Enum.Material.Wood, COL.Plank, { CanCollide = false })
	end
	part(model, "RoloCorda", Vector3.new(0.5, 1.6, 1.6), cf * CFrame.new(5.5, floorY + 0.25, -3) * UPRIGHT, Enum.Material.SmoothPlastic, COL.Rope, { Shape = Enum.PartType.Cylinder, CanCollide = false })
	Structures.LootPoint(model, cf * CFrame.new(0, floorY + 1.5, 3), true)
	Structures.SpawnPoint(model, cf * CFrame.new(-9, 2, 0))
	model:SetAttribute("Construcao", "CasaDeBarcos")
	return model
end

--------------------------------------------------------------------------------
-- CELEIRO (no campo aberto)
--------------------------------------------------------------------------------

function Structures.Barn(parent: Instance, cf: CFrame): Model
	local W, D, H = 28, 40, 13
	local floorY = 0.4
	local model = newModel(parent, "Celeiro")

	part(model, "Piso", Vector3.new(W + 0.4, 0.5, D + 0.4), cf * CFrame.new(0, floorY - 0.25, 0), Enum.Material.WoodPlanks, COL.PlankDark)

	local doorW, doorH = 11, 10
	wallWithOpenings(model, cf * CFrame.new(0, floorY, -D / 2), W, H, 0.7, { { x0 = -doorW / 2, x1 = doorW / 2, y0 = 0, y1 = doorH } }, Enum.Material.WoodPlanks, COL.Red)
	wallWithOpenings(model, cf * CFrame.new(0, floorY, D / 2), W, H, 0.7, { { x0 = -1.6, x1 = 1.6, y0 = 7, y1 = 10 } }, Enum.Material.WoodPlanks, COL.Red)
	local sideOpenings = { { x0 = -D / 4 - 1.6, x1 = -D / 4 + 1.6, y0 = 4, y1 = 7 }, { x0 = D / 4 - 1.6, x1 = D / 4 + 1.6, y0 = 4, y1 = 7 } }
	wallWithOpenings(model, cf * CFrame.new(-W / 2, floorY, 0) * CFrame.Angles(0, math.pi / 2, 0), D, H, 0.7, sideOpenings, Enum.Material.WoodPlanks, COL.Red)
	wallWithOpenings(model, cf * CFrame.new(W / 2, floorY, 0) * CFrame.Angles(0, math.pi / 2, 0), D, H, 0.7, sideOpenings, Enum.Material.WoodPlanks, COL.Red)

	-- Portas de correr abertas (encostadas nos lados da abertura).
	for _, sx in { -1, 1 } do
		part(model, "PortaCorrer", Vector3.new(doorW / 2 + 0.5, doorH - 0.3, 0.35), cf * CFrame.new(sx * (doorW / 2 + doorW / 4 + 0.6), floorY + doorH / 2, -D / 2 - 0.7), Enum.Material.WoodPlanks, COL.PlankDark)
	end
	part(model, "Trilho", Vector3.new(doorW * 2 + 3, 0.3, 0.3), cf * CFrame.new(0, floorY + doorH + 0.4, -D / 2 - 0.7), Enum.Material.Metal, COL.Metal, { CanCollide = false })

	-- Vigas de canto.
	for _, sx in { -1, 1 } do
		for _, sz in { -1, 1 } do
			part(model, "Viga", Vector3.new(1.0, H, 1.0), cf * CFrame.new(sx * W / 2, floorY + H / 2, sz * D / 2), Enum.Material.Wood, COL.LogDark, { CanCollide = false })
		end
	end

	gableRoof(model, cf, W, D, floorY + H, 36, 1.6, Color3.fromRGB(58, 48, 42))

	-- Mezanino no fundo + escada (TrussPart é escalável).
	local loftY = floorY + 8
	part(model, "Mezanino", Vector3.new(W - 1.4, 0.5, D / 2 - 1), cf * CFrame.new(0, loftY, D / 4 + 0.5), Enum.Material.WoodPlanks, COL.PlankDark)
	part(model, "MezaninoGuarda", Vector3.new(W - 1.4, 0.3, 0.3), cf * CFrame.new(0, loftY + 2.6, 1.2), Enum.Material.Wood, COL.PlankDark, { CanCollide = false })
	local truss = Instance.new("TrussPart")
	truss.Name = "Escada"
	truss.Size = Vector3.new(2, 8, 2)
	truss.CFrame = cf * CFrame.new(-W / 2 + 3, floorY + 4, 0)
	truss.Anchored = true
	truss.Material = Enum.Material.Wood
	truss.Color = COL.PlankDark
	truss.Parent = model

	-- Fardos de feno.
	local hay = { { -8, 6 }, { -5, 6.2 }, { -8, 10 }, { 7, 12 }, { 9, 8 } }
	for i, h in hay do
		Structures.HayBale(model, cf * CFrame.new(h[1], floorY, h[2]) * CFrame.Angles(0, i * 0.7, 0), i % 2 == 0)
	end
	Structures.HayBale(model, cf * CFrame.new(6, loftY + 0.25, 12), false)

	-- Ferramentas na parede, caixotes.
	crate(model, cf * CFrame.new(W / 2 - 3, floorY, -D / 2 + 4), 2.0)
	crate(model, cf * CFrame.new(W / 2 - 5.2, floorY, -D / 2 + 4.5), 1.4)
	part(model, "Barril", Vector3.new(2.4, 1.8, 1.8), cf * CFrame.new(-W / 2 + 3, floorY + 1.2, -D / 2 + 5) * UPRIGHT, Enum.Material.Wood, COL.LogDark, { Shape = Enum.PartType.Cylinder })

	Structures.LootPoint(model, cf * CFrame.new(W / 2 - 4, floorY + 1.5, -D / 2 + 6), true)
	Structures.LootPoint(model, cf * CFrame.new(-6, loftY + 1.5, 8))
	Structures.LootPoint(model, cf * CFrame.new(0, floorY + 1.5, 4))
	Structures.SpawnPoint(model, cf * CFrame.new(0, 2, -D / 2 - 6))

	model:SetAttribute("Construcao", "Celeiro")
	return model
end

--------------------------------------------------------------------------------
-- PÍER + BARCOS
--------------------------------------------------------------------------------

--[[
	Dock(parent, shoreCF, length, waterLevel)
	shoreCF: ponto da margem, LookVector apontando pra dentro da água.
]]
function Structures.Dock(parent: Instance, shoreCF: CFrame, length: number, waterLevel: number): Model
	local model = newModel(parent, "Pier")
	local deckY = waterLevel + 1.3
	local base = CFrame.new(Vector3.new(shoreCF.Position.X, deckY, shoreCF.Position.Z), Vector3.new(shoreCF.Position.X, deckY, shoreCF.Position.Z) + shoreCF.LookVector)

	local segments = math.max(math.floor(length / 6), 2)
	for i = 0, segments - 1 do
		local z = -(i * 6 + 3)
		part(model, "Tabuado", Vector3.new(6, 0.4, 6), base * CFrame.new(0, 0, z), Enum.Material.WoodPlanks, COL.PlankDark)
		for _, sx in { -1, 1 } do
			part(model, "Estaca", Vector3.new(9, 0.8, 0.8), base * CFrame.new(sx * 2.7, -3.5, z + 2.5) * UPRIGHT, Enum.Material.Wood, COL.LogDark, { Shape = Enum.PartType.Cylinder })
		end
	end
	local endZ = -(segments * 6 + 5)
	part(model, "TabuadoFim", Vector3.new(12, 0.4, 10), base * CFrame.new(0, 0, endZ), Enum.Material.WoodPlanks, COL.PlankDark)
	for _, sx in { -1, 1 } do
		for _, sz in { -1, 1 } do
			part(model, "Estaca", Vector3.new(10, 0.8, 0.8), base * CFrame.new(sx * 5.6, -3.8, endZ + sz * 4.6) * UPRIGHT, Enum.Material.Wood, COL.LogDark, { Shape = Enum.PartType.Cylinder })
		end
	end
	-- Poste com lampião no fim.
	Structures.TrailLamp(model, base * CFrame.new(5.2, 0.2, endZ - 4), true)
	Structures.LootPoint(model, base * CFrame.new(-3, 1.5, endZ))
	Structures.Boat(model, base * CFrame.new(8.5, -1.1, endZ + 2) * CFrame.Angles(0, math.rad(80), 0), false)
	return model
end

function Structures.Boat(parent: Instance, cf: CFrame, overturned: boolean): Model
	local model = newModel(parent, if overturned then "BarcoVirado" else "Barco")
	local roll = if overturned then math.pi else 0
	local base = cf * CFrame.Angles(math.rad(if overturned then 6 else 0), 0, roll)
	part(model, "Casco", Vector3.new(4.2, 1.7, 10), base * CFrame.new(0, 0.85, 0), Enum.Material.WoodPlanks, COL.PlankDark)
	wedge(model, "Proa", Vector3.new(4.2, 1.7, 3), base * CFrame.new(0, 0.85, -6.5), Enum.Material.WoodPlanks, COL.PlankDark)
	wedge(model, "Popa", Vector3.new(4.2, 1.7, 2), base * CFrame.new(0, 0.85, 6) * CFrame.Angles(0, math.pi, 0), Enum.Material.WoodPlanks, COL.PlankDark)
	if not overturned then
		part(model, "Interior", Vector3.new(3.4, 0.4, 9), base * CFrame.new(0, 1.6, 0), Enum.Material.WoodPlanks, Color3.fromRGB(40, 30, 24), { CanCollide = false })
		part(model, "Assento", Vector3.new(3.6, 0.3, 1.2), base * CFrame.new(0, 1.9, -1), Enum.Material.WoodPlanks, COL.Plank, { CanCollide = false })
		part(model, "Assento", Vector3.new(3.6, 0.3, 1.2), base * CFrame.new(0, 1.9, 3), Enum.Material.WoodPlanks, COL.Plank, { CanCollide = false })
	else
		part(model, "Quilha", Vector3.new(0.5, 0.4, 9), base * CFrame.new(0, 1.85, 0), Enum.Material.Wood, COL.LogDark, { CanCollide = false })
		-- O furo.
		part(model, "Furo", Vector3.new(1.6, 0.15, 1.2), base * CFrame.new(1.0, 1.75, 2.2), Enum.Material.SmoothPlastic, Color3.fromRGB(20, 18, 16), { CanCollide = false })
	end
	return model
end

function Structures.Canoe(parent: Instance, cf: CFrame): Model
	local model = newModel(parent, "Canoa")
	local base = cf * CFrame.Angles(0, 0, math.pi)
	part(model, "Casco", Vector3.new(2.2, 1.0, 9), base * CFrame.new(0, 0.5, 0), Enum.Material.Wood, COL.LogDark)
	wedge(model, "Proa", Vector3.new(2.2, 1.0, 2.4), base * CFrame.new(0, 0.5, -5.7), Enum.Material.Wood, COL.LogDark)
	wedge(model, "Popa", Vector3.new(2.2, 1.0, 2.4), base * CFrame.new(0, 0.5, 5.7) * CFrame.Angles(0, math.pi, 0), Enum.Material.Wood, COL.LogDark)
	return model
end

--------------------------------------------------------------------------------
-- TORRE DE VIGIA
--------------------------------------------------------------------------------

function Structures.WatchTower(parent: Instance, cf: CFrame): Model
	local model = newModel(parent, "TorreDeVigia")
	local platY = 24
	local legBase, legTop = 5.4, 3.9

	local function legPoint(sx: number, sz: number, y: number): Vector3
		local t = y / platY
		local off = legBase + (legTop - legBase) * t
		return (cf * CFrame.new(sx * off, y, sz * off)).Position
	end

	for _, sx in { -1, 1 } do
		for _, sz in { -1, 1 } do
			beam(model, "Perna", legPoint(sx, sz, -1.5), legPoint(sx, sz, platY + 0.5), 1.0, Enum.Material.Wood, COL.LogDark)
		end
	end
	-- Travessas horizontais em dois níveis + cruzetas.
	for _, y in { 7, 15 } do
		local pts = { legPoint(-1, -1, y), legPoint(1, -1, y), legPoint(1, 1, y), legPoint(-1, 1, y) }
		for i = 1, 4 do
			beam(model, "Travessa", pts[i], pts[i % 4 + 1], 0.5, Enum.Material.Wood, COL.Log, false)
		end
	end
	for _, side in { { -1, -1, 1, -1 }, { 1, 1, -1, 1 }, { -1, 1, -1, -1 }, { 1, -1, 1, 1 } } do
		beam(model, "Cruzeta", legPoint(side[1], side[2], 7), legPoint(side[3], side[4], 15), 0.4, Enum.Material.Wood, COL.Log, false)
	end

	part(model, "Plataforma", Vector3.new(11.5, 0.6, 11.5), cf * CFrame.new(0, platY, 0), Enum.Material.WoodPlanks, COL.PlankDark)
	-- Guarda-corpo (menos o lado da escada, -Z).
	for _, sx in { -1, 1 } do
		for _, sz in { -1, 1 } do
			part(model, "GuardaPoste", Vector3.new(0.4, 3.2, 0.4), cf * CFrame.new(sx * 5.5, platY + 1.9, sz * 5.5), Enum.Material.Wood, COL.LogDark, { CanCollide = false })
		end
	end
	for _, y in { platY + 1.6, platY + 3.2 } do
		part(model, "Guarda", Vector3.new(11.4, 0.25, 0.25), cf * CFrame.new(0, y, 5.5), Enum.Material.Wood, COL.Log, { CanCollide = false })
		part(model, "Guarda", Vector3.new(0.25, 0.25, 11.4), cf * CFrame.new(-5.5, y, 0), Enum.Material.Wood, COL.Log, { CanCollide = false })
		part(model, "Guarda", Vector3.new(0.25, 0.25, 11.4), cf * CFrame.new(5.5, y, 0), Enum.Material.Wood, COL.Log, { CanCollide = false })
		part(model, "Guarda", Vector3.new(3.4, 0.25, 0.25), cf * CFrame.new(-4, y, -5.5), Enum.Material.Wood, COL.Log, { CanCollide = false })
		part(model, "Guarda", Vector3.new(3.4, 0.25, 0.25), cf * CFrame.new(4, y, -5.5), Enum.Material.Wood, COL.Log, { CanCollide = false })
	end
	-- Telhado.
	for _, sx in { -1, 1 } do
		for _, sz in { -1, 1 } do
			part(model, "TelhadoPoste", Vector3.new(0.5, 6.5, 0.5), cf * CFrame.new(sx * 5, platY + 3.5, sz * 5), Enum.Material.Wood, COL.LogDark, { CanCollide = false })
		end
	end
	gableRoof(model, cf, 13, 13, platY + 6.6, 24, 0.8)

	-- Escada (TrussPart: dá pra subir).
	local truss = Instance.new("TrussPart")
	truss.Name = "Escada"
	truss.Size = Vector3.new(2, platY + 2, 2)
	truss.CFrame = cf * CFrame.new(0, (platY + 2) / 2 - 0.5, -6.9)
	truss.Anchored = true
	truss.Material = Enum.Material.Wood
	truss.Color = COL.PlankDark
	truss.Parent = model

	Structures.TrailLamp(model, cf * CFrame.new(4.4, platY + 0.3, 4.4), true)
	Structures.LootPoint(model, cf * CFrame.new(-2, platY + 1.5, 2), true)
	Structures.SpawnPoint(model, cf * CFrame.new(0, 2, -11))
	Structures.Marker(model, "Mirante", cf * CFrame.new(0, platY + 2, 0), { Mirante = true })

	model:SetAttribute("Construcao", "Torre")
	return model
end

--------------------------------------------------------------------------------
-- FAROL
--------------------------------------------------------------------------------

function Structures.Lighthouse(parent: Instance, cf: CFrame): Model
	local model = newModel(parent, "Farol")
	local segments = 6
	local segH = 6.8
	local y = 0
	for i = 1, segments do
		local r = 5.6 - (i - 1) * 0.22
		local color = if i % 2 == 1 then COL.White else COL.Red
		part(model, "Torre_" .. i, Vector3.new(segH, r * 2, r * 2), cf * CFrame.new(0, y + segH / 2, 0) * UPRIGHT, Enum.Material.Concrete, color, { Shape = Enum.PartType.Cylinder })
		y += segH
	end
	-- Base de pedra.
	part(model, "Base", Vector3.new(1.4, 14, 14), cf * CFrame.new(0, 0.5, 0) * UPRIGHT, Enum.Material.Cobblestone, COL.StoneDark, { Shape = Enum.PartType.Cylinder })
	-- Galeria.
	part(model, "Galeria", Vector3.new(0.6, 14.6, 14.6), cf * CFrame.new(0, y + 0.3, 0) * UPRIGHT, Enum.Material.Metal, COL.Metal, { Shape = Enum.PartType.Cylinder })
	for i = 1, 10 do
		local a = i / 10 * TAU
		local px, pz = math.cos(a) * 6.9, math.sin(a) * 6.9
		part(model, "GaleriaPoste", Vector3.new(0.25, 3, 0.25), cf * CFrame.new(px, y + 2.1, pz), Enum.Material.Metal, COL.Metal, { CanCollide = false })
		local nx, nz = math.cos((i + 1) / 10 * TAU) * 6.9, math.sin((i + 1) / 10 * TAU) * 6.9
		beam(model, "GaleriaAro", (cf * CFrame.new(px, y + 3.5, pz)).Position, (cf * CFrame.new(nx, y + 3.5, nz)).Position, 0.2, Enum.Material.Metal, COL.Metal, false)
	end
	-- Lanterna.
	local lampY = y + 0.6
	part(model, "LanternaVidro", Vector3.new(6.2, 8.2, 8.2), cf * CFrame.new(0, lampY + 3.1, 0) * UPRIGHT, Enum.Material.Glass, COL.Glass, { Shape = Enum.PartType.Cylinder, Transparency = 0.5, CanCollide = false })
	local lamp = part(model, "Lampada", Vector3.new(2.4, 2.4, 2.4), cf * CFrame.new(0, lampY + 3.1, 0), Enum.Material.Neon, Color3.fromRGB(255, 214, 150), { Shape = Enum.PartType.Ball, CanCollide = false })
	pointLight(lamp, Color3.fromRGB(255, 205, 140), 120, 0.9, true)
	-- Teto.
	part(model, "Teto", Vector3.new(0.8, 9.6, 9.6), cf * CFrame.new(0, lampY + 6.6, 0) * UPRIGHT, Enum.Material.Metal, COL.Red, { Shape = Enum.PartType.Cylinder })
	local coneY = lampY + 7.2
	for i, r in { 3.9, 2.8, 1.7, 0.8 } do
		part(model, "Cone", Vector3.new(1.1, r * 2, r * 2), cf * CFrame.new(0, coneY + (i - 1) * 1.05, 0) * UPRIGHT, Enum.Material.Metal, COL.Red, { Shape = Enum.PartType.Cylinder, CanCollide = false })
	end
	part(model, "Ponta", Vector3.new(0.8, 0.8, 0.8), cf * CFrame.new(0, coneY + 4.6, 0), Enum.Material.Metal, COL.Metal, { Shape = Enum.PartType.Ball, CanCollide = false })

	-- Porta decorativa e degraus.
	part(model, "PortaFarol", Vector3.new(3.6, 6.5, 0.3), cf * CFrame.new(0, 3.8, -5.55), Enum.Material.WoodPlanks, COL.PlankDark, { CanCollide = false })
	part(model, "Degrau", Vector3.new(5, 0.6, 2), cf * CFrame.new(0, 0.7, -6.8), Enum.Material.Concrete, COL.Stone)

	Structures.LootPoint(model, cf * CFrame.new(0, 2, -9))
	Structures.SpawnPoint(model, cf * CFrame.new(0, 2, -13))
	model:SetAttribute("Construcao", "Farol")
	return model
end

--------------------------------------------------------------------------------
-- PROPS
--------------------------------------------------------------------------------

function Structures.FireCircle(parent: Instance, cf: CFrame, rng: Random, withSeats: boolean): Model
	local model = newModel(parent, "Fogueira")
	local ash = part(model, "Cinzas", Vector3.new(0.4, 5, 5), cf * CFrame.new(0, 0.2, 0) * UPRIGHT, Enum.Material.Slate, Color3.fromRGB(35, 33, 32), { Shape = Enum.PartType.Cylinder })
	for i = 1, 10 do
		local a = (i - 1) / 10 * TAU + rng:NextNumber(-0.15, 0.15)
		local s = rng:NextNumber(1.0, 1.5)
		part(model, "Pedra", Vector3.new(s, s, s), cf * CFrame.new(math.cos(a) * 2.9, s * 0.35, math.sin(a) * 2.9), Enum.Material.Slate, Color3.fromRGB(100 + rng:NextInteger(-15, 15), 100, 100), { Shape = Enum.PartType.Ball })
	end
	for i = 1, 3 do
		part(model, "Lenha", Vector3.new(3, 0.55, 0.55), cf * CFrame.new(0, 0.6, 0) * CFrame.Angles(0, (i - 1) / 3 * math.pi + rng:NextNumber(-0.2, 0.2), 0), Enum.Material.Wood, Color3.fromRGB(40, 30, 25), { Shape = Enum.PartType.Cylinder, CanCollide = false })
	end
	local smoke = Instance.new("Smoke")
	smoke.Color = Color3.fromRGB(120, 120, 120)
	smoke.Size = 1.6
	smoke.Opacity = 0.1
	smoke.RiseVelocity = 1.5
	smoke.Parent = ash
	pointLight(ash, Color3.fromRGB(255, 120, 40), 8, 0.25, true)

	if withSeats then
		for i = 1, 4 do
			local a = (i - 1) / 4 * TAU + math.pi / 4
			part(model, "Tronco", Vector3.new(5.5, 1.2, 1.2), cf * CFrame.new(math.cos(a) * 6, 0.6, math.sin(a) * 6) * CFrame.Angles(0, -a + math.pi / 2, 0), Enum.Material.Wood, COL.Log, { Shape = Enum.PartType.Cylinder })
		end
	end
	return model
end

function Structures.PicnicTable(parent: Instance, cf: CFrame): Model
	local model = newModel(parent, "MesaPiquenique")
	part(model, "Tampo", Vector3.new(7, 0.3, 2.6), cf * CFrame.new(0, 2.8, 0), Enum.Material.WoodPlanks, COL.Plank)
	for _, sz in { -1, 1 } do
		part(model, "Banco", Vector3.new(7, 0.3, 1.1), cf * CFrame.new(0, 1.6, sz * 2.2), Enum.Material.WoodPlanks, COL.Plank)
	end
	for _, sx in { -1, 1 } do
		part(model, "Pe", Vector3.new(0.35, 2.7, 2.4), cf * CFrame.new(sx * 3.0, 1.4, 0), Enum.Material.Wood, COL.PlankDark, { CanCollide = false })
		part(model, "PeBanco", Vector3.new(0.35, 0.3, 5.4), cf * CFrame.new(sx * 3.0, 1.45, 0), Enum.Material.Wood, COL.PlankDark, { CanCollide = false })
	end
	Structures.LootPoint(model, cf * CFrame.new(0, 3.3, 0))
	return model
end

function Structures.TrailLamp(parent: Instance, cf: CFrame, lit: boolean): Model
	local model = newModel(parent, "Lampiao")
	part(model, "Poste", Vector3.new(0.4, 7, 0.4), cf * CFrame.new(0, 3.5, 0), Enum.Material.Wood, COL.LogDark)
	part(model, "Braco", Vector3.new(0.3, 0.3, 1.6), cf * CFrame.new(0, 6.7, -0.7), Enum.Material.Wood, COL.LogDark, { CanCollide = false })
	local lantern = part(model, "Caixa", Vector3.new(0.7, 1.0, 0.7), cf * CFrame.new(0, 5.9, -1.4), Enum.Material.Metal, COL.Metal, { CanCollide = false })
	local glass = part(model, "Vidro", Vector3.new(0.45, 0.6, 0.45), cf * CFrame.new(0, 5.9, -1.4), if lit then Enum.Material.Neon else Enum.Material.Glass, if lit then Color3.fromRGB(255, 190, 110) else COL.Glass, { CanCollide = false })
	glass.Transparency = if lit then 0 else 0.35
	pointLight(lantern, Color3.fromRGB(255, 175, 95), 22, 0.7, lit)
	return model
end

function Structures.ArcheryTarget(parent: Instance, cf: CFrame): Model
	local model = newModel(parent, "AlvoDeArco")
	local rings = { { 2.4, COL.White, 0 }, { 1.7, COL.Blue, 0.06 }, { 1.0, COL.Red, 0.12 }, { 0.4, COL.Gold, 0.18 } }
	for i, ring in rings do
		local r = ring[1] :: number
		part(model, "Anel_" .. i, Vector3.new(0.5, r * 2, r * 2), cf * CFrame.new(0, 3.4, -(ring[3] :: number)) * ALONG_Z, Enum.Material.Fabric, ring[2] :: Color3, { Shape = Enum.PartType.Cylinder, CanCollide = i == 1 })
	end
	for _, sx in { -1, 1 } do
		part(model, "Perna", Vector3.new(0.35, 6, 0.35), cf * CFrame.new(sx * 1.4, 2.9, 0.5) * CFrame.Angles(0, 0, sx * math.rad(-16)), Enum.Material.Wood, COL.LogDark)
	end
	part(model, "PernaTras", Vector3.new(0.35, 6, 0.35), cf * CFrame.new(0, 2.9, 1.6) * CFrame.Angles(math.rad(-24), 0, 0), Enum.Material.Wood, COL.LogDark)
	return model
end

function Structures.HayBale(parent: Instance, cf: CFrame, standing: boolean): Part
	local rot = if standing then UPRIGHT else CFrame.identity
	return part(parent, "Fardo", Vector3.new(4.2, 3.4, 3.4), cf * CFrame.new(0, 1.7, 0) * rot, Enum.Material.Grass, COL.Straw, { Shape = Enum.PartType.Cylinder })
end

function Structures.FishRack(parent: Instance, cf: CFrame): Model
	local model = newModel(parent, "SecadorDePeixe")
	for _, sx in { -1, 1 } do
		part(model, "Poste", Vector3.new(0.35, 5, 0.35), cf * CFrame.new(sx * 3, 2.5, 0), Enum.Material.Wood, COL.LogDark)
	end
	part(model, "Vara", Vector3.new(6.8, 0.3, 0.3), cf * CFrame.new(0, 4.8, 0), Enum.Material.Wood, COL.Log, { CanCollide = false })
	for i = 1, 5 do
		part(model, "Peixe", Vector3.new(0.35, 1.5, 0.9), cf * CFrame.new(-2.4 + (i - 1) * 1.2, 4.0, 0), Enum.Material.Fabric, Color3.fromRGB(150, 140, 120), { CanCollide = false })
	end
	return model
end

function Structures.Pot(parent: Instance, cf: CFrame, s: number): Part
	return part(parent, "Pote", Vector3.new(s * 0.9, s, s), cf * CFrame.new(0, s * 0.45, 0) * UPRIGHT, Enum.Material.Sand, Color3.fromRGB(150, 90, 60), { Shape = Enum.PartType.Cylinder })
end

--------------------------------------------------------------------------------
-- CABANA NATIVA + TOTEM
--------------------------------------------------------------------------------

function Structures.Hut(parent: Instance, cf: CFrame, r: number, rng: Random): Model
	local model = newModel(parent, "CabanaNativa")
	local wallH = rng:NextNumber(7, 8.2)
	local logD = 1.0
	local logCount = math.ceil((TAU * r) / (logD * 0.95))
	local doorHalf = 2.3 / r
	local doorAngle = -math.pi / 2 -- porta na frente (-Z local)

	for i = 1, logCount do
		local a = (i - 1) / logCount * TAU
		local diff = math.atan2(math.sin(a - doorAngle), math.cos(a - doorAngle))
		if math.abs(diff) > doorHalf then
			local lh = wallH + rng:NextNumber(-0.4, 0.4)
			local shade = rng:NextInteger(-12, 12)
			part(model, "Tronco", Vector3.new(lh, logD, logD), cf * CFrame.new(math.cos(a) * r, lh / 2 - 0.3, math.sin(a) * r) * UPRIGHT, Enum.Material.Wood, Color3.fromRGB(110 + shade, 75 + shade, 40 + shade), { Shape = Enum.PartType.Cylinder })
		end
	end
	-- Verga da porta.
	part(model, "Verga", Vector3.new(5.2, 0.8, 0.8), cf * CFrame.new(0, wallH - 0.6, -r), Enum.Material.Wood, COL.LogDark)

	-- Teto de palha em camadas.
	local tiers = 6
	local roofH = r * 1.05
	for t = 0, tiers - 1 do
		local frac = t / tiers
		local tierR = (r + 1.6) * (1 - frac) + 0.6
		local tierH = roofH / tiers + 0.35
		part(model, "Palha_" .. t, Vector3.new(tierH, tierR * 2, tierR * 2), cf * CFrame.new(0, wallH - 0.2 + frac * roofH + tierH / 2, 0) * UPRIGHT, Enum.Material.Grass, COL.Thatch, { Shape = Enum.PartType.Cylinder, CanCollide = t == 0 })
	end

	-- Interior: esteira, pote, fogo interno apagado.
	part(model, "Esteira", Vector3.new(5, 0.3, 2.6), cf * CFrame.new(r * 0.35, 0.15, r * 0.3) * CFrame.Angles(0, rng:NextNumber(0, TAU), 0), Enum.Material.Fabric, COL.Fabric, { CanCollide = false })
	Structures.Pot(model, cf * CFrame.new(-r * 0.45, 0, r * 0.25), 1.2)
	Structures.LootPoint(model, cf * CFrame.new(-r * 0.3, 1.5, -r * 0.2))
	Structures.SpawnPoint(model, cf * CFrame.new(0, 2, -r - 5))
	model:SetAttribute("Construcao", "CabanaNativa")
	return model
end

function Structures.Totem(parent: Instance, cf: CFrame, rng: Random): Model
	local model = newModel(parent, "Totem")
	local segments = {
		{ r = 2.2, h = 3.8, c = Color3.fromRGB(80, 50, 30) },
		{ r = 1.9, h = 3.8, c = Color3.fromRGB(150, 60, 40) },
		{ r = 1.6, h = 3.4, c = Color3.fromRGB(190, 140, 60) },
		{ r = 1.3, h = 3.0, c = Color3.fromRGB(60, 40, 30) },
	}
	local y = 0
	for i, seg in segments do
		part(model, "Segmento_" .. i, Vector3.new(seg.h, seg.r * 2, seg.r * 2), cf * CFrame.new(0, y + seg.h / 2, 0) * CFrame.Angles(0, rng:NextNumber(0, TAU), 0) * UPRIGHT, Enum.Material.Wood, seg.c, { Shape = Enum.PartType.Cylinder })
		y += seg.h
	end
	part(model, "Topo", Vector3.new(2.8, 2.8, 2.8), cf * CFrame.new(0, y + 1.2, 0), Enum.Material.Wood, Color3.fromRGB(120, 40, 40), { Shape = Enum.PartType.Ball })
	-- "Asas".
	part(model, "Asa", Vector3.new(7, 0.6, 1.4), cf * CFrame.new(0, y - 1.2, 0), Enum.Material.Wood, Color3.fromRGB(190, 140, 60), { CanCollide = false })
	return model
end

--------------------------------------------------------------------------------
-- VEGETAÇÃO RASTEIRA
--------------------------------------------------------------------------------

function Structures.Bush(parent: Instance, pos: Vector3, rng: Random)
	local s = rng:NextNumber(2.6, 4.8)
	local color = if rng:NextNumber() < 0.5 then COL.Leaf else COL.LeafDark
	local b = part(parent, "Arbusto", Vector3.new(s, s, s), CFrame.new(pos + Vector3.new(0, s * 0.32, 0)), Enum.Material.LeafyGrass, color, { Shape = Enum.PartType.Ball, CanCollide = false, CastShadow = false })
	if rng:NextNumber() < 0.5 then
		local s2 = s * rng:NextNumber(0.6, 0.85)
		part(parent, "Arbusto", Vector3.new(s2, s2, s2), CFrame.new(pos + Vector3.new(rng:NextNumber(-1.2, 1.2), s2 * 0.3, rng:NextNumber(-1.2, 1.2))), Enum.Material.LeafyGrass, color, { Shape = Enum.PartType.Ball, CanCollide = false, CastShadow = false })
	end
	return b
end

function Structures.FallenLog(parent: Instance, pos: Vector3, rng: Random)
	local len = rng:NextNumber(8, 15)
	local dia = rng:NextNumber(1.4, 2.3)
	local cf = CFrame.new(pos + Vector3.new(0, dia * 0.35, 0)) * CFrame.Angles(0, rng:NextNumber(0, TAU), rng:NextNumber(-0.08, 0.08))
	part(parent, "TroncoCaido", Vector3.new(len, dia, dia), cf, Enum.Material.Wood, Color3.fromRGB(70 + rng:NextInteger(-10, 10), 50, 32), { Shape = Enum.PartType.Cylinder })
	-- Toco ao lado, às vezes.
	if rng:NextNumber() < 0.4 then
		part(parent, "Toco", Vector3.new(1.6, dia * 1.1, dia * 1.1), cf * CFrame.new(len / 2 + 2, 0.5, 0) * UPRIGHT, Enum.Material.Wood, Color3.fromRGB(80, 56, 36), { Shape = Enum.PartType.Cylinder })
	end
end

return Structures
