--!strict
-- Digital's OTS Patch2 adaptado ao jogo atual.
-- Mantém o PlayerModule, Animate, sprint, crouch, stamina e hotbar existentes.
local Players = game:GetService("Players")
local Debris = game:GetService("Debris")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Remotes = require(ReplicatedStorage.Modules.Remotes)
local Ammo = require(ReplicatedStorage.Modules.OTSAmmo)
local Rules = require(ReplicatedStorage.Modules.OTSRules)
local HUD = require(script.Parent.OTSHUD)

local player = Players.LocalPlayer
local lastFire = -math.huge
local hud = HUD.new(player:WaitForChild("PlayerGui") :: PlayerGui)
local assets = ReplicatedStorage:WaitForChild("WeaponAssets")
local pistolAnimations = assets:WaitForChild("Animations"):WaitForChild("PistolAnimations")
local pistolAudios = assets:WaitForChild("Audios")

local EXPECTED_ANIMATION_IDS = {
	Fire = "rbxassetid://17861277580",
	Holster = "rbxassetid://17837420732",
	Reload = "rbxassetid://17837428175",
	Aim = "rbxassetid://97722809924272",
}

local character: Model? = nil
local humanoid: Humanoid? = nil
local tool: Tool? = nil
local tracks: { [string]: AnimationTrack } = {}
local toolConnections: { RBXScriptConnection } = {}
local characterConnections: { RBXScriptConnection } = {}
local markerConnections: { RBXScriptConnection } = {}
local pending: { [number]: number } = {}
local sequence = 0
local shownAmmo = 0
local aiming = false
local touchAim = false
local reloading = false
local reloadRequested = false
local reloadStarted = 0
local generation = 0
local recoilPosition = Vector2.zero
local recoilVelocity = Vector2.zero
local previousRecoil = Vector2.zero

local function disconnect(list: { RBXScriptConnection })
	for _, connection in list do connection:Disconnect() end
	table.clear(list)
end

local function blocked(): boolean
	local model = character
	local human = humanoid
	local currentTool = tool
	local waitingRoomBlocked = player:GetAttribute("InWaitingRoom") == true
		and not (currentTool and currentTool:GetAttribute("LobbyTestWeapon") == true)
	return UserInputService:GetFocusedTextBox() ~= nil
		or player:GetAttribute("CursorLivre") == true
		or waitingRoomBlocked
		or player:GetAttribute("Eliminado") == true
		or player:GetAttribute("Amarrado") == true
		or not model or not human or human.Health <= 0
		or model:GetAttribute("Eliminado") == true
		or model:GetAttribute("Amarrado") == true
		or model:GetAttribute("GrabLocked") == true
		or model:GetAttribute("PowerStunned") == true
		or model:GetAttribute("ShadowRushBusy") == true
end

local function playLocalSound(folderName: string, soundName: string)
	local folder = pistolAudios:FindFirstChild(folderName)
	local template = folder and folder:FindFirstChild(soundName)
	if not template or not template:IsA("Sound") then return end
	local sound = template:Clone()
	sound.Parent = Workspace.CurrentCamera or Workspace
	sound:Play()
	Debris:AddItem(sound, 5)
end

local function setAim(value: boolean)
	value = value and tool ~= nil and not reloading and not reloadRequested and not blocked()
	if value == aiming then return end
	aiming = value
	if character then character:SetAttribute("FirearmAiming", value) end
	hud:SetAiming(value)
	local track = tracks.Aim
	if track then
		if value then track:Play(0.18) else track:Stop(0.18) end
	end
	playLocalSound("Misc", if value then "AimIn" else "AimOut")
end

local function unequip()
	local previous = tool
	if previous and (reloading or reloadRequested) then Remotes.FirearmReload:FireServer(previous, "Cancel") end
	setAim(false)
	disconnect(toolConnections)
	disconnect(markerConnections)
	for _, track in tracks do
		track:Stop(0.12)
		track:Destroy()
	end
	table.clear(tracks)
	table.clear(pending)
	tool = nil
	if character then character:SetAttribute("FirearmAimFOV", nil) end
	reloading = false
	reloadRequested = false
	touchAim = false
	hud:SetEnabled(false)
end

local function aimPoint(): Vector3?
	local camera = Workspace.CurrentCamera
	if not camera then return nil end
	local center = camera.ViewportSize / 2
	local ray = camera:ViewportPointToRay(center.X, center.Y)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.IgnoreWater = true
	local ignore: { Instance } = {}
	if character then table.insert(ignore, character) end
	local system = Workspace:FindFirstChild("System")
	if system and (not tool or not Rules.IsFoundation(tool)) then table.insert(ignore, system) end
	params.FilterDescendantsInstances = ignore
	local hit = Workspace:Raycast(ray.Origin, ray.Direction * (if tool then Rules.AttackRange(tool) else Rules.Range), params)
	return if hit then hit.Position else ray.Origin + ray.Direction * (if tool then Rules.AttackRange(tool) else Rules.Range)
