--!strict
--[[
	ItemDiscovery
	Quando um jogador passa perto de um item do mundo, esse item fica marcado
	PARA SEMPRE no mapa dele (Modules/IslandMapUI, via Remotes.MapDiscovery).
	Cada jogador tem seu próprio progresso -- descobrir não avisa ninguém mais,
	e a marca nunca é desfeita (nem ao morrer/respawnar/trocar de rodada: os
	itens do mapa não são resorteados a cada partida, então "esquecer" ao
	reiniciar a rodada seria o jogador perder uma informação que continua
	verdadeira). Só sai ao deixar o servidor.

	POR QUE NO SERVIDOR, NÃO NO CLIENTE: com StreamingEnabled o cliente nem
	sempre tem os Parts do item carregados/perto o bastante pra detectar
	sozinho; o servidor sempre enxerga tudo, então é ele quem varre a
	distância (GameConfig.MapDiscovery.Radius, sem exigir linha de visão).

	O QUE CONTA COMO "ITEM DO MUNDO" hoje:
	  - Pickup de Tool (Faca/Lança/Pedra/Tocha/Lanterna/Chocolate/Bandagem):
	    Part "<itemId>_Pickup" (Tools/ItemSpawner.lua).
	  - Peça de rádio: Part com Attribute PecaRadio+TipoPeca.
	  - Caixa de munição: Part com Attribute MunicaoPickup==true (AmmoSystem.lua).
	  - Caixa de loot: Part com Attribute CaixaLoot==true (LootCrateSystem.lua).
	  - Arma de fogo ou Tool largada no mundo: a própria Tool, reconhecida
	    pelo nome (GameConfig.Firearms.Allowed) ou pelos MESMOS Attributes que
	    o resto do jogo já usa (ItemIcons.ItemIdFromTool) -- cobre WeaponSpawner,
	    DropItemSystem.PlaceInWorld/dropTool e a Lança Ancestral das Ruínas.

	Segue o mesmo padrão de varredura de RadioObjective/SabotageSystem/
	MonsterLightWeakness: GetDescendants() uma vez + Workspace.DescendantAdded
	depois, com SafeAttribute.Get (instâncias do Toolbox podem lançar em
	GetAttribute direto -- ver Modules/SafeAttribute.lua).

	Uso (uma vez no boot do servidor):
		require(script.ItemDiscovery).Init()
]]

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage.Modules.GameConfig)
local Remotes = require(ReplicatedStorage.Modules.Remotes)
local ItemRegistry = require(ReplicatedStorage.Modules.ItemRegistry)
local ItemIcons = require(ReplicatedStorage.Modules.ItemIcons)
local MapMarkers = require(ReplicatedStorage.Modules.MapMarkers)
local SafeAttribute = require(ReplicatedStorage.Modules.SafeAttribute)

local ItemDiscovery = {}

--[[
	ItemDiscovered:Fire(player, entry)
	Gancho SÓ DE SERVIDOR pro mesmo evento que o MapDiscovery manda pro
	cliente -- `entry` é a mesma tabela, com os mesmos campos (key, x, z,
	itemId, category, label).

	Existe porque FireClient não volta pro servidor: um sistema do servidor
	que precise saber que alguém achou um item (hoje: MatchRewardService, pro
	XP de "item importante encontrado") não teria como escutar o remote.
	A descoberta continua sendo por jogador -- cada um só recebe/dispara a
	dele, e o mesmo item nunca é redescoberto pelo mesmo jogador.
]]
ItemDiscovery.ItemDiscovered = Instance.new("BindableEvent")

local CFG = GameConfig.MapDiscovery

type Info = { itemId: string?, category: string, label: string? }
type Discoverable = { instance: Instance, getPosition: () -> Vector3?, info: Info }

local discoverables: { [Instance]: Discoverable } = {}
local discoveredBy: { [Player]: { [Instance]: boolean } } = {}
local keyOf: { [Instance]: string } = {}
local nextKey = 0
local initialized = false
local loopToken = 0

--------------------------------------------------------------------------------
-- Identidade estável por instância (chave enviada ao cliente)
--------------------------------------------------------------------------------

local function keyFor(instance: Instance): string
	local existing = keyOf[instance]
	if existing then
		return existing
	end
	nextKey += 1
	local key = "i" .. nextKey
	keyOf[instance] = key
	return key
end

--------------------------------------------------------------------------------
-- Classificação
--------------------------------------------------------------------------------

local function labelFor(itemId: string?, fallback: string?): string?
	if itemId then
		local def = ItemRegistry.Items[itemId]
		if def then
			return def.DisplayName
		end
	end
	return fallback
end

