--!strict
--[[
	IslandLayout
	O "mapa mental" da ilha: forma da costa, relevo, biomas, pontos de
	interesse (POIs) e trilhas -- tudo ANALÍTICO (só matemática, nenhuma
	Instance), fixo por seed.

	Quem usa:
	  - IslandGenerator: Height/Material/WaterLevel por coluna no WriteVoxels;
	    IsClearAt() pra floresta/rochas não invadirem trilha/POI/lago/campo.
	  - PoiGenerator: Sites() pra saber ONDE construir cada coisa e
	    TrailSegments() pros lampiões de trilha.
	  - Runtime (LobbyManager, WeaponSpawner, LootCrateSystem, ItemSpawner,
	    RaftGenerator, PlaneCrashGenerator): CoastRadiusMax()/AreaHalf() em vez
	    de número mágico repetido.

	INSPIRAÇÃO: mapas do Friday the 13th (Camp Crystal Lake / Packanack /
	Higgins Haven) -- POIs espalhados a 150-300 studs uns dos outros, ligados
	por trilhas de terra, floresta fechada no meio, lago com píer, campo
	aberto, marcos altos pra se orientar. Aqui numa ilha.

	POIs (nome do site -> o que PoiGenerator constrói):
	  Acampamento  lodge + 3 cabanas + fogueira + mesa (clareira grande)
	  CabanasA/B   2-3 cabanas + fogueira + latrina (clareiras menores)
	  Lago         bacia com água, píer, casa de barcos, barco virado
	  Campo        planície plana de grama, celeiro, alvo de arco, fardos
	  Torre        torre de vigia num morro (o site mais alto)
	  Farol        farol velho numa ponta rochosa da costa
	  VilaNativa   cabanas nativas, totem, fogueira apagada, secador de peixe
	  Ruinas       círculo de pedras + Lança Ancestral (IslandGenerator)
	  (Montanha/Caverna continuam no IslandGenerator; Jangada no RaftGenerator)

	TRILHAS: um loop passando pelos POIs "de morador" (ordenados por ângulo
	em volta do centro) + ramais pra Torre, Farol, Ruínas e boca da Caverna.
	Cada trecho é subdividido e sacudido de leve pra não ficar reto, e desvia
	do lago. Trilha = faixa de Ground levemente rebaixada, sem árvores.

	Uso:
		local Layout = require(script.Parent.IslandLayout)
		Layout.Plan(seed)          -- (re)calcula tudo; chamar antes de gerar
		Layout.Height(x, z)        -- altura do terreno final em (x, z)
		Layout.Material(x, z)
		Layout.WaterLevel(x, z)    -- nível d'água local (mar ou lago)
		Layout.Sites()             -- { [nome] = { x, z, r, y, angle } }
		Layout.TrailSegments()     -- { {a = Vector3, b = Vector3} }
		Layout.IsClearAt(x, z, margin) -- true = NÃO plantar árvore/rocha aqui
]]

local IslandLayout = {}

--------------------------------------------------------------------------------
-- Ajustes
--------------------------------------------------------------------------------

