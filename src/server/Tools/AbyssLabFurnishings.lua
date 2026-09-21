--!strict
-- Mobiliário nativo da Estação Abismo. O piso da sala é Y=0 no frame recebido.
-- O corredor X=-4..4 e uma faixa de 4 studs junto às paredes ficam livres.
local S = require(script.Parent.Structures)

local Furnishings = {}
local C = {
	White = Color3.fromRGB(218, 230, 231),
	Steel = Color3.fromRGB(143, 167, 178),
	Dark = Color3.fromRGB(31, 47, 58),
	Teal = Color3.fromRGB(36, 80, 91),
	Black = Color3.fromRGB(12, 23, 31),
	Cyan = Color3.fromRGB(81, 209, 220),
	Amber = Color3.fromRGB(237, 182, 88),
	Glass = Color3.fromRGB(152, 214, 218),
}
local METAL = Enum.Material.Metal
local PLASTIC = Enum.Material.SmoothPlastic
local NEON = Enum.Material.Neon
local UPRIGHT = CFrame.Angles(0, 0, math.pi / 2)

local function block(parent: Instance, frame: CFrame, name: string, size: Vector3, x: number, y: number, z: number, color: Color3, solid: boolean?, material: Enum.Material?): Part
	local p = S.Part(parent, name, size, frame * CFrame.new(x, y, z), material or METAL, color, { CanCollide = solid == true })
	p.CanTouch = false
	p.CanQuery = solid == true
	return p
end

local function cylinder(parent: Instance, frame: CFrame, name: string, x: number, y: number, z: number, radius: number, height: number, color: Color3, material: Enum.Material?, solid: boolean?): Part
	local p = S.Part(parent, name, Vector3.new(height, radius * 2, radius * 2), frame * CFrame.new(x, y, z) * UPRIGHT, material or METAL, color, { Shape = Enum.PartType.Cylinder, CanCollide = solid == true })
	p.CanTouch = false
	p.CanQuery = solid == true
	return p
end

local function label(p: BasePart, title: string, subtitle: string, color: Color3?)
	local gui = Instance.new("SurfaceGui")
	gui.Name = "Identificacao"
	gui.Face = Enum.NormalId.Front
	gui.CanvasSize = Vector2.new(480, 180)
	gui.LightInfluence = 0.2
	gui.Parent = p
	local text = Instance.new("TextLabel")
	text.Size = UDim2.fromScale(0.9, 0.86)
	text.Position = UDim2.fromScale(0.05, 0.07)
	text.BackgroundTransparency = 1
	text.Text = title .. "\n" .. subtitle
	text.TextColor3 = color or C.Cyan
	text.Font = Enum.Font.GothamMedium
	text.TextSize = 26
	text.TextWrapped = true
	text.Parent = gui
end

local function bench(parent: Instance, frame: CFrame, depth: number)
	block(parent, frame, "BancadaInox", Vector3.new(4.8, 0.22, depth), 0, 2.9, 0, C.Steel, true)
	block(parent, frame, "Rodabanca", Vector3.new(4.8, 0.35, 0.13), 0, 3.18, depth / 2 - 0.1, C.White)
	block(parent, frame, "Gaveteiro", Vector3.new(1.65, 2.55, depth - 0.35), -1.36, 1.45, 0.05, C.White, true)
	for i = 1, 3 do
		block(parent, frame, "FrenteGaveta", Vector3.new(1.46, 0.65, 0.08), -1.36, 0.62 + i * 0.63, -depth / 2 + 0.17, C.Teal)
		block(parent, frame, "PuxadorInox", Vector3.new(0.62, 0.07, 0.12), -1.36, 0.8 + i * 0.63, -depth / 2 + 0.09, C.Steel)
	end
	for _, z in { -depth / 2 + 0.24, depth / 2 - 0.24 } do
		block(parent, frame, "PeBancada", Vector3.new(0.14, 2.8, 0.14), 2.12, 1.4, z, C.Steel)
	end
	block(parent, frame, "Travessa", Vector3.new(0.12, 0.14, depth - 0.4), 2.12, 0.45, 0, C.Teal)
end

