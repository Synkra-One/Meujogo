-- Deterministic tests of the actual rules, targeting and server modules.
-- The ray mock intersects test geometry; it does not claim Roblox physics QA.
local function signal()
	local callbacks = {}
	return {
		Connect = function(_, callback)
			local link = { active = true }
			function link:Disconnect() self.active = false end
			table.insert(callbacks, { callback, link })
			return link
		end,
		Fire = function(_, ...)
			for _, item in table.clone(callbacks) do if item[2].active then item[1](...) end end
		end,
	}
end

local V, vectorMeta = {}, {}
function V.new(x, y, z) return setmetatable({ X = x or 0, Y = y or 0, Z = z or 0, _kind = "Vector3" }, vectorMeta) end
vectorMeta.__add = function(a, b) return V.new(a.X + b.X, a.Y + b.Y, a.Z + b.Z) end
vectorMeta.__sub = function(a, b) return V.new(a.X - b.X, a.Y - b.Y, a.Z - b.Z) end
vectorMeta.__mul = function(a, b)
	if type(b) == "table" then return V.new(a.X * b.X, a.Y * b.Y, a.Z * b.Z) end
	return V.new(a.X * b, a.Y * b, a.Z * b)
end
vectorMeta.__div = function(a, b) return a * (1 / b) end
vectorMeta.__index = function(a, key)
	if key == "Magnitude" then return math.sqrt(a.X ^ 2 + a.Y ^ 2 + a.Z ^ 2) end
	if key == "Unit" then return a / a.Magnitude end
	if key == "Dot" then return function(_, b) return a.X * b.X + a.Y * b.Y + a.Z * b.Z end end
end

local function object(class, name)
	local self = { ClassName = class, Name = name or class, _kind = "Instance", attributes = {}, children = {} }
	if class == "Part" then
		self.Position = V.new()
		self.AssemblyLinearVelocity = V.new()
		self.CFrame = { VectorToObjectSpace = function(_, direction) return direction end }
	end
	for _, key in { "ChildAdded", "ChildRemoved", "DescendantAdded", "CharacterAdded", "CharacterRemoving", "AncestryChanged", "Unequipped", "Destroying" } do self[key] = signal() end
	function self:IsA(kind) return kind == self.ClassName or kind == "Instance" or (kind == "BasePart" and class == "Part") end
	function self:FindFirstChild(key) for _, child in self.children do if child.Name == key then return child end end; return nil end
	function self:FindFirstChildOfClass(kind) for _, child in self.children do if child:IsA(kind) then return child end end; return nil end
	function self:GetChildren() return table.clone(self.children) end
	function self:GetDescendants()
		local descendants = {}
		local function collect(item)
			for _, child in item.children do
				table.insert(descendants, child)
				collect(child)
			end
		end
		collect(self)
		return descendants
	end
	function self:GetAttribute(key) return self.attributes[key] end
	function self:SetAttribute(key, value) self.attributes[key] = value end
	function self:TakeDamage(amount) self.Health = math.max(0, self.Health - amount) end
	function self:CanSetNetworkOwnership() return not self.Anchored end
	function self:GetNetworkOwnershipAuto() return self.autoOwner ~= false end
	function self:GetNetworkOwner() return self.owner end
	function self:SetNetworkOwner(owner) self.owner = owner; self.autoOwner = false end
	function self:SetNetworkOwnershipAuto() self.autoOwner = true end
	function self:GetStateEnabled() return self.jumpEnabled ~= false end
	function self:SetStateEnabled(_, enabled) self.jumpEnabled = enabled end
	function self:IsDescendantOf(ancestor)
		local current = self.Parent
		while current do if current == ancestor then return true end; current = current.Parent end
		return false
	end
	return self
end
local function move(item, parent)
	local old = item.Parent
	if old then table.remove(old.children, assert(table.find(old.children, item))) end
	item.Parent = parent
	if old then old.ChildRemoved:Fire(item) end
	if parent then
		table.insert(parent.children, item)
		parent.ChildAdded:Fire(item)
		local ancestor = parent
		while ancestor do
			if ancestor.DescendantAdded then ancestor.DescendantAdded:Fire(item) end
			ancestor = ancestor.Parent
		end
	end
	item.AncestryChanged:Fire(item, parent)
	return item
end

local now = 100
local heartbeat = signal()
local workspace = object("Workspace")
function workspace:GetServerTimeNow() return now end
local playerList = {}
local players = { PlayerAdded = signal(), PlayerRemoving = signal() }
function players:GetPlayers() return table.clone(playerList) end
function players:GetPlayerFromCharacter(character)
	for _, p in playerList do if p.Character == character then return p end end
	return nil