local CONFIG = {
	Seed = 1337,

	-- Área de terreno real: AreaHalf*2 de lado. PRECISA ser múltiplo de
	-- Chunk/2 (o loop de chunks vai de -AreaHalf a +AreaHalf de Chunk em Chunk).
	AreaHalf = 960, -- 1920 x 1920
	Chunk = 96, -- 96/4 = 24 voxels por lado de chunk
	VoxelRes = 4,

	WaterHalf = 2600, -- lençol de mar visual: 5200 x 5200
	OceanDepth = 96, -- profundidade do oceano visual fora da área real

	-- Costa: raio médio ~700 -> diâmetro jogável ~1400-1600 (correndo a
	-- ~23 studs/s, atravessar leva ~60-70s em linha reta, mais com relevo).
	CoastRadius = 700,
	CoastRadiusMin = 560,
	CoastRadiusMax = 820,
	BeachWidth = 45,

	-- Mar/praia (valores herdados do reparo de água): a superfície do mar fica
	-- em SeaLevel; a areia na beira d'água fica ShoreHeight acima dele, e o
	-- fundo já começa 18 studs abaixo da linha d'água (senão vira placa
	-- caminhável/xadrez) e afunda ShoreDrop por stud saindo da praia.
	SeaLevel = 4,
	SeaFloorDrop = 18,
	ShoreHeight = 8,
	ShoreDrop = 6,

	MinY = -24,
	MaxY = 172, -- (MaxY - MinY) precisa ser múltiplo de VoxelRes

	Hills = {
		Amplitude = 26,
		Scale = 170,
		Detail = 5,
		DetailScale = 48,
		Dome = 16, -- quanto o interior sobe em relação à praia (por inland/coast)
	},

	Mountain = {
		Inland = 270, -- distância da costa até o centro
		Radius = 150,
		Peak = 95,
	},

	-- Trilhas de terra.
	Trail = {
		HalfWidth = 3.8,
		Depth = 0.5,
		Jitter = 0.16, -- fração do comprimento do trecho usada pra sacudir os pontos
		Subdivisions = 4,
	},

	-- Campo aberto (planície).
	Meadow = {
		Radius = 130,
		EdgeBlend = 45,
	},

	-- Lago.
	Lake = {
		Radius = 60, -- raio da água
		Depth = 9,
		ShoreBand = 8, -- faixa de areia em volta
		LevelBelowRim = 1.4,
	},

	-- Sites: raio da clareira/nivelamento e faixa de distância da costa
	-- (inland) onde podem cair. Ordem = prioridade de colocação.
	Sites = {
		{ name = "Campo", r = 130, inlandMin = 190, inlandMax = 360, flatten = true, blend = 45 },
		{ name = "Lago", r = 60, inlandMin = 150, inlandMax = 330, flatten = true, blend = 30 },
		{ name = "Acampamento", r = 62, inlandMin = 95, inlandMax = 230, flatten = true, blend = 24 },
		{ name = "VilaNativa", r = 50, inlandMin = 95, inlandMax = 220, flatten = true, blend = 20 },
		{ name = "CabanasA", r = 40, inlandMin = 85, inlandMax = 240, flatten = true, blend = 18 },
		{ name = "CabanasB", r = 40, inlandMin = 85, inlandMax = 240, flatten = true, blend = 18 },
		{ name = "Ruinas", r = 24, inlandMin = 110, inlandMax = 260, flatten = true, blend = 14 },
		{ name = "Torre", r = 14, inlandMin = 130, inlandMax = 320, flatten = true, blend = 12, highest = true },
		{ name = "Farol", r = 18, inlandMin = 8, inlandMax = 14, flatten = true, blend = 16, coastal = true },
	},
	SiteSpacing = 70, -- folga extra entre bordas de dois sites
	MountainMargin = 40,
}

IslandLayout.CONFIG = CONFIG

local TAU = math.pi * 2

--------------------------------------------------------------------------------
-- Estado do plano
--------------------------------------------------------------------------------

export type Site = {
	name: string,
	x: number,
	z: number,
	r: number,
	y: number, -- altura nivelada do site (onde as construções assentam)
	angle: number, -- ângulo polar em volta do centro da ilha
	blend: number,
	flatten: boolean,
	inland: number,
}

export type Segment = { a: Vector3, b: Vector3, minX: number, maxX: number, minZ: number, maxZ: number }

local currentSeed = CONFIG.Seed
local sites: { [string]: Site } = {}
local siteList: { Site } = {}
local segments: { Segment } = {}
local lakeLevel = CONFIG.SeaLevel
local planned = false

--------------------------------------------------------------------------------
-- Forma da ilha (função analítica) -- sem sites
--------------------------------------------------------------------------------

local function smoothstep(t: number): number
	t = math.clamp(t, 0, 1)
	return t * t * (3 - 2 * t)
end

local function noise2(x: number, z: number, layer: number): number
	return math.noise(x, currentSeed * 0.013 + layer * 17.31, z)
end

local function coastRadiusAt(angle: number): number
	local c, s = math.cos(angle), math.sin(angle)
	local n1 = noise2(c * 1.3 + 7.1, s * 1.3 + 3.7, 1)
	local n2 = noise2(c * 3.1 + 2.2, s * 3.1 + 9.4, 2)
	return math.clamp(CONFIG.CoastRadius + n1 * 220 + n2 * 70, CONFIG.CoastRadiusMin, CONFIG.CoastRadiusMax)
end

-- (distância do centro, raio da costa nesse ângulo, quanto pra dentro da costa)
local function islandInfo(x: number, z: number): (number, number, number)
	local d = math.sqrt(x * x + z * z)
	local coast = coastRadiusAt(math.atan2(z, x))
	return d, coast, coast - d
