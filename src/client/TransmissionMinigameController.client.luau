--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Remotes = require(ReplicatedStorage.Modules.Remotes)
local UIConfig = require(ReplicatedStorage.Modules.TransmissionUIConfig)

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local gui = Instance.new("ScreenGui")
gui.Name = "TransmissionMinigame"
gui.DisplayOrder = 40
gui.IgnoreGuiInset = true
gui.ResetOnSpawn = false
gui.Enabled = false
gui.Parent = playerGui

local shade = Instance.new("TextButton")
shade.Name = "Shade"
shade.Size = UDim2.fromScale(1, 1)
shade.BackgroundColor3 = Color3.new(0, 0, 0)
shade.BackgroundTransparency = 0.22
shade.BorderSizePixel = 0
shade.AutoButtonColor = false
shade.Modal = true
shade.Text = ""
shade.Parent = gui

local image = Instance.new("ImageLabel")
image.Name = "PanelImage"
image.AnchorPoint = Vector2.new(0.5, 0.5)
image.Position = UDim2.fromScale(0.5, 0.43)
image.BackgroundColor3 = Color3.fromRGB(12, 10, 9)
image.BorderSizePixel = 0
image.ScaleType = Enum.ScaleType.Fit
image.Active = true
image.Parent = shade

local imageCorner = Instance.new("UICorner")
imageCorner.CornerRadius = UDim.new(0, 4)
imageCorner.Parent = image

local imageStroke = Instance.new("UIStroke")
imageStroke.Color = Color3.fromRGB(104, 78, 55)
imageStroke.Thickness = 2
imageStroke.Transparency = 0.25
imageStroke.Parent = image

local missingImage = Instance.new("TextLabel")
missingImage.Name = "MissingImage"
missingImage.Size = UDim2.fromScale(1, 1)
missingImage.BackgroundTransparency = 1
missingImage.Font = Enum.Font.GothamMedium
missingImage.Text = "Imagem ainda nao publicada"
missingImage.TextColor3 = Color3.fromRGB(210, 194, 174)
missingImage.TextScaled = true
missingImage.Parent = image

local missingPadding = Instance.new("UIPadding")
missingPadding.PaddingLeft = UDim.new(0.2, 0)
missingPadding.PaddingRight = UDim.new(0.2, 0)
missingPadding.PaddingTop = UDim.new(0.4, 0)
missingPadding.PaddingBottom = UDim.new(0.4, 0)
missingPadding.Parent = missingImage

local close = Instance.new("TextButton")
close.Name = "Close"
close.AnchorPoint = Vector2.new(0.5, 0.5)
close.BackgroundColor3 = Color3.fromRGB(24, 20, 18)
close.BorderSizePixel = 0
close.Font = Enum.Font.GothamBold
close.Text = "X"
close.TextColor3 = Color3.fromRGB(238, 229, 217)
close.TextSize = 17
close.ZIndex = 8
close.Parent = shade

local closeCorner = Instance.new("UICorner")
closeCorner.CornerRadius = UDim.new(0, 4)
closeCorner.Parent = close

local closeStroke = Instance.new("UIStroke")
closeStroke.Color = Color3.fromRGB(130, 103, 77)
closeStroke.Transparency = 0.25
closeStroke.Parent = close

local dropZone = Instance.new("Frame")
dropZone.Name = "MissingFuseSlot"
dropZone.BackgroundColor3 = Color3.fromRGB(245, 175, 74)
dropZone.BackgroundTransparency = 1
dropZone.BorderSizePixel = 0
dropZone.ZIndex = 4
dropZone.Parent = image

local dropStroke = Instance.new("UIStroke")
dropStroke.Color = Color3.fromRGB(255, 191, 92)
dropStroke.Thickness = 3
dropStroke.Transparency = 1
dropStroke.Parent = dropZone

local status = Instance.new("TextLabel")
status.Name = "Status"
status.AnchorPoint = Vector2.new(0.5, 0.5)
status.BackgroundTransparency = 1
status.Font = Enum.Font.GothamMedium
status.TextColor3 = Color3.fromRGB(230, 214, 190)
status.TextSize = 14
status.Text = ""
status.ZIndex = 8
status.Parent = shade

