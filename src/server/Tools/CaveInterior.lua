--!strict
--[[
	CaveInterior (ferramenta de editor)
	O covil do Monstro dentro da montanha: escava o terreno e monta o interior
	em Parts primitivas (nada depende de asset, tudo Anchored).

	Antes era uma bola de terreno de raio 17 num canto da montanha -- pequena,
	lisa e sem nada dentro. A montanha tem Radius 150 e Peak 95 (IslandLayout),
	então dá pra usar MUITO mais espaço: aqui o salão tem raio 40 e 56 studs de
	pé-direito, com TRÊS níveis ligados por rampa, escada e ponte.

	Nível 0 (chão)  -- salão, poço rochoso no meio, câmaras laterais
		Nível 1 (meio)  -- galeria em volta da parede + ponte de tábuas
		Nível 2 (topo)  -- laje larga no fundo com o NINHO (spawn do Monstro)

	O interior não cria iluminação própria. Zonas invisíveis delimitam o efeito
	local de escuridão dos sobreviventes e a visão exclusiva do Monstro.

	ESPAÇO LOCAL: tudo é descrito em coordenadas polares em volta do centro da
	montanha. theta = 90 graus aponta pra BOCA da caverna (o centro da ilha);
	theta = 270 é o fundo. r = distância do eixo, y = altura acima do chão do
	salão.

	Uso (via IslandGenerator.GenerateCave, ou direto no Command Bar):
		local Cave = require(game.ServerScriptService.Server.Tools.CaveInterior)
		local spawn = Cave.Build(folder, frame, seed)
]]

local Workspace = game:GetService("Workspace")
local Terrain = Workspace.Terrain

local S = require(script.Parent.Structures)

local CaveInterior = {}

local TAU = math.pi * 2
local UP = Vector3.yAxis
local UPRIGHT = CFrame.Angles(0, 0, math.pi / 2) -- cilindro em pé (eixo no Y)

local part = S.Part
local beam = S.Beam

--------------------------------------------------------------------------------
-- Medidas
--------------------------------------------------------------------------------

local CONFIG = {
	Tunnel = {
		Width = 13,
		Height = 13,
		Drop = 9, -- quanto o túnel desce da boca até o salão
	},

	Hall = {
		Radius = 40, -- parede do salão (as reentrâncias chegam a ~49)
		WallTop = 40, -- onde a parede reta vira abóbada
		Height = 56, -- topo da abóbada
	},

	Levels = {
		Mid = 17, -- galeria do meio
		Top = 33, -- laje do ninho
	},

	Pit = {
		Theta = 90,
		Dist = 10,
		Radius = 13,
		Depth = 6,
	},

	-- Câmaras laterais (theta, distância do centro, raio).
	Chambers = {
		{ Name = "CamaraMineral", Theta = 178, Dist = 54, Radius = 15 },
		{ Name = "Deposito", Theta = 352, Dist = 52, Radius = 13 },
	},

	Nest = { Theta = 245, Dist = 30, Radius = 10 },
}

CaveInterior.CONFIG = CONFIG

--------------------------------------------------------------------------------
-- Paleta
--------------------------------------------------------------------------------

local COL = {
	Rock = Color3.fromRGB(78, 76, 74),
	RockDark = Color3.fromRGB(54, 53, 52),
	RockWarm = Color3.fromRGB(86, 78, 68),
	Gravel = Color3.fromRGB(62, 58, 52),
	Mud = Color3.fromRGB(48, 40, 32),
	Mineral = Color3.fromRGB(126, 145, 153),
	Wood = Color3.fromRGB(74, 54, 36),
	WoodDark = Color3.fromRGB(52, 38, 26),
	Rope = Color3.fromRGB(138, 118, 84),
	Metal = Color3.fromRGB(62, 58, 54),
	Rust = Color3.fromRGB(92, 58, 38),
	Rag = Color3.fromRGB(88, 78, 66),
	Fungus = Color3.fromRGB(42, 69, 62),
}

CaveInterior.Colors = COL

local ROCK_MATERIALS = {
	Enum.Material.Rock,
	Enum.Material.Slate,
	Enum.Material.Basalt,
	Enum.Material.Cobblestone,
	Enum.Material.Limestone,
}

--------------------------------------------------------------------------------
-- Espaço local (polar em volta do centro da montanha)
--------------------------------------------------------------------------------

export type Frame = {
	Center: Vector3, -- centro da montanha com Y = 0 (a altura vem de FloorY)
	Dir: Vector3, -- do centro da montanha pra boca (unitário, horizontal)
	Side: Vector3, -- perpendicular a Dir
	FloorY: number, -- Y do chão do salão
	MouthY: number, -- Y do chão da boca (mais alto: o túnel desce)
	MouthDist: number, -- distância do centro até a boca
	SurfaceY: (number, number) -> number, -- altura do terreno real em (x, z)
	PlanY: (number, number) -> number, -- altura do relevo SEM escavação nenhuma
}

local function at(f: Frame, x: number, y: number, z: number): Vector3
	return f.Center + f.Side * x + f.Dir * z + Vector3.new(0, f.FloorY + y, 0)
end

-- Vetor radial (pra fora) no ângulo theta.
local function radial(f: Frame, thetaDeg: number): Vector3
	local t = math.rad(thetaDeg)
	return f.Side * math.cos(t) + f.Dir * math.sin(t)
end

-- Ponto na coordenada polar do salão.
local function polar(f: Frame, thetaDeg: number, dist: number, y: number): Vector3
	return at(f, 0, y, 0) + radial(f, thetaDeg) * dist
end

-- CFrame com X local = radial (fundo), Y = cima, Z = tangente (theta caindo).
local function radialCF(f: Frame, thetaDeg: number, dist: number, y: number): CFrame
	return CFrame.fromMatrix(polar(f, thetaDeg, dist, y), radial(f, thetaDeg), UP)
end

--------------------------------------------------------------------------------
-- Terreno
--------------------------------------------------------------------------------

local AIR = Enum.Material.Air

local function airBall(center: Vector3, radius: number)
	Terrain:FillBall(center, radius, AIR)
end

local function airBlock(cf: CFrame, size: Vector3)
	Terrain:FillBlock(cf, size, AIR)
end

-- Cilindro vertical de ar entre duas alturas do mundo.
local function airColumn(x: number, z: number, yBottom: number, yTop: number, radius: number)
	local h = yTop - yBottom
	if h <= 0.1 or radius <= 0.1 then
		return
	end
	Terrain:FillCylinder(CFrame.new(x, yBottom + h * 0.5, z), h, radius, AIR)
end

-- Túnel entre dois pontos (o chão do túnel passa exatamente pelos pontos).
local function carveTunnel(a: Vector3, b: Vector3, width: number, height: number)
	local lift = Vector3.new(0, height * 0.5, 0)
	local from, to = a + lift, b + lift
	local len = (to - from).Magnitude
	if len < 0.5 then
		return
	end
	local cf = CFrame.lookAt((from + to) * 0.5, to)
	airBlock(cf, Vector3.new(width, height, len))
	-- Arredonda as pontas pra junção não ficar em quina.
	airBall(from + Vector3.new(0, height * 0.06, 0), width * 0.56)
	airBall(to + Vector3.new(0, height * 0.06, 0), width * 0.56)
end

-- Caminho do túnel: boca (fora da rocha), dois cotovelos e a entrada do
-- salão. O chão do túnel passa exatamente por estes pontos -- a escavação e a
-- decoração usam a MESMA lista pra não sair de sincronia.
local function tunnelWaypoints(f: Frame): { Vector3 }
	local mouthY = f.MouthY - f.FloorY
	return {
		at(f, 0, mouthY, f.MouthDist + 7),
		at(f, 0, mouthY, f.MouthDist - 4),
		at(f, 12, mouthY * 0.5, f.MouthDist - 27),
		at(f, 6, mouthY * 0.17, f.MouthDist - 49),
		at(f, 0, 0.2, CONFIG.Hall.Radius - 3),
	}
end

