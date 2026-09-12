--!strict
--[[
	SabotageSystem
	Processa pedidos de sabotagem do Espião (RemoteEvent SabotageAction,
	ver contrato em ReplicatedStorage/Modules/Remotes.lua).

	Fluxo atual (placeholder, até conectar aos objetivos de Rádio/Jangada):
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
-- aqui quando os objetivos de Rádio/Jangada existirem (ex: desligar luzes,
-- travar porta, atrasar reparo).
local function applySabotage(player: Player, target: Instance)
	target:SetAttribute("Sabotado", true)
	print(string.format("[Sabotage] %s sabotou %s", player.Name, target:GetFullName()))
end

local function onSabotageAction(player: Player, target: unknown)
	if player:GetAttribute("Role") ~= GameConfig.Roles.Spy then
		return
	end
	if player.Character and player.Character:GetAttribute("GrabLocked") == true then
		return
	end

	-- Amarrado (ConfrontSystem) bloqueia a sabotagem.
	if player:GetAttribute("Amarrado") == true then
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

local function setupRepairPrompt(target: Instance)
	local anchor = getPromptAnchor(target)
	if not anchor or anchor:FindFirstChild("Reparar") then
		return
	end

	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "Reparar"
	prompt.ActionText = "Reparar"
	prompt.ObjectText = "Fio Cortado"
	prompt.HoldDuration = GameConfig.Spy.RepairHoldDuration
	prompt.Enabled = target:GetAttribute("Sabotado") == true
	prompt.Parent = anchor

	target:GetAttributeChangedSignal("Sabotado"):Connect(function()
		prompt.Enabled = target:GetAttribute("Sabotado") == true
	end)

	prompt.Triggered:Connect(function(player)
		onRepairTriggered(player, target)
	end)
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
