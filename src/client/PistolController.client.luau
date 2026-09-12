--!strict
-- Pistola OTS integrada ao PlayerModule R6 existente. Sem câmera/Animate duplicados.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local Remotes = require(ReplicatedStorage.Modules.Remotes)
local Ammo = require(ReplicatedStorage.Modules.Ammo)
local Rules = require(ReplicatedStorage.Modules.FirearmRules)
local Grip = require(ReplicatedStorage.Modules.PistolGrip)
local HUD = require(script.Parent.PistolHUD)
local PistolPose = require(script.Parent.PistolPose)
local player = Players.LocalPlayer
local hud = HUD.new(player:WaitForChild("PlayerGui"))
local animations = ReplicatedStorage:WaitForChild("WeaponAssets"):WaitForChild("Animations"):WaitForChild("PistolAnimations")

local tool: Tool? = nil
local character: Model? = nil
local humanoid: Humanoid? = nil
local tracks: { [string]: AnimationTrack } = {}
local toolConnections: { RBXScriptConnection } = {}
local characterConnections: { RBXScriptConnection } = {}
local aiming, reloading = false, false
local reloadStarted, reloadDuration, nextShot = 0, Rules.ReloadDuration, 0
local pending: { [number]: number } = {}
local sequence, shownAmmo = 0, 0
local kick, previousKick = 0, 0
local oldMouseIconEnabled = true
local generation = 0
local RELOAD_ANIMATION_SPEED = 0.82

-- AimFire: segura no frame 10; clique percorre 10–15–20 e volta à mira.
local pose: PistolPose.Controller? = nil
local touchAim = false
local windowFocused = true

local function disconnect(list: { RBXScriptConnection })
	for _, connection in list do connection:Disconnect() end
	table.clear(list)
end

local function blocked(): boolean
	return UserInputService:GetFocusedTextBox() ~= nil or player:GetAttribute("CursorLivre") == true
		or player:GetAttribute("InWaitingRoom") == true or player:GetAttribute("Eliminado") == true
		or player:GetAttribute("Amarrado") == true
		or humanoid == nil or (humanoid :: Humanoid).Health <= 0
		or (character ~= nil and ((character :: Model):GetAttribute("Amarrado") == true
			or (character :: Model):GetAttribute("GrabLocked") == true))
end

local function applyGrip()
	local current = tool
	if not current then return end
	current.Grip = Grip.Resolve(current, aiming)
end

local function setAim(value: boolean)
	value = value and tool ~= nil and not reloading and not blocked()
	if value == aiming then return end
	aiming = value
	applyGrip()
	if character then character:SetAttribute("FirearmAiming", value) end
	if pose then
		pose:SetAiming(value)
		return
	end
	local track = tracks.Aim
	if track then
		if value then track:Play(0.15) else track:Stop(0.15) end
	end
end

local function unequip()
	local old = tool
	if old and reloading then Remotes.FirearmReload:FireServer(old, "Cancel") end
	setAim(false)
	if old then old.Grip = Grip.Resolve(old, false) end
	reloading = false
	pose = nil
	touchAim = false
	disconnect(toolConnections)
	for _, track in tracks do track:Stop(0.12); track:Destroy() end
	table.clear(tracks)
	table.clear(pending)
	if old then UserInputService.MouseIconEnabled = oldMouseIconEnabled end
	tool = nil
	hud.Gui.Enabled = false
end

-- Brilho/fagulha saindo do cano ao disparar: usa os ParticleEmitters que a
-- própria Tool já traz em Components/Muzzle (FrontView/SideView), mais um
-- PointLight rápido pra dar o "flash" de luz.
local function muzzleFlash(current: Tool)
	local components = current:FindFirstChild("Components")
	local muzzle = components and components:FindFirstChild("Muzzle")
	if not muzzle or not muzzle:IsA("BasePart") then return end
	for _, attachmentName in { "FrontView", "SideView" } do
		local attachment = muzzle:FindFirstChild(attachmentName)
		if attachment then
			for _, emitter in attachment:GetChildren() do
				if emitter:IsA("ParticleEmitter") then
					emitter:Emit(8)
				end
			end
		end
	end
	local light = Instance.new("PointLight")
	light.Name = "TiroFlash"
	light.Color = Color3.fromRGB(255, 214, 140)
	light.Range = 12
	light.Brightness = 8
	light.Shadows = false
	light.Parent = muzzle
	task.delay(0.05, function() light:Destroy() end)
end

local function aimRay(): (Ray?, Vector2)
	local camera = Workspace.CurrentCamera
	if not camera then return nil, Vector2.zero end
	if UserInputService.TouchEnabled or UserInputService:GetLastInputType() == Enum.UserInputType.Gamepad1 then
		local center = camera.ViewportSize / 2
		return camera:ViewportPointToRay(center.X, center.Y), center
	end
	local mouse = UserInputService:GetMouseLocation()
	return camera:ScreenPointToRay(mouse.X, mouse.Y), mouse
