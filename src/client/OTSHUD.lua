--!strict
-- Apresentação do HUD original do Digital's OTS, com contador de munição
-- integrado ao mesmo ScreenGui. Não cria uma segunda interface de arma.
local Debris = game:GetService("Debris")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local HUD = {}
HUD.__index = HUD

local WHITE = Color3.fromRGB(238, 242, 247)
local ACCENT = Color3.fromRGB(232, 180, 86)

local function textLabel(parent: Instance, name: string, text: string, size: number): TextLabel
	local label = Instance.new("TextLabel")
	label.Name = name
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamMedium
	label.Text = text
	label.TextColor3 = WHITE
	label.TextSize = size
	label.Parent = parent
	return label
end

local function playHudSound(name: string)
	local assets = ReplicatedStorage:FindFirstChild("WeaponAssets")
	local audios = assets and assets:FindFirstChild("Audios")
	local folder = audios and audios:FindFirstChild("HUD")
	local template = folder and folder:FindFirstChild(name)
	if not template or not template:IsA("Sound") then return end
	local sound = template:Clone()
	sound.Parent = game:GetService("SoundService")
	sound:Play()
	Debris:AddItem(sound, 5)
end

function HUD.new(playerGui: PlayerGui)
	local gui = playerGui:WaitForChild("Weapon", 10)
	assert(gui and gui:IsA("ScreenGui"), "StarterGui/Weapon do Digital's OTS não foi carregado")
	local self = setmetatable({}, HUD)
	self.Gui = gui
	self.Crosshair = gui:WaitForChild("Crosshair") :: Frame
	self.Content = gui:WaitForChild("Content") :: Folder
	self.FeedContainer = gui:WaitForChild("Feed") :: Frame
	self.Aiming = false

	local ammoPanel = gui:FindFirstChild("Ammo")
	if not ammoPanel then
		ammoPanel = Instance.new("Frame")
		ammoPanel.Name = "Ammo"
		ammoPanel.AnchorPoint = Vector2.new(1, 1)
		ammoPanel.Position = UDim2.new(0.5, -24, 1, -28)
		ammoPanel.Size = UDim2.fromOffset(206, 78)
		ammoPanel.BackgroundColor3 = Color3.fromRGB(12, 16, 21)
		ammoPanel.BackgroundTransparency = 0.18
		ammoPanel.BorderSizePixel = 0
		ammoPanel.Parent = gui
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0, 7)
		corner.Parent = ammoPanel
		local stroke = Instance.new("UIStroke")
		stroke.Color = ACCENT
		stroke.Transparency = 0.62
		stroke.Parent = ammoPanel
	end
	self.AmmoText = ammoPanel:FindFirstChild("Count") :: TextLabel?
	if not self.AmmoText then
		self.AmmoText = textLabel(ammoPanel, "Count", "17 / 00", 30)
		self.AmmoText.Font = Enum.Font.GothamBold
		self.AmmoText.Position = UDim2.fromOffset(12, 7)
		self.AmmoText.Size = UDim2.new(1, -24, 0, 36)
		self.AmmoText.TextXAlignment = Enum.TextXAlignment.Left
	end
	self.Status = ammoPanel:FindFirstChild("Status") :: TextLabel?
	if not self.Status then
		self.Status = textLabel(ammoPanel, "Status", "GLOCK 17 • SEMIAUTOMÁTICA", 10)
		self.Status.Position = UDim2.fromOffset(13, 47)
		self.Status.Size = UDim2.new(1, -24, 0, 18)
		self.Status.TextColor3 = ACCENT
		self.Status.TextXAlignment = Enum.TextXAlignment.Left
	end

	local touch = gui:FindFirstChild("TouchControls")
	if not touch then
		touch = Instance.new("Frame")
		touch.Name = "TouchControls"
		touch.BackgroundTransparency = 1
		touch.AnchorPoint = Vector2.new(1, 0.5)
		touch.Position = UDim2.new(1, -18, 0.5, 0)
		touch.Size = UDim2.fromOffset(112, 150)
		touch.Parent = gui
	end
	self.Buttons = {}
	for index, entry in ipairs({ { "Fire", "ATIRAR" }, { "Aim", "MIRAR" }, { "Reload", "RECARREGAR" } }) do
		local name, caption = entry[1], entry[2]
		local button = touch:FindFirstChild(name) :: TextButton?
		if not button then
			button = Instance.new("TextButton")
			button.Name = name
			button.Text = caption
			button.Font = Enum.Font.GothamBold
			button.TextColor3 = WHITE
			button.TextSize = 11
			button.BackgroundColor3 = Color3.fromRGB(18, 23, 29)
			button.BackgroundTransparency = 0.15
			button.BorderSizePixel = 0
			button.Position = UDim2.fromOffset(0, (index - 1) * 50)
			button.Size = UDim2.fromOffset(112, 43)
			button.Parent = touch
			local corner = Instance.new("UICorner")
			corner.CornerRadius = UDim.new(0, 7)
			corner.Parent = button
		end
		self.Buttons[name] = button
	end
	gui.Enabled = false
	return self
