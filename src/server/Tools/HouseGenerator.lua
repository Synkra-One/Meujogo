--!strict
--[[
	HouseGenerator (ferramenta de editor)
	Põe as casas grandes nas clareiras Acampamento, CabanasA, CabanasB e
	VilaNativa, e a FAZENDA (celeiro + casa de fazenda) no Campo
	(Workspace.Ilha.Layout.<nome>, Attribute Raio):

	  1. LOTE -- onde cada casa fica. Na primeira vez é escolhido sozinho:
	     dentro do raio da clareira, longe das trilhas, sem encostar em
	     rocha, poste ou qualquer coisa que não seja mato/item solto, e com
	     as duas casas da clareira de frente uma pra outra. O lote vira uma
	     Part invisível do tamanho da casa em Workspace.Ilha.LotesCasas
	     (Attributes Clareira/Estilo). Pra mudar uma casa de lugar: arraste
	     /gire o lote no Studio (ou troque o Estilo) e rode Generate() de novo.
	  2. TERRENO -- a ALTURA do terreno do mapa não é mexida. A casa é que se
	     adapta: o piso fica Found acima do ponto mais alto do chão sob ela e
	     a fundação/saia/degraus descem até o ponto mais baixo
	     (HouseKit.ExtraDepth). Só o MATERIAL muda: terra (Ground, sem grama
	     animada) sob a casa, numa faixa em volta e no caminho até a trilha
	     -- nada de grama atravessando piso.
	     Lotes feitos pela versão antiga (que nivelava o chão) têm o terreno
	     reconstruído a partir do IslandLayout, igual ao gerado pela ilha.
	  3. LIMPEZA -- arbustos, troncos caídos e itens soltos que ficariam
	     dentro da casa vão pra ServerStorage.MapEditBackups (não são apagados).
	  4. CASA -- CampCabin ou CasaDoCaseiro (Tools/Houses), com portas,
	     gavetas (DrawerSystem), SpawnPOI e PontoLoot.

	A CampCabin_01 antiga solta no Workspace e o celeiro simples do Campo
	(Ilha.POIs.Campo) vão pro backup: a fazenda nova ocupa o Campo.

	USO (Studio, MODO DE EDIÇÃO, Command Bar) -- depois salve (Ctrl+S):
		require(game.ServerScriptService.Server.Tools.HouseGenerator).Generate()
		require(game.ServerScriptService.Server.Tools.HouseGenerator).Replan()  -- esquece os lotes e escolhe de novo
	Depois rode o ItemSpawner de novo se quiser itens também nos PontoLoot
	das casas: require(game.ServerScriptService.Server.Tools.ItemSpawner).Generate()
]]

local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")
local Workspace = game:GetService("Workspace")

local IslandLayout = require(script.Parent.IslandLayout)
local Structures = require(script.Parent.Structures)
local HouseKit = require(script.Parent.Houses.HouseKit)
local CampCabin = require(script.Parent.Houses.CampCabin)
local CasaDoCaseiro = require(script.Parent.Houses.CasaDoCaseiro)
local Celeiro = require(script.Parent.Houses.Celeiro)
local CasaDaFazenda = require(script.Parent.Houses.CasaDaFazenda)

local HouseGenerator = {}

export type Rect = { MinX: number, MaxX: number, MinZ: number, MaxZ: number }

type Style = {
	Style: string,
	Found: number,
	Footprint: Rect,
	Core: { Rect }, -- construção em si (altura do piso, chão de terra)
	Entrances: { Vector3 },
	Build: (parent: Instance, house: CFrame, opts: { Name: string?, Seed: number? }?) -> Model,
}

HouseGenerator.Styles = {
	CampCabin = CampCabin :: any,
	CasaDoCaseiro = CasaDoCaseiro :: any,
	Celeiro = Celeiro :: any,
	CasaDaFazenda = CasaDaFazenda :: any,
} :: { [string]: Style }

-- Duas casas por clareira, um estilo de cada; a ordem alterna qual escolhe lugar primeiro.
HouseGenerator.Plan = {
	{ Site = "Acampamento", Houses = { "CampCabin", "CasaDoCaseiro" } },
	{ Site = "CabanasA", Houses = { "CasaDoCaseiro", "CampCabin" } },
	{ Site = "CabanasB", Houses = { "CampCabin", "CasaDoCaseiro" } },
	{ Site = "VilaNativa", Houses = { "CasaDoCaseiro", "CampCabin" } },
	{ Site = "Campo", Houses = { "Celeiro", "CasaDaFazenda" } }, -- a fazenda
}

