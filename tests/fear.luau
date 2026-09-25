-- Real module sources are injected by run_fear.py; only Roblox services are mocked.
local function near(a, b, message)
	assert(math.abs(a - b) < 1e-7, (message or "mismatch") .. ": " .. tostring(a) .. " / " .. tostring(b))
end
local function signal()
	local self = { listeners = {} }
	function self:Connect(callback)
		local connection = { Connected = true, callback = callback }
		function connection:Disconnect() self.Connected = false end
		table.insert(self.listeners, connection)
		return connection
	end
	function self:Fire(...)
		for _, c in table.clone(self.listeners) do if c.Connected then c.callback(...) end end
	end
	function self:Count()
		local n = 0
		for _, c in self.listeners do if c.Connected then n += 1 end end
		return n
	end
	return self
end
local function object(class)
	local self = { ClassName = class, attributes = {}, children = {} }
	function self:GetAttribute(key) return self.attributes[key] end
	function self:SetAttribute(key, value) self.attributes[key] = value end
	function self:IsA(key) return key == class or (class == "Part" and key == "BasePart") end
	function self:FindFirstChild(key) return self.children[key] end
	function self:FindFirstChildOfClass(key)
		for _, child in self.children do if child:IsA(key) then return child end end
		return nil
	end
	return self
end
local cframeMeta = {}
cframeMeta.__mul = function(a, b) return a end
local function cframe() return setmetatable({}, cframeMeta) end
local vectorMeta = {}
local function vector(x, y, z) return setmetatable({ X=x, Y=y, Z=z }, vectorMeta) end
vectorMeta.__sub = function(a,b) return vector(a.X-b.X,a.Y-b.Y,a.Z-b.Z) end
vectorMeta.__add = function(a,b) return vector(a.X+b.X,a.Y+b.Y,a.Z+b.Z) end
vectorMeta.__mul = function(a,b) return vector(a.X*b,a.Y*b,a.Z*b) end
vectorMeta.__index = function(a,key)
	if key == "Magnitude" then return math.sqrt(a.X*a.X+a.Y*a.Y+a.Z*a.Z) end
	if key == "Unit" then return vector(a.X/a.Magnitude,a.Y/a.Magnitude,a.Z/a.Magnitude) end
	if key == "Dot" then return function(_,b) return a.X*b.X+a.Y*b.Y+a.Z*b.Z end end
end
local function position(x) return vector(x, 0, 0) end
local players = { PlayerAdded = signal(), PlayerRemoving = signal(), list = {} }
function players:GetPlayers() return table.clone(self.list) end
local heartbeat = signal()
local runService = { Heartbeat = heartbeat, IsServer = function() return true end }
local moduleNames = setmetatable({}, { __index = function(_, key) return key end })
local active = false
local round = { RoundPrepared = { Event = signal() }, RoundEnded = { Event = signal() },
	IsRoundActive = function() return active end }
