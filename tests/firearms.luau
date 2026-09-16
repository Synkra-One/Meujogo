-- Deterministic service simulation; executes actual server modules, not a copy of the logic.
local function signal()
	local listeners = {}
	local s = {}
	function s:Connect(callback)
		local connection = { Connected = true }
		function connection:Disconnect() self.Connected = false end
		table.insert(listeners, { callback, connection })
		return connection
	end
	function s:Once(callback)
		local connection
		connection = self:Connect(function(...) connection:Disconnect(); callback(...) end)
		return connection
	end
	function s:Fire(...)
		for _, item in table.clone(listeners) do if item[2].Connected then item[1](...) end end
	end
	return s
end

local V, vectorMeta = {}, {}
function V.new(x, y, z) return setmetatable({ X = x or 0, Y = y or 0, Z = z or 0, _kind = "Vector3" }, vectorMeta) end
vectorMeta.__add = function(a, b) return V.new(a.X + b.X, a.Y + b.Y, a.Z + b.Z) end
vectorMeta.__sub = function(a, b) return V.new(a.X - b.X, a.Y - b.Y, a.Z - b.Z) end
vectorMeta.__mul = function(a, b) return V.new(a.X * b, a.Y * b, a.Z * b) end
vectorMeta.__index = function(a, key)
	if key == "Magnitude" then return math.sqrt(a.X^2 + a.Y^2 + a.Z^2) end
	if key == "Unit" then return a * (1 / a.Magnitude) end
end
V.zero = V.new()
local CF, cfMeta = {}, {}
function CF.new(x, y, z)
	return setmetatable({ Position = if type(x) == "table" then x else V.new(x, y, z), LookVector = V.new(0, 0, -1) }, cfMeta)
end
function CF.lookAt(origin, target) local cf = CF.new(origin); cf.LookVector = (target-origin).Unit; return cf end
function CF.Angles() return CF.new() end
cfMeta.__mul = function(a, b) local cf = CF.new(a.Position + b.Position); cf.LookVector = a.LookVector; return cf end
cfMeta.__index = { Inverse = function(a) return CF.new(a.Position * -1) end }

local function object(class, name, parent)
	local props = { ClassName = class, Name = name or class, _kind = "Instance", CFrame = CF.new(), Size = V.new(1, 1, 1) }
	local children, attributes, attributeSignals = {}, {}, {}
	local methods = {}
	for _, key in { "Changed", "AncestryChanged", "ChildAdded", "ChildRemoved", "DescendantAdded", "Destroying", "Died", "HealthChanged", "Triggered", "CharacterAdded", "CharacterRemoving", "PlayerAdded", "PlayerRemoving" } do
		props[key] = signal()
	end
	local self
	function methods:IsA(kind)
		return kind == class or kind == "Instance" or (kind == "BasePart" and (class == "Part" or class == "MeshPart" or class == "SpawnLocation"))
			or (kind == "Model" and class == "Tool") or (kind == "ValueBase" and (class == "NumberValue" or class == "BoolValue"))
	end
	function methods:GetChildren() return table.clone(children) end
	function methods:GetDescendants()
		local list = {}
		for _, child in children do table.insert(list, child); for _, descendant in child:GetDescendants() do table.insert(list, descendant) end end
		return list
	end
	function methods:FindFirstChild(key)
		for _, child in children do if child.Name == key then return child end end
		return nil
	end
	function methods:WaitForChild(key) return assert(self:FindFirstChild(key), self.Name .. "/" .. key) end
	function methods:FindFirstChildOfClass(kind)
		for _, child in children do if child:IsA(kind) then return child end end
		return nil
	end
	function methods:IsDescendantOf(ancestor)
		local current = props.Parent
		while current do
			if current == ancestor then return true end
			current = current.Parent
		end
		return false
	end
	function methods:GetAttribute(key) return attributes[key] end
	function methods:SetAttribute(key, value)
		attributes[key] = value
		if attributeSignals[key] then attributeSignals[key]:Fire() end
	end
	function methods:GetAttributeChangedSignal(key)
		attributeSignals[key] = attributeSignals[key] or signal()
		return attributeSignals[key]
	end
	function methods:GetPivot() return props.CFrame end
	function methods:PivotTo(cf)
		local delta = cf.Position - props.CFrame.Position
		props.CFrame = cf
		for _, p in self:GetDescendants() do if p:IsA("BasePart") then p.Position += delta end end
	end
	function methods:Clone()
		local clone = object(class, props.Name)
		for key, value in props do
			if key ~= "Parent" and key ~= "_destroyed" and key ~= "_remove" and (type(value) ~= "table" or value._kind == "Vector3" or key == "CFrame") then clone[key] = value end
		end
		for key, value in attributes do clone:SetAttribute(key, value) end
		for _, child in children do child:Clone().Parent = clone end
		return clone
	end
	function methods:Destroy()
		if props._destroyed then return end
		props._destroyed = true
		props.Destroying:Fire()
		for _, child in table.clone(children) do child:Destroy() end
		self.Parent = nil
	end
	function methods:TakeDamage(amount) self.Health = math.max(0, self.Health - amount) end
	function methods:Emit() end
	function methods:Play() end
	function methods:_remove(child)
		local index = table.find(children, child)
		if index then table.remove(children, index) end
	end
	function methods:_add(child) table.insert(children, child) end
	self = setmetatable({}, {
		__index = function(_, key)
			if key == "Position" then return props.CFrame.Position end
			if props[key] ~= nil then return props[key] end
			return methods[key] or methods.FindFirstChild(self, key)
		end,
		__newindex = function(_, key, value)
			local old = props[key]
			if key == "Position" then props.CFrame = CF.new(value); return end
			props[key] = value
			if key == "Parent" then
				if old then old:_remove(self); old.ChildRemoved:Fire(self) end
				if value then
					value:_add(self); value.ChildAdded:Fire(self)
					local ancestor = value
					while ancestor do
						ancestor.DescendantAdded:Fire(self)
						for _, descendant in self:GetDescendants() do ancestor.DescendantAdded:Fire(descendant) end
						ancestor = ancestor.Parent
					end
				end
				props.AncestryChanged:Fire(self, value)
			elseif key == "Value" then props.Changed:Fire(value)
			elseif key == "Health" then
				props.HealthChanged:Fire(value)
				if old and old > 0 and value <= 0 then props.Died:Fire() end
			end
		end,
	})
	if parent then self.Parent = parent end
	return self