local FOLDER = "Casas"
local LOTS = "LotesCasas"
local REMOVABLE = { Vegetacao = true, Itens = true } -- pastas de Ilha que podem sair do caminho
local EDGE_MARGIN = 3 -- folga até a borda da clareira
local TRAIL_MARGIN = 2.5 -- folga até a beira da trilha
local HOUSE_GAP = 5 -- folga entre as duas casas
local RELAX_EDGE = 24 -- quanto a casa pode passar da borda nas tentativas relaxadas

--------------------------------------------------------------------------------
-- Planejamento (puro -- tests/house_plan.luau)
--------------------------------------------------------------------------------

export type PlanEnv = {
	TrailDistance: (x: number, z: number) -> number,
	TrailHalfWidth: number,
	Blocked: (ground: CFrame, rect: Rect) -> boolean,
	-- Segunda tentativa, pra clareira apertada: qualquer orientação e até
	-- RELAX_EDGE studs além da borda (árvores no caminho saem pro backup).
	Relaxed: boolean?,
	-- Terceira tentativa, último recurso: ignora a trilha (ela não é sólida,
	-- só textura de terreno -- a casa pode ficar em cima; dá pra desviar a
	-- trilha depois à mão). Só entra em ação se nem a relaxada coube.
	IgnoreTrail: boolean?,
}

local function rectCorners(rect: Rect, margin: number): { Vector3 }
	return {
		Vector3.new(rect.MinX - margin, 0, rect.MinZ - margin),
		Vector3.new(rect.MaxX + margin, 0, rect.MinZ - margin),
		Vector3.new(rect.MaxX + margin, 0, rect.MaxZ + margin),
		Vector3.new(rect.MinX - margin, 0, rect.MaxZ + margin),
	}
end

-- Caixa 2D (centro, eixos, meias-medidas) de um retângulo local posto em `cf`.
local function box2(cf: CFrame, rect: Rect, margin: number)
	local cx, cz = (rect.MinX + rect.MaxX) / 2, (rect.MinZ + rect.MaxZ) / 2
	local c = (cf * CFrame.new(cx, 0, cz)).Position
	local right = cf.RightVector
	local back = -cf.LookVector
	return {
		C = Vector3.new(c.X, 0, c.Z),
		A = { Vector3.new(right.X, 0, right.Z).Unit, Vector3.new(back.X, 0, back.Z).Unit },
		E = { (rect.MaxX - rect.MinX) / 2 + margin, (rect.MaxZ - rect.MinZ) / 2 + margin },
	}
end

local function overlaps2(a, b): boolean
	local d = b.C - a.C
	for _, axis in { a.A[1], a.A[2], b.A[1], b.A[2] } do
		local ra = a.E[1] * math.abs(a.A[1]:Dot(axis)) + a.E[2] * math.abs(a.A[2]:Dot(axis))
		local rb = b.E[1] * math.abs(b.A[1]:Dot(axis)) + b.E[2] * math.abs(b.A[2]:Dot(axis))
		if math.abs(d:Dot(axis)) > ra + rb then
			return false
		end
	end
	return true
end

--[[
	PlanSite(center, radius, rects, env) -> { CFrame | false }
	Pra cada retângulo (Footprint de um estilo, na ordem), um CFrame no
	CHÃO (y = center.Y) com LookVector = frente da casa, ou false se não
	coube. As casas ficam viradas pro miolo da clareira e, juntas, escolhem
	a MELHOR COMBINAÇÃO (não a melhor da primeira + o que sobrar pra segunda):
	longe da trilha, perto do meio do raio, em lados opostos da clareira.
]]
type Candidate = { cf: CFrame, score: number, angle: number, box: any }

