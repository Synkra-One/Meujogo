--!strict
--[[
	BatController
	Animacao e golpes do Taco de Beisebol (Tool com Attribute "TacoBeisebol").

	DUAS ANIMACOES AO MESMO TEMPO: o clip Idle toca em loop na mesma camada
	Movement do Animate/pacote de movimento. O peso cai enquanto o personagem
	anda/corre, entao o walk/run continua visivel mesmo se o asset do Taco tiver
	algum keyframe extra no tronco ou nas pernas. O clip deve preferencialmente
	conter apenas a camada superior do R6, mas a mistura tambem protege clips
	publicados com keyframes de corpo inteiro.

	GOLPES: clique curto toca Hit (golpe leve); segurar o botao ate
	BatConfig.HoldThreshold toca Finish (golpe pesado). O remote so pede o INICIO
	do golpe, com "Light"/"Heavy"; WeaponSystem abre a janela de hitbox no
	servidor. AttackStart marker e usado quando existir; sem marker ha fallback.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ContentProvider = game:GetService("ContentProvider")
local UserInputService = game:GetService("UserInputService")

local BatConfig = require(ReplicatedStorage.Modules.BaseballBatConfig)
local Rules = require(ReplicatedStorage.Modules.CombatRules)
local Remotes = require(ReplicatedStorage.Modules.Remotes)

type Kind = "Hit" | "Finish"

local ITEM_ATTRIBUTE = "TacoBeisebol"
-- Mesma lista da FlashlightPose: estados que tomam o controle do corpo.
local BLOCKING_FLAGS = { "GrabLocked", "ShadowRushBusy", "TeleportBusy", "PowerStunned", "FearTripping" }

local player = Players.LocalPlayer

local tool: Tool? = nil
local character: Model? = nil
local humanoid: Humanoid? = nil
local tracks: { [string]: AnimationTrack } = {}
local animations: { Animation } = {}
local toolConnections: { RBXScriptConnection } = {}
local characterConnections: { RBXScriptConnection } = {}

local swingId = 0 -- invalida o impacto agendado de um golpe cancelado
local pressId = 0
local pressPending = false
local busyUntil = 0 -- fim da animacao agendada: cliques antes disso sao ignorados
local serverReadyAt = 0 -- estimativa de quando o servidor aceita o proximo golpe

local function timingFor(kind: Kind)
	return if kind == "Hit" then BatConfig.Swings.Hit else BatConfig.Swings.Finish
end

local function clipLength(kind: Kind): number
	local track = tracks[kind]
	if track and track.Length > 0 then
		return track.Length
	end
	return timingFor(kind).FallbackLength
end

local function impactDelay(kind: Kind): number
	local track = tracks[kind]
	if track and track.Length > 0 then
		return track.Length * timingFor(kind).ImpactFraction
	end
	return timingFor(kind).FallbackImpact
end

local function blocked(): boolean
	local char, hum = character, humanoid
	if not char or not hum or hum.Health <= 0 then
		return true
	end
	local combatState = char:GetAttribute("CombatAnimationState")
	if combatState == "Hurt" or combatState == "Death" then
		return true
	end
	for _, flag in BLOCKING_FLAGS do
		if char:GetAttribute(flag) == true then
			return true
		end
	end
	local root = char:FindFirstChild("HumanoidRootPart")
	return root ~= nil and root:GetAttribute("IsCrawling") == true
end

local function loadTracks(hum: Humanoid)
	local animator = hum:FindFirstChildOfClass("Animator")
	if not animator then
		local created = Instance.new("Animator")
		created.Parent = hum
		animator = created
	end
	local activeAnimator = animator :: Animator
	for name, id in BatConfig.Animations do
		local animation = Instance.new("Animation")
		animation.Name = "Taco" .. name
		animation.AnimationId = id
		local ok, loaded = pcall(function()
			return activeAnimator:LoadAnimation(animation)
		end)
		if ok and loaded then
			local track = loaded :: AnimationTrack
			-- Idle precisa compartilhar a prioridade da locomocao. Action aqui
			-- faria o clip inteiro do Taco ganhar de walk/run, mesmo quando o
			-- asset tivesse sido publicado com keyframes das pernas.
			track.Priority = if name == "Idle" then Enum.AnimationPriority.Movement else Enum.AnimationPriority.Action2
			track.Looped = name == "Idle"
			tracks[name] = track
			table.insert(animations, animation)
		else
			warn(string.format("[Taco] Nao foi possivel carregar a animacao %s (%s): %s", name, id, tostring(loaded)))
			animation:Destroy()
		end
	end
	-- Preload faz track.Length ficar valido antes do primeiro golpe.
	local toPreload = table.clone(animations)
	task.spawn(function()
		pcall(function()
			ContentProvider:PreloadAsync(toPreload)
		end)
	end)
	task.delay(BatConfig.AnimationLoadWarningDelay, function()
		for name, track in tracks do
			if track.Length == 0 then
				warn(string.format("[Taco] A animacao %s nao carregou. Confirme R6 e a permissao do asset para esta experiencia.", name))
			end
		end
	end)
end

local function moving(): boolean
	local hum = humanoid
	if not hum or hum.Health <= 0 then
		return false
	end
	if hum.MoveDirection.Magnitude > 0.08 then
		return true
	end
	local char = character
	local root = char and char:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		return (root.AssemblyLinearVelocity * Vector3.new(1, 0, 1)).Magnitude > 0.65
	end
	return false
end

local function ensureIdlePlaying(idle: AnimationTrack)
	local isMoving = moving()
	-- Parado, o Idle do Taco assume o corpo inteiro para a pose ficar
	-- exatamente como foi criada. Em movimento, volta para Movement e mistura
	-- com walk/run para não bloquear as pernas.
	idle.Priority = if isMoving then Enum.AnimationPriority.Movement else Enum.AnimationPriority.Action
	local weight = if isMoving then BatConfig.IdleMovingWeight else 1
	if not idle.IsPlaying then
		idle:Play(BatConfig.AnimationFadeTime, weight, 1)
	else
		idle:AdjustWeight(weight, BatConfig.AnimationFadeTime)
	end
end

local function clearTool()
	swingId += 1
	pressId += 1
	pressPending = false
	busyUntil = 0
	serverReadyAt = 0
	for _, connection in toolConnections do
		connection:Disconnect()
	end
	table.clear(toolConnections)
	for _, track in tracks do
		track:Stop(0)
		track:Destroy()
	end
	table.clear(tracks)
	for _, animation in animations do
		animation:Destroy()
	end
	table.clear(animations)
	tool = nil
end

local function inputBlocked(): boolean
	return UserInputService:GetFocusedTextBox() ~= nil or player:GetAttribute("CursorLivre") == true
end

local function swing(kind: Kind)
	local currentTool, currentCharacter = tool, character
	if not currentTool or not currentCharacter or blocked() then
		return
	end
	local definition = Rules.Definition(currentTool)
	if not definition then
		return
	end
	local variant = if kind == "Finish" then "Heavy" else "Light"
	local profile = Rules.Profile(definition, variant)
	local strikeDelay = impactDelay(kind)

	-- Comeca no mais cedo em que o impacto ja encontra o servidor liberado.
	local now = os.clock()
	local startAt = math.max(now, busyUntil, serverReadyAt + BatConfig.CooldownPadding - strikeDelay)
	busyUntil = startAt + clipLength(kind)
	-- O servidor recebe o inicio do golpe, portanto o cooldown começa aqui;
	-- a janela de acerto continua inteiramente calculada no servidor.
	serverReadyAt = startAt + profile.Cooldown

	swingId += 1
	local thisSwing = swingId
	local function stillValid(): boolean
		return swingId == thisSwing and tool == currentTool and currentTool.Parent == currentCharacter
	end

	task.delay(startAt - now, function()
		if not stillValid() then
			return
		end
		local track = tracks[kind]
		local requested = false
		local function requestServerAttack()
			if requested or not stillValid() or not Rules.CanAttack(player) then
				return
			end
			requested = true
			Remotes.WeaponAttack:FireServer(currentTool, variant)
		end
		if track then
			-- Clips publicados com AttackStart sincronizam a solicitacao com a
			-- animacao. Os clips atuais sem marker mantem o mesmo comportamento
			-- via um fallback curtissimo e o servidor ainda valida a janela.
			track:GetMarkerReachedSignal("AttackStart"):Once(requestServerAttack)
			track:Stop(0)
			track:Play(BatConfig.AnimationFadeTime, 1, 1)
			task.delay(BatConfig.MarkerStartFallback, requestServerAttack)
		else
			requestServerAttack()
		end
	end)
end

local function onActivated()
	if not tool or inputBlocked() or blocked() then
		return
	end
	local maxImpact = math.max(impactDelay("Hit"), impactDelay("Finish"))
	if os.clock() < math.max(busyUntil, serverReadyAt + BatConfig.CooldownPadding - maxImpact) then
		return
	end
	pressId += 1
	local thisPress = pressId
	pressPending = true
	task.delay(BatConfig.HoldThreshold, function()
		if pressPending and pressId == thisPress then
			pressPending = false
			swing("Finish")
		end
	end)
end

local function onDeactivated()
	if pressPending then
		pressPending = false
		swing("Hit")
	end
end

local function setTool(newTool: Tool)
	if tool == newTool then
		return
	end
	clearTool()
	local char = newTool.Parent
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if not char or not char:IsA("Model") or not hum then
		return
	end
	tool, character, humanoid = newTool, char, hum
	loadTracks(hum)
	table.insert(toolConnections, newTool.Activated:Connect(onActivated))
	table.insert(toolConnections, newTool.Deactivated:Connect(onDeactivated))
	local idle = tracks.Idle
	if idle and not blocked() then
		ensureIdlePlaying(idle)
	end
end

local function isBat(instance: Instance): boolean
	return instance:IsA("Tool") and instance:GetAttribute(ITEM_ATTRIBUTE) == true
end

local function watchCharacter(newCharacter: Model)
	for _, connection in characterConnections do
		connection:Disconnect()
	end
	table.clear(characterConnections)
	clearTool()
	for _, child in newCharacter:GetChildren() do
		if isBat(child) then
			setTool(child :: Tool)
		end
	end
	table.insert(characterConnections, newCharacter.ChildAdded:Connect(function(child)
		if isBat(child) then
			setTool(child :: Tool)
		end
	end))
	table.insert(characterConnections, newCharacter.ChildRemoved:Connect(function(child)
		if child == tool then
			clearTool()
		end
	end))
end

-- Idle so toca livre; estados que tomam o corpo (agarrado, dano, rastejar...)
-- interrompem o taco por completo e cancelam o golpe agendado.
task.spawn(function()
	while true do
		task.wait(BatConfig.PollInterval)
		local idle = tracks.Idle
		if tool and idle then
			if blocked() then
				swingId += 1
				busyUntil = 0
				for _, track in tracks do
					if track.IsPlaying then
						track:Stop(BatConfig.AnimationFadeTime)
					end
				end
			elseif not idle.IsPlaying then
				ensureIdlePlaying(idle)
			else
				local isMoving = moving()
				idle.Priority = if isMoving then Enum.AnimationPriority.Movement else Enum.AnimationPriority.Action
				idle:AdjustWeight(if isMoving then BatConfig.IdleMovingWeight else 1, BatConfig.AnimationFadeTime)
			end
		end
	end
end)

player.CharacterAdded:Connect(watchCharacter)
if player.Character then
	watchCharacter(player.Character)
end