local function monitor(parent: Instance, frame: CFrame, x: number, y: number, title: string)
	block(parent, frame, "BaseMonitor", Vector3.new(1.1, 0.09, 0.7), x, y + 0.04, 0.32, C.Dark)
	block(parent, frame, "SuporteMonitor", Vector3.new(0.15, 0.55, 0.15), x, y + 0.34, 0.48, C.Steel)
	block(parent, frame, "Monitor", Vector3.new(1.95, 1.25, 0.17), x, y + 1.09, 0.45, C.Dark)
	local screen = block(parent, frame, "Display", Vector3.new(1.76, 1.06, 0.025), x, y + 1.09, 0.35, C.Black, false, PLASTIC)
	label(screen, title, "ABISMO / SISTEMA ATIVO")
	block(parent, frame, "Teclado", Vector3.new(1.45, 0.09, 0.5), x, y + 0.045, -0.8, C.Dark)
end

local function microscope(parent: Instance, frame: CFrame, x: number)
	block(parent, frame, "BaseMicroscopio", Vector3.new(0.85, 0.13, 0.95), x, 3.08, -0.12, C.White)
	block(parent, frame, "ColunaMicroscopio", Vector3.new(0.22, 1.12, 0.23), x, 3.7, 0.19, C.Teal)
	block(parent, frame, "MesaMicroscopio", Vector3.new(0.7, 0.1, 0.55), x, 3.52, -0.12, C.Dark)
	block(parent, frame, "BracoOptico", Vector3.new(0.32, 0.2, 0.68), x, 4.19, -0.02, C.White)
	cylinder(parent, frame, "Objetiva", x, 4.02, -0.25, 0.12, 0.32, C.Steel)
	cylinder(parent, frame, "Ocular", x, 4.43, 0.1, 0.12, 0.3, C.Dark)
	block(parent, frame, "Lamina", Vector3.new(0.35, 0.02, 0.17), x, 3.58, -0.15, C.Cyan, false, Enum.Material.Glass)
end

local function samples(parent: Instance, frame: CFrame, x: number, y: number, z: number)
	block(parent, frame, "RackAmostras", Vector3.new(1.15, 0.12, 0.48), x, y + 0.06, z, C.Teal)
	for i = 1, 3 do
		local vial = cylinder(parent, frame, "TuboSelado", x - 0.36 + (i - 1) * 0.36, y + 0.39, z, 0.11, 0.55, C.Glass, Enum.Material.Glass)
		vial.Transparency = 0.22
		cylinder(parent, frame, "TampaAmostra", x - 0.36 + (i - 1) * 0.36, y + 0.68, z, 0.12, 0.09, C.Amber)
	end
end

local function cabinet(parent: Instance, frame: CFrame, title: string, depth: number)
	block(parent, frame, "BaseArmario", Vector3.new(4.2, 0.18, depth - 0.1), 0, 0.18, 0, C.Dark, true)
	block(parent, frame, "ArmarioTecnico", Vector3.new(4.15, 6.45, depth - 0.2), 0, 3.47, 0.05, C.White, true)
	for _, x in { -1.04, 1.04 } do
		block(parent, frame, "FolhaArmario", Vector3.new(1.97, 5.58, 0.1), x, 3.24, -depth / 2 + 0.12, C.Teal)
		block(parent, frame, "PuxadorArmario", Vector3.new(0.08, 0.9, 0.11), x / 5, 3.1, -depth / 2 + 0.03, C.Steel)
	end
	local sign = block(parent, frame, "RotuloArmario", Vector3.new(3.8, 0.55, 0.08), 0, 6.3, -depth / 2 + 0.1, C.Dark)
	label(sign, title, "ACESSO CONTROLADO", C.White)
end

local function server(parent: Instance, frame: CFrame, depth: number)
	block(parent, frame, "RackComputacao", Vector3.new(4.2, 6.8, depth - 0.1), 0, 3.5, 0, C.Dark, true)
	for i = 1, 6 do
		local y = 0.65 + i * 0.81
		block(parent, frame, "ModuloServidor", Vector3.new(3.75, 0.65, 0.14), 0, y, -depth / 2 + 0.03, C.Teal)
		block(parent, frame, "StatusServidor", Vector3.new(0.34, 0.07, 0.03), -1.48, y, -depth / 2 - 0.06, if i == 5 then C.Amber else C.Cyan, false, NEON)
	end
	local screen = block(parent, frame, "RackIdentificacao", Vector3.new(3.7, 0.52, 0.035), 0, 6.32, -depth / 2 - 0.03, C.Black)
	label(screen, "NÓ AB-07", "TELEMETRIA / ARQUIVO")
