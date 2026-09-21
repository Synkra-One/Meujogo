--!strict
--[[
	Apagão do Abismo -- cliente.

	Duas metades, nenhuma com autoridade:
	  MONSTRO: manda "Use" e mostra o cooldown que o SERVIDOR publica em
	    Player.AbyssBlackoutReadyAt. Nenhum alvo, raio ou duração sai daqui.
	  SOBREVIVENTE ATINGIDO: recebe "Hit" com duração/fim e desenha o pulso
	    escuro/vermelho + estrondo grave. Quem manda no bloqueio da lanterna
	    continua sendo o Attribute "AbyssBlackout" no character (lido pelo
	    FlashlightController pela lista FlashlightConfig.BlockingFlags).

	O visual usa o MESMO envelope do servidor (AbyssBlackoutRules) e termina
	junto com ele: nada aqui fica permanente.
]]
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local FlashlightRules = require(ReplicatedStorage.Modules.FlashlightRules)
local RunService = game:GetService("RunService")
local ContextActionService = game:GetService("ContextActionService")
local UserInputService = game:GetService("UserInputService")
local SoundService = game:GetService("SoundService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Modules.GameConfig)
local Rules = require(ReplicatedStorage.Modules.AbyssBlackoutRules)
local AssetRules = require(ReplicatedStorage.Modules.FearPresentationRules)
local Remotes = require(ReplicatedStorage.Modules.Remotes)

local CFG = Config.Monster.AbyssBlackout
local ACTION = "AbyssBlackout"
local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local gui = Instance.new("ScreenGui")
gui.Name, gui.ResetOnSpawn, gui.IgnoreGuiInset = "AbyssBlackout", false, true
gui.DisplayOrder, gui.Enabled = 2, false
gui.Parent = playerGui

-- Tela cheia (escuridão) + moldura (pulso). Mesma ideia da vignette do Fear.
local tint = Instance.new("Frame")
tint.Name, tint.Size, tint.BorderSizePixel, tint.Active = "AbyssTint", UDim2.fromScale(1, 1), 0, false
tint.BackgroundColor3, tint.BackgroundTransparency = CFG.SustainColor, 1
tint.Parent = gui

local edges: { Frame } = {}
local edgeSize = math.clamp(CFG.EdgeSize, 0.05, 0.4)
for _, data in {
	{ "Left", UDim2.fromScale(0, 0), UDim2.fromScale(edgeSize, 1), 0 },
	{ "Right", UDim2.fromScale(1 - edgeSize, 0), UDim2.fromScale(edgeSize, 1), 180 },
	{ "Top", UDim2.fromScale(0, 0), UDim2.fromScale(1, edgeSize), 90 },
	{ "Bottom", UDim2.fromScale(0, 1 - edgeSize), UDim2.fromScale(1, edgeSize), 270 },
} do
	local edge = Instance.new("Frame")
	edge.Name, edge.Position, edge.Size = data[1] :: string, data[2] :: UDim2, data[3] :: UDim2
	edge.BackgroundColor3, edge.BackgroundTransparency = CFG.PulseColor, 1
	edge.BorderSizePixel, edge.Active = 0, false
	edge.Parent = gui
	local gradient = Instance.new("UIGradient")
	gradient.Rotation = data[4] :: number
	gradient.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0),
		NumberSequenceKeypoint.new(0.5, 0.55), NumberSequenceKeypoint.new(1, 1) })
	gradient.Parent = edge
	table.insert(edges, edge)
end

local label = Instance.new("TextLabel")
label.Name, label.AnchorPoint = "AbyssLabel", Vector2.new(0.5, 1)
label.Position, label.Size = UDim2.fromScale(0.5, 0.9), UDim2.fromOffset(360, 24)
label.BackgroundTransparency, label.TextColor3, label.TextSize = 1, Color3.fromRGB(196, 158, 158), 14
label.Font, label.Visible, label.Parent = Enum.Font.GothamMedium, false, gui

local blur = Instance.new("BlurEffect")
blur.Name, blur.Size, blur.Enabled = "AbyssBlur", 0, false
blur.Parent = Workspace.CurrentCamera

