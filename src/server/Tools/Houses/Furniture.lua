--!strict
--[[
	Furniture
	Móveis das casas grandes. Toda função recebe `cf` = centro do móvel NO
	PISO, LookVector = frente do móvel (virada pro cômodo), e devolve o Model.

	GAVETAS (server/DrawerSystem.lua dá vida a elas)
	  Cada gaveta é um Model "Gaveta" cuja peça "Frente" é a raiz: fundo,
	  laterais, traseira e puxador são SOLDADOS na frente, então deslizam
	  junto quando o DrawerSystem move a frente pelo LookVector. O corpo do
	  móvel é maciço -- a gaveta fechada fica escondida dentro dele, e uma
	  placa escura atrás da frente vira o "vão" quando ela abre.

	  Attributes na Frente (contrato com DrawerSystem):
	    Gaveta          true
	    GavetaAberta    boolean
	    CFrameFechada   CFrame   pose fechada da frente
	    GavetaCurso     number   quanto desliza (studs)
	    GavetaInterior  Vector3  espaço útil pro item (largura, altura,
	                             profundidade da parte que sai do móvel)
	    GavetaSlot      CFrame   centro do fundo útil, relativo à frente
	    GavetaMovel     string   nome do móvel (texto do prompt)
]]

local Kit = require(script.Parent.HouseKit)

local Furniture = {}

local P = Kit.P
local DECO = Kit.Deco
local COL = Kit.Colors

local UPRIGHT = CFrame.Angles(0, 0, math.pi / 2)
local BRASS = Color3.fromRGB(170, 142, 88)
local IRON = Color3.fromRGB(40, 38, 36)
local CAVITY = Color3.fromRGB(22, 18, 15)

Furniture.Wood = {
	Oak = Color3.fromRGB(128, 90, 56),
	Walnut = Color3.fromRGB(86, 60, 40),
	Pine = Color3.fromRGB(160, 122, 80),
	Painted = Color3.fromRGB(196, 190, 172),
	Green = Color3.fromRGB(88, 106, 84),
}

--------------------------------------------------------------------------------
-- Gaveta
--------------------------------------------------------------------------------

--[[
	Drawer(parent, carcassFace, x, y, w, h, depth, color, label)
	carcassFace = CFrame no plano da FACE da frente do corpo do móvel,
	LookVector pra fora; (x, y) = centro da gaveta nesse plano.
]]
function Furniture.Drawer(parent: Instance, carcassFace: CFrame, x: number, y: number, w: number, h: number, depth: number, color: Color3, label: string): Model
	local model = Kit.Model(parent, "Gaveta")
	local frontCF = carcassFace * CFrame.new(x, y, -0.12)
	local travel = math.max(1, depth * 0.78)

	P(model, "Vao", Vector3.new(w - 0.06, h - 0.06, 0.02), carcassFace * CFrame.new(x, y, -0.01), Enum.Material.SmoothPlastic, CAVITY, DECO)

	-- Frente sem colisão/raycast: o item deitado atrás dela precisa passar no
	-- teste de linha de visão do "Pegar" (InteractionGuard) com a gaveta aberta.
	local front = P(model, "Frente", Vector3.new(w, h, 0.2), frontCF, Enum.Material.WoodPlanks, color, DECO)
	local inner = color:Lerp(Color3.new(1, 1, 1), 0.12)
	-- Bandeja de z 0.14 (já dentro do corpo) até `depth` atrás da frente.
	local trayLen = depth - 0.14
	local trayZ = 0.14 + trayLen / 2
	local pieces = {
		P(model, "Fundo", Vector3.new(w - 0.3, 0.08, trayLen), frontCF * CFrame.new(0, -h / 2 + 0.1, trayZ), Enum.Material.Wood, inner, DECO),
		P(model, "Lateral", Vector3.new(0.08, h - 0.25, trayLen), frontCF * CFrame.new(-(w / 2 - 0.19), -0.05, trayZ), Enum.Material.Wood, inner, DECO),
		P(model, "Lateral", Vector3.new(0.08, h - 0.25, trayLen), frontCF * CFrame.new(w / 2 - 0.19, -0.05, trayZ), Enum.Material.Wood, inner, DECO),
		P(model, "Traseira", Vector3.new(w - 0.3, h - 0.25, 0.08), frontCF * CFrame.new(0, -0.05, depth - 0.04), Enum.Material.Wood, inner, DECO),
	}
	if w >= 1.9 then
		table.insert(pieces, P(model, "Puxador", Vector3.new(math.min(w * 0.34, 1.5), 0.13, 0.13), frontCF * CFrame.new(0, 0.02, -0.2), Enum.Material.Metal, BRASS, DECO))
		for _, sx in { -1, 1 } do
			table.insert(pieces, P(model, "PuxadorApoio", Vector3.new(0.1, 0.1, 0.16), frontCF * CFrame.new(sx * math.min(w * 0.34, 1.5) / 2.3, 0.02, -0.12), Enum.Material.Metal, BRASS, DECO))
		end
	else
		table.insert(pieces, P(model, "Puxador", Vector3.new(0.3, 0.3, 0.3), frontCF * CFrame.new(0, 0, -0.2), Enum.Material.Metal, BRASS, { Collide = false, Shape = Enum.PartType.Ball }))
	end
	for _, piece in pieces do
		Kit.Weld(front, piece)
	end

	front:SetAttribute("Gaveta", true)
	front:SetAttribute("GavetaAberta", false)
	front:SetAttribute("CFrameFechada", frontCF)
	front:SetAttribute("GavetaCurso", travel)
	front:SetAttribute("GavetaInterior", Vector3.new(w - 0.5, h - 0.3, travel - 0.1))
	front:SetAttribute("GavetaSlot", CFrame.new(0, -h / 2 + 0.14, travel / 2 + 0.1))
	front:SetAttribute("GavetaMovel", label)
	return model
end

--------------------------------------------------------------------------------
-- Peças comuns
--------------------------------------------------------------------------------

-- Corpo maciço de h0 até h1, com tampo opcional. Devolve o CFrame da face frontal.
local function body(model: Model, cf: CFrame, w: number, d: number, h0: number, h1: number, color: Color3, topColor: Color3?, topMat: Enum.Material?): CFrame
	P(model, "Corpo", Vector3.new(w, h1 - h0, d), cf * CFrame.new(0, (h0 + h1) / 2, 0), Enum.Material.WoodPlanks, color)
	if topColor then
		-- Sobra do tampo só pra frente (-Z): atrás ele encosta na parede.
		P(model, "Tampo", Vector3.new(w + 0.2, 0.16, d + 0.15), cf * CFrame.new(0, h1 + 0.08, -0.075), topMat or Enum.Material.Wood, topColor)
	end
	return cf * CFrame.new(0, 0, -d / 2)
end

local function feet(model: Model, cf: CFrame, w: number, d: number, h: number, color: Color3)
	for _, sx in { -1, 1 } do
		for _, sz in { -1, 1 } do
			P(model, "Pe", Vector3.new(0.3, h, 0.3), cf * CFrame.new(sx * (w / 2 - 0.25), h / 2, sz * (d / 2 - 0.25)), Enum.Material.Wood, color, DECO)
		end
	end
end

local function cabinetDoor(model: Model, face: CFrame, x: number, y: number, w: number, h: number, color: Color3, knobSide: number)
	P(model, "PortaArmario", Vector3.new(w, h, 0.14), face * CFrame.new(x, y, -0.07), Enum.Material.WoodPlanks, color, DECO)
	P(model, "Almofada", Vector3.new(w - 0.45, h - 0.45, 0.05), face * CFrame.new(x, y, -0.16), Enum.Material.Wood, color:Lerp(Color3.new(0, 0, 0), 0.12), DECO)
	P(model, "Puxador", Vector3.new(0.22, 0.22, 0.22), face * CFrame.new(x + knobSide * (w / 2 - 0.3), y + h / 2 - 0.45, -0.22), Enum.Material.Metal, BRASS, { Collide = false, Shape = Enum.PartType.Ball })
end

--------------------------------------------------------------------------------
-- Móveis com gaveta
--------------------------------------------------------------------------------

function Furniture.Nightstand(parent: Instance, cf: CFrame, color: Color3, lamp: boolean?, lit: boolean?): Model
	local model = Kit.Model(parent, "CriadoMudo")
	local w, d = 2.3, 1.9
	feet(model, cf, w, d, 0.4, color)
	local face = body(model, cf, w, d, 0.4, 2.35, color, color:Lerp(Color3.new(0, 0, 0), 0.15))
	Furniture.Drawer(model, face, 0, 1.9, 1.95, 0.72, d - 0.35, color, "Criado-mudo")
	P(model, "Nicho", Vector3.new(1.95, 0.9, 0.02), face * CFrame.new(0, 0.95, -0.01), Enum.Material.SmoothPlastic, CAVITY, DECO)
	if lamp then
		Furniture.TableLamp(model, cf * CFrame.new(-0.35, 2.51, 0.15), lit == true)
	end
	return model
end

