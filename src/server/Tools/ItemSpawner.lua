--!strict
--[[
	ItemSpawner (ferramenta de editor)
	Espalha os itens coletáveis de ItemRegistry.lua pelas zonas já geradas
	da ilha. Rode DEPOIS de IslandGenerator.Generate() e (se quiser
	Antena/Bateria/Transmissor/Corda/Lona nos destroços) PlaneCrashGenerator.Generate().

	AUTO-BOOT: init.server.luau chama Generate() sozinho ao dar Play, por
	último (depois de Ilha + Destroços), SE Workspace.Ilha ainda não existir
	(ver comentário lá). Continua dando pra chamar manualmente também --
	inclusive SpawnSampleNear(), que só faz sentido chamado à mão mesmo.

	USO (Command Bar do Studio, em modo de edição):
		local Spawner = require(game.ServerScriptService.Server.Tools.ItemSpawner)
		Spawner.Generate()       -- ou Spawner.Generate(7) pra outra seed
		Spawner.ClearItems()

	COMO FUNCIONA: pra cada item com Rarity definida em ItemRegistry.Items,
	cria ItemRegistry.RarityCount[Rarity] cópias no total (não por zona).
	Cada cópia sorteia uma das item.Zones, acha um ponto real dessa zona
	(lido dos Models/Parts que IslandGenerator/PlaneCrashGenerator já
	criaram -- "Floresta" pega posição de árvore, "Rochas" de formação,
	"DestrocosMar/Praia/Floresta" de peça de avião, "VilaNativa" de cabana;
	"Praia" não tem pasta própria, então amostra pontos aleatórios e
	confere por raycast se o material é Sand) e um pequeno desvio aleatório
	perto dele. Se uma zona não tiver nenhum ponto disponível (ex: rodou
	sem gerar destroços do avião), aquela tentativa é só pulada -- o resumo
	final mostra quantos de cada item realmente couberam.

	Madeira/Corda/Lona nascem como Parts com Attribute "MaterialJangada" +
	"TipoMaterial" (RaftObjective.lua já sabe reconhecer, nada mudou lá).
	Antena/Bateria/Transmissor nascem com "PecaRadio" + "TipoPeca"
	(RadioObjective.lua idem). Faca/Lança de Bambu/Pedra Afiada/Tocha
	nascem como uma Part com ProximityPrompt "Pegar" que entrega a Tool
	(ToolFactory.lua) no Backpack e se destrói.

	Lança Ancestral NÃO é spawnada aqui (Rarity = nil, MaxPerMap = 1) --
	fica em IslandGenerator.GenerateRuins(), junto da estrutura das Ruínas.

	Agrupa tudo em Workspace/Ilha/Itens.
]]

local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ItemRegistry = require(ReplicatedStorage.Modules.ItemRegistry)
local ToolFactory = require(ReplicatedStorage.Modules.ToolFactory)
local IslandLayout = require(script.Parent.IslandLayout)

local ItemSpawner = {}

local currentSeed = 555

local raycastParams = RaycastParams.new()
raycastParams.FilterType = Enum.RaycastFilterType.Include
raycastParams.FilterDescendantsInstances = { Workspace.Terrain }
raycastParams.IgnoreWater = true

local function probeGround(x: number, z: number): (number?, Enum.Material)
	local result = Workspace:Raycast(Vector3.new(x, 400, z), Vector3.new(0, -900, 0), raycastParams)
	if result then
		return result.Position.Y, result.Material
	end
	return nil, Enum.Material.Air
end

--------------------------------------------------------------------------------
-- Pontos candidatos por zona
--------------------------------------------------------------------------------

local function getIlha(): Folder?
	local found = Workspace:FindFirstChild("Ilha")
	if found and found:IsA("Folder") then
		return found
	end
	return nil
end

local function pointsFromPath(path: { string }): { Vector3 }
	local points: { Vector3 } = {}
	local current: Instance? = getIlha()

	for _, name in path do
		current = current and current:FindFirstChild(name)
	end
	if not current then
		return points
	end

	for _, child in (current :: Instance):GetChildren() do
		if child:IsA("Model") then
			table.insert(points, child:GetPivot().Position)
		elseif child:IsA("BasePart") then
			table.insert(points, child.Position)
		end
	end

	return points
end

local function samplePraiaPoints(rng: Random, count: number): { Vector3 }
	local points: { Vector3 } = {}
	local attempts = 0

	local limit = IslandLayout.CoastRadiusMax()
	while #points < count and attempts < count * 40 do
		attempts += 1
		local x, z = rng:NextNumber(-limit, limit), rng:NextNumber(-limit, limit)
		local y, material = probeGround(x, z)
		if y and material == Enum.Material.Sand then
			table.insert(points, Vector3.new(x, y, z))
		end
	end

	return points
