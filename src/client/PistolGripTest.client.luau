--!strict
-- Calibrador secreto da Glock17: funciona sem Command Bar e sem pausar.
local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Remotes = require(ReplicatedStorage.Modules.Remotes)
local Grip = require(ReplicatedStorage.Modules.PistolGrip)
local player = Players.LocalPlayer
local ALLOWED: { [number]: boolean } = { [11555748600] = true }
if not ALLOWED[player.UserId] and not RunService:IsStudio() then return end

local ACTION_NAME = "PistolGripTestControls"
local ACTION_PRIORITY = 4000
local enabled = false
local controlsBound = false
local poseLocked = false
local spectator = false
local freeCameraCFrame: CFrame? = nil
local freeCameraPitch = 0
local freeCameraYaw = 0
local freeCameraSpeed = 5
local savedCameraType: Enum.CameraType? = nil
local savedCameraSubject: Instance? = nil
local savedMouseBehavior: Enum.MouseBehavior? = nil
local savedMouseIconEnabled: boolean? = nil
local savedWalkSpeed: number? = nil
local savedJumpPower: number? = nil
local savedJumpHeight: number? = nil
local savedAutoRotate: boolean? = nil
local savedAnchored: boolean? = nil
local savedRootCFrame: CFrame? = nil
local savedHadCrawlLock = false
local savedCrawlLock: unknown = nil
local gui = Instance.new("ScreenGui")
gui.Name, gui.ResetOnSpawn, gui.Enabled = "PistolGripTest", false, false
gui.DisplayOrder = 30
gui.Parent = player:WaitForChild("PlayerGui")
local panel = Instance.new("TextLabel")
panel.AnchorPoint, panel.Position = Vector2.new(1, 0), UDim2.new(1, -18, 0, 78)
panel.Size = UDim2.fromOffset(370, 370)
panel.BackgroundColor3, panel.BackgroundTransparency = Color3.fromRGB(12, 16, 20), 0.12
panel.BorderSizePixel, panel.Font = 0, Enum.Font.GothamMedium
panel.TextColor3, panel.TextSize = Color3.fromRGB(245, 239, 220), 13
panel.TextXAlignment, panel.TextYAlignment = Enum.TextXAlignment.Left, Enum.TextYAlignment.Top
panel.TextWrapped, panel.Text = true, ""
panel.Parent = gui
local padding = Instance.new("UIPadding")
padding.PaddingTop, padding.PaddingBottom = UDim.new(0, 11), UDim.new(0, 11)
padding.PaddingLeft, padding.PaddingRight = UDim.new(0, 14), UDim.new(0, 14)
padding.Parent = panel
local corner = Instance.new("UICorner")
corner.CornerRadius, corner.Parent = UDim.new(0, 9), panel

local function pistol(): Tool?
	local character = player.Character
	local found = character and character:FindFirstChild("Glock17")
	return if found and found:IsA("Tool") then found else nil
end

local update: () -> ()

local function humanoidAndRoot(): (Humanoid?, BasePart?)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart")
	return humanoid, if root and root:IsA("BasePart") then root else nil
end

local function seedFreeCamera(): CFrame?
	local camera = Workspace.CurrentCamera
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not camera then return nil end
	if root and root:IsA("BasePart") then
		local rightArm = character and character:FindFirstChild("Right Arm")
		local target = if rightArm and rightArm:IsA("BasePart")
			then rightArm.Position + Vector3.new(0, 0.35, 0)
			else root.Position + Vector3.new(0, 1.2, 0)
		local position = target + root.CFrame.RightVector * 3 + root.CFrame.LookVector * -2 + Vector3.new(0, 1.2, 0)
		return CFrame.lookAt(position, target)
	end
	return camera.CFrame
end

