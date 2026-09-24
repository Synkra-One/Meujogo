--!strict
--[[
	CasaDoCaseiro
	Segundo estilo de casa grande: a casa do caseiro da ilha. Onde a
	CampCabin é cabana de toras de acampamento, esta é casa de verdade de
	morador -- tábuas pintadas (verde-musgo / vermelho-celeiro / azul-cinza),
	acabamento branco, telhado de telha asfáltica, chaminé de pedra, planta em L.

	  Bloco principal 48 x 26          Ala do quarto 18 x 18 (fundos, leste)
	  +-----------+------+----------+
	  |           |      | corredor | banheiro |   <- z 3..13
	  |   sala    | hall +----------+----------+
	  | (lareira) |      |   cozinha + jantar  |   <- z -13..3
	  +-----------+------+---------------------+
	           varanda de ponta a ponta (frente = -Z)

	  - Porta da frente e dos fundos; portas do banheiro e do quarto abrem.
	  - Sala com lareira acesa (brasa), cozinha com fogão a lenha e pia,
	    banheiro com banheira, quarto com cama, criados-mudos, cômoda,
	    guarda-roupa e escrivaninha -- gavetas funcionais em todos.
	  - Pisos: tábua na área social/quarto, cerâmica na cozinha e banheiro.
	  - SpawnArma num PontoLoot da cozinha (caseiro guarda arma em casa).

	Coordenadas locais: piso acabado em y = 0, frente = -Z.
]]

local Structures = require(script.Parent.Parent.Structures)
local Kit = require(script.Parent.HouseKit)
local Furniture = require(script.Parent.Furniture)

local CasaDoCaseiro = {}

CasaDoCaseiro.Style = "CasaDoCaseiro"
CasaDoCaseiro.Found = 1.9
CasaDoCaseiro.Footprint = { MinX = -28.4, MaxX = 26.4, MinZ = -26.8, MaxZ = 33.4 }
-- A construção em si: o piso fica acima do ponto mais alto do terreno aqui
-- dentro, e o chão vira terra batida (sem grama).
CasaDoCaseiro.Core = {
	{ MinX = -24.5, MaxX = 24.5, MinZ = -13.5, MaxZ = 13.5 },
	{ MinX = 5.5, MaxX = 24.5, MinZ = 13.5, MaxZ = 31.5 },
}
CasaDoCaseiro.Entrances = {
	Vector3.new(0, 0, -26.8), -- pé da escada da varanda
	Vector3.new(0.25, 0, 23.2), -- pé da escada dos fundos
}

local H = 11
local PITCH = 32
local DOOR_H = 8
local WY0, WY1 = 3.2, 8.2 -- janelas comuns
local KY0 = 3.8 -- janelas acima de balcão

local SIDINGS = {
	{ Color3.fromRGB(92, 110, 88), Color3.fromRGB(60, 64, 58) }, -- verde-musgo, veneziana grafite
	{ Color3.fromRGB(128, 58, 48), Color3.fromRGB(58, 52, 46) }, -- vermelho-celeiro
	{ Color3.fromRGB(104, 118, 128), Color3.fromRGB(56, 70, 60) }, -- azul-cinza, veneziana verde
}

