--!strict
-- Visão exclusiva do Monstro. Tudo aqui é local: sobreviventes não recebem
-- brilho extra, vinheta roxa nem qualquer alteração de iluminação.

local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage.Modules.GameConfig)
local LocalPlayer = Players.LocalPlayer
local CFG = GameConfig.Monster.Vision

local POST_COLOR_NAME = "MonsterNightVisionColor"
local POST_BLOOM_NAME = "MonsterNightVisionBloom"
local GUI_NAME = "MonsterNightVisionCorners"

local character: Model? = nil
local humanoid: Humanoid? = nil
local active = false
local refreshQueued = false
local characterConnections: { RBXScriptConnection } = {}

local gui: ScreenGui? = nil
local edges: { Frame } = {}
local colorFx: ColorCorrectionEffect? = nil
local bloomFx: BloomEffect? = nil

local function disconnectCharacter()
	for _, connection in characterConnections do
		connection:Disconnect()
	end
	table.clear(characterConnections)
	character = nil
	humanoid = nil
end

local function createPostEffects()
	if not colorFx or not colorFx.Parent then
		local existing = Lighting:FindFirstChild(POST_COLOR_NAME)
		if existing and existing:IsA("ColorCorrectionEffect") then
			colorFx = existing
		else
			local effect = Instance.new("ColorCorrectionEffect")
			effect.Name = POST_COLOR_NAME
			effect.Parent = Lighting
			colorFx = effect
		end
	end
	if not bloomFx or not bloomFx.Parent then
		local existing = Lighting:FindFirstChild(POST_BLOOM_NAME)
		if existing and existing:IsA("BloomEffect") then
			bloomFx = existing
		else
			local effect = Instance.new("BloomEffect")
			effect.Name = POST_BLOOM_NAME
			effect.Parent = Lighting
			bloomFx = effect
		end
	end

	local color = colorFx :: ColorCorrectionEffect
	color.Brightness = CFG.Brightness
	color.Contrast = CFG.Contrast
	color.Saturation = CFG.Saturation
	color.TintColor = CFG.TintColor

	local bloom = bloomFx :: BloomEffect
	bloom.Intensity = CFG.BloomIntensity
	bloom.Size = CFG.BloomSize
	bloom.Threshold = CFG.BloomThreshold
end

local function shadowRushActive(): boolean
	return character ~= nil and character:GetAttribute("ShadowRushBusy") == true
end

local function addEdge(name: string, position: UDim2, size: UDim2, rotation: number)
	local overlay = gui :: ScreenGui
	local edge = Instance.new("Frame")
	edge.Name = name
	edge.Position = position
	edge.Size = size
	edge.BackgroundColor3 = Color3.fromRGB(116, 71, 190)
	edge.BackgroundTransparency = 1 - CFG.CornerOpacity
	edge.BorderSizePixel = 0
	edge.Active = false
	edge.ZIndex = 1
	edge.Parent = overlay

	local gradient = Instance.new("UIGradient")
	gradient.Rotation = rotation
	gradient.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0),
		NumberSequenceKeypoint.new(0.42, 0.52),
		NumberSequenceKeypoint.new(1, 1),
	})
	gradient.Parent = edge
	table.insert(edges, edge)
end

local function createGui()
	if gui and gui.Parent then
		return
	end

	local playerGui = LocalPlayer:WaitForChild("PlayerGui")
	local existing = playerGui:FindFirstChild(GUI_NAME)
	if existing and existing:IsA("ScreenGui") then
		gui = existing
	else
		local screen = Instance.new("ScreenGui")
		screen.Name = GUI_NAME
		screen.ResetOnSpawn = false
		screen.IgnoreGuiInset = true
		screen.DisplayOrder = 3
		screen.Enabled = false
		screen.Parent = playerGui
		gui = screen
	end

	for _, child in (gui :: ScreenGui):GetChildren() do
		child:Destroy()
	end
	table.clear(edges)

	local width = math.clamp(CFG.CornerSize, 0.08, 0.28)
	addEdge("PurpleEdgeLeft", UDim2.fromScale(0, 0), UDim2.fromScale(width, 1), 0)
	addEdge("PurpleEdgeRight", UDim2.fromScale(1 - width, 0), UDim2.fromScale(width, 1), 180)
	addEdge("PurpleEdgeTop", UDim2.fromScale(0, 0), UDim2.fromScale(1, width), 90)
	addEdge("PurpleEdgeBottom", UDim2.fromScale(0, 1 - width), UDim2.fromScale(1, width), 270)