local function freezeCharacterFrame()
	if not poseLocked then return end
	local humanoid, root = humanoidAndRoot()
	if humanoid then
		humanoid.WalkSpeed = 0
		humanoid.JumpPower = 0
		humanoid.JumpHeight = 0
		humanoid.AutoRotate = false
	end
	if root then
		savedRootCFrame = savedRootCFrame or root.CFrame
		root.AssemblyLinearVelocity = Vector3.zero
		root.AssemblyAngularVelocity = Vector3.zero
		root.Anchored = true
		root.CFrame = savedRootCFrame
	end
end

local function setPoseLocked(value: boolean)
	poseLocked = value
	player:SetAttribute("PistolGripAimLock", value)
	local humanoid, root = humanoidAndRoot()
	if value then
		if humanoid then
			savedWalkSpeed = savedWalkSpeed or humanoid.WalkSpeed
			savedJumpPower = savedJumpPower or humanoid.JumpPower
			savedJumpHeight = savedJumpHeight or humanoid.JumpHeight
			savedAutoRotate = if savedAutoRotate == nil then humanoid.AutoRotate else savedAutoRotate
			humanoid.WalkSpeed = 0
			humanoid.JumpPower = 0
			humanoid.JumpHeight = 0
			humanoid.AutoRotate = false
		end
		if root then
			savedAnchored = if savedAnchored == nil then root.Anchored else savedAnchored
			if savedRootCFrame == nil then
				savedRootCFrame = root.CFrame
				savedHadCrawlLock = root:GetAttribute("CrawlLock") ~= nil
				savedCrawlLock = root:GetAttribute("CrawlLock")
			end
			root:SetAttribute("CrawlLock", true)
			root.AssemblyLinearVelocity = Vector3.zero
			root.AssemblyAngularVelocity = Vector3.zero
			root.Anchored = true
			root.CFrame = savedRootCFrame
		end
	else
		if humanoid then
			if savedWalkSpeed then humanoid.WalkSpeed = savedWalkSpeed end
			if savedJumpPower then humanoid.JumpPower = savedJumpPower end
			if savedJumpHeight then humanoid.JumpHeight = savedJumpHeight end
			if savedAutoRotate ~= nil then humanoid.AutoRotate = savedAutoRotate end
		end
		if root then
			if savedRootCFrame then root.CFrame = savedRootCFrame end
			if savedAnchored ~= nil then root.Anchored = savedAnchored end
			if savedHadCrawlLock then root:SetAttribute("CrawlLock", savedCrawlLock) else root:SetAttribute("CrawlLock", nil) end
		end
		savedWalkSpeed, savedJumpPower, savedJumpHeight, savedAutoRotate, savedAnchored = nil, nil, nil, nil, nil
		savedRootCFrame, savedCrawlLock, savedHadCrawlLock = nil, nil, false
	end
	if enabled then update() end
end

local function setSpectator(value: boolean)
	spectator = value
	local camera = Workspace.CurrentCamera
	if not camera then return end
	if value then
		if not poseLocked then setPoseLocked(true) end
		savedCameraType = savedCameraType or camera.CameraType
		savedCameraSubject = savedCameraSubject or camera.CameraSubject
		savedMouseBehavior = savedMouseBehavior or UserInputService.MouseBehavior
		savedMouseIconEnabled = if savedMouseIconEnabled == nil then UserInputService.MouseIconEnabled else savedMouseIconEnabled
		camera.CameraType = Enum.CameraType.Scriptable
		freeCameraCFrame = seedFreeCamera()
		if freeCameraCFrame then
			local x, y = freeCameraCFrame:ToOrientation()
			freeCameraPitch, freeCameraYaw = x, y
			camera.CFrame = freeCameraCFrame
		end
		UserInputService.MouseBehavior = Enum.MouseBehavior.LockCenter
		UserInputService.MouseIconEnabled = false
	else
		camera.CameraType = savedCameraType or Enum.CameraType.Custom
		if savedCameraSubject then camera.CameraSubject = savedCameraSubject end
		if savedMouseBehavior then UserInputService.MouseBehavior = savedMouseBehavior end
		if savedMouseIconEnabled ~= nil then UserInputService.MouseIconEnabled = savedMouseIconEnabled end
		savedCameraType, savedCameraSubject, savedMouseBehavior, savedMouseIconEnabled = nil, nil, nil, nil
		freeCameraCFrame = nil
	end
	if enabled then update() end