-- O item arrastavel e desenhado em UI para continuar nitido em qualquer tela.
local fuse = Instance.new("TextButton")
fuse.Name = "Fuse"
fuse.AnchorPoint = Vector2.new(0.5, 0.5)
fuse.BackgroundColor3 = Color3.fromRGB(151, 145, 133)
fuse.BorderSizePixel = 0
fuse.AutoButtonColor = false
fuse.Text = ""
fuse.ZIndex = 10
fuse.Parent = shade

local fuseCorner = Instance.new("UICorner")
fuseCorner.CornerRadius = UDim.new(0.5, 0)
fuseCorner.Parent = fuse

local fuseStroke = Instance.new("UIStroke")
fuseStroke.Color = Color3.fromRGB(69, 48, 33)
fuseStroke.Thickness = 3
fuseStroke.Parent = fuse

local glass = Instance.new("Frame")
glass.Name = "Glass"
glass.AnchorPoint = Vector2.new(0.5, 0.5)
glass.Position = UDim2.fromScale(0.5, 0.5)
glass.Size = UDim2.fromScale(0.56, 0.58)
glass.BackgroundColor3 = Color3.fromRGB(220, 211, 190)
glass.BackgroundTransparency = 0.08
glass.BorderSizePixel = 0
glass.ZIndex = 11
glass.Parent = fuse

local glassCorner = Instance.new("UICorner")
glassCorner.CornerRadius = UDim.new(0.5, 0)
glassCorner.Parent = glass

local filament = Instance.new("Frame")
filament.Name = "Filament"
filament.AnchorPoint = Vector2.new(0.5, 0.5)
filament.Position = UDim2.fromScale(0.5, 0.5)
filament.Size = UDim2.fromScale(0.1, 0.78)
filament.BackgroundColor3 = Color3.fromRGB(117, 69, 35)
filament.BorderSizePixel = 0
filament.ZIndex = 12
filament.Parent = glass

local dragging = false
local pending = false
local dragInput: InputObject? = nil
local dragOffset = Vector2.zero
local fuseHome = Vector2.zero

local function setImage(asset: string)
	image.Image = asset
	missingImage.Visible = asset == ""
end

local function viewportSize(): Vector2
	local camera = Workspace.CurrentCamera
	return if camera then camera.ViewportSize else Vector2.new(1280, 720)
end

local function layout()
	local viewport = viewportSize()
	local width = math.min(viewport.X * 0.9, viewport.Y * 0.68 * 1.5, 1080)
	local height = width / 1.5
	image.Size = UDim2.fromOffset(width, height)

	close.Size = UDim2.fromOffset(36, 36)
	close.Position = UDim2.fromOffset(viewport.X * 0.5 + width * 0.5 - 18, viewport.Y * 0.43 - height * 0.5 + 18)
	status.Size = UDim2.fromOffset(math.min(420, viewport.X - 32), 24)
	status.Position = UDim2.fromOffset(viewport.X * 0.5, viewport.Y * 0.43 + height * 0.5 + 17)

	-- Coordenadas do encaixe vazio na arte 1536x1024.
	dropZone.Position = UDim2.fromScale(0.374, 0.265)
	dropZone.Size = UDim2.fromScale(0.145, 0.48)

	local fuseHeight = math.clamp(height * 0.22, 74, 130)
	fuse.Size = UDim2.fromOffset(fuseHeight * 0.34, fuseHeight)
	fuseHome = Vector2.new(viewport.X * 0.5, math.min(viewport.Y - fuseHeight * 0.58 - 12, viewport.Y * 0.43 + height * 0.5 + fuseHeight * 0.62 + 22))
	if not dragging and not pending then
		fuse.Position = UDim2.fromOffset(fuseHome.X, fuseHome.Y)
	end
end

local function setDropHighlight(visible: boolean)
	TweenService:Create(dropStroke, TweenInfo.new(0.12), { Transparency = if visible then 0.12 else 1 }):Play()
	TweenService:Create(dropZone, TweenInfo.new(0.12), { BackgroundTransparency = if visible then 0.88 else 1 }):Play()
