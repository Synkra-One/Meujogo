--!strict
--[[
	SabotageSystem
	Processa pedidos de sabotagem do Espião (RemoteEvent SabotageAction,
	ver contrato em ReplicatedStorage/Modules/Remotes.lua).

	Fluxo atual (placeholder, até conectar aos objetivos de Rádio):
	  cliente dispara SabotageAction:FireServer(target) -> se o jogador for
	  Espiao, o alvo for Sabotavel, estiver por perto e o cooldown já tiver
	  passado, o servidor marca target:SetAttribute("Sabotado", true) e
	  reinicia o cooldown. Quem precisar reagir à sabotagem escuta
	  target:GetAttributeChangedSignal("Sabotado") -- Attributes replicam
	  para os clientes sozinhos, não precisa de outro remote.

	Qualquer falha de validação (não é Espiao, alvo inválido, cooldown ainda
	ativo) é rejeitada em silêncio: nada é enviado de volta ao cliente e
	nenhum erro é gerado.

	REPARO ("Fio Cortado"): o pedido original só diz "gerado quando sabota"
	e "precisa trocar por um novo fio (força re-visita ao ponto sabotado)",
	sem nenhum local de spawn pra um Fio coletável. Interpretei que o ponto
	da mecânica É a revisita, não carregar um item de outro lugar: qualquer
	Sobrevivente que interaja com o objeto sabotado (ProximityPrompt
	"Reparar", só aparece enquanto Sabotado == true) desfaz a sabotagem, sem
	precisar de item nenhum. Se você queria um "Fio" carregável de verdade,
	me diga onde ele deveria spawnar.

	O "segure E por GameConfig.Spy.RepairHoldDuration" virou o minigame de
	precisão de RepairMinigameSystem. A REGRA continua aqui: quem pode
	reparar e o que reparar faz (onRepairTriggered) não mudaram -- o minigame
	só decide QUANDO essa função é chamada. Com
	RepairMinigameConfig.Tasks.SabotagemFio.Enabled = false tudo volta a
	resolver na hora, sem minigame.

	Uso (chamar uma vez no boot do servidor):
		local SabotageSystem = require(script.SabotageSystem)
		SabotageSystem.Init()
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local GameConfig = require(ReplicatedStorage.Modules.GameConfig)
local Remotes = require(ReplicatedStorage.Modules.Remotes)
local SafeAttribute = require(ReplicatedStorage.Modules.SafeAttribute)
local RepairMinigameSystem = require(script.Parent.RepairMinigameSystem)
local MatchStateService = require(script.Parent.MatchStateService)

local SabotageSystem = {}

-- Alvo precisa estar a até esta distância (studs) do character do jogador.
-- Sem isso, um cliente alterado poderia sabotar qualquer objeto do mapa
-- mandando a referência dele direto, sem estar perto.
-- TODO: mover para GameConfig se precisar ajustar durante playtest.
local MAX_SABOTAGE_DISTANCE = 12

-- player.UserId -> os.clock() da última sabotagem bem-sucedida.
local lastSabotageAt: { [number]: number } = {}

local function isOnCooldown(player: Player): boolean
	local last = lastSabotageAt[player.UserId]
	if not last then
		return false
	end

	return (os.clock() - last) < GameConfig.Spy.SabotageCooldownDefault
end

-- BasePart usa a própria posição; Model usa o pivot. Qualquer outra coisa
-- não é um alvo físico válido.
local function getTargetPosition(target: Instance): Vector3?
	if target:IsA("BasePart") then
		return target.Position
	elseif target:IsA("Model") then
		return target:GetPivot().Position
	end

	return nil
end

local function isValidTarget(player: Player, target: unknown): boolean
	if typeof(target) ~= "Instance" then
		return false
	end

	if (target :: Instance):GetAttribute("Sabotavel") ~= true then
		return false
	end

	local character = player.Character
	local rootPart = character and character:FindFirstChild("HumanoidRootPart")
	if not (rootPart and rootPart:IsA("BasePart")) then
		return false
	end

	local targetPosition = getTargetPosition(target :: Instance)
	if not targetPosition then
		return false
	end

	return (rootPart.Position - targetPosition).Magnitude <= MAX_SABOTAGE_DISTANCE
end

-- PLACEHOLDER: só marca o Attribute e loga no console. Substitua/expanda
-- aqui quando os objetivos de Rádio existirem (ex: desligar luzes,
-- travar porta, atrasar reparo).
local function applySabotage(player: Player, target: Instance)
	target:SetAttribute("Sabotado", true)
	print(string.format("[Sabotage] %s sabotou %s", player.Name, target:GetFullName()))
end

local function onSabotageAction(player: Player, target: unknown)
	if not MatchStateService.IsGameplayEnabled(player) then return end
	if player:GetAttribute("Role") ~= GameConfig.Roles.Spy then
		return
	end
	if player.Character and player.Character:GetAttribute("GrabLocked") == true then
		return
	end


	if isOnCooldown(player) then
		return
	end

	if not isValidTarget(player, target) then
		return
	end

	lastSabotageAt[player.UserId] = os.clock()
	applySabotage(player, target :: Instance)

	Remotes.CooldownUpdate:FireClient(player, "Sabotagem", os.time() + GameConfig.Spy.SabotageCooldownDefault)
end

--------------------------------------------------------------------------------
-- Reparo ("Fio Cortado" -- ver nota no cabeçalho)
--------------------------------------------------------------------------------

local function getPromptAnchor(target: Instance): BasePart?
	if target:IsA("BasePart") then
		return target
	elseif target:IsA("Model") then
		return (target :: Model).PrimaryPart or target:FindFirstChildWhichIsA("BasePart")
	end
	return nil
end

local function onRepairTriggered(player: Player, target: Instance)
	if player:GetAttribute("Role") ~= GameConfig.Roles.Survivor then
		return
	end
	if target:GetAttribute("Sabotado") ~= true then
		return
	end

	target:SetAttribute("Sabotado", false)
	print(string.format("[Sabotage] %s reparou %s", player.Name, target:GetFullName()))
end

-- Revalidada pelo minigame a cada tique: outro sobrevivente terminar o reparo
-- (ou o Espião desfazer a sabotagem) derruba a sessão de quem ficou pra trás.
local function canRepair(player: Player, target: Instance): (boolean, string?)
	if not MatchStateService.IsGameplayEnabled(player) then
		return false, "A partida ainda não começou."
	end
	if player:GetAttribute("Role") ~= GameConfig.Roles.Survivor then
		return false, "Só os Sobreviventes consertam o fio."
	end
	if target:GetAttribute("Sabotado") ~= true then
		return false, "O fio já foi consertado."
	end
	return true, nil
end

-- Id estável por ponto sabotado. Um contador, não Instance:GetDebugId() --
-- aquele é restrito a plugin e erraria num Script de servidor -- nem
-- GetFullName(), que dois irmãos de mesmo nome repetiriam.
local nextRepairId = 0

local function setupRepairPrompt(target: Instance)
	local anchor = getPromptAnchor(target)
	if not anchor or anchor:FindFirstChild("Reparar") then
		return
	end

	nextRepairId += 1
	local repairTaskId = string.format("SabotagemFio:%d", nextRepairId)

	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "Reparar"
	prompt.ActionText = "Reparar"
	prompt.ObjectText = "Fio Cortado"
	-- HoldDuration fica com o minigame (Bind zera). Fora dele o valor antigo
	-- de GameConfig.Spy.RepairHoldDuration continua sendo o que vale.
	prompt.HoldDuration = GameConfig.Spy.RepairHoldDuration
	prompt.Enabled = target:GetAttribute("Sabotado") == true
	prompt.Parent = anchor

	target:GetAttributeChangedSignal("Sabotado"):Connect(function()
		prompt.Enabled = target:GetAttribute("Sabotado") == true
		-- Ponto reparado/sabotado de novo: o progresso parcial não fica
		-- guardado de uma sabotagem pra outra.
		RepairMinigameSystem.ResetTask(repairTaskId)
	end)

	RepairMinigameSystem.Bind(prompt, {
		-- Um id por ponto sabotado: dois fios cortados no mapa são reparos
		-- independentes, e reparar junto no MESMO fio soma progresso.
		taskId = repairTaskId,
		configId = "SabotagemFio",
		part = anchor,
		range = MAX_SABOTAGE_DISTANCE,
		canStart = function(player)
			return canRepair(player, target)
		end,
		onComplete = function(player)
			onRepairTriggered(player, target)
		end,
	})
end

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
	Init()
	Assina o RemoteEvent SabotageAction, os prompts de reparo (existentes +
	futuros) e a limpeza de cooldown ao sair. Chame uma vez no boot do
	servidor.
]]
function SabotageSystem.Init()
	Remotes.SabotageAction.OnServerEvent:Connect(onSabotageAction)
	forEachTagged(Workspace, "Sabotavel", setupRepairPrompt)

	Players.PlayerRemoving:Connect(function(player)
		lastSabotageAt[player.UserId] = nil
	end)
end

return SabotageSystem
