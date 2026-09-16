--!strict
--[[
	PoiGenerator (ferramenta de editor)
	Constrói os pontos de interesse nos sites que IslandLayout planejou, com
	as peças de Structures.lua. Roda DEPOIS do terreno e da floresta
	(IslandGenerator.Generate chama sozinho, mas dá pra repetir na mão pra
	reconstruir só os POIs):

		local Poi = require(game.ServerScriptService.Server.Tools.PoiGenerator)
		Poi.Generate()      -- reconstrói todos (limpa Workspace/Ilha/POIs)
		Poi.Clear()

	O QUE VAI EM CADA SITE (nomes de IslandLayout.CONFIG.Sites):
	  Acampamento  Lodge de frente pra fogueira central, 3 cabanas em volta,
	               2 mesas de piquenique, lampiões acesos, varal.
	  CabanasA/B   2-3 cabanas + fogueira + latrina + mesa; 1 lampião aceso.
	  Lago         Píer entrando na água, casa de barcos na margem, barco
	               furado virado, canoa, secador de peixe.
	  Campo        Celeiro, dois alvos de arco, fardos de feno espalhados,
	               cerca curta caída.
	  Torre        Torre de vigia (escada TrussPart escalável).
	  Farol        Farol na ponta rochosa + barraco do faroleiro.
	  VilaNativa   5 moradias + casa comunal mobiliadas, varandas, totem,
	               fogueira, preparo de carne, sangue e canoa.
	  Trilhas      Lampiões a cada ~60 studs; acesos só perto dos POIs.
	  Layout       Marcadores invisíveis de cada site (Attribute Poi/Raio) --
	               LobbyManager/RaftGenerator/PlaneCrash leem daqui depois de
	               salvo, sem precisar recalcular o layout.

	Ruínas e Caverna continuam no IslandGenerator; a Jangada no RaftGenerator.
]]

local Workspace = game:GetService("Workspace")
local Terrain = Workspace.Terrain

local IslandLayout = require(script.Parent.IslandLayout)
local S = require(script.Parent.Structures)
local NativeVillage = require(script.Parent.NativeVillage)

local PoiGenerator = {}

local TAU = math.pi * 2

--------------------------------------------------------------------------------
-- Chão
--------------------------------------------------------------------------------

local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Include
rayParams.FilterDescendantsInstances = { Terrain }
rayParams.IgnoreWater = true

local function groundY(x: number, z: number): number
	local result = Workspace:Raycast(Vector3.new(x, IslandLayout.MaxY() + 60, z), Vector3.new(0, -(IslandLayout.MaxY() + 200), 0), rayParams)
	if result then
		return result.Position.Y
	end
	return IslandLayout.Height(x, z)
end

-- CFrame no chão em (x, z) olhando pra `toward` (só no plano).
local function groundCF(x: number, z: number, toward: Vector3?): CFrame
	local pos = Vector3.new(x, groundY(x, z), z)
	if toward then
		local look = Vector3.new(toward.X, pos.Y, toward.Z)
		if (look - pos).Magnitude > 0.5 then
			return CFrame.lookAt(pos, look)
		end
	end
	return CFrame.new(pos)
end

local function polar(cx: number, cz: number, angle: number, dist: number): (number, number)
	return cx + math.cos(angle) * dist, cz + math.sin(angle) * dist
end

--------------------------------------------------------------------------------
-- Pastas
--------------------------------------------------------------------------------

local function getIlha(): Folder
	local ilha = Workspace:FindFirstChild("Ilha")
	if not ilha then
		ilha = Instance.new("Folder")
		ilha.Name = "Ilha"
		ilha.Parent = Workspace
	end
	return ilha :: Folder
end

local function resetFolder(parent: Instance, name: string): Folder
	local existing = parent:FindFirstChild(name)
	if existing then
		existing:Destroy()
	end
	local folder = Instance.new("Folder")
	folder.Name = name
	folder.Parent = parent
	return folder
end

--------------------------------------------------------------------------------
-- POIs
--------------------------------------------------------------------------------

