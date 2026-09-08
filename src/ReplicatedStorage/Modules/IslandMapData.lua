--!strict
--[[
	IslandMapData
	Formato + matemática do MAPA DA ILHA (visão de cima). Compartilhado:
	  server/IslandMap.lua      -> gera e publica
	  Modules/MonsterMapUI.lua  -> lê e desenha

	O mapa NÃO é estético: cada célula vem de IslandLayout (a MESMA matemática
	que escreveu o terreno), então a proporção é 1:1 com o mundo. Clicar em
	(u, v) no mapa vira um (x, z) real do mundo por MapToWorld() -- e é isso
	que o servidor valida e usa como destino do teleporte.

	COMO O MAPA É EMPACOTADO
	  1. O servidor amostra uma grade Resolution x Resolution cobrindo
	     [-MapHalf, +MapHalf] em X e Z.
	  2. Cada célula vira um índice de paleta = tipo de terreno + nível de
	     sombreamento (relevo). Poucos índices -> dá pra compactar muito.
	  3. A grade é fundida em RETÂNGULOS (greedy 2D). Um mapa de 100x100 vira
	     ~800-1500 retângulos em vez de 10.000 células -> o cliente cria um
	     Frame por retângulo, não por célula.
	  4. Tudo isso + POIs + trilhas viram um JSON num StringValue em
	     ReplicatedStorage.

	EIXOS: mapa visto de cima, olhando pra baixo.
	  u (0..1) da esquerda pra direita  -> mundo +X
	  v (0..1) de cima pra baixo        -> mundo +Z
	  Ou seja: NORTE (topo do mapa) = -Z.
]]

local IslandMapData = {}

IslandMapData.Version = 3
IslandMapData.ValueName = "IslandMapData"
IslandMapData.Resolution = 100 -- células por lado (a grade é quadrada)

--------------------------------------------------------------------------------
-- Paleta: tipo de terreno x nível de sombreamento (relevo)
--------------------------------------------------------------------------------

IslandMapData.ShadeLevels = 7
IslandMapData.ShadeMin = 0.68
IslandMapData.ShadeMax = 1.26

-- Ordem IMPORTA: o índice do tipo é a posição nesta lista.
IslandMapData.TerrainNames = {
	"DeepSea",
	"Sea",
	"Shallow",
	"Beach",
	"Grass",
	"Forest",
	"Ground",
	"Rock",
	"Peak",
	"Lake",
}

local TERRAIN_COLORS: { [string]: Color3 } = {
	DeepSea = Color3.fromRGB(8, 20, 38),
	Sea = Color3.fromRGB(14, 38, 64),
	Shallow = Color3.fromRGB(28, 68, 96),
	Beach = Color3.fromRGB(190, 172, 126),
	Grass = Color3.fromRGB(70, 98, 55),
	Forest = Color3.fromRGB(36, 60, 35),
	Ground = Color3.fromRGB(88, 72, 52),
	Rock = Color3.fromRGB(96, 93, 90),
	Peak = Color3.fromRGB(140, 137, 133),
	Lake = Color3.fromRGB(26, 64, 78),
}
IslandMapData.TerrainColors = TERRAIN_COLORS

IslandMapData.TerrainIndex = (function()
	local map: { [string]: number } = {}
	for i, name in IslandMapData.TerrainNames do
		map[name] = i
	end
	return map
end)()

-- Terrenos onde NÃO dá pra teleportar (o servidor rejeita de qualquer jeito;
-- isto é só pra o cursor do mapa ficar vermelho antes de clicar).
local WATER_TERRAIN: { [number]: boolean } = {
	[IslandMapData.TerrainIndex.DeepSea] = true,
	[IslandMapData.TerrainIndex.Sea] = true,
	[IslandMapData.TerrainIndex.Shallow] = true,
	[IslandMapData.TerrainIndex.Lake] = true,
}
IslandMapData.WaterTerrain = WATER_TERRAIN

--[[
	PaletteIndex(terrainIndex, shadeLevel)
	shadeLevel: 1..ShadeLevels. Devolve o índice usado nos retângulos.
]]
function IslandMapData.PaletteIndex(terrainIndex: number, shadeLevel: number): number
	return (terrainIndex - 1) * IslandMapData.ShadeLevels + shadeLevel
end

