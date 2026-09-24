--!nocheck
-- `sources` vem de run_house_plan.py. Roda HouseGenerator.PlanSite (puro)
-- com as clareiras REAIS do mapa salvo (centro/raio dos marcadores Layout),
-- trilhas aproximadas pelos postes salvos e as rochas/postes como
-- obstáculos. Prova que as duas casas de cada clareira cabem, dentro do
-- raio, sem se encostar, longe da trilha e fora das rochas.

local stub = loadstring(sources.RobloxStub, "RobloxStub")()
local tokens
tokens = setmetatable({}, { __index = function(t, key)
	local token = setmetatable({ __module = key }, { __index = function(_, k) return tokens[k] end })
	rawset(t, key, token)
	return token
end })
local modules = {}
local env
local function loadModule(name)
	if modules[name] then return modules[name] end
	local fn = assert(loadstring(assert(sources[name], name), name))
	setfenv(fn, env)
	modules[name] = fn()
	return modules[name]
end
env = setmetatable({ script = { Parent = tokens }, require = function(t) return loadModule(t.__module) end }, { __index = getfenv() })
RaycastParams = { new = function() return {} end }
local Footprints = {
	CampCabin = { MinX = -36, MaxX = 34.5, MinZ = -29.8, MaxZ = 25.6 },
	CasaDoCaseiro = { MinX = -28.4, MaxX = 26.4, MinZ = -26.8, MaxZ = 33.4 },
	Celeiro = { MinX = -34, MaxX = 31.8, MinZ = -31.8, MaxZ = 48.6 },
	CasaDaFazenda = { MinX = -37, MaxX = 28.8, MinZ = -26.4, MaxZ = 34 },
}
-- Só PlanSite interessa: dublês pros módulos que o gerador carrega.
modules.IslandLayout = {}
modules.Structures = {}
modules.CampCabin = { Footprint = Footprints.CampCabin }
modules.CasaDoCaseiro = { Footprint = Footprints.CasaDoCaseiro }
modules.Celeiro = { Footprint = Footprints.Celeiro }
modules.CasaDaFazenda = { Footprint = Footprints.CasaDaFazenda }
modules.HouseKit = {}
local HG = loadModule("HouseGenerator")

local checks = 0
local function check(c, m, ...) checks += 1 if not c then error(string.format(m, ...), 0) end end

-- Mapa salvo (~/Documents/Roblox/server.rbxl): marcadores e postes (x, z relativos ao centro).
local SITES = {
	{ name = "Acampamento", c = Vector3.new(-565.5, 23.8, 112.3), r = 100, lamps = { { 63, 56 }, { -6, -144 } }, rocks = { { 0, -97, 20 } } },
	{ name = "CabanasA", c = Vector3.new(96.8, 21.6, 487.5), r = 85, lamps = { { 63, -58 }, { -117, -16 } }, rocks = {} },
	{ name = "CabanasB", c = Vector3.new(-606.1, 30.2, -335.5), r = 85, lamps = { { 44, 12 }, { -3, 68 }, { 118, -1 } },
		-- Afloramento_6 e Rochas_20: corte de cada rocha na altura do chão
		-- (elas estão meio enterradas), não a caixa inteira.
		rocks = { { -4, -42, 37.6 }, { -13, -28, 15.8 }, { 10, -44, 10 }, { 50, -53, 21 }, { 45, -46, 13 }, { 57, -54, 11.5 }, { 51, -70, 11.2 } } },
	{ name = "VilaNativa", c = Vector3.new(607.8, 25.6, -141.0), r = 95, lamps = { { -33, -42 }, { 90, -84 }, { -46, 115 } }, rocks = { { -35, -27, 2 } } },
	-- Campo: trilhas pra Vila Nativa (-63°) e CabanasA (139°); as três
	-- árvores solitárias (copa inteira) como obstáculo.
	{ name = "Campo", c = Vector3.new(380.3, 33.8, 240.7), r = 130, lamps = { { 41, -79 }, { -141, 105 } }, rocks = { { -116, -17, 17 }, { 46, 44, 19 }, { 46, -27, 4 } } },
}
local plans = { Acampamento = { "CampCabin", "CasaDoCaseiro" }, CabanasA = { "CasaDoCaseiro", "CampCabin" }, CabanasB = { "CampCabin", "CasaDoCaseiro" }, VilaNativa = { "CasaDoCaseiro", "CampCabin" }, Campo = { "Celeiro", "CasaDaFazenda" } }

local function segDist(px, pz, ax, az, bx, bz)
	local dx, dz = bx - ax, bz - az
	local t = math.clamp(((px - ax) * dx + (pz - az) * dz) / (dx * dx + dz * dz), 0, 1)
	return math.sqrt((px - ax - dx * t) ^ 2 + (pz - az - dz * t) ^ 2)