local function buildCamp(folder: Folder, site: IslandLayout.Site, rng: Random)
	local cx, cz = site.x, site.z
	local center = Vector3.new(cx, 0, cz)
	-- A frente do acampamento aponta pro centro da ilha.
	local inward = (Vector3.new(0, 0, 0) - center)
	inward = if inward.Magnitude > 1 then inward.Unit else Vector3.new(0, 0, 1)
	local baseAngle = math.atan2(inward.Z, inward.X)

	S.FireCircle(folder, groundCF(cx, cz), rng, true)

	-- Lodge atrás da fogueira, olhando pra ela.
	local lx, lz = polar(cx, cz, baseAngle + math.pi, 30)
	S.Lodge(folder, groundCF(lx, lz, center))

	-- Cabanas em leque na frente/lados, todas viradas pra fogueira.
	for i, a in { baseAngle - 0.9, baseAngle + 0.9, baseAngle + math.pi / 2 + 0.5 } do
		local d = 34 + rng:NextNumber(-3, 3)
		local x, z = polar(cx, cz, a, d)
		S.Cabin(folder, groundCF(x, z, center), { Name = "Cabana_" .. i, Lit = i == 1, Weapon = i == 2, Width = 16 + rng:NextNumber(-1, 2), Depth = 14 + rng:NextNumber(-1, 2) })
	end

	-- Mesas, varal, lampiões.
	local tx, tz = polar(cx, cz, baseAngle - math.pi / 2, 12)
	S.PicnicTable(folder, groundCF(tx, tz) * CFrame.Angles(0, rng:NextNumber(0, TAU), 0))
	tx, tz = polar(cx, cz, baseAngle - math.pi / 2 + 0.6, 19)
	S.PicnicTable(folder, groundCF(tx, tz) * CFrame.Angles(0, rng:NextNumber(0, TAU), 0))
	for i = 1, 3 do
		local a = baseAngle + (i - 2) * 1.1
		local x, z = polar(cx, cz, a, 14)
		S.TrailLamp(folder, groundCF(x, z, center), true)
	end
	-- Varal.
	local vx, vz = polar(cx, cz, baseAngle + math.pi / 2 - 0.6, 20)
	local vcf = groundCF(vx, vz)
	for _, sx in { -1, 1 } do
		S.Part(folder, "VaralPoste", Vector3.new(0.35, 6, 0.35), vcf * CFrame.new(sx * 4, 3, 0), Enum.Material.Wood, S.Colors.LogDark)
	end
	S.Beam(folder, "VaralCorda", (vcf * CFrame.new(-4, 5.8, 0)).Position, (vcf * CFrame.new(4, 5.4, 0)).Position, 0.12, Enum.Material.SmoothPlastic, S.Colors.Rope, false)
	for i = 1, 3 do
		S.Part(folder, "Roupa", Vector3.new(1.6, 2.2, 0.15), vcf * CFrame.new(-2.5 + (i - 1) * 2.5, 4.5, 0), Enum.Material.Fabric, Color3.fromRGB(120 + i * 30, 110, 100), { CanCollide = false })
	end
end

local function buildCabinCluster(folder: Folder, site: IslandLayout.Site, rng: Random, count: number)
	local cx, cz = site.x, site.z
	local center = Vector3.new(cx, 0, cz)
	local start = rng:NextNumber(0, TAU)

	S.FireCircle(folder, groundCF(cx, cz), rng, true)
	for i = 1, count do
		local a = start + (i - 1) / count * TAU + rng:NextNumber(-0.25, 0.25)
		local x, z = polar(cx, cz, a, 26 + rng:NextNumber(-2, 3))
		S.Cabin(folder, groundCF(x, z, center), { Name = "Cabana_" .. i, Lit = i == 1, Weapon = i == count, Width = 15 + rng:NextNumber(0, 3), Depth = 13 + rng:NextNumber(0, 2) })
	end
	-- Latrina + mesa + lampião.
	local ox, oz = polar(cx, cz, start + math.pi / count, 33)
	S.Cabin(folder, groundCF(ox, oz, center), { Name = "Latrina", Width = 4.6, Depth = 4.6, WallHeight = 7.2, Windows = false, Furniture = false, Spawn = false, Pitch = 22 })
	local tx, tz = polar(cx, cz, start + math.pi / count + 1.2, 13)
	S.PicnicTable(folder, groundCF(tx, tz) * CFrame.Angles(0, rng:NextNumber(0, TAU), 0))
	local lx, lz = polar(cx, cz, start - 0.5, 9)
	S.TrailLamp(folder, groundCF(lx, lz, center), true)
end

