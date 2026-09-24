--!strict
-- Substitui o antigo heartbeat por tempo fora de zona segura. Só lê Fear.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")
local Workspace = game:GetService("Workspace")
local ProximityPromptService = game:GetService("ProximityPromptService")
local Config = require(ReplicatedStorage.Modules.GameConfig)
local Rules = require(ReplicatedStorage.Modules.FearPresentationRules)
local Remotes = require(ReplicatedStorage.Modules.Remotes)
local AnimationPlayer = require(script.Parent.FearAnimationPlayer)
local CFG = Config.Fear
local Presentation = {}
local initialized = false

function Presentation.Init()
	if initialized then return end
	initialized = true
	local player = Players.LocalPlayer
	local playerGui = player:WaitForChild("PlayerGui")
	local connections: { RBXScriptConnection } = {}
	local characterConnections: { RBXScriptConnection } = {}
	local character: Model? = nil
	local animationPlayer: any = nil
	local smoothedFear, elapsed, debugElapsed = 0, 0, 0
	local presentationTime, interactionUntil = 0, 0
	local heldPrompt: ProximityPrompt? = nil
	local disabledRound = false
	local destroyed = false
	local gui = Instance.new("ScreenGui")
	gui.Name, gui.ResetOnSpawn, gui.IgnoreGuiInset = "FearPresentation", false, true
	gui.DisplayOrder, gui.Enabled = 1, false
	gui.Parent = playerGui
	-- Escurecimento de tela cheia, POR BAIXO da vinheta (ZIndex menor): em
	-- pânico a tela inteira perde luz e respira devagar.
	local darken = Instance.new("Frame")
	darken.Name, darken.Size = "FearDarken", UDim2.fromScale(1, 1)
	darken.BackgroundColor3 = Color3.fromRGB(3, 4, 7)
	darken.BackgroundTransparency, darken.BorderSizePixel = 1, 0
	darken.Active, darken.ZIndex = false, 0
	darken.Parent = gui
	local edges: { Frame } = {}
	local width = math.clamp(CFG.VignetteEdgeSize, 0.05, 0.3)
	for _, data in {
		{ "Left", UDim2.fromScale(0, 0), UDim2.fromScale(width, 1), 0 },
		{ "Right", UDim2.fromScale(1-width, 0), UDim2.fromScale(width, 1), 180 },
		{ "Top", UDim2.fromScale(0, 0), UDim2.fromScale(1, width), 90 },
		{ "Bottom", UDim2.fromScale(0, 1-width), UDim2.fromScale(1, width), 270 },
	} do
		local edge = Instance.new("Frame")
		edge.Name, edge.Position, edge.Size = data[1] :: string, data[2] :: UDim2, data[3] :: UDim2
		edge.BackgroundColor3 = Color3.new(0,0,0)
		edge.BackgroundTransparency, edge.BorderSizePixel, edge.Active = 1, 0, false
		edge.ZIndex = 1
		edge.Parent = gui
		local gradient = Instance.new("UIGradient")
		gradient.Rotation = data[4] :: number
		gradient.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0,0),
			NumberSequenceKeypoint.new(0.5,0.65), NumberSequenceKeypoint.new(1,1) })
		gradient.Parent = edge
		table.insert(edges, edge)
	end
	local blur = Instance.new("BlurEffect")
	blur.Name, blur.Size, blur.Enabled = "FearBlur", 0, false
	blur.Parent = Workspace.CurrentCamera -- efeito próprio local, sem alterar outros Blurs/Lighting
	local function sound(name: string): Sound
		local result = Instance.new("Sound")
		result.Name, result.Looped, result.Volume = name, true, 0
		result.Parent = SoundService
		return result
	end
	local heartbeat, breathing = sound("FearHeartbeat"), sound("FearBreathing")
	local function updateSound(instance: Sound, idValue: string, volume: number, speed: number)
		local id = Rules.AssetId(idValue)
		if instance.SoundId ~= (id or "") then instance:Stop(); instance.SoundId = id or "" end
		instance.Volume = if id then volume else 0
		instance.PlaybackSpeed = speed
		if id and volume > 0.001 then
			if not instance.IsPlaying then instance:Play() end
		elseif instance.IsPlaying then instance:Stop() end
	end
	local function reset()
		smoothedFear = 0
		heldPrompt, interactionUntil = nil, 0
		heartbeat:Stop(); heartbeat.Volume = 0
		breathing:Stop(); breathing.Volume = 0
		gui.Enabled = false
		darken.BackgroundTransparency = 1
		for _, edge in edges do edge.BackgroundTransparency = 1 end
		blur.Size, blur.Enabled = 0, false
		if animationPlayer then animationPlayer.Reset() end
	end
	local function eligible(): boolean
		if disabledRound or not character or player.Character ~= character then return false end
		local humanoid = character:FindFirstChildOfClass("Humanoid")
		return player:GetAttribute("Role") == Config.Roles.Survivor and player:GetAttribute("InRound") == true
			and ReplicatedStorage:GetAttribute("MatchState") == "InMatch"
			and player:GetAttribute("Eliminado") ~= true and character:GetAttribute("Eliminado") ~= true
			and player:GetAttribute("CharacterSelectOpen") ~= true and humanoid ~= nil and humanoid.Health > 0
	end
	local function clearCharacter()
		reset()
		if animationPlayer then animationPlayer.Destroy(); animationPlayer = nil end
		for _, connection in characterConnections do connection:Disconnect() end
		table.clear(characterConnections)
		character = nil
	end
	local function bindCharacter(model: Model)
		clearCharacter()
		character = model
		animationPlayer = AnimationPlayer.new(player, model)
		local attached = false
		local function attachHumanoid(child: Instance)
			if attached or not child:IsA("Humanoid") then return end
			attached = true
			table.insert(characterConnections, child.Died:Connect(clearCharacter))
		end
		table.insert(characterConnections, model.ChildAdded:Connect(attachHumanoid))
		table.insert(characterConnections, model:GetAttributeChangedSignal("Eliminado"):Connect(function()
			if not eligible() then reset() end
		end))
		local h = model:FindFirstChildOfClass("Humanoid")
		if h then attachHumanoid(h) end
	end
	table.insert(connections, player.CharacterAdded:Connect(bindCharacter))
	table.insert(connections, player.CharacterRemoving:Connect(clearCharacter))
	for _, name in { "Role", "InRound", "Eliminado", "CharacterSelectOpen" } do
		table.insert(connections, player:GetAttributeChangedSignal(name):Connect(function()
			if not eligible() then reset() end
		end))
	end
	table.insert(connections, ReplicatedStorage:GetAttributeChangedSignal("MatchState"):Connect(function()
		disabledRound = ReplicatedStorage:GetAttribute("MatchState") ~= "InMatch"
		if not eligible() then reset() end
	end))
	table.insert(connections, Remotes.RoundEnded.OnClientEvent:Connect(function()
		disabledRound = true; reset()
	end))
	table.insert(connections, Remotes.FearPresentation.OnClientEvent:Connect(function(event, model, duration)
		if event == "Trip" and model == character and eligible() and animationPlayer
			and type(duration) == "number" and duration > 0 and duration < math.huge then
			animationPlayer.PlayTrip(duration)
		end
	end))
	table.insert(connections, Workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function()
		blur.Parent = Workspace.CurrentCamera
	end))
	table.insert(connections, ProximityPromptService.PromptButtonHoldBegan:Connect(function(prompt, who)
		if who and who ~= player then return end
		heldPrompt = prompt
		if animationPlayer then animationPlayer.SetInteracting(true) end
	end))
	local function releasePrompt(prompt: ProximityPrompt)
		if heldPrompt == prompt then heldPrompt = nil end
	end
	table.insert(connections, ProximityPromptService.PromptButtonHoldEnded:Connect(releasePrompt))
	table.insert(connections, ProximityPromptService.PromptHidden:Connect(releasePrompt))
	table.insert(connections, ProximityPromptService.PromptTriggered:Connect(function(prompt, who)
		if who and who ~= player then return end
		releasePrompt(prompt)
		interactionUntil = presentationTime + CFG.FearInteractionGrace
		if animationPlayer then animationPlayer.SetInteracting(true) end
	end))
	if player.Character then bindCharacter(player.Character) end
	if CFG.EnableFearFOV then
		warn("[FearPresentation] Fear FOV desativado: movimento/mira já controlam o tween. Offset permanece zero.")
	end
	table.insert(connections, RunService.Heartbeat:Connect(function(dt)
		elapsed += dt
		if elapsed < CFG.PresentationUpdateInterval then return end
		local stepDt = elapsed; elapsed = 0
		presentationTime += stepDt
		if not eligible() then reset(); return end
		local value = player:GetAttribute("Fear")
		local fear = if type(value) == "number" and value == value then math.clamp(value, 0, CFG.MaxFear) else 0
		smoothedFear = Rules.Smooth(smoothedFear, fear, stepDt, CFG.PresentationSmoothTime)
		local targets = Rules.Targets(smoothedFear, CFG)
		updateSound(heartbeat, CFG.HeartbeatSoundId, targets.HeartbeatVolume, targets.HeartbeatPlaybackSpeed)
		updateSound(breathing, CFG.BreathingSoundId, targets.BreathingVolume, targets.BreathingPlaybackSpeed)
		-- Um relógio próprio (soma dos passos) em vez de os.clock(): a
		-- respiração não pula se um frame atrasar e o teste reproduz o valor.
		local darkness = Rules.Darken(smoothedFear, presentationTime, CFG)
		gui.Enabled = targets.VignetteOpacity > 0.001 or darkness > 0.001
		darken.BackgroundTransparency = 1 - darkness
		for _, edge in edges do edge.BackgroundTransparency = 1 - targets.VignetteOpacity end
		blur.Size, blur.Enabled = targets.BlurSize, targets.BlurSize > 0.001
		if animationPlayer then
			-- "Reparando" é marcado pelo servidor durante o reparo de precisão
			-- (RepairMinigameSystem): esse prompt tem HoldDuration 0, então nenhum
			-- PromptButtonHoldBegan acontece e a pose viria só do grace de 0,4s.
			local repairing = character ~= nil and character:GetAttribute("Reparando") == true
			animationPlayer.SetInteracting(heldPrompt ~= nil or presentationTime < interactionUntil or repairing)
			animationPlayer.Step(fear, stepDt)
		end
		debugElapsed = if CFG.DebugMode then debugElapsed + stepDt else 0
		if CFG.DebugMode and debugElapsed >= CFG.DebugPrintInterval then
			debugElapsed = 0
			local hud = Rules.HudFade(fear, CFG)
			print(string.format("[FearPresentation] Fear: %.1f | FearState: %s | HeartbeatVolume: %.2f | HeartbeatPlaybackSpeed: %.2f | BreathingVolume: %.2f | VignetteOpacity: %.2f | Darken: %.2f | BlurSize: %.2f | HudFadeVitals: %.2f | HudFadeHotbar: %.2f | FullMapBlocked: %s | FearFOVOffset: 0 | CurrentFearAnimation: %s",
				fear, tostring(player:GetAttribute("FearState")), heartbeat.Volume, heartbeat.PlaybackSpeed,
				breathing.Volume, targets.VignetteOpacity, darkness, blur.Size, hud.Vitals, hud.Hotbar,
				tostring(hud.FullMapBlocked), if animationPlayer then animationPlayer.CurrentName else "None"))
		end
	end))
	function Presentation.Destroy()
		if destroyed then return end
		destroyed = true
		clearCharacter()
		for _, connection in connections do connection:Disconnect() end
		table.clear(connections)
		heartbeat:Destroy(); breathing:Destroy(); blur:Destroy(); gui:Destroy() -- darken/edges vão com o gui
		initialized = false
	end
end

return Presentation
