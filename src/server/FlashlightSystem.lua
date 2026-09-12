--!strict
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local Modules = game:GetService("ReplicatedStorage").Modules
local Config = require(Modules.FlashlightConfig)
local Rules = require(Modules.FlashlightRules)
local Rig = require(Modules.FlashlightRig)
local GameConfig = require(Modules.GameConfig)
local Remotes = require(Modules.Remotes)
local DamageSystem = require(script.Parent.DamageSystem)
local Round = require(script.Parent.RoundManager)
local Targeting = require(script.Parent.FlashlightTargeting)

local System = {}
type Lamp = { battery: number, on: boolean, direction: Vector3, aimAt: number, drainAt: number }
local lamps: { [Tool]: Lamp } = {}
local exposures: { [Model]: Rules.ExposureState } = {}
local limits: { [Player]: { aim: number, toggle: number } } = {}
local initialized = false

local function publish(instance: Instance, name: string, value: any)
	if instance:GetAttribute(name) ~= value then instance:SetAttribute(name, value) end
end

local function drain(tool: Tool, state: Lamp, now: number)
	state.battery = Rules.Battery(state.battery, state.on, math.max(0, now - state.drainAt))
	state.drainAt = now
	publish(tool, "Battery", math.floor(state.battery * 10 + 0.00001) / 10)
end

local function setOn(tool: Tool, state: Lamp, enabled: boolean)
	drain(tool, state, os.clock())
	state.on = enabled and state.battery > 0
	publish(tool, "FlashlightOn", state.on)
	if not state.on then publish(tool, "FlashlightDirection", nil) end
end

local function alive(player: Player): boolean
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	return character ~= nil and humanoid ~= nil and humanoid.Health > 0
		and player:GetAttribute("Eliminado") ~= true and character:GetAttribute("Eliminado") ~= true
		and character:FindFirstChild("Dead") == nil
end

local function canUse(player: Player, tool: Tool): boolean
	local character = player.Character
	if not character or tool.Parent ~= character or not alive(player)
		or player:GetAttribute("Role") ~= GameConfig.Roles.Survivor
		or player:GetAttribute("InWaitingRoom") == true then return false end
	for _, flag in { "GrabLocked", "ShadowRushBusy", "TeleportBusy", "PowerStunned", "Amarrado" } do
		if character:GetAttribute(flag) == true or player:GetAttribute(flag) == true then return false end
	end
	return true
end

local function watch(tool: Instance)
	if not tool:IsA("Tool") or tool:GetAttribute("Lanterna") ~= true or lamps[tool] then return end
	if not Rig.Prepare(tool) then return end
	local battery = tool:GetAttribute("Battery")
	if type(battery) ~= "number" or battery ~= battery then battery = Config.BatteryMax end
	local state: Lamp = { battery = math.clamp(battery, 0, Config.BatteryMax), on = false,
		direction = Vector3.new(0, 0, -1), aimAt = 0, drainAt = os.clock() }
	lamps[tool] = state
	setOn(tool, state, false)
	tool.Unequipped:Connect(function() setOn(tool, state, false) end)
	tool.AncestryChanged:Connect(function()
		local parent = tool.Parent
		local owner = if parent and parent:IsA("Model") then Players:GetPlayerFromCharacter(parent) else nil
		if not owner or not canUse(owner, tool) then setOn(tool, state, false) end
	end)
	tool.Destroying:Connect(function() lamps[tool] = nil end)
end

-- Server-only recharge API. Refill never turns a light back on automatically.
function System.Recharge(tool: Tool, amount: number): number
	if type(amount) ~= "number" or amount ~= amount or amount <= 0 or amount == math.huge then return 0 end
	watch(tool)
	local state = lamps[tool]
	if not state then return 0 end
	drain(tool, state, os.clock())
	local before = state.battery
	state.battery = math.min(Config.BatteryMax, before + amount)
	drain(tool, state, os.clock())
	return state.battery - before
end

local function request(player: Player, action: any, tool: any, value: any, direction: any, sequence: any)
	if action ~= "Aim" and action ~= "Toggle" then return end
	local now = os.clock()
	local limit = limits[player]
	if not limit then limit = { aim = -math.huge, toggle = -math.huge }; limits[player] = limit end
	local key = if action == "Aim" then "aim" else "toggle"
	local interval = if action == "Aim" then Config.AimSendInterval * 0.8 else Config.ToggleCooldown * 0.8
	if now - limit[key] < interval then return end
	limit[key] = now
	if typeof(tool) ~= "Instance" or not tool:IsA("Tool") or tool.Parent ~= player.Character then return end
	local state = lamps[tool]
	if not state then return end
	if action == "Toggle" then
		if type(value) ~= "boolean" or type(sequence) ~= "number" or sequence ~= sequence
			or sequence < 0 or sequence > 2147483647 or sequence % 1 ~= 0 then return end
		if not value then
			setOn(tool, state, false)
		elseif canUse(player, tool) and Rules.ValidDirection(direction) then
			state.direction, state.aimAt = direction.Unit, now
			setOn(tool, state, true)
		end
		Remotes.Flashlight:FireClient(player, "State", tool, state.on, state.battery, sequence)
	elseif state.on and canUse(player, tool) and Rules.ValidDirection(value) then
		state.direction, state.aimAt = value.Unit, now
	end