end

-- Zona "Construcoes": todo marcador PontoLoot (Structures.LootPoint) dentro
-- das construções dos POIs -- armário, prateleira, mesa, mezanino etc.
local function constructionPoints(): { Vector3 }
	local points: { Vector3 } = {}
	local ilha = getIlha()
	if not ilha then
		return points
	end
	for _, d in ilha:GetDescendants() do
		if d:IsA("BasePart") and d:GetAttribute("PontoLoot") == true then
			table.insert(points, d.Position)
		end
	end
	return points
end

local ZONE_PATHS: { [string]: { string } } = {
	[ItemRegistry.Zone.DestrocosMar] = { "Destrocos", "Mar" },
	[ItemRegistry.Zone.DestrocosPraia] = { "Destrocos", "Praia" },
	[ItemRegistry.Zone.DestrocosFloresta] = { "Destrocos", "Floresta" },
	[ItemRegistry.Zone.VilaNativa] = { "VilaNativa" },
	[ItemRegistry.Zone.Floresta] = { "Floresta" },
	[ItemRegistry.Zone.Rochas] = { "Rochas" },
}

local praiaCache: { Vector3 }? = nil
local construcoesCache: { Vector3 }? = nil

local function candidatePoints(zone: string, rng: Random): { Vector3 }
	if zone == ItemRegistry.Zone.Praia then
		if not praiaCache then
			praiaCache = samplePraiaPoints(rng, 24)
		end
		return praiaCache :: { Vector3 }
	end
	if zone == ItemRegistry.Zone.Construcoes then
		if not construcoesCache then
			construcoesCache = constructionPoints()
		end
		return construcoesCache :: { Vector3 }
	end

	local path = ZONE_PATHS[zone]
	if not path then
		return {}
	end
	return pointsFromPath(path)
end

--------------------------------------------------------------------------------
-- Criação das Parts
--------------------------------------------------------------------------------

local function newPickupAnchor(name: string, position: Vector3, parent: Instance): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Size = Vector3.new(1.2, 1.2, 1.2)
	part.Position = position
	part.Anchored = true
	part.CanCollide = false
	part.Material = Enum.Material.Neon
	part.Parent = parent
	return part
end

local function spawnMaterialPart(itemId: string, category: string, position: Vector3, parent: Instance)
	local part = newPickupAnchor(itemId, position, parent)
	part.Color = Color3.fromRGB(255, 195, 70)

	if category == "MaterialJangada" then
		part:SetAttribute("MaterialJangada", true)
		part:SetAttribute("TipoMaterial", itemId)
	else
		part:SetAttribute("PecaRadio", true)
		part:SetAttribute("TipoPeca", itemId)
	end
end

local function spawnToolPickup(itemId: string, displayName: string, position: Vector3, parent: Instance)
	local anchor = newPickupAnchor(itemId .. "_Pickup", position, parent)
	anchor.Color = Color3.fromRGB(130, 210, 255)

	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = "Pegar"
	prompt.ObjectText = displayName
	prompt.Parent = anchor

	prompt.Triggered:Connect(function(player: Player)
		local tool = ToolFactory.Create(itemId)
		if not tool then
			return
		end

		local backpack = player:FindFirstChildOfClass("Backpack")
		tool.Parent = backpack or player
		anchor:Destroy()
	end)
end

--------------------------------------------------------------------------------
-- API
--------------------------------------------------------------------------------

function ItemSpawner.SetSeed(seed: number)
	currentSeed = seed
end

--[[
	ClearItems()
	Apaga Workspace.Ilha.Itens.
]]
function ItemSpawner.ClearItems()
	local ilha = getIlha()
	local existing = ilha and ilha:FindFirstChild("Itens")
	if existing then
		existing:Destroy()
	end
end

