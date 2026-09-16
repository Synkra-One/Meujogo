--!strict
-- Apresentação local da super audição. Projeta uma posição FIXA do mundo em
-- ScreenGui: atravessa paredes/árvores/pedras, sem seguir o sobrevivente.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local GameConfig = require(ReplicatedStorage.Modules.GameConfig)
local Remotes = require(ReplicatedStorage.Modules.Remotes)
local CFG = GameConfig.Noise.Visual
local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui") :: PlayerGui

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "NoiseVisualizer"
screenGui.DisplayOrder = CFG.DisplayOrder
screenGui.IgnoreGuiInset = true
screenGui.ResetOnSpawn = false
screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
screenGui.Parent = playerGui

type Ping = {
	position: Vector3,
	intensity: number,
	visuals: { Frame },
	destroyed: boolean,
}

local pings: { Ping } = {}
local characterConnections: { RBXScriptConnection } = {}
local projectionConnection: RBXScriptConnection? = nil
local roundEnded = false
local roleWasReady = false
local firstPingLogged = false

-- Só o Monstro ouve. A exceção é o eco de teste solo do Studio, que o
-- servidor já decidiu mandar (GameConfig.Noise.Debug.SelfHear): aqui o papel
-- de Sobrevivente só é aceito sob a MESMA condição, nunca em jogo publicado.
local function allowedRole(): boolean
	local role = player:GetAttribute("Role")
	if role == GameConfig.Roles.Monster then return true end
	return GameConfig.Noise.Debug.SelfHear == true and RunService:IsStudio()
		and role == GameConfig.Roles.Survivor
end

local function eligible(): boolean
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	return GameConfig.Noise.Enabled and not roundEnded and player:GetAttribute("InRound") == true
		and allowedRole() and player:GetAttribute("Eliminado") ~= true
		and character ~= nil and character:GetAttribute("Eliminado") ~= true
		and humanoid ~= nil and humanoid.Health > 0
end

local function updateProjection()
	local camera = Workspace.CurrentCamera
	if not camera then
		for _, ping in pings do
			for _, visual in ping.visuals do visual.Visible = false end
		end
		return
	end
	-- O booleano de WorldToViewportPoint vira false assim que o PONTO sai da
	-- tela, o que apagava a onda inteira de uma vez enquanto metade dela ainda
	-- estaria visível. A margem resolve isso sem virar seta de borda: passou
	-- dela, some mesmo.
	local viewport = camera.ViewportSize
	local margin = CFG.EdgeMarginPixels
	local allowed = eligible()
	for _, ping in pings do
		local point = camera:WorldToViewportPoint(ping.position)
		local visible = allowed and point.Z > 0
			and point.X >= -margin and point.X <= viewport.X + margin
			and point.Y >= -margin and point.Y <= viewport.Y + margin
		for _, visual in ping.visuals do
			visual.Visible = visible
			if visible then visual.Position = UDim2.fromOffset(point.X, point.Y) end
		end
	end
end

local function stopProjectionIfIdle()
	if #pings == 0 and projectionConnection then
		projectionConnection:Disconnect()
		projectionConnection = nil
	end
end

local function removePing(ping: Ping)
	if ping.destroyed then return end
	ping.destroyed = true
	local index = table.find(pings, ping)
	if index then table.remove(pings, index) end
	for _, visual in ping.visuals do visual:Destroy() end
	table.clear(ping.visuals)
	stopProjectionIfIdle()
end

local function clear()
	local copy = table.clone(pings)
	for _, ping in copy do removePing(ping) end
end

local function startProjection()
	if projectionConnection then return end
	projectionConnection = RunService.RenderStepped:Connect(updateProjection)
	updateProjection()
end

-- Um anel: moldura arredondada sem preenchimento. Devolve o UIStroke porque
-- é ele que some no tween.
local function makeRing(parent: Frame, zIndex: number, color: { number },
	thickness: number, transparency: number): UIStroke
	local frame = Instance.new("Frame")
	frame.Name = "Ring"
	frame.Size = UDim2.fromScale(1, 1)
	frame.BackgroundTransparency = 1
	frame.BorderSizePixel = 0
	frame.ZIndex = zIndex
	frame.Parent = parent

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.5, 0)
	corner.Parent = frame

	local stroke = Instance.new("UIStroke")
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Color = Color3.fromRGB(color[1], color[2], color[3])
	stroke.Thickness = thickness
	stroke.Transparency = math.clamp(transparency, 0, 1)
	stroke.Parent = frame
	return stroke
end