end

local function mountainSite(): (number, number)
	local rng = Random.new(currentSeed + 7)
	local angle = rng:NextNumber(0, TAU)
	local dist = coastRadiusAt(angle) - CONFIG.Mountain.Inland
	return math.cos(angle) * dist, math.sin(angle) * dist
end

local function mountainContribution(x: number, z: number): number
	local mx, mz = mountainSite()
	local R = CONFIG.Mountain.Radius
	local d = math.sqrt((x - mx) ^ 2 + (z - mz) ^ 2)
	if d >= R then
		return 0
	end
	local f = smoothstep(1 - d / R)
	return CONFIG.Mountain.Peak * f ^ 1.4 + noise2(x / 30, z / 30, 7) * 9 * f
end

-- Relevo bruto: mar, praia, colinas, domo, montanha. Nenhum site ainda.
local function rawHeight(x: number, z: number): number
	local _, coast, inland = islandInfo(x, z)
	local shore = CONFIG.ShoreHeight

	if inland < 0 then
		return math.max(CONFIG.MinY + 2, CONFIG.SeaLevel - CONFIG.SeaFloorDrop + inland * CONFIG.ShoreDrop)
	end

	local beach = CONFIG.BeachWidth
	if inland < beach then
		return shore + smoothstep(inland / beach) * 4
	end

	local H = CONFIG.Hills
	local t = smoothstep(math.min((inland - beach) / 40, 1))
	local h01 = math.clamp(noise2(x / H.Scale, z / H.Scale, 3) + 0.5, 0, 1)
	local hills = h01 * H.Amplitude + noise2(x / H.DetailScale, z / H.DetailScale, 4) * H.Detail
	local dome = (inland / coast) * H.Dome
	return shore + 4 + t * math.max(dome + hills, 0) + mountainContribution(x, z)
end

--------------------------------------------------------------------------------
-- Trilhas: distância ponto-segmento com AABB
--------------------------------------------------------------------------------

local function segmentDistance(x: number, z: number, seg: Segment): number
	local ax, az = seg.a.X, seg.a.Z
	local bx, bz = seg.b.X, seg.b.Z
	local dx, dz = bx - ax, bz - az
	local len2 = dx * dx + dz * dz
	local t = 0
	if len2 > 1e-6 then
		t = math.clamp(((x - ax) * dx + (z - az) * dz) / len2, 0, 1)
	end
	local px, pz = ax + dx * t, az + dz * t
	return math.sqrt((x - px) ^ 2 + (z - pz) ^ 2)
end

local function distToTrail(x: number, z: number): number
	local best = math.huge
	local margin = CONFIG.Trail.HalfWidth + 12
	for _, seg in segments do
		if x >= seg.minX - margin and x <= seg.maxX + margin and z >= seg.minZ - margin and z <= seg.maxZ + margin then
			local d = segmentDistance(x, z, seg)
			if d < best then
				best = d
			end
		end
	end
	return best
end

--------------------------------------------------------------------------------
-- Altura / material / água finais (com sites, lago, campo, trilhas)
--------------------------------------------------------------------------------

local function siteInfluence(site: Site, x: number, z: number): (number, number)
	local d = math.sqrt((x - site.x) ^ 2 + (z - site.z) ^ 2)
	if not site.flatten or d >= site.r + site.blend then
		return d, 0
	end
	local f = smoothstep((site.r + site.blend - d) / site.blend)
	return d, f
end

function IslandLayout.Height(x: number, z: number): number
	local h = rawHeight(x, z)
	local _, _, inland = islandInfo(x, z)
	if inland < 4 then
		return h -- mar e beira d'água intocados
	end

	for _, site in siteList do
		local d, f = siteInfluence(site, x, z)
		if f > 0 then
			local target = site.y
			if site.name == "Farol" then
				target = site.y -- já elevado no plano
			end
			h = h * (1 - f) + target * f
		end

		if site.name == "Lago" then
			local R = CONFIG.Lake.Radius
			if d < R + 2 then
				local depth = CONFIG.Lake.Depth * smoothstep(1 - d / (R + 2)) ^ 0.85
				h -= depth
			end
		end
	end

	local td = distToTrail(x, z)
	if td < CONFIG.Trail.HalfWidth then
		h -= CONFIG.Trail.Depth * smoothstep((CONFIG.Trail.HalfWidth - td) / CONFIG.Trail.HalfWidth)
	end

	return h
end