function Furniture.Dresser(parent: Instance, cf: CFrame, color: Color3): Model
	local model = Kit.Model(parent, "Comoda")
	local w, d = 5.6, 2.2
	P(model, "Rodape", Vector3.new(w - 0.2, 0.38, d - 0.25), cf * CFrame.new(0, 0.19, 0.05), Enum.Material.Wood, color:Lerp(Color3.new(0, 0, 0), 0.25))
	local face = body(model, cf, w, d, 0.36, 3.75, color, color:Lerp(Color3.new(0, 0, 0), 0.15))
	local depth = d - 0.35
	Furniture.Drawer(model, face, -1.35, 3.23, 2.55, 0.8, depth, color, "Cômoda")
	Furniture.Drawer(model, face, 1.35, 3.23, 2.55, 0.8, depth, color, "Cômoda")
	Furniture.Drawer(model, face, 0, 2.255, 5.2, 0.95, depth, color, "Cômoda")
	Furniture.Drawer(model, face, 0, 1.205, 5.2, 0.95, depth, color, "Cômoda")
	return model
end

function Furniture.ToolChest(parent: Instance, cf: CFrame, color: Color3): Model
	local model = Kit.Model(parent, "Gaveteiro")
	local w, d = 5.6, 2.3
	P(model, "Rodape", Vector3.new(w - 0.2, 0.3, d - 0.25), cf * CFrame.new(0, 0.15, 0.05), Enum.Material.Wood, color:Lerp(Color3.new(0, 0, 0), 0.3))
	local face = body(model, cf, w, d, 0.3, 3.45, color, color:Lerp(Color3.new(0, 0, 0), 0.2))
	for _, y in { 2.88, 1.88, 0.88 } do
		Furniture.Drawer(model, face, 0, y, 5.2, 0.9, d - 0.35, color, "Gaveteiro")
	end
	-- Ferragem de canto (baú de oficina, não cômoda de quarto).
	for _, sx in { -1, 1 } do
		P(model, "Cantoneira", Vector3.new(0.25, 3.2, 0.25), cf * CFrame.new(sx * (w / 2 - 0.05), 1.85, -d / 2 + 0.05), Enum.Material.Metal, IRON, DECO)
	end
	return model
end

function Furniture.Desk(parent: Instance, cf: CFrame, color: Color3, lit: boolean?): Model
	local model = Kit.Model(parent, "Escrivaninha")
	local w, d = 5.2, 2.4
	P(model, "Tampo", Vector3.new(w, 0.2, d), cf * CFrame.new(0, 2.8, 0), Enum.Material.Wood, color:Lerp(Color3.new(0, 0, 0), 0.1))
	P(model, "Lateral", Vector3.new(0.3, 2.7, d - 0.1), cf * CFrame.new(-w / 2 + 0.2, 1.35, 0), Enum.Material.WoodPlanks, color)
	-- Pedestal de gavetas à direita.
	local pedW = 1.95
	local pedCF = cf * CFrame.new(w / 2 - pedW / 2 - 0.05, 0, 0)
	local face = body(model, pedCF, pedW, d - 0.1, 0.1, 2.7, color)
	Furniture.Drawer(model, face, 0, 2.15, 1.65, 0.8, d - 0.45, color, "Escrivaninha")
	Furniture.Drawer(model, face, 0, 1.15, 1.65, 0.95, d - 0.45, color, "Escrivaninha")
	-- Gaveta rasa do meio, embaixo do tampo.
	local midCF = cf * CFrame.new(-0.6, 0, 0)
	local midFace = body(model, midCF, 2.4, d - 0.1, 2.0, 2.7, color)
	Furniture.Drawer(model, midFace, 0, 2.36, 2.2, 0.64, d - 0.45, color, "Escrivaninha")
	P(model, "Fundo", Vector3.new(w - pedW - 0.4, 1.6, 0.15), cf * CFrame.new(-0.95, 1.8, d / 2 - 0.1), Enum.Material.WoodPlanks, color, DECO)

	-- Tampo: luminária, papéis e uma máquina de escrever.
	Furniture.TableLamp(model, cf * CFrame.new(-w / 2 + 0.7, 2.9, 0.5), lit == true)
	P(model, "Papel", Vector3.new(0.9, 0.03, 1.2), cf * CFrame.new(0.9, 2.915, -0.2) * CFrame.Angles(0, 0.25, 0), Enum.Material.SmoothPlastic, Color3.fromRGB(226, 218, 196), DECO)
	P(model, "Papel", Vector3.new(0.9, 0.03, 1.2), cf * CFrame.new(1.1, 2.93, 0.1) * CFrame.Angles(0, -0.15, 0), Enum.Material.SmoothPlastic, Color3.fromRGB(214, 206, 182), DECO)
	P(model, "Maquina", Vector3.new(1.5, 0.45, 1.1), cf * CFrame.new(-0.6, 3.12, 0.1), Enum.Material.Metal, Color3.fromRGB(46, 50, 48), DECO)
	P(model, "MaquinaRolo", Vector3.new(1.5, 0.22, 0.22), cf * CFrame.new(-0.6, 3.42, 0.45), Enum.Material.Metal, IRON, { Collide = false, Shape = Enum.PartType.Cylinder })
	return model
end

function Furniture.Sideboard(parent: Instance, cf: CFrame, color: Color3): Model
	local model = Kit.Model(parent, "Aparador")
	local w, d = 6.2, 2.0
	feet(model, cf, w, d, 0.45, color)
	local face = body(model, cf, w, d, 0.45, 3.0, color, color:Lerp(Color3.new(0, 0, 0), 0.15))
	for i, x in { -2.0, 0, 2.0 } do
		Furniture.Drawer(model, face, x, 2.55, 1.85, 0.66, d - 0.35, color, "Aparador")
		cabinetDoor(model, face, x, 1.35, 1.85, 1.55, color, if i == 1 then 1 else -1)
	end
	return model
end

-- Módulo de balcão de cozinha: "D" = gaveta + porta, "S" = pia.
function Furniture.CounterModule(parent: Instance, cf: CFrame, kind: string, color: Color3, top: Color3): Model
	local model = Kit.Model(parent, if kind == "S" then "BalcaoPia" else "Balcao")
	local w, d = 3.0, 2.4
	P(model, "Rodape", Vector3.new(w, 0.35, d - 0.4), cf * CFrame.new(0, 0.175, 0.2), Enum.Material.SmoothPlastic, Color3.fromRGB(30, 26, 22))
	local face = body(model, cf, w, d, 0.35, 2.95, color)
	if kind == "S" then
		P(model, "Tampo", Vector3.new(w, 0.16, d + 0.1), cf * CFrame.new(0, 3.03, -0.05), Enum.Material.Marble, top)
		P(model, "Cuba", Vector3.new(2.0, 0.05, 1.4), cf * CFrame.new(0, 3.115, 0.05), Enum.Material.Metal, Color3.fromRGB(120, 124, 126), DECO)
		P(model, "CubaFundo", Vector3.new(1.8, 0.03, 1.2), cf * CFrame.new(0, 3.13, 0.05), Enum.Material.Metal, Color3.fromRGB(58, 60, 62), DECO)
		P(model, "Torneira", Vector3.new(0.9, 0.14, 0.14), cf * CFrame.new(0, 3.55, 0.85) * UPRIGHT, Enum.Material.Metal, Color3.fromRGB(180, 182, 184), { Collide = false, Shape = Enum.PartType.Cylinder })
		P(model, "TorneiraBico", Vector3.new(0.12, 0.12, 0.6), cf * CFrame.new(0, 3.95, 0.6), Enum.Material.Metal, Color3.fromRGB(180, 182, 184), DECO)
		cabinetDoor(model, face, -0.72, 1.6, 1.4, 2.2, color, 1)
		cabinetDoor(model, face, 0.72, 1.6, 1.4, 2.2, color, -1)
	else
		P(model, "Tampo", Vector3.new(w, 0.16, d + 0.1), cf * CFrame.new(0, 3.03, -0.05), Enum.Material.Marble, top)
		Furniture.Drawer(model, face, 0, 2.5, 2.7, 0.62, d - 0.4, color, "Balcão")
		cabinetDoor(model, face, 0, 1.2, 2.7, 1.7, color, 1)
	end
	return model
end

function Furniture.Wardrobe(parent: Instance, cf: CFrame, color: Color3): Model
	local model = Kit.Model(parent, "GuardaRoupa")
	local w, d = 4.2, 2.2
	P(model, "Rodape", Vector3.new(w, 0.3, d - 0.2), cf * CFrame.new(0, 0.15, 0.1), Enum.Material.Wood, color:Lerp(Color3.new(0, 0, 0), 0.3))
	local face = body(model, cf, w, d, 0.3, 7.3, color)
	P(model, "Cornija", Vector3.new(w + 0.3, 0.3, d + 0.2), cf * CFrame.new(0, 7.45, -0.1), Enum.Material.Wood, color:Lerp(Color3.new(0, 0, 0), 0.2))
	cabinetDoor(model, face, -1.0, 4.6, 1.95, 5.0, color, 1)
	cabinetDoor(model, face, 1.0, 4.6, 1.95, 5.0, color, -1)
	Furniture.Drawer(model, face, 0, 1.0, 3.9, 1.0, d - 0.35, color, "Guarda-roupa")
	return model
end

function Furniture.Vanity(parent: Instance, cf: CFrame, color: Color3): Model
	local model = Kit.Model(parent, "Gabinete")
	local w, d = 3.4, 1.9
	local face = body(model, cf, w, d, 0.3, 2.75, color)
	P(model, "Tampo", Vector3.new(w, 0.16, d + 0.1), cf * CFrame.new(0, 2.83, -0.05), Enum.Material.Marble, Color3.fromRGB(222, 218, 210))
	P(model, "Cuba", Vector3.new(1.6, 0.05, 1.1), cf * CFrame.new(0, 2.915, 0.05), Enum.Material.SmoothPlastic, Color3.fromRGB(236, 234, 228), DECO)
	P(model, "Torneira", Vector3.new(0.12, 0.12, 0.5), cf * CFrame.new(0, 3.2, 0.55), Enum.Material.Metal, Color3.fromRGB(180, 182, 184), DECO)
	Furniture.Drawer(model, face, 0, 2.33, 3.0, 0.66, d - 0.35, color, "Gabinete")
	cabinetDoor(model, face, -0.78, 1.1, 1.45, 1.4, color, 1)
	cabinetDoor(model, face, 0.78, 1.1, 1.45, 1.4, color, -1)
	return model
