--!strict
-- Glock17 do Digital's OTS: um pedido = um raycast no servidor.
-- Nenhum remote aceita dano/impacto escolhido pelo cliente.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local Debris = game:GetService("Debris")

local GameConfig = require(ReplicatedStorage.Modules.GameConfig)
local Remotes = require(ReplicatedStorage.Modules.Remotes)
local Rules = require(ReplicatedStorage.Modules.FirearmRules)
local Ammo = require(ReplicatedStorage.Modules.Ammo)
local WeaponEffects = require(ReplicatedStorage.Modules.WeaponEffects)
local DamageSystem = require(script.Parent.DamageSystem)
local PowerStatus = require(script.Parent.SurvivorPowerStatus)
local AmmoSystem = require(script.Parent.AmmoSystem)
local assets = ReplicatedStorage:WaitForChild("WeaponAssets")
local toolsFolder = assets:WaitForChild("Tools")
local audios = assets:WaitForChild("Audios")
local FirearmServer = {}
local initialized = false
local rng = Random.new()
local lastShot: { [Player]: number } = {}
type Reload = { tool: Tool, connections: { RBXScriptConnection } }
local reloads: { [Player]: Reload } = {}

local function alive(player: Player): boolean
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	return character ~= nil and humanoid ~= nil and humanoid.Health > 0
		and character:GetAttribute("Eliminado") ~= true and character:FindFirstChild("Dead") == nil
		and character:GetAttribute("Amarrado") ~= true and player:GetAttribute("Eliminado") ~= true
		and player:GetAttribute("Amarrado") ~= true
		and player:GetAttribute("InWaitingRoom") ~= true
end

local function equipped(player: Player, candidate: unknown): Tool?
	if typeof(candidate) ~= "Instance" or not Rules.IsPistol(candidate :: Instance) or not alive(player) then return nil end
	local tool = candidate :: Tool
	return if tool.Parent == player.Character then tool else nil
end

local function setReloading(tool: Tool, value: boolean)
	local flag = Rules.Value(tool, "Config", "Reloading")
	if flag and flag:IsA("BoolValue") then flag.Value = value end
	tool:SetAttribute("FirearmReloading", value)
end

local function magazineVisible(tool: Tool, visible: boolean)
	local components = tool:FindFirstChild("Components")
	local mag = components and components:FindFirstChild("Mag")
	if mag and mag:IsA("BasePart") then mag.Transparency = if visible then 0 else 1 end
end

local function finishReload(player: Player, completed: boolean)
	local state = reloads[player]
	if not state then return end
	reloads[player] = nil
	for _, connection in state.connections do connection:Disconnect() end
	setReloading(state.tool, false)
	magazineVisible(state.tool, true)
	if player.Parent == Players then
		Remotes.FirearmReload:FireClient(player, state.tool, if completed then "Done" else "Cancelled")
	end
end

local function handleSound(tool: Tool, name: string)
	local handle = tool:FindFirstChild("Handle")
	local sound = handle and handle:FindFirstChild(name)
	if sound and sound:IsA("Sound") then sound:Play() end
end

local function dropMagazine(tool: Tool)
	local components = tool:FindFirstChild("Components")
	local mag = components and components:FindFirstChild("Mag")
	if not mag or not mag:IsA("BasePart") then return end
	local clone = mag:Clone()
	for _, child in clone:GetDescendants() do
		if child:IsA("JointInstance") or child:IsA("WeldConstraint") then child:Destroy() end
	end
	clone.Anchored, clone.CanCollide, clone.CanTouch, clone.CanQuery = false, false, false, false
	clone.Transparency = 0
	clone.Parent = Workspace:FindFirstChild("System") or Workspace
	Debris:AddItem(clone, 3)
	magazineVisible(tool, false)
end