end
local remote = { OnServerEvent = signal(), events = {} }
function remote:FireClient(player, ...) table.insert(self.events, { player, ... }) end
local roundActive = true
local round = { RoundEnded = { Event = signal() }, RoundPrepared = { Event = signal() }, IsRoundActive = function() return roundActive end }
local damageCalls = {}
local modules = {
	MonsterAnimationConfig = { AnimationIds = { Damage = "", Death = "" },
		IsUsableAnimationId = function() return false end },
	GameConfig = {
		Roles = { Survivor = "Sobrevivente", Monster = "Monstro" },
		Health = {
			HurtIdleAnimationId = "",
			HurtWalkAnimationId = "",
			DeathAnimationId = "",
			HurtAnimationDuration = 0.55,
			RegenPerSecond = 0,
			RegenDelayAfterDamage = 6,
			DisableRobloxDefaultRegen = false,
			-- Piso de vida do Monstro: o DamageSystem real usa isto em
			-- protectMonster() antes de aplicar qualquer dano.
			MonsterMinimum = 1,
		},
		-- Estados de combate lidos por DamageSystem.GetMonsterState.
		Monster = { CombatStates = { Normal = "Normal", Weakened = "Enfraquecido", Vulnerable = "Vulneravel" } },
	},
	ItemRegistry = { Items = { Lanterna = { AssetId = 6715358554 } } },
	Remotes = { Flashlight = remote }, RoundManager = round,
	FlashlightRig = { Prepare = function(tool) return tool:FindFirstChild("Handle"):FindFirstChild("FlashlightOrigin") end },
	DamageSystem = { Apply = function(target, amount, info)
		table.insert(damageCalls, { target = target, amount = amount, time = now, source = info.Source })
	end },
}
local names = setmetatable({}, { __index = function(_, key) return key end })
local services = {
	Players = players,
	RunService = { Heartbeat = heartbeat, IsStudio = function() return false end },
	StarterPack = object("StarterPack", "StarterPack"),
	Workspace = workspace,
	ReplicatedStorage = { Modules = names },
	-- O DamageSystem real (carregado no fim deste arquivo) agenda a limpeza
	-- do flash de dano pelo Debris. Só precisa existir: nada aqui mede tempo.
	Debris = { AddItem = function() end },
}
local env = setmetatable({ game = { GetService = function(_, key) return assert(services[key], key) end },
	script = { Parent = names }, Vector3 = V, os = { clock = function() return now end },
	Random = { new = function() return { NextNumber = function() return 0.75 end } end },
	Enum = {
		HumanoidStateType = { Jumping = "Jumping" },
		AnimationPriority = { Action2 = "Action2", Action4 = "Action4" },
		RaycastFilterType = { Exclude = "Exclude" },
		-- Flash de acerto do DamageSystem real (Highlight + Debris). Só
		-- precisa existir: este arquivo não verifica nada visual.
		HighlightDepthMode = { Occluded = "Occluded", AlwaysOnTop = "AlwaysOnTop" },
	},
	Color3 = { fromRGB = function(...) return { ... } end, new = function(...) return { ... } end },
	RaycastParams = { new = function() return {} end },
	-- O DamageSystem publica DamageApplied/Healed (BindableEvent) pra quem
	-- quiser OBSERVAR combate sem mexer no dano -- hoje o relatório de
	-- partida. Estes testes não escutam nada disso, mas o módulo cria os dois
	-- ao carregar, então o dublê precisa existir.
	Instance = { new = function(class)
		if class == "BindableEvent" then
			local event = signal()
			return { Event = event, Fire = function(_, ...) event:Fire(...) end }
		end
		return object(class, class)
	end },
	typeof = function(v) return if type(v) == "table" then v._kind or "table" else type(v) end,
}, { __index = getfenv() })
local function loadModule(name)
	if modules[name] then return modules[name] end
	local chunk = assert(loadstring(assert(sources[name], name), name))
	setfenv(chunk, env)
	modules[name] = chunk()
	return modules[name]
end
env.require = loadModule
local config, rules = loadModule("FlashlightConfig"), loadModule("FlashlightRules")
local function near(actual, expected, message)
	assert(math.abs(actual - expected) < 0.001, `{message}: got {actual}, expected {expected}`)