end

--------------------------------------------------------------------------------
-- Sala / quarto
--------------------------------------------------------------------------------

--[[
	Bed(parent, cf, blanket) -- cabeceira no +Z local (encostada na parede de
	trás). Usa "Bed horror game" de Workspace["Modelos para as casas"] quando
	existe; senão monta uma cama de casal com cabeceira.
]]
Furniture.ReferenceBedHeadAtPlusZ = true -- inverter se a cama de referência ficar ao contrário

function Furniture.Bed(parent: Instance, house: CFrame, pos: Vector3, yaw: number, blanket: Color3): Model
	local ref = Kit.CloneReference("Bed horror game")
	if ref then
		ref.Name = "Cama"
		local flip = if Furniture.ReferenceBedHeadAtPlusZ then 0 else math.pi
		Kit.PlaceReference(ref, parent, house, pos, yaw + flip, "Floor")
		return ref
	end

	local model = Kit.Model(parent, "Cama")
	local cf = house * CFrame.new(pos.X, pos.Y, pos.Z) * CFrame.Angles(0, yaw, 0)
	local frame = Furniture.Wood.Walnut
	local w, l = 5.2, 8.6
	P(model, "Estrado", Vector3.new(w, 1.0, l), cf * CFrame.new(0, 0.9, 0), Enum.Material.Wood, frame)
	P(model, "Colchao", Vector3.new(w - 0.3, 0.8, l - 0.4), cf * CFrame.new(0, 1.8, -0.1), Enum.Material.Fabric, COL.Mattress)
	P(model, "Cabeceira", Vector3.new(w + 0.3, 4.2, 0.35), cf * CFrame.new(0, 2.1, l / 2), Enum.Material.WoodPlanks, frame)
	P(model, "Peseira", Vector3.new(w + 0.3, 2.4, 0.3), cf * CFrame.new(0, 1.2, -l / 2), Enum.Material.WoodPlanks, frame)
	for _, sx in { -1, 1 } do
		P(model, "Travesseiro", Vector3.new(1.9, 0.45, 1.1), cf * CFrame.new(sx * 1.2, 2.42, l / 2 - 1.0), Enum.Material.Fabric, Color3.fromRGB(226, 222, 210), DECO)
	end
	P(model, "Cobertor", Vector3.new(w - 0.1, 0.18, l * 0.62), cf * CFrame.new(0, 2.26, -l * 0.17), Enum.Material.Fabric, blanket, DECO)
	P(model, "CobertorAba", Vector3.new(w - 0.1, 0.7, 0.18), cf * CFrame.new(0, 1.95, -l / 2 + 0.28), Enum.Material.Fabric, blanket, DECO)
	return model
end

function Furniture.Sofa(parent: Instance, cf: CFrame, color: Color3, length: number?): Model
	local model = Kit.Model(parent, "Sofa")
	local len = length or 7
	local dark = color:Lerp(Color3.new(0, 0, 0), 0.25)
	P(model, "Base", Vector3.new(len, 1.1, 3.0), cf * CFrame.new(0, 0.85, 0), Kit.Mat.Leather, dark)
	P(model, "Encosto", Vector3.new(len, 2.3, 0.8), cf * CFrame.new(0, 2.05, 1.1), Kit.Mat.Leather, color)
	for _, sx in { -1, 1 } do
		P(model, "Braco", Vector3.new(0.7, 1.5, 3.0), cf * CFrame.new(sx * (len / 2 - 0.35), 1.45, 0), Kit.Mat.Leather, color)
	end
	local seats = math.max(2, math.floor(len / 2.4))
	local seatW = (len - 1.5) / seats
	for i = 1, seats do
		local x = -len / 2 + 0.75 + (i - 0.5) * seatW
		P(model, "Assento", Vector3.new(seatW - 0.08, 0.5, 2.2), cf * CFrame.new(x, 1.62, -0.25), Kit.Mat.Leather, color, DECO)
	end
	for _, sx in { -1, 1 } do
		P(model, "Pe", Vector3.new(0.3, 0.3, 0.3), cf * CFrame.new(sx * (len / 2 - 0.4), 0.15, -1.2), Enum.Material.Wood, Furniture.Wood.Walnut, DECO)
	end
	return model
end

function Furniture.Armchair(parent: Instance, cf: CFrame, color: Color3): Model
	local model = Kit.Model(parent, "Poltrona")
	P(model, "Base", Vector3.new(3.0, 1.1, 2.9), cf * CFrame.new(0, 0.85, 0), Kit.Mat.Leather, color:Lerp(Color3.new(0, 0, 0), 0.25))
	P(model, "Encosto", Vector3.new(3.0, 2.6, 0.7), cf * CFrame.new(0, 2.2, 1.1), Kit.Mat.Leather, color)
	for _, sx in { -1, 1 } do
		P(model, "Braco", Vector3.new(0.55, 1.4, 2.9), cf * CFrame.new(sx * 1.25, 1.45, 0), Kit.Mat.Leather, color)
	end
	P(model, "Assento", Vector3.new(1.9, 0.45, 2.2), cf * CFrame.new(0, 1.6, -0.2), Kit.Mat.Leather, color, DECO)
	return model
end

function Furniture.CoffeeTable(parent: Instance, cf: CFrame, color: Color3): Model
	local model = Kit.Model(parent, "MesaCentro")
	P(model, "Tampo", Vector3.new(4.2, 0.22, 2.2), cf * CFrame.new(0, 1.5, 0), Enum.Material.Wood, color)
	P(model, "Prateleira", Vector3.new(3.8, 0.12, 1.8), cf * CFrame.new(0, 0.5, 0), Enum.Material.Wood, color, DECO)
	feet(model, cf, 4.2, 2.2, 1.4, color)
	P(model, "Revista", Vector3.new(0.9, 0.05, 1.2), cf * CFrame.new(-0.9, 1.635, 0.1) * CFrame.Angles(0, 0.4, 0), Enum.Material.SmoothPlastic, Color3.fromRGB(150, 60, 50), DECO)
	P(model, "Caneca", Vector3.new(0.45, 0.35, 0.35), cf * CFrame.new(1.1, 1.78, -0.3) * UPRIGHT, Enum.Material.SmoothPlastic, Color3.fromRGB(210, 206, 196), { Collide = false, Shape = Enum.PartType.Cylinder })
	return model
end

function Furniture.Chair(parent: Instance, cf: CFrame, color: Color3): Model
	local model = Kit.Model(parent, "Cadeira")
	P(model, "Assento", Vector3.new(1.7, 0.2, 1.7), cf * CFrame.new(0, 1.8, 0), Enum.Material.Wood, color)
	P(model, "Encosto", Vector3.new(1.7, 2.0, 0.18), cf * CFrame.new(0, 2.9, 0.78), Enum.Material.WoodPlanks, color)
	feet(model, cf, 1.6, 1.6, 1.7, color)
	return model
end

function Furniture.DiningTable(parent: Instance, cf: CFrame, color: Color3, len: number, chairs: boolean, rng: Random): Model
	local model = Kit.Model(parent, "MesaJantar")
	P(model, "Tampo", Vector3.new(len, 0.25, 3.6), cf * CFrame.new(0, 2.9, 0), Enum.Material.Wood, color)
	feet(model, cf, len - 0.2, 3.3, 2.78, color)
	P(model, "Toalha", Vector3.new(len * 0.45, 0.04, 3.7), cf * CFrame.new(0, 3.045, 0), Enum.Material.Fabric, Color3.fromRGB(190, 176, 150), DECO)
	for i = 1, 3 do
		local x = -len / 2 + i * len / 4
		P(model, "Prato", Vector3.new(0.05, 1.0, 1.0), cf * CFrame.new(x, 3.09, 0.9) * UPRIGHT, Enum.Material.SmoothPlastic, Color3.fromRGB(226, 224, 216), { Collide = false, Shape = Enum.PartType.Cylinder })
	end
	P(model, "Vela", Vector3.new(0.9, 0.25, 0.25), cf * CFrame.new(0.3, 3.5, -0.2) * UPRIGHT, Enum.Material.SmoothPlastic, Color3.fromRGB(230, 222, 200), { Collide = false, Shape = Enum.PartType.Cylinder })
	if chairs then
		local per = math.max(1, math.floor(len / 2.6))
		for side = -1, 1, 2 do
			for i = 1, per do
				local x = -len / 2 + (i - 0.5) * len / per
				local jitter = rng:NextNumber(-0.15, 0.15)
				-- Frente da cadeira (-Z local) virada pra mesa.
				local chairCF = cf * CFrame.new(x + jitter, 0, side * 2.45) * CFrame.Angles(0, if side < 0 then math.pi else 0, 0) * CFrame.Angles(0, rng:NextNumber(-0.12, 0.12), 0)
				Furniture.Chair(model, chairCF, color)
			end
		end
	end
	return model
end