--[[
	resealMountain(f)
	Devolve rocha maciça ao miolo da montanha ANTES de escavar, pra apagar
	qualquer caverna anterior (a versão antiga era um túnel reto com uma bola
	de raio 17 no fim -- sem isso, sobrariam buracos soltos na parede).

	O teto de cada anel vem de PlanY (o relevo calculado, que não enxerga
	escavação -- um raycast cairia dentro do buraco velho e encheria de menos)
	e fica 2 studs abaixo da superfície, então a montanha vista de fora não
	muda. Anéis do maior raio (mais baixo) pro menor (mais alto): o de dentro
	sempre sobrescreve o de fora.
]]
local function resealMountain(f: Frame)
	local bottom = f.FloorY - 14
	local ceiling = f.FloorY + CONFIG.Hall.Height + 6
	local samples = 8

	for r = 110, 6, -6 do
		local lowest = math.huge
		for i = 1, samples do
			local p = polar(f, (i - 1) * (360 / samples), r, 0)
			lowest = math.min(lowest, f.PlanY(p.X, p.Z))
		end
		local top = math.min(lowest - 2, ceiling)
		if top > bottom then
			Terrain:FillCylinder(CFrame.new(f.Center.X, (bottom + top) * 0.5, f.Center.Z), top - bottom, r, Enum.Material.Rock)
		end
	end
	-- Tampa a fenda de luz de versões antigas sem abrir um novo buraco na superfície.
	local oldShaft = polar(f, 245, 30, 0)
	local capBottom = f.FloorY + CONFIG.Hall.Height - 2
	local capTop = f.PlanY(oldShaft.X, oldShaft.Z) - 2
	if capTop > capBottom then
		Terrain:FillCylinder(CFrame.new(oldShaft.X, (capBottom + capTop) * 0.5, oldShaft.Z), capTop - capBottom, 4.5, Enum.Material.Rock)
	end
	task.wait()
end

--[[
	Carve(f, rng)
	Escava a caverna inteira no terreno da montanha: boca, túnel quebrado em
	três trechos (não dá pra ver o salão da entrada), o salão com parede
	recortada e abóbada, o poço e as câmaras laterais.
]]
function CaveInterior.Carve(f: Frame, rng: Random)
	local H = CONFIG.Hall
	local T = CONFIG.Tunnel
	local floorY = f.FloorY

	resealMountain(f)

	----------------------------------------------------------------------------
	-- Boca + túnel em S, descendo até o salão.
	----------------------------------------------------------------------------
	local waypoints = tunnelWaypoints(f)
	for i = 1, #waypoints - 1 do
		carveTunnel(waypoints[i], waypoints[i + 1], T.Width, T.Height)
	end

	-- Arco alto na boca e um vestíbulo no primeiro cotovelo.
	airBall(waypoints[2] + Vector3.new(0, T.Height * 0.72, 0), 7.5)
	airBall(waypoints[3] + Vector3.new(0, 7, 0), 11)

	----------------------------------------------------------------------------
	-- Salão: cilindro até WallTop, depois abóbada elipsoidal.
	----------------------------------------------------------------------------
	local cx, cz = f.Center.X, f.Center.Z
	airColumn(cx, cz, floorY, floorY + H.WallTop, H.Radius)

	local domeSpan = H.Height - H.WallTop
	local step = 2
	for y = H.WallTop, H.Height, step do
		local k = (y - H.WallTop) / domeSpan
		local r = H.Radius * math.sqrt(math.max(1 - k * k, 0))
		airColumn(cx, cz, floorY + y, floorY + y + step, r)
	end

	-- Parede recortada: bolsões verticais na borda tiram o ar de "cano".
	for i = 1, 16 do
		local theta = (i - 1) * (360 / 16) + rng:NextNumber(-7, 7)
		local p = polar(f, theta, H.Radius, 0)
		local r = rng:NextNumber(7, 12)
		local yBottom = rng:NextNumber(0, 6)
		local yTop = math.min(rng:NextNumber(18, H.WallTop), H.WallTop)
		airColumn(p.X, p.Z, floorY + yBottom, floorY + yTop, r)
		if i % 4 == 0 then
			task.wait()
		end
	end

	-- Algumas bolhas soltas pra quebrar a simetria da abóbada.
	for i = 1, 7 do
		local theta = rng:NextNumber(0, 360)
		local dist = rng:NextNumber(H.Radius * 0.5, H.Radius * 0.95)
		local y = rng:NextNumber(H.WallTop - 12, H.Height - 10)
		airBall(polar(f, theta, dist, y), rng:NextNumber(7, 12))
	end

	----------------------------------------------------------------------------
	-- Poço no meio do salão.
	----------------------------------------------------------------------------
	local P = CONFIG.Pit
	local pit = polar(f, P.Theta, P.Dist, 0)
	airColumn(pit.X, pit.Z, floorY - P.Depth, floorY + 2, P.Radius)
	airBall(pit + Vector3.new(0, -P.Depth * 0.5, 0), P.Radius * 0.7)

	----------------------------------------------------------------------------
	-- Câmaras laterais + corredor ligando ao salão.
	----------------------------------------------------------------------------
	for _, c in CONFIG.Chambers do
		local center = polar(f, c.Theta, c.Dist, c.Radius * 0.45)
		airBall(center, c.Radius)
		airBall(center + Vector3.new(0, -c.Radius * 0.3, 0), c.Radius * 0.86)
		airColumn(center.X, center.Z, floorY, floorY + c.Radius * 0.9, c.Radius * 0.78)
		carveTunnel(
			polar(f, c.Theta, H.Radius - 6, 0.2),
			polar(f, c.Theta, c.Dist, 0.2),
			10,
			11
		)
	end

	task.wait()
end

--------------------------------------------------------------------------------
-- Primitivas de cenário
--------------------------------------------------------------------------------

local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Include
rayParams.FilterDescendantsInstances = { Terrain }
rayParams.IgnoreWater = true

-- Raycast só no terreno (a rocha da caverna). Serve pra colar estalactite
-- e fungo exatamente na superfície escavada.
local function castTerrain(from: Vector3, direction: Vector3, dist: number): RaycastResult?
	if direction.Magnitude < 1e-4 then
		return nil
	end
	return Workspace:Raycast(from, direction.Unit * dist, rayParams)
end

local function rockTone(rng: Random): Color3
	local v = rng:NextInteger(58, 92)
	return Color3.fromRGB(v, v - rng:NextInteger(0, 4), v - rng:NextInteger(0, 8))
end