end

local function bed(parent: Instance, frame: CFrame, depth: number)
	local bedDepth = math.min(depth - 0.25, 2.65)
	block(parent, frame, "PedestalMaca", Vector3.new(2.45, 1.8, 1.35), 0, 1.05, 0, C.White, true)
	block(parent, frame, "EstruturaMaca", Vector3.new(4.75, 0.25, bedDepth), 0, 2.08, 0, C.Steel, true)
	block(parent, frame, "ColchaoClinico", Vector3.new(4.48, 0.33, bedDepth - 0.16), 0, 2.36, 0, C.Teal, false, PLASTIC)
	block(parent, frame, "TravesseiroSelado", Vector3.new(0.87, 0.2, bedDepth - 0.35), -1.65, 2.62, 0, C.White, false, PLASTIC)
	for _, z in { -bedDepth / 2, bedDepth / 2 } do
		block(parent, frame, "GradeMaca", Vector3.new(2.8, 0.09, 0.09), 0, 2.97, z, C.Steel)
		for _, x in { -1.35, 1.35 } do
			block(parent, frame, "SuporteGrade", Vector3.new(0.08, 0.76, 0.08), x, 2.6, z, C.Steel)
		end
	end
end

local function archive(parent: Instance, frame: CFrame, depth: number)
	for _, x in { -2.12, 2.12 } do
		block(parent, frame, "MontanteArquivo", Vector3.new(0.13, 6.2, depth - 0.2), x, 3.18, 0, C.Dark, true)
	end
	block(parent, frame, "FundoArquivo", Vector3.new(4.2, 6.2, 0.1), 0, 3.18, depth / 2 - 0.12, C.Teal, true)
	for row = 0, 3 do
		local y = 0.38 + row * 1.53
		block(parent, frame, "PrateleiraInox", Vector3.new(4.2, 0.12, depth - 0.2), 0, y, 0, C.Steel, true)
		for col = 1, 2 do
			local x = -0.99 + (col - 1) * 1.98
			local box = block(parent, frame, "CaixaAmostras", Vector3.new(1.64, 1.1, depth - 0.65), x, y + 0.61, 0, C.White, true, PLASTIC)
			label(box, "AB / " .. tostring(row * 2 + col), "AMOSTRAS CATALOGADAS", C.Dark)
		end
	end
end

local function utility(parent: Instance, frame: CFrame, depth: number)
	block(parent, frame, "BaseEnergia", Vector3.new(4.65, 0.3, depth), 0, 0.2, 0, C.Dark, true)
	block(parent, frame, "UnidadeTratamento", Vector3.new(4.3, 5.6, depth - 0.2), 0, 3.11, 0.02, C.White, true)
	local front = -depth / 2 + 0.07
	block(parent, frame, "GrelhaVentilacao", Vector3.new(3.66, 2.1, 0.09), 0, 2.1, front, C.Dark)
	for i = 1, 6 do
		block(parent, frame, "AletaVentilacao", Vector3.new(3.45, 0.06, 0.06), 0, 1.22 + i * 0.27, front - 0.07, C.Steel)
	end
	local screen = block(parent, frame, "ControleAmbiental", Vector3.new(2.8, 1.35, 0.12), 0, 4.36, front - 0.03, C.Black)
	label(screen, "SUPORTE AMBIENTAL", "AR 98%  /  PRESSÃO ESTÁVEL")
	block(parent, frame, "IndicadorEnergia", Vector3.new(3.75, 0.06, 0.04), 0, 5.59, front - 0.07, C.Cyan, false, NEON)
end

