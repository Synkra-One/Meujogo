--!strict
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")
local Remotes = require(ReplicatedStorage.Modules.Remotes)
local Characters = require(ReplicatedStorage.Modules.CharacterData)
local Assets = require(ReplicatedStorage.Modules.AssetRegistry).SurvivorPowers
local VFX = require(ReplicatedStorage.Modules.SurvivorPowerVFX)
local player = Players.LocalPlayer
local gui = player:WaitForChild("PlayerGui"):WaitForChild("SurvivorPowersHUD") :: ScreenGui

local function create(class: string, parent: Instance, properties: { [string]: any }): any
	local object = Instance.new(class)
	for key, value in properties do (object :: any)[key] = value end
	object.Parent = parent
	return object
end

local dock = create("Frame", gui, { Name = "Powers", AnchorPoint = Vector2.new(1, 1),
	Position = UDim2.new(1, -26, 1, -22), Size = UDim2.fromOffset(264, 132), BackgroundTransparency = 1 })
local scale = create("UIScale", dock, { Scale = 1 })
local message = create("TextLabel", dock, { Name = "Feedback", Position = UDim2.fromOffset(-50, -48),
	Size = UDim2.fromOffset(314, 40), BackgroundTransparency = 1, Text = "", TextWrapped = true,
	TextSize = 13, Font = Enum.Font.GothamMedium, TextColor3 = Color3.fromRGB(240, 203, 162), TextStrokeTransparency = 0.6 })
local interactionHint = create("TextLabel", dock, { Position = UDim2.fromOffset(0, 116),
	Size = UDim2.fromOffset(264, 16), BackgroundTransparency = 1, Text = "F  ·  INTERAGIR",
	TextSize = 10, Font = Enum.Font.GothamMedium, TextColor3 = Color3.fromRGB(158, 162, 166) })
local buttons: { any } = {}
local pending: { [number]: number } = {}
local blocked = false
local roundEnded = false
local messageUntil = 0
local direction: any = nil
local shakeUntil = 0
local prompts: { [ProximityPrompt]: Enum.KeyCode } = {}

for slot = 1, 2 do
	local frame = create("Frame", dock, { Name = "Slot" .. slot, Position = UDim2.fromOffset((slot - 1) * 136, 0),
		Size = UDim2.fromOffset(128, 116), BackgroundTransparency = 1 })
	local button = create("TextButton", frame, { Name = "Activate", AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0), Size = UDim2.fromOffset(78, 78), Text = "", AutoButtonColor = false,
		BackgroundColor3 = Color3.fromRGB(10, 12, 15), BackgroundTransparency = 0.2 })
	create("UICorner", button, { CornerRadius = UDim.new(0.5, 0) })
	local stroke = create("UIStroke", button, { Thickness = 1.4, Color = Color3.fromRGB(161, 172, 178), Transparency = 0.2 })
	local icon = create("ImageLabel", button, { Name = "Icon", AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(42, 42), BackgroundTransparency = 1, Image = "" })
	local glyph = create("TextLabel", button, { Name = "Placeholder", Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1, Text = if slot == 1 then "Ⅰ" else "Ⅱ", TextSize = 30,
		Font = Enum.Font.GothamBold, TextColor3 = Color3.fromRGB(224, 229, 232) })
	local overlay = create("Frame", button, { Name = "CooldownOverlay", Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.new(0, 0, 0), BackgroundTransparency = 0.25, Visible = false, ZIndex = 3 })
	create("UICorner", overlay, { CornerRadius = UDim.new(0.5, 0) })
	local counter = create("TextLabel", overlay, { Name = "Seconds", Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1, Text = "", TextColor3 = Color3.fromRGB(240, 241, 240),
		TextSize = 23, Font = Enum.Font.GothamMedium, ZIndex = 4 })
	local key = create("TextLabel", button, { Name = "Key", Position = UDim2.fromOffset(-1, -2),
		Size = UDim2.fromOffset(24, 24), BackgroundColor3 = Color3.fromRGB(34, 38, 42), Text = if slot == 1 then "Q" else "E",
		TextSize = 13, Font = Enum.Font.GothamBold, TextColor3 = Color3.new(1, 1, 1), ZIndex = 5 })
	create("UICorner", key, { CornerRadius = UDim.new(0.5, 0) })
	local label = create("TextLabel", frame, { Name = "PowerName", Position = UDim2.fromOffset(0, 82),
		Size = UDim2.fromOffset(128, 32), BackgroundTransparency = 1, Text = "", TextWrapped = true,
		TextSize = 12, Font = Enum.Font.GothamMedium, TextColor3 = Color3.fromRGB(222, 224, 226), TextStrokeTransparency = 0.6 })
	buttons[slot] = { button = button, stroke = stroke, icon = icon, glyph = glyph, overlay = overlay, counter = counter, label = label }
