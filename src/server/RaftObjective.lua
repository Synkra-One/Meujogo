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

	Ao chegar em 100%: marca Attribute "JangadaPronta" = true no Model
	"Jangada" e habilita o ProximityPrompt "EmpurrarJangada" (criado por
	este script, anexado ao PrimaryPart do Model).

	Empurrar a jangada: usa BasePart:GetTouchingParts() em todas as partes
	do Model no momento do trigger pra descobrir quem está tocando AGORA.
	Não restrinjo por Role (ver RaftEscaped) -- um Espião infiltrado também
	pode escapar tocando a jangada.

	IMPORTANTE (setup no Studio, fora do escopo deste script):
	  - Parts de material com Attribute "MaterialJangada" = true e "TipoMaterial".
	  - Uma Part chamada "LocalJangada" (zona de entrega) no Workspace.
	  - Um Model chamado "Jangada" com PrimaryPart definido.

	Uso (chamar uma vez no boot do servidor):
		local RaftObjective = require(script.RaftObjective)
		RaftObjective.Init()
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local GameConfig = require(ReplicatedStorage.Modules.GameConfig)
local Remotes = require(ReplicatedStorage.Modules.Remotes)
local SafeAttribute = require(ReplicatedStorage.Modules.SafeAttribute)
local StatScaling = require(ReplicatedStorage.Modules.StatScaling)

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
-- Entrega em LocalJangada e progresso
--------------------------------------------------------------------------------

local function markRaftReady()
	if raftReady then
		return
	end
	raftReady = true

	local raftModel = getRaftModel()
	if raftModel then
		raftModel:SetAttribute("JangadaPronta", true)
	end

	if pushPrompt then
		pushPrompt.Enabled = true
	end

	print("[RaftObjective] Jangada pronta! Interaja com 'EmpurrarJangada' pra fugir.")
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

local function onPushRaft(raftModel: Model)
	if not raftReady or raftPushed then
		return
	end
	raftPushed = true

	local escapedPlayers = getPlayersTouchingRaft(raftModel)

	print(string.format("[RaftObjective] Jangada empurrada ao mar! %d jogador(es) a bordo.", #escapedPlayers))
	for _, player in escapedPlayers do
		print(string.format("[RaftObjective] %s escapou na jangada!", player.Name))
	end

	Remotes.ObjectiveProgress:FireAllClients("FugaJangada", #escapedPlayers, #Players:GetPlayers(), escapedPlayers)
	RaftObjective.RaftEscaped:Fire(escapedPlayers)
end

local function setupPushPrompt()
	local raftModel = getRaftModel()
	if not raftModel then
		warn("[RaftObjective] Model 'Jangada' não encontrado no Workspace.")
		return
	end

	local anchor = raftModel.PrimaryPart or raftModel:FindFirstChildWhichIsA("BasePart")
	if not anchor then
		warn("[RaftObjective] Model 'Jangada' não tem nenhuma BasePart pra ancorar o ProximityPrompt.")
		return
	end

	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "EmpurrarJangada"
	prompt.ActionText = "Empurrar ao Mar"
	prompt.ObjectText = "Jangada"
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
	end

	if pushPrompt then
		pushPrompt.Enabled = false
	end
end

--[[
	Init()
	Conecta os materiais existentes/futuros, a zona de entrega e o prompt
	de empurrar a jangada. Chame uma vez no boot do servidor.
]]
function RaftObjective.Init()
	forEachTagged(Workspace, "MaterialJangada", watchMaterial)
	setupDeliveryZone()
	setupPushPrompt()

	Players.PlayerRemoving:Connect(function(player)
		inventory[player] = nil
	end)
end

return RaftObjective
