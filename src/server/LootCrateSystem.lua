--!strict
--[[
	LootCrateSystem
	Caixas de loot espalhadas pela ilha. É AQUI que o atributo SORTE vira
	jogo de verdade.

	SORTE MEXE EM DUAS COISAS (multiplicadores de Modules/StatScaling.lua):
	  1. QUANTOS itens saem  -- LootQuantityMultiplier (0.7x .. 1.8x sobre
	     GameConfig.LootCrates.BaseRolls). A parte fracionária vira CHANCE
	     (2.6 rolagens = 2 garantidas + 60% de uma terceira), então não some
	     no arredondamento.
	  2. QUÃO RAROS  -- LootRarityMultiplier (0.5x .. 2.4x) multiplica o peso
	     de "Media" e "Rara" no sorteio. "Comum" não muda -- o efeito é a
	     cauda rara crescer, não o comum encolher artificialmente.

	  Na prática: Camila (Sorte 96) abre uma caixa e costuma tirar 3-4 itens
	  com boa chance de raro; Kevin (Sorte 12) tira 1-2 quase sempre comuns.

	O QUE É UMA CAIXA
	  Qualquer BasePart com Attribute "CaixaLoot" == true. O sistema:
	    - acha as que já existem no Workspace e observa as novas
	    - anexa um ProximityPrompt "Abrir Caixa"
	    - ao acionar, o CLIENTE só dispara Remotes.OpenCrate:FireServer(caixa);
	      alcance, "já foi aberta?" e o sorteio inteiro são decididos aqui
	  Também SPAWNA as caixas sozinho (Generate) usando os mesmos pontos de
	  terreno que o resto do jogo usa -- não precisa colocar na mão no Studio.

	ITENS POSSÍVEIS: tudo de ItemRegistry.Items que tenha Rarity definida
	(LancaAncestral tem Rarity = nil de propósito -- é 1 por mapa, nas
	Ruínas, e nunca sai de caixa). São TRÊS tipos, e cada um é entregue do
	jeito certo:
	  Category "Tool"            -> ToolFactory.Create -> Backpack
	  Category "MaterialJangada" -> RaftObjective.AddMaterial (estoque pessoal)
	  Category "PecaRadio"       -> RadioObjective.CollectPiece (do time)

	Isso importa muito pro peso da SORTE: os DOIS únicos itens "Rara" do jogo
	são Lona (vela da jangada) e Transmissor (peça do rádio) -- os dois são
	gargalo de objetivo. Tirar um deles de uma caixa muda a partida, e é
	exatamente aí que Camila (Sorte 96) brilha sobre Kevin (Sorte 12).
	Peça de rádio repetida (o time já tem) é re-sorteada, não desperdiçada.

	Uso (uma vez no boot, DEPOIS de CharacterStatsApplier pra a Sorte já
	estar publicada):
		require(script.LootCrateSystem).Init()
]]

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage.Modules.GameConfig)
local ItemRegistry = require(ReplicatedStorage.Modules.ItemRegistry)
local Remotes = require(ReplicatedStorage.Modules.Remotes)
local StatScaling = require(ReplicatedStorage.Modules.StatScaling)
local ToolFactory = require(ReplicatedStorage.Modules.ToolFactory)

local RadioObjective = require(script.Parent.RadioObjective)
local RaftObjective = require(script.Parent.RaftObjective)

local LootCrateSystem = {}

local CFG = GameConfig.LootCrates
local FOLDER_NAME = "CaixasLoot"
local OPENED_ATTR = "CaixaAberta"

local rng = Random.new()
local watched: { [BasePart]: true } = {}

--------------------------------------------------------------------------------
-- Tabela de loot (itens com Rarity, agrupados)
--------------------------------------------------------------------------------

-- rarity -> { itemId }
local pool: { [string]: { string } } = {}
for itemId, def in ItemRegistry.Items do
	local rarity = (def :: any).Rarity
	if type(rarity) == "string" and CFG.RarityWeights[rarity] then
		pool[rarity] = pool[rarity] or {}
		table.insert(pool[rarity], itemId)
	end
end

-- Ordem determinística (a iteração de tabela em Lua não tem ordem garantida,
-- e um sorteio precisa ser reproduzível pra dar pra depurar).
local rarityOrder: { string } = {}
for rarity in CFG.RarityWeights do
	if pool[rarity] and #pool[rarity] > 0 then
		table.insert(rarityOrder, rarity)
	end
end
table.sort(rarityOrder)
for _, list in pool do
	table.sort(list)
end

