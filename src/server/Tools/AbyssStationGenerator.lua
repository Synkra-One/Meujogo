--!strict
--[[
	AbyssStationGenerator (ferramenta de editor)
	A ESTAÇÃO ABISMO: um laboratório subterrâneo abandonado sob a floresta,
	com uma rota de fuga que termina numa caverna costeira dentro d'água.

		FLORESTA
		  v  escotilha escondida entre árvores e pedras
		POÇO DE ACESSO (escada de treliça)
		  v
		NÍVEL -1  eclusa/vestiário
		  v  caixa de escada fechada
		NÍVEL -2  átrio, corredor, LABORATÓRIO, CONTROLE, ALA CLÍNICA
		  v  câmara de bombas
		TÚNEL DE EVACUAÇÃO (ACESSO MARÍTIMO) -- vai degradando
		  v  comporta estanque
		TRECHO ALAGADO (nada-se)
		  v  grade antiga
		CAVERNA COSTEIRA -> OCEANO

	USO (Command Bar do Studio, em MODO DE EDIÇÃO, e salve depois):
		local Abismo = require(game.ServerScriptService.Server.Tools.AbyssStationGenerator)
		Abismo.Build()
		Abismo.Clear()

	Roda DEPOIS de IslandGenerator.Generate() -- precisa do terreno pra achar
	a costa, medir o chão e cavar.

	TUDO TAMPADO (por que existe wallX/wallZ/slab e a passagem de ROCHA)
	  Nenhuma superfície de ambiente pode ser terreno: o jogador não vê terra,
	  areia nem grama em lugar nenhum da instalação. Duas garantias, porque
	  uma só não basta:
	    1. cada ambiente é uma CASCA FECHADA de Parts -- piso, teto e as
	       quatro paredes, e todo vão entre ambientes é emoldurado (as
	       paredes vão em segmentos com verga, nunca "some" um pedaço);
	    2. antes de cavar, o miolo em volta da instalação inteira vira ROCHA.
	       Se sobrar qualquer fresta de voxel entre o acabamento e o terreno,
	       o que aparece é pedra -- nunca o barro da floresta ou a areia da
	       praia. O topo desse preenchimento fica ~9 studs abaixo da
	       superfície (amostrada por raycast) pra não brotar mancha de rocha
	       no meio do mato.
	  A caverna costeira é a única área de rocha exposta, e é de propósito:
	  ali a estação já acabou.

	ORÇAMENTO VERTICAL (por que os níveis são estes)
	  IslandLayout.CONFIG.MinY = -24: abaixo disso NÃO EXISTE terreno. Tudo
	  que é cavado precisa caber entre MinY e a superfície, com folga em
	  cima pra nenhuma parede aparecer do lado de fora:
	      Nível -1   piso  -4   teto  +8   (findSite exige chão >= +18)
	      Nível -2   piso -18   teto  -6   (~12 de rocha sob a praia)
	      Caverna    piso -20   teto  +8   (dentro do promontório de rocha)
	  A praia é um platô em +8..+12 e o fundo do mar despenca pra -20/-22 a
	  um stud da linha d'água (IslandLayout.rawHeight), então a boca da
	  caverna abre direto em água funda.

	ÁGUA: o trecho final é alagado de propósito -- o teto dele fica muito
	abaixo do nível do mar, então "cheio d'água" é o estado coerente. As
	poças do trecho seco são infiltração (volumes isolados, rasos). A
	comporta estanque é o que separa os dois. A água de terreno é preenchida
	só até o TETO do vazio escavado, pra não deixar bolsão de água preso
	dentro da rocha.

	ASSETS DO TOOLBOX (ver ASSETS, abaixo)
	  O mobiliário do laboratório e da ala clínica vem de modelos reais; o
	  que eu construo é a casca que os contém e sela. Cada asset é usado de
	  duas formas: inteiro no ambiente principal dele, e despedaçado em
	  props avulsos espalhados nos outros ambientes. Se um asset não carregar
	  (InsertService só funciona direito em modo de edição), o ambiente cai
	  no mobiliário procedural de reserva -- a estação nunca fica vazia.

	PRONTO PRA DEPOIS (nada disso é implementado aqui, só a arquitetura):
	  Attribute "AbismoZona" em marcadores por área  -- Escotilha, Poco,
	    NivelMenos1, NivelMenos2, Bombas, Tunel, Alagado, Caverna, Mar
	  Attribute "AbismoAlagavel" + "NivelAguaCheio"  -- áreas que um sistema
	    de inundação futuro pode encher
	  Attribute "AbismoPortaPrincipal" na escotilha  -- pra bloquear a saída
	  Attribute "Porta" (DoorSystem) nas portas, comporta e grade
	  PontoLoot pros itens (ItemSpawner)
]]

local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")
local InsertService = game:GetService("InsertService")
local Terrain = Workspace.Terrain

local S = require(script.Parent.Structures)
local Layout = require(script.Parent.IslandLayout)

local AbyssStationGenerator = {}

local part = S.Part
local beam = S.Beam
local TAU = math.pi * 2

--------------------------------------------------------------------------------
-- Medidas
--------------------------------------------------------------------------------

