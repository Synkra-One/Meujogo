--!strict
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ContextActionService = game:GetService("ContextActionService")
local SoundService = game:GetService("SoundService")
local UserInputService = game:GetService("UserInputService")
local Modules = game:GetService("ReplicatedStorage"):WaitForChild("Modules")
local Config = require(Modules.FlashlightConfig)
local GameConfig = require(Modules.GameConfig)
local ItemRegistry = require(Modules.ItemRegistry)
local Remotes = require(Modules.Remotes)
local Visuals = require(script.Parent.FlashlightVisuals)
local HUD = require(script.Parent.FlashlightHUD)
local ExposureFX = require(script.Parent.FlashlightExposureFX)
local Pose = require(script.Parent.FlashlightPose)

local player = Players.LocalPlayer
local hud = HUD.new(player:WaitForChild("PlayerGui") :: PlayerGui)
local fx = ExposureFX.new(player)
local pose: Pose.Controller = Pose.new()
local remotePoses: { [Tool]: Pose.Controller } = {}
local equipped: Tool? = nil
local predicted = false
local pendingAt: number? = nil
local toggleSequence = 0
local lastToggle, lastAim, lastHUD = -math.huge, -math.huge, 0
local lastBlockedReason, lastBlockedWarn = "", -math.huge
local lastDirection: Vector3? = nil
local aimDirection = Vector3.new(0, 0, -1)
local visibleTools: { [Tool]: Player } = {}
local toolConnections: { RBXScriptConnection } = {}
local characterConnections: { [Player]: { RBXScriptConnection } } = {}
local playerConnections: { [Player]: { RBXScriptConnection } } = {}
local ACTION = "ToggleSurvivorFlashlight"
local BURST_ACTION = "BurstSurvivorFlashlight"
local burstSequence, lastBurstRequest = 0, -math.huge
local burstPendingAt: number? = nil
local burstReadyAt = 0
local switch = Instance.new("Sound")
switch.Name, switch.SoundId, switch.Volume, switch.Parent = "FlashlightSwitch", Config.SwitchSound, 0.25, SoundService
local empty = Instance.new("Sound")
empty.Name, empty.SoundId, empty.Volume, empty.Parent = "FlashlightEmpty", Config.EmptySound, 0.3, SoundService
empty.PlaybackSpeed = 0.55
local burstFeedbackSound = Instance.new("Sound")
burstFeedbackSound.Name, burstFeedbackSound.SoundId = "FlashBurstConfirmation", Config.SwitchSound
burstFeedbackSound.Volume, burstFeedbackSound.Parent = 0.16, SoundService
local aimParams = RaycastParams.new()
aimParams.FilterType = Enum.RaycastFilterType.Exclude

local function battery(): number
	local value = equipped and equipped:GetAttribute("Battery")
	return if type(value) == "number" then value else Config.BatteryMax
end

local function canUseRole(): boolean
	return player:GetAttribute("Role") == GameConfig.Roles.Survivor or RunService:IsStudio()
end

local function blockedReason(): string?
	if player:GetAttribute("GameplayEnabled") ~= true then return "estado de preparação" end
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not character or not humanoid or humanoid.Health <= 0 or not equipped or equipped.Parent ~= character
		or player:GetAttribute("Eliminado") == true then return "sem personagem vivo ou lanterna equipada" end
	if not canUseRole() then return "papel atual nao pode usar lanterna" end
	if player:GetAttribute("InWaitingRoom") == true and not RunService:IsStudio() then return "fila de preparação" end
	for _, flag in Config.BlockingFlags do
		if character:GetAttribute(flag) == true or player:GetAttribute(flag) == true then return flag end
	end
	return nil
end

local function eligible(): boolean
	return blockedReason() == nil
end

local function warnBlocked(reason: string?)
	local now = os.clock()
	reason = reason or "bloqueio desconhecido"
	if reason == lastBlockedReason and now - lastBlockedWarn < 1.5 then return end
	lastBlockedReason, lastBlockedWarn = reason, now
	warn("[Lanterna] Nao ligou: " .. reason)
