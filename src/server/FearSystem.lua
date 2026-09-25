--!strict
-- Fear partes 1/2. Autoridade: tabela privada no servidor; Player.Fear só replica
-- o resultado. Nenhum Remote aceita Fear do cliente. Init é idempotente.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local GameConfig = require(ReplicatedStorage.Modules.GameConfig)
local StatScaling = require(ReplicatedStorage.Modules.StatScaling)
local RoundManager = require(script.Parent.RoundManager)
local Elimination = require(script.Parent.Elimination)
local Rules = require(script.Parent.FearRules)
local DamageSystem = require(script.Parent.DamageSystem)
local CFG = GameConfig.Fear

local FearSystem = {}
-- Hooks de servidor para a Parte 3. Não há Remote de solicitação destes efeitos.
FearSystem.FearStateChanged = Instance.new("BindableEvent") -- (player, newState, previousState)
FearSystem.TripTriggered = Instance.new("BindableEvent") -- (player, position, duration)
FearSystem.PanicSoundTriggered = Instance.new("BindableEvent") -- (player, position, radius)
type Trip = { root: BasePart, character: Model, humanoid: Humanoid,
	autoOwnership: boolean, owner: Player?, previousSpeed: number, speedCap: number }
type State = Rules.State & {
	los: boolean, losElapsed: number, target: BasePart?, chase: boolean, chaseFor: number,
	tripCheck: number, tripUntil: number, tripCooldownUntil: number, trip: Trip?,
	panicCheck: number, panicCooldownUntil: number,
}
type Watch = { playerConnections: { RBXScriptConnection }, characterConnections: { RBXScriptConnection } }
local states: { [Player]: State } = {}
local watches: { [Player]: Watch } = {}
local witnessAt: { [Player]: { [Player]: number } } = {}
local initialized = false
local now = 0
local rng = Random.new()
local function setIfChanged(instance: Instance, name: string, value: any)
	if instance:GetAttribute(name) ~= value then instance:SetAttribute(name, value) end
end

local function publish(player: Player, value: number)
	setIfChanged(player, "Fear", value)
	local name = Rules.GetState(value, CFG)
	local previous = player:GetAttribute("FearState")
	setIfChanged(player, "FearState", name)
	if previous ~= name then FearSystem.FearStateChanged:Fire(player, name, previous) end
end

local function endTrip(state: State)
	local trip = state.trip
	if not trip then return end
	state.trip = nil
	setIfChanged(trip.character, "FearTripping", nil)
	setIfChanged(trip.character, "FearTripSpeedCap", nil)
	if trip.humanoid.Parent and trip.humanoid.WalkSpeed == trip.speedCap then
		trip.humanoid.WalkSpeed = trip.previousSpeed
	end
	if trip.root.Parent then
		-- Não sobrescreve um novo dono escolhido por outro sistema.
		local ok, err = pcall(function()
			if trip.root:CanSetNetworkOwnership() and trip.root:GetNetworkOwner() == nil then
				if trip.autoOwnership then trip.root:SetNetworkOwnershipAuto()
				else trip.root:SetNetworkOwner(trip.owner) end
			end
		end)
		if not ok then warn("[Fear] Falha ao restaurar ownership: " .. tostring(err)) end
	end
end

local function reset(player: Player)
	local state = states[player]
	if state then endTrip(state) end
	states[player] = nil
	witnessAt[player] = nil
	setIfChanged(player, "FearLineOfSight", false)
	setIfChanged(player, "FearChase", false)
	publish(player, 0)
end

local function livingRoot(player: Player): BasePart?
	if player.Parent ~= Players or player:GetAttribute("InRound") ~= true
		or Elimination.IsEliminated(player) then return nil end
	local character = player.Character
	if not character or not character.Parent then return nil end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local root = character:FindFirstChild("HumanoidRootPart")
	if not humanoid or humanoid.Health <= 0 or not root or not root:IsA("BasePart") then return nil end
	return root
end

local function survivorRoot(player: Player): BasePart?
	if not RoundManager.IsRoundActive() or player:GetAttribute("Role") ~= GameConfig.Roles.Survivor
		or player:GetAttribute("CharacterSelectOpen") == true then return nil end
	return livingRoot(player)
end

local function getState(player: Player): State
	local state = states[player]
	if not state then
		state = { value = 0, safeFor = 0, exposureFor = 0, los = false, losElapsed = 0, target = nil,
			chase = false, chaseFor = 0, tripCheck = 0, tripUntil = 0, tripCooldownUntil = 0,
			trip = nil, panicCheck = 0, panicCooldownUntil = 0 }
		states[player] = state
	end
	return state