local function buildLake(folder: Folder, site: IslandLayout.Site, rng: Random)
	local cx, cz = site.x, site.z
	local R = IslandLayout.CONFIG.Lake.Radius
	local level = IslandLayout.LakeLevel()
	local center = Vector3.new(cx, level, cz)

	-- Lado da margem "usado": virado pro centro da ilha.
	local inward = Vector3.new(-cx, 0, -cz)
	inward = if inward.Magnitude > 1 then inward.Unit else Vector3.new(0, 0, 1)
	local a0 = math.atan2(inward.Z, inward.X)

	-- Píer: começa na areia e entra na água.
	local sx, sz = polar(cx, cz, a0, R + 2)
	local shoreCF = CFrame.lookAt(Vector3.new(sx, level, sz), center)
	S.Dock(folder, shoreCF, 30, level)

	-- Casa de barcos na margem, ao lado do píer, de frente pra água.
	local bx, bz = polar(cx, cz, a0 + 0.42, R + 22)
	S.Boathouse(folder, groundCF(bx, bz, center))

	-- Barco furado virado e canoa em outros pontos da margem.
	local ox, oz = polar(cx, cz, a0 - 0.7, R + 6)
	S.Boat(folder, groundCF(ox, oz, center) * CFrame.Angles(0, rng:NextNumber(-0.5, 0.5), 0), true)
	local kx, kz = polar(cx, cz, a0 + 2.2, R + 5)
	S.Canoe(folder, groundCF(kx, kz, center) * CFrame.Angles(0, math.pi / 2 + rng:NextNumber(-0.3, 0.3), 0))

	local fx, fz = polar(cx, cz, a0 - 0.35, R + 16)
	S.FishRack(folder, groundCF(fx, fz, center))

	-- Pedras na margem.
	for i = 1, 7 do
		local a = rng:NextNumber(0, TAU)
		local d = R + rng:NextNumber(3, 12)
		local px, pz = polar(cx, cz, a, d)
		local s = rng:NextNumber(1.2, 3.2)
		S.Part(folder, "Pedra_" .. i, Vector3.new(s, s * 0.7, s * 1.1), groundCF(px, pz) * CFrame.new(0, s * 0.2, 0) * CFrame.Angles(0, a, 0), Enum.Material.Slate, Color3.fromRGB(105, 103, 98))
	end
end

local function buildMeadow(folder: Folder, site: IslandLayout.Site, rng: Random)
	local cx, cz = site.x, site.z
	local center = Vector3.new(cx, 0, cz)
	local a0 = rng:NextNumber(0, TAU)

	-- Celeiro deslocado do centro, com as portas viradas pro centro do campo.
	local bx, bz = polar(cx, cz, a0, 42)
	S.Barn(folder, groundCF(bx, bz, center))

	-- Alvos de arco em linha, apontando pra onde se atira deles.
	for i = 1, 2 do
		local x, z = polar(cx, cz, a0 + math.pi * 0.7, 30 + (i - 1) * 9)
		S.ArcheryTarget(folder, groundCF(x, z) * CFrame.Angles(0, a0 + math.pi * 0.7 + math.pi / 2, 0))
	end
	-- Linha de tiro (uma tora).
	local lx, lz = polar(cx, cz, a0 + math.pi * 0.7 + 0.35, 34)
	S.Part(folder, "LinhaDeTiro", Vector3.new(9, 0.9, 0.9), groundCF(lx, lz) * CFrame.new(0, 0.45, 0) * CFrame.Angles(0, a0 + math.pi * 0.7, 0), Enum.Material.Wood, S.Colors.Log, { Shape = Enum.PartType.Cylinder })

	-- Fardos espalhados.
	for i = 1, 7 do
		local a = rng:NextNumber(0, TAU)
		local d = rng:NextNumber(15, site.r * 0.8)
		local x, z = polar(cx, cz, a, d)
		S.HayBale(folder, groundCF(x, z) * CFrame.Angles(0, rng:NextNumber(0, TAU), 0), rng:NextNumber() < 0.3)
	end

	-- Cerca velha caída (uns mourões com travessas quebradas).
	local fa = a0 + math.pi * 1.35
	local fx, fz = polar(cx, cz, fa, 55)
	local fcf = groundCF(fx, fz) * CFrame.Angles(0, fa + math.pi / 2, 0)
	for i = 0, 6 do
		local pcf = fcf * CFrame.new((i - 3) * 6, 0, 0)
		S.Part(folder, "Mourao", Vector3.new(0.5, 4.2, 0.5), pcf * CFrame.new(0, 2.0, 0) * CFrame.Angles(0, 0, rng:NextNumber(-0.12, 0.12)), Enum.Material.Wood, S.Colors.LogDark)
		if i < 6 and rng:NextNumber() < 0.75 then
			S.Part(folder, "Travessa", Vector3.new(6.2, 0.35, 0.3), pcf * CFrame.new(3, 3.2 + rng:NextNumber(-0.4, 0.2), 0) * CFrame.Angles(0, 0, rng:NextNumber(-0.05, 0.05)), Enum.Material.Wood, S.Colors.Log, { CanCollide = false })
		end
	end

	local lx, lz = polar(cx, cz, a0 + 0.35, 32)
	S.TrailLamp(folder, groundCF(lx, lz), true)
	S.Marker(folder, "SpawnPOI", groundCF(cx, cz) * CFrame.new(0, 2, 0), { SpawnPOI = true })