end

update = function()
	local tool = pistol()
	local p, r = Vector3.zero, Vector3.zero
	if tool then p, r = Grip.GetOffset(tool, true) end
	panel.Text = string.format(
		"CALIBRACAO DA PISTOLA - MIRA\n\nL abre/fecha\nT trava pose: %s\nV modo fantasma: %s\nShift = passo maior\nBackspace = zerar mira\n\nPOSICAO DO OBJETO\nA/D lado   Q/E altura   W/S frente\n\nROTACAO DO OBJETO\nI/K X      J/H Y        U/P Z\n\nFANTASMA\nMouse olha\nSetas andam\nR/F sobe/desce\nZ/X velocidade\n\nRotacao: X %.0f | Y %.0f | Z %.0f\nPosicao: X %.2f | Y %.2f | Z %.2f",
		if poseLocked then "ON" else "OFF",
		if spectator then "ON" else "OFF",
		r.X, r.Y, r.Z, p.X, p.Y, p.Z
	)
end

local function adjust(action: string, vector: Vector3)
	if not pistol() then return end
	Remotes.PistolGripTest:FireServer(action, vector)
	task.delay(0.08, update)
end

local function scale(): number
	return if UserInputService:IsKeyDown(Enum.KeyCode.LeftShift) or UserInputService:IsKeyDown(Enum.KeyCode.RightShift) then 5 else 1
end

local function handleControl(_actionName: string, inputState: Enum.UserInputState, input: InputObject): Enum.ContextActionResult
	if inputState ~= Enum.UserInputState.Begin then return Enum.ContextActionResult.Sink end
	if UserInputService:GetFocusedTextBox() then return Enum.ContextActionResult.Pass end
	local currentScale = scale()
	local rotation = {
		[Enum.KeyCode.I] = Vector3.new(currentScale, 0, 0), [Enum.KeyCode.K] = Vector3.new(-currentScale, 0, 0),
		[Enum.KeyCode.J] = Vector3.new(0, currentScale, 0), [Enum.KeyCode.H] = Vector3.new(0, -currentScale, 0),
		[Enum.KeyCode.U] = Vector3.new(0, 0, currentScale), [Enum.KeyCode.P] = Vector3.new(0, 0, -currentScale),
	}
	local positionStep = if currentScale == 5 then 0.1 else 0.02
	local position = {
		[Enum.KeyCode.D] = Vector3.new(positionStep, 0, 0), [Enum.KeyCode.A] = Vector3.new(-positionStep, 0, 0),
		[Enum.KeyCode.E] = Vector3.new(0, positionStep, 0), [Enum.KeyCode.Q] = Vector3.new(0, -positionStep, 0),
		[Enum.KeyCode.W] = Vector3.new(0, 0, -positionStep), [Enum.KeyCode.S] = Vector3.new(0, 0, positionStep),
	}
	if input.KeyCode == Enum.KeyCode.Backspace then
		if pistol() then Remotes.PistolGripTest:FireServer("Reset"); task.delay(0.08, update) end
	elseif input.KeyCode == Enum.KeyCode.T then
		setPoseLocked(not poseLocked)
	elseif input.KeyCode == Enum.KeyCode.V then
		setSpectator(not spectator)
	elseif input.KeyCode == Enum.KeyCode.Z then
		freeCameraSpeed = math.max(1.5, freeCameraSpeed - 0.75)
		update()
	elseif input.KeyCode == Enum.KeyCode.X then
		freeCameraSpeed = math.min(16, freeCameraSpeed + 0.75)
		update()
	elseif rotation[input.KeyCode] then
		adjust("AdjustRotation", rotation[input.KeyCode])
	elseif position[input.KeyCode] then
		adjust("AdjustPosition", position[input.KeyCode])
	end
	return Enum.ContextActionResult.Sink
