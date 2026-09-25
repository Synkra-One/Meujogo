--!strict
--[[
	BoatCamera
	Câmeras do barco de fuga (docs/Barco.md), independentes do Humanoid.

	PERSEGUIÇÃO (StartChase) -- piloto e passageiros
	  - Atrás do barco, acompanhando o RUMO com atraso de mola: na curva dá
	    pra ver o costado e o deslize, como câmera de jogo de corrida.
	  - Olha à frente conforme a velocidade; afasta e abre o FOV acelerando.
	  - Tremida fina planando + tranco quando o casco bate numa onda.
	  - Órbita: botão direito arrastando, analógico direito ou arrastar na
	    tela (toque). Soltou, volta sozinha pra trás do barco. Roda = zoom.
	  - Nunca atravessa rocha/píer (raio da mira até a câmera) nem desce pra
	    baixo d'água.

	CENA DE FUGA (Cinematic)
	  Começa onde a câmera estava e vira uma grua: sobe e se afasta enquanto
	  o barco continua pro mar aberto, ficando pequeno no enquadramento
	  (BoatRules.EscapeCamera). Lente fecha aos poucos, como teleobjetiva.

	Prioridade Camera + 30 (mesma da câmera do helicóptero): roda depois da
	câmera padrão e dos tremores de outros sistemas, que só mexem com
	CameraType Custom.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local BoatPhysics = require(ReplicatedStorage.Modules.BoatPhysics)
local BoatRules = require(ReplicatedStorage.Modules.BoatRules)
local GameConfig = require(ReplicatedStorage.Modules.GameConfig)

local CFG = GameConfig.Boat
local STEP = "BoatCamera"
local player = Players.LocalPlayer

local BoatCamera = {}

type Saved = { fov: number, mouse: Enum.MouseBehavior }

local active = false
local mode: "Chase" | "Cinematic" | nil = nil
local saved: Saved? = nil
local boat: Model? = nil
local pose: CFrame? = nil
local fov = 70
local camYaw: number? = nil
local orbitYaw, orbitPitch, zoom = 0, 0, 1
local lastOrbitInput = 0
local dragging = false
local shake = 0
local connections: { RBXScriptConnection } = {}

-- Cena
local sceneStart: CFrame? = nil
local sceneClock = 0
local sceneDuration = 9
local sceneFrom: CFrame? = nil
local sceneBoatPose: (() -> CFrame?)? = nil

local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude
rayParams.IgnoreWater = true
rayParams.RespectCanCollide = true

local function angleLerp(a: number, b: number, alpha: number): number
	local delta = (b - a + math.pi) % (2 * math.pi) - math.pi
	return a + delta * alpha
end

local function flat(v: Vector3): Vector3
	local f = Vector3.new(v.X, 0, v.Z)
	return if f.Magnitude > 1e-3 then f.Unit else Vector3.new(0, 0, -1)
end

local function excludeList(): { Instance }
	local list: { Instance } = {}
	if boat then
		table.insert(list, boat)
	end
	for _, other in Players:GetPlayers() do
		if other.Character then
			table.insert(list, other.Character)
		end
	end
	local ilha = Workspace:FindFirstChild("Ilha")
	local ring = ilha and ilha:FindFirstChild("LimiteFuga")
	if ring then
		table.insert(list, ring)
	end
	return list
end

-- Mira até a posição desejada: encurta se bater em algo, nunca abaixo d'água.
local function clearPosition(focus: Vector3, desired: Vector3, waterY: number?): Vector3
	rayParams.FilterDescendantsInstances = excludeList()
	local hit = Workspace:Raycast(focus, desired - focus, rayParams)
	local position = if hit then hit.Position + (focus - desired).Unit * 1.2 else desired
	if waterY and position.Y < waterY + 1.4 then
		position = Vector3.new(position.X, waterY + 1.4, position.Z)
	end
	return position
end

--------------------------------------------------------------------------------
-- Entrada da órbita
--------------------------------------------------------------------------------

local function bindInput()
	table.insert(connections, UserInputService.InputBegan:Connect(function(input, processed)
		if processed then
			return
		end
		if input.UserInputType == Enum.UserInputType.MouseButton2 then
			dragging = true
			UserInputService.MouseBehavior = Enum.MouseBehavior.LockCurrentPosition
		end
	end))
	table.insert(connections, UserInputService.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton2 then
			dragging = false
			UserInputService.MouseBehavior = Enum.MouseBehavior.Default
		end
	end))
	table.insert(connections, UserInputService.InputChanged:Connect(function(input, processed)
		if mode ~= "Chase" then
			return
		end
		if input.UserInputType == Enum.UserInputType.MouseMovement and dragging then
			orbitYaw -= input.Delta.X * 0.006
			orbitPitch = math.clamp(orbitPitch - input.Delta.Y * 0.004, -0.2, 0.75)
			lastOrbitInput = os.clock()
		elseif input.UserInputType == Enum.UserInputType.MouseWheel and not processed then
			zoom = math.clamp(zoom - input.Position.Z * 0.08, 0.7, 1.6)
		elseif input.KeyCode == Enum.KeyCode.Thumbstick2 then
			local stick = input.Position
			if stick.Magnitude > 0.2 then
				orbitYaw -= stick.X * 0.05
				orbitPitch = math.clamp(orbitPitch + stick.Y * 0.03, -0.2, 0.75)
				lastOrbitInput = os.clock()
			end
		end
	end))
	table.insert(connections, UserInputService.TouchPan:Connect(function(_, _, velocity, _, processed)
		if processed or mode ~= "Chase" then
			return
		end
		orbitYaw -= velocity.X * 0.00022
		orbitPitch = math.clamp(orbitPitch - velocity.Y * 0.00016, -0.2, 0.75)
		lastOrbitInput = os.clock()
	end))
end

local function unbindInput()
	for _, c in connections do
		c:Disconnect()
	end
	table.clear(connections)
	dragging = false
end

--------------------------------------------------------------------------------
-- Poses
--------------------------------------------------------------------------------

local function chasePose(dt: number): CFrame?
	local model = boat
	local root = model and model.PrimaryPart
	local frame = root and root:FindFirstChild(BoatPhysics.FrameName)
	if not model or not root or not frame or not frame:IsA("Attachment") then
		return nil
	end
	local frameCF = frame.WorldCFrame
	local forward = flat(frameCF.LookVector)
	local velocity = root.AssemblyLinearVelocity
	local speed = Vector3.new(velocity.X, 0, velocity.Z).Magnitude
	local ratio = math.clamp(speed / CFG.VelocidadeMax, 0, 1)
	local length = (model:GetAttribute("Comprimento") :: number?) or 20

	-- Sem mexer na órbita por 1,6s, ela volta pra trás do barco.
	if os.clock() - lastOrbitInput > 1.6 and not dragging then
		local back = 1 - math.exp(-2.2 * dt)
		orbitYaw += (0 - orbitYaw) * back
		orbitPitch += (0 - orbitPitch) * back
	end

	local boatYaw = math.atan2(-forward.X, -forward.Z)
	camYaw = angleLerp(camYaw or boatYaw, boatYaw, 1 - math.exp(-3.4 * dt))
	local yaw = (camYaw :: number) + orbitYaw
	local elevation = math.rad(13) + orbitPitch - ratio * math.rad(3)
	local distance = (length * 1.05 + 7 + ratio * 9) * zoom

	local focus = frameCF.Position + Vector3.new(0, 2.8, 0) + forward * (ratio * 7)
	local back = CFrame.Angles(0, yaw, 0):VectorToWorldSpace(Vector3.new(0, 0, 1))
	local desired = focus + back * (distance * math.cos(elevation)) + Vector3.new(0, distance * math.sin(elevation), 0)
	local waterY = BoatPhysics.Probe(desired)
	local position = clearPosition(focus, desired, waterY)
	return CFrame.lookAt(position, focus + forward * 4)
end

local function applyShake(cf: CFrame, amount: number): CFrame
	if amount <= 0.001 then
		return cf
	end
	local t = os.clock()
	local rx = math.noise(t * 11, 0.3) * amount
	local ry = math.noise(0.7, t * 13) * amount * 0.6
	local rz = math.noise(t * 9, 1.9) * amount * 0.8
	return cf * CFrame.Angles(rx, ry, rz)
end

local function scenePose(dt: number): CFrame?
	local start = sceneStart
	local boatPose = sceneBoatPose
	if not start or not boatPose then
		return nil
	end
	sceneClock += dt
	local current = boatPose()
	if not current then
		return nil
	end
	local forward = flat(start.LookVector)
	local right = Vector3.new(-forward.Z, 0, forward.X)
	local anchor, back, height, side = BoatRules.EscapeCamera(sceneClock, sceneDuration)
	local traveled = (current.Position - start.Position):Dot(forward)
	local anchorPoint = start.Position + forward * (traveled * anchor)
	local position = anchorPoint - forward * back + right * side + Vector3.new(0, height, 0)
	local lookAt = current.Position + forward * 10 + Vector3.new(0, 1.5, 0)
	local desired = CFrame.lookAt(position, lookAt)
	-- Entra na cena sem corte: mistura a partir da câmera anterior.
	local from = sceneFrom
	if from and sceneClock < 1.1 then
		local a = sceneClock / 1.1
		desired = from:Lerp(desired, a * a * (3 - 2 * a))
	end
	return desired
end

--------------------------------------------------------------------------------
-- Ciclo
--------------------------------------------------------------------------------

local function render(dt: number)
	local camera = Workspace.CurrentCamera
	if not camera then
		return
	end
	camera.CameraType = Enum.CameraType.Scriptable
	local target: CFrame? = nil
	local targetFov = 70
	if mode == "Chase" then
		target = chasePose(dt)
		local root = boat and boat.PrimaryPart
		local speed = if root then Vector3.new(root.AssemblyLinearVelocity.X, 0, root.AssemblyLinearVelocity.Z).Magnitude else 0
		local ratio = math.clamp(speed / CFG.VelocidadeMax, 0, 1)
		targetFov = 70 + 12 * ratio
		shake = math.max(shake - dt * 3.5, ratio * ratio * 0.0035)
	elseif mode == "Cinematic" then
		target = scenePose(dt)
		local progress = math.clamp(sceneClock / math.max(sceneDuration, 1), 0, 1)
		targetFov = 72 - 20 * progress * progress
		shake = math.max(shake - dt * 2, 0)
	end
	if not target then
		return
	end
	local follow = if mode == "Cinematic" then 1 else 1 - math.exp(-9 * math.min(dt, 0.1))
	pose = if pose and mode == "Chase" then pose:Lerp(target, follow) else target
	camera.CFrame = applyShake(pose :: CFrame, shake)
	camera.Focus = CFrame.new((pose :: CFrame).Position + (pose :: CFrame).LookVector * 20)
	fov += (targetFov - fov) * (1 - math.exp(-3 * dt))
	camera.FieldOfView = fov
end

local function start()
	if active then
		return
	end
	active = true
	local camera = Workspace.CurrentCamera
	saved = {
		fov = if camera then camera.FieldOfView else 70,
		mouse = UserInputService.MouseBehavior,
	}
	fov = if camera then camera.FieldOfView else 70
	pose = if camera then camera.CFrame else nil
	camYaw = nil
	orbitYaw, orbitPitch, zoom, shake = 0, 0, 1, 0
	UserInputService.MouseBehavior = Enum.MouseBehavior.Default
	bindInput()
	RunService:BindToRenderStep(STEP, Enum.RenderPriority.Camera.Value + 30, render)
end

function BoatCamera.StartChase(model: Model)
	boat = model
	if mode == "Cinematic" then
		return
	end
	mode = "Chase"
	start()
end

-- Tranco da batida de onda (0..1).
function BoatCamera.Bump(strength: number)
	if mode == "Chase" then
		shake = math.max(shake, 0.012 * strength)
	end
end

--[[
	Cinematic(model, start, duration, boatPose)
	`start` = QuadroBarco ao cruzar o limite; `boatPose()` devolve o
	QuadroBarco animado agora (quem anima é o BoatController).
]]
function BoatCamera.Cinematic(model: Model, startCF: CFrame, duration: number, boatPose: () -> CFrame?)
	boat = model
	local camera = Workspace.CurrentCamera
	sceneFrom = if camera then camera.CFrame else nil
	sceneStart = startCF
	sceneDuration = duration
	sceneClock = 0
	sceneBoatPose = boatPose
	mode = "Cinematic"
	start()
end

function BoatCamera.Stop()
	if not active then
		mode = nil
		return
	end
	active = false
	mode = nil
	RunService:UnbindFromRenderStep(STEP)
	unbindInput()
	local camera = Workspace.CurrentCamera
	local character = player and player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if camera then
		camera.CameraType = Enum.CameraType.Custom
		if humanoid then
			camera.CameraSubject = humanoid
		end
		if saved then
			camera.FieldOfView = saved.fov
		end
	end
	if saved then
		UserInputService.MouseBehavior = saved.mouse
	end
	saved, pose, boat = nil, nil, nil
	sceneStart, sceneFrom, sceneBoatPose = nil, nil, nil
end

function BoatCamera.Mode(): string?
	return mode
end

return BoatCamera
