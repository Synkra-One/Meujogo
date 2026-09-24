--!strict
--[[
	Tela de transição para a PARTIDA, não para o lobby.

	Abre quando WaitingRoomManager publica MatchState = "Loading", isto é:
	  - depois de o Sobrevivente confirmar o personagem; ou
	  - depois do sorteio, para o Monstro (Jason é automático).

	Fica por cima do respawn e do teleporte enquanto o servidor prepara os
	corpos. Só some depois de MatchState = "InMatch", do stream na posição
	exata do novo personagem e de alguns frames já renderizados.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ContentProvider = game:GetService("ContentProvider")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local IMAGE = "rbxassetid://118186163301819"
local STREAM_TIMEOUT = 5
local COMPLETE_HOLD = 0.2

local function setControlsEnabled(enabled: boolean)
	local ok, controls = pcall(function()
		local scripts = player:WaitForChild("PlayerScripts", 5)
		local playerModule = scripts and scripts:WaitForChild("PlayerModule", 5)
		return playerModule and require(playerModule :: ModuleScript):GetControls()
	end)
	if ok and controls then
		if enabled then (controls :: any):Enable() else (controls :: any):Disable() end
	end
end

local screen = Instance.new("ScreenGui")
screen.Name = "MatchLoadingHUD"
screen.ResetOnSpawn = false
screen.IgnoreGuiInset = true
screen.DisplayOrder = 950
screen.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
screen.Enabled = false
screen.Parent = playerGui

local root = Instance.new("CanvasGroup")
root.Name = "Root"
root.Size = UDim2.fromScale(1, 1)
root.BackgroundColor3 = Color3.fromRGB(4, 5, 7)
root.BackgroundTransparency = 0
root.BorderSizePixel = 0
root.GroupTransparency = 0
root.Active = true
root.Parent = screen

local artwork = Instance.new("ImageLabel")
artwork.Name = "Artwork"
artwork.Size = UDim2.fromScale(1, 1)
artwork.BackgroundTransparency = 1
artwork.BorderSizePixel = 0
artwork.Image = IMAGE
artwork.ImageTransparency = 0
artwork.ScaleType = Enum.ScaleType.Crop
artwork.ZIndex = 1
artwork.Parent = root

-- Só escurece a faixa inferior. A arte continua realmente visível.
local footerShade = Instance.new("Frame")
footerShade.Name = "FooterShade"
footerShade.AnchorPoint = Vector2.new(0, 1)
footerShade.Position = UDim2.fromScale(0, 1)
footerShade.Size = UDim2.fromScale(1, 0.34)
footerShade.BackgroundColor3 = Color3.fromRGB(3, 4, 6)
footerShade.BackgroundTransparency = 0.16
footerShade.BorderSizePixel = 0
footerShade.ZIndex = 2
footerShade.Parent = root
local footerGradient = Instance.new("UIGradient")
footerGradient.Rotation = 90
footerGradient.Transparency = NumberSequence.new({
	NumberSequenceKeypoint.new(0, 1),
	NumberSequenceKeypoint.new(0.38, 0.45),
	NumberSequenceKeypoint.new(1, 0),
})
footerGradient.Parent = footerShade

local title = Instance.new("TextLabel")
title.Name = "Title"
title.AnchorPoint = Vector2.new(0.5, 0.5)
title.Position = UDim2.fromScale(0.5, 0.78)
title.Size = UDim2.new(0.82, 0, 0, 42)
title.BackgroundTransparency = 1
title.Font = Enum.Font.GothamBlack
title.Text = "ENTRANDO NA PARTIDA"
title.TextColor3 = Color3.fromRGB(245, 245, 248)
title.TextSize = 26
title.TextXAlignment = Enum.TextXAlignment.Center
title.ZIndex = 3
title.Parent = root

local status = Instance.new("TextLabel")
status.Name = "Status"
status.AnchorPoint = Vector2.new(0.5, 0.5)
status.Position = UDim2.fromScale(0.5, 0.83)
status.Size = UDim2.new(0.82, 0, 0, 24)
status.BackgroundTransparency = 1
status.Font = Enum.Font.GothamMedium
status.Text = "PREPARANDO A ILHA"
status.TextColor3 = Color3.fromRGB(215, 215, 222)
status.TextSize = 13
status.TextXAlignment = Enum.TextXAlignment.Center
status.ZIndex = 3
status.Parent = root

local track = Instance.new("Frame")
track.Name = "Track"
track.AnchorPoint = Vector2.new(0.5, 0.5)
track.Position = UDim2.fromScale(0.5, 0.875)
track.Size = UDim2.new(0.42, 0, 0, 8)
track.BackgroundColor3 = Color3.fromRGB(46, 47, 54)
track.BackgroundTransparency = 0.15
track.BorderSizePixel = 0
track.ZIndex = 3
track.ClipsDescendants = true
track.Parent = root
local trackCorner = Instance.new("UICorner")
trackCorner.CornerRadius = UDim.new(0, 8)
trackCorner.Parent = track

local fill = Instance.new("Frame")
fill.Name = "Fill"
fill.Size = UDim2.fromScale(0, 1)
fill.BackgroundColor3 = Color3.fromRGB(205, 48, 40)
fill.BorderSizePixel = 0
fill.ZIndex = 4
fill.Parent = track
local fillCorner = Instance.new("UICorner")
fillCorner.CornerRadius = UDim.new(0, 8)
fillCorner.Parent = fill
local fillGradient = Instance.new("UIGradient")
fillGradient.Color = ColorSequence.new({
	ColorSequenceKeypoint.new(0, Color3.fromRGB(115, 20, 24)),
	ColorSequenceKeypoint.new(0.7, Color3.fromRGB(218, 45, 38)),
	ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 205, 175)),
})
fillGradient.Parent = fill