--[[
	rollItem(player)
	Sorteia UM item. "Comum" mantém o peso base; "Media"/"Rara" são
	multiplicados pela Sorte do personagem.
]]
local function rollItem(player: Player): string?
	local rarityMul = StatScaling.LootRarityMultiplier(player)

	local total = 0
	local weights: { number } = {}
	for index, rarity in rarityOrder do
		local weight = CFG.RarityWeights[rarity]
		if rarity ~= "Comum" then
			weight *= rarityMul
		end
		weights[index] = weight
		total += weight
	end
	if total <= 0 then
		return nil
	end

	local pick = rng:NextNumber() * total
	for index, rarity in rarityOrder do
		pick -= weights[index]
		if pick <= 0 then
			local list = pool[rarity]
			return list[rng:NextInteger(1, #list)]
		end
	end
	return nil
end

--[[
	rollCount(player)
	Quantas rolagens essa caixa dá pra esse jogador. A fração vira chance.
]]
local function rollCount(player: Player): number
	local exact = CFG.BaseRolls * StatScaling.LootQuantityMultiplier(player)
	local whole = math.floor(exact)
	if rng:NextNumber() < (exact - whole) then
		whole += 1
	end
	return math.max(1, whole)
end

--------------------------------------------------------------------------------
-- Entrega (cada Category vai pro lugar certo)
--------------------------------------------------------------------------------

--[[
	grantItem(player, backpack, itemId)
	Entrega UM item. Devolve false quando o item não pôde ser dado (peça de
	rádio que o time já tem, asset do Toolbox que não carregou) -- aí quem
	chamou re-sorteia em vez de perder a rolagem.
]]
local function grantItem(player: Player, backpack: Backpack, itemId: string): boolean
	local def = ItemRegistry.Items[itemId]
	if not def then
		return false
	end
	local category = (def :: any).Category

	if category == "MaterialJangada" then
		-- Estoque pessoal de material (mesmo que tocar na Part no chão daria).
		RaftObjective.AddMaterial(player, itemId, 1)
		return true
	elseif category == "PecaRadio" then
		-- Peça do time. Repetida = false, pra re-sortear.
		return RadioObjective.CollectPiece(itemId, player)
	end

	local tool = ToolFactory.Create(itemId)
	if not tool then
		return false
	end
	tool.Parent = backpack
	return true
end

--------------------------------------------------------------------------------
-- Abrir
--------------------------------------------------------------------------------

local function markOpened(crate: BasePart)
	crate:SetAttribute(OPENED_ATTR, true)
	crate.Color = Color3.fromRGB(70, 62, 52)
	crate.Transparency = 0.35
	local prompt = crate:FindFirstChildOfClass("ProximityPrompt")
	if prompt then
		prompt.Enabled = false
	end
end

local function onOpenRequest(player: Player, crate: unknown)
	if typeof(crate) ~= "Instance" or not (crate :: Instance):IsA("BasePart") then
		return
	end
	local part = crate :: BasePart
	if part:GetAttribute("CaixaLoot") ~= true or part:GetAttribute(OPENED_ATTR) == true then
		return
	end

	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root or not root:IsA("BasePart") then
		return
	end
	if (root.Position - part.Position).Magnitude > CFG.OpenRange then
		return -- longe demais: cliente mentindo ou lag extremo
	end

	local backpack = player:FindFirstChildOfClass("Backpack")
	if not backpack then
		return
	end

	markOpened(part)

	local given: { string } = {}
	for _ = 1, rollCount(player) do
		-- Até 3 tentativas por rolagem: peça de rádio que o time já tem é
		-- re-sorteada em vez de virar rolagem perdida.
		for _ = 1, 3 do
			local itemId = rollItem(player)
			if itemId and grantItem(player, backpack, itemId) then
				table.insert(given, itemId)
				break
			end
		end
	end

	Remotes.OpenCrate:FireClient(player, given)
	print(
		string.format(
			"[LootCrateSystem] %s (Sorte %d) abriu uma caixa -> %s",
			player.Name,
			StatScaling.Of(player, "Sorte") or 0,
			#given > 0 and table.concat(given, ", ") or "nada"
		)
	)
end

--------------------------------------------------------------------------------
-- Prompt nas caixas
--------------------------------------------------------------------------------

local function attachPrompt(crate: BasePart)
	if watched[crate] then
		return
	end
	watched[crate] = true

	local prompt = crate:FindFirstChildOfClass("ProximityPrompt")
	if not prompt then
		prompt = Instance.new("ProximityPrompt")
		prompt.Name = "AbrirCaixa"
		prompt.ActionText = "Abrir Caixa"
		prompt.ObjectText = "Caixa"
		prompt.HoldDuration = 0.6
		prompt.MaxActivationDistance = CFG.OpenRange
		prompt.RequiresLineOfSight = false
		prompt.Parent = crate
	end
	prompt.Enabled = crate:GetAttribute(OPENED_ATTR) ~= true

	prompt.Triggered:Connect(function(player: Player)
		onOpenRequest(player, crate)
	end)

	crate.Destroying:Connect(function()
		watched[crate] = nil
	end)
end

local function scanWorkspace()
	for _, descendant in Workspace:GetDescendants() do
		if descendant:IsA("BasePart") and descendant:GetAttribute("CaixaLoot") == true then
			attachPrompt(descendant)
		end
	end
end

--------------------------------------------------------------------------------
-- Spawn das caixas
--------------------------------------------------------------------------------

local groundParams = RaycastParams.new()
groundParams.FilterType = Enum.RaycastFilterType.Include
groundParams.FilterDescendantsInstances = { Workspace.Terrain }
groundParams.IgnoreWater = true

-- Um ponto de terra firme (areia ou grama) dentro da ilha.
local function findGroundPoint(): Vector3?
	for _ = 1, 40 do
		local x = rng:NextNumber(-260, 260)
		local z = rng:NextNumber(-260, 260)
		local result = Workspace:Raycast(Vector3.new(x, 400, z), Vector3.new(0, -900, 0), groundParams)
		if result then
			local mat = result.Material
			if mat == Enum.Material.Sand or mat == Enum.Material.Grass or mat == Enum.Material.LeafyGrass then
				return result.Position
			end
		end
	end
	return nil
end

local function getFolder(): Folder
	local existing = Workspace:FindFirstChild(FOLDER_NAME)
	if existing and existing:IsA("Folder") then
		return existing
	end
	local folder = Instance.new("Folder")
	folder.Name = FOLDER_NAME
	folder.Parent = Workspace
	return folder
end

--[[
	Generate()
	(Re)espalha as caixas pela ilha. Limpa as anteriores. Dá pra chamar de
	novo na Command Bar pra reposicionar sem reiniciar o servidor.
]]
function LootCrateSystem.Generate()
	local existing = Workspace:FindFirstChild(FOLDER_NAME)
	if existing then
		existing:Destroy()
	end
	local folder = getFolder()

	local placed = 0
	for _ = 1, CFG.Count do
		local anchor = findGroundPoint()
		if not anchor then
			continue
		end
		local x = anchor.X + rng:NextNumber(-CFG.SpreadRadius, CFG.SpreadRadius)
		local z = anchor.Z + rng:NextNumber(-CFG.SpreadRadius, CFG.SpreadRadius)
		local result = Workspace:Raycast(Vector3.new(x, 400, z), Vector3.new(0, -900, 0), groundParams)
		local y = if result then result.Position.Y else anchor.Y

		local crate = Instance.new("Part")
		crate.Name = "CaixaLoot"
		crate.Size = Vector3.new(3, 2.4, 3)
		crate.CFrame = CFrame.new(x, y + 1.2, z) * CFrame.Angles(0, rng:NextNumber(0, math.pi * 2), 0)
		crate.Anchored = true
		crate.CanCollide = true
		crate.Material = Enum.Material.WoodPlanks
		crate.Color = Color3.fromRGB(126, 92, 56)
		crate:SetAttribute("CaixaLoot", true)
		crate.Parent = folder

		attachPrompt(crate)
		placed += 1
	end

	print(string.format("[LootCrateSystem] %d caixa(s) espalhada(s) pela ilha.", placed))
end

--------------------------------------------------------------------------------
-- Init
--------------------------------------------------------------------------------

function LootCrateSystem.Init()
	Remotes.OpenCrate.OnServerEvent:Connect(onOpenRequest)

	scanWorkspace()
	Workspace.DescendantAdded:Connect(function(descendant)
		if descendant:IsA("BasePart") and descendant:GetAttribute("CaixaLoot") == true then
			attachPrompt(descendant)
		end
	end)

	-- Caixas novas (e todas fechadas de novo) a cada partida.
	local RoundManager = require(script.Parent.RoundManager)
	RoundManager.RoundPrepared.Event:Connect(function()
		LootCrateSystem.Generate()
	end)

	if #rarityOrder == 0 then
		warn("[LootCrateSystem] Nenhum item com Rarity em ItemRegistry -- as caixas vão sair vazias.")
	end
end

return LootCrateSystem