local function palette(rng: Random): Kit.Palette
	local choice = SIDINGS[rng:NextInteger(1, #SIDINGS)]
	local faded = rng:NextNumber(0.05, 0.2)
	return {
		Siding = choice[1]:Lerp(Color3.fromRGB(150, 146, 136), faded),
		SidingMat = Enum.Material.WoodPlanks,
		Interior = Color3.fromRGB(198, 188, 164),
		InteriorMat = Kit.Mat.Plaster,
		Trim = Color3.fromRGB(214, 208, 192),
		Roof = Color3.fromRGB(62, 62, 66),
		Floor = Color3.fromRGB(122, 86, 56),
		Ceiling = Color3.fromRGB(214, 208, 192),
		CeilingMat = Kit.Mat.Plaster,
		Foundation = Color3.fromRGB(122, 118, 110),
		FoundationMat = Enum.Material.Cobblestone,
		Shutter = choice[2],
		Door = Color3.fromRGB(104, 44, 36),
		Deck = Color3.fromRGB(118, 100, 82),
	}
end

export type BuildOpts = { Name: string?, Seed: number? }

function CasaDoCaseiro.Build(parent: Instance, house: CFrame, opts: BuildOpts?): Model
	local o = opts or {}
	local rng = Random.new(o.Seed or 1)
	local pal = palette(rng)
	local found = CasaDoCaseiro.Found

	local model = Kit.Model(parent, o.Name or "CasaDoCaseiro")
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
	local function v(x: number, z: number): Vector3
		return Vector3.new(x, 0, z)
	end

	----------------------------------------------------------------------------
	-- Fundação, pisos, forro
	----------------------------------------------------------------------------

	Kit.Foundation(S, house, -24.5, 24.5, -13.5, 13.5, found, pal)
	Kit.Foundation(S, house, 5.5, 24.5, 13.5, 31.5, found, pal)
	local floor = Kit.Floor(S, house, -24.5, 24.5, -13.5, 13.5, Enum.Material.WoodPlanks, pal.Floor)
	Kit.Floor(S, house, 5.5, 24.5, 13.5, 31.5, Enum.Material.WoodPlanks, pal.Floor, "PisoAla")
	Kit.FloorFinish(S, house, 6.4, 23.5, -12.5, 2.6, Kit.Mat.Tiles, Color3.fromRGB(176, 170, 156)) -- cozinha
	Kit.FloorFinish(S, house, 16.4, 23.5, 3.4, 12.6, Kit.Mat.Tiles, Color3.fromRGB(150, 176, 178)) -- banheiro
	Kit.Ceiling(S, house, -23.5, 23.5, -12.5, 12.5, H, pal)
	Kit.Ceiling(S, house, 6.5, 23.5, 13.5, 30.5, H, pal)

	----------------------------------------------------------------------------
	-- Paredes externas
	----------------------------------------------------------------------------

	-- Frente (z = -13): sala (2 janelas), porta, cozinha.
	Kit.Wall(S, house, v(-24.5, -13), v(24.5, -13), H, {
		{ x0 = -20, x1 = -15.5, y0 = WY0, y1 = WY1 },
		{ x0 = -12, x1 = -7.5, y0 = WY0, y1 = WY1 },
		{ x0 = -2.3, x1 = 2.3, y0 = 0, y1 = DOOR_H },
		{ x0 = 13, x1 = 18.5, y0 = KY0, y1 = WY1 },
	}, pal, { Exterior = true, InsideDir = Z })
	-- Oeste (x = -24): janelas dos dois lados da chaminé.
	Kit.Wall(S, house, v(-24, -12.5), v(-24, 12.5), H, {
		{ x0 = -10.5, x1 = -6.5, y0 = WY0, y1 = WY1 },
		{ x0 = 6.5, x1 = 10.5, y0 = WY0, y1 = WY1 },
	}, pal, { Exterior = true, InsideDir = X })
	-- Fundos do bloco principal (z = 13, x -24.5..6.5): janela da sala, porta dos fundos.
	-- x local = x da casa + 9.
	Kit.Wall(S, house, v(-24.5, 13), v(6.5, 13), H, {
		{ x0 = -19 + 9, x1 = -14.5 + 9, y0 = WY0, y1 = WY1 },
		{ x0 = -2 + 9, x1 = 2.5 + 9, y0 = 0, y1 = DOOR_H },
	}, pal, { Exterior = true, InsideDir = -Z })
	-- Leste (x = 24, z -12.5..30.5): cozinha, banheiro (alta, fosca), quarto.
	-- x local = z da casa - 9.
	Kit.Wall(S, house, v(24, -12.5), v(24, 30.5), H, {
		{ x0 = -8 - 9, x1 = -3 - 9, y0 = KY0, y1 = WY1 },
		{ x0 = 6 - 9, x1 = 8.8 - 9, y0 = 5.2, y1 = WY1 },
		{ x0 = 19 - 9, x1 = 24 - 9, y0 = WY0, y1 = WY1 },
	}, pal, { Exterior = true, InsideDir = -X })
	-- Ala: oeste (x = 6, z 13.5..30.5) e norte (z = 31, x 5.5..24.5).
	Kit.Wall(S, house, v(6, 13.5), v(6, 30.5), H, {
		{ x0 = 20 - 22, x1 = 24.5 - 22, y0 = WY0, y1 = WY1 },
	}, pal, { Exterior = true, InsideDir = X })
	Kit.Wall(S, house, v(5.5, 31), v(24.5, 31), H, {
		{ x0 = 12.5 - 15, x1 = 17.5 - 15, y0 = WY0, y1 = WY1 },
	}, pal, { Exterior = true, InsideDir = -Z })

	for _, c in { v(-24, -13), v(24, -13), v(-24, 13), v(24, 31), v(6, 31) } do
		Kit.CornerBoard(S, house, c.X, c.Z, H, pal.Trim)
	end

	----------------------------------------------------------------------------
	-- Divisórias internas
	----------------------------------------------------------------------------

	local T = 0.8
	Kit.Wall(S, house, v(-6, -12.5), v(-6, 12.5), H, { { x0 = -5, x1 = 5, y0 = 0, y1 = 9 } }, pal, { Thickness = T })
	Kit.CasedOpening(S, house, v(-6, 0), Z, 10, 9, pal, T)
	Kit.Wall(S, house, v(6, -12.5), v(6, 12.5), H, {
		{ x0 = -9, x1 = -4.5, y0 = 0, y1 = 8.5 },
		{ x0 = 5.5, x1 = 10, y0 = 0, y1 = DOOR_H },
	}, pal, { Thickness = T })
	Kit.CasedOpening(S, house, v(6, -6.75), Z, 4.5, 8.5, pal, T)
	Kit.CasedOpening(S, house, v(6, 7.75), Z, 4.5, DOOR_H, pal, T)
	Kit.Wall(S, house, v(6.4, 3), v(23.5, 3), H, {}, pal, { Thickness = T })
	Kit.Wall(S, house, v(16, 3.4), v(16, 12.6), H, { { x0 = 5.4 - 8, x1 = 9.9 - 8, y0 = 0, y1 = DOOR_H } }, pal, { Thickness = T })
	Kit.Wall(S, house, v(6.4, 13), v(23.5, 13), H, { { x0 = 8.5 - 14.95, x1 = 13 - 14.95, y0 = 0, y1 = DOOR_H } }, pal, { Thickness = T })

	----------------------------------------------------------------------------
	-- Telhado: principal (cumeeira em X) + ala (cumeeira em Z) com rincão
	----------------------------------------------------------------------------

	local tanP = math.tan(math.rad(PITCH))
	local mainRise = 13.5 * tanP
	local mainRidge = H + mainRise
	local over = 1.2
	local ma, mb = Vector3.new(-25.1, mainRidge, 0), Vector3.new(25.5, mainRidge, 0)
	Kit.RoofSlope(S, house, ma, mb, -Z, 13.5 + over, PITCH, pal.Roof)
	-- Água de trás em dois pedaços: sobre a ala o beiral não pode entrar no quarto.
	Kit.RoofSlope(S, house, ma, Vector3.new(5.5, mainRidge, 0), Z, 13.5 + over, PITCH, pal.Roof)
	Kit.RoofSlope(S, house, Vector3.new(5.5, mainRidge, 0), mb, Z, 13.5, PITCH, pal.Roof, nil, false)
	Kit.RidgeCap(S, house, ma, mb, pal.Roof)
	Kit.GableEnd(S, house, Vector3.new(-24, H, 0), Z, 27, mainRise, 1, pal.SidingMat, pal.Siding)
	Kit.GableEnd(S, house, Vector3.new(24, H, 0), Z, 27, mainRise, 1, pal.SidingMat, pal.Siding)

	local wingRise = 9.5 * tanP
	local wingRidge = H + wingRise
	local valleyZ = (mainRidge - wingRidge) / tanP -- onde a cumeeira da ala encontra o telhado principal
	local wa, wmid, wb = Vector3.new(15, wingRidge, valleyZ), Vector3.new(15, wingRidge, 13.5), Vector3.new(15, wingRidge, 31.5 + over)
	for _, side in { -1, 1 } do
		local down = Vector3.new(side, 0, 0)
		Kit.RoofSlope(S, house, wa, wmid, down, 9.5, PITCH, pal.Roof, nil, false)
		Kit.RoofSlope(S, house, wmid, wb, down, 9.5 + over, PITCH, pal.Roof)
	end
	Kit.RidgeCap(S, house, wa, wb, pal.Roof)
	Kit.GableEnd(S, house, Vector3.new(15, H, 31), X, 19, wingRise, 1, pal.SidingMat, pal.Siding)

	-- Chaminé de pedra na empena oeste, atravessando o beiral.
	local chimneyTop = mainRidge + 2.6
	local chimneyBottom = -found - 1 - Kit.ExtraDepth
	Kit.P(S, "Chamine", Vector3.new(3.2, chimneyTop - chimneyBottom, 4.6), house * CFrame.new(-26.1, (chimneyTop + chimneyBottom) / 2, 0), Enum.Material.Cobblestone, Color3.fromRGB(116, 108, 100))
	Kit.P(S, "ChamineCapa", Vector3.new(3.8, 0.4, 5.2), house * CFrame.new(-26.1, chimneyTop + 0.2, 0), Enum.Material.Concrete, Color3.fromRGB(96, 92, 88))
	Kit.P(S, "ChamineBoca", Vector3.new(1.6, 0.1, 2.4), house * CFrame.new(-26.1, chimneyTop + 0.45, 0), Enum.Material.Slate, Color3.fromRGB(20, 18, 16), Kit.Deco)
	local smokePart = Kit.P(S, "ChamineFumaca", Vector3.new(0.5, 0.5, 0.5), house * CFrame.new(-26.1, chimneyTop + 0.8, 0), Enum.Material.SmoothPlastic, Color3.new(0, 0, 0), { Collide = false, Transparency = 1, Shadow = false })
	local smoke = Instance.new("Smoke")
	smoke.Color = Color3.fromRGB(110, 110, 110)
	smoke.Size = 2.2
	smoke.Opacity = 0.08
	smoke.RiseVelocity = 2.5
	smoke.Parent = smokePart

	----------------------------------------------------------------------------
	-- Varanda de ponta a ponta
	----------------------------------------------------------------------------

	local porchZ = -20.5
	Kit.Deck(Out, house, -24.5, 24.5, porchZ, -13.5, found, pal)
	local postZ = porchZ + 0.4
	local porchPitch = 12
	local porchTop = 9.6
	local beamY = porchTop - (-13.5 - postZ) * math.tan(math.rad(porchPitch))
	for _, x in { -24.1, -12, -3.3, 3.3, 12, 24.1 } do
		Kit.Post(Out, house, x, postZ, 0, beamY - 0.6, pal)
	end
	Kit.P(Out, "Viga", Vector3.new(49, 0.6, 0.6), house * CFrame.new(0, beamY - 0.3, postZ), Enum.Material.Wood, pal.Trim)
	Kit.RoofSlope(Out, house, Vector3.new(-25, porchTop, -13.5), Vector3.new(25, porchTop, -13.5), -Z, 7.8, porchPitch, pal.Roof, 0.4)
	Kit.Railing(Out, house, v(-24.1, postZ), v(-3.3, postZ), pal)
	Kit.Railing(Out, house, v(3.3, postZ), v(24.1, postZ), pal)
	Kit.Railing(Out, house, v(-24.1, -13.5), v(-24.1, postZ), pal)
	Kit.Railing(Out, house, v(24.1, -13.5), v(24.1, postZ), pal)
	Kit.Stairs(Out, house, v(0, porchZ), -Z, 6, found, pal)
	Kit.WallLantern(Lights, house, Vector3.new(-3.4, 6.4, -13.5), -Z, true)
	Kit.WallLantern(Lights, house, Vector3.new(3.4, 6.4, -13.5), -Z, rng:NextNumber() < 0.5)
	Furniture.Chair(Out, at(-9.5, 0, -16.8, Vector3.new(0.15, 0, -1)), Color3.fromRGB(200, 196, 184))
	Furniture.Chair(Out, at(-15, 0, -16.8, Vector3.new(-0.15, 0, -1)), Color3.fromRGB(200, 196, 184))
	Furniture.Barrel(Out, at(21.8, 0, -16.2), Color3.fromRGB(92, 70, 48))

	-- Fundos: patamar e escada da porta da cozinha/hall.
	Kit.Deck(Out, house, -3.5, 4, 13.5, 17, found, pal)
	Kit.Railing(Out, house, v(-3.3, 13.5), v(-3.3, 16.8), pal)
	Kit.Railing(Out, house, v(3.8, 13.5), v(3.8, 16.8), pal)
	Kit.Stairs(Out, house, v(0.25, 17), Z, 4.5, found, pal)
	Kit.RoofSlope(Out, house, Vector3.new(-3.9, 9.6, 13.5), Vector3.new(4.4, 9.6, 13.5), Z, 4.2, 15, pal.Roof, 0.35)
	Kit.WallLantern(Lights, house, Vector3.new(-3.4, 6.4, 13.5), Z, true)

	----------------------------------------------------------------------------
	-- Portas
	----------------------------------------------------------------------------

	Kit.Door(Doors, house, v(0, -13), X, Z, 4.6, DOOR_H, pal, { Name = "PortaEntrada", HingeAtEnd = false, Glass = true })
	Kit.Door(Doors, house, v(0.25, 13), X, -Z, 4.5, DOOR_H, pal, { Name = "PortaFundos", HingeAtEnd = true })
	Kit.Door(Doors, house, v(16, 7.65), Z, X, 4.5, DOOR_H, pal, { Name = "PortaBanheiro", HingeAtEnd = true, Thickness = T, Color = pal.Trim })
	Kit.Door(Doors, house, v(10.75, 13), X, Z, 4.5, DOOR_H, pal, { Name = "PortaQuarto", HingeAtEnd = false, Thickness = T, Color = pal.Trim })

	----------------------------------------------------------------------------
	-- Janelas
	----------------------------------------------------------------------------

	local curtain = ({ Color3.fromRGB(196, 178, 140), Color3.fromRGB(124, 52, 46), Color3.fromRGB(90, 104, 120) })[rng:NextInteger(1, 3)]
	local winH, kitH = WY1 - WY0, WY1 - KY0
	local windows: { { any } } = {
		{ Vector3.new(-17.75, (WY0 + WY1) / 2, -13), -Z, 4.5, winH, true },
		{ Vector3.new(-9.75, (WY0 + WY1) / 2, -13), -Z, 4.5, winH, true },
		{ Vector3.new(15.75, (KY0 + WY1) / 2, -13), -Z, 5.5, kitH, false },
		{ Vector3.new(-24, (WY0 + WY1) / 2, -8.5), -X, 4, winH, true },
		{ Vector3.new(-24, (WY0 + WY1) / 2, 8.5), -X, 4, winH, true },
		{ Vector3.new(-16.75, (WY0 + WY1) / 2, 13), Z, 4.5, winH, true },
		{ Vector3.new(24, (KY0 + WY1) / 2, -5.5), X, 5, kitH, false },
		{ Vector3.new(24, (5.2 + WY1) / 2, 7.4), X, 2.8, WY1 - 5.2, false },
		{ Vector3.new(24, (WY0 + WY1) / 2, 21.5), X, 5, winH, true },
		{ Vector3.new(6, (WY0 + WY1) / 2, 22.25), -X, 4.5, winH, true },
		{ Vector3.new(15, (WY0 + WY1) / 2, 31), Z, 5, winH, true },
	}
	local boarded = ({ 5, 6, 10 })[rng:NextInteger(1, 3)]
	for i, spec in windows do
		Kit.Window(Win, house, spec[1], spec[2], spec[3], spec[4], pal, {
			Shutters = spec[5] == true,
			Curtains = if spec[5] == true then curtain else nil,
			Frosted = i == 8,
			Boarded = i == boarded,
		})
	end

	----------------------------------------------------------------------------
	-- Sala (x -23.5 .. -6.4)
	----------------------------------------------------------------------------

	Furniture.Fireplace(Props, at(-22.1, 0, 0, X))
	Furniture.Sofa(Props, at(-12.5, 0, 0, -X), Color3.fromRGB(86, 70, 60), 8)
	Furniture.CoffeeTable(Props, at(-16.9, 0, 0, -X), Furniture.Wood.Walnut)
	Furniture.Armchair(Props, at(-18, 0, -8.6, Vector3.new(-0.25, 0, 1)), Color3.fromRGB(120, 58, 46))
	Furniture.Armchair(Props, at(-18, 0, 8.6, Vector3.new(-0.25, 0, -1)), Color3.fromRGB(120, 58, 46))
	Furniture.Rug(Props, at(-16.2, 0, 0), 9, 12, Color3.fromRGB(96, 46, 40))
	Furniture.Bookshelf(Props, at(-21.3, 0, 11.75, -Z), Furniture.Wood.Walnut, rng)
	Furniture.Sideboard(Props, at(-7.4, 0, -8.75, -X), Furniture.Wood.Walnut)
	Furniture.Desk(Props, at(-7.6, 0, 8.75, -X), Furniture.Wood.Oak, rng:NextNumber() < 0.5)
	-- Cadeira afastada: as gavetas da escrivaninha abrem 1,5 stud pra fora.
	Furniture.Chair(Props, at(-11.7, 0, 8.4, Vector3.new(1, 0, 0.2)), Furniture.Wood.Oak)
	Furniture.FloorLamp(Props, at(-22.4, 0, -11.4), true)
	Furniture.Picture(Props, at(-13.75, 6.8, -12.45, Z), 1.7, 2.1, Color3.fromRGB(92, 104, 88))

	----------------------------------------------------------------------------
	-- Hall (x -5.6 .. 5.6)
	----------------------------------------------------------------------------

	Furniture.Nightstand(Props, at(-4.6, 0, -10.2, X), Furniture.Wood.Walnut, true, true)
	Furniture.CoatRack(Props, at(4.6, 0, -11.6), Color3.fromRGB(64, 70, 58))
	Furniture.Rug(Props, at(0, 0, 0.5), 4, 17, Color3.fromRGB(88, 60, 50))
	Furniture.WallClock(Props, at(5.55, 8.6, 0.5, -X))
	Furniture.Picture(Props, at(-5.55, 6.6, -9, X), 2.4, 3, Color3.fromRGB(128, 112, 80))

	----------------------------------------------------------------------------
	-- Cozinha (x 6.4 .. 23.5, z -12.5 .. 2.6)
	----------------------------------------------------------------------------

	local cabinet = Color3.fromRGB(206, 200, 184)
	local top = Color3.fromRGB(72, 70, 68)
	for _, x in { 13.4, 16.4, 19.4 } do
		Furniture.CounterModule(Props, at(x, 0, -11.3, Z), "D", cabinet, top)
	end
	-- Quina do L (sem gaveta: o canto de balcão real também não tem), um
	-- pouco mais larga pra gaveta do lado leste não bater na frente do sul.
	local cornerModel = Kit.Model(Props, "BalcaoCanto")
	Kit.P(cornerModel, "Corpo", Vector3.new(2.6, 2.6, 2.7), house * CFrame.new(22.2, 1.65, -11.15), Enum.Material.WoodPlanks, cabinet)
	Kit.P(cornerModel, "Tampo", Vector3.new(2.6, 0.16, 2.7), house * CFrame.new(22.2, 3.03, -11.15), Enum.Material.Marble, top)
	for i, z in { -8.3, -5.3, -2.3 } do
		Furniture.CounterModule(Props, at(22.3, 0, z, -X), if i == 2 then "S" else "D", cabinet, top)
	end
	Furniture.CookStove(Props, at(16.5, 0, 1.3, -Z), 20.5)
	Furniture.Fridge(Props, at(22.1, 0, 1.3, -Z))
	Furniture.DiningTable(Props, at(12, 0, -3.5), Furniture.Wood.Pine, 5, true, rng)
	Furniture.Picture(Props, at(8.5, 7, -12.45, Z), 2, 1.6, Color3.fromRGB(170, 150, 110))

	----------------------------------------------------------------------------
	-- Corredor, banheiro
	----------------------------------------------------------------------------

	Furniture.ToolChest(Props, at(10.5, 0, 4.55, Z), Color3.fromRGB(70, 84, 96))
	-- A porta do banheiro varre x 16.4..20.7 / z 5.6..10.4: nada fica nesse arco.
	Furniture.Bathtub(Props, at(22.1, 0, 8.4, -Z))
	Furniture.Toilet(Props, at(17.8, 0, 11.5, X))
	Furniture.Vanity(Props, at(19, 0, 4.35, Z), cabinet)
	Furniture.Mirror(Props, at(19, 6.2, 3.45, Z), 2.4, 2.2)

	----------------------------------------------------------------------------
	-- Quarto (ala: x 6.5 .. 23.5, z 13.4 .. 30.5)
	----------------------------------------------------------------------------

	local blanket = ({ Color3.fromRGB(150, 128, 96), Color3.fromRGB(96, 50, 46), Color3.fromRGB(70, 84, 104) })[rng:NextInteger(1, 3)]
	Furniture.Bed(Props, house, Vector3.new(15, 0, 25.4), 0, blanket)
	Furniture.Nightstand(Props, at(10.15, 0, 29.55, -Z), Furniture.Wood.Walnut, true, rng:NextNumber() < 0.5)
	-- Guarda-roupa à direita da cama: a gaveta de baixo abre até x 19,7, antes da cama.
	Furniture.Wardrobe(Props, at(22.4, 0, 27.2, -X), Furniture.Wood.Walnut)
	Furniture.Bookshelf(Props, at(7.25, 0, 27.7, X), Furniture.Wood.Walnut, rng)
	Furniture.Dresser(Props, at(22.4, 0, 16.3, -X), Furniture.Wood.Walnut)
	Furniture.Mirror(Props, at(23.45, 6.6, 16.3, -X), 3.2, 2.4)
	Furniture.Desk(Props, at(7.7, 0, 22.25, X), Furniture.Wood.Walnut, false)
	Furniture.Rug(Props, at(15, 0, 18), 8, 5, Color3.fromRGB(140, 120, 88))

	----------------------------------------------------------------------------
	-- Luzes
	----------------------------------------------------------------------------

	Kit.CeilingLight(Lights, house, Vector3.new(-15, H, 0), true, 0.55)
	Kit.CeilingLight(Lights, house, Vector3.new(0, H, -4), true, 0.5)
	Kit.CeilingLight(Lights, house, Vector3.new(14, H, -5), rng:NextNumber() < 0.7, 0.6)
	Kit.CeilingLight(Lights, house, Vector3.new(11, H, 8), false, 0.4, true)
	Kit.CeilingLight(Lights, house, Vector3.new(20, H, 8), rng:NextNumber() < 0.4, 0.45, true)
	Kit.CeilingLight(Lights, house, Vector3.new(15, H, 20), rng:NextNumber() < 0.5, 0.5)

	----------------------------------------------------------------------------
	-- Área externa e marcadores
	----------------------------------------------------------------------------

	Furniture.Woodpile(Out, at(4.2, -found, 27.5, -X), rng)
	Furniture.Barrel(Out, at(-8, -found, 15.5), Color3.fromRGB(70, 90, 110))

	local Markers = Kit.Folder(model, "Marcadores")
	Structures.SpawnPoint(Markers, at(0, -found + 2, -30))
	Structures.LootPoint(Markers, at(-12, 1.5, -8))
	Structures.LootPoint(Markers, at(18, 1.5, -6), true)
	Structures.LootPoint(Markers, at(17.5, 1.5, 16.5))

	model.PrimaryPart = floor
	model:SetAttribute("Construcao", CasaDoCaseiro.Style)
	model:SetAttribute("CasaGerada", true)
	return model
end

return CasaDoCaseiro