end

function HUD:SetEnabled(enabled: boolean)
	self.Gui.Enabled = enabled
	if not enabled then self:SetAiming(false) end
end

local function crosshairPosition(name: string, gap: number): UDim2
	if name == "Top" then return UDim2.new(0.5, 0, 0.5, -gap) end
	if name == "Bottom" then return UDim2.new(0.5, 0, 0.5, gap) end
	if name == "Left" then return UDim2.new(0.5, -gap, 0.5, 0) end
	return UDim2.new(0.5, gap, 0.5, 0)
end

function HUD:SetAiming(aiming: boolean)
	self.Aiming = aiming
	for _, child in self.Crosshair:GetChildren() do
		if child:IsA("ImageLabel") then
			local target = if child.Name == "Center" then (if aiming then 0.15 else 1) else (if aiming then 0.3 else 1)
			TweenService:Create(child, TweenInfo.new(0.18), { ImageTransparency = target }):Play()
		end
	end
end

function HUD:Shove(amount: number)
	for _, child in self.Crosshair:GetChildren() do
		if child:IsA("ImageLabel") and child.Name ~= "Center" then
			child.Position = crosshairPosition(child.Name, 15 + amount)
			TweenService:Create(child, TweenInfo.new(0.18, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), {
				Position = crosshairPosition(child.Name, 15),
			}):Play()
		end
	end
end

function HUD:Update(magazine: number, reserve: number, reloading: boolean, touchEnabled: boolean, blocked: boolean)
	self.AmmoText.Text = string.format("%02d / %02d", magazine, reserve)
	self.AmmoText.TextColor3 = if magazine <= 0 then Color3.fromRGB(242, 102, 91) else WHITE
	self.Status.Text = if reloading then "RECARREGANDO..." elseif magazine <= 0 then
		(if reserve > 0 then "PRESSIONE R PARA RECARREGAR" else "SEM MUNIÇÃO RESERVA")
		else "GLOCK 17 • SEMIAUTOMÁTICA"
	local controls = self.Gui:FindFirstChild("TouchControls")
	if controls and controls:IsA("GuiObject") then controls.Visible = touchEnabled and not blocked end
	self.Crosshair.Visible = not blocked
end

function HUD:Hitmarker(kind: string)
	local templateName = if kind == "Head" then "HeadHitmarker" elseif kind == "HeadArmor" then "HeadArmorHitmarker"
		elseif kind == "Armor" then "ArmorHitmarker" else "Hitmarker"
	local template = self.Content:FindFirstChild(templateName)
	if not template or not template:IsA("GuiObject") then return end
	local marker = template:Clone()
	marker.Visible = true
	marker.Parent = self.Gui
	marker.Size = UDim2.fromOffset(0, 0)
	TweenService:Create(marker, TweenInfo.new(0.1), { Size = UDim2.fromOffset(25, 25) }):Play()
	task.delay(0.18, function()
		TweenService:Create(marker, TweenInfo.new(0.1), { Size = UDim2.fromOffset(0, 0) }):Play()
		Debris:AddItem(marker, 0.12)
	end)
	playHudSound(if kind == "Armor" or kind == "HeadArmor" then "ArmorHitmarker" else "Hitmarker")
end

function HUD:Feed(kind: string, victimName: string)
	local template = self.Content:FindFirstChild(if kind == "Armor" then "Armour" else "Kill")
	if not template or not template:IsA("GuiObject") then return end
	local card = template:Clone()
	card.Visible = true
	card.Parent = self.FeedContainer
	local texts = card:FindFirstChild("Texts")
	local information = texts and texts:FindFirstChild("Information")
	local notification = information and information:FindFirstChild("Notf")
	local playerName = information and information:FindFirstChild("Plr")
	if notification and notification:IsA("TextLabel") then notification.Text = if kind == "Armor" then "ARMOUR" else "KILLED" end
	if playerName and playerName:IsA("TextLabel") then playerName.Text = victimName end
	playHudSound(if kind == "Armor" then "ArmourBreakSound" else "KillSound")
	task.delay(4.5, function()
		for _, descendant in card:GetDescendants() do
			if descendant:IsA("ImageLabel") then
				TweenService:Create(descendant, TweenInfo.new(0.35), { ImageTransparency = 1 }):Play()
			elseif descendant:IsA("TextLabel") then
				TweenService:Create(descendant, TweenInfo.new(0.35), { TextTransparency = 1 }):Play()
			end
		end
		Debris:AddItem(card, 0.4)
	end)
end

return HUD
