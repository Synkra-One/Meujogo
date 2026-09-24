--!strict
--[[
	Celeiro (fazenda do Campo)
	Celeiro grande de fazenda, 36 x 52, vermelho com acabamento branco e
	telhado holandês (gambrel: água de baixo íngreme, de cima suave) em
	chapa de metal, com o "capuz" do feno na frente e a roldana de içar.

	  Frente (-Z): porta dupla de correr-em-X (abre pra fora, DoorSystem)
	  Corredor central de terra batida/concreto
	  Direita: 3 baias com portão (abre de verdade: esconderijo)
	  Esquerda: selaria (quarto fechado com porta), escada pro palheiro,
	            oficina embaixo do palheiro
	  Fundos: palheiro (mezanino a 12 studs) com porta de feno aberta,
	          porta dupla de trás (duas saídas no térreo)
	  Anexo (+X): telheiro aberto com trator velho, pneus e tambores
	  Fora: silo de concreto com cúpula, curral com cocho atrás

	Gavetas: bancada, gaveteiro, aparador da selaria e baús.
	Coordenadas locais: piso do celeiro em y = 0, frente = -Z.
]]

local Structures = require(script.Parent.Parent.Structures)
local Kit = require(script.Parent.HouseKit)
local Furniture = require(script.Parent.Furniture)

local Celeiro = {}

Celeiro.Style = "Celeiro"
Celeiro.Found = 0.8
Celeiro.Footprint = { MinX = -34, MaxX = 31.8, MinZ = -31.8, MaxZ = 48.6 }
-- A construção em si: o piso fica acima do ponto mais alto do terreno aqui
-- dentro, e o chão vira terra batida (sem grama).
Celeiro.Core = {
	{ MinX = -18.5, MaxX = 18.5, MinZ = -26.5, MaxZ = 26.5 },
	{ MinX = 18.5, MaxX = 30.5, MinZ = -17.5, MaxZ = 8 }, -- telheiro (chão de terra)
}
Celeiro.Entrances = {
	Vector3.new(0, 0, -29.8), -- pé da rampa da frente
	Vector3.new(0, 0, 29.8), -- pé da rampa dos fundos
}

local W, L = 36, 52
local HW, HL = W / 2, L / 2
local E = 13 -- beiral
local KNEE_X = 10 -- quebra do gambrel
local LOW_PITCH, HIGH_PITCH = 60, 25
local LOFT_Y = 12 -- piso do palheiro
local LOFT_Z = 8 -- borda da frente do palheiro

local UPRIGHT = CFrame.Angles(0, 0, math.pi / 2)

local function palette(rng: Random): Kit.Palette
	local weather = rng:NextNumber(0.05, 0.22)
	return {
		Siding = Color3.fromRGB(146, 40, 32):Lerp(Color3.fromRGB(110, 92, 84), weather),
		SidingMat = Enum.Material.WoodPlanks,
		Interior = Color3.fromRGB(116, 86, 58),
		InteriorMat = Enum.Material.WoodPlanks,
		Trim = Color3.fromRGB(222, 216, 202),
		Roof = Color3.fromRGB(122, 120, 114),
		Floor = Color3.fromRGB(122, 118, 108),
		Ceiling = Color3.fromRGB(120, 90, 60),
		CeilingMat = Enum.Material.WoodPlanks,
		Foundation = Color3.fromRGB(118, 114, 106),
		FoundationMat = Enum.Material.Concrete,
		Shutter = Color3.fromRGB(222, 216, 202),
		Door = Color3.fromRGB(96, 70, 48),
		Deck = Color3.fromRGB(104, 80, 56),
	}
end

--------------------------------------------------------------------------------
-- Peças do celeiro
--------------------------------------------------------------------------------