function Furniture.Bookshelf(parent: Instance, cf: CFrame, color: Color3, rng: Random): Model
	local model = Kit.Model(parent, "Estante")
	local w, h, d = 3.8, 7.2, 1.5
	P(model, "Fundo", Vector3.new(w, h, 0.15), cf * CFrame.new(0, h / 2, d / 2 - 0.08), Enum.Material.WoodPlanks, color:Lerp(Color3.new(0, 0, 0), 0.2))
	for _, sx in { -1, 1 } do
		P(model, "Lateral", Vector3.new(0.2, h, d), cf * CFrame.new(sx * (w / 2 - 0.1), h / 2, 0), Enum.Material.WoodPlanks, color)
	end
	local shelves = 5
	for i = 0, shelves do
		local y = 0.2 + i * (h - 0.4) / shelves
		P(model, "Prateleira", Vector3.new(w - 0.4, 0.16, d - 0.1), cf * CFrame.new(0, y, 0.05), Enum.Material.Wood, color, if i == 0 then nil else DECO)
		if i < shelves then
			local x = -w / 2 + 0.35
			while x < w / 2 - 0.6 do
				if rng:NextNumber() < 0.14 then
					x += rng:NextNumber(0.4, 0.8)
				else
					local bw = rng:NextNumber(0.2, 0.36)
					local bh = rng:NextNumber(0.85, 1.15)
					local tone = rng:NextInteger(1, 5)
					local colors = { Color3.fromRGB(110, 40, 36), Color3.fromRGB(46, 62, 90), Color3.fromRGB(58, 80, 52), Color3.fromRGB(140, 120, 84), Color3.fromRGB(70, 52, 44) }
					P(model, "Livro", Vector3.new(bw, bh, 1.0), cf * CFrame.new(x + bw / 2, y + 0.08 + bh / 2, 0.05), Enum.Material.SmoothPlastic, colors[tone], { Collide = false, Shadow = false })
					x += bw + 0.02
				end
			end
		end
	end
	return model
end

function Furniture.Rug(parent: Instance, cf: CFrame, w: number, d: number, color: Color3): Model
	local model = Kit.Model(parent, "Tapete")
	P(model, "Tapete", Vector3.new(w, 0.06, d), cf * CFrame.new(0, 0.11, 0), Kit.Mat.Carpet, color, DECO)
	P(model, "Borda", Vector3.new(w - 0.8, 0.065, d - 0.8), cf * CFrame.new(0, 0.115, 0), Kit.Mat.Carpet, color:Lerp(Color3.new(0.9, 0.85, 0.7), 0.25), DECO)
	P(model, "Miolo", Vector3.new(w - 1.4, 0.07, d - 1.4), cf * CFrame.new(0, 0.12, 0), Kit.Mat.Carpet, color, DECO)
	return model
end

--[[
	Fireplace(parent, cf, flueTop) -- lareira de pedra encostada na parede
	(o fundo do móvel em +Z local). Brasas acesas e fracas: a sala fica
	iluminada de laranja sem virar zona segura contra o Monstro.
]]
function Furniture.Fireplace(parent: Instance, cf: CFrame): Model
	local model = Kit.Model(parent, "Lareira")
	local stone = Color3.fromRGB(118, 112, 104)
	P(model, "Corpo", Vector3.new(7.2, 7.6, 2.4), cf * CFrame.new(0, 3.8, 0.2), Enum.Material.Cobblestone, stone)
	P(model, "Boca", Vector3.new(3.6, 3.0, 0.3), cf * CFrame.new(0, 1.8, -1.02), Enum.Material.Slate, Color3.fromRGB(26, 24, 22), DECO)
	P(model, "Soleira", Vector3.new(8.2, 0.35, 2.0), cf * CFrame.new(0, 0.18, -1.6), Enum.Material.Slate, Color3.fromRGB(78, 74, 70))
	P(model, "ConsoloMadeira", Vector3.new(8.0, 0.4, 1.2), cf * CFrame.new(0, 4.3, -1.2), Enum.Material.Wood, Furniture.Wood.Walnut)
	for i = 1, 3 do
		P(model, "Lenha", Vector3.new(2.4, 0.4, 0.4), cf * CFrame.new(-0.3 + i * 0.2, 0.55 + (i - 1) * 0.12, -0.6) * CFrame.Angles(0, 0.3 * (i - 2), 0), Enum.Material.Wood, Color3.fromRGB(46, 34, 26), { Collide = false, Shape = Enum.PartType.Cylinder })
	end
	local ember = P(model, "Brasa", Vector3.new(2.2, 0.2, 0.9), cf * CFrame.new(0, 0.42, -0.6), Enum.Material.Neon, Color3.fromRGB(255, 96, 36), DECO)
	Kit.Light(ember, Color3.fromRGB(255, 120, 50), 16, 0.7, true)
	-- Decoração no consolo.
	P(model, "Relogio", Vector3.new(0.9, 1.1, 0.35), cf * CFrame.new(-2.4, 5.05, -1.25), Enum.Material.Wood, Furniture.Wood.Walnut, DECO)
	P(model, "Vela", Vector3.new(0.7, 0.22, 0.22), cf * CFrame.new(2.3, 4.85, -1.25) * UPRIGHT, Enum.Material.SmoothPlastic, Color3.fromRGB(230, 222, 200), { Collide = false, Shape = Enum.PartType.Cylinder })
	P(model, "Quadro", Vector3.new(3.4, 2.4, 0.15), cf * CFrame.new(0, 6.0, -1.05), Enum.Material.Wood, Color3.fromRGB(60, 44, 30), DECO)
	P(model, "Tela", Vector3.new(3.0, 2.0, 0.05), cf * CFrame.new(0, 6.0, -1.14), Enum.Material.SmoothPlastic, Color3.fromRGB(70, 84, 74), DECO)
	return model
end

-- Fogão a lenha de ferro com chaminé (cano) subindo até `pipeTop` (local ao cf).
function Furniture.CookStove(parent: Instance, cf: CFrame, pipeTop: number): Model
	local model = Kit.Model(parent, "FogaoLenha")
	P(model, "Corpo", Vector3.new(4.0, 2.6, 2.4), cf * CFrame.new(0, 1.7, 0), Enum.Material.Metal, IRON)
	P(model, "Chapa", Vector3.new(4.2, 0.2, 2.6), cf * CFrame.new(0, 3.1, 0), Enum.Material.Metal, Color3.fromRGB(24, 22, 20))
	P(model, "PortaForno", Vector3.new(1.8, 1.3, 0.1), cf * CFrame.new(-0.8, 1.6, -1.25), Enum.Material.Metal, Color3.fromRGB(52, 50, 48), DECO)
	P(model, "PortaFornalha", Vector3.new(1.0, 0.9, 0.1), cf * CFrame.new(1.2, 1.9, -1.25), Enum.Material.Metal, Color3.fromRGB(52, 50, 48), DECO)
	P(model, "Visor", Vector3.new(0.6, 0.3, 0.05), cf * CFrame.new(1.2, 1.9, -1.31), Enum.Material.Neon, Color3.fromRGB(200, 70, 30), DECO)
	for _, sx in { -1, 1 } do
		for _, sz in { -1, 1 } do
			P(model, "Pe", Vector3.new(0.35, 0.4, 0.35), cf * CFrame.new(sx * 1.7, 0.2, sz * 0.9), Enum.Material.Metal, IRON, DECO)
		end
	end
	P(model, "Panela", Vector3.new(0.8, 1.1, 1.1), cf * CFrame.new(-1.0, 3.6, -0.2) * UPRIGHT, Enum.Material.Metal, Color3.fromRGB(70, 70, 72), { Collide = false, Shape = Enum.PartType.Cylinder })
	local pipeH = pipeTop - 3.2
	P(model, "Cano", Vector3.new(pipeH, 0.7, 0.7), cf * CFrame.new(1.1, 3.2 + pipeH / 2, 0.6) * UPRIGHT, Enum.Material.Metal, Color3.fromRGB(30, 30, 30), { Collide = false, Shape = Enum.PartType.Cylinder })
	P(model, "CanoChapeu", Vector3.new(0.3, 1.2, 1.2), cf * CFrame.new(1.1, pipeTop + 0.2, 0.6) * UPRIGHT, Enum.Material.Metal, Color3.fromRGB(30, 30, 30), { Collide = false, Shape = Enum.PartType.Cylinder })
	return model
end

function Furniture.Fridge(parent: Instance, cf: CFrame): Model
	local model = Kit.Model(parent, "Geladeira")
	local cream = Color3.fromRGB(214, 206, 180)
	P(model, "Corpo", Vector3.new(2.8, 6.4, 2.5), cf * CFrame.new(0, 3.3, 0), Enum.Material.SmoothPlastic, cream)
	P(model, "Topo", Vector3.new(2.8, 0.3, 2.5), cf * CFrame.new(0, 6.6, 0) , Enum.Material.SmoothPlastic, cream:Lerp(Color3.new(1, 1, 1), 0.1), DECO)
	P(model, "Frisos", Vector3.new(2.7, 0.08, 0.05), cf * CFrame.new(0, 4.6, -1.27), Enum.Material.Metal, Color3.fromRGB(150, 150, 150), DECO)
	P(model, "Puxador", Vector3.new(0.18, 1.6, 0.25), cf * CFrame.new(1.1, 5.2, -1.35), Enum.Material.Metal, Color3.fromRGB(190, 190, 190), DECO)
	P(model, "Puxador", Vector3.new(0.18, 1.4, 0.25), cf * CFrame.new(1.1, 3.2, -1.35), Enum.Material.Metal, Color3.fromRGB(190, 190, 190), DECO)
	P(model, "Ferrugem", Vector3.new(1.0, 0.8, 0.02), cf * CFrame.new(-0.7, 1.0, -1.26), Enum.Material.CorrodedMetal, Color3.fromRGB(120, 76, 44), DECO)
	return model