end

local compass = create("TextLabel", gui, { Name = "Direction", AnchorPoint = Vector2.new(0.5, 0.5),
	Size = UDim2.fromOffset(40, 40), BackgroundTransparency = 1, Text = "▲", TextSize = 32,
	Font = Enum.Font.GothamBold, Visible = false, TextStrokeTransparency = 0.5 })
local senseLabel = create("TextLabel", gui, { Name = "SenseLabel", AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.fromScale(0.5, 0.08), Size = UDim2.fromOffset(300, 24), BackgroundTransparency = 1,
	Text = "", TextSize = 13, Font = Enum.Font.GothamMedium, Visible = false, TextStrokeTransparency = 0.5 })

local function available(): boolean
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	return not roundEnded and player:GetAttribute("InRound") == true and player:GetAttribute("Role") == "Sobrevivente"
		and player:GetAttribute("GameplayEnabled") == true
		and player:GetAttribute("CharacterSelectOpen") ~= true and player:GetAttribute("Eliminado") ~= true
		and character ~= nil and humanoid ~= nil and humanoid.Health > 0
end

local function updatePrompt(prompt: ProximityPrompt)
	if gui.Enabled then
		if prompt.KeyboardKeyCode == Enum.KeyCode.E then
			prompts[prompt] = Enum.KeyCode.E
			prompt.KeyboardKeyCode = Enum.KeyCode.F
		end
	elseif prompts[prompt] then
		if prompt.KeyboardKeyCode == Enum.KeyCode.F then prompt.KeyboardKeyCode = prompts[prompt] end
		prompts[prompt] = nil
	end
end

local function refresh()
	local wasEnabled = gui.Enabled
	local data = Characters.GetById(player:GetAttribute("CharacterId"))
	gui.Enabled = available() and data ~= nil and data.PowerId1 ~= nil
	if wasEnabled ~= gui.Enabled then
		if gui.Enabled then
			for _, object in Workspace:GetDescendants() do if object:IsA("ProximityPrompt") then updatePrompt(object) end end
		else
			for prompt in prompts do updatePrompt(prompt) end
			direction = nil
		end
	end
	if not data then return end
	for slot, view in buttons do
		local id = if slot == 1 then data.PowerId1 else data.PowerId2
		local asset = id and Assets[id]
		view.id = id
		view.label.Text = if asset then asset.Label else ""
		local hasIcon = asset and asset.Icon and asset.Icon ~= "rbxassetid://0" and asset.Icon ~= ""
		view.icon.Image = if hasIcon then asset.Icon else ""
		view.glyph.Visible = not hasIcon
		view.color = if asset then asset.Color else Color3.new(1, 1, 1)
		view.icon.ImageColor3 = view.color
	end
end

local function request(slot: number)
	if not gui.Enabled or blocked or UserInputService:GetFocusedTextBox() then return end
	local now = Workspace:GetServerTimeNow()
	if now < (player:GetAttribute("SurvivorPowerReadyAt" .. slot) or 0) or os.clock() < (pending[slot] or 0) then return end
	pending[slot] = os.clock() + 0.3
	Remotes.UseSurvivorPower:FireServer(slot)
end

for slot, view in buttons do
	view.button.Activated:Connect(function() request(slot) end)
	view.button.MouseEnter:Connect(function()
		TweenService:Create(view.button, TweenInfo.new(0.12), { BackgroundTransparency = 0.05 }):Play()
	end)
	view.button.MouseLeave:Connect(function()
		TweenService:Create(view.button, TweenInfo.new(0.12), { BackgroundTransparency = 0.2 }):Play()
	end)
end
UserInputService.InputBegan:Connect(function(input, processed)
	if processed then return end
	if input.KeyCode == Enum.KeyCode.Q then request(1) elseif input.KeyCode == Enum.KeyCode.E then request(2) end
end)
Workspace.DescendantAdded:Connect(function(object)
	if object:IsA("ProximityPrompt") then task.defer(updatePrompt, object) end
end)
Workspace.DescendantRemoving:Connect(function(object)
	if object:IsA("ProximityPrompt") and prompts[object] then
		if object.KeyboardKeyCode == Enum.KeyCode.F then object.KeyboardKeyCode = prompts[object] end
		prompts[object] = nil
	end
end)