end
near(rules.Battery(100, true, 30), 50, "Half battery after 30s")
near(rules.Battery(100, true, 60), 0, "Empty after 60s")
near(rules.Battery(50, false, 999), 50, "Off never drains")
assert(not rules.ValidDirection(V.new(0/0, 0, -1)))
assert(not rules.ValidDirection(V.new(math.huge, 0, 0)))
assert(not rules.ValidDirection(V.new()))
assert(not rules.ValidDirection("forward"))
assert(rules.ValidDirection(V.new(0, 0, -1)))
assert(rules.InCone(V.new(), V.new(0, 0, -1), V.new(0, 0, -20)))
assert(not rules.InCone(V.new(), V.new(0, 0, -1), V.new(20, 0, -1)))
assert(not rules.InCone(V.new(), V.new(0, 0, -1), V.new(0, 0, -40)))
assert(not rules.InCone(V.new(), V.new(0, 0, -1), V.new(0, 0, 5)))
local state = rules.NewExposure()
rules.Step(state, true, 0.9, 1)
assert(rules.Slow(state, true, 1) == 0, "First second is visual only")
rules.Step(state, true, 2, 3)
assert(rules.Slow(state, true, 3) > 0 and rules.Slow(state, true, 3) < 0.08)
rules.Step(state, false, 0.5, 3.5)
near(state.exposure, 2.15, "Exposure decays gradually")
rules.Step(state, true, 4, 7.5)
assert(state.resistantUntil == 7.5 + config.MaxExposureDisorientation + config.ResistanceDuration)
near(rules.Slow(state, true, 7.5), 0.08, "Max slow")
local untilTime = state.resistantUntil
for t = 7.6, untilTime - 0.01, 0.1 do
	local damage, peak = rules.Step(state, true, 0.1, t)
	assert(not damage and not peak and state.exposure == 0, "Resistance prevents damage and repeated peak")
end
near(rules.Slow(state, true, untilTime - 0.01), 0.008, "Resistance cuts slow by 90%")
rules.Step(state, true, 0.1, untilTime + 0.01)
near(state.exposure, 0.1, "Exposure must rebuild after resistance")
print("PASS: battery duration, cone, finite inputs, gradual exposure, peak and resistance")

local function player(name, role)
	local p = object("Player", name)
	p:SetAttribute("Role", role)
	p:SetAttribute("InRound", true)
	p.Character = move(object("Model", name), workspace)
	local humanoid = move(object("Humanoid", "Humanoid"), p.Character)
	humanoid.Health = 100
	humanoid.WalkSpeed = 16
	for _, key in { "Head", "Torso", "HumanoidRootPart" } do
		move(object("Part", key), p.Character).Position = V.new(0, 2, 0)
	end
	move(object("Backpack"), p)
	table.insert(playerList, p)
	players.PlayerAdded:Fire(p)
	return p
end
local alice = player("Alice", "Sobrevivente")
local bob = player("Bob", "Sobrevivente")
local monster = player("Monster", "Monstro")
for _, name in { "Head", "Torso", "HumanoidRootPart" } do monster.Character:FindFirstChild(name).Position = V.new(0, 2, -12) end
local wall = object("Part", "Wall")
local wallZ, muzzleBlocked, rayCalls = nil, false, 0
function workspace:Raycast(origin, direction, params)
	rayCalls += 1
	assert(params.FilterDescendantsInstances[1] ~= monster.Character, "Target must not be excluded")
	local length = direction.Magnitude
	if length < 0.01 then return nil end
	local unit = direction.Unit
	if muzzleBlocked and length < 5 then return { Instance = wall } end
	local closest, chosen = length + 0.01, nil
	if wallZ and math.abs(unit.Z) > 0.001 then
		local distance = (wallZ - origin.Z) / unit.Z
		if distance >= 0 and distance <= length then closest, chosen = distance, wall end
	end
	for _, part in monster.Character:GetChildren() do
		if part:IsA("BasePart") then
			local offset = part.Position - origin
			local along = offset:Dot(unit)
			if along >= 0 and along <= length + 0.01 and (offset - unit * along).Magnitude < 0.75 then
				local distance = math.max(0, along - 0.5)
				if distance < closest then closest, chosen = distance, part end
			end
		end
	end
	return if chosen then { Instance = chosen } else nil
end
local function lamp(owner)
	local tool = object("Tool", "Lanterna")
	tool:SetAttribute("Lanterna", true)
	tool:SetAttribute("FlashlightModelAssetId", 6715358554)
	local handle = move(object("Part", "Handle"), tool)
	move(object("Attachment", "FlashlightOrigin"), handle).WorldPosition = V.new(0.5, 2, -1)
	move(tool, owner.Character)
	return tool