local function furnishStation(parent: Instance, frame: CFrame, depth: number, kind: string, index: number)
	if kind == "Laboratorio" then
		bench(parent, frame, depth)
		microscope(parent, frame, -1.1)
		samples(parent, frame, 1.06, 3.02, -0.35)
		local panel = block(parent, frame, "AnaliseAmostras", Vector3.new(1.43, 0.92, 0.12), 1.12, 3.74, 0.8, C.Dark)
		label(panel, "ANÁLISE " .. tostring(index), "BIOMATERIAL / SELADO")
	elseif kind == "Controle" then
		if index % 2 == 0 then
			server(parent, frame, depth)
		else
			bench(parent, frame, depth)
			monitor(parent, frame, -1.12, 3.02, "SEGURANÇA")
			monitor(parent, frame, 1.12, 3.02, "COMUNICAÇÕES")
		end
	elseif kind == "Clinica" then
		if index % 2 == 0 then
			cabinet(parent, frame, "MATERIAL ESTÉRIL", depth)
		else
			bed(parent, frame, depth)
		end
	elseif kind == "Arquivo" then
		archive(parent, frame, depth)
	elseif kind == "Utilidades" then
		if index % 2 == 0 then
			cabinet(parent, frame, "MANUTENÇÃO / EPI", depth)
		else
			utility(parent, frame, depth)
		end
	else
		if index % 2 == 0 then
			cabinet(parent, frame, "VESTIÁRIO / EQUIPE", depth)
		else
			bench(parent, frame, depth)
			monitor(parent, frame, 0, 3.02, "RECEPÇÃO ABISMO")
			block(parent, frame, "LeitorCredencial", Vector3.new(0.48, 0.14, 0.7), -1.65, 3.08, -0.65, C.Teal)
		end
	end
end

--------------------------------------------------------------------------------
-- Distribuição no ambiente
--------------------------------------------------------------------------------
-- Os postos encostam nas paredes e deixam o miolo da sala livre. Cada vão
-- declarado no plano (porta ou passagem) abre uma janela na parede: a varredura
-- da folha nunca passa da largura do próprio vão, então basta a folga lateral.
-- Nas quinas a folga é maior: ali o posto da parede vizinha avança para dentro.
local DOOR_CLEARANCE = 3
local MIN_SPAN = 6
local STATION_PITCH = 16

local function freeSpans(lo: number, hi: number, openings: any, corner: number): { { number } }
	local spans = { { lo + corner, hi - corner } }
	for _, opening in openings or {} do
		local a, b = opening[1] - DOOR_CLEARANCE, opening[2] + DOOR_CLEARANCE
		local kept = {}
		for _, span in spans do
			if b <= span[1] or a >= span[2] then
				table.insert(kept, span)
			else
				if a - span[1] >= MIN_SPAN then table.insert(kept, { span[1], a }) end
				if span[2] - b >= MIN_SPAN then table.insert(kept, { b, span[2] }) end
			end
		end
		spans = kept
	end
	return spans
end

function Furnishings.Room(parent: Instance, floorFrame: CFrame, room: any): Model
	local width, depth = room.X1 - room.X0, room.Z1 - room.Z0
	assert(width >= 24 and depth >= 20, "Mobiliário Abismo requer sala de pelo menos 24x20 studs")
	local model = Instance.new("Model")
	model.Name = "Mobiliario_" .. room.Kind
	model:SetAttribute("AbismoMobiliario", true)
	model.Parent = parent
	local bankDepth = math.min(3.8, width / 2 - 8.4, depth / 2 - 8.4)
	local inset = 1.2 + bankDepth / 2
	local index = 0
	local function place(x: number, z: number, yaw: number)
		index += 1
		furnishStation(model, floorFrame * CFrame.new(x, 0, z) * CFrame.Angles(0, yaw, 0), bankDepth, room.Kind, index)
	end
	-- Postos de parede: a frente de cada um olha para o miolo da sala.
	for _, side in {
		{ Edge = "XMin", Fixed = -width / 2 + inset, Lo = room.Z0, Hi = room.Z1, Yaw = -math.pi / 2, Along = "Z" },
		{ Edge = "XMax", Fixed = width / 2 - inset, Lo = room.Z0, Hi = room.Z1, Yaw = math.pi / 2, Along = "Z" },
		{ Edge = "ZMin", Fixed = -depth / 2 + inset, Lo = room.X0, Hi = room.X1, Yaw = math.pi, Along = "X" },
		{ Edge = "ZMax", Fixed = depth / 2 - inset, Lo = room.X0, Hi = room.X1, Yaw = 0, Along = "X" },
	} do
		local center = (side.Lo + side.Hi) / 2
		for _, span in freeSpans(side.Lo, side.Hi, room.Openings[side.Edge], inset + 2.5) do
			local count = math.clamp(math.floor((span[2] - span[1]) / STATION_PITCH), 1, 3)
			for i = 1, count do
				local along = span[1] + (span[2] - span[1]) * (i - 0.5) / count - center
				if side.Along == "Z" then place(side.Fixed, along, side.Yaw) else place(along, side.Fixed, side.Yaw) end
			end
		end
	end
	-- Ilhas centrais apenas onde as duas paredes de fundo são cegas: o eixo da
	-- porta e o centro da sala continuam desimpedidos.
	if width >= 40 and depth >= 30 and #(room.Openings.ZMin or {}) == 0 and #(room.Openings.ZMax or {}) == 0 then
		for _, side in { -1, 1 } do
			place(0, side * depth / 4, if side < 0 then math.pi else 0)
		end
	end
	return model
