--!strict
-- Input + presentation for all streamed characters. One bounded render loop;
-- state/position/cooldown are always received from the server.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local FlashlightRules = require(ReplicatedStorage.Modules.FlashlightRules)
local RunService = game:GetService("RunService")
local ContextActionService = game:GetService("ContextActionService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")
local Debris = game:GetService("Debris")
local Config = require(ReplicatedStorage.Modules.GameConfig)
local Remotes = require(ReplicatedStorage.Modules.Remotes)
local AssetRules = require(ReplicatedStorage.Modules.FearPresentationRules)
local Rules = require(ReplicatedStorage.Modules.ShadowRushRules)
local VFX = require(ReplicatedStorage.Modules.ShadowRushVFX)
local CFG = Config.Monster.ShadowRush
local player = Players.LocalPlayer
local effects: { [Model]: any } = {}
local tokens: { [Model]: number } = {}
local view = VFX.newView()
local lowQuality = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
pcall(function()
	local quality = UserSettings():GetService("UserGameSettings").SavedQualityLevel.Value
	lowQuality = lowQuality or (quality > 0 and quality <= 4)
end)
local folder = Instance.new("Folder")
folder.Name, folder.Parent = "ShadowRushVFX", Workspace
local gui = Instance.new("ScreenGui")
gui.Name, gui.ResetOnSpawn, gui.IgnoreGuiInset = "ShadowRushHUD", false, true
gui.Parent = player:WaitForChild("PlayerGui")
local label = Instance.new("TextLabel")
label.AnchorPoint, label.Position, label.Size = Vector2.new(0.5, 1), UDim2.fromScale(0.5, 0.86), UDim2.fromOffset(340, 26)
label.BackgroundTransparency, label.TextColor3, label.TextSize = 1, Color3.fromRGB(175, 178, 182), 14
label.Font, label.Parent = Enum.Font.GothamMedium, gui
local edges: { Frame } = {}
for i = 1, 4 do
	local edge = Instance.new("Frame")
	edge.BorderSizePixel, edge.BackgroundColor3, edge.BackgroundTransparency = 0, Color3.new(0, 0, 0), 1
	edge.Size = if i <= 2 then UDim2.fromScale(1, 0.12) else UDim2.fromScale(0.1, 1)
	edge.Position = if i == 2 then UDim2.fromScale(0, 0.88) elseif i == 4 then UDim2.fromScale(0.9, 0) else UDim2.fromScale(0, 0)
	local gradient = Instance.new("UIGradient")
	gradient.Transparency = NumberSequence.new(0, 1)
	gradient.Rotation = if i == 1 then 90 elseif i == 2 then 270 elseif i == 3 then 0 else 180
	gradient.Parent, edge.Parent = edge, gui
	table.insert(edges, edge)
end
local bound, accumulator, passAt, warningUntil, warningText = false, 0, -100, 0, ""
local oldCharacter: Model? = nil
local visionHidden = 0
local lastToken: number? = nil
local names = { EnteringShadow = "Desfazendo…", ShadowRush = "F · Materializar", Materializing = "Materializando…", Recovery = "Recuperando…" }
local function action(_, state)
	if state ~= Enum.UserInputState.Begin then return Enum.ContextActionResult.Sink end
	local char = player.Character
	if not char or FlashlightRules.PowerBlocked(char) or UserInputService:GetFocusedTextBox() or player:GetAttribute("MapaAberto")
		or player:GetAttribute("CursorLivre") or char:GetAttribute("TeleportBusy")
		or char:GetAttribute("GrabLocked") then return Enum.ContextActionResult.Pass end
	if char:GetAttribute("ShadowRushBusy") then
		Remotes.ShadowRush:FireServer("Stop", char:GetAttribute("ShadowRushToken"))
	elseif Workspace:GetServerTimeNow() >= (player:GetAttribute("ShadowRushReadyAt") or 0) then
		Remotes.ShadowRush:FireServer("Start")
	end
	return Enum.ContextActionResult.Sink
end

local remoteConnection = Remotes.ShadowRush.OnClientEvent:Connect(function(kind, message)
	if kind == "Pass" then
		passAt = os.clock()
		local id = AssetRules.AssetId(CFG.ShadowPassSoundId)
		if id then
			local s = Instance.new("Sound")
			s.Name, s.SoundId, s.Volume = "ShadowPass", id, CFG.SoundVolume
			s.Parent = game:GetService("SoundService")
			s:Play(); Debris:AddItem(s, 4)
		end
	elseif kind == "Rejected" and type(message) == "string" then
		warningText, warningUntil = message, os.clock() + 2
	end
end)