end

function Furniture.WallCabinet(parent: Instance, cf: CFrame, w: number, color: Color3): Model
	-- cf = centro no piso, embaixo do armário. Fica de 6,2 a 8,6 de altura.
	local model = Kit.Model(parent, "ArmarioAlto")
	local face = cf * CFrame.new(0, 0, -0.7)
	P(model, "Corpo", Vector3.new(w, 2.4, 1.4), cf * CFrame.new(0, 7.4, 0), Enum.Material.WoodPlanks, color)
	local doors = math.max(1, math.floor(w / 1.5))
	local dw = w / doors
	for i = 1, doors do
		cabinetDoor(model, face, -w / 2 + (i - 0.5) * dw, 7.4, dw - 0.1, 2.2, color, if i % 2 == 0 then -1 else 1)
	end
	return model
end

--------------------------------------------------------------------------------
-- Banheiro
--------------------------------------------------------------------------------

function Furniture.Bathtub(parent: Instance, cf: CFrame): Model
	local model = Kit.Model(parent, "Banheira")
	local white = Color3.fromRGB(226, 224, 216)
	local w, l = 2.8, 6.0
	P(model, "Fundo", Vector3.new(w, 0.3, l), cf * CFrame.new(0, 0.6, 0), Enum.Material.SmoothPlastic, white)
	for _, sx in { -1, 1 } do
		P(model, "Borda", Vector3.new(0.35, 2.0, l), cf * CFrame.new(sx * (w / 2 - 0.175), 1.45, 0), Enum.Material.SmoothPlastic, white)
	end
	for _, sz in { -1, 1 } do
		P(model, "Borda", Vector3.new(w, 2.0, 0.35), cf * CFrame.new(0, 1.45, sz * (l / 2 - 0.175)), Enum.Material.SmoothPlastic, white)
	end
	P(model, "Mancha", Vector3.new(w - 0.8, 0.02, l - 1.4), cf * CFrame.new(0, 0.77, 0.3), Enum.Material.SmoothPlastic, Color3.fromRGB(118, 96, 70), DECO)
	for _, sx in { -1, 1 } do
		for _, sz in { -1, 1 } do
			P(model, "PeGarra", Vector3.new(0.4, 0.45, 0.4), cf * CFrame.new(sx * (w / 2 - 0.35), 0.22, sz * 2.4), Enum.Material.Metal, BRASS, DECO)
		end
	end
	P(model, "Torneira", Vector3.new(0.14, 0.14, 0.6), cf * CFrame.new(0, 2.7, l / 2 - 0.3), Enum.Material.Metal, Color3.fromRGB(180, 182, 184), DECO)
	P(model, "Cortina", Vector3.new(0.08, 5.0, l - 0.5), cf * CFrame.new(-w / 2 + 0.05, 5.4, 0.2), Enum.Material.Fabric, Color3.fromRGB(196, 204, 196), { Collide = false, Transparency = 0.1 })
	return model
end

function Furniture.Toilet(parent: Instance, cf: CFrame): Model
	local model = Kit.Model(parent, "Privada")
	local white = Color3.fromRGB(228, 226, 218)
	P(model, "Base", Vector3.new(1.2, 1.5, 1.6), cf * CFrame.new(0, 0.75, -0.1), Enum.Material.SmoothPlastic, white)
	P(model, "Assento", Vector3.new(1.6, 0.2, 2.0), cf * CFrame.new(0, 1.6, -0.25), Enum.Material.SmoothPlastic, white)
	P(model, "Caixa", Vector3.new(2.0, 1.7, 0.8), cf * CFrame.new(0, 2.4, 0.95), Enum.Material.SmoothPlastic, white)
	P(model, "Tampa", Vector3.new(2.1, 0.15, 0.9), cf * CFrame.new(0, 3.3, 0.95), Enum.Material.SmoothPlastic, white, DECO)
	return model
end

function Furniture.Mirror(parent: Instance, cf: CFrame, w: number, h: number): Model
	-- cf = centro do espelho encostado na parede, LookVector pra fora da parede.
	local model = Kit.Model(parent, "Espelho")
	P(model, "Moldura", Vector3.new(w + 0.3, h + 0.3, 0.12), cf, Enum.Material.Wood, Furniture.Wood.Walnut, DECO)
	P(model, "Espelho", Vector3.new(w, h, 0.05), cf * CFrame.new(0, 0, -0.07), Enum.Material.Glass, Color3.fromRGB(150, 160, 160), { Collide = false, Reflectance = 0.35, Shadow = false })
	P(model, "Mancha", Vector3.new(w * 0.35, h * 0.3, 0.01), cf * CFrame.new(w * 0.2, -h * 0.25, -0.1), Enum.Material.SmoothPlastic, Color3.fromRGB(90, 40, 34), { Collide = false, Transparency = 0.35 })
	return model
end

--------------------------------------------------------------------------------
-- Detalhes
--------------------------------------------------------------------------------

function Furniture.TableLamp(parent: Instance, cf: CFrame, lit: boolean): Model
	-- cf = base apoiada no tampo.
	local model = Kit.Model(parent, "Abajur")
	P(model, "Base", Vector3.new(0.2, 0.7, 0.7), cf * CFrame.new(0, 0.1, 0) * UPRIGHT, Enum.Material.Metal, BRASS, { Collide = false, Shape = Enum.PartType.Cylinder })
	P(model, "Haste", Vector3.new(1.2, 0.12, 0.12), cf * CFrame.new(0, 0.8, 0) * UPRIGHT, Enum.Material.Metal, BRASS, { Collide = false, Shape = Enum.PartType.Cylinder })
	local shade = P(model, "Cupula", Vector3.new(0.9, 1.1, 1.1), cf * CFrame.new(0, 1.55, 0) * UPRIGHT, Enum.Material.Fabric, Color3.fromRGB(220, 196, 150), { Collide = false, Shape = Enum.PartType.Cylinder, Transparency = if lit then 0.15 else 0 })
	Kit.Light(shade, Color3.fromRGB(255, 190, 120), 10, 0.55, lit)
	return model
end

function Furniture.FloorLamp(parent: Instance, cf: CFrame, lit: boolean): Model
	local model = Kit.Model(parent, "Luminaria")
	P(model, "Base", Vector3.new(0.2, 1.1, 1.1), cf * CFrame.new(0, 0.1, 0) * UPRIGHT, Enum.Material.Metal, IRON, { Collide = false, Shape = Enum.PartType.Cylinder })
	P(model, "Haste", Vector3.new(4.8, 0.15, 0.15), cf * CFrame.new(0, 2.5, 0) * UPRIGHT, Enum.Material.Metal, IRON, { Collide = false, Shape = Enum.PartType.Cylinder })
	local shade = P(model, "Cupula", Vector3.new(1.1, 1.5, 1.5), cf * CFrame.new(0, 5.2, 0) * UPRIGHT, Enum.Material.Fabric, Color3.fromRGB(200, 170, 120), { Collide = false, Shape = Enum.PartType.Cylinder, Transparency = if lit then 0.15 else 0 })
	Kit.Light(shade, Color3.fromRGB(255, 186, 120), 14, 0.5, lit)
	return model
end

function Furniture.CoatRack(parent: Instance, cf: CFrame, coat: Color3): Model
	local model = Kit.Model(parent, "Cabideiro")
	P(model, "Haste", Vector3.new(6.2, 0.25, 0.25), cf * CFrame.new(0, 3.1, 0) * UPRIGHT, Enum.Material.Wood, Furniture.Wood.Walnut, { Collide = false, Shape = Enum.PartType.Cylinder })
	P(model, "Base", Vector3.new(0.25, 1.4, 1.4), cf * CFrame.new(0, 0.12, 0) * UPRIGHT, Enum.Material.Wood, Furniture.Wood.Walnut, { Collide = false, Shape = Enum.PartType.Cylinder })
	P(model, "Casaco", Vector3.new(1.3, 2.8, 0.5), cf * CFrame.new(0.2, 4.5, -0.35) * CFrame.Angles(0.08, 0.2, 0), Enum.Material.Fabric, coat, DECO)
	P(model, "Chapeu", Vector3.new(0.35, 1.0, 1.0), cf * CFrame.new(0, 6.25, 0) * UPRIGHT, Enum.Material.Fabric, Color3.fromRGB(60, 50, 40), { Collide = false, Shape = Enum.PartType.Cylinder })
	return model
end

-- Quadro na parede: cf encostado na parede, LookVector pra fora.
function Furniture.Picture(parent: Instance, cf: CFrame, w: number, h: number, canvas: Color3)
	P(parent, "Quadro", Vector3.new(w + 0.3, h + 0.3, 0.1), cf, Enum.Material.Wood, Color3.fromRGB(64, 46, 30), DECO)
	P(parent, "QuadroTela", Vector3.new(w, h, 0.04), cf * CFrame.new(0, 0, -0.06), Enum.Material.SmoothPlastic, canvas, DECO)
end