--[[
	SpawnSampleNear(position?, spacing?)
	DEBUG/preview: cria UMA cópia de cada item (menos os com MaxPerMap, tipo
	a Lança Ancestral -- essa já é única e fica nas Ruínas) num círculo ao
	redor de `position`, ignorando raridade e zona -- é só pra inspecionar
	visualmente como cada item ficou de perto, não é pensado pra ficar no
	mapa de uma partida de verdade (rode ItemSpawner.ClearItems() depois).

	Sem `position`, acha uma praia sozinho (mesma amostragem usada em
	Generate() pra Praia) -- assim dá pra rodar só `Spawner.SpawnSampleNear()`
	e já ver os itens perto de onde os jogadores vão desembarcar.
]]
function ItemSpawner.SpawnSampleNear(position: Vector3?, spacing: number?)
	local ilha = getIlha()
	if not ilha then
		warn("[ItemSpawner] Workspace.Ilha não existe -- rode IslandGenerator.Generate() primeiro.")
		return
	end

	local pos = position
	if not pos then
		local beachPoints = samplePraiaPoints(Random.new(), 1)
		pos = beachPoints[1]
		if not pos then
			warn("[ItemSpawner] Não achei praia pra colocar a amostra -- passe uma posição manualmente.")
			return
		end
	end
	local anchor = pos :: Vector3

	local itens = ilha:FindFirstChild("Itens")
	if not itens then
		itens = Instance.new("Folder")
		itens.Name = "Itens"
		itens.Parent = ilha
	end

	local ids = {}
	for itemId, def in ItemRegistry.Items do
		if not def.MaxPerMap then
			table.insert(ids, itemId)
		end
	end
	table.sort(ids)

	local gap = spacing or 5
	for i, itemId in ids do
		local def = ItemRegistry.Items[itemId]
		local ring = (i - 1) // 8
		local slotInRing = (i - 1) % 8
		local angle = slotInRing / 8 * (2 * math.pi)
		local radius = gap * (ring + 1)
		local x = anchor.X + math.cos(angle) * radius
		local z = anchor.Z + math.sin(angle) * radius
		local groundY = probeGround(x, z)
		local placePosition = Vector3.new(x, (groundY or anchor.Y) + 1, z)

		if def.Category == "Tool" then
			spawnToolPickup(itemId, def.DisplayName, placePosition, itens :: Folder)
		else
			spawnMaterialPart(itemId, def.Category, placePosition, itens :: Folder)
		end
	end

	print(string.format("[ItemSpawner] Amostra de %d itens colocada perto de (%.0f, %.0f, %.0f).", #ids, anchor.X, anchor.Y, anchor.Z))
end

--[[
	Generate(seed?)
	Espalha todos os itens com Rarity definida. Imprime quantos de cada
	item couberam (pode ser menos que RarityCount se as zonas não tiverem
	pontos suficientes -- ex: sem destroços de avião gerados ainda).
]]
function ItemSpawner.Generate(seed: number?)
	if seed then
		ItemSpawner.SetSeed(seed)
	end

	local ilha = getIlha()
	if not ilha then
		warn("[ItemSpawner] Workspace.Ilha não existe -- rode IslandGenerator.Generate() primeiro.")
		return
	end

	ItemSpawner.ClearItems()
	praiaCache = nil
	construcoesCache = nil

	local itens = Instance.new("Folder")
	itens.Name = "Itens"
	itens.Parent = ilha

	local rng = Random.new(currentSeed)
	local counts: { [string]: number } = {}

	for itemId, def in ItemRegistry.Items do
		if def.Rarity then
			local total = ItemRegistry.RarityCount[def.Rarity] or 0
			local placed = 0

			for _ = 1, total do
				if #def.Zones == 0 then
					break
				end

				local zone = def.Zones[rng:NextInteger(1, #def.Zones)]
				local candidates = candidatePoints(zone, rng)

				if #candidates > 0 then
					local anchorPoint = candidates[rng:NextInteger(1, #candidates)]
					local position: Vector3
					if zone == ItemRegistry.Zone.Construcoes then
						-- Dentro da construção: fica no ponto marcado, sem raycast
						-- (o chão ali é piso de Part, não Terrain).
						position = anchorPoint + Vector3.new(rng:NextNumber(-0.6, 0.6), 0, rng:NextNumber(-0.6, 0.6))
					else
						local x = anchorPoint.X + rng:NextNumber(-4, 4)
						local z = anchorPoint.Z + rng:NextNumber(-4, 4)
						local groundY = probeGround(x, z)
						position = Vector3.new(x, (groundY or anchorPoint.Y) + 1, z)
					end

					if def.Category == "Tool" then
						spawnToolPickup(itemId, def.DisplayName, position, itens)
					else
						spawnMaterialPart(itemId, def.Category, position, itens)
					end

					placed += 1
				end
			end

			counts[itemId] = placed
		end
	end

	local summaryParts = {}
	for itemId, n in counts do
		table.insert(summaryParts, string.format("%s=%d", itemId, n))
	end
	table.sort(summaryParts)

	print("[ItemSpawner] Itens espalhados -- " .. table.concat(summaryParts, ", "))
end

return ItemSpawner
