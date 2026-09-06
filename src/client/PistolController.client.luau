--!strict
--[[
	PistolController
	Tiro da pistola SEM dono da câmera. Substitui o CameraWeapon/WeaponController
	(sistema OTS), que foi removido porque o "Ultimate R6 Movement System" traz
	o próprio PlayerModule/câmera e os dois brigavam pelo CFrame do Camera.

	O QUE ESTE SCRIPT FAZ (e o que NÃO faz)
	  FAZ: clique esquerdo atira, R recarrega, toca as animações R6 da pistola
	  (WeaponAssets/Animations/PistolAnimations), mira pelo cursor do mouse,
	  aplica spread, e conversa com o MESMO servidor de antes (FirearmServer:
	  munição, dano, som, muzzle flash, tracer, hitmarker, kill feed).
	  NÃO FAZ: mexer na câmera, no WalkSpeed, no shift lock nem na mira de
	  ombro -- tudo isso agora é do pacote de movimento.

	MIRA: a câmera é a padrão do Roblox (PlayerModule do pacote), então o
	ponto de mira é onde o CURSOR está, via Camera:ScreenPointToRay. Não tem
	mira "por cima do ombro"; é tiro de quadril com cursor, como Tool comum.

	RECARGA: dirigida pelos markers da animação (Start/MagOut/MagIn/BoltPull/
	BoltRelease/End), igual antes -- é o FirearmServer que move munição da
	RESERVA (AmmoSystem) pro pente. Sem reserva, nem começa.

	HUD: contador "PENTE | RESERVA" no canto inferior direito (o StatusHUD que
	tinha isso foi removido junto com as barras de vida/fôlego, que agora são
	as do pacote -- PixelHealthGui e PixelStaminaGui).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Remotes = require(ReplicatedStorage.Modules.Remotes)
local SafeWait = require(ReplicatedStorage.Modules.SafeWait)
local Ammo = require(ReplicatedStorage.Modules.Ammo)

local LocalPlayer = Players.LocalPlayer
local playerGui = LocalPlayer:WaitForChild("PlayerGui")

local WeaponAssets = SafeWait.Child(ReplicatedStorage, "WeaponAssets")
local AnimationsFolder = SafeWait.Child(WeaponAssets, "Animations")

local MAX_RANGE = 1000
local SPREAD_DEGREES_PER_UNIT = 0.35 -- Settings/Config/Spread -> graus de meio-cone
local RELOAD_MARKERS = { "Start", "MagOut", "MagIn", "BoltPull", "BoltRelease", "End", "ShellIn" }
local RELOAD_FALLBACK_TIME = 1.5 -- se a animação não tiver markers

local rng = Random.new()

--------------------------------------------------------------------------------
-- Estado
--------------------------------------------------------------------------------

local tool: Tool? = nil
local animator: Animator? = nil
local tracks: { [string]: AnimationTrack } = {}
local connections: { RBXScriptConnection } = {}
local reloading = false
local cooldownUntil = 0

-- Declarada aqui porque onEquip() liga o Tool.Activated nela, mas o corpo só
-- vem lá embaixo (precisa dos helpers de leitura da Tool).
local fire: () -> ()

local function disconnectAll()
	for _, connection in connections do
		connection:Disconnect()
	end
	table.clear(connections)
end

--------------------------------------------------------------------------------
-- Leitura da Tool (mesma estrutura do OTS, nada mudou nas armas)
--------------------------------------------------------------------------------

local function isFirearm(instance: Instance): boolean
	if not instance:IsA("Tool") then
		return false
	end
	local flag = instance:FindFirstChild("Weapon")
	if flag and flag:IsA("BoolValue") and flag.Value then
		return true
	end
	return instance:GetAttribute("Firearm") == true
end

local function configValue(current: Tool, name: string): ValueBase?
	local settings = current:FindFirstChild("Settings")
	local config = settings and settings:FindFirstChild("Config")
	local value = config and config:FindFirstChild(name)
	return if value and value:IsA("ValueBase") then value else nil
end

local function configNumber(current: Tool, name: string, default: number): number
	local value = configValue(current, name)
	if value and (value:IsA("NumberValue") or value:IsA("IntValue")) then
		return value.Value
	end
	return default
end

local function configBool(current: Tool, name: string, default: boolean): boolean
	local value = configValue(current, name)
	if value and value:IsA("BoolValue") then
		return value.Value
	end
	return default
end

local function getMuzzle(current: Tool): BasePart?
	local components = current:FindFirstChild("Components")
	local muzzle = components and components:FindFirstChild("Muzzle")
	return if muzzle and muzzle:IsA("BasePart") then muzzle else nil
end

-- Conjunto de animação: Settings/Animations/{Pistol,Shotgun,Rifle}.
local function animationSetName(current: Tool): string
	local settings = current:FindFirstChild("Settings")
	local anims = settings and settings:FindFirstChild("Animations")
	for _, name in { "Pistol", "Shotgun", "Rifle" } do
		local flag = anims and anims:FindFirstChild(name)
		if flag and flag:IsA("BoolValue") and flag.Value then
			return name
		end
	end
	return "Pistol"
end

--------------------------------------------------------------------------------
-- Equipar / desequipar
--------------------------------------------------------------------------------

local function stopTracks()
	for name, track in tracks do
		track:Stop(0.15)
		track:Destroy()
		tracks[name] = nil
	end
end

local function loadTracks(current: Tool)
	local currentAnimator = animator
	local folder = AnimationsFolder:FindFirstChild(animationSetName(current) .. "Animations")
	if not currentAnimator or not folder then
		return
	end

	for name, priority in
		{
			Holster = Enum.AnimationPriority.Action2,
			Fire = Enum.AnimationPriority.Action4,
			Reload = Enum.AnimationPriority.Action4,
		} :: { [string]: Enum.AnimationPriority }
	do
		local animation = folder:FindFirstChild(name)
		if animation and animation:IsA("Animation") then
			local ok, track = pcall(function()
				return currentAnimator:LoadAnimation(animation)
			end)
			if ok and track then
				track.Priority = priority
				track.Looped = name == "Holster"
				tracks[name] = track
			end
		end
	end
end

local function setReloading(value: boolean)
	reloading = value
end

local function onUnequip()
	disconnectAll()
	stopTracks()
	setReloading(false)
	tool = nil
end

local function onEquip(current: Tool)
	if tool == current then
		return
	end
	onUnequip()
	tool = current

	loadTracks(current)

	local holster = tracks.Holster
	if holster then
		holster:Play(0.15) -- pose de "arma na mão"
	end

	-- Markers da recarga -> servidor (sons, pente caindo, munição).
	local reload = tracks.Reload
	if reload then
		for _, stage in RELOAD_MARKERS do
			table.insert(
				connections,
				reload:GetMarkerReachedSignal(stage):Connect(function()
					Remotes.FirearmReload:FireServer(stage)
					if stage == "End" or stage == "ShellIn" then
						setReloading(false)
					end
				end)
			)
		end
		table.insert(
			connections,
			reload.Stopped:Connect(function()
				-- Animação sem marker "End": fecha a recarga mesmo assim.
				if reloading then
					Remotes.FirearmReload:FireServer("End")
					setReloading(false)
				end
			end)
		)
	end

	table.insert(connections, current.Activated:Connect(function()
		fire()
	end))
end

--------------------------------------------------------------------------------
-- Tiro
--------------------------------------------------------------------------------

local function aimPoint(origin: Vector3, ignore: { Instance }): Vector3
	local camera = Workspace.CurrentCamera
	if not camera then
		return origin + Vector3.new(0, 0, -MAX_RANGE)
	end

	local mouse = UserInputService:GetMouseLocation()
	local unitRay = camera:ScreenPointToRay(mouse.X, mouse.Y)

	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.IgnoreWater = true
	params.FilterDescendantsInstances = ignore

	local hit = Workspace:Raycast(unitRay.Origin, unitRay.Direction * MAX_RANGE, params)
	return if hit then hit.Position else unitRay.Origin + unitRay.Direction * MAX_RANGE
end

function fire()
	local current = tool
	local character = LocalPlayer.Character
	if not current or not character or reloading then
		return
	end
	if os.clock() < cooldownUntil then
		return
	end
	if configBool(current, "Reloading", false) then
		return -- servidor ainda recarregando
	end

	local ammoValue = configValue(current, "Ammo")
	if ammoValue and (ammoValue :: NumberValue).Value <= 0 then
		return -- pente vazio
	end

	local muzzle = getMuzzle(current)
	local head = character:FindFirstChild("Head")
	local origin = if muzzle
		then muzzle.Position
		elseif head and head:IsA("BasePart") then head.Position
		else character:GetPivot().Position

	local ignore: { Instance } = { character, current }
	local system = Workspace:FindFirstChild("System")
	if system then
		table.insert(ignore, system)
	end
	local dropped = Workspace:FindFirstChild("ArmasNoChao")
	if dropped then
		table.insert(ignore, dropped)
	end

	local target = aimPoint(origin, ignore)
	local baseDirection = target - origin
	if baseDirection.Magnitude < 1e-3 then
		baseDirection = Vector3.new(0, 0, -1)
	end

	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.IgnoreWater = true
	params.FilterDescendantsInstances = ignore

	local spread = configNumber(current, "Spread", 3) * SPREAD_DEGREES_PER_UNIT
	local bullets = math.max(1, math.floor(configNumber(current, "NumberOfBullets", 1)))

	for _ = 1, bullets do
		local cone = CFrame.lookAt(origin, origin + baseDirection.Unit)
			* CFrame.Angles(math.rad(rng:NextNumber(-spread, spread)), math.rad(rng:NextNumber(-spread, spread)), 0)
		local direction = cone.LookVector
		local result = Workspace:Raycast(origin, direction * MAX_RANGE, params)

		if result then
			local model = result.Instance:FindFirstAncestorOfClass("Model")
			if model and model:FindFirstChildOfClass("Humanoid") then
				Remotes.FirearmDamage:FireServer(result.Instance)
			end
			Remotes.FirearmHit:FireServer(result.Position, result.Instance, result.Normal)
		else
			Remotes.FirearmHit:FireServer(origin + direction * MAX_RANGE, nil, nil)
		end
	end

	-- Munição, som da arma e muzzle flash são autoridade do servidor.
	Remotes.FirearmShoot:FireServer()

	local fireTrack = tracks.Fire
	if fireTrack then
		fireTrack:Play(0.02)
	end

	cooldownUntil = os.clock() + math.max(configNumber(current, "Delay", 0.1), 0.02)
end

--------------------------------------------------------------------------------
-- Recarga
--------------------------------------------------------------------------------

local function tryReload()
	local current = tool
	if not current or reloading then
		return
	end
	if configNumber(current, "Ammo", 0) >= configNumber(current, "MaxAmmo", 0) then
		return -- pente cheio
	end
	if Ammo.GetReserve(LocalPlayer, Ammo.TypeFor(current)) <= 0 then
		return -- sem reserva: o servidor não teria o que entregar
	end

	setReloading(true)

	local reload = tracks.Reload
	if reload then
		reload:Play(0.1)
	else
		-- Sem animação: recarga simulada, o servidor decide a munição.
		Remotes.FirearmReload:FireServer("Start")
		task.delay(RELOAD_FALLBACK_TIME, function()
			if reloading and tool == current then
				Remotes.FirearmReload:FireServer("End")
				setReloading(false)
			end
		end)
	end
end

UserInputService.InputBegan:Connect(function(input: InputObject, gameProcessed: boolean)
	if gameProcessed then
		return
	end
	if input.KeyCode == Enum.KeyCode.R then
		tryReload()
	end
end)

--------------------------------------------------------------------------------
-- Personagem: descobrir a arma equipada
--------------------------------------------------------------------------------

local function watchCharacter(character: Model)
	onUnequip()

	local humanoid = character:FindFirstChildOfClass("Humanoid") or character:WaitForChild("Humanoid", 10)
	if humanoid and humanoid:IsA("Humanoid") then
		local found = humanoid:FindFirstChildOfClass("Animator") or humanoid:WaitForChild("Animator", 10)
		animator = if found and found:IsA("Animator") then found else nil
	end

	character.ChildAdded:Connect(function(child)
		if isFirearm(child) then
			onEquip(child :: Tool)
		end
	end)
	character.ChildRemoved:Connect(function(child)
		if child == tool then
			onUnequip()
		end
	end)

	for _, child in character:GetChildren() do
		if isFirearm(child) then
			onEquip(child :: Tool)
			break
		end
	end
end

LocalPlayer.CharacterAdded:Connect(watchCharacter)
if LocalPlayer.Character then
	watchCharacter(LocalPlayer.Character)
end

--------------------------------------------------------------------------------
-- HUD de munição (PENTE | RESERVA)
--------------------------------------------------------------------------------

local gui = Instance.new("ScreenGui")
gui.Name = "AmmoHUD"
gui.ResetOnSpawn = false
gui.DisplayOrder = 7
gui.Enabled = false
gui.Parent = playerGui

local row = Instance.new("Frame")
row.AnchorPoint = Vector2.new(1, 1)
row.Position = UDim2.new(1, -24, 1, -24)
row.Size = UDim2.fromOffset(170, 34)
row.BackgroundTransparency = 1
row.Parent = gui

local magLabel = Instance.new("TextLabel")
magLabel.Size = UDim2.fromScale(1, 1)
magLabel.BackgroundTransparency = 1
magLabel.Font = Enum.Font.GothamBold
magLabel.TextSize = 28
magLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
magLabel.TextStrokeTransparency = 0.4
magLabel.TextXAlignment = Enum.TextXAlignment.Right
magLabel.Text = ""
magLabel.Parent = row

task.spawn(function()
	while true do
		task.wait(0.1)
		local current = tool
		gui.Enabled = current ~= nil
		if current then
			local magazine = math.floor(Ammo.GetMagazine(current))
			local reserve = math.floor(Ammo.GetReserve(LocalPlayer, Ammo.TypeFor(current)))
			magLabel.Text = string.format("%d  |  %d", magazine, reserve)
			magLabel.TextColor3 = if magazine <= 0
				then Color3.fromRGB(235, 85, 70)
				else Color3.fromRGB(255, 255, 255)
		end
	end
end)