function Furniture.WallClock(parent: Instance, cf: CFrame)
	P(parent, "Relogio", Vector3.new(0.15, 1.4, 1.4), cf * CFrame.Angles(0, math.pi / 2, 0), Enum.Material.Wood, Furniture.Wood.Walnut, { Collide = false, Shape = Enum.PartType.Cylinder })
	P(parent, "Mostrador", Vector3.new(0.05, 1.15, 1.15), cf * CFrame.new(0, 0, -0.08) * CFrame.Angles(0, math.pi / 2, 0), Enum.Material.SmoothPlastic, Color3.fromRGB(226, 220, 200), { Collide = false, Shape = Enum.PartType.Cylinder })
	P(parent, "Ponteiro", Vector3.new(0.06, 0.45, 0.03), cf * CFrame.new(0.1, 0.15, -0.12) * CFrame.Angles(0, 0, -0.5), Enum.Material.Metal, IRON, DECO)
end

--------------------------------------------------------------------------------
-- Área externa
--------------------------------------------------------------------------------

function Furniture.Woodpile(parent: Instance, cf: CFrame, rng: Random): Model
	local model = Kit.Model(parent, "PilhaLenha")
	local wood = Color3.fromRGB(112, 80, 52)
	P(model, "Estrado", Vector3.new(6.4, 0.35, 2.4), cf * CFrame.new(0, 0.18, 0), Enum.Material.WoodPlanks, Color3.fromRGB(90, 70, 50))
	for row = 0, 3 do
		local count = 7 - row
		for i = 1, count do
			local x = -((count - 1) * 0.85) / 2 + (i - 1) * 0.85
			local s = rng:NextNumber(0.72, 0.86)
			P(model, "Lenha", Vector3.new(2.2, s, s), cf * CFrame.new(x, 0.75 + row * 0.72, 0) * CFrame.Angles(0, math.pi / 2, 0), Enum.Material.Wood, wood:Lerp(Color3.new(0, 0, 0), rng:NextNumber(0, 0.25)), { Shape = Enum.PartType.Cylinder, Collide = row == 0 })
		end
	end
	-- Uma barreira simples cobre a pilha inteira (tropeçar em toras é chato).
	P(model, "PilhaColisao", Vector3.new(6.0, 3.0, 2.2), cf * CFrame.new(0, 1.7, 0), Enum.Material.SmoothPlastic, wood, { Transparency = 1, Shadow = false })
	-- Toco com machado cravado.
	local block = cf * CFrame.new(4.6, 0, 0.4)
	P(model, "Toco", Vector3.new(1.6, 2.0, 2.0), block * CFrame.new(0, 0.8, 0) * UPRIGHT, Enum.Material.Wood, Color3.fromRGB(120, 88, 58), { Shape = Enum.PartType.Cylinder })
	P(model, "MachadoCabo", Vector3.new(0.18, 2.4, 0.18), block * CFrame.new(0.2, 2.4, 0) * CFrame.Angles(0, 0, -0.5), Enum.Material.Wood, Color3.fromRGB(150, 110, 70), DECO)
	P(model, "MachadoLamina", Vector3.new(0.6, 0.5, 0.08), block * CFrame.new(-0.25, 1.75, 0) * CFrame.Angles(0, 0, -0.5), Enum.Material.Metal, Color3.fromRGB(140, 140, 144), DECO)
	return model
end

function Furniture.Barrel(parent: Instance, cf: CFrame, color: Color3): Model
	local model = Kit.Model(parent, "Barril")
	P(model, "Corpo", Vector3.new(3.0, 2.2, 2.2), cf * CFrame.new(0, 1.5, 0) * UPRIGHT, Enum.Material.Wood, color, { Shape = Enum.PartType.Cylinder })
	for _, y in { 0.5, 2.5 } do
		P(model, "Aro", Vector3.new(0.2, 2.3, 2.3), cf * CFrame.new(0, y, 0) * UPRIGHT, Enum.Material.Metal, IRON, { Collide = false, Shape = Enum.PartType.Cylinder })
	end
	return model
end

--------------------------------------------------------------------------------
-- Fazenda (CasaDaFazenda / Celeiro)
--------------------------------------------------------------------------------

-- Piano de armário velho, encostado na parede (+Z local).
function Furniture.Piano(parent: Instance, cf: CFrame): Model
	local model = Kit.Model(parent, "Piano")
	local wood = Color3.fromRGB(52, 34, 24)
	P(model, "Corpo", Vector3.new(5.2, 4.6, 2.0), cf * CFrame.new(0, 2.3, 0.3), Enum.Material.Wood, wood)
	P(model, "Teclado", Vector3.new(4.6, 0.35, 1.0), cf * CFrame.new(0, 2.55, -1.1), Enum.Material.Wood, wood)
	P(model, "Teclas", Vector3.new(4.3, 0.06, 0.8), cf * CFrame.new(0, 2.76, -1.15), Enum.Material.SmoothPlastic, Color3.fromRGB(226, 218, 196), DECO)
	for i = 0, 17 do
		if i % 7 ~= 2 and i % 7 ~= 6 then
			P(model, "TeclaPreta", Vector3.new(0.12, 0.08, 0.45), cf * CFrame.new(-2.05 + i * 0.24, 2.82, -0.98), Enum.Material.SmoothPlastic, Color3.fromRGB(20, 18, 16), DECO)
		end
	end
	P(model, "Estante", Vector3.new(2.2, 0.8, 0.1), cf * CFrame.new(0, 3.5, -0.65) * CFrame.Angles(-0.2, 0, 0), Enum.Material.Wood, wood, DECO)
	P(model, "Partitura", Vector3.new(1.6, 1.1, 0.03), cf * CFrame.new(0, 3.75, -0.75) * CFrame.Angles(-0.2, 0, 0), Enum.Material.SmoothPlastic, Color3.fromRGB(210, 198, 170), DECO)
	P(model, "Banco", Vector3.new(3.0, 1.9, 1.3), cf * CFrame.new(0, 0.95, -2.6), Enum.Material.Wood, wood)
	P(model, "Castical", Vector3.new(0.9, 0.2, 0.2), cf * CFrame.new(2.1, 5.05, 0.3) * UPRIGHT, Enum.Material.Metal, BRASS, { Collide = false, Shape = Enum.PartType.Cylinder })
	return model
end

-- Relógio de pêndulo (carrilhão), alto e estreito.
function Furniture.GrandfatherClock(parent: Instance, cf: CFrame): Model
	local model = Kit.Model(parent, "RelogioPendulo")
	local wood = Furniture.Wood.Walnut
	P(model, "Base", Vector3.new(2.0, 1.4, 1.4), cf * CFrame.new(0, 0.7, 0), Enum.Material.Wood, wood)
	P(model, "Caixa", Vector3.new(1.6, 4.6, 1.2), cf * CFrame.new(0, 3.7, 0), Enum.Material.Wood, wood)
	P(model, "Cabeca", Vector3.new(2.1, 2.0, 1.4), cf * CFrame.new(0, 7.0, 0), Enum.Material.Wood, wood)
	P(model, "Mostrador", Vector3.new(0.05, 1.4, 1.4), cf * CFrame.new(0, 7.0, -0.72) * CFrame.Angles(0, math.pi / 2, 0), Enum.Material.SmoothPlastic, Color3.fromRGB(226, 216, 186), { Collide = false, Shape = Enum.PartType.Cylinder })
	P(model, "Vidro", Vector3.new(1.0, 3.4, 0.05), cf * CFrame.new(0, 3.9, -0.62), Enum.Material.Glass, Color3.fromRGB(160, 170, 160), { Collide = false, Transparency = 0.5 })
	P(model, "Pendulo", Vector3.new(0.08, 2.6, 0.08), cf * CFrame.new(0, 4.3, -0.5), Enum.Material.Metal, BRASS, DECO)
	P(model, "PenduloDisco", Vector3.new(0.08, 0.6, 0.6), cf * CFrame.new(0, 3.0, -0.5) * CFrame.Angles(0, math.pi / 2, 0), Enum.Material.Metal, BRASS, { Collide = false, Shape = Enum.PartType.Cylinder })
	return model
end

-- Cristaleira: vitrine em cima (louça atrás do vidro), 2 gavetas + portas embaixo.
function Furniture.Hutch(parent: Instance, cf: CFrame, color: Color3): Model
	local model = Kit.Model(parent, "Cristaleira")
	local w, d = 5.4, 2.1
	local face = body(model, cf, w, d, 0.3, 3.2, color, color:Lerp(Color3.new(0, 0, 0), 0.15))
	Furniture.Drawer(model, face, -1.3, 2.75, 2.5, 0.66, d - 0.35, color, "Cristaleira")
	Furniture.Drawer(model, face, 1.3, 2.75, 2.5, 0.66, d - 0.35, color, "Cristaleira")
	cabinetDoor(model, face, -1.3, 1.35, 2.5, 1.9, color, 1)
	cabinetDoor(model, face, 1.3, 1.35, 2.5, 1.9, color, -1)
	P(model, "Vitrine", Vector3.new(w - 0.4, 4.2, 1.1), cf * CFrame.new(0, 5.46, 0.4), Enum.Material.WoodPlanks, color)
	P(model, "Cornija", Vector3.new(w, 0.3, 1.4), cf * CFrame.new(0, 7.7, 0.3), Enum.Material.Wood, color:Lerp(Color3.new(0, 0, 0), 0.2))
	for _, sx in { -1, 1 } do
		P(model, "VidroVitrine", Vector3.new(2.3, 3.8, 0.06), cf * CFrame.new(sx * 1.25, 5.46, -0.18), Enum.Material.Glass, Color3.fromRGB(180, 196, 196), { Collide = false, Transparency = 0.55, Shadow = false })
	end
	for i = 0, 3 do
		P(model, "Prato", Vector3.new(0.05, 0.9, 0.9), cf * CFrame.new(-1.8 + i * 1.2, 6.3, 0.5) * CFrame.Angles(0, math.pi / 2, 0) * CFrame.Angles(0, 0, 0.15), Enum.Material.SmoothPlastic, Color3.fromRGB(220, 222, 214), { Collide = false, Shape = Enum.PartType.Cylinder })
		P(model, "Xicara", Vector3.new(0.4, 0.35, 0.35), cf * CFrame.new(-1.8 + i * 1.2, 4.55, 0.3) * UPRIGHT, Enum.Material.SmoothPlastic, Color3.fromRGB(214, 206, 190), { Collide = false, Shape = Enum.PartType.Cylinder })
	end
	return model