local percent = Instance.new("TextLabel")
percent.Name = "Percent"
percent.AnchorPoint = Vector2.new(0.5, 0)
percent.Position = UDim2.fromScale(0.5, 0.89)
percent.Size = UDim2.new(0.2, 0, 0, 24)
percent.BackgroundTransparency = 1
percent.Font = Enum.Font.GothamBold
percent.Text = "0%"
percent.TextColor3 = Color3.fromRGB(235, 92, 76)
percent.TextSize = 12
percent.TextXAlignment = Enum.TextXAlignment.Center
percent.ZIndex = 3
percent.Parent = root

-- Carrega a imagem ainda no lobby para ela já estar pronta quando Starting
-- chegar. O pcall cobre asset privado/indisponível sem travar a partida.
task.spawn(function()
	pcall(function() ContentProvider:PreloadAsync({ artwork }) end)
end)

local active = false
local finishing = false
local generation = 0
local shownAt = 0
local progress = 0
local nextProgressUpdate = 0
local characterBeforeStart: Model? = nil

local function setProgress(value: number, message: string?)
	progress = math.max(progress, math.clamp(value, 0, 1))
	TweenService:Create(fill, TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Size = UDim2.fromScale(progress, 1),
	}):Play()
	percent.Text = string.format("%d%%", math.floor(progress * 100 + 0.5))
	if message then status.Text = message end
end

local function show()
	if active then return end
	active = true
	finishing = false
	generation += 1
	shownAt = os.clock()
	nextProgressUpdate = 0
	characterBeforeStart = player.Character
	progress = 0
	root.GroupTransparency = 0
	fill.Size = UDim2.fromScale(0, 1)
	status.Text = "PREPARANDO SEU PERSONAGEM"
	percent.Text = "0%"
	screen.Enabled = true
	player:SetAttribute("MatchLoadingOpen", true)
	setControlsEnabled(false)
	setProgress(0.08)
end

local function closeImmediately()
	if not active then return end
	generation += 1
	active = false
	finishing = false
	characterBeforeStart = nil
	screen.Enabled = false
	root.GroupTransparency = 0
	player:SetAttribute("MatchLoadingOpen", nil)
	if ReplicatedStorage:GetAttribute("MatchState") == "InMatch"
		and player:GetAttribute("GameplayEnabled") == true then
		setControlsEnabled(true)
	end
end

local function finish()
	if not active or finishing then return end
	finishing = true
	local myGeneration = generation
	task.spawn(function()
		setProgress(0.86, "RENDERIZANDO O MAPA")
		-- MatchState e Player.Character chegam por canais de replicação
		-- diferentes. Aguarde o corpo novo da partida para não pedir streaming
		-- em volta do avatar antigo que ainda estava no lobby.
		local character: Model? = nil
		local characterDeadline = os.clock() + STREAM_TIMEOUT
		while os.clock() < characterDeadline do
			local current = player.Character
			if current and player:GetAttribute("InRound") == true and current ~= characterBeforeStart then
				character = current
				break
			end
			task.wait(0.05)
		end
		character = character or player.Character
		local rootPart = character and character:FindFirstChild("HumanoidRootPart")
		if not rootPart and character then rootPart = character:WaitForChild("HumanoidRootPart", STREAM_TIMEOUT) end
		if myGeneration ~= generation then return end
		if rootPart and rootPart:IsA("BasePart") then
			pcall(function()
				player:RequestStreamAroundAsync(rootPart.Position, STREAM_TIMEOUT)
			end)
		end
		if myGeneration ~= generation then return end
		RunService.RenderStepped:Wait()
		RunService.RenderStepped:Wait()
		RunService.RenderStepped:Wait()
		setProgress(1, "MAPA PRONTO")
		task.wait(COMPLETE_HOLD)
		if myGeneration ~= generation then return end
		local tween = TweenService:Create(root, TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			GroupTransparency = 1,
		})
		tween:Play()
		tween.Completed:Wait()
		if myGeneration ~= generation then return end
		active = false
		finishing = false
		characterBeforeStart = nil
		screen.Enabled = false
		root.GroupTransparency = 0
		player:SetAttribute("MatchLoadingOpen", nil)
		if ReplicatedStorage:GetAttribute("MatchState") == "InMatch"
			and player:GetAttribute("GameplayEnabled") == true then
			setControlsEnabled(true)
		end
	end)
end

local function onMatchStateChanged()
	local state = ReplicatedStorage:GetAttribute("MatchState")
	if state == "Loading" then
		show()
	elseif state == "InMatch" then
		finish()
	elseif active then
		-- Falha de preparação / retorno ao lobby não pode deixar um véu preso.
		closeImmediately()
	end
end

player.CharacterAdded:Connect(function()
	if active then task.defer(setControlsEnabled, false) end
end)

RunService.Heartbeat:Connect(function()
	if not active or finishing then return end
	local now = os.clock()
	if now < nextProgressUpdate then return end
	nextProgressUpdate = now + 0.1
	local elapsed = now - shownAt
	setProgress(math.min(0.8, 0.08 + elapsed * 0.075), "CARREGANDO A PARTIDA")
end)

ReplicatedStorage:GetAttributeChangedSignal("MatchState"):Connect(onMatchStateChanged)
onMatchStateChanged()

script.Destroying:Connect(function()
	player:SetAttribute("MatchLoadingOpen", nil)
	if ReplicatedStorage:GetAttribute("MatchState") == "InMatch"
		and player:GetAttribute("GameplayEnabled") == true then
		setControlsEnabled(true)
	end
end)