end

local function setPanel(value: boolean)
	enabled, gui.Enabled = value, value
	if enabled and not controlsBound then
		controlsBound = true
		ContextActionService:BindActionAtPriority(
			ACTION_NAME,
			handleControl,
			false,
			ACTION_PRIORITY,
			Enum.KeyCode.W, Enum.KeyCode.A, Enum.KeyCode.S, Enum.KeyCode.D,
			Enum.KeyCode.Q, Enum.KeyCode.E,
			Enum.KeyCode.I, Enum.KeyCode.K, Enum.KeyCode.J, Enum.KeyCode.H,
			Enum.KeyCode.U, Enum.KeyCode.P,
			Enum.KeyCode.T, Enum.KeyCode.V,
			Enum.KeyCode.Up, Enum.KeyCode.Down, Enum.KeyCode.Left, Enum.KeyCode.Right,
			Enum.KeyCode.Z, Enum.KeyCode.X,
			Enum.KeyCode.R, Enum.KeyCode.F,
			Enum.KeyCode.Backspace
		)
	elseif not enabled and controlsBound then
		controlsBound = false
		ContextActionService:UnbindAction(ACTION_NAME)
		setPoseLocked(false)
		setSpectator(false)
	end
	if enabled then update() end
end

UserInputService.InputBegan:Connect(function(input: InputObject, processed: boolean)
	if UserInputService:GetFocusedTextBox() then return end
	if input.KeyCode == Enum.KeyCode.L then
		setPanel(not enabled)
	elseif not enabled and processed then
		return
	end
end)

player.CharacterRemoving:Connect(function()
	setPanel(false)
end)

RunService:BindToRenderStep("PistolGripSpectatorCamera", Enum.RenderPriority.Camera.Value + 20, function(dt: number)
	if not spectator then return end
	local camera = Workspace.CurrentCamera
	if not camera then return end
	freeCameraCFrame = freeCameraCFrame or camera.CFrame
	local mouseDelta = UserInputService:GetMouseDelta()
	freeCameraYaw -= mouseDelta.X * 0.003
	freeCameraPitch = math.clamp(freeCameraPitch - mouseDelta.Y * 0.003, math.rad(-80), math.rad(80))
	local rotation = CFrame.fromOrientation(freeCameraPitch, freeCameraYaw, 0)
	local move = Vector3.zero
	if UserInputService:IsKeyDown(Enum.KeyCode.Up) then move += Vector3.new(0, 0, -1) end
	if UserInputService:IsKeyDown(Enum.KeyCode.Down) then move += Vector3.new(0, 0, 1) end
	if UserInputService:IsKeyDown(Enum.KeyCode.Left) then move += Vector3.new(-1, 0, 0) end
	if UserInputService:IsKeyDown(Enum.KeyCode.Right) then move += Vector3.new(1, 0, 0) end
	if UserInputService:IsKeyDown(Enum.KeyCode.R) then move += Vector3.new(0, 1, 0) end
	if UserInputService:IsKeyDown(Enum.KeyCode.F) then move += Vector3.new(0, -1, 0) end
	local position = freeCameraCFrame.Position
	if move.Magnitude > 0 then
		position += rotation:VectorToWorldSpace(move.Unit) * freeCameraSpeed * math.min(0.1, dt)
	end
	freeCameraCFrame = CFrame.new(position) * rotation
	camera.CFrame = freeCameraCFrame
end)

RunService:BindToRenderStep("PistolGripFrozenCharacter", Enum.RenderPriority.Last.Value, function()
	freezeCharacterFrame()
end)