end

-- Cadeira de balanço (base curva feita de duas lâminas).
function Furniture.RockingChair(parent: Instance, cf: CFrame, color: Color3): Model
	local model = Kit.Model(parent, "CadeiraBalanco")
	for _, sx in { -1, 1 } do
		P(model, "Balanco", Vector3.new(0.2, 0.3, 3.2), cf * CFrame.new(sx * 0.85, 0.2, 0.1) * CFrame.Angles(0.08, 0, 0), Enum.Material.Wood, color, DECO)
		P(model, "Perna", Vector3.new(0.2, 1.4, 0.2), cf * CFrame.new(sx * 0.85, 1.0, -0.6), Enum.Material.Wood, color, DECO)
		P(model, "Perna", Vector3.new(0.2, 1.4, 0.2), cf * CFrame.new(sx * 0.85, 1.0, 0.7), Enum.Material.Wood, color, DECO)
		P(model, "Braco", Vector3.new(0.2, 0.2, 1.8), cf * CFrame.new(sx * 0.9, 2.5, 0), Enum.Material.Wood, color, DECO)
	end
	P(model, "Assento", Vector3.new(1.9, 0.2, 1.7), cf * CFrame.new(0, 1.75, 0), Enum.Material.Wood, color)
	P(model, "Encosto", Vector3.new(1.9, 2.6, 0.15), cf * CFrame.new(0, 3.1, 0.95) * CFrame.Angles(-0.15, 0, 0), Enum.Material.WoodPlanks, color)
	P(model, "Manta", Vector3.new(1.4, 1.6, 0.1), cf * CFrame.new(0.1, 2.9, 0.82) * CFrame.Angles(-0.15, 0, 0.05), Enum.Material.Fabric, Color3.fromRGB(124, 60, 48), DECO)
	return model
end

-- Cama de solteiro (quarto das crianças). Cabeceira no +Z local.
function Furniture.TwinBed(parent: Instance, cf: CFrame, blanket: Color3): Model
	local model = Kit.Model(parent, "CamaSolteiro")
	local frame = Color3.fromRGB(150, 140, 126)
	P(model, "Estrado", Vector3.new(3.2, 0.9, 6.6), cf * CFrame.new(0, 0.9, 0), Enum.Material.Metal, frame)
	P(model, "Colchao", Vector3.new(3.0, 0.6, 6.3), cf * CFrame.new(0, 1.65, 0), Enum.Material.Fabric, COL.Mattress)
	P(model, "Cabeceira", Vector3.new(3.3, 3.6, 0.2), cf * CFrame.new(0, 1.8, 3.35), Enum.Material.Metal, frame)
	P(model, "Peseira", Vector3.new(3.3, 2.2, 0.2), cf * CFrame.new(0, 1.1, -3.35), Enum.Material.Metal, frame)
	P(model, "Travesseiro", Vector3.new(2.2, 0.4, 1.0), cf * CFrame.new(0, 2.15, 2.5), Enum.Material.Fabric, Color3.fromRGB(226, 222, 210), DECO)
	P(model, "Cobertor", Vector3.new(3.1, 0.15, 4.0), cf * CFrame.new(0, 2.0, -0.9), Enum.Material.Fabric, blanket, DECO)
	return model
end

-- Boneca de pano sentada (detalhe de terror no quarto das crianças).
function Furniture.Doll(parent: Instance, cf: CFrame)
	local model = Kit.Model(parent, "Boneca")
	local skin = Color3.fromRGB(214, 196, 170)
	P(model, "Corpo", Vector3.new(0.7, 0.8, 0.45), cf * CFrame.new(0, 0.5, 0), Enum.Material.Fabric, Color3.fromRGB(120, 40, 44), DECO)
	P(model, "Cabeca", Vector3.new(0.6, 0.6, 0.6), cf * CFrame.new(0, 1.2, 0) * CFrame.Angles(0, 0, 0.25), Enum.Material.Fabric, skin, { Collide = false, Shape = Enum.PartType.Ball })
	P(model, "Olho", Vector3.new(0.12, 0.12, 0.05), cf * CFrame.new(-0.12, 1.25, -0.29), Enum.Material.SmoothPlastic, Color3.new(0, 0, 0), DECO)
	P(model, "Botao", Vector3.new(0.14, 0.14, 0.05), cf * CFrame.new(0.13, 1.28, -0.29), Enum.Material.SmoothPlastic, Color3.fromRGB(150, 20, 20), DECO)
	for _, sx in { -1, 1 } do
		P(model, "Perna", Vector3.new(0.2, 0.2, 0.7), cf * CFrame.new(sx * 0.18, 0.12, -0.35), Enum.Material.Fabric, skin, DECO)
	end
end

-- Balanço de varanda pendurado por correntes. cf = no piso, embaixo do balanço.
function Furniture.PorchSwing(parent: Instance, cf: CFrame, ceilingY: number, color: Color3): Model
	local model = Kit.Model(parent, "BalancoVaranda")
	P(model, "Assento", Vector3.new(5.0, 0.3, 1.8), cf * CFrame.new(0, 1.9, 0), Enum.Material.WoodPlanks, color)
	P(model, "Encosto", Vector3.new(5.0, 1.8, 0.2), cf * CFrame.new(0, 2.9, 0.85) * CFrame.Angles(-0.2, 0, 0), Enum.Material.WoodPlanks, color)
	for _, sx in { -1, 1 } do
		P(model, "Braco", Vector3.new(0.2, 0.9, 1.8), cf * CFrame.new(sx * 2.45, 2.4, 0), Enum.Material.Wood, color, DECO)
		for _, sz in { -0.8, 0.8 } do
			local len = ceilingY - 2.0
			P(model, "Corrente", Vector3.new(0.08, len, 0.08), cf * CFrame.new(sx * 2.3, 2.0 + len / 2, sz), Enum.Material.Metal, IRON, DECO)
		end
	end
	return model
end

-- Bancada de oficina com 3 gavetas, morsa e ferramentas.
function Furniture.Workbench(parent: Instance, cf: CFrame, color: Color3): Model
	local model = Kit.Model(parent, "Bancada")
	local w, d = 7.0, 2.6
	P(model, "Tampo", Vector3.new(w, 0.35, d), cf * CFrame.new(0, 3.0, 0), Enum.Material.WoodPlanks, Color3.fromRGB(110, 84, 58))
	for _, sx in { -1, 1 } do
		P(model, "Pe", Vector3.new(0.5, 2.85, 0.5), cf * CFrame.new(sx * (w / 2 - 0.35), 1.4, -d / 2 + 0.35), Enum.Material.Wood, color, DECO)
		P(model, "Pe", Vector3.new(0.5, 2.85, 0.5), cf * CFrame.new(sx * (w / 2 - 0.35), 1.4, d / 2 - 0.35), Enum.Material.Wood, color, DECO)
	end
	local face = body(model, cf * CFrame.new(1.6, 0, 0), 3.4, d - 0.2, 1.3, 2.82, color)
	Furniture.Drawer(model, face, 0, 2.43, 3.1, 0.66, d - 0.55, color, "Bancada")
	Furniture.Drawer(model, face, 0, 1.7, 3.1, 0.66, d - 0.55, color, "Bancada")
	local face2 = body(model, cf * CFrame.new(-1.9, 0, 0), 2.8, d - 0.2, 2.1, 2.82, color)
	Furniture.Drawer(model, face2, 0, 2.46, 2.5, 0.62, d - 0.55, color, "Bancada")
	P(model, "Prateleira", Vector3.new(w - 0.8, 0.2, d - 0.4), cf * CFrame.new(0, 0.6, 0), Enum.Material.WoodPlanks, color, DECO)
	-- Morsa, lata de óleo, serrote.
	P(model, "Morsa", Vector3.new(0.9, 0.7, 1.1), cf * CFrame.new(-w / 2 + 0.7, 3.5, -0.6), Enum.Material.Metal, Color3.fromRGB(56, 70, 90), DECO)
	P(model, "Lata", Vector3.new(0.8, 0.55, 0.55), cf * CFrame.new(-1.2, 3.58, 0.4) * UPRIGHT, Enum.Material.Metal, Color3.fromRGB(150, 60, 40), { Collide = false, Shape = Enum.PartType.Cylinder })
	P(model, "Serrote", Vector3.new(2.2, 0.05, 0.7), cf * CFrame.new(1.5, 3.2, 0.3) * CFrame.Angles(0, 0.3, 0), Enum.Material.Metal, Color3.fromRGB(150, 150, 150), DECO)
	return model
end