end

local function buildTower(folder: Folder, site: IslandLayout.Site)
	local toward = Vector3.new(0, 0, 0)
	S.WatchTower(folder, groundCF(site.x, site.z, toward))
end

local function buildLighthouse(folder: Folder, site: IslandLayout.Site, rng: Random)
	local cx, cz = site.x, site.z
	local inward = Vector3.new(-cx, 0, -cz).Unit
	S.Lighthouse(folder, groundCF(cx, cz, Vector3.new(0, 0, 0)))
	-- Barraco do faroleiro, um pouco pra dentro, virado pro farol.
	local kx, kz = cx + inward.X * 26, cz + inward.Z * 26
	S.Cabin(folder, groundCF(kx, kz, Vector3.new(cx, 0, cz)), { Name = "BarracoFaroleiro", Width = 11, Depth = 10, WallHeight = 8, Pitch = 32, Lit = true })
	-- Pedras da ponta.
	for i = 1, 6 do
		local a = rng:NextNumber(0, TAU)
		local d = rng:NextNumber(9, 17)
		local px, pz = polar(cx, cz, a, d)
		local s = rng:NextNumber(2.5, 5.5)
		S.Part(folder, "Rocha_" .. i, Vector3.new(s, s * 0.8, s * 1.2), groundCF(px, pz) * CFrame.new(0, s * 0.15, 0) * CFrame.Angles(rng:NextNumber(-0.2, 0.2), a, 0), Enum.Material.Rock, Color3.fromRGB(96, 94, 90))
	end
end

local function buildVillage(folder: Folder, site: IslandLayout.Site)
	NativeVillage.Build(folder, Vector3.new(site.x, groundY(site.x, site.z), site.z), IslandLayout.Seed())
end

--------------------------------------------------------------------------------
-- Lampiões de trilha
--------------------------------------------------------------------------------

local function buildTrailLamps(folder: Folder, rng: Random)
	local sites = IslandLayout.Sites()
	local spacing = 60
	local carry = 0
	local count = 0

	for _, seg in IslandLayout.TrailSegments() do
		local delta = seg.b - seg.a
		local len = delta.Magnitude
		if len < 1 then
			continue
		end
		local dir = delta.Unit
		local side = Vector3.new(-dir.Z, 0, dir.X)
		local t = spacing - carry
		while t < len do
			local p = seg.a + dir * t
			local sideSign = if rng:NextNumber() < 0.5 then -1 else 1
			local lp = p + side * (sideSign * (IslandLayout.CONFIG.Trail.HalfWidth + 1.6))

			local lit = false
			for _, site in sites do
				if (lp.X - site.x) ^ 2 + (lp.Z - site.z) ^ 2 < (site.r + 40) ^ 2 then
					lit = true
					break
				end
			end

			S.TrailLamp(folder, groundCF(lp.X, lp.Z, p), lit)
			count += 1
			t += spacing
		end
		carry = (len - (t - spacing)) % spacing
	end

	return count
end

--------------------------------------------------------------------------------
-- API
--------------------------------------------------------------------------------