end

local function clearExposure(character: Model)
	exposures[character] = nil
	for _, name in { "FlashlightExposure", "FlashlightIntensity", "FlashlightSlow",
		"FlashlightResistantUntil", "FlashlightDisorientedUntil" } do publish(character, name, nil) end
end

local function step(dt: number)
	local now, serverNow = os.clock(), Workspace:GetServerTimeNow()
	local roundActive = Round.IsRoundActive()
	local targets: { [Model]: Player } = {}
	for _, player in Players:GetPlayers() do
		if roundActive and player:GetAttribute("InRound") == true and player:GetAttribute("Role") == GameConfig.Roles.Monster
			and alive(player) and player.Character then targets[player.Character] = player end
	end
	local hits: { [Model]: Player } = {}
	for tool, state in lamps do
		if not state.on then continue end
		drain(tool, state, now)
		local character = tool.Parent
		local player = if character and character:IsA("Model") then Players:GetPlayerFromCharacter(character) else nil
		if state.battery <= 0 or not player or not canUse(player, tool) or now - state.aimAt > Config.AimTimeout then
			setOn(tool, state, false)
			continue
		end
		publish(tool, "FlashlightDirection", state.direction)
		if not roundActive or player:GetAttribute("InRound") ~= true then continue end
		local origin, params = Targeting.Source(player.Character :: Model, tool)
		if not origin or not params then continue end
		for target in targets do
			if not hits[target] and Targeting.Hits(origin, state.direction, target, params) then hits[target] = player end
		end
	end
	for character in exposures do
		if not targets[character] then clearExposure(character) end
	end
	for target in targets do
		local state = exposures[target]
		if not state then state = Rules.NewExposure(); exposures[target] = state end
		local source = hits[target]
		local protected = target:GetAttribute("Imune") == true or target:GetAttribute("Invulneravel") == true
			or target:GetAttribute("TeleportBusy") == true or target:FindFirstChildOfClass("ForceField") ~= nil
		local lit = source ~= nil and not protected
		local damage = Rules.Step(state, lit, math.min(dt, 0.25), serverNow)
		publish(target, "FlashlightExposure", math.floor(state.exposure * 10) / 10)
		publish(target, "FlashlightIntensity", if protected then 0 else math.floor(Rules.Intensity(state, lit, serverNow) * 100) / 100)
		publish(target, "FlashlightSlow", if protected then 0 else Rules.Slow(state, lit, serverNow))
		publish(target, "FlashlightResistantUntil", state.resistantUntil)
		publish(target, "FlashlightDisorientedUntil", if protected then 0 else state.disorientedUntil)
		if damage then DamageSystem.Apply(target, Config.Damage, { Source = source, Cause = "Lanterna", MaxDamage = Config.Damage }) end
	end
end

function System.Reset()
	for tool, state in lamps do setOn(tool, state, false) end
	for character in exposures do clearExposure(character) end
	table.clear(limits)
end

local function watchContainer(container: Instance)
	container.ChildAdded:Connect(watch)
	for _, child in container:GetChildren() do watch(child) end
end

local function watchPlayer(player: Player)
	player.CharacterAdded:Connect(watchContainer)
	player.CharacterRemoving:Connect(function(character)
		clearExposure(character)
		for _, child in character:GetChildren() do
			local state = lamps[child :: Tool]
			if state then setOn(child :: Tool, state, false) end
		end
	end)
	player.ChildAdded:Connect(function(child) if child:IsA("Backpack") then watchContainer(child) end end)
	local backpack = player:FindFirstChildOfClass("Backpack")
	if backpack then watchContainer(backpack) end
	if player.Character then watchContainer(player.Character) end
end

function System.Init()
	if initialized then return end
	initialized = true
	Remotes.Flashlight.OnServerEvent:Connect(request)
	Players.PlayerAdded:Connect(watchPlayer)
	Players.PlayerRemoving:Connect(function(player) limits[player] = nil end)
	for _, player in Players:GetPlayers() do watchPlayer(player) end
	Round.RoundEnded.Event:Connect(System.Reset)
	Round.RoundPrepared.Event:Connect(System.Reset)
	local accumulator = 0
	RunService.Heartbeat:Connect(function(dt)
		accumulator += dt
		if accumulator < Config.ServerInterval then return end
		step(accumulator)
		accumulator = 0
	end)
end

return System
