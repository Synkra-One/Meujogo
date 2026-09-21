-- Paste this whole file into Roblox Studio's Command Bar and run it once
-- (modo de edição). Constrói uma cabana explorável média em Workspace.CampCabin_01,
-- inspirada no clima de Crystal Lake (Friday the 13th) sem copiar nada 1:1.
--
-- O QUE FAZ:
--   * Cria Workspace.CampCabin_01 com subpastas Structure/Doors/Windows/Props/Lights.
--   * Constrói piso, paredes externas, 2 divisórias internas, telhado de duas
--     águas e postes de canto -- tudo com Structures.lua (mesmo estilo de
--     madeira usado nas cabanas/lodge da ilha).
--   * Sala/cozinha (oeste) -> corredor/hall largo (centro) -> 2 quartos
--     pequenos lado a lado (leste), cada um com sua porta.
--   * Clona Bed horror game / Door / ceiling ligh de
--     Workspace["Modelos para as casas"] quando existem (sem mexer nos
--     originais); se algum não existir, cria um substituto simples com Parts.
--   * Nenhum script de gameplay: sem ProximityPrompt, sem Attribute "Porta"
--     (isso ligaria a porta ao DoorSystem existente), sem loot, sem som.
--
-- Depois de rodar: a casa aparece perto de (250, ?, 250) no mapa da ilha
-- (a altura Y é resolvida por raycast contra o Terrain/partes existentes,
-- com fallback se ainda não gerou a ilha). Arraste o Model CampCabin_01
-- pra outro lugar se quiser -- tudo foi construído com CFrame absoluto, não
-- depende de ficar exatamente ali.

local Workspace = game:GetService("Workspace")
local ServerScriptService = game:GetService("ServerScriptService")

local function fail(message: string)
	error("[CampCabin_01] " .. message, 0)
end

-- Structures.lua tem os helpers de parede-com-abertura, telhado de duas
-- águas e a paleta de cores de madeira já usada nas cabanas da ilha.
local serverFolder = ServerScriptService:FindFirstChild("Server")
local toolsFolder = serverFolder and serverFolder:FindFirstChild("Tools")
local structuresModule = toolsFolder and toolsFolder:FindFirstChild("Structures")
if not structuresModule then
	fail('Não encontrei ServerScriptService.Server.Tools.Structures. Sincronize o projeto com o Rojo (ou abra o Studio já conectado) antes de rodar este script.')
end
local S = require(structuresModule :: ModuleScript)
local COL = S.Colors

--------------------------------------------------------------------------------
-- Config (studs)
--------------------------------------------------------------------------------

local W = 64 -- comprimento (X), -32..32
local D = 34 -- profundidade (Z), -17..17
local WALL_H = 14
local WALL_T = 1
local FLOOR_T = 1
local DOOR_W, DOOR_H = 5, 8
local WIN_W, WIN_H = 6, 5
local WIN_Y0, WIN_Y1 = 3.5, 3.5 + WIN_H
local ROOF_PITCH_DEG = 24
local ROOF_OVERHANG = 1.5

local PLACEMENT_X, PLACEMENT_Z = 250, 250

--------------------------------------------------------------------------------
-- Onde apoiar a casa (raycast contra o que já existir; sem ilha gerada ainda,
-- cai num nível padrão pra dar pra testar mesmo assim).
--------------------------------------------------------------------------------

local function findGroundY(x: number, z: number): number
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = {}
	local result = Workspace:Raycast(Vector3.new(x, 500, z), Vector3.new(0, -1000, 0), params)
	if result then
		return result.Position.Y
	end
	return 0
end

local groundY = findGroundY(PLACEMENT_X, PLACEMENT_Z)
if groundY < -5 then
	warn("[CampCabin_01] O raycast achou chão bem abaixo do nível do mar nesse ponto (pode ter caído na água/fora da ilha). Mova o Model depois se necessário.")
end
local originCF = CFrame.new(PLACEMENT_X, groundY + FLOOR_T, PLACEMENT_Z)

--------------------------------------------------------------------------------
-- Model + subpastas
--------------------------------------------------------------------------------

