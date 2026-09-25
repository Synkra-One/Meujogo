--!strict
--[[
	BoatController
	O barco de fuga no cliente (docs/Barco.md). Junta as peças:

	  PILOTO   dono de rede do barco: a cada passo de física lê acelerador e
	           volante (VehicleSeat.ThrottleFloat/SteerFloat, que o
	           ControlModule do Roblox preenche com teclado, controle e
	           analógico de toque) e roda BoatPhysics.Step. F / Y / botão
	           MOTOR pede pro servidor ligar ou desligar.
	  A BORDO  câmera de perseguição (BoatCamera), painel de pilotagem
	           (BoatHUD) e prompts escondidos -- sentado, o E não pode abrir
	           "Embarcar" do próprio barco.
	  TODOS    efeitos do barco e das boias (BoatEffects) e o checklist do
	           barco durante a partida.
	  FUGA     o servidor ancora o barco ao cruzar o limite e manda "Fuga":
	           aqui o barco segue pro mar aberto (animado localmente, liso a
	           60 fps) e quem estava a bordo ganha a cena de cinema.

	O papel (piloto/passageiro) vem do Attribute "BarcoAssento" do character,
	que só o servidor escreve depois de validar quem sentou.
]]

local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local BoatPhysics = require(ReplicatedStorage.Modules.BoatPhysics)
local BoatRules = require(ReplicatedStorage.Modules.BoatRules)
local GameConfig = require(ReplicatedStorage.Modules.GameConfig)
local Remotes = require(ReplicatedStorage.Modules.Remotes)
local BoatCamera = require(script.Parent.BoatCamera)
local BoatEffects = require(script.Parent.BoatEffects)
local BoatHUD = require(script.Parent.BoatHUD)

local CFG = GameConfig.Boat
local ENGINE_ACTION = "BarcoMotor"
local SCENE_STEP = "BoatEscapeScene"
local player = Players.LocalPlayer

type Scene = {
	model: Model,
	start: CFrame,
	speed: number,
	duration: number,
	clock: number,
	frameToPivot: CFrame,
	phase: number,
	aboard: boolean,
	pose: CFrame,
}

local boat: Model? = nil
local effects: BoatEffects.Handle? = nil
local physics: BoatPhysics.Controller? = nil
local telemetry: BoatPhysics.Telemetry? = nil
local role: string? = nil
local engineBound = false
local savedPromptsEnabled: boolean? = nil
local inMatch = false
local scene: Scene? = nil
local controls: any = nil
local checklistElapsed = 0

local function flat(v: Vector3): Vector3
	local f = Vector3.new(v.X, 0, v.Z)
	return if f.Magnitude > 1e-3 then f.Unit else Vector3.new(0, 0, -1)
end

-- Pra onde fica o limite (radial, pra fora do centro da ilha) em relação à
-- câmera, em graus de tela: 0 = em frente, positivo = à direita.
local function limitBearing(position: Vector3): number
	local camera = Workspace.CurrentCamera
	if not camera then
		return 0
	end
	local ahead = flat(camera.CFrame.LookVector)
	local outward = flat(position)
	return -math.deg(math.atan2(ahead:Cross(outward).Y, ahead:Dot(outward)))
end

--------------------------------------------------------------------------------
-- Achar o barco (o servidor publica a referência em ReplicatedStorage)
--------------------------------------------------------------------------------

local function setBoat(model: Model?)
	if model == boat then
		return
	end
	if effects then
		BoatEffects.Destroy(effects)
		effects = nil
	end
	boat = model
	physics = nil
end

task.spawn(function()
	local ref = ReplicatedStorage:WaitForChild("BarcoFuga", 60)
	if not ref or not ref:IsA("ObjectValue") then
		return
	end
	local function sync()
		local value = ref.Value
		setBoat(if value and value:IsA("Model") then value else nil)
	end
	ref.Changed:Connect(sync)
	sync()
end)

task.spawn(function()
	local ok, module = pcall(function()
		local scripts = player:WaitForChild("PlayerScripts", 10)
		local playerModule = scripts and scripts:WaitForChild("PlayerModule", 10)
		return if playerModule then require(playerModule :: ModuleScript) else nil
	end)
	if ok and module then
		controls = (module :: any):GetControls()
	end
end)

--------------------------------------------------------------------------------
-- Sentado ou não
--------------------------------------------------------------------------------

local function humanoid(): Humanoid?
	local character = player.Character
	return character and character:FindFirstChildOfClass("Humanoid") or nil
end

local function currentRole(): string?
	local character = player.Character
	local model = boat
	local h = humanoid()
	local value = character and character:GetAttribute("BarcoAssento")
	if not model or not h or type(value) ~= "string" then
		return nil
	end
	local seat = h.SeatPart
	if not seat or not seat:IsDescendantOf(model) then
		return nil
	end
	return value
end