--[[
	Eixo z local: 0 = eixo do poço de acesso, crescendo rumo ao mar.
	DistanciaDaCosta é onde fica o z = 178 (a linha d'água), então a
	escotilha nasce 178 studs terra adentro -- 133 deles dentro da floresta,
	porque a praia tem 45 de largura.
]]
local CONFIG = {
	DistanciaDaCosta = 178,

	NivelMenos1 = -4,
	NivelMenos2 = -18,
	AlturaSala = 12,
	AlturaPorta = 9,
	PisoCaverna = -20,
	TetoCaverna = 8,

	-- Nível -1 (eclusa/vestiário) e a caixa de escada.
	EclusaZ0 = -13,
	EclusaZ1 = 19,
	EclusaX = 12,
	EscadaZ1 = 40,
	EscadaX = 7,

	-- Nível -2.
	AtrioZ1 = 54,
	AtrioX = 14,
	CorredorZ1 = 112,
	CorredorX = 7,

	LabX = 40, -- parede do fundo, à esquerda (x negativo)
	LabZ0 = 60,
	LabZ1 = 92,
	LabPortaZ0 = 62,
	LabPortaZ1 = 70,

	CtrlX = 30, -- à direita (x positivo)
	CtrlZ0 = 58,
	CtrlZ1 = 78,
	CtrlPortaZ0 = 64,
	CtrlPortaZ1 = 71,

	ClinX = 28, -- à direita
	ClinZ0 = 84,
	ClinZ1 = 106,
	ClinPortaZ0 = 86,
	ClinPortaZ1 = 92,

	BombasZ1 = 124,
	BombasX = 13,

	-- Túnel de evacuação, comporta e trecho alagado.
	TunelZ1 = 152, -- aqui fica a comporta estanque
	AlagadoZ1 = 170,
	LarguraTunel = 8,

	-- Caverna costeira.
	CavernaZ0 = 170,
	CavernaZ1 = 186,
	BocaZ = 188,
}

AbyssStationGenerator.CONFIG = CONFIG

-- Modelos do Toolbox. Ver o bloco "ASSETS DO TOOLBOX" no topo.
local ASSETS = {
	Laboratorio = 1105615633, -- cenário de laboratório (com sangue)
	Porta = 4590494732, -- porta de laboratório
	Complexo = 12470367049, -- segundo conjunto de laboratório
}

AbyssStationGenerator.ASSETS = ASSETS

local COL = {
	Concreto = Color3.fromRGB(126, 124, 118),
	ConcretoSujo = Color3.fromRGB(96, 94, 88),
	ConcretoVelho = Color3.fromRGB(78, 76, 71),
	Azulejo = Color3.fromRGB(158, 162, 158),
	Aco = Color3.fromRGB(112, 118, 122),
	AcoEscuro = Color3.fromRGB(64, 70, 74),
	Ferrugem = Color3.fromRGB(118, 68, 38),
	FerrugemClara = Color3.fromRGB(146, 92, 52),
	Cano = Color3.fromRGB(96, 102, 100),
	CanoVerde = Color3.fromRGB(72, 96, 82),
	Cabo = Color3.fromRGB(32, 32, 34),
	Umidade = Color3.fromRGB(58, 66, 58),
	Musgo = Color3.fromRGB(62, 82, 54),
	Sangue = Color3.fromRGB(78, 14, 12),
	SangueVelho = Color3.fromRGB(52, 16, 14),
	Lampada = Color3.fromRGB(255, 236, 186),
	Vidro = Color3.fromRGB(150, 180, 186),
	Placa = Color3.fromRGB(206, 180, 52),
	PlacaTexto = Color3.fromRGB(26, 24, 18),
	Rocha = Color3.fromRGB(82, 80, 76),
	Agua = Color3.fromRGB(38, 70, 78),
}

local DECO = { CanCollide = false, CastShadow = false }

--------------------------------------------------------------------------------
-- Utilidades de espaço
--------------------------------------------------------------------------------

local terrainRay = RaycastParams.new()
terrainRay.FilterType = Enum.RaycastFilterType.Include
terrainRay.FilterDescendantsInstances = { Terrain }
terrainRay.IgnoreWater = true

local function groundY(x: number, z: number): number
	local hit = Workspace:Raycast(Vector3.new(x, 400, z), Vector3.new(0, -900, 0), terrainRay)
	if hit then
		return hit.Position.Y
	end
	return Layout.Height(x, z)
end

local function getIlha(): Folder
	local ilha = Workspace:FindFirstChild("Ilha")
	if ilha and ilha:IsA("Folder") then
		return ilha
	end
	local folder = Instance.new("Folder")
	folder.Name = "Ilha"
	folder.Parent = Workspace
	return folder
end

export type Frame = {
	Origin: Vector3, -- escotilha, no chão
	Sea: Vector3, -- unitário horizontal apontando pro mar
	Side: Vector3,
	SurfaceY: number,
}

-- Coordenada local: x = lateral, y = Y ABSOLUTO, z = distância rumo ao mar.
local function at(f: Frame, x: number, y: number, z: number): Vector3
	local p = f.Origin + f.Side * x + f.Sea * z
	return Vector3.new(p.X, y, p.Z)
end

-- CFrame com a FRENTE (LookVector) apontando pro mar. O eixo Z local é
-- paralelo ao túnel e o X local à lateral, então Vector3.new(sx, sy, sz) num
-- Part colocado aqui já sai alinhado ao corredor.
local function cfAt(f: Frame, x: number, y: number, z: number, yaw: number?): CFrame
	local pos = at(f, x, y, z)
	local base = CFrame.lookAt(pos, pos + f.Sea)
	return if yaw then base * CFrame.Angles(0, yaw, 0) else base
end

-- Mundo -> coordenada local (usado pra saber se um Part de asset invade um vão).
local function localOf(f: Frame, p: Vector3): Vector3
	local d = p - f.Origin
	return Vector3.new(d:Dot(f.Side), p.Y, d:Dot(f.Sea))
end

--------------------------------------------------------------------------------
-- Terreno
--------------------------------------------------------------------------------

local AIR, ROCK, WATER = Enum.Material.Air, Enum.Material.Rock, Enum.Material.Water

-- Caixa alinhada ao eixo do túnel (não ao mundo): evita escada de voxel nas
-- diagonais e deixa o corredor reto de verdade.
local function fillBox(f: Frame, material: Enum.Material, x: number, y: number, z: number, sx: number, sy: number, sz: number)
	if sx <= 0.1 or sy <= 0.1 or sz <= 0.1 then
		return
	end
	local pos = at(f, x, y, z)
	local cf = CFrame.lookAt(pos, pos + f.Sea)
	Terrain:FillBlock(cf, Vector3.new(sx, sy, sz), material)
end

-- Caixa por CANTOS, que é como os volumes deste arquivo são pensados.
local function box(f: Frame, material: Enum.Material, x0: number, x1: number, y0: number, y1: number, z0: number, z1: number)
	fillBox(f, material, (x0 + x1) / 2, (y0 + y1) / 2, (z0 + z1) / 2, x1 - x0, y1 - y0, z1 - z0)
end

local function fillBall(f: Frame, material: Enum.Material, x: number, y: number, z: number, r: number)
	Terrain:FillBall(at(f, x, y, z), r, material)
end

--------------------------------------------------------------------------------
-- Escolha do sítio: floresta perto do litoral
--------------------------------------------------------------------------------

--[[
	findSite()
	Varre a costa procurando uma direção onde exista FLORESTA de verdade
	entre a escotilha e o mar. Rejeita:
	  - montanha (a caverna do Monstro já mora lá, e o relevo estraga o poço);
	  - clareiras/POIs/trilhas/lago (IsClearAt) -- o pedido era floresta;
	  - chão baixo demais (precisa de rocha acima do teto do Nível -1);
	  - qualquer ponto do caminho até a praia que não seja floresta.
	Devolve nil se a ilha não tiver nenhum trecho de costa assim.
]]
local function findSite(): Frame?
	Layout.Plan()

	local seed = Layout.Seed()
	local startAngle = (seed % 360) * math.pi / 180
	-- +12: o vazio do Nível -1 vai até y = n1 + h + 2, e ainda precisa sobrar
	-- rocha acima dele pra nenhuma laje aflorar no meio da floresta.
	local minGround = CONFIG.NivelMenos1 + CONFIG.AlturaSala + 12

	for i = 0, 71 do
		local angle = startAngle + (i * 5) * math.pi / 180
		local coast = Layout.CoastRadiusAt(angle)
		local dist = coast - CONFIG.DistanciaDaCosta
		if dist < 110 then
			continue -- costa curta demais: a escotilha cairia quase no centro
		end

		local dirX, dirZ = math.cos(angle), math.sin(angle)
		local hx, hz = dirX * dist, dirZ * dist

		local ok = Layout.MountainContribution(hx, hz) < 4
			and not Layout.IsClearAt(hx, hz, 22)
			and groundY(hx, hz) >= minGround

		-- O caminho inteiro até a praia precisa ser floresta: o túnel passa
		-- por baixo, mas a escotilha não pode ficar num corredor de trilha
		-- nem coberta por uma clareira de POI.
		if ok then
			for step = 1, 9 do
				local d = dist + (CONFIG.DistanciaDaCosta - 10) * (step / 9)
				local px, pz = dirX * d, dirZ * d
				if Layout.MountainContribution(px, pz) > 8 or Layout.IsClearAt(px, pz, 10) then
					ok = false
					break
				end
			end
		end

		if ok then
			local origin = Vector3.new(hx, groundY(hx, hz), hz)
			local sea = Vector3.new(dirX, 0, dirZ).Unit -- pra fora da ilha = pro mar
			return {
				Origin = origin,
				Sea = sea,
				Side = Vector3.new(-sea.Z, 0, sea.X),
				SurfaceY = origin.Y,
			}
		end
	end
	return nil
end

--------------------------------------------------------------------------------
-- Escavação
--------------------------------------------------------------------------------

--[[
	envelopeHalfWidth(z)
	Meia-largura da casca de rocha por trecho. O miolo do Nível -2 é largo
	(o laboratório vai até x = -43), o túnel é estreito -- não adianta
	converter meia ilha em pedra.
]]
local function envelopeHalfWidth(z: number): number
	local C = CONFIG
	if z < C.EclusaZ1 then
		return 22
	elseif z < C.AtrioZ1 then
		return 24
	elseif z < C.CorredorZ1 then
		return 48
	elseif z < C.BombasZ1 then
		return 22
	end
	return 14
end

--[[
	encaseRock(f)
	Envolve a instalação inteira em ROCHA ANTES de cavar. É a segunda
	garantia do "tudo tampado": mesmo que apareça uma fresta de voxel entre o
	acabamento e o terreno, o que se vê é pedra, nunca terra/areia/grama.

	Amostra TODAS as alturas do chão primeiro e só depois preenche -- se
	intercalasse, os raycasts seguintes bateriam na rocha recém-criada.
]]
local function encaseRock(f: Frame)
	local C = CONFIG
	local step = 12
	local z0 = C.EclusaZ0 - 8
	local z1 = C.AlagadoZ1

	local samples: { { z: number, top: number, half: number } } = {}
	for z = z0, z1, step do
		local half = envelopeHalfWidth(z)
		local lowest = math.huge
		for _, sx in { -1, -0.5, 0, 0.5, 1 } do
			local p = at(f, sx * half, 0, z + step / 2)
			lowest = math.min(lowest, groundY(p.X, p.Z))
		end
		table.insert(samples, { z = z, top = lowest - 9, half = half })
	end

	for _, s in samples do
		box(f, ROCK, -s.half, s.half, -23, s.top, s.z - 2, s.z + step + 2)
	end

	-- PROMONTÓRIO DA COSTA: a caverna é cavada DENTRO dele, então ele precisa
	-- existir antes de tudo (e o mar ali já está em -20/-22, não há rocha
	-- natural nenhuma pra cavar). A base submersa é uma caixa; o que aparece
	-- acima da água são bolas, pra não virar um paralelepípedo na praia.
	box(f, ROCK, -22, 22, -23, -2, C.CavernaZ0 - 10, C.BocaZ + 16)
	fillBall(f, ROCK, 0, 2, C.CavernaZ0 + 2, 14)
	fillBall(f, ROCK, 0, 2, C.CavernaZ1 - 2, 14)
	fillBall(f, ROCK, -11, 0, C.CavernaZ0 + 8, 12)
	fillBall(f, ROCK, 11, 0, C.CavernaZ0 + 10, 12)
	fillBall(f, ROCK, 0, -2, C.BocaZ + 2, 12)
	fillBall(f, ROCK, -9, -4, C.BocaZ + 8, 10)
	fillBall(f, ROCK, 9, -3, C.BocaZ + 7, 10)
end

--[[
	carve(f)
	Abre TODO o vazio no terreno de uma vez, antes de construir qualquer
	Part. Cada volume é cavado com folga (as paredes são Parts montadas por
	dentro, então a rocha nunca encosta no acabamento).
]]
local function carve(f: Frame)
	local C = CONFIG
	local n1, n2, h = C.NivelMenos1, C.NivelMenos2, C.AlturaSala
	local teto1, teto2 = n1 + h + 2, n2 + h + 2
	local piso1, piso2 = n1 - 1.5, n2 - 1.5

	encaseRock(f)

	-- Poço de acesso: caixa, não cilindro -- o revestimento é quadrado, e
	-- caixa contra caixa não deixa canto de voxel exposto.
	box(f, AIR, -8, 8, n1, f.SurfaceY + 3, -8, 8)

	-- Nível -1 (eclusa) e a caixa de escada que desce pro Nível -2.
	box(f, AIR, -15, 15, piso1, teto1, C.EclusaZ0 - 3, C.EclusaZ1 + 3)
	-- A caixa de escada desce 2 studs abaixo do piso do Nível -2: o degrau
	-- mais baixo tem 1,4 de espessura (encavala no seguinte) e precisa caber.
	box(f, AIR, -9.5, 9.5, n2 - 2, teto1, C.EclusaZ1 - 1, C.EscadaZ1 + 2)

	-- Nível -2: átrio, corredor e as três salas.
	box(f, AIR, -17, 17, piso2, teto2, C.EscadaZ1 - 2, C.AtrioZ1 + 2)
	box(f, AIR, -10, 10, piso2, teto2, C.AtrioZ1 - 2, C.CorredorZ1 + 2)
	box(f, AIR, -C.LabX - 3, -6, piso2, teto2, C.LabZ0 - 3, C.LabZ1 + 3)
	box(f, AIR, 6, C.CtrlX + 3, piso2, teto2, C.CtrlZ0 - 3, C.CtrlZ1 + 3)
	box(f, AIR, 6, C.ClinX + 3, piso2, teto2, C.ClinZ0 - 3, C.ClinZ1 + 3)
	box(f, AIR, -16, 16, piso2, teto2, C.CorredorZ1 - 2, C.BombasZ1 + 2)

	-- Túnel de evacuação e trecho alagado (mesma seção, o que muda é a água).
	box(f, AIR, -7, 7, piso2, teto2 - 0.5, C.BombasZ1 - 2, C.TunelZ1 + 2)
	box(f, AIR, -7, 7, piso2, teto2 - 0.5, C.TunelZ1 - 2, C.AlagadoZ1 + 2)

	-- Caverna costeira, dentro do promontório.
	box(f, AIR, -11, 11, C.PisoCaverna, C.TetoCaverna, C.CavernaZ0 - 2, C.CavernaZ1 + 2)
	fillBall(f, AIR, -5, -8, C.CavernaZ0 + 5, 9)
	fillBall(f, AIR, 4, -3, C.CavernaZ0 + 13, 9)

	-- Boca: fresta alta e estreita, com o topo acima da linha d'água pra ser
	-- vista do mar como uma sombra entre as pedras.
	-- Dois trechos, e os DOIS sobem até +7 (3 acima do mar). Se o trecho de
	-- fora parasse na linha d'água, a fresta visível ficaria enterrada no
	-- promontório e ninguém acharia a saída vindo do mar. O segundo passa de
	-- z = BocaZ + 16, onde a rocha artificial acaba, pra não sobrar um lábio
	-- de pedra fechando a saída.
	box(f, AIR, -4.5, 4.5, -18, 7, C.BocaZ - 4, C.BocaZ + 9)
	box(f, AIR, -6, 6, -18, 7, C.BocaZ + 6, C.BocaZ + 18)

	-- ÁGUA. Preenchida só até o TETO do vazio escavado: se subisse até o
	-- nível do mar, deixaria um bolsão de água preso dentro da rocha acima do
	-- túnel. O trecho alagado + caverna + boca formam um volume contínuo até
	-- o mar aberto, e o teto do trecho alagado (-6) está muito abaixo do mar
	-- (+4) -- é isso que obriga a nadar.
	local seaLevel = Layout.CONFIG.SeaLevel
	box(f, WATER, -7, 7, piso2, teto2 - 0.5, C.TunelZ1 + 1, C.AlagadoZ1 + 2)
	box(f, WATER, -11, 11, C.PisoCaverna, seaLevel, C.CavernaZ0 - 1, C.CavernaZ1 + 2)
	box(f, WATER, -6, 6, -18, seaLevel, C.BocaZ - 3, C.BocaZ + 18)
end

--------------------------------------------------------------------------------
-- Casca: paredes segmentadas e lajes
--------------------------------------------------------------------------------

-- Vão numa parede, em coordenada AO LONGO da parede (a) e em Y absoluto.
type Vao = { a0: number, a1: number, y0: number, y1: number }

--[[
	wallSegments(...)
	Recorta a faixa [a0, a1] x [yFloor, yTop] nos retângulos cheios que
	sobram depois dos vãos. É daqui que sai a garantia de "nenhum pedaço
	some": todo vão vira peitoril embaixo + verga em cima, e o resto da
	parede continua inteiro. Devolve { {a0, a1, y0, y1}, ... }.
]]
local function wallSegments(a0: number, a1: number, yFloor: number, yTop: number, vaos: { Vao }?): { { number } }
	local out: { { number } } = {}
	if a1 - a0 <= 0.02 or yTop - yFloor <= 0.02 then
		return out
	end
	if not vaos or #vaos == 0 then
		return { { a0, a1, yFloor, yTop } }
	end

	local sorted = table.clone(vaos)
	table.sort(sorted, function(p, q)
		return p.a0 < q.a0
	end)

	local cursor = a0
	for _, v in sorted do
		local g0 = math.max(v.a0, cursor)
		local g1 = math.min(v.a1, a1)
		if g1 - g0 <= 0.02 then
			continue
		end
		if g0 - cursor > 0.02 then
			table.insert(out, { cursor, g0, yFloor, yTop })
		end
		local gy0 = math.clamp(v.y0, yFloor, yTop)
		local gy1 = math.clamp(v.y1, yFloor, yTop)
		if gy0 - yFloor > 0.02 then
			table.insert(out, { g0, g1, yFloor, gy0 })
		end
		if yTop - gy1 > 0.02 then
			table.insert(out, { g0, g1, gy1, yTop })
		end
		cursor = g1
	end
	if a1 - cursor > 0.02 then
		table.insert(out, { cursor, a1, yFloor, yTop })
	end
	return out
end

-- Parede no plano x = const, correndo em z de z0 a z1.
local function wallX(parent: Instance, f: Frame, x: number, z0: number, z1: number, yFloor: number, yTop: number, color: Color3, vaos: { Vao }?, thickness: number?, material: Enum.Material?)
	local t = thickness or 0.8
	for _, seg in wallSegments(z0, z1, yFloor, yTop, vaos) do
		part(parent, "Parede", Vector3.new(t, seg[4] - seg[3], seg[2] - seg[1]), cfAt(f, x, (seg[3] + seg[4]) / 2, (seg[1] + seg[2]) / 2), material or Enum.Material.Concrete, color)
	end
end

-- Parede no plano z = const, correndo em x de x0 a x1.
local function wallZ(parent: Instance, f: Frame, z: number, x0: number, x1: number, yFloor: number, yTop: number, color: Color3, vaos: { Vao }?, thickness: number?, material: Enum.Material?)
	local t = thickness or 0.8
	for _, seg in wallSegments(x0, x1, yFloor, yTop, vaos) do
		part(parent, "Parede", Vector3.new(seg[2] - seg[1], seg[4] - seg[3], t), cfAt(f, (seg[1] + seg[2]) / 2, (seg[3] + seg[4]) / 2, z), material or Enum.Material.Concrete, color)
	end
end

-- Laje horizontal. `y` é a face SUPERIOR se for piso, a INFERIOR se for teto.
local function slab(parent: Instance, f: Frame, name: string, x0: number, x1: number, z0: number, z1: number, y: number, isCeiling: boolean, color: Color3, thickness: number?)
	if x1 - x0 <= 0.02 or z1 - z0 <= 0.02 then
		return
	end
	local t = thickness or 0.8
	local cy = if isCeiling then y + t / 2 else y - t / 2
	part(parent, name, Vector3.new(x1 - x0, t, z1 - z0), cfAt(f, (x0 + x1) / 2, cy, (z0 + z1) / 2), Enum.Material.Concrete, color)
end

-- Laje com um buraco retangular no meio (teto do Nível -1, por onde o poço
-- desce). Sai em quatro retângulos que se encontram sem fresta.
local function slabWithHole(parent: Instance, f: Frame, name: string, x0: number, x1: number, z0: number, z1: number, hx0: number, hx1: number, hz0: number, hz1: number, y: number, isCeiling: boolean, color: Color3)
	slab(parent, f, name, x0, x1, z0, hz0, y, isCeiling, color)
	slab(parent, f, name, x0, x1, hz1, z1, y, isCeiling, color)
	slab(parent, f, name, x0, hx0, hz0, hz1, y, isCeiling, color)
	slab(parent, f, name, hx1, x1, hz0, hz1, y, isCeiling, color)
end

--[[
	roomShell(...)
	Casca fechada de um ambiente retangular. `skip` desliga a parede de um
	lado quando ela pertence ao vizinho (a parede do corredor já é a parede
	da sala -- construir as duas deixaria o vão tapado, que foi exatamente o
	bug da versão anterior).
]]
type ShellSpec = {
	x0: number,
	x1: number,
	z0: number,
	z1: number,
	y: number,
	h: number,
	color: Color3,
	name: string?,
	vaosXMin: { Vao }?,
	vaosXMax: { Vao }?,
	vaosZMin: { Vao }?,
	vaosZMax: { Vao }?,
	semXMin: boolean?,
	semXMax: boolean?,
	semZMin: boolean?,
	semZMax: boolean?,
	semPiso: boolean?,
	semTeto: boolean?,
}

local function roomShell(parent: Instance, f: Frame, spec: ShellSpec)
	local y, top = spec.y, spec.y + spec.h
	local tetoCor = spec.color:Lerp(Color3.new(0, 0, 0), 0.28)
	local nome = spec.name or "Sala"

	if not spec.semPiso then
		slab(parent, f, "Piso" .. nome, spec.x0, spec.x1, spec.z0, spec.z1, y, false, spec.color)
	end
	if not spec.semTeto then
		slab(parent, f, "Teto" .. nome, spec.x0, spec.x1, spec.z0, spec.z1, top, true, tetoCor)
	end
	if not spec.semXMin then
		wallX(parent, f, spec.x0, spec.z0, spec.z1, y, top, spec.color, spec.vaosXMin)
	end
	if not spec.semXMax then
		wallX(parent, f, spec.x1, spec.z0, spec.z1, y, top, spec.color, spec.vaosXMax)
	end
	if not spec.semZMin then
		wallZ(parent, f, spec.z0, spec.x0, spec.x1, y, top, spec.color, spec.vaosZMin)
	end
	if not spec.semZMax then
		wallZ(parent, f, spec.z1, spec.x0, spec.x1, y, top, spec.color, spec.vaosZMax)
	end
end

--------------------------------------------------------------------------------
-- Peças de acabamento: placas, lâmpadas, canos, umidade, poças, sangue
--------------------------------------------------------------------------------

-- Placa industrial com texto de verdade (SurfaceGui, sem asset).
local function sign(parent: Instance, cf: CFrame, width: number, height: number, title: string, subtitle: string?, color: Color3?)
	local plate = part(parent, "Placa", Vector3.new(width, height, 0.16), cf, Enum.Material.Metal, color or COL.Placa, { CanCollide = false })
	local gui = Instance.new("SurfaceGui")
	gui.Name = "Texto"
	gui.Face = Enum.NormalId.Front
	gui.CanvasSize = Vector2.new(math.floor(width * 44), math.floor(height * 44))
	gui.LightInfluence = 0.75
	gui.MaxDistance = 90
	gui.Parent = plate

	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, if subtitle then 0.6 else 1)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamBold
	label.Text = title
	label.TextColor3 = COL.PlacaTexto
	label.TextScaled = true
	label.Parent = gui

	if subtitle then
		local sub = Instance.new("TextLabel")
		sub.Size = UDim2.fromScale(1, 0.4)
		sub.Position = UDim2.fromScale(0, 0.6)
		sub.BackgroundTransparency = 1
		sub.Font = Enum.Font.Gotham
		sub.Text = subtitle
		sub.TextColor3 = COL.PlacaTexto
		sub.TextScaled = true
		sub.Parent = gui
	end
	return plate