local existing = Workspace:FindFirstChild("CampCabin_01")
if existing then
	existing:Destroy()
end

local cabin = Instance.new("Model")
cabin.Name = "CampCabin_01"
cabin.Parent = Workspace

local folders: { [string]: Folder } = {}
for _, name in { "Structure", "Doors", "Windows", "Props", "Lights" } do
	local f = Instance.new("Folder")
	f.Name = name
	f.Parent = cabin
	folders[name] = f
end
local Structure, Doors, Windows, Props, Lights = folders.Structure, folders.Doors, folders.Windows, folders.Props, folders.Lights

--------------------------------------------------------------------------------
-- Referências em Workspace["Modelos para as casas"] (clona, nunca move o original)
--------------------------------------------------------------------------------

local refFolder = Workspace:FindFirstChild("Modelos para as casas")
if not refFolder then
	warn('[CampCabin_01] Não achei Workspace["Modelos para as casas"]. Vou usar substitutos simples com Parts pra cama, porta e luminária.')
end

local function findReference(...: string): Instance?
	if not refFolder then
		return nil
	end
	for _, name in { ... } do
		local found = refFolder:FindFirstChild(name)
		if found then
			return found
		end
	end
	return nil
end

-- Clona a referência (se existir) já ancorada e sem scripts. Não mexe no original.
local function cloneReference(...: string): Instance?
	local src = findReference(...)
	if not src then
		return nil
	end
	local ok, clone = pcall(function()
		return src:Clone()
	end)
	if not ok or not clone then
		warn(("[CampCabin_01] Falhou ao clonar %s: %s"):format(src:GetFullName(), tostring(clone)))
		return nil
	end
	if clone:IsA("BasePart") then
		(clone :: BasePart).Anchored = true
	end
	for _, d in clone:GetDescendants() do
		if d:IsA("BasePart") then
			d.Anchored = true
		elseif d:IsA("Script") or d:IsA("LocalScript") then
			d:Destroy()
		end
	end
	return clone
end

local function placeClone(clone: Instance, parent: Instance, targetCF: CFrame)
	clone.Parent = parent
	pcall(function()
		(clone :: any):PivotTo(targetCF)
	end)
end

--------------------------------------------------------------------------------
-- Piso (uma laje só, sem emendas -- ninguém prende o pé em degrau escondido)
--------------------------------------------------------------------------------

S.Part(Structure, "Piso", Vector3.new(W + 1, FLOOR_T, D + 1), originCF * CFrame.new(0, -FLOOR_T / 2, 0), Enum.Material.WoodPlanks, COL.PlankDark)

--------------------------------------------------------------------------------
-- Paredes externas (com portas/janelas recortadas)
--------------------------------------------------------------------------------

-- Sul (frente): porta principal + janela da sala + janela do hall + janela do quarto B.
S.WallWithOpenings(Structure, originCF * CFrame.new(0, 0, -D / 2), W, WALL_H, WALL_T, {
	{ x0 = -22.5, x1 = -17.5, y0 = 0, y1 = DOOR_H }, -- porta de entrada
	{ x0 = -29, x1 = -23, y0 = WIN_Y0, y1 = WIN_Y1 }, -- janela da sala
	{ x0 = 1, x1 = 7, y0 = WIN_Y0, y1 = WIN_Y1 }, -- janela do hall
	{ x0 = 21, x1 = 27, y0 = WIN_Y0, y1 = WIN_Y1 }, -- janela do quarto B
}, Enum.Material.WoodPlanks, COL.Plank)

-- Norte (fundo): janela da sala + janela do hall + janela do quarto A.
S.WallWithOpenings(Structure, originCF * CFrame.new(0, 0, D / 2), W, WALL_H, WALL_T, {
	{ x0 = -29, x1 = -23, y0 = WIN_Y0, y1 = WIN_Y1 },
	{ x0 = 1, x1 = 7, y0 = WIN_Y0, y1 = WIN_Y1 },
	{ x0 = 21, x1 = 27, y0 = WIN_Y0, y1 = WIN_Y1 },
}, Enum.Material.WoodPlanks, COL.Plank)