local function onEngineAction(_: string, state: Enum.UserInputState): Enum.ContextActionResult
	if state == Enum.UserInputState.Begin then
		Remotes.BoatControl:FireServer("Motor")
	end
	return Enum.ContextActionResult.Sink
end

local function setEngineBinding(bound: boolean)
	if bound == engineBound then
		return
	end
	engineBound = bound
	if bound then
		ContextActionService:BindActionAtPriority(ENGINE_ACTION, onEngineAction, true,
			Enum.ContextActionPriority.High.Value, Enum.KeyCode.F, Enum.KeyCode.ButtonY)
		ContextActionService:SetTitle(ENGINE_ACTION, "MOTOR")
		ContextActionService:SetPosition(ENGINE_ACTION, UDim2.new(1, -170, 1, -210))
	else
		ContextActionService:UnbindAction(ENGINE_ACTION)
	end
end

-- Sentado no barco nenhum prompt aparece (o E do próprio barco, as peças
-- no píer...). Enabled do serviço vale só pra este cliente; volta ao valor
-- de antes ao levantar.
local function setPromptsHidden(hidden: boolean)
	if hidden and savedPromptsEnabled == nil then
		savedPromptsEnabled = ProximityPromptService.Enabled
		ProximityPromptService.Enabled = false
	elseif not hidden and savedPromptsEnabled ~= nil then
		ProximityPromptService.Enabled = savedPromptsEnabled :: boolean
		savedPromptsEnabled = nil
	end
end

local function refreshRole()
	local newRole = if scene then role else currentRole()
	if newRole == role then
		return
	end
	role = newRole
	local model = boat
	if role and model then
		setPromptsHidden(true)
		BoatCamera.StartChase(model)
		if physics then
			BoatPhysics.Reset(physics)
		end
	else
		setPromptsHidden(false)
		BoatHUD.HideDrive()
		if not scene then
			BoatCamera.Stop()
		end
	end
	setEngineBinding(role == "Piloto")
end

--------------------------------------------------------------------------------
-- Piloto: física no passo de simulação
--------------------------------------------------------------------------------

local function readInput(): (number, number)
	local h = humanoid()
	local seat = h and h.SeatPart
	local throttle, steer = 0, 0
	if seat and seat:IsA("VehicleSeat") then
		throttle, steer = seat.ThrottleFloat, seat.SteerFloat
	end
	if math.abs(throttle) < 0.01 and math.abs(steer) < 0.01 and controls then
		local ok, move = pcall(function()
			return controls:GetMoveVector()
		end)
		if ok and typeof(move) == "Vector3" then
			throttle, steer = -move.Z, move.X
		end
	end
	return math.clamp(throttle, -1, 1), math.clamp(steer, -1, 1)
end

local function isDriving(model: Model): boolean
	local root = model.PrimaryPart
	return role == "Piloto" and scene == nil and root ~= nil and not root.Anchored
		and model:GetAttribute("PilotoId") == player.UserId
end

RunService.PreSimulation:Connect(function(dt: number)
	local model = boat
	if not model or not isDriving(model) then
		telemetry = nil
		return
	end
	if not physics then
		physics = BoatPhysics.Bind(model, CFG)
		if not physics then
			return
		end
	end
	local throttle, steer = readInput()
	telemetry = BoatPhysics.Step(physics :: BoatPhysics.Controller, dt, throttle, steer, model:GetAttribute("MotorLigado") == true)
end)

--------------------------------------------------------------------------------
-- Cena de fuga
--------------------------------------------------------------------------------

local function setJumping(enabled: boolean)
	local h = humanoid()
	if h then
		h:SetStateEnabled(Enum.HumanoidStateType.Jumping, enabled)
	end
end

local function endScene()
	if not scene then
		return
	end
	local ended = scene
	scene = nil
	RunService:UnbindFromRenderStep(SCENE_STEP)
	if ended.aboard then
		setJumping(true)
	end
	refreshRole()
end

local function sceneStep(dt: number)
	local current = scene
	if not current then
		return
	end
	current.clock += dt
	local t = current.clock
	local traveled = BoatRules.EscapeTravel(t, current.speed, CFG)
	local speedNow = (BoatRules.EscapeTravel(t + 0.05, current.speed, CFG) - traveled) / 0.05
	local heave, wavePitch, waveRoll = BoatRules.Waves(t, current.phase, speedNow, CFG)
	current.pose = current.start
		* CFrame.new(0, CFG.ElevacaoPlaneio + heave, -traveled)
		* CFrame.Angles(math.rad(CFG.TrimPlaneio + wavePitch), 0, math.rad(waveRoll))
	local root = current.model.PrimaryPart
	if root and root.Anchored then
		current.model:PivotTo(current.pose * current.frameToPivot)
	end
	local handle = effects
	if handle then
		BoatEffects.Update(handle, dt, {
			speed = speedNow,
			planing = 1,
			rpm = 1,
			throttle = 1,
			steer = 0,
			surface = "Agua",
		})
	end
	if t > current.duration + 5 or current.model:GetAttribute("Escapando") ~= true then
		endScene()
	end