end

local function fire()
	local current = tool
	if not current or blocked() or reloading or current:GetAttribute("FirearmReloading") == true or os.clock() < nextShot then return end
	if shownAmmo <= 0 then
		hud:Message(if Ammo.GetReserve(player, Ammo.TypeFor(current)) > 0 then "Pente vazio • R para recarregar" else "Sem munição • pegue uma caixa")
		nextShot = os.clock() + 0.25
		return
	end
	local ray = aimRay()
	if not ray then return end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.IgnoreWater = true
	local ignore: { Instance } = {}
	if character then table.insert(ignore, character) end
	local system = Workspace:FindFirstChild("System")
	if system then table.insert(ignore, system) end
	params.FilterDescendantsInstances = ignore
	local hit = Workspace:Raycast(ray.Origin, ray.Direction * Rules.Range, params)
	local point = if hit then hit.Position else ray.Origin + ray.Direction * Rules.Range
	sequence += 1
	pending[sequence] = os.clock()
	shownAmmo = math.max(0, shownAmmo - 1)
	nextShot = os.clock() + Rules.ShotInterval + 0.01
	Remotes.FirearmShoot:FireServer(current, point, aiming, sequence)
	muzzleFlash(current)
	if pose and aiming then
		pose:Fire()
	else
		local track = tracks.Fire
		if track then track:Play(0.02) end
	end
	kick = math.min(kick + Rules.RecoilDegrees * (if aiming then 0.75 else 1), 3)
end

local function tryReload()
	local current = tool
	if not current or reloading or blocked() then return end
	if shownAmmo >= Ammo.GetMagazineMax(current) then return end
	if Ammo.GetReserve(player, Ammo.TypeFor(current)) <= 0 then hud:Message("Sem munição reserva"); return end
	setAim(false)
	reloading = true
	reloadStarted = os.clock()
	Remotes.FirearmReload:FireServer(current, "Start")
end

local function equip(current: Tool)
	if tool == current then return end
	unequip()
	tool = current
	Grip.EnsureBase(current)
	current.Grip = Grip.Resolve(current, false)
	oldMouseIconEnabled = UserInputService.MouseIconEnabled
	shownAmmo = Ammo.GetMagazine(current)
	hud.Gui.Enabled = true
	local animator = humanoid and humanoid:FindFirstChildOfClass("Animator")
	if animator and humanoid and humanoid.RigType == Enum.HumanoidRigType.R6 then
		for name, priority in {
			Holster = Enum.AnimationPriority.Action,
			Aim = Enum.AnimationPriority.Action2,
			AimFire = Enum.AnimationPriority.Action2, -- substitui Aim/Fire quando presente (ver setAim/fire)
			Fire = Enum.AnimationPriority.Action3,
			Reload = Enum.AnimationPriority.Action4,
		} do
			local animation = animations:FindFirstChild(name)
			if animation and animation:IsA("Animation") then
				local ok, track = pcall(function() return animator:LoadAnimation(animation) end)
				if ok and track then
					track.Priority = priority
					track.Looped = name == "Holster" or name == "Aim"
					tracks[name] = track
				end
			end
		end
	end
	if tracks.AimFire then pose = PistolPose.new(tracks.AimFire) end
	if tracks.Holster then tracks.Holster:Play(0.15) end
	-- Diagnóstico de permissões sem travar tiro/recarga.
	task.delay(5, function()
		if tool ~= current then return end
		for name, track in tracks do
			if track.Length == 0 then
				warn("[Pistola OTS] Animação " .. name .. " não carregou. Confira a permissão do asset para esta experiência.")
			end
		end
	end)
	table.insert(toolConnections, current.Activated:Connect(fire))
	local ammo = Rules.Value(current, "Config", "Ammo")
	if ammo and (ammo:IsA("NumberValue") or ammo:IsA("IntValue")) then
		table.insert(toolConnections, ammo.Changed:Connect(function()
			if next(pending) == nil then shownAmmo = Ammo.GetMagazine(current) end
		end))
	end
end

Remotes.FirearmShoot.OnClientEvent:Connect(function(current: Tool, id: number, _accepted: boolean, magazine: number)
	if current ~= tool or pending[id] == nil then return end
	pending[id] = nil
	local outstanding = 0
	for _ in pending do outstanding += 1 end
	shownAmmo = math.max(0, magazine - outstanding)
end)