-- Oeste: janela da sala.
S.WallWithOpenings(Structure, originCF * CFrame.new(-W / 2, 0, 0) * CFrame.Angles(0, math.pi / 2, 0), D, WALL_H, WALL_T, {
	{ x0 = -3, x1 = 3, y0 = WIN_Y0, y1 = WIN_Y1 },
}, Enum.Material.WoodPlanks, COL.Plank)

-- Leste: janela do quarto A + janela do quarto B.
S.WallWithOpenings(Structure, originCF * CFrame.new(W / 2, 0, 0) * CFrame.Angles(0, math.pi / 2, 0), D, WALL_H, WALL_T, {
	{ x0 = 5.5, x1 = 11.5, y0 = WIN_Y0, y1 = WIN_Y1 },
	{ x0 = -11.5, x1 = -5.5, y0 = WIN_Y0, y1 = WIN_Y1 },
}, Enum.Material.WoodPlanks, COL.Plank)

--------------------------------------------------------------------------------
-- Divisórias internas
--   Sala/Cozinha (X -32..-8)  |  Hall largo (X -8..16)  |  Quarto A/B (X 16..32)
--------------------------------------------------------------------------------

-- Divisória 1: separa a sala do hall. Um vão de porta no centro.
S.WallWithOpenings(Structure, originCF * CFrame.new(-8, 0, 0) * CFrame.Angles(0, math.pi / 2, 0), D, WALL_H, WALL_T, {
	{ x0 = -DOOR_W / 2, x1 = DOOR_W / 2, y0 = 0, y1 = DOOR_H },
}, Enum.Material.WoodPlanks, COL.PlankDark)

-- Divisória 2: separa o hall do bloco de quartos. Dois vãos de porta (um por quarto).
S.WallWithOpenings(Structure, originCF * CFrame.new(16, 0, 0) * CFrame.Angles(0, math.pi / 2, 0), D, WALL_H, WALL_T, {
	{ x0 = 6, x1 = 11, y0 = 0, y1 = DOOR_H }, -- entrada do Quarto A (norte)
	{ x0 = -11, x1 = -6, y0 = 0, y1 = DOOR_H }, -- entrada do Quarto B (sul)
}, Enum.Material.WoodPlanks, COL.PlankDark)

-- Divisória 3: separa Quarto A de Quarto B (sem vão, cada um só entra pelo hall).
S.WallWithOpenings(Structure, originCF * CFrame.new(24, 0, 0), 15, WALL_H, WALL_T, {}, Enum.Material.WoodPlanks, COL.PlankDark)

--------------------------------------------------------------------------------
-- Postes de canto (decoração leve, sem colisão -- não atrapalha andar perto da parede)
--------------------------------------------------------------------------------

local UPRIGHT = CFrame.Angles(0, 0, math.pi / 2)
for _, sx in { -1, 1 } do
	for _, sz in { -1, 1 } do
		S.Part(Structure, "PosteCanto", Vector3.new(WALL_H + 0.4, 1.3, 1.3), originCF * CFrame.new(sx * W / 2, WALL_H / 2, sz * D / 2) * UPRIGHT, Enum.Material.Wood, COL.LogDark, { Shape = Enum.PartType.Cylinder, CanCollide = false })
	end
end

--------------------------------------------------------------------------------
-- Telhado de duas águas -- cumeeira corre no eixo comprido (X), a água desce
-- pro norte/sul. width=D (é o eixo que desce), depth=W (é o eixo da cumeeira).
--------------------------------------------------------------------------------

S.GableRoof(Structure, originCF * CFrame.Angles(0, math.pi / 2, 0), D, W, WALL_H, ROOF_PITCH_DEG, ROOF_OVERHANG, COL.Roof)

--------------------------------------------------------------------------------
-- Janelas (moldura + vidro) -- puramente visual, encaixadas nos vãos acima.
--------------------------------------------------------------------------------

type WindowSpec = { cf: CFrame, horizontal: boolean }

