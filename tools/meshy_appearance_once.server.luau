-- Execute na Command Bar, em modo de edição (Rojo conectado). Pode rodar de novo.
--
-- 1) Localiza o modelo Meshy que você importou (Workspace, senão ReplicatedStorage/
--    ServerStorage): as 6 MeshParts Head, Torso, Left/Right Arm, Left/Right Leg.
-- 2) Imprime os ids no formato de model/roblox_upload/asset_ids.json. Cole lá e
--    rode `python3 tools/build_meshy_monster.py`: isso grava a aparência de forma
--    permanente no jogo (ServerStorage.MonsterMeshyVisuals).
-- 3) Cria "R6 Monster (Meshy Preview)": uma CÓPIA do "R6 Monster" vestida com as
--    MeshParts importadas, pelo mesmo código que o jogo usa
--    (ServerScriptService.Server.MonsterMeshyVisuals), e confere que o rig não mudou.
--
-- Não altera nem apaga o modelo importado, o "R6 Monster" ou o StarterCharacter.
-- Só cria a cópia de preview e um template temporário em ServerStorage.
-- Para remover a cópia e o template: REMOVER_PREVIEW = true e rode de novo.

local REMOVER_PREVIEW = false

-- Só se as peças importadas NÃO trouxerem SurfaceAppearance: cole aqui os ids das
-- imagens (Asset Manager). Vazio = não mexe.
local TEXTURAS_DE_RESERVA = { ColorMap = "", NormalMap = "", MetalnessMap = "", RoughnessMap = "" }

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local ServerStorage = game:GetService("ServerStorage")
local Workspace = game:GetService("Workspace")

local PREVIEW_NAME = "R6 Monster (Meshy Preview)"
local TEMP_TEMPLATE_NAME = "MonsterMeshyVisuals_Preview"
local SOURCE_MONSTER = "R6 Monster"
local PART_NAMES = { "Head", "Torso", "Left Arm", "Right Arm", "Left Leg", "Right Leg" }
local MAP_NAMES = { "ColorMap", "NormalMap", "MetalnessMap", "RoughnessMap" }
-- Onde NÃO procurar: os monstros de verdade, templates e o preview.
local EXCLUDED = {
	[SOURCE_MONSTER] = true, [PREVIEW_NAME] = true, MonsterAnimationRig = true,
	["Monster Animation Rig (Authoring)"] = true, ["R6 novo"] = true, GameCharacter = true,
	StarterCharacter = true, MonsterMeshyVisuals = true, [TEMP_TEMPLATE_NAME] = true,
}
-- Proporção (X:Y:Z, com Y = 1) esperada de cada peça exportada pelo build_meshy_monster.py.
-- Serve para avisar se o importador girou/escalou os eixos de forma diferente.
local EXPECTED_SHAPE = {
	Head = Vector3.new(0.844, 1, 0.854), Torso = Vector3.new(1.082, 1, 0.513),
	["Left Arm"] = Vector3.new(0.426, 1, 0.410), ["Right Arm"] = Vector3.new(0.437, 1, 0.411),
	["Left Leg"] = Vector3.new(0.446, 1, 0.367), ["Right Leg"] = Vector3.new(0.449, 1, 0.368),
}

local function cleanup()
	local removed = 0
	for _, holder in { Workspace, ServerStorage } do
		for _, name in { PREVIEW_NAME, TEMP_TEMPLATE_NAME } do
			local item = holder:FindFirstChild(name)
			if item then
				item:Destroy()
				removed += 1
			end
		end
	end
	return removed
end

if REMOVER_PREVIEW then
	print("[Meshy] Removidos: " .. cleanup() .. " (preview/template temporário).")
	return
end

--------------------------------------------------------------------------------
-- 1) Achar o import
--------------------------------------------------------------------------------
local LABELS = {
	leftarm = "Left Arm", rightarm = "Right Arm", leftleg = "Left Leg", rightleg = "Right Leg",
}
local function labelFor(name: string): string?
	local n = string.lower((name:gsub("[^%a]", "")))
	for key, label in LABELS do
		if string.find(n, key, 1, true) then return label end
	end
	if string.find(n, "torso", 1, true) then return "Torso" end
	if string.find(n, "head", 1, true) then return "Head" end
	return nil
end

local function excluded(part: Instance): boolean
	local ancestor = part.Parent
	while ancestor and ancestor ~= game do
		if EXCLUDED[ancestor.Name] then return true end
		ancestor = ancestor.Parent
	end
	return false
end

-- O rótulo vem do nome da MeshPart ou, se for genérico ("Mesh"), do Model/pasta que a contém.
local function labelOfPart(part: Instance): string?
	local node: Instance? = part
	for _ = 1, 3 do
		if not node or node == game or node == Workspace then break end
		local label = labelFor(node.Name)
		if label then return label end
		node = node.Parent
	end
	return nil
end

