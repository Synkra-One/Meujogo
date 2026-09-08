--!strict
--[[
	RaftObjective
	Objetivo da Jangada: coletar materiais, entregar em LocalJangada até
	100% de progresso, depois empurrar a jangada pronta ao mar.

	Materiais: Parts com Attribute "MaterialJangada" == true e Attribute
	"TipoMaterial" = "Madeira" | "Corda" | "Lona".

	INVENTÁRIO PESSOAL (contagem por tipo, não Tool no Backpack): tocar num
	material soma 1 ao estoque do jogador daquele tipo e destrói a Part.
	Virou contagem (em vez do antigo "carrega um por vez") porque Corda
	agora também é gasta por ConfrontSystem (amarrar o Espião) e craft
	(CraftingSystem) precisa combinar dois materiais diferentes ao mesmo
	tempo -- um slot único não permitiria isso. GetMaterialCount/
	ConsumeMaterial são a API pública que esses outros sistemas usam; são
	o MESMO estoque, então "gastar Corda pra amarrar" e "levar Corda pra
	jangada" competem pelo mesmo recurso, de propósito.

	Entrega em LocalJangada: consome TODO o estoque de material de jangada
	do jogador de uma vez (não uma unidade por vez). Progresso = unidades
	entregues * ProgressPerMaterial + bônus por ajudante simultâneo (outros
	jogadores com QUALQUER material de jangada em estoque nesse instante).

	MONTAGEM VISUAL: a Jangada é construída por Tools/RaftGenerator (só Part
	primitiva -- Init() a monta sozinho no meio da praia se ainda não existir).
	Cada peça nasce como "planta baixa" azul translúcida e carrega o estado
	construído nos Attributes. Conforme o progresso do objetivo sobe, as
	etapas (troncos do convés -> travessas -> proa -> leme -> mastro -> vela
	-> cordame -> suprimentos) vão sendo reveladas em sequência, com poeira e
	som -- parece a jangada sendo montada. No Reset da rodada todas voltam
	pra planta e a jangada volta pra praia.

	Ao chegar em 100%: marca Attribute "JangadaPronta" = true no Model
	"Jangada" e habilita o ProximityPrompt "EmpurrarJangada" (no leme).

	Empurrar a jangada: pega quem está EM CIMA do convés (caixa delimitadora
	do Model, com GetTouchingParts de reserva), prende esses jogadores à pose
	relativa e DESLIZA a jangada da praia pro mar aberto (~5,5s, desacelerando,
	afundando no surf, com respingo, rastro e balanço). Não restrinjo por Role
	-- um Espião infiltrado também pode escapar.

	IMPORTANTE:
	  - Parts de material com Attribute "MaterialJangada" = true e "TipoMaterial"
	    (ItemSpawner cuida disso).
	  - A Jangada e a zona "LocalJangada" são geradas por RaftGenerator; não
	    precisa colocar nada no Studio.

	Uso (chamar uma vez no boot do servidor):
		local RaftObjective = require(script.RaftObjective)
		RaftObjective.Init()
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local Debris = game:GetService("Debris")

local GameConfig = require(ReplicatedStorage.Modules.GameConfig)
local Remotes = require(ReplicatedStorage.Modules.Remotes)
local SafeAttribute = require(ReplicatedStorage.Modules.SafeAttribute)
local StatScaling = require(ReplicatedStorage.Modules.StatScaling)
local RaftGenerator = require(script.Parent.Tools.RaftGenerator)

local RaftObjective = {}

-- Hook público: disparado com a lista de jogadores a bordo quando a jangada
-- é empurrada ao mar (o RoundManager escuta pra encerrar a partida).
RaftObjective.RaftEscaped = Instance.new("BindableEvent")

local RAFT_MATERIALS = { "Madeira", "Corda", "Lona" }

-- player -> { TipoMaterial = quantidade }. Cobre qualquer material que
-- outros sistemas queiram registrar aqui (ex: CraftingSystem também lê/
-- consome Madeira e Lona), não só os 3 de jangada.
local inventory: { [Player]: { [string]: number } } = {}

local progress = 0
local raftReady = false
local raftPushed = false

local raftModelCache: Model? = nil
local pushPrompt: ProximityPrompt? = nil

local function getRaftModel(): Model?
	if raftModelCache and raftModelCache.Parent then
		return raftModelCache
	end

	local found = Workspace:FindFirstChild("Jangada", true)
	if found and found:IsA("Model") then
		raftModelCache = found
		return found
	end

	return nil
end

--------------------------------------------------------------------------------
-- Montagem visual da jangada (cada material entregue "constrói" uma peça)
--------------------------------------------------------------------------------
-- As Parts nascem como "planta baixa" (RaftGenerator) e carregam o estado
-- construído nos Attributes. Aqui só alternamos entre planta e construído
-- conforme o progresso do objetivo sobe/zera.

local BP_COLOR = Color3.fromRGB(96, 172, 235)
local BP_TRANSPARENCY = 0.72

type StepPart = { part: BasePart, step: number }
type PassengerLock = { root: BasePart, offset: CFrame, wasAnchored: boolean }

local assembly = {
	parts = {} :: { StepPart },
	totalSteps = 0,
	revealed = 0,
	generation = 0, -- invalida corrotinas de revelação em andamento no Reset
	homeCF = nil :: CFrame?,
	seaDir = Vector3.new(0, 0, 1),
	launching = false,
}

local function setLights(part: BasePart, on: boolean)
	for _, d in part:GetDescendants() do
		if d:IsA("Light") then
			d.Enabled = on
		end
	end
end

local function hidePart(part: BasePart)
	part.Transparency = BP_TRANSPARENCY
	part.Material = Enum.Material.SmoothPlastic
	part.Color = BP_COLOR
	part.CanCollide = false
	part.CastShadow = false
	setLights(part, false)
end

local function buildFxAt(part: BasePart)
	local attachment = Instance.new("Attachment")
	attachment.Name = "JangadaFX"
	attachment.Parent = part

	local dust = Instance.new("ParticleEmitter")
	dust.Texture = "rbxasset://textures/particles/smoke_main.dds"
	dust.Color = ColorSequence.new(Color3.fromRGB(198, 172, 122))
	dust.Lifetime = NumberRange.new(0.35, 0.75)
	dust.Speed = NumberRange.new(2, 6)
	dust.Rate = 0
	dust.SpreadAngle = Vector2.new(180, 180)
	dust.Acceleration = Vector3.new(0, -14, 0)
	dust.Size = NumberSequence.new(0.55)
	dust.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.2),
		NumberSequenceKeypoint.new(1, 1),
	})
	dust.Parent = attachment
	dust:Emit(14)

	local sound = Instance.new("Sound")
	sound.SoundId = "rbxasset://sounds/impact_generic.mp3"
	sound.Volume = 0.5
	sound.PlaybackSpeed = 0.78 + math.random() * 0.4
	sound.RollOffMode = Enum.RollOffMode.InverseTapered
	sound.RollOffMaxDistance = 55
	sound.Parent = part
	sound:Play()

	Debris:AddItem(attachment, 1.5)
	Debris:AddItem(sound, 2.5)