function IslandLayout.WaterLevel(x: number, z: number): number
	local lake = sites.Lago
	if lake then
		local d = math.sqrt((x - lake.x) ^ 2 + (z - lake.z) ^ 2)
		if d < CONFIG.Lake.Radius + 2 then
			return lakeLevel
		end
	end
	return CONFIG.SeaLevel
end

function IslandLayout.Material(x: number, z: number): Enum.Material
	local _, _, inland = islandInfo(x, z)
	if inland < CONFIG.BeachWidth then
		return Enum.Material.Sand
	end
	if inland < CONFIG.BeachWidth + 10 and noise2(x / 9, z / 9, 5) > 0 then
		return Enum.Material.Sand
	end

	local lake = sites.Lago
	if lake then
		local d = math.sqrt((x - lake.x) ^ 2 + (z - lake.z) ^ 2)
		if d < CONFIG.Lake.Radius + CONFIG.Lake.ShoreBand then
			return Enum.Material.Sand
		elseif d < CONFIG.Lake.Radius + CONFIG.Lake.ShoreBand + 6 then
			return Enum.Material.Ground
		end
	end

	local farol = sites.Farol
	if farol then
		local d = math.sqrt((x - farol.x) ^ 2 + (z - farol.z) ^ 2)
		if d < farol.r + 8 then
			return Enum.Material.Rock
		end
	end

	local td = distToTrail(x, z)
	if td < CONFIG.Trail.HalfWidth then
		if lake and math.sqrt((x - lake.x) ^ 2 + (z - lake.z) ^ 2) < CONFIG.Lake.Radius + 45 then
			return Enum.Material.Mud
		end
		return Enum.Material.Ground
	end

	local mountain = mountainContribution(x, z)
	if mountain > 12 then
		return Enum.Material.Rock
	elseif mountain > 5 then
		return Enum.Material.Ground
	end

	local campo = sites.Campo
	if campo then
		local d = math.sqrt((x - campo.x) ^ 2 + (z - campo.z) ^ 2)
		if d < campo.r + 10 then
			return Enum.Material.Grass
		end
	end

	local vila = sites.VilaNativa
	if vila then
		local d = math.sqrt((x - vila.x) ^ 2 + (z - vila.z) ^ 2)
		if d < vila.r * 0.8 then
			return Enum.Material.Ground
		end
	end

	if noise2(x / 60, z / 60, 6) > 0.1 then
		return Enum.Material.LeafyGrass
	end
	return Enum.Material.Grass
end

--------------------------------------------------------------------------------
-- Planejamento dos sites
--------------------------------------------------------------------------------

local function polar(angle: number, dist: number): (number, number)
	return math.cos(angle) * dist, math.sin(angle) * dist
end

local function farFromExisting(x: number, z: number, r: number): boolean
	local mx, mz = mountainSite()
	if math.sqrt((x - mx) ^ 2 + (z - mz) ^ 2) < CONFIG.Mountain.Radius + r + CONFIG.MountainMargin then
		return false
	end
	for _, other in siteList do
		local minDist = other.r + r + CONFIG.SiteSpacing
		if math.sqrt((x - other.x) ^ 2 + (z - other.z) ^ 2) < minDist then
			return false
		end
	end
	return true
end

local function planSites(rng: Random)
	sites = {}
	siteList = {}

	for _, spec in CONFIG.Sites do
		local best: Site? = nil
		local bestScore = -math.huge
		local tries = if spec.highest then 60 else 160

		for _ = 1, tries do
			local angle = rng:NextNumber(0, TAU)
			local coast = coastRadiusAt(angle)
			local inland = rng:NextNumber(spec.inlandMin, spec.inlandMax)
			local x, z = polar(angle, coast - inland)

			if farFromExisting(x, z, spec.r) then
				local y = rawHeight(x, z)
				local score = if spec.highest then y else rng:NextNumber()

				-- Farol: prefere longe do Acampamento (ponta oposta da ilha).
				if spec.coastal and sites.Acampamento then
					local camp = sites.Acampamento
					score = math.sqrt((x - camp.x) ^ 2 + (z - camp.z) ^ 2)
				end

				if score > bestScore then
					bestScore = score
					best = {
						name = spec.name,
						x = x,
						z = z,
						r = spec.r,
						y = y,
						angle = angle,
						blend = spec.blend,
						flatten = spec.flatten,
						inland = inland,
					}
					if not spec.highest and not spec.coastal then
						break -- primeiro válido serve
					end
				end
			end
		end

		if best then
			if best.name == "Farol" then
				best.y = math.max(best.y, CONFIG.ShoreHeight + 3) + 4 -- ponta rochosa elevada
			end
			if best.name == "Campo" then
				best.y = best.y + 0.5
			end
			sites[best.name] = best
			table.insert(siteList, best)
		else
			warn(string.format("[IslandLayout] Não achei lugar pro site '%s' -- ele não vai existir nesta seed.", spec.name))
		end
	end

	local lake = sites.Lago
	if lake then
		lakeLevel = lake.y - CONFIG.Lake.LevelBelowRim
	end