end

--------------------------------------------------------------------------------
-- Salão de testes: onde os cientistas trabalhavam com os monstros
--------------------------------------------------------------------------------
local BLOOD = Color3.fromRGB(74, 14, 16)
local GREEN = Color3.fromRGB(96, 219, 128)

local function stain(parent: Instance, frame: CFrame, x: number, z: number, size: number, tilt: number)
	local p = block(parent, frame, "MarcaDeSangue", Vector3.new(size, 0.03, size * 0.72), x, 0.03, z, BLOOD, false, PLASTIC)
	p.CFrame = frame * CFrame.new(x, 0.03, z) * CFrame.Angles(0, tilt, 0)
	p.Transparency = 0.12
end

local function stripes(parent: Instance, frame: CFrame, x: number, z: number, halfX: number, halfZ: number)
	for i = -3, 3 do
		block(parent, frame, "FaixaPerigo", Vector3.new(1.1, 0.04, halfZ * 2), x - halfX + 0.9 + (i + 3) * (halfX * 2 - 1.8) / 6, 0.02, z, C.Amber, false, PLASTIC)
	end
	for _, side in { -1, 1 } do
		block(parent, frame, "BordaPerigo", Vector3.new(halfX * 2, 0.05, 0.5), x, 0.025, z + side * halfZ, C.Black, false, PLASTIC)
	end
end