end

local function finiteNonnegative(amount: number): boolean
	return type(amount) == "number" and amount == amount and amount >= 0 and amount < math.huge
end

-- API só de servidor. AddFear recebe pontos FINAIS, não reaplica Compostura:
-- futuras fontes podem usar StatScaling.FearGainMultiplier antes de chamar.
function FearSystem.GetFear(player: Player): number
	if not survivorRoot(player) then reset(player); return 0 end
	local state = states[player]
	return if state then state.value else 0
end

function FearSystem.GetFearState(player: Player): string
	return Rules.GetState(FearSystem.GetFear(player), CFG)
end

function FearSystem.GetStaminaRegenMultiplier(player: Player): number
	return Rules.StaminaRegenMultiplier(FearSystem.GetFear(player), CFG)
end

function FearSystem.AddFear(player: Player, amount: number, _source: string?): number
	if player.Character and player.Character:GetAttribute("PowerFearHidden") == true then return FearSystem.GetFear(player) end
	if not finiteNonnegative(amount) then return FearSystem.GetFear(player) end
	if not survivorRoot(player) then reset(player); return 0 end
	local state = getState(player)
	if amount > 0 then
		state.value = math.clamp(state.value + amount, 0, CFG.MaxFear)
		state.safeFor = 0 -- qualquer nova ameaça reinicia o atraso de recuperação
	end
	publish(player, state.value)
	return state.value
end

function FearSystem.ReduceFear(player: Player, amount: number): number
	if not finiteNonnegative(amount) then return FearSystem.GetFear(player) end
	if not survivorRoot(player) then reset(player); return 0 end
	local state = getState(player)
	state.value = math.clamp(state.value - amount, 0, CFG.MaxFear)
	publish(player, state.value)
	return state.value
end

local function disconnect(connections: { RBXScriptConnection })
	for _, connection in connections do connection:Disconnect() end
	table.clear(connections)
end

local function watchPlayer(player: Player)
	if watches[player] then return end
	local watch: Watch = { playerConnections = {}, characterConnections = {} }
	watches[player] = watch
	local function clearCharacter()
		disconnect(watch.characterConnections)
		reset(player)
	end
	local function watchCharacter(character: Model)
		clearCharacter()
		local attached = false
		local function attachHumanoid(child: Instance)
			if attached or not child:IsA("Humanoid") then return end
			attached = true
			table.insert(watch.characterConnections, child.Died:Connect(clearCharacter))
		end
		-- Sem WaitForChild/task pendente que possa sobreviver ao respawn.
		table.insert(watch.characterConnections, character.ChildAdded:Connect(attachHumanoid))
		local humanoid = character:FindFirstChildOfClass("Humanoid")
		if humanoid then attachHumanoid(humanoid) end
	end
	table.insert(watch.playerConnections, player.CharacterAdded:Connect(watchCharacter))
	table.insert(watch.playerConnections, player.CharacterRemoving:Connect(clearCharacter))
	reset(player)
	if player.Character then watchCharacter(player.Character) end
end

local function resetAll()
	for _, player in Players:GetPlayers() do reset(player) end
end

local function horizontalVelocity(root: BasePart): Vector3
	local v = root.AssemblyLinearVelocity
	return Vector3.new(v.X, 0, v.Z)
end

local function sightPosition(root: BasePart): Vector3
	local head = root.Parent and root.Parent:FindFirstChild("Head")
	return if head and head:IsA("BasePart") then head.Position else root.Position
end

local function witnessed(witness: Player, victim: Player, victimRoot: BasePart): boolean
	local root = survivorRoot(witness)
	if not root or witness == victim or (root.Position - victimRoot.Position).Magnitude > CFG.WitnessRange then
		return false
	end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { root.Parent :: Instance, victimRoot.Parent :: Instance }
	params.RespectCanCollide, params.IgnoreWater = true, true
	local origin = sightPosition(root)
	return Workspace:Raycast(origin, sightPosition(victimRoot) - origin, params) == nil
end