local function rockMaterial(rng: Random): Enum.Material
	return ROCK_MATERIALS[rng:NextInteger(1, #ROCK_MATERIALS)]
end

-- Disco fino deitado (cilindro em pé com "altura" mínima).
local function disc(parent: Instance, name: string, center: Vector3, diameter: number, thickness: number, yaw: number, material: Enum.Material, color: Color3): Part
	local p = part(
		parent,
		name,
		Vector3.new(thickness, diameter, diameter),
		CFrame.new(center) * CFrame.Angles(0, yaw, 0) * UPRIGHT,
		material,
		color,
		{ Shape = Enum.PartType.Cylinder, CanCollide = false, CastShadow = false }
	)
	return p
end

--[[
	arcRun(...)
	Trecho de laje curva colada na parede: de theta0 a theta1 (pode ser
	decrescente), subindo de y0 a y1, ocupando a faixa radial rIn..rOut.
	Cada passo vira uma Part inclinada -- é com isso que a rampa, a galeria,
	a escada e a laje do ninho são feitas.
]]
local function arcRun(
	parent: Instance,
	f: Frame,
	name: string,
	theta0: number,
	theta1: number,
	y0: number,
	y1: number,
	rIn: number,
	rOut: number,
	steps: number,
	thickness: number,
	rng: Random
): { Part }
	local out = {}
	local delta = theta1 - theta0
	local rMid = (rIn + rOut) * 0.5
	local depth = rOut - rIn
	local segDeg = delta / steps
	local segLen = math.abs(math.rad(segDeg)) * rMid
	local rise = (y1 - y0) / steps
	-- radialCF deixa o +Z local apontando pro lado do theta CRESCENTE, e
	-- CFrame.Angles(a, 0, 0) com a > 0 abaixa esse +Z. Então, quando a laje
	-- sobe junto com theta, o ângulo tem que ser negativo (e vice-versa).
	local pitch = -math.atan2(rise * (if delta >= 0 then 1 else -1), segLen)

	for i = 0, steps - 1 do
		local tA = theta0 + segDeg * i
		local mid = tA + segDeg * 0.5
		local yTop = y0 + rise * (i + 0.5)
		local cf = radialCF(f, mid, rMid, yTop - thickness * 0.5) * CFrame.Angles(pitch, 0, 0)
		local p = part(
			parent,
			name .. "_" .. (i + 1),
			Vector3.new(depth, thickness, segLen + 0.8),
			cf,
			rockMaterial(rng),
			rockTone(rng)
		)
		table.insert(out, p)
	end
	return out
end

-- Degraus de rocha num arco (cada degrau é uma laje plana mais alta).
local function arcStairs(
	parent: Instance,
	f: Frame,
	name: string,
	theta0: number,
	theta1: number,
	y0: number,
	y1: number,
	rIn: number,
	rOut: number,
	steps: number,
	rng: Random
)
	local delta = theta1 - theta0
	local rMid = (rIn + rOut) * 0.5
	local segDeg = delta / steps
	local segLen = math.abs(math.rad(segDeg)) * rMid
	for i = 0, steps - 1 do
		local mid = theta0 + segDeg * (i + 0.5)
		local yTop = y0 + (y1 - y0) * ((i + 1) / steps)
		local h = 2.4 + (yTop - y0) * 0.02
		part(
			parent,
			name .. "_" .. (i + 1),
			Vector3.new(rOut - rIn, h, segLen + 1.2),
			radialCF(f, mid, rMid, yTop - h * 0.5),
			rockMaterial(rng),
			rockTone(rng)
		)
	end
end

-- Pilar/escora de rocha do chão até embaixo de uma laje.
local function pillar(parent: Instance, name: string, base: Vector3, height: number, diameter: number, rng: Random)
	local segments = math.max(2, math.floor(height / 9))
	local segH = height / segments
	for i = 1, segments do
		local d = diameter * (1 - (i - 1) / segments * 0.25)
		part(
			parent,
			name .. "_" .. i,
			Vector3.new(segH + 0.4, d, d),
			CFrame.new(base + Vector3.new(0, segH * (i - 0.5), 0))
				* CFrame.Angles(0, rng:NextNumber(0, TAU), 0)
				* UPRIGHT,
			rockMaterial(rng),
			rockTone(rng),
			{ Shape = Enum.PartType.Cylinder }
		)
	end
end

-- Espinho de rocha: estalactite (dirSign -1) ou estalagmite (dirSign 1).
local function spike(parent: Instance, name: string, origin: Vector3, dirSign: number, len: number, diameter: number, rng: Random)
	local segments = 3
	local segLen = len / segments
	for i = 1, segments do
		local d = diameter * (1 - (i - 1) / segments * 0.62)
		local y = origin.Y + dirSign * segLen * (i - 0.5)
		part(
			parent,
			name .. "_" .. i,
			Vector3.new(segLen + 0.25, d, d),
			CFrame.new(origin.X, y, origin.Z) * CFrame.Angles(0, rng:NextNumber(0, TAU), 0) * UPRIGHT,
			Enum.Material.Rock,
			rockTone(rng),
			{ Shape = Enum.PartType.Cylinder, CanCollide = false, CastShadow = false }
		)
	end
end

-- Pedregulho meio enterrado.
local function boulder(parent: Instance, name: string, groundPos: Vector3, size: number, rng: Random)
	part(
		parent,
		name,
		Vector3.new(size, size * rng:NextNumber(0.6, 0.95), size * rng:NextNumber(0.75, 1.15)),
		CFrame.new(groundPos + Vector3.new(0, size * 0.28, 0))
			* CFrame.Angles(rng:NextNumber(-0.2, 0.2), rng:NextNumber(0, TAU), rng:NextNumber(-0.2, 0.2)),
		rockMaterial(rng),
		rockTone(rng),
		{ Shape = Enum.PartType.Ball }
	)
end

-- Mancha de cascalho/terra pisada no chão.
local function gravelPatch(parent: Instance, center: Vector3, radius: number, rng: Random)
	for i = 1, rng:NextInteger(2, 4) do
		local off = Vector3.new(rng:NextNumber(-radius, radius) * 0.5, 0, rng:NextNumber(-radius, radius) * 0.5)
		disc(
			parent,
			"Cascalho",
			center + off + Vector3.new(0, 0.06 + i * 0.01, 0),
			radius * rng:NextNumber(0.7, 1.4),
			0.12,
			rng:NextNumber(0, TAU),
			if i % 2 == 0 then Enum.Material.Ground else Enum.Material.Pebble,
			if i % 2 == 0 then COL.Mud else COL.Gravel
		)
	end
end

--------------------------------------------------------------------------------
-- Props: fungo, corrente, jaula, ponte, guarda-corpo
--------------------------------------------------------------------------------

-- Fungo opaco: forma visível quando a lanterna o ilumina.
local function fungusPatch(parent: Instance, hitPos: Vector3, normal: Vector3, rng: Random)
	local base = CFrame.lookAt(hitPos + normal * 0.2, hitPos + normal * 10)
	for i = 1, rng:NextInteger(5, 9) do
		local d = rng:NextNumber(0.3, 0.95)
		part(
			parent,
			"Fungo",
			Vector3.new(d, d, d * 0.7),
			base * CFrame.new(rng:NextNumber(-1.6, 1.6), rng:NextNumber(-1.4, 1.4), rng:NextNumber(0, 0.35)),
			Enum.Material.Slate,
			COL.Fungus,
			{ Shape = Enum.PartType.Ball, CanCollide = false, CastShadow = false }
		)
	end
end

-- Corrente pendurada no teto, com gancho na ponta.
local function hangingChain(parent: Instance, top: Vector3, bottom: Vector3, rng: Random)
	beam(parent, "Corrente", top, bottom, 0.22, Enum.Material.CorrodedMetal, COL.Metal, false)
	for i = 1, 4 do
		local t = i / 5
		local p = top:Lerp(bottom, t)
		part(parent, "Elo", Vector3.new(0.45, 0.45, 0.28), CFrame.new(p) * CFrame.Angles(0, rng:NextNumber(0, TAU), 0), Enum.Material.CorrodedMetal, COL.Metal, {
			Shape = Enum.PartType.Cylinder,
			CanCollide = false,
			CastShadow = false,
		})
	end
	part(parent, "Gancho", Vector3.new(0.24, 1.1, 0.24), CFrame.new(bottom + Vector3.new(0, -0.5, 0)) * CFrame.Angles(0.5, 0, 0), Enum.Material.CorrodedMetal, COL.Rust, {
		CanCollide = false,
		CastShadow = false,
	})
end

-- Jaula de barras retorcidas (sucata do acampamento/avião).
local function cage(parent: Instance, cf: CFrame, width: number, depth: number, height: number, rng: Random)
	local hw, hd = width * 0.5, depth * 0.5
	for _, c in { Vector2.new(-hw, -hd), Vector2.new(hw, -hd), Vector2.new(-hw, hd), Vector2.new(hw, hd) } do
		part(parent, "Coluna", Vector3.new(0.28, height, 0.28), cf * CFrame.new(c.X, height * 0.5, c.Y), Enum.Material.CorrodedMetal, COL.Metal)
	end
	for i = 0, 2 do
		local y = height * (i / 2)
		part(parent, "Aro", Vector3.new(width, 0.2, 0.2), cf * CFrame.new(0, y, -hd), Enum.Material.CorrodedMetal, COL.Metal, { CastShadow = false })
		part(parent, "Aro", Vector3.new(width, 0.2, 0.2), cf * CFrame.new(0, y, hd), Enum.Material.CorrodedMetal, COL.Metal, { CastShadow = false })
		part(parent, "Aro", Vector3.new(0.2, 0.2, depth), cf * CFrame.new(-hw, y, 0), Enum.Material.CorrodedMetal, COL.Metal, { CastShadow = false })
	end
	-- Barras verticais só em dois lados (o resto está arrebentado).
	for i = 1, 4 do
		local x = -hw + width * (i / 5)
		part(parent, "Barra", Vector3.new(0.18, height, 0.18), cf * CFrame.new(x, height * 0.5, -hd) * CFrame.Angles(0, 0, rng:NextNumber(-0.06, 0.06)), Enum.Material.CorrodedMetal, COL.Metal, {
			CastShadow = false,
		})
	end
	part(parent, "PisoJaula", Vector3.new(width, 0.25, depth), cf * CFrame.new(0, 0.12, 0), Enum.Material.Wood, COL.WoodDark)
end

--[[
	plankBridge(...)
	Ponte de tábuas (madeira arrastada do acampamento) ligando dois pontos da
	galeria por cima do salão. O deck é uma laje fina que colide -- as tábuas
	por cima são só aparência, então nenhum buraco engole ninguém.
]]
local function plankBridge(parent: Instance, a: Vector3, b: Vector3, width: number, rng: Random)
	local delta = b - a
	local len = delta.Magnitude
	local mid = (a + b) * 0.5
	local cf = CFrame.lookAt(mid, b)

	part(parent, "Deck", Vector3.new(width, 0.3, len), cf * CFrame.new(0, -0.2, 0), Enum.Material.Wood, COL.WoodDark)
	for _, s in { -1, 1 } do
		part(parent, "Longarina", Vector3.new(0.5, 0.7, len), cf * CFrame.new(s * (width * 0.5 - 0.25), -0.5, 0), Enum.Material.Wood, COL.WoodDark)
	end

	local planks = math.floor(len / 1.4)
	for i = 0, planks - 1 do
		local z = -len * 0.5 + 0.7 + i * 1.4
		local tilt = rng:NextNumber(-0.05, 0.05)
		part(
			parent,
			"Tabua",
			Vector3.new(width * rng:NextNumber(0.88, 1.02), 0.28, 1.15),
			cf * CFrame.new(rng:NextNumber(-0.3, 0.3), 0.1, z) * CFrame.Angles(0, tilt, tilt * 0.5),
			Enum.Material.WoodPlanks,
			if rng:NextNumber() < 0.25 then COL.WoodDark else COL.Wood,
			{ CanCollide = false, CastShadow = false }
		)
	end

	-- Corrimão de corda com postes tortos (alguns faltando).
	local posts = math.max(2, math.floor(len / 7))
	for _, s in { -1, 1 } do
		local prev: Vector3? = nil
		for i = 0, posts do
			local z = -len * 0.5 + (len / posts) * i
			local top = (cf * CFrame.new(s * width * 0.5, 2.6, z)).Position
			if rng:NextNumber() > 0.18 then
				part(parent, "Poste", Vector3.new(0.3, 2.6, 0.3), cf * CFrame.new(s * width * 0.5, 1.3, z) * CFrame.Angles(rng:NextNumber(-0.05, 0.05), 0, rng:NextNumber(-0.07, 0.07)), Enum.Material.Wood, COL.Wood, {
					CastShadow = false,
				})
			end
			if prev then
				beam(parent, "Corda", prev, top, 0.14, Enum.Material.Fabric, COL.Rope, false)
			end
			prev = top
		end
	end
end

-- Guarda-corpo tosco na borda de uma laje curva (postes + corda).
local function arcRail(parent: Instance, f: Frame, theta0: number, theta1: number, r: number, y0: number, y1: number, rng: Random)
	local delta = theta1 - theta0
	local posts = math.max(2, math.floor(math.abs(math.rad(delta)) * r / 7))
	local prev: Vector3? = nil
	for i = 0, posts do
		local t = i / posts
		local theta = theta0 + delta * t
		local y = y0 + (y1 - y0) * t
		local basePos = polar(f, theta, r, y)
		local top = basePos + Vector3.new(0, 2.7, 0)
		if rng:NextNumber() > 0.15 then
			part(
				parent,
				"PosteGaleria",
				Vector3.new(0.34, 2.7, 0.34),
				CFrame.new(basePos + Vector3.new(0, 1.35, 0)) * CFrame.Angles(rng:NextNumber(-0.06, 0.06), math.rad(theta), rng:NextNumber(-0.06, 0.06)),
				Enum.Material.Wood,
				COL.Wood,
				{ CastShadow = false }
			)
		end
		if prev then
			beam(parent, "CordaGaleria", prev, top, 0.15, Enum.Material.Fabric, COL.Rope, false)
			beam(parent, "CordaGaleria", prev - Vector3.new(0, 1.2, 0), top - Vector3.new(0, 1.2, 0), 0.12, Enum.Material.Fabric, COL.Rope, false)
		end
		prev = top
	end
end

-- Escada de treliça (dá pra subir de verdade).
local function trussLadder(parent: Instance, basePos: Vector3, height: number, yaw: number)
	local truss = Instance.new("TrussPart")
	truss.Name = "Escada"
	truss.Size = Vector3.new(2, height, 2)
	truss.CFrame = CFrame.new(basePos + Vector3.new(0, height * 0.5, 0)) * CFrame.Angles(0, yaw, 0)
	truss.Anchored = true
	truss.Material = Enum.Material.Wood
	truss.Color = COL.WoodDark
	truss.Parent = parent
	return truss
end

--------------------------------------------------------------------------------
-- Planta dos três níveis (ângulos em graus; ver a convenção no topo)
--------------------------------------------------------------------------------

local LAYOUT = {
	-- Rampa de rocha do chão até a galeria, colada na parede.
	RampTheta0 = 200,
	RampTheta1 = 280,
	RampIn = 32,
	RampOut = 46,
	RampY0 = 1.5,

	-- Galeria do meio: quase um anel inteiro (fecha o circuito com a rampa).
	GalleryTheta0 = 280,
	GalleryTheta1 = 560, -- = 200 depois de dar a volta
	GalleryIn = 34,
	GalleryOut = 48,

	-- Escada da galeria pra laje de cima, por dentro (sobre o vão).
	StairTheta0 = 350,
	StairTheta1 = 295,
	StairIn = 24,
	StairOut = 34,

	-- Laje do ninho + varanda estreita virada pra entrada.
	ShelfTheta0 = 195,
	ShelfTheta1 = 295,
	ShelfIn = 14,
	ShelfOut = 48,
	BalconyTheta0 = 150,
	BalconyTheta1 = 195,
	BalconyIn = 34,
	BalconyOut = 48,

	-- Ponte de tábuas atravessando o salão por cima do poço.
	BridgeTheta0 = 60,
	BridgeTheta1 = 170,
	BridgeR = 34,
	BridgeWidth = 6,
}

CaveInterior.LAYOUT = LAYOUT

local function folder(parent: Instance, name: string): Folder
	local ff = Instance.new("Folder")
	ff.Name = name
	ff.Parent = parent
	return ff
end

-- Laje inclinada entre dois pontos (rampa reta, escora, tábua solta).
local function slabBetween(parent: Instance, name: string, a: Vector3, b: Vector3, width: number, thickness: number, material: Enum.Material, color: Color3): Part
	local len = (b - a).Magnitude
	local cf = CFrame.lookAt((a + b) * 0.5, b)
	return part(parent, name, Vector3.new(width, thickness, len), cf, material, color)
end

-- Névoa baixa e parada (dá volume ao escuro).
local function mistEmitter(parent: Instance, pos: Vector3, size: number)
	local anchor = part(parent, "Nevoa", Vector3.new(1, 1, 1), CFrame.new(pos), Enum.Material.SmoothPlastic, Color3.new(0, 0, 0), {
		CanCollide = false,
		Transparency = 1,
		CastShadow = false,
	})
	anchor.CanQuery = false
	anchor.CanTouch = false
	local e = Instance.new("ParticleEmitter")
	e.Texture = "rbxasset://textures/particles/smoke_main.dds"
	e.Color = ColorSequence.new(Color3.fromRGB(42, 44, 48))
	e.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(0.35, 0.9),
		NumberSequenceKeypoint.new(1, 1),
	})
	e.Size = NumberSequence.new(size)
	e.Rate = 1.4
	e.Lifetime = NumberRange.new(14, 22)
	e.Speed = NumberRange.new(0.2, 0.8)
	e.SpreadAngle = Vector2.new(180, 180)
	e.Rotation = NumberRange.new(0, 360)
	e.RotSpeed = NumberRange.new(-3, 3)
	e.LightEmission = 0
	e.Parent = anchor
