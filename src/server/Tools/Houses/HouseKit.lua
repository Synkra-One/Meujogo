--!strict
--[[
	HouseKit
	Peças de construção das casas grandes (Houses/CampCabin, Houses/CasaDoCaseiro):
	fundação, piso, paredes com forro interno, janelas, portas que abrem
	(DoorSystem), telhado de duas águas com empenas, varanda, escada,
	guarda-corpo, luminárias e os modelos de Workspace["Modelos para as casas"].

	ESPAÇO: toda função recebe `house` = CFrame da casa no PISO ACABADO
	(y = 0 local), LookVector = frente (-Z local), e posições LOCAIS da casa.
	O chão do terreno fica em y = -Found (a fundação cobre esse vão).

	COLISÃO: estrutura (parede, piso, forro, telhado, degrau) colide; detalhe
	(moldura, rodapé, maçaneta, livro...) não colide nem entra em raycast --
	evita tropeço invisível e deixa os ProximityPrompts enxergarem através.
]]

local Workspace = game:GetService("Workspace")

local Structures = require(script.Parent.Parent.Structures)

local HouseKit = {}

--------------------------------------------------------------------------------
-- Materiais (os de 2022 caem num equivalente se a engine não tiver)
--------------------------------------------------------------------------------

local function material(name: string, fallback: Enum.Material): Enum.Material
	local ok, value = pcall(function()
		return (Enum.Material :: any)[name]
	end)
	if ok and value then
		return value
	end
	return fallback
end

HouseKit.Mat = {
	Shingles = material("RoofShingles", Enum.Material.Slate),
	Plaster = material("Plaster", Enum.Material.SmoothPlastic),
	Tiles = material("CeramicTiles", Enum.Material.Marble),
	Carpet = material("Carpet", Enum.Material.Fabric),
	Leather = material("Leather", Enum.Material.Fabric),
	Rubber = material("Rubber", Enum.Material.SmoothPlastic),
}

HouseKit.Colors = Structures.Colors

--[[
	ExtraDepth: quanto o terreno sob a casa desce abaixo do ponto mais alto
	(o piso fica Found acima do ponto MAIS ALTO). O HouseGenerator mede antes
	de construir; fundação, saia do deck e degraus externos descem esse tanto
	a mais -- a casa se adapta ao chão, o terreno do mapa não é mexido.
]]
HouseKit.ExtraDepth = 0

--------------------------------------------------------------------------------
-- Primitivas
--------------------------------------------------------------------------------

export type PartOpts = {
	Shape: Enum.PartType?,
	Collide: boolean?, -- default true
	Transparency: number?,
	Shadow: boolean?,
	Reflectance: number?,
}

--[[
	P(parent, name, size, cf, material, color, opts?)
	Part ancorada. Com opts.Collide == false vira "detalhe": sem colisão,
	sem toque e fora de raycast.
]]
function HouseKit.P(parent: Instance, name: string, size: Vector3, cf: CFrame, mat: Enum.Material, color: Color3, opts: PartOpts?): Part
	local o = opts or {}
	local collide = o.Collide ~= false
	local p = Structures.Part(parent, name, size, cf, mat, color, {
		Shape = o.Shape,
		CanCollide = collide,
		Transparency = o.Transparency,
		CastShadow = o.Shadow,
	})
	if not collide then
		p.CanTouch = false
		p.CanQuery = false
	end
	if o.Reflectance then
		p.Reflectance = o.Reflectance
	end
	return p
end

local DECO: PartOpts = { Collide = false }
HouseKit.Deco = DECO

function HouseKit.Wedge(parent: Instance, name: string, size: Vector3, cf: CFrame, mat: Enum.Material, color: Color3): WedgePart
	local w = Instance.new("WedgePart")
	w.Name = name
	w.Size = size
	w.CFrame = cf
	w.Anchored = true
	w.Material = mat
	w.Color = color
	w.TopSurface = Enum.SurfaceType.Smooth
	w.BottomSurface = Enum.SurfaceType.Smooth
	w.Parent = parent
	return w
end

-- Solda `part` em `root`: a peça passa a seguir o root quando ele se move
-- (porta girando, gaveta deslizando). Continua sem colisão/massa.
function HouseKit.Weld(root: BasePart, part: BasePart)
	part.Anchored = false
	part.Massless = true
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = root
	weld.Part1 = part
	weld.Parent = part
end

function HouseKit.Model(parent: Instance, name: string): Model
	local m = Instance.new("Model")
	m.Name = name
	m.Parent = parent
	return m
end

function HouseKit.Folder(parent: Instance, name: string): Folder
	local f = Instance.new("Folder")
	f.Name = name
	f.Parent = parent
	return f
end

-- CFrame do mundo em `pos` (local da casa) olhando pra `look` (vetor local).
function HouseKit.At(house: CFrame, pos: Vector3, look: Vector3?): CFrame
	local world = house * CFrame.new(pos.X, pos.Y, pos.Z)
	if not look then
		return world
	end
	local dir = (house * CFrame.new(look.X, look.Y, look.Z)).Position - house.Position
	return CFrame.lookAt(world.Position, world.Position + dir)
end

function HouseKit.Light(parentPart: BasePart, color: Color3, range: number, brightness: number, enabled: boolean): PointLight
	local light = Instance.new("PointLight")
	light.Color = color
	light.Range = range
	light.Brightness = brightness
	light.Shadows = false
	light.Enabled = enabled
	light.Parent = parentPart
	return light
end

HouseKit.WarmLight = Color3.fromRGB(255, 196, 130)

--------------------------------------------------------------------------------
-- Estrutura
--------------------------------------------------------------------------------

export type Palette = {
	Siding: Color3,
	SidingMat: Enum.Material,
	Interior: Color3,
	InteriorMat: Enum.Material,
	Trim: Color3,
	Roof: Color3,
	Floor: Color3,
	Ceiling: Color3,
	CeilingMat: Enum.Material,
	Foundation: Color3,
	FoundationMat: Enum.Material,
	Shutter: Color3,
	Door: Color3,
	Deck: Color3,
}