local function onDamage(_attacker: Player?, victim: Player?, applied: number, died: boolean, _cause: string?)
	if not RoundManager.IsRoundActive() or not victim or victim:GetAttribute("Role") ~= GameConfig.Roles.Survivor
		or victim:GetAttribute("InRound") ~= true or victim:GetAttribute("CharacterSelectOpen") == true
		or type(applied) ~= "number" or applied <= 0 then return end
	local character = victim.Character
	local victimRoot = character and character:FindFirstChild("HumanoidRootPart")
	if not victimRoot or not victimRoot:IsA("BasePart") then return end
	if not died and survivorRoot(victim) then
		local shock = math.min(CFG.DamageFearMax, CFG.DamageFearBase + applied * CFG.DamageFearPerHealth)
		FearSystem.AddFear(victim, shock * StatScaling.FearGainMultiplier(victim), "Damage")
	end
	if not died and applied < CFG.WitnessMinDamage then return end
	for _, witness in Players:GetPlayers() do
		if witnessed(witness, victim, victimRoot) then
			local history = witnessAt[witness]
			if not history then history = {}; witnessAt[witness] = history end
			if died or not history[victim] or now - history[victim] >= CFG.WitnessCooldown then
				history[victim] = now
				local shock = if died then CFG.WitnessDeathFear else CFG.WitnessDamageFear
				FearSystem.AddFear(witness, shock * StatScaling.FearGainMultiplier(witness),
					if died then "WitnessDeath" else "WitnessDamage")
			end
		end
	end
end

local function updateThreat(state: State, root: BasePart, target: BasePart?, distance: number, dt: number)
	state.losElapsed += dt
	if not target or distance >= CFG.MaxFearDistance then
		state.target, state.los, state.chase, state.chaseFor = nil, false, false, 0
		return
	end
	if state.target ~= target or state.losElapsed >= CFG.LineOfSightUpdateInterval then
		if state.target ~= target then state.chaseFor = 0 end
		state.target = target
		state.losElapsed = 0
		local params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Exclude
		params.FilterDescendantsInstances = { root.Parent :: Instance, target.Parent :: Instance }
		params.RespectCanCollide = true -- sólido bloqueia, triggers/efeitos não
		params.IgnoreWater = true -- terreno sólido continua sendo testado
		local origin = sightPosition(root)
		local direction = sightPosition(target) - origin
		state.los = direction.Magnitude == 0 or Workspace:Raycast(origin, direction, params) == nil
	end
	local victimVelocity, monsterVelocity = horizontalVelocity(root), horizontalVelocity(target)
	local delta = root.Position - target.Position
	local horizontal = Vector3.new(delta.X, 0, delta.Z)
	local qualifies = distance <= CFG.ChaseDistance and not root.Anchored and not target.Anchored
		and victimVelocity.Magnitude >= CFG.ChaseMinSpeed and monsterVelocity.Magnitude >= CFG.ChaseMinSpeed
		and horizontal.Magnitude > 0
		and (not CFG.ChaseRequiresLineOfSight or state.los)
	if qualifies then
		qualifies = monsterVelocity.Unit:Dot(horizontal.Unit) >= CFG.ChaseTowardDot
			and victimVelocity.Unit:Dot(horizontal.Unit) >= CFG.ChaseAwayDot
	end
	state.chaseFor = if qualifies then state.chaseFor + dt else 0
	state.chase = qualifies and state.chaseFor >= CFG.ChaseConfirmTime
end

local function enforceTrip(trip: Trip)
	-- Ownership temporário no servidor impede o cliente de cancelar a perda de ritmo.
	trip.humanoid.WalkSpeed = math.min(trip.humanoid.WalkSpeed, trip.speedCap)
	local velocity = trip.root.AssemblyLinearVelocity
	local horizontal = horizontalVelocity(trip.root)
	if horizontal.Magnitude > trip.speedCap then
		trip.root.AssemblyLinearVelocity = horizontal.Unit * trip.speedCap + Vector3.new(0, velocity.Y, 0)
	end
end

local function beginTrip(player: Player, state: State, root: BasePart): boolean
	local character = player.Character
	if character and (character:GetAttribute("PowerStunImmune") == true or character:GetAttribute("Imune") == true
		or character:GetAttribute("PowerStunned") == true or character:GetAttribute("PowerMoving") == true) then return false end
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not character or not humanoid or not root:CanSetNetworkOwnership() then return false end
	local trip: Trip = { root = root, character = character, humanoid = humanoid,
		autoOwnership = root:GetNetworkOwnershipAuto(), owner = root:GetNetworkOwner(),
		previousSpeed = humanoid.WalkSpeed, speedCap = StatScaling.WalkSpeed(player) * CFG.TripSpeedMultiplier }
	root:SetNetworkOwner(nil)
	state.trip = trip
	state.tripUntil = now + CFG.TripDuration
	state.tripCooldownUntil = now + CFG.TripCooldown
	setIfChanged(character, "FearTripping", true)
	setIfChanged(character, "FearTripSpeedCap", trip.speedCap)
	enforceTrip(trip)
	FearSystem.TripTriggered:Fire(player, root.Position, CFG.TripDuration)
	return true