local logs = {}
local raycasts, obstacle, randomCalls, randomValue = 0, { CanCollide=true }, 0, 0.99
local world = {}
function world:Raycast(_,_,params)
	raycasts += 1
	assert(params.FilterType == "Exclude" and #params.FilterDescendantsInstances == 2)
	assert(params.RespectCanCollide and params.IgnoreWater)
	return if obstacle and obstacle.CanCollide then { Instance = obstacle } else nil
end
local services = { Players = players, RunService = runService, ReplicatedStorage = { Modules = moduleNames }, Workspace = world }
local sprintIntent = signal()
local modules = { RoundManager = round, LoadoutData = { GetPerk = function() return nil end },
	Remotes = { SprintIntent = { OnServerEvent = sprintIntent } },
	MatchStateService = { IsGameplayEnabled = function() return active end },
	DamageSystem = { DamageApplied = { Event = signal() } } }
local environment = setmetatable({
	game = { GetService = function(_, name) return assert(services[name], name) end },
	script = { Parent = moduleNames },
	print = function(message) table.insert(logs, message) end,
	warn = function(message) error(message) end,
	Vector3 = { new = vector },
	CFrame = { new = cframe, Angles = cframe },
	Color3 = { new = function(...) return {...} end, fromRGB = function(...) return {...} end },
	RaycastParams = { new = function() return {} end },
	Enum = { RaycastFilterType = { Exclude = "Exclude" }, Material = { Air="Air", Water="Water" },
		HumanoidStateType = { Swimming="Swimming" },
		KeyCode = { E = "E", X = "X", ButtonX = "ButtonX", ButtonB = "ButtonB" } },
	Random = { new = function() return { NextNumber = function() randomCalls+=1; return randomValue end } end },
	Instance = { new = function(class)
		assert(class == "BindableEvent")
		local s = signal()
		return { Event=s, Fire=function(_,...) s:Fire(...) end }
	end },
}, { __index = getfenv() })
local function loadModule(name)
	if modules[name] then return modules[name] end
	local chunk = assert(loadstring(assert(sources[name], name), name))
	setfenv(chunk, environment)
	modules[name] = chunk()
	return modules[name]
end
environment.require = loadModule
local config = loadModule("GameConfig")
local cfg = config.Fear
local function rampAt(seconds)
	return cfg.ExposureInitialMultiplier + (1 - cfg.ExposureInitialMultiplier)
		* math.min(seconds, cfg.ExposureRampSeconds) / cfg.ExposureRampSeconds
end
local scaling = loadModule("StatScaling")
local rules = loadModule("FearRules")
local fear = loadModule("FearSystem")
local function character(x, delayedHumanoid)
	local c, h, root = object("Model"), object("Humanoid"), object("Part")
	c.Parent = services.Workspace
	c.ChildAdded = signal()
	h.Health = 100
	h.Died = signal()
	h.Parent = c
	h.WalkSpeed, h.FloorMaterial, h.Sit = 12, "Ground", false
	function h:GetState() return "Running" end
	root.Position = position(x)
	root.Parent, root.Anchored = c, false
	root.AssemblyLinearVelocity = position(0)
	root.autoOwnership, root.owner = true, nil
	function root:CanSetNetworkOwnership() return not self.Anchored end
	function root:GetNetworkOwnershipAuto() return self.autoOwnership end
	function root:GetNetworkOwner() return self.owner end
	function root:SetNetworkOwner(owner) self.owner=owner; self.autoOwnership=false end
	function root:SetNetworkOwnershipAuto() self.autoOwnership=true end
	c.children.HumanoidRootPart = root
	if not delayedHumanoid then c.children.Humanoid = h end
	return c, h, root
end
local function player(name, role, x, composure)
	local p = object("Player")
	p.Name, p.Parent = name, players
	p.CharacterAdded, p.CharacterRemoving = signal(), signal()
	p.Character = character(x)
	p:SetAttribute("Role", role)
	p:SetAttribute("InRound", true)
	p:SetAttribute("Stat_Compostura", composure)
	table.insert(players.list, p)
	players.PlayerAdded:Fire(p)
	return p
end
local low = player("Low", config.Roles.Survivor, 0, 0)
local high = player("High", config.Roles.Survivor, 0, 100)
local monster = player("Monster", config.Roles.Monster, 40, 85)
local spy = player("Spy", config.Roles.Spy, 0, 50)
local lobby = player("Lobby", config.Roles.Survivor, 0, 50)
lobby:SetAttribute("InRound", false)
near(scaling.FearGainMultiplier(low), 1.5)
near(scaling.FearGainMultiplier(high), 0.55)
assert(math.abs(scaling.FearGainMultiplier(spy) - 1) < 0.01)
near(scaling.FearRecoveryMultiplier(low), 0.65)
near(scaling.FearRecoveryMultiplier(high), 1.35)
-- A rampa vem da config; o teste nunca repete os números dela, senão um
-- rebalanceamento quebra o teste em vez de ser verificado por ele.
local danger, closest = cfg.MaxFearDistance, cfg.MinFearDistance
local far = danger * 2
local previous = math.huge
for d = 0, far, 0.05 do
	local rate = rules.ProximityRate(d, cfg)
	assert(rate <= previous + 1e-10 and rate >= 0 and rate <= cfg.MaxProximityFearPerSecond)
	previous = rate
end
for _, d in { closest, closest + 10, danger * 0.4, danger * 0.75, danger } do
	assert(math.abs(rules.ProximityRate(d - 1e-5, cfg) - rules.ProximityRate(d + 1e-5, cfg)) < 1e-4)
end
near(rules.ProximityRate(0, cfg), cfg.MaxProximityFearPerSecond)
near(rules.ProximityRate(danger, cfg), 0)
near(rules.ProximityRate(math.huge, cfg), 0)
-- A BARRA SOBE COM O TEMPO: colado no Monstro, nem o pior caso possível
-- (Compostura 0 + linha de visão + perseguição) enche a barra num piscar.
local worst = cfg.MaxProximityFearPerSecond * 1.5 * cfg.LineOfSightMultiplier * cfg.ChaseFearMultiplier
local fastest = cfg.MaxFear / math.min(worst, cfg.MaxFearGainPerSecond)
assert(fastest >= 18, "0 -> 100 no pior caso leva pelo menos 18 s: " .. string.format("%.1f", fastest))
local typical = cfg.MaxFear / (cfg.MaxProximityFearPerSecond * cfg.LineOfSightMultiplier)
assert(typical >= 25 and typical <= 45, "exposição típica exige tempo: " .. string.format("%.1f", typical))
-- E DESCE quando a pessoa fica longe da zona de perigo.
local drain = cfg.MaxFear / cfg.BaseFearRecoveryPerSecond
assert(drain > fastest and drain <= 45, "descer é mais lento que subir, mas não eterno")
local state = { value = 50, safeFor = 0 }
rules.Step(state, far, 1, 1, 3.9, cfg)
near(state.value, 50)
rules.Step(state, far, 1, 1, 0.3, cfg)
near(state.value, 49.3, "only post-delay fraction recovers")
rules.Step(state, danger - 0.1, 1, 1, 0.2, cfg)
near(state.safeFor, 0)
local before = state.value
rules.Step(state, far, 1, 1, 4, cfg)
near(state.value, before, "reentry restarts delay")
local a, b = { value = 80, safeFor = 0 }, { value = 80, safeFor = 0 }
rules.Step(a, far, 1, 1, 9, cfg)
for _ = 1, 45 do rules.Step(b, far, 1, 1, 0.2, cfg) end
near(a.value, b.value, "recovery independent of tick size")
local exposed = { value = 0, safeFor = 0 }
local firstGain = rules.Step(exposed, closest, 1, 1, 0.2, cfg)
near(firstGain, cfg.MaxProximityFearPerSecond * rampAt(0.2), "first contact is gentle")
for _ = 1, 25 do rules.Step(exposed, closest, 1, 1, 0.2, cfg) end
near(exposed.exposureFor, cfg.ExposureRampSeconds)
rules.Step(exposed, far, 1, 1, 0.2, cfg)
near(exposed.exposureFor, 0, "leaving danger resets exposure")

fear.Init(); fear.Init()
assert(heartbeat:Count() == 1 and players.PlayerAdded:Count() == 1)
heartbeat:Fire(0.2)
near(fear.GetFear(low), 0, "inactive round")
active = true
round.RoundPrepared.Event:Fire()
heartbeat:Fire(0.1)
near(fear.GetFear(low), 0, "does not calculate every frame")
heartbeat:Fire(0.1)
near(fear.GetFear(low), rules.ProximityRate(40, cfg) * 1.5 * rampAt(0.2) * 0.2)
near(fear.GetFear(high), rules.ProximityRate(40, cfg) * 0.55 * rampAt(0.2) * 0.2)
for _, p in { spy, monster, lobby } do near(fear.AddFear(p, 10, "Test"), 0) end
low:SetAttribute("Fear", 99)
assert(fear.GetFear(low) < 10, "replicated attribute is not source of truth")
near(fear.AddFear(low, 1000, "Test"), 100)
near(fear.AddFear(low, math.huge), 100)
near(fear.AddFear(low, 0/0), 100)
near(fear.ReduceFear(low, -100), 100)
near(fear.ReduceFear(low, 1000), 0)
fear.AddFear(low, 50, "Test"); fear.AddFear(high, 50 - fear.GetFear(high), "Test")
monster.Character.children.HumanoidRootPart.Position = position(far)
for _ = 1, 20 do heartbeat:Fire(0.2) end
near(fear.GetFear(low), 50)
near(fear.GetFear(high), 50)
heartbeat:Fire(0.2)
near(fear.GetFear(low), 50 - cfg.BaseFearRecoveryPerSecond * 0.65 * 0.2)
near(fear.GetFear(high), 50 - cfg.BaseFearRecoveryPerSecond * 1.35 * 0.2)
fear.AddFear(low, 1, "FutureSource")
before = fear.GetFear(low)
heartbeat:Fire(0.2)
near(fear.GetFear(low), before, "external source interrupts recovery")
local monster2 = player("Nearest", config.Roles.Monster, closest, 50)
heartbeat:Fire(0.2)
near(fear.GetFear(low), before + rules.ProximityRate(closest, cfg) * 1.5 * rampAt(0.2) * 0.2, "nearest monster selected")
monster2:SetAttribute("Eliminado", true)
before = fear.GetFear(low)
heartbeat:Fire(0.2)
near(fear.GetFear(low), before, "eliminated monster ignored")
monster.Character.children.Humanoid.Health = 0
for _ = 1, 21 do heartbeat:Fire(0.2) end
assert(fear.GetFear(low) < before, "no living monster allows recovery")
low.Character.children.Humanoid.Health = 0
low.Character.children.Humanoid.Died:Fire()
near(low:GetAttribute("Fear"), 0, "death resets immediately")
assert(low.Character.ChildAdded:Count() == 0)
local old = low.Character
low.CharacterRemoving:Fire(old)
low.Character = character(0, true)
low.CharacterAdded:Fire(low.Character)
local h = object("Humanoid"); h.Health = 100; h.Died = signal()
h.Parent = low.Character; h.WalkSpeed=12; h.FloorMaterial="Ground"; h.Sit=false
function h:GetState() return "Running" end
low.Character.children.Humanoid = h
low.Character.ChildAdded:Fire(h)
assert(h.Died:Count() == 1 and old.ChildAdded:Count() == 0)
fear.AddFear(low, 20)
low:SetAttribute("Eliminado", true)
heartbeat:Fire(0.2)
near(low:GetAttribute("Fear"), 0)
near(fear.AddFear(low, 20), 0, "eliminated respawn cannot regain fear")
low:SetAttribute("Eliminado", nil)
low:SetAttribute("CharacterSelectOpen", true)
near(fear.AddFear(low, 20), 0, "selection does not accumulate fear")
low:SetAttribute("CharacterSelectOpen", nil)
fear.AddFear(low, 20)
round.RoundEnded.Event:Fire(); active = false
near(low:GetAttribute("Fear"), 0)
active = true; round.RoundPrepared.Event:Fire()
near(fear.GetFear(low), 0, "new round starts calm")
cfg.DebugMode = true
for _ = 1, 40 do heartbeat:Fire(0.2) end
assert(#logs >= 6 and #logs <= 8, "debug throttled for two survivors")
assert(string.find(logs[1], "MonsterDistance:") and string.find(logs[1], "FearRecoveryPerSecond:"))
players.PlayerRemoving:Fire(low)
low.Parent = nil
table.remove(players.list, 1)
assert(low.CharacterAdded:Count() == 0 and low.CharacterRemoving:Count() == 0)
assert(low.Character.ChildAdded:Count() == 0 and h.Died:Count() == 0)
print("PASS: continuous curve, existing Compostura, recovery delay/reentry/partial ticks, clamping, server authority, role/round/death filters, nearest monster, respawn/exit cleanup, idempotent Init and throttled debug")
for _, d in { danger, danger * 0.75, danger * 0.5, danger * 0.25, closest } do
	print(string.format("%d studs -> %.3f base Fear/s", d, rules.ProximityRate(d, cfg)))
end

-- Parte 2: mesmos módulos/loop e estado da Parte 1.
cfg.DebugMode = false
for _, item in { {0,"Calm"}, {24.999,"Calm"}, {25,"Nervous"}, {49.999,"Nervous"},
	{50,"Scared"}, {74.999,"Scared"}, {75,"Panicked"}, {89.999,"Panicked"}, {90,"ExtremePanic"}, {100,"ExtremePanic"} } do
	assert(rules.GetState(item[1], cfg) == item[2])
end
near(rules.StaminaRegenMultiplier(0,cfg),1)
near(rules.StaminaRegenMultiplier(25,cfg),1)
near(rules.StaminaRegenMultiplier(100,cfg),0.5)
assert(math.abs(rules.StaminaRegenMultiplier(50,cfg)-0.9)<0.01)
assert(math.abs(rules.StaminaRegenMultiplier(75,cfg)-0.7)<0.03)
near(rules.EffectChance(74.99,75,100,0.03,0.12),0)
near(rules.EffectChance(75,75,100,0.03,0.12),0.03)
near(rules.EffectChance(100,75,100,0.03,0.12),0.12)
near(rules.EffectChance(87,75,100,0.03,0.12),0.0732)
local capped = { value=0,safeFor=0,exposureFor=cfg.ExposureRampSeconds }
local gain = rules.Step(capped,closest,1.5*cfg.LineOfSightMultiplier*cfg.ChaseFearMultiplier,1,0.2,cfg)
near(gain,cfg.MaxFearGainPerSecond)

local subject = high
local root = subject.Character.children.HumanoidRootPart
local hum = subject.Character.children.Humanoid
local monRoot = monster.Character.children.HumanoidRootPart
monster.Character.children.Humanoid.Health = 100
monRoot.Position = position(40)
round.RoundPrepared.Event:Fire()
obstacle = nil
local changes, trips, sounds = 0, 0, 0
fear.FearStateChanged.Event:Connect(function(p) if p==subject then changes+=1 end end)
fear.TripTriggered.Event:Connect(function(p,pos,duration)
	if p==subject then trips+=1; assert(pos==root.Position); near(duration,cfg.TripDuration) end
end)
fear.PanicSoundTriggered.Event:Connect(function(p,pos,radius)
	if p==subject then sounds+=1; assert(pos==root.Position); near(radius,cfg.PanicSoundRadius) end
end)
heartbeat:Fire(0.2)
assert(subject:GetAttribute("FearLineOfSight") == true)
near(fear.GetFear(subject), rules.ProximityRate(40,cfg)*0.55*1.35*rampAt(0.2)*0.2)
local casts = raycasts
heartbeat:Fire(0.2)
assert(raycasts==casts, "LOS cache reused between 0.4s checks")
obstacle = { CanCollide=true, ClassName="Terrain" }
heartbeat:Fire(0.2)
assert(subject:GetAttribute("FearLineOfSight") == false)
before=fear.GetFear(subject)
heartbeat:Fire(0.2)
near(fear.GetFear(subject)-before, rules.ProximityRate(40,cfg)*0.55*rampAt(0.8)*0.2)
obstacle = { CanCollide=false }
heartbeat:Fire(0.2)
assert(subject:GetAttribute("FearLineOfSight"), "noncollidable decorations ignored")
root.AssemblyLinearVelocity=position(-25)
monRoot.AssemblyLinearVelocity=position(-25)
heartbeat:Fire(0.2); heartbeat:Fire(0.2)
assert(not subject:GetAttribute("FearChase"), "confirmation prevents one-tick chase")
before=fear.GetFear(subject)
heartbeat:Fire(0.2)
assert(subject:GetAttribute("FearChase"))
near(fear.GetFear(subject)-before, rules.ProximityRate(40,cfg)*0.55*1.35*1.4*rampAt(1.6)*0.2)
monRoot.AssemblyLinearVelocity=position(25)
heartbeat:Fire(0.2)
assert(not subject:GetAttribute("FearChase"), "monster moving away is not chasing")
monRoot.AssemblyLinearVelocity=position(-25)
root.AssemblyLinearVelocity=position(25)
for _=1,4 do heartbeat:Fire(0.2) end
assert(not subject:GetAttribute("FearChase"), "approaching monster is not fleeing")
root.AssemblyLinearVelocity=position(0)
for _=1,4 do heartbeat:Fire(0.2) end
assert(not subject:GetAttribute("FearChase"), "stationary survivor never chased")
root.AssemblyLinearVelocity=position(-25)
monRoot.Position=position(100)
for _=1,4 do heartbeat:Fire(0.2) end
assert(not subject:GetAttribute("FearChase"), "chase distance gate")
monRoot.Position=position(40)
obstacle={CanCollide=true}
for _=1,4 do heartbeat:Fire(0.2) end
assert(not subject:GetAttribute("FearChase"), "LOS requirement respected")

round.RoundPrepared.Event:Fire()
monRoot.AssemblyLinearVelocity=position(0)
root.AssemblyLinearVelocity=position(0)
fear.AddFear(subject,100,"Test")
assert(fear.GetFearState(subject)=="ExtremePanic")
local eventCount=changes
fear.AddFear(subject,1)
assert(changes==eventCount,"state event fires only on transitions")
subject:SetAttribute("Stat_Compostura",0)
near(fear.GetStaminaRegenMultiplier(subject),0.5,"no duplicate composure penalty")
subject:SetAttribute("Stat_Compostura",100)
near(fear.GetStaminaRegenMultiplier(subject),0.5)
randomValue=0
for _=1,14 do heartbeat:Fire(0.2) end
assert(trips==0,"standing cannot trip")
round.RoundPrepared.Event:Fire()
fear.AddFear(subject,100)
root:SetNetworkOwner(subject)
root.autoOwnership=true
for _=1,14 do root.AssemblyLinearVelocity=position(30); heartbeat:Fire(0.2) end
assert(trips==0,"no early trip roll")
root.AssemblyLinearVelocity=position(30); heartbeat:Fire(0.2)
assert(trips==1 and subject.Character:GetAttribute("FearTripping"))
assert(root:GetNetworkOwner()==nil and not root:GetNetworkOwnershipAuto(),"server owns trip physics")
assert(root.AssemblyLinearVelocity.Magnitude <= scaling.WalkSpeed(subject)*cfg.TripSpeedMultiplier)
near(hum.WalkSpeed,scaling.WalkSpeed(subject)*cfg.TripSpeedMultiplier)
for _=1,4 do heartbeat:Fire(0.2) end
assert(not subject.Character:GetAttribute("FearTripping") and root:GetNetworkOwnershipAuto())
for _=1,25 do root.AssemblyLinearVelocity=position(30); heartbeat:Fire(0.2) end
assert(trips==1,"trip cooldown blocks repeated checks")
assert(sounds==1,"panic sound hook has cooldown")
root.AssemblyLinearVelocity=position(0)
local rolls=randomCalls
heartbeat:Fire(0.01)
assert(randomCalls==rolls,"no RNG per frame")
active=false; round.RoundEnded.Event:Fire()
assert(fear.GetFearState(subject)=="Calm" and not subject.Character:GetAttribute("FearTripping"))
active=true; round.RoundPrepared.Event:Fire()
fear.AddFear(subject,100)
for _=1,16 do root.AssemblyLinearVelocity=position(30); heartbeat:Fire(0.2) end
assert(subject.Character:GetAttribute("FearTripping"))
hum.Health=0; hum.Died:Fire()
assert(not subject.Character:GetAttribute("FearTripping") and root:GetNetworkOwnershipAuto(),"death releases ownership")
hum.Health=100
round.RoundPrepared.Event:Fire()

subject.CharacterAdded:Fire(subject.Character)
local function prepareEffectTrial()
	round.RoundPrepared.Event:Fire()
	fear.AddFear(subject,100)
	root.AssemblyLinearVelocity=position(30)
end
for _, mode in { "Air", "Water", "Seated", "Anchored" } do
	prepareEffectTrial()
	hum.FloorMaterial = if mode=="Air" or mode=="Water" then mode else "Ground"
	hum.Sit = mode=="Seated"
	root.Anchored = mode=="Anchored"
	local count=trips
	for _=1,16 do heartbeat:Fire(0.2) end
	assert(trips==count, "no trip while "..mode)
end
root.Anchored=false; hum.Sit=false; hum.FloorMaterial="Ground"
prepareEffectTrial()
root:SetNetworkOwner(subject) -- explicitly owned, not automatic
for _=1,16 do heartbeat:Fire(0.2) end
assert(subject.Character:GetAttribute("FearTripping"))
round.RoundEnded.Event:Fire()
assert(root:GetNetworkOwner()==subject and not root:GetNetworkOwnershipAuto(),"round end restores exact ownership mode")
prepareEffectTrial()
for _=1,16 do heartbeat:Fire(0.2) end
assert(subject.Character:GetAttribute("FearTripping"))
subject.CharacterRemoving:Fire(subject.Character)
assert(not subject.Character:GetAttribute("FearTripping"),"removal clears movement penalty")
assert(root:GetNetworkOwner()==subject,"removal releases server ownership")
subject.CharacterAdded:Fire(subject.Character)

-- Integração com o StaminaSystem REAL: máximo/dreno intactos, só regen reduz.
local stamina = loadModule("StaminaSystem")
stamina.Init(); stamina.Init()
assert(heartbeat:Count()==2 and sprintIntent:Count()==1,"one existing stamina loop plus one Fear loop")
local function regenTrial(value)
	round.RoundPrepared.Event:Fire()
	stamina.Refill(subject)
	root.AssemblyLinearVelocity=position(30)
	sprintIntent:Fire(subject,true)
	for _=1,5 do heartbeat:Fire(0.1) end
	local depleted=stamina.Get(subject)
	assert(depleted<100)
	root.AssemblyLinearVelocity=position(0)
	sprintIntent:Fire(subject,false)
	-- Keep Fear fixed while measuring; proximity/recovery rates disabled only in this test.
	cfg.MaxProximityFearPerSecond=0
	fear.ReduceFear(subject,100); fear.AddFear(subject,value)
	for _=1,15 do heartbeat:Fire(0.1) end
	return stamina.Get(subject)-depleted
end
local proximityRate = cfg.MaxProximityFearPerSecond
local normal=regenTrial(0)
local frightened=regenTrial(100)
near(frightened,normal*0.5,"real stamina recovers at half rate")
near(subject:GetAttribute("Stat_Compostura"),100,"attribute unchanged")
print("PASS Part 2: state thresholds, LOS cache/blocking/filter, directional chase/confirmation, multiplier cap, real stamina integration, server trip ownership/release, event transitions, RNG intervals and cooldowns")

-- Survivor powers integrate with the actual Fear/Stamina loops.
round.RoundPrepared.Event:Fire()
cfg.MaxProximityFearPerSecond=proximityRate
fear.AddFear(subject,60)
subject.Character:SetAttribute("PowerFearHidden",true)
local hiddenFear=fear.GetFear(subject)
casts=raycasts
for _=1,10 do heartbeat:Fire(0.2) end
near(fear.GetFear(subject),hiddenFear,"cloak preserves tension while suspending detection")
assert(raycasts==casts and not subject:GetAttribute("FearLineOfSight") and not subject:GetAttribute("FearChase"))
fear.AddFear(subject,20); near(fear.GetFear(subject),hiddenFear,"cloak suppresses external fear sources")
subject.Character:SetAttribute("PowerFearHidden",nil)
heartbeat:Fire(0.4); assert(fear.GetFear(subject)>hiddenFear,"detection resumes after cloak")
prepareEffectTrial()
subject.Character:SetAttribute("PowerStunImmune",true)
local previousTrips=trips
for _=1,16 do root.AssemblyLinearVelocity=position(30); heartbeat:Fire(0.2) end
assert(trips==previousTrips,"stance prevents Fear trip")
subject.Character:SetAttribute("PowerStunImmune",nil)
round.RoundPrepared.Event:Fire()
subject.Character:SetAttribute("PowerInfiniteStamina",true)
sprintIntent:Fire(subject,true)
for _=1,20 do root.AssemblyLinearVelocity=position(30); heartbeat:Fire(0.1) end
near(stamina.Get(subject),100,"rush never drains stamina")
assert(root:GetAttribute("CanSprint")==true)
subject.Character:SetAttribute("PowerInfiniteStamina",nil)
heartbeat:Fire(0.1); assert(stamina.Get(subject)<100,"normal drain resumes")
print("PASS survivor integration: cloak detection/external-source gates, stance prevents trips, infinite stamina and normal recovery")

-- Real DamageSystem hook: bounded personal shock and visible witness reactions.
local witness = player("Witness", config.Roles.Survivor, 18, 50)
round.RoundPrepared.Event:Fire()
obstacle = nil
local damage = modules.DamageSystem.DamageApplied.Event
damage:Fire(monster, subject, 25, false, "Monster")
near(fear.GetFear(subject), (cfg.DamageFearBase + 25 * cfg.DamageFearPerHealth)
	* scaling.FearGainMultiplier(subject), "victim gets bounded shock")
local witnessedFear = cfg.WitnessDamageFear * scaling.FearGainMultiplier(witness)
near(fear.GetFear(witness), witnessedFear, "nearby visible witness reacts")
damage:Fire(monster, subject, 25, false, "Monster")
near(fear.GetFear(witness), witnessedFear, "witness hit spam throttled")
obstacle = { CanCollide = true }
damage:Fire(monster, subject, 25, true, "Monster")
near(fear.GetFear(witness), witnessedFear, "walls prevent witnessing death")
obstacle = nil
damage:Fire(monster, subject, 25, true, "Monster")
near(fear.GetFear(witness), witnessedFear + cfg.WitnessDeathFear * scaling.FearGainMultiplier(witness),
	"visible death overrides damage cooldown")
local beforeWitness = fear.GetFear(witness)
witness.Character.children.HumanoidRootPart.Position = position(200)
damage:Fire(monster, subject, 25, true, "Monster")
near(fear.GetFear(witness), beforeWitness, "distant survivor does not witness")
active = false
damage:Fire(monster, subject, 25, true, "Monster")
near(fear.GetFear(witness), 0, "inactive rounds ignore combat")
print("PASS fear combat: damage shock, line-of-sight witnessing, death, cooldown, distance and round gating")