end

local function fire()
	local current = tool
	if not current or (not Rules.IsFoundation(current) and not aiming) or blocked() or reloading or reloadRequested
		or current:GetAttribute("FirearmReloading") == true then return end
	if shownAmmo <= 0 or os.clock() - lastFire < Rules.ShotInterval(current) then return end
	local point = aimPoint()
	if not point then return end
	lastFire = os.clock()
	sequence += 1
	pending[sequence] = os.clock()
	shownAmmo = math.max(0, shownAmmo - 1)
	Remotes.FirearmShoot:FireServer(current, point, aiming, sequence)
	local fireTrack = tracks.Fire
	if fireTrack then
		fireTrack:Stop(0)
		fireTrack:Play(0.02)
	end
	local recoil = Rules.Recoil(current)
	recoilVelocity += Vector2.new(recoil * 5.5, math.random(-100, 100) / 100 * recoil * 1.8)
	hud:Shove(Rules.Number(current, "Config", "CrosshairShove", 2.1) * 5)
end

local function tryReload()
	local current = tool
	if not current or not Rules.ReloadEnabled(current) or reloading or reloadRequested or blocked() then return end
	if shownAmmo >= Ammo.GetMagazineMax(current) or Ammo.GetReserve(player, Ammo.TypeFor(current)) <= 0 then return end
	setAim(false)
	reloadRequested = true
	Remotes.FirearmReload:FireServer(current, "Start")
end

local function loadTrack(animator: Animator, name: string, priority: Enum.AnimationPriority, looped: boolean)
	local animation = pistolAnimations:FindFirstChild(name)
	local expectedId = EXPECTED_ANIMATION_IDS[name]
	if not animation or not animation:IsA("Animation") then
		if not expectedId then
			warn("[Digital's OTS] Animação ausente: " .. name)
			return
		end
		local fallback = Instance.new("Animation")
		fallback.Name = name
		fallback.AnimationId = expectedId
		animation = fallback
	elseif expectedId and animation.AnimationId ~= expectedId then
		warn(string.format("[Digital's OTS] %s estava com AnimationId '%s'; restaurando para '%s'.",
			name, animation.AnimationId, expectedId))
		animation.AnimationId = expectedId
	end
	local ok, result = pcall(function() return animator:LoadAnimation(animation) end)
	if not ok or not result then
		warn("[Digital's OTS] Falha ao carregar " .. name .. ": " .. tostring(result))
		return
	end
	result.Priority = priority
	result.Looped = looped
	tracks[name] = result
end

local function equip(current: Tool)
	if tool == current then return end
	unequip()
	tool = current
	if character then character:SetAttribute("FirearmAimFOV", Rules.AimFOV(current)) end
	shownAmmo = Ammo.GetMagazine(current)
	hud:SetEnabled(true)
	hud.Buttons.Reload.Visible = Rules.ReloadEnabled(current)
	local animator = humanoid and humanoid:FindFirstChildOfClass("Animator")
	if not animator and humanoid then animator = Instance.new("Animator", humanoid) end
	if animator and Rules.AnimationsEnabled(current) then
		loadTrack(animator, "Holster", Enum.AnimationPriority.Action, true)
		loadTrack(animator, "Aim", Enum.AnimationPriority.Action2, true)
		loadTrack(animator, "Fire", Enum.AnimationPriority.Action3, false)
		loadTrack(animator, "Reload", Enum.AnimationPriority.Action4, false)
	end
	if tracks.Holster then tracks.Holster:Play(0.18) end
	local reloadTrack = tracks.Reload
	if reloadTrack then
		for _, marker in { "Start", "MagOut", "MagIn", "BoltPull", "BoltRelease", "End" } do
			table.insert(markerConnections, reloadTrack:GetMarkerReachedSignal(marker):Connect(function()
				local equippedTool = tool
				if equippedTool == current and reloading then
					Remotes.FirearmReload:FireServer(equippedTool, "Marker", marker)
				end
			end))
		end
	end
	table.insert(toolConnections, current.Activated:Connect(fire))
	local ammoValue = Rules.Value(current, "Config", "Ammo")
	if ammoValue and (ammoValue:IsA("NumberValue") or ammoValue:IsA("IntValue")) then
		table.insert(toolConnections, ammoValue.Changed:Connect(function()
			if next(pending) == nil then shownAmmo = Ammo.GetMagazine(current) end
		end))
	end
	task.delay(5, function()
		if tool ~= current then return end
		for name, track in tracks do
			if track.Length == 0 then
				warn("[Digital's OTS] " .. name .. " não carregou; troque/autorize o AnimationId em WeaponAssets/Animations.")
			end
		end
	end)
