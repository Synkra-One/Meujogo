--!strict
--[[
	RadioObjective
	Objetivo do Rádio de Resgate: coletar 3 peças e sintonizar na
	TorreDeRadio.

	Peças: Parts com Attribute "PecaRadio" == true e Attribute "TipoPeca"
	== "Antena" | "Bateria" | "Transmissor". Ao serem tocadas por um
	Sobrevivente, são coletadas.

	ABORDAGEM ESCOLHIDA (a mais simples pra Roblox): as peças NÃO viram um
	item no inventário de ninguém. Tocar nelas já credita a peça pro time
	inteiro (tabela compartilhada `collectedPieces`) e a Part é destruída.
	Isso evita ter que lidar com Tools, drop-on-death, quem tá carregando o
	quê, etc. -- qualquer Sobrevivente vivo pode terminar o que os outros
	começaram.

	TorreDeRadio: uma Part única no Workspace (por nome). Ganha um
	ProximityPrompt criado por este script. Interagir com as 3 peças já
	coletadas dispara o minigame de sintonia -- por enquanto (sem UI ainda)
	é só um sorteio (GameConfig.RadioObjective.SuccessChance):
	  sucesso -> ObjectiveProgress("RadioCompleto", 1, 1) + começa a
	             contagem de vitória por resgate (RadioObjective.RescueCountdownStarted)
	  falha   -> RadioObjective.TuningFailed (hook pronto pra lógica do
	             Monstro escutar um "barulho" depois; nada o consome ainda)

	Interagir de novo após falhar tenta de novo (as peças continuam
	creditadas); interagir após o sucesso não faz mais nada.

	IMPORTANTE (setup no Studio, fora do escopo deste script):
	  - As 3 Parts de peça precisam de Attribute "PecaRadio" = true e
	    "TipoPeca" = "Antena"/"Bateria"/"Transmissor".
	  - Precisa existir uma Part chamada "TorreDeRadio" em algum lugar do
	    Workspace.

	Uso (chamar uma vez no boot do servidor):
		local RadioObjective = require(script.RadioObjective)
		RadioObjective.Init()

	Hooks pra outros sistemas conectarem depois:
		RadioObjective.RescueCountdownStarted.Event:Connect(function(duration) ... end)
		RadioObjective.TuningFailed.Event:Connect(function(towerPosition) ... end)
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local GameConfig = require(ReplicatedStorage.Modules.GameConfig)
local Remotes = require(ReplicatedStorage.Modules.Remotes)
local StatScaling = require(ReplicatedStorage.Modules.StatScaling)
local SafeAttribute = require(ReplicatedStorage.Modules.SafeAttribute)

local RadioObjective = {}

-- Hooks públicos: outros scripts server-side conectam aqui depois.
RadioObjective.RescueCountdownStarted = Instance.new("BindableEvent")
RadioObjective.TuningFailed = Instance.new("BindableEvent")

local REQUIRED_PIECES = { "Antena", "Bateria", "Transmissor" }

local rng = Random.new()

-- TipoPeca -> true, uma vez coletada. Compartilhado entre todos os
-- Sobreviventes (ver nota de design acima).
local collectedPieces: { [string]: boolean } = {}
local radioCompleted = false

local function hasAllPieces(): boolean
	for _, tipo in REQUIRED_PIECES do
		if not collectedPieces[tipo] then
			return false
		end
	end
	return true
end

local function countCollected(): number
	local count = 0
	for _ in collectedPieces do
		count += 1
	end
	return count
end

--------------------------------------------------------------------------------
-- Coleta de peças
--------------------------------------------------------------------------------

local function onPieceTouched(piece: BasePart, hit: BasePart)
	local character = hit:FindFirstAncestorOfClass("Model")
	local player = character and Players:GetPlayerFromCharacter(character)
	if not player or player:GetAttribute("Role") ~= GameConfig.Roles.Survivor then
		return
	end

	local tipoPeca = piece:GetAttribute("TipoPeca")
	if type(tipoPeca) ~= "string" or collectedPieces[tipoPeca] then
		return
	end

	collectedPieces[tipoPeca] = true
	piece:Destroy()

	local collected = countCollected()
	Remotes.ObjectiveProgress:FireAllClients("RadioPecas", collected, #REQUIRED_PIECES)
	print(string.format("[RadioObjective] %s coletou a peça '%s' (%d/%d)", player.Name, tipoPeca, collected, #REQUIRED_PIECES))
end

--[[
	CollectPiece(tipoPeca, player?)
	Credita uma peça do rádio SEM precisar de uma Part física no mundo --
	é como server/LootCrateSystem.lua entrega um "Transmissor" que saiu de
	uma caixa. Devolve true se a peça era válida e ainda não tinha sido
	coletada (peça repetida devolve false, pra quem chamou poder sortear
	outra coisa).
]]
function RadioObjective.CollectPiece(tipoPeca: unknown, player: Player?): boolean
	if type(tipoPeca) ~= "string" or table.find(REQUIRED_PIECES, tipoPeca) == nil then
		return false
	end
	if collectedPieces[tipoPeca] then
		return false
	end

	collectedPieces[tipoPeca] = true
	local collected = countCollected()
	Remotes.ObjectiveProgress:FireAllClients("RadioPecas", collected, #REQUIRED_PIECES)
	print(
		string.format(
			"[RadioObjective] %s conseguiu a peça '%s' (%d/%d)",
			player and player.Name or "alguém",
			tipoPeca,
			collected,
			#REQUIRED_PIECES
		)
	)
	return true
end

local function watchPiece(piece: Instance)
	if not piece:IsA("BasePart") then
		return
	end

	piece.Touched:Connect(function(hit)
		onPieceTouched(piece, hit)
	end)
end

--------------------------------------------------------------------------------
-- Torre de Rádio: minigame de sintonia (placeholder por sorteio)
--------------------------------------------------------------------------------

local function attemptTuning(player: Player, tower: BasePart)
	if radioCompleted then
		return
	end

	if player:GetAttribute("Role") ~= GameConfig.Roles.Survivor then
		return
	end

	if not hasAllPieces() then
		return
	end

	-- PLACEHOLDER: até existir a UI do minigame, o resultado é só um sorteio.
	-- REPARO -> multiplica a chance de sintonizar (teto de 95%, pra nunca ser
	-- garantido). Diego (Reparo 96) acerta ~96% das vezes; Marina (Reparo 10)
	-- ~35%. É o atributo mais decisivo do objetivo do Rádio.
	local chance = math.min(0.95, GameConfig.RadioObjective.SuccessChance * StatScaling.RepairMultiplier(player))
	local success = rng:NextNumber() <= chance

	if success then
		radioCompleted = true
		Remotes.ObjectiveProgress:FireAllClients("RadioCompleto", 1, 1)
		print(string.format("[RadioObjective] %s sintonizou o rádio com sucesso!", player.Name))

		RadioObjective.RescueCountdownStarted:Fire(GameConfig.RadioObjective.RescueCountdownDuration)
		print(string.format("[RadioObjective] Contagem de vitória por resgate iniciada (%ds).", GameConfig.RadioObjective.RescueCountdownDuration))
	else
		print(string.format("[RadioObjective] %s falhou a sintonia do rádio.", player.Name))
		RadioObjective.TuningFailed:Fire(tower.Position)
	end
end

local function setupTowerPrompt()
	local tower = Workspace:FindFirstChild("TorreDeRadio", true)
	if not tower or not tower:IsA("BasePart") then
		warn("[RadioObjective] Part 'TorreDeRadio' não encontrada no Workspace.")
		return
	end

	local prompt = tower:FindFirstChildOfClass("ProximityPrompt")
	if not prompt then
		prompt = Instance.new("ProximityPrompt")
		prompt.ActionText = "Sintonizar Rádio"
		prompt.ObjectText = "Torre de Rádio"
		prompt.Parent = tower
	end

	prompt.Triggered:Connect(function(playerWhoTriggered)
		attemptTuning(playerWhoTriggered, tower :: BasePart)
	end)
end

--------------------------------------------------------------------------------
-- Descoberta de peças (existentes + futuras)
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
	Limpa o progresso do objetivo (peças coletadas e estado de conclusão).
	Não mexe nas Parts físicas -- é pra ser chamado por um futuro
	gerenciador de partida no início de uma nova rodada, com o mapa já
	recarregado/reposto.
]]
function RadioObjective.Reset()
	table.clear(collectedPieces)
	radioCompleted = false
end

--[[
	Init()
	Conecta as peças existentes/futuras e a TorreDeRadio. Chame uma vez no
	boot do servidor.
]]
function RadioObjective.Init()
	forEachTagged(Workspace, "PecaRadio", watchPiece)
	setupTowerPrompt()
end

return RadioObjective
