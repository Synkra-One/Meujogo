--!strict
--[[
	StaminaSystem
	Fôlego de sprint, AUTORITATIVO NO SERVIDOR. Substituiu o StaminaSystem
	client-side que vinha no pacote de movimento (aquele era 100% cliente:
	dava pra editar o valor e correr pra sempre).

	POR QUE É À PROVA DE EXPLOIT
	  O cliente só manda a INTENÇÃO ("estou segurando Shift", Remotes.
	  SprintIntent). Quem decide se o fôlego cai é este módulo, e ele NÃO
	  confia na intenção: mede a velocidade horizontal real do
	  HumanoidRootPart. Se o personagem está de fato se movendo acima do
	  limiar de corrida, gasta -- tenha o cliente dito o que disser. Mentir
	  "não estou correndo" não ajuda, porque a velocidade real entrega.
	  A intenção só serve pra reagir rápido (soltar o Shift para o gasto no
	  mesmo instante, sem esperar o corpo desacelerar).

	COMO O SPRINT É BLOQUEADO
	  Sem reescrever o pacote: o script Crouching já lê dois Attributes do
	  HumanoidRootPart antes de deixar correr --
	    "CanSprint"       (false = nem começa a correr)
	    "ForceStopSprint" (true = para a corrida em andamento)
	  Este módulo escreve os dois. É o mesmo contrato que o StaminaSystem
	  original do pacote usava, então o Crouching não precisou mudar.

	ATRIBUTO DO PERSONAGEM
	  Stamina alta gasta MAIS DEVAGAR e recupera MAIS RÁPIDO -- as duas
	  faixas em GameConfig.Characters (StaminaDrain é invertida de propósito).
	  Marina/Rafael (Stamina 93-95) correm quase o dobro do tempo de
	  Diego (Stamina 20).

	VALOR PRO CLIENTE
	  O fôlego atual vai como Attribute "Stamina" no Player e o teto como
	  "StaminaMax" (hoje 100). Attributes replicam sozinhos -- o anel em
	  client/StaminaHUD só lê os dois e divide um pelo outro, sem remote de
	  volta e sem escala própria.

	INTENÇÃO (Remotes.SprintIntent)
	  O cliente manda true enquanto o pacote de movimento está DE FATO em
	  corrida (Attribute local "IsSprinting" do HumanoidRootPart) -- não só
	  "Shift apertado". Esse Attribute é escrito pelo cliente e NÃO replica
	  pro servidor; por isso ele chega pela intenção.

	Uso (uma vez no boot):
		require(script.StaminaSystem).Init()
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage.Modules.GameConfig)
local Remotes = require(ReplicatedStorage.Modules.Remotes)
local StatScaling = require(ReplicatedStorage.Modules.StatScaling)
local FearSystem = require(script.Parent.FearSystem)
local MatchStateService = require(script.Parent.MatchStateService)

local StaminaSystem = {}

-- Amostra já calculada no loop de stamina; consumidores não precisam de outro Heartbeat.
-- (player, character, humanoid, root, horizontalSpeed, walkBase)
StaminaSystem.MovementSampled = Instance.new("BindableEvent")

local MAX = 100
local TICK = 0.05 -- 20 Hz: portão da corrida e HUD mudam no mesmo instante perceptível
local JUMP_COST = 30 -- pulo é uma reserva de emergência, não uma ação gratuita

-- Fração do WalkSpeed atual acima da qual consideramos que ESTÁ correndo.
-- O sprint do pacote é ~1.9x o andar, então 1.35x separa bem andar de correr
-- sem depender de números fixos (o WalkSpeed varia com Velocidade do personagem).
local SPRINT_SPEED_RATIO = GameConfig.Characters.SprintSpeedRatio
local initialized = false

type State = {
	value: number, -- fôlego 0..100
	intent: boolean, -- cliente segurando Shift
	exhausted: boolean, -- zerou: só volta a correr em StaminaMinToSprint
	idleFor: number, -- segundos sem gastar (gate do RegenDelay)
	wasAirborne: boolean,
}

local states: { [Player]: State } = {}

--------------------------------------------------------------------------------
-- Helpers
--------------------------------------------------------------------------------

local function getState(player: Player): State
	local state = states[player]
	if not state then
		state = { value = MAX, intent = false, exhausted = false, idleFor = 0, wasAirborne = false }
		states[player] = state
	end
	return state
end

-- Só escreve quando MUDA: Attribute replica pra todos os clientes, e escrever
-- o mesmo valor 10x por segundo pra cada jogador é tráfego à toa.
local function setIfChanged(instance: Instance, name: string, value: unknown)
	if instance:GetAttribute(name) ~= value then
		instance:SetAttribute(name, value)
	end
end

local function publish(player: Player, state: State)
	-- Uma casa decimal evita que a HUD pareça ficar parada entre saltos inteiros,
	-- mas limita atualizações desnecessárias de Attribute pela rede.
	setIfChanged(player, "StaminaMax", MAX)
	setIfChanged(player, "Stamina", math.floor(math.clamp(state.value, 0, MAX) * 10 + 0.5) / 10)
	setIfChanged(player, "StaminaExausto", state.exhausted or nil)
end

local function setSprintGate(character: Model, canSprint: boolean, forceStop: boolean)
	local root = character:FindFirstChild("HumanoidRootPart")
	if root then
		setIfChanged(root, "CanSprint", canSprint)
		setIfChanged(root, "ForceStopSprint", forceStop or nil)
	end
end

local function horizontalSpeed(root: BasePart): number
	local v = root.AssemblyLinearVelocity
	return Vector3.new(v.X, 0, v.Z).Magnitude
end

--------------------------------------------------------------------------------
-- Loop
--------------------------------------------------------------------------------

local function step(dt: number)
	for _, player in Players:GetPlayers() do
		local state = getState(player)
		if not MatchStateService.IsGameplayEnabled(player) then
			state.intent = false
			state.idleFor = 0
			state.exhausted = false
			state.value = MAX
			local character = player.Character
			if character then setSprintGate(character, false, true) end
			publish(player, state)
			continue
		end
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		local root = character and character:FindFirstChild("HumanoidRootPart")

		if not character or not humanoid or not root or not root:IsA("BasePart") or humanoid.Health <= 0 then
			-- Sem corpo vivo: recupera devagar e não trava nada.
			state.value = math.min(MAX, state.value + StatScaling.StaminaRegen(player) * dt)
			if state.value >= GameConfig.Characters.StaminaMinToSprint then
				state.exhausted = false
			end
			publish(player, state)
			continue
		end

		local humanoidState = humanoid:GetState()
		local airborne = humanoidState == Enum.HumanoidStateType.Jumping
			or humanoidState == Enum.HumanoidStateType.Freefall
		local jumpStarted = humanoidState == Enum.HumanoidStateType.Jumping
			or (humanoidState == Enum.HumanoidStateType.Freefall and root.AssemblyLinearVelocity.Y > 4)
		if jumpStarted and not state.wasAirborne and character:GetAttribute("PowerInfiniteStamina") ~= true then
			state.value = math.max(0, state.value - JUMP_COST)
			state.idleFor = 0
			if state.value <= 0 then state.exhausted = true end
		end
		state.wasAirborne = airborne

		-- CORRENDO DE VERDADE? intenção + velocidade real acima do limiar.
		-- O limiar sai do WalkSpeed do próprio personagem, então vale pra
		-- todo mundo (Rafael anda mais rápido que Diego CORRE, e ainda assim
		-- cada um gasta só quando está de fato em sprint).
		local walkBase = StatScaling.WalkSpeed(player)
		local speed = horizontalSpeed(root)
		StaminaSystem.MovementSampled:Fire(player, character, humanoid, root, speed, walkBase)
		-- Em múltiplos de walkBase o pacote anda 1.0, trota 1.25 e CORRE 1.92
		-- (12/15/23 sobre NormalSpeed 12, e SpeedMul = walkBase/12). Só a
		-- velocidade não bastava: curva, tranco, ladeira ou rampa derrubam a
		-- velocidade abaixo de 1.35 por alguns frames e o fôlego congelava
		-- enquanto o personagem seguia correndo -- era isso que fazia a corrida
		-- inteira gastar só um pedaço da barra.
		-- A intenção agora é o estado REAL de corrida do pacote (o cliente lê o
		-- IsSprinting local e manda por SprintIntent). Antes este módulo lia o
		-- Attribute IsSprinting direto do HumanoidRootPart -- mas ele é
		-- escrito pelo CLIENTE e nunca replica pro servidor, então era sempre
		-- nil: numa curva/tranco o gasto parava e, depois do RegenDelay, o
		-- fôlego SUBIA com o personagem ainda correndo (a barra "descolava" do
		-- que o jogador via). A intenção só SOMA casos de gasto: quem mentir
		-- "true" só perde fôlego; mentir "false" não dá corrida grátis porque
		-- o portão CanSprint continua fechando no zero.
		local moving = speed > walkBase * SPRINT_SPEED_RATIO
			or (state.intent and speed > walkBase * 0.6)
		local shadowBusy = character:GetAttribute("ShadowRushBusy") == true
		local grabLocked = character:GetAttribute("GrabLocked") == true
		if character:GetAttribute("PowerInfiniteStamina") == true then
			state.value, state.exhausted, state.idleFor = MAX, false, 0
			setSprintGate(character, not shadowBusy and not grabLocked
				and character:GetAttribute("PowerStunned") ~= true, shadowBusy or grabLocked)
			publish(player, state)
			continue
		end
		local sprinting = state.intent
			and moving and not state.exhausted and not shadowBusy and not grabLocked

		if sprinting then
			state.idleFor = 0
			state.value = math.max(0, state.value - StatScaling.StaminaDrain(player) * dt)
			if state.value <= 0 then
				state.exhausted = true
			end
		else
			state.idleFor += dt
			if state.idleFor >= GameConfig.Characters.StaminaRegenDelay then
				state.value = math.min(MAX, state.value + StatScaling.StaminaRegen(player)
					* FearSystem.GetStaminaRegenMultiplier(player) * dt)
			end
			if state.exhausted and state.value >= GameConfig.Characters.StaminaMinToSprint then
				state.exhausted = false
			end
		end

		-- Portão do sprint (contrato que o Crouching do pacote já lê).
		setSprintGate(character, not state.exhausted and not shadowBusy and not grabLocked,
			state.exhausted or shadowBusy or grabLocked)
		publish(player, state)
	end
end

--------------------------------------------------------------------------------
-- API
--------------------------------------------------------------------------------

--[[ Get(player) -- fôlego atual 0..Max(). ]]
function StaminaSystem.Get(player: Player): number
	return getState(player).value
end

--[[ Max() -- teto do fôlego (o mesmo publicado em "StaminaMax"). ]]
function StaminaSystem.Max(): number
	return MAX
end

--[[ Refill(player) -- enche o fôlego (respawn, item, começo de partida). ]]
function StaminaSystem.Refill(player: Player)
	local state = getState(player)
	state.value = MAX
	state.exhausted = false
	state.idleFor = 0
	publish(player, state)
end

function StaminaSystem.Init()
	if initialized then return end
	initialized = true
	Remotes.SprintIntent.OnServerEvent:Connect(function(player: Player, holding: unknown)
		getState(player).intent = holding == true
	end)

	local function watchPlayer(player: Player)
		StaminaSystem.Refill(player)
		player.CharacterAdded:Connect(function()
			StaminaSystem.Refill(player)
		end)
	end

	for _, player in Players:GetPlayers() do
		watchPlayer(player)
	end
	Players.PlayerAdded:Connect(watchPlayer)
	Players.PlayerRemoving:Connect(function(player)
		states[player] = nil
	end)

	local acc = 0
	RunService.Heartbeat:Connect(function(dt)
		acc += dt
		if acc < TICK then
			return
		end
		step(acc)
		acc = 0
	end)
end

return StaminaSystem