-- Atualização isolada do mapa salvo. Não use Generate() só para mudar a vila:
-- aquela função também reconstrói todos os outros POIs e seus marcadores.
function PoiGenerator.GenerateVillage(): Folder
	assert(not game:GetService("RunService"):IsRunning(), "Atualize a vila em modo de edição, fora do Play.")
	local ilha = getIlha()
	local pois = ilha:FindFirstChild("POIs")
	assert(pois, "Gere os POIs primeiro: Workspace.Ilha.POIs não existe.")
	local old = pois:FindFirstChild("VilaNativa")
	local layout = ilha:FindFirstChild("Layout")
	local anchor = if layout then layout:FindFirstChild("VilaNativa") else nil
	assert(anchor and anchor:IsA("BasePart"), "Marcador Layout.VilaNativa ausente; não vou adivinhar a posição da vila salva.")
	local center = anchor.Position
	local replacement = Instance.new("Folder")
	replacement.Name = "VilaNativa"
	-- Constrói antes de mexer na antiga. Um erro deixa a cena atual intacta.
	local ok, err = pcall(NativeVillage.Build, replacement, center, IslandLayout.Seed())
	if not ok then
		replacement:Destroy()
		error(err)
	end
	if old then
		local storage = game:GetService("ServerStorage")
		local backups = storage:FindFirstChild("MapEditBackups")
		if not backups then
			backups = Instance.new("Folder")
			backups.Name = "MapEditBackups"
			backups.Parent = storage
		end
		-- Move o original inteiro para backup: inclui alterações manuais e loot.
		-- Nunca apaga o conteúdo anterior, nem toca em Ilha.VilaNativa (rádio).
		local legacyNames = { CabanaNativa = true, Totem = true, Fogueira = true,
			SecadorDePeixe = true, Canoa = true, Pote = true, SpawnPOI = true }
		for _, child in old:GetChildren() do
			if not child:GetAttribute("VilaGerada") and not legacyNames[child.Name] then
				-- Objetos extras pertencem ao projeto: conservam identidade/posição.
				child.Parent = replacement
			end
		end
		old.Name = "VilaNativa_" .. os.date("!%Y%m%d_%H%M%S") .. "_" .. (#backups:GetChildren() + 1)
		old.Parent = backups
	end
	replacement.Parent = pois
	print("[PoiGenerator] Vila ampliada; anterior em ServerStorage.MapEditBackups. Salve o lugar.")
	return replacement
end

function PoiGenerator.Clear()
	local ilha = Workspace:FindFirstChild("Ilha")
	if not ilha then
		return
	end
	for _, name in { "POIs", "Trilhas", "Layout", "VilaNativa", "Clareiras" } do
		local f = ilha:FindFirstChild(name)
		if f then
			f:Destroy()
		end
	end
end

--[[
	Generate()
	Constrói todos os POIs + lampiões + marcadores de layout. Precisa do
	terreno pronto (raycast). Devolve o número de construções.
]]
function PoiGenerator.Generate(): number
	IslandLayout.Plan()
	local sites = IslandLayout.Sites()
	local ilha = getIlha()
	PoiGenerator.Clear()

	local pois = resetFolder(ilha, "POIs")
	local trilhas = resetFolder(ilha, "Trilhas")
	local layout = resetFolder(ilha, "Layout")
	local rng = Random.new(IslandLayout.Seed() + 55)

	-- Marcadores de site.
	for name, site in sites do
		local m = S.Marker(layout, name, CFrame.new(site.x, site.y + 1, site.z), { Poi = name, Raio = site.r, Angulo = site.angle })
		m.Name = name
	end

	local built = 0
	local function poiFolder(name: string): Folder
		local f = Instance.new("Folder")
		f.Name = name
		f.Parent = pois
		return f
	end

	if sites.Acampamento then
		buildCamp(poiFolder("Acampamento"), sites.Acampamento, rng)
		built += 1
		task.wait()
	end
	if sites.CabanasA then
		buildCabinCluster(poiFolder("CabanasA"), sites.CabanasA, rng, 3)
		built += 1
	end
	if sites.CabanasB then
		buildCabinCluster(poiFolder("CabanasB"), sites.CabanasB, rng, 2)
		built += 1
		task.wait()
	end
	if sites.Lago then
		buildLake(poiFolder("Lago"), sites.Lago, rng)
		built += 1
	end
	if sites.Campo then
		buildMeadow(poiFolder("Campo"), sites.Campo, rng)
		built += 1
		task.wait()
	end
	if sites.Torre then
		buildTower(poiFolder("Torre"), sites.Torre)
		built += 1
	end
	if sites.Farol then
		buildLighthouse(poiFolder("Farol"), sites.Farol, rng)
		built += 1
	end
	if sites.VilaNativa then
		buildVillage(poiFolder("VilaNativa"), sites.VilaNativa)
		built += 1
		task.wait()
	end

	local lamps = buildTrailLamps(trilhas, rng)

	print(string.format("[PoiGenerator] %d POIs construídos, %d lampiões de trilha.", built, lamps))
	return built
end

return PoiGenerator