end

local now, delayed = 100, {}
local function delay(seconds, callback, ...)
	table.insert(delayed, { at = now + seconds, callback = callback, args = table.pack(...) })
end
local function advance(seconds)
	local limit = now + seconds
	while true do
		table.sort(delayed, function(a, b) return a.at < b.at end)
		local first = delayed[1]
		if not first or first.at > limit then break end
		table.remove(delayed, 1); now = first.at; first.callback(table.unpack(first.args, 1, first.args.n))
	end
	now = limit
end
local workspace = object("Workspace")
local players = object("Players")
local storage = object("ReplicatedStorage")
storage.Modules = setmetatable({}, { __index = function(_, key) return key end })
local playerList = {}
function players:GetPlayers() return table.clone(playerList) end
function players:GetPlayerFromCharacter(model)
	for _, p in playerList do if p.Character == model then return p end end
	return nil
end
local rayCalls, traces, hits = 0, 0, 0
local rayResult, obstruction = nil, nil
function workspace:Raycast(_, direction)
	rayCalls += 1
	return if direction.Magnitude < 8 then obstruction else rayResult
end
local remotes = setmetatable({}, { __index = function(t, key)
	local r = { OnServerEvent = signal(), events = {} }
	function r:FireClient(player, ...) table.insert(self.events, { player = player, args = { ... } }) end
	rawset(t, key, r); return r
end })
local modules = {
	Remotes = remotes,
	ItemRegistry = { Items = {} },
	ToolFactory = { Create = function() return nil end },
	-- Status behavior is exercised against the real module in survivor_powers.luau.
	SurvivorPowerStatus = { BeginAttack = function() return false end, BlockAttack = function() return false end,
		Active = function() return false end, Stun = function() return false end, Emit = function() end },
	OTSEffects = { CreateTracer = function() traces += 1 end, CreateImpact = function() end },
	DamageSystem = {
		IsDamageable = function(model) return model:FindFirstChildOfClass("Humanoid").Health > 0 end,
		Apply = function(humanoid, damage)
			hits += 1
			local before = humanoid.Health
			humanoid:TakeDamage(damage)
			return before-humanoid.Health, humanoid.Health <= 0
		end,
	},
}
local services = { Workspace = workspace, Players = players, ReplicatedStorage = storage, Debris = { AddItem = function(_, item, seconds) delay(seconds, function() item:Destroy() end) end } }
local enum = setmetatable({}, { __index = function(t, key)
	local item = setmetatable({}, { __index = function(_, value) return value end }); rawset(t, key, item); return item
end })
local environment = setmetatable({
	game = { GetService = function(_, key) return assert(services[key], key) end },
	workspace = workspace, script = { Parent = storage.Modules }, Enum = enum,
	Instance = { new = function(class) return object(class) end },
	Vector3 = V, CFrame = CF, Color3 = { new = function(...) return {...} end, fromRGB = function(...) return {...} end },
	UDim = { new = function(...) return {...} end },
	UDim2 = { fromScale = function(...) return {...} end, fromOffset = function(...) return {...} end },
	Random = { new = function() return { NextNumber = function() return 0 end } end },
	RaycastParams = { new = function() return {} end },
	os = { clock = function() return now end },
	task = { delay = delay, defer = function(callback, ...) delay(0, callback, ...) end },
	typeof = function(value) return if type(value) == "table" then value._kind or "table" else type(value) end,
}, { __index = getfenv() })
local function loadModule(name)
	if not modules[name] then
		local chunk = assert(loadstring(sources[name], name)); setfenv(chunk, environment); modules[name] = chunk()
	end
	return modules[name]
