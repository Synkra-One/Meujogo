--!strict
-- Câmera externa do helicóptero, independente do Humanoid oculto.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local Input = game:GetService("UserInputService")
local player = Players.LocalPlayer
local Camera = {}
local STEP = "ExtractionPassengerCamera"
local active = false
local model: Model? = nil
local span = 34
local pose: CFrame? = nil
local saved: { fov: number, mouse: Enum.MouseBehavior, icon: boolean }? = nil
local ray = RaycastParams.new()
ray.FilterType = Enum.RaycastFilterType.Exclude
ray.RespectCanCollide = true
ray.IgnoreWater = true

local function setModel(value: Model)
	model = value
	local _, size = value:GetBoundingBox()
	span = math.clamp(math.max(size.X, size.Y, size.Z), 20, 65)
	pose = nil
end

function Camera.Stop()
	if not active then return end
	active = false
	RunService:UnbindFromRenderStep(STEP)
	local camera = Workspace.CurrentCamera
	local human = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	if camera then
		camera.CameraType = Enum.CameraType.Custom
		if human then camera.CameraSubject = human end
		if saved then camera.FieldOfView = saved.fov end
		local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
		if root and root:IsA("BasePart") then
			local at = root.Position + Vector3.new(0, 1.5, 0)
			camera.CFrame = CFrame.lookAt(at - root.CFrame.LookVector * 6 + Vector3.new(0, 2, 0), at)
			camera.Focus = CFrame.new(at)
		end
	end
	if saved then Input.MouseBehavior = saved.mouse; Input.MouseIconEnabled = saved.icon end
	model, pose, saved = nil, nil, nil
end

function Camera.Start(helicopter: Model?)
	if helicopter and helicopter:IsA("Model") then setModel(helicopter) end
	if active then return end
	active = true
	local initial = Workspace.CurrentCamera
	saved = { fov = if initial then initial.FieldOfView else 70, mouse = Input.MouseBehavior, icon = Input.MouseIconEnabled }
	if initial then initial.CameraType = Enum.CameraType.Scriptable end
	RunService:BindToRenderStep(STEP, Enum.RenderPriority.Camera.Value + 30, function(dt)
		local camera = Workspace.CurrentCamera
		if not camera then return end
		camera.CameraType = Enum.CameraType.Scriptable
		Input.MouseBehavior = Enum.MouseBehavior.Default
		Input.MouseIconEnabled = true
		-- Com streaming, o remote pode chegar antes do Model.
		if not model or not model.Parent then
			local island = Workspace:FindFirstChild("Ilha")
			local found = island and island:FindFirstChild("Helicoptero")
			if found and found:IsA("Model") and found:GetAttribute("ExtractionHelicopter") == true then setModel(found) end
		end
		local target = model
		if not target or not target.Parent then return end
		local pivot = target:GetPivot()
		local forward = Vector3.new(pivot.LookVector.X, 0, pivot.LookVector.Z)
		if forward.Magnitude < 0.01 then forward = Vector3.new(0, 0, -1) end
		local level = CFrame.lookAt(pivot.Position, pivot.Position + forward)
		local aspect = camera.ViewportSize.X / math.max(1, camera.ViewportSize.Y)
		local distance = span * 1.15 / math.clamp(aspect, 0.55, 1)
		local at = pivot.Position + Vector3.new(0, 2, 0)
		local position = level:PointToWorldSpace(Vector3.new(distance * 0.65, distance * 0.42, distance))
		local excluded: { Instance } = { target }
		for _, other in Players:GetPlayers() do
			if other.Character then table.insert(excluded, other.Character) end
		end
		ray.FilterDescendantsInstances = excluded
		local hit = Workspace:Raycast(at, position - at, ray)
		if hit then position = hit.Position + hit.Normal * 2 end
		local desired = CFrame.lookAt(position, at)
		pose = if pose then pose:Lerp(desired, 1 - math.exp(-10 * math.min(dt, 0.1))) else desired
		camera.CFrame = pose :: CFrame
		camera.Focus = CFrame.new(at)
		camera.FieldOfView = 65
	end)
end

return Camera
