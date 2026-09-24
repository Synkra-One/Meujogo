--!strict
-- PlayerModule continua responsavel por mouse, toque e controle. Este script
-- compoe o enquadramento apos ele e valida a colisao novamente apos o recoil.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local Actions = game:GetService("ContextActionService")
local Input = game:GetService("UserInputService")
local VR = game:GetService("VRService")
local Config = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("ShoulderCameraConfig"))
local Occlusion = require(script.Parent.CameraOcclusion)
local player = Players.LocalPlayer
local CAMERA_STEP, SAFETY_STEP, SWITCH_ACTION = "AdaptiveShoulderCamera", "AdaptiveCameraSafety", "SwitchCameraShoulder"
local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude
rayParams.IgnoreWater = true
rayParams.RespectCanCollide = true
local overlapParams = OverlapParams.new()
overlapParams.FilterType = Enum.RaycastFilterType.Exclude
overlapParams.RespectCanCollide = true

local character: Model? = nil
local humanoid: Humanoid? = nil
local root: BasePart? = nil
local parts: { BasePart | Decal } = {}
local descendantConnection: RBXScriptConnection? = nil
local generation = 0
local active = false
local lastCamera: Camera? = nil
local lastRoot: Vector3? = nil
local pivot: Vector3? = nil
local actualDistance = Config.Distance
local distance, shoulder, height = Config.Distance, Config.Shoulder, Config.Height
local indoor, indoorTarget, nextProbe, lastTight = 0, 0, 0, -math.huge
local shoulderSide = 1
local clock, motion = 0, 0
local radius = Config.CollisionRadius

local function blend(a: number, b: number, response: number, dt: number): number
	return a + (b - a) * (1 - math.exp(-response * dt))
end

local function refreshFilters()
	local excluded: { Instance } = {}
	for _, other in Players:GetPlayers() do
		if other.Character then table.insert(excluded, other.Character) end
	end
	if Workspace.CurrentCamera then table.insert(excluded, Workspace.CurrentCamera) end
	rayParams.FilterDescendantsInstances = excluded
	overlapParams.FilterDescendantsInstances = excluded
end

local function resetVisibility()
	local powerFade = if character and character:GetAttribute("PowerFearHidden") == true then 0.65 else 0
	for _, part in parts do
		if part.Parent then part.LocalTransparencyModifier = powerFade end
	end
end

local function canControl(camera: Camera?): boolean
	return camera ~= nil and camera.CameraType == Enum.CameraType.Custom
		and humanoid ~= nil and camera.CameraSubject == humanoid
		and humanoid.Health > 0 and root ~= nil and root.Parent ~= nil
		and player:GetAttribute("MovementLocked") ~= true
		and not VR.VREnabled
end

local function setActive(value: boolean)
	if active == value then return end
	active = value
	player:SetAttribute("AdaptiveShoulderCameraActive", value)
	if not value then resetVisibility(); pivot = nil; lastRoot = nil end
end

local function bindCharacter(model: Model)
	generation += 1
	local token = generation
	setActive(false)
	if descendantConnection then descendantConnection:Disconnect(); descendantConnection = nil end
	table.clear(parts)
	character, humanoid, root = model, nil, nil
	local human = model:WaitForChild("Humanoid", 10)
	local rootPart = model:WaitForChild("HumanoidRootPart", 10)
	if token ~= generation or model ~= player.Character then return end
	if not human or not human:IsA("Humanoid") or not rootPart or not rootPart:IsA("BasePart") then return end
	humanoid, root = human, rootPart
	local function remember(instance: Instance)
		if instance:IsA("BasePart") or instance:IsA("Decal") then table.insert(parts, instance) end
	end
	for _, child in model:GetDescendants() do remember(child) end
	descendantConnection = model.DescendantAdded:Connect(remember)
	indoor, indoorTarget, nextProbe, lastTight = 0, 0, 0, -math.huge
	distance, shoulder, height = Config.Distance, Config.Shoulder * shoulderSide, Config.Height
	actualDistance, motion = Config.Distance, 0
	refreshFilters()
end

