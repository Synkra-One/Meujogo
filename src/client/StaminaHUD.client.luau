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
local GameConfig = require(ReplicatedStorage.Modules.GameConfig)
local FearRules = require(ReplicatedStorage.Modules.FearPresentationRules)
local DiscoveredItemsStore = require(script.Parent.DiscoveredItemsStore)
local SurvivalMinimapHUD = require(script.Parent.SurvivalMinimapHUD)
local StaminaRing = require(script.Parent.StaminaRing)

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

-- O anel é a ÚNICA leitura de fôlego na tela. Qualquer outra barra some --
-- inclusive as que ficaram salvas dentro do .rbxl (fora do Rojo), que é de
-- onde vinha a "barra debaixo" que não existia em lugar nenhum do código.
-- Casamos por nome em minúsculas pra pegar variações (StaminaBar, BarraFolego,
-- SprintGui...), protegendo explicitamente o nosso HUD.
local OWN_GUI_NAME = "SurvivalStatusHUD"
local LEGACY_GUI_PATTERNS = { "stamina", "folego", "fôlego", "sprint", "pixelhealth" }

local function isLegacyStatusGui(child: Instance): boolean
	if child.Name == OWN_GUI_NAME or not child:IsA("LayerCollector") then
		return false
	end
	local name = child.Name:lower()
	for _, pattern in LEGACY_GUI_PATTERNS do
		if name:find(pattern, 1, true) then
			return true
		end
	end
	return false
end

local function removeLegacyStatusGuis()
	for _, child in playerGui:GetChildren() do
		if isLegacyStatusGui(child) then
			warn("[StaminaHUD] removendo barra de fôlego legada: " .. child.Name)
			child:Destroy()
		end
	end
end

task.spawn(hideCoreHealth)
removeLegacyStatusGuis()
-- ChildAdded já cobre o que aparecer depois: varrer o PlayerGui todo frame
-- (como era antes) é trabalho repetido à toa 60x por segundo.
playerGui.ChildAdded:Connect(function(child: Instance)
	if isLegacyStatusGui(child) then
		warn("[StaminaHUD] removendo barra de fôlego legada: " .. child.Name)
		child:Destroy()
	end
end)

--------------------------------------------------------------------------------
-- Intenção de correr
--
-- O que vai pro servidor é o estado REAL de corrida do pacote de movimento
-- (Attribute local "IsSprinting" no HumanoidRootPart, escrito pelo script
-- Crouching). Esse Attribute nasce no cliente e não replica, então é daqui
-- que o servidor fica sabendo. Recalculado todo frame e enviado só quando
-- muda: nunca fica preso num valor antigo (ex.: Shift já apertado quando a
-- partida libera o movimento). Sem o pacote, cai pro Shift/botão apertado.
--------------------------------------------------------------------------------

local sprintKeyHeld = false -- input físico (fallback quando o pacote não publica)
local holding = false -- última intenção enviada ao servidor

local function setHolding(value: boolean)
	if value == holding then
		return
	end
	holding = value
	Remotes.SprintIntent:FireServer(value)
end

local function packSprinting(): boolean?
	local character = LocalPlayer.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local value = root and root:GetAttribute("IsSprinting")
	return if type(value) == "boolean" then value else nil
end

UserInputService.InputBegan:Connect(function(input: InputObject, _gameProcessed: boolean)
	-- Outros controles locais (câmera/PlayerModule) podem marcar Shift como
	-- processado antes deste listener; só um campo de texto bloqueia.
	if UserInputService:GetFocusedTextBox() then
		return
	end
	if input.KeyCode == Enum.KeyCode.LeftShift or input.KeyCode == Enum.KeyCode.RightShift then
		sprintKeyHeld = true
	end
end)

UserInputService.InputEnded:Connect(function(input: InputObject)
	if input.KeyCode == Enum.KeyCode.LeftShift or input.KeyCode == Enum.KeyCode.RightShift then
		sprintKeyHeld = false
	end
end)

ContextActionService:BindAction("SprintIntent", function(_, state: Enum.UserInputState)
	if state == Enum.UserInputState.Begin then
		sprintKeyHeld = true
	elseif state == Enum.UserInputState.End or state == Enum.UserInputState.Cancel then
		sprintKeyHeld = false
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

local function onCharacterAdded(character: Model)
	hookCharacter(character)
	-- Se a troca de corpo ocorreu com Shift já pressionado, InputBegan não
	-- dispara de novo; o frame seguinte reenvia a intenção sozinho.
	sprintKeyHeld = UserInputService:IsKeyDown(Enum.KeyCode.LeftShift)
		or UserInputService:IsKeyDown(Enum.KeyCode.RightShift)
end

if LocalPlayer.Character then
	task.defer(onCharacterAdded, LocalPlayer.Character)
end
LocalPlayer.CharacterAdded:Connect(onCharacterAdded)

RunService.RenderStepped:Connect(function(dt: number)
	if LocalPlayer:GetAttribute("GameplayEnabled") ~= true then
		if holding then setHolding(false) end
		gui.Enabled = false
		return
	end
	-- Enquanto a tela inicial (ReplicatedFirst/MenuBoot) estiver aberta, o
	-- HUD de partida não pode aparecer por baixo dela. gui.Enabled é
	-- reescrito nos dois sentidos aqui -- sem isto, fechar o menu deixaria
	-- o HUD escondido pra sempre (nada mais neste arquivo o reabilita).
	if LocalPlayer:GetAttribute("IntroMenuOpen") == true then
		gui.Enabled = false
		return
	end
	gui.Enabled = true
	local pack = packSprinting()
	setHolding(if pack ~= nil then pack else sprintKeyHeld)

	-- FONTE ÚNICA do fôlego: Attributes "Stamina" e "StaminaMax" no Player,
	-- escritos só pelo servidor (StaminaSystem.lua). Fraction limita a 0..1,
	-- trata teto 0 como vazio e devolve nil enquanto os Attributes não
	-- chegaram (o anel mantém o último valor). Ninguém divide de novo depois.
	local target = StaminaRing.Fraction(LocalPlayer:GetAttribute("Stamina"), LocalPlayer:GetAttribute("StaminaMax"))
	local exhausted = LocalPlayer:GetAttribute("StaminaExausto") == true

	local humanoid = currentHumanoid
	local health = if humanoid and humanoid.Parent
		then humanoid.Health / math.max(humanoid.MaxHealth, 1)
		else 1
	-- Pânico apaga o painel de mapa/fôlego. Fonte única: o Attribute "Fear"
	-- que o servidor replica -- nenhum cálculo de medo acontece aqui.
	local fearValue = LocalPlayer:GetAttribute("Fear")
	local fear = if type(fearValue) == "number" and fearValue == fearValue
		then math.clamp(fearValue, 0, GameConfig.Fear.MaxFear) else 0
	statusHud:Update(dt, health, target, exhausted, holding, FearRules.HudFade(fear, GameConfig.Fear).Vitals)

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