end

--[[
	lamp(parent, cf, decay, rng)
	Luminária de teto em gaiola. `decay` 0..1 decide a chance de estar
	queimada: perto do mar quase nenhuma acende, que é o que faz o túnel
	escurecer conforme você avança.
]]
local function lamp(parent: Instance, cf: CFrame, decay: number, rng: Random)
	local dead = rng:NextNumber() < decay * 0.75
	local body = part(parent, "Luminaria", Vector3.new(2.4, 0.4, 0.9), cf, Enum.Material.Metal, COL.AcoEscuro, DECO)
	local tube = part(parent, "Tubo", Vector3.new(2, 0.3, 0.55), cf * CFrame.new(0, -0.3, 0), if dead then Enum.Material.Glass else Enum.Material.Neon, if dead then COL.Vidro else COL.Lampada, DECO)
	tube.Transparency = if dead then 0.5 else 0.15

	for i = -1, 1 do
		part(parent, "Grade", Vector3.new(0.08, 0.5, 0.08), cf * CFrame.new(i * 0.9, -0.3, 0.3), Enum.Material.Metal, COL.Ferrugem, DECO)
	end

	if not dead then
		local light = Instance.new("PointLight")
		light.Color = COL.Lampada
		-- Fraca de propósito: "lâmpadas fracas" era parte do pedido, e luz
		-- baixa é o que faz a lanterna do jogador valer alguma coisa.
		light.Brightness = 0.6 - decay * 0.25
		light.Range = 18 - decay * 6
		light.Shadows = false
		light.Parent = tube
	end
	return body
end

-- Cano com barriga entre dois pontos (não uso reta pura: denuncia Part).
local function pipeRun(parent: Instance, a: Vector3, b: Vector3, dia: number, color: Color3, sag: number)
	local steps = 4
	local prev = a
	for i = 1, steps do
		local t = i / steps
		local p = a:Lerp(b, t) - Vector3.new(0, math.sin(t * math.pi) * sag, 0)
		beam(parent, "Cano", prev, p, dia, Enum.Material.Metal, color, false)
		prev = p
	end
end

-- Mancha de umidade/mofo numa parede. Várias sobrepostas pra não virar
-- retângulo, do mesmo jeito que o sangue da caverna do Monstro.
local function moisture(parent: Instance, cf: CFrame, scale: number, rng: Random)
	for i = 1, rng:NextInteger(2, 4) do
		local w = scale * rng:NextNumber(0.4, 1.1)
		local h = scale * rng:NextNumber(0.5, 1.4)
		local p = part(
			parent,
			"Umidade",
			Vector3.new(w, h, 0.08),
			cf * CFrame.new(scale * rng:NextNumber(-0.4, 0.4), scale * rng:NextNumber(-0.3, 0.3), 0.02),
			Enum.Material.Slate,
			if i == 1 then COL.Umidade else COL.Musgo,
			DECO
		)
		p.Transparency = 0.25
	end
	for i = 1, rng:NextInteger(1, 3) do
		part(parent, "Escorrido", Vector3.new(rng:NextNumber(0.1, 0.3), scale * rng:NextNumber(0.8, 2), 0.07), cf * CFrame.new(scale * rng:NextNumber(-0.5, 0.5), -scale * 0.9, 0.03), Enum.Material.Slate, COL.Umidade, DECO)
	end
end

-- Rachadura no concreto.
local function crack(parent: Instance, cf: CFrame, length: number, rng: Random)
	local segments = rng:NextInteger(2, 4)
	local cursor = cf
	for i = 1, segments do
		local seg = length / segments
		cursor = cursor * CFrame.Angles(0, 0, rng:NextNumber(-0.5, 0.5))
		part(parent, "Rachadura", Vector3.new(0.09, seg, 0.06), cursor * CFrame.new(0, -seg / 2, 0.02), Enum.Material.SmoothPlastic, Color3.fromRGB(38, 36, 34), DECO)
		cursor = cursor * CFrame.new(0, -seg, 0)
	end
end

-- Poça no chão: água PARADA de infiltração (isolada, rasa). A água que
-- conecta com o mar é terreno, não isto.
local function puddle(parent: Instance, center: Vector3, radius: number, rng: Random)
	local disc = part(parent, "Poca", Vector3.new(radius * 2, 0.12, radius * 2 * rng:NextNumber(0.7, 1.1)), CFrame.new(center + Vector3.new(0, 0.08, 0)) * CFrame.Angles(0, rng:NextNumber(0, TAU), 0), Enum.Material.SmoothPlastic, COL.Agua, DECO)
	disc.Reflectance = 0.32
	disc.Transparency = 0.25
	for i = 1, rng:NextInteger(1, 3) do
		local ang = rng:NextNumber(0, TAU)
		local d = radius * rng:NextNumber(0.6, 1.3)
		local lobe = part(parent, "PocaBorda", Vector3.new(radius * rng:NextNumber(0.5, 1.1), 0.11, radius * rng:NextNumber(0.5, 1.1)), CFrame.new(center + Vector3.new(math.cos(ang) * d, 0.07, math.sin(ang) * d)) * CFrame.Angles(0, rng:NextNumber(0, TAU), 0), Enum.Material.SmoothPlastic, COL.Agua, DECO)
		lobe.Reflectance = 0.3
		lobe.Transparency = 0.3
	end
end

-- Gotejamento: fio d'água caindo do teto + respingo no chão.
local function drip(parent: Instance, top: Vector3, floorY: number, rng: Random)
	local height = top.Y - floorY
	if height < 1 then
		return
	end
	local p = part(parent, "Gotejamento", Vector3.new(0.08, height, 0.08), CFrame.new(top - Vector3.new(0, height / 2, 0)), Enum.Material.Glass, COL.Agua, DECO)
	p.Transparency = 0.55
	puddle(parent, Vector3.new(top.X, floorY, top.Z), rng:NextNumber(1, 2.2), rng)
end

-- Poça de sangue seco no chão (mesma técnica da caverna do Monstro: lobos
-- sobrepostos, senão vira um disco liso).
local function bloodPool(parent: Instance, center: Vector3, radius: number, rng: Random)
	for i = 1, rng:NextInteger(3, 5) do
		local ang = rng:NextNumber(0, TAU)
		local d = if i == 1 then 0 else radius * rng:NextNumber(0.3, 0.9)
		local s = radius * rng:NextNumber(0.6, 1.2)
		local p = part(parent, "PocaSangue", Vector3.new(s, 0.08, s * rng:NextNumber(0.6, 1.1)), CFrame.new(center + Vector3.new(math.cos(ang) * d, 0.05, math.sin(ang) * d)) * CFrame.Angles(0, rng:NextNumber(0, TAU), 0), Enum.Material.SmoothPlastic, if i == 1 then COL.Sangue else COL.SangueVelho, DECO)
		p.Reflectance = 0.06
	end
end

-- Respingo de sangue numa parede + arrasto descendo.
local function bloodSplat(parent: Instance, cf: CFrame, scale: number, rng: Random)
	for i = 1, rng:NextInteger(2, 4) do
		part(parent, "MarcaSangue", Vector3.new(scale * rng:NextNumber(0.3, 1), scale * rng:NextNumber(0.3, 1.1), 0.07), cf * CFrame.new(scale * rng:NextNumber(-0.5, 0.5), scale * rng:NextNumber(-0.4, 0.4), 0.02), Enum.Material.SmoothPlastic, if i == 1 then COL.Sangue else COL.SangueVelho, DECO)
	end
	for i = 1, rng:NextInteger(1, 3) do
		part(parent, "Escorrido", Vector3.new(rng:NextNumber(0.08, 0.22), scale * rng:NextNumber(0.8, 2.2), 0.06), cf * CFrame.new(scale * rng:NextNumber(-0.5, 0.5), -scale * 0.9, 0.03), Enum.Material.SmoothPlastic, COL.SangueVelho, DECO)
	end
end

local function marker(parent: Instance, name: string, pos: Vector3, attrs: { [string]: any }): Part
	return S.Marker(parent, name, CFrame.new(pos), attrs)
end

--------------------------------------------------------------------------------
-- Assets do Toolbox
--------------------------------------------------------------------------------

--[[
	Carregador local (mesmo padrão de Tools/IslandGenerator.lua): baixa,
	APAGA todo script embutido -- free model traz qualquer coisa junto --,
	ancora as Parts e cacheia. O template nunca é parenteado; quem usa clona.

	Só funciona direito em MODO DE EDIÇÃO: InsertService é restrito em
	runtime. Se falhar, cada ambiente cai no mobiliário procedural de
	reserva em vez de ficar vazio.
]]
local templates: { [number]: Model } = {}
local failedAssets: { [number]: boolean } = {}

local function loadTemplate(assetId: number): Model?
	local cached = templates[assetId]
	if cached then
		return cached
	end
	if failedAssets[assetId] then
		return nil
	end

	local ok, container = pcall(function()
		return InsertService:LoadAsset(assetId)
	end)
	if not ok or typeof(container) ~= "Instance" then
		ok, container = pcall(function()
			local objects = game:GetObjects("rbxassetid://" .. assetId)
			local holder = Instance.new("Model")
			for _, obj in objects do
				obj.Parent = holder
			end
			return holder
		end)
	end
	if not ok or typeof(container) ~= "Instance" then
		failedAssets[assetId] = true
		warn(string.format("[Abismo] Não consegui carregar o asset %d: %s", assetId, tostring(container)))
		return nil
	end

	local holder = container :: Instance
	holder.Parent = nil
	for _, d in holder:GetDescendants() do
		if d:IsA("LuaSourceContainer") then
			d:Destroy()
		end
	end
	for _, d in holder:GetDescendants() do
		if d:IsA("BasePart") then
			local bp = d :: BasePart
			bp.Anchored = true
			bp.Locked = false
		end
	end

	local children = holder:GetChildren()
	local model: Model
	if #children == 1 and children[1]:IsA("Model") then
		model = children[1] :: Model
	else
		model = Instance.new("Model")
		model.Name = "Asset_" .. assetId
		for _, child in children do
			child.Parent = model
		end
	end
	model.Parent = nil
	holder:Destroy()

	if not model.PrimaryPart then
		local first = model:FindFirstChildWhichIsA("BasePart", true)
		if first then
			model.PrimaryPart = first
		end
	end

	templates[assetId] = model
	return model
end

--[[
	fitInto(...)
	Encaixa um Model dentro de uma caixa (largura, altura, profundidade) no
	espaço local do túnel, APOIADO no piso em (x, yFloor, z).

	O Toolbox não segue escala nenhuma -- o mesmo "laboratório" pode vir com
	4 ou 400 studs --, então a escala sai da própria bounding box. E o
	alinhamento usa o CENTRO da bounding box, não o pivô: um asset com pivô
	torto (o normal) ficaria meio enterrado no chão se eu usasse PivotTo cru.
]]
local function fitInto(model: Model, f: Frame, x: number, yFloor: number, z: number, fitBox: Vector3, yaw: number?): boolean
	local _, size = model:GetBoundingBox()
	if size.Magnitude < 0.05 then
		return false
	end

	local scale = math.min(fitBox.X / math.max(size.X, 0.05), fitBox.Y / math.max(size.Y, 0.05), fitBox.Z / math.max(size.Z, 0.05))
	if scale == scale and scale > 0 and math.abs(scale - 1) > 0.01 then
		pcall(function()
			model:ScaleTo(model:GetScale() * scale)
		end)
	end

	local bbCF, newSize = model:GetBoundingBox()
	local target = cfAt(f, x, yFloor + newSize.Y / 2 + 0.05, z, yaw)
	model:PivotTo(target * (bbCF:Inverse() * model:GetPivot()))
	return true
end

--[[
	openPassage(...)
	Garante que o vão de entrada continue vago depois que o asset entrou.
	Não dá pra saber onde o modelo do Toolbox colocou as próprias paredes,
	então: o que for do tamanho de móvel e estiver no caminho da porta é
	APAGADO (vira o vão); o que for grande demais pra apagar sem furar a
	cena vira atravessável. Nenhuma das duas saídas deixa o jogador preso --
	que é a regra que não pode quebrar.
]]
local function openPassage(model: Model, f: Frame, x0: number, x1: number, z0: number, z1: number, yFloor: number, yTop: number, maxProp: number)
	for _, d in model:GetDescendants() do
		if not d:IsA("BasePart") then
			continue
		end
		local p = d :: BasePart
		local lp = localOf(f, p.Position)
		local half = math.max(p.Size.X, p.Size.Z) / 2
		local hy = p.Size.Y / 2
		local hits = lp.X + half > x0
			and lp.X - half < x1
			and lp.Z + half > z0
			and lp.Z - half < z1
			and lp.Y + hy > yFloor
			and lp.Y - hy < yTop
		if not hits then
			continue
		end
		if math.max(p.Size.X, p.Size.Y, p.Size.Z) <= maxProp then
			p:Destroy()
		else
			p.CanCollide = false
		end
	end