-- Painel de ferramentas na parede: cf encostado na parede, LookVector pra fora.
function Furniture.Pegboard(parent: Instance, cf: CFrame)
	local model = Kit.Model(parent, "PainelFerramentas")
	P(model, "Painel", Vector3.new(6.0, 3.2, 0.12), cf, Enum.Material.WoodPlanks, Color3.fromRGB(150, 126, 92), DECO)
	local tools = {
		{ -2.3, 0.4, Vector3.new(0.15, 2.4, 0.1), Color3.fromRGB(150, 110, 70), 0.2 }, -- cabo de enxada
		{ -1.4, 0.2, Vector3.new(0.9, 0.25, 0.1), Color3.fromRGB(120, 120, 124), 0.0 }, -- martelo
		{ -0.4, -0.3, Vector3.new(0.12, 1.8, 0.1), Color3.fromRGB(110, 90, 60), -0.1 }, -- chave de fenda longa
		{ 0.6, 0.5, Vector3.new(1.6, 0.5, 0.08), Color3.fromRGB(140, 140, 146), 0.0 }, -- serrote
		{ 1.7, -0.2, Vector3.new(0.18, 1.6, 0.1), Color3.fromRGB(80, 80, 84), 0.05 }, -- alicate
		{ 2.4, 0.3, Vector3.new(0.5, 0.5, 0.25), Color3.fromRGB(170, 140, 60), 0.0 }, -- rolo de corda
	}
	for _, t in tools do
		P(model, "Ferramenta", t[3], cf * CFrame.new(t[1], t[2], -0.12) * CFrame.Angles(0, 0, t[5]), Enum.Material.Metal, t[4], DECO)
	end
	return model
end

-- Trator velho enferrujado (colisão por uma caixa só, rodas/detalhes sem colisão).
function Furniture.Tractor(parent: Instance, cf: CFrame): Model
	local model = Kit.Model(parent, "Trator")
	local paint = Color3.fromRGB(150, 58, 36)
	local rust = Color3.fromRGB(110, 70, 44)
	P(model, "Colisao", Vector3.new(6.2, 5.2, 10.0), cf * CFrame.new(0, 2.6, 0), Enum.Material.SmoothPlastic, paint, { Transparency = 1, Shadow = false })
	P(model, "Capo", Vector3.new(2.6, 2.4, 5.2), cf * CFrame.new(0, 3.6, -2.2), Enum.Material.CorrodedMetal, paint, DECO)
	P(model, "Grade", Vector3.new(2.4, 2.2, 0.2), cf * CFrame.new(0, 3.5, -4.85), Enum.Material.Metal, Color3.fromRGB(60, 58, 54), DECO)
	P(model, "Chassi", Vector3.new(2.2, 1.0, 8.4), cf * CFrame.new(0, 2.0, 0), Enum.Material.Metal, rust, DECO)
	P(model, "Assento", Vector3.new(1.6, 0.3, 1.4), cf * CFrame.new(0, 4.0, 2.6), Enum.Material.Metal, Color3.fromRGB(40, 40, 40), DECO)
	P(model, "Volante", Vector3.new(0.15, 1.3, 1.3), cf * CFrame.new(0, 4.9, 1.4) * CFrame.Angles(0.9, math.pi / 2, 0), Enum.Material.Metal, IRON, { Collide = false, Shape = Enum.PartType.Cylinder })
	P(model, "Escapamento", Vector3.new(2.6, 0.35, 0.35), cf * CFrame.new(0.7, 6.0, -3.2) * UPRIGHT, Enum.Material.Metal, Color3.fromRGB(34, 32, 30), { Collide = false, Shape = Enum.PartType.Cylinder })
	for _, sx in { -1, 1 } do
		P(model, "RodaTraseira", Vector3.new(1.3, 4.6, 4.6), cf * CFrame.new(sx * 2.4, 2.3, 2.5), Kit.Mat.Rubber, Color3.fromRGB(28, 26, 24), { Collide = false, Shape = Enum.PartType.Cylinder })
		P(model, "Aro", Vector3.new(1.35, 2.2, 2.2), cf * CFrame.new(sx * 2.4, 2.3, 2.5), Enum.Material.Metal, paint, { Collide = false, Shape = Enum.PartType.Cylinder })
		P(model, "RodaDianteira", Vector3.new(0.8, 2.4, 2.4), cf * CFrame.new(sx * 1.6, 1.2, -3.6), Enum.Material.SmoothPlastic, Color3.fromRGB(28, 26, 24), { Collide = false, Shape = Enum.PartType.Cylinder })
		P(model, "Paralama", Vector3.new(1.4, 0.2, 3.6), cf * CFrame.new(sx * 2.4, 4.75, 2.5), Enum.Material.CorrodedMetal, paint, DECO)
	end
	return model
end

-- Lampião pendurado numa viga (aceso fraco). cf = ponto de fixação.
function Furniture.HangingLantern(parent: Instance, cf: CFrame, drop: number, lit: boolean): Model
	local model = Kit.Model(parent, "Lampiao")
	P(model, "Gancho", Vector3.new(0.08, drop, 0.08), cf * CFrame.new(0, -drop / 2, 0), Enum.Material.Metal, IRON, DECO)
	local body = cf * CFrame.new(0, -drop - 0.5, 0)
	P(model, "Tampa", Vector3.new(0.7, 0.2, 0.7), body * CFrame.new(0, 0.55, 0), Enum.Material.Metal, IRON, DECO)
	P(model, "Globo", Vector3.new(0.6, 0.8, 0.6), body, Enum.Material.Glass, Color3.fromRGB(255, 220, 160), { Collide = false, Transparency = 0.4, Shadow = false })
	P(model, "Base", Vector3.new(0.7, 0.2, 0.7), body * CFrame.new(0, -0.5, 0), Enum.Material.Metal, IRON, DECO)
	local flame = P(model, "Chama", Vector3.new(0.2, 0.3, 0.2), body, if lit then Enum.Material.Neon else Enum.Material.Glass, if lit then Color3.fromRGB(255, 180, 90) else Color3.fromRGB(90, 80, 70), DECO)
	Kit.Light(flame, Color3.fromRGB(255, 170, 90), 20, 0.75, lit)
	return model
end

function Furniture.Trough(parent: Instance, cf: CFrame, len: number): Model
	local model = Kit.Model(parent, "Cocho")
	local wood = Color3.fromRGB(96, 76, 56)
	P(model, "Fundo", Vector3.new(len, 0.3, 1.8), cf * CFrame.new(0, 0.9, 0), Enum.Material.WoodPlanks, wood)
	for _, sz in { -1, 1 } do
		P(model, "Lado", Vector3.new(len, 1.3, 0.25), cf * CFrame.new(0, 1.5, sz * 0.8), Enum.Material.WoodPlanks, wood)
	end
	for _, sx in { -1, 1 } do
		P(model, "Cabeceira", Vector3.new(0.25, 1.3, 1.8), cf * CFrame.new(sx * (len / 2 - 0.12), 1.5, 0), Enum.Material.WoodPlanks, wood)
		P(model, "Pe", Vector3.new(0.35, 0.8, 1.9), cf * CFrame.new(sx * (len / 2 - 0.6), 0.4, 0), Enum.Material.Wood, wood, DECO)
	end
	P(model, "Agua", Vector3.new(len - 0.6, 0.05, 1.3), cf * CFrame.new(0, 1.9, 0), Enum.Material.Glass, Color3.fromRGB(70, 84, 70), { Collide = false, Transparency = 0.3 })
	return model
end

-- Baú de pé de cama com uma gaveta larga (cabe arma longa).
function Furniture.Trunk(parent: Instance, cf: CFrame, color: Color3): Model
	local model = Kit.Model(parent, "Bau")
	local w, d = 5.2, 2.2
	local face = body(model, cf, w, d, 0.2, 2.2, color)
	P(model, "Tampa", Vector3.new(w + 0.15, 0.35, d + 0.1), cf * CFrame.new(0, 2.37, -0.05), Enum.Material.Wood, color:Lerp(Color3.new(0, 0, 0), 0.2))
	for _, sx in { -1, 1 } do
		P(model, "Cinta", Vector3.new(0.3, 2.3, d + 0.12), cf * CFrame.new(sx * 1.8, 1.25, -0.02), Enum.Material.Metal, IRON, DECO)
	end
	Furniture.Drawer(model, face, 0, 1.15, 4.9, 1.0, d - 0.35, color, "Baú")
	return model
end

function Furniture.SaddleRack(parent: Instance, cf: CFrame)
	-- cf encostado na parede, LookVector pra fora.
	local model = Kit.Model(parent, "Sela")
	P(model, "Suporte", Vector3.new(0.3, 0.3, 1.6), cf * CFrame.new(0, 0, -0.8), Enum.Material.Wood, Furniture.Wood.Walnut, DECO)
	P(model, "Sela", Vector3.new(1.6, 0.9, 2.0), cf * CFrame.new(0, 0.55, -1.0), Kit.Mat.Leather, Color3.fromRGB(98, 58, 34), DECO)
	P(model, "Estribo", Vector3.new(0.12, 1.2, 0.5), cf * CFrame.new(0.85, -0.3, -1.0), Kit.Mat.Leather, Color3.fromRGB(70, 42, 26), DECO)
	return model
end

function Furniture.FeedSacks(parent: Instance, cf: CFrame, rng: Random): Model
	local model = Kit.Model(parent, "Sacos")
	for i = 0, 3 do
		local x = (i % 2) * 1.8 - 0.9
		local y = if i < 2 then 0.55 else 1.55
		P(model, "Saco", Vector3.new(1.6, 1.0, 2.4), cf * CFrame.new(x + rng:NextNumber(-0.1, 0.1), y, 0) * CFrame.Angles(0, rng:NextNumber(-0.15, 0.15), 0), Enum.Material.Fabric, Color3.fromRGB(196, 176, 132), { Collide = i < 2 })
	end
	return model
end

return Furniture
