--!strict
--[[
	LethalAbility
	Processa o uso da habilidade letal do Espião (RemoteEvent
	LethalAbilityUsed, ver contrato em ReplicatedStorage/Modules/Remotes.lua).

	Fluxo atual: cliente dispara LethalAbilityUsed:FireServer(targetPlayer)
	-> se o jogador for Espiao, o alvo estiver a até
	8 studs, não estiver já eliminado e o cooldown
	(GameConfig.Spy.LethalCooldown = 180s) já tiver passado, o servidor:
	    1) executa o alvo pelo DamageSystem (vida, animação e eliminação),
	    2) dispara PlayerKilled(vítima, autor, causa) para todos os clientes,
	    3) reinicia o cooldown do Espião.

	Qualquer falha de validação (não é Espiao, alvo fora de alcance, alvo já
	eliminado, cooldown ainda ativo) é rejeitada em silêncio.

	Uso (chamar uma vez no boot do servidor):
		local LethalAbility = require(script.LethalAbility)
		LethalAbility.Init()
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage.Modules.GameConfig)
local Remotes = require(ReplicatedStorage.Modules.Remotes)
local Elimination = require(script.Parent.Elimination)
local DamageSystem = require(script.Parent.DamageSystem)
local SoundManager = require(script.Parent.SoundManager)
local PowerStatus = require(script.Parent.SurvivorPowerStatus)
local MatchStateService = require(script.Parent.MatchStateService)

local LethalAbility = {}

-- Alcance da habilidade letal, em studs.
local MAX_LETHAL_RANGE = 8

-- player.UserId -> os.clock() do último uso bem-sucedido.
local lastLethalAt: { [number]: number } = {}

local function isOnCooldown(player: Player): boolean
	local last = lastLethalAt[player.UserId]
	if not last then
		return false
	end

	return (os.clock() - last) < GameConfig.Spy.LethalCooldown
end

local function isValidTarget(caster: Player, target: unknown): boolean
	if typeof(target) ~= "Instance" or not (target :: Instance):IsA("Player") then
		return false
	end

	local targetPlayer = target :: Player
	if targetPlayer == caster then
		return false
	end

	local casterCharacter = caster.Character
	local targetCharacter = targetPlayer.Character
	if not (casterCharacter and targetCharacter) then
		return false
	end

	if Elimination.IsEliminated(targetPlayer) then
		return false
	end

	local casterRoot = casterCharacter:FindFirstChild("HumanoidRootPart")
	local targetRoot = targetCharacter:FindFirstChild("HumanoidRootPart")
	if not (casterRoot and casterRoot:IsA("BasePart") and targetRoot and targetRoot:IsA("BasePart")) then
		return false
	end

	return (casterRoot.Position - targetRoot.Position).Magnitude <= MAX_LETHAL_RANGE
end

local function onLethalAbilityUsed(caster: Player, target: unknown)
	if not MatchStateService.IsGameplayEnabled(caster) then return end
	if caster.Character and caster.Character:GetAttribute("PowerStunned") == true then return end
	if caster.Character and caster.Character:GetAttribute("GrabLocked") == true then return end
	if caster:GetAttribute("Role") ~= GameConfig.Roles.Spy then
		return
	end

	if isOnCooldown(caster) then
		return
	end

	if not isValidTarget(caster, target) then
		return
	end

	local targetPlayer = target :: Player
	local targetRoot = targetPlayer.Character and targetPlayer.Character:FindFirstChild("HumanoidRootPart")

	lastLethalAt[caster.UserId] = os.clock()
	if targetPlayer.Character and PowerStatus.BlockAttack(targetPlayer.Character) then
		Remotes.CooldownUpdate:FireClient(caster, "HabilidadeLetal", os.time() + GameConfig.Spy.LethalCooldown)
		return
	end
	local executed = DamageSystem.Execute(targetPlayer, { Source = caster, Cause = GameConfig.Roles.Spy })
	if not executed then
		return
	end
	Remotes.CooldownUpdate:FireClient(caster, "HabilidadeLetal", os.time() + GameConfig.Spy.LethalCooldown)

	if targetRoot and targetRoot:IsA("BasePart") then
		SoundManager.PlayDeathSound(targetRoot.Position)
	end
end

--[[
	Init()
	Assina o RemoteEvent LethalAbilityUsed e a limpeza de cooldown ao sair.
	Chame uma vez no boot do servidor.
]]
function LethalAbility.Init()
	Remotes.LethalAbilityUsed.OnServerEvent:Connect(onLethalAbilityUsed)

	Players.PlayerRemoving:Connect(function(player)
		lastLethalAt[player.UserId] = nil
	end)
end

return LethalAbility