local function candidatesFor(center: Vector3, radius: number, rect: Rect, env: PlanEnv): { Candidate }
	local list: { Candidate } = {}
	local yaws = if env.Relaxed then { 0, -0.3, 0.3, -0.6, 0.6, -0.9, 0.9, -1.25, 1.25, -math.pi / 2, math.pi / 2, math.pi } else { 0, -0.3, 0.3, -0.6, 0.6 }
	local limit = radius - EDGE_MARGIN + (if env.Relaxed then RELAX_EDGE else 0)
	local fracs = if env.Relaxed
		then { 0.16, 0.24, 0.32, 0.4, 0.48, 0.56, 0.64, 0.72, 0.8, 0.88, 0.96, 1.04, 1.12, 1.2 }
		else { 0.16, 0.24, 0.32, 0.4, 0.48, 0.56, 0.64 }
	for step = 0, 47 do
		local angle = step * math.pi / 24
		local dir = Vector3.new(math.cos(angle), 0, math.sin(angle))
		for _, frac in fracs do
			local pos = center + dir * (radius * frac)
			for _, yaw in yaws do
				local cf = CFrame.lookAt(pos, pos - dir) * CFrame.Angles(0, yaw, 0)
				local inside = true
				for _, corner in rectCorners(rect, 2) do
					local w = cf * corner
					if Vector3.new(w.X - center.X, 0, w.Z - center.Z).Magnitude > limit then
						inside = false
						break
					end
				end
				if not inside then
					continue
				end
				local nearest = math.huge
				local x = rect.MinX - 2.5
				while x <= rect.MaxX + 2.5 do
					local z = rect.MinZ - 2.5
					while z <= rect.MaxZ + 2.5 do
						local w = cf * Vector3.new(x, 0, z)
						nearest = math.min(nearest, env.TrailDistance(w.X, w.Z))
						z += 4
					end
					x += 4
				end
				if not env.IgnoreTrail and nearest < env.TrailHalfWidth + TRAIL_MARGIN then
					continue
				end
				local score = math.min(nearest, 30) * 0.5 - math.abs(frac - 0.44) * 25 - math.min(math.abs(yaw), 1.3) * 6
				if env.IgnoreTrail and nearest < env.TrailHalfWidth + TRAIL_MARGIN then
					score -= 200 -- só escolhe em cima da trilha se não houver opção melhor
				end
				table.insert(list, { cf = cf, score = score, angle = angle, box = box2(cf, rect, HOUSE_GAP / 2) })
			end
		end
	end
	table.sort(list, function(a, b)
		return a.score > b.score
	end)
	return list
end

-- Bloqueio (rocha, poste...) é a consulta cara no Studio: só pros melhores, com memo.
local function unblocked(list: { Candidate }, rect: Rect, env: PlanEnv, limit: number): { Candidate }
	local out = {}
	for _, c in list do
		if #out >= limit then
			break
		end
		if not env.Blocked(c.cf, rect) then
			table.insert(out, c)
		end
	end
	return out
end

local function separation(a: number, b: number): number
	return math.deg(math.abs(((a - b + math.pi) % (2 * math.pi)) - math.pi)) * 0.12
end

function HouseGenerator.PlanSite(center: Vector3, radius: number, rects: { Rect }, env: PlanEnv): { CFrame | false }
	local pools: { { Candidate } } = {}
	for i, rect in rects do
		pools[i] = unblocked(candidatesFor(center, radius, rect, env), rect, env, 160)
	end

	local result: { CFrame | false } = {}
	if #rects == 2 then
		local best, bi, bj = -math.huge, nil, nil
		for _, a in pools[1] do
			for _, b in pools[2] do
				local total = a.score + b.score + separation(a.angle, b.angle)
				if total > best and not overlaps2(a.box, b.box) then
					best, bi, bj = total, a, b
				end
			end
		end
		if bi and bj then
			return { bi.cf, bj.cf }
		end
	end

	-- Uma casa (ou nenhum par possível): cada uma pega o melhor lugar que sobrar.
	local chosen: { Candidate } = {}
	for i in rects do
		local pick = nil
		local bestScore = -math.huge
		for _, c in pools[i] do
			local ok = true
			local score = c.score
			for _, other in chosen do
				if overlaps2(c.box, other.box) then
					ok = false
					break
				end
				score += separation(c.angle, other.angle)
			end
			if ok and score > bestScore then
				pick, bestScore = c, score
			end
		end
		if pick then
			table.insert(chosen, pick)
			table.insert(result, pick.cf)
		else
			table.insert(result, false)
		end
	end
	return result
end

--------------------------------------------------------------------------------
-- Mundo
--------------------------------------------------------------------------------

local Terrain = Workspace.Terrain

local terrainRay = RaycastParams.new()
terrainRay.FilterType = Enum.RaycastFilterType.Include
terrainRay.FilterDescendantsInstances = { Terrain }
terrainRay.IgnoreWater = true

local function groundAt(x: number, z: number): number?
	local hit = Workspace:Raycast(Vector3.new(x, IslandLayout.MaxY() + 60, z), Vector3.new(0, -(IslandLayout.MaxY() + 260), 0), terrainRay)
	return if hit then hit.Position.Y else nil
end

local function getIlha(): Instance
	local ilha = Workspace:FindFirstChild("Ilha")
	assert(ilha, "Workspace.Ilha não existe: gere a ilha primeiro (IslandGenerator.Generate).")
	return ilha
end

local function childFolder(parent: Instance, name: string): Folder
	local existing = parent:FindFirstChild(name)
	if existing and existing:IsA("Folder") then
		return existing
	end
	local f = Instance.new("Folder")
	f.Name = name
	f.Parent = parent
	return f
end