local function sampleRoom(origin: Vector3, orientation: CFrame, now: number)
	refreshFilters()
	local roof = Workspace:Raycast(origin, Vector3.new(0, Config.CeilingDistance, 0), rayParams)
	local hits = 0
	for _, direction in { orientation.RightVector, -orientation.RightVector, orientation.LookVector, -orientation.LookVector } do
		local flat = Vector3.new(direction.X, 0, direction.Z)
		if flat.Magnitude > 0.01 and Workspace:Raycast(origin, flat.Unit * Config.ProbeDistance, rayParams) then hits += 1 end
	end
	if (roof and hits >= 1) or hits >= 2 then
		indoorTarget, lastTight = 1, now
	elseif now - lastTight > Config.IndoorHold then
		indoorTarget = 0
	end
end

local function solve(origin: Vector3, target: Vector3): number
	return Occlusion.Distance(Workspace, origin, target, radius, Config.CollisionPadding, rayParams, overlapParams)
end

RunService:BindToRenderStep(CAMERA_STEP, Enum.RenderPriority.Camera.Value + 1, function(dt: number)
	local camera = Workspace.CurrentCamera
	if not canControl(camera) then setActive(false); return end
	local cam = camera :: Camera
	local human, body, model = humanoid :: Humanoid, root :: BasePart, character :: Model
	dt = math.min(dt, 0.1)
	clock += dt
	local resuming = not active or lastCamera ~= cam or lastRoot == nil
		or (body.Position - (lastRoot :: Vector3)).Magnitude > 15
	setActive(true)
	lastCamera, lastRoot = cam, body.Position
	-- Keep the exact input direction. Smoothing mouse rotation introduces aim
	-- latency; only distance, shoulder, height and FOV are smoothed.
	local orientation = cam.CFrame.Rotation
	local origin = body.Position + Vector3.new(0,
		math.clamp(Config.PivotHeight + human.CameraOffset.Y * 0.55, -0.4, 1.7), 0)
	if clock >= nextProbe or resuming then
		sampleRoom(origin, orientation, clock)
		nextProbe = clock + Config.ProbeInterval
	end
	indoor = blend(indoor, indoorTarget, Config.ProfileResponse, dt)
	local aiming = model:GetAttribute("FirearmAiming") == true
	local crouched = body:GetAttribute("IsCrouching") == true or body:GetAttribute("CrawlLock") == true
	local sprinting = body:GetAttribute("IsSprinting") == true
	local baseDistance = if aiming then Config.AimDistance elseif crouched then Config.CrouchDistance
		elseif sprinting then Config.SprintDistance else Config.Distance
	local desiredDistance = baseDistance + (math.min(baseDistance, Config.IndoorDistance) - baseDistance) * indoor
	local baseShoulder = if aiming then Config.AimShoulder else Config.Shoulder
	local desiredShoulder = (baseShoulder + (Config.IndoorShoulder - baseShoulder) * indoor) * shoulderSide
	local desiredHeight = Config.Height + (Config.IndoorHeight - Config.Height) * indoor
	if resuming then
		distance, shoulder, height, actualDistance = desiredDistance, desiredShoulder, desiredHeight, desiredDistance
	else
		distance = blend(distance, desiredDistance, Config.ProfileResponse, dt)
		shoulder = blend(shoulder, desiredShoulder, Config.ShoulderResponse, dt)
		height = blend(height, desiredHeight, Config.ProfileResponse, dt)
	end

	-- Movement publishes its FOV target; this is the sole normal-gameplay
	-- writer. Ability deltas are composed here rather than fighting tweens.
	local movementFOV = model:GetAttribute("MovementCameraFOV")
	local targetFOV = if type(movementFOV) == "number" then movementFOV else Config.FOV
	targetFOV += (math.min(targetFOV, Config.IndoorFOV) - targetFOV) * indoor
	if aiming then
		local weaponFOV = model:GetAttribute("FirearmAimFOV")
		targetFOV = math.min(targetFOV, Config.AimFOV, if type(weaponFOV) == "number" then weaponFOV else Config.AimFOV)
	end
	if model:GetAttribute("ShadowRushBusy") == true then
		targetFOV = Config.FOV + (model:GetAttribute("ShadowRushFOV") or 0)
	end
	-- Teleport owns its short cinematic FOV envelope.
	if model:GetAttribute("TeleportState") == nil then
		cam.FieldOfView = blend(cam.FieldOfView, math.clamp(targetFOV, 35, 90), Config.FOVResponse, dt)
	end
	-- Enclose the near plane too, including widescreen corners.
	local near = math.max(0.1, math.abs(cam.NearPlaneZ))
	local halfHeight = near * math.tan(math.rad(cam.FieldOfView * 0.5))
	local aspect = cam.ViewportSize.X / math.max(cam.ViewportSize.Y, 1)
	radius = math.max(Config.CollisionRadius, math.sqrt(near * near + halfHeight * halfHeight * (1 + aspect * aspect)) + 0.06)

	-- Minimal handheld motion, quieter while aiming and in tight spaces.
	local moving = human.MoveDirection.Magnitude > 0.1 and human.FloorMaterial ~= Enum.Material.Air
	motion = blend(motion, if moving then 1 else 0, 7, dt)
	local amplitude = (if aiming then 0.008 else 0.028) * (1 - indoor * 0.6)
	local sway = math.sin(clock * (if sprinting then 10 else 6)) * amplitude * motion
	local breath = math.sin(clock * 1.5) * 0.008
	local offset = orientation:VectorToWorldSpace(Vector3.new(shoulder + sway, height + breath, distance))
	local wanted = origin + offset
	local limit = solve(origin, wanted)
	actualDistance = Occlusion.Release(actualDistance, limit, Config.CollisionRelease, dt)
	local position = origin + offset.Unit * actualDistance
	cam.CFrame = CFrame.new(position) * orientation
	cam.Focus = CFrame.new(position + orientation.LookVector * distance)
	pivot = origin
end)

