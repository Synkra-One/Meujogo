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
	  - WeaponSystem.lua   (chave inglesa e pé de cabra; configuração central)
	  - UtilityItemSystem.lua (Chocolate cura pelo Heal)

	MONSTRO: nasce com 1000 HP e Apply/Execute limitam o dano antes de chegar
	a zero. Derrota temporária não dispara Dead/Elimination/PlayerKilled.

	MORTE DOS HUMANOS: quando Health chega a 0, o character ganha um BoolValue "Dead"
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
	RegenDelayAfterDamage segundos sem tomar dano. O Monstro não regenera
	passivamente nesta etapa, para permitir o teste até 1 HP.

	Uso (uma vez no boot do servidor, ANTES de OTSFirearmService/WeaponSystem):
		local DamageSystem = require(script.DamageSystem)
		DamageSystem.Init()
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Debris = game:GetService("Debris")

local GameConfig = require(ReplicatedStorage.Modules.GameConfig)
local MonsterAnimationConfig = require(ReplicatedStorage.Modules.MonsterAnimationConfig)
local Remotes = require(ReplicatedStorage.Modules.Remotes)
local StatScaling = require(ReplicatedStorage.Modules.StatScaling)
local Elimination = require(script.Parent.Elimination)
local PowerStatus = require(script.Parent.SurvivorPowerStatus)

local DamageSystem = {}
local initialized = false

--[[
	GANCHOS DE OBSERVAÇÃO (só leitura -- não alteram dano nem cura)

	Existem porque o DamageSystem já é a PORTA ÚNICA de dano e cura: golpe do
	Monstro, faca/lança/pedra, tiro da Glock, chocolate e bandagem passam
	todos por aqui. Um sistema que queira SABER de combate (hoje:
	MatchRewardService, pras estatísticas e o XP da partida) escuta estes dois
	eventos em vez de cada sistema de arma ter que avisá-lo -- que seria o
	mesmo registro copiado em quatro arquivos, divergindo no primeiro que
	alguém esquecesse de atualizar.

	DamageApplied:Fire(attacker: Player?, victim: Player?, applied: number,
	                   died: boolean, cause: string?)
	  Só dispara quando dano foi REALMENTE aplicado (applied > 0). Guardas
	  (invulnerável, já morto, ForceField) não disparam nada.
	  attacker/victim são nil quando não há Player por trás (ambiente, NPC).

	Healed:Fire(healer: Player?, target: Player?, healed: number)
	  Só dispara quando vida foi REALMENTE devolvida (healed > 0).

	São BindableEvents: os listeners rodam DEPOIS do dano/cura já aplicado, e
	um erro num listener não quebra o combate.
]]
DamageSystem.DamageApplied = Instance.new("BindableEvent")
DamageSystem.Healed = Instance.new("BindableEvent")