end
environment.require = loadModule

-- These reserve scenarios start empty, independently of the game's spawn loadout.
loadModule("GameConfig").Firearms.StartingReserve.Pistola = 0

local assets = object("Folder", "WeaponAssets", storage)
local templates = object("Folder", "Tools", assets)
object("Folder", "Audios", assets)
local template = object("Tool", "Glock17", templates)
object("BoolValue", "Weapon", template).Value = true
local handle = object("Part", "Handle", template)
handle.Anchored, handle.CanCollide, handle.CanTouch = false, false, false
local settings = object("Folder", "Settings", template)
local config = object("Folder", "Config", settings)
object("NumberValue", "Ammo", config).Value = 17
object("NumberValue", "MaxAmmo", config).Value = 17
object("NumberValue", "Delay", config).Value = 0.06
object("NumberValue", "Spread", config).Value = 3
object("NumberValue", "Recoil", config).Value = 0.4
object("NumberValue", "AimFOV", config).Value = 62
object("BoolValue", "Reloading", config).Value = false
local components = object("Folder", "Components", template)
object("Part", "Muzzle", components).Position = V.new(0, 2, -1)
object("Part", "Mag", components)
local spawn = object("SpawnLocation", "LobbySpawn", workspace)
spawn.Position, spawn.Size = V.new(0, 10.5, -400), V.new(8, 1, 8)
local function player(name)
	local p = object("Player", name, players)
	p.Character = object("Model", name, workspace)
	local hum = object("Humanoid", "Humanoid", p.Character)
	hum.Health, hum.MaxHealth = 100, 100
	object("Part", "HumanoidRootPart", p.Character)
	object("Part", "Head", p.Character).Position = V.new(0, 2, 0)
	object("Backpack", "Backpack", p)
	function hum:UnequipTools()
		for _, child in p.Character:GetChildren() do if child:IsA("Tool") then child.Parent = p.Backpack end end
	end
	table.insert(playerList, p)
	players.PlayerAdded:Fire(p)
	return p
end
local alice, bob = player("Alice"), player("Bob")
local ammoSystem, drop, server = loadModule("AmmoSystem"), loadModule("DropItemSystem"), loadModule("OTSFirearmService")
ammoSystem.Init(); drop.Init(); server.Init(); server.Init()
local rules = loadModule("OTSRules")
assert(rules.ShotInterval(template) == 0.06 and rules.Spread(template) == 3
	and rules.Recoil(template) == 0.4 and rules.AimFOV(template) == 62,
	"OTS settings must come from the Glock17 Tool")
local pistol = template:Clone(); pistol.Parent = alice.Character
local mag = pistol.Settings.Config.Ammo
local function shoot(target)
	remotes.FirearmShoot.OnServerEvent:Fire(alice, pistol, target or V.new(0, 2, -80), true, 1)
end