--[[
	Foundation(parent, house, x0, x1, z0, z1, found)
	Bloco maciço de pedra do piso (y = -1) até 1,5 stud ABAIXO do terreno.
	É o que garante que grama/terreno nunca aparecem no piso: não existe vão
	entre o chão da casa e o terreno. Respiros escuros dão leitura de
	"porão ventilado" sem abrir buraco nenhum.
]]
function HouseKit.Foundation(parent: Instance, house: CFrame, x0: number, x1: number, z0: number, z1: number, found: number, pal: Palette)
	local top, bottom = -1, -(found + 1.5 + HouseKit.ExtraDepth)
	local h = top - bottom
	local w, d = x1 - x0, z1 - z0
	local cx, cz = (x0 + x1) / 2, (z0 + z1) / 2
	HouseKit.P(parent, "Fundacao", Vector3.new(w, h, d), house * CFrame.new(cx, bottom + h / 2, cz), pal.FoundationMat, pal.Foundation)
	HouseKit.P(parent, "FundacaoCapa", Vector3.new(w + 0.3, 0.25, d + 0.3), house * CFrame.new(cx, top - 0.125, cz), Enum.Material.Concrete, Color3.fromRGB(128, 124, 116), DECO)

	local ventY = -found + (found - 1) * 0.55
	if found > 1.6 then
		for _, side in { -1, 1 } do
			for _, t in { -0.3, 0.3 } do
				HouseKit.P(parent, "Respiro", Vector3.new(1.4, 0.45, 0.1), house * CFrame.new(cx + t * w, ventY, cz + side * (d / 2 + 0.03)), Enum.Material.Metal, Color3.fromRGB(28, 26, 24), DECO)
			end
		end
	end
end

function HouseKit.Floor(parent: Instance, house: CFrame, x0: number, x1: number, z0: number, z1: number, mat: Enum.Material, color: Color3, name: string?): Part
	return HouseKit.P(parent, name or "Piso", Vector3.new(x1 - x0, 1, z1 - z0), house * CFrame.new((x0 + x1) / 2, -0.5, (z0 + z1) / 2), mat, color)
end

-- Revestimento de piso (cerâmica, tapete embutido) 0.08 acima do piso.
function HouseKit.FloorFinish(parent: Instance, house: CFrame, x0: number, x1: number, z0: number, z1: number, mat: Enum.Material, color: Color3)
	HouseKit.P(parent, "Revestimento", Vector3.new(x1 - x0, 0.08, z1 - z0), house * CFrame.new((x0 + x1) / 2, 0.04, (z0 + z1) / 2), mat, color)
end

function HouseKit.Ceiling(parent: Instance, house: CFrame, x0: number, x1: number, z0: number, z1: number, y: number, pal: Palette)
	HouseKit.P(parent, "Forro", Vector3.new(x1 - x0, 0.4, z1 - z0), house * CFrame.new((x0 + x1) / 2, y + 0.2, (z0 + z1) / 2), pal.CeilingMat, pal.Ceiling)
end

export type Opening = Structures.Opening