end

Remotes.FirearmShoot.OnClientEvent:Connect(function(current: Tool, id: number, accepted: boolean, magazine: number)
	if current ~= tool or pending[id] == nil then return end
	pending[id] = nil
	local outstanding = 0
	for _ in pending do outstanding += 1 end
	shownAmmo = math.max(0, magazine - outstanding)
	if not accepted then recoilVelocity *= 0.35 end
end)

Remotes.FirearmReload.OnClientEvent:Connect(function(current: Tool, state: string, duration: number?)
	if current ~= tool then return end
	reloadRequested = false
	if state == "Start" then
		setAim(false)
		reloading = true
		reloadStarted = os.clock()
		local track = tracks.Reload
		if track then
			track:Stop(0)
			track:Play(0.08)
		end
	else
		reloading = false
		if tracks.Reload then tracks.Reload:Stop(0.12) end
		shownAmmo = Ammo.GetMagazine(current)
	end
end)

Remotes.FirearmDamage.OnClientEvent:Connect(function(kind: string)
	if tool then hud:Hitmarker(kind) end
end)
Remotes.FirearmFeed.OnClientEvent:Connect(function(kind: string, name: string)
	if tool then hud:Feed(kind, name) end
end)

UserInputService.InputBegan:Connect(function(input: InputObject, processed: boolean)
	if processed or not tool then return end
	if input.UserInputType == Enum.UserInputType.MouseButton2 or input.KeyCode == Enum.KeyCode.ButtonL2 then
		setAim(true)
	elseif input.KeyCode == Enum.KeyCode.L then
		fire()
	elseif input.KeyCode == Enum.KeyCode.R or input.KeyCode == Enum.KeyCode.ButtonX then
		tryReload()
	end
end)
UserInputService.InputEnded:Connect(function(input: InputObject)
	if input.UserInputType == Enum.UserInputType.MouseButton2 or input.KeyCode == Enum.KeyCode.ButtonL2 then
		setAim(false)
	end
end)
UserInputService.WindowFocusReleased:Connect(function()
	touchAim = false
	setAim(false)
end)

hud.Buttons.Fire.Activated:Connect(fire)
hud.Buttons.Aim.Activated:Connect(function()
	touchAim = not touchAim
	setAim(touchAim)
end)
hud.Buttons.Reload.Activated:Connect(tryReload)

local function watchCharacter(model: Model)
	generation += 1
	local currentGeneration = generation
	unequip()
	disconnect(characterConnections)
	character = model
	humanoid = nil
	local found = model:WaitForChild("Humanoid", 10)
	if currentGeneration ~= generation or player.Character ~= model or not found or not found:IsA("Humanoid") then return end
	humanoid = found
	if not found:FindFirstChildOfClass("Animator") then Instance.new("Animator", found) end
	table.insert(characterConnections, found.Died:Connect(unequip))
	table.insert(characterConnections, model.ChildAdded:Connect(function(child)
		if Rules.IsWeapon(child) then equip(child :: Tool) end
	end))
	table.insert(characterConnections, model.ChildRemoved:Connect(function(child)
		if child == tool then unequip() end
	end))
	for _, child in model:GetChildren() do
		if Rules.IsWeapon(child) then equip(child :: Tool); break end
	end
end

player.CharacterRemoving:Connect(function()
	generation += 1
	unequip()
	disconnect(characterConnections)
	character = nil
	humanoid = nil
end)
player.CharacterAdded:Connect(watchCharacter)
if player.Character then task.spawn(watchCharacter, player.Character) end

RunService:BindToRenderStep("DigitalOTSFeedback", Enum.RenderPriority.Camera.Value + 5, function(dt: number)
	local clamped = math.min(dt, 0.05)
	recoilVelocity += (-recoilPosition * 70 - recoilVelocity * 14) * clamped
	recoilPosition += recoilVelocity * clamped
	local delta = recoilPosition - previousRecoil
	local camera = Workspace.CurrentCamera
	if camera and camera.CameraType ~= Enum.CameraType.Scriptable then
		camera.CFrame *= CFrame.Angles(math.rad(delta.X), math.rad(delta.Y), 0)
	end
	previousRecoil = recoilPosition
	local current = tool
	if not current then return end
	if aiming and blocked() then setAim(false) end
	for id, sentAt in pending do
		if os.clock() - sentAt > 3 then pending[id] = nil end
	end
	if reloading and os.clock() - reloadStarted > Rules.ReloadDuration + 3 then
		Remotes.FirearmReload:FireServer(current, "Cancel")
		reloading = false
	end
	hud:Update(shownAmmo, if Rules.ReloadEnabled(current) then Ammo.GetReserve(player, Ammo.TypeFor(current)) else 0, reloading,
		UserInputService.TouchEnabled, blocked())
end)