end

local function toggle()
	local tool = equipped
	local now = os.clock()
	if not tool then return end
	local reason = blockedReason()
	if reason then warnBlocked(reason); return end
	if now - lastToggle < Config.ToggleCooldown then return end
	lastToggle = now
	predicted, pendingAt = not predicted, now
	toggleSequence += 1
	pose:PlayClick()
	switch:Play()
	Remotes.Flashlight:FireServer("Toggle", tool, predicted, aimDirection, toggleSequence)
end

local function burstCooldown(): number
	return math.max(burstReadyAt, player:GetAttribute("FlashBurstReadyAt") or 0,
		if equipped then equipped:GetAttribute("FlashBurstReadyAt") or 0 else 0)
end

local function fireBurst()
	if not equipped or not eligible() or UserInputService:GetFocusedTextBox()
		or player:GetAttribute("CursorLivre") == true then return end
	local now = os.clock()
	if burstPendingAt and now - burstPendingAt < 1.5 then return end
	if now - lastBurstRequest < Config.FlashBurstInputInterval then return end
	lastBurstRequest = now
	if workspace:GetServerTimeNow() < burstCooldown() then hud:BurstFeedback("Cooldown", false); return end
	if battery() < Config.FlashBurstCost then hud:BurstFeedback("Battery", false); empty:Play(); return end
	burstSequence += 1
	burstPendingAt = now
	Remotes.Flashlight:FireServer("Burst", equipped, nil, aimDirection, burstSequence)
end

local function unequip()
	local old = equipped
	equipped, predicted, pendingAt = nil, false, nil
	for _, connection in toolConnections do connection:Disconnect() end
	table.clear(toolConnections)
	ContextActionService:UnbindAction(ACTION)
	ContextActionService:UnbindAction(BURST_ACTION)
	burstPendingAt = nil
	if old then Visuals.Remove(old) end
	pose:SetTool(nil)
	hud:Update(false, 0, false, 0)
end

local function equip(tool: Tool)
	if equipped == tool then return end
	unequip()
	local duplicatePose = remotePoses[tool]
	if duplicatePose then duplicatePose:Destroy(); remotePoses[tool] = nil end
	equipped = tool
	predicted = tool:GetAttribute("FlashlightOn") == true
	lastAim, lastDirection = -math.huge, nil
	pose:SetTool(tool)
	print(string.format("[Lanterna] Sistema novo equipado. Use clique, toque, R2, T ou Y. Bateria: %.0f%%.", battery()))
	local camera = workspace.CurrentCamera
	if camera then aimDirection = camera.CFrame.LookVector end
	table.insert(toolConnections, tool.Activated:Connect(toggle))
	table.insert(toolConnections, tool:GetAttributeChangedSignal("FlashlightOn"):Connect(function()
		if not pendingAt then predicted = tool:GetAttribute("FlashlightOn") == true end
	end))
	-- Tool.Activated already handles mouse/tap/R2. T and Y are additional
	-- bindings; the touch button is separate and never sends a second toggle.
	ContextActionService:BindAction(ACTION, function(_, state)
		if not eligible() then return Enum.ContextActionResult.Pass end
		if state == Enum.UserInputState.Begin then toggle() end
		return Enum.ContextActionResult.Sink
	end, true, Enum.KeyCode.T, Enum.KeyCode.ButtonY)
	ContextActionService:SetTitle(ACTION, "")
	ContextActionService:SetImage(ACTION, if tool.TextureId ~= "" then tool.TextureId
		else `rbxthumb://type=Asset&id={ItemRegistry.Items.Lanterna.AssetId}&w=150&h=150`)
	ContextActionService:SetPosition(ACTION, UDim2.fromScale(0.72, 0.56))
	ContextActionService:BindAction(BURST_ACTION, function(_, state)
		if not eligible() then return Enum.ContextActionResult.Pass end
		if state == Enum.UserInputState.Begin then fireBurst() end
		return Enum.ContextActionResult.Sink
	end, true, Enum.KeyCode[Config.FlashBurstKey], Enum.KeyCode[Config.FlashBurstGamepadKey])
	ContextActionService:SetTitle(BURST_ACTION, "Clarão")
	ContextActionService:SetPosition(BURST_ACTION, UDim2.fromScale(0.85, 0.56))