end

local function resetFuse(message: string?)
	pending = false
	dragging = false
	dragInput = nil
	fuse.Active = true
	setDropHighlight(false)
	TweenService:Create(fuse, TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Position = UDim2.fromOffset(fuseHome.X, fuseHome.Y),
	}):Play()
	status.Text = message or ""
end

local function insideDropZone(point: Vector2): boolean
	local p = dropZone.AbsolutePosition
	local s = dropZone.AbsoluteSize
	return point.X >= p.X and point.X <= p.X + s.X and point.Y >= p.Y and point.Y <= p.Y + s.Y
end

local function finishDrag()
	if not dragging then
		return
	end
	dragging = false
	dragInput = nil
	setDropHighlight(false)

	local center = fuse.AbsolutePosition + fuse.AbsoluteSize * 0.5
	if not insideDropZone(center) then
		resetFuse(nil)
		return
	end

	pending = true
	fuse.Active = false
	local target = dropZone.AbsolutePosition + dropZone.AbsoluteSize * 0.5
	TweenService:Create(fuse, TweenInfo.new(0.16, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Position = UDim2.fromOffset(target.X, target.Y),
	}):Play()
	Remotes.TransmissionMinigame:FireServer("InstallFuse")
end

fuse.InputBegan:Connect(function(input: InputObject)
	if pending or (input.UserInputType ~= Enum.UserInputType.MouseButton1 and input.UserInputType ~= Enum.UserInputType.Touch) then
		return
	end
	dragging = true
	dragInput = input
	dragOffset = Vector2.new(input.Position.X, input.Position.Y) - (fuse.AbsolutePosition + fuse.AbsoluteSize * 0.5)
	status.Text = ""
	setDropHighlight(true)
end)

UserInputService.InputChanged:Connect(function(input: InputObject)
	if not dragging then
		return
	end
	local isMouse = input.UserInputType == Enum.UserInputType.MouseMovement
	if input ~= dragInput and not isMouse then
		return
	end
	local point = Vector2.new(input.Position.X, input.Position.Y) - dragOffset
	fuse.Position = UDim2.fromOffset(point.X, point.Y)
end)

UserInputService.InputEnded:Connect(function(input: InputObject)
	if dragging and (input == dragInput or input.UserInputType == Enum.UserInputType.MouseButton1) then
		finishDrag()
	end
end)

local function closeUI()
	if pending then
		return
	end
	gui.Enabled = false
	dragging = false
	dragInput = nil
	status.Text = ""
end

close.Activated:Connect(closeUI)
shade.Activated:Connect(function()
	closeUI()
end)

UserInputService.InputBegan:Connect(function(input: InputObject, processed: boolean)
	if not processed and gui.Enabled and input.KeyCode == Enum.KeyCode.Escape then
		closeUI()
	end
end)

local function openFuse(hasFuse: boolean)
	pending = false
	dragging = false
	setImage(UIConfig.FuseBoxImage)
	dropZone.Visible = true
	fuse.Visible = hasFuse
	status.Text = ""
	gui.Enabled = true
	layout()
end

local function openPanel()
	pending = false
	dragging = false
	setImage(UIConfig.ControlPanelImage)
	dropZone.Visible = false
	fuse.Visible = false
	status.Text = ""
	gui.Enabled = true
	layout()
end

Remotes.TransmissionMinigame.OnClientEvent:Connect(function(action: string, first: unknown, second: unknown)
	if action == "OpenFuse" then
		openFuse(first == true)
	elseif action == "OpenPanel" then
		openPanel()
	elseif action == "FuseResult" then
		if first == true then
			pending = false
			gui.Enabled = false
		else
			resetFuse(if type(second) == "string" then second else "Nao foi possivel instalar o fusivel.")
		end
	end
end)

local camera = Workspace.CurrentCamera
if camera then
	camera:GetPropertyChangedSignal("ViewportSize"):Connect(layout)
end
Workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function()
	camera = Workspace.CurrentCamera
	if camera then
		camera:GetPropertyChangedSignal("ViewportSize"):Connect(layout)
	end
	layout()
end)