local found: { [string]: { MeshPart } } = {}
local allMeshParts: { MeshPart } = {}
for _, root in { Workspace, ReplicatedStorage, ServerStorage } do
	for _, item in root:GetDescendants() do
		if item:IsA("MeshPart") and item.MeshId ~= "" and not excluded(item) then
			table.insert(allMeshParts, item)
			local label = labelOfPart(item)
			if label then
				found[label] = found[label] or {}
				table.insert(found[label], item)
			end
		end
	end
end

local missing = {}
for _, name in PART_NAMES do
	if not found[name] then table.insert(missing, name) end
end
if #missing > 0 then
	warn("[Meshy] Não achei as 6 peças com MeshId. Faltam: " .. table.concat(missing, ", "))
	warn("[Meshy] MeshParts com MeshId encontradas (fora dos monstros): " .. #allMeshParts)
	for index, part in allMeshParts do
		if index > 12 then warn("  ..."); break end
		warn(string.format("  %s  Size=(%.2f, %.2f, %.2f)", part:GetFullName(), part.Size.X, part.Size.Y, part.Size.Z))
	end
	warn("[Meshy] Se você importou o FBX ORIGINAL inteiro, ele é uma malha única e NÃO dá para dividir em Head/Torso/"
		.. "braços/pernas dentro do Studio. Importe os 6 .obj de model/roblox_upload/parts/ (Asset Manager > Bulk Import) "
		.. "e rode este script de novo. Nada foi alterado.")
	return
end

local chosen: { [string]: MeshPart } = {}
for _, name in PART_NAMES do
	chosen[name] = found[name][1]
	if #found[name] > 1 then
		warn(string.format("[Meshy] %d candidatos para '%s'; usando %s", #found[name], name, chosen[name]:GetFullName()))
	end
end

--------------------------------------------------------------------------------
-- 2) Ids para o asset_ids.json
--------------------------------------------------------------------------------
local function surfaceMaps(part: MeshPart): { [string]: string }?
	local sa = part:FindFirstChildOfClass("SurfaceAppearance")
	if not sa then return nil end
	local maps = {}
	for _, map in MAP_NAMES do
		local value = (sa :: any)[map]
		if type(value) == "string" and value ~= "" then maps[map] = value end
	end
	return maps
end

local shared: { [string]: string } = {}
for _, map in MAP_NAMES do
	local counts, best, bestCount = {}, "", 0
	for _, name in PART_NAMES do
		local maps = surfaceMaps(chosen[name])
		local value = maps and maps[map]
		if value then
			counts[value] = (counts[value] or 0) + 1
			if counts[value] > bestCount then best, bestCount = value, counts[value] end
		end
	end
	shared[map] = if bestCount > 0 then best else (TEXTURAS_DE_RESERVA :: any)[map]
end

local lines = { "{", '  "meshes": {' }
for index, name in PART_NAMES do
	table.insert(lines, string.format("    %q: %q%s", name, chosen[name].MeshId, if index < #PART_NAMES then "," else ""))
end
table.insert(lines, "  },")
table.insert(lines, '  "textures": {')
for index, map in MAP_NAMES do
	table.insert(lines, string.format("    %q: %q%s", map, shared[map] or "", if index < #MAP_NAMES then "," else ""))
end
local extras = {}
local textureIds, overrides = {}, {}
for _, name in PART_NAMES do
	local part = chosen[name]
	if part.TextureID ~= "" then table.insert(textureIds, string.format("    %q: %q", name, part.TextureID)) end
	local maps = surfaceMaps(part)
	if maps then
		local diff = {}
		for _, map in MAP_NAMES do
			if maps[map] and maps[map] ~= shared[map] then
				table.insert(diff, string.format("%q: %q", map, maps[map]))
			end
		end
		if #diff > 0 then
			table.insert(overrides, string.format("    %q: { %s }", name, table.concat(diff, ", ")))
		end
	end
end
if #textureIds > 0 then
	table.insert(extras, '  "texture_ids": {\n' .. table.concat(textureIds, ",\n") .. "\n  }")
end
if #overrides > 0 then
	table.insert(extras, '  "part_textures": {\n' .. table.concat(overrides, ",\n") .. "\n  }")
end
table.insert(lines, "  }" .. (if #extras > 0 then "," else ""))
for index, block in extras do
	table.insert(lines, block .. (if index < #extras then "," else ""))
end
table.insert(lines, "}")

print("[Meshy] Peças encontradas:")
for _, name in PART_NAMES do
	print(string.format("  %-9s %s  (%s)", name, chosen[name].MeshId, chosen[name]:GetFullName()))
end
local hasAnySurface = false
for _, name in PART_NAMES do
	if surfaceMaps(chosen[name]) then hasAnySurface = true end
end
if not hasAnySurface and (shared.ColorMap or "") == "" then
	warn("[Meshy] As peças importadas NÃO têm SurfaceAppearance. Pegue os ids das 4 imagens no Asset Manager e coloque em "
		.. "\"textures\" abaixo (ou em TEXTURAS_DE_RESERVA no topo deste script para o preview).")
end
print("[Meshy] Cole isto em model/roblox_upload/asset_ids.json e rode: python3 tools/build_meshy_monster.py\n"
	.. table.concat(lines, "\n"))

-- Orientação/escala do import (o encaixe absorve escala uniforme, mas não eixos trocados).
for _, name in PART_NAMES do
	local size = chosen[name].Size
	local shape, want = size / size.Y, EXPECTED_SHAPE[name]
	if math.abs(shape.X - want.X) > 0.25 * want.X or math.abs(shape.Z - want.Z) > 0.25 * want.Z then
		warn(string.format("[Meshy] %s: proporção importada (%.2f : 1 : %.2f) difere da esperada (%.2f : 1 : %.2f). "
			.. "O importador pode ter girado/escalado os eixos; a peça vai aparecer deformada/torta.",
			name, shape.X, shape.Z, want.X, want.Z))
	end
end

--------------------------------------------------------------------------------
-- 3) Preview: cópia do R6 Monster vestida com as peças importadas
--------------------------------------------------------------------------------
local source = Workspace:FindFirstChild(SOURCE_MONSTER)
if not (source and source:IsA("Model") and source:FindFirstChildOfClass("Humanoid")) then
	warn("[Meshy] Workspace." .. SOURCE_MONSTER .. " não existe (Rojo conectado?). Ids impressos acima; preview não criado.")
	return
end

cleanup()
local template = Instance.new("Model")
template.Name = TEMP_TEMPLATE_NAME
for _, name in PART_NAMES do
	local copy = chosen[name]:Clone()
	copy.Name = name
	if not copy:FindFirstChildOfClass("SurfaceAppearance") and (TEXTURAS_DE_RESERVA.ColorMap :: string) ~= "" then
		local sa = Instance.new("SurfaceAppearance")
		for _, map in MAP_NAMES do
			local value = (TEXTURAS_DE_RESERVA :: any)[map]
			if value ~= "" then (sa :: any)[map] = value end
		end
		sa.Parent = copy
	end
	copy.Parent = template
end
template.Parent = ServerStorage

local Visuals = require(ServerScriptService.Server.MonsterMeshyVisuals)
local AssetRegistry = require(ReplicatedStorage.Modules.AssetRegistry)
local config = table.clone(AssetRegistry.Monstro_Modelo.Meshy :: any)
config.TemplateName = TEMP_TEMPLATE_NAME

local preview = source:Clone()
preview.Name = PREVIEW_NAME
preview.Parent = Workspace
preview:PivotTo(source:GetPivot() + Vector3.new(-10, 0, 0))

local before = Visuals.RigSnapshot(preview)
local ok, reason = Visuals.Apply(preview, config)
if not ok then
	warn("[Meshy] Preview NÃO aplicado: " .. tostring(reason))
	return
end

local problems = Visuals.Verify(preview, config)
for _, line in Visuals.DiffSnapshots(before, Visuals.RigSnapshot(preview)) do
	table.insert(problems, "rig alterado -> " .. line)
end

print(string.format("[Meshy] Encaixe por peça (importada -> visual no monstro atual, escala do modelo %.2f).", preview:GetScale()))
print("        Deformação = quanto cada eixo foge de uma escala uniforme (0% = só mudou de tamanho, sem esticar):")
local folder = preview:FindFirstChild(Visuals.FOLDER_NAME)
for _, name in PART_NAMES do
	local visual = folder and folder:FindFirstChild(Visuals.VisualName(name)) :: MeshPart?
	if visual then
		local native = chosen[name].Size
		local rx, ry, rz = visual.Size.X / native.X, visual.Size.Y / native.Y, visual.Size.Z / native.Z
		local uniform = (rx * ry * rz) ^ (1 / 3)
		print(string.format("  %-9s (%.2f, %.2f, %.2f) -> (%.2f, %.2f, %.2f)   deformação x%+.0f%% y%+.0f%% z%+.0f%%",
			name, native.X, native.Y, native.Z, visual.Size.X, visual.Size.Y, visual.Size.Z,
			(rx / uniform - 1) * 100, (ry / uniform - 1) * 100, (rz / uniform - 1) * 100))
	end
end

if #problems == 0 then
	print("[Meshy] VERIFICAÇÃO OK: 6 visuais no lugar, soldados, sem colisão/massa; Humanoid, HumanoidRootPart, "
		.. "6 Motor6D (C0/C1), tamanhos e colisão das partes R6 idênticos aos de antes.")
else
	warn("[Meshy] VERIFICAÇÃO FALHOU:")
	for _, problem in problems do warn("  - " .. problem) end
end
print("[Meshy] Preview em Workspace['" .. PREVIEW_NAME .. "'] (10 studs ao lado do R6 Monster). "
	.. "Para ver as juntas em movimento, use o Animation Editor/Monster Preview nessa cópia ou dê Play.")
