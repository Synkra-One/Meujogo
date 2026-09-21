--!strict
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local StarterPack = game:GetService("StarterPack")
local Workspace = game:GetService("Workspace")
local Modules = game:GetService("ReplicatedStorage").Modules
local Config = require(Modules.FlashlightConfig)
local Rules = require(Modules.FlashlightRules)
local Rig = require(Modules.FlashlightRig)
local GameConfig = require(Modules.GameConfig)
local ItemRegistry = require(Modules.ItemRegistry)
local Remotes = require(Modules.Remotes)
local DamageSystem = require(script.Parent.DamageSystem)
local Round = require(script.Parent.RoundManager)
local Targeting = require(script.Parent.FlashlightTargeting)
local Status = require(script.Parent.SurvivorPowerStatus)

local System = {}
type Lamp = { battery: number, on: boolean, direction: Vector3, aimAt: number, drainAt: number, burstReadyAt: number }
local lamps: { [Tool]: Lamp } = {}
local exposures: { [Model]: Rules.ExposureState } = {}
local limits: { [Player]: { aim: number, toggle: number, burst: number, sequence: number } } = {}
local burstCooldowns: { [Player]: number } = {}
local burstVictims: { [Model]: { player: Player, combatState: any } } = {}
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
		or (player:GetAttribute("Role") ~= GameConfig.Roles.Survivor and not RunService:IsStudio())
		or (player:GetAttribute("InWaitingRoom") == true and not RunService:IsStudio()) then return false end
	for _, flag in Config.BlockingFlags do
		if character:GetAttribute(flag) == true or player:GetAttribute(flag) == true then return false end
	end
	return true
end

local function isFlashlightCandidate(tool: Tool): boolean
	local name = string.gsub(string.lower(tool.Name), "[^%w]", "")
	return tool:GetAttribute("Lanterna") == true
		or tool:GetAttribute("IsFlashlight") == true
		or string.find(name, "lanterna", 1, true) ~= nil
		or string.find(name, "flashlight", 1, true) ~= nil
end

local function isCurrentFlashlight(tool: Tool): boolean
	return tool:GetAttribute("Lanterna") == true
		and tool:GetAttribute("FlashlightModelAssetId") == ItemRegistry.Items.Lanterna.AssetId
end

local function normalizeFlashlight(tool: Tool): Tool?
	if not isFlashlightCandidate(tool) then
		return tool
	end
	if isCurrentFlashlight(tool) and Rig.Prepare(tool) then
		return tool
	end
	warn(string.format("[FlashlightSystem] Lanterna antiga removida do inventario: %s", tool:GetFullName()))
	tool:Destroy()
	return nil
end

local function watch(tool: Instance)
	if not tool:IsA("Tool") then return end
	local normalized = normalizeFlashlight(tool)
	if not normalized or normalized:GetAttribute("Lanterna") ~= true or lamps[normalized] then return end
	local activeTool = normalized
	if not Rig.Prepare(activeTool) then return end
	local battery = activeTool:GetAttribute("Battery")
	if type(battery) ~= "number" or battery ~= battery then battery = Config.BatteryMax end
	local state: Lamp = { battery = math.clamp(battery, 0, Config.BatteryMax), on = false,
		direction = Vector3.new(0, 0, -1), aimAt = 0, drainAt = os.clock(), burstReadyAt = 0 }
	lamps[activeTool] = state
	setOn(activeTool, state, false)
	activeTool.Unequipped:Connect(function() setOn(activeTool, state, false) end)
	activeTool.AncestryChanged:Connect(function()
		local parent = activeTool.Parent
		local owner = if parent and parent:IsA("Model") then Players:GetPlayerFromCharacter(parent) else nil
		if not owner or not canUse(owner, activeTool) then setOn(activeTool, state, false) end
	end)
	activeTool.Destroying:Connect(function() lamps[activeTool] = nil end)
end

--[[
	ForceOff(character)
	Apaga AGORA toda lanterna carregada por este character, sem tocar no
	inventário nem na bateria: a Tool continua onde estava. Existe para
	poderes que ligam um Attribute de Config.BlockingFlags (ex: o Apagão do
	Abismo) não precisarem esperar o próximo passo de step() pro corte.
	Nunca LIGA nada -- religar continua sendo um pedido do dono da lanterna.
]]
function System.ForceOff(character: Model): number
	if typeof(character) ~= "Instance" or not character:IsA("Model") then return 0 end
	local count = 0
	for tool, state in lamps do
		if tool.Parent == character then
			if state.on then count += 1 end
			setOn(tool, state, false)
		end
	end
	return count
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