--[[
	Frog Generator
	A cápsula de cultivo do salão de testes: tanque de vidro com fluido, o
	espécime suspenso dentro, anéis de pressão, mangueiras e o console de
	comando. `FrogGenerator` fica no Model para o resto do jogo achá-lo.
]]
local function frogGenerator(parent: Instance, frame: CFrame): Model
	local model = Instance.new("Model")
	model.Name = "FrogGenerator"
	model:SetAttribute("FrogGenerator", true)
	model:SetAttribute("AbismoCapsula", "FrogGenerator")
	model.Parent = parent
	block(model, frame, "PlataformaCapsula", Vector3.new(15, 0.34, 15), 0, 0.17, 0, C.Dark, true, METAL)
	cylinder(model, frame, "BaseCapsula", 0, 1.3, 0, 6.2, 2.3, C.Steel, METAL, true)
	cylinder(model, frame, "AnelInferior", 0, 2.85, 0, 5.6, 1.1, C.Dark)
	-- Tanque: vidro por fora, fluido por dentro, espécime no meio.
	local glass = cylinder(model, frame, "VidroCapsula", 0, 8.6, 0, 4.9, 10.4, C.Glass, Enum.Material.Glass, true)
	glass.Transparency = 0.6
	glass.Reflectance = 0.12
	local fluid = cylinder(model, frame, "FluidoCapsula", 0, 8.2, 0, 4.5, 9.2, GREEN, NEON)
	fluid.Transparency = 0.62
	local glow = Instance.new("PointLight")
	glow.Color, glow.Brightness, glow.Range, glow.Shadows = GREEN, 1.6, 30, false
	glow.Parent = fluid
	for _, piece in {
		{ "TorsoEspecime", Vector3.new(2.1, 3.2, 1.5), 0, 8.6, 0 },
		{ "CabecaEspecime", Vector3.new(1.5, 1.4, 1.5), 0, 10.7, 0 },
		{ "CoxaEspecime", Vector3.new(0.8, 2.6, 0.8), -1.2, 6.2, 0.4 },
		{ "CoxaEspecime", Vector3.new(0.8, 2.6, 0.8), 1.2, 6.2, 0.4 },
		{ "BracoEspecime", Vector3.new(0.7, 3, 0.7), -1.7, 8.8, -0.3 },
		{ "BracoEspecime", Vector3.new(0.7, 3, 0.7), 1.7, 8.8, -0.3 },
	} do
		local limb = block(model, frame, piece[1], piece[2], piece[3], piece[4], piece[5], Color3.fromRGB(38, 52, 41), false, PLASTIC)
		limb.Transparency = 0.15
	end
	for i = 0, 3 do
		local a = i * math.pi / 2 + math.pi / 4
		block(model, frame, "ColunaCapsula", Vector3.new(0.55, 11, 0.55), math.cos(a) * 5.2, 8.5, math.sin(a) * 5.2, C.Steel)
		S.Beam(model, "MangueiraCapsula",
			(frame * CFrame.new(math.cos(a) * 5.6, 14.6, math.sin(a) * 5.6)).Position,
			(frame * CFrame.new(math.cos(a) * 8.4, 0.6, math.sin(a) * 8.4)).Position,
			0.42, METAL, C.Teal, false)
	end
	cylinder(model, frame, "AnelSuperior", 0, 14.4, 0, 5.7, 1.3, C.Dark)
	cylinder(model, frame, "TampaCapsula", 0, 15.6, 0, 4.4, 1.2, C.Steel)
	local marquee = block(model, frame, "PlacaCapsula", Vector3.new(6.4, 1.5, 0.16), 0, 15.9, -5.5, C.Black, false, PLASTIC)
	label(marquee, "FROG GENERATOR", "CULTIVO / UNIDADE 01", GREEN)
	-- Console de comando: atravessado na frente da cápsula, olhando para a
	-- porta do salão, entre a plataforma e a faixa de circulação do meio.
	local desk = frame * CFrame.new(-9.6, 0, 0) * CFrame.Angles(0, math.pi / 2, 0)
	block(model, desk, "ConsoleCapsula", Vector3.new(6.2, 2.6, 2.3), 0, 1.3, 0, C.Dark, true)
	block(model, desk, "TampoConsole", Vector3.new(6.6, 0.22, 2.7), 0, 2.72, 0, C.Steel, true)
	monitor(model, desk, -1.62, 2.83, "FROG GENERATOR")
	monitor(model, desk, 1.62, 2.83, "CICLO 14 / ESTÁVEL")
	for i = 1, 4 do
		block(model, desk, "AlavancaCapsula", Vector3.new(0.22, 0.75, 0.22), -2.6 + i * 0.6, 3.2, -0.75, if i == 3 then C.Amber else C.Steel)
	end
	-- Tanques de reserva atrás da cápsula.
	for _, side in { -1, 1 } do
		cylinder(model, frame, "TanqueCriogenico", 10.4, 3.1, side * 6.6, 1.5, 6.2, C.Teal, METAL, true)
		block(model, frame, "ValvulaTanque", Vector3.new(1.1, 0.5, 1.1), 10.4, 6.4, side * 6.6, C.Amber)
	end
	return model
end