end

for _, site in SITES do
	-- Trilha: da borda de entrada (0,55 r) passando pelo poste e seguindo pra fora.
	local segs = {}
	for _, l in site.lamps do
		local d = Vector3.new(l[1], 0, l[2])
		local dir = d.Unit
		local node = site.c + dir * (site.r * 0.55)
		local far = site.c + dir * (d.Magnitude + 120)
		table.insert(segs, { node.X, node.Z, far.X, far.Z })
	end
	local planEnv = {
		TrailHalfWidth = 3.8,
		TrailDistance = function(x, z)
			local best = math.huge
			for _, s in segs do best = math.min(best, segDist(x, z, s[1], s[2], s[3], s[4]) - 3) end
			return best
		end,
		Blocked = function(cf, rect)
			for _, rock in site.rocks do
				local p = site.c + Vector3.new(rock[1], 0, rock[2])
				local l = cf:PointToObjectSpace(p)
				local dx = math.max(rect.MinX - l.X, 0, l.X - rect.MaxX)
				local dz = math.max(rect.MinZ - l.Z, 0, l.Z - rect.MaxZ)
				if math.sqrt(dx * dx + dz * dz) < rock[3] then return true end
			end
			for _, lamp in site.lamps do
				local l = cf:PointToObjectSpace(site.c + Vector3.new(lamp[1], 0, lamp[2]))
				if l.X > rect.MinX - 1 and l.X < rect.MaxX + 1 and l.Z > rect.MinZ - 1 and l.Z < rect.MaxZ + 1 then return true end
			end
			return false
		end,
	}
	local rects = {}
	for _, s in plans[site.name] do table.insert(rects, Footprints[s]) end
	local picks = HG.PlanSite(site.c, site.r, rects, planEnv)
	local placed = 0
	for _, cf in picks do if cf then placed += 1 end end
	local relaxed = false
	if placed < #rects then
		-- Mesmo fluxo do Generate: segunda tentativa relaxada, depois
		-- terceira ignorando a trilha (último recurso).
		planEnv.Relaxed = true
		picks = HG.PlanSite(site.c, site.r, rects, planEnv)
		placed = 0
		for _, cf in picks do if cf then placed += 1 end end
		relaxed = true
		if placed < #rects then
			planEnv.IgnoreTrail = true
			local desperate = HG.PlanSite(site.c, site.r, rects, planEnv)
			local dplaced = 0
			for _, cf in desperate do if cf then dplaced += 1 end end
			if dplaced > placed then
				picks, placed = desperate, dplaced
			end
		end
	end
	-- CabanasB: o Afloramento_6 ocupa a metade sul e as trilhas (Acampamento
	-- ao norte, Vila Nativa a leste) cortam o resto; com as rochas modeladas
	-- de forma conservadora aqui só uma casa garantida. No Studio o
	-- GetPartsInPart usa a forma real da rocha.
	local needed = if site.name == "CabanasB" then 1 else #rects
	check(placed >= needed, "%s: só %d de %d casas couberam", site.name, placed, #rects)
	print(string.format("[plan] %s: %d de %d casas%s", site.name, placed, #rects, if relaxed then " (tentativa relaxada)" else ""))
	local edge = site.r - 3 + (if relaxed then 24 else 0)
	for i, cf in picks do
		if not cf then continue end
		check(cf ~= false, "%s: casa %d (%s) não coube", site.name, i, plans[site.name][i])
		for _, corner in { { rects[i].MinX, rects[i].MinZ }, { rects[i].MaxX, rects[i].MinZ }, { rects[i].MaxX, rects[i].MaxZ }, { rects[i].MinX, rects[i].MaxZ } } do
			local w = cf * Vector3.new(corner[1], 0, corner[2])
			check((Vector3.new(w.X, 0, w.Z) - Vector3.new(site.c.X, 0, site.c.Z)).Magnitude <= edge + 1e-6, "%s: casa %d fora do raio", site.name, i)
			check(planEnv.TrailDistance(w.X, w.Z) >= 3.8 + 2.5 - 1e-6, "%s: casa %d em cima da trilha", site.name, i)
		end
		check(not planEnv.Blocked(cf, rects[i]), "%s: casa %d em cima de rocha/poste", site.name, i)
		check(math.abs(cf.Position.Y - site.c.Y) < 1e-6, "%s: CFrame no chão da clareira", site.name)
		local toCenter = (site.c - cf.Position)
		local ang = math.deg(math.acos(math.clamp(cf.LookVector:Dot(Vector3.new(toCenter.X, 0, toCenter.Z).Unit), -1, 1)))
		check(relaxed or ang < 40, "%s: casa %d deveria olhar pro miolo (%.0f°)", site.name, i, ang)
	end
	-- As duas não se sobrepõem (amostra de pontos de uma dentro da outra).
	local a, b = picks[1], picks[2]
	if not a or not b then
		local only = a or b
		local p = only.Position - site.c
		print(string.format("[plan] %s: só %s em %.0f° (%.0f do centro)", site.name, if a then plans[site.name][1] else plans[site.name][2], math.deg(math.atan2(p.Z, p.X)), p.Magnitude))
		continue
	end
	for x = rects[2].MinX, rects[2].MaxX, 2 do
		for z = rects[2].MinZ, rects[2].MaxZ, 2 do
			local l = a:PointToObjectSpace(b * Vector3.new(x, 0, z))
			check(not (l.X > rects[1].MinX and l.X < rects[1].MaxX and l.Z > rects[1].MinZ and l.Z < rects[1].MaxZ), "%s: casas sobrepostas", site.name)
		end
	end
	local pa, pb = a.Position - site.c, b.Position - site.c
	print(string.format("[plan] %s: %s em ângulo %.0f° (%.0f do centro), %s em %.0f° (%.0f)", site.name,
		plans[site.name][1], math.deg(math.atan2(pa.Z, pa.X)), pa.Magnitude, plans[site.name][2], math.deg(math.atan2(pb.Z, pb.X)), pb.Magnitude))
end
--------------------------------------------------------------------------------
-- RestoreTerrain: reescreve o lote com a altura do IslandLayout (desfaz o
-- nivelamento da versão antiga). Superfície implícita pela ocupação = altura.
--------------------------------------------------------------------------------

Region3 = { new = function(lo, hi) return { Lo = lo, Hi = hi } end }
local written = nil
function stub.Workspace.Terrain.WriteVoxels(_, region, res, mats, occs)
	written = { region = region, res = res, mats = mats, occs = occs }
end
local function heightAt(x, z) return 30 + 0.08 * x - 0.05 * z + math.sin(x / 7) end
modules.IslandLayout.CONFIG = { VoxelRes = 4, MinY = -24, MaxY = 172 }
modules.IslandLayout.Height = heightAt
modules.IslandLayout.Material = function() return Enum.Material.Grass end
modules.IslandLayout.WaterLevel = function() return 4 end
local ground = CFrame.new(103.7, 36.2, 51.3) * CFrame.Angles(0, 0.55, 0)
local rect = Footprints.CasaDoCaseiro
HG.RestoreTerrain(ground, rect)
check(written ~= nil, "RestoreTerrain deveria escrever voxels")
local r = written.region
for _, v in { r.Lo.X, r.Lo.Z, r.Hi.X, r.Hi.Z } do check(v % 4 == 0, "região fora da grade de 4") end
check((r.Lo.Y + 24) % 4 == 0 and (r.Hi.Y + 24) % 4 == 0, "altura fora da grade do IslandGenerator")
local nx, ny, nz = (r.Hi.X - r.Lo.X) / 4, (r.Hi.Y - r.Lo.Y) / 4, (r.Hi.Z - r.Lo.Z) / 4
check(#written.mats == nx and #written.mats[1] == ny and #written.mats[1][1] == nz, "dimensões dos voxels")
for _, cx in { rect.MinX - 6, 0, rect.MaxX + 6 } do
	for _, cz in { rect.MinZ - 6, 0, rect.MaxZ + 6 } do
		local w = ground * Vector3.new(cx, 0, cz)
		check(w.X > r.Lo.X and w.X < r.Hi.X and w.Z > r.Lo.Z and w.Z < r.Hi.Z, "região não cobre o lote + folga")
	end
end
check(r.Lo.Y <= 36.2 - 12 and r.Hi.Y >= 36.2 + 40, "região não cobre o corte/aterro antigo (Y %.0f..%.0f)", r.Lo.Y, r.Hi.Y)
for i = 1, nx, 5 do
	for k = 1, nz, 5 do
		local x, z = r.Lo.X + (i - 0.5) * 4, r.Lo.Z + (k - 0.5) * 4
		local surface = r.Lo.Y
		for j = 1, ny do
			local occ = written.occs[i][j][k]
			if occ > 0 and written.mats[i][j][k] ~= Enum.Material.Water then
				surface = r.Lo.Y + (j - 1) * 4 + occ * 4
			end
		end
		check(math.abs(surface - heightAt(x, z)) < 0.01, "superfície %.2f ~= altura do layout %.2f", surface, heightAt(x, z))
	end
end

print(string.format("PASS: planejamento das casas; %d verificações", checks))
