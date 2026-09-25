--!strict
--[[
	FallEffects
	Substitui o LocalScript "FallSystem" que veio no "Ultimate R6 Movement
	System" (removido de src/MovementPack/StarterCharacterScripts).

	POR QUE FOI SUBSTITUÍDO -- era ele que travava o boneco:
	O FallSystem original, ao pousar, fazia `Humanoid.WalkSpeed = 0`, tocava
	uma animação de pouso (ID privado do autor do pacote -> `:Play()` avisa
	"not authorized") e chamava um efeito de poeira, e SÓ DEPOIS de um
	`task.wait` restaurava `WalkSpeed = 16`. Como o handler de StateChanged
	não tinha proteção nenhuma, qualquer erro no meio (animação sem permissão,
	partícula faltando) estourava a função ANTES da linha que devolve a
	velocidade -> WalkSpeed ficava 0 pra sempre. O boneco continuava animando
	e inclinando (outros scripts), mas não andava. Ainda por cima isso
	disparava logo no primeiro pouso, no spawn.

	O QUE ESTE FAZ (igual, mas à prova de erro):
	  - 3 faixas de queda pela altura: pouso normal / queda curta / queda longa
	  - toca as animações de pouso do pacote SE elas carregarem (pcall); se
	    não, só pula -- nunca trava
	  - O pouso trava a locomoção por menos de um segundo. A "cambaleada" no
	    pouso forte é uma lentidão temporária que se restaura sozinha por `task.delay` com teto de tempo,
	    e respeita quem já é dono do WalkSpeed (o script Crouching do pacote)
	  - shake de câmera leve
	  - dano de queda: manda a DISTÂNCIA pro servidor (ReplicatedStorage.
	    FallDamageEvent -> DamageSystem.onFallDamage), nunca o dano
	  - IGNORA a "queda" do spawn (primeiro pouso, ou queda que durou menos
	    que SPAWN_GRACE)

	Bobbing de câmera NÃO está aqui -- é o LocalScript "Bobbing Camera"
	(StarterGui), que continua intacto.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Debris = game:GetService("Debris")

local LocalPlayer = Players.LocalPlayer

--------------------------------------------------------------------------------
-- Config (mesmos números do FallSystem original)
--------------------------------------------------------------------------------

local MIN_DAMAGE_HEIGHT = 4 -- abaixo disso: pouso normal, sem dano nem cambaleada
local HIGH_FALL_THRESHOLD = 15 -- acima disso: queda longa (dano + cambaleada)
local SPAWN_GRACE = 0.35 -- s de Freefall abaixo disso = não conta (assentando no spawn)

local STAGGER_SLOWDOWN = 0.45 -- fração da velocidade durante a cambaleada da queda longa
local STAGGER_TIME = 0.9 -- s de cambaleada (com teto -- ver applyStagger)
local LANDING_LOCK_MIN = 0.32 -- reação curta mesmo em pousos pequenos

-- A queda no ar ja e controlada pelo Animate. Este script assume apenas o
-- pouso, sempre com o clipe de aterrissagem escolhido pelo jogo.
local FALL_ANIM_LAND = "rbxassetid://127719647307661"

--------------------------------------------------------------------------------
-- Recursos do pacote (podem faltar -- tudo tolerante a nil)
--------------------------------------------------------------------------------

local fallSounds = SoundService:FindFirstChild("FallSounds")
local soundSmall = fallSounds and fallSounds:FindFirstChild("SmallFall")
local soundLarge = fallSounds and fallSounds:FindFirstChild("LargeFall")

local dustTemplate: Instance? = nil
do
	local folder = ReplicatedStorage:FindFirstChild("FallSystem")
	local dust = folder and folder:FindFirstChild("Dust")
	if dust and dust:IsA("BasePart") then
		dustTemplate = dust
	end
end

local fallDamageEvent: RemoteEvent? = nil

local function getFallDamageEvent(): RemoteEvent?
	if fallDamageEvent and fallDamageEvent.Parent then
		return fallDamageEvent
	end
	local found = ReplicatedStorage:FindFirstChild("FallDamageEvent")
	if found and found:IsA("RemoteEvent") then
		fallDamageEvent = found
		return found
	end
	return nil
end

task.spawn(function()
	local found = ReplicatedStorage:WaitForChild("FallDamageEvent", 10)
	if found and found:IsA("RemoteEvent") then
		fallDamageEvent = found
	end
end)

--------------------------------------------------------------------------------
-- Estado por character
--------------------------------------------------------------------------------

local humanoid: Humanoid? = nil
local rootPart: BasePart? = nil
local tracks: { [string]: AnimationTrack } = {}
local freefallStart = 0
local freefallStartY = 0
local freefallPeakY = 0
local staggerToken = 0
local landingToken = 0
local movementLockToken = 0

-- onLanded é chamado por onCharacter (StateChanged) mas o corpo vem depois.
local onLanded: () -> ()

local function loadTrack(anim: Animator, id: string): AnimationTrack?
	local animation = Instance.new("Animation")
	animation.AnimationId = id
	local ok, track = pcall(function()
		return anim:LoadAnimation(animation)
	end)
	if ok and track then
		track.Looped = false
		-- Acima do Hurt (Action2): uma queda alta causa dano no mesmo frame e,
		-- sem esta prioridade, a reacao de dano escondia todo o pouso.
		track.Priority = Enum.AnimationPriority.Action3
		return track
	end
	return nil
end

local function onCharacter(character: Model)
	tracks = {}
	freefallStart = 0
	freefallPeakY = 0
	staggerToken += 1
	landingToken += 1

	local hum = character:FindFirstChildOfClass("Humanoid") or character:WaitForChild("Humanoid", 10)
	humanoid = if hum and hum:IsA("Humanoid") then hum else nil
	local hrp = character:FindFirstChild("HumanoidRootPart") or character:WaitForChild("HumanoidRootPart", 10)
	rootPart = if hrp and hrp:IsA("BasePart") then hrp else nil

	local currentHumanoid = humanoid
	if not currentHumanoid then
		return
	end

	local animator = currentHumanoid:FindFirstChildOfClass("Animator")
	if animator then
		tracks.Land = loadTrack(animator, FALL_ANIM_LAND) :: AnimationTrack
	end

	currentHumanoid.StateChanged:Connect(function(_, newState)
		if currentHumanoid ~= humanoid then
			return -- character já trocou
		end
		if newState == Enum.HumanoidStateType.Freefall then
			-- Microtrocas de estado podem acontecer no mesmo salto. Nao reinicie
			-- a medicao, senao uma queda alta vira uma queda de poucos centimetros.
			if freefallStart == 0 then
				freefallStart = os.clock()
				freefallStartY = if rootPart then rootPart.Position.Y else 0
				freefallPeakY = freefallStartY
			end
		elseif newState == Enum.HumanoidStateType.Landed
			or newState == Enum.HumanoidStateType.Running
			or newState == Enum.HumanoidStateType.RunningNoPhysics
			or newState == Enum.HumanoidStateType.GettingUp then
			-- Em relevos o Humanoid frequentemente passa direto de Freefall para
			-- Running, sem emitir Landed. O defer deixa FloorMaterial atualizar.
			task.defer(onLanded)
		end
	end)
end

--------------------------------------------------------------------------------
-- Efeitos (nenhum deles pode travar o jogador)
--------------------------------------------------------------------------------

local function playOnce(track: AnimationTrack?, stopAfter: number)
	if not track then
		return
	end
	local landingRoot = rootPart
	landingToken += 1
	local myToken = landingToken
	if landingRoot then
		landingRoot:SetAttribute("IsLanding", true)
	end
	-- A animação de pouso precisa ter alguns frames de peso antes de aceitar
	-- outra direção. WalkSpeed zero é temporário e restaurado com guarda, para
	-- não atropelar Crouching ou outro sistema que tenha assumido o controle.
	local landingHumanoid = humanoid
	local landingCharacter = landingHumanoid and landingHumanoid.Parent
	local previousSpeed = if landingHumanoid then landingHumanoid.WalkSpeed else 0
	local previousRotate = if landingHumanoid then landingHumanoid.AutoRotate else true
	movementLockToken += 1
	local lockToken = movementLockToken
	if landingHumanoid and previousSpeed > 0.1 then
		landingHumanoid.WalkSpeed = 0
		landingHumanoid.AutoRotate = false
	end
	if landingCharacter and landingCharacter:IsA("Model") then
		landingCharacter:SetAttribute("LandingLocked", true)
	end
	pcall(function()
		track:Stop(0)
		track:Play(0.1)
	end)
	task.delay(stopAfter, function()
		pcall(function()
			track:Stop(0.2)
		end)
		if landingToken == myToken and landingRoot and landingRoot.Parent then
			landingRoot:SetAttribute("IsLanding", false)
		end
		if movementLockToken == lockToken and humanoid == landingHumanoid and landingHumanoid
			and landingHumanoid.Parent and math.abs(landingHumanoid.WalkSpeed) < 0.01 then
			landingHumanoid.WalkSpeed = previousSpeed
			landingHumanoid.AutoRotate = previousRotate
		end
		if movementLockToken == lockToken and landingCharacter and landingCharacter.Parent then
			landingCharacter:SetAttribute("LandingLocked", nil)
		end
	end)
end

local function spawnDust()
	local template = dustTemplate
	local hrp = rootPart
	if not template or not hrp then
		return
	end
	local ok, effect = pcall(function()
		return (template :: BasePart):Clone()
	end)
	if not ok or not effect then
		return
	end
	;(effect :: BasePart).Anchored = true
	;(effect :: BasePart).CanCollide = false
	;(effect :: BasePart).Transparency = 1
	;(effect :: BasePart).Position = hrp.Position - Vector3.new(0, 3, 0)
	effect.Parent = workspace
	for _, descendant in effect:GetDescendants() do
		if descendant:IsA("ParticleEmitter") then
			pcall(function()
				descendant:Emit(12)
			end)
		end
	end
	Debris:AddItem(effect, 2)
end

local function shakeCamera(magnitude: number, duration: number)
	local camera = workspace.CurrentCamera
	if not camera then
		return
	end
	local start = os.clock()
	local seed = math.random(0, 1000)
	RunService:BindToRenderStep("FallImpactCamera", Enum.RenderPriority.Camera.Value + 6, function()
		local elapsed = os.clock() - start
		if elapsed >= duration then
			RunService:UnbindFromRenderStep("FallImpactCamera")
			return
		end
		camera = workspace.CurrentCamera
		if not camera or camera.CameraType ~= Enum.CameraType.Custom then return end
		local envelope = (1 - elapsed / duration) ^ 2
		local ox = (math.noise(elapsed * 8, seed, 0)) * magnitude * envelope
		local oy = (math.noise(elapsed * 8, seed + 50, 0)) * magnitude * envelope
		camera.CFrame = camera.CFrame * CFrame.new(ox, oy, 0)
	end)
end

-- Cambaleada: reduz a velocidade e devolve sozinha. Guarda o valor de ANTES
-- e só restaura se ninguém tiver mexido no meio -- e mesmo que algo dê errado,
-- o teto de tempo garante que volta.
local function applyStagger()
	local currentHumanoid = humanoid
	if not currentHumanoid then
		return
	end
	local before = currentHumanoid.WalkSpeed
	if before <= 0.1 then
		return -- já tá parado por outro motivo (transição) -- não mexe
	end

	staggerToken += 1
	local myToken = staggerToken
	currentHumanoid.WalkSpeed = before * STAGGER_SLOWDOWN

	task.delay(math.min(STAGGER_TIME, 2), function()
		if humanoid == currentHumanoid and staggerToken == myToken then
			-- Só devolve se o valor atual ainda for o "abaixado" -- se o
			-- Crouching (dono do WalkSpeed) já reassumiu, não desfaz nada.
			if math.abs(currentHumanoid.WalkSpeed - before * STAGGER_SLOWDOWN) < 0.01 then
				currentHumanoid.WalkSpeed = before
			end
		end
	end)
end

--------------------------------------------------------------------------------
-- Pouso
--------------------------------------------------------------------------------

function onLanded()
	local currentHumanoid: Humanoid? = humanoid
	local hrp: BasePart? = rootPart
	if not currentHumanoid or not hrp then
		return
	end

	if freefallStart == 0 then
		return
	end
	if currentHumanoid.FloorMaterial == Enum.Material.Air then
		return -- StateChanged chegou antes do contato fisico; o Heartbeat tenta de novo.
	end

	-- Limpa antes de qualquer retorno. Assim um contato curto no spawn nao e
	-- reinterpretado como uma queda longa alguns frames depois.
	local startedAt = freefallStart
	freefallStart = 0
	local airborneTime = os.clock() - startedAt
	if airborneTime < SPAWN_GRACE then
		return
	end

	local fallDistance = math.max(freefallStartY, freefallPeakY) - hrp.Position.Y
	freefallPeakY = 0
	if fallDistance <= MIN_DAMAGE_HEIGHT then
		playOnce(tracks.Land, math.max(0.5, LANDING_LOCK_MIN))
		return
	end

	if fallDistance <= HIGH_FALL_THRESHOLD then
		-- Queda curta: efeito, sem dano, sem travar.
		if soundSmall and soundSmall:IsA("Sound") then
			soundSmall:Play()
		end
		playOnce(tracks.Land, math.max(0.7, LANDING_LOCK_MIN))
		spawnDust()
		shakeCamera(0.15, 0.35)
		return
	end

	-- Queda longa: efeito forte, cambaleada que se cura, e dano no servidor.
	if soundLarge and soundLarge:IsA("Sound") then
		soundLarge:Play()
	end
	playOnce(tracks.Land, math.max(0.9, LANDING_LOCK_MIN))
	spawnDust()
	shakeCamera(math.min(0.2 + fallDistance / 10, 2), math.min(0.3 + fallDistance / 50, 0.7))
	applyStagger()

	local event = getFallDamageEvent()
	if event then
		event:FireServer(fallDistance)
	end
end

-- Fallback independente de StateChanged. E essencial em encostas e relevos,
-- onde a maquina do Humanoid pode nao passar pelo estado Landed.
RunService.Heartbeat:Connect(function()
	local currentHumanoid = humanoid
	local hrp = rootPart
	if not currentHumanoid or not hrp then
		return
	end
	-- Modo voar de teste (FlyTest): no ar de propósito, nada de altura de queda.
	-- Sem isto o fallback abaixo contava a altura do voo e matava no pouso.
	if hrp.Parent and hrp.Parent:GetAttribute("Voando") == true then
		freefallStart = 0
		return
	end
	local state = currentHumanoid:GetState()
	local floor = currentHumanoid.FloorMaterial
	local airborneState = state == Enum.HumanoidStateType.Freefall
		or state == Enum.HumanoidStateType.Jumping
		or state == Enum.HumanoidStateType.FallingDown
	-- StateChanged pode não emitir Freefall ao sair de uma quina. O contato
	-- físico e a velocidade vertical são a fonte de verdade nesse caso.
	if freefallStart == 0 and floor == Enum.Material.Air
		and state ~= Enum.HumanoidStateType.Swimming
		and state ~= Enum.HumanoidStateType.Climbing
		and state ~= Enum.HumanoidStateType.Seated
		and (airborneState or math.abs(hrp.AssemblyLinearVelocity.Y) > 1) then
		freefallStart = os.clock()
		freefallStartY = hrp.Position.Y
		freefallPeakY = freefallStartY
	end
	if freefallStart == 0 then
		return
	end
	freefallPeakY = math.max(freefallPeakY, hrp.Position.Y)
	if floor ~= Enum.Material.Air and floor ~= Enum.Material.Water then
		onLanded()
	end
end)

--------------------------------------------------------------------------------
-- Boot
--------------------------------------------------------------------------------

LocalPlayer.CharacterAdded:Connect(onCharacter)
if LocalPlayer.Character then
	onCharacter(LocalPlayer.Character)
end