end

--------------------------------------------------------------------------------
-- Trilhas
--------------------------------------------------------------------------------

local function addSegment(a: Vector3, b: Vector3)
	table.insert(segments, {
		a = a,
		b = b,
		minX = math.min(a.X, b.X),
		maxX = math.max(a.X, b.X),
		minZ = math.min(a.Z, b.Z),
		maxZ = math.max(a.Z, b.Z),
	})
end

-- Ponto de "entrada" de trilha de um site: a borda da clareira virada pro
-- vizinho (lago: a margem, não o meio da água).
local function trailNode(site: Site, toward: Vector3): Vector3
	local center = Vector3.new(site.x, 0, site.z)
	local dir = (toward - center) * Vector3.new(1, 0, 1)
	if dir.Magnitude < 1 then
		return center
	end
	dir = dir.Unit
	local edge = if site.name == "Lago" then CONFIG.Lake.Radius + 16 else math.max(site.r * 0.55, 8)
	return center + dir * edge
end

local function addTrail(rng: Random, from: Vector3, to: Vector3)
	-- Desvia do lago se o trecho passar por cima dele.
	local lake = sites.Lago
	local waypoints = { from }
	if lake then
		local lc = Vector3.new(lake.x, 0, lake.z)
		local seg: Segment = { a = from, b = to, minX = 0, maxX = 0, minZ = 0, maxZ = 0 }
		local d = segmentDistance(lc.X, lc.Z, seg)
		local endpointsNear = (from - lc).Magnitude < CONFIG.Lake.Radius + 30 or (to - lc).Magnitude < CONFIG.Lake.Radius + 30
		if d < CONFIG.Lake.Radius + 14 and not endpointsNear then
			local dir = (to - from).Unit
			local side = Vector3.new(-dir.Z, 0, dir.X)
			local mid = (from + to) / 2
			local sign = if (lc - mid):Dot(side) > 0 then -1 else 1
			table.insert(waypoints, lc + side * (sign * (CONFIG.Lake.Radius + 28)))
		end
	end
	table.insert(waypoints, to)

	for i = 1, #waypoints - 1 do
		local a, b = waypoints[i], waypoints[i + 1]
		local n = CONFIG.Trail.Subdivisions
		local dir = (b - a)
		local len = dir.Magnitude
		if len < 1 then
			continue
		end
		dir = dir.Unit
		local side = Vector3.new(-dir.Z, 0, dir.X)
		local prev = a
		for k = 1, n do
			local t = k / n
			local p = a + (b - a) * t
			if k < n then
				local wobble = math.sin(t * math.pi) * len * CONFIG.Trail.Jitter
				p += side * rng:NextNumber(-wobble, wobble)
			end
			addSegment(prev, p)
			prev = p
		end
	end
end