local target = object("Model", "Target", workspace)
target:SetAttribute("FirearmTestTarget", true)
local targetHum = object("Humanoid", "Humanoid", target); targetHum.Health = 100
local targetHead = object("Part", "Head", target); targetHead.Position = V.new(0, 2, -80)
rayResult = { Instance = targetHead, Position = targetHead.Position, Normal = V.new(0, 0, 1) }
shoot()
assert(mag.Value == 16 and hits == 1 and traces == 1, "A shot must debit exactly one bullet and damage once")
shoot(); assert(mag.Value == 16 and hits == 1, "Fire rate spam must not deal damage")
advance(0.2)
shoot(V.new(0/0, 0, 0)); shoot(V.new(math.huge, 0, 0)); shoot(V.new(0, 0, -9000))
assert(mag.Value == 16 and hits == 1, "Reject nonfinite/out-of-range aim points")
remotes.FirearmDamage.OnServerEvent:Fire(alice, targetHead)
assert(hits == 1 and traces == 1, "Server-to-client feedback remote cannot forge damage")
remotes.FirearmShoot.OnServerEvent:Fire(bob, pistol, targetHead.Position, true, 1)
assert(mag.Value == 16, "Cannot fire another player's gun")
pistol.Parent = alice.Backpack; shoot(); assert(mag.Value == 16, "Cannot shoot an unequipped gun")
pistol.Parent = alice.Character
alice:SetAttribute("Amarrado", true); shoot(); assert(mag.Value == 16, "Restrained player cannot fire")
alice:SetAttribute("Amarrado", nil)
alice.Character:SetAttribute("PowerStunned", true); shoot(); assert(mag.Value == 16, "Stunned player cannot fire")
alice.Character:SetAttribute("PowerStunned", nil)
alice:SetAttribute("InWaitingRoom", true); shoot(); assert(mag.Value == 16, "Waiting-room player cannot fire")
alice:SetAttribute("InWaitingRoom", nil)
mag.Value = 0; shoot(); assert(hits == 1, "Empty gun cannot deal damage")
mag.Value = 17
local wall = object("Part", "Wall", workspace)
obstruction = { Instance = wall, Position = V.new(0, 2, -0.5), Normal = V.new(0, 0, 1) }
shoot(); assert(mag.Value == 16 and hits == 1, "Head-to-muzzle wall prevents shooting through cover")
obstruction = nil
advance(0.2)
rayResult.Instance = bob.Character.Head
pistol:SetAttribute("LobbyTestWeapon", true)
alice:SetAttribute("InRound", true); bob:SetAttribute("InRound", true)
shoot(); assert(bob.Character.Humanoid.Health == 100, "Test weapon cannot damage a player even in round")
advance(0.2)
pistol.Parent = alice.Character
rayResult.Instance = targetHead
alice:SetAttribute("InWaitingRoom", true)
shoot(); assert(hits == 2, "Lobby test weapon must fire at its training target")
alice:SetAttribute("InWaitingRoom", nil)
advance(0.2)
pistol:SetAttribute("LobbyTestWeapon", nil); bob:SetAttribute("InRound", nil)
rayResult.Instance = bob.Character.Head
shoot(); assert(bob.Character.Humanoid.Health == 100, "Lobby player must be protected from live weapons")
advance(0.2); bob:SetAttribute("InRound", true); shoot()
assert(bob.Character.Humanoid.Health < 100, "Live weapon should work in round")
alice:SetAttribute("InRound", nil); bob:SetAttribute("InRound", nil)
print("PASS: authoritative shooting, malformed requests, walls, ownership, cadence, lobby isolation")

mag.Value = 4
ammoSystem.AddReserve(alice, "Pistola", 8)
local function reload(action) remotes.FirearmReload.OnServerEvent:Fire(alice, pistol, action or "Start") end
reload("End"); assert(mag.Value == 4, "Old End marker cannot refill ammo")
reload(); reload()
assert(pistol:GetAttribute("FirearmReloading") == true)
advance(0.5)
assert(pistol.Components.Mag.Transparency == 1)
shoot(); assert(mag.Value == 4, "No firing during reload")
advance(1.69); assert(mag.Value == 4, "Reload cannot finish early")
advance(0.02)
assert(mag.Value == 12 and ammoSystem.GetReserve(alice, "Pistola") == 0,
	`Reload consumes only existing reserve, exactly once (mag={mag.Value}, reserve={ammoSystem.GetReserve(alice, "Pistola")})`)
