--!strict
--[[
	CasaDaFazenda (fazenda do Campo)
	Casa velha de fazenda de DOIS andares -- diferente das outras duas:
	tábua creme descascando, acabamento verde-escuro, telhado de zinco
	enferrujado bem inclinado, chaminé de tijolo, varanda em L com balanço,
	e a cozinha num puxado nos fundos (casa que "cresceu" com o tempo).

	  Térreo:  sala de estar (lareira, piano, relógio de pêndulo) | hall com
	           escada | sala de jantar (mesa comprida, cristaleira)
	           + cozinha no puxado (fogão a lenha, pia, geladeira velha)
	  Andar:   quarto do casal | corredor com vão da escada | quarto das
	           crianças (2 camas, baú de brinquedos, boneca)
	  Quintal: cata-vento de bomba d'água, poço com telhadinho, casinha
	           (banheiro de fora) com porta que abre -- esconderijo.

	Três saídas no térreo: frente, lateral (varanda) e fundos (cozinha).
	Coordenadas locais: piso do térreo em y = 0, frente = -Z.
]]

local Structures = require(script.Parent.Parent.Structures)
local Kit = require(script.Parent.HouseKit)
local Furniture = require(script.Parent.Furniture)

local CasaDaFazenda = {}

CasaDaFazenda.Style = "CasaDaFazenda"
CasaDaFazenda.Found = 2.0
CasaDaFazenda.Footprint = { MinX = -37, MaxX = 28.8, MinZ = -26.4, MaxZ = 34 }
-- A construção em si: o piso fica acima do ponto mais alto do terreno aqui
-- dentro, e o chão vira terra batida (sem grama).
CasaDaFazenda.Core = {
	{ MinX = -20.5, MaxX = 20.5, MinZ = -14.5, MaxZ = 14.5 },
	{ MinX = -12.5, MaxX = 12.5, MinZ = 14.5, MaxZ = 25.5 },
}
CasaDaFazenda.Entrances = {
	Vector3.new(-1.5, 0, -26.2), -- pé da escada da varanda
	Vector3.new(5.25, 0, 33.4), -- pé da escada da cozinha
}

local W, D = 40, 28
local HW, HD = W / 2, D / 2
local G = 10.5 -- teto do térreo (base da laje)
local U = 11.5 -- piso do andar de cima
local TOP = 21 -- topo das paredes / forro do andar
local PITCH = 42
local LH = 8.8 -- pé-direito do puxado da cozinha
local WY0, WY1 = 3.2, 8.2 -- janelas do térreo
local UY0, UY1 = U + 2.7, U + 7.2 -- janelas do andar
local DOOR_H = 8.2

local UPRIGHT = CFrame.Angles(0, 0, math.pi / 2)

local function palette(rng: Random): Kit.Palette
	local peel = rng:NextNumber(0.08, 0.25)
	return {
		Siding = Color3.fromRGB(206, 196, 170):Lerp(Color3.fromRGB(150, 140, 122), peel),
		SidingMat = Enum.Material.WoodPlanks,
		Interior = Color3.fromRGB(176, 162, 128), -- papel de parede amarelado
		InteriorMat = Kit.Mat.Plaster,
		Trim = Color3.fromRGB(62, 78, 64),
		Roof = Color3.fromRGB(134, 84, 58),
		Floor = Color3.fromRGB(112, 80, 52),
		Ceiling = Color3.fromRGB(196, 186, 160),
		CeilingMat = Kit.Mat.Plaster,
		Foundation = Color3.fromRGB(128, 96, 84),
		FoundationMat = Enum.Material.Brick,
		Shutter = Color3.fromRGB(62, 78, 64),
		Door = Color3.fromRGB(62, 78, 64),
		Deck = Color3.fromRGB(128, 112, 92),
	}
end

--------------------------------------------------------------------------------
-- Quintal
--------------------------------------------------------------------------------