end

local function unwatchCharacter(owner: Player)
	local connections = characterConnections[owner]
	if connections then for _, connection in connections do connection:Disconnect() end end
	characterConnections[owner] = nil
	for tool, toolOwner in visibleTools do
		if toolOwner == owner then
			Visuals.Remove(tool)
			local remotePose = remotePoses[tool]
			if remotePose then remotePose:Destroy(); remotePoses[tool] = nil end
			visibleTools[tool] = nil
		end
	end
	if owner == player then unequip() end
end

local function watchCharacter(owner: Player, character: Model)
	unwatchCharacter(owner)
	local function added(child: Instance)
		if not child:IsA("Tool") or child:GetAttribute("Lanterna") ~= true then return end
		visibleTools[child] = owner
		if owner == player and canUseRole() then
			equip(child)
		else
			local remotePose = Pose.new(false)
			remotePose:SetTool(child)
			remotePoses[child] = remotePose
		end
	end
	characterConnections[owner] = {
		character.ChildAdded:Connect(added),
		character.ChildRemoved:Connect(function(child)
			if child:IsA("Tool") then
				Visuals.Remove(child)
				local remotePose = remotePoses[child]
				if remotePose then remotePose:Destroy(); remotePoses[child] = nil end
				visibleTools[child] = nil
				if child == equipped then unequip() end
			end
		end),
	}
	for _, child in character:GetChildren() do added(child) end
end

local function watchPlayer(owner: Player)
	playerConnections[owner] = {
		owner.CharacterAdded:Connect(function(character) watchCharacter(owner, character) end),
		owner.CharacterRemoving:Connect(function() unwatchCharacter(owner) end),
	}
	if owner.Character then watchCharacter(owner, owner.Character) end
end

Remotes.Flashlight.OnClientEvent:Connect(function(kind, tool, enabled, result, sequence)
	if kind == "BurstResult" then
		if tool ~= equipped or sequence ~= burstSequence then return end
		burstPendingAt = nil
		hud:BurstFeedback(result, enabled == true)
		if enabled then
			burstReadyAt = workspace:GetServerTimeNow() + Config.FlashBurstCooldown
			pose:PlayBurst()
			burstFeedbackSound.PlaybackSpeed = if result == "Hit" then 1.8 else 0.65
			burstFeedbackSound:Play()
		else empty:Play() end
		return
	end
	if kind ~= "State" or tool ~= equipped or sequence ~= toggleSequence then return end
	predicted, pendingAt = enabled == true, nil
end)
player:GetAttributeChangedSignal("FlashBurstReadyAt"):Connect(function()
	if player:GetAttribute("FlashBurstReadyAt") == nil then burstReadyAt = 0 end
end)
Players.PlayerAdded:Connect(watchPlayer)
Players.PlayerRemoving:Connect(function(owner)
	unwatchCharacter(owner)
	for _, connection in playerConnections[owner] or {} do connection:Disconnect() end
	playerConnections[owner] = nil
end)
for _, owner in Players:GetPlayers() do watchPlayer(owner) end

player:GetAttributeChangedSignal("Role"):Connect(function()
	if not canUseRole() then unequip(); return end
	local character = player.Character
	if character then
		for _, child in character:GetChildren() do
			if child:IsA("Tool") and child:GetAttribute("Lanterna") == true then equip(child); break end
		end
	end
end)

