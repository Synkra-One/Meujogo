--!strict
--[[
	MonsterCombat
	O Monstro finalmente tem dentes. Este módulo é o dono de:

	  1. GOLPE  -- client/MonsterController pede (Remotes.MonsterAttack:FireServer,
	     botão esquerdo). O servidor valida (é o Monstro, vivo, partida ativa,
	     vivo, cooldown passou), faz um hitbox em CONE à frente do
	     HumanoidRootPart e roteia o dano por DamageSystem.Apply
	     (Cause = "Monstro"). 3 golpes limpos matam um Sobrevivente (100 HP).

	  2. VELOCIDADE -- o Monstro precisa alcançar quem foge. Como o script
	     Crouching (pacote de movimento) é o dono do WalkSpeed e o reescreve
	     todo frame, aqui a gente só publica o Attribute "MonsterSpeedMul" no
	     character; o Crouching multiplica por ele. Fora do Monstro o atributo
	     não existe (multiplicador 1).

	INTEGRAÇÃO COM A FRAQUEZA À LUZ (MonsterLightWeakness):
	  enquanto MonsterLightWeakness.IsWeakened(character) for true, o Monstro
	  anda a GameConfig.Monster.WeakenedSpeedMultiplier e o golpe sai com
	  GameConfig.Monster.Attack.WeakenedDamageMul do dano. Zona Segura / Tocha
	  viram counterplay de verdade sem desligar o Monstro por completo.

	ALVOS: Sobreviventes E o Espião (o Espião está disfarçado, mas o Monstro
	não sabe quem é -- e mecanicamente o Monstro quer todo mundo morto menos
	ele). O próprio Monstro nunca é alvo.

	ANTI-CHEAT: o cliente só PEDE o golpe; alcance, cone, cooldown, dano e
	morte são todos decididos aqui. O knockback da vítima é aplicado no
	cliente DELA (network ownership), então o servidor só manda a direção.

	Uso (uma vez no boot, DEPOIS de DamageSystem.Init()):
		require(script.MonsterCombat).Init()
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local FlashlightRules = require(ReplicatedStorage.Modules.FlashlightRules)

local GameConfig = require(ReplicatedStorage.Modules.GameConfig)
local Remotes = require(ReplicatedStorage.Modules.Remotes)

local DamageSystem = require(script.Parent.DamageSystem)
local Elimination = require(script.Parent.Elimination)
local RoundManager = require(script.Parent.RoundManager)
local MonsterLightWeakness = require(script.Parent.MonsterLightWeakness)

local MonsterCombat = {}
local initialized = false

local CFG = GameConfig.Monster
local ATK = CFG.Attack

type Candidate = { player: Player, root: BasePart, dist: number }

-- player -> os.clock() do último golpe aceito (gate do cooldown no servidor).
local lastAttackAt: { [Player]: number } = {}

--------------------------------------------------------------------------------
-- Helpers
--------------------------------------------------------------------------------

local function isMonster(player: Player): boolean
	return player:GetAttribute("Role") == GameConfig.Roles.Monster
end

local function isTarget(player: Player): boolean
	local role = player:GetAttribute("Role")
	return role == GameConfig.Roles.Survivor or role == GameConfig.Roles.Spy
end

local function livingCharacter(player: Player): (Model?, Humanoid?, BasePart?)
	local character = player.Character
	if not character or Elimination.IsEliminated(player) then
		return nil, nil, nil
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local root = character:FindFirstChild("HumanoidRootPart")
	if not humanoid or humanoid.Health <= 0 or not root or not root:IsA("BasePart") then
		return nil, nil, nil
	end
	return character, humanoid, root
end

--------------------------------------------------------------------------------
-- Golpe
--------------------------------------------------------------------------------

local function onAttackRequest(player: Player)
	if not RoundManager.IsRoundActive() or not isMonster(player)
		or player:GetAttribute("InRound") ~= true or player:GetAttribute("InWaitingRoom") == true then
		return
	end

	local character, _, monsterRoot = livingCharacter(player)
	if not character or not monsterRoot then
		return
	end
	if FlashlightRules.PowerBlocked(character) then return end

	-- Durante o teleporte (server/MonsterTeleport) o Monstro não ataca: está
	-- abrindo/atravessando/saindo da fenda. TeleportBusy é Attribute do
	-- character, setado pelo servidor.
	if character:GetAttribute("TeleportBusy") == true or character:GetAttribute("ShadowRushBusy") == true
		or character:GetAttribute("GrabLocked") == true then
		return
	end

	local now = os.clock()
	local last = lastAttackAt[player]
	if last and (now - last) < ATK.Cooldown then
		return -- ainda no cooldown (o cliente também segura, isto é a rede de segurança)
	end
	lastAttackAt[player] = now

	local weakened = MonsterLightWeakness.IsWeakened(character)
	local damage = ATK.Damage * (weakened and ATK.WeakenedDamageMul or 1)

	-- Hitbox: cone à frente. Junta os candidatos e ordena por distância.
	local origin = monsterRoot.Position
	local forward = monsterRoot.CFrame.LookVector
	local candidates: { Candidate } = {}
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { character }
	params.IgnoreWater = true

	for _, other in Players:GetPlayers() do
		if other == player or not isTarget(other) or other:GetAttribute("InRound") ~= true
			or other:GetAttribute("InWaitingRoom") == true then
			continue
		end
		local _, _, otherRoot = livingCharacter(other)
		if not otherRoot then
			continue
		end
		local offset = otherRoot.Position - origin
		local dist = offset.Magnitude
		if dist < 0.01 or dist > ATK.Range then
			continue
		end
		if offset.Unit:Dot(forward) < ATK.ConeCos then
			continue -- fora do cone: o Monstro precisa MIRAR
		end
		local hit = workspace:Raycast(origin, offset, params)
		if hit and not hit.Instance:IsDescendantOf(other.Character :: Model) then continue end
		table.insert(candidates, { player = other, root = otherRoot, dist = dist })
	end

	table.sort(candidates, function(a, b)
		return a.dist < b.dist
	end)

	local hits = 0
	for index, cand in candidates do
		if index > ATK.MaxHitsPerSwing then
			break
		end
		local applied = DamageSystem.Apply(cand.player, damage, { Source = player, Cause = "Monstro" })
		if applied > 0 then
			hits += 1
			-- Knockback no cliente da vítima (ela é a dona da física do
			-- próprio character; velocity setada no servidor não gruda).
			Remotes.MonsterAttack:FireClient(cand.player, "knockback", origin)
		end
	end

	-- Feedback pro Monstro: confirma o golpe (o cliente aplica o lunge) e
	-- diz quantos conectou (kick de câmera + som só se hits > 0).
	Remotes.MonsterAttack:FireClient(player, "confirm", hits)
end

--------------------------------------------------------------------------------
-- Velocidade do Monstro (Attribute lido pelo Crouching do pacote)
--------------------------------------------------------------------------------

local SPEED_TICK = 0.2

local function speedStep()
	local roundActive = RoundManager.IsRoundActive()

	for _, player in Players:GetPlayers() do
		local character = player.Character
		if not character then
			continue
		end

		local shouldBoost = roundActive and isMonster(player) and not Elimination.IsEliminated(player)
		if not shouldBoost then
			if character:GetAttribute("MonsterSpeedMul") ~= nil then
				character:SetAttribute("MonsterSpeedMul", nil)
			end
			continue
		end

		local mul = MonsterLightWeakness.IsWeakened(character) and CFG.WeakenedSpeedMultiplier or CFG.SpeedMultiplier
		local flashlightSlow = character:GetAttribute("FlashlightSlow")
		if type(flashlightSlow) == "number" then mul *= 1 - math.clamp(flashlightSlow, 0, 1) end
		if character:GetAttribute("MonsterSpeedMul") ~= mul then
			character:SetAttribute("MonsterSpeedMul", mul)
		end
	end
end

--------------------------------------------------------------------------------
-- Init
--------------------------------------------------------------------------------

function MonsterCombat.Init()
	if initialized then return end
	initialized = true
	Remotes.MonsterAttack.OnServerEvent:Connect(onAttackRequest)

	Players.PlayerRemoving:Connect(function(player)
		lastAttackAt[player] = nil
	end)

	-- Zera o cooldown a cada partida nova (personagem novo, sem histórico).
	RoundManager.RoundPrepared.Event:Connect(function()
		table.clear(lastAttackAt)
	end)

	local acc = 0
	RunService.Heartbeat:Connect(function(dt)
		acc += dt
		if acc < SPEED_TICK then
			return
		end
		acc = 0
		speedStep()
	end)
end

return MonsterCombat