-- Cela de contenção: grades, visor blindado e sangue seco no chão.
local function containmentCell(parent: Instance, frame: CFrame, index: number)
	local w, d, h = 11, 9.5, 12
	block(parent, frame, "PisoCela", Vector3.new(w, 0.12, d), 0, 0.06, 0, C.Black, false, PLASTIC)
	block(parent, frame, "TetoCela", Vector3.new(w, 0.5, d), 0, h, 0, C.Dark, true)
	for _, side in { -1, 1 } do
		block(parent, frame, "LateralCela", Vector3.new(0.45, h, d), side * (w / 2 - 0.2), h / 2, 0, C.Dark, true)
	end
	block(parent, frame, "FundoCela", Vector3.new(w, h, 0.45), 0, h / 2, d / 2 - 0.2, C.Teal, true)
	-- Frente: grades verticais com um vão de passagem no meio.
	for i = -4, 4 do
		if math.abs(i) > 1 then
			block(parent, frame, "GradeCela", Vector3.new(0.34, h - 0.5, 0.34), i * 1.15, h / 2, -d / 2 + 0.3, C.Steel, true)
		end
	end
	block(parent, frame, "VergaCela", Vector3.new(w, 1.1, 0.6), 0, h - 0.8, -d / 2 + 0.3, C.Dark, true)
	local plate = block(parent, frame, "IdentificacaoCela", Vector3.new(3.4, 0.9, 0.1), 0, h - 2.1, -d / 2 + 0.05, C.Black, false, PLASTIC)
	label(plate, "CELA " .. string.format("%02d", index), if index % 3 == 0 then "VAZIA / RUPTURA" else "CONTENÇÃO ATIVA",
		if index % 3 == 0 then C.Amber else C.Cyan)
	block(parent, frame, "ComedouroCela", Vector3.new(2.2, 0.55, 1.4), -w / 2 + 2.4, 0.4, d / 2 - 2, C.Steel, true)
	stain(parent, frame, 1.2, 1.4, 4.4 + index % 3, 0.4 * index)
	if index % 3 == 0 then
		for i = 1, 3 do
			block(parent, frame, "GradeTorcida", Vector3.new(0.34, 7, 0.34), (i - 2) * 1.15, 3.4, -d / 2 + 0.3 - i * 0.2, C.Steel)
		end
	end
end

local function observationConsole(parent: Instance, frame: CFrame, index: number)
	block(parent, frame, "MesaObservacao", Vector3.new(5.6, 0.25, 2.4), 0, 2.85, 0, C.Steel, true)
	block(parent, frame, "CorpoObservacao", Vector3.new(5.2, 2.7, 2.1), 0, 1.4, 0.1, C.Dark, true)
	monitor(parent, frame, -1.3, 3.02, "CÂMARA " .. tostring(index))
	monitor(parent, frame, 1.3, 3.02, "SINAIS VITAIS")
	block(parent, frame, "CadeiraObservacao", Vector3.new(1.6, 0.22, 1.6), 0, 1.5, -2.3, C.Teal, true)
	block(parent, frame, "EncostoObservacao", Vector3.new(1.6, 1.7, 0.22), 0, 2.3, -3, C.Teal)
end

local function dissectionTable(parent: Instance, frame: CFrame, index: number)
	block(parent, frame, "PedestalMesa", Vector3.new(1.6, 2.5, 1.6), 0, 1.25, 0, C.Steel, true)
	block(parent, frame, "TampoMesa", Vector3.new(7.2, 0.3, 3.4), 0, 2.6, 0, C.Steel, true)
	block(parent, frame, "CanaletaMesa", Vector3.new(6.6, 0.1, 0.3), 0, 2.78, 1.5, C.Black, false, PLASTIC)
	for _, x in { -2.4, 2.4 } do
		block(parent, frame, "CorreiaMesa", Vector3.new(0.5, 0.16, 3.6), x, 2.82, 0, C.Dark)
	end
	block(parent, frame, "CarrinhoInstrumentos", Vector3.new(2.4, 0.18, 1.6), 4.9, 2.3, 0, C.Steel, true)
	for i = 1, 3 do
		block(parent, frame, "InstrumentoCirurgico", Vector3.new(0.14, 0.08, 1.1), 4.4 + i * 0.35, 2.44, 0, C.White)
	end
	block(parent, frame, "FocoCirurgico", Vector3.new(2.6, 0.45, 2.6), 0, 7.4, 0, C.White, false, PLASTIC)
	local bulb = block(parent, frame, "LampadaCirurgica", Vector3.new(2.2, 0.12, 2.2), 0, 7.14, 0, C.Glass, false, NEON)
	local light = Instance.new("PointLight")
	light.Color, light.Brightness, light.Range, light.Shadows = C.White, 1.1, 16, false
	light.Parent = bulb
	block(parent, frame, "HasteFoco", Vector3.new(0.22, 3.4, 0.22), 0, 9.2, 0, C.Steel)
	stain(parent, frame, 0, 2.6, 6 + index, 0.7 * index)