-- Cata-vento de bomba d'água (torre treliçada + roda de pás + leme).
local function windmill(parent: Instance, house: CFrame, x: number, z: number, groundY: number)
	local model = Kit.Model(parent, "CataVento")
	local steel = Color3.fromRGB(96, 94, 90)
	local height = 36
	local baseHalf, topHalf = 3.4, 0.9
	for _, sx in { -1, 1 } do
		for _, sz in { -1, 1 } do
			local a = Vector3.new(x + sx * baseHalf, groundY - 1 - Kit.ExtraDepth, z + sz * baseHalf)
			local b = Vector3.new(x + sx * topHalf, groundY + height, z + sz * topHalf)
			local mid = (a + b) / 2
			Kit.P(model, "Perna", Vector3.new(0.35, 0.35, (b - a).Magnitude), house * CFrame.lookAt(mid, b), Enum.Material.Metal, steel)
		end
	end
	for level = 1, 5 do
		local t = level / 6
		local y = groundY + height * t
		local half = baseHalf + (topHalf - baseHalf) * t
		for _, side in { -1, 1 } do
			Kit.P(model, "Travessa", Vector3.new(half * 2, 0.15, 0.15), house * CFrame.new(x, y, z + side * half), Enum.Material.Metal, steel, Kit.Deco)
			Kit.P(model, "Travessa", Vector3.new(0.15, 0.15, half * 2), house * CFrame.new(x + side * half, y, z), Enum.Material.Metal, steel, Kit.Deco)
		end
	end
	local hub = house * CFrame.new(x, groundY + height + 1.2, z) * CFrame.Angles(0, 0.6, 0)
	Kit.P(model, "Plataforma", Vector3.new(2.6, 0.3, 2.6), house * CFrame.new(x, groundY + height, z), Enum.Material.WoodPlanks, Color3.fromRGB(96, 80, 60), Kit.Deco)
	Kit.P(model, "Cubo", Vector3.new(1.4, 1.0, 1.0), hub * CFrame.new(0, 0, -0.8) * CFrame.Angles(0, math.pi / 2, 0), Enum.Material.Metal, steel, { Collide = false, Shape = Enum.PartType.Cylinder })
	for i = 0, 17 do
		local a = i / 18 * math.pi * 2
		Kit.P(model, "Pa", Vector3.new(0.9, 4.2, 0.08), hub * CFrame.new(0, 0, -1.4) * CFrame.Angles(0, 0, a) * CFrame.new(0, 3.2, 0) * CFrame.Angles(0, 0.35, 0), Enum.Material.Metal, Color3.fromRGB(150, 146, 136), Kit.Deco)
	end
	Kit.P(model, "Aro", Vector3.new(0.12, 10.8, 10.8), hub * CFrame.new(0, 0, -1.35) * CFrame.Angles(0, math.pi / 2, 0), Enum.Material.Metal, steel, { Collide = false, Shape = Enum.PartType.Cylinder, Transparency = 0.9 })
	Kit.P(model, "Cauda", Vector3.new(0.15, 0.15, 5.0), hub * CFrame.new(0, 0, 2.2), Enum.Material.Metal, steel, Kit.Deco)
	Kit.P(model, "Leme", Vector3.new(0.08, 2.4, 3.0), hub * CFrame.new(0, 0.3, 4.6), Enum.Material.Metal, Color3.fromRGB(150, 60, 44), Kit.Deco)
	-- Bomba e cocho na base.
	Kit.P(model, "Bomba", Vector3.new(0.5, 3.4, 0.5), house * CFrame.new(x, groundY + 1.7, z), Enum.Material.Metal, Color3.fromRGB(40, 38, 36))
	Furniture.Trough(model, Kit.At(house, Vector3.new(x + 2.2, groundY, z - 3.4), Vector3.new(1, 0, 0)), 4.5)
end

local function well(parent: Instance, house: CFrame, x: number, z: number, groundY: number)
	local model = Kit.Model(parent, "Poco")
	local stone = Color3.fromRGB(118, 112, 104)
	local base = house * CFrame.new(x, groundY, z)
	Kit.P(model, "Boca", Vector3.new(3.2 + Kit.ExtraDepth, 5.2, 5.2), base * CFrame.new(0, (3.2 - Kit.ExtraDepth) / 2 - 1.0, 0) * UPRIGHT, Enum.Material.Cobblestone, stone, { Shape = Enum.PartType.Cylinder })
	Kit.P(model, "Agua", Vector3.new(0.1, 4.0, 4.0), base * CFrame.new(0, 2.25, 0) * UPRIGHT, Enum.Material.Slate, Color3.fromRGB(16, 18, 18), { Collide = false, Shape = Enum.PartType.Cylinder })
	for _, sx in { -1, 1 } do
		Kit.P(model, "Poste", Vector3.new(0.5, 6.4, 0.5), base * CFrame.new(sx * 2.5, 3.2, 0), Enum.Material.Wood, Color3.fromRGB(86, 64, 44))
	end
	Kit.P(model, "Eixo", Vector3.new(5.6, 0.35, 0.35), base * CFrame.new(0, 4.8, 0), Enum.Material.Wood, Color3.fromRGB(86, 64, 44), { Collide = false, Shape = Enum.PartType.Cylinder })
	Kit.P(model, "Manivela", Vector3.new(0.2, 1.0, 0.2), base * CFrame.new(3.0, 4.4, 0), Enum.Material.Metal, Color3.fromRGB(40, 38, 36), Kit.Deco)
	Kit.P(model, "Corda", Vector3.new(0.08, 1.6, 0.08), base * CFrame.new(0, 3.9, 0), Enum.Material.Fabric, Color3.fromRGB(170, 140, 90), Kit.Deco)
	Kit.P(model, "Balde", Vector3.new(0.9, 0.8, 0.8), base * CFrame.new(0, 2.8, 0) * UPRIGHT, Enum.Material.Metal, Color3.fromRGB(110, 106, 98), { Collide = false, Shape = Enum.PartType.Cylinder })
	for _, side in { -1, 1 } do
		Kit.P(model, "Telhadinho", Vector3.new(6.4, 0.25, 2.4), base * CFrame.new(0, 6.9, side * 1.0) * CFrame.Angles(side * math.rad(-32), 0, 0), Enum.Material.WoodPlanks, Color3.fromRGB(96, 70, 50))
	end
end

