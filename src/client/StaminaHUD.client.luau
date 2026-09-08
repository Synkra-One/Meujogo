--!strict
--[[
	SurvivalStatusHUD

	Mantém a parte autoritativa do sprint (envia intenção para o servidor),
	mas troca a antiga barra horizontal de fôlego por um widget circular no
	canto direito: rosto do personagem no centro + fôlego em volta.

	A vida não fica aparente. Quando o Humanoid toma dano, a resposta visual é
	sangue/vinheta na tela por alguns instantes.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local ContextActionService = game:GetService("ContextActionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterGui = game:GetService("StarterGui")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")

local Remotes = require(ReplicatedStorage.Modules.Remotes)

local LocalPlayer = Players.LocalPlayer
local playerGui = LocalPlayer:WaitForChild("PlayerGui")

local WIDGET_SIZE = 154
local FACE_SIZE = 104
local SEGMENTS = 48
local RING_RADIUS = 66
local BLOOD_IMAGE = "rbxassetid://176533208"

--------------------------------------------------------------------------------
-- Esconde qualquer HUD de vida antiga/padrão
--------------------------------------------------------------------------------

local function hideCoreHealth()
	for _ = 1, 20 do
		local ok = pcall(function()
			StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Health, false)
		end)
		if ok then
			break
		end
		task.wait(0.25)
	end
end

local function removeLegacyHealthGui()
	local legacy = playerGui:FindFirstChild("PixelHealthGui")
	if legacy then
		legacy:Destroy()
	end
end

task.spawn(hideCoreHealth)
removeLegacyHealthGui()
playerGui.ChildAdded:Connect(function(child: Instance)
	if child.Name == "PixelHealthGui" then
		child:Destroy()
	end
end)

--------------------------------------------------------------------------------
-- Intenção de correr
--------------------------------------------------------------------------------

local holding = false

local function setHolding(value: boolean)
	if value == holding then
		return
	end
	holding = value
	Remotes.SprintIntent:FireServer(value)
end

UserInputService.InputBegan:Connect(function(input: InputObject, gameProcessed: boolean)
	if gameProcessed then
		return
	end
	if input.KeyCode == Enum.KeyCode.LeftShift or input.KeyCode == Enum.KeyCode.RightShift then
		setHolding(true)
	end
end)

UserInputService.InputEnded:Connect(function(input: InputObject)
	if input.KeyCode == Enum.KeyCode.LeftShift or input.KeyCode == Enum.KeyCode.RightShift then
		setHolding(false)
	end
end)

ContextActionService:BindAction("SprintIntent", function(_, state: Enum.UserInputState)
	if state == Enum.UserInputState.Begin then
		setHolding(true)
	elseif state == Enum.UserInputState.End or state == Enum.UserInputState.Cancel then
		setHolding(false)
	end
	return Enum.ContextActionResult.Pass
end, UserInputService.TouchEnabled, Enum.KeyCode.ButtonL3)

if UserInputService.TouchEnabled then
	ContextActionService:SetTitle("SprintIntent", "Correr")
end

LocalPlayer.CharacterRemoving:Connect(function()
	setHolding(false)
end)

--------------------------------------------------------------------------------
-- HUD circular
--------------------------------------------------------------------------------

local gui = Instance.new("ScreenGui")
gui.Name = "SurvivalStatusHUD"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.DisplayOrder = 20
gui.Parent = playerGui

local widget = Instance.new("CanvasGroup")
widget.Name = "PortraitStamina"
widget.AnchorPoint = Vector2.new(1, 1)
widget.Position = UDim2.new(1, -34, 1, -172)
widget.Size = UDim2.fromOffset(WIDGET_SIZE, WIDGET_SIZE)
widget.BackgroundTransparency = 1
widget.Parent = gui

local shadow = Instance.new("Frame")
shadow.Name = "Shadow"
shadow.AnchorPoint = Vector2.new(0.5, 0.5)
shadow.Position = UDim2.fromScale(0.5, 0.5)
shadow.Size = UDim2.fromOffset(132, 132)
shadow.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
shadow.BackgroundTransparency = 0.42
shadow.BorderSizePixel = 0
shadow.ZIndex = 1
shadow.Parent = widget
local shadowCorner = Instance.new("UICorner")
shadowCorner.CornerRadius = UDim.new(1, 0)
shadowCorner.Parent = shadow

local backRing = Instance.new("Frame")
backRing.Name = "BackRing"
backRing.AnchorPoint = Vector2.new(0.5, 0.5)
backRing.Position = UDim2.fromScale(0.5, 0.5)
backRing.Size = UDim2.fromOffset(126, 126)
backRing.BackgroundTransparency = 1
backRing.ZIndex = 2
backRing.Parent = widget
local backStroke = Instance.new("UIStroke")
backStroke.Color = Color3.fromRGB(210, 215, 205)
backStroke.Transparency = 0.68
backStroke.Thickness = 3
backStroke.Parent = backRing
local backCorner = Instance.new("UICorner")
backCorner.CornerRadius = UDim.new(1, 0)
backCorner.Parent = backRing

local dangerGlow = Instance.new("Frame")
dangerGlow.Name = "DangerGlow"
dangerGlow.AnchorPoint = Vector2.new(0.5, 0.5)
dangerGlow.Position = UDim2.fromScale(0.5, 0.5)
dangerGlow.Size = UDim2.fromOffset(142, 142)
dangerGlow.BackgroundTransparency = 1
dangerGlow.ZIndex = 2
dangerGlow.Parent = widget
local dangerStroke = Instance.new("UIStroke")
dangerStroke.Color = Color3.fromRGB(255, 54, 39)
dangerStroke.Transparency = 1
dangerStroke.Thickness = 4
dangerStroke.Parent = dangerGlow
local dangerCorner = Instance.new("UICorner")
dangerCorner.CornerRadius = UDim.new(1, 0)
dangerCorner.Parent = dangerGlow

local faceFrame = Instance.new("Frame")
faceFrame.Name = "FaceFrame"
faceFrame.AnchorPoint = Vector2.new(0.5, 0.5)
faceFrame.Position = UDim2.fromScale(0.5, 0.5)
faceFrame.Size = UDim2.fromOffset(FACE_SIZE, FACE_SIZE)
faceFrame.BackgroundColor3 = Color3.fromRGB(16, 18, 20)
faceFrame.BackgroundTransparency = 0.03
faceFrame.BorderSizePixel = 0
faceFrame.ZIndex = 4
faceFrame.ClipsDescendants = true
faceFrame.Parent = widget
local faceCorner = Instance.new("UICorner")
faceCorner.CornerRadius = UDim.new(1, 0)
faceCorner.Parent = faceFrame
local faceStroke = Instance.new("UIStroke")
faceStroke.Color = Color3.fromRGB(245, 239, 218)
faceStroke.Transparency = 0.28
faceStroke.Thickness = 2
faceStroke.Parent = faceFrame

local viewport = Instance.new("ViewportFrame")
viewport.Name = "CharacterFace"
viewport.Size = UDim2.fromScale(1, 1)
viewport.BackgroundTransparency = 1
viewport.Ambient = Color3.fromRGB(105, 108, 112)
viewport.LightColor = Color3.fromRGB(255, 238, 210)
viewport.LightDirection = Vector3.new(-0.35, -0.55, -1)
viewport.ZIndex = 5
viewport.Parent = faceFrame

local world = Instance.new("WorldModel")
world.Parent = viewport

local camera = Instance.new("Camera")
camera.FieldOfView = 28
camera.CFrame = CFrame.new(Vector3.new(0, 0.08, -2.75), Vector3.new(0, 0.04, 0))
camera.Parent = viewport
viewport.CurrentCamera = camera

local fallbackFace = Instance.new("TextLabel")
fallbackFace.Name = "FallbackFace"
fallbackFace.Size = UDim2.fromScale(1, 1)
fallbackFace.BackgroundTransparency = 1
fallbackFace.Font = Enum.Font.GothamBlack
fallbackFace.Text = "?"
fallbackFace.TextSize = 42
fallbackFace.TextColor3 = Color3.fromRGB(235, 228, 210)
fallbackFace.TextTransparency = 0.15
fallbackFace.ZIndex = 6
fallbackFace.Parent = faceFrame

local caption = Instance.new("TextLabel")
caption.Name = "Caption"
caption.AnchorPoint = Vector2.new(0.5, 1)
caption.Position = UDim2.new(0.5, 0, 1, -12)
caption.Size = UDim2.fromOffset(88, 18)
caption.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
caption.BackgroundTransparency = 0.58
caption.BorderSizePixel = 0
caption.Font = Enum.Font.GothamBold
caption.Text = "FÔLEGO"
caption.TextSize = 10
caption.TextColor3 = Color3.fromRGB(235, 232, 220)
caption.TextStrokeTransparency = 0.75
caption.ZIndex = 8
caption.Parent = widget
local captionCorner = Instance.new("UICorner")
captionCorner.CornerRadius = UDim.new(1, 0)
captionCorner.Parent = caption

local ringSegments: { Frame } = {}
for i = 1, SEGMENTS do
	local angle = math.rad(-225 + ((i - 1) / SEGMENTS) * 360)
	local segment = Instance.new("Frame")
	segment.Name = string.format("Folego_%02d", i)
	segment.AnchorPoint = Vector2.new(0.5, 0.5)
	segment.Position = UDim2.new(
		0.5,
		math.cos(angle) * RING_RADIUS,
		0.5,
		math.sin(angle) * RING_RADIUS
	)
	segment.Size = UDim2.fromOffset(5, 17)
	segment.Rotation = math.deg(angle) + 90
	segment.BackgroundColor3 = Color3.fromRGB(232, 206, 113)
	segment.BackgroundTransparency = 0.08
	segment.BorderSizePixel = 0
	segment.ZIndex = 7
	segment.Parent = widget
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(1, 0)
	corner.Parent = segment
	ringSegments[i] = segment
end

--------------------------------------------------------------------------------
-- Rosto do personagem
--------------------------------------------------------------------------------

local function clearWorld()
	for _, child in world:GetChildren() do
		child:Destroy()
	end
end

local function sanitizeClone(instance: Instance)
	for _, descendant in instance:GetDescendants() do
		if descendant:IsA("Script") or descendant:IsA("LocalScript") or descendant:IsA("ModuleScript") then
			descendant:Destroy()
		elseif descendant:IsA("BasePart") then
			descendant.Anchored = true
			descendant.CanCollide = false
			descendant.CanTouch = false
			descendant.CanQuery = false
		end
	end
end

local function rebuildPortrait(character: Model)
	clearWorld()
	fallbackFace.Visible = true

	local head = character:FindFirstChild("Head")
	if not head or not head:IsA("BasePart") then
		return
	end

	local clone = head:Clone()
	sanitizeClone(clone)
	clone.CFrame = CFrame.new(0, 0, 0)
	clone.Parent = world

	local cosmetic = character:FindFirstChild("MonsterCosmetic")
	if cosmetic then
		for _, item in cosmetic:GetChildren() do
			if item:IsA("BasePart") then
				local weld = item:FindFirstChildOfClass("WeldConstraint")
				if weld and weld.Part0 == head then
					local accessory = item:Clone()
					sanitizeClone(accessory)
					accessory.CFrame = clone.CFrame * head.CFrame:ToObjectSpace(item.CFrame)
					accessory.Parent = world
				end
			end
		end
	end

	local largest = math.max(clone.Size.X, clone.Size.Y, clone.Size.Z)
	camera.CFrame = CFrame.new(Vector3.new(0, largest * 0.03, -largest * 2.35), Vector3.new(0, 0, 0))
	fallbackFace.Visible = false
end

--------------------------------------------------------------------------------
-- Sangue/dano na tela
--------------------------------------------------------------------------------

local damageLayer = Instance.new("Frame")
damageLayer.Name = "DamageLayer"
damageLayer.Size = UDim2.fromScale(1, 1)
damageLayer.BackgroundTransparency = 1
damageLayer.ZIndex = 100
damageLayer.Parent = gui

local damageVignette = Instance.new("ImageLabel")
damageVignette.Name = "BloodVignette"
damageVignette.AnchorPoint = Vector2.new(0.5, 0.5)
damageVignette.Position = UDim2.fromScale(0.5, 0.5)
damageVignette.Size = UDim2.fromScale(1.28, 1.28)
damageVignette.BackgroundTransparency = 1
damageVignette.Image = BLOOD_IMAGE
damageVignette.ImageColor3 = Color3.fromRGB(155, 0, 0)
damageVignette.ImageTransparency = 1
damageVignette.ScaleType = Enum.ScaleType.Stretch
damageVignette.ZIndex = 101
damageVignette.Parent = damageLayer

local redFlash = Instance.new("Frame")
redFlash.Name = "RedFlash"
redFlash.Size = UDim2.fromScale(1, 1)
redFlash.BackgroundColor3 = Color3.fromRGB(120, 0, 0)
redFlash.BackgroundTransparency = 1
redFlash.BorderSizePixel = 0
redFlash.ZIndex = 100
redFlash.Parent = damageLayer

local function createBloodSplash(strength: number)
	local splash = Instance.new("ImageLabel")
	splash.Name = "BloodSplash"
	splash.AnchorPoint = Vector2.new(0.5, 0.5)
	splash.BackgroundTransparency = 1
	splash.Image = BLOOD_IMAGE
	splash.ImageColor3 = Color3.fromRGB(110 + math.random(0, 55), 0, 0)
	splash.ImageTransparency = 1
	splash.Rotation = math.random(0, 359)
	splash.ScaleType = Enum.ScaleType.Stretch
	splash.ZIndex = 102

	local side = math.random(1, 4)
	local x = math.random(12, 88) / 100
	local y = math.random(12, 88) / 100
	if side == 1 then
		x = math.random(3, 20) / 100
	elseif side == 2 then
		x = math.random(80, 97) / 100
	elseif side == 3 then
		y = math.random(3, 20) / 100
	else
		y = math.random(80, 97) / 100
	end

	local size = math.random(240, 430) * (0.75 + strength * 0.5)
	splash.Position = UDim2.fromScale(x, y)
	splash.Size = UDim2.fromOffset(size, size)
	splash.Parent = damageLayer

	TweenService:Create(splash, TweenInfo.new(0.08, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		ImageTransparency = 0.42 - strength * 0.16,
		Size = UDim2.fromOffset(size * 1.05, size * 1.05),
	}):Play()

	task.delay(0.18, function()
		if splash.Parent then
			TweenService:Create(splash, TweenInfo.new(1.1, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
				ImageTransparency = 1,
				Size = UDim2.fromOffset(size * 1.18, size * 1.18),
			}):Play()
		end
	end)

	Debris:AddItem(splash, 1.45)
end

local currentDamageTweens: { Tween } = {}

local function cancelDamageTweens()
	for _, tween in currentDamageTweens do
		tween:Cancel()
	end
	table.clear(currentDamageTweens)
end

local function flashDamage(damage: number, maxHealth: number)
	local strength = math.clamp(damage / math.max(maxHealth, 1), 0.18, 0.9)
	cancelDamageTweens()

	damageVignette.ImageTransparency = 1 - (0.38 + strength * 0.38)
	damageVignette.Size = UDim2.fromScale(1.22, 1.22)
	redFlash.BackgroundTransparency = 1 - (0.12 + strength * 0.18)

	local grow = TweenService:Create(damageVignette, TweenInfo.new(0.16, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Size = UDim2.fromScale(1.34, 1.34),
	})
	local fadeVignette = TweenService:Create(damageVignette, TweenInfo.new(1.05, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
		ImageTransparency = 1,
	})
	local fadeFlash = TweenService:Create(redFlash, TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		BackgroundTransparency = 1,
	})

	table.insert(currentDamageTweens, grow)
	table.insert(currentDamageTweens, fadeVignette)
	table.insert(currentDamageTweens, fadeFlash)

	grow:Play()
	fadeFlash:Play()
	task.delay(0.12, function()
		fadeVignette:Play()
	end)

	for _ = 1, math.clamp(math.floor(2 + strength * 4), 2, 6) do
		createBloodSplash(strength)
	end