--[[
	Wall(parent, house, a, b, height, openings, pal, opts)
	Parede reta de `a` até `b` (locais, no piso). Aberturas em coordenadas
	ao longo da parede: x vai de -comprimento/2 (lado `a`) até +comprimento/2.
	opts.Exterior: casca externa (Siding) + forro interno (Interior) no lado
	opts.InsideDir (vetor local que aponta pra DENTRO da casa).
]]
--[[
	WallStrips(parent, baseCF, length, height, thickness, openings, mat, color)
	Parede com qualquer conjunto de aberturas retangulares -- inclusive uma
	em cima da outra (janela do andar sobre janela do térreo), coisa que o
	Structures.WallWithOpenings não suporta (ele supõe aberturas lado a lado).
	Corta a parede em faixas verticais em cada borda de abertura, calcula os
	trechos cheios de cada faixa e junta faixas vizinhas iguais.
]]
local function wallStrips(parent: Instance, baseCF: CFrame, length: number, height: number, thickness: number, openings: { Opening }, mat: Enum.Material, color: Color3)
	local half = length / 2
	local xs = { -half, half }
	for _, op in openings do
		table.insert(xs, math.clamp(op.x0, -half, half))
		table.insert(xs, math.clamp(op.x1, -half, half))
	end
	table.sort(xs)
	local cuts = {}
	for _, x in xs do
		if #cuts == 0 or x - cuts[#cuts] > 1e-4 then
			table.insert(cuts, x)
		end
	end

	local function solids(xa: number, xb: number): { { number } }
		local mid = (xa + xb) / 2
		local holes = {}
		for _, op in openings do
			if op.x0 < mid and op.x1 > mid then
				table.insert(holes, { math.max(0, op.y0), math.min(height, op.y1) })
			end
		end
		table.sort(holes, function(a, b)
			return a[1] < b[1]
		end)
		local out = {}
		local y = 0
		for _, hole in holes do
			if hole[1] - y > 0.02 then
				table.insert(out, { y, hole[1] })
			end
			y = math.max(y, hole[2])
		end
		if height - y > 0.02 then
			table.insert(out, { y, height })
		end
		return out
	end

	local function same(a: { { number } }, b: { { number } }): boolean
		if #a ~= #b then
			return false
		end
		for i = 1, #a do
			if math.abs(a[i][1] - b[i][1]) > 1e-4 or math.abs(a[i][2] - b[i][2]) > 1e-4 then
				return false
			end
		end
		return true
	end

	local runStart, runSegs = nil :: number?, nil :: { { number } }?
	local function flush(xEnd: number)
		if runStart and runSegs then
			for _, seg in runSegs do
				Structures.Part(parent, "Parede", Vector3.new(xEnd - runStart, seg[2] - seg[1], thickness), baseCF * CFrame.new((runStart + xEnd) / 2, (seg[1] + seg[2]) / 2, 0), mat, color)
			end
		end
	end
	for i = 1, #cuts - 1 do
		local xa, xb = cuts[i], cuts[i + 1]
		local segs = solids(xa, xb)
		if runSegs and same(segs, runSegs) then
			continue
		end
		flush(xa)
		runStart, runSegs = xa, segs
	end
	flush(cuts[#cuts])
end
HouseKit.WallStrips = wallStrips

export type WallOpts = { Exterior: boolean?, InsideDir: Vector3?, Thickness: number?, NoTrim: boolean? }

-- Trechos da parede (em x local) sem porta/passagem no nível do piso --
-- rodapé e faixa da base não podem atravessar um vão de porta.
local function floorRuns(length: number, openings: { Opening }): { { number } }
	local doors = {}
	for _, op in openings do
		if op.y0 <= 0.05 then
			table.insert(doors, op)
		end
	end
	table.sort(doors, function(a, b)
		return a.x0 < b.x0
	end)
	local runs = {}
	local cursor = -length / 2
	for _, op in doors do
		if op.x0 - cursor > 0.1 then
			table.insert(runs, { cursor, op.x0 })
		end
		cursor = math.max(cursor, op.x1)
	end
	if length / 2 - cursor > 0.1 then
		table.insert(runs, { cursor, length / 2 })
	end
	return runs
end

function HouseKit.Wall(parent: Instance, house: CFrame, a: Vector3, b: Vector3, height: number, openings: { Opening }, pal: Palette, opts: WallOpts?)
	local o = opts or {}
	local thickness = o.Thickness or 1
	local mid = (a + b) / 2
	local along = (b - a).Unit
	local length = (b - a).Magnitude
	-- X local da parede = `along`; Z local = normal.
	local normal = Vector3.new(-along.Z, 0, along.X)
	local base = house * CFrame.fromMatrix(mid, along, Vector3.new(0, 1, 0), normal)
	local runs = floorRuns(length, openings)

	local function trim(name: string, h: number, depth: number, z: number, mat: Enum.Material, grow: number)
		if o.NoTrim then
			return
		end
		for _, run in runs do
			local x0, x1 = run[1], run[2]
			HouseKit.P(parent, name, Vector3.new(x1 - x0 + grow, h, depth), base * CFrame.new((x0 + x1) / 2, h / 2, z), mat, pal.Trim, DECO)
		end
	end

	if o.Exterior then
		local inside = o.InsideDir or normal
		local sign = if inside:Dot(normal) >= 0 then 1 else -1
		local outerT, innerT = thickness * 0.65, thickness * 0.35
		wallStrips(parent, base * CFrame.new(0, 0, -sign * (thickness / 2 - outerT / 2)), length, height, outerT, openings, pal.SidingMat, pal.Siding)
		wallStrips(parent, base * CFrame.new(0, 0, sign * (thickness / 2 - innerT / 2)), length, height, innerT, openings, pal.InteriorMat, pal.Interior)
		-- Rodapé interno e faixa de acabamento externa na base.
		trim("Rodape", 0.5, 0.12, sign * (thickness / 2 + 0.06), Enum.Material.Wood, 0)
		trim("FaixaBase", 0.7, 0.14, -sign * (thickness / 2 + 0.07), Enum.Material.WoodPlanks, 0.2)
	else
		wallStrips(parent, base, length, height, thickness, openings, pal.InteriorMat, pal.Interior)
		for _, side in { -1, 1 } do
			trim("Rodape", 0.5, 0.12, side * (thickness / 2 + 0.06), Enum.Material.Wood, 0)
		end
	end
end

-- Tábua vertical de canto (esconde a emenda das paredes externas).
function HouseKit.CornerBoard(parent: Instance, house: CFrame, x: number, z: number, height: number, color: Color3, mat: Enum.Material?)
	HouseKit.P(parent, "CantoneiraExterna", Vector3.new(1.35, height, 1.35), house * CFrame.new(x, height / 2, z), mat or Enum.Material.WoodPlanks, color, DECO)
end

--------------------------------------------------------------------------------
-- Janela
--------------------------------------------------------------------------------

export type WindowOpts = {
	Shutters: boolean?,
	Curtains: Color3?,
	Boarded: boolean?,
	Frosted: boolean?,
	Thickness: number?,
}

--[[
	Window(parent, house, center, outward, width, height, pal, opts)
	`center` = centro do VÃO (local), `outward` = normal local pra fora.
	Vidro colide (ninguém atravessa janela); moldura, peitoril, venezianas
	e cortinas são detalhe.
]]
function HouseKit.Window(parent: Instance, house: CFrame, center: Vector3, outward: Vector3, width: number, height: number, pal: Palette, opts: WindowOpts?)
	local o = opts or {}
	local t = o.Thickness or 1
	local model = HouseKit.Model(parent, "Janela")
	local cf = HouseKit.At(house, center, outward) -- -Z local = pra fora
	local w, h = width, height

	if o.Boarded then
		HouseKit.P(model, "VidroQuebrado", Vector3.new(w - 0.2, h - 0.2, 0.1), cf, Enum.Material.Glass, Color3.fromRGB(150, 170, 165), { Transparency = 0.75, Shadow = false })
		local tilt = { 0.18, -0.12, 0.08 }
		for i = 1, 3 do
			local y = -h / 2 + (i - 0.5) * (h / 3)
			HouseKit.P(model, "Tabua", Vector3.new(w + 1.1, 0.75, 0.16), cf * CFrame.new(0, y, -t / 2 - 0.12) * CFrame.Angles(0, 0, tilt[i]), Enum.Material.WoodPlanks, Color3.fromRGB(96, 78, 58))
		end
	else
		local glassColor = if o.Frosted then Color3.fromRGB(226, 232, 230) else Color3.fromRGB(168, 196, 206)
		HouseKit.P(model, "Vidro", Vector3.new(w - 0.2, h - 0.2, 0.12), cf, Enum.Material.Glass, glassColor, { Transparency = if o.Frosted then 0.25 else 0.45, Shadow = false })
		HouseKit.P(model, "Travessa", Vector3.new(w - 0.2, 0.14, 0.2), cf, Enum.Material.Wood, pal.Trim, DECO)
		HouseKit.P(model, "Montante", Vector3.new(0.14, h - 0.2, 0.2), cf, Enum.Material.Wood, pal.Trim, DECO)
	end

	-- Caixilho interno (4 lados) na espessura da parede.
	HouseKit.P(model, "Caixilho", Vector3.new(w, 0.2, t + 0.1), cf * CFrame.new(0, h / 2 - 0.1, 0), Enum.Material.Wood, pal.Trim, DECO)
	HouseKit.P(model, "Caixilho", Vector3.new(w, 0.2, t + 0.1), cf * CFrame.new(0, -h / 2 + 0.1, 0), Enum.Material.Wood, pal.Trim, DECO)
	HouseKit.P(model, "Caixilho", Vector3.new(0.2, h, t + 0.1), cf * CFrame.new(-w / 2 + 0.1, 0, 0), Enum.Material.Wood, pal.Trim, DECO)
	HouseKit.P(model, "Caixilho", Vector3.new(0.2, h, t + 0.1), cf * CFrame.new(w / 2 - 0.1, 0, 0), Enum.Material.Wood, pal.Trim, DECO)

	-- Guarnição externa, peitoril e pingadeira.
	local faceOut = -t / 2 - 0.06
	HouseKit.P(model, "Guarnicao", Vector3.new(w + 0.9, 0.45, 0.12), cf * CFrame.new(0, h / 2 + 0.22, faceOut), Enum.Material.Wood, pal.Trim, DECO)
	HouseKit.P(model, "Guarnicao", Vector3.new(0.45, h, 0.12), cf * CFrame.new(-w / 2 - 0.22, 0, faceOut), Enum.Material.Wood, pal.Trim, DECO)
	HouseKit.P(model, "Guarnicao", Vector3.new(0.45, h, 0.12), cf * CFrame.new(w / 2 + 0.22, 0, faceOut), Enum.Material.Wood, pal.Trim, DECO)
	HouseKit.P(model, "Peitoril", Vector3.new(w + 1.1, 0.22, 0.75), cf * CFrame.new(0, -h / 2 - 0.11, -t / 2 - 0.3), Enum.Material.Wood, pal.Trim, DECO)
	-- Pingadeira interna (onde se apoia um vaso/garrafa).
	HouseKit.P(model, "Pingadeira", Vector3.new(w + 0.5, 0.16, 0.5), cf * CFrame.new(0, -h / 2 - 0.08, t / 2 + 0.2), Enum.Material.Wood, pal.Trim, DECO)

	if o.Shutters and not o.Boarded then
		for _, side in { -1, 1 } do
			local sx = side * (w / 2 + 0.45 + w / 4)
			local shutter = HouseKit.P(model, "Veneziana", Vector3.new(w / 2, h + 0.2, 0.14), cf * CFrame.new(sx, 0, faceOut - 0.05), Enum.Material.WoodPlanks, pal.Shutter, DECO)
			shutter.Name = "Veneziana"
			for k = -1, 1 do
				HouseKit.P(model, "VenezianaRipa", Vector3.new(w / 2 - 0.3, 0.12, 0.06), cf * CFrame.new(sx, k * h / 3.2, faceOut - 0.14), Enum.Material.Wood, pal.Trim, DECO)
			end
		end
	end

	if o.Curtains then
		local faceIn = t / 2 + 0.35
		HouseKit.P(model, "Varao", Vector3.new(w + 1.6, 0.14, 0.14), cf * CFrame.new(0, h / 2 + 0.6, faceIn), Enum.Material.Metal, Color3.fromRGB(60, 56, 50), DECO)
		for _, side in { -1, 1 } do
			HouseKit.P(model, "Cortina", Vector3.new(w * 0.3, h + 1.1, 0.1), cf * CFrame.new(side * (w / 2 - w * 0.1 + 0.35), 0.05, faceIn), Enum.Material.Fabric, o.Curtains, DECO)
		end
	end
	return model
end

--------------------------------------------------------------------------------
-- Porta (funcional -- DoorSystem)
--------------------------------------------------------------------------------

export type DoorOpts = {
	Name: string?,
	HingeAtEnd: boolean?, -- dobradiça no lado +along do vão (senão no lado -along)
	Thickness: number?,
	Glass: boolean?, -- porta de entrada com visor de vidro
	Color: Color3?,
}

--[[
	Door(parent, house, center, along, swing, width, height, pal, opts) -> folha
	center = meio do vão NO PISO (local). along = direção da parede (local),
	swing = pra onde a folha abre (local, perpendicular à parede).
	opts.HingeAtEnd escolhe de que lado do vão fica a dobradiça -- quem monta
	a casa escolhe o lado que deixa a folha aberta encostada numa parede.

	A folha é uma Part com Attribute Porta (DoorSystem cria o prompt e gira
	em volta da dobradiça). Almofadas, maçanetas e visor são SOLDADOS nela,
	então giram junto -- a maçaneta de Structures.Door ficava parada no ar.
	Batente (guarnição dos dois lados) é fixo, na parede.
]]
function HouseKit.Door(parent: Instance, house: CFrame, center: Vector3, along: Vector3, swing: Vector3, width: number, height: number, pal: Palette, opts: DoorOpts?): Part
	local o = opts or {}
	local t = o.Thickness or 1
	local model = HouseKit.Model(parent, o.Name or "Porta")
	-- LookVector = sentido de abertura (DoorSystem gira a folha pra ele).
	local frameCF = HouseKit.At(house, center + Vector3.new(0, height / 2, 0), swing)
	local worldAlong = (house * CFrame.new(along.X, along.Y, along.Z)).Position - house.Position
	local rightIsAlong = frameCF.RightVector:Dot(worldAlong) > 0
	-- DoorSystem: dobradiça no -X local da folha, ou no +X com DobradicaDireita.
	local hingeRight = if o.HingeAtEnd then rightIsAlong else not rightIsAlong

	local leafW, leafH = width - 0.25, height - 0.12
	local leafCF = frameCF * CFrame.new(0, -0.06, 0)
	local color = o.Color or pal.Door
	local leaf = HouseKit.P(model, "Porta", Vector3.new(leafW, leafH, 0.28), leafCF, Enum.Material.WoodPlanks, color)
	leaf:SetAttribute("Porta", true)
	leaf:SetAttribute("PortaAberta", false)
	leaf:SetAttribute("CFrameFechada", leafCF)
	leaf:SetAttribute("LarguraPorta", leafW)
	if hingeRight then
		leaf:SetAttribute("DobradicaDireita", true)
	end

	local hingeSign = if hingeRight then 1 else -1
	for _, face in { -1, 1 } do
		local z = face * 0.16
		if o.Glass then
			local visor = HouseKit.P(model, "Visor", Vector3.new(leafW * 0.5, leafH * 0.28, 0.06), leafCF * CFrame.new(0, leafH * 0.22, z), Enum.Material.Glass, Color3.fromRGB(150, 175, 180), { Collide = false, Transparency = 0.35, Shadow = false })
			HouseKit.Weld(leaf, visor)
		else
			local upper = HouseKit.P(model, "Almofada", Vector3.new(leafW * 0.62, leafH * 0.3, 0.06), leafCF * CFrame.new(0, leafH * 0.2, z), Enum.Material.Wood, color:Lerp(Color3.new(0, 0, 0), 0.18), DECO)
			HouseKit.Weld(leaf, upper)
		end
		local lower = HouseKit.P(model, "Almofada", Vector3.new(leafW * 0.62, leafH * 0.32, 0.06), leafCF * CFrame.new(0, -leafH * 0.22, z), Enum.Material.Wood, color:Lerp(Color3.new(0, 0, 0), 0.18), DECO)
		HouseKit.Weld(leaf, lower)
		local knob = HouseKit.P(model, "Macaneta", Vector3.new(0.34, 0.34, 0.34), leafCF * CFrame.new(-hingeSign * (leafW / 2 - 0.45), -leafH / 2 + 3.6, face * 0.3), Enum.Material.Metal, Color3.fromRGB(176, 150, 96), { Collide = false, Shape = Enum.PartType.Ball })
		HouseKit.Weld(leaf, knob)
	end
	for _, y in { leafH * 0.32, -leafH * 0.32 } do
		local hinge = HouseKit.P(model, "Dobradica", Vector3.new(0.12, 0.6, 0.34), leafCF * CFrame.new(hingeSign * (leafW / 2 - 0.02), y, 0), Enum.Material.Metal, Color3.fromRGB(58, 54, 50), DECO)
		HouseKit.Weld(leaf, hinge)
	end

	-- Batente/guarnição fixos nas duas faces da parede.
	for _, face in { -1, 1 } do
		local z = face * (t / 2 + 0.07)
		HouseKit.P(model, "Guarnicao", Vector3.new(0.45, height + 0.35, 0.14), frameCF * CFrame.new(-width / 2 - 0.22, 0.17, z), Enum.Material.Wood, pal.Trim, DECO)
		HouseKit.P(model, "Guarnicao", Vector3.new(0.45, height + 0.35, 0.14), frameCF * CFrame.new(width / 2 + 0.22, 0.17, z), Enum.Material.Wood, pal.Trim, DECO)
		HouseKit.P(model, "Guarnicao", Vector3.new(width + 0.9, 0.45, 0.14), frameCF * CFrame.new(0, height / 2 + 0.22, z), Enum.Material.Wood, pal.Trim, DECO)
	end
	return leaf
end

-- Passagem sem porta: só guarnição dos dois lados (arco de sala).
function HouseKit.CasedOpening(parent: Instance, house: CFrame, center: Vector3, along: Vector3, width: number, height: number, pal: Palette, thickness: number?)
	local t = thickness or 1
	local normal = Vector3.new(-along.Z, 0, along.X)
	local cf = HouseKit.At(house, center + Vector3.new(0, height / 2, 0), normal)
	for _, face in { -1, 1 } do
		local z = face * (t / 2 + 0.07)
		HouseKit.P(parent, "Guarnicao", Vector3.new(0.45, height + 0.35, 0.14), cf * CFrame.new(-width / 2 - 0.22, 0.17, z), Enum.Material.Wood, pal.Trim, DECO)
		HouseKit.P(parent, "Guarnicao", Vector3.new(0.45, height + 0.35, 0.14), cf * CFrame.new(width / 2 + 0.22, 0.17, z), Enum.Material.Wood, pal.Trim, DECO)
		HouseKit.P(parent, "Guarnicao", Vector3.new(width + 0.9, 0.45, 0.14), cf * CFrame.new(0, height / 2 + 0.22, z), Enum.Material.Wood, pal.Trim, DECO)
	end
	-- Forro do vão (a espessura da parede à mostra fica em madeira).
	HouseKit.P(parent, "VaoTopo", Vector3.new(width, 0.12, t + 0.02), cf * CFrame.new(0, height / 2 - 0.06, 0), Enum.Material.Wood, pal.Trim, DECO)
end

--------------------------------------------------------------------------------
-- Telhado
--------------------------------------------------------------------------------

--[[
	RoofSlope(parent, house, ridgeA, ridgeB, down, run, pitchDeg, color, thickness?, fascia?)
	Uma água do telhado. ridgeA/ridgeB = pontos da cumeeira (locais, na
	altura da cumeeira). down = direção horizontal (local, unitária) em que a
	água desce; run = distância horizontal da cumeeira até a borda do beiral.
	A face DE BAIXO da placa passa exatamente pela linha cumeeira-parede, então
	o telhado assenta no topo da parede sem fresta. fascia = false omite a
	testeira (água que termina rente à parede, sem beiral, por dentro da casa).
]]
function HouseKit.RoofSlope(parent: Instance, house: CFrame, ridgeA: Vector3, ridgeB: Vector3, down: Vector3, run: number, pitchDeg: number, color: Color3, thickness: number?, fascia: boolean?, mat: Enum.Material?)
	local th = thickness or 0.55
	local p = math.rad(pitchDeg)
	local slope = (down + Vector3.new(0, -math.tan(p), 0)).Unit
	local ridgeDir = (ridgeB - ridgeA).Unit
	local normal = ridgeDir:Cross(slope)
	if normal.Y < 0 then
		normal = -normal
	end
	local len = (ridgeB - ridgeA).Magnitude
	local slabW = run / math.cos(p)
	local center = (ridgeA + ridgeB) / 2 + slope * (slabW / 2) + normal * (th / 2)
	local cf = house * CFrame.fromMatrix(center, slope, normal)
	HouseKit.P(parent, "Telhado", Vector3.new(slabW, th, len), cf, mat or HouseKit.Mat.Shingles, color)
	if fascia == false then
		return
	end
	-- Testeira (tábua na borda do beiral).
	local eave = (ridgeA + ridgeB) / 2 + slope * slabW
	HouseKit.P(parent, "Testeira", Vector3.new(0.25, 0.7, len), house * CFrame.fromMatrix(eave + Vector3.new(0, -0.1, 0), down, Vector3.new(0, 1, 0)), Enum.Material.Wood, Color3.fromRGB(58, 46, 38), DECO)
end

--[[
	GableEnd(parent, house, center, along, span, rise, thickness, mat, color)
	Empena triangular: `center` = meio da base do triângulo (local, no topo
	da parede), `along` = direção da base (local), span = largura da base.
]]
function HouseKit.GableEnd(parent: Instance, house: CFrame, center: Vector3, along: Vector3, span: number, rise: number, thickness: number, mat: Enum.Material, color: Color3)
	local normal = Vector3.new(-along.Z, 0, along.X)
	-- WedgePart: rampa sobe de -Z (baixo) pra +Z (alto); face vertical em +Z.
	-- Metade de `along` positivo: +Z do wedge aponta pro centro (-along).
	for _, side in { -1, 1 } do
		local mid = center + along * (side * span / 4) + Vector3.new(0, rise / 2, 0)
		local back = along * (-side) -- +Z do wedge: sentido do centro da empena
		-- X = side*normal mantém a base destra (X × Y = Z) nas duas metades.
		local cf = house * CFrame.fromMatrix(mid, normal * side, Vector3.new(0, 1, 0), back)
		HouseKit.Wedge(parent, "Empena", Vector3.new(thickness, rise, span / 2), cf, mat, color)
	end
end

function HouseKit.RidgeCap(parent: Instance, house: CFrame, a: Vector3, b: Vector3, color: Color3, mat: Enum.Material?)
	local dir = (b - a).Unit
	local mid = (a + b) / 2 + Vector3.new(0, 0.3, 0)
	HouseKit.P(parent, "Cumeeira", Vector3.new(0.9, 0.35, (b - a).Magnitude), house * CFrame.fromMatrix(mid, Vector3.new(-dir.Z, 0, dir.X), Vector3.new(0, 1, 0)), mat or HouseKit.Mat.Shingles, color:Lerp(Color3.new(0, 0, 0), 0.2), DECO)
end

--------------------------------------------------------------------------------
-- Varanda, escada, guarda-corpo, pilar
--------------------------------------------------------------------------------

function HouseKit.Deck(parent: Instance, house: CFrame, x0: number, x1: number, z0: number, z1: number, found: number, pal: Palette)
	local w, d = x1 - x0, z1 - z0
	HouseKit.P(parent, "Deck", Vector3.new(w, 0.5, d), house * CFrame.new((x0 + x1) / 2, -0.25, (z0 + z1) / 2), Enum.Material.WoodPlanks, pal.Deck)
	-- Saia do deck (esconde o vão até o chão) e pilares de apoio.
	local skirtH = found + 1.2 + HouseKit.ExtraDepth
	local cx, cz = (x0 + x1) / 2, (z0 + z1) / 2
	local sides = {
		{ Vector3.new(cx, 0, z0), Vector3.new(w, 0, 0) },
		{ Vector3.new(cx, 0, z1), Vector3.new(w, 0, 0) },
		{ Vector3.new(x0, 0, cz), Vector3.new(0, 0, d) },
		{ Vector3.new(x1, 0, cz), Vector3.new(0, 0, d) },
	}
	for _, s in sides do
		local pos, span = s[1], s[2]
		local size = Vector3.new(math.max(span.X, 0.3), skirtH, math.max(span.Z, 0.3))
		HouseKit.P(parent, "SaiaDeck", size, house * CFrame.new(pos.X, -0.5 - skirtH / 2, pos.Z), Enum.Material.WoodPlanks, pal.Trim:Lerp(pal.Deck, 0.6))
	end
end

export type StairOpts = {
	Run: number?, -- profundidade de cada degrau (default 1,15)
	Interior: boolean?, -- escada interna: degraus "DegrauInterno", maciços só até o piso de baixo
	Color: Color3?,
}

--[[
	Stairs(parent, house, top, down, width, rise, pal, opts?) -> distância horizontal
	`top` = meio da borda superior (local, na altura do piso), `down` =
	direção horizontal (local) em que a escada desce. Degraus de no máximo
	0,6 de espelho -- o Humanoid sobe sem pular. Externa: maciça até abaixo
	do terreno (ExtraDepth incluso). Interna: maciça até o piso de baixo.
]]
function HouseKit.Stairs(parent: Instance, house: CFrame, top: Vector3, down: Vector3, width: number, rise: number, pal: Palette, opts: StairOpts?): number
	local o = opts or {}
	local steps = math.max(1, math.ceil(rise / 0.6))
	local stepRise = rise / steps
	local run = o.Run or 1.15
	local along = Vector3.new(-down.Z, 0, down.X)
	local bottom = if o.Interior then top.Y - rise else top.Y - rise - 1.5 - HouseKit.ExtraDepth
	local count = if o.Interior then steps - 1 else steps -- o último degrau interno seria o próprio piso
	for i = 1, count do
		local treadY = top.Y - i * stepRise
		local h = treadY - bottom
		local pos = top + down * ((i - 0.5) * run)
		local cf = house * CFrame.fromMatrix(Vector3.new(pos.X, bottom + h / 2, pos.Z), along, Vector3.new(0, 1, 0))
		HouseKit.P(parent, if o.Interior then "DegrauInterno" else "Degrau", Vector3.new(width, h, run), cf, Enum.Material.WoodPlanks, o.Color or pal.Deck)
	end
	-- Laterais (longarinas).
	local total = steps * run
	for _, side in { -1, 1 } do
		local base = top + along * (side * (width / 2 + 0.15)) + down * (total / 2)
		local cf = house * CFrame.fromMatrix(Vector3.new(base.X, top.Y - rise / 2 - 0.2, base.Z), along, Vector3.new(0, 1, 0))
		-- +Z local aponta pra casa (topo): inclina esse lado pra cima.
		HouseKit.P(parent, "Longarina", Vector3.new(0.3, 0.9, math.sqrt(total * total + rise * rise)), cf * CFrame.Angles(-math.atan2(rise, total), 0, 0), Enum.Material.Wood, pal.Trim, DECO)
	end
	return total
end

function HouseKit.Post(parent: Instance, house: CFrame, x: number, z: number, y0: number, y1: number, pal: Palette, size: number?)
	local s = size or 0.75
	HouseKit.P(parent, "Pilar", Vector3.new(s, y1 - y0, s), house * CFrame.new(x, (y0 + y1) / 2, z), Enum.Material.Wood, pal.Trim)
	HouseKit.P(parent, "PilarBase", Vector3.new(s + 0.3, 0.4, s + 0.3), house * CFrame.new(x, y0 + 0.2, z), Enum.Material.Wood, pal.Trim, DECO)
end

--[[
	Railing(parent, house, a, b, pal) -- guarda-corpo de a até b (locais, no
	piso da varanda). Corrimão colide (não dá pra cair do deck), balaústres não.
]]
function HouseKit.Railing(parent: Instance, house: CFrame, a: Vector3, b: Vector3, pal: Palette)
	local len = (b - a).Magnitude
	if len < 0.5 then
		return
	end
	local dir = (b - a).Unit
	local mid = (a + b) / 2
	HouseKit.P(parent, "Corrimao", Vector3.new(len, 0.28, 0.4), house * CFrame.fromMatrix(mid + Vector3.new(0, 3.1, 0), dir, Vector3.new(0, 1, 0)), Enum.Material.Wood, pal.Trim)
	HouseKit.P(parent, "Travessa", Vector3.new(len, 0.2, 0.25), house * CFrame.fromMatrix(mid + Vector3.new(0, 0.45, 0), dir, Vector3.new(0, 1, 0)), Enum.Material.Wood, pal.Trim, DECO)
	-- Barreira invisível até a altura do corrimão (os balaústres são detalhe).
	HouseKit.P(parent, "GuardaCorpo", Vector3.new(len, 3.0, 0.2), house * CFrame.fromMatrix(mid + Vector3.new(0, 1.6, 0), dir, Vector3.new(0, 1, 0)), Enum.Material.SmoothPlastic, pal.Trim, { Transparency = 1, Shadow = false })
	local count = math.max(1, math.floor(len / 1.05))
	for i = 1, count - 1 do
		local p = a + dir * (i * len / count)
		HouseKit.P(parent, "Balaustre", Vector3.new(0.22, 2.6, 0.22), house * CFrame.new(p.X, p.Y + 1.75, p.Z), Enum.Material.Wood, pal.Trim, DECO)
	end
end

--------------------------------------------------------------------------------
-- Luminárias
--------------------------------------------------------------------------------

local REFERENCE_FOLDER = "Modelos para as casas"

-- Caixa alinhada ao mundo de todas as BaseParts de `root`.
function HouseKit.WorldBounds(root: Instance): (Vector3, Vector3)
	local lo = Vector3.new(math.huge, math.huge, math.huge)
	local hi = Vector3.new(-math.huge, -math.huge, -math.huge)
	local parts: { Instance } = root:GetDescendants()
	if root:IsA("BasePart") then
		table.insert(parts, root)
	end
	for _, d in parts do
		if d:IsA("BasePart") then
			local cf, s = d.CFrame, d.Size
			local r, u, l = cf.RightVector, cf.UpVector, cf.LookVector
			local ex = (math.abs(r.X) * s.X + math.abs(u.X) * s.Y + math.abs(l.X) * s.Z) / 2
			local ey = (math.abs(r.Y) * s.X + math.abs(u.Y) * s.Y + math.abs(l.Y) * s.Z) / 2
			local ez = (math.abs(r.Z) * s.X + math.abs(u.Z) * s.Y + math.abs(l.Z) * s.Z) / 2
			local p = cf.Position
			lo = Vector3.new(math.min(lo.X, p.X - ex), math.min(lo.Y, p.Y - ey), math.min(lo.Z, p.Z - ez))
			hi = Vector3.new(math.max(hi.X, p.X + ex), math.max(hi.Y, p.Y + ey), math.max(hi.Z, p.Z + ez))
		end
	end
	return lo, hi
end

--[[
	CloneReference(...nomes) -> Model?
	Clona o primeiro modelo existente em Workspace["Modelos para as casas"]
	(nunca mexe no original): ancorado, sem Script/ClickDetector (o modelo
	"Door" do Toolbox, por exemplo, trazia um script próprio de clique).
]]
function HouseKit.CloneReference(...: string): Model?
	local folder = Workspace:FindFirstChild(REFERENCE_FOLDER)
	if not folder then
		return nil
	end
	for _, name in { ... } do
		local source = folder:FindFirstChild(name)
		if source and source:IsA("Model") then
			local ok, clone = pcall(function()
				return source:Clone()
			end)
			if ok and clone then
				for _, d in clone:GetDescendants() do
					if d:IsA("BasePart") then
						d.Anchored = true
						d.CanTouch = false
					elseif d:IsA("LuaSourceContainer") or d:IsA("ClickDetector") then
						d:Destroy()
					end
				end
				return clone :: Model
			end
		end
	end
	return nil
end

--[[
	PlaceReference(model, parent, house, pos, yaw, align)
	Mantém a orientação ORIGINAL do modelo de referência (ele está de pé na
	pasta), só gira em volta do Y e translada. Depois acerta pela caixa real:
	"Floor" = base encostada em pos.Y; "Ceiling" = topo encostado em pos.Y.
	(O pivot desses modelos do Toolbox não é a base -- a cama da primeira
	versão da cabana ficou afundada até a metade no piso por isso.)
]]
function HouseKit.PlaceReference(model: Model, parent: Instance, house: CFrame, pos: Vector3, yaw: number, align: string)
	model.Parent = parent
	local pivot = model:GetPivot()
	local rotation = pivot - pivot.Position
	local target = house * CFrame.new(pos.X, pos.Y, pos.Z)
	local houseYaw = house - house.Position
	model:PivotTo(CFrame.new(target.Position) * houseYaw * CFrame.Angles(0, yaw, 0) * rotation)
	local lo, hi = HouseKit.WorldBounds(model)
	local center = (lo + hi) / 2
	local dy = if align == "Ceiling" then target.Position.Y - hi.Y else target.Position.Y - lo.Y
	local delta = Vector3.new(target.Position.X - center.X, dy, target.Position.Z - center.Z)
	model:PivotTo(model:GetPivot() + delta)
end

--[[
	CeilingLight(parent, house, pos, lit, brightness, compact?)
	Pendente de teto. Usa "ceiling ligh" de Workspace["Modelos para as casas"]
	quando existe (luz própria dele ajustada), senão monta um pendente de
	chapa com lâmpada. `pos` = ponto no forro (local). compact = sempre o
	pendente próprio (o de referência tem 5 de largura e desce 3,5: não cabe
	em banheiro/corredor sem bater na porta).
]]
function HouseKit.CeilingLight(parent: Instance, house: CFrame, pos: Vector3, lit: boolean, brightness: number?, compact: boolean?)
	local b = brightness or 0.6
	local ref = if compact then nil else HouseKit.CloneReference("ceiling ligh", "ceiling light", "Ceiling Light")
	if ref then
		ref.Name = "Luminaria"
		HouseKit.PlaceReference(ref, parent, house, pos, 0, "Ceiling")
		for _, d in ref:GetDescendants() do
			if d:IsA("BasePart") then
				d.CanCollide = false
				d.CanQuery = false
			elseif d:IsA("PointLight") then
				d.Brightness = b
				d.Range = 18
				d.Shadows = false
				d.Enabled = lit
				d.Color = HouseKit.WarmLight
			end
		end
		return
	end

	local model = HouseKit.Model(parent, "Luminaria")
	local top = house * CFrame.new(pos.X, pos.Y, pos.Z)
	HouseKit.P(model, "Canopla", Vector3.new(0.25, 0.9, 0.9), top * CFrame.new(0, -0.12, 0) * CFrame.Angles(0, 0, math.pi / 2), Enum.Material.Metal, Color3.fromRGB(60, 56, 50), { Collide = false, Shape = Enum.PartType.Cylinder })
	HouseKit.P(model, "Haste", Vector3.new(1.8, 0.1, 0.1), top * CFrame.new(0, -1.1, 0) * CFrame.Angles(0, 0, math.pi / 2), Enum.Material.Metal, Color3.fromRGB(40, 38, 36), { Collide = false, Shape = Enum.PartType.Cylinder })
	HouseKit.P(model, "Cupula", Vector3.new(0.9, 2.2, 2.2), top * CFrame.new(0, -2.2, 0) * CFrame.Angles(0, 0, math.pi / 2), Enum.Material.Metal, Color3.fromRGB(64, 78, 66), { Collide = false, Shape = Enum.PartType.Cylinder })
	local bulb = HouseKit.P(model, "Lampada", Vector3.new(0.6, 0.6, 0.6), top * CFrame.new(0, -2.75, 0), if lit then Enum.Material.Neon else Enum.Material.Glass, if lit then Color3.fromRGB(255, 214, 160) else Color3.fromRGB(200, 196, 180), { Collide = false, Shape = Enum.PartType.Ball })
	HouseKit.Light(bulb, HouseKit.WarmLight, 18, b, lit)
end

--[[
	WallLantern(parent, house, pos, outward, lit) -- arandela de varanda.
	`pos` = ponto na face da parede (local). É o que deixa cada casa visível
	de longe na noite -- referência de navegação, não só enfeite.
]]
function HouseKit.WallLantern(parent: Instance, house: CFrame, pos: Vector3, outward: Vector3, lit: boolean)
	local model = HouseKit.Model(parent, "Arandela")
	local cf = HouseKit.At(house, pos, outward)
	local iron = Color3.fromRGB(34, 32, 30)
	HouseKit.P(model, "Base", Vector3.new(0.6, 1.1, 0.15), cf * CFrame.new(0, 0, -0.07), Enum.Material.Metal, iron, DECO)
	HouseKit.P(model, "Braco", Vector3.new(0.14, 0.14, 0.8), cf * CFrame.new(0, 0.3, -0.45), Enum.Material.Metal, iron, DECO)
	HouseKit.P(model, "Teto", Vector3.new(0.8, 0.15, 0.8), cf * CFrame.new(0, 0.55, -0.9), Enum.Material.Metal, iron, DECO)
	HouseKit.P(model, "Caixa", Vector3.new(0.62, 0.9, 0.62), cf * CFrame.new(0, 0.05, -0.9), Enum.Material.Glass, Color3.fromRGB(255, 226, 170), { Collide = false, Transparency = 0.45, Shadow = false })
	local flame = HouseKit.P(model, "Chama", Vector3.new(0.25, 0.4, 0.25), cf * CFrame.new(0, 0.0, -0.9), if lit then Enum.Material.Neon else Enum.Material.Glass, if lit then Color3.fromRGB(255, 190, 110) else Color3.fromRGB(120, 110, 100), DECO)
	HouseKit.Light(flame, Color3.fromRGB(255, 180, 110), 22, 0.9, lit)
end

return HouseKit