local backupFolder: Folder? = nil
local function backup(): Folder
	if backupFolder and backupFolder.Parent then
		return backupFolder
	end
	local root = childFolder(ServerStorage, "MapEditBackups")
	local f = Instance.new("Folder")
	f.Name = "Casas_" .. os.date("!%Y%m%d_%H%M%S")
	f.Parent = root
	backupFolder = f
	return f
end

type SiteInfo = { name: string, center: Vector3, radius: number, planOk: boolean }

local function siteInfo(ilha: Instance, name: string): SiteInfo?
	local layout = ilha:FindFirstChild("Layout")
	local marker = layout and layout:FindFirstChild(name)
	local planned = IslandLayout.Site(name)
	if marker and marker:IsA("BasePart") then
		local radius = marker:GetAttribute("Raio")
		local center = marker.Position - Vector3.new(0, 1, 0)
		local planOk = planned ~= nil and Vector3.new(planned.x - center.X, 0, planned.z - center.Z).Magnitude < 3
		return { name = name, center = center, radius = if type(radius) == "number" then radius else (planned and planned.r or 80), planOk = planOk }
	end
	if planned then
		return { name = name, center = Vector3.new(planned.x, planned.y, planned.z), radius = planned.r, planOk = true }
	end
	return nil
end

-- O que ocupa o volume da casa: (bloqueia?, removíveis).
local function occupants(ilha: Instance, ground: CFrame, rect: Rect, ignore: { Instance }, allowTrees: boolean?): (boolean, { Instance })
	local cx, cz = (rect.MinX + rect.MaxX) / 2, (rect.MinZ + rect.MaxZ) / 2
	local probe = Instance.new("Part")
	probe.Anchored = true
	probe.CanCollide = false
	probe.Transparency = 1
	probe.Size = Vector3.new(rect.MaxX - rect.MinX, 30, rect.MaxZ - rect.MinZ)
	probe.CFrame = ground * CFrame.new(cx, 15.5, cz)
	probe.Parent = Workspace
	local params = OverlapParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local filter = { Terrain, probe }
	for _, i in ignore do
		table.insert(filter, i)
	end
	params.FilterDescendantsInstances = filter
	-- GetPartsInPart usa a geometria real (união/rocha irregular), não a caixa.
	local hits = Workspace:GetPartsInPart(probe, params)
	probe:Destroy()

	local removable: { [Instance]: true } = {}
	for _, part in hits do
		local node: Instance = part
		while node.Parent and node.Parent ~= ilha and node.Parent ~= Workspace do
			node = node.Parent
		end
		local group = if node.Parent == ilha then node.Name else nil
		if group and (REMOVABLE[group] or (allowTrees and group == "Floresta")) then
			local top: Instance = part
			while top.Parent and top.Parent ~= node do
				top = top.Parent
			end
			removable[top] = true
		elseif part.CanCollide or part.Transparency < 1 then
			return true, {}
		end
	end
	local list = {}
	for inst in removable do
		table.insert(list, inst)
	end
	return false, list
end

local function nearestTrailPoint(from: Vector3, maxDist: number): Vector3?
	local best: Vector3? = nil
	local bestD = maxDist
	for _, seg in IslandLayout.TrailSegments() do
		local a, b = Vector3.new(seg.a.X, 0, seg.a.Z), Vector3.new(seg.b.X, 0, seg.b.Z)
		local ab = b - a
		local t = if ab:Dot(ab) > 0 then math.clamp((Vector3.new(from.X, 0, from.Z) - a):Dot(ab) / ab:Dot(ab), 0, 1) else 0
		local p = a + ab * t
		local d = (p - Vector3.new(from.X, 0, from.Z)).Magnitude
		if d < bestD then
			bestD = d
			best = p
		end
	end
	return best
end

local function paintCell(x: number, z: number, y: number)
	local region = Region3.new(Vector3.new(x - 2, y - 10, z - 2), Vector3.new(x + 2, y + 8, z + 2)):ExpandToGrid(4)
	Terrain:ReplaceMaterial(region, 4, Enum.Material.Grass, Enum.Material.Ground)
	Terrain:ReplaceMaterial(region, 4, Enum.Material.LeafyGrass, Enum.Material.Ground)
end

-- CFrame da origem da casa no chão a partir do lote (lote = centro do Footprint).
local function lotGround(lot: BasePart, style: Style): CFrame
	local rect = style.Footprint
	local cx, cz = (rect.MinX + rect.MaxX) / 2, (rect.MinZ + rect.MaxZ) / 2
	local look = lot.CFrame.LookVector
	local level = CFrame.lookAt(lot.Position, lot.Position + Vector3.new(look.X, 0, look.Z))
	return level * CFrame.new(-cx, -0.2, -cz)