-- Remove our previous impulse before the existing camera controller runs.
RunService:BindToRenderStep("ShadowRushUnshake", Enum.RenderPriority.Camera.Value - 1, view.Unshake)
RunService:BindToRenderStep("ShadowRushPresentation", Enum.RenderPriority.Camera.Value + 4, function(dt)
	accumulator += dt
	local char = player.Character
	if oldCharacter ~= char then
		if oldCharacter then oldCharacter:SetAttribute("ShadowRushFOV", nil) end
		oldCharacter = char
		view.Destroy(); visionHidden, lastToken = 0, nil
	end
	local monster = player:GetAttribute("Role") == Config.Roles.Monster and player:GetAttribute("Eliminado") ~= true
	if monster ~= bound then
		bound = monster
		if bound then
			ContextActionService:BindAction("ShadowRush", action, true, Enum.KeyCode.F, Enum.KeyCode.ButtonL1)
			ContextActionService:SetTitle("ShadowRush", "Desaparecer")
			ContextActionService:SetPosition("ShadowRush", UDim2.fromScale(0.72, 0.62))
		else ContextActionService:UnbindAction("ShadowRush") end
	end
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	local root = char and char:FindFirstChild("HumanoidRootPart")
	local busy = char and char:GetAttribute("ShadowRushBusy") == true
	local personal = busy and monster and hum and hum.Health > 0 and char:IsDescendantOf(Workspace)
	local speed = 0
	if personal and root and root:IsA("BasePart") then
		speed = math.clamp((root.AssemblyLinearVelocity * Vector3.new(1, 0, 1)).Magnitude / CFG.ShadowRushMaxSpeed, 0, 1)
	end
	local phase = char and char:GetAttribute("ShadowRushState")
	local elapsed = if char then math.max(0, Workspace:GetServerTimeNow() - (char:GetAttribute("ShadowRushPhaseAt") or Workspace:GetServerTimeNow())) else 0
	visionHidden = if personal then Rules.Hidden(phase, elapsed, char:GetAttribute("ShadowRushExitHidden") or visionHidden, CFG) else 0
	local token = if personal then char:GetAttribute("ShadowRushToken") else nil
	local enter = token ~= lastToken and phase == "EnteringShadow" and elapsed < CFG.ShadowRushEnterDuration
	lastToken = token
	local vision = view.Update(dt, visionHidden, speed, enter)
	local pass = math.max(0, 1 - (os.clock() - passAt) / 0.4)
	for _, edge in edges do edge.BackgroundTransparency = 1 - math.max(vision * CFG.Visual.VignetteOpacity, pass * 0.38) end
	label.Visible = monster
	if accumulator >= CFG.InputInterval then
		accumulator = 0
		if char then char:SetAttribute("ShadowRushFOV", if personal then math.floor(speed * vision * CFG.FOVOffset * 2) / 2 else nil) end
		local remaining = math.max(0, (player:GetAttribute("ShadowRushReadyAt") or 0) - Workspace:GetServerTimeNow())
		local state = char and char:GetAttribute("ShadowRushState")
		label.Text = if os.clock() < warningUntil then warningText
			elseif FlashlightRules.PowerBlocked(char) then "Ofuscado · poderes bloqueados"
			elseif busy then (names :: any)[state] or "Desaparecer"
			elseif remaining > 0 then string.format("Desaparecer · %.0fs", math.ceil(remaining)) else "F · Desaparecer"
		-- Attributes survive late joins and StreamingEnabled. No missed start
		-- remote can leave a nearby observer looking at the normal body.
		for _, p in Players:GetPlayers() do
			local c = p.Character
			local r = c and c:FindFirstChild("HumanoidRootPart")
			local h = c and c:FindFirstChildOfClass("Humanoid")
			if c and r and r:IsA("BasePart") and h and h.Health > 0 and c:GetAttribute("ShadowRushBusy") == true then
				local nextToken = c:GetAttribute("ShadowRushToken")
				if effects[c] and tokens[c] ~= nextToken then effects[c].Destroy(); effects[c] = nil end
				if not effects[c] then
					effects[c] = VFX.new(c, r, folder, c == char, lowQuality)
					tokens[c] = nextToken
				end
			end
		end
	end
	for c, effect in effects do
		local r, h = c:FindFirstChild("HumanoidRootPart"), c:FindFirstChildOfClass("Humanoid")
		if not c:IsDescendantOf(Workspace) or not h or h.Health <= 0
			or not r or not r:IsA("BasePart") then
			effect.Destroy(); effects[c], tokens[c] = nil, nil
		else
			if c:GetAttribute("ShadowRushBusy") ~= true then effect.Finish() end
			local camera = Workspace.CurrentCamera
			local distance = if camera then (camera.CFrame.Position - r.Position).Magnitude else math.huge
			local ok, finished = pcall(effect.Update, dt, distance)
			if not ok or finished then
				effect.Destroy(); effects[c], tokens[c] = nil, nil
				if not ok then warn("[ShadowRushVFX] " .. tostring(finished)) end
			end
		end
	end
end)

script.Destroying:Connect(function()
	RunService:UnbindFromRenderStep("ShadowRushPresentation")
	RunService:UnbindFromRenderStep("ShadowRushUnshake")
	view.Destroy()
	remoteConnection:Disconnect()
	ContextActionService:UnbindAction("ShadowRush")
	for _, effect in effects do effect.Destroy() end
	if oldCharacter then oldCharacter:SetAttribute("ShadowRushFOV", nil) end
	folder:Destroy(); gui:Destroy()
end)
