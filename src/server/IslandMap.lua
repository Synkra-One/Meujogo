--!strict
--[[
	IslandMap
	Gera o MAPA DA ILHA (visão de cima) a partir de Tools/IslandLayout -- a
	MESMA matemática que escreveu o terreno -- e publica pros clientes num
	StringValue em ReplicatedStorage.

	Por isso o mapa é REAL, não decorativo: a célula (i, j) do mapa
	corresponde exatamente a um (x, z) do mundo (ver IslandMapData.CellCenter),
	então clicar no mapa vira um destino de teleporte exato.

	O QUE VAI NO PAYLOAD
	  resolution, mapHalf, seaLevel
	  rects   -- a grade fundida em retângulos (IslandMapData)
	  pois    -- { nome, x, z, raio } de cada ponto de interesse (Layout.Sites)
	  trails  -- segmentos das trilhas, pra desenhar por cima (na grade eles
	             sumiriam: uma trilha de ~8 studs num mapa de ~1760 dá meia célula)
	  cave    -- boca da caverna do Monstro

	RELEVO: cada célula ganha um nível de sombreamento calculado por
	hillshading (inclinação contra uma luz vinda do noroeste), o que dá o
	aspecto de mapa topográfico em vez de manchas chapadas.

	Uso (uma vez no boot; é barato -- só matemática, sem raycast):
		require(script.IslandMap).Init()
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HttpService = game:GetService("HttpService")

local IslandMapData = require(ReplicatedStorage.Modules.IslandMapData)
local IslandLayout = require(script.Parent.Tools.IslandLayout)

local IslandMap = {}

local LC = IslandLayout.CONFIG
local TI = IslandMapData.TerrainIndex

-- Quanto do mundo o mapa cobre. Um pouco além da costa máxima pra a ilha não
-- encostar na borda do quadro.
local function mapHalf(): number
	return math.floor(LC.CoastRadiusMax * 1.12)
end

--------------------------------------------------------------------------------
-- Classificação de terreno
--------------------------------------------------------------------------------

-- Faixas do mar por DISTÂNCIA DA COSTA, não por profundidade. A batimetria da
-- ilha é comprimida de propósito (IslandLayout: o fundo já começa
-- SeaFloorDrop abaixo da linha d'água e trava em MinY+2), então ela vai de
-- "raso" a "fundo" em ~1 stud -- menos de uma célula do mapa. Usando a
-- distância da costa, o mar ganha um degradê largo e legível em volta da ilha.
local SHALLOW_BAND = 30 -- studs mar adentro
local MID_BAND = 120
local FADE_BAND = 260 -- em quantos studs o tom do mar termina de escurecer
local COAST_DARKEN = 0.12 -- quanto a terra colada na água escurece (linha de costa)

local function terrainAt(x: number, z: number, height: number, waterLevel: number): number
	-- Água primeiro: distância da costa decide o tom.
	if height < waterLevel - 0.05 then
		if waterLevel > LC.SeaLevel + 0.5 then
			return TI.Lake -- lago interno (nível próprio, acima do mar)
		end
		local _, _, inland = IslandLayout.IslandInfo(x, z)
		local offshore = -inland
		if offshore < SHALLOW_BAND then
			return TI.Shallow
		elseif offshore < MID_BAND then
			return TI.Sea
		end
		return TI.DeepSea
	end

	local material = IslandLayout.Material(x, z)
	if material == Enum.Material.Sand then
		return TI.Beach
	elseif material == Enum.Material.Rock then
		-- pico da montanha fica mais claro
		local mountain = IslandLayout.MountainContribution(x, z)
		return if mountain > LC.Mountain.Peak * 0.62 then TI.Peak else TI.Rock
	elseif material == Enum.Material.Ground or material == Enum.Material.Mud then
		return TI.Ground
	elseif material == Enum.Material.LeafyGrass then
		return TI.Forest
	end
	return TI.Grass
end

--------------------------------------------------------------------------------
-- Amostragem + hillshading
--------------------------------------------------------------------------------

-- true se alguma das 4 células vizinhas for água -- usado pra desenhar uma
-- linha de costa fina em vez de deixar o limite cru entre um retângulo de
-- praia e um de mar (que lê como "pixelado").
local function isCoastCell(types: { { number } }, i: number, j: number, resolution: number): boolean
	if i > 1 and IslandMapData.WaterTerrain[types[j][i - 1]] then
		return true
	end
	if i < resolution and IslandMapData.WaterTerrain[types[j][i + 1]] then
		return true
	end
	if j > 1 and IslandMapData.WaterTerrain[types[j - 1][i]] then
		return true
	end
	if j < resolution and IslandMapData.WaterTerrain[types[j + 1][i]] then
		return true
	end
	return false
end

local function buildGrid(resolution: number, half: number): { { number } }
	local cell = (half * 2) / resolution
	local levels = IslandMapData.ShadeLevels

	-- Passo 1: alturas e tipos (uma passada).
	local heights: { { number } } = {}
	local types: { { number } } = {}
	for j = 1, resolution do
		local hRow = table.create(resolution, 0)
		local tRow = table.create(resolution, 1)
		local z = -half + (j - 0.5) * cell
		for i = 1, resolution do
			local x = -half + (i - 0.5) * cell
			local h = IslandLayout.Height(x, z)
			local water = IslandLayout.WaterLevel(x, z)
			hRow[i] = h
			tRow[i] = terrainAt(x, z, h, water)
		end
		heights[j] = hRow
		types[j] = tRow
		if j % 12 == 0 then
			task.wait()
		end
	end

	-- Passo 2: hillshading. Luz vindo do noroeste (-X, -Z), bem inclinada.
	-- shade = quanto a normal da superfície aponta pra luz.
	local grid: { { number } } = {}
	local lightX, lightZ = -0.60, -0.60
	local lightY = 0.53
	for j = 1, resolution do
		local row = table.create(resolution, 1)
		for i = 1, resolution do
			local terrain = types[j][i]
			local shade: number

			if IslandMapData.WaterTerrain[terrain] then
				-- Água: sem relevo, mas escurece conforme se afasta da costa --
				-- é isso que faz a ilha "flutuar" no mapa em vez de ter uma
				-- borda dura. Um fio de ruído tira o chapado.
				local x = -half + (i - 0.5) * cell
				local z = -half + (j - 0.5) * cell
				local _, _, inland = IslandLayout.IslandInfo(x, z)
				local t = math.clamp(-inland / FADE_BAND, 0, 1)
				shade = math.clamp((1 - t) * 0.85 + math.noise(i * 0.09, j * 0.09, 3.1) * 0.2, 0, 1)
			else
				local hL = heights[j][math.max(i - 1, 1)]
				local hR = heights[j][math.min(i + 1, resolution)]
				local hU = heights[math.max(j - 1, 1)][i]
				local hD = heights[math.min(j + 1, resolution)][i]
				-- gradiente -> normal aproximada
				local dx = (hL - hR) / (2 * cell)
				local dz = (hU - hD) / (2 * cell)
				local len = math.sqrt(dx * dx + dz * dz + 1)
				local nx, ny, nz = dx / len, 1 / len, dz / len
				local dot = nx * lightX + ny * lightY + nz * lightZ
				-- realce mais suave que antes (1.55 -> 1.25): junto com os 16
				-- níveis de sombra (era 7), o relevo vira gradiente contínuo
				-- em vez de degraus grandes.
				shade = math.clamp(0.5 + dot * 1.25, 0, 1)

				-- Linha de costa: terra colada na água escurece um pouco mais,
				-- dá uma borda fina e contínua em vez do limite cru entre um
				-- retângulo de praia e um de mar.
				if isCoastCell(types, i, j, resolution) then
					shade = math.clamp(shade - COAST_DARKEN, 0, 1)
				end
			end

			local level = math.clamp(math.floor(shade * levels) + 1, 1, levels)
			row[i] = IslandMapData.PaletteIndex(terrain, level)
		end
		grid[j] = row
		if j % 16 == 0 then
			task.wait()
		end
	end

	return grid
end

--------------------------------------------------------------------------------
-- POIs e trilhas
--------------------------------------------------------------------------------

-- Nome bonito pra mostrar no mapa (a chave do Layout é o id interno).
local POI_LABELS: { [string]: string } = {
	Acampamento = "Acampamento",
	CabanasA = "Cabanas Norte",
	CabanasB = "Cabanas Sul",
	Lago = "Lago",
	Campo = "Campo Aberto",
	Torre = "Torre de Vigia",
	Farol = "Farol",
	VilaNativa = "Vila Nativa",
	Ruinas = "Ruínas",
	Radio = "Estação de Rádio",
}

local function collectPois(): { { [string]: any } }
	local list = {}
	for name, site in IslandLayout.Sites() do
		table.insert(list, {
			n = POI_LABELS[name] or name,
			id = name,
			x = math.floor(site.x * 10) / 10,
			z = math.floor(site.z * 10) / 10,
			r = site.r,
		})
	end
	table.sort(list, function(a, b)
		return a.id < b.id
	end)
	return list
end

local function collectTrails(): { { number } }
	local list = {}
	for _, seg in IslandLayout.TrailSegments() do
		table.insert(list, {
			math.floor(seg.a.X * 10) / 10,
			math.floor(seg.a.Z * 10) / 10,
			math.floor(seg.b.X * 10) / 10,
			math.floor(seg.b.Z * 10) / 10,
		})
	end
	return list
end

--------------------------------------------------------------------------------
-- Publicação
--------------------------------------------------------------------------------

local function publish(payload: string)
	local existing = ReplicatedStorage:FindFirstChild(IslandMapData.ValueName)
	if existing then
		existing:Destroy()
	end
	local value = Instance.new("StringValue")
	value.Name = IslandMapData.ValueName
	value.Value = payload
	value.Parent = ReplicatedStorage
end

--[[
	Generate()
	(Re)gera e publica o mapa. Dá pra chamar de novo na Command Bar depois de
	regerar a ilha com outra seed.
]]
function IslandMap.Generate(): number
	IslandLayout.Plan()

	local t0 = os.clock()
	local resolution = IslandMapData.Resolution
	local half = mapHalf()

	local grid = buildGrid(resolution, half)
	local rects = IslandMapData.MergeRects(grid, resolution)

	local payload = HttpService:JSONEncode({
		version = IslandMapData.Version,
		resolution = resolution,
		mapHalf = half,
		seaLevel = LC.SeaLevel,
		rects = IslandMapData.EncodeRects(rects),
		pois = collectPois(),
		trails = collectTrails(),
		cave = { select(1, IslandLayout.CaveEntrance()), select(2, IslandLayout.CaveEntrance()) },
	})

	publish(payload)

	print(string.format(
		"[IslandMap] Mapa pronto em %.1fs -- %dx%d células -> %d retângulos, alcance +-%d studs, %d POIs, payload %.1f KB.",
		os.clock() - t0, resolution, resolution, #rects, half, #collectPois(), #payload / 1024
	))
	return #rects
end

function IslandMap.Init()
	task.spawn(function()
		local ok, err = pcall(IslandMap.Generate)
		if not ok then
			warn("[IslandMap] Falha ao gerar o mapa: " .. tostring(err))
		end
	end)
end

return IslandMap