end

local function revealPart(part: BasePart)
	local builtColor = part:GetAttribute("CorConstruida")
	local builtMaterial = part:GetAttribute("MaterialConstruido")
	local builtTransparency = part:GetAttribute("TransparenciaConstruida")
	local builtCollide = part:GetAttribute("ColidivelConstruido")

	if typeof(builtColor) == "Color3" then
		part.Color = builtColor
	end
	if type(builtMaterial) == "string" then
		local material = (Enum.Material :: any)[builtMaterial]
		if material then
			part.Material = material
		end
	end
	part.CanCollide = builtCollide == true
	part.CastShadow = true
	setLights(part, true)

	local target = if type(builtTransparency) == "number" then builtTransparency else 0
	TweenService:Create(part, TweenInfo.new(0.35, Enum.EasingStyle.Quad), { Transparency = target }):Play()

	buildFxAt(part)
end

local function indexAssembly(model: Model)
	assembly.parts = {}
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BasePart") then
			local step = descendant:GetAttribute("EtapaConstrucao")
			if type(step) == "number" then
				table.insert(assembly.parts, { part = descendant, step = step })
			end
		end
	end
	table.sort(assembly.parts, function(a, b)
		return a.step < b.step
	end)

	local total = model:GetAttribute("EtapasTotais")
	if type(total) == "number" then
		assembly.totalSteps = total
	elseif #assembly.parts > 0 then
		assembly.totalSteps = assembly.parts[#assembly.parts].step
	else
		assembly.totalSteps = 0
	end

	assembly.homeCF = model:GetPivot()
	local dir = model:GetAttribute("DirecaoMar")
	if typeof(dir) == "Vector3" and dir.Magnitude > 0.1 then
		assembly.seaDir = dir.Unit
	end

	assembly.revealed = 0
	assembly.generation += 1
	for _, entry in assembly.parts do
		hidePart(entry.part)
	end
end

-- Reconcilia as peças visíveis com o `progress` atual. Progresso subindo:
-- revela as etapas novas em sequência rápida (parece montagem). Progresso
-- zerado (Reset): esconde tudo de volta na hora.
local function applyAssembly()
	if assembly.totalSteps <= 0 then
		return
	end

	local target = math.clamp(math.floor(progress / 100 * assembly.totalSteps + 1e-4), 0, assembly.totalSteps)
	if target == assembly.revealed then
		return
	end

	if target < assembly.revealed then
		assembly.generation += 1
		for _, entry in assembly.parts do
			if entry.step > target then
				hidePart(entry.part)
			end
		end
		assembly.revealed = target
		return
	end

	local from = assembly.revealed + 1
	assembly.revealed = target
	local myGeneration = assembly.generation
	task.spawn(function()
		for step = from, target do
			if assembly.generation ~= myGeneration then
				return
			end
			for _, entry in assembly.parts do
				if entry.step == step then
					revealPart(entry.part)
				end
			end
			task.wait(0.14)
		end
	end)
end

--------------------------------------------------------------------------------
-- Inventário pessoal (API pública pra outros sistemas)
--------------------------------------------------------------------------------

local function getOrCreateInventory(player: Player): { [string]: number }
	local inv = inventory[player]
	if not inv then
		inv = {}
		inventory[player] = inv
	end
	return inv
end

--[[
	AddMaterial(player, materialType, amount?)
	Soma ao estoque pessoal do jogador. Usado pelo pickup de material da
	jangada aqui embaixo, e também disponível pra ItemSpawner/outros
	sistemas creditarem Madeira/Lona sem passar por uma Part física.
]]
function RaftObjective.AddMaterial(player: Player, materialType: string, amount: number?)
	local inv = getOrCreateInventory(player)
	inv[materialType] = (inv[materialType] or 0) + (amount or 1)
end

--[[
	GetMaterialCount(player, materialType)
]]
function RaftObjective.GetMaterialCount(player: Player, materialType: string): number
	local inv = inventory[player]
	return inv and (inv[materialType] or 0) or 0
end

--[[
	ConsumeMaterial(player, materialType, amount?)
	Só consome se houver o suficiente; devolve se conseguiu.
]]
function RaftObjective.ConsumeMaterial(player: Player, materialType: string, amount: number?): boolean
	amount = amount or 1
	local inv = inventory[player]
	if not inv or (inv[materialType] or 0) < (amount :: number) then
		return false
	end
	inv[materialType] = (inv[materialType] :: number) - (amount :: number)
	return true
end

--------------------------------------------------------------------------------
-- Coleta de materiais
--------------------------------------------------------------------------------

local function onMaterialTouched(material: BasePart, hit: BasePart)
	local character = hit:FindFirstAncestorOfClass("Model")
	local player = character and Players:GetPlayerFromCharacter(character)
	if not player or player:GetAttribute("Role") ~= GameConfig.Roles.Survivor then
		return
	end

	local tipoMaterial = material:GetAttribute("TipoMaterial")
	local materialType = (type(tipoMaterial) == "string") and tipoMaterial or "Material"
	RaftObjective.AddMaterial(player, materialType)
	material:Destroy()

	print(string.format("[RaftObjective] %s pegou material '%s'", player.Name, materialType))
end

local function watchMaterial(material: Instance)
	if not material:IsA("BasePart") then
		return
	end

	material.Touched:Connect(function(hit)
		onMaterialTouched(material, hit)
	end)
end

--------------------------------------------------------------------------------
-- KIT DE TESTE (GameConfig.Testing.RaftKit -- TEMPORÁRIO)
--------------------------------------------------------------------------------
-- Larga material de jangada suficiente pra fechar 100% ao lado da própria
-- LocalJangada, do lado da praia. Some quando GameConfig.Testing.RaftKit = false.
-- Quantidade folgada de propósito: mesmo o personagem de Reparo mais baixo
-- (~0.55x no progresso) fecha 100% numa entrega só.

local KIT_FOLDER_NAME = "KitTesteJangada"
local KIT = { Madeira = 8, Corda = 6, Lona = 6 } -- 20 unidades -> ~132% no pior caso

local KIT_COLORS: { [string]: Color3 } = {
	Madeira = Color3.fromRGB(150, 100, 55),
	Corda = Color3.fromRGB(202, 176, 122),
	Lona = Color3.fromRGB(224, 214, 194),
}

local kitRayParams = RaycastParams.new()
kitRayParams.FilterType = Enum.RaycastFilterType.Include
kitRayParams.FilterDescendantsInstances = { Workspace.Terrain }
kitRayParams.IgnoreWater = true

local function spawnTestKit()
	if not GameConfig.Testing.RaftKit then
		return
	end

	local zone = Workspace:FindFirstChild("LocalJangada", true)
	if not zone or not zone:IsA("BasePart") then
		return
	end

	local host = zone.Parent or Workspace
	local existing = host:FindFirstChild(KIT_FOLDER_NAME)
	if existing then
		existing:Destroy()
	end
	local folder = Instance.new("Folder")
	folder.Name = KIT_FOLDER_NAME
	folder.Parent = host

	local specs: { string } = {}
	for tipo, qty in KIT do
		for _ = 1, qty do
			table.insert(specs, tipo)
		end
	end

	local perRow = 7
	for index, tipo in specs do
		local col = (index - 1) % perRow
		local row = (index - 1) // perRow
		-- +Z local da zona = lado da praia (LookVector dela aponta pro mar).
		local spot = zone.CFrame
			* CFrame.new((col - (perRow - 1) / 2) * 2.1, 0, zone.Size.Z / 2 + 3 + row * 2.4)
		local hit = Workspace:Raycast(spot.Position + Vector3.new(0, 25, 0), Vector3.new(0, -90, 0), kitRayParams)
		local y = (hit and hit.Position.Y or zone.Position.Y) + 1

		local part = Instance.new("Part")
		part.Name = tipo
		part.Size = Vector3.new(1.3, 1.3, 1.3)
		part.Position = Vector3.new(spot.Position.X, y, spot.Position.Z)
		part.Anchored = true
		part.CanCollide = false
		part.Material = Enum.Material.Neon
		part.Color = KIT_COLORS[tipo] or Color3.fromRGB(255, 195, 70)
		part:SetAttribute("MaterialJangada", true)
		part:SetAttribute("TipoMaterial", tipo)
		part.Parent = folder
	end

	print(string.format("[RaftObjective] KIT DE TESTE: %d materiais de jangada ao lado de LocalJangada.", #specs))
end

--------------------------------------------------------------------------------
-- Entrega em LocalJangada e progresso
--------------------------------------------------------------------------------

local function markRaftReady()
	if raftReady then
		return
	end
	raftReady = true

	-- Garante que nenhuma peça ficou pra trás por arredondamento.
	assembly.revealed = math.max(assembly.revealed - 1, 0)
	progress = 100
	applyAssembly()

	local raftModel = getRaftModel()
	if raftModel then
		raftModel:SetAttribute("JangadaPronta", true)
	end

	if pushPrompt then
		pushPrompt.Enabled = true
	end

	print("[RaftObjective] Jangada pronta! Empurre-a para o mar para fugir.")
end

-- Quantos OUTROS jogadores têm QUALQUER material de jangada em estoque agora.
local function countOtherHelpers(excluding: Player): number
	local count = 0
	for player, inv in inventory do
		if player ~= excluding then
			for _, materialType in RAFT_MATERIALS do
				if (inv[materialType] or 0) > 0 then
					count += 1
					break
				end
			end
		end
	end
	return count
end

local function tryDeliver(player: Player)
	if raftReady then
		return
	end

	local inv = inventory[player]
	if not inv then
		return
	end

	local totalUnits = 0
	for _, materialType in RAFT_MATERIALS do
		totalUnits += inv[materialType] or 0
		inv[materialType] = nil
	end

	if totalUnits <= 0 then
		return
	end

	-- PASSIVA do Bruno ("carrega o dobro de material por slot"): cada unidade
	-- entregue conta por duas.
	if player:GetAttribute("PassivaCargaDupla") == true then
		totalUnits *= 2
	end

	local simultaneousHelpers = countOtherHelpers(player)
	-- REPARO -> multiplica o progresso por entrega. Diego (Reparo 96) monta a
	-- jangada ~3x mais rápido que Marina (Reparo 10) com o mesmo material.
	local repairMul = StatScaling.RepairMultiplier(player)
	local gained = math.floor(
		(
			totalUnits * GameConfig.RaftObjective.ProgressPerMaterial
			+ simultaneousHelpers * GameConfig.RaftObjective.SimultaneousHelperBonus
		) * repairMul
	)
	progress = math.min(100, progress + gained)

	Remotes.ObjectiveProgress:FireAllClients("JangadaProgresso", progress, 100)
	print(
		string.format(
			"[RaftObjective] %s entregou %d unidade(s) (+%d%%, %d ajudante(s) simultâneo(s)) -- progresso total: %d%%",
			player.Name,
			totalUnits,
			gained,
			simultaneousHelpers,
			progress
		)
	)

	applyAssembly()

	if progress >= 100 then
		markRaftReady()
	end
end

local function onZoneTouched(hit: BasePart)
	local character = hit:FindFirstAncestorOfClass("Model")
	local player = character and Players:GetPlayerFromCharacter(character)
	if player then
		tryDeliver(player)
	end
end

-- Delivery is touch-based: standing inside LocalJangada is the repair interaction.
function RaftObjective.ApplyPowerRepair(player: Player): BasePart?
	if raftReady or raftPushed or player:GetAttribute("InRound") ~= true
		or player:GetAttribute("Role") ~= GameConfig.Roles.Survivor then return nil end
	local zone = Workspace:FindFirstChild("LocalJangada", true)
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	if not zone or not zone:IsA("BasePart") or not root or not root:IsA("BasePart") then return nil end
	local p = zone.CFrame:PointToObjectSpace(root.Position)
	if math.abs(p.X) > zone.Size.X / 2 + 1 or math.abs(p.Z) > zone.Size.Z / 2 + 1
		or math.abs(p.Y) > zone.Size.Y / 2 + 4 then return nil end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { player.Character :: Model, zone }
	params.RespectCanCollide = true
	local endPosition = Vector3.new(zone.Position.X, root.Position.Y, zone.Position.Z)
	if Workspace:Raycast(root.Position, endPosition - root.Position, params) then return nil end
	progress = math.min(100, progress + 25)
	Remotes.ObjectiveProgress:FireAllClients("JangadaProgresso", progress, 100)
	applyAssembly()
	if progress >= 100 then markRaftReady() end
	return zone
end

local function setupDeliveryZone()
	local zone = Workspace:FindFirstChild("LocalJangada", true)
	if not zone or not zone:IsA("BasePart") then
		warn("[RaftObjective] Part 'LocalJangada' não encontrada no Workspace.")
		return
	end

	zone.Touched:Connect(onZoneTouched)
end

--------------------------------------------------------------------------------
-- Empurrar a jangada ao mar
--------------------------------------------------------------------------------

local function getPlayersTouchingRaft(raftModel: Model): { Player }
	local seen: { [Player]: true } = {}
	local result: { Player } = {}

	for _, part in raftModel:GetDescendants() do
		if part:IsA("BasePart") then
			for _, touching in part:GetTouchingParts() do
				local character = touching:FindFirstAncestorOfClass("Model")
				local player = character and Players:GetPlayerFromCharacter(character)
				if player and not seen[player] then
					seen[player] = true
					table.insert(result, player)
				end
			end
		end
	end

	return result
end

-- Quem está EM CIMA do convés no momento do empurrão. Primeiro pela caixa
-- delimitadora do Model (pega quem está parado no deque), com o
-- GetTouchingParts como rede de segurança.
local function collectPassengers(raftModel: Model): { Player }
	local seen: { [Player]: true } = {}
	local result: { Player } = {}

	local modelCF, modelSize = raftModel:GetBoundingBox()
	local halfX = modelSize.X / 2 + 2
	local halfZ = modelSize.Z / 2 + 2

	for _, player in Players:GetPlayers() do
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if root and root:IsA("BasePart") and humanoid and humanoid.Health > 0 then
			local localPos = modelCF:PointToObjectSpace(root.Position)
			if math.abs(localPos.X) <= halfX and math.abs(localPos.Z) <= halfZ and localPos.Y > -1 and localPos.Y < 9 then
				if not seen[player] then
					seen[player] = true
					table.insert(result, player)
				end
			end
		end
	end

	if #result == 0 then
		for _, player in getPlayersTouchingRaft(raftModel) do
			if not seen[player] then
				seen[player] = true
				table.insert(result, player)
			end
		end
	end

	return result
end

local function positionalSound(position: Vector3, soundId: string, volume: number, pitch: number)
	local anchor = Instance.new("Part")
	anchor.Name = "JangadaFX"
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.CanTouch = false
	anchor.Transparency = 1
	anchor.Size = Vector3.new(0.2, 0.2, 0.2)
	anchor.CFrame = CFrame.new(position)
	anchor.Parent = Workspace

	local sound = Instance.new("Sound")
	sound.SoundId = soundId
	sound.Volume = volume
	sound.PlaybackSpeed = pitch
	sound.RollOffMode = Enum.RollOffMode.InverseTapered
	sound.RollOffMaxDistance = 120
	sound.Parent = anchor
	sound:Play()

	Debris:AddItem(anchor, 6)
end

local function attachWaterFx(raftModel: Model)
	local root = raftModel.PrimaryPart
	if not root then
		return
	end

	local attachment = Instance.new("Attachment")
	attachment.Name = "JangadaFX"
	attachment.Position = Vector3.new(0, -0.2, 0)
	attachment.Parent = root

	local spray = Instance.new("ParticleEmitter")
	spray.Texture = "rbxasset://textures/particles/smoke_main.dds"
	spray.Color = ColorSequence.new(Color3.fromRGB(236, 244, 248))
	spray.Lifetime = NumberRange.new(0.5, 1.1)
	spray.Speed = NumberRange.new(6, 12)
	spray.Rate = 55
	spray.SpreadAngle = Vector2.new(35, 12)
	spray.Acceleration = Vector3.new(0, -22, 0)
	spray.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1.4),
		NumberSequenceKeypoint.new(1, 3.6),
	})
	spray.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.25),
		NumberSequenceKeypoint.new(1, 1),
	})
	spray.Parent = attachment
	spray:Emit(40)

	local wake = Instance.new("ParticleEmitter")
	wake.Texture = "rbxasset://textures/particles/smoke_main.dds"
	wake.Color = ColorSequence.new(Color3.fromRGB(210, 228, 236))
	wake.Lifetime = NumberRange.new(1.4, 2.6)
	wake.Speed = NumberRange.new(0, 1)
	wake.Rate = 26
	wake.SpreadAngle = Vector2.new(20, 20)
	wake.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 2.2),
		NumberSequenceKeypoint.new(1, 5.5),
	})
	wake.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.55),
		NumberSequenceKeypoint.new(1, 1),
	})
	wake.Parent = attachment

	task.delay(4, function()
		spray.Enabled = false
		wake.Enabled = false
	end)
	Debris:AddItem(attachment, 12)