end

--[[
	TestHall(parent, floorFrame, room)
	A maior ala do laboratório. O Frog Generator fica de frente para a porta,
	as celas encostam nas duas paredes longas e o centro do salão continua
	livre para andar.
]]
function Furnishings.TestHall(parent: Instance, floorFrame: CFrame, room: any): Model
	local width, depth = room.X1 - room.X0, room.Z1 - room.Z0
	assert(width >= 48 and depth >= 48, "Salão de testes do Abismo precisa de pelo menos 48x48 studs")
	local model = Instance.new("Model")
	model.Name = "Mobiliario_Bioteste"
	model:SetAttribute("AbismoMobiliario", true)
	model.Parent = parent
	local halfX, halfZ = width / 2, depth / 2
	-- A porta fica na parede XMin: o corredor de acesso e o miolo ficam vazios.
	stripes(model, floorFrame, 13, 0, 11, 11)
	frogGenerator(model, floorFrame * CFrame.new(13, 0, 0))
	block(model, floorFrame, "RaloCentral", Vector3.new(4, 0.08, 4), 0, 0.04, 0, C.Black, false, METAL)
	for i = -2, 2 do
		block(model, floorFrame, "GrelhaRalo", Vector3.new(0.2, 0.1, 3.6), i * 0.7, 0.09, 0, C.Steel, false, METAL)
	end
	-- Celas nas duas paredes longas, viradas para dentro.
	local cell = 0
	for _, side in { -1, 1 } do
		for _, x in { -halfX + 16, 0, halfX - 20 } do
			cell += 1
			-- 5,6 studs da parede: as grades tortas da cela rompida ainda ficam dentro.
			containmentCell(model, floorFrame * CFrame.new(x, 0, side * (halfZ - 5.6)) * CFrame.Angles(0, if side < 0 then 0 else math.pi, 0), cell)
		end
	end
	-- Consoles de observação junto à porta, fora da varredura da folha.
	local desk = 0
	for _, side in { -1, 1 } do
		for _, offset in { 13, 24 } do
			desk += 1
			observationConsole(model, floorFrame * CFrame.new(-halfX + 5, 0, side * offset) * CFrame.Angles(0, -math.pi / 2, 0), desk)
		end
	end
	for _, side in { -1, 1 } do
		dissectionTable(model, floorFrame * CFrame.new(-12, 0, side * 22) * CFrame.Angles(0, if side < 0 then 0 else math.pi, 0), if side < 0 then 1 else 2)
	end
	-- Ponte rolante: trilho do fundo até a cápsula, com o guincho parado.
	for _, side in { -1, 1 } do
		block(model, floorFrame, "TrilhoPonte", Vector3.new(width - 14, 0.7, 0.7), 0, 16.2, side * 7.5, C.Dark)
	end
	block(model, floorFrame, "CarroPonte", Vector3.new(4.2, 1.2, 16.6), -4, 15.5, 0, C.Steel)
	block(model, floorFrame, "GuinchoPonte", Vector3.new(1.9, 3.4, 1.9), -4, 13.2, 0, C.Amber)
	-- O gancho fica bem acima da cabeça: ninguém passa dentro dele.
	S.Beam(model, "CaboGuincho", (floorFrame * CFrame.new(-4, 11.5, 0)).Position, (floorFrame * CFrame.new(-4, 9, 0)).Position, 0.16, METAL, C.Steel, false)
	block(model, floorFrame, "GanchoGuincho", Vector3.new(0.9, 1.3, 0.9), -4, 8.5, 0, C.Steel)
	-- Rastros do que escapou.
	stain(model, floorFrame, -20, 0, 9, 0.3)
	stain(model, floorFrame, -28, -8, 6, 1.1)
	stain(model, floorFrame, 2, 12, 7, 2.2)
	return model
end

return Furnishings