--[[
	Folha de porta de celeiro (DoorSystem): tábuas com moldura e "X" brancos
	soldados dos dois lados. hingeSide = lado (x da casa, -1/+1) da dobradiça;
	swing = pra onde abre (vetor local).
]]
local function barnLeaf(parent: Instance, house: CFrame, x0: number, x1: number, z: number, height: number, hingeSide: number, swing: Vector3, pal: Kit.Palette): Part
	local model = Kit.Model(parent, "PortaCeleiro")
	local w = x1 - x0 - 0.15
	local h = height - 0.12
	-- Folha pendurada na face de FORA da parede (como porta de celeiro de
	-- verdade): assim ela gira os 100° sem encostar na parede.
	local outside = z + swing.Z * (0.5 + 0.22)
	local cf = Kit.At(house, Vector3.new((x0 + x1) / 2, height / 2 - 0.06, outside), swing)
	local leaf = Kit.P(model, "Porta", Vector3.new(w, h, 0.4), cf, Enum.Material.WoodPlanks, pal.Siding:Lerp(Color3.new(0, 0, 0), 0.08))
	local hingeRight = hingeSide * cf.RightVector:Dot((house - house.Position) * Vector3.new(1, 0, 0)) > 0
	leaf:SetAttribute("Porta", true)
	leaf:SetAttribute("PortaAberta", false)
	leaf:SetAttribute("CFrameFechada", cf)
	leaf:SetAttribute("LarguraPorta", w)
	if hingeRight then
		leaf:SetAttribute("DobradicaDireita", true)
	end
	local diag = math.sqrt((w - 1) ^ 2 + (h - 1) ^ 2)
	local angle = math.atan2(h - 1, w - 1)
	for _, face in { -1, 1 } do
		local z0 = face * 0.24
		local pieces = {
			Kit.P(model, "Moldura", Vector3.new(w, 0.55, 0.1), cf * CFrame.new(0, h / 2 - 0.28, z0), Enum.Material.Wood, pal.Trim, Kit.Deco),
			Kit.P(model, "Moldura", Vector3.new(w, 0.55, 0.1), cf * CFrame.new(0, -h / 2 + 0.28, z0), Enum.Material.Wood, pal.Trim, Kit.Deco),
			Kit.P(model, "Moldura", Vector3.new(0.55, h, 0.1), cf * CFrame.new(-w / 2 + 0.28, 0, z0), Enum.Material.Wood, pal.Trim, Kit.Deco),
			Kit.P(model, "Moldura", Vector3.new(0.55, h, 0.1), cf * CFrame.new(w / 2 - 0.28, 0, z0), Enum.Material.Wood, pal.Trim, Kit.Deco),
			Kit.P(model, "Xis", Vector3.new(diag, 0.5, 0.08), cf * CFrame.new(0, 0, z0) * CFrame.Angles(0, 0, angle), Enum.Material.Wood, pal.Trim, Kit.Deco),
			Kit.P(model, "Xis", Vector3.new(diag, 0.5, 0.08), cf * CFrame.new(0, 0, z0) * CFrame.Angles(0, 0, -angle), Enum.Material.Wood, pal.Trim, Kit.Deco),
			Kit.P(model, "Puxador", Vector3.new(0.18, 1.6, 0.22), cf * CFrame.new(-hingeSide * math.sign(cf.RightVector:Dot((house - house.Position) * Vector3.new(1, 0, 0))) * (w / 2 - 0.9), -0.8, face * 0.36), Enum.Material.Metal, Color3.fromRGB(40, 38, 36), Kit.Deco),
		}
		for _, piece in pieces do
			Kit.Weld(leaf, piece)
		end
	end
	for _, y in { h / 2 - 1.2, -h / 2 + 1.2 } do
		local strap = Kit.P(model, "Dobradica", Vector3.new(1.8, 0.3, 0.5), cf * CFrame.new(math.sign(hingeSide * cf.RightVector:Dot((house - house.Position) * Vector3.new(1, 0, 0))) * (w / 2 - 0.9), y, 0), Enum.Material.Metal, Color3.fromRGB(40, 38, 36), Kit.Deco)
		Kit.Weld(leaf, strap)
	end
	return leaf
end

-- Rampa (cunha) do chão até o piso, em frente a uma porta. `at` = meio da
-- borda de cima (na soleira); `out` = direção em que a rampa desce.
local function ramp(parent: Instance, house: CFrame, at: Vector3, out: Vector3, width: number, rise: number, length: number, pal: Kit.Palette)
	local mid = at + out * (length / 2) + Vector3.new(0, -rise / 2, 0)
	-- Face alta (+Z do wedge) encostada na soleira: +Z = -out.
	local back = -out
	local cf = house * CFrame.fromMatrix(mid, Vector3.new(0, 1, 0):Cross(back), Vector3.new(0, 1, 0), back)
	Kit.Wedge(parent, "Rampa", Vector3.new(width, rise, length), cf, Enum.Material.Concrete, pal.Foundation)
	local extra = Kit.ExtraDepth + 1.2
	Kit.P(parent, "RampaBase", Vector3.new(width, extra, length), house * CFrame.new(mid.X, at.Y - rise - extra / 2, mid.Z), Enum.Material.Concrete, pal.Foundation)
end

-- Fardo quadrado de feno (o redondo do Structures é de campo aberto).
local function bale(parent: Instance, cf: CFrame, collide: boolean?)
	Kit.P(parent, "Fardo", Vector3.new(3.6, 1.8, 2.2), cf * CFrame.new(0, 0.9, 0), Enum.Material.Grass, Color3.fromRGB(196, 168, 92), { Collide = collide ~= false })
	Kit.P(parent, "Amarra", Vector3.new(0.08, 1.82, 2.22), cf * CFrame.new(-0.9, 0.9, 0), Enum.Material.Fabric, Color3.fromRGB(150, 110, 60), Kit.Deco)
	Kit.P(parent, "Amarra", Vector3.new(0.08, 1.82, 2.22), cf * CFrame.new(0.9, 0.9, 0), Enum.Material.Fabric, Color3.fromRGB(150, 110, 60), Kit.Deco)
end

local function straw(parent: Instance, house: CFrame, x: number, z: number, w: number, d: number, y: number, rng: Random)
	Kit.P(parent, "Palha", Vector3.new(w, 0.08, d), house * CFrame.new(x, y + 0.04, z) * CFrame.Angles(0, rng:NextNumber(-0.3, 0.3), 0), Enum.Material.Grass, Color3.fromRGB(186, 160, 90), Kit.Deco)
end

--------------------------------------------------------------------------------
-- Build
--------------------------------------------------------------------------------

export type BuildOpts = { Name: string?, Seed: number? }