Remotes.FirearmReload.OnClientEvent:Connect(function(current: Tool, state: string, duration: number?)
	if current ~= tool then return end
	if state == "Start" then
		setAim(false)
		reloading, reloadStarted, reloadDuration = true, os.clock(), duration or Rules.ReloadDuration
		local track = tracks.Reload
		if track then
			track:Stop(0)
			track:Play(0.08, 1, RELOAD_ANIMATION_SPEED)
		end
	else
		reloading = false
		if tracks.Reload then tracks.Reload:Stop(0.12) end
		shownAmmo = Ammo.GetMagazine(current)
	end
end)
Remotes.FirearmDamage.OnClientEvent:Connect(function(kind: string) if tool then hud:Hitmarker(kind) end end)
Remotes.FirearmFeed.OnClientEvent:Connect(function(kind: string, name: string)
	if tool and kind == "Kill" then hud:Message(name .. " • neutralizado") end
end)

UserInputService.InputBegan:Connect(function(input: InputObject, processed: boolean)
	if processed or not tool then return end
	if input.KeyCode == Enum.KeyCode.R or input.KeyCode == Enum.KeyCode.ButtonX then
		tryReload()
	end
end)
UserInputService.WindowFocusReleased:Connect(function()
	windowFocused, touchAim = false, false
	setAim(false)
end)
UserInputService.WindowFocused:Connect(function() windowFocused = true end)

-- Input desejado e reprodução da pose são estados separados.
local function wantsToAim(): boolean
	return windowFocused and (touchAim or player:GetAttribute("PistolGripAimLock") == true
		or UserInputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton2)
		or UserInputService:IsGamepadButtonDown(Enum.UserInputType.Gamepad1, Enum.KeyCode.ButtonL2))
end
hud.Buttons[1].Activated:Connect(fire)
hud.Buttons[2].Activated:Connect(function() touchAim = not touchAim; setAim(touchAim) end)
hud.Buttons[3].Activated:Connect(tryReload)

local function watchCharacter(model: Model)
	generation += 1
	local currentGeneration = generation
	unequip()
	disconnect(characterConnections)
	character, humanoid = model, nil
	local found = model:WaitForChild("Humanoid", 10)
	if currentGeneration ~= generation or player.Character ~= model or not found or not found:IsA("Humanoid") then return end
	humanoid = found
	found:WaitForChild("Animator", 5)
	if currentGeneration ~= generation then return end
	table.insert(characterConnections, found.Died:Connect(unequip))
	table.insert(characterConnections, model.ChildAdded:Connect(function(child)
		if Rules.IsPistol(child) then equip(child :: Tool) end
	end))
	table.insert(characterConnections, model.ChildRemoved:Connect(function(child) if child == tool then unequip() end end))
	for _, child in model:GetChildren() do if Rules.IsPistol(child) then equip(child :: Tool); break end end
end
player.CharacterRemoving:Connect(function()
	generation += 1
	unequip()
	disconnect(characterConnections)
	character, humanoid = nil, nil
end)
player.CharacterAdded:Connect(watchCharacter)
if player.Character then task.spawn(watchCharacter, player.Character) end

RunService.PreAnimation:Connect(function(dt: number)
	if not tool then return end
	setAim(wantsToAim())
	applyGrip()
	if pose then pose:Update(dt) end
end)

RunService:BindToRenderStep("PistolFeedback", Enum.RenderPriority.Camera.Value + 5, function(dt: number)
	-- Recuo angular aditivo; PlayerModule mantém colisão, zoom e posição da câmera.
	kick *= math.exp(-13 * dt)
	local camera = Workspace.CurrentCamera
	if camera and camera.CameraType ~= Enum.CameraType.Scriptable then
		camera.CFrame *= CFrame.Angles(math.rad(kick - previousKick), 0, 0)
	end
	previousKick = kick
	local current = tool
	if not current then return end
	local isBlocked = blocked()
	UserInputService.MouseIconEnabled = if isBlocked then oldMouseIconEnabled else false
	if reloading and os.clock() - reloadStarted > reloadDuration + 3 then
		Remotes.FirearmReload:FireServer(current, "Cancel")
		reloading = false
		if tracks.Reload then tracks.Reload:Stop(0.1) end
	end
	if reloading and tracks.Reload and tracks.Reload.IsPlaying then
		tracks.Reload:AdjustSpeed(RELOAD_ANIMATION_SPEED)
	end
	for id, sent in pending do
		if os.clock() - sent > 3 then pending[id] = nil; shownAmmo = Ammo.GetMagazine(current) end
	end
	local _, position = aimRay()
	hud:Update(position, shownAmmo, Ammo.GetReserve(player, Ammo.TypeFor(current)), aiming, kick,
		reloading, (os.clock() - reloadStarted) / reloadDuration, current:GetAttribute("LobbyTestWeapon") == true,
		UserInputService.TouchEnabled, isBlocked)
end)