-- Casinha (banheiro de fora) com porta que abre pra fora. cf = chão, frente -Z.
local function outhouse(parent: Instance, house: CFrame, pos: Vector3, look: Vector3, pal: Kit.Palette)
	local model = Kit.Model(parent, "Casinha")
	local cf = Kit.At(house, pos, look)
	local wood = Color3.fromRGB(116, 96, 70)
	local w, d, h = 5, 5, 8
	Kit.P(model, "Base", Vector3.new(w + 0.4, 0.5 + Kit.ExtraDepth, d + 0.4), cf * CFrame.new(0, 0.25 - Kit.ExtraDepth / 2, 0), Enum.Material.WoodPlanks, wood)
	local floorCF = cf * CFrame.new(0, 0.5, 0)
	-- Frente com vão da porta (3 x 6,6); fundos e laterais cheios.
	Structures.WallWithOpenings(model, floorCF * CFrame.new(0, 0, -d / 2), w, h, 0.4, { { x0 = -1.5, x1 = 1.5, y0 = 0, y1 = 6.6 } }, Enum.Material.WoodPlanks, wood)
	Structures.WallWithOpenings(model, floorCF * CFrame.new(0, 0, d / 2), w, h - 0.8, 0.4, {}, Enum.Material.WoodPlanks, wood)
	for _, sx in { -1, 1 } do
		Structures.WallWithOpenings(model, floorCF * CFrame.new(sx * w / 2, 0, 0) * CFrame.Angles(0, math.pi / 2, 0), d - 0.4, h - 0.4, 0.4, {}, Enum.Material.WoodPlanks, wood)
	end
	Kit.P(model, "Telhado", Vector3.new(w + 1.2, 0.35, d + 1.6), floorCF * CFrame.new(0, h - 0.3, 0) * CFrame.Angles(math.rad(-8), 0, 0), Enum.Material.CorrodedMetal, pal.Roof)
	Kit.P(model, "Banco", Vector3.new(w - 0.8, 2.2, 1.8), floorCF * CFrame.new(0, 1.1, d / 2 - 1.1), Enum.Material.WoodPlanks, wood:Lerp(Color3.new(0, 0, 0), 0.15))
	Kit.P(model, "Buraco", Vector3.new(0.05, 0.9, 0.9), floorCF * CFrame.new(0, 2.22, d / 2 - 1.1) * UPRIGHT, Enum.Material.SmoothPlastic, Color3.new(0, 0, 0), { Collide = false, Shape = Enum.PartType.Cylinder })
	-- Porta: abre pra fora (-Z local), dobradiça à esquerda.
	local leafCF = floorCF * CFrame.new(0, 3.24, -d / 2 - 0.35) * CFrame.Angles(0, 0, 0)
	local leaf = Kit.P(model, "Porta", Vector3.new(2.85, 6.48, 0.2), leafCF, Enum.Material.WoodPlanks, wood:Lerp(Color3.new(0, 0, 0), 0.1))
	leaf:SetAttribute("Porta", true)
	leaf:SetAttribute("PortaAberta", false)
	leaf:SetAttribute("CFrameFechada", leafCF)
	leaf:SetAttribute("LarguraPorta", 2.85)
	local moon = Kit.P(model, "Lua", Vector3.new(0.6, 0.9, 0.06), leafCF * CFrame.new(0, 2.3, -0.12), Enum.Material.SmoothPlastic, Color3.fromRGB(20, 18, 16), Kit.Deco)
	Kit.Weld(leaf, moon)
	local handle = Kit.P(model, "Macaneta", Vector3.new(0.3, 0.3, 0.3), leafCF * CFrame.new(1.1, -0.3, -0.2), Enum.Material.Metal, Color3.fromRGB(40, 38, 36), { Collide = false, Shape = Enum.PartType.Ball })
	Kit.Weld(leaf, handle)
end

--------------------------------------------------------------------------------
-- Build
--------------------------------------------------------------------------------

export type BuildOpts = { Name: string?, Seed: number? }