end

-- Distância (no plano local) de um ponto até o retângulo; 0 dentro.
local function outside(rect: Rect, lx: number, lz: number): number
	local dx = math.max(rect.MinX - lx, 0, lx - rect.MaxX)
	local dz = math.max(rect.MinZ - lz, 0, lz - rect.MaxZ)
	return math.sqrt(dx * dx + dz * dz)
end

--[[
	paintYard(ground, style)
	Só troca o MATERIAL (a altura do terreno fica a do mapa): terra batida
	sob a construção e numa faixa em volta, manchas irregulares no resto do
	lote (quintal pisado).
]]
local function paintYard(ground: CFrame, style: Style)
	local rect = style.Footprint
	local y = ground.Position.Y
	local lo = Vector3.new(math.huge, 0, math.huge)
	local hi = Vector3.new(-math.huge, 0, -math.huge)
	for _, corner in rectCorners(rect, 8) do
		local w = ground * corner
		lo = Vector3.new(math.min(lo.X, w.X), 0, math.min(lo.Z, w.Z))
		hi = Vector3.new(math.max(hi.X, w.X), 0, math.max(hi.Z, w.Z))
	end
	local x = math.floor(lo.X / 4) * 4 + 2
	while x <= hi.X do
		local z = math.floor(lo.Z / 4) * 4 + 2
		while z <= hi.Z do
			local l = ground:PointToObjectSpace(Vector3.new(x, y, z))
			local core = math.huge
			for _, r in style.Core do
				core = math.min(core, outside(r, l.X, l.Z))
			end
			local lotDist = outside(rect, l.X, l.Z)
			local patchy = math.noise(x / 9, z / 9, 3.7) > 0.12
			if core <= 3 or (lotDist <= 0 and patchy) or (lotDist <= 6 and patchy and math.noise(x / 5, z / 5, 1.1) > 0) then
				paintCell(x, z, groundAt(x, z) or y)
			end
			z += 4
		end
		x += 4
	end
end

--[[
	restoreTerrain(ground, rect)
	Reescreve o terreno do lote (+ folga) exatamente como o IslandGenerator
	escreveu (IslandLayout.Height/Material/WaterLevel). Desfaz o nivelamento
	da versão antiga do gerador, que subia o chão sob as casas.
]]
local function restoreTerrain(ground: CFrame, rect: Rect)
	local LC = IslandLayout.CONFIG
	local res = LC.VoxelRes
	local lo = Vector3.new(math.huge, 0, math.huge)
	local hi = Vector3.new(-math.huge, 0, -math.huge)
	for _, corner in rectCorners(rect, 8) do
		local w = ground * corner
		lo = Vector3.new(math.min(lo.X, w.X), 0, math.min(lo.Z, w.Z))
		hi = Vector3.new(math.max(hi.X, w.X), 0, math.max(hi.Z, w.Z))
	end
	local x0, x1 = math.floor(lo.X / res) * res, math.ceil(hi.X / res) * res
	local z0, z1 = math.floor(lo.Z / res) * res, math.ceil(hi.Z / res) * res
	local nx, nz = (x1 - x0) // res, (z1 - z0) // res

	local heights = table.create(nx)
	local minH, maxH = math.huge, -math.huge
	for i = 1, nx do
		heights[i] = table.create(nz)
		for k = 1, nz do
			local h = IslandLayout.Height(x0 + (i - 0.5) * res, z0 + (k - 0.5) * res)
			heights[i][k] = h
			minH = math.min(minH, h)
			maxH = math.max(maxH, h)
		end
	end
	-- A versão antiga cortava até 40 acima e enchia até 8 abaixo do chão.
	local gy = ground.Position.Y
	local y0 = math.max(LC.MinY, math.floor((math.min(minH, gy) - 12 - LC.MinY) / res) * res + LC.MinY)
	local y1 = math.min(LC.MaxY, math.ceil((math.max(maxH, gy) + 44 - LC.MinY) / res) * res + LC.MinY)
	local ny = (y1 - y0) // res
	if nx <= 0 or nz <= 0 or ny <= 0 then
		return
	end

	local air, water = Enum.Material.Air, Enum.Material.Water
	local materials = table.create(nx)
	local occupancies = table.create(nx)
	for i = 1, nx do
		local x = x0 + (i - 0.5) * res
		local colM, colO = table.create(ny), table.create(ny)
		for j = 1, ny do
			colM[j] = table.create(nz, air)
			colO[j] = table.create(nz, 0)
		end
		for k = 1, nz do
			local z = z0 + (k - 0.5) * res
			local h = heights[i][k]
			local mat = IslandLayout.Material(x, z)
			local waterLevel = IslandLayout.WaterLevel(x, z)
			for j = 1, ny do
				local yb = y0 + (j - 1) * res
				local occ = math.clamp((h - yb) / res, 0, 1)
				if occ > 0.02 then
					colM[j][k] = mat
					colO[j][k] = occ
				elseif yb < waterLevel then
					colM[j][k] = water
					colO[j][k] = math.clamp((waterLevel - yb) / res, 0, 1)
				end
			end
		end
		materials[i] = colM
		occupancies[i] = colO
	end
	Terrain:WriteVoxels(Region3.new(Vector3.new(x0, y0, z0), Vector3.new(x1, y1, z1)), res, materials, occupancies)