-- Transform is batched after PreSimulation; RenderStep writes get replaced
-- by Animator before they move the arm. Remove the previous layer first so
-- unkeyed joints and throttled remote animators cannot accumulate rotation.
local beforeAnimation = RunService.PreAnimation:Connect(function()
	pose:Reset()
	for _, remotePose in remotePoses do remotePose:Reset() end
end)
local beforeSimulation = RunService.PreSimulation:Connect(function(dt)
	pose:Update(aimDirection, equipped ~= nil and eligible(), dt)
	for tool, remotePose in remotePoses do
		local direction = tool:GetAttribute("FlashlightDirection")
		local character = tool.Parent
		local root = character and character:FindFirstChild("HumanoidRootPart")
		local fallback = if root and root:IsA("BasePart") then root.CFrame.LookVector else Vector3.new(0, 0, -1)
		remotePose:Update(if typeof(direction) == "Vector3" then direction else fallback,
			tool:GetAttribute("FlashlightOn") == true, dt)
	end
end)
-- A luz/feixe (FlashlightVisuals) precisa ler a pose do braço JA aplicada
-- neste quadro. PreRender (onde o resto da lanterna roda, abaixo) acontece
-- ANTES de PreAnimation/PreSimulation no mesmo quadro -- ler a pose dali
-- pegava sempre o resultado do quadro ANTERIOR, e em giros rapidos a luz
-- ficava visivelmente atrasada em relacao ao modelo da lanterna.
-- PostSimulation roda depois da fisica, entao a pose ja assentou.
local afterSimulation = RunService.PostSimulation:Connect(function()
	local allowed = eligible()
	for tool, owner in visibleTools do
		local isLocal = owner == player
		local on = if isLocal then predicted and allowed else tool:GetAttribute("FlashlightOn") == true
		Visuals.Update(tool, on)
	end
	Visuals.UpdateImpacts(Players:GetPlayers())
end)

RunService:BindToRenderStep("SurvivorFlashlight", Enum.RenderPriority.Camera.Value + 2, function(dt)
	local now, camera = os.clock(), workspace.CurrentCamera
	local allowed = eligible()
	if equipped and camera then
		local character = player.Character :: Model
		if pendingAt and now - pendingAt > Config.AimTimeout then
			pendingAt, predicted = nil, equipped:GetAttribute("FlashlightOn") == true
		end
		if not allowed then predicted = false end
		-- Sample the camera every frame: a cached WORLD point jumps sideways
		-- when the shoulder camera turns or changes its collision offset.
		aimParams.FilterDescendantsInstances = { character }
		local ray = camera.CFrame.LookVector * (Config.LightRange + 16)
		local hit = workspace:Raycast(camera.CFrame.Position, ray, aimParams)
		local aimPoint = if hit then hit.Position else camera.CFrame.Position + ray
		local origin = equipped:FindFirstChild("FlashlightOrigin", true)
		local offset = if origin and origin:IsA("Attachment") then aimPoint - origin.WorldPosition else camera.CFrame.LookVector
		aimDirection = if offset.Magnitude > 0.1 and offset.Unit:Dot(camera.CFrame.LookVector) > 0.1
			then offset.Unit else camera.CFrame.LookVector
		if predicted and now - lastAim >= Config.AimSendInterval
			and (not lastDirection or lastDirection:Dot(aimDirection) < 0.9998 or now - lastAim >= Config.AimTimeout / 2) then
			lastAim, lastDirection = now, aimDirection
			Remotes.Flashlight:FireServer("Aim", equipped, aimDirection)
		end
	end
	if now - lastHUD >= 0.05 then
		lastHUD = now
		hud:Update(equipped ~= nil and canUseRole(),
			battery(), predicted and allowed, now, math.max(0, burstCooldown() - workspace:GetServerTimeNow()))
	end
	fx:Update(dt)
end)

script.Destroying:Connect(function()
	RunService:UnbindFromRenderStep("SurvivorFlashlight")
	beforeAnimation:Disconnect()
	beforeSimulation:Disconnect()
	afterSimulation:Disconnect()
	unequip()
	pose:Destroy()
	for tool, remotePose in remotePoses do
		remotePose:Destroy()
		remotePoses[tool] = nil
	end
	for owner in characterConnections do unwatchCharacter(owner) end
	for _, connections in playerConnections do for _, connection in connections do connection:Disconnect() end end
	hud.Gui:Destroy()
	fx:Destroy()
	Visuals.ClearImpacts()
	switch:Destroy()
	empty:Destroy()
	burstFeedbackSound:Destroy()
end)
