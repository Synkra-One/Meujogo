--!strict
--[[
	DamageSystem
	Porta ÚNICA de dano e cura de "Náufragos". Todo sistema que quiser tirar
	ou devolver vida chama DamageSystem.Apply / DamageSystem.Heal em vez de
	mexer em Humanoid.Health direto -- assim as regras (invulnerabilidade,
	já-eliminado, spawn protection, morte -> Elimination + PlayerKilled,
	atraso de regeneração) ficam num lugar só.

	HOJE quem usa:
	  - OTSFirearmService.lua  (dano da Glock17 -- a armadura continua lá,
	    só o TakeDamage final + a morte passam por aqui)
	  - WeaponSystem.lua   (Faca/Lança/Pedra: só se GameConfig.Weapons.*Damage
	    for > 0 -- por padrão continuam sendo só empurrão)
	  - UtilityItemSystem.lua (Chocolate cura pelo Heal)

	MORTE: quando Health chega a 0, o character ganha um BoolValue "Dead"
	(mesmo marcador que o sistema OTS usa), e se for um Player:
	Elimination.Eliminate + Remotes.PlayerKilled:FireAllClients(vítima, autor,
	causa). Apply devolve (danoAplicado, morreuAgora) pra quem chamou poder
	disparar o feedback específico da arma (kill feed etc).

	GUARDAS (Apply não faz nada e devolve 0 se):
	  - alvo sem Humanoid, ou Humanoid.Health <= 0
	  - character com Attribute "Eliminado" (Elimination) ou BoolValue "Dead"
	  - character com Attribute "Invulneravel" == true
	  - Humanoid com ForceField (spawn protection -- TakeDamage já ignora,
	    aqui a gente nem registra o "tomou dano" pra regen)

	REGENERAÇÃO: a do Roblox (script "Health", 1%/s) é desligada no spawn
	(GameConfig.Health.DisableRobloxDefaultRegen). Em vez dela, um loop aqui
	regenera GameConfig.Health.RegenPerSecond por segundo, mas só depois de
	RegenDelayAfterDamage segundos sem tomar dano.

	Uso (uma vez no boot do servidor, ANTES de OTSFirearmService/WeaponSystem):
		local DamageSystem = require(script.DamageSystem)
		DamageSystem.Init()
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage.Modules.GameConfig)
local Remotes = require(ReplicatedStorage.Modules.Remotes)
local StatScaling = require(ReplicatedStorage.Modules.StatScaling)
local Elimination = require(script.Parent.Elimination)
local PowerStatus = require(script.Parent.SurvivorPowerStatus)

local DamageSystem = {}

export type DamageInfo = {
	Source: Player?, -- quem causou (pra PlayerKilled e futuras regras de time)
	Cause: string?, -- texto da causa ("Tiro", "Monstro", "Ambiente"...)
	Empowered: boolean?, -- server-only token consumed when a validated attack begins
	MaxDamage: number?, -- server-only ceiling after stat multipliers (utility effects)
}

-- character -> os.clock() do último dano tomado (gate da regeneração).
local lastDamageAt: { [Model]: number } = {}

type FallState = {
	player: Player,
	humanoid: Humanoid,
	root: BasePart,
	active: boolean,
	startY: number,
	peakY: number,
	startedAt: number,
	lastAppliedAt: number,
}

local fallStates: { [Model]: FallState } = {}

-- Uma única reação autoritativa por character. Animações iniciadas no
-- servidor replicam para vítima e atacante; isso evita cada tela decidir um
-- estado diferente a partir do próprio HealthChanged.
local reactionTracks: { [Model]: AnimationTrack } = {}
local reactionAnimationIds: { [Model]: string } = {}
local hurtHealthConnections: { [Model]: RBXScriptConnection } = {}
local hurtMovingStates: { [Model]: boolean } = {}

local function stopReactionTrack(model: Model, fadeTime: number)
	local previous = reactionTracks[model]
	reactionTracks[model] = nil
	reactionAnimationIds[model] = nil
	if not previous then
		return
	end
	pcall(function()
		previous:Stop(fadeTime)
		previous:Destroy()
	end)
end

local function stopReaction(model: Model, fadeTime: number)
	local healthConnection = hurtHealthConnections[model]
	if healthConnection then
		hurtHealthConnections[model] = nil
		healthConnection:Disconnect()
	end
	hurtMovingStates[model] = nil
	stopReactionTrack(model, fadeTime)
end

local function playReaction(model: Model, humanoid: Humanoid, animationId: string, priority: Enum.AnimationPriority, looped: boolean?): boolean
	if animationId == "" or animationId == "rbxassetid://0" then
		return false
	end

	local current = reactionTracks[model]
	if current and reactionAnimationIds[model] == animationId and current.IsPlaying then
		return true
	end

	-- Trocar HurtIdle por HurtWalk nao pode desconectar o observador de vida.
	-- So a trilha e substituida; o estado Hurt continua ativo.
	stopReactionTrack(model, 0.08)

	local animator = humanoid:FindFirstChildOfClass("Animator")
	if not animator then
		animator = Instance.new("Animator")
		animator.Parent = humanoid
	end

	local animation = Instance.new("Animation")
	animation.AnimationId = animationId
	local ok, loaded = pcall(function()
		return animator:LoadAnimation(animation)
	end)
	animation:Destroy()
	if not ok or not loaded then
		warn("[DamageSystem] Não foi possível carregar a animação de combate " .. animationId)
		return false
	end

	local track = loaded :: AnimationTrack
	track.Priority = priority
	track.Looped = looped == true
	reactionTracks[model] = track
	reactionAnimationIds[model] = animationId
	track.Stopped:Once(function()
		if reactionTracks[model] == track then
			reactionTracks[model] = nil
			reactionAnimationIds[model] = nil
		end
		track:Destroy()
	end)
	track:Play(0.06)
	return true
end

local function isHurtMoving(model: Model, wasMoving: boolean?): boolean
	local root = model:FindFirstChild("HumanoidRootPart")
	local speed = if root and root:IsA("BasePart")
		then (root.AssemblyLinearVelocity * Vector3.new(1, 0, 1)).Magnitude
		else 0
	-- Histerese evita piscar entre Idle/Walk quando o corpo termina de frear
	-- ou escorrega alguns centimetros numa encosta.
	return speed > (if wasMoving == true then 0.75 else 1.5)
end

local function playHurtReaction(model: Model, humanoid: Humanoid)
	local moving = isHurtMoving(model, hurtMovingStates[model])
	local animationId = if moving
		then GameConfig.Health.HurtWalkAnimationId
		else GameConfig.Health.HurtIdleAnimationId
	if playReaction(model, humanoid, animationId, Enum.AnimationPriority.Action2, true) then
		hurtMovingStates[model] = moving
		model:SetAttribute("CombatAnimationState", "Hurt")
		if not hurtHealthConnections[model] then
			hurtHealthConnections[model] = humanoid.HealthChanged:Connect(function(newHealth: number)
				if newHealth <= 0 then
					return
				end
				if newHealth >= humanoid.MaxHealth - 0.01 then
					model:SetAttribute("CombatAnimationState", nil)
					stopReaction(model, 0.08)
				end
			end)
		end
	end
end

local function playDeathReaction(model: Model, humanoid: Humanoid)
	stopReaction(model, 0.05)
	model:SetAttribute("CombatAnimationState", "Death")
	playReaction(model, humanoid, GameConfig.Health.DeathAnimationId, Enum.AnimationPriority.Action4)
end

local function refreshHurtReactions()
	for model, wasMoving in hurtMovingStates do
		local humanoid = model:FindFirstChildOfClass("Humanoid")
		if not model.Parent or not humanoid or humanoid.Health <= 0
			or model:GetAttribute("CombatAnimationState") ~= "Hurt" then
			stopReaction(model, 0.05)
			continue
		end

		local moving = isHurtMoving(model, wasMoving)
		if moving ~= wasMoving or not reactionTracks[model] then
			playHurtReaction(model, humanoid)
		end
	end
end

--------------------------------------------------------------------------------
-- Resolução de alvo
--------------------------------------------------------------------------------

local function resolveHumanoid(target: unknown): (Humanoid?, Model?)
	if typeof(target) ~= "Instance" then
		return nil, nil
	end
	local inst = target :: Instance

	if inst:IsA("Humanoid") then
		local model = inst.Parent
		return inst, if model and model:IsA("Model") then model else nil
	end

	if inst:IsA("Player") then
		local character = (inst :: Player).Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		return humanoid, character
	end

	if inst:IsA("Model") then
		local humanoid = inst:FindFirstChildOfClass("Humanoid")
		return humanoid, inst
	end

	-- BasePart de um character: sobe até o Model com Humanoid.
	local model = inst:FindFirstAncestorOfClass("Model")
	local humanoid = model and model:FindFirstChildOfClass("Humanoid")
	return humanoid, model
end

--[[
	IsDamageable(target)
	true se DamageSystem.Apply teria efeito nesse alvo agora.
]]
function DamageSystem.IsDamageable(target: unknown): boolean
	local humanoid, model = resolveHumanoid(target)
	if not humanoid or not model then
		return false
	end
	if humanoid.Health <= 0 then
		return false
	end
	if model:GetAttribute("Eliminado") == true or model:FindFirstChild("Dead") then
		return false
	end
	if model:GetAttribute("Invulneravel") == true then
		return false
	end
	return true
end

--------------------------------------------------------------------------------
-- Morte
--------------------------------------------------------------------------------

local function handleDeath(model: Model, humanoid: Humanoid, info: DamageInfo?)
	if model:FindFirstChild("Dead") then
		return
	end
	if model:GetAttribute("CombatAnimationState") ~= "Death" then
		playDeathReaction(model, humanoid)
	end

	local dead = Instance.new("BoolValue")
	dead.Name = "Dead"
	dead.Parent = model

	lastDamageAt[model] = nil

	local victim = Players:GetPlayerFromCharacter(model)
	if not victim then
		return -- NPC futuro: marca Dead e para por aqui
	end

	Elimination.Eliminate(victim)

	local source = info and info.Source
	local cause = (info and info.Cause) or "Desconhecida"
	Remotes.PlayerKilled:FireAllClients(victim.UserId, if source then source.UserId else nil, cause)
end

--------------------------------------------------------------------------------
-- API
--------------------------------------------------------------------------------

--[[
	Apply(target, amount, info?)
	Tira `amount` de vida do alvo (Humanoid | Model | Player | BasePart do
	character). Devolve (danoAplicado, morreuAgora).
	  danoAplicado = 0 e morreuAgora = false quando alguma guarda barra
	  (ver cabeçalho) ou amount <= 0.
]]
function DamageSystem.Apply(target: unknown, amount: number, info: DamageInfo?): (number, boolean, boolean?)
	if type(amount) ~= "number" or amount ~= amount or amount == math.huge or amount < 0 then
		return 0, false
	end

	local humanoid, model = resolveHumanoid(target)
	if not humanoid or not model then
		return 0, false
	end
	if not DamageSystem.IsDamageable(model) then
		return 0, false, true
	end

	-- Spawn protection: o ForceField fica no Character (irmão do Humanoid).
	-- TakeDamage já ignora sozinho; a gente nem registra o "tomou dano" pra
	-- não atrasar a regeneração à toa.
	if model:FindFirstChildOfClass("ForceField") then
		return 0, false, true
	end
	if model:GetAttribute("Imune") == true then return 0, false, true end
	if info and info.Source and PowerStatus.BlockAttack(model) then return 0, false, true end
	if info and info.Empowered then
		amount *= 3
		PowerStatus.Stun(model, 2)
		local root = model:FindFirstChild("HumanoidRootPart")
		if root and root:IsA("BasePart") then PowerStatus.Emit("TiroCerteiro", model, root.Position, 0.6, "Impact") end
	end
	if PowerStatus.Active(model, "PowerDamageReduction") then amount *= 0.5 end

	-- ATRIBUTOS DE PERSONAGEM (CharacterStatsApplier publica; StatScaling
	-- converte). Quem não escolheu personagem cai no fator neutro 1.
	--   FORÇA do autor      -> multiplica o dano CAUSADO
	--   COMPOSTURA da vítima -> multiplica o dano RECEBIDO (alta = absorve)
	local source = info and info.Source
	if source then
		amount *= StatScaling.DamageDealtMultiplier(source)
	end
	local victimPlayer = Players:GetPlayerFromCharacter(model)
	if victimPlayer then
		amount *= StatScaling.DamageTakenMultiplier(victimPlayer)
	end
	local cap = info and info.MaxDamage
	if type(cap) == "number" and cap == cap and cap >= 0 and cap < math.huge then
		amount = math.min(amount, cap)
	end
	if amount <= 0 then
		return 0, false
	end

	local before = humanoid.Health
	local expectedLethal = amount >= before
	if expectedLethal then
		-- Começa antes de zerar a vida para não perder o primeiro frame quando
		-- o Humanoid entra no estado Dead.
		playDeathReaction(model, humanoid)
	end
	humanoid:TakeDamage(amount)
	local applied = before - humanoid.Health
	if applied <= 0 then
		return 0, false
	end

	lastDamageAt[model] = os.clock()

	if humanoid.Health <= 0 then
		handleDeath(model, humanoid, info)
		return applied, true
	end

	if expectedLethal then
		-- Proteção para qualquer sistema externo que tenha impedido o dano
		-- letal depois da nossa previsão.
		model:SetAttribute("CombatAnimationState", nil)
		stopReaction(model, 0.05)
	end
	playHurtReaction(model, humanoid)

	return applied, false
end

-- Server-authoritative finisher for executions that have already completed
-- their own validation (for example, the Kill marker of Monster Grab).
-- Unlike Apply, this is not reduced by character stats and therefore cannot
-- leave the victim with a fraction of health after the execution animation.
function DamageSystem.Execute(target: unknown, info: DamageInfo?): boolean
	local humanoid, model = resolveHumanoid(target)
	if not humanoid or not model or not DamageSystem.IsDamageable(model)
		or model:FindFirstChildOfClass("ForceField") or model:GetAttribute("Imune") == true then
		return false
	end

	playDeathReaction(model, humanoid)
	humanoid.Health = 0
	handleDeath(model, humanoid, info)
	return true
end

--[[
	Heal(target, amount)
	Devolve vida (respeita MaxHealth). Não ressuscita: alvo já morto/eliminado
	é ignorado. Devolve a vida efetivamente recuperada.
]]
function DamageSystem.Heal(target: unknown, amount: number): number
	if type(amount) ~= "number" or amount <= 0 then
		return 0
	end
	local humanoid, model = resolveHumanoid(target)
	if not humanoid or not model or not DamageSystem.IsDamageable(model) then
		return 0
	end

	local before = humanoid.Health
	humanoid.Health = math.min(humanoid.MaxHealth, humanoid.Health + amount)
	return humanoid.Health - before
end

--------------------------------------------------------------------------------
-- Setup por character + regeneração
--------------------------------------------------------------------------------

local function disableDefaultRegen(character: Model)
	if not GameConfig.Health.DisableRobloxDefaultRegen then
		return
	end
	-- O Roblox injeta um Script chamado "Health" (às vezes só depois de 1
	-- frame). Tenta agora e observa o que chegar depois.
	local existing = character:FindFirstChild("Health")
	if existing and existing:IsA("Script") then
		existing:Destroy()
	end
	character.ChildAdded:Connect(function(child)
		if child:IsA("Script") and child.Name == "Health" then
			child:Destroy()
		end
	end)
end

--------------------------------------------------------------------------------
-- Dano de queda
--------------------------------------------------------------------------------

local FALL_MIN_HEIGHT = 4 -- studs de queda sem dano nenhum no calculo original
local FALL_DAMAGE_START_HEIGHT = 15 -- o cliente tambem so manda dano acima disso
local FALL_DAMAGE_PER_STUD = 1.5
local FALL_MAX_REPORTED = 500 -- acima disso é cliente mentindo, ignora
local FALL_DUPLICATE_WINDOW = 0.45 -- evita client + server aplicarem o mesmo pouso

local function applyFallDamage(player: Player, fallDistance: number)
	local character = player.Character
	if not character or type(fallDistance) ~= "number" or fallDistance <= FALL_DAMAGE_START_HEIGHT
		or fallDistance > FALL_MAX_REPORTED then
		return
	end

	local state = fallStates[character]
	local now = os.clock()
	if state and now - state.lastAppliedAt < FALL_DUPLICATE_WINDOW then
		return
	end

	local damage = math.floor((fallDistance - FALL_MIN_HEIGHT) * FALL_DAMAGE_PER_STUD)
	if damage <= 0 then
		return
	end

	local applied = DamageSystem.Apply(player, damage, { Cause = "Queda" })
	if applied > 0 and state then
		state.lastAppliedAt = now
	end
end

local function startFall(state: FallState)
	if state.active then
		state.peakY = math.max(state.peakY, state.root.Position.Y)
		return
	end
	state.active = true
	state.startedAt = os.clock()
	state.startY = state.root.Position.Y
	state.peakY = state.startY
end

local function finishFall(state: FallState)
	if not state.active or state.humanoid.FloorMaterial == Enum.Material.Air then
		return
	end

	state.active = false
	local fallDistance = math.max(state.startY, state.peakY) - state.root.Position.Y
	applyFallDamage(state.player, fallDistance)
end

local function monitorFall(player: Player, character: Model, humanoid: Humanoid)
	local root = character:FindFirstChild("HumanoidRootPart") or character:WaitForChild("HumanoidRootPart", 10)
	if not root or not root:IsA("BasePart") then
		return
	end

	local state: FallState = {
		player = player,
		humanoid = humanoid,
		root = root,
		active = false,
		startY = 0,
		peakY = 0,
		startedAt = 0,
		lastAppliedAt = 0,
	}
	fallStates[character] = state

	humanoid.StateChanged:Connect(function(_, newState)
		if fallStates[character] ~= state or humanoid.Health <= 0 then
			return
		end
		if newState == Enum.HumanoidStateType.Freefall then
			startFall(state)
		elseif newState == Enum.HumanoidStateType.Landed
			or newState == Enum.HumanoidStateType.Running
			or newState == Enum.HumanoidStateType.RunningNoPhysics
			or newState == Enum.HumanoidStateType.GettingUp then
			task.defer(function()
				if fallStates[character] == state then
					finishFall(state)
				end
			end)
		end
	end)
end

local function onCharacterAdded(character: Model)
	local humanoid = character:FindFirstChildOfClass("Humanoid") or character:WaitForChild("Humanoid", 10)
	if humanoid and humanoid:IsA("Humanoid") then
		-- Sem isso o Roblox quebra os joints no mesmo instante da morte e
		-- nenhuma animação de queda consegue mover o corpo R6.
		humanoid.BreakJointsOnDeath = false
		-- COMPOSTURA -> vida máxima. Sem personagem escolhido, StatScaling
		-- devolve o meio da faixa; GameConfig.Health.Max continua sendo o
		-- teto de referência do jogo (a faixa de Compostura é centrada nele).
		local owner = Players:GetPlayerFromCharacter(character)
		local maxHealth = if owner then StatScaling.MaxHealth(owner) else GameConfig.Health.Max
		humanoid.MaxHealth = maxHealth
		humanoid.Health = maxHealth
		if owner then
			monitorFall(owner, character, humanoid)
		end
	end
	disableDefaultRegen(character)

	character.Destroying:Connect(function()
		lastDamageAt[character] = nil
		fallStates[character] = nil
		stopReaction(character, 0)
	end)
end

local function watchPlayer(player: Player)
	player.CharacterAdded:Connect(onCharacterAdded)
	if player.Character then
		onCharacterAdded(player.Character)
	end
end

local function regenStep(dt: number)
	local perSecond = GameConfig.Health.RegenPerSecond
	if perSecond <= 0 then
		return
	end
	local now = os.clock()
	local delay = GameConfig.Health.RegenDelayAfterDamage

	for _, player in Players:GetPlayers() do
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if character and humanoid and humanoid.Health > 0 and humanoid.Health < humanoid.MaxHealth then
			if not DamageSystem.IsDamageable(character) then
				continue
			end
			local hurtAt = lastDamageAt[character]
			if not hurtAt or (now - hurtAt) >= delay then
				humanoid.Health = math.min(humanoid.MaxHealth, humanoid.Health + perSecond * dt)
			end
		end
	end
end

--------------------------------------------------------------------------------
-- Compatibilidade com o efeito de queda do cliente
--------------------------------------------------------------------------------
-- O servidor monitora a queda de forma autoritativa em fallStates. O RemoteEvent
-- continua aceito como apoio para efeitos/scripts antigos, mas usa a mesma
-- applyFallDamage com janela anti-duplicada.

local function onFallDamage(player: Player, fallDistance: unknown)
	if type(fallDistance) ~= "number" then
		return
	end
	applyFallDamage(player, fallDistance)
end

--[[
	Init()
	Aplica MaxHealth/regen-off nos characters, liga o loop de regeneração e o
	dano de queda. Chame uma vez no boot, ANTES de OTSFirearmService/WeaponSystem.
]]
function DamageSystem.Init()
	local fallEvent = ReplicatedStorage:FindFirstChild("FallDamageEvent")
		or ReplicatedStorage:WaitForChild("FallDamageEvent", 10)
	if fallEvent and fallEvent:IsA("RemoteEvent") then
		fallEvent.OnServerEvent:Connect(onFallDamage)
	else
		warn("[DamageSystem] ReplicatedStorage.FallDamageEvent não existe -- dano de queda desligado.")
	end

	for _, player in Players:GetPlayers() do
		watchPlayer(player)
	end
	Players.PlayerAdded:Connect(watchPlayer)
	Players.PlayerRemoving:Connect(function(player)
		local character = player.Character
		if character then
			lastDamageAt[character] = nil
		end
	end)

	local regenAccumulator = 0
	local hurtAccumulator = 0
	RunService.Heartbeat:Connect(function(dt: number)
		hurtAccumulator += dt
		if hurtAccumulator >= 0.1 then
			refreshHurtReactions()
			hurtAccumulator = 0
		end

		for character, state in fallStates do
			if not character.Parent or state.humanoid.Health <= 0 or state.root.Parent ~= character then
				fallStates[character] = nil
				continue
			end

			local floor = state.humanoid.FloorMaterial
			local verticalSpeed = state.root.AssemblyLinearVelocity.Y
			if floor == Enum.Material.Air and verticalSpeed < -8 then
				startFall(state)
			end
			if state.active then
				state.peakY = math.max(state.peakY, state.root.Position.Y)
				if floor ~= Enum.Material.Air and floor ~= Enum.Material.Water
					and state.humanoid:GetState() ~= Enum.HumanoidStateType.Freefall then
					finishFall(state)
				end
			end
		end

		regenAccumulator += dt
		if regenAccumulator >= 0.25 then
			regenStep(regenAccumulator)
			regenAccumulator = 0
		end
	end)
end

return DamageSystem