end

--[[
	harvest(assetId)
	Separa o asset em pedaços avulsos "interessantes" pra eu espalhar em
	OUTROS ambientes -- é o "umas partes de um, umas partes de outro". Corta
	fora o que for casca do próprio modelo (parede/piso/teto/terreno): isso
	só faz sentido no lugar de origem, solto vira um paredão no meio da sala.
]]
local ESTRUTURA_HINTS = {
	"wall", "parede", "floor", "piso", "chao", "ceiling", "teto", "roof", "telhado",
	"ground", "terrain", "grass", "sand", "dirt", "baseplate", "base_", "foundation",
	"room", "sala", "building", "predio", "corridor", "corredor",
}

local function isEstrutura(name: string, size: Vector3): boolean
	local lower = name:lower()
	for _, hint in ESTRUTURA_HINTS do
		if lower:find(hint, 1, true) then
			return true
		end
	end
	-- Placa grande e fina: quase sempre é parede/piso mesmo sem dizer o nome.
	local sorted = { size.X, size.Y, size.Z }
	table.sort(sorted)
	return sorted[3] > 18 and sorted[1] < 2.5
end

local harvestCache: { [number]: { Instance } } = {}

local function harvest(assetId: number): { Instance }
	local cached = harvestCache[assetId]
	if cached then
		return cached
	end

	local out: { Instance } = {}
	local template = loadTemplate(assetId)
	if not template then
		harvestCache[assetId] = out
		return out
	end

	-- Se o asset inteiro é um Model só (uma cena), desce um nível pra achar
	-- os objetos de verdade em vez de "clonar a cena" como único pedaço.
	local source: Instance = template
	local kids = template:GetChildren()
	if #kids == 1 and kids[1]:IsA("Model") then
		source = kids[1]
	end

	for _, child in source:GetChildren() do
		local size: Vector3
		if child:IsA("BasePart") then
			size = child.Size
		elseif child:IsA("Model") then
			local _, s = child:GetBoundingBox()
			size = s
		else
			continue
		end
		if size.Magnitude < 0.3 or isEstrutura(child.Name, size) then
			continue
		end
		table.insert(out, child)
	end

	harvestCache[assetId] = out
	return out
end

--[[
	placeAsset(...)
	Coloca o asset INTEIRO num ambiente. Devolve o Model ou nil se o asset
	não carregou -- o chamador usa isso pra decidir entre o cenário real e o
	mobiliário procedural de reserva.
]]
local function placeAsset(parent: Instance, f: Frame, assetId: number, name: string, x: number, yFloor: number, z: number, fitBox: Vector3, yaw: number?): Model?
	local template = loadTemplate(assetId)
	if not template then
		return nil
	end
	local model = template:Clone()
	model.Name = name
	model.Parent = parent
	if not fitInto(model, f, x, yFloor, z, fitBox, yaw) then
		model:Destroy()
		return nil
	end
	return model
end