function Celeiro.Build(parent: Instance, house: CFrame, opts: BuildOpts?): Model
	local o = opts or {}
	local rng = Random.new(o.Seed or 1)
	local pal = palette(rng)
	local found = Celeiro.Found
	local ground = -found

	local model = Kit.Model(parent, o.Name or "Celeiro")
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
	local metal = Enum.Material.CorrodedMetal

	----------------------------------------------------------------------------
	-- Base, piso
	----------------------------------------------------------------------------

	Kit.Foundation(S, house, -HW - 0.5, HW + 0.5, -HL - 0.5, HL + 0.5, found, pal)
	local floor = Kit.Floor(S, house, -HW - 0.5, HW + 0.5, -HL - 0.5, HL + 0.5, Enum.Material.Concrete, pal.Floor)
	for _ = 1, 14 do
		straw(S, house, rng:NextNumber(-15, 15), rng:NextNumber(-24, 6), rng:NextNumber(2, 5), rng:NextNumber(2, 4), 0, rng)
	end

	----------------------------------------------------------------------------
	-- Paredes externas (até o beiral)
	----------------------------------------------------------------------------

	Kit.Wall(S, house, v(-HW - 0.5, -HL), v(HW + 0.5, -HL), E, {
		{ x0 = -7, x1 = 7, y0 = 0, y1 = 12 },
	}, pal, { Exterior = true, InsideDir = Z })
	Kit.Wall(S, house, v(-HW - 0.5, HL), v(HW + 0.5, HL), E, {
		{ x0 = -6, x1 = 6, y0 = 0, y1 = 11 },
	}, pal, { Exterior = true, InsideDir = -Z })
	-- Esquerda: janela da selaria e da oficina. x local = z da casa.
	Kit.Wall(S, house, v(-HW, -HL + 0.5), v(-HW, HL - 0.5), E, {
		{ x0 = -22.5, x1 = -19.5, y0 = 5, y1 = 7.5 },
		{ x0 = 21, x1 = 24, y0 = 5, y1 = 7.5 },
	}, pal, { Exterior = true, InsideDir = X })
	-- Direita: janelinha de cada baia e a porta do telheiro.
	Kit.Wall(S, house, v(HW, -HL + 0.5), v(HW, HL - 0.5), E, {
		{ x0 = -22.5, x1 = -19.5, y0 = 6, y1 = 8.5 },
		{ x0 = -14, x1 = -11, y0 = 6, y1 = 8.5 },
		{ x0 = -5.5, x1 = -2.5, y0 = 6, y1 = 8.5 },
		{ x0 = 1.5, x1 = 6, y0 = 0, y1 = 8 },
	}, pal, { Exterior = true, InsideDir = -X })
	for _, sx in { -1, 1 } do
		for _, sz in { -1, 1 } do
			Kit.CornerBoard(S, house, sx * HW, sz * HL, E, pal.Trim)
		end
	end

	----------------------------------------------------------------------------
	-- Empenas gambrel (retângulo do meio + triângulos) e telhado
	----------------------------------------------------------------------------

	local lowRun = HW + 0.5 - KNEE_X
	local kneeY = E + lowRun * math.tan(math.rad(LOW_PITCH))
	local ridgeY = kneeY + KNEE_X * math.tan(math.rad(HIGH_PITCH))
	for _, sz in { -1, 1 } do
		local zc = sz * HL
		local inside = Vector3.new(0, 0, -sz)
		local openings = if sz < 0
			then { { x0 = -3, x1 = 3, y0 = 3, y1 = 9 } } -- porta de feno da frente (sob o capuz)
			else { { x0 = -3.5, x1 = 3.5, y0 = 0.4, y1 = 7.5 } } -- porta do palheiro, nos fundos
		Kit.Wall(S, house, v(-KNEE_X, zc, E), v(KNEE_X, zc, E), kneeY - E, openings, pal, { Exterior = true, InsideDir = inside, NoTrim = true })
		for _, side in { -1, 1 } do
			-- Triângulo de baixo: lado vertical em x = ±KNEE_X, base no beiral.
			local mid = Vector3.new(side * (KNEE_X + lowRun / 2), E + (kneeY - E) / 2, zc)
			local back = Vector3.new(-side, 0, 0)
			Kit.Wedge(S, "Empena", Vector3.new(1, kneeY - E, lowRun), house * CFrame.fromMatrix(mid, Vector3.new(0, 1, 0):Cross(back), Vector3.new(0, 1, 0), back), pal.SidingMat, pal.Siding)
		end
		Kit.GableEnd(S, house, v(0, zc, kneeY), X, KNEE_X * 2, ridgeY - kneeY, 1, pal.SidingMat, pal.Siding)
		-- Faixa branca na quebra do telhado (a cara de celeiro americano).
		Kit.P(S, "FaixaEmpena", Vector3.new(W + 1, 0.5, 0.14), house * CFrame.new(0, E + 0.25, zc + sz * 0.57), Enum.Material.Wood, pal.Trim, Kit.Deco)
	end
	-- Folha fixa na porta de feno da frente (só dá pra ver de fora).
	Kit.P(S, "PortaFeno", Vector3.new(6, 6, 0.3), house * CFrame.new(0, E + 6, -HL - 0.2), Enum.Material.WoodPlanks, pal.Siding:Lerp(Color3.new(0, 0, 0), 0.1))
	Kit.P(S, "PortaFenoXis", Vector3.new(8, 0.4, 0.08), house * CFrame.new(0, E + 6, -HL - 0.45) * CFrame.Angles(0, 0, math.rad(45)), Enum.Material.Wood, pal.Trim, Kit.Deco)
	Kit.P(S, "PortaFenoXis", Vector3.new(8, 0.4, 0.08), house * CFrame.new(0, E + 6, -HL - 0.45) * CFrame.Angles(0, 0, math.rad(-45)), Enum.Material.Wood, pal.Trim, Kit.Deco)

	-- Águas de cima vão até a frente do capuz; as de baixo param no beiral.
	local hoodZ = -HL - 0.5 - 4.7
	local backZ = HL + 0.5 + 1.2
	local ra, rb = v(0, hoodZ, ridgeY), v(0, backZ, ridgeY)
	for _, side in { -1, 1 } do
		local down = Vector3.new(side, 0, 0)
		Kit.RoofSlope(S, house, ra, rb, down, KNEE_X, HIGH_PITCH, pal.Roof, 0.55, false, metal)
		Kit.RoofSlope(S, house, v(side * KNEE_X, -HL - 1.7, kneeY), v(side * KNEE_X, backZ, kneeY), down, lowRun + 1.1, LOW_PITCH, pal.Roof, 0.55, true, metal)
		Kit.P(S, "Quebra", Vector3.new(0.7, 0.7, backZ + HL + 1.7), house * CFrame.new(side * KNEE_X, kneeY + 0.35, (backZ - HL - 1.7) / 2) * CFrame.Angles(0, 0, math.rad(45)), metal, pal.Roof:Lerp(Color3.new(0, 0, 0), 0.25), Kit.Deco)
	end
	Kit.RidgeCap(S, house, ra, rb, pal.Roof, metal)

	-- Roldana de içar feno sob o capuz.
	local beamY = ridgeY - 2.4
	Kit.P(Out, "VigaRoldana", Vector3.new(0.7, 0.7, 5.4), house * CFrame.new(0, beamY, -HL - 2.4), Enum.Material.Wood, Color3.fromRGB(70, 52, 36), Kit.Deco)
	Kit.P(Out, "Roldana", Vector3.new(0.35, 1.1, 1.1), house * CFrame.new(0, beamY - 0.8, -HL - 4.6), Enum.Material.Metal, Color3.fromRGB(40, 38, 36), { Collide = false, Shape = Enum.PartType.Cylinder })
	local ropeLen = beamY - 0.8 - (E + 3)
	Kit.P(Out, "Corda", Vector3.new(0.12, ropeLen, 0.12), house * CFrame.new(0, beamY - 0.8 - ropeLen / 2, -HL - 4.6), Enum.Material.Fabric, Color3.fromRGB(170, 140, 90), Kit.Deco)
	Kit.P(Out, "Gancho", Vector3.new(0.3, 0.8, 0.3), house * CFrame.new(0, E + 2.6, -HL - 4.6), Enum.Material.Metal, Color3.fromRGB(40, 38, 36), Kit.Deco)

	-- Cata-vento de galo na cumeeira.
	local vane = house * CFrame.new(0, ridgeY + 0.5, 0)
	Kit.P(Out, "CataVentoHaste", Vector3.new(0.15, 4, 0.15), vane * CFrame.new(0, 2, 0), Enum.Material.Metal, Color3.fromRGB(30, 30, 30), Kit.Deco)
	Kit.P(Out, "CataVentoSeta", Vector3.new(0.1, 0.2, 3.2), vane * CFrame.new(0, 3.2, 0) * CFrame.Angles(0, 0.7, 0), Enum.Material.Metal, Color3.fromRGB(30, 30, 30), Kit.Deco)
	Kit.P(Out, "CataVentoGalo", Vector3.new(0.08, 1.4, 1.6), vane * CFrame.new(0, 4.3, 0) * CFrame.Angles(0, 0.7, 0), Enum.Material.Metal, Color3.fromRGB(30, 30, 30), Kit.Deco)

	-- Estrutura aparente: tirantes no beiral e na quebra.
	for _, z in { -17, -8.5, 0 } do
		Kit.P(S, "Tirante", Vector3.new(W - 1, 0.8, 0.8), house * CFrame.new(0, E + 0.3, z), Enum.Material.Wood, Color3.fromRGB(84, 62, 42), Kit.Deco)
	end
	for _, z in { -17, -4, 9, 22 } do
		Kit.P(S, "Linha", Vector3.new(KNEE_X * 2, 0.6, 0.6), house * CFrame.new(0, kneeY - 0.4, z), Enum.Material.Wood, Color3.fromRGB(84, 62, 42), Kit.Deco)
	end

	----------------------------------------------------------------------------
	-- Portas
	----------------------------------------------------------------------------

	barnLeaf(Doors, house, -7, 0, -HL, 12, -1, -Z, pal)
	barnLeaf(Doors, house, 0, 7, -HL, 12, 1, -Z, pal)
	barnLeaf(Doors, house, -6, 0, HL, 11, -1, Z, pal)
	barnLeaf(Doors, house, 0, 6, HL, 11, 1, Z, pal)
	ramp(Out, house, v(0, -HL - 0.5), -Z, 14.5, found, 3, pal)
	ramp(Out, house, v(0, HL + 0.5), Z, 12.5, found, 3, pal)
	-- Porta lateral pro telheiro (abre pra dentro, encosta na parede).
	Kit.Door(Doors, house, v(HW, 3.75), Z, -X, 4.5, 8, pal, { Name = "PortaTelheiro", HingeAtEnd = true, Color = pal.Door })
	Kit.WallLantern(Lights, house, Vector3.new(8.2, 9, -HL - 0.5), -Z, true)

	for _, spec in {
		{ Vector3.new(-HW, 6.25, -21), -X, 3, 2.5 },
		{ Vector3.new(-HW, 6.25, 22.5), -X, 3, 2.5 },
		{ Vector3.new(HW, 7.25, -21), X, 3, 2.5 },
		{ Vector3.new(HW, 7.25, -12.5), X, 3, 2.5 },
		{ Vector3.new(HW, 7.25, -4), X, 3, 2.5 },
	} do
		Kit.Window(Win, house, spec[1], spec[2], spec[3], spec[4], pal, { Shutters = false })
	end

	----------------------------------------------------------------------------
	-- Baias (direita, x 7.5 .. 17.5, z -25.5 .. 0) -- a porta da frente
	-- (x -7..7) abre inteira pro corredor.
	----------------------------------------------------------------------------

	local STALL_H = 4.6
	local stalls = { { -25.5, -17 }, { -17, -8.5 }, { -8.5, 0 } }
	local stallWall: { Kit.Opening } = {}
	for _, st in stalls do
		local mid = (st[1] + st[2]) / 2
		table.insert(stallWall, { x0 = mid - 2 + 12.75, x1 = mid + 2 + 12.75, y0 = 0, y1 = STALL_H })
	end
	-- Frente das baias em x = 7.5 (x local da parede = z + 12.75).
	local SX = 7.5
	Kit.Wall(S, house, v(SX, -25.5), v(SX, 0), STALL_H, stallWall, pal, { Thickness = 0.4 })
	for _, z in { -17, -8.5, 0 } do
		Kit.Wall(S, house, v(SX + 0.2, z), v(HW - 0.5, z), STALL_H, {}, pal, { Thickness = 0.4 })
		-- Grade de ferro por cima da divisória (não dá pra pular pra outra baia).
		Kit.P(S, "Grade", Vector3.new(HW - 0.5 - SX - 0.2, 2.6, 0.2), house * CFrame.new((SX + 0.2 + HW - 0.5) / 2, STALL_H + 1.3, z), Enum.Material.SmoothPlastic, Color3.new(0, 0, 0), { Transparency = 1, Shadow = false })
		for x = SX + 1, HW - 1, 0.9 do
			Kit.P(S, "Barra", Vector3.new(0.1, 2.6, 0.1), house * CFrame.new(x, STALL_H + 1.3, z), Enum.Material.Metal, Color3.fromRGB(40, 38, 36), Kit.Deco)
		end
		Kit.P(S, "BarraTopo", Vector3.new(HW - 0.5 - SX - 0.2, 0.15, 0.15), house * CFrame.new((SX + 0.2 + HW - 0.5) / 2, STALL_H + 2.6, z), Enum.Material.Metal, Color3.fromRGB(40, 38, 36), Kit.Deco)
	end
	local blanket = Color3.fromRGB(70, 60, 110)
	for i, st in stalls do
		local mid = (st[1] + st[2]) / 2
		Kit.Door(Doors, house, v(SX, mid), Z, X, 4, STALL_H, pal, { Name = "PortaoBaia", HingeAtEnd = true, Thickness = 0.4, Color = Color3.fromRGB(110, 82, 56) })
		Furniture.Trough(Props, at(HW - 1.5, 0, mid, -X), 5)
		straw(Props, house, 12.8, mid, 7.5, 6.5, 0.02, rng)
		if i == 2 then
			Kit.P(Props, "Manta", Vector3.new(0.15, 2.4, 4.5), house * CFrame.new(SX + 0.4, 3.3, mid - 2.5), Enum.Material.Fabric, blanket, Kit.Deco)
		elseif i == 3 then
			-- Mancha escura no feno da última baia.
			Kit.P(Props, "Mancha", Vector3.new(2.6, 0.03, 1.8), house * CFrame.new(12, 0.11, mid + 1) * CFrame.Angles(0, 0.4, 0), Enum.Material.SmoothPlastic, Color3.fromRGB(64, 18, 16), Kit.Deco)
		end
	end
	bale(Props, at(13.2, 0, -22.8, X))

	----------------------------------------------------------------------------
	-- Selaria (esquerda, frente: x -17.5 .. -6.4, z -25.5 .. -16.4)
	----------------------------------------------------------------------------

	local tackTop = 10.5
	-- Parede em x = -7.5: a porta grande da frente (x -7..7) abre pro corredor.
	Kit.Wall(S, house, v(-7.5, -25.5), v(-7.5, -16), tackTop + 0.4, { { x0 = -2.25 - 0.5, x1 = 2.25 - 0.5, y0 = 0, y1 = 8 } }, pal, { Thickness = 0.8 })
	Kit.Wall(S, house, v(-17.5, -16), v(-7.1, -16), tackTop + 0.4, {}, pal, { Thickness = 0.8 })
	Kit.Ceiling(S, house, -17.5, -7.9, -25.5, -16.4, tackTop, pal)
	-- Dobradiça do lado norte: a folha aberta encosta na parede de dentro, longe do baú.
	Kit.Door(Doors, house, v(-7.5, -21.25), Z, -X, 4.5, 8, pal, { Name = "PortaSelaria", HingeAtEnd = true, Thickness = 0.8, Color = pal.Door })
	Furniture.Sideboard(Props, at(-16.5, 0, -21.3, X), Furniture.Wood.Walnut)
	Furniture.Trunk(Props, at(-11.1, 0, -24.4, Z), Color3.fromRGB(86, 64, 44))
	for _, x in { -15, -12.6 } do
		Furniture.SaddleRack(Props, at(x, 4.6, -16.45, -Z))
	end
	Furniture.HangingLantern(Lights, at(-12.6, tackTop, -20.8), 1.2, true)

	----------------------------------------------------------------------------
	-- Escada e palheiro (fundos: z 8 .. 25.5, y 12)
	----------------------------------------------------------------------------

	local loftTop = LOFT_Y
	Kit.P(S, "PisoSuperior", Vector3.new(W - 1, 0.6, HL - 0.5 - LOFT_Z), house * CFrame.new(0, loftTop - 0.3, (LOFT_Z + HL - 0.5) / 2), Enum.Material.WoodPlanks, Color3.fromRGB(122, 94, 64))
	Kit.P(S, "VigaPalheiro", Vector3.new(W - 1, 0.8, 0.7), house * CFrame.new(0, loftTop - 1.0, LOFT_Z + 0.35), Enum.Material.Wood, Color3.fromRGB(84, 62, 42))
	for _, x in { -6, 6 } do
		Kit.P(S, "Esteio", Vector3.new(0.9, loftTop - 1.4, 0.9), house * CFrame.new(x, (loftTop - 1.4) / 2, LOFT_Z + 0.35), Enum.Material.Wood, Color3.fromRGB(84, 62, 42))
	end
	-- Escada afastada da parede: encostada nela, o telhado íngreme de baixo
	-- tiraria a altura dos últimos degraus. Atrás dela fica um corredor
	-- estreito que liga a frente à oficina (rota de fuga/esconderijo).
	local stairW = 3.8
	local stairX = -11.6
	Kit.Railing(S, house, v(-HW + 0.6, LOFT_Z + 0.3, loftTop), v(stairX - stairW / 2 - 0.3, LOFT_Z + 0.3, loftTop), pal)
	Kit.Railing(S, house, v(stairX + stairW / 2 + 0.3, LOFT_Z + 0.3, loftTop), v(HW - 0.6, LOFT_Z + 0.3, loftTop), pal)
	local stairRun = Kit.Stairs(S, house, v(stairX, LOFT_Z, loftTop), -Z, stairW, loftTop, pal, { Run = 1.05, Interior = true, Color = Color3.fromRGB(110, 84, 56) })
	-- Corrimão inclinado dos dois lados (os dois são abertos).
	for _, side in { -1, 1 } do
		local railA = Vector3.new(stairX + side * (stairW / 2 + 0.2), 3.1, LOFT_Z - stairRun + 1.05)
		local railB = Vector3.new(stairX + side * (stairW / 2 + 0.2), loftTop + 3.1, LOFT_Z)
		local railDir = (railB - railA)
		Kit.P(S, "CorrimaoEscada", Vector3.new(0.3, 0.3, railDir.Magnitude), house * CFrame.lookAt((railA + railB) / 2, railB), Enum.Material.Wood, pal.Trim)
		for i = 2, 18, 2 do
			local p = railA:Lerp(railB, i / 20)
			Kit.P(S, "Balaustre", Vector3.new(0.2, 3.0, 0.2), house * CFrame.new(p.X, p.Y - 1.5, p.Z), Enum.Material.Wood, pal.Trim, Kit.Deco)
		end
	end

	-- Porta do palheiro (fundos): barra de segurança na altura do peito.
	Kit.P(S, "BarraPalheiro", Vector3.new(7, 0.3, 0.3), house * CFrame.new(0, loftTop + 3.2, HL - 0.2), Enum.Material.Wood, pal.Trim)
	for i = 1, 5 do
		local x = -15 + i * 5.2
		bale(Props, at(x, loftTop, 23.6, Z))
		if i ~= 3 then
			bale(Props, at(x, loftTop + 1.8, 23.6, Z))
		end
	end
	for _, x in { -12, 12 } do
		bale(Props, at(x, loftTop, 19.4, X))
		bale(Props, at(x, loftTop, 15.6, X))
	end
	straw(Props, house, 0, 16, 10, 6, loftTop, rng)
	Furniture.Trunk(Props, at(4.5, loftTop, 13.4, -Z), Color3.fromRGB(70, 56, 44))
	Furniture.HangingLantern(Lights, at(0, kneeY - 0.7, 16), 3.5, rng:NextNumber() < 0.6)

	----------------------------------------------------------------------------
	-- Oficina (esquerda, embaixo do palheiro) e depósito (direita)
	----------------------------------------------------------------------------

	Furniture.Workbench(Props, at(-HW + 0.5 + 1.3, 0, 15.5, X), Color3.fromRGB(96, 74, 52))
	Furniture.Pegboard(Props, at(-HW + 0.55, 5.8, 15.5, X))
	Furniture.ToolChest(Props, at(-11, 0, HL - 0.5 - 1.15, -Z), Color3.fromRGB(56, 72, 60))
	Furniture.Barrel(Props, at(-7.6, 0, 18.4), Color3.fromRGB(80, 64, 48))
	Furniture.HangingLantern(Lights, at(-11, loftTop - 0.6, 18), 1.0, true)
	for i = 0, 2 do
		bale(Props, at(12.2, 0, 10.5 + i * 3.7, X))
		bale(Props, at(12.2, 1.8, 10.5 + i * 3.7, X))
	end
	Furniture.FeedSacks(Props, at(9, 0, 22.5, -Z), rng)
	Furniture.Barrel(Props, at(15.5, 0, 23.2), Color3.fromRGB(64, 84, 60))

	-- Lampiões do corredor.
	Furniture.HangingLantern(Lights, at(0, E - 0.1, -17), 2.4, true)
	Furniture.HangingLantern(Lights, at(0, E - 0.1, 0), 2.4, rng:NextNumber() < 0.7)

	----------------------------------------------------------------------------
	-- Telheiro (anexo +X: x 18.5 .. 30.5, z -20 .. 8), piso de terra
	----------------------------------------------------------------------------

	-- Começa entre as janelas das baias 1 e 2 (a da 1 continua pra fora).
	local shedZ0, shedZ1 = -17.5, 8
	local shedOuter = HW + 0.5 + 12
	local shedPitch = 16
	local shedTop = 10.6 -- abaixo da ponta do beiral do celeiro
	Kit.RoofSlope(Out, house, v(HW + 0.5, shedZ0 - 0.6, shedTop), v(HW + 0.5, shedZ1 + 0.6, shedTop), X, 12.6, shedPitch, pal.Roof, 0.45, true, metal)
	local postTop = shedTop - (shedOuter - 0.5 - (HW + 0.5)) * math.tan(math.rad(shedPitch))
	for _, z in { shedZ0 + 0.5, -8, 0, shedZ1 - 0.5 } do
		Kit.Post(Out, house, shedOuter - 0.5, z, ground - 0.5 - Kit.ExtraDepth, postTop, pal)
	end
	Kit.P(Out, "VigaTelheiro", Vector3.new(0.7, 0.7, shedZ1 - shedZ0), house * CFrame.new(shedOuter - 0.5, postTop - 0.35, (shedZ0 + shedZ1) / 2), Enum.Material.Wood, pal.Trim)
	-- Fechamento das duas pontas (tábua até o telhado).
	for _, z in { shedZ0, shedZ1 } do
		local wallH = postTop - ground - 0.4
		Kit.P(Out, "ParedeTelheiro", Vector3.new(12, wallH, 0.5), house * CFrame.new(HW + 0.5 + 6, ground + wallH / 2, z), Enum.Material.WoodPlanks, pal.Siding)
		local topRise = shedTop - postTop
		Kit.Wedge(Out, "EmpenaTelheiro", Vector3.new(0.5, topRise, 11.5), house * CFrame.fromMatrix(Vector3.new(HW + 0.5 + 5.75, postTop - 0.4 + topRise / 2, z), Vector3.new(0, 0, 1), Vector3.new(0, 1, 0), Vector3.new(-1, 0, 0)), Enum.Material.WoodPlanks, pal.Siding)
	end
	-- Rampa interna da porta lateral (piso do celeiro -> chão do telheiro).
	ramp(Out, house, v(HW + 0.5, 3.75), X, 4.5, found, 2.5, pal)
	Furniture.Tractor(Out, at(25.2, ground, -4.5, -Z))
	for i = 0, 3 do
		Kit.P(Out, "Pneu", Vector3.new(0.9, 3.2, 3.2), house * CFrame.new(28.3, ground + 0.45 + i * 0.9, -12.3) * UPRIGHT, Kit.Mat.Rubber, Color3.fromRGB(28, 26, 24), { Shape = Enum.PartType.Cylinder, Collide = i == 0 })
	end
	Furniture.Barrel(Out, at(27.4, ground, 5.6), Color3.fromRGB(120, 56, 40))
	Furniture.Barrel(Out, at(27.6, ground, 2.9), Color3.fromRGB(120, 56, 40))
	Furniture.Woodpile(Out, at(23.6, ground, -15.9, Z), rng)

	----------------------------------------------------------------------------
	-- Silo (esquerda, fora)
	----------------------------------------------------------------------------

	local siloX, siloZ, siloR = -27.2, 10, 6
	local siloTop = 34
	local siloBottom = ground - 1.2 - Kit.ExtraDepth
	local concrete = Color3.fromRGB(176, 170, 158)
	Kit.P(Out, "Silo", Vector3.new(siloTop - siloBottom, siloR * 2, siloR * 2), house * CFrame.new(siloX, (siloTop + siloBottom) / 2, siloZ) * UPRIGHT, Enum.Material.Concrete, concrete, { Shape = Enum.PartType.Cylinder })
	Kit.P(Out, "SiloBase", Vector3.new(1.2, siloR * 2 + 0.8, siloR * 2 + 0.8), house * CFrame.new(siloX, ground + 0.2, siloZ) * UPRIGHT, Enum.Material.Concrete, Color3.fromRGB(140, 136, 126), { Shape = Enum.PartType.Cylinder })
	Kit.P(Out, "SiloCupula", Vector3.new(siloR * 2 + 0.3, siloR * 2 + 0.3, siloR * 2 + 0.3), house * CFrame.new(siloX, siloTop, siloZ), metal, Color3.fromRGB(128, 52, 38), { Shape = Enum.PartType.Ball })
	for y = ground + 4, siloTop - 2, 4.5 do
		Kit.P(Out, "SiloCinta", Vector3.new(0.35, siloR * 2 + 0.16, siloR * 2 + 0.16), house * CFrame.new(siloX, y, siloZ) * UPRIGHT, Enum.Material.Metal, Color3.fromRGB(70, 66, 60), { Collide = false, Shape = Enum.PartType.Cylinder })
	end
	-- Calha de portinholas + escada de marinheiro na face da frente (-Z).
	local faceZ = siloZ - siloR
	Kit.P(Out, "SiloCalha", Vector3.new(1.8, siloTop - ground - 3, 0.9), house * CFrame.new(siloX, (siloTop + ground - 1) / 2, faceZ - 0.3), Enum.Material.Concrete, concrete:Lerp(Color3.new(0, 0, 0), 0.1))
	for y = ground + 3, siloTop - 3, 3 do
		Kit.P(Out, "SiloPortinhola", Vector3.new(1.3, 1.6, 0.1), house * CFrame.new(siloX, y, faceZ - 0.8), Enum.Material.WoodPlanks, Color3.fromRGB(96, 70, 48), Kit.Deco)
	end
	for _, dx in { -1.6, 1.6 } do
		Kit.P(Out, "EscadaTrilho", Vector3.new(0.15, siloTop - ground - 4, 0.15), house * CFrame.new(siloX + dx, (siloTop + ground) / 2, faceZ - 1.1), Enum.Material.Metal, Color3.fromRGB(60, 58, 54), Kit.Deco)
	end

	----------------------------------------------------------------------------
	-- Curral (atrás do celeiro)
	----------------------------------------------------------------------------

	local cz0, cz1, cx = HL + 4, HL + 22, 16
	local function fence(a: Vector3, b: Vector3)
		local dir = (b - a)
		local len = dir.Magnitude
		local n = math.max(1, math.floor(len / 5 + 0.5))
		for i = 0, n do
			local p = a + dir * (i / n)
			-- Enterrado 1,2 (+ o desnível do terreno), 3,8 acima do chão.
			Kit.P(Out, "Mourao", Vector3.new(0.6, 5.0 + Kit.ExtraDepth, 0.6), house * CFrame.new(p.X, ground + 1.3 - Kit.ExtraDepth / 2, p.Z), Enum.Material.Wood, Color3.fromRGB(96, 76, 56))
		end
		local mid = (a + b) / 2
		for _, y in { 1.6, 3.4 } do
			Kit.P(Out, "Travessa", Vector3.new(0.35, 0.45, len), house * CFrame.lookAt(Vector3.new(mid.X, ground + y, mid.Z), Vector3.new(b.X, ground + y, b.Z)), Enum.Material.Wood, Color3.fromRGB(120, 96, 70))
		end
	end
	-- Porteira larga: as folhas de trás abrem até x ±7 sem bater na cerca.
	fence(v(-cx, cz0), v(-8.5, cz0))
	fence(v(8.5, cz0), v(cx, cz0))
	fence(v(-cx, cz0), v(-cx, cz1))
	fence(v(cx, cz0), v(cx, cz1))
	fence(v(-cx, cz1), v(cx, cz1))
	Furniture.Trough(Out, at(-9, ground, cz1 - 2.5, Z), 7)
	Kit.P(Out, "FenoRedondo", Vector3.new(3.4, 3.4, 4.2), house * CFrame.new(9, ground + 1.7, cz1 - 5) * UPRIGHT, Enum.Material.Grass, Color3.fromRGB(196, 168, 92), { Shape = Enum.PartType.Cylinder })

	----------------------------------------------------------------------------
	-- Marcadores
	----------------------------------------------------------------------------

	local Markers = Kit.Folder(model, "Marcadores")
	Structures.SpawnPoint(Markers, at(0, ground + 2, -34))
	Structures.LootPoint(Markers, at(-1, 1.5, -10))
	Structures.LootPoint(Markers, at(-12.3, 1.5, -20.4), true)
	Structures.LootPoint(Markers, at(-2, loftTop + 1.5, 17))

	model.PrimaryPart = floor
	model:SetAttribute("Construcao", Celeiro.Style)
	model:SetAttribute("CasaGerada", true)
	return model
end

return Celeiro