end

local function updateEffects(player: Player, state: State, root: BasePart, dt: number)
	if state.trip then
		if now >= state.tripUntil then endTrip(state) else enforceTrip(state.trip) end
	end
	local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	local running = humanoid ~= nil and not root.Anchored and humanoid.FloorMaterial ~= Enum.Material.Air
		and humanoid.FloorMaterial ~= Enum.Material.Water and not humanoid.Sit
		and humanoid:GetState() ~= Enum.HumanoidStateType.Swimming
		and horizontalVelocity(root).Magnitude > StatScaling.WalkSpeed(player) * GameConfig.Characters.SprintSpeedRatio
	if state.value >= CFG.TripMinFear and running and not state.trip and now >= state.tripCooldownUntil then
		state.tripCheck += dt
		if state.tripCheck >= CFG.TripCheckInterval then
			state.tripCheck = 0 -- não faz rajada de sorteios após um tick atrasado
			local chance = Rules.EffectChance(state.value, CFG.TripMinFear, CFG.MaxFear, CFG.TripChanceMin, CFG.TripChanceMax)
			if rng:NextNumber() < chance then beginTrip(player, state, root) end
		end
	else state.tripCheck = 0 end
	if state.value >= CFG.PanicSoundMinFear and now >= state.panicCooldownUntil then
		state.panicCheck += dt
		if state.panicCheck >= CFG.PanicSoundCheckInterval then
			state.panicCheck = 0
			local chance = Rules.EffectChance(state.value, CFG.PanicSoundMinFear, CFG.MaxFear,
				CFG.PanicSoundChanceMin, CFG.PanicSoundChanceMax)
			if rng:NextNumber() < chance then
				state.panicCooldownUntil = now + CFG.PanicSoundCooldown
				-- Sem ID: nenhum Sound vazio/falso é criado. Parte 3 poderá tocar
				-- áudio 3D no padrão SoundManager e localizar a origem pelo hook.
				FearSystem.PanicSoundTriggered:Fire(player, root.Position, CFG.PanicSoundRadius)
			end
		end
	else state.panicCheck = 0 end
end

local function step(dt: number, debugNow: boolean)
	now += dt
	if not RoundManager.IsRoundActive() then resetAll(); return end
	local players = Players:GetPlayers()
	local monsters: { BasePart } = {}
	-- Uma coleta por atualização. Se houver mais de um monstro, vale o mais próximo.
	for _, player in players do
		if player:GetAttribute("Role") == GameConfig.Roles.Monster then
			local root = livingRoot(player)
			if root then table.insert(monsters, root) end
		end
	end
	for _, player in players do
		local root = survivorRoot(player)
		if not root then reset(player); continue end
		local distance = math.huge -- sem monstro vivo: zona sem ameaça, com o mesmo atraso
		local target: BasePart? = nil
		for _, monsterRoot in monsters do
			local candidateDistance = (root.Position - monsterRoot.Position).Magnitude
			if candidateDistance < distance then distance, target = candidateDistance, monsterRoot end
		end
		local state = getState(player)
		if player.Character and player.Character:GetAttribute("PowerFearHidden") == true then
			endTrip(state)
			state.target, state.los, state.chase, state.chaseFor = nil, false, false, 0
			setIfChanged(player, "FearLineOfSight", false)
			setIfChanged(player, "FearChase", false)
			continue -- suspend detection without erasing accumulated tension
		end
		updateThreat(state, root, target, distance, dt)
		setIfChanged(player, "FearLineOfSight", state.los)
		setIfChanged(player, "FearChase", state.chase)
		local multiplier = StatScaling.FearGainMultiplier(player)
		if state.los then multiplier *= CFG.LineOfSightMultiplier end
		if state.chase then multiplier *= CFG.ChaseFearMultiplier end
		local gain, recovering, recovery = Rules.Step(state, distance,
			multiplier, StatScaling.FearRecoveryMultiplier(player), dt, CFG)
		publish(player, state.value)
		updateEffects(player, state, root, dt)
		if debugNow then
			local composure = StatScaling.Of(player, "Compostura")
			print(string.format("[Fear] Player: %s | Fear: %.1f | FearState: %s | Composure: %s | MonsterDistance: %s | LineOfSight: %s | Chase: %s | FearGainPerSecond: %.2f | Recovery: %s | FearRecoveryPerSecond: %.2f | StaminaRegenMultiplier: %.2f | TripCooldown: %.1f | PanicSoundCooldown: %.1f",
				player.Name, state.value, Rules.GetState(state.value, CFG), if composure then tostring(composure) else "neutra (sem seleção)",
				if distance < math.huge then string.format("%.1f", distance) else "sem monstro vivo",
				tostring(state.los), tostring(state.chase), gain, tostring(recovering), recovery,
				Rules.StaminaRegenMultiplier(state.value, CFG), math.max(0, state.tripCooldownUntil - now),
				math.max(0, state.panicCooldownUntil - now)))
		end
	end