local function classifyPart(part: BasePart): Info?
	-- Pickup de Tool: Part "<itemId>_Pickup" (ver Tools/ItemSpawner.lua).
	local pickupId = string.match(part.Name, "^(.+)_Pickup$")
	if pickupId and ItemRegistry.Items[pickupId] then
		return { itemId = pickupId, category = MapMarkers.CategoryOf(nil, pickupId), label = labelFor(pickupId) }
	end

	if SafeAttribute.Get(part, "PecaRadio") == true then
		local tipo = SafeAttribute.Get(part, "TipoPeca")
		if type(tipo) == "string" then
			return { itemId = tipo, category = MapMarkers.CategoryOf(nil, tipo), label = labelFor(tipo, tipo) }
		end
	end

	if SafeAttribute.Get(part, "CaixaLoot") == true then
		return { itemId = nil, category = MapMarkers.Category.Crate, label = "Caixa de Loot" }
	end

	if SafeAttribute.Get(part, "MunicaoPickup") == true then
		local tipo = SafeAttribute.Get(part, "TipoMunicao")
		local label = if type(tipo) == "string" then string.format("Munição (%s)", tipo) else "Munição"
		return { itemId = nil, category = MapMarkers.Category.Firearm, label = label }
	end

	return nil
end

local function classifyTool(tool: Tool): Info?
	if table.find(GameConfig.Firearms.Allowed, tool.Name) then
		return { itemId = nil, category = MapMarkers.CategoryOf(tool.Name, nil), label = tool.Name }
	end

	-- Mesma resolução de Attributes que ItemIcons já usa pra achar o ícone da
	-- hotbar -- cobre Faca/Lança/Pedra/Tocha/Lanterna/Chocolate/Bandagem/
	-- Lança Ancestral sem duplicar a lista de Attributes em outro lugar.
	local itemId = ItemIcons.ItemIdFromTool(tool)
	if itemId then
		return { itemId = itemId, category = MapMarkers.CategoryOf(nil, itemId), label = labelFor(itemId, tool.Name) }
	end

	return nil
end

local function classify(instance: Instance): Info?
	if instance:IsA("BasePart") then
		return classifyPart(instance)
	elseif instance:IsA("Tool") then
		return classifyTool(instance)
	end
	return nil
end

--------------------------------------------------------------------------------
-- Posição (só importa enquanto a instância estiver no Workspace de verdade --
-- uma Tool guardada no Backpack não é "um item no mundo").
--------------------------------------------------------------------------------

local function positionOf(instance: Instance): Vector3?
	if instance:IsA("BasePart") then
		return instance.Position
	elseif instance:IsA("Tool") then
		local handle = instance:FindFirstChild("Handle")
		if handle and handle:IsA("BasePart") then
			return handle.Position
		end
	end
	return nil
end

--------------------------------------------------------------------------------
-- Registro
--------------------------------------------------------------------------------

local function register(instance: Instance)
	if discoverables[instance] then
		return
	end
	local info = classify(instance)
	if not info then
		return
	end
	discoverables[instance] = { instance = instance, getPosition = function() return positionOf(instance) end, info = info }
	instance.Destroying:Connect(function()
		discoverables[instance] = nil
	end)
end

--------------------------------------------------------------------------------
-- Varredura de proximidade
--------------------------------------------------------------------------------

local function livingRoot(player: Player): BasePart?
	if player:GetAttribute("InRound") ~= true then
		return nil
	end
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then
		return nil
	end
	local root = character:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		return root
	end
	return nil
end

local function scanOnce()
	for _, player in Players:GetPlayers() do
		local root = livingRoot(player)
		if not root then
			continue
		end
		local seen = discoveredBy[player]
		if not seen then
			seen = {}
			discoveredBy[player] = seen
		end
		local playerPos = root.Position
		for instance, entry in discoverables do
			-- Item numa gaveta fechada (DrawerSystem) ninguém está vendo.
			if seen[instance] or not instance:IsDescendantOf(Workspace) or SafeAttribute.Get(instance, "OcultoNaGaveta") == true then
				continue
			end
			local pos = entry.getPosition()
			if not pos then
				continue
			end
			if (pos - playerPos).Magnitude <= CFG.Radius then
				seen[instance] = true
				local discovery = {
					key = keyFor(instance),
					x = pos.X,
					z = pos.Z,
					itemId = entry.info.itemId,
					category = entry.info.category,
					label = entry.info.label,
				}
				Remotes.MapDiscovery:FireClient(player, discovery)
				ItemDiscovery.ItemDiscovered:Fire(player, discovery)
			end
		end
	end
end

--------------------------------------------------------------------------------
-- Init
--------------------------------------------------------------------------------

function ItemDiscovery.Init()
	if initialized or not CFG.Enabled then
		return
	end
	initialized = true

	for _, descendant in Workspace:GetDescendants() do
		register(descendant)
	end
	Workspace.DescendantAdded:Connect(register)

	Players.PlayerRemoving:Connect(function(player)
		discoveredBy[player] = nil
	end)

	loopToken += 1
	local token = loopToken
	task.spawn(function()
		while loopToken == token do
			task.wait(CFG.ScanInterval)
			scanOnce()
		end
	end)
end

return ItemDiscovery
