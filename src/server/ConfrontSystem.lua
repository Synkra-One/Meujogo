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

	PARTE 2 -- EXECUTAR (Tool "ArmaRara" = Lança Ancestral, ver ItemRegistry)
	  Cliente dispara ConfrontKill:FireServer(target). Com a arma equipada e
	  o alvo vivo dentro de KillRange, o alvo é executado pelo DamageSystem
	  e PlayerKilled é disparado com cause
	  "Confronto". Se o alvo NÃO era o Espião, dispara também o hook
	  ConfrontSystem.PunicaoInocente -- por enquanto ninguém escuta.

	  MONSTRO: só pode ser executado enquanto estiver enfraquecido pela luz
	  (MonsterLightWeakness.IsWeakened) -- a Lança Ancestral "só mata o
	  Monstro depois de enfraquecê-lo", não a qualquer momento. Espião não
	  tem essa restrição.

	NOTA DE ESCOPO: a execução não é restrita por Role. Qualquer jogador pode
	executar qualquer outro se tiver a arma válida.

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

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage.Modules.GameConfig)
local Remotes = require(ReplicatedStorage.Modules.Remotes)
local AssetRegistry = require(ReplicatedStorage.Modules.AssetRegistry)
local SafeAttribute = require(ReplicatedStorage.Modules.SafeAttribute)
local Elimination = require(script.Parent.Elimination)
local DamageSystem = require(script.Parent.DamageSystem)
local SoundManager = require(script.Parent.SoundManager)
local MonsterLightWeakness = require(script.Parent.MonsterLightWeakness)
local MatchStateService = require(script.Parent.MatchStateService)

local ConfrontSystem = {}
local PowerStatus = require(script.Parent.SurvivorPowerStatus)

-- Hook público: disparado quando alguém executa um inocente.
ConfrontSystem.PunicaoInocente = Instance.new("BindableEvent")

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
	if not MatchStateService.IsGameplayEnabled(caller) then return end
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
-- PARTE 2 -- Executar com a Arma Rara
--------------------------------------------------------------------------------

local function onConfrontKill(killer: Player, target: unknown)
	if not MatchStateService.IsGameplayEnabled(killer) then return end
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

--[[
	Init()
	Assina os remotes de detecção e execução.
	Chame uma vez no boot do servidor.
]]
function ConfrontSystem.Init()
	Remotes.DetectSuspect.OnServerEvent:Connect(onDetectSuspect)
	Remotes.ConfrontKill.OnServerEvent:Connect(onConfrontKill)
end

return ConfrontSystem