end

HouseGenerator.RestoreTerrain = restoreTerrain

-- Lote da versão antiga (terreno nivelado) -> terreno original de volta.
local function restoreLegacyLot(ilha: Instance, lot: BasePart): boolean
	if lot:GetAttribute("TerrenoOriginal") == true then
		return false
	end
	local styleName = lot:GetAttribute("Estilo")
	local style = if type(styleName) == "string" then HouseGenerator.Styles[styleName] else nil
	local site = lot:GetAttribute("Clareira")
	local info = if type(site) == "string" then siteInfo(ilha, site) else nil
	if not style or not info then
		return false
	end
	if not info.planOk then
		warn(string.format("[HouseGenerator] %s: não dá pra reconstruir o terreno original (o marcador não bate com o IslandLayout). Ajuste o chão à mão se ficou degrau.", lot.Name))
		lot:SetAttribute("TerrenoOriginal", true)
		return false
	end
	restoreTerrain(lotGround(lot, style), style.Footprint)
	lot:SetAttribute("TerrenoOriginal", true)
	return true
end

local function paintPath(a: Vector3, b: Vector3)
	local flatA, flatB = Vector3.new(a.X, 0, a.Z), Vector3.new(b.X, 0, b.Z)
	local len = (flatB - flatA).Magnitude
	if len < 1 then
		return
	end
	local dir = (flatB - flatA).Unit
	local side = Vector3.new(-dir.Z, 0, dir.X)
	local done: { [string]: true } = {}
	local t = 0
	while t <= len do
		local wobble = math.noise(t / 14, a.X / 50, 1.3) * 2.2
		for _, off in { -1.6, 1.6 } do
			local p = flatA + dir * t + side * (off + wobble)
			local gx, gz = math.floor(p.X / 4) * 4 + 2, math.floor(p.Z / 4) * 4 + 2
			local key = gx .. ":" .. gz
			if not done[key] then
				done[key] = true
				local y = groundAt(gx, gz) or a.Y
				paintCell(gx, gz, y)
			end
		end
		t += 2
	end
end

local function retireLegacy(ilha: Instance)
	local legacy = Workspace:FindFirstChild("CampCabin_01")
	if legacy and legacy:GetAttribute("CasaGerada") ~= true then
		legacy.Name = "CampCabin_01_original"
		legacy.Parent = backup()
		print("[HouseGenerator] CampCabin_01 antiga (solta no Campo) movida pra ServerStorage.MapEditBackups.")
	end
	-- Celeiro simples, alvos e fardos do PoiGenerator: a fazenda ocupa o Campo.
	local pois = ilha:FindFirstChild("POIs")
	local campo = pois and pois:FindFirstChild("Campo")
	if campo then
		campo.Name = "Campo_original"
		campo.Parent = backup()
		print("[HouseGenerator] Celeiro antigo do Campo (Ilha.POIs.Campo) movido pra ServerStorage.MapEditBackups.")
	end
end

--------------------------------------------------------------------------------
-- Lotes
--------------------------------------------------------------------------------

type Lot = { part: BasePart, site: string, style: string, index: number }

local function makeLot(lots: Folder, site: string, index: number, styleName: string, ground: CFrame): BasePart
	local rect = HouseGenerator.Styles[styleName].Footprint
	local cx, cz = (rect.MinX + rect.MaxX) / 2, (rect.MinZ + rect.MaxZ) / 2
	local lot = Structures.Part(lots, string.format("Lote_%s_%d", site, index), Vector3.new(rect.MaxX - rect.MinX, 0.4, rect.MaxZ - rect.MinZ), ground * CFrame.new(cx, 0.2, cz), Enum.Material.SmoothPlastic, Color3.fromRGB(255, 190, 60), { CanCollide = false, Transparency = 1, CastShadow = false })
	lot.CanQuery = false
	lot.CanTouch = false
	lot:SetAttribute("Clareira", site)
	lot:SetAttribute("Estilo", styleName)
	lot:SetAttribute("Indice", index)
	lot:SetAttribute("TerrenoOriginal", true) -- esta versão nunca mexe na altura do terreno
	return lot
