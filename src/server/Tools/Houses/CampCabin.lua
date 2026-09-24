--!strict
--[[
	CampCabin (estilo "CampCabin_01")
	Cabana de acampamento de madeira, 64 x 34, térrea -- a mesma planta da
	CampCabin_01 original, agora pronta pro jogo:

	  Sala + cozinha (oeste) -> Hall largo (centro) -> Quarto A / Quarto B (leste)

	  - Fundação de pedra maciça até abaixo do terreno: piso nunca mostra grama.
	  - Varanda coberta na frente (escada, guarda-corpo, arandela acesa) e
	    porta dos fundos com patamar: DUAS saídas, como nas cabanas do F13.
	  - Porta de entrada, fundos e dos quartos abrem de verdade (DoorSystem).
	  - Forro em todos os cômodos; telhado de duas águas com empenas.
	  - Móveis com gavetas funcionais (DrawerSystem): balcões, escrivaninha,
	    gaveteiro, cômodas, criados-mudos, guarda-roupas.
	  - SpawnPOI na frente e PontoLoot no piso (caixas do LootCrateSystem).

	Planta em coordenadas locais: piso acabado em y = 0, frente = -Z.
	`Footprint` inclui varanda, escadas, beiral e pilha de lenha -- é o que o
	HouseGenerator usa pra escolher onde a casa cabe na clareira.
]]

local Structures = require(script.Parent.Parent.Structures)
local Kit = require(script.Parent.HouseKit)
local Furniture = require(script.Parent.Furniture)

local CampCabin = {}

CampCabin.Style = "CampCabin"
CampCabin.Found = 1.6 -- piso acabado acima do ponto mais alto do terreno
CampCabin.Footprint = { MinX = -36, MaxX = 34.5, MinZ = -29.8, MaxZ = 25.6 }
-- A construção em si: o piso fica acima do ponto mais alto do terreno aqui
-- dentro, e o chão vira terra batida (sem grama).
CampCabin.Core = { { MinX = -32.5, MaxX = 32.5, MinZ = -17.5, MaxZ = 17.5 } }
CampCabin.Entrances = {
	Vector3.new(-18, 0, -29.8), -- pé da escada da varanda
	Vector3.new(11.75, 0, 25.6), -- pé da escada dos fundos
}

local W, D, H = 64, 34, 12
local HW, HD = W / 2, D / 2
local PITCH = 24
local WIN_Y0, WIN_Y1 = 3.5, 8.5
local DOOR_H = 8

local COL = Kit.Colors

local function palette(rng: Random): Kit.Palette
	local weather = rng:NextNumber(0, 0.12)
	return {
		Siding = COL.Plank:Lerp(Color3.fromRGB(96, 86, 74), weather),
		SidingMat = Enum.Material.WoodPlanks,
		Interior = Color3.fromRGB(146, 108, 70),
		InteriorMat = Enum.Material.WoodPlanks,
		Trim = COL.PlankDark,
		Roof = Color3.fromRGB(78, 66, 58),
		Floor = Color3.fromRGB(98, 70, 46),
		Ceiling = Color3.fromRGB(126, 94, 62),
		CeilingMat = Enum.Material.WoodPlanks,
		Foundation = Color3.fromRGB(106, 102, 96),
		FoundationMat = Enum.Material.Cobblestone,
		Shutter = Color3.fromRGB(66, 84, 62),
		Door = Color3.fromRGB(86, 58, 36),
		Deck = Color3.fromRGB(106, 80, 54),
	}
end

--[[
	Build(parent, house, opts) -> Model
	house = CFrame no PISO ACABADO (y = 0 local), LookVector = frente.
]]
export type BuildOpts = { Name: string?, Seed: number? }

