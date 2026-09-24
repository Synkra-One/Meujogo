--!strict
--[[
	DrawerSystem
	Gavetas que abrem, fecham e guardam item. Toda BasePart com Attribute
	"Gaveta" == true (Tools/Houses/Furniture.Drawer cria assim: a "Frente",
	com a bandeja soldada nela) é candidata à seleção por casa:

	  E  Abrir / Fechar   -- desliza a frente pelo LookVector (GavetaCurso)
	  B  Guardar item     -- guarda a Tool da mão numa gaveta aberta e vazia
	     Pegar            -- o item dentro usa o prompt normal do DropItemSystem

	ITEM DENTRO DA GAVETA
	  É a própria Tool, colocada com DropItemSystem.PlaceInWorld (então o
	  "Pegar", o XP de item encontrado e as regras de peça do rádio continuam
	  as mesmas) e ANCORADA deitada no fundo da gaveta. Ela desliza junto com
	  a gaveta; fechada, fica dentro do móvel com o "Pegar" desligado e o
	  Attribute OcultoNaGaveta = true (ItemDiscovery não marca no mapa o que
	  ninguém está vendo).

	LOOT POR RODADA (RoundPrepared)
	  Fecha todas as gavetas, apaga o que ficou guardado da rodada anterior e
	  escolhe 5–7 gavetas por casa, priorizando a superior de cada móvel, e
	  sorteia 1–3 delas pra ter item. As demais ficam apenas decorativas. O ITEM só é
	  sorteado quando alguém abre a gaveta pela primeira vez -- com a Sorte
	  dessa pessoa, como nas caixas (LootCrateSystem). Quem está no servidor
	  não descobre pelo Attribute quais gavetas têm algo: isso fica só aqui.

	O Monstro não usa gaveta (GameConfig.Drawers.MonsterCanUse); o cliente
	esconde os prompts dele (DrawerPromptController) e o servidor recusa.

	Uso (boot, depois de DropItemSystem e CharacterStatsApplier):
		require(script.DrawerSystem).Init()
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local GameConfig = require(ReplicatedStorage.Modules.GameConfig)
local ItemRegistry = require(ReplicatedStorage.Modules.ItemRegistry)
local Remotes = require(ReplicatedStorage.Modules.Remotes)
local StatScaling = require(ReplicatedStorage.Modules.StatScaling)
local ToolFactory = require(ReplicatedStorage.Modules.ToolFactory)

local DropItemSystem = require(script.Parent.DropItemSystem)
local InteractionGuard = require(script.Parent.InteractionGuard)
local DrawerRules = require(script.Parent.DrawerRules)

local DrawerSystem = {}

local CFG = GameConfig.Drawers
local TWEEN = TweenInfo.new(CFG.SlideTime, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local HIDDEN_ATTR = "OcultoNaGaveta"
local ITEM_ATTR = "GavetaItem"

type Drawer = {
	front: BasePart,
	model: Instance,
	toggle: ProximityPrompt,
	functional: boolean,
	epoch: number,
	tween: Tween?,
	itemTween: Tween?,
	busy: boolean,
	loot: boolean,
	item: Tool?,
	itemOffset: CFrame?, -- CFrame do Handle relativo à frente
	itemConn: RBXScriptConnection?,
}

local drawers: { [BasePart]: Drawer } = {}
local rng = Random.new()

-- Mesmo universo das caixas: itens com raridade, fora as peças únicas do rádio.
local pool: { [string]: { string } } = {}
for itemId, def in ItemRegistry.Items do
	local rarity = (def :: any).Rarity
	if (def :: any).Category == "Tool" and type(rarity) == "string" then
		pool[rarity] = pool[rarity] or {}
		table.insert(pool[rarity], itemId)
	end
end
for _, list in pool do
	table.sort(list)
end

--------------------------------------------------------------------------------
-- Geometria
--------------------------------------------------------------------------------

local function pose(d: Drawer, open: boolean): CFrame
	local closed = d.front:GetAttribute("CFrameFechada") :: CFrame
	if not open then
		return closed
	end
	local travel = d.front:GetAttribute("GavetaCurso") :: number
	return closed * CFrame.new(0, 0, -travel)
end

local function handleOf(tool: Tool): BasePart?
	local handle = tool:FindFirstChild("Handle")
	if handle and handle:IsA("BasePart") then
		return handle
	end
	return tool:FindFirstChildWhichIsA("BasePart", true)
end

-- Caixa de todas as peças da Tool nos eixos do Handle: (tamanho, centro local).
local function localBounds(tool: Tool, handle: BasePart): (Vector3, Vector3)
	local lo = Vector3.new(math.huge, math.huge, math.huge)
	local hi = -lo
	for _, d in tool:GetDescendants() do
		if d:IsA("BasePart") then
			local rel = handle.CFrame:ToObjectSpace(d.CFrame)
			local half = d.Size / 2
			for _, sx in { -1, 1 } do
				for _, sy in { -1, 1 } do
					for _, sz in { -1, 1 } do
						local p = rel * Vector3.new(sx * half.X, sy * half.Y, sz * half.Z)
						lo = lo:Min(p)
						hi = hi:Max(p)
					end
				end
			end
		end
	end
	return hi - lo, (hi + lo) / 2
end

--[[
	layout(d, tool, open) -> CFrame do Handle?
	Deita a Tool no fundo útil da gaveta (maior lado na largura). nil = não cabe.
]]
local function layout(d: Drawer, tool: Tool, open: boolean): CFrame?
	local handle = handleOf(tool)
	local interior = d.front:GetAttribute("GavetaInterior")
	local slot = d.front:GetAttribute("GavetaSlot")
	if not handle or typeof(interior) ~= "Vector3" or typeof(slot) ~= "CFrame" then
		return nil
	end
	local size, center = localBounds(tool, handle)
	local fits, order = DrawerRules.FitOrientation(size, interior)
	if not fits then
		return nil
	end
	local slotCF = pose(d, open) * slot
	local drawerAxes = { slotCF.RightVector, slotCF.UpVector, -slotCF.LookVector }
	local axes: { Vector3 } = { Vector3.zero, Vector3.zero, Vector3.zero }
	for k = 1, 3 do
		axes[order[k]] = drawerAxes[k]
	end
	if axes[1]:Cross(axes[2]):Dot(axes[3]) < 0 then
		axes[3] = -axes[3]
	end
	local rotation = CFrame.fromMatrix(Vector3.zero, axes[1], axes[2], axes[3])
	local dims = { size.X, size.Y, size.Z }
	local target = slotCF.Position + slotCF.UpVector * (dims[order[2]] / 2 + 0.01)
	return CFrame.new(target - rotation:VectorToWorldSpace(center)) * rotation
end

--------------------------------------------------------------------------------
-- Item dentro da gaveta
--------------------------------------------------------------------------------

local function setItemVisible(tool: Tool, visible: boolean)
	tool:SetAttribute(HIDDEN_ATTR, if visible then nil else true)
	local handle = handleOf(tool)
	local prompt = handle and handle:FindFirstChild("PegarPrompt")
	if prompt and prompt:IsA("ProximityPrompt") then
		prompt.Enabled = visible
	end
end

local function clearItem(d: Drawer)
	if d.itemConn then
		d.itemConn:Disconnect()
		d.itemConn = nil
	end
	local tool = d.item
	d.item = nil
	d.itemOffset = nil
	d.front:SetAttribute(ITEM_ATTR, nil)
	if tool and tool.Parent and not tool:IsDescendantOf(d.model) then
		tool:SetAttribute(HIDDEN_ATTR, nil)
	end
end

--[[
	putItem(d, tool, open) -> boolean
	Põe a Tool na gaveta (na pose aberta ou fechada). false = não coube; a
	Tool fica onde estava.
]]
local function putItem(d: Drawer, tool: Tool, open: boolean): boolean
	local handleCF = layout(d, tool, open)
	local handle = handleOf(tool)
	if not handleCF or not handle then
		return false
	end
	DropItemSystem.PlaceInWorld(tool, handleCF, d.model, nil)
	-- PlaceInWorld posiciona pelo pivot da Tool; corrige pro Handle exato.
	local pivotFromHandle = handle.CFrame:ToObjectSpace(tool:GetPivot())
	tool:PivotTo(handleCF * pivotFromHandle)
	handle.Anchored = true
	handle.AssemblyLinearVelocity = Vector3.zero

	d.item = tool
	d.itemOffset = pose(d, open):ToObjectSpace(handle.CFrame)
	local def = ItemRegistry.Items[tool:GetAttribute("WorldItemId") or ""]
	d.front:SetAttribute(ITEM_ATTR, if def then def.DisplayName else tool.Name)
	setItemVisible(tool, open)
	d.itemConn = tool.AncestryChanged:Connect(function()
		if not tool:IsDescendantOf(d.model) then
			clearItem(d)
		end
	end)
	return true
end

local function rollLoot(d: Drawer, player: Player)
	local epoch = d.epoch
	local available: { [string]: { string } } = {}
	local weights = table.clone(GameConfig.LootCrates.RarityWeights)
	for rarity, list in pool do available[rarity] = table.clone(list) end
	-- Tenta candidatos sem repetição: item grande/asset indisponível não pode
	-- consumir uma das 1–3 vagas enquanto ainda houver um item que caiba.
	while true do
		for rarity in weights do
			if not available[rarity] or #available[rarity] == 0 then weights[rarity] = nil end
		end
		local rarity = DrawerRules.RollRarity(weights, StatScaling.LootRarityMultiplier(player), rng)
		if not rarity then break end
		local list = available[rarity]
		if list and #list > 0 then
			local itemId = table.remove(list, rng:NextInteger(1, #list))
			local tool = ToolFactory.Create(itemId)
			if d.epoch ~= epoch or not d.front.Parent then
				if tool then tool:Destroy() end
				return
			end
			if tool then
				tool:SetAttribute("WorldItemId", itemId)
				if putItem(d, tool, false) then
					local handle = handleOf(tool)
					local prompt = handle and handle:FindFirstChild("PegarPrompt")
					if prompt and prompt:IsA("ProximityPrompt") then
						prompt.ObjectText = ItemRegistry.Items[itemId].DisplayName
					end
					return
				end
				tool:Destroy() -- não coube nessa gaveta: tenta outro item
			end
		end
	end
	warn("[DrawerSystem] Nenhum item disponível cabe em " .. d.front:GetFullName())
end

--------------------------------------------------------------------------------
-- Abrir / fechar
--------------------------------------------------------------------------------

local function playSlide(front: BasePart, open: boolean)
	local sound = Instance.new("Sound")
	sound.SoundId = "rbxasset://sounds/impact_generic.mp3"
	sound.Volume = 0.22
	sound.PlaybackSpeed = if open then 1.25 else 1.05
	sound.RollOffMaxDistance = 30
	sound.Parent = front
	sound:Play()
	game:GetService("Debris"):AddItem(sound, 2)
end

local function move(d: Drawer, open: boolean, instant: boolean?)
	local target = pose(d, open)
	d.front:SetAttribute("GavetaAberta", open)
	d.toggle.ActionText = if open then "Fechar" else "Abrir"
	local tool = d.item
	local handle = tool and handleOf(tool)
	if tool and not open then
		setItemVisible(tool, false)
	end

	if instant then
		d.front.CFrame = target
		if handle and d.itemOffset then
			handle.CFrame = target * d.itemOffset
		end
		return
	end

	d.busy = true
	playSlide(d.front, open)
	local tween = TweenService:Create(d.front, TWEEN, { CFrame = target })
	d.tween = tween
	if handle and d.itemOffset then
		d.itemTween = TweenService:Create(handle, TWEEN, { CFrame = target * d.itemOffset })
		d.itemTween:Play()
	end
	local epoch = d.epoch
	tween.Completed:Once(function()
		if d.epoch ~= epoch then return end
		d.tween = nil
		d.itemTween = nil
		d.busy = false
		if open and d.item and d.item == tool then
			setItemVisible(d.item, true)
		end
	end)
	tween:Play()
end

local function canUse(player: Player, d: Drawer): boolean
	if not d.functional then return false end
	if not CFG.MonsterCanUse and player:GetAttribute("Role") == GameConfig.Roles.Monster then
		return false
	end
	return InteractionGuard.CanReach(player, d.front, CFG.OpenRange + 2)
end

local function onToggle(player: Player, d: Drawer)
	if d.busy or not canUse(player, d) then
		return
	end
	local open = d.front:GetAttribute("GavetaAberta") ~= true
	if open and d.loot and not d.item then
		local epoch = d.epoch
		d.loot = false
		d.busy = true -- ToolFactory pode ceder (asset); ninguém abre em paralelo
		local ok, err = pcall(rollLoot, d, player)
		if d.epoch ~= epoch or not d.front.Parent then return end
		d.busy = false
		if not ok then
			warn("[DrawerSystem] Falha ao sortear item da gaveta: " .. tostring(err))
		end
	end
	move(d, open)
end

local function onStore(player: Player, d: Drawer)
	if d.busy or d.item or d.front:GetAttribute("GavetaAberta") ~= true or not canUse(player, d) then
		return
	end
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local tool = character and character:FindFirstChildOfClass("Tool")
	if not humanoid or humanoid.Health <= 0 or not tool or character:GetAttribute("GrabLocked") == true then
		return
	end
	if tool:GetAttribute("LobbyTestWeapon") == true then
		return
	end
	if not layout(d, tool, true) then
		Remotes.LobbyMessage:FireClient(player, "Esse item não cabe nessa gaveta.")
		return
	end
	humanoid:UnequipTools()
	if tool.Parent ~= player:FindFirstChildOfClass("Backpack") then
		return -- a Tool sumiu no meio do caminho (morreu, largou)
	end
	putItem(d, tool, true)
end

--------------------------------------------------------------------------------
-- Registro
--------------------------------------------------------------------------------

local function register(front: Instance)
	if not front:IsA("BasePart") or drawers[front] or front:GetAttribute("Gaveta") ~= true then
		return
	end
	if typeof(front:GetAttribute("CFrameFechada")) ~= "CFrame" or type(front:GetAttribute("GavetaCurso")) ~= "number" then
		warn("[DrawerSystem] Gaveta sem CFrameFechada/GavetaCurso: " .. front:GetFullName())
		return
	end
	local label = front:GetAttribute("GavetaMovel")
	local objectText = if type(label) == "string" then label else "Gaveta"
	front:SetAttribute("GavetaFuncional", false)
	-- Mapas salvos podem conter os prompts de uma sessão anterior.
	for _, child in front:GetChildren() do
		if child:IsA("ProximityPrompt") and (child.Name == "GavetaPrompt" or child.Name == "GuardarPrompt") then
			child:Destroy()
		end
	end

	local toggle = Instance.new("ProximityPrompt")
	toggle.Name = "GavetaPrompt"
	toggle.ObjectText = objectText
	toggle.ActionText = "Abrir"
	toggle.HoldDuration = 0
	toggle.MaxActivationDistance = CFG.OpenRange
	toggle.RequiresLineOfSight = true
	toggle.Enabled = false
	toggle.Parent = front

	-- O cliente liga este prompt só pra quem está com Tool na mão.
	local store = Instance.new("ProximityPrompt")
	store.Name = "GuardarPrompt"
	store.ObjectText = objectText
	store.ActionText = "Guardar item"
	store.KeyboardKeyCode = CFG.StoreKey
	store.GamepadKeyCode = CFG.StoreGamepadKey
	store.HoldDuration = 0.25
	store.MaxActivationDistance = CFG.OpenRange
	store.RequiresLineOfSight = true
	store.UIOffset = Vector2.new(0, 72)
	store.Enabled = false
	store.Parent = front

	local d: Drawer = {
		front = front,
		model = front.Parent or front,
		toggle = toggle,
		functional = false,
		epoch = 0,
		busy = false,
		loot = false,
		item = nil,
		itemOffset = nil,
		itemConn = nil,
	}
	drawers[front] = d
	move(d, false, true)

	toggle.Triggered:Connect(function(player: Player)
		onToggle(player, d)
	end)
	store.Triggered:Connect(function(player: Player)
		onStore(player, d)
	end)
	front.Destroying:Connect(function()
		clearItem(d)
		drawers[front] = nil
	end)
end

-- Casas já salvas têm CasaGerada/Construcao; Moveis serve como fallback
-- para modelos antigos. Nunca agrupa casas diferentes pela pasta Ilha/Casas.
local function houseOf(d: Drawer): Instance
	local ancestor = d.model.Parent
	local fallback = ancestor or d.model
	while ancestor and ancestor ~= Workspace do
		if ancestor:GetAttribute("CasaGerada") == true or ancestor:GetAttribute("Construcao") ~= nil then
			return ancestor
		end
		if ancestor.Name == "Moveis" and ancestor.Parent then fallback = ancestor.Parent end
		ancestor = ancestor.Parent
	end
	return fallback
end

local function selectFunctional(list: { Drawer }): { Drawer }
	local furniture: { [Instance]: { Drawer } } = {}
	for _, d in list do
		local owner = d.model.Parent or d.model
		furniture[owner] = furniture[owner] or {}
		table.insert(furniture[owner], d)
	end
	local preferred: { Drawer } = {}
	local extra: { Drawer } = {}
	for _, group in furniture do
		table.sort(group, function(a, b)
			local ac = a.front:GetAttribute("CFrameFechada") :: CFrame
			local bc = b.front:GetAttribute("CFrameFechada") :: CFrame
			if ac.Position.Y ~= bc.Position.Y then return ac.Position.Y > bc.Position.Y end
			if ac.Position.X ~= bc.Position.X then return ac.Position.X < bc.Position.X end
			return ac.Position.Z < bc.Position.Z
		end)
		table.insert(preferred, group[1])
		for i = 2, #group do table.insert(extra, group[i]) end
	end
	local selected: { Drawer } = {}
	for _, i in DrawerRules.ChooseLoot(#preferred, CFG.FunctionalPerHouse.Min, CFG.FunctionalPerHouse.Max, rng) do
		table.insert(selected, preferred[i])
	end
	-- Só usa mais de uma gaveta do móvel quando faltam móveis para atingir 5.
	local missing = math.max(0, CFG.FunctionalPerHouse.Min - #selected)
	for _, i in DrawerRules.ChooseLoot(#extra, missing, missing, rng) do
		table.insert(selected, extra[i])
	end
	return selected
end

--[[
	Reset()
	Fecha tudo, apaga o que ficou guardado e sorteia as gavetas com item.
	Chamado a cada RoundPrepared (e no Init, pra testar no Play do Studio).
]]
function DrawerSystem.Reset()
	-- Inclui casas adicionadas depois do boot, com atributos definidos após Parent.
	for _, instance in Workspace:GetDescendants() do register(instance) end
	local houses: { [Instance]: { Drawer } } = {}
	for _, d in drawers do
		d.epoch += 1
		if d.tween then d.tween:Cancel(); d.tween = nil end
		if d.itemTween then d.itemTween:Cancel(); d.itemTween = nil end
		local tool = d.item
		clearItem(d)
		if tool and tool:IsDescendantOf(d.model) then
			tool:Destroy()
		end
		d.busy = false
		d.loot = false
		d.functional = false
		d.toggle.Enabled = false
		d.front:SetAttribute("GavetaFuncional", false)
		move(d, false, true)
		local house = houseOf(d)
		houses[house] = houses[house] or {}
		table.insert(houses[house], d)
	end
	for _, list in houses do
		local active = selectFunctional(list)
		for _, d in active do
			d.functional = true
			d.front:SetAttribute("GavetaFuncional", true)
			d.toggle.Enabled = true
		end
		for _, index in DrawerRules.ChooseLoot(#active, CFG.LootPerHouse.Min, CFG.LootPerHouse.Max, rng) do
			active[index].loot = true
		end
	end
end

function DrawerSystem.Init()
	for _, d in Workspace:GetDescendants() do
		if d:GetAttribute("Gaveta") == true then
			register(d)
		end
	end
	Workspace.DescendantAdded:Connect(function(d)
		if d:GetAttribute("Gaveta") == true then
			register(d)
		end
	end)

	local RoundManager = require(script.Parent.RoundManager)
	RoundManager.RoundPrepared.Event:Connect(DrawerSystem.Reset)
	DrawerSystem.Reset()

	local count = 0
	for _ in drawers do
		count += 1
	end
	print(string.format("[DrawerSystem] %d gaveta(s) prontas.", count))
end

return DrawerSystem