local rumble = Instance.new("Sound")
rumble.Name, rumble.Volume, rumble.Looped = "AbyssBlackoutHit", 0, false
rumble.PlaybackSpeed = CFG.HitSoundPlaybackSpeed
-- Aceita rbxassetid:// validado pelo mesmo helper do Fear, ou um rbxasset://
-- embutido da Roblox. Qualquer outra coisa fica vazia: nenhum Sound falso.
rumble.SoundId = AssetRules.AssetId(CFG.HitSoundId)
	or (if type(CFG.HitSoundId) == "string" and string.sub(CFG.HitSoundId, 1, 11) == "rbxasset://"
		then CFG.HitSoundId else "")
rumble.Parent = SoundService

local castSoundId = AssetRules.AssetId(CFG.CastSoundId)

local function playCastSound(rawCharacter: unknown, serverSoundAt: unknown)
	if not castSoundId then return end
	local caster = if typeof(rawCharacter) == "Instance" and (rawCharacter :: Instance):IsA("Model")
		then rawCharacter :: Model else nil
	local delaySeconds = if type(serverSoundAt) == "number"
		then math.max(0, (serverSoundAt :: number) - Workspace:GetServerTimeNow())
		else CFG.CastSoundDelay
	task.delay(delaySeconds, function()
		if not player.Parent or (caster and (not caster:IsDescendantOf(Workspace)
			or FlashlightRules.PowerBlocked(caster))) then return end
		local root = caster and caster:FindFirstChild("HumanoidRootPart")
		if not root or not root:IsA("BasePart") then return end
		local sound = Instance.new("Sound")
		sound.Name = "AbyssBlackoutMonsterScream"
		sound.SoundId = castSoundId :: string
		sound.Volume = CFG.CastSoundVolume
		sound.RollOffMode = Enum.RollOffMode.InverseTapered
		sound.RollOffMinDistance = 12
		sound.RollOffMaxDistance = CFG.SoundMaxDistance
		sound.EmitterSize = 5
		sound.Parent = root
		sound.Ended:Once(function() sound:Destroy() end)
		sound:Play()
		task.delay(12, function()
			if sound.Parent then sound:Destroy() end
		end)
	end)
end

local bound, effectStart, effectEndsAt = false, 0, 0
local warningText, warningUntil, caughtUntil, caughtCount = "", 0, 0, 0
local connections: { RBXScriptConnection } = {}

local function stopEffect()
	effectStart, effectEndsAt = 0, 0
	gui.Enabled = false
	tint.BackgroundTransparency = 1
	for _, edge in edges do edge.BackgroundTransparency = 1 end
	blur.Size, blur.Enabled = 0, false
	if rumble.IsPlaying then rumble:Stop() end
end

local function startEffect(duration: number, endsAt: number)
	if type(duration) ~= "number" or duration ~= duration or duration <= 0 or duration > 120 then return end
	effectStart = os.clock()
	-- endsAt do servidor manda; a duração local é só o formato do envelope.
	effectEndsAt = if type(endsAt) == "number" and endsAt == endsAt then endsAt else 0
	gui.Enabled = true
	if rumble.SoundId ~= "" then
		rumble.Volume = CFG.HitSoundVolume
		rumble:Play()
	end
end

local function action(_, state: Enum.UserInputState)
	if state ~= Enum.UserInputState.Begin then return Enum.ContextActionResult.Sink end
	local character = player.Character
	if not character or UserInputService:GetFocusedTextBox() or player:GetAttribute("MapaAberto")
		or player:GetAttribute("CursorLivre") or character:GetAttribute("TeleportBusy")
		or FlashlightRules.PowerBlocked(character) or character:GetAttribute("GrabLocked") then return Enum.ContextActionResult.Pass end
	if Workspace:GetServerTimeNow() < (player:GetAttribute("AbyssBlackoutReadyAt") or 0) then
		return Enum.ContextActionResult.Sink -- o servidor recusaria de qualquer forma
	end
	Remotes.AbyssBlackout:FireServer("Use")
	return Enum.ContextActionResult.Sink
