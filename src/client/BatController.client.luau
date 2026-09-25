--!strict
--[[
	BatController
	Animacao e golpes do Taco de Beisebol (Attribute "TacoBeisebol") e do Pe de
	cabra (Attribute "LancaDeBambu"): os dois usam os MESMOS clips de
	BaseballBatConfig.Animations.

	POSE DE SEGURAR: o clip Idle publicado do Taco toca em loop enquanto a arma
	está equipada e define toda a postura do personagem.

	GOLPES: no Taco, clique curto toca Hit (golpe leve); segurar o botao ate
	BatConfig.HoldThreshold toca Finish (golpe pesado). Armas sem perfil Heavy
	(Pe de cabra) golpeiam com Hit assim que o botao e apertado. O remote so pede
	o INICIO do golpe, com "Light"/"Heavy"; WeaponSystem abre a janela de hitbox
	no servidor. AttackStart marker e usado quando existir; sem marker ha fallback.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ContentProvider = game:GetService("ContentProvider")
local UserInputService = game:GetService("UserInputService")

local BatConfig = require(ReplicatedStorage.Modules.BaseballBatConfig)
local Rules = require(ReplicatedStorage.Modules.CombatRules)
local Remotes = require(ReplicatedStorage.Modules.Remotes)

type Kind = "Hit" | "Finish"

local ITEM_ATTRIBUTES = { "TacoBeisebol", "LancaDeBambu" }
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
	for _, name in { "Idle", "Hit", "Finish" } do
		local id = BatConfig.Animations[name]
		local animation = Instance.new("Animation")
		animation.Name = "Taco" .. name
		animation.AnimationId = id
		local ok, loaded = pcall(function()
			return activeAnimator:LoadAnimation(animation)
		end)
		if ok and loaded then
			local track = loaded :: AnimationTrack
			track.Priority = if name == "Idle" then Enum.AnimationPriority.Action else Enum.AnimationPriority.Action3
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

-- Mantém exatamente o Idle publicado para o taco. Ele controla a postura
-- enquanto equipado e volta sozinho ao fim do golpe.
local function ensureIdlePlaying(idle: AnimationTrack)
	idle.Priority = Enum.AnimationPriority.Action
	idle.Looped = true
	if not idle.IsPlaying then
		idle:Play(BatConfig.AnimationFadeTime, 1, 1)
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
	local definition = Rules.Definition(tool)
	local hasHeavy = definition ~= nil and definition.Heavy ~= nil
	local maxImpact = if hasHeavy then math.max(impactDelay("Hit"), impactDelay("Finish")) else impactDelay("Hit")
	if os.clock() < math.max(busyUntil, serverReadyAt + BatConfig.CooldownPadding - maxImpact) then
		return
	end
	if not hasHeavy then
		swing("Hit")
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
	if not instance:IsA("Tool") then
		return false
	end
	for _, attribute in ITEM_ATTRIBUTES do
		if instance:GetAttribute(attribute) == true then
			return true
		end
	end
	return false
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

-- Estados que tomam o corpo (agarrado, dano, rastejar...) interrompem os golpes
-- e cancelam o agendado.
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
			else
				ensureIdlePlaying(idle)
			end
		end
	end
end)

player.CharacterAdded:Connect(watchCharacter)
if player.Character then
	watchCharacter(player.Character)
end
