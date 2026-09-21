--!strict
--[[
	ConfrontSystem
	As três formas de os jogadores lidarem com um suspeito.

	PARTE 1 -- DETECTAR (Tool "CristalAncestral")
	  Cliente dispara DetectSuspect:FireServer(target). Se quem pediu estiver
	  com a Tool equipada (Attribute "CristalAncestral" == true) e o alvo
	  estiver dentro de GameConfig.Confront.DetectRange, o servidor responde
	  SÓ para quem pediu, via DetectSuspect:FireClient(caller, target, isSpy).
	  Ninguém mais recebe a leitura.

	PARTE 2 -- AMARRAR (cooperativo, 2 jogadores)
	  Todo character ganha um ProximityPrompt "Amarrar" (criado no servidor,
	  então todos veem). Acionar o prompt registra o jogador como ajudante do
	  alvo por GameConfig.Confront.TieAssistWindow segundos. Quando há
	  TieHelpersRequired (2) ajudantes ativos ao mesmo tempo, começa a contagem
	  de TieHoldDuration (5s); se a dupla continuar ativa e no alcance até o
	  fim, o alvo é amarrado.

	  Usei "aciona o prompt e fica valendo por uma janela" em vez de segurar
	  o botão (o pedido permite "lógica equivalente"). Motivo: com HoldDuration
	  do próprio prompt, quem começou primeiro termina o próprio hold antes do
	  parceiro e a sobreposição quebra sozinha -- dá pra travar num ciclo em
	  que a dupla nunca completa se um começou alguns segundos depois do outro.

	  Amarrado: Attribute "Amarrado" == true no Player, WalkSpeed 0, e
	  sabotagem/habilidade letal bloqueadas (as checagens ficam em
	  SabotageSystem.lua e LethalAbility.lua). Solta sozinho depois de
	  GameConfig.Effects.AmarradoDuration (90s).

	  A amarração depende da cooperação dos ajudantes ativos; materiais da
	  objetivos antigos não fazem mais parte desse fluxo.

	PARTE 3 -- EXECUTAR (Tool "ArmaRara" = Lança Ancestral, ver ItemRegistry)
	  Cliente dispara ConfrontKill:FireServer(target). Com a arma equipada e
	  o alvo vivo dentro de KillRange, o alvo é executado pelo DamageSystem
	  e PlayerKilled é disparado com cause
	  "Confronto". Se o alvo NÃO era o Espião, dispara também o hook
	  ConfrontSystem.PunicaoInocente -- por enquanto ninguém escuta.

	  MONSTRO: só pode ser executado enquanto estiver enfraquecido pela luz
	  (MonsterLightWeakness.IsWeakened) -- a Lança Ancestral "só mata o
	  Monstro depois de enfraquecê-lo", não a qualquer momento. Espião não
	  tem essa restrição.

	NOTA DE ESCOPO: nem amarrar nem executar são restritos por Role, porque o
	pedido não restringiu. Qualquer jogador pode amarrar ou executar qualquer
	outro (inclusive o Monstro executando alguém, se alguém der um ArmaRara
	pra ele). Fácil de restringir depois.

	IMPORTANTE (setup no Studio, fora do escopo deste script):
	  - Tool com Attribute "CristalAncestral" = true.
	  - Tool com Attribute "ArmaRara" = true (Lança Ancestral -- hoje colocada
	    nas Ruínas Antigas por Tools/IslandGenerator.lua).

	Uso (chamar uma vez no boot do servidor):
		local ConfrontSystem = require(script.ConfrontSystem)
		ConfrontSystem.Init()

	Hook pra outros sistemas conectarem depois:
		ConfrontSystem.PunicaoInocente.Event:Connect(function(killer, victim) ... end)
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage.Modules.GameConfig)
local Remotes = require(ReplicatedStorage.Modules.Remotes)
local AssetRegistry = require(ReplicatedStorage.Modules.AssetRegistry)
local SafeAttribute = require(ReplicatedStorage.Modules.SafeAttribute)
local Elimination = require(script.Parent.Elimination)
local DamageSystem = require(script.Parent.DamageSystem)
local SoundManager = require(script.Parent.SoundManager)
local MonsterLightWeakness = require(script.Parent.MonsterLightWeakness)

local ConfrontSystem = {}
local PowerStatus = require(script.Parent.SurvivorPowerStatus)

-- Hook público: disparado quando alguém executa um inocente.
ConfrontSystem.PunicaoInocente = Instance.new("BindableEvent")

type TieAttempt = {
	helpers: { [Player]: number }, -- ajudante -> os.clock() do registro
	running: boolean, -- já existe uma contagem de 5s em andamento?
}

-- alvo -> tentativa de amarração em andamento.
local tieAttempts: { [Player]: TieAttempt } = {}

-- alvo amarrado -> WalkSpeed que ele tinha antes de ser amarrado.
local tiedBaseWalkSpeed: { [Player]: number } = {}

--------------------------------------------------------------------------------
-- Helpers comuns
--------------------------------------------------------------------------------

local function getRootPart(player: Player): BasePart?
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		return root
	end
	return nil
end

local function isWithin(a: Player, b: Player, maxDistance: number): boolean
	local rootA, rootB = getRootPart(a), getRootPart(b)
	if not (rootA and rootB) then
		return false
	end
	return (rootA.Position - rootB.Position).Magnitude <= maxDistance
end

-- Tool equipada fica como filha do Character (não da Backpack).
local function hasEquippedTool(player: Player, attributeName: string): boolean
	local character = player.Character
	if not character then
		return false
	end

	for _, child in character:GetChildren() do
		if child:IsA("Tool") and SafeAttribute.Get(child, attributeName) == true then
			return true
		end
	end

	return false
end

-- Valida o argumento cru vindo de um remote: precisa ser um Player que não
-- seja quem chamou.
local function toTargetPlayer(caller: Player, target: unknown): Player?
	if typeof(target) ~= "Instance" or not (target :: Instance):IsA("Player") then
		return nil
	end

	local targetPlayer = target :: Player
	if targetPlayer == caller then
		return nil
	end

	return targetPlayer
end

--------------------------------------------------------------------------------
-- PARTE 1 -- Detectar com o Cristal Ancestral
--------------------------------------------------------------------------------

local function onDetectSuspect(caller: Player, target: unknown)
	if caller.Character and caller.Character:GetAttribute("GrabLocked") == true then
		return
	end
	local targetPlayer = toTargetPlayer(caller, target)
	if not targetPlayer then
		return
	end

	if not hasEquippedTool(caller, AssetRegistry.CristalAncestral_Modelo.AttributeName) then
		return
	end

	if not isWithin(caller, targetPlayer, GameConfig.Confront.DetectRange) then
		return
	end

	local isSpy = targetPlayer:GetAttribute("Role") == GameConfig.Roles.Spy
	Remotes.DetectSuspect:FireClient(caller, targetPlayer, isSpy)
end

--------------------------------------------------------------------------------
-- PARTE 2 -- Amarrar (cooperativo)
--------------------------------------------------------------------------------

local function releaseTie(target: Player)
	if target:GetAttribute("Amarrado") ~= true then
		return
	end

	target:SetAttribute("Amarrado", false)

	local baseWalkSpeed = tiedBaseWalkSpeed[target]
	tiedBaseWalkSpeed[target] = nil

	local character = target.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if humanoid and baseWalkSpeed then
		humanoid.WalkSpeed = baseWalkSpeed
	end

	Remotes.PlayerRestrained:FireAllClients(target.UserId, false)
	print(string.format("[ConfrontSystem] %s foi solto.", target.Name))
end

local function applyTie(target: Player)
	if target:GetAttribute("Amarrado") == true then
		return
	end

	local character = target.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		tiedBaseWalkSpeed[target] = humanoid.WalkSpeed
		humanoid.WalkSpeed = 0
	end

	target:SetAttribute("Amarrado", true)

	local duration = GameConfig.Effects.AmarradoDuration
	Remotes.PlayerRestrained:FireAllClients(target.UserId, true, os.time() + duration)
	print(string.format("[ConfrontSystem] %s foi amarrado por %ds.", target.Name, duration))

	local rootPart = character and character:FindFirstChild("HumanoidRootPart")
	if rootPart and rootPart:IsA("BasePart") then
		SoundManager.PlayRestrainSound(rootPart.Position)
	end

	task.delay(duration, function()
		releaseTie(target)
	end)
end

-- Remove ajudantes que expiraram, saíram do jogo ou se afastaram, e devolve
-- quantos continuam valendo.
local function countActiveHelpers(attempt: TieAttempt, target: Player): number
	local now = os.clock()
	local count = 0

	for helper, registeredAt in attempt.helpers do
		local expired = (now - registeredAt) > GameConfig.Confront.TieAssistWindow
		local gone = helper.Parent == nil or Elimination.IsEliminated(helper)
		local tooFar = not isWithin(helper, target, GameConfig.Confront.TieRange)

		if expired or gone or tooFar then
			attempt.helpers[helper] = nil
		else
			count += 1
		end
	end

	return count
end

local function onAmarrarTriggered(target: Player, helper: Player)
	if helper == target then
		return
	end

	if target:GetAttribute("Amarrado") == true then
		return
	end

	if Elimination.IsEliminated(target) or Elimination.IsEliminated(helper) then
		return
	end

	if not isWithin(helper, target, GameConfig.Confront.TieRange) then
		return
	end

	local attempt = tieAttempts[target]
	if not attempt then
		attempt = { helpers = {}, running = false }
		tieAttempts[target] = attempt
	end
	attempt.helpers[helper] = os.clock()

	if attempt.running then
		return
	end

	if countActiveHelpers(attempt, target) < GameConfig.Confront.TieHelpersRequired then
		return
	end

	attempt.running = true
	print(string.format("[ConfrontSystem] Amarração de %s iniciada.", target.Name))

	task.delay(GameConfig.Confront.TieHoldDuration, function()
		local current = tieAttempts[target]
		if current ~= attempt then
			return -- tentativa foi descartada no meio do caminho
		end
		attempt.running = false

		if target:GetAttribute("Amarrado") == true then
			return
		end

		if countActiveHelpers(attempt, target) < GameConfig.Confront.TieHelpersRequired then
			print(string.format("[ConfrontSystem] Amarração de %s falhou: ajuda insuficiente.", target.Name))
			return
		end

		tieAttempts[target] = nil
		applyTie(target)
	end)
end

local function setupAmarrarPrompt(target: Player, character: Model)
	local root = character:WaitForChild("HumanoidRootPart", 10)
	if not root or not root:IsA("BasePart") then
		return
	end

	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "Amarrar"
	prompt.ActionText = "Amarrar"
	prompt.ObjectText = target.Name
	prompt.KeyboardKeyCode = GameConfig.Confront.TieInputKey
	prompt.GamepadKeyCode = GameConfig.Confront.TieGamepadKey
	prompt.MaxActivationDistance = GameConfig.Confront.TieRange
	prompt.RequiresLineOfSight = false
	prompt.Parent = root

	prompt.Triggered:Connect(function(helper)
		onAmarrarTriggered(target, helper)
	end)
end

--------------------------------------------------------------------------------
-- PARTE 3 -- Executar com a Arma Rara
--------------------------------------------------------------------------------

local function onConfrontKill(killer: Player, target: unknown)
	if killer.Character and killer.Character:GetAttribute("PowerStunned") == true then return end
	if killer.Character and killer.Character:GetAttribute("GrabLocked") == true then return end
	local targetPlayer = toTargetPlayer(killer, target)
	if not targetPlayer then
		return
	end

	if not hasEquippedTool(killer, AssetRegistry.ArmaRara_Item.AttributeName) then
		return
	end

	if Elimination.IsEliminated(targetPlayer) then
		return
	end

	if not isWithin(killer, targetPlayer, GameConfig.Confront.KillRange) then
		return
	end

	-- Monstro só morre enfraquecido pela luz; Espião não tem essa restrição.
	if targetPlayer:GetAttribute("Role") == GameConfig.Roles.Monster then
		local targetCharacter = targetPlayer.Character
		if not targetCharacter or not MonsterLightWeakness.IsWeakened(targetCharacter) then
			return
		end
	end

	local wasSpy = targetPlayer:GetAttribute("Role") == GameConfig.Roles.Spy
	local targetRoot = targetPlayer.Character and targetPlayer.Character:FindFirstChild("HumanoidRootPart")

	if targetPlayer.Character and PowerStatus.BlockAttack(targetPlayer.Character) then return end
	if not DamageSystem.Execute(targetPlayer, { Source = killer, Cause = "Confronto" }) then
		return
	end
	print(string.format("[ConfrontSystem] %s executou %s.", killer.Name, targetPlayer.Name))

	if targetRoot and targetRoot:IsA("BasePart") then
		SoundManager.PlayDeathSound(targetRoot.Position)
	end

	if not wasSpy then
		print(string.format("[ConfrontSystem] %s era inocente -- punição disparada.", targetPlayer.Name))
		ConfrontSystem.PunicaoInocente:Fire(killer, targetPlayer)
	end
end

--------------------------------------------------------------------------------
-- Ciclo de vida
--------------------------------------------------------------------------------

local function watchPlayer(player: Player)
	player.CharacterAdded:Connect(function(character)
		setupAmarrarPrompt(player, character)

		-- Amarrado sobrevive ao respawn (o Attribute fica no Player), então
		-- o character novo precisa nascer travado também.
		if player:GetAttribute("Amarrado") == true then
			local humanoid = character:FindFirstChildOfClass("Humanoid")
				or character:WaitForChild("Humanoid", 10) :: Humanoid?
			if humanoid then
				tiedBaseWalkSpeed[player] = tiedBaseWalkSpeed[player] or humanoid.WalkSpeed
				humanoid.WalkSpeed = 0
			end
		end
	end)

	if player.Character then
		setupAmarrarPrompt(player, player.Character)
	end
end

--[[
	Init()
	Assina os remotes das partes 1 e 3 e prepara os prompts de amarrar.
	Chame uma vez no boot do servidor.
]]
function ConfrontSystem.Init()
	Remotes.DetectSuspect.OnServerEvent:Connect(onDetectSuspect)
	Remotes.ConfrontKill.OnServerEvent:Connect(onConfrontKill)

	Players.PlayerAdded:Connect(watchPlayer)
	for _, player in Players:GetPlayers() do
		watchPlayer(player)
	end

	Players.PlayerRemoving:Connect(function(player)
		tieAttempts[player] = nil
		tiedBaseWalkSpeed[player] = nil

		for _, attempt in tieAttempts do
			attempt.helpers[player] = nil
		end
	end)
end

return ConfrontSystem