function CasaDaFazenda.Build(parent: Instance, house: CFrame, opts: BuildOpts?): Model
	local o = opts or {}
	local rng = Random.new(o.Seed or 1)
	local pal = palette(rng)
	local found = CasaDaFazenda.Found
	local ground = -found

	local model = Kit.Model(parent, o.Name or "CasaDaFazenda")
	local S = Kit.Folder(model, "Estrutura")
	local Doors = Kit.Folder(model, "Portas")
	local Win = Kit.Folder(model, "Janelas")
	local Props = Kit.Folder(model, "Moveis")
	local Lights = Kit.Folder(model, "Luzes")
	local Out = Kit.Folder(model, "Externo")

	local function at(x: number, y: number, z: number, look: Vector3?): CFrame
		return Kit.At(house, Vector3.new(x, y, z), look)
	end
	local function v(x: number, z: number, y: number?): Vector3
		return Vector3.new(x, y or 0, z)
	end
	local X, Z = Vector3.new(1, 0, 0), Vector3.new(0, 0, 1)
	local tin = Enum.Material.CorrodedMetal

	----------------------------------------------------------------------------
	-- Fundação, pisos, lajes
	----------------------------------------------------------------------------

	Kit.Foundation(S, house, -HW - 0.5, HW + 0.5, -HD - 0.5, HD + 0.5, found, pal)
	Kit.Foundation(S, house, -12.5, 12.5, HD + 0.5, 25.5, found, pal)
	local floor = Kit.Floor(S, house, -HW - 0.5, HW + 0.5, -HD - 0.5, HD + 0.5, Enum.Material.WoodPlanks, pal.Floor)
	Kit.Floor(S, house, -12.5, 12.5, HD + 0.5, 25.5, Enum.Material.WoodPlanks, pal.Floor, "PisoAnexo")
	Kit.FloorFinish(S, house, -11.5, 11.5, HD + 0.5, 24.5, Enum.Material.Slate, Color3.fromRGB(96, 92, 86))

	-- Laje do andar com o vão da escada (x 0.6 .. 4.6, z -9 .. 13).
	local stairX0, stairX1 = 0.6, 4.6
	local holeZ0, holeZ1 = -9, 13
	local slabs = {
		{ -HW + 0.5, stairX0, -HD + 0.5, HD - 0.5 },
		{ stairX1, HW - 0.5, -HD + 0.5, HD - 0.5 },
		{ stairX0, stairX1, -HD + 0.5, holeZ0 },
		{ stairX0, stairX1, holeZ1, HD - 0.5 },
	}
	for _, sl in slabs do
		Kit.P(S, "PisoSuperior", Vector3.new(sl[2] - sl[1], U - G, sl[4] - sl[3]), house * CFrame.new((sl[1] + sl[2]) / 2, (G + U) / 2, (sl[3] + sl[4]) / 2), Enum.Material.WoodPlanks, pal.Floor)
	end
	Kit.Ceiling(S, house, -HW + 0.5, HW - 0.5, -HD + 0.5, HD - 0.5, TOP, pal)
	Kit.Ceiling(S, house, -11.5, 11.5, HD + 0.5, 24.5, LH, pal)

	----------------------------------------------------------------------------
	-- Paredes externas (dois andares numa parede só)
	----------------------------------------------------------------------------

	Kit.Wall(S, house, v(-HW - 0.5, -HD), v(HW + 0.5, -HD), TOP, {
		{ x0 = -16, x1 = -12.5, y0 = WY0, y1 = WY1 },
		{ x0 = -10, x1 = -6.5, y0 = WY0, y1 = WY1 },
		{ x0 = -3.7, x1 = 0.7, y0 = 0, y1 = DOOR_H },
		{ x0 = 7.5, x1 = 11, y0 = WY0, y1 = WY1 },
		{ x0 = 13.5, x1 = 17, y0 = WY0, y1 = WY1 },
		{ x0 = -14, x1 = -10.5, y0 = UY0, y1 = UY1 },
		{ x0 = -3.25, x1 = 0.25, y0 = UY0, y1 = UY1 },
		{ x0 = 10.5, x1 = 14, y0 = UY0, y1 = UY1 },
	}, pal, { Exterior = true, InsideDir = Z })
	Kit.Wall(S, house, v(-HW - 0.5, HD), v(HW + 0.5, HD), TOP, {
		{ x0 = -4, x1 = 0.5, y0 = 0, y1 = 8.5 },
		{ x0 = 7, x1 = 11, y0 = 0, y1 = 8.5 },
		{ x0 = 14, x1 = 17.5, y0 = WY0, y1 = WY1 },
		{ x0 = -14, x1 = -10.5, y0 = UY0, y1 = UY1 },
		{ x0 = 10.5, x1 = 14, y0 = UY0, y1 = UY1 },
	}, pal, { Exterior = true, InsideDir = -Z })
	Kit.Wall(S, house, v(-HW, -HD + 0.5), v(-HW, HD - 0.5), TOP, {
		{ x0 = -10, x1 = -6.5, y0 = WY0, y1 = WY1 },
		{ x0 = 8, x1 = 11.5, y0 = WY0, y1 = WY1 },
		{ x0 = -10, x1 = -6.5, y0 = UY0, y1 = UY1 },
		{ x0 = 8, x1 = 11.5, y0 = UY0, y1 = UY1 },
	}, pal, { Exterior = true, InsideDir = X })
	Kit.Wall(S, house, v(HW, -HD + 0.5), v(HW, HD - 0.5), TOP, {
		{ x0 = -9, x1 = -5.5, y0 = WY0, y1 = WY1 },
		{ x0 = -2, x1 = 2.4, y0 = 0, y1 = DOOR_H },
		{ x0 = 5.5, x1 = 9, y0 = WY0, y1 = WY1 },
		{ x0 = -9, x1 = -5.5, y0 = UY0, y1 = UY1 },
		{ x0 = 5.5, x1 = 9, y0 = UY0, y1 = UY1 },
	}, pal, { Exterior = true, InsideDir = -X })
	for _, sx in { -1, 1 } do
		for _, sz in { -1, 1 } do
			Kit.CornerBoard(S, house, sx * HW, sz * HD, TOP, pal.Trim)
		end
	end
	-- Faixa entre os andares (a cara de casa de fazenda de dois pavimentos).
	for _, sz in { -1, 1 } do
		Kit.P(S, "FaixaAndar", Vector3.new(W + 1.3, 0.5, 0.14), house * CFrame.new(0, G + 0.5, sz * (HD + 0.57)), Enum.Material.Wood, pal.Trim, Kit.Deco)
	end
	for _, sx in { -1, 1 } do
		Kit.P(S, "FaixaAndar", Vector3.new(0.14, 0.5, D + 1.3), house * CFrame.new(sx * (HW + 0.57), G + 0.5, 0), Enum.Material.Wood, pal.Trim, Kit.Deco)
	end

	-- Puxado da cozinha (x -12.5 .. 12.5, z 14.5 .. 25.5).
	Kit.Wall(S, house, v(-12.5, 25), v(12.5, 25), LH, {
		{ x0 = -8, x1 = -4, y0 = 3.8, y1 = 7.3 },
		{ x0 = 3, x1 = 7.5, y0 = 0, y1 = 8 },
	}, pal, { Exterior = true, InsideDir = -Z })
	Kit.Wall(S, house, v(-12, HD + 0.5), v(-12, 24.5), LH, {
		{ x0 = 0.5, x1 = 3.5, y0 = 3.8, y1 = 7.3 },
	}, pal, { Exterior = true, InsideDir = X })
	Kit.Wall(S, house, v(12, HD + 0.5), v(12, 24.5), LH, {}, pal, { Exterior = true, InsideDir = -X })

	----------------------------------------------------------------------------
	-- Divisórias
	----------------------------------------------------------------------------

	local T = 0.8
	Kit.Wall(S, house, v(-5, -HD + 0.5), v(-5, HD - 0.5), G, { { x0 = -9, x1 = -1, y0 = 0, y1 = 8.5 } }, pal, { Thickness = T })
	Kit.CasedOpening(S, house, v(-5, -5), Z, 8, 8.5, pal, T)
	Kit.Wall(S, house, v(5, -HD + 0.5), v(5, HD - 0.5), G, { { x0 = -13, x1 = -8.5, y0 = 0, y1 = 8.5 } }, pal, { Thickness = T })
	Kit.CasedOpening(S, house, v(5, -10.75), Z, 4.5, 8.5, pal, T)
	Kit.CasedOpening(S, house, v(-1.75, HD), X, 4.5, 8.5, pal)
	Kit.CasedOpening(S, house, v(9, HD), X, 4, 8.5, pal)
	Kit.Wall(S, house, v(-5, -HD + 0.5, U), v(-5, HD - 0.5, U), TOP - U, { { x0 = 4, x1 = 8.5, y0 = 0, y1 = 8 } }, pal, { Thickness = T })
	Kit.Wall(S, house, v(5, -HD + 0.5, U), v(5, HD - 0.5, U), TOP - U, { { x0 = -13.3, x1 = -9.3, y0 = 0, y1 = 8 } }, pal, { Thickness = T })

	----------------------------------------------------------------------------
	-- Escada (sobe pro fundo, encostada na divisória leste do hall)
	----------------------------------------------------------------------------

	local stairW = stairX1 - stairX0
	local stairMid = (stairX0 + stairX1) / 2
	local run = Kit.Stairs(S, house, v(stairMid, holeZ1, U), -Z, stairW, U, pal, { Run = 1.05, Interior = true, Color = Color3.fromRGB(96, 66, 42) })
	local railA = Vector3.new(stairX0 - 0.2, 3.1, holeZ1 - run + 1.05)
	local railB = Vector3.new(stairX0 - 0.2, U + 3.1, holeZ1)
	Kit.P(S, "CorrimaoEscada", Vector3.new(0.3, 0.3, (railB - railA).Magnitude), house * CFrame.lookAt((railA + railB) / 2, railB), Enum.Material.Wood, pal.Trim)
	for i = 2, 18, 2 do
		local p = railA:Lerp(railB, i / 20)
		Kit.P(S, "Balaustre", Vector3.new(0.2, 3.0, 0.2), house * CFrame.new(p.X, p.Y - 1.5, p.Z), Enum.Material.Wood, pal.Trim, Kit.Deco)
	end
	-- Guarda-corpo do vão no andar (aberto no fim, onde se sai da escada).
	Kit.Railing(S, house, v(stairX0 - 0.1, holeZ0 + 0.1, U), v(stairX0 - 0.1, 9.4, U), pal)
	Kit.Railing(S, house, v(stairX0, holeZ0 - 0.1, U), v(stairX1 - 0.1, holeZ0 - 0.1, U), pal)

	----------------------------------------------------------------------------
	-- Telhados
	----------------------------------------------------------------------------

	local rise = (HD + 0.5) * math.tan(math.rad(PITCH))
	local ridgeY = TOP + rise
	local ra, rb = v(-HW - 1.3, 0, ridgeY), v(HW + 1.3, 0, ridgeY)
	Kit.RoofSlope(S, house, ra, rb, -Z, HD + 0.5 + 1.2, PITCH, pal.Roof, 0.5, true, tin)
	Kit.RoofSlope(S, house, ra, rb, Z, HD + 0.5 + 1.2, PITCH, pal.Roof, 0.5, true, tin)
	Kit.RidgeCap(S, house, ra, rb, pal.Roof, tin)
	for _, sx in { -1, 1 } do
		Kit.GableEnd(S, house, v(sx * HW, 0, TOP), Z, D + 1, rise, 1, pal.SidingMat, pal.Siding)
		Kit.P(S, "Respiro", Vector3.new(0.2, 2.6, 2.6), house * CFrame.new(sx * (HW + 0.55), TOP + rise * 0.45, 0) * CFrame.Angles(0, 0, 0), Enum.Material.WoodPlanks, pal.Trim, { Collide = false, Shape = Enum.PartType.Cylinder })
	end
	-- Puxado: meia-água de zinco encostada na parede dos fundos.
	local leanRise = 10.4 - LH
	local leanPitch = math.deg(math.atan(leanRise / 11))
	Kit.RoofSlope(S, house, v(-13.1, HD + 0.5, 10.4), v(13.1, HD + 0.5, 10.4), Z, 11.8, leanPitch, pal.Roof, 0.4, true, tin)
	for _, sx in { -1, 1 } do
		local back = Vector3.new(0, 0, -1)
		Kit.Wedge(S, "Empena", Vector3.new(1, leanRise, 11), house * CFrame.fromMatrix(Vector3.new(sx * 12, LH + leanRise / 2, HD + 0.5 + 5.5), Vector3.new(0, 1, 0):Cross(back), Vector3.new(0, 1, 0), back), pal.SidingMat, pal.Siding)
	end

	-- Chaminé de tijolo na empena oeste.
	local chimTop = ridgeY + 2.6
	local chimBottom = ground - 1 - Kit.ExtraDepth
	Kit.P(S, "Chamine", Vector3.new(2.9, chimTop - chimBottom, 4.5), house * CFrame.new(-HW - 1.95, (chimTop + chimBottom) / 2, 2.25), Enum.Material.Brick, Color3.fromRGB(132, 62, 48))
	Kit.P(S, "ChamineCapa", Vector3.new(3.5, 0.4, 5.1), house * CFrame.new(-HW - 1.95, chimTop + 0.2, 2.25), Enum.Material.Concrete, Color3.fromRGB(90, 86, 82))
	Kit.P(S, "ChamineBoca", Vector3.new(1.4, 0.1, 2.6), house * CFrame.new(-HW - 1.95, chimTop + 0.45, 2.25), Enum.Material.Slate, Color3.fromRGB(20, 18, 16), Kit.Deco)

	----------------------------------------------------------------------------
	-- Varanda em L (frente + lado leste) com balanço
	----------------------------------------------------------------------------

	local porchZ = -HD - 0.5 - 6.5
	local sideX = HW + 0.5 + 7
	Kit.Deck(Out, house, -HW - 0.5, sideX, porchZ, -HD - 0.5, found, pal)
	Kit.Deck(Out, house, HW + 0.5, sideX, -HD - 0.5, 8, found, pal)
	local porchTop, porchPitch = 10.2, 15
	local tanP = math.tan(math.rad(porchPitch))
	local frontBeam = porchTop - (-HD - 0.5 - (porchZ + 0.4)) * tanP
	local sideBeam = porchTop - ((sideX - 0.4) - (HW + 0.5)) * tanP
	Kit.RoofSlope(Out, house, v(-HW - 1.1, -HD - 0.5, porchTop), v(sideX + 0.6, -HD - 0.5, porchTop), -Z, 7.3, porchPitch, pal.Roof, 0.35, true, tin)
	Kit.RoofSlope(Out, house, v(HW + 0.5, -HD - 0.5, porchTop), v(HW + 0.5, 8.6, porchTop), X, 7.3, porchPitch, pal.Roof, 0.35, true, tin)
	for _, x in { -HW - 0.1, -10, -4.6, 1.6, 10, HW + 0.1, sideX - 0.4 } do
		Kit.Post(Out, house, x, porchZ + 0.4, 0, frontBeam - 0.6, pal)
	end
	for _, z in { -3, 7.6 } do
		Kit.Post(Out, house, sideX - 0.4, z, 0, sideBeam - 0.6, pal)
	end
	Kit.P(Out, "Viga", Vector3.new(sideX + HW + 0.5, 0.6, 0.6), house * CFrame.new((sideX - HW - 0.5) / 2, frontBeam - 0.3, porchZ + 0.4), Enum.Material.Wood, pal.Trim)
	Kit.P(Out, "Viga", Vector3.new(0.6, 0.6, 8 - porchZ), house * CFrame.new(sideX - 0.4, sideBeam - 0.3, (8 + porchZ) / 2), Enum.Material.Wood, pal.Trim)
	Kit.Railing(Out, house, v(-HW - 0.1, porchZ + 0.4), v(-4.6, porchZ + 0.4), pal)
	Kit.Railing(Out, house, v(1.6, porchZ + 0.4), v(sideX - 0.4, porchZ + 0.4), pal)
	Kit.Railing(Out, house, v(-HW - 0.1, porchZ + 0.4), v(-HW - 0.1, -HD - 0.5), pal)
	Kit.Railing(Out, house, v(sideX - 0.4, porchZ + 0.4), v(sideX - 0.4, 7.6), pal)
	Kit.Railing(Out, house, v(HW + 0.6, 7.6), v(sideX - 0.4, 7.6), pal)
	Kit.Stairs(Out, house, v(-1.5, porchZ), -Z, 5, found, pal)
	Kit.WallLantern(Lights, house, Vector3.new(2.0, 6.8, -HD - 0.5), -Z, true)
	Kit.WallLantern(Lights, house, Vector3.new(HW + 0.5, 6.8, 3.6), X, rng:NextNumber() < 0.6)
	Furniture.PorchSwing(Out, at(24.4, 0, 4.3, X), porchTop - (24.4 - (HW + 0.5)) * tanP - 0.4, Color3.fromRGB(210, 204, 190))
	Furniture.RockingChair(Out, at(-14, 0, -17.6, Vector3.new(0.2, 0, -1)), Color3.fromRGB(120, 92, 64))
	Furniture.RockingChair(Out, at(-8.5, 0, -17.8, Vector3.new(-0.2, 0, -1)), Color3.fromRGB(120, 92, 64))
	Furniture.Barrel(Out, at(24.6, 0, -18), Color3.fromRGB(92, 70, 48))

	-- Fundos: patamar e escada da cozinha.
	Kit.Deck(Out, house, 2, 8.5, 25.5, 28.5, found, pal)
	Kit.Railing(Out, house, v(2.2, 25.5), v(2.2, 28.3), pal)
	Kit.Railing(Out, house, v(8.3, 25.5), v(8.3, 28.3), pal)
	Kit.Stairs(Out, house, v(5.25, 28.5), Z, 4.5, found, pal)
	Kit.WallLantern(Lights, house, Vector3.new(1.6, 6.4, 25.5), Z, true)

	----------------------------------------------------------------------------
	-- Portas e janelas
	----------------------------------------------------------------------------

	Kit.Door(Doors, house, v(-1.5, -HD), X, Z, 4.4, DOOR_H, pal, { Name = "PortaEntrada", HingeAtEnd = false, Glass = true })
	Kit.Door(Doors, house, v(HW, 0.2), Z, -X, 4.4, DOOR_H, pal, { Name = "PortaLateral", HingeAtEnd = true, Glass = true })
	Kit.Door(Doors, house, v(5.25, 25), X, -Z, 4.5, 8, pal, { Name = "PortaCozinha", HingeAtEnd = true })
	Kit.Door(Doors, house, Vector3.new(-5, U, 6.25), Z, -X, 4.5, 8, pal, { Name = "PortaQuartoCasal", HingeAtEnd = true, Thickness = T, Color = Color3.fromRGB(150, 128, 96) })
	Kit.Door(Doors, house, Vector3.new(5, U, -11.3), Z, X, 4, 8, pal, { Name = "PortaQuartoCriancas", HingeAtEnd = true, Thickness = T, Color = Color3.fromRGB(150, 128, 96) })

	local curtain = ({ Color3.fromRGB(160, 150, 120), Color3.fromRGB(120, 60, 52), Color3.fromRGB(96, 110, 90) })[rng:NextInteger(1, 3)]
	local wy, uy = (WY0 + WY1) / 2, (UY0 + UY1) / 2
	local wh, uh = WY1 - WY0, UY1 - UY0
	local windows: { { any } } = {
		{ v(-14.25, -HD, wy), -Z, 3.5, wh }, { v(-8.25, -HD, wy), -Z, 3.5, wh },
		{ v(9.25, -HD, wy), -Z, 3.5, wh }, { v(15.25, -HD, wy), -Z, 3.5, wh },
		{ v(-12.25, -HD, uy), -Z, 3.5, uh }, { v(-1.5, -HD, uy), -Z, 3.5, uh }, { v(12.25, -HD, uy), -Z, 3.5, uh },
		{ v(15.75, HD, wy), Z, 3.5, wh }, { v(-12.25, HD, uy), Z, 3.5, uh }, { v(12.25, HD, uy), Z, 3.5, uh },
		{ v(-HW, -8.25, wy), -X, 3.5, wh }, { v(-HW, 9.75, wy), -X, 3.5, wh },
		{ v(-HW, -8.25, uy), -X, 3.5, uh }, { v(-HW, 9.75, uy), -X, 3.5, uh },
		{ v(HW, -7.25, wy), X, 3.5, wh }, { v(HW, 7.25, wy), X, 3.5, wh },
		{ v(HW, -7.25, uy), X, 3.5, uh }, { v(HW, 7.25, uy), X, 3.5, uh },
	}
	local boarded = rng:NextInteger(5, #windows)
	for i, spec in windows do
		Kit.Window(Win, house, spec[1], spec[2], spec[3], spec[4], pal, { Shutters = true, Curtains = curtain, Boarded = i == boarded })
	end
	Kit.Window(Win, house, v(-6, 25, 5.55), Z, 4, 3.5, pal, { Curtains = Color3.fromRGB(196, 186, 150) })
	Kit.Window(Win, house, v(-12, 21.5, 5.55), -X, 3, 3.5, pal, {})

	----------------------------------------------------------------------------
	-- Sala de estar (x -19.5 .. -5.4)
	----------------------------------------------------------------------------

	Furniture.Fireplace(Props, at(-HW + 0.5 + 1.4, 0, 2.25, X))
	Furniture.Sofa(Props, at(-10.5, 0, 2.25, -X), Color3.fromRGB(110, 70, 58), 7)
	Furniture.CoffeeTable(Props, at(-14.3, 0, 2.25, -X), Furniture.Wood.Walnut)
	Furniture.Armchair(Props, at(-14.5, 0, -4.8, Vector3.new(-0.5, 0, 1)), Color3.fromRGB(88, 96, 70))
	Furniture.RockingChair(Props, at(-15, 0, 9, Vector3.new(-0.5, 0, -1)), Furniture.Wood.Walnut)
	Furniture.Piano(Props, at(-6.7, 0, 9.5, -X))
	Furniture.GrandfatherClock(Props, at(-10.8, 0, HD - 0.5 - 0.75, -Z))
	Furniture.Sideboard(Props, at(-14.25, 0, -HD + 0.5 + 1.0, Z), Furniture.Wood.Walnut)
	Furniture.Rug(Props, at(-12.5, 0, 2.25), 9, 11, Color3.fromRGB(110, 58, 46))
	Furniture.FloorLamp(Props, at(-18.6, 0, 12.4), true)
	Furniture.Picture(Props, at(-HW + 0.55, 6.6, -3, X), 2.2, 2.8, Color3.fromRGB(96, 90, 70))

	----------------------------------------------------------------------------
	-- Hall
	----------------------------------------------------------------------------

	Furniture.CoatRack(Props, at(-3.9, 0, -7.4), Color3.fromRGB(80, 60, 44))
	Furniture.Nightstand(Props, at(-3.7, 0, 5, X), Furniture.Wood.Walnut, true, true)
	Furniture.Picture(Props, at(-4.55, 6.4, 10.5, X), 2.0, 2.6, Color3.fromRGB(70, 60, 50))
	Furniture.Rug(Props, at(-2, 0, -2), 3.8, 14, Color3.fromRGB(80, 46, 40))

	----------------------------------------------------------------------------
	-- Sala de jantar (x 5.4 .. 19.5)
	----------------------------------------------------------------------------

	-- Longe do arco da porta lateral (dobradiça em x 19,5 / z 2,4, raio 4,2).
	Furniture.DiningTable(Props, at(12, 0, -3), Furniture.Wood.Oak, 8, true, rng)
	Furniture.Hutch(Props, at(5.4 + 1.05, 0, 4, X), Furniture.Wood.Walnut)
	Furniture.Sideboard(Props, at(15.25, 0, -HD + 0.5 + 1.0, Z), Furniture.Wood.Oak)
	Furniture.Picture(Props, at(12.5, 6.8, HD - 0.55, -Z), 3.2, 2.2, Color3.fromRGB(120, 104, 70))

	----------------------------------------------------------------------------
	-- Cozinha (puxado)
	----------------------------------------------------------------------------

	local cabinet = Color3.fromRGB(176, 170, 146)
	for i, x in { -9, -6, -3 } do
		Furniture.CounterModule(Props, at(x, 0, 24.5 - 1.2, -Z), if i == 2 then "S" else "D", cabinet, Color3.fromRGB(86, 80, 74))
	end
	Furniture.CookStove(Props, at(10.2, 0, 18.8, -X), 12.5)
	Furniture.Fridge(Props, at(10.2, 0, 23, -X))
	Furniture.DiningTable(Props, at(-6, 0, 18.5), Furniture.Wood.Pine, 5, true, rng)
	Furniture.Bookshelf(Props, at(-10.75, 0, 16.5, X), Furniture.Wood.Pine, rng)

	----------------------------------------------------------------------------
	-- Andar de cima
	----------------------------------------------------------------------------

	-- Quarto do casal (x -19.5 .. -5.4).
	local blanket = ({ Color3.fromRGB(128, 104, 80), Color3.fromRGB(96, 46, 44), Color3.fromRGB(70, 84, 100) })[rng:NextInteger(1, 3)]
	Furniture.Bed(Props, house, Vector3.new(-14.4, U, -3), -math.pi / 2, blanket)
	Furniture.Nightstand(Props, at(-18.55, U, -8.1, X), Furniture.Wood.Walnut, true, rng:NextNumber() < 0.5)
	Furniture.Nightstand(Props, at(-18.55, U, 2.1, X), Furniture.Wood.Walnut, false)
	Furniture.Wardrobe(Props, at(-8.1, U, -HD + 0.5 + 1.1, Z), Furniture.Wood.Walnut)
	Furniture.Dresser(Props, at(-6.5, U, -6, -X), Furniture.Wood.Walnut)
	Furniture.RockingChair(Props, at(-16, U, 10, Vector3.new(0.5, 0, -1)), Furniture.Wood.Walnut)
	Furniture.Rug(Props, at(-12, U, 4.5), 7, 5, Color3.fromRGB(150, 128, 92))

	-- Corredor de cima.
	Furniture.Nightstand(Props, at(-3.7, U, -3, X), Furniture.Wood.Walnut, true, rng:NextNumber() < 0.5)

	-- Quarto das crianças (x 5.4 .. 19.5).
	Furniture.TwinBed(Props, at(8.6, U, 10.1), Color3.fromRGB(96, 120, 150))
	Furniture.TwinBed(Props, at(15.9, U, 10.1), Color3.fromRGB(150, 90, 100))
	Furniture.Doll(Props, at(8.8, U + 2.0, 11.4, Vector3.new(0.3, 0, -1)))
	Furniture.Trunk(Props, at(12.25, U, 5.3, -Z), Color3.fromRGB(120, 70, 60))
	Furniture.Wardrobe(Props, at(HW - 0.5 - 1.1, U, -0.5, -X), Color3.fromRGB(150, 128, 96))
	Furniture.Desk(Props, at(16.5, U, -HD + 0.5 + 1.2, Z), Color3.fromRGB(150, 128, 96), false)
	Furniture.Rug(Props, at(12, U, 0), 6, 7, Color3.fromRGB(70, 90, 120))

	----------------------------------------------------------------------------
	-- Luzes
	----------------------------------------------------------------------------

	Kit.CeilingLight(Lights, house, Vector3.new(-12, G, 2.25), true, 0.55)
	Kit.CeilingLight(Lights, house, Vector3.new(-2, G, -4), true, 0.45, true)
	Kit.CeilingLight(Lights, house, Vector3.new(13, G, -1.5), rng:NextNumber() < 0.7, 0.55)
	Kit.CeilingLight(Lights, house, Vector3.new(0, LH, 19.5), rng:NextNumber() < 0.6, 0.5, true)
	Kit.CeilingLight(Lights, house, Vector3.new(-12.5, TOP, 0), rng:NextNumber() < 0.5, 0.45)
	Kit.CeilingLight(Lights, house, Vector3.new(-2, TOP, 3), false, 0.4, true)
	Kit.CeilingLight(Lights, house, Vector3.new(12.5, TOP, 0), false, 0.45)

	----------------------------------------------------------------------------
	-- Quintal e marcadores
	----------------------------------------------------------------------------

	windmill(Out, house, -30.8, 24, ground)
	well(Out, house, 21.5, 17.5, ground)
	outhouse(Out, house, Vector3.new(22, ground, 30), -Z, pal)
	Furniture.Woodpile(Out, at(-15, ground, 16.2, X), rng)

	local Markers = Kit.Folder(model, "Marcadores")
	Structures.SpawnPoint(Markers, at(-1.5, ground + 2, -29.5))
	Structures.LootPoint(Markers, at(-9, 1.5, -8.5), true)
	Structures.LootPoint(Markers, at(13, 1.5, 7))
	Structures.LootPoint(Markers, at(-12, U + 1.5, 6.5))
	Structures.LootPoint(Markers, at(12, U + 1.5, -4))

	model.PrimaryPart = floor
	model:SetAttribute("Construcao", CasaDaFazenda.Style)
	model:SetAttribute("CasaGerada", true)
	return model
end

return CasaDaFazenda
