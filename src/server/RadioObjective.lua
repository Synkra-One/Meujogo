--!strict
--[[
	RadioObjective
	Estado compartilhado do objetivo do Rádio de Resgate.

	As três peças físicas principais são gerenciadas por RadioPieces.lua:
	viram Tools no inventário e caem na morte. Este módulo considera as peças
	que os Sobreviventes carregam ao liberar a sintonia da torre. O método
	CollectPiece continua disponível como compatibilidade para entregas
	server-side sem uma Part física.

	RadioInstallSystem.lua controla o prompt da TorreDeRadio, consome as
	peças e encerra esta etapa em "TodasPecasInstaladas". A implementação
	legada de sintonia abaixo permanece desconectada até ser substituída pelo
	minigame definitivo.

	IMPORTANTE (setup no Studio):
	  - RadioPieces.lua cria e posiciona as 3 Parts automaticamente.
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

-- Compatibilidade com fontes server-side que creditam uma peça direto ao time.
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

local function availablePieceTypes(): { [string]: boolean }
	local available = table.clone(collectedPieces)
	local ilha = Workspace:FindFirstChild("Ilha")
	local tower = ilha and ilha:FindFirstChild("TorreDeRadio")
	if tower then
		for _, tipo in REQUIRED_PIECES do
			if tower:GetAttribute(tipo .. "Instalada") == true then
				available[tipo] = true
			end
		end
	end
	for _, player in Players:GetPlayers() do
		if player:GetAttribute("Role") ~= GameConfig.Roles.Survivor then continue end
		local containers: { Instance? } = { player.Character, player:FindFirstChildOfClass("Backpack") }
		for _, container in containers do
			if container then
				for _, item in container:GetChildren() do
					if item:IsA("Tool") and item:GetAttribute("PecaRadio") == true then
						local tipo = item:GetAttribute("TipoPeca")
						if type(tipo) == "string" and table.find(REQUIRED_PIECES, tipo) then
							available[tipo] = true
						end
					end
				end
			end
		end
	end
	return available
end

local function hasAllPieces(): boolean
	local available = availablePieceTypes()
	for _, tipo in REQUIRED_PIECES do
		if not available[tipo] then return false end
	end
	return true
end

local function countCollected(): number
	local count = 0
	for _ in availablePieceTypes() do count += 1 end
	return count
end

function RadioObjective.RefreshPieceProgress()
	Remotes.ObjectiveProgress:FireAllClients("RadioPecas", countCollected(), #REQUIRED_PIECES)
end

--------------------------------------------------------------------------------
-- Coleta de peças
--------------------------------------------------------------------------------

local function onPieceTouched(piece: BasePart, hit: BasePart)
	-- RadioPieces gerencia essas Parts como itens de inventário. Sem esta
	-- guarda, os dois listeners de Touched disputariam a mesma peça.
	if piece:GetAttribute("_RadioPiecesManaged") == true then
		return
	end

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
	RadioObjective.RefreshPieceProgress()
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
	RadioObjective.RefreshPieceProgress()
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

--[[
	CompleteRescueCall(player?)
	Fim de linha do objetivo do Rádio: RadioSiteSystem chama quando o pedido
	de socorro termina de ser transmitido na estação. É o MESMO desfecho da
	sintonia legada -- marca o rádio como concluído, publica o progresso e
	dispara RescueCountdownStarted (que o RoundManager escuta).

	Devolve false se o rádio já tinha sido concluído nesta rodada.
]]
function RadioObjective.CompleteRescueCall(player: Player?): boolean
	if radioCompleted then
		return false
	end
	completeRadio()
	print(string.format(
		"[RadioObjective] Pedido de socorro enviado por %s -- contagem de resgate iniciada (%ds).",
		player and player.Name or "alguém",
		GameConfig.RadioObjective.RescueCountdownDuration
	))
	return true
end

-- true depois que o socorro foi pedido nesta rodada.
function RadioObjective.IsCompleted(): boolean
	return radioCompleted
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
-- Sintonia legada, mantida somente como API compatível e desativada no Init
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
		or character:GetAttribute("PowerStunned") == true or character:GetAttribute("GrabLocked") == true
		or not tower:IsDescendantOf(Workspace)
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
	local ilha = Workspace:FindFirstChild("Ilha")
	local tower = ilha and ilha:FindFirstChild("TorreDeRadio")
	if tower then
		for _, tipo in REQUIRED_PIECES do
			tower:SetAttribute(tipo .. "Instalada", nil)
		end
	end
	RadioObjective.RefreshPieceProgress()
end

--[[
	Init()
	Conecta as peças existentes/futuras e a TorreDeRadio. Chame uma vez no
	boot do servidor.
]]
function RadioObjective.Init()
	Players.PlayerRemoving:Connect(function(player) interacting[player] = nil end)
	forEachTagged(Workspace, "PecaRadio", watchPiece)
	-- A sintonia fica bloqueada até o sistema futuro de minigame. Por ora,
	-- RadioInstallSystem controla exclusivamente o prompt da torre e emite
	-- "TodasPecasInstaladas" quando as três instalações terminarem.
end

return RadioObjective