local windowSpecs: { WindowSpec } = {
	{ cf = originCF * CFrame.new(-26, (WIN_Y0 + WIN_Y1) / 2, -D / 2), horizontal = true }, -- sala, parede sul
	{ cf = originCF * CFrame.new(-26, (WIN_Y0 + WIN_Y1) / 2, D / 2), horizontal = true }, -- sala, parede norte
	{ cf = originCF * CFrame.new(4, (WIN_Y0 + WIN_Y1) / 2, -D / 2), horizontal = true }, -- hall, parede sul
	{ cf = originCF * CFrame.new(4, (WIN_Y0 + WIN_Y1) / 2, D / 2), horizontal = true }, -- hall, parede norte
	{ cf = originCF * CFrame.new(24, (WIN_Y0 + WIN_Y1) / 2, -D / 2), horizontal = true }, -- quarto B, parede sul
	{ cf = originCF * CFrame.new(24, (WIN_Y0 + WIN_Y1) / 2, D / 2), horizontal = true }, -- quarto A, parede norte
	{ cf = originCF * CFrame.new(-W / 2, (WIN_Y0 + WIN_Y1) / 2, 0), horizontal = false }, -- sala, parede oeste
	{ cf = originCF * CFrame.new(W / 2, (WIN_Y0 + WIN_Y1) / 2, 8.5), horizontal = false }, -- quarto A, parede leste
	{ cf = originCF * CFrame.new(W / 2, (WIN_Y0 + WIN_Y1) / 2, -8.5), horizontal = false }, -- quarto B, parede leste
}

for i, spec in windowSpecs do
	local rot = if spec.horizontal then CFrame.new() else CFrame.Angles(0, math.pi / 2, 0)
	local frame = S.Part(Windows, "JanelaMoldura", Vector3.new(WIN_W + 0.5, WIN_H + 0.5, 0.2), spec.cf * rot, Enum.Material.WoodPlanks, COL.PlankDark, { CanCollide = false })
	frame.Name = "JanelaMoldura_" .. i
	local glass = S.Part(Windows, "JanelaVidro", Vector3.new(WIN_W - 0.4, WIN_H - 0.4, WALL_T - 0.3), spec.cf * rot, Enum.Material.Glass, COL.Glass, { CanCollide = true, Transparency = 0.35 })
	glass.Name = "JanelaVidro_" .. i
end

--------------------------------------------------------------------------------
-- Porta principal -- clona a referência "Door" (aberta, encostada na parede
-- interna) ou monta uma folha simples se não existir. Sem Attribute "Porta":
-- não liga no DoorSystem, é só cenário por enquanto.
--------------------------------------------------------------------------------

local FRONT_DOOR_HINGE_X = -17.5 -- borda leste do vão (X -22.5..-17.5)
local frontDoorClosedCF = originCF * CFrame.new(FRONT_DOOR_HINGE_X, DOOR_H / 2, -D / 2)
local frontDoorOpenCF = frontDoorClosedCF * CFrame.Angles(0, math.rad(82), 0) * CFrame.new((DOOR_W - 0.3) / 2, 0, 0)

local frontDoorClone = cloneReference("Door")
if frontDoorClone then
	placeClone(frontDoorClone, Doors, frontDoorOpenCF)
else
	S.Part(Doors, "PortaEntrada", Vector3.new(DOOR_W - 0.3, DOOR_H - 0.2, 0.2), frontDoorOpenCF, Enum.Material.WoodPlanks, COL.PlankDark)
	S.Part(Doors, "PortaEntradaMacaneta", Vector3.new(0.25, 0.25, 0.5), frontDoorOpenCF * CFrame.new((DOOR_W - 0.3) / 2 - 0.5, 0, 0), Enum.Material.Metal, COL.Metal, { CanCollide = false })
end

--------------------------------------------------------------------------------
-- Camas (Quarto A e Quarto B) -- clona "Bed horror game" ou monta uma cama simples.
--------------------------------------------------------------------------------