assert(not pistol:GetAttribute("FirearmReloading") and pistol.Components.Mag.Transparency == 0)
reload(); assert(not pistol:GetAttribute("FirearmReloading"), "No reserve means no reload")
ammoSystem.AddReserve(alice, "Pistola", 20)
reload(); advance(0.4); pistol.Parent = alice.Backpack
assert(not pistol:GetAttribute("FirearmReloading") and pistol.Components.Mag.Transparency == 0, "Unequip immediately cancels/restores magazine")
advance(3); assert(mag.Value == 12 and ammoSystem.GetReserve(alice, "Pistola") == 20, "Cancelled timer cannot refill")
pistol.Parent = alice.Character
reload(); advance(0.4); reload("Cancel"); reload()
advance(1.81); assert(mag.Value == 12, "Old reload timer cannot complete the new reload")
advance(0.4); assert(mag.Value == 17 and ammoSystem.GetReserve(alice, "Pistola") == 15)
mag.Value = 2; reload(); alice.Character.Humanoid.Health = 0; advance(3)
assert(mag.Value == 2 and not pistol:GetAttribute("FirearmReloading"), "Death cancels reload")
alice.Character.Humanoid.Health = 100
reload(); alice.CharacterRemoving:Fire(alice.Character); advance(3)
assert(mag.Value == 2 and not pistol:GetAttribute("FirearmReloading"), "Character swap cancels reload")
print("PASS: timed reload, duplicate requests, partial reserve, cancellation, death, character swap")

ammoSystem.ResetReserves(alice)
ammoSystem.AddReserve(alice, "Pistola", 65)
local box = ammoSystem.CreatePickup(V.new(2, 0, 0), "Pistola", 17)
box.MunicaoPrompt.Triggered:Fire(alice)
assert(ammoSystem.GetReserve(alice, "Pistola") == 68 and box:GetAttribute("Quantidade") == 14, "Partial pickup retains leftover rounds")
box.MunicaoPrompt.Triggered:Fire(alice); assert(box.Parent ~= nil, "Full reserve must not consume pickup")
bob.Character.HumanoidRootPart.Position = V.new(100, 0, 0)
box.MunicaoPrompt.Triggered:Fire(bob); assert(ammoSystem.GetReserve(bob, "Pistola") == 0, "Remote pickup spoof must fail distance check")
bob.Character.HumanoidRootPart.Position = V.zero
box.MunicaoPrompt.Triggered:Fire(bob)
assert(box.Parent == nil and ammoSystem.GetReserve(bob, "Pistola") == 14)
print("PASS: ammo pickup distance, capacity, leftovers and single consumption")

local range = loadModule("LobbyFiringRange")
range.Init(); range.Init(); advance(0)
local folder = workspace.TestePistolaLobby
assert(folder and #folder:GetChildren() > 8, "Lobby station must be created")
local testPistol, testBox = folder.Glock17, folder.Municao_Pistola
assert(testPistol and testPistol.Handle.Anchored and testBox:GetAttribute("Quantidade") == 34)
assert(testPistol:GetAttribute("LobbyTestWeapon") and folder:FindFirstChild("Alvo de treino"))
local pickup = testPistol.Handle.PegarPrompt
pickup.Triggered:Fire(alice); assert(testPistol.Parent == folder, "Distant player cannot claim bench pistol")
alice.Character.HumanoidRootPart.Position = testPistol.Handle.Position
pistol.Parent = alice.Backpack
pickup.Triggered:Fire(alice)
assert(testPistol.Parent == alice.Backpack and testPistol.Handle.Anchored == false, "Pickup unanchors pistol before equip")
advance(4); assert(folder.Glock17 == nil, "Picking the pistol must not duplicate it")
local stored = testPistol.Settings.Config.Ammo.Value
remotes.DropItem.OnServerEvent:Fire(alice, testPistol)
assert(testPistol:GetAttribute("_Dropped") == true and not testPistol.Handle.Anchored)
testPistol.Handle.PegarPrompt.Triggered:Fire(alice)
assert(testPistol.Parent == alice.Backpack and testPistol.Settings.Config.Ammo.Value == stored, "Drop/repickup preserves magazine")
testPistol:Destroy(); advance(3.1); assert(folder.Glock17 ~= nil, "Destroyed test pistol replenishes")
alice.Character.HumanoidRootPart.Position = testBox.Position
ammoSystem.ResetReserves(alice)
testBox.MunicaoPrompt.Triggered:Fire(alice)
assert(ammoSystem.GetReserve(alice, "Pistola") == 34 and testBox.Parent == nil)
advance(5.1); assert(folder.Municao_Pistola ~= nil, "Test ammunition replenishes")
local dummy = folder:FindFirstChild("Alvo de treino")
dummy.Humanoid.Health = 0; advance(3.1)
assert(folder:FindFirstChild("Alvo de treino") ~= dummy and folder:FindFirstChild("Alvo de treino").Humanoid.Health == 100)
print("PASS: lobby station, one pistol, pickup/unanchor, drop, ammo and target respawns")
print("All firearm scenarios passed (simulated services; Studio visual/physics testing still required).")