end

-- Desliza a jangada da praia pro mar aberto, carregando quem está a bordo.
local LAUNCH_DISTANCE = 96
local LAUNCH_DURATION = 5.5
local FLOAT_HEIGHT = 0.9

local function launchRaft(raftModel: Model, passengers: { Player })
	assembly.launching = true

	local startCF = raftModel:GetPivot()
	local dir = assembly.seaDir
	local startPos = startCF.Position
	local endPos = Vector3.new(startPos.X, startPos.Y, startPos.Z) + dir * LAUNCH_DISTANCE

	-- Prende os passageiros ao convés pela pose relativa que tinham na largada.
	local locks: { PassengerLock } = {}
	for _, player in passengers do
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if root and root:IsA("BasePart") then
			table.insert(locks, {
				root = root,
				offset = startCF:ToObjectSpace(root.CFrame),
				wasAnchored = root.Anchored,
			})
			root.Anchored = true
		end
	end

	positionalSound(startPos, "rbxasset://sounds/impact_generic.mp3", 1, 0.42)

	local t0 = os.clock()
	local splashed = false

	while true do
		local a = math.clamp((os.clock() - t0) / LAUNCH_DURATION, 0, 1)
		-- XZ: empurrão forte que desacelera (cúbica de saída).
		local aXZ = 1 - (1 - a) ^ 3
		-- Y: fica alto enquanto raspa a areia e só afunda no surf (quadrática de entrada).
		local aY = a * a

		local x = startPos.X + (endPos.X - startPos.X) * aXZ
		local z = startPos.Z + (endPos.Z - startPos.Z) * aXZ
		local y = startPos.Y + (FLOAT_HEIGHT - startPos.Y) * aY

		local level = CFrame.lookAt(Vector3.new(x, y, z), Vector3.new(x, y, z) + dir)

		-- Balanço aumenta conforme entra na água.
		local water = math.clamp((a - 0.25) / 0.75, 0, 1)
		local bob = math.sin(os.clock() * 2.3) * 0.13 * water
		local roll = math.sin(os.clock() * 1.7) * math.rad(2.3) * water
		local pitch = math.sin(os.clock() * 1.3 + 1) * math.rad(1.4) * water
		local currentCF = level * CFrame.new(0, bob, 0) * CFrame.Angles(pitch, 0, roll)

		raftModel:PivotTo(currentCF)
		for _, lock in locks do
			if lock.root.Parent then
				lock.root.CFrame = currentCF * lock.offset
			end
		end

		if not splashed and a > 0.32 then
			splashed = true
			positionalSound(raftModel:GetPivot().Position, "rbxasset://sounds/impact_water.mp3", 1, 1)
			attachWaterFx(raftModel)
		end

		if a >= 1 then
			break
		end
		RunService.Heartbeat:Wait()
	end

	-- Solta os passageiros pouco depois (a partida costuma encerrar aqui).
	task.delay(3, function()
		for _, lock in locks do
			if lock.root.Parent then
				lock.root.Anchored = lock.wasAnchored
			end
		end
	end)

	assembly.launching = false