end

local function startScene(model: Model, start: CFrame, speed: number, duration: number, rescued: { number })
	local root = model.PrimaryPart
	local frame = root and root:FindFirstChild(BoatPhysics.FrameName)
	if not root or not frame or not frame:IsA("Attachment") then
		return
	end
	endScene()
	local aboard = table.find(rescued, player.UserId) ~= nil
	scene = {
		model = model,
		start = start,
		speed = speed,
		duration = duration,
		clock = 0,
		-- Quadro -> pivot é fixo (tudo soldado): anima o quadro e deriva o pivot.
		frameToPivot = frame.WorldCFrame:ToObjectSpace(model:GetPivot()),
		phase = (model:GetAttribute("FaseOnda") :: number?) or 0,
		aboard = aboard,
		pose = start,
	}
	-- Antes da câmera (Camera + 30): o barco anda, depois a câmera enquadra.
	RunService:BindToRenderStep(SCENE_STEP, Enum.RenderPriority.Camera.Value + 20, sceneStep)
	if aboard then
		setJumping(false)
		setEngineBinding(false)
		BoatHUD.HideDrive()
		BoatHUD.PlayCinema(duration, "Fuga de barco")
		BoatCamera.Cinematic(model, start, duration, function(): CFrame?
			local current = scene
			return if current then current.pose else nil
		end)
	end
end

Remotes.BoatControl.OnClientEvent:Connect(function(action: string, a: any, b: any, c: any, d: any, e: any)
	if action == "Fuga" then
		if typeof(a) == "Instance" and a:IsA("Model") and typeof(b) == "CFrame" and type(c) == "number"
			and type(d) == "number" and type(e) == "table" then
			startScene(a, b, c, d, e)
		end
	elseif action == "Assento" or action == "Saiu" then
		task.defer(refreshRole)
	end
end)

--------------------------------------------------------------------------------
-- Partida / fim
--------------------------------------------------------------------------------

local function closeEverything()
	endScene()
	BoatCamera.Stop()
	BoatHUD.StopCinema()
	BoatHUD.HideDrive()
	setEngineBinding(false)
	setPromptsHidden(false)
	role = nil
end

Remotes.RoundStateChanged.OnClientEvent:Connect(function()
	inMatch = true
	BoatHUD.SetMatchVisible(true)
end)

Remotes.RoundEnded.OnClientEvent:Connect(function()
	inMatch = false
	BoatHUD.SetMatchVisible(false)
	-- Deixa o escuro do fim da cena até o resultado aparecer por cima.
	task.delay(0.4, closeEverything)
end)

Remotes.MatchResults.OnClientEvent:Connect(function()
	BoatHUD.StopCinema()
end)

player.CharacterRemoving:Connect(function()
	closeEverything()
end)

if ReplicatedStorage:GetAttribute("MatchState") == "InMatch" and player:GetAttribute("InRound") == true then
	inMatch = true
	BoatHUD.SetMatchVisible(true)
end

--------------------------------------------------------------------------------
-- Frame a frame: efeitos, HUD, câmera
--------------------------------------------------------------------------------

RunService.RenderStepped:Connect(function(dt: number)
	BoatEffects.UpdateBuoys(dt)
	local model = boat
	if not model or not model.Parent then
		return
	end
	if not effects then
		effects = BoatEffects.Attach(model)
	end
	if not physics then
		physics = BoatPhysics.Bind(model, CFG)
	end

	refreshRole()

	local handle = effects
	if handle and not scene then
		local slammed = BoatEffects.Update(handle, dt, if telemetry then {
			speed = telemetry.speed,
			planing = telemetry.planing,
			rpm = telemetry.rpm,
			throttle = telemetry.throttle,
			steer = telemetry.steer,
			surface = telemetry.surface,
		} else nil)
		if slammed and role then
			local root = model.PrimaryPart
			local speed = if root then root.AssemblyLinearVelocity.Magnitude else 0
			BoatCamera.Bump(math.clamp(speed / CFG.VelocidadeMax, 0.3, 1))
		end
	end

	if role and not scene then
		local frame = model.PrimaryPart and model.PrimaryPart:FindFirstChild(BoatPhysics.FrameName)
		local position = if frame and frame:IsA("Attachment") then frame.WorldPosition else model:GetPivot().Position
		local root = model.PrimaryPart
		local speed = if telemetry then telemetry.speed
			elseif root then Vector3.new(root.AssemblyLinearVelocity.X, 0, root.AssemblyLinearVelocity.Z).Magnitude
			else 0
		BoatHUD.UpdateDrive(model, role, speed, if telemetry then telemetry.throttle else 0,
			BoatRules.DistanceToFinish(position.X, position.Z, CFG.RaioChegada), limitBearing(position))
	end

	checklistElapsed += dt
	if checklistElapsed >= 0.25 then
		checklistElapsed = 0
		if inMatch then
			BoatHUD.UpdateChecklist(model)
		end
	end
end)
