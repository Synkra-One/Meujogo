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
local tuningProgress = 0
local interacting: { [Player]: { tower: BasePart, untilTime: number } } = {}

local function completeRadio()
	if radioCompleted then return end
	radioCompleted = true
	tuningProgress = 100
	Remotes.ObjectiveProgress:FireAllClients("RadioSintonia", 100, 100)
	Remotes.ObjectiveProgress:FireAllClients("RadioCompleto", 1, 1)
	RadioObjective.RescueCountdownStarted:Fire(GameConfig.RadioObjective.RescueCountdownDuration)
end

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
	local chance = math.min(0.95, GameConfig.RadioObjective.SuccessChance * StatScaling.RepairMultiplier(player) + tuningProgress / 100)
	local success = rng:NextNumber() <= chance

	if success then
		completeRadio()
		print(string.format("[RadioObjective] %s sintonizou o rádio com sucesso!", player.Name))

		print(string.format("[RadioObjective] Contagem de vitória por resgate iniciada (%ds).", GameConfig.RadioObjective.RescueCountdownDuration))
	else
		print(string.format("[RadioObjective] %s falhou a sintonia do rádio.", player.Name))
		RadioObjective.TuningFailed:Fire(tower.Position)
	end
end

local function canInteract(player: Player, tower: BasePart): boolean
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if player:GetAttribute("InRound") ~= true or player:GetAttribute("Role") ~= GameConfig.Roles.Survivor
		or player:GetAttribute("Eliminado") == true or player:GetAttribute("Amarrado") == true
		or not humanoid or humanoid.Health <= 0 or not root or not root:IsA("BasePart")
		or character:GetAttribute("PowerStunned") == true or not tower:IsDescendantOf(Workspace)
		or (root.Position - tower.Position).Magnitude > 12 then return false end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { character, tower }
	params.RespectCanCollide = true
	return Workspace:Raycast(root.Position, tower.Position - root.Position, params) == nil
end

-- Adds exactly 25 percentage points to tuning, never fabricates missing pieces.
function RadioObjective.ApplyPowerRepair(player: Player): BasePart?
	local state = interacting[player]
	if not state or state.untilTime < Workspace:GetServerTimeNow() or radioCompleted or not hasAllPieces()
		or not canInteract(player, state.tower) then return nil end
	tuningProgress = math.min(100, tuningProgress + 25)
	Remotes.ObjectiveProgress:FireAllClients("RadioSintonia", tuningProgress, 100)
	if tuningProgress >= 100 then completeRadio() end
	return state.tower
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

	prompt.HoldDuration = 2
	prompt.MaxActivationDistance = 10
	prompt.PromptButtonHoldBegan:Connect(function(player)
		if canInteract(player, tower :: BasePart) then
			interacting[player] = { tower = tower :: BasePart, untilTime = Workspace:GetServerTimeNow() + 3 }
		end
	end)
	prompt.PromptButtonHoldEnded:Connect(function(player) interacting[player] = nil end)
	prompt.Triggered:Connect(function(playerWhoTriggered)
		if canInteract(playerWhoTriggered, tower :: BasePart) then attemptTuning(playerWhoTriggered, tower :: BasePart) end
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
	tuningProgress = 0
	table.clear(interacting)
end

--[[
	Init()
	Conecta as peças existentes/futuras e a TorreDeRadio. Chame uma vez no
	boot do servidor.
]]
function RadioObjective.Init()
	Players.PlayerRemoving:Connect(function(player) interacting[player] = nil end)
	forEachTagged(Workspace, "PecaRadio", watchPiece)
	setupTowerPrompt()
end

return RadioObjective