local function planTrails(rng: Random)
	segments = {}

	-- Loop principal: POIs "habitados", em ordem angular.
	local loopNames = { "Acampamento", "CabanasA", "Lago", "Campo", "CabanasB", "VilaNativa" }
	local loop: { Site } = {}
	for _, name in loopNames do
		if sites[name] then
			table.insert(loop, sites[name])
		end
	end
	table.sort(loop, function(a, b)
		return a.angle < b.angle
	end)

	for i, site in loop do
		local nextSite = loop[(i % #loop) + 1]
		if nextSite ~= site then
			local a = trailNode(site, Vector3.new(nextSite.x, 0, nextSite.z))
			local b = trailNode(nextSite, Vector3.new(site.x, 0, site.z))
			addTrail(rng, a, b)
		end
	end

	-- Ramais: do POI do loop mais perto.
	local function nearestLoopSite(x: number, z: number): Site?
		local best: Site? = nil
		local bestD = math.huge
		for _, s in loop do
			local d = (s.x - x) ^ 2 + (s.z - z) ^ 2
			if d < bestD then
				bestD = d
				best = s
			end
		end
		return best
	end

	for _, name in { "Torre", "Farol", "Ruinas" } do
		local site = sites[name]
		if site then
			local near = nearestLoopSite(site.x, site.z)
			if near then
				local a = trailNode(near, Vector3.new(site.x, 0, site.z))
				local b = trailNode(site, Vector3.new(near.x, 0, near.z))
				addTrail(rng, a, b)
			end
		end
	end

	-- Boca da caverna.
	local ex, ez = IslandLayout.CaveEntrance()
	local near = nearestLoopSite(ex, ez)
	if near then
		local a = trailNode(near, Vector3.new(ex, 0, ez))
		addTrail(rng, a, Vector3.new(ex, 0, ez))
	end
end

--------------------------------------------------------------------------------
-- API
--------------------------------------------------------------------------------

function IslandLayout.SetSeed(seed: number)
	currentSeed = seed
	planned = false
end

--[[
	Plan(seed?)
	Recalcula sites e trilhas. IslandGenerator chama antes do terreno; os
	outros módulos chamam Plan() sem argumento só pra garantir que existe
	(é barato e idempotente pra mesma seed).
]]
function IslandLayout.Plan(seed: number?)
	if seed then
		IslandLayout.SetSeed(seed)
	end
	if planned then
		return
	end
	local rng = Random.new(currentSeed + 101)
	planSites(rng)
	planTrails(rng)
	planned = true
end

function IslandLayout.Seed(): number
	return currentSeed
end

function IslandLayout.IslandInfo(x: number, z: number): (number, number, number)
	return islandInfo(x, z)
end

function IslandLayout.CoastRadiusAt(angle: number): number
	return coastRadiusAt(angle)
end

function IslandLayout.RawHeight(x: number, z: number): number
	return rawHeight(x, z)
end

function IslandLayout.MountainSite(): (number, number)
	return mountainSite()
end

function IslandLayout.MountainContribution(x: number, z: number): number
	return mountainContribution(x, z)
end

-- Boca da caverna: na base da montanha, virada pro centro da ilha.
function IslandLayout.CaveEntrance(): (number, number)
	local mx, mz = mountainSite()
	local len = math.sqrt(mx * mx + mz * mz)
	local dx, dz = 1, 0
	if len > 0.01 then
		dx, dz = -mx / len, -mz / len
	end
	local e = CONFIG.Mountain.Radius * 0.72
	return mx + dx * e, mz + dz * e
end

function IslandLayout.Sites(): { [string]: Site }
	IslandLayout.Plan()
	return sites
end

function IslandLayout.Site(name: string): Site?
	IslandLayout.Plan()
	return sites[name]
end

function IslandLayout.TrailSegments(): { Segment }
	IslandLayout.Plan()
	return segments
end

function IslandLayout.DistToTrail(x: number, z: number): number
	return distToTrail(x, z)
end

function IslandLayout.LakeLevel(): number
	return lakeLevel
end

--[[
	IsClearAt(x, z, margin?)
	true quando NÃO se deve plantar árvore/rocha/arbusto ali: dentro de
	trilha, de clareira de POI, do campo, do lago ou perto da boca da caverna.
]]
function IslandLayout.IsClearAt(x: number, z: number, margin: number?): boolean
	local m = margin or 0
	if distToTrail(x, z) < CONFIG.Trail.HalfWidth + 4 + m then
		return true
	end
	for _, site in siteList do
		local d = math.sqrt((x - site.x) ^ 2 + (z - site.z) ^ 2)
		local keep = site.r + m
		if site.name == "Lago" then
			keep = CONFIG.Lake.Radius + CONFIG.Lake.ShoreBand + 10 + m
		end
		if d < keep then
			return true
		end
	end
	local ex, ez = IslandLayout.CaveEntrance()
	if (x - ex) ^ 2 + (z - ez) ^ 2 < (26 + m) ^ 2 then
		return true
	end
	return false
end

-- Constantes pros sistemas de runtime (em vez de "260" espalhado).
function IslandLayout.CoastRadiusMax(): number
	return CONFIG.CoastRadiusMax
end

function IslandLayout.AreaHalf(): number
	return CONFIG.AreaHalf
end

function IslandLayout.MaxY(): number
	return CONFIG.MaxY
end

return IslandLayout