export type DamageInfo = {
	Source: Player?, -- quem causou (pra PlayerKilled e futuras regras de time)
	Cause: string?, -- texto da causa ("Tiro", "Monstro", "Ambiente"...)
	Empowered: boolean?, -- server-only token consumed when a validated attack begins
	FixedDamage: boolean?, -- Parte 1: valores exatos da arma, sem multiplicadores
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

local function playReaction(model: Model, humanoid: Humanoid, animationId: string, priority: Enum.AnimationPriority, looped: boolean?, allowWhenGlobalDisabled: boolean?): boolean
	if (GameConfig.Health.CombatAnimationsEnabled == false and allowWhenGlobalDisabled ~= true)
		or not MonsterAnimationConfig.IsUsableAnimationId(animationId) then
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
	local owner = Players:GetPlayerFromCharacter(model)
	local isMonster = owner ~= nil and owner:GetAttribute("Role") == GameConfig.Roles.Monster
	if GameConfig.Health.CombatAnimationsEnabled == false
		and (not isMonster or not MonsterAnimationConfig.IsUsableAnimationId(MonsterAnimationConfig.AnimationIds.Damage)) then
		return
	end
	local moving = isHurtMoving(model, hurtMovingStates[model])
	local animationId = if isMonster then MonsterAnimationConfig.AnimationIds.Damage else if moving
		then GameConfig.Health.HurtWalkAnimationId else GameConfig.Health.HurtIdleAnimationId
	if playReaction(model, humanoid, animationId, Enum.AnimationPriority.Action2, true, isMonster) then
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
	local owner = Players:GetPlayerFromCharacter(model)
	local isMonster = owner ~= nil and owner:GetAttribute("Role") == GameConfig.Roles.Monster
	local animationId = if isMonster then MonsterAnimationConfig.AnimationIds.Death else GameConfig.Health.DeathAnimationId
	playReaction(model, humanoid, animationId, Enum.AnimationPriority.Action4, nil, isMonster)
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

-- Estado futuro de vulnerabilidade é independente do debuff de luz existente.
-- Apenas estas funções no servidor escrevem MonsterCombatState.
function DamageSystem.GetMonsterState(target: unknown): string?
	local _, model = resolveHumanoid(target)
	local owner = model and Players:GetPlayerFromCharacter(model)
	if not model or not owner or owner:GetAttribute("Role") ~= GameConfig.Roles.Monster then return nil end
	local state = model:GetAttribute("MonsterCombatState")
	local states = GameConfig.Monster.CombatStates
	return if state == states.Weakened or state == states.Vulnerable then state :: string else states.Normal
end

function DamageSystem.SetMonsterState(target: unknown, state: string): boolean
	local _, model = resolveHumanoid(target)
	if not model or not DamageSystem.GetMonsterState(model) then return false end
	local states = GameConfig.Monster.CombatStates
	if state ~= states.Normal and state ~= states.Weakened and state ~= states.Vulnerable then return false end
	model:SetAttribute("MonsterCombatState", state)
	return true
end

local function protectMonster(model: Model, humanoid: Humanoid, amount: number): number
	if not DamageSystem.GetMonsterState(model) then return amount end
	local floor = GameConfig.Health.MonsterMinimum
	if amount >= humanoid.Health and model:GetAttribute("MonsterTemporarilyDefeated") ~= true then
		model:SetAttribute("MonsterTemporarilyDefeated", true)
		print(string.format("[DamageSystem] %s foi derrotado temporariamente; Monstro mantido com pelo menos %d de vida.", model.Name, floor))
	end
	-- Nunca passa por zero: impede Humanoid.Died, eliminação e fim da rodada.
	return math.min(amount, math.max(0, humanoid.Health - floor))
end

local function hitFeedback(model: Model)
	local old = model:FindFirstChild("CombatHitFeedback")
	if old then old:Destroy() end
	local flash = Instance.new("Highlight")
	flash.Name = "CombatHitFeedback"
	flash.Adornee = model
	flash.DepthMode = Enum.HighlightDepthMode.Occluded
	flash.FillColor = Color3.fromRGB(255, 65, 55)
	flash.FillTransparency, flash.OutlineTransparency = 0.45, 1
	flash.Parent = model
	Debris:AddItem(flash, 0.18)
end

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
	if info and info.Empowered and not info.FixedDamage then
		amount *= 3
		PowerStatus.Stun(model, 2)
		local root = model:FindFirstChild("HumanoidRootPart")
		if root and root:IsA("BasePart") then PowerStatus.Emit("TiroCerteiro", model, root.Position, 0.6, "Impact") end
	end
	if not (info and info.FixedDamage) and PowerStatus.Active(model, "PowerDamageReduction") then amount *= 0.5 end

	-- ATRIBUTOS DE PERSONAGEM (CharacterStatsApplier publica; StatScaling
	-- converte). Quem não escolheu personagem cai no fator neutro 1.
	--   FORÇA do autor      -> multiplica o dano CAUSADO
	--   COMPOSTURA da vítima -> multiplica o dano RECEBIDO (alta = absorve)
	local source = info and info.Source
	if source and not (info and info.FixedDamage) then
		amount *= StatScaling.DamageDealtMultiplier(source)
	end
	local victimPlayer = Players:GetPlayerFromCharacter(model)
	if victimPlayer and not (info and info.FixedDamage) then
		amount *= StatScaling.DamageTakenMultiplier(victimPlayer)
	end
	local cap = info and info.MaxDamage
	if type(cap) == "number" and cap == cap and cap >= 0 and cap < math.huge then
		amount = math.min(amount, cap)
	end
	if amount <= 0 then
		return 0, false
	end

	amount = protectMonster(model, humanoid, amount)
	if amount <= 0 then return 0, false end
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

	hitFeedback(model)
	lastDamageAt[model] = os.clock()

	local attacker = info and info.Source
	local cause = info and info.Cause

	if humanoid.Health <= 0 then
		handleDeath(model, humanoid, info)
		DamageSystem.DamageApplied:Fire(attacker, victimPlayer, applied, true, cause)
		return applied, true
	end

	if expectedLethal then
		-- Proteção para qualquer sistema externo que tenha impedido o dano
		-- letal depois da nossa previsão.
		model:SetAttribute("CombatAnimationState", nil)
		stopReaction(model, 0.05)
	end
	playHurtReaction(model, humanoid)

	-- Por último, com a reação de dano já disparada: listener de BindableEvent
	-- roda no mesmo instante, e avisar antes deixaria um observador lento
	-- atrasando o feedback do golpe.
	DamageSystem.DamageApplied:Fire(attacker, victimPlayer, applied, false, cause)

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

	if DamageSystem.GetMonsterState(model) then
		DamageSystem.Apply(model, humanoid.Health, { Source = info and info.Source, Cause = info and info.Cause, FixedDamage = true })
		return false
	end
	local before = humanoid.Health
	playDeathReaction(model, humanoid)
	humanoid.Health = 0
	handleDeath(model, humanoid, info)

	DamageSystem.DamageApplied:Fire(
		info and info.Source,
		Players:GetPlayerFromCharacter(model),
		before,
		true,
		info and info.Cause
	)
	return true
end

--[[
	Heal(target, amount, healer?)
	Devolve vida (respeita MaxHealth). Não ressuscita: alvo já morto/eliminado
	é ignorado. Devolve a vida efetivamente recuperada.

	`healer` é OPCIONAL e serve só pra observação (evento Healed): quem
	aplicou a cura. Toda cura do jogo hoje é em si mesmo, então quem chama
	pode passar o próprio jogador ou omitir -- o comportamento é idêntico.
	Ele existe pra que, quando cura de ALIADO passar a existir, o relatório de
	partida consiga separar "curou o time" de "se curou" sem mudar nada aqui.
]]
function DamageSystem.Heal(target: unknown, amount: number, healer: Player?): number
	if type(amount) ~= "number" or amount ~= amount or math.abs(amount) == math.huge or amount <= 0 then
		return 0
	end
	local humanoid, model = resolveHumanoid(target)
	if not humanoid or not model or not DamageSystem.IsDamageable(model) then
		return 0
	end

	local before = humanoid.Health
	humanoid.Health = math.min(humanoid.MaxHealth, humanoid.Health + amount)
	local healed = humanoid.Health - before

	if healed > 0 then
		local targetPlayer = Players:GetPlayerFromCharacter(model)
		DamageSystem.Healed:Fire(healer or targetPlayer, targetPlayer, healed)
	end

	return healed
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
		if owner and owner:GetAttribute("Role") == GameConfig.Roles.Monster then
			character:SetAttribute("MonsterCombatState", GameConfig.Monster.CombatStates.Normal)
		end
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
	player:GetAttributeChangedSignal("Role"):Connect(function()
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if not character or not humanoid or humanoid.Health <= 0 then return end
		local maxHealth = StatScaling.MaxHealth(player)
		humanoid.MaxHealth = maxHealth
		humanoid.Health = maxHealth
		character:SetAttribute("MonsterTemporarilyDefeated", nil)
		character:SetAttribute("MonsterCombatState", if player:GetAttribute("Role") == GameConfig.Roles.Monster
			then GameConfig.Monster.CombatStates.Normal else nil)
	end)
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
			if DamageSystem.GetMonsterState(character) or not DamageSystem.IsDamageable(character) then
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
	if initialized then return end
	initialized = true
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