local function makeWave(ping: Ping, initialTransparency: number)
	if ping.destroyed or not eligible() then return end
	-- O contêiner é o único que a projeção posiciona, e o UIScale dele cresce
	-- as três camadas juntas.
	local wave = Instance.new("Frame")
	wave.Name = "SoundWave"
	wave.AnchorPoint = Vector2.new(0.5, 0.5)
	local pixels = CFG.BaseSizePixels * math.clamp(0.85 + ping.intensity * 0.05, 0.9, 1.2)
	wave.Size = UDim2.fromOffset(pixels, pixels)
	wave.BackgroundTransparency = 1
	wave.BorderSizePixel = 0
	wave.ZIndex = CFG.ZIndex
	wave.Visible = false
	wave.Parent = screenGui

	local scale = Instance.new("UIScale")
	scale.Scale = CFG.StartScale
	scale.Parent = wave

	local halo = Instance.new("Frame")
	halo.Name = "Halo"
	halo.Size = UDim2.fromScale(1, 1)
	halo.BackgroundColor3 = Color3.fromRGB(CFG.Color[1], CFG.Color[2], CFG.Color[3])
	halo.BackgroundTransparency = math.clamp(CFG.HaloTransparency + initialTransparency * 0.1, 0, 1)
	halo.BorderSizePixel = 0
	halo.ZIndex = CFG.ZIndex
	halo.Parent = wave

	local haloCorner = Instance.new("UICorner")
	haloCorner.CornerRadius = UDim.new(0.5, 0)
	haloCorner.Parent = halo

	-- Contorno escuro ATRÁS do claro: um anel fino quase branco desaparece em
	-- céu, areia e névoa. Com a sombra ele lê em qualquer cenário.
	local shadow = makeRing(wave, CFG.ZIndex + 1, CFG.ShadowColor,
		CFG.StrokeThickness + CFG.ShadowThickness, CFG.ShadowTransparency + initialTransparency)
	local core = makeRing(wave, CFG.ZIndex + 2, CFG.Color, CFG.StrokeThickness, initialTransparency)

	table.insert(ping.visuals, wave)
	updateProjection()

	local grow = TweenInfo.new(CFG.Duration, Enum.EasingStyle.Quart, Enum.EasingDirection.Out)
	local fade = TweenInfo.new(CFG.Duration, Enum.EasingStyle.Sine, Enum.EasingDirection.In)
	TweenService:Create(scale, grow, { Scale = CFG.EndScale }):Play()
	TweenService:Create(halo, fade, { BackgroundTransparency = 1 }):Play()
	TweenService:Create(shadow, fade, { Transparency = 1 }):Play()
	TweenService:Create(core, fade, { Transparency = 1 }):Play()
end

Remotes.NoiseDetected.OnClientEvent:Connect(function(position: Vector3, intensity: number)
	if not eligible() or typeof(position) ~= "Vector3" or type(intensity) ~= "number" then return end
	if not firstPingLogged then
		firstPingLogged = true
		print("[NoiseVisualizer] Primeiro ping recebido e renderizado acima do cenário.")
	end
	if #pings >= CFG.MaxActivePings then removePing(pings[1]) end
	local ping: Ping = { position = position, intensity = intensity, visuals = {}, destroyed = false }
	table.insert(pings, ping)
	startProjection()
	makeWave(ping, CFG.StartTransparency)
	task.delay(CFG.SecondWaveDelay, function()
		makeWave(ping, CFG.SecondWaveTransparency)
	end)
	task.delay(CFG.Duration + CFG.SecondWaveDelay, function()
		removePing(ping)
	end)
end)

local function watchCharacter(character: Model)
	clear()
	for _, connection in characterConnections do connection:Disconnect() end
	table.clear(characterConnections)
	local function watchHumanoid(child: Instance)
		if child:IsA("Humanoid") then table.insert(characterConnections, child.Died:Connect(clear)) end
	end
	for _, child in character:GetChildren() do watchHumanoid(child) end
	table.insert(characterConnections, character.ChildAdded:Connect(watchHumanoid))
	table.insert(characterConnections, character:GetAttributeChangedSignal("Eliminado"):Connect(function()
		if not eligible() then clear() end
	end))
end

local function onEligibilityChanged()
	if not eligible() then
		clear()
	elseif not roleWasReady then
		roleWasReady = true
		print("[NoiseVisualizer] Super audição visual ativa (papel: "
			.. tostring(player:GetAttribute("Role")) .. ").")
	end
end

for _, attribute in { "Role", "InRound", "Eliminado" } do
	player:GetAttributeChangedSignal(attribute):Connect(onEligibilityChanged)
end
player.CharacterAdded:Connect(function(character)
	watchCharacter(character)
	task.defer(onEligibilityChanged)
end)
player.CharacterRemoving:Connect(clear)
if player.Character then watchCharacter(player.Character) end
Remotes.RoundEnded.OnClientEvent:Connect(function() roundEnded = true; clear() end)
Remotes.RoundStateChanged.OnClientEvent:Connect(function() roundEnded = false; onEligibilityChanged() end)
onEligibilityChanged()
