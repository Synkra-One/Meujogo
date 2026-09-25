--!strict
--[[
	ExtractionController
	Opções enquanto está a bordo do helicóptero do resgate:

		[ PARTIR AGORA ]   decola já, com quem estiver a bordo
		[ ESPERAR ]        segura o voo pelos colegas
		[ SAIR ]           volta ao solo e restaura corpo/câmera

	Toda a UI é feita em código (mesmo caminho de RoleRevealController), então
	não precisa de nada no StarterGui.

	Contrato do remote (ReplicatedStorage/Modules/Remotes.lua):
		Server -> Client: "Embarcar" | "Desembarcar" | "Partindo" | "Esperando"
		Client -> Server: "Partir" | "Esperar" | "Sair"

	Quem manda no estado é o servidor: aqui só desenho e repasso o clique.
	A câmera acompanha o helicóptero até a saída ou o fim da rodada.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Remotes = require(ReplicatedStorage.Modules.Remotes)
local Camera = require(script.Parent.ExtractionCamera)

local LocalPlayer = Players.LocalPlayer
local playerGui = LocalPlayer:WaitForChild("PlayerGui")
local aboard, departing = false, false

local FADE = TweenInfo.new(0.22, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

local screen = Instance.new("ScreenGui")
screen.Name = "ExtracaoHUD"
screen.ResetOnSpawn = false
screen.IgnoreGuiInset = false
screen.DisplayOrder = 15
screen.Enabled = false
screen.Parent = playerGui

local panel = Instance.new("Frame")
panel.AnchorPoint = Vector2.new(0.5, 1)
panel.Size = UDim2.new(0.92, 0, 0, 150)
panel.Position = UDim2.new(0.5, 0, 1, -36)
panel.BackgroundColor3 = Color3.fromRGB(14, 16, 20)
panel.BackgroundTransparency = 0.12
panel.BorderSizePixel = 0
panel.Parent = screen
local limit = Instance.new("UISizeConstraint")
limit.MaxSize = Vector2.new(560, 150)
limit.Parent = panel

local panelCorner = Instance.new("UICorner")
panelCorner.CornerRadius = UDim.new(0, 10)
panelCorner.Parent = panel

local panelStroke = Instance.new("UIStroke")
panelStroke.Color = Color3.fromRGB(255, 120, 100)
panelStroke.Thickness = 2
panelStroke.Parent = panel

local title = Instance.new("TextLabel")
title.Size = UDim2.new(1, -24, 0, 30)
title.Position = UDim2.fromOffset(12, 10)
title.BackgroundTransparency = 1
title.Font = Enum.Font.GothamBold
title.Text = "VOCÊ ESTÁ A BORDO"
title.TextColor3 = Color3.fromRGB(245, 245, 240)
title.TextSize = 19
title.TextWrapped = true
title.Parent = panel

local hint = Instance.new("TextLabel")
hint.Size = UDim2.new(1, -24, 0, 30)
hint.Position = UDim2.fromOffset(12, 39)
hint.BackgroundTransparency = 1
hint.Font = Enum.Font.Gotham
hint.Text = "Partir deixa quem ficou pra trás."
hint.TextColor3 = Color3.fromRGB(170, 172, 178)
hint.TextSize = 13
hint.TextWrapped = true
hint.Parent = panel

local function makeButton(text: string, color: Color3, index: number): TextButton
	local button = Instance.new("TextButton")
	button.Size = UDim2.new(1 / 3, -12, 0, 56)
	button.Position = UDim2.new((index - 1) / 3, 8, 0, 82)
	button.BackgroundColor3 = color
	button.BackgroundTransparency = 0.1
	button.BorderSizePixel = 0
	button.AutoButtonColor = true
	button.Font = Enum.Font.GothamBold
	button.Text = text
	button.TextColor3 = Color3.fromRGB(16, 16, 18)
	button.TextSize = 15
	button.TextWrapped = true
	button.Selectable = true
	button.Parent = panel

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 8)
	corner.Parent = button

	return button
end

local goButton = makeButton("PARTIR\nAGORA", Color3.fromRGB(120, 225, 140), 1)
local waitButton = makeButton("ESPERAR", Color3.fromRGB(238, 206, 120), 2)
local exitButton = makeButton("SAIR DO\nHELICÓPTERO", Color3.fromRGB(208, 216, 226), 3)

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
	if aboard and not departing then Remotes.ExtractionChoice:FireServer("Partir") end
end)

waitButton.Activated:Connect(function()
	if aboard and not departing then Remotes.ExtractionChoice:FireServer("Esperar") end
end)
exitButton.Activated:Connect(function()
	if aboard and not departing then Remotes.ExtractionChoice:FireServer("Sair") end
end)

local function close()
	aboard, departing = false, false
	setOpen(false)
	Camera.Stop()
end

Remotes.ExtractionChoice.OnClientEvent:Connect(function(action: string, model: Model?)
	if action == "Embarcar" then
		aboard, departing = true, false
		title.Text = "VOCÊ ESTÁ A BORDO"
		hint.Text = "Partir deixa quem ficou para trás. Você pode esperar ou sair."
		goButton.Visible, waitButton.Visible, exitButton.Visible = true, true, true
		setOpen(true)
		Camera.Start(model)
	elseif action == "Esperando" and aboard then
		hint.Text = "Aguardando os outros. Você pode partir ou sair quando quiser."
	elseif action == "Partindo" and aboard then
		departing = true
		title.Text = "RESGATE EM VOO"
		hint.Text = "O helicóptero está deixando a ilha."
		goButton.Visible, waitButton.Visible, exitButton.Visible = false, false, false
	elseif action == "Desembarcar" then
		close()
	end
end)

-- Rodada nova / morte: nunca deixa o painel preso na tela.
Remotes.RoundEnded.OnClientEvent:Connect(close)
LocalPlayer.CharacterRemoving:Connect(close)
LocalPlayer:GetAttributeChangedSignal("ExtractionBoarded"):Connect(function()
	if LocalPlayer:GetAttribute("ExtractionBoarded") == true then Camera.Start(nil) else close() end
end)