function IslandMapData.TerrainOf(paletteIndex: number): number
	return ((paletteIndex - 1) // IslandMapData.ShadeLevels) + 1
end

--[[
	BuildPalette()
	Lista de Color3 (índice = PaletteIndex). Server e client geram a MESMA
	paleta, então ela não precisa ir no payload.
]]
function IslandMapData.BuildPalette(): { Color3 }
	local palette: { Color3 } = {}
	local levels = IslandMapData.ShadeLevels
	for t, name in IslandMapData.TerrainNames do
		local base = IslandMapData.TerrainColors[name]
		for level = 1, levels do
			local f = if levels > 1 then (level - 1) / (levels - 1) else 0.5
			local mul = IslandMapData.ShadeMin + (IslandMapData.ShadeMax - IslandMapData.ShadeMin) * f
			palette[IslandMapData.PaletteIndex(t, level)] = Color3.new(
				math.clamp(base.R * mul, 0, 1),
				math.clamp(base.G * mul, 0, 1),
				math.clamp(base.B * mul, 0, 1)
			)
		end
	end
	return palette
end

--------------------------------------------------------------------------------
-- Coordenadas: mundo <-> mapa (é ISTO que faz o clique ser exato)
--------------------------------------------------------------------------------

--[[
	WorldToMap(x, z, mapHalf) -> u, v  (0..1, fora dos limites sai fora de 0..1)
]]
function IslandMapData.WorldToMap(x: number, z: number, mapHalf: number): (number, number)
	return (x + mapHalf) / (mapHalf * 2), (z + mapHalf) / (mapHalf * 2)
end

--[[
	MapToWorld(u, v, mapHalf) -> x, z
]]
function IslandMapData.MapToWorld(u: number, v: number, mapHalf: number): (number, number)
	return u * mapHalf * 2 - mapHalf, v * mapHalf * 2 - mapHalf
end

-- Centro da célula (i, j), 0-indexado, em coordenadas de mundo.
function IslandMapData.CellCenter(i: number, j: number, mapHalf: number, resolution: number): (number, number)
	local cell = (mapHalf * 2) / resolution
	return -mapHalf + (i + 0.5) * cell, -mapHalf + (j + 0.5) * cell
end

--------------------------------------------------------------------------------
-- Retângulos: fusão (server) e codificação
--------------------------------------------------------------------------------

export type Rect = { x: number, y: number, w: number, h: number, c: number }

--[[
	MergeRects(grid, resolution)
	grid[j][i] = índice de paleta (1-indexado, j = linha/Z, i = coluna/X).
	Funde células iguais em retângulos (greedy: cresce em largura, depois em
	altura). Roda no servidor, uma vez.
]]
function IslandMapData.MergeRects(grid: { { number } }, resolution: number): { Rect }
	local used: { { boolean } } = {}
	for j = 1, resolution do
		used[j] = table.create(resolution, false)
	end

	local rects: { Rect } = {}
	for j = 1, resolution do
		local row = grid[j]
		for i = 1, resolution do
			if used[j][i] then
				continue
			end
			local color = row[i]

			-- cresce pra direita
			local w = 1
			while i + w <= resolution and not used[j][i + w] and row[i + w] == color do
				w += 1
			end

			-- cresce pra baixo (a linha inteira precisa bater)
			local h = 1
			while j + h <= resolution do
				local ok = true
				local below = grid[j + h]
				local usedBelow = used[j + h]
				for k = i, i + w - 1 do
					if usedBelow[k] or below[k] ~= color then
						ok = false
						break
					end
				end
				if not ok then
					break
				end
				h += 1
			end

			for jj = j, j + h - 1 do
				local u = used[jj]
				for ii = i, i + w - 1 do
					u[ii] = true
				end
			end

			table.insert(rects, { x = i - 1, y = j - 1, w = w, h = h, c = color })
		end
	end

	return rects
end

--[[
	EncodeRects / DecodeRects
	"x,y,w,h,c;x,y,w,h,c;..." -- compacto e fácil de ler no Output se precisar
	depurar. Nada de JSON por retângulo (seriam centenas de KB).
]]
function IslandMapData.EncodeRects(rects: { Rect }): string
	local parts = table.create(#rects)
	for index, r in rects do
		parts[index] = string.format("%d,%d,%d,%d,%d", r.x, r.y, r.w, r.h, r.c)
	end
	return table.concat(parts, ";")
end

function IslandMapData.DecodeRects(encoded: string): { Rect }
	local rects: { Rect } = {}
	if encoded == "" then
		return rects
	end
	for chunk in string.gmatch(encoded, "[^;]+") do
		local x, y, w, h, c = string.match(chunk, "^(%-?%d+),(%-?%d+),(%d+),(%d+),(%d+)$")
		if x then
			table.insert(rects, {
				x = tonumber(x) :: number,
				y = tonumber(y) :: number,
				w = tonumber(w) :: number,
				h = tonumber(h) :: number,
				c = tonumber(c) :: number,
			})
		end
	end
	return rects
end

return IslandMapData