end

local function planLots(ilha: Instance, lots: Folder, casas: Instance): number
	local planned = 0
	for _, entry in HouseGenerator.Plan do
		local site = entry.Site
		local existing = false
		for _, lot in lots:GetChildren() do
			if lot:GetAttribute("Clareira") == site then
				existing = true
			end
		end
		if existing then
			continue
		end
		local info = siteInfo(ilha, site)
		if not info then
			warn(string.format("[HouseGenerator] Clareira %s não existe neste mapa -- pulando.", site))
			continue
		end
		if not info.planOk then
			warn(string.format("[HouseGenerator] %s: o marcador não bate com o IslandLayout (seed diferente?). Vou desviar só do que existe no mapa, sem saber das trilhas.", site))
		end
		local rects: { Rect } = {}
		for _, styleName in entry.Houses do
			table.insert(rects, HouseGenerator.Styles[styleName].Footprint)
		end
		local function envFor(relaxed: boolean, ignoreTrail: boolean?): PlanEnv
			return {
				TrailHalfWidth = IslandLayout.CONFIG.Trail.HalfWidth,
				TrailDistance = function(x: number, z: number): number
					return if info.planOk then IslandLayout.DistToTrail(x, z) else math.huge
				end,
				Blocked = function(ground: CFrame, rect: Rect): boolean
					local blocked = occupants(ilha, ground, rect, { casas, lots }, relaxed)
					return blocked
				end,
				Relaxed = relaxed,
				IgnoreTrail = ignoreTrail,
			}
		end
		local function count(picks: { CFrame | false }): number
			local n = 0
			for _, cf in picks do
				if cf then
					n += 1
				end
			end
			return n
		end
		local picks = HouseGenerator.PlanSite(info.center, info.radius, rects, envFor(false))
		local tier = 1
		if count(picks) < #rects then
			local relaxed = HouseGenerator.PlanSite(info.center, info.radius, rects, envFor(true))
			if count(relaxed) > count(picks) then
				picks, tier = relaxed, 2
			end
			if count(picks) < #rects then
				-- Último recurso: ignora a trilha (ela não é sólida, só
				-- textura -- funcionalmente inofensivo, só pode ficar feio;
				-- só usa quando não sobra outra opção).
				local desperate = HouseGenerator.PlanSite(info.center, info.radius, rects, envFor(true, true))
				if count(desperate) > count(picks) then
					picks, tier = desperate, 3
				end
			end
			if tier == 2 then
				print(string.format("[HouseGenerator] %s: clareira apertada (rocha/trilhas) -- as casas podem virar de lado e passar até %d studs da borda; árvores no caminho vão pro backup.", site, RELAX_EDGE))
			elseif tier == 3 then
				warn(string.format("[HouseGenerator] %s: clareira MUITO apertada -- pelo menos uma casa pode ter ficado em cima da trilha (a trilha não é sólida, mas pode ficar estranho visualmente). Considere mover o lote à mão ou trocar o Estilo.", site))
			end
		end
		for i, cf in picks do
			if cf then
				local lot = makeLot(lots, site, i, entry.Houses[i], cf :: CFrame)
				if tier >= 2 then
					lot:SetAttribute("PodeTirarArvore", true)
				end
				planned += 1
			else
				warn(string.format("[HouseGenerator] %s: não coube a casa %d (%s) nem no último recurso (rocha/poste bloqueando demais). Posicione um lote à mão: duplique um Lote_* em Ilha.%s, ajuste Clareira/Estilo/Indice (ou troque o Estilo por um menor) e rode Generate() de novo.", site, i, entry.Houses[i], LOTS))
			end
		end
	end
	return planned
end

--------------------------------------------------------------------------------
-- API
--------------------------------------------------------------------------------