end

--------------------------------------------------------------------------------
-- Atualização
--------------------------------------------------------------------------------

local shown = 1
local healthConnection: RBXScriptConnection? = nil

local function hookCharacter(character: Model)
	rebuildPortrait(character)

	if healthConnection then
		healthConnection:Disconnect()
		healthConnection = nil
	end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		humanoid = character:WaitForChild("Humanoid", 8) :: Humanoid?
	end
	if not humanoid then
		return
	end

	local lastHealth = humanoid.Health
	damageVignette.ImageTransparency = 1
	redFlash.BackgroundTransparency = 1

	healthConnection = humanoid.HealthChanged:Connect(function(newHealth: number)
		if newHealth < lastHealth then
			flashDamage(lastHealth - newHealth, humanoid.MaxHealth)
		end
		lastHealth = newHealth
	end)
end

if LocalPlayer.Character then
	task.defer(hookCharacter, LocalPlayer.Character)
end
LocalPlayer.CharacterAdded:Connect(hookCharacter)

RunService.RenderStepped:Connect(function(dt: number)
	removeLegacyHealthGui()

	local raw = LocalPlayer:GetAttribute("Stamina")
	local target = math.clamp((if type(raw) == "number" then raw else 100) / 100, 0, 1)
	local exhausted = LocalPlayer:GetAttribute("StaminaExausto") == true

	shown += (target - shown) * math.min(1, dt * 14)

	local activeColor = if exhausted
		then Color3.fromRGB(255, 54, 39)
		elseif shown < 0.28 then Color3.fromRGB(255, 111, 55)
		elseif shown < 0.55 then Color3.fromRGB(235, 183, 75)
		else Color3.fromRGB(223, 229, 195)

	for i, segment in ringSegments do
		local active = (i / SEGMENTS) <= shown
		segment.BackgroundColor3 = activeColor
		segment.BackgroundTransparency = if active then 0.05 else 0.84
		segment.Size = if active then UDim2.fromOffset(5, 18) else UDim2.fromOffset(4, 13)
	end

	local pulse = (math.sin(os.clock() * 7) + 1) / 2
	if exhausted then
		dangerStroke.Transparency = 0.15 + pulse * 0.28
		caption.Text = "EXAUSTO"
		caption.TextColor3 = Color3.fromRGB(255, 112, 94)
	elseif shown < 0.25 then
		dangerStroke.Transparency = 0.58 + pulse * 0.22
		caption.Text = "FÔLEGO"
		caption.TextColor3 = Color3.fromRGB(255, 186, 96)
	else
		dangerStroke.Transparency = 1
		caption.Text = "FÔLEGO"
		caption.TextColor3 = Color3.fromRGB(235, 232, 220)
	end

	local visibleAlpha = if shown >= 0.995 and not holding then 0.24 else 0
	widget.GroupTransparency = visibleAlpha
end)