local function buildSimpleBed(parent: Instance, cf: CFrame)
	local model = Instance.new("Model")
	model.Name = "Cama"
	S.Part(model, "CamaEstrutura", Vector3.new(4, 1.1, 7), cf * CFrame.new(0, 0.55, 0), Enum.Material.Wood, COL.PlankDark)
	S.Part(model, "CamaColchao", Vector3.new(3.6, 0.5, 6.4), cf * CFrame.new(0, 1.35, 0), Enum.Material.Fabric, COL.Mattress, { CanCollide = false })
	S.Part(model, "CamaTravesseiro", Vector3.new(2.4, 0.4, 1.2), cf * CFrame.new(0, 1.8, -2.3), Enum.Material.Fabric, Color3.fromRGB(220, 216, 205), { CanCollide = false })
	model.Parent = parent
end

local bedACF = originCF * CFrame.new(24, 0, 12) -- Quarto A, encostada na parede norte
local bedBCF = originCF * CFrame.new(24, 0, -12) * CFrame.Angles(0, math.pi, 0) -- Quarto B, encostada na parede sul

local bedAClone = cloneReference("Bed horror game")
if bedAClone then
	placeClone(bedAClone, Props, bedACF)
else
	buildSimpleBed(Props, bedACF)
end

local bedBClone = cloneReference("Bed horror game")
if bedBClone then
	placeClone(bedBClone, Props, bedBCF)
else
	buildSimpleBed(Props, bedBCF)
end

--------------------------------------------------------------------------------
-- Luminárias de teto -- clona "ceiling ligh" ou monta um bico simples com
-- PointLight (fraco, clima abandonado -- não é sistema de gameplay).
--------------------------------------------------------------------------------

local function buildSimpleCeilingLight(parent: Instance, cf: CFrame)
	local fixture = S.Part(parent, "LuminariaTeto", Vector3.new(1.2, 0.5, 1.2), cf, Enum.Material.Metal, COL.Metal, { Shape = Enum.PartType.Cylinder, CanCollide = false })
	fixture.Orientation = Vector3.new(0, 0, 90)
	local bulb = S.Part(parent, "LuminariaLampada", Vector3.new(0.5, 0.5, 0.5), cf * CFrame.new(0, -0.4, 0), Enum.Material.Neon, Color3.fromRGB(255, 200, 140), { Shape = Enum.PartType.Ball, CanCollide = false })
	local light = Instance.new("PointLight")
	light.Color = Color3.fromRGB(255, 190, 130)
	light.Range = 14
	light.Brightness = 0.35
	light.Shadows = false
	light.Parent = bulb
end

local lightSpots = {
	{ x = -20, z = 0, room = "Sala" },
	{ x = 4, z = 0, room = "Hall" },
	{ x = 24, z = 8.5, room = "QuartoA" },
	{ x = 24, z = -8.5, room = "QuartoB" },
}
for _, spot in lightSpots do
	local cf = originCF * CFrame.new(spot.x, WALL_H - 1, spot.z)
	local clone = cloneReference("ceiling ligh", "ceiling light", "Ceiling Light")
	if clone then
		placeClone(clone, Lights, cf)
	else
		buildSimpleCeilingLight(Lights, cf)
	end
end

--------------------------------------------------------------------------------
-- Fim
--------------------------------------------------------------------------------

local floorPart = Structure:FindFirstChild("Piso")
if floorPart and floorPart:IsA("BasePart") then
	cabin.PrimaryPart = floorPart
end

local totalHeight = WALL_H + (D / 2) * math.tan(math.rad(ROOF_PITCH_DEG)) + 0.1
print(("[CampCabin_01] Pronto. Casa %dx%d studs, paredes de %d studs, altura total ~%.1f studs (chão -> cumeeira), piso no mundo em Y=%.1f, centro em (%.0f, _, %.0f)."):format(
	W, D, WALL_H, totalHeight, groundY + FLOOR_T, PLACEMENT_X, PLACEMENT_Z
))
print("[CampCabin_01] Layout: Sala/Cozinha (oeste) -> Hall (centro, 24 studs de largura) -> Quarto A / Quarto B (leste, lado a lado). Porta de entrada na parede sul, aberta e encostada. Confira andando: entrada -> hall -> os dois quartos -> volta, sem travar em nenhuma porta (todos os vãos são 5x8).")