function CampCabin.Build(parent: Instance, house: CFrame, opts: BuildOpts?): Model
	local o = opts or {}
	local rng = Random.new(o.Seed or 1)
	local pal = palette(rng)
	local found = CampCabin.Found

	local model = Kit.Model(parent, o.Name or "CampCabin")
	local S = Kit.Folder(model, "Estrutura")
	local Doors = Kit.Folder(model, "Portas")
	local Win = Kit.Folder(model, "Janelas")
	local Props = Kit.Folder(model, "Moveis")
	local Lights = Kit.Folder(model, "Luzes")
	local Out = Kit.Folder(model, "Externo")

	local function at(x: number, y: number, z: number, look: Vector3?): CFrame
		return Kit.At(house, Vector3.new(x, y, z), look)
	end
	local X, Z = Vector3.new(1, 0, 0), Vector3.new(0, 0, 1)

	----------------------------------------------------------------------------
	-- Fundação, piso, forro
	----------------------------------------------------------------------------

	Kit.Foundation(S, house, -HW - 0.5, HW + 0.5, -HD - 0.5, HD + 0.5, found, pal)
	local floor = Kit.Floor(S, house, -HW - 0.5, HW + 0.5, -HD - 0.5, HD + 0.5, Enum.Material.WoodPlanks, pal.Floor)
	Kit.Ceiling(S, house, -HW + 0.5, HW - 0.5, -HD + 0.5, HD - 0.5, H, pal)

	----------------------------------------------------------------------------
	-- Paredes externas
	----------------------------------------------------------------------------

	-- Sul (frente): sala, porta, hall, quarto B.
	Kit.Wall(S, house, Vector3.new(-HW - 0.5, 0, -HD), Vector3.new(HW + 0.5, 0, -HD), H, {
		{ x0 = -29.5, x1 = -24.5, y0 = WIN_Y0, y1 = WIN_Y1 },
		{ x0 = -20.5, x1 = -15.5, y0 = 0, y1 = DOOR_H },
		{ x0 = 1, x1 = 7, y0 = WIN_Y0, y1 = WIN_Y1 },
		{ x0 = 21, x1 = 27, y0 = WIN_Y0, y1 = WIN_Y1 },
	}, pal, { Exterior = true, InsideDir = Z })
	-- Norte (fundos): cozinha, hall, porta dos fundos, quarto A.
	Kit.Wall(S, house, Vector3.new(-HW - 0.5, 0, HD), Vector3.new(HW + 0.5, 0, HD), H, {
		{ x0 = -29, x1 = -23, y0 = WIN_Y0 + 0.5, y1 = WIN_Y1 },
		{ x0 = 1, x1 = 6, y0 = WIN_Y0, y1 = WIN_Y1 },
		{ x0 = 9.5, x1 = 14, y0 = 0, y1 = DOOR_H },
		{ x0 = 21, x1 = 27, y0 = WIN_Y0, y1 = WIN_Y1 },
	}, pal, { Exterior = true, InsideDir = -Z })
	-- Oeste: janela da sala. (x local da parede = z da casa)
	Kit.Wall(S, house, Vector3.new(-HW, 0, -HD + 0.5), Vector3.new(-HW, 0, HD - 0.5), H, {
		{ x0 = -3, x1 = 3, y0 = WIN_Y0, y1 = WIN_Y1 },
	}, pal, { Exterior = true, InsideDir = X })
	-- Leste: janela de cada quarto.
	Kit.Wall(S, house, Vector3.new(HW, 0, -HD + 0.5), Vector3.new(HW, 0, HD - 0.5), H, {
		{ x0 = -11.5, x1 = -5.5, y0 = WIN_Y0, y1 = WIN_Y1 },
		{ x0 = 5.5, x1 = 11.5, y0 = WIN_Y0, y1 = WIN_Y1 },
	}, pal, { Exterior = true, InsideDir = -X })

	-- Troncos de canto (a cara de cabana de toras da CampCabin_01).
	for _, sx in { -1, 1 } do
		for _, sz in { -1, 1 } do
			Kit.P(S, "TroncoCanto", Vector3.new(H + 0.6, 1.4, 1.4), house * CFrame.new(sx * HW, H / 2 - 0.3, sz * HD) * CFrame.Angles(0, 0, math.pi / 2), Enum.Material.Wood, COL.LogDark, { Shape = Enum.PartType.Cylinder, Collide = false })
		end
	end

	----------------------------------------------------------------------------
	-- Divisórias
	--   Sala/Cozinha (x -32..-8) | Hall (x -8..16) | Quartos A/B (x 16..32)
	----------------------------------------------------------------------------

	Kit.Wall(S, house, Vector3.new(-8, 0, -HD + 0.5), Vector3.new(-8, 0, HD - 0.5), H, {
		{ x0 = -3, x1 = 3, y0 = 0, y1 = 9 },
	}, pal, { Thickness = 0.8 })
	Kit.CasedOpening(S, house, Vector3.new(-8, 0, 0), Z, 6, 9, pal, 0.8)

	Kit.Wall(S, house, Vector3.new(16, 0, -HD + 0.5), Vector3.new(16, 0, HD - 0.5), H, {
		{ x0 = -10.5, x1 = -6, y0 = 0, y1 = DOOR_H },
		{ x0 = 6, x1 = 10.5, y0 = 0, y1 = DOOR_H },
	}, pal, { Thickness = 0.8 })
	Kit.Wall(S, house, Vector3.new(16.4, 0, 0), Vector3.new(HW - 0.5, 0, 0), H, {}, pal, { Thickness = 0.8 })

	----------------------------------------------------------------------------
	-- Telhado
	----------------------------------------------------------------------------

	local tanP = math.tan(math.rad(PITCH))
	local rise = (HD + 0.5) * tanP
	local ridgeY = H + rise
	local gableOver = 1.2
	local ra, rb = Vector3.new(-HW - 0.5 - gableOver, ridgeY, 0), Vector3.new(HW + 0.5 + gableOver, ridgeY, 0)
	Kit.RoofSlope(S, house, ra, rb, -Z, HD + 0.5 + 1.5, PITCH, pal.Roof)
	Kit.RoofSlope(S, house, ra, rb, Z, HD + 0.5 + 1.5, PITCH, pal.Roof)
	Kit.RidgeCap(S, house, ra, rb, pal.Roof)
	for _, sx in { -1, 1 } do
		Kit.GableEnd(S, house, Vector3.new(sx * HW, H, 0), Z, D + 1, rise, 1, pal.SidingMat, pal.Siding)
	end

	----------------------------------------------------------------------------
	-- Varanda da frente
	----------------------------------------------------------------------------

	local porchX0, porchX1, porchZ = -31, -6, -HD - 0.5 - 7
	Kit.Deck(Out, house, porchX0, porchX1, porchZ, -HD - 0.5, found, pal)
	local postZ = porchZ + 0.4
	-- Altura da face de baixo do telhado da varanda na linha dos pilares.
	local beamY = 10.6 - (-HD - 0.5 - postZ) * math.tan(math.rad(14))
	for _, x in { porchX0 + 0.4, -21.4, -14.6, porchX1 - 0.4 } do
		Kit.Post(Out, house, x, postZ, 0, beamY - 0.6, pal)
	end
	Kit.P(Out, "Viga", Vector3.new(porchX1 - porchX0 + 0.6, 0.6, 0.6), house * CFrame.new((porchX0 + porchX1) / 2, beamY - 0.3, postZ), Enum.Material.Wood, pal.Trim)
	Kit.RoofSlope(Out, house, Vector3.new(porchX0 - 0.6, 10.6, -HD - 0.5), Vector3.new(porchX1 + 0.6, 10.6, -HD - 0.5), -Z, 7.7, 14, pal.Roof, 0.4)
	Kit.Railing(Out, house, Vector3.new(porchX0 + 0.4, 0, postZ), Vector3.new(-21.4, 0, postZ), pal)
	Kit.Railing(Out, house, Vector3.new(-14.6, 0, postZ), Vector3.new(porchX1 - 0.4, 0, postZ), pal)
	Kit.Railing(Out, house, Vector3.new(porchX0 + 0.4, 0, -HD - 0.5), Vector3.new(porchX0 + 0.4, 0, postZ), pal)
	Kit.Railing(Out, house, Vector3.new(porchX1 - 0.4, 0, -HD - 0.5), Vector3.new(porchX1 - 0.4, 0, postZ), pal)
	Kit.Stairs(Out, house, Vector3.new(-18, 0, porchZ), -Z, 6, found, pal)
	Kit.WallLantern(Lights, house, Vector3.new(-14.3, 6.4, -HD - 0.5), -Z, true)
	Furniture.Barrel(Out, at(-8, 0, -20.5), Color3.fromRGB(96, 70, 44))
	Furniture.Chair(Out, at(-27.5, 0, -20.5, Vector3.new(0.3, 0, -1)), Furniture.Wood.Pine)
	Furniture.Chair(Out, at(-24.5, 0, -20.8, Vector3.new(-0.2, 0, -1)), Furniture.Wood.Pine)

	----------------------------------------------------------------------------
	-- Fundos: patamar, escada, toldo
	----------------------------------------------------------------------------

	Kit.Deck(Out, house, 8.5, 15, HD + 0.5, HD + 3.5, found, pal)
	Kit.Railing(Out, house, Vector3.new(8.7, 0, HD + 0.5), Vector3.new(8.7, 0, HD + 3.3), pal)
	Kit.Railing(Out, house, Vector3.new(14.8, 0, HD + 0.5), Vector3.new(14.8, 0, HD + 3.3), pal)
	Kit.Stairs(Out, house, Vector3.new(11.75, 0, HD + 3.5), Z, 4.5, found, pal)
	Kit.RoofSlope(Out, house, Vector3.new(8.2, 10.2, HD + 0.5), Vector3.new(15.3, 10.2, HD + 0.5), Z, 3.6, 18, pal.Roof, 0.35)
	Kit.WallLantern(Lights, house, Vector3.new(7.8, 6.4, HD + 0.5), Z, rng:NextNumber() < 0.5)

	----------------------------------------------------------------------------
	-- Portas e janelas
	----------------------------------------------------------------------------

	Kit.Door(Doors, house, Vector3.new(-18, 0, -HD), X, Z, 5, DOOR_H, pal, { Name = "PortaEntrada", HingeAtEnd = true, Glass = true })
	Kit.Door(Doors, house, Vector3.new(11.75, 0, HD), X, -Z, 4.5, DOOR_H, pal, { Name = "PortaFundos", HingeAtEnd = true })
	Kit.Door(Doors, house, Vector3.new(16, 0, 8.25), Z, X, 4.5, DOOR_H, pal, { Name = "PortaQuartoA", HingeAtEnd = true, Thickness = 0.8 })
	Kit.Door(Doors, house, Vector3.new(16, 0, -8.25), Z, X, 4.5, DOOR_H, pal, { Name = "PortaQuartoB", HingeAtEnd = false, Thickness = 0.8 })

	local curtain = ({ Color3.fromRGB(128, 44, 38), Color3.fromRGB(70, 88, 64), Color3.fromRGB(170, 150, 110) })[rng:NextInteger(1, 3)]
	local boarded = rng:NextInteger(1, 4) -- uma janela pregada com tábuas por casa
	local windows = {
		{ Vector3.new(-27, (WIN_Y0 + WIN_Y1) / 2, -HD), -Z, 5, WIN_Y1 - WIN_Y0 },
		{ Vector3.new(4, (WIN_Y0 + WIN_Y1) / 2, -HD), -Z, 6, WIN_Y1 - WIN_Y0 },
		{ Vector3.new(24, (WIN_Y0 + WIN_Y1) / 2, -HD), -Z, 6, WIN_Y1 - WIN_Y0 },
		{ Vector3.new(-26, (WIN_Y0 + 0.5 + WIN_Y1) / 2, HD), Z, 6, WIN_Y1 - WIN_Y0 - 0.5 },
		{ Vector3.new(3.5, (WIN_Y0 + WIN_Y1) / 2, HD), Z, 5, WIN_Y1 - WIN_Y0 },
		{ Vector3.new(24, (WIN_Y0 + WIN_Y1) / 2, HD), Z, 6, WIN_Y1 - WIN_Y0 },
		{ Vector3.new(-HW, (WIN_Y0 + WIN_Y1) / 2, 0), -X, 6, WIN_Y1 - WIN_Y0 },
		{ Vector3.new(HW, (WIN_Y0 + WIN_Y1) / 2, -8.5), X, 6, WIN_Y1 - WIN_Y0 },
		{ Vector3.new(HW, (WIN_Y0 + WIN_Y1) / 2, 8.5), X, 6, WIN_Y1 - WIN_Y0 },
	}
	for i, spec in windows do
		local isBedroom = i == 3 or i == 6 or i >= 8
		Kit.Window(Win, house, spec[1], spec[2], spec[3], spec[4], pal, {
			Shutters = i ~= 4,
			Curtains = if isBedroom or i == 1 or i == 7 then curtain else nil,
			Boarded = i == ({ 2, 5, 7, 9 })[boarded],
		})
	end

	----------------------------------------------------------------------------
	-- Sala e cozinha (x -31.5 .. -8.4)
	----------------------------------------------------------------------------

	local counterTop = Color3.fromRGB(96, 92, 86)
	local cabinet = Furniture.Wood.Green
	for i, kind in { "D", "S", "D", "D" } do
		Furniture.CounterModule(Props, at(-30 + (i - 1) * 3, 0, HD - 0.5 - 1.2, -Z), kind, cabinet, counterTop)
	end
	Furniture.WallCabinet(Props, at(-20.9, 0, HD - 0.5 - 0.7, -Z), 2.8, cabinet)
	Furniture.CookStove(Props, at(-15.6, 0, HD - 0.5 - 1.3, -Z), 16)
	Furniture.Fridge(Props, at(-11, 0, HD - 0.5 - 1.3, -Z))
	Furniture.DiningTable(Props, at(-24, 0, 6.5), Furniture.Wood.Oak, 6, true, rng)

	Furniture.Sofa(Props, at(-29.9, 0, -9, X), Color3.fromRGB(104, 56, 42), 7)
	Furniture.CoffeeTable(Props, at(-25.3, 0, -9, X), Furniture.Wood.Walnut)
	Furniture.Armchair(Props, at(-20.5, 0, -12, Vector3.new(-1, 0, 0.35)), Color3.fromRGB(92, 72, 50))
	Furniture.Rug(Props, at(-25.5, 0, -9), 7.5, 10, Color3.fromRGB(118, 52, 40))
	Furniture.Bookshelf(Props, at(-9.15, 0, -12, -X), Furniture.Wood.Walnut, rng)
	Furniture.FloorLamp(Props, at(-30.5, 0, -14.6), true)
	Furniture.Picture(Props, at(-31.4, 7.2, -9, X), 4, 2.6, Color3.fromRGB(82, 96, 80))

	----------------------------------------------------------------------------
	-- Hall (x -7.6 .. 15.6)
	----------------------------------------------------------------------------

	Furniture.Desk(Props, at(-3.5, 0, HD - 0.5 - 1.2, -Z), Furniture.Wood.Oak, rng:NextNumber() < 0.5)
	Furniture.Chair(Props, at(-3.9, 0, 13.1, Z), Furniture.Wood.Oak)
	Furniture.ToolChest(Props, at(11, 0, -HD + 0.5 + 1.15, Z), Color3.fromRGB(120, 48, 40))
	Furniture.Dresser(Props, at(14.5, 0, 0, -X), Furniture.Wood.Pine)
	Furniture.CoatRack(Props, at(7.4, 0, 15.3), Color3.fromRGB(70, 60, 44))
	Furniture.Rug(Props, at(3.5, 0, 0), 9, 14, Color3.fromRGB(70, 60, 88))
	Furniture.Armchair(Props, at(0.5, 0, -12.8, Vector3.new(0.3, 0, 1)), Color3.fromRGB(96, 60, 46))
	Furniture.Picture(Props, at(15.55, 7.6, 0, -X), 3.4, 2.4, Color3.fromRGB(120, 96, 70))
	Furniture.WallClock(Props, at(7.7, 9.2, HD - 0.55, -Z))

	----------------------------------------------------------------------------
	-- Quartos (A norte, B sul)
	----------------------------------------------------------------------------

	local blankets = { Color3.fromRGB(120, 40, 36), Color3.fromRGB(58, 76, 98), Color3.fromRGB(96, 104, 70) }
	for _, sz in { 1, -1 } do
		Furniture.Bed(Props, house, Vector3.new(26.4, 0, sz * 8.5), math.pi / 2, blankets[rng:NextInteger(1, 3)])
		Furniture.Nightstand(Props, at(30.4, 0, sz * 13.4, -X), Furniture.Wood.Walnut, true, rng:NextNumber() < 0.35)
		Furniture.Wardrobe(Props, at(18.6, 0, sz * (HD - 0.5 - 1.1), Vector3.new(0, 0, -sz)), Furniture.Wood.Walnut)
		Furniture.Dresser(Props, at(24.5, 0, sz * 1.5, Vector3.new(0, 0, sz)), Furniture.Wood.Walnut)
		Furniture.Mirror(Props, at(24.5, 6.6, sz * 0.45, Vector3.new(0, 0, sz)), 3.2, 2.4)
		Furniture.Rug(Props, at(21.6, 0, sz * 8.5), 4.5, 7, Color3.fromRGB(150, 126, 90))
	end

	----------------------------------------------------------------------------
	-- Luzes (cômodos acesos ao acaso: casa abandonada às pressas)
	----------------------------------------------------------------------------

	Kit.CeilingLight(Lights, house, Vector3.new(-20, H, -8), true, 0.6)
	Kit.CeilingLight(Lights, house, Vector3.new(-22, H, 7), rng:NextNumber() < 0.6, 0.55)
	Kit.CeilingLight(Lights, house, Vector3.new(4, H, 0), true, 0.6)
	local litRoom = rng:NextInteger(1, 2)
	Kit.CeilingLight(Lights, house, Vector3.new(24, H, 8.5), litRoom == 1, 0.5)
	Kit.CeilingLight(Lights, house, Vector3.new(24, H, -8.5), litRoom == 2, 0.5)

	----------------------------------------------------------------------------
	-- Área externa e marcadores
	----------------------------------------------------------------------------

	Furniture.Woodpile(Out, at(-HW - 1.7, -found, 8, -X), rng)
	Furniture.Barrel(Out, at(17.5, -found, HD + 2.2), Color3.fromRGB(80, 64, 48))

	local Markers = Kit.Folder(model, "Marcadores")
	Structures.SpawnPoint(Markers, at(-18, -found + 2, -33))
	Structures.LootPoint(Markers, at(-12.5, 1.5, 8))
	Structures.LootPoint(Markers, at(8, 1.5, -6))

	model.PrimaryPart = floor
	model:SetAttribute("Construcao", CampCabin.Style)
	model:SetAttribute("CasaGerada", true)
	return model
end

return CampCabin