end
local system = loadModule("FlashlightSystem")
system.Init(); system.Init()
local a, b = lamp(alice), lamp(bob)
local direction = V.new(-0.5, 0, -11).Unit
local function toggle(owner, tool, on) remote.OnServerEvent:Fire(owner, "Toggle", tool, on, direction, 1) end
local function advance(duration, aim)
	local stop = now + duration
	while now < stop - 0.00001 do
		local dt = math.min(0.1, stop - now)
		now += dt
		if aim then
			remote.OnServerEvent:Fire(alice, "Aim", a, direction)
			remote.OnServerEvent:Fire(bob, "Aim", b, direction)
		end
		heartbeat:Fire(dt)
	end
end
toggle(bob, a, true)
assert(a:GetAttribute("FlashlightOn") == false, "Ownership enforced")
toggle(alice, a, true)
assert(a:GetAttribute("FlashlightOn") == true)
assert(remote.events[#remote.events][6] == 1, "Toggle acknowledgement echoes the request sequence")
advance(0.2, true); toggle(bob, b, true)
advance(3, true)
assert(#damageCalls == 1 and damageCalls[1].amount == 4, "Two survivors share one damage interval")
assert(monster.Character:GetAttribute("FlashlightExposure") < 3.5, "Multiple lamps do not multiply exposure")
assert(monster.Character:GetAttribute("FlashlightSlow") <= 0.08)
local beforeExposure = monster.Character:GetAttribute("FlashlightExposure")
wallZ = -5
advance(0.5, true)
assert(monster.Character:GetAttribute("FlashlightExposure") < beforeExposure, "Wall breaks exposure")
assert(monster.Character:GetAttribute("FlashlightExposure") > 0, "Cover does not instantly erase exposure")
advance(3, true)
assert(monster.Character:GetAttribute("FlashlightExposure") == 0 and #damageCalls == 1)
wallZ, muzzleBlocked = nil, true
advance(1, true)
assert(monster.Character:GetAttribute("FlashlightExposure") == 0, "Hand through wall cannot illuminate")
muzzleBlocked = false
local savedDirection = direction
direction = V.new(1, 0, 0)
advance(1, true)
assert(monster.Character:GetAttribute("FlashlightExposure") == 0, "Near monster outside cone is unaffected")
direction = savedDirection
advance(6.2, true)
assert(monster.Character:GetAttribute("FlashlightResistantUntil") > now, "Peak applies global resistance")
local damageAtPeak = #damageCalls
advance(5, true)
assert(#damageCalls == damageAtPeak, "Continuous multiplayer light cannot bypass resistance")
for i = 2, #damageCalls do
	assert(damageCalls[i].time - damageCalls[i - 1].time >= config.DamageCooldown - 0.001, "Global damage cooldown")
end
print("PASS: server ownership, two survivors, shared damage/exposure, walls and off-axis targeting")

local targeting = loadModule("FlashlightTargeting")
local origin, params = targeting.Source(alice.Character, a)
assert(origin and params)
assert(targeting.Hits(origin, direction, monster.Character, params))
for _, key in { "Head", "Torso", "HumanoidRootPart" } do monster.Character:FindFirstChild(key).Position = V.new(0, 2, -50) end
assert(not targeting.Hits(origin, direction, monster.Character, params), "Out of range")
for _, key in { "Head", "Torso", "HumanoidRootPart" } do monster.Character:FindFirstChild(key).Position = V.new(0, 2, -12) end
local muzzle = a:FindFirstChild("Handle"):FindFirstChild("FlashlightOrigin")
muzzle.WorldPosition = V.new(500, 2, -1)
assert(targeting.Source(alice.Character, a) == nil, "Forged distant muzzle rejected")
muzzle.WorldPosition = V.new(0.5, 2, -1)

advance(1, false)
assert(a:GetAttribute("FlashlightOn") == false and b:GetAttribute("FlashlightOn") == false, "Missing aim heartbeat turns off")
local charge = a:GetAttribute("Battery")
advance(5, false)
near(a:GetAttribute("Battery"), charge, "Off battery preserved")
move(a, alice:FindFirstChild("Backpack"))
toggle(alice, a, true)
assert(not a:GetAttribute("FlashlightOn"), "Backpack activation denied")
move(a, alice.Character)
advance(0.2, false); toggle(alice, a, true)
advance(0.5, true)
move(a, workspace)
assert(not a:GetAttribute("FlashlightOn"), "Drop shuts off immediately")
charge = a:GetAttribute("Battery")
advance(1, false)
move(a, alice.Character)
near(a:GetAttribute("Battery"), charge, "Repick does not refill")
advance(0.2, false)
remote.OnServerEvent:Fire(alice, "Toggle", a, true, V.new(0/0, 0, -1), 1)
assert(not a:GetAttribute("FlashlightOn"), "NaN aim cannot turn on")
advance(0.2, false)
alice.Character:SetAttribute("GrabLocked", true)
toggle(alice, a, true)
assert(not a:GetAttribute("FlashlightOn"), "Grab lock enforced")
alice.Character:SetAttribute("GrabLocked", nil)
advance(0.2, false)
alice:SetAttribute("Role", "Monstro")
toggle(alice, a, true)
assert(not a:GetAttribute("FlashlightOn"), "Only survivors can activate")
alice:SetAttribute("Role", "Sobrevivente")
remote.OnServerEvent:Fire(alice, "Recharge", a, 100)
near(a:GetAttribute("Battery"), charge, "Client cannot recharge")
advance(0.2, false); toggle(alice, a, true)
advance(70, true)
assert(a:GetAttribute("Battery") == 0 and not a:GetAttribute("FlashlightOn"), "Battery depletion automatically shuts off")
toggle(alice, a, true)
assert(not a:GetAttribute("FlashlightOn"), "Empty cannot switch on")
near(system.Recharge(a, 25), 25, "Server recharge API")
assert(not a:GetAttribute("FlashlightOn"), "Recharge does not switch on")
advance(0.2, false); toggle(alice, a, true)
assert(a:GetAttribute("FlashlightOn"), "Recharged tool works")
assert(system.Recharge(a, -5) == 0 and system.Recharge(a, 0/0) == 0)
print("PASS: range, forged origins, aim expiry, drop/repick, depletion, locks and recharge")

advance(0.2, true)
local calls = rayCalls
for _ = 1, 1000 do remote.OnServerEvent:Fire(alice, "Aim", a, direction) end
assert(rayCalls == calls, "Remote spam never triggers raycasts")
local damageBeforeLobby = #damageCalls
monster:SetAttribute("InRound", false)
advance(3, true)
assert(#damageCalls == damageBeforeLobby and monster.Character:GetAttribute("FlashlightIntensity") == nil, "Lobby isolated")
monster:SetAttribute("InRound", true)
advance(3, true)
assert(monster.Character:GetAttribute("FlashlightExposure") > 0)
round.RoundEnded.Event:Fire()
assert(not a:GetAttribute("FlashlightOn") and monster.Character:GetAttribute("FlashlightSlow") == nil, "Round reset clears effects")
advance(0.2, false); toggle(alice, a, true)
alice.Character:FindFirstChildOfClass("Humanoid").Health = 0
advance(0.2, true)
assert(not a:GetAttribute("FlashlightOn"), "Death turns off")
alice.Character:FindFirstChildOfClass("Humanoid").Health = 100
advance(0.2, false); toggle(alice, a, true)
alice.CharacterRemoving:Fire(alice.Character)
assert(not a:GetAttribute("FlashlightOn"), "Character replacement turns off")
print("PASS: bounded remote work, lobby isolation, round cleanup, death and character replacement")

modules.DamageSystem = nil
modules.Elimination = { Eliminate = function() end }
modules.SurvivorPowerStatus = { BlockAttack = function() return false end, Active = function() return false end }
modules.StatScaling = { DamageDealtMultiplier = function() return 1.5 end, DamageTakenMultiplier = function() return 1.35 end }
local damage = loadModule("DamageSystem")
near(damage.Apply(monster.Character, 4, { Source = alice, MaxDamage = 4 }), 4, "Cap applied after all stat multipliers")
near(damage.Apply(monster.Character, 4, { Source = alice }), 8.1, "Existing uncapped combat scaling preserved")
modules.StatScaling.DamageDealtMultiplier = function() return 0.6 end
modules.StatScaling.DamageTakenMultiplier = function() return 0.7 end
near(damage.Apply(monster.Character, 4, { Source = alice, MaxDamage = 4 }), 1.68, "Cap does not cancel damage reductions")
print("PASS: real damage system cap, normal stat scaling and damage reductions")
print("All flashlight scenarios passed; visual/asset/physics checks still require Studio.")