local function onReload(player: Player, candidate: unknown, action: unknown)
	if action == "Cancel" then
		local state = reloads[player]
		if state and state.tool == candidate then finishReload(player, false) end
		return
	end
	if player.Character and player.Character:GetAttribute("ShadowRushBusy") == true then return end
	if action ~= "Start" then return end
	local tool = equipped(player, candidate)
	if not tool or reloads[player] then return end
	local ammo = Rules.Value(tool, "Config", "Ammo")
	if not ammo or not (ammo:IsA("NumberValue") or ammo:IsA("IntValue")) then return end
	if Rules.ReloadAmount(ammo.Value, Ammo.GetMagazineMax(tool), Ammo.GetReserve(player, Ammo.TypeFor(tool))) <= 0 then
		Remotes.FirearmReload:FireClient(player, tool, "Cancelled")
		return
	end
	local state: Reload = { tool = tool, connections = {} }
	reloads[player] = state
	setReloading(tool, true)
	table.insert(state.connections, tool.AncestryChanged:Connect(function()
		if tool.Parent ~= player.Character then finishReload(player, false) end
	end))
	local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	if humanoid then table.insert(state.connections, humanoid.Died:Connect(function() finishReload(player, false) end)) end
	Remotes.FirearmReload:FireClient(player, tool, "Start", Rules.ReloadDuration)
	local function stage(delay: number, callback: () -> ())
		task.delay(delay, function()
			if reloads[player] ~= state then return end
			if not equipped(player, tool) then finishReload(player, false); return end
			callback()
		end)
	end
	-- Agenda autoritativa: animação privada/sem markers não prende a recarga.
	stage(0.3, function() handleSound(tool, "MagOut"); dropMagazine(tool) end)
	stage(1.25, function() handleSound(tool, "MagIn"); magazineVisible(tool, true) end)
	stage(1.75, function() handleSound(tool, "BoltIn") end)
	stage(1.95, function() handleSound(tool, "BoltOut") end)
	stage(Rules.ReloadDuration, function()
		local amount = Rules.ReloadAmount(ammo.Value, Ammo.GetMagazineMax(tool), Ammo.GetReserve(player, Ammo.TypeFor(tool)))
		ammo.Value += AmmoSystem.TakeReserve(player, Ammo.TypeFor(tool), amount)
		finishReload(player, true)
	end)
end

local function shotEffects(tool: Tool, muzzle: BasePart)
	local folder = audios:FindFirstChild("Weapons")
	local template = folder and folder:FindFirstChild(tool.Name)
	if template and template:IsA("Sound") then
		local sound = template:Clone()
		sound.PlayOnRemove = false
		sound.RollOffMaxDistance = 180
		sound.Parent = muzzle
		sound:Play()
		Debris:AddItem(sound, 10)
	end
	for _, child in muzzle:GetDescendants() do
		if child:IsA("ParticleEmitter") then child:Emit(3) end
	end
end

local function damageHit(player: Player, tool: Tool, part: Instance, empowered: boolean)
	local model: Instance? = part
	while model and model ~= Workspace do
		if model:IsA("Model") and model:FindFirstChildOfClass("Humanoid") then break end
		model = model.Parent
	end
	if not model or not model:IsA("Model") or model == player.Character then return end
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	if not humanoid or not DamageSystem.IsDamageable(model) or model:FindFirstChildOfClass("ForceField") then return end
	local trainingTarget = model:GetAttribute("FirearmTestTarget") == true
	if tool:GetAttribute("LobbyTestWeapon") == true and not trainingTarget then return end
	local victim = Players:GetPlayerFromCharacter(model)
	-- Lobby/sala de espera são áreas de preparação, inclusive durante outra partida.
	if not trainingTarget and (player:GetAttribute("InRound") ~= true
		or (victim and (victim:GetAttribute("InRound") ~= true or victim:GetAttribute("Eliminado") == true))) then return end
	local isHead = part.Name == "Head"
	local torso = part.Name == "Torso" or part.Name == "UpperTorso" or part.Name == "LowerTorso" or part.Name == "HumanoidRootPart"
	local damage = Rules.Number(tool, "Damage", if isHead then "HeadDamage" elseif torso then "TorsoDamage" else "LimbsDamage", 13)
	local armour = model:FindFirstChild("Armour")
	local health = armour and armour:FindFirstChild("Health")
	if health and health:IsA("NumberValue") and health.Value > 0 then
		if PowerStatus.BlockAttack(model) then return end
		if empowered then damage *= 3; PowerStatus.Stun(model, 2)
			PowerStatus.Emit("TiroCerteiro", model, (part :: BasePart).Position, 0.6, "Impact") end
		if PowerStatus.Active(model, "PowerDamageReduction") then damage *= 0.5 end
		health.Value = math.max(0, health.Value - damage)
		Remotes.FirearmDamage:FireClient(player, if isHead then "HeadArmor" else "Armor")
		return
	end
	local applied, died = DamageSystem.Apply(humanoid, damage, { Source = player, Cause = "Tiro", Empowered = empowered })
	if applied > 0 then Remotes.FirearmDamage:FireClient(player, if isHead then "Head" else "Hit") end
	if died then Remotes.FirearmFeed:FireClient(player, "Kill", model.Name) end
end

