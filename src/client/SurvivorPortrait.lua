--!strict
-- Shared icon/hero renderer. Resolves presentation assets from CharacterData,
-- sanitizes model copies, and fits the full body to the actual viewport aspect.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local SelectionConfig = require(ReplicatedStorage.Modules.SurvivorSelectionConfig)

local CharacterData = require(ReplicatedStorage.Modules.CharacterData)
local State = require(ReplicatedStorage.Modules.SurvivorSelectionState)
local Assets = require(script.Parent.SurvivorSelectionAssets)
local SurvivorPortrait = {}

local function part(
	model: Model,
	name: string,
	size: Vector3,
	position: Vector3,
	color: Color3,
	rotation: CFrame?
): Part
	local item = Instance.new("Part")
	item.Name = name
	item.Size = size
	item.CFrame = CFrame.new(position) * (rotation or CFrame.new())
	item.Color = color
	item.Material = Enum.Material.SmoothPlastic
	item.Anchored = true
	item.CanCollide = false
	item.CanTouch = false
	item.CanQuery = false
	item.CastShadow = true
	item.Parent = model
	return item
end

local function buildPlaceholder(characterId: string): Model
	local profile = SelectionConfig.GetPortrait(characterId)
	local model = Instance.new("Model")
	model.Name = characterId .. "PreviewR6"

	part(model, "Torso", Vector3.new(2, 2, 1), Vector3.new(0, 3.1, 0), profile.ShirtColor)
	local head = part(model, "Head", Vector3.new(2, 1, 1), Vector3.new(0, 4.65, 0), profile.BodyColor)
	local headMesh = Instance.new("SpecialMesh")
	headMesh.MeshType = Enum.MeshType.Head
	headMesh.Scale = Vector3.new(1.25, 1.25, 1.25)
	headMesh.Parent = head

	-- Pose neutra levemente relaxada, sem AnimationController e sem qualquer
	-- vinculo com o personagem real do jogador.
	part(model, "Left Arm", Vector3.new(1, 2, 1), Vector3.new(-1.52, 3.02, 0), profile.BodyColor, CFrame.Angles(0, 0, math.rad(-4)))
	part(model, "Right Arm", Vector3.new(1, 2, 1), Vector3.new(1.52, 3.02, 0), profile.BodyColor, CFrame.Angles(0, 0, math.rad(4)))
	part(model, "Left Leg", Vector3.new(1, 2, 1), Vector3.new(-0.52, 1.08, 0), profile.PantsColor, CFrame.Angles(0, 0, math.rad(-1)))
	part(model, "Right Leg", Vector3.new(1, 2, 1), Vector3.new(0.52, 1.08, 0), profile.PantsColor, CFrame.Angles(0, 0, math.rad(1)))

	local face = Instance.new("Decal")
	face.Name = "face"
	face.Texture = "rbxasset://textures/face.png"
	face.Face = Enum.NormalId.Front
	face.Parent = head
	return model
end

local function customRig(characterId: string): Model?
	local profile = SelectionConfig.GetPortrait(characterId)
	local template = Assets.Find("PreviewModels", profile.RigName or characterId)
	-- Compatibility with rigs imported before SelectionAssets existed.
	local legacy = ReplicatedStorage:FindFirstChild("SurvivorPreviewRigs")
	if not template and legacy then template = legacy:FindFirstChild(profile.RigName or characterId) end
	if not template or not template:IsA("Model") or not template.Archivable then return nil end
	local clone = template:Clone()
	if not clone:FindFirstChildWhichIsA("BasePart", true) then clone:Destroy(); return nil end
	-- Strip executable content BEFORE parenting the clone anywhere rendered.
	for _, descendant in clone:GetDescendants() do
		if descendant:IsA("LuaSourceContainer") or descendant:IsA("Sound") then
			descendant:Destroy()
		elseif descendant:IsA("BasePart") then
			descendant.Anchored = true
			descendant.CanCollide = false
			descendant.CanTouch = false
			descendant.CanQuery = false
		end
	end
	return clone
end