end

local function onPushRaft(raftModel: Model)
	if not raftReady or raftPushed then
		return
	end
	raftPushed = true

	if pushPrompt then
		pushPrompt.Enabled = false
	end

	local escapedPlayers = collectPassengers(raftModel)

	print(string.format("[RaftObjective] Jangada empurrada ao mar! %d jogador(es) a bordo.", #escapedPlayers))
	for _, player in escapedPlayers do
		print(string.format("[RaftObjective] %s escapou na jangada!", player.Name))
	end

	task.spawn(function()
		launchRaft(raftModel, escapedPlayers)
	end)

	-- Deixa a fuga "ler" na tela antes de a rodada resolver.
	task.wait(1.2)

	Remotes.ObjectiveProgress:FireAllClients("FugaJangada", #escapedPlayers, #Players:GetPlayers(), escapedPlayers)
	RaftObjective.RaftEscaped:Fire(escapedPlayers)
end

local function setupPushPrompt()
	local raftModel = getRaftModel()
	if not raftModel then
		warn("[RaftObjective] Model 'Jangada' não encontrado no Workspace.")
		return
	end

	-- De preferência no leme (popa, do lado da praia -- fácil de alcançar).
	local anchor = raftModel:FindFirstChild("Leme", true)
		or raftModel.PrimaryPart
		or raftModel:FindFirstChildWhichIsA("BasePart")
	if not anchor or not anchor:IsA("BasePart") then
		warn("[RaftObjective] Model 'Jangada' não tem nenhuma BasePart pra ancorar o ProximityPrompt.")
		return
	end

	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "EmpurrarJangada"
	prompt.ActionText = "Empurrar para o mar"
	prompt.ObjectText = "Jangada"
	prompt.HoldDuration = 1
	prompt.RequiresLineOfSight = false
	prompt.MaxActivationDistance = 12
	prompt.Enabled = false -- só habilita quando JangadaPronta == true
	prompt.Parent = anchor

	prompt.Triggered:Connect(function()
		onPushRaft(raftModel :: Model)
	end)

	pushPrompt = prompt
end

--------------------------------------------------------------------------------
-- Descoberta de materiais (existentes + futuros)
--------------------------------------------------------------------------------

local function forEachTagged(root: Instance, attributeName: string, callback: (Instance) -> ())
	for _, descendant in root:GetDescendants() do
		if SafeAttribute.Get(descendant, attributeName) == true then
			callback(descendant)
		end
	end

	root.DescendantAdded:Connect(function(descendant)
		if SafeAttribute.Get(descendant, attributeName) == true then
			callback(descendant)
		end
	end)
end

--[[
	Reset()
	Zera o progresso do objetivo e os inventários pessoais pra uma nova
	rodada. Não repõe as Parts de material no mapa.
]]
function RaftObjective.Reset()
	table.clear(inventory)
	progress = 0
	raftReady = false
	raftPushed = false

	local raftModel = getRaftModel()
	if raftModel then
		raftModel:SetAttribute("JangadaPronta", false)

		-- Limpa efeitos de água/rastro e devolve a jangada pra praia.
		for _, descendant in raftModel:GetDescendants() do
			if descendant.Name == "JangadaFX" then
				descendant:Destroy()
			end
		end
		if assembly.homeCF and not assembly.launching then
			raftModel:PivotTo(assembly.homeCF)
		end
	end

	-- progress = 0 -> applyAssembly esconde tudo de volta no estado de planta.
	applyAssembly()

	if pushPrompt then
		pushPrompt.Enabled = false
	end

	spawnTestKit()
end

--[[
	Init()
	Conecta os materiais existentes/futuros, a zona de entrega e o prompt
	de empurrar a jangada. Chame uma vez no boot do servidor.
]]
function RaftObjective.Init()
	-- Garante a jangada + a zona de entrega no mundo. Só primitivas -- pode
	-- construir em runtime sem cair em placeholder (ver RaftGenerator).
	local raftModel = getRaftModel()
	if not raftModel and Workspace:FindFirstChild("Ilha") then
		local ok, built = pcall(RaftGenerator.Build)
		if ok and typeof(built) == "Instance" then
			raftModelCache = built :: Model
			raftModel = built :: Model
			print("[RaftObjective] Jangada não existia -- construída automaticamente no meio da praia.")
		elseif ok then
			warn("[RaftObjective] RaftGenerator não achou praia pra montar a Jangada -- gere/salve a ilha.")
		else
			warn("[RaftObjective] Falha ao construir a Jangada automaticamente: " .. tostring(built))
		end
	end

	if raftModel then
		indexAssembly(raftModel)
	end

	forEachTagged(Workspace, "MaterialJangada", watchMaterial)
	setupDeliveryZone()
	setupPushPrompt()
	spawnTestKit()

	Players.PlayerRemoving:Connect(function(player)
		inventory[player] = nil
	end)
end

return RaftObjective