local BURST_ATTRIBUTES = { "FlashStunned", "FlashPowerBlocked", "FlashBurstAt", "FlashBurstBlindUntil" }

local function clearBurst(character: Model)
	if not burstVictims[character] then return end
	burstVictims[character] = nil
	Status.ClearStun(character, "FlashBurst")
	for _, name in BURST_ATTRIBUTES do Status.Clear(character, name) end
end

local function burst(player: Player, tool: Tool, state: Lamp, direction: any, sequence: any)
	local now = os.clock()
	local limit = limits[player]
	if type(sequence) ~= "number" or sequence ~= sequence or sequence % 1 ~= 0
		or sequence <= limit.sequence or sequence > 2147483647 then return end
	limit.sequence = sequence -- replayed requests cannot become valid after cooldown
	local function reject(reason: string)
		Remotes.Flashlight:FireClient(player, "BurstResult", tool, false, reason, sequence)
	end
	if not canUse(player, tool) or player:GetAttribute("Role") ~= GameConfig.Roles.Survivor
		or not Round.IsRoundActive() or player:GetAttribute("InRound") ~= true
		or player:GetAttribute("InWaitingRoom") == true then reject("Blocked"); return end
	local character = player.Character :: Model
	local root = character:FindFirstChild("HumanoidRootPart")
	if not root or not root:IsA("BasePart") or not Rules.ValidBurstAim(root, direction) then reject("Aim"); return end
	if now < math.max(state.burstReadyAt, burstCooldowns[player] or 0) then reject("Cooldown"); return end
	drain(tool, state, now)
	if state.battery < Config.FlashBurstCost then reject("Battery"); return end
	local origin, params = Targeting.Source(character, tool)
	if not origin or not params then reject("Obstructed"); return end
	params.RespectCanCollide, params.IgnoreWater = true, true
	local candidates: { { player: Player, character: Model, distance: number } } = {}
	for _, other in Players:GetPlayers() do
		local target = other.Character
		local part = target and target:FindFirstChild("HumanoidRootPart")
		if other ~= player and target and part and part:IsA("BasePart") and alive(other)
			and other:GetAttribute("Role") == GameConfig.Roles.Monster and other:GetAttribute("InRound") == true
			and other:GetAttribute("InWaitingRoom") ~= true then
			local distance = (part.Position - origin).Magnitude
			if distance <= Config.FlashBurstRange then
				table.insert(candidates, { player = other, character = target, distance = distance })
			end
		end
	end
	if #candidates == 0 then reject("Range"); return end
	table.sort(candidates, function(a, b) return a.distance < b.distance end)
	-- Commit once, before applying effects. Cooldown belongs to both owner
	-- and Tool, so swapping/dropping a lamp cannot bypass it.
	local serverNow = Workspace:GetServerTimeNow()
	state.battery -= Config.FlashBurstCost
	state.burstReadyAt, burstCooldowns[player] = now + Config.FlashBurstCooldown, now + Config.FlashBurstCooldown
	drain(tool, state, now)
	if state.battery <= 0 then setOn(tool, state, false) end
	publish(tool, "FlashBurstReadyAt", serverNow + Config.FlashBurstCooldown)
	publish(player, "FlashBurstReadyAt", serverNow + Config.FlashBurstCooldown)
	publish(tool, "FlashBurstAt", serverNow)
	local hit = false
	for _, candidate in candidates do
		local target = candidate.character
		if Targeting.Hits(origin, direction.Unit, target, params, Config.FlashBurstRange, Config.FlashBurstAngle) then
			if Status.Stun(target, Config.FlashBurstStunDuration, "FlashBurst") then
				burstVictims[target] = { player = candidate.player, combatState = target:GetAttribute("MonsterCombatState") }
				Status.Set(target, "FlashStunned", true, Config.FlashBurstStunDuration)
				Status.Set(target, "FlashPowerBlocked", true, Config.FlashBurstPowerBlockDuration)
				Status.Set(target, "FlashBurstAt", serverNow, Config.FlashBurstBlindDuration)
				Status.Set(target, "FlashBurstBlindUntil", serverNow + Config.FlashBurstBlindDuration, Config.FlashBurstBlindDuration)
				hit = true
			end
			break -- one nearest visible monster; immunity doesn't let light pierce it
		end
	end
	Remotes.Flashlight:FireClient(player, "BurstResult", tool, true, if hit then "Hit" else "Miss", sequence)
end