function SurvivorPortrait.Viewport(parent: Instance, characterId: string)
	local frame = Instance.new("ViewportFrame")
	frame.Name = "Portrait"
	frame.Size = UDim2.fromScale(1, 1)
	frame.BackgroundTransparency = 1
	frame.BorderSizePixel = 0
	frame.Ambient = Color3.fromRGB(155, 173, 186)
	frame.LightColor = Color3.fromRGB(217, 236, 245)
	frame.LightDirection = Vector3.new(1, -0.6, -1)
	frame.Parent = parent
	local world = Instance.new("WorldModel")
	world.Name = "PreviewWorld"
	world.Parent = frame
	local rig = customRig(characterId) or buildPlaceholder(characterId)
	rig.Parent = world
	local camera = Instance.new("Camera")
	camera.FieldOfView = 34
	camera.Parent = frame
	frame.CurrentCamera = camera
	local bounds, size = rig:GetBoundingBox()
	-- Normalize position AND orientation so the measured box matches camera axes.
	-- A template saved sideways in Studio must not invalidate the framing math.
	rig:PivotTo(bounds:Inverse() * rig:GetPivot())
	local distance = 10
	local function fit()
		local pixels = frame.AbsoluteSize
		distance = State.CameraDistance(size.X, size.Y, size.Z, pixels.X / math.max(1, pixels.Y), camera.FieldOfView)
		camera.CFrame = CFrame.lookAt(Vector3.new(0, 0, -distance), Vector3.zero)
	end
	local resize = frame:GetPropertyChangedSignal("AbsoluteSize"):Connect(fit)
	fit()
	local track: AnimationTrack? = nil
	local portrait = { Root = frame }
	function portrait.Step(time: number)
		-- A slight camera orbit is cheap and works for both static R6 and future rigs.
		local angle = math.rad(6) + math.sin(time * 0.55) * math.rad(2)
		local eye = Vector3.new(math.sin(angle) * distance, math.sin(time * 1.1) * size.Y * 0.006, -math.cos(angle) * distance)
		camera.CFrame = CFrame.lookAt(eye, Vector3.zero)
	end
	function portrait.PlayIdle()
		local character = CharacterData.GetById(characterId)
		local reference = character and character.IdleAnimation
		if not reference or reference == "" then reference = character and character.PreviewModel end
		local id = Assets.Content("IdleAnimations", reference)
		if id == "" then return end
		local humanoid = rig:FindFirstChildOfClass("Humanoid")
		local host: Instance = humanoid or rig:FindFirstChildOfClass("AnimationController") or Instance.new("AnimationController", rig)
		local animator = host:FindFirstChildOfClass("Animator") or Instance.new("Animator", host)
		local root = rig:FindFirstChild("HumanoidRootPart")
		if root and root:IsA("BasePart") then
			for _, item in rig:GetDescendants() do
				if item:IsA("BasePart") then item.Anchored = item == root end
			end
		end
		local animation = Instance.new("Animation")
		animation.AnimationId = id
		animation.Parent = rig
		local ok, result = pcall(function() return (animator :: Animator):LoadAnimation(animation) end)
		if ok then
			track = result
			result.Looped = true
			result:Play(0.2)
		else warn("[SurvivorPreview] Idle indisponível: " .. tostring(result)) end
	end
	function portrait.Destroy()
		resize:Disconnect()
		if track then track:Stop(); track:Destroy(); track = nil end
		frame:Destroy()
	end
	return portrait
end

function SurvivorPortrait.Create(parent: Instance, characterId: string): GuiObject
	local profile = SelectionConfig.GetPortrait(characterId)
	local reference = profile.ImageId
	if not reference or reference == "" then reference = profile.RigName or characterId end
	local content = Assets.Content("CharacterIcons", reference)
	if content ~= "" then
		local image = Instance.new("ImageLabel")
		image.Name = "Portrait"
		image.Size = UDim2.fromScale(1, 1)
		image.BackgroundTransparency = 1
		image.Image = content
		image.ScaleType = Enum.ScaleType.Fit
		image.Parent = parent
		return image
	end
	local portrait = SurvivorPortrait.Viewport(parent, characterId)
	-- The frame owns its resize signal. Destroying it disconnects the signal.
	return portrait.Root
end
return SurvivorPortrait