end

--------------------------------------------------------------------------------
-- Túnel de entrada
--------------------------------------------------------------------------------

local function buildTunnel(dest: Instance, f: Frame, rng: Random)
	local pts = tunnelWaypoints(f)
	local mouth = pts[1]

	-- Totem de aviso: dois na encosta, um de cada lado da boca. Ficam no
	-- terreno de fora, então a altura vem da superfície e não do túnel.
	for i = 1, 2 do
		local s = if i == 1 then -1 else 1
		local ground = mouth + f.Side * (s * 11) + f.Dir * 5
		local base = Vector3.new(ground.X, f.SurfaceY(ground.X, ground.Z), ground.Z)
		part(dest, "Totem", Vector3.new(0.7, 7, 0.7), CFrame.new(base + Vector3.new(0, 3.5, 0)) * CFrame.Angles(rng:NextNumber(-0.07, 0.07), rng:NextNumber(0, TAU), rng:NextNumber(-0.07, 0.07)), Enum.Material.Wood, COL.WoodDark)
		part(dest, "TotemPedra", Vector3.new(1.5, 1.5, 1.5), CFrame.new(base + Vector3.new(0, 7.5, 0)), Enum.Material.Rock, COL.Mineral, {
			Shape = Enum.PartType.Ball,
			CanCollide = false,
			CastShadow = false,
		})
		gravelPatch(dest, base, 2.5, rng)
	end

	-- Pedras soltas e fungos discretos pelo caminho todo.
	for i = 1, #pts - 1 do
		local a, b = pts[i], pts[i + 1]
		local dirSeg = (b - a)
		local steps = math.max(2, math.floor(dirSeg.Magnitude / 7))
		local sideSeg = Vector3.new(-dirSeg.Unit.Z, 0, dirSeg.Unit.X)
		for j = 0, steps do
			local p = a:Lerp(b, j / steps)
			for _, s in { -1, 1 } do
				local hit = castTerrain(p + Vector3.new(0, rng:NextNumber(1, 8), 0), sideSeg * s, 14)
				if hit and rng:NextNumber() < 0.25 then
					fungusPatch(dest, hit.Position, hit.Normal, rng)
				end
			end
			if rng:NextNumber() < 0.5 then
				boulder(dest, "RochaTunel", p + sideSeg * rng:NextNumber(-4.5, 4.5), rng:NextNumber(1.5, 3), rng)
			end
		end
		gravelPatch(dest, (a + b) * 0.5, 2.5, rng)
	end

	-- Estalactites no teto do túnel.
	for i = 1, 10 do
		local t = rng:NextNumber(0, 1)
		local seg = rng:NextInteger(1, #pts - 1)
		local p = pts[seg]:Lerp(pts[seg + 1], t)
		local hit = castTerrain(p + Vector3.new(0, 2, 0), UP, 16)
		if hit then
			spike(dest, "Estalactite", hit.Position, -1, rng:NextNumber(1.5, 4), rng:NextNumber(0.5, 1.1), rng)
		end
	end
end

--------------------------------------------------------------------------------
-- Nível 0: chão do salão e poço
--------------------------------------------------------------------------------

local function buildHallFloor(dest: Instance, f: Frame, rng: Random)
	local H = CONFIG.Hall
	local P = CONFIG.Pit
	local pitCenter = polar(f, P.Theta, P.Dist, 0)

	-- Sorteia um ponto livre do chão: longe do poço e fora da faixa onde a
	-- rampa passa por cima (senão pedra/estalagmite atravessa a laje).
	local function freeSpot(minR: number, maxR: number): Vector3?
		for _ = 1, 14 do
			local theta = rng:NextNumber(0, 360)
			local d = rng:NextNumber(minR, maxR)
			local underRamp = theta > LAYOUT.RampTheta0 - 6 and theta < LAYOUT.RampTheta1 + 6 and d > LAYOUT.RampIn - 4
			local p = polar(f, theta, d, 0)
			local farFromPit = (Vector3.new(p.X, 0, p.Z) - Vector3.new(pitCenter.X, 0, pitCenter.Z)).Magnitude > P.Radius + 3
			if farFromPit and not underRamp then
				return p
			end
		end
		return nil
	end

	-- Chão vivido: cascalho, lama, pedregulhos, estalagmites.
	for i = 1, 20 do
		local p = freeSpot(4, H.Radius - 3)
		if p then
			gravelPatch(dest, p, rng:NextNumber(3, 8), rng)
		end
	end
	for i = 1, 16 do
		local p = freeSpot(8, H.Radius - 2)
		if p then
			boulder(dest, "Pedregulho_" .. i, p, rng:NextNumber(2.5, 7), rng)
		end
	end
	for i = 1, 14 do
		local p = freeSpot(10, H.Radius - 4)
		if p then
			spike(dest, "Estalagmite_" .. i, p, 1, rng:NextNumber(2, 6.5), rng:NextNumber(0.8, 2), rng)
		end
	end

	-- Pedras e cascalho espalhados.
	for i = 1, 9 do
		local p = freeSpot(6, H.Radius - 6)
		if p then
			gravelPatch(dest, p, rng:NextNumber(2.5, 6), rng)
		end
	end

	-- Sucata arrastada pra dentro: caixotes quebrados e duas jaulas.
	for i = 1, 6 do
		local p = freeSpot(12, H.Radius - 6)
		if p then
			part(
				dest,
				"Caixote_" .. i,
				Vector3.new(rng:NextNumber(2, 3.4), rng:NextNumber(1.6, 2.6), rng:NextNumber(2, 3.4)),
				CFrame.new(p + Vector3.new(0, 1.1, 0)) * CFrame.Angles(rng:NextNumber(-0.25, 0.25), rng:NextNumber(0, TAU), rng:NextNumber(-0.25, 0.25)),
				Enum.Material.WoodPlanks,
				COL.WoodDark
			)
		end
	end
	for i = 1, 2 do
		local theta = if i == 1 then 320 else 25
		local p = polar(f, theta, H.Radius - 9, 0)
		cage(dest, CFrame.new(p) * CFrame.Angles(0, math.rad(theta), 0), 5, 5, 6, rng)
		gravelPatch(dest, p, 2.5, rng)
	end
end

local function buildPit(dest: Instance, f: Frame, rng: Random)
	local P = CONFIG.Pit
	local center = polar(f, P.Theta, P.Dist, 0)
	local bottom = center - Vector3.new(0, P.Depth, 0)

	-- Fundo rochoso com minerais e fungos, sem elementos orgânicos.
	for i = 1, 8 do
		local ang = rng:NextNumber(0, TAU)
		local d = rng:NextNumber(1, P.Radius * 0.75)
		boulder(dest, "MineralPoco", bottom + Vector3.new(math.cos(ang) * d, 0, math.sin(ang) * d), rng:NextNumber(1.3, 2.6), rng)
	end

	-- Rampa tosca pra descer (e pra quem cair conseguir sair).
	local top = center + radial(f, P.Theta + 50) * (P.Radius + 2)
	local low = center + radial(f, P.Theta + 50) * 2 - Vector3.new(0, P.Depth - 0.6, 0)
	slabBetween(dest, "RampaPoco", top, low, 7, 1.4, Enum.Material.Rock, COL.RockDark)

	-- Fungos marcando a parede do poço.
	for i = 1, 10 do
		local theta = rng:NextNumber(0, 360)
		local from = center + Vector3.new(0, -rng:NextNumber(0.5, P.Depth - 0.5), 0)
		local hit = castTerrain(from, radial(f, theta), P.Radius + 4)
		if hit then
			fungusPatch(dest, hit.Position, hit.Normal, rng)
		end
	end

	-- Borda: pedras soltas marcando o buraco no escuro.
	for i = 1, 14 do
		local theta = (i - 1) * (360 / 14) + rng:NextNumber(-8, 8)
		boulder(dest, "BordaPoco_" .. i, center + radial(f, theta) * (P.Radius + 1.5), rng:NextNumber(1.6, 3.2), rng)
	end
end

--------------------------------------------------------------------------------
-- Nível 1: rampa, galeria e ponte
--------------------------------------------------------------------------------

local function rampHeightAt(theta: number): number
	local L = LAYOUT
	local t = math.clamp((theta - L.RampTheta0) / (L.RampTheta1 - L.RampTheta0), 0, 1)
	return L.RampY0 + (CONFIG.Levels.Mid - L.RampY0) * t
end

local function buildMidLevel(dest: Instance, f: Frame, rng: Random)
	local L = LAYOUT
	local MID = CONFIG.Levels.Mid
	local rMid = (L.RampIn + L.RampOut) * 0.5

	-- Rampa escavada subindo pela parede.
	arcRun(dest, f, "Rampa", L.RampTheta0, L.RampTheta1, L.RampY0, MID, L.RampIn, L.RampOut, 18, 2.4, rng)
	arcRail(dest, f, L.RampTheta0 + 3, L.RampTheta1, L.RampIn + 0.8, L.RampY0 + 1, MID, rng)
	for _, theta in { 222, 244, 266 } do
		local h = rampHeightAt(theta) - 2.4
		if h > 1 then
			pillar(dest, "EscoraRampa_" .. theta, polar(f, theta, rMid, 0), h, 3.4, rng)
		end
	end

	-- Galeria: quase o anel inteiro, fechando o circuito no alto da rampa.
	arcRun(dest, f, "Galeria", L.GalleryTheta0, L.GalleryTheta1, MID, MID, L.GalleryIn, L.GalleryOut, 42, 2.6, rng)
	-- O guarda-corpo abre nos dois pontos onde a ponte (e a escada de
	-- treliça) encostam na galeria -- senão os postes fecham a passagem.
	for _, gap in { { L.GalleryTheta0, 412 }, { 428, 522 }, { 538, L.GalleryTheta1 } } do
		arcRail(dest, f, gap[1], gap[2], L.GalleryIn + 0.8, MID, MID, rng)
	end

	-- Mãos-francesas embaixo da galeria (a parede segura o resto).
	for i = 0, 6 do
		local theta = L.GalleryTheta0 + (L.GalleryTheta1 - L.GalleryTheta0) * (i / 6)
		local under = polar(f, theta, L.GalleryIn + 1, MID - 2.6)
		local wall = polar(f, theta, L.GalleryOut - 3, MID - 9)
		beam(dest, "MaoFrancesa", under, wall, 1.1, Enum.Material.Wood, COL.WoodDark, false)
	end

	-- Ponte de tábuas cruzando o salão por cima do poço.
	local a = polar(f, L.BridgeTheta0, L.BridgeR, MID)
	local b = polar(f, L.BridgeTheta1, L.BridgeR, MID)
	plankBridge(dest, a, b, L.BridgeWidth, rng)
	-- Cordas segurando a ponte no teto.
	for _, t in { 0.28, 0.72 } do
		local p = a:Lerp(b, t)
		local hit = castTerrain(p + Vector3.new(0, 2, 0), UP, 60)
		if hit then
			beam(dest, "Tirante", p + Vector3.new(0, 2.4, 0), hit.Position, 0.16, Enum.Material.Fabric, COL.Rope, false)
		end
	end

	-- Escada de treliça do chão direto pra galeria, do lado da entrada.
	trussLadder(dest, polar(f, L.BridgeTheta0 + 8, L.GalleryIn - 1, 0), MID, math.rad(L.BridgeTheta0))

	-- O que vive na galeria: rocha, sucata e fungos.
	for i = 1, 7 do
		local theta = rng:NextNumber(L.GalleryTheta0 + 10, L.GalleryTheta1 - 10)
		local p = polar(f, theta, rng:NextNumber(L.GalleryIn + 3, L.GalleryOut - 6), MID)
		gravelPatch(dest, p, rng:NextNumber(2, 4), rng)
	end
	for i = 1, 4 do
		local theta = rng:NextNumber(L.GalleryTheta0 + 20, L.GalleryTheta1 - 20)
		local p = polar(f, theta, L.GalleryOut - 7, MID)
		part(
			dest,
			"CaixoteGaleria_" .. i,
			Vector3.new(rng:NextNumber(2, 3), rng:NextNumber(1.5, 2.4), rng:NextNumber(2, 3)),
			CFrame.new(p + Vector3.new(0, 1, 0)) * CFrame.Angles(0, rng:NextNumber(0, TAU), 0),
			Enum.Material.WoodPlanks,
			COL.WoodDark
		)
	end

	-- Correntes e ganchos decorativos pendurados do teto, vistos da galeria.
	for i = 1, 4 do
		local theta = rng:NextNumber(300, 545) -- fora do vão da laje de cima
		local p = polar(f, theta, rng:NextNumber(18, 30), MID + 9)
		local hit = castTerrain(p, UP, 50)
		if hit then
			local bottom = Vector3.new(p.X, at(f, 0, MID + 8, 0).Y, p.Z)
			hangingChain(dest, hit.Position - Vector3.new(0, 0.2, 0), bottom, rng)
		end
	end
end

--------------------------------------------------------------------------------
-- Nível 2: escada, laje do fundo e o ninho
--------------------------------------------------------------------------------

local function buildNest(dest: Instance, f: Frame, rng: Random): Vector3
	local N = CONFIG.Nest
	local TOP = CONFIG.Levels.Top
	local center = polar(f, N.Theta, N.Dist, TOP)

	-- Cama de trapos e madeira, sem materiais orgânicos.
	for i = 1, 14 do
		local ang = rng:NextNumber(0, TAU)
		local d = rng:NextNumber(0, N.Radius * 0.8)
		local p = center + Vector3.new(math.cos(ang) * d, 0.2, math.sin(ang) * d)
		local kind = rng:NextNumber()
		disc(
			dest,
			"Forro",
			p,
			rng:NextNumber(1.6, 4.5),
			rng:NextNumber(0.2, 0.5),
			rng:NextNumber(0, TAU),
			if kind < 0.7 then Enum.Material.Fabric else Enum.Material.WoodPlanks,
			if kind < 0.7 then COL.Rag else COL.WoodDark
		)
	end

	-- Borda do ninho: estacas de madeira e fragmentos de rocha.
	for i = 1, 26 do
		local ang = (i - 1) / 26 * TAU + rng:NextNumber(-0.06, 0.06)
		local d = N.Radius * rng:NextNumber(0.92, 1.12)
		local p = center + Vector3.new(math.cos(ang) * d, 0, math.sin(ang) * d)
		local len = rng:NextNumber(2.5, 5)
		local lean = rng:NextNumber(0.5, 0.95)
		local cf = CFrame.new(p + Vector3.new(0, len * 0.35, 0))
			* CFrame.Angles(0, -ang + math.pi / 2, 0)
			* CFrame.Angles(lean, 0, 0)
		part(dest, "EstacaNinho_" .. i, Vector3.new(0.5, len, 0.5), cf, Enum.Material.Wood, COL.WoodDark, {
			CanCollide = false,
			CastShadow = false,
		})
	end

	-- Cristais discretos substituem os antigos troféus orgânicos.
	for i = 1, 9 do
		local ang = rng:NextNumber(0, TAU)
		local d = N.Radius * rng:NextNumber(0.55, 1.05)
		spike(dest, "CristalNinho", center + Vector3.new(math.cos(ang) * d, 0.2, math.sin(ang) * d), 1, rng:NextNumber(1.3, 2.3), rng:NextNumber(0.35, 0.7), rng)
	end
	gravelPatch(dest, center + radial(f, N.Theta + 90) * (N.Radius + 3), 3.5, rng)
	gravelPatch(dest, center + radial(f, N.Theta - 90) * (N.Radius + 3), 3.5, rng)

	return center
end

local function buildTopLevel(dest: Instance, f: Frame, rng: Random): Vector3
	local L = LAYOUT
	local MID, TOP = CONFIG.Levels.Mid, CONFIG.Levels.Top

	-- Escada de pedra subindo por dentro do vão.
	arcStairs(dest, f, "Escadaria", L.StairTheta0, L.StairTheta1 + 2, MID, TOP, L.StairIn, L.StairOut, 16, rng)
	for _, theta in { 340, 322, 306 } do
		pillar(dest, "EscoraEscada_" .. theta, polar(f, theta, (L.StairIn + L.StairOut) * 0.5, 0), MID + (TOP - MID) * ((L.StairTheta0 - theta) / (L.StairTheta0 - L.StairTheta1)) - 2.5, 3, rng)
	end

	-- Laje do fundo (o "segundo andar") e a varanda virada pra entrada.
	arcRun(dest, f, "LajeSuperior", L.ShelfTheta0, L.ShelfTheta1, TOP, TOP, L.ShelfIn, L.ShelfOut, 18, 3, rng)
	arcRun(dest, f, "Varanda", L.BalconyTheta0, L.BalconyTheta1, TOP, TOP, L.BalconyIn, L.BalconyOut, 8, 2.6, rng)
	arcRail(dest, f, L.ShelfTheta0 + 4, L.ShelfTheta1 - 4, L.ShelfIn + 0.8, TOP, TOP, rng)
	arcRail(dest, f, L.BalconyTheta0, L.BalconyTheta1, L.BalconyIn + 0.8, TOP, TOP, rng)

	-- Colunas de rocha do chão do salão até a laje (o vão é grande demais
	-- pra laje só se apoiar na parede).
	for _, theta in { 206, 232, 260, 288 } do
		pillar(dest, "Coluna_" .. theta, polar(f, theta, 19, 0), TOP - 3, 6.5, rng)
	end

	local nest = buildNest(dest, f, rng)

	-- Correntes vazias em volta do ninho.
	for i = 1, 3 do
		local theta = CONFIG.Nest.Theta + (i - 2) * 26
		local p = polar(f, theta, CONFIG.Nest.Dist + rng:NextNumber(-6, 6), TOP + 10)
		local hit = castTerrain(p, UP, 40)
		if hit then
			local bottom = Vector3.new(p.X, at(f, 0, TOP + 8, 0).Y, p.Z)
			hangingChain(dest, hit.Position - Vector3.new(0, 0.2, 0), bottom, rng)
			gravelPatch(dest, Vector3.new(p.X, at(f, 0, TOP, 0).Y, p.Z), 2, rng)
		end
	end

	-- Rochas e cascalho pela laje toda.
	for i = 1, 8 do
		local theta = rng:NextNumber(L.ShelfTheta0 + 6, L.ShelfTheta1 - 6)
		local p = polar(f, theta, rng:NextNumber(L.ShelfIn + 3, L.ShelfOut - 9), TOP)
		gravelPatch(dest, p, rng:NextNumber(2, 4.5), rng)
	end

	return nest
end

--------------------------------------------------------------------------------
-- Câmaras laterais
--------------------------------------------------------------------------------

local function buildMineralChamber(dest: Instance, f: Frame, c: { Name: string, Theta: number, Dist: number, Radius: number }, rng: Random)
	local center = polar(f, c.Theta, c.Dist, 0)
	local R = c.Radius

	-- Prateleiras de rocha com minerais e cristais.
	for i = 1, 34 do
		local ang = rng:NextNumber(0, TAU)
		local d = R * rng:NextNumber(0.55, 0.95)
		local p = center + Vector3.new(math.cos(ang) * d, 0, math.sin(ang) * d)
		local row = rng:NextInteger(0, 2)
		if row > 0 then
			part(dest, "Prateleira_" .. i, Vector3.new(3.2, 0.5, 1.8), CFrame.new(p + Vector3.new(0, row * 1.8, 0)) * CFrame.Angles(0, -ang, 0), Enum.Material.Rock, COL.RockDark, {
				CastShadow = false,
			})
		end
		if row > 0 then
			spike(dest, "CristalPrateleira", p + Vector3.new(0, row * 1.8 + 0.3, 0), 1, rng:NextNumber(0.8, 1.5), rng:NextNumber(0.25, 0.55), rng)
		end
	end

	-- Montes de pedras encostados na parede.
	for i = 1, 6 do
		local ang = (i - 1) / 6 * TAU
		gravelPatch(dest, center + Vector3.new(math.cos(ang) * R * 0.7, 0, math.sin(ang) * R * 0.7), rng:NextNumber(3, 5), rng)
	end

	-- Mesa de pedra com minerais no meio.
	local altar = center + Vector3.new(0, 0, 0)
	part(dest, "Altar", Vector3.new(7, 1.6, 4), CFrame.new(altar + Vector3.new(0, 0.8, 0)) * CFrame.Angles(0, math.rad(c.Theta), 0), Enum.Material.Rock, COL.RockDark)
	for i = 1, 5 do
		local ang = (i - 1) / 5 * TAU
		spike(dest, "CristalAltar", altar + Vector3.new(math.cos(ang) * 2.1, 1.6, math.sin(ang) * 1.1), 1, rng:NextNumber(0.8, 1.8), rng:NextNumber(0.3, 0.6), rng)
	end

	-- Fungo opaco nas paredes.
	for i = 1, 4 do
		local ang = rng:NextNumber(0, TAU)
		local hit = castTerrain(center + Vector3.new(0, rng:NextNumber(2, 8), 0), Vector3.new(math.cos(ang), 0, math.sin(ang)), R + 5)
		if hit then
			fungusPatch(dest, hit.Position, hit.Normal, rng)
		end
	end
	for i = 1, 6 do
		local ang = rng:NextNumber(0, TAU)
		local d = R * rng:NextNumber(0.3, 0.9)
		spike(dest, "Estalagmite_" .. i, center + Vector3.new(math.cos(ang) * d, 0, math.sin(ang) * d), 1, rng:NextNumber(1.5, 4), rng:NextNumber(0.6, 1.4), rng)
	end
end

local function buildSupplyChamber(dest: Instance, f: Frame, c: { Name: string, Theta: number, Dist: number, Radius: number }, rng: Random)
	local center = polar(f, c.Theta, c.Dist, 0)
	local R = c.Radius

	-- Varal de equipamentos: dois postes e uma trave com lonas penduradas.
	local yaw = math.rad(c.Theta)
	local rackCF = CFrame.new(center) * CFrame.Angles(0, yaw, 0)
	for _, s in { -1, 1 } do
		part(dest, "PosteVaral", Vector3.new(0.6, 6, 0.6), rackCF * CFrame.new(s * 5, 3, 0), Enum.Material.Wood, COL.WoodDark)
	end
	part(dest, "TraveVaral", Vector3.new(11, 0.5, 0.5), rackCF * CFrame.new(0, 6, 0), Enum.Material.Wood, COL.WoodDark)
	for i = 1, 7 do
		local x = -4.5 + i * 1.2
		local len = rng:NextNumber(1.6, 3.4)
		part(dest, "Lona_" .. i, Vector3.new(0.7, len, 0.15), rackCF * CFrame.new(x, 6 - len * 0.5 - 0.3, rng:NextNumber(-0.3, 0.3)), Enum.Material.Fabric, COL.Rag, {
			CanCollide = false,
			CastShadow = false,
		})
	end

	-- Correntes vazias no teto.
	for i = 1, 4 do
		local ang = rng:NextNumber(0, TAU)
		local d = R * rng:NextNumber(0.35, 0.8)
		local p = center + Vector3.new(math.cos(ang) * d, 6, math.sin(ang) * d)
		local hit = castTerrain(p, UP, 30)
		if hit then
			local bottom = Vector3.new(p.X, center.Y + 5.5, p.Z)
			hangingChain(dest, hit.Position - Vector3.new(0, 0.2, 0), bottom, rng)
			gravelPatch(dest, Vector3.new(p.X, center.Y, p.Z), 1.8, rng)
		end
	end

	-- Jaulas e tonéis contra a parede.
	for i = 1, 2 do
		local ang = (i - 1) * math.pi + yaw
		local p = center + Vector3.new(math.cos(ang) * R * 0.72, 0, math.sin(ang) * R * 0.72)
		cage(dest, CFrame.new(p) * CFrame.Angles(0, -ang, 0), 5, 5, 6, rng)
		gravelPatch(dest, p, 2, rng)
	end
	for i = 1, 4 do
		local ang = rng:NextNumber(0, TAU)
		local d = R * rng:NextNumber(0.5, 0.9)
		part(
			dest,
			"Tonel_" .. i,
			Vector3.new(3.2, 2.4, 2.4),
			CFrame.new(center + Vector3.new(math.cos(ang) * d, 1.6, math.sin(ang) * d)) * CFrame.Angles(0, rng:NextNumber(0, TAU), 0) * UPRIGHT,
			Enum.Material.Wood,
			COL.WoodDark,
			{ Shape = Enum.PartType.Cylinder }
		)
	end
	for i = 1, 2 do
		local ang = rng:NextNumber(0, TAU)
		local hit = castTerrain(center + Vector3.new(0, rng:NextNumber(2, 7), 0), Vector3.new(math.cos(ang), 0, math.sin(ang)), R + 5)
		if hit then
			fungusPatch(dest, hit.Position, hit.Normal, rng)
		end
	end
end

local function buildChambers(dest: Instance, f: Frame, rng: Random)
	for _, c in CONFIG.Chambers do
		local sub = folder(dest, c.Name)
		if c.Name == "CamaraMineral" then
			buildMineralChamber(sub, f, c, rng)
		else
			buildSupplyChamber(sub, f, c, rng)
		end

		-- Corredor de ligação com cascalho e fungos.
		local a = polar(f, c.Theta, CONFIG.Hall.Radius - 8, 0)
		local b = polar(f, c.Theta, c.Dist - c.Radius * 0.5, 0)
		gravelPatch(sub, (a + b) * 0.5, 3, rng)
		local sideSeg = radial(f, c.Theta + 90)
		local steps = 3
		for i = 0, steps do
			local p = a:Lerp(b, i / steps) + Vector3.new(0, rng:NextNumber(1, 6), 0)
			for _, s in { -1, 1 } do
				local hit = castTerrain(p, sideSeg * s, 12)
				if hit then
					fungusPatch(sub, hit.Position, hit.Normal, rng)
				end
			end
		end
		task.wait()
	end
end

--------------------------------------------------------------------------------
-- Clima: estalactites, fungo e névoa
--------------------------------------------------------------------------------

local function buildAmbience(dest: Instance, f: Frame, rng: Random)
	local H = CONFIG.Hall

	-- Estalactites na abóbada.
	for i = 1, 28 do
		local theta = rng:NextNumber(0, 360)
		local d = rng:NextNumber(4, H.Radius - 4)
		local from = polar(f, theta, d, H.WallTop - 8)
		local hit = castTerrain(from, UP, 40)
		if hit then
			spike(dest, "Estalactite_" .. i, hit.Position, -1, rng:NextNumber(2.5, 8), rng:NextNumber(0.9, 2.4), rng)
		end
	end

	-- Fungo opaco espalhado pelas paredes.
	for i = 1, 14 do
		local theta = rng:NextNumber(0, 360)
		local y = rng:NextNumber(1.5, H.WallTop - 6)
		local from = polar(f, theta, H.Radius - 22, y)
		local hit = castTerrain(from, radial(f, theta), 42)
		if hit then
			fungusPatch(dest, hit.Position, hit.Normal, rng)
		end
	end

	-- Névoa parada no chão e na altura da galeria.
	for i = 1, 5 do
		local theta = rng:NextNumber(0, 360)
		mistEmitter(dest, polar(f, theta, rng:NextNumber(6, H.Radius - 8), rng:NextNumber(1, 3)), rng:NextNumber(22, 34))
	end
	for i = 1, 2 do
		mistEmitter(dest, polar(f, rng:NextNumber(0, 360), rng:NextNumber(10, 28), CONFIG.Levels.Mid + 2), 26)
	end
end

--------------------------------------------------------------------------------
-- Montagem
--------------------------------------------------------------------------------

-- Volumes invisíveis lidos apenas pelo cliente; não bloqueiam movimento nem raycasts.
local function buildDarknessZones(parent: Instance, f: Frame)
	local zones = folder(parent, "DarknessZones")
	local function zone(name: string, cf: CFrame, size: Vector3)
		local marker = part(zones, name, size, cf, Enum.Material.SmoothPlastic, Color3.new(0, 0, 0), {
			CanCollide = false,
			Transparency = 1,
			CastShadow = false,
		})
		marker.CanTouch = false
		marker.CanQuery = false
	end

	zone("Salao", CFrame.new(at(f, 0, 24, 0)), Vector3.new(102, 62, 102))
	for _, chamber in CONFIG.Chambers do
		zone(chamber.Name, CFrame.new(polar(f, chamber.Theta, chamber.Dist, 9)),
			Vector3.new(chamber.Radius * 2 + 4, 28, chamber.Radius * 2 + 4))
		local a = polar(f, chamber.Theta, CONFIG.Hall.Radius - 6, 0)
		local b = polar(f, chamber.Theta, chamber.Dist, 0)
		zone(chamber.Name .. "Corredor", CFrame.lookAt((a + b) * 0.5 + Vector3.new(0, 7, 0), b + Vector3.new(0, 7, 0)),
			Vector3.new(14, 18, (b - a).Magnitude + 8))
	end

	local waypoints = tunnelWaypoints(f)
	for i = 1, #waypoints - 1 do
		local a, b = waypoints[i], waypoints[i + 1]
		local lift = Vector3.new(0, CONFIG.Tunnel.Height * 0.5, 0)
		zone("Tunel_" .. i, CFrame.lookAt((a + b) * 0.5 + lift, b + lift),
			Vector3.new(CONFIG.Tunnel.Width + 5, CONFIG.Tunnel.Height + 5, (b - a).Magnitude + 9))
	end
end

--[[
	Dress(parent, f, seed)
	Só o cenário (pressupõe o terreno já escavado). Devolve a posição onde o
	Monstro deve nascer -- em cima do ninho, no nível de cima.
]]
function CaveInterior.Dress(parent: Instance, f: Frame, seed: number): Vector3
	local rng = Random.new(seed)

	buildDarknessZones(parent, f)
	buildTunnel(folder(parent, "Tunel"), f, rng)
	task.wait()
	buildHallFloor(folder(parent, "Nivel0_Salao"), f, rng)
	buildPit(folder(parent, "Nivel0_Poco"), f, rng)
	task.wait()
	buildMidLevel(folder(parent, "Nivel1_Galeria"), f, rng)
	task.wait()
	local nest = buildTopLevel(folder(parent, "Nivel2_Ninho"), f, rng)
	task.wait()
	buildChambers(folder(parent, "Camaras"), f, rng)
	buildAmbience(folder(parent, "Ambiente"), f, rng)

	return nest + Vector3.new(0, 0.8, 0)
end

--[[
	Build(parent, f, seed)
	Escava o terreno e monta o interior. Devolve a posição de spawn do Monstro.
]]
function CaveInterior.Build(parent: Instance, f: Frame, seed: number): Vector3
	CaveInterior.Carve(f, Random.new(seed))
	task.wait()
	return CaveInterior.Dress(parent, f, seed + 101)
end

return CaveInterior