--[[
	scatterPieces(...)
	Espalha pedaços colhidos de um asset nos pontos dados. Cada pedaço entra
	num Model próprio (é o que permite escalar e apoiar no chão pela
	bounding box) e fica sem colisão: são adereços de cenário, e malha de
	asset como colisor é o jeito mais curto de prender o jogador.
]]
local function scatterPieces(parent: Instance, f: Frame, assetId: number, spots: { { number } }, fitBox: Vector3, rng: Random): number
	local pool = harvest(assetId)
	if #pool == 0 then
		return 0
	end
	local placed = 0
	for _, spot in spots do
		local source = pool[rng:NextInteger(1, #pool)]
		local holder = Instance.new("Model")
		holder.Name = "Peca_" .. source.Name
		source:Clone().Parent = holder
		holder.Parent = parent
		local scale = rng:NextNumber(0.75, 1)
		if fitInto(holder, f, spot[1], spot[2], spot[3], fitBox * scale, rng:NextNumber(0, TAU)) then
			for _, d in holder:GetDescendants() do
				if d:IsA("BasePart") then
					local bp = d :: BasePart
					bp.CanCollide = false
					bp.Anchored = true
				end
			end
			placed += 1
		else
			holder:Destroy()
		end
	end
	return placed
end

--[[
	assetDoor(...)
	Porta funcional com o modelo do Toolbox. O DoorSystem só sabe girar UMA
	BasePart (tween no CFrame dela), então o arranjo é:
	  - a folha de verdade é uma Part minha, do tamanho exato do vão, que
	    leva o Attribute "Porta" e a colisão (retangular, previsível);
	  - as Parts do asset entram DESANCORADAS e presas nela por
	    WeldConstraint, e assim acompanham o tween;
	  - e elas ficam CanCollide = false. Colisão de malha de asset num vão
	    estreito é o caminho mais curto pra prender o jogador -- a mesma
	    regra que vale pra saída no mar vale aqui.
	Sem o asset, a folha vira uma porta de aço lisa e o jogo segue igual.
]]
local function assetDoor(parent: Instance, f: Frame, x: number, yFloor: number, z: number, width: number, height: number, facingSide: boolean, name: string): Part
	local yaw = if facingSide then math.pi / 2 else 0
	local cf = cfAt(f, x, yFloor + height / 2, z, yaw)

	local leaf = part(parent, "Porta", Vector3.new(width, height, 0.4), cf, Enum.Material.DiamondPlate, COL.Aco:Lerp(COL.Ferrugem, 0.25))
	leaf:SetAttribute("Porta", true)
	leaf:SetAttribute("PortaAberta", false)
	leaf:SetAttribute("CFrameFechada", cf)
	leaf:SetAttribute("LarguraPorta", width)
	leaf:SetAttribute("AbismoPorta", name)

	local template = loadTemplate(ASSETS.Porta)
	if not template then
		part(parent, "Visor", Vector3.new(width * 0.4, height * 0.22, 0.5), cf * CFrame.new(0, height * 0.2, 0), Enum.Material.Glass, COL.Vidro, { Transparency = 0.55, CanCollide = false })
		part(parent, "Macaneta", Vector3.new(0.3, 0.3, 0.8), cf * CFrame.new(width / 2 - 0.7, -0.3, 0), Enum.Material.Metal, COL.FerrugemClara, { CanCollide = false })
		return leaf
	end

	local skin = template:Clone()
	skin.Name = "FolhaAsset"
	skin.Parent = parent
	-- A folha do asset é levemente MAIOR que a Part (0.98 do vão em largura)
	-- pra não aparecer um fio da minha Part por trás dela.
	if not fitInto(skin, f, x, yFloor, z, Vector3.new(width * 0.98, height * 0.99, 1.6), yaw) then
		skin:Destroy()
		return leaf
	end
	for _, d in skin:GetDescendants() do
		if d:IsA("BasePart") then
			local bp = d :: BasePart
			bp.Anchored = false
			bp.CanCollide = false
			bp.Massless = true
			local weld = Instance.new("WeldConstraint")
			weld.Part0 = leaf
			weld.Part1 = bp
			weld.Parent = bp
		end
	end
	leaf.Transparency = 1 -- o asset é o visual; a minha Part é só colisão/eixo
	return leaf
end

--------------------------------------------------------------------------------
-- Superfície: a escotilha escondida
--------------------------------------------------------------------------------

--[[
	buildHatch(...)
	A boca do poço, no meio da floresta. Fica ABERTA (tampa tombada pra trás,
	enferrujada): a estação está abandonada, e assim não dependo de nenhum
	sistema de runtime pra o jogador conseguir descer. O Attribute
	"AbismoPortaPrincipal" fica na tampa pra um sistema futuro poder fechar
	ou travar essa saída.

	O colar de concreto é um ANEL, não uma tampa: ele fecha a volta do vão
	até a parede do poço, então quem olha pra dentro vê concreto descendo --
	nunca a terra da floresta em corte.
]]
local function buildHatch(parent: Instance, f: Frame, rng: Random)
	local folder = Instance.new("Folder")
	folder.Name = "Escotilha"
	folder.Parent = parent

	local y = f.SurfaceY

	slabWithHole(folder, f, "ColarEscotilha", -9.5, 9.5, -9.5, 9.5, -5, 5, -5, 5, y + 1.2, false, COL.ConcretoSujo)
	-- Meio-fio: a borda alta que faz o vão ser um buraco, não um degrau.
	for _, sx in { -1, 1 } do
		part(folder, "MeioFio", Vector3.new(0.9, 1.4, 12), cfAt(f, sx * 5.6, y + 1.9, 0), Enum.Material.Concrete, COL.ConcretoSujo)
		part(folder, "MeioFio", Vector3.new(12, 1.4, 0.9), cfAt(f, 0, y + 1.9, sx * 5.6), Enum.Material.Concrete, COL.ConcretoSujo)
	end

	-- Tampa tombada, encostada no colar.
	local lid = part(folder, "TampaEscotilha", Vector3.new(11, 0.6, 11), cfAt(f, -9.4, y + 4.6, 0) * CFrame.Angles(0, 0, math.rad(74)), Enum.Material.DiamondPlate, COL.Ferrugem)
	lid:SetAttribute("AbismoPortaPrincipal", true)
	part(folder, "Dobradica", Vector3.new(1.4, 0.6, 10.6), cfAt(f, -6, y + 1.4, 0), Enum.Material.Metal, COL.AcoEscuro, DECO)
	part(folder, "Volante", Vector3.new(3, 0.35, 3), cfAt(f, -10.2, y + 6.6, 0) * CFrame.Angles(0, 0, math.rad(74)), Enum.Material.Metal, COL.FerrugemClara, DECO)

	sign(folder, cfAt(f, 5.2, y + 2.6, 4.6) * CFrame.Angles(0, math.rad(-140), math.rad(-8)), 4.4, 2.2, "ESTAÇÃO ABISMO", "ACESSO RESTRITO")

	-- Camuflagem: pedras e mato em volta. É isto que faz a escotilha não
	-- saltar aos olhos de quem só passa correndo pela floresta.
	for i = 1, 16 do
		local ang = rng:NextNumber(0, TAU)
		local d = rng:NextNumber(9, 20)
		local px, pz = math.cos(ang) * d, math.sin(ang) * d
		local wp = at(f, px, 0, pz)
		local gy = groundY(wp.X, wp.Z)
		local size = rng:NextNumber(2.5, 7)
		part(folder, "PedraCamuflagem_" .. i, Vector3.new(size, size * rng:NextNumber(0.5, 0.9), size * rng:NextNumber(0.7, 1.2)), cfAt(f, px, gy + size * 0.2, pz) * CFrame.Angles(rng:NextNumber(-0.3, 0.3), rng:NextNumber(0, TAU), rng:NextNumber(-0.3, 0.3)), Enum.Material.Rock, COL.Rocha:Lerp(COL.Musgo, rng:NextNumber(0, 0.4)))
	end
	for i = 1, 12 do
		local ang = rng:NextNumber(0, TAU)
		local d = rng:NextNumber(7, 14)
		local px, pz = math.cos(ang) * d, math.sin(ang) * d
		local wp = at(f, px, 0, pz)
		local gy = groundY(wp.X, wp.Z)
		part(folder, "Mato_" .. i, Vector3.new(rng:NextNumber(2, 4.5), rng:NextNumber(1.2, 2.4), rng:NextNumber(2, 4.5)), cfAt(f, px, gy + 0.6, pz) * CFrame.Angles(0, rng:NextNumber(0, TAU), 0), Enum.Material.Grass, COL.Musgo, DECO)
	end

	marker(folder, "ZonaEscotilha", at(f, 0, y + 2.5, 0), { AbismoZona = "Escotilha" })
end

--------------------------------------------------------------------------------
-- Poço de acesso
--------------------------------------------------------------------------------

--[[
	buildShaft(...)
	Tubo QUADRADO de concreto da superfície até o teto do Nível -1. Quadrado
	e não cilíndrico porque ele encosta num buraco retangular de laje: anel
	de painéis curvos sempre deixa canto sem cobrir, e canto sem cobrir é
	exatamente onde a terra apareceria.
]]
local function buildShaft(parent: Instance, f: Frame, rng: Random)
	local folder = Instance.new("Folder")
	folder.Name = "PocoAcesso"
	folder.Parent = parent

	local top = f.SurfaceY + 1.2
	local bottom = CONFIG.NivelMenos1 + CONFIG.AlturaSala -- teto do Nível -1
	local tone = COL.ConcretoSujo

	-- Paredes: as de X cobrem os cantos (vão de -5.8 a 5.8), as de Z encaixam
	-- entre elas. Sem sobreposição dupla e sem fresta.
	for _, sx in { -1, 1 } do
		wallX(folder, f, sx * 5.4, -5.8, 5.8, bottom, top, tone)
		wallZ(folder, f, sx * 5.4, -5, 5, bottom, top, tone)
	end

	-- Anéis de reforço, só leitura de escala.
	local rings = math.max(2, math.floor((top - bottom) / 5))
	for i = 0, rings do
		local y = bottom + (top - bottom) * (i / rings)
		for _, sx in { -1, 1 } do
			part(folder, "AnelPoco", Vector3.new(0.35, 0.7, 11.6), cfAt(f, sx * 4.9, y, 0), Enum.Material.Concrete, COL.ConcretoVelho, DECO)
			part(folder, "AnelPoco", Vector3.new(9.8, 0.7, 0.35), cfAt(f, 0, y, sx * 4.9), Enum.Material.Concrete, COL.ConcretoVelho, DECO)
		end
	end

	-- Escada de treliça: desce do topo até o PISO do Nível -1, atravessando o
	-- vão da laje. Dá pra subir de volta.
	local ladderBottom = CONFIG.NivelMenos1
	local ladder = Instance.new("TrussPart")
	ladder.Name = "EscadaPoco"
	ladder.Size = Vector3.new(2, top - ladderBottom, 2)
	ladder.CFrame = cfAt(f, 4, (top + ladderBottom) / 2, 0)
	ladder.Anchored = true
	ladder.Material = Enum.Material.Metal
	ladder.Color = COL.Ferrugem
	ladder.Parent = folder

	pipeRun(folder, at(f, -4.6, top, 0), at(f, -4.6, ladderBottom, 0), 0.4, COL.Cano, 0)
	pipeRun(folder, at(f, -3.4, top, 0), at(f, -3.4, ladderBottom, 0), 0.18, COL.Cabo, 0)

	for i = 1, 6 do
		local y = rng:NextNumber(bottom + 2, top - 3)
		local sx = if rng:NextNumber() < 0.5 then -1 else 1
		moisture(folder, cfAt(f, sx * 4.9, y, rng:NextNumber(-4, 4)) * CFrame.Angles(0, if sx < 0 then math.pi / 2 else -math.pi / 2, 0), rng:NextNumber(1.5, 3), rng)
	end
	for _, spec in { { top - 4, 0.1 }, { (top + bottom) / 2, 0.35 } } do
		lamp(folder, cfAt(f, -4.7, spec[1], 0) * CFrame.Angles(0, math.pi / 2, 0), spec[2], rng)
	end

	marker(folder, "ZonaPoco", at(f, 0, (top + bottom) / 2, 0), { AbismoZona = "Poco" })
end

--------------------------------------------------------------------------------
-- Nível -1: eclusa / vestiário
--------------------------------------------------------------------------------

local function buildLevelMinus1(parent: Instance, f: Frame, rng: Random)
	local folder = Instance.new("Folder")
	folder.Name = "NivelMenos1"
	folder.Parent = parent

	local C = CONFIG
	local y, h = C.NivelMenos1, C.AlturaSala
	local top = y + h
	local x, z0, z1 = C.EclusaX, C.EclusaZ0, C.EclusaZ1
	local tone = COL.Concreto

	slab(folder, f, "PisoN1", -x, x, z0, z1, y, false, tone)
	-- Teto com o vão do poço.
	slabWithHole(folder, f, "TetoN1", -x, x, z0, z1, -5.4, 5.4, -5.4, 5.4, top, true, tone:Lerp(Color3.new(0, 0, 0), 0.28))
	for _, sx in { -1, 1 } do
		wallX(folder, f, sx * x, z0, z1, y, top, tone)
	end
	wallZ(folder, f, z0, -x, x, y, top, tone)
	wallZ(folder, f, z1, -x, x, y, top, tone, { { a0 = -4, a1 = 4, y0 = y, y1 = y + C.AlturaPorta } })
	assetDoor(folder, f, 0, y, z1, 8, C.AlturaPorta, false, "Eclusa")

	-- Batente do vão do poço, por baixo da laje: fecha a junta entre o tubo e
	-- o teto sem depender de encaixe perfeito de dois Parts.
	for _, sx in { -1, 1 } do
		part(folder, "BatentePoco", Vector3.new(0.9, 1, 12), cfAt(f, sx * 5.4, top - 0.5, 0), Enum.Material.Metal, COL.AcoEscuro, DECO)
		part(folder, "BatentePoco", Vector3.new(10.8, 1, 0.9), cfAt(f, 0, top - 0.5, sx * 5.4), Enum.Material.Metal, COL.AcoEscuro, DECO)
	end

	-- Armários e banco: o vestiário de quem trabalhava aqui.
	for i = 1, 6 do
		part(folder, "Armario", Vector3.new(2.4, 6, 1.6), cfAt(f, -x + 1.4, y + 3, z0 + 3 + i * 2.6), Enum.Material.Metal, COL.Aco:Lerp(COL.Ferrugem, rng:NextNumber(0.1, 0.6)))
		part(folder, "PortaArmario", Vector3.new(0.12, 5.4, 1.4), cfAt(f, -x + 2.65, y + 3, z0 + 3 + i * 2.6) * CFrame.Angles(0, rng:NextNumber(-0.5, 0.2), 0), Enum.Material.Metal, COL.AcoEscuro, DECO)
	end
	part(folder, "Banco", Vector3.new(1.6, 0.4, 10), cfAt(f, -6.5, y + 1.6, 4), Enum.Material.Metal, COL.AcoEscuro)
	for _, pz in { 0, 8 } do
		part(folder, "PeBanco", Vector3.new(1.4, 1.6, 0.3), cfAt(f, -6.5, y + 0.8, pz), Enum.Material.Metal, COL.AcoEscuro, DECO)
	end

	-- Chuveiro de descontaminação.
	part(folder, "Descontaminacao", Vector3.new(0.5, 5, 0.5), cfAt(f, x - 2.5, y + 2.5, z0 + 5), Enum.Material.Metal, COL.Cano, DECO)
	part(folder, "Crivo", Vector3.new(2, 0.3, 2), cfAt(f, x - 2.5, y + 5, z0 + 5), Enum.Material.Metal, COL.Cano, DECO)
	puddle(folder, at(f, x - 2.5, y, z0 + 5), 2.6, rng)

	sign(folder, cfAt(f, 0, top - 2.4, z1 - 0.6), 9, 2.8, "ESTAÇÃO ABISMO", "NÍVEL -1  ·  ECLUSA")
	sign(folder, cfAt(f, x - 0.6, y + 6, 12) * CFrame.Angles(0, math.rad(90), 0), 5, 2.2, "NÍVEL -2  ↓", "LABORATÓRIO / CONTROLE / CLÍNICA")

	S.LootPoint(folder, cfAt(f, -6.5, y + 2, 6))
	S.LootPoint(folder, cfAt(f, x - 3, y + 1.4, 14))
	-- Pedaços do complexo colhidos do OUTRO asset: a eclusa é do mesmo
	-- lugar que a ala clínica, e mostrar isso custa três props.
	scatterPieces(folder, f, ASSETS.Complexo, {
		{ -x + 3.5, y, z1 - 4 },
		{ x - 4, y, z1 - 6 },
		{ 6, y, z0 + 3 },
	}, Vector3.new(4.5, 5, 4.5), rng)

	for i = 1, 4 do
		lamp(folder, cfAt(f, 0, top - 0.6, z0 + i * 7), 0.2, rng)
	end
	marker(folder, "ZonaNivelMenos1", at(f, 0, y + 2, (z0 + z1) / 2), { AbismoZona = "NivelMenos1" })
end

--------------------------------------------------------------------------------
-- Caixa de escada fechada, Nível -1 -> Nível -2
--------------------------------------------------------------------------------

--[[
	buildStairs(...)
	Escada num poço FECHADO: cada degrau leva o pedaço de parede e de teto
	dele junto. É mais Part que uma caixa única, mas é o que faz o teto
	acompanhar a descida em vez de virar um vão de 26 studs de altura -- e o
	que garante que não sobre rocha à mostra em nenhum degrau.

	Degraus e lajes são mais grossos que o passo (1,4 contra 1,0) de
	propósito: assim cada um encavala no seguinte e não abre fresta.
]]
local function buildStairs(parent: Instance, f: Frame, rng: Random)
	local folder = Instance.new("Folder")
	folder.Name = "CaixaDeEscada"
	folder.Parent = parent

	local C = CONFIG
	local x = C.EscadaX
	local z0, z1 = C.EclusaZ1, C.EscadaZ1
	local yTopo, yBase = C.NivelMenos1, C.NivelMenos2
	local steps = 14
	local run = (z1 - z0) / steps
	local rise = (yTopo - yBase) / steps
	local headroom = 11
	local tone = COL.Concreto:Lerp(COL.ConcretoSujo, 0.4)

	for i = 1, steps do
		local y = yTopo - rise * i
		local a = z0 + (i - 1) * run
		local b = z0 + i * run
		local teto = y + headroom

		part(folder, "Degrau_" .. i, Vector3.new(2 * x, 1.4, run + 0.1), cfAt(f, 0, y - 0.7, (a + b) / 2), Enum.Material.Concrete, tone)
		slab(folder, f, "TetoEscada", -x - 0.4, x + 0.4, a, b + 0.1, teto, true, tone:Lerp(Color3.new(0, 0, 0), 0.3), 1.4)
		for _, sx in { -1, 1 } do
			wallX(folder, f, sx * x, a, b + 0.1, y - 1.4, teto + 1.4, tone)
		end
		if i % 4 == 0 then
			lamp(folder, cfAt(f, 0, teto - 0.6, (a + b) / 2), 0.25, rng)
		end
	end

	for _, sx in { -1, 1 } do
		beam(folder, "Corrimao", at(f, sx * (x - 1), yTopo + 1.1, z0 + 0.5), at(f, sx * (x - 1), yBase + 1.1, z1 - 0.5), 0.22, Enum.Material.Metal, COL.Ferrugem, false)
	end
	-- A parede do fundo (z1) é a parede do ÁTRIO, não desta função: ela
	-- precisa cobrir a altura inteira do átrio (-18 a -6), e não só a da
	-- caixa de escada (-18 a -7). Construir as duas deixaria uma faixa de
	-- 1 stud sem vedação bem no encontro.

	sign(folder, cfAt(f, x - 0.5, yTopo - 3, z0 + 5) * CFrame.Angles(0, math.rad(90), 0), 4, 2, "↓ NÍVEL -2", "PROFUNDIDADE 18 m")
	marker(folder, "ZonaEscada", at(f, 0, (yTopo + yBase) / 2, (z0 + z1) / 2), { AbismoZona = "Escada" })
end

--------------------------------------------------------------------------------
-- Nível -2: átrio e corredor principal
--------------------------------------------------------------------------------

local function buildAtrio(parent: Instance, f: Frame, rng: Random)
	local folder = Instance.new("Folder")
	folder.Name = "AtrioNivelMenos2"
	folder.Parent = parent

	local C = CONFIG
	local y, h = C.NivelMenos2, C.AlturaSala
	local x, z0, z1 = C.AtrioX, C.EscadaZ1, C.AtrioZ1
	local tone = COL.Concreto:Lerp(COL.ConcretoSujo, 0.35)

	roomShell(folder, f, {
		x0 = -x,
		x1 = x,
		z0 = z0,
		z1 = z1,
		y = y,
		h = h,
		color = tone,
		name = "Atrio",
		-- Vão da escada (porta) e boca do corredor (altura inteira).
		vaosZMin = { { a0 = -5, a1 = 5, y0 = y, y1 = y + C.AlturaPorta } },
		vaosZMax = { { a0 = -C.CorredorX, a1 = C.CorredorX, y0 = y, y1 = y + h } },
	})

	sign(folder, cfAt(f, 0, y + 8.4, z0 + 0.6), 14, 3.6, "ESTAÇÃO ABISMO", "NÍVEL -2  ·  PESQUISA")
	sign(folder, cfAt(f, -x + 0.6, y + 6, z0 + 8) * CFrame.Angles(0, math.rad(-90), 0), 6, 3, "ROTA DE EVACUAÇÃO", "SIGA AS SETAS ATÉ O ACESSO MARÍTIMO")

	-- Guarita de controle de acesso: dá volume ao átrio e serve de cobertura
	-- numa perseguição futura.
	part(folder, "Guarita", Vector3.new(7, 4.5, 5), cfAt(f, x - 5, y + 2.25, z0 + 5), Enum.Material.Metal, COL.AcoEscuro)
	local vidro = part(folder, "VidroGuarita", Vector3.new(7, 3.5, 0.2), cfAt(f, x - 5, y + 6.2, z0 + 2.6), Enum.Material.Glass, COL.Vidro, { Transparency = 0.5, CanCollide = false })
	vidro.Reflectance = 0.1
	part(folder, "TampoGuarita", Vector3.new(7.6, 0.4, 5.6), cfAt(f, x - 5, y + 4.6, z0 + 5), Enum.Material.Metal, COL.Aco)
	S.LootPoint(folder, cfAt(f, x - 5, y + 5, z0 + 5))

	for i = 1, 3 do
		part(folder, "Engradado", Vector3.new(3.4, 3.4, 3.4), cfAt(f, -x + 3 + i * 0.6, y + 1.7, z1 - 3 - i * 3.4) * CFrame.Angles(0, rng:NextNumber(-0.3, 0.3), 0), Enum.Material.WoodPlanks, COL.ConcretoVelho)
	end
	S.LootPoint(folder, cfAt(f, -x + 4, y + 3.6, z1 - 6))

	scatterPieces(folder, f, ASSETS.Laboratorio, {
		{ -x + 4, y, z0 + 4 },
		{ 4, y, z0 + 3 },
	}, Vector3.new(5, 6, 5), rng)

	for i = 1, 2 do
		lamp(folder, cfAt(f, 0, y + h - 0.6, z0 + i * 5), 0.3, rng)
	end
	moisture(folder, cfAt(f, -x + 0.5, y + 5, z1 - 4) * CFrame.Angles(0, math.rad(-90), 0), 3, rng)
	marker(folder, "ZonaAtrio", at(f, 0, y + 2, (z0 + z1) / 2), { AbismoZona = "NivelMenos2", AbismoSala = "Atrio" })
end

local function buildCorredor(parent: Instance, f: Frame, rng: Random)
	local folder = Instance.new("Folder")
	folder.Name = "CorredorPrincipal"
	folder.Parent = parent

	local C = CONFIG
	local y, h = C.NivelMenos2, C.AlturaSala
	local x, z0, z1 = C.CorredorX, C.AtrioZ1, C.CorredorZ1
	local hp = C.AlturaPorta
	local tone = COL.Concreto:Lerp(COL.ConcretoSujo, 0.35)

	roomShell(folder, f, {
		x0 = -x,
		x1 = x,
		z0 = z0,
		z1 = z1,
		y = y,
		h = h,
		color = tone,
		name = "Corredor",
		semZMin = true, -- parede do átrio
		semZMax = true, -- parede da câmara de bombas
		vaosXMin = { { a0 = C.LabPortaZ0, a1 = C.LabPortaZ1, y0 = y, y1 = y + hp } },
		vaosXMax = {
			{ a0 = C.CtrlPortaZ0, a1 = C.CtrlPortaZ1, y0 = y, y1 = y + hp },
			{ a0 = C.ClinPortaZ0, a1 = C.ClinPortaZ1, y0 = y, y1 = y + hp },
		},
	})

	-- Portas das três salas (modelo do Toolbox; ver assetDoor).
	assetDoor(folder, f, -x, y, (C.LabPortaZ0 + C.LabPortaZ1) / 2, C.LabPortaZ1 - C.LabPortaZ0, hp, true, "Laboratorio")
	assetDoor(folder, f, x, y, (C.CtrlPortaZ0 + C.CtrlPortaZ1) / 2, C.CtrlPortaZ1 - C.CtrlPortaZ0, hp, true, "Controle")
	assetDoor(folder, f, x, y, (C.ClinPortaZ0 + C.ClinPortaZ1) / 2, C.ClinPortaZ1 - C.ClinPortaZ0, hp, true, "Clinica")

	sign(folder, cfAt(f, -x + 0.6, y + hp + 1.2, (C.LabPortaZ0 + C.LabPortaZ1) / 2) * CFrame.Angles(0, math.rad(-90), 0), 6, 1.8, "LABORATÓRIO")
	sign(folder, cfAt(f, x - 0.6, y + hp + 1.2, (C.CtrlPortaZ0 + C.CtrlPortaZ1) / 2) * CFrame.Angles(0, math.rad(90), 0), 5, 1.8, "CONTROLE")
	sign(folder, cfAt(f, x - 0.6, y + hp + 1.2, (C.ClinPortaZ0 + C.ClinPortaZ1) / 2) * CFrame.Angles(0, math.rad(90), 0), 5, 1.8, "ALA CLÍNICA")

	-- Ritmo: cavaletes, canos e cabos correndo o corredor inteiro.
	for i = 0, math.floor((z1 - z0) / 8) do
		local z = z0 + i * 8
		if z > z1 - 1 then
			break
		end
		for _, sx in { -1, 1 } do
			part(folder, "Montante", Vector3.new(0.4, h, 0.4), cfAt(f, sx * (x - 0.6), y + h / 2, z), Enum.Material.Metal, COL.Aco:Lerp(COL.Ferrugem, 0.3), DECO)
		end
		part(folder, "Travessa", Vector3.new(2 * x - 1.2, 0.4, 0.4), cfAt(f, 0, y + h - 0.4, z), Enum.Material.Metal, COL.Aco:Lerp(COL.Ferrugem, 0.3), DECO)
		lamp(folder, cfAt(f, 0, y + h - 0.6, z + 4), 0.2 + (i / 8) * 0.35, rng)
		-- Seta de evacuação pintada no chão.
		part(folder, "SetaEvacuacao", Vector3.new(1.6, 0.06, 3), cfAt(f, -x + 1.6, y + 0.03, z + 4), Enum.Material.SmoothPlastic, COL.Placa, DECO)
	end
	pipeRun(folder, at(f, -x + 0.9, y + h - 1.5, z0), at(f, -x + 0.9, y + h - 1.5, z1), 0.5, COL.Cano, 0.15)
	pipeRun(folder, at(f, -x + 0.9, y + h - 2.4, z0), at(f, -x + 0.9, y + h - 2.4, z1), 0.34, COL.CanoVerde, 0.12)
	pipeRun(folder, at(f, x - 0.9, y + h - 1.5, z0), at(f, x - 0.9, y + h - 1.5, z1), 0.2, COL.Cabo, 0.5)
	pipeRun(folder, at(f, x - 0.9, y + h - 2.1, z0), at(f, x - 0.9, y + h - 2.1, z1), 0.16, COL.Cabo, 0.6)

	for i = 1, 6 do
		local sx = if rng:NextNumber() < 0.5 then -1 else 1
		local wall = cfAt(f, sx * (x - 0.45), y + rng:NextNumber(2, h - 2), rng:NextNumber(z0 + 3, z1 - 3)) * CFrame.Angles(0, if sx < 0 then math.pi / 2 else -math.pi / 2, 0)
		moisture(folder, wall, rng:NextNumber(1.5, 3), rng)
		if rng:NextNumber() < 0.5 then
			crack(folder, wall * CFrame.new(rng:NextNumber(-1, 1), 2, 0), rng:NextNumber(2, 4), rng)
		end
	end
	for _ = 1, 3 do
		puddle(folder, at(f, rng:NextNumber(-x + 2, x - 2), y, rng:NextNumber(z0 + 4, z1 - 4)), rng:NextNumber(1.5, 3), rng)
	end
	-- Rastro de sangue: alguém foi arrastado corredor abaixo.
	bloodPool(folder, at(f, -2, y, z0 + 14), 3.2, rng)
	for i = 1, 5 do
		part(folder, "Arrasto", Vector3.new(rng:NextNumber(0.5, 1.4), 0.06, 3), cfAt(f, -2 + i * 0.7, y + 0.04, z0 + 16 + i * 2.4), Enum.Material.SmoothPlastic, COL.SangueVelho, DECO)
	end
	bloodSplat(folder, cfAt(f, x - 0.45, y + 4, z0 + 24) * CFrame.Angles(0, math.rad(90), 0), 3, rng)

	sign(folder, cfAt(f, 0, y + h - 2, z1 - 0.9), 12, 3.2, "→ ACESSO MARÍTIMO", "CÂMARA DE BOMBAS  ·  TÚNEL DE EVACUAÇÃO")
	S.LootPoint(folder, cfAt(f, x - 2, y + 1, z0 + 30))
	marker(folder, "ZonaCorredor", at(f, 0, y + 2, (z0 + z1) / 2), { AbismoZona = "NivelMenos2", AbismoSala = "Corredor" })
end

--------------------------------------------------------------------------------
-- Nível -2: laboratório, controle e ala clínica
--------------------------------------------------------------------------------

-- Mobiliário de reserva do laboratório, usado SÓ quando o asset não carrega
-- (InsertService é restrito fora do modo de edição). Melhor uma bancada
-- primitiva do que uma sala vazia.
local function labFallback(parent: Instance, f: Frame, y: number, cx: number, cz: number, rng: Random)
	for i = 1, 3 do
		local bz = cz - 9 + i * 7
		part(parent, "Bancada", Vector3.new(11, 0.4, 2.6), cfAt(f, cx - 6, y + 3.2, bz), Enum.Material.Metal, COL.Aco)
		part(parent, "PeBancada", Vector3.new(10, 3, 0.4), cfAt(f, cx - 6, y + 1.6, bz), Enum.Material.Metal, COL.AcoEscuro, DECO)
		S.LootPoint(parent, cfAt(f, cx - 6, y + 3.8, bz))
	end
	for i = 1, 4 do
		local tz = cz - 9 + i * 5
		local tank = part(parent, "TanqueEspecime", Vector3.new(4, 7, 4), cfAt(f, cx + 8, y + 3.5, tz), Enum.Material.Glass, COL.Vidro, { CanCollide = false })
		tank.Transparency = 0.55
		part(parent, "BaseTanque", Vector3.new(4.6, 1.2, 4.6), cfAt(f, cx + 8, y + 0.6, tz), Enum.Material.Metal, COL.AcoEscuro)
		part(parent, "TampaTanque", Vector3.new(4.6, 0.8, 4.6), cfAt(f, cx + 8, y + 7.4, tz), Enum.Material.Metal, COL.Ferrugem, DECO)
		if rng:NextNumber() < 0.5 then
			for _ = 1, 4 do
				part(parent, "Caco", Vector3.new(rng:NextNumber(0.6, 1.6), 0.1, rng:NextNumber(0.6, 1.6)), cfAt(f, cx + 8 + rng:NextNumber(-3, 3), y + 0.1, tz + rng:NextNumber(-3, 3)) * CFrame.Angles(0, rng:NextNumber(0, TAU), 0), Enum.Material.Glass, COL.Vidro, DECO)
			end
		end
	end
end

local function buildLaboratorio(parent: Instance, f: Frame, rng: Random)
	local folder = Instance.new("Folder")
	folder.Name = "Laboratorio"
	folder.Parent = parent

	local C = CONFIG
	local y, h = C.NivelMenos2, C.AlturaSala
	local x0, x1 = -C.LabX, -C.CorredorX
	local z0, z1 = C.LabZ0, C.LabZ1
	local tone = COL.Azulejo

	roomShell(folder, f, {
		x0 = x0,
		x1 = x1,
		z0 = z0,
		z1 = z1,
		y = y,
		h = h,
		color = tone,
		name = "Lab",
		semXMax = true, -- essa é a parede do corredor, com o vão da porta
	})

	-- O CENÁRIO: o modelo do Toolbox ocupa a metade do fundo da sala, longe
	-- da porta. Depois openPassage limpa o que tiver invadido o caminho de
	-- entrada -- não dá pra saber onde o asset pôs as próprias paredes.
	local cx, cz = (x0 + x1) / 2 - 3, z1 - 11
	local cenario = placeAsset(folder, f, ASSETS.Laboratorio, "CenarioLaboratorio", cx, y, cz, Vector3.new((x1 - x0) - 6, h - 1.2, 20))
	if cenario then
		openPassage(cenario, f, x1 - 11, x1, C.LabPortaZ0 - 1, C.LabPortaZ1 + 1, y, y + h, 14)
	else
		labFallback(folder, f, y, cx, cz, rng)
	end

	-- Sangue: o asset já vem com o dele, mas a sala é maior que o asset e a
	-- história precisa continuar até a porta.
	bloodPool(folder, at(f, x1 - 6, y, C.LabPortaZ1 + 3), 3.6, rng)
	bloodPool(folder, at(f, x0 + 7, y, z0 + 6), 2.8, rng)
	bloodSplat(folder, cfAt(f, x0 + 0.45, y + 4.5, z0 + 8) * CFrame.Angles(0, math.rad(90), 0), 3.5, rng)
	bloodSplat(folder, cfAt(f, x0 + 0.45, y + 3, z1 - 6) * CFrame.Angles(0, math.rad(90), 0), 2.5, rng)

	-- Props colhidos do OUTRO asset, pra as duas alas parecerem a mesma obra.
	scatterPieces(folder, f, ASSETS.Complexo, {
		{ x0 + 5, y, z0 + 14 },
		{ x0 + 5, y, z0 + 20 },
		{ x1 - 5, y, z1 - 4 },
		{ x0 + 12, y, z1 - 3 },
	}, Vector3.new(6, 7, 6), rng)

	for _, sz in { z0 + 8, (z0 + z1) / 2, z1 - 8 } do
		lamp(folder, cfAt(f, (x0 + x1) / 2, y + h - 0.6, sz), 0.35, rng)
	end
	for i = 1, 4 do
		moisture(folder, cfAt(f, x0 + 0.5, y + rng:NextNumber(2, h - 3), rng:NextNumber(z0 + 3, z1 - 3)) * CFrame.Angles(0, math.rad(90), 0), rng:NextNumber(2, 4), rng)
	end
	S.LootPoint(folder, cfAt(f, x0 + 4, y + 1, z1 - 5))
	S.LootPoint(folder, cfAt(f, x1 - 5, y + 1, z0 + 4))
	sign(folder, cfAt(f, (x0 + x1) / 2, y + h - 2, z0 + 0.6), 10, 3, "LABORATÓRIO", "NÍVEL -2  ·  BIOSSEGURANÇA 3")
	marker(folder, "ZonaLaboratorio", at(f, (x0 + x1) / 2, y + 2, (z0 + z1) / 2), { AbismoZona = "NivelMenos2", AbismoSala = "Laboratorio" })
end

local function buildControle(parent: Instance, f: Frame, rng: Random)
	local folder = Instance.new("Folder")
	folder.Name = "SalaDeControle"
	folder.Parent = parent

	local C = CONFIG
	local y, h = C.NivelMenos2, C.AlturaSala
	local x0, x1 = C.CorredorX, C.CtrlX
	local z0, z1 = C.CtrlZ0, C.CtrlZ1
	local tone = COL.Concreto:Lerp(COL.ConcretoSujo, 0.2)

	roomShell(folder, f, {
		x0 = x0,
		x1 = x1,
		z0 = z0,
		z1 = z1,
		y = y,
		h = h,
		color = tone,
		name = "Ctrl",
		semXMin = true, -- parede do corredor
	})

	-- Consoles e mesa de operação (procedurais: o que importa aqui é a
	-- silhueta de cobertura numa perseguição, não o detalhe).
	for i = 1, 4 do
		local cz = z0 + 2 + i * 4
		part(folder, "Console", Vector3.new(3.4, 4, 2.2), cfAt(f, x1 - 2.4, y + 2, cz), Enum.Material.Metal, COL.AcoEscuro)
		local screen = part(folder, "Tela", Vector3.new(0.14, 2, 1.8), cfAt(f, x1 - 4.2, y + 3.4, cz) * CFrame.Angles(0, 0, math.rad(-12)), Enum.Material.Neon, Color3.fromRGB(56, 92, 84), DECO)
		screen.Transparency = 0.45
	end
	part(folder, "MesaControle", Vector3.new(12, 0.4, 3), cfAt(f, (x0 + x1) / 2 + 1, y + 3.2, (z0 + z1) / 2), Enum.Material.Metal, COL.Aco)
	for _, sz in { -4, 4 } do
		part(folder, "PeMesa", Vector3.new(11, 3, 0.4), cfAt(f, (x0 + x1) / 2 + 1, y + 1.6, (z0 + z1) / 2 + sz), Enum.Material.Metal, COL.AcoEscuro, DECO)
	end
	part(folder, "QuadroEletrico", Vector3.new(0.6, 6, 5), cfAt(f, x1 - 0.8, y + 4.5, z1 - 4), Enum.Material.Metal, COL.AcoEscuro)

	-- Props colhidos do asset do laboratório: a sala de controle é do mesmo
	-- complexo e herda o mesmo mobiliário.
	scatterPieces(folder, f, ASSETS.Laboratorio, {
		{ x0 + 4, y, z0 + 4 },
		{ x0 + 4, y, z1 - 4 },
		{ (x0 + x1) / 2, y, z1 - 3 },
	}, Vector3.new(5.5, 6.5, 5.5), rng)

	S.LootPoint(folder, cfAt(f, (x0 + x1) / 2 + 1, y + 3.8, (z0 + z1) / 2))
	S.LootPoint(folder, cfAt(f, x1 - 3, y + 1, z0 + 3))
	lamp(folder, cfAt(f, (x0 + x1) / 2, y + h - 0.6, (z0 + z1) / 2), 0.4, rng)
	lamp(folder, cfAt(f, (x0 + x1) / 2, y + h - 0.6, z1 - 4), 0.5, rng)
	moisture(folder, cfAt(f, x1 - 0.5, y + 5, z0 + 4) * CFrame.Angles(0, math.rad(-90), 0), 3, rng)
	sign(folder, cfAt(f, (x0 + x1) / 2, y + h - 2, z0 + 0.6), 8, 2.6, "CONTROLE", "NÍVEL -2")
	marker(folder, "ZonaControle", at(f, (x0 + x1) / 2, y + 2, (z0 + z1) / 2), { AbismoZona = "NivelMenos2", AbismoSala = "Controle" })
end

local function buildClinica(parent: Instance, f: Frame, rng: Random)
	local folder = Instance.new("Folder")
	folder.Name = "AlaClinica"
	folder.Parent = parent

	local C = CONFIG
	local y, h = C.NivelMenos2, C.AlturaSala
	local x0, x1 = C.CorredorX, C.ClinX
	local z0, z1 = C.ClinZ0, C.ClinZ1
	local tone = COL.Azulejo:Lerp(COL.ConcretoSujo, 0.3)

	roomShell(folder, f, {
		x0 = x0,
		x1 = x1,
		z0 = z0,
		z1 = z1,
		y = y,
		h = h,
		color = tone,
		name = "Clin",
		semXMin = true,
	})

	-- O SEGUNDO cenário do Toolbox mora aqui, no fundo da ala -- de novo
	-- longe da porta, e de novo com openPassage garantindo a entrada.
	local cx, cz = (x0 + x1) / 2 + 1, z1 - 6
	local cenario = placeAsset(folder, f, ASSETS.Complexo, "CenarioClinica", cx, y, cz, Vector3.new((x1 - x0) - 4, h - 1.2, 11))
	if cenario then
		openPassage(cenario, f, x0, x0 + 11, C.ClinPortaZ0 - 1, C.ClinPortaZ1 + 1, y, y + h, 14)
	else
		-- Reserva: macas e um necrotério improvisado.
		for i = 1, 4 do
			local mz = z0 + 3 + i * 4
			part(folder, "Maca", Vector3.new(3, 0.4, 7), cfAt(f, x1 - 4, y + 3, mz), Enum.Material.Metal, COL.Aco)
			part(folder, "PeMaca", Vector3.new(2.4, 3, 0.4), cfAt(f, x1 - 4, y + 1.5, mz), Enum.Material.Metal, COL.AcoEscuro, DECO)
			local lencol = part(folder, "Lencol", Vector3.new(3.2, 0.5, 6), cfAt(f, x1 - 4, y + 3.4, mz), Enum.Material.Fabric, Color3.fromRGB(196, 192, 182), DECO)
			lencol.Transparency = 0.05
		end
	end

	-- Sangue: esta é a ala onde a coisa acabou mal.
	bloodPool(folder, at(f, x0 + 5, y, z0 + 5), 4, rng)
	bloodPool(folder, at(f, (x0 + x1) / 2, y, z0 + 12), 3, rng)
	bloodSplat(folder, cfAt(f, x0 + 0.5, y + 4, z0 + 16) * CFrame.Angles(0, math.rad(-90), 0), 4, rng)
	bloodSplat(folder, cfAt(f, (x0 + x1) / 2, y + 5, z0 + 0.5), 3, rng)

	scatterPieces(folder, f, ASSETS.Laboratorio, {
		{ x0 + 4, y, z0 + 8 },
		{ x1 - 4, y, z0 + 4 },
	}, Vector3.new(5.5, 6.5, 5.5), rng)

	S.LootPoint(folder, cfAt(f, x0 + 4, y + 1, z0 + 4))
	S.LootPoint(folder, cfAt(f, x1 - 4, y + 1, z1 - 4))
	lamp(folder, cfAt(f, (x0 + x1) / 2, y + h - 0.6, z0 + 6), 0.5, rng)
	lamp(folder, cfAt(f, (x0 + x1) / 2, y + h - 0.6, z1 - 6), 0.6, rng)
	for i = 1, 3 do
		moisture(folder, cfAt(f, x1 - 0.5, y + rng:NextNumber(2, h - 3), rng:NextNumber(z0 + 3, z1 - 3)) * CFrame.Angles(0, math.rad(-90), 0), rng:NextNumber(2, 3.5), rng)
	end
	sign(folder, cfAt(f, (x0 + x1) / 2, y + h - 2, z0 + 0.6), 8, 2.6, "ALA CLÍNICA", "QUARENTENA  ·  NÍVEL -2")
	marker(folder, "ZonaClinica", at(f, (x0 + x1) / 2, y + 2, (z0 + z1) / 2), { AbismoZona = "NivelMenos2", AbismoSala = "Clinica" })
end

--------------------------------------------------------------------------------
-- Câmara de bombas: antessala do túnel
--------------------------------------------------------------------------------

--[[
	buildPumpRoom(...)
	A sala que explica a comporta: é daqui que se bombeava a água do túnel
	marítimo. Também é o último ambiente largo antes do gargalo -- bom lugar
	pra uma perseguição futura virar, e o gancho natural pro sistema de
	inundação (AbismoAlagavel já está no marcador).
]]
local function buildPumpRoom(parent: Instance, f: Frame, rng: Random)
	local folder = Instance.new("Folder")
	folder.Name = "CamaraDeBombas"
	folder.Parent = parent

	local C = CONFIG
	local y, h = C.NivelMenos2, C.AlturaSala
	local x, z0, z1 = C.BombasX, C.CorredorZ1, C.BombasZ1
	local tone = COL.ConcretoSujo

	roomShell(folder, f, {
		x0 = -x,
		x1 = x,
		z0 = z0,
		z1 = z1,
		y = y,
		h = h,
		color = tone,
		name = "Bombas",
		vaosZMin = { { a0 = -C.CorredorX, a1 = C.CorredorX, y0 = y, y1 = y + h } },
		vaosZMax = { { a0 = -C.LarguraTunel / 2, a1 = C.LarguraTunel / 2, y0 = y, y1 = y + C.AlturaPorta } },
	})
	assetDoor(folder, f, 0, y, z1, C.LarguraTunel, C.AlturaPorta, false, "Bombas")

	-- Bombas e coletores.
	for i = -1, 1, 2 do
		local bx = i * 8
		part(folder, "Bomba", Vector3.new(4.5, 4.5, 6), cfAt(f, bx, y + 2.25, z0 + 5), Enum.Material.Metal, COL.Aco:Lerp(COL.Ferrugem, 0.4))
		part(folder, "MotorBomba", Vector3.new(2.6, 2.6, 3), cfAt(f, bx, y + 5.8, z0 + 5), Enum.Material.Metal, COL.AcoEscuro)
		pipeRun(folder, at(f, bx, y + 3, z0 + 8), at(f, bx, y + 3, z1 - 1), 0.9, COL.Cano:Lerp(COL.Ferrugem, 0.5), 0.1)
		part(folder, "Valvula", Vector3.new(2.2, 0.3, 2.2), cfAt(f, bx, y + 4.4, z0 + 9) * CFrame.Angles(math.rad(90), 0, 0), Enum.Material.Metal, COL.FerrugemClara, DECO)
	end
	part(folder, "Coletor", Vector3.new(2 * x - 4, 1.4, 1.4), cfAt(f, 0, y + h - 2, z0 + 3), Enum.Material.Metal, COL.Cano:Lerp(COL.Ferrugem, 0.5), DECO)
	part(folder, "PainelBombas", Vector3.new(0.6, 5, 6), cfAt(f, -x + 0.8, y + 3.5, z1 - 4), Enum.Material.Metal, COL.AcoEscuro)

	scatterPieces(folder, f, ASSETS.Complexo, {
		{ x - 4, y, z1 - 4 },
		{ -x + 4, y, z0 + 3 },
	}, Vector3.new(5, 6, 5), rng)

	for _ = 1, 3 do
		puddle(folder, at(f, rng:NextNumber(-x + 3, x - 3), y, rng:NextNumber(z0 + 3, z1 - 3)), rng:NextNumber(2, 4), rng)
	end
	drip(folder, at(f, 3, y + h - 0.3, z1 - 5), y, rng)
	lamp(folder, cfAt(f, 0, y + h - 0.6, z0 + 4), 0.55, rng)
	lamp(folder, cfAt(f, 0, y + h - 0.6, z1 - 4), 0.7, rng)
	sign(folder, cfAt(f, 0, y + C.AlturaPorta + 1.4, z1 - 0.8), 10, 2.8, "TÚNEL DE EVACUAÇÃO", "ACESSO MARÍTIMO  ·  SAÍDA DE EMERGÊNCIA")
	S.LootPoint(folder, cfAt(f, -x + 3, y + 1, z1 - 4))
	marker(folder, "ZonaBombas", at(f, 0, y + 2, (z0 + z1) / 2), { AbismoZona = "Bombas", AbismoAlagavel = true, NivelAguaCheio = Layout.CONFIG.SeaLevel })
end

--------------------------------------------------------------------------------
-- Túnel de evacuação, comporta e trecho alagado
--------------------------------------------------------------------------------

--[[
	tunnelSection(...)
	UM trecho do túnel. `decay` (0..1) controla tudo que se degrada: cor do
	concreto, ferrugem, umidade, rachadura, poça e chance da lâmpada estar
	queimada. Chamar em sequência com decay crescente é o que faz o túnel
	piorar conforme se aproxima do mar, sem escrever cada metro na mão.

	A seção é FECHADA (piso, teto e duas paredes) como todo o resto: o túnel
	é a parte mais perto da superfície da praia, e é justamente onde a areia
	apareceria se faltasse acabamento.
]]
local function tunnelSection(parent: Instance, f: Frame, z: number, len: number, floorY: number, width: number, height: number, decay: number, rng: Random)
	local tone = COL.Concreto:Lerp(COL.ConcretoVelho, decay)
	local mid = z + len / 2

	part(parent, "PisoTunel", Vector3.new(width, 0.7, len), cfAt(f, 0, floorY - 0.35, mid), Enum.Material.Concrete, tone)
	part(parent, "TetoTunel", Vector3.new(width, 0.7, len), cfAt(f, 0, floorY + height + 0.35, mid), Enum.Material.Concrete, tone:Lerp(Color3.new(0, 0, 0), 0.3))
	for _, sx in { -1, 1 } do
		part(parent, "ParedeTunel", Vector3.new(0.7, height, len), cfAt(f, sx * width / 2, floorY + height / 2, mid), Enum.Material.Concrete, tone)
	end

	-- Cavalete estrutural: dá ritmo ao corredor e escala de leitura.
	local ribColor = COL.Aco:Lerp(COL.Ferrugem, decay)
	for _, sx in { -1, 1 } do
		part(parent, "Montante", Vector3.new(0.45, height, 0.5), cfAt(f, sx * (width / 2 - 0.5), floorY + height / 2, z + 0.6), Enum.Material.Metal, ribColor, DECO)
	end
	part(parent, "Travessa", Vector3.new(width - 1, 0.45, 0.5), cfAt(f, 0, floorY + height - 0.3, z + 0.6), Enum.Material.Metal, ribColor, DECO)

	-- Canos numa parede, cabos na outra.
	local pipeY = floorY + height - 1.6
	pipeRun(parent, at(f, -width / 2 + 0.9, pipeY, z), at(f, -width / 2 + 0.9, pipeY, z + len), 0.5, COL.Cano:Lerp(COL.Ferrugem, decay), 0.12)
	pipeRun(parent, at(f, -width / 2 + 0.9, pipeY - 0.9, z), at(f, -width / 2 + 0.9, pipeY - 0.9, z + len), 0.34, COL.CanoVerde:Lerp(COL.Ferrugem, decay), 0.1)
	pipeRun(parent, at(f, width / 2 - 0.8, pipeY, z), at(f, width / 2 - 0.8, pipeY, z + len), 0.18, COL.Cabo, 0.5)
	pipeRun(parent, at(f, width / 2 - 0.8, pipeY - 0.5, z), at(f, width / 2 - 0.8, pipeY - 0.5, z + len), 0.14, COL.Cabo, 0.7)

	lamp(parent, cfAt(f, 0, floorY + height - 0.6, mid), decay, rng)

	-- Degradação.
	local marks = 1 + math.floor(decay * 3)
	for _ = 1, marks do
		local sx = if rng:NextNumber() < 0.5 then -1 else 1
		local wallCF = cfAt(f, sx * (width / 2 - 0.45), floorY + rng:NextNumber(1.5, height - 1.5), z + rng:NextNumber(1, len - 1))
			* CFrame.Angles(0, if sx < 0 then math.pi / 2 else -math.pi / 2, 0)
		moisture(parent, wallCF, rng:NextNumber(1.4, 3) * (0.6 + decay), rng)
		if rng:NextNumber() < 0.4 + decay * 0.4 then
			crack(parent, wallCF * CFrame.new(rng:NextNumber(-1, 1), 1.5, 0), rng:NextNumber(1.5, 3.5), rng)
		end
	end

	if rng:NextNumber() < decay * 1.2 then
		puddle(parent, at(f, rng:NextNumber(-width / 2 + 1.5, width / 2 - 1.5), floorY, z + rng:NextNumber(1, len - 1)), rng:NextNumber(1.4, 3.2), rng)
	end
	if rng:NextNumber() < decay then
		drip(parent, at(f, rng:NextNumber(-2, 2), floorY + height - 0.2, z + rng:NextNumber(1, len - 1)), floorY, rng)
	end
end

local TUNEL_ALTURA = 10

local function buildEvacTunnel(parent: Instance, f: Frame, rng: Random)
	local folder = Instance.new("Folder")
	folder.Name = "TunelEvacuacao"
	folder.Parent = parent

	local C = CONFIG
	local y = C.NivelMenos2
	local z0, z1 = C.BombasZ1, C.TunelZ1
	local sections = 4
	local len = (z1 - z0) / sections

	for i = 0, sections - 1 do
		-- Degradação sobe a cada trecho: é o "quanto mais perto do mar, pior".
		local decay = 0.3 + (i / sections) * 0.45
		tunnelSection(folder, f, z0 + i * len, len, y, C.LarguraTunel, TUNEL_ALTURA, decay, rng)
	end

	sign(folder, cfAt(f, C.LarguraTunel / 2 - 0.5, y + 6, z0 + 12) * CFrame.Angles(0, math.rad(90), 0), 4.5, 2, "SAÍDA DE EMERGÊNCIA", "→ 60 m")
	sign(folder, cfAt(f, -C.LarguraTunel / 2 + 0.5, y + 6, z0 + 22) * CFrame.Angles(0, math.rad(-90), 0), 4.5, 2, "NÍVEL -2", "ACESSO MARÍTIMO")
	marker(folder, "ZonaTunel", at(f, 0, y + 2, (z0 + z1) / 2), { AbismoZona = "Tunel", AbismoAlagavel = true, NivelAguaCheio = Layout.CONFIG.SeaLevel })
end

--[[
	buildBulkhead(...)
	A comporta estanque. É ela que explica por que o túnel atrás está seco e
	o da frente está cheio d'água -- e é o gancho óbvio pro evento de
	inundação que o pedido deixou pra depois.

	O batente é uma MOLDURA (wallZ com vão), não uma laje. Uma parede cheia
	aqui fecharia o túnel de vez: nem com a porta aberta daria pra passar.
]]
local function buildBulkhead(parent: Instance, f: Frame)
	local folder = Instance.new("Folder")
	folder.Name = "Comporta"
	folder.Parent = parent

	local C = CONFIG
	local y = C.NivelMenos2
	local z = C.TunelZ1

	wallZ(folder, f, z, -5.5, 5.5, y, y + TUNEL_ALTURA, COL.Aco:Lerp(COL.Ferrugem, 0.45), { { a0 = -3, a1 = 3, y0 = y, y1 = y + 8 } }, 1.6, Enum.Material.Metal)
	for _, sx in { -1, 1 } do
		part(folder, "MontanteComporta", Vector3.new(1, 8, 2), cfAt(f, sx * 3.5, y + 4, z), Enum.Material.Metal, COL.Ferrugem, DECO)
	end
	part(folder, "VergaComporta", Vector3.new(8, 1.2, 2), cfAt(f, 0, y + 8.4, z), Enum.Material.Metal, COL.Ferrugem, DECO)

	local doorCF = cfAt(f, 0, y + 4, z)
	local door = part(folder, "Porta", Vector3.new(6, 8, 0.5), doorCF, Enum.Material.DiamondPlate, COL.Aco:Lerp(COL.Ferrugem, 0.3))
	door:SetAttribute("Porta", true)
	door:SetAttribute("PortaAberta", false)
	door:SetAttribute("CFrameFechada", doorCF)
	door:SetAttribute("LarguraPorta", 6)
	door:SetAttribute("AbismoComporta", true)
	part(folder, "VolanteComporta", Vector3.new(2.8, 0.35, 2.8), doorCF * CFrame.new(0, 0, -0.45) * CFrame.Angles(math.rad(90), 0, 0), Enum.Material.Metal, COL.FerrugemClara, DECO)

	sign(folder, cfAt(f, 0, y + TUNEL_ALTURA - 0.9, z - 1.2), 7, 2.2, "ACESSO MARÍTIMO", "ALÉM DESTE PONTO: ALAGADO")
end

local function buildFlooded(parent: Instance, f: Frame, rng: Random)
	local folder = Instance.new("Folder")
	folder.Name = "TrechoAlagado"
	folder.Parent = parent

	local C = CONFIG
	local y = C.NivelMenos2
	local z0, z1 = C.TunelZ1, C.AlagadoZ1
	local sections = 3
	local len = (z1 - z0) / sections

	for i = 0, sections - 1 do
		-- Praticamente tudo apagado e enferrujado: aqui já é nado.
		tunnelSection(folder, f, z0 + i * len, len, y, C.LarguraTunel, TUNEL_ALTURA, 0.85 + i * 0.05, rng)
	end

	-- Sinais de que a água venceu: canos rompidos e grades caídas.
	for _ = 1, 4 do
		local z = z0 + rng:NextNumber(2, z1 - z0 - 2)
		part(folder, "CanoRompido", Vector3.new(0.6, 0.6, rng:NextNumber(3, 6)), cfAt(f, rng:NextNumber(-3, 3), y + rng:NextNumber(1, 7), z) * CFrame.Angles(rng:NextNumber(-0.6, 0.6), rng:NextNumber(0, TAU), 0), Enum.Material.CorrodedMetal, COL.Ferrugem, DECO)
	end
	for _ = 1, 3 do
		part(folder, "GradeCaida", Vector3.new(4, 0.2, 3), cfAt(f, rng:NextNumber(-2.5, 2.5), y + 0.3, z0 + rng:NextNumber(2, z1 - z0 - 2)) * CFrame.Angles(0, rng:NextNumber(0, TAU), rng:NextNumber(-0.2, 0.2)), Enum.Material.CorrodedMetal, COL.Ferrugem, DECO)
	end

	-- COLAR DA BOCA DO TÚNEL: tapa a folga entre a seção de concreto e a
	-- rocha da caverna. Sem ele, quem está na caverna enxerga o vazio
	-- escavado em volta do túnel -- e é exatamente lá que o terreno da praia
	-- apareceria.
	wallZ(folder, f, z1, -7.5, 7.5, C.PisoCaverna, y + TUNEL_ALTURA + 2, COL.ConcretoVelho, {
		{ a0 = -C.LarguraTunel / 2 + 0.4, a1 = C.LarguraTunel / 2 - 0.4, y0 = y, y1 = y + TUNEL_ALTURA - 0.7 },
	}, 1.2)

	marker(folder, "ZonaAlagada", at(f, 0, y + 4, (z0 + z1) / 2), { AbismoZona = "Alagado", AbismoAlagavel = true, NivelAguaCheio = Layout.CONFIG.SeaLevel })
end

--------------------------------------------------------------------------------
-- Caverna costeira e a boca no mar
--------------------------------------------------------------------------------

local function buildSeaCave(parent: Instance, f: Frame, rng: Random)
	local folder = Instance.new("Folder")
	folder.Name = "CavernaCosteira"
	folder.Parent = parent

	local C = CONFIG
	local y = C.NivelMenos2
	local zc = C.CavernaZ0
	local seaLevel = Layout.CONFIG.SeaLevel

	-- GRADE ANTIGA: o último obstáculo antes da caverna. Abre pelo
	-- DoorSystem, então dá pra passar nos dois sentidos -- inclusive vindo
	-- do mar, que era o pedido.
	local gateCF = cfAt(f, 0, y + 4, zc - 2.5)
	local gate = part(folder, "Porta", Vector3.new(6, 8, 0.35), gateCF, Enum.Material.CorrodedMetal, COL.Ferrugem)
	gate:SetAttribute("Porta", true)
	gate:SetAttribute("PortaAberta", false)
	gate:SetAttribute("CFrameFechada", gateCF)
	gate:SetAttribute("LarguraPorta", 6)
	gate:SetAttribute("AbismoGradeMar", true)
	for i = 1, 5 do
		part(folder, "BarraGrade", Vector3.new(0.22, 7.4, 0.22), gateCF * CFrame.new(-2.4 + i * 0.8, 0, -0.25), Enum.Material.CorrodedMetal, COL.FerrugemClara, DECO)
	end
	sign(folder, cfAt(f, 0, y + TUNEL_ALTURA - 0.8, zc - 3.4), 6, 2.2, "SAÍDA DE EMERGÊNCIA", "ACESSO MARÍTIMO")

	-- Dentro da caverna: rocha natural, estalactites e pedregulhos. Nada de
	-- concreto daqui pra frente -- a estação acabou.
	for i = 1, 16 do
		local px = rng:NextNumber(-8, 8)
		local pz = zc + rng:NextNumber(1, 15)
		local len = rng:NextNumber(2, 6)
		part(folder, "Estalactite_" .. i, Vector3.new(rng:NextNumber(0.8, 2), len, rng:NextNumber(0.8, 2)), cfAt(f, px, C.TetoCaverna - len / 2, pz) * CFrame.Angles(rng:NextNumber(-0.15, 0.15), rng:NextNumber(0, TAU), rng:NextNumber(-0.15, 0.15)), Enum.Material.Rock, COL.Rocha, DECO)
	end
	for i = 1, 12 do
		local s = rng:NextNumber(2, 6)
		part(folder, "Pedregulho_" .. i, Vector3.new(s, s * rng:NextNumber(0.6, 1), s * rng:NextNumber(0.7, 1.2)), cfAt(f, rng:NextNumber(-8, 8), C.PisoCaverna + s * 0.3, zc + rng:NextNumber(2, 15)) * CFrame.Angles(rng:NextNumber(-0.3, 0.3), rng:NextNumber(0, TAU), rng:NextNumber(-0.3, 0.3)), Enum.Material.Rock, COL.Rocha:Lerp(COL.Musgo, rng:NextNumber(0, 0.35)))
	end

	-- Uma luz fraca sobrevivente logo depois da grade, e o resto é escuro.
	lamp(folder, cfAt(f, 0, seaLevel + 2.5, zc + 3), 0.9, rng)

	-- ESTRUTURA METÁLICA ARREBENTADA na boca: é o que faz a abertura parecer
	-- proposital vista do mar, sem virar "porta na praia".
	for i = 1, 4 do
		part(folder, "VigaBoca_" .. i, Vector3.new(0.5, rng:NextNumber(4, 9), 0.5), cfAt(f, -3.5 + i * 2, rng:NextNumber(-4, 2), C.BocaZ - 1) * CFrame.Angles(rng:NextNumber(-0.4, 0.4), 0, rng:NextNumber(-0.5, 0.5)), Enum.Material.CorrodedMetal, COL.Ferrugem, DECO)
	end
	part(folder, "GradeArrebentada", Vector3.new(7, 5, 0.3), cfAt(f, 1, -2, C.BocaZ - 0.5) * CFrame.Angles(math.rad(28), 0, math.rad(14)), Enum.Material.CorrodedMetal, COL.Ferrugem, DECO)

	-- Pedras quebrando a silhueta da boca: de fora parece só uma fresta
	-- escura entre as pedras, não uma entrada.
	for i = 1, 10 do
		local s = rng:NextNumber(4, 9)
		local px = (if i % 2 == 0 then 1 else -1) * rng:NextNumber(5, 11)
		part(folder, "PedraBoca_" .. i, Vector3.new(s, s * rng:NextNumber(0.8, 1.5), s), cfAt(f, px, rng:NextNumber(-6, 6), C.BocaZ + rng:NextNumber(-4, 8)) * CFrame.Angles(rng:NextNumber(-0.3, 0.3), rng:NextNumber(0, TAU), rng:NextNumber(-0.3, 0.3)), Enum.Material.Rock, COL.Rocha)
	end

	marker(folder, "ZonaCaverna", at(f, 0, seaLevel, zc + 8), { AbismoZona = "Caverna" })
	marker(folder, "SaidaMar", at(f, 0, seaLevel - 2, C.BocaZ + 4), { AbismoZona = "Mar", AbismoSaidaMaritima = true })
end

--------------------------------------------------------------------------------
-- Montagem
--------------------------------------------------------------------------------

function AbyssStationGenerator.Clear()
	local ilha = Workspace:FindFirstChild("Ilha")
	if not ilha then
		return
	end
	local existing = ilha:FindFirstChild("EstacaoAbismo")
	if existing then
		existing:Destroy()
	end
end

--[[
	Build(seed?)
	Acha o sítio, escava e monta tudo. Modo de EDIÇÃO (escreve terreno E
	baixa os assets do Toolbox) -- rode depois de IslandGenerator.Generate()
	e salve.

	Nada de vegetação é apagado de propósito: a escotilha DEVE ficar entre
	árvores. Só o colar de concreto e as pedras de camuflagem aparecem na
	superfície.
]]
function AbyssStationGenerator.Build(seed: number?): Model?
	AbyssStationGenerator.Clear()

	local f = findSite()
	if not f then
		warn("[Abismo] Não achei um trecho de floresta costeira livre (montanha/clareiras ocupam a volta toda). Regere a ilha com outra seed.")
		return nil
	end

	local rng = Random.new(seed or (Layout.Seed() + 91))
	local model = Instance.new("Model")
	model.Name = "EstacaoAbismo"
	model:SetAttribute("EstacaoAbismo", true)
	model:SetAttribute("Construcao", "Abismo")
	model.Parent = getIlha()

	carve(f)
	task.wait()

	buildHatch(model, f, rng)
	buildShaft(model, f, rng)
	buildLevelMinus1(model, f, rng)
	buildStairs(model, f, rng)
	task.wait()
	buildAtrio(model, f, rng)
	buildCorredor(model, f, rng)
	task.wait()
	buildLaboratorio(model, f, rng)
	buildControle(model, f, rng)
	buildClinica(model, f, rng)
	task.wait()
	buildPumpRoom(model, f, rng)
	buildEvacTunnel(model, f, rng)
	buildBulkhead(model, f)
	buildFlooded(model, f, rng)
	buildSeaCave(model, f, rng)

	local hatch = model:FindFirstChild("Escotilha")
	local primary = hatch and hatch:FindFirstChild("ColarEscotilha")
	if primary and primary:IsA("BasePart") then
		model.PrimaryPart = primary
	end

	local faltando = {}
	for name, id in ASSETS do
		if failedAssets[id] then
			table.insert(faltando, string.format("%s (%d)", name, id))
		end
	end
	if #faltando > 0 then
		warn("[Abismo] Assets que não carregaram (os ambientes caíram na versão de reserva): " .. table.concat(faltando, ", "))
	end

	local mouth = at(f, 0, Layout.CONFIG.SeaLevel, CONFIG.BocaZ)
	print(string.format(
		"[Abismo] Estação montada. Escotilha em (%.0f, %.0f, %.0f); saída no mar em (%.0f, %.0f). Salve o lugar.",
		f.Origin.X, f.Origin.Y, f.Origin.Z, mouth.X, mouth.Z
	))
	if not RunService:IsEdit() then
		warn("[Abismo] Rodou em runtime: o terreno escavado NÃO fica salvo e os assets do Toolbox não carregam. Rode em modo de edição e salve.")
	end
	return model
end

return AbyssStationGenerator
