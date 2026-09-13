--!strict
--[[
	SurvivalStatusHUD

	Mantém a parte autoritativa do sprint (envia intenção para o servidor),
	mas troca as barras antigas por um HUD circular com minimapa, vida e folego.
	Os itens descobertos usam a mesma fonte de dados do mapa grande (tecla M).
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
local DiscoveredItemsStore = require(script.Parent.DiscoveredItemsStore)
local SurvivalMinimapHUD = require(script.Parent.SurvivalMinimapHUD)

local LocalPlayer = Players.LocalPlayer
local playerGui = LocalPlayer:WaitForChild("PlayerGui")

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

local LEGACY_GUI_NAMES = {
	PixelHealthGui = true,
	PixelStaminaGui = true,
	StaminaGui = true,
	SprintGui = true,
}

local function removeLegacyStatusGuis()
	for _, child in playerGui:GetChildren() do
		if LEGACY_GUI_NAMES[child.Name] then
			child:Destroy()
		end
	end
end

task.spawn(hideCoreHealth)
removeLegacyStatusGuis()
playerGui.ChildAdded:Connect(function(child: Instance)
	if LEGACY_GUI_NAMES[child.Name] then
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
-- HUD circular: vida, folego e minimapa
--------------------------------------------------------------------------------

local gui = Instance.new("ScreenGui")
gui.Name = "SurvivalStatusHUD"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.DisplayOrder = 20
gui.Parent = playerGui

local statusHud = SurvivalMinimapHUD.new(gui)
statusHud:SetDiscoveredItems(DiscoveredItemsStore.GetAll() :: any)
DiscoveredItemsStore.Changed:Connect(function(entry)
	statusHud:AddDiscoveredItem(entry :: any)
end)

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

local healthConnection: RBXScriptConnection? = nil
local currentHumanoid: Humanoid? = nil
local currentCharacter: Model? = nil

local function hookCharacter(character: Model)
	currentCharacter = character

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
	currentHumanoid = humanoid

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
	removeLegacyStatusGuis()

	local raw = LocalPlayer:GetAttribute("Stamina")
	local target = math.clamp((if type(raw) == "number" then raw else 100) / 100, 0, 1)
	local exhausted = LocalPlayer:GetAttribute("StaminaExausto") == true

	local humanoid = currentHumanoid
	local health = if humanoid and humanoid.Parent
		then humanoid.Health / math.max(humanoid.MaxHealth, 1)
		else 1
	statusHud:Update(dt, health, target, exhausted, holding)

	local character = currentCharacter
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		local look = root.CFrame.LookVector
		local heading = math.deg(math.atan2(look.X, -look.Z))
		statusHud:UpdatePlayer(root.Position, heading)
	else
		statusHud:UpdatePlayer(nil, nil)
	end
end)