end

table.insert(connections, Remotes.AbyssBlackout.OnClientEvent:Connect(function(kind, a, b)
	if kind == "Hit" then
		startEffect(a, b)
	elseif kind == "Cast" then
		playCastSound(a, b)
	elseif kind == "End" then
		stopEffect()
	elseif kind == "Result" and type(a) == "number" then
		caughtCount, caughtUntil = a, os.clock() + 2.5
	elseif kind == "Rejected" and type(a) == "string" then
		warningText, warningUntil = a, os.clock() + 2
	end
end))

table.insert(connections, Workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function()
	blur.Parent = Workspace.CurrentCamera
end))
table.insert(connections, player.CharacterRemoving:Connect(stopEffect))

-- Rede de segurança: se o "End" se perder, o Attribute autoritativo some
-- quando o servidor libera a lanterna, e o visual cai junto.
local function watchCharacter(character: Model)
	table.insert(connections, character:GetAttributeChangedSignal("AbyssBlackout"):Connect(function()
		if character:GetAttribute("AbyssBlackout") ~= true then stopEffect() end
	end))
end
table.insert(connections, player.CharacterAdded:Connect(watchCharacter))
if player.Character then watchCharacter(player.Character) end

local accumulator = 0
RunService:BindToRenderStep("AbyssBlackoutPresentation", Enum.RenderPriority.Camera.Value + 3, function(dt)
	local now = os.clock()
	local monster = player:GetAttribute("Role") == Config.Roles.Monster and player:GetAttribute("Eliminado") ~= true
	if monster ~= bound then
		bound = monster
		if bound then
			ContextActionService:BindAction(ACTION, action, true, CFG.InputKey, CFG.GamepadKey)
			ContextActionService:SetTitle(ACTION, "Apagão")
			ContextActionService:SetPosition(ACTION, UDim2.fromScale(0.72, 0.68))
		else
			ContextActionService:UnbindAction(ACTION)
		end
	end
	if effectStart > 0 then
		local character = player.Character
		local blocked = character ~= nil and character:GetAttribute("AbyssBlackout") == true
		local remaining = Rules.Remaining(effectEndsAt, Workspace:GetServerTimeNow())
		if not blocked and remaining <= 0 then
			stopEffect()
		else
			local targets = Rules.Presentation(now - effectStart, CFG.Duration, CFG)
			tint.BackgroundTransparency = 1 - targets.Opacity * (1 - targets.Blend)
			for _, edge in edges do edge.BackgroundTransparency = 1 - targets.Opacity * targets.Blend end
			blur.Size, blur.Enabled = targets.Blur, targets.Blur > 0.01
			if targets.Opacity <= 0.001 and remaining <= 0 then stopEffect() end
		end
	end
	accumulator += dt
	if accumulator < CFG.InputInterval then return end
	accumulator = 0
	label.Visible = monster or effectStart > 0
	if not label.Visible then return end
	if effectStart > 0 then
		label.TextColor3 = Color3.fromRGB(214, 138, 138)
		label.Text = string.format("Lanterna apagada pelo Abismo · %.0fs",
			math.ceil(Rules.Remaining(effectEndsAt, Workspace:GetServerTimeNow())))
		return
	end
	label.TextColor3 = Color3.fromRGB(196, 158, 158)
	local ready = math.max(0, (player:GetAttribute("AbyssBlackoutReadyAt") or 0) - Workspace:GetServerTimeNow())
	label.Text = if now < warningUntil then warningText
		elseif now < caughtUntil then string.format("Apagão do Abismo · %d atingido(s)", caughtCount)
		elseif ready > 0 then string.format("Apagão · %.0fs", math.ceil(ready))
		else "R · Apagão do Abismo"
end)

script.Destroying:Connect(function()
	RunService:UnbindFromRenderStep("AbyssBlackoutPresentation")
	ContextActionService:UnbindAction(ACTION)
	for _, connection in connections do connection:Disconnect() end
	table.clear(connections)
	stopEffect()
	rumble:Destroy(); blur:Destroy(); gui:Destroy()
end)