RunService:BindToRenderStep(SAFETY_STEP, Enum.RenderPriority.Camera.Value + 20, function()
	local camera, origin = Workspace.CurrentCamera, pivot
	if not active or not origin or not canControl(camera) then return end
	local cam = camera :: Camera
	local delta = cam.CFrame.Position - origin
	local safe = solve(origin, cam.CFrame.Position)
	if delta.Magnitude > 0.001 and safe < delta.Magnitude then
		cam.CFrame = CFrame.new(origin + delta.Unit * safe) * cam.CFrame.Rotation
	end
	-- The stock transparency controller measures the stock center camera.
	-- Use the final shoulder camera distance so it doesn't hide the whole rig
	-- just because its own Popper temporarily zoomed in at a door.
	local finalDistance = (cam.CFrame.Position - origin).Magnitude
	local fade = math.clamp((Config.FadeStart - finalDistance) / (Config.FadeStart - Config.FadeEnd), 0, 1)
	if character and character:GetAttribute("PowerFearHidden") == true then fade = math.max(fade, 0.65) end
	for _, part in parts do
		if part.Parent then part.LocalTransparencyModifier = fade end
	end
end)

Actions:BindAction(SWITCH_ACTION, function(_, state: Enum.UserInputState)
	if not active or player:GetAttribute("CursorLivre") == true or Input:GetFocusedTextBox() then
		return Enum.ContextActionResult.Pass
	end
	if state == Enum.UserInputState.Begin then shoulderSide = -shoulderSide end
	return Enum.ContextActionResult.Sink
end, true, Enum.KeyCode.V, Enum.KeyCode.ButtonR3)
Actions:SetTitle(SWITCH_ACTION, "Ombro")
Actions:SetPosition(SWITCH_ACTION, UDim2.fromScale(0.68, 0.55))

player.CharacterAdded:Connect(function(model) task.spawn(bindCharacter, model) end)
player.CharacterRemoving:Connect(function(model)
	if character ~= model then return end
	generation += 1
	setActive(false)
	if descendantConnection then descendantConnection:Disconnect(); descendantConnection = nil end
	character, humanoid, root = nil, nil, nil
	table.clear(parts)
end)
if player.Character then task.spawn(bindCharacter, player.Character) end
script.Destroying:Connect(function()
	setActive(false)
	RunService:UnbindFromRenderStep(CAMERA_STEP)
	RunService:UnbindFromRenderStep(SAFETY_STEP)
	Actions:UnbindAction(SWITCH_ACTION)
	if descendantConnection then descendantConnection:Disconnect() end
end)
