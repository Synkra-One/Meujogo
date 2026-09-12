--!strict
--[[
	ExtractionController
	As DUAS opções que aparecem quando você embarca no helicóptero do resgate:

		[ PARTIR AGORA ]   decola já, com quem estiver a bordo
		[ ESPERAR ]        segura o voo pelos colegas

	Toda a UI é feita em código (mesmo caminho de RoleRevealController), então
	não precisa de nada no StarterGui.

	Contrato do remote (ReplicatedStorage/Modules/Remotes.lua):
		Server -> Client: "Abrir" | "Fechar"
		Client -> Server: "Partir" | "Esperar"

	Quem manda no estado é o servidor: aqui só desenho e repasso o clique.
	Desembarcar NÃO é feito por esta tela -- é o ProximityPrompt "Sair" no
	próprio helicóptero, que foi o pedido ("interagir para sair").
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Remotes = require(ReplicatedStorage.Modules.Remotes)

local LocalPlayer = Players.LocalPlayer
local playerGui = LocalPlayer:WaitForChild("PlayerGui")

local FADE = TweenInfo.new(0.22, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

local screen = Instance.new("ScreenGui")
screen.Name = "ExtracaoHUD"
screen.ResetOnSpawn = false
screen.IgnoreGuiInset = false
screen.DisplayOrder = 8
screen.Enabled = false
screen.Parent = playerGui

local panel = Instance.new("Frame")
panel.Size = UDim2.fromOffset(420, 148)
panel.Position = UDim2.new(0.5, -210, 1, -220)
panel.BackgroundColor3 = Color3.fromRGB(14, 16, 20)
panel.BackgroundTransparency = 0.12
panel.BorderSizePixel = 0
panel.Parent = screen

local panelCorner = Instance.new("UICorner")
panelCorner.CornerRadius = UDim.new(0, 10)
panelCorner.Parent = panel

local panelStroke = Instance.new("UIStroke")
panelStroke.Color = Color3.fromRGB(255, 120, 100)
panelStroke.Thickness = 2
panelStroke.Parent = panel

local title = Instance.new("TextLabel")
title.Size = UDim2.new(1, -24, 0, 46)
title.Position = UDim2.fromOffset(12, 10)
title.BackgroundTransparency = 1
title.Font = Enum.Font.GothamBold
title.Text = "VOCÊ ESTÁ A BORDO"
title.TextColor3 = Color3.fromRGB(245, 245, 240)
title.TextSize = 20
title.TextWrapped = true
title.Parent = panel

local hint = Instance.new("TextLabel")
hint.Size = UDim2.new(1, -24, 0, 18)
hint.Position = UDim2.fromOffset(12, 44)
hint.BackgroundTransparency = 1
hint.Font = Enum.Font.Gotham
hint.Text = "Partir deixa quem ficou pra trás."
hint.TextColor3 = Color3.fromRGB(170, 172, 178)
hint.TextSize = 13
hint.Parent = panel

local function makeButton(text: string, sub: string, color: Color3, xScale: number): TextButton
	local button = Instance.new("TextButton")
	button.Size = UDim2.new(0.5, -18, 0, 58)
	button.Position = UDim2.new(xScale, if xScale == 0 then 12 else 6, 0, 76)
	button.BackgroundColor3 = color
	button.BackgroundTransparency = 0.1
	button.BorderSizePixel = 0
	button.AutoButtonColor = true
	button.Font = Enum.Font.GothamBold
	button.Text = text
	button.TextColor3 = Color3.fromRGB(16, 16, 18)
	button.TextSize = 17
	button.Parent = panel

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 8)
	corner.Parent = button

	local caption = Instance.new("TextLabel")
	caption.Size = UDim2.new(1, -12, 0, 16)
	caption.Position = UDim2.new(0, 6, 1, -20)
	caption.BackgroundTransparency = 1
	caption.Font = Enum.Font.Gotham
	caption.Text = sub
	caption.TextColor3 = Color3.fromRGB(30, 30, 34)
	caption.TextSize = 12
	caption.TextWrapped = true
	caption.Parent = button

	return button
end

local goButton = makeButton("PARTIR AGORA", "decola imediatamente", Color3.fromRGB(120, 225, 140), 0)
local waitButton = makeButton("ESPERAR", "segura o voo pelos colegas", Color3.fromRGB(238, 206, 120), 0.5)

local function setOpen(open: boolean)
	if open then
		screen.Enabled = true
		panel.BackgroundTransparency = 1
		TweenService:Create(panel, FADE, { BackgroundTransparency = 0.12 }):Play()
	else
		screen.Enabled = false
	end
end

goButton.Activated:Connect(function()
	setOpen(false)
	Remotes.ExtractionChoice:FireServer("Partir")
end)

waitButton.Activated:Connect(function()
	setOpen(false)
	Remotes.ExtractionChoice:FireServer("Esperar")
end)

Remotes.ExtractionChoice.OnClientEvent:Connect(function(action: string)
	if action == "Abrir" then
		setOpen(true)
	elseif action == "Fechar" then
		setOpen(false)
	end
end)

-- Rodada nova / morte: nunca deixa o painel preso na tela.
Remotes.RoundEnded.OnClientEvent:Connect(function()
	setOpen(false)
end)