local function request(player: Player, action: any, tool: any, value: any, direction: any, sequence: any)
	if action ~= "Aim" and action ~= "Toggle" and action ~= "Burst" then return end
	local now = os.clock()
	local limit = limits[player]
	if not limit then
		limit = { aim = -math.huge, toggle = -math.huge, burst = -math.huge, sequence = 0 }; limits[player] = limit
	end
	local key = if action == "Aim" then "aim" elseif action == "Burst" then "burst" else "toggle"
	local interval = if action == "Aim" then Config.AimSendInterval * 0.8
		elseif action == "Burst" then Config.FlashBurstInputInterval else Config.ToggleCooldown * 0.8
	if now - limit[key] < interval then return end
	limit[key] = now
	if typeof(tool) ~= "Instance" or not tool:IsA("Tool") or tool.Parent ~= player.Character then return end
	local state = lamps[tool]
	if not state then return end
	if action == "Burst" then
		burst(player, tool, state, direction, sequence)
	elseif action == "Toggle" then
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
	for character, entry in burstVictims do
		if targets[character] ~= entry.player or not character.Parent
			or character:GetAttribute("MonsterCombatState") ~= entry.combatState
			or serverNow >= (character:GetAttribute("FlashBurstBlindUntil") or 0) then clearBurst(character) end
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
	for tool, state in lamps do
		setOn(tool, state, false)
		state.burstReadyAt = 0
		publish(tool, "FlashBurstReadyAt", nil)
		publish(tool, "FlashBurstAt", nil)
	end
	for character in burstVictims do clearBurst(character) end
	for _, player in Players:GetPlayers() do publish(player, "FlashBurstReadyAt", nil) end
	table.clear(burstCooldowns)
	for character in exposures do clearExposure(character) end
	table.clear(limits)
end

local function watchContainer(container: Instance)
	container.DescendantAdded:Connect(watch)
	for _, child in container:GetDescendants() do watch(child) end
end

local function normalizeStarterPack()
	StarterPack.DescendantAdded:Connect(function(child)
		if child:IsA("Tool") and isFlashlightCandidate(child) then
			child:Destroy()
		end
	end)
	for _, child in StarterPack:GetDescendants() do
		if child:IsA("Tool") and isFlashlightCandidate(child) then
			child:Destroy()
		end
	end
end

local function removeInitialFlashlights(player: Player)
	for _, container in { player:FindFirstChildOfClass("Backpack"), player:FindFirstChild("StarterGear"), player.Character } do
		if not container then continue end
		for _, item in container:GetDescendants() do
			if item:IsA("Tool") and isFlashlightCandidate(item) then
				item:Destroy()
			end
		end
	end
end

local function watchPlayer(player: Player)
	-- O jogo nao concede lanterna no loadout inicial. As unicas lanternas
	-- validas entram depois pelos pickups/loot e usam o asset configurado.
	removeInitialFlashlights(player)
	player.CharacterAdded:Connect(watchContainer)
	player.CharacterRemoving:Connect(function(character)
		clearBurst(character)
		clearExposure(character)
		for _, child in character:GetChildren() do
			local state = lamps[child :: Tool]
			if state then setOn(child :: Tool, state, false) end
		end
	end)
	player.ChildAdded:Connect(function(child)
		if child:IsA("Backpack") or child.Name == "StarterGear" then
			watchContainer(child)
		elseif child:IsA("Tool") then
			watch(child)
		end
	end)
	local backpack = player:FindFirstChildOfClass("Backpack")
	if backpack then watchContainer(backpack) end
	local starterGear = player:FindFirstChild("StarterGear")
	if starterGear then watchContainer(starterGear) end
	if player.Character then watchContainer(player.Character) end
end

function System.Init()
	if initialized then return end
	assert(Config.FlashBurstCost > 0 and Config.FlashBurstCost <= Config.BatteryMax
		and Config.FlashBurstCooldown > 0 and Config.FlashBurstRange > 0
		and Config.FlashBurstAngle > 0 and Config.FlashBurstAngle < 180
		and Config.FlashBurstStunDuration > 0
		and Config.FlashBurstPowerBlockDuration >= Config.FlashBurstStunDuration
		and Config.FlashBurstBlindDuration > Config.FlashBurstPowerBlockDuration,
		"FlashBurst: invalid cost/range/cooldown/durations")
	initialized = true
	Status.Init()
	normalizeStarterPack()
	Remotes.Flashlight.OnServerEvent:Connect(request)
	Players.PlayerAdded:Connect(watchPlayer)
	Players.PlayerRemoving:Connect(function(player)
		if player.Character then clearBurst(player.Character) end
		limits[player], burstCooldowns[player] = nil, nil
	end)
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