end

local function applyProfile()
	local brightProfile = shadowRushActive()
	local color = colorFx :: ColorCorrectionEffect
	local bloom = bloomFx :: BloomEffect
	local cornerOpacity = if brightProfile then CFG.ShadowRushCornerOpacity else CFG.CornerOpacity
	color.Brightness = if brightProfile then CFG.ShadowRushBrightness else CFG.Brightness
	color.Contrast = if brightProfile then CFG.ShadowRushContrast else CFG.Contrast
	color.Saturation = if brightProfile then CFG.ShadowRushSaturation else CFG.Saturation
	color.TintColor = if brightProfile then CFG.ShadowRushTintColor else CFG.TintColor
	bloom.Intensity = if brightProfile then CFG.ShadowRushBloomIntensity else CFG.BloomIntensity
	bloom.Size = if brightProfile then CFG.ShadowRushBloomSize else CFG.BloomSize
	bloom.Threshold = if brightProfile then CFG.ShadowRushBloomThreshold else CFG.BloomThreshold
	for _, edge in edges do
		edge.BackgroundTransparency = 1 - cornerOpacity
	end
end

local function setEnabled(shouldEnable: boolean)
	active = shouldEnable
	createPostEffects()
	createGui()
	local color = colorFx :: ColorCorrectionEffect
	local bloom = bloomFx :: BloomEffect
	local overlay = gui :: ScreenGui
	color.Enabled = shouldEnable
	bloom.Enabled = shouldEnable
	overlay.Enabled = shouldEnable
	applyProfile()
end

local function isEligible(): boolean
	if LocalPlayer:GetAttribute("Role") ~= GameConfig.Roles.Monster then
		return false
	end
	if LocalPlayer:GetAttribute("InRound") ~= true or LocalPlayer:GetAttribute("Eliminado") == true then
		return false
	end
	local model = character
	local hum = humanoid
	return model ~= nil and LocalPlayer.Character == model and hum ~= nil and hum.Health > 0
end

local function refresh()
	refreshQueued = false
	setEnabled(isEligible())
end

local function queueRefresh()
	if refreshQueued then
		return
	end
	refreshQueued = true
	task.defer(refresh)
end

local function bindCharacter(model: Model)
	disconnectCharacter()
	character = model
	local foundHumanoid = model:FindFirstChildOfClass("Humanoid")
	if foundHumanoid then
		humanoid = foundHumanoid
		table.insert(characterConnections, foundHumanoid.Died:Connect(queueRefresh))
	else
		table.insert(characterConnections, model.ChildAdded:Connect(function(child)
			if child:IsA("Humanoid") and not humanoid then
				humanoid = child
				table.insert(characterConnections, child.Died:Connect(queueRefresh))
				queueRefresh()
			end
		end))
	end
	table.insert(characterConnections, model:GetAttributeChangedSignal("ShadowRushBusy"):Connect(queueRefresh))
	queueRefresh()
end

for _, attribute in { "Role", "InRound", "Eliminado" } do
	LocalPlayer:GetAttributeChangedSignal(attribute):Connect(queueRefresh)
end
LocalPlayer.CharacterAdded:Connect(bindCharacter)
LocalPlayer.CharacterRemoving:Connect(function(model)
	if model == character then
		disconnectCharacter()
		queueRefresh()
	end
end)

if LocalPlayer.Character then
	bindCharacter(LocalPlayer.Character)
else
	queueRefresh()
end

-- Reaplica os valores caso outro efeito ou uma troca de Lighting remova a
-- instância local, sem atualizar a tela a cada frame.
local elapsed = 0
RunService.Heartbeat:Connect(function(dt)
	elapsed += dt
	if elapsed < 0.25 then
		return
	end
	elapsed = 0
	if active and (not colorFx or not colorFx.Parent or not bloomFx or not bloomFx.Parent) then
		queueRefresh()
	elseif active ~= isEligible() then
		queueRefresh()
	end
end)