end

function FearSystem.Init()
	if initialized then return end
	assert(RunService:IsServer(), "FearSystem só pode iniciar no servidor")
	assert(CFG.MaxFear > 0 and CFG.MaxFear <= 100 and CFG.MinFearDistance >= 0
		and CFG.MaxFearDistance > CFG.MinFearDistance, "Fear: limites inválidos")
	assert(CFG.FearUpdateInterval > 0 and CFG.DebugPrintInterval >= CFG.FearUpdateInterval
		and CFG.FearRecoveryDelay >= 0 and CFG.ProximityCurveExponent >= 1,
		"Fear: intervalos/curva inválidos")
	assert(CFG.LineOfSightUpdateInterval >= CFG.FearUpdateInterval and CFG.MaxFearGainPerSecond > 0,
		"Fear: intervalo LOS/teto de ganho inválido")
	assert(CFG.ExposureRampSeconds > 0 and CFG.ExposureInitialMultiplier >= 0
		and CFG.ExposureInitialMultiplier <= 1 and CFG.WitnessRange > 0 and CFG.WitnessCooldown >= 0,
		"Fear: exposição/testemunhas inválidas")
	assert(CFG.StaminaPenaltyStartFear < CFG.MaxFear and CFG.MinStaminaRegenMultiplier > 0
		and CFG.MinStaminaRegenMultiplier <= 1 and CFG.StaminaRegenCurveExponent >= 1,
		"Fear: curva de stamina inválida")
	assert(CFG.TripMinFear < CFG.MaxFear and CFG.PanicSoundMinFear < CFG.MaxFear
		and CFG.TripCheckInterval > 0 and CFG.PanicSoundCheckInterval > 0
		and CFG.TripDuration > 0 and CFG.TripCooldown >= CFG.TripDuration
		and CFG.TripSpeedMultiplier > 0 and CFG.TripSpeedMultiplier <= 1 and CFG.PanicSoundCooldown >= 0,
		"Fear: intervalos/limites de efeitos inválidos")
	local limits = CFG.FearStates
	assert(limits.Nervous > 0 and limits.Nervous < limits.Scared and limits.Scared < limits.Panicked
		and limits.Panicked < limits.ExtremePanic and limits.ExtremePanic <= CFG.MaxFear,
		"Fear: estados devem ter limites crescentes")
	assert(CFG.ChaseMinSpeed > 0 and CFG.ChaseConfirmTime >= 0 and CFG.ChaseDistance > 0
		and CFG.ChaseDistance <= CFG.MaxFearDistance and CFG.LineOfSightMultiplier >= 1 and CFG.ChaseFearMultiplier >= 1,
		"Fear: parâmetros de ameaça inválidos")
	initialized = true
	Players.PlayerAdded:Connect(watchPlayer)
	Players.PlayerRemoving:Connect(function(player)
		reset(player)
		for _, history in witnessAt do history[player] = nil end
		local watch = watches[player]
		if watch then
			disconnect(watch.playerConnections)
			disconnect(watch.characterConnections)
		end
		watches[player] = nil
		states[player] = nil
	end)
	for _, player in Players:GetPlayers() do watchPlayer(player) end
	RoundManager.RoundPrepared.Event:Connect(resetAll)
	RoundManager.RoundEnded.Event:Connect(resetAll)
	DamageSystem.DamageApplied.Event:Connect(onDamage)
	local elapsed, debugElapsed = 0, 0
	-- ÚNICA conexão de atualização; integra o tempo real acumulado.
	RunService.Heartbeat:Connect(function(dt)
		elapsed += dt
		debugElapsed = if CFG.DebugMode then debugElapsed + dt else 0
		if elapsed < CFG.FearUpdateInterval then return end
		local debugNow = CFG.DebugMode and debugElapsed >= CFG.DebugPrintInterval
		if debugNow then debugElapsed = 0 end
		step(elapsed, debugNow)
		elapsed = 0
	end)
end

return FearSystem