local function onShoot(player: Player, candidate: unknown, target: unknown, aimed: unknown, sequence: unknown)
	if player.Character and player.Character:GetAttribute("PowerStunned") == true then return end
	if player.Character and player.Character:GetAttribute("ShadowRushBusy") == true then return end
	local tool = equipped(player, candidate)
	if not tool or typeof(target) ~= "Vector3" or type(aimed) ~= "boolean" then return end
	local point = target :: Vector3
	if not Rules.IsFinite(point.X) or not Rules.IsFinite(point.Y) or not Rules.IsFinite(point.Z) then return end
	if not Rules.IsFinite(sequence) or (sequence :: number) % 1 ~= 0 or math.abs(sequence :: number) > 1e9 then return end
	local ammo = Rules.Value(tool, "Config", "Ammo")
	local muzzle = Rules.Muzzle(tool)
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local head = character and character:FindFirstChild("Head")
	if not ammo or not (ammo:IsA("NumberValue") or ammo:IsA("IntValue")) or not muzzle
		or not root or not root:IsA("BasePart") or not head or not head:IsA("BasePart") then return end
	local now = os.clock()
	local valid = Rules.CanShoot(now, lastShot[player], ammo.Value, reloads[player] ~= nil)
	local delta = point - muzzle.Position
	valid = valid and delta.Magnitude > 0.01 and delta.Magnitude <= Rules.Range + 40
		and (muzzle.Position - root.Position).Magnitude <= 8
	if not valid then
		Remotes.FirearmShoot:FireClient(player, tool, sequence, false, ammo.Value)
		return
	end
	lastShot[player] = now
	local empowered = PowerStatus.BeginAttack(player)
	ammo.Value -= 1
	Remotes.FirearmShoot:FireClient(player, tool, sequence, true, ammo.Value)
	local ignore: { Instance } = { character :: Model }
	local system = Workspace:FindFirstChild("System")
	if system then table.insert(ignore, system) end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = ignore
	params.IgnoreWater = true
	-- Parede entre o corpo e o cano também bloqueia o tiro.
	local obstruction = Workspace:Raycast(head.Position, muzzle.Position - head.Position, params)
	local spread = if aimed then Rules.AimSpread else Rules.HipSpread
	local direction = (CFrame.lookAt(Vector3.zero, delta.Unit)
		* CFrame.Angles(math.rad(rng:NextNumber(-spread, spread)), math.rad(rng:NextNumber(-spread, spread)), 0)).LookVector
	local result = obstruction or Workspace:Raycast(muzzle.Position, direction * Rules.Range, params)
	local endpoint = if result then result.Position else muzzle.Position + direction * Rules.Range
	if result then damageHit(player, tool, result.Instance, empowered) end
	local ok, err = pcall(function()
		shotEffects(tool, muzzle)
		WeaponEffects.CreateTracer(muzzle.CFrame, endpoint)
		if result then WeaponEffects.CreateImpact(result.Position, result.Instance, result.Normal) end
	end)
	if not ok then warn("[FirearmServer] Efeito OTS indisponível: " .. tostring(err)) end
end

local function giveTestWeapons(player: Player)
	local backpack = player:FindFirstChildOfClass("Backpack") or player:WaitForChild("Backpack", 5)
	if not backpack then return end
	for _, name in GameConfig.Testing.GiveTestWeapons do
		local template = toolsFolder:FindFirstChild(name)
		if template and Rules.IsPistol(template) and not backpack:FindFirstChild(name) then template:Clone().Parent = backpack end
	end
end

function FirearmServer.Init()
	if initialized then return end
	initialized = true
	-- Mantém meshes, welds e grip originais; a pistola não pesa no R6.
	for _, template in toolsFolder:GetChildren() do
		if Rules.IsPistol(template) then
			(template :: Tool).CanBeDropped = false -- G usa o pickup validado; Backspace não perde a Tool.
			for _, part in template:GetDescendants() do
				if part:IsA("BasePart") then
					part.Massless, part.Anchored, part.CanCollide = true, false, false
					part.CanTouch, part.CanQuery = false, false
				end
			end
		end
	end
	Remotes.FirearmShoot.OnServerEvent:Connect(onShoot)
	Remotes.FirearmReload.OnServerEvent:Connect(onReload)
	-- FirearmHit/FirearmDamage deliberadamente sem listeners OnServerEvent.
	local function watchPlayer(player: Player)
		player.CharacterRemoving:Connect(function() finishReload(player, false) end)
		player.CharacterAdded:Connect(function()
			lastShot[player] = nil
			task.defer(giveTestWeapons, player)
		end)
		if player.Character then task.defer(giveTestWeapons, player) end
	end
	for _, player in Players:GetPlayers() do watchPlayer(player) end
	Players.PlayerAdded:Connect(watchPlayer)
	Players.PlayerRemoving:Connect(function(player)
		finishReload(player, false)
		lastShot[player] = nil
	end)
end

return FirearmServer