--[[
	Generate() -> número de casas construídas
	Usa os lotes salvos (ou escolhe, na primeira vez), prepara o terreno e
	(re)constrói todas as casas em Workspace.Ilha.Casas.
]]
function HouseGenerator.Generate(): number
	assert(not RunService:IsRunning(), "Rode o HouseGenerator em modo de edição (fora do Play).")
	IslandLayout.Plan()
	local ilha = getIlha()
	retireLegacy(ilha)

	local old = ilha:FindFirstChild(FOLDER)
	if old then
		old:Destroy()
	end
	local casas = childFolder(ilha, FOLDER)
	local lots = childFolder(ilha, LOTS)

	-- Desfaz o nivelamento dos lotes da versão antiga antes de medir o chão.
	local restored = 0
	for _, lot in lots:GetChildren() do
		if lot:IsA("BasePart") and restoreLegacyLot(ilha, lot) then
			restored += 1
			task.wait()
		end
	end
	if restored > 0 then
		print(string.format("[HouseGenerator] Terreno original reconstruído em %d lote(s) (a versão antiga tinha nivelado/subido o chão).", restored))
	end

	local planned = planLots(ilha, lots, casas)

	local built, moved = 0, 0
	local lotList = lots:GetChildren()
	table.sort(lotList, function(a, b)
		return a.Name < b.Name
	end)
	for _, lot in lotList do
		if not lot:IsA("BasePart") then
			continue
		end
		local site = lot:GetAttribute("Clareira")
		local styleName = lot:GetAttribute("Estilo")
		local style = if type(styleName) == "string" then HouseGenerator.Styles[styleName] else nil
		if type(site) ~= "string" or not style then
			warn("[HouseGenerator] Lote sem Clareira/Estilo válido: " .. lot:GetFullName())
			continue
		end
		local ground = lotGround(lot, style)
		local rect = style.Footprint

		-- Piso acima do ponto MAIS ALTO do chão sob a construção (nada de
		-- terreno furando o piso); fundação desce até o mais BAIXO do lote.
		local top, bottom = -math.huge, math.huge
		local function sample(r: Rect, keepTop: boolean)
			local x = r.MinX + 1
			while x <= r.MaxX - 1 do
				local z = r.MinZ + 1
				while z <= r.MaxZ - 1 do
					local w = ground * Vector3.new(x, 0, z)
					local y = groundAt(w.X, w.Z)
					if y then
						if keepTop then
							top = math.max(top, y)
						end
						bottom = math.min(bottom, y)
					end
					z += 3
				end
				x += 3
			end
		end
		for _, r in style.Core do
			sample(r, true)
		end
		sample(rect, false)
		local padY = if top > -math.huge then top else ground.Position.Y
		local drop = if bottom < math.huge then math.clamp(padY - bottom, 0, 8) else 0
		ground = CFrame.new(ground.Position.X, padY, ground.Position.Z) * (ground - ground.Position)

		local _, clutter = occupants(ilha, ground, rect, { casas, lots }, lot:GetAttribute("PodeTirarArvore") == true)
		for _, inst in clutter do
			inst.Parent = backup()
			moved += 1
		end

		paintYard(ground, style)
		local index = lot:GetAttribute("Indice")
		local name = string.format("Casa_%s_%s_%s", site, tostring(index or 1), style.Style)
		local seed = 0
		for i = 1, #name do
			seed = (seed * 31 + string.byte(name, i)) % 2147483647
		end
		HouseKit.ExtraDepth = drop
		local ok, err = pcall(style.Build, casas, ground * CFrame.new(0, style.Found, 0), { Name = name, Seed = seed })
		HouseKit.ExtraDepth = 0
		if not ok then
			warn(string.format("[HouseGenerator] Falha ao construir %s: %s", name, tostring(err)))
			continue
		end

		local entrance = ground * style.Entrances[1]
		local info = siteInfo(ilha, site)
		local target = if info and info.planOk then nearestTrailPoint(entrance, 140) else nil
		if not target and info then
			target = info.center
		end
		if target then
			paintPath(entrance, Vector3.new(target.X, padY, target.Z))
		end
		lot.CFrame = ground * CFrame.new((rect.MinX + rect.MaxX) / 2, 0.2, (rect.MinZ + rect.MaxZ) / 2)
		built += 1
		task.wait()
	end

	print(string.format(
		"[HouseGenerator] %d casa(s) construída(s) em Workspace.Ilha.%s (%d lote(s) novo(s)); %d arbusto/tronco/item solto movido(s) pro backup. Salve o lugar (Ctrl+S).",
		built, FOLDER, planned, moved
	))
	if built > 0 then
		print("[HouseGenerator] Itens nos PontoLoot das casas: require(game.ServerScriptService.Server.Tools.ItemSpawner).Generate()")
	end
	return built
end

-- Esquece os lotes (escolhe tudo de novo) e reconstrói.
function HouseGenerator.Replan(): number
	local ilha = getIlha()
	local lots = ilha:FindFirstChild(LOTS)
	if lots then
		for _, lot in lots:GetChildren() do
			if lot:IsA("BasePart") then
				restoreLegacyLot(ilha, lot)
			end
		end
		lots:Destroy()
	end
	return HouseGenerator.Generate()
end

function HouseGenerator.Clear()
	local ilha = Workspace:FindFirstChild("Ilha")
	local casas = ilha and ilha:FindFirstChild(FOLDER)
	if casas then
		casas:Destroy()
	end
end

return HouseGenerator
