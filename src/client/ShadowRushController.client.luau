--!strict
-- Input + presentation for all streamed characters. One bounded render loop;
-- state/position/cooldown are always received from the server.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ContextActionService = game:GetService("ContextActionService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")
local Debris = game:GetService("Debris")
local Config = require(ReplicatedStorage.Modules.GameConfig)
local Remotes = require(ReplicatedStorage.Modules.Remotes)
local AssetRules = require(ReplicatedStorage.Modules.FearPresentationRules)
local VFX = require(ReplicatedStorage.Modules.ShadowRushVFX)
local CFG = Config.Monster.ShadowRush
local player = Players.LocalPlayer
local effects: { [Model]: any } = {}
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
local controls: any = nil
task.spawn(function()
	local scripts = player:WaitForChild("PlayerScripts")
	local pm = scripts:WaitForChild("PlayerModule", 10)
	if pm then controls = require(pm :: ModuleScript):GetControls() end
end)

local function direction(): Vector3
	local char, camera = player.Character, Workspace.CurrentCamera
	if UserInputService:GetFocusedTextBox() or player:GetAttribute("MapaAberto") then return Vector3.zero end
	if controls and camera then
		local v = controls:GetMoveVector()
		local fwd = camera.CFrame.LookVector * Vector3.new(1, 0, 1)
		if fwd.Magnitude < 0.01 then return Vector3.zero end
		fwd = fwd.Unit
		local right = fwd:Cross(Vector3.yAxis)
		local desired = right * v.X - fwd * v.Z
		return if desired.Magnitude > 1 then desired.Unit else desired
	end
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	return if hum then hum.MoveDirection * Vector3.new(1, 0, 1) else Vector3.zero
end

local bound, accumulator, passAt, warningUntil, warningText = false, 0, -100, 0, ""
local oldCharacter: Model? = nil
local names = { EnteringShadow = "Desfazendo…", ShadowRush = "F · Materializar", Materializing = "Materializando…", Recovery = "Recuperando…" }
local function action(_, state)
	if state ~= Enum.UserInputState.Begin then return Enum.ContextActionResult.Sink end
	local char = player.Character
	if not char or UserInputService:GetFocusedTextBox() or player:GetAttribute("MapaAberto")
		or player:GetAttribute("CursorLivre") or char:GetAttribute("TeleportBusy") then return Enum.ContextActionResult.Pass end
	if char:GetAttribute("ShadowRushBusy") then
		Remotes.ShadowRush:FireServer("Stop", char:GetAttribute("ShadowRushToken"))
	elseif Workspace:GetServerTimeNow() >= (player:GetAttribute("ShadowRushReadyAt") or 0) then
		Remotes.ShadowRush:FireServer("Start", nil, direction())
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

local renderConnection = RunService.RenderStepped:Connect(function(dt)
	accumulator += dt
	local char = player.Character
	if oldCharacter ~= char then
		if oldCharacter then oldCharacter:SetAttribute("ShadowRushFOV", nil) end
		oldCharacter = char
	end
	local monster = player:GetAttribute("Role") == Config.Roles.Monster and player:GetAttribute("Eliminado") ~= true
	if monster ~= bound then
		bound = monster
		if bound then
			ContextActionService:BindAction("ShadowRush", action, true, Enum.KeyCode.F, Enum.KeyCode.ButtonL1)
			ContextActionService:SetTitle("ShadowRush", "Sombra")
			ContextActionService:SetPosition("ShadowRush", UDim2.fromScale(0.72, 0.62))
		else ContextActionService:UnbindAction("ShadowRush") end
	end
	local busy = char and char:GetAttribute("ShadowRushBusy") == true
	local speed = if char and busy then math.clamp((char:GetAttribute("ShadowRushSpeed") or 0) / CFG.ShadowRushMaxSpeed, 0, 1) else 0
	local pass = math.max(0, 1 - (os.clock() - passAt) / 0.4)
	for _, edge in edges do edge.BackgroundTransparency = 1 - math.max(speed * 0.18, pass * 0.38) end
	label.Visible = monster
	if accumulator >= CFG.InputInterval then
		accumulator = 0
		if char then char:SetAttribute("ShadowRushFOV", if busy then math.floor(speed * CFG.FOVOffset * 2) / 2 else nil) end
		if char and busy then Remotes.ShadowRush:FireServer("Move", char:GetAttribute("ShadowRushToken"), direction()) end
		local remaining = math.max(0, (player:GetAttribute("ShadowRushReadyAt") or 0) - Workspace:GetServerTimeNow())
		local state = char and char:GetAttribute("ShadowRushState")
		label.Text = if os.clock() < warningUntil then warningText
			elseif busy then (names :: any)[state] or "Shadow Rush"
			elseif remaining > 0 then string.format("Shadow Rush · %.0fs", math.ceil(remaining)) else "F · Shadow Rush"
		-- Attributes survive late joins and StreamingEnabled. No missed start
		-- remote can leave a nearby observer looking at the normal body.
		for _, p in Players:GetPlayers() do
			local c = p.Character
			local r = c and c:FindFirstChild("HumanoidRootPart")
			local h = c and c:FindFirstChildOfClass("Humanoid")
			if c and r and r:IsA("BasePart") and h and h.Health > 0 and c:GetAttribute("ShadowRushBusy") == true
				and not effects[c] then
				effects[c] = VFX.new(c, r, folder)
			end
		end
	end
	for c, effect in effects do
		local r, h = c:FindFirstChild("HumanoidRootPart"), c:FindFirstChildOfClass("Humanoid")
		if not c:IsDescendantOf(Workspace) or c:GetAttribute("ShadowRushBusy") ~= true or not h or h.Health <= 0
			or not r or not r:IsA("BasePart") then
			effect.Destroy(); effects[c] = nil
		else
			local ok, err = pcall(effect.Update, dt)
			if not ok then effect.Destroy(); effects[c] = nil; warn("[ShadowRushVFX] " .. tostring(err)) end
		end
	end
end)

script.Destroying:Connect(function()
	renderConnection:Disconnect()
	remoteConnection:Disconnect()
	ContextActionService:UnbindAction("ShadowRush")
	for _, effect in effects do effect.Destroy() end
	if oldCharacter then oldCharacter:SetAttribute("ShadowRushFOV", nil) end
	folder:Destroy(); gui:Destroy()
end)