Remotes.UseSurvivorPower.OnClientEvent:Connect(function(op, a, b, c)
	if op == "Rejected" then
		message.Text = a or "Poder indisponível."
		messageUntil = os.clock() + 3
	elseif op == "Direction" and Assets[a] and typeof(b) == "Vector3" then
		direction = { id = a, localDirection = b, endsAt = c }
	end
end)
Remotes.SurvivorPowerFX.OnClientEvent:Connect(function(id, character, position, duration, phase)
	if not Assets[id] or typeof(position) ~= "Vector3" then return end
	VFX.Play(id, character, position, duration, phase)
	if id == "InvestidaBrutal" and phase == "Impact" then
		local camera = Workspace.CurrentCamera
		if camera and (camera.CFrame.Position - position).Magnitude < 25 then shakeUntil = os.clock() + 0.25 end
	end
end)
for _, name in { "Role", "CharacterId", "InRound", "Eliminado", "CharacterSelectOpen" } do
	player:GetAttributeChangedSignal(name):Connect(refresh)
end
player.CharacterAdded:Connect(function() direction = nil; task.defer(refresh) end)
player.CharacterRemoving:Connect(function() direction = nil; refresh() end)
Remotes.RoundStateChanged.OnClientEvent:Connect(function() roundEnded = false; refresh() end)
Remotes.RoundEnded.OnClientEvent:Connect(function() roundEnded = true; direction = nil; VFX.Clear(); refresh() end)

local refreshElapsed = 0
RunService.RenderStepped:Connect(function(dt)
	VFX.Step()
	refreshElapsed += dt
	if refreshElapsed >= 0.2 then refreshElapsed = 0; refresh() end
	if not gui.Enabled then compass.Visible = false; senseLabel.Visible = false; return end
	local camera = Workspace.CurrentCamera
	local character = player.Character
	blocked = character == nil or character:GetAttribute("PowerStunned") == true
		or character:GetAttribute("PowerMoving") == true or character:GetAttribute("FearTripping") == true
		or character:GetAttribute("GrabLocked") == true
	local viewport = if camera then camera.ViewportSize else Vector2.new(1280, 720)
	scale.Scale = math.clamp(math.min(viewport.X / 1050, viewport.Y / 700), 0.68, 1)
	dock.Position = UDim2.new(1, if UserInputService.TouchEnabled then -140 else -26, 1, -22)
	interactionHint.Visible = UserInputService.KeyboardEnabled
	message.Visible = os.clock() < messageUntil
	for slot, view in buttons do
		local remaining = math.max(0, (player:GetAttribute("SurvivorPowerReadyAt" .. slot) or 0) - Workspace:GetServerTimeNow())
		view.overlay.Visible = remaining > 0 or blocked
		view.counter.Text = if remaining > 0 then tostring(math.ceil(remaining)) elseif blocked then "—" else ""
		view.stroke.Color = if remaining > 0 or blocked then Color3.fromRGB(71, 78, 83) else view.color
	end
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local sensing = direction and direction.endsAt > Workspace:GetServerTimeNow() and root and root:IsA("BasePart") and camera
	compass.Visible = sensing and direction.localDirection.Magnitude > 0.01 or false
	senseLabel.Visible = sensing ~= nil and sensing ~= false
	if sensing then
		local asset = Assets[direction.id]
		local worldDirection = (root :: BasePart).CFrame:VectorToWorldSpace(direction.localDirection)
		local screenDirection = camera.CFrame:VectorToObjectSpace(worldDirection)
		local angle = math.atan2(screenDirection.X, -screenDirection.Z)
		compass.Position = UDim2.fromScale(0.5 + math.sin(angle) * 0.43, 0.5 - math.cos(angle) * 0.36)
		compass.Rotation = math.deg(angle)
		compass.TextColor3 = asset.Color
		compass.TextTransparency = 0.15 + (math.sin(os.clock() * 7) + 1) * 0.2
		senseLabel.TextColor3 = asset.Color
		senseLabel.Text = asset.Label .. (if compass.Visible then "" else " · sem sinal")
	end
end)
RunService:BindToRenderStep("SurvivorPowerCamera", Enum.RenderPriority.Camera.Value + 2, function()
	local camera = Workspace.CurrentCamera
	if camera and os.clock() < shakeUntil then
		local strength = (shakeUntil - os.clock()) / 0.25
		camera.CFrame *= CFrame.Angles(math.sin(os.clock() * 63) * 0.004 * strength, 0, math.cos(os.clock() * 51) * 0.003 * strength)
	end
end)
refresh()
