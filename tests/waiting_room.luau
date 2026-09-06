-- Roblox service doubles. The runner injects the real module sources above.
local function signal()
	local listeners = {}
	return {
		Connect = function(_, callback) table.insert(listeners, callback) end,
		Fire = function(_, ...) for _, callback in listeners do callback(...) end end,
	}
end
local function object(class)
	local attributes, children = {}, {}
	local result = { ClassName = class, Name = class }
	function result:SetAttribute(key, value) attributes[key] = value end
	function result:GetAttribute(key) return attributes[key] end
	function result:FindFirstChild(name) return children[name] end
	function result:FindFirstChildOfClass(name)
		for _, child in children do if child.ClassName == name then return child end end
		return nil
	end
	function result:IsA(name) return name == class or (name == "BasePart" and class == "Part") end
	function result:PivotTo(cf) self.LastPivot = cf end
	result._children = children
	return setmetatable(result, { __newindex = function(t, key, value)
		rawset(t, key, value)
		if key == "Parent" and value and value._children then value._children[t.Name] = t end
	end })
end
local vectorMeta = { __add = function(a, b) return { X = a.X + b.X, Y = a.Y + b.Y, Z = a.Z + b.Z } end }
local Vector3Mock = { new = function(x, y, z) return setmetatable({ X = x, Y = y, Z = z }, vectorMeta) end }
local Color3Mock = { fromRGB = function(...) return { ... } end, new = function(...) return { ... } end }
local clock = 100
local delayed = {}
local spawned = {}
local Tasks = {
	delay = function(seconds, callback) table.insert(delayed, { at = clock + seconds, callback = callback }) end,
	defer = function(callback) callback() end,
	spawn = function(callback) table.insert(spawned, callback) end,
	wait = function(seconds) clock += seconds or 0 end,
}
local function advance(seconds)
	clock += seconds
	local previous = delayed
	delayed = {}
	for _, pending in previous do
		if pending.at <= clock then pending.callback() else table.insert(delayed, pending) end
	end
end
local players = object("Players")
players.PlayerAdded = signal()
players.PlayerRemoving = signal()
local playerList = {}
function players:GetPlayers() return table.clone(playerList) end
local storage = object("ReplicatedStorage")
storage.Modules = setmetatable({}, { __index = function(_, key) return key end })
local workspaceMock = object("Workspace")
function workspaceMock:GetServerTimeNow() return clock end
local lobby = object("Part")
lobby.Name = "LobbySpawn"
lobby.CFrame = Vector3Mock.new(0, 10, -400)
lobby.Parent = workspaceMock
local services = { Players = players, ReplicatedStorage = storage, Workspace = workspaceMock }
local remotes = setmetatable({}, { __index = function(t, key)
	local remote = { OnServerEvent = signal(), events = {} }
	function remote:FireClient(player, ...) table.insert(self.events, { player = player, args = { ... } }) end
	function remote:FireAllClients(...) table.insert(self.events, { args = { ... } }) end
	rawset(t, key, remote)
	return remote
end })
local started = {}
local roundStub = { RoundPrepared = { Event = signal() }, RoundEnded = { Event = signal() } }
function roundStub.IsRoundActive() return false end
function roundStub.StartRound(participants)
	table.insert(started, table.clone(participants))
	roundStub.RoundPrepared.Event:Fire(participants)
end
local modules = { Remotes = remotes, RoundManager = roundStub }
local environment = setmetatable({
	game = { GetService = function(_, name) return assert(services[name], name) end },
	script = { Parent = storage.Modules },
	Instance = { new = function(class)
		if class == "BindableEvent" then
			local event = signal()
			return { Event = event, Fire = function(_, ...) event:Fire(...) end }
		end
		return object(class)
	end },
	Color3 = Color3Mock, Vector3 = Vector3Mock,
	UDim2 = { fromScale = function(...) return { ... } end },
	CFrame = { new = function(value) return value end },
	Enum = { Material = { WoodPlanks = "Wood" }, NormalId = { Back = "Back" }, Font = { GothamBold = "Bold" } },
	Random = { new = function() return { NextInteger = function(_, min) return min end } end },
	task = Tasks, os = { clock = function() return clock end, time = function() return clock end },
	warn = function(...) print("WARN", ...) end,
}, { __index = getfenv() })
local function loadModule(name)
	if modules[name] then return modules[name] end
	local chunk = assert(loadstring(sources[name], name))
	setfenv(chunk, environment)
	local module = chunk()
	modules[name] = module
	return module
end
environment.require = loadModule
local function player(id)
	local p = object("Player")
	p.UserId, p.Name, p.DisplayName = id, "Player" .. id, "Jogador " .. id
	p.CharacterAdded = signal()
	p.Parent = players
	p.Character = object("Model")
	function p:LoadCharacter() self.Loads = (self.Loads or 0) + 1 end
	table.insert(playerList, p)
	players.PlayerAdded:Fire(p)
	return p
end
local function request(p, action, value)
	clock += 0.2
	remotes.WaitingRoom.OnServerEvent:Fire(p, action, value)
end
local function pick(p, id) remotes.SelectCharacter.OnServerEvent:Fire(p, id) end
local function snapshot() return remotes.WaitingRoom.events[#remotes.WaitingRoom.events].args[1] end
local config = loadModule("GameConfig")
local data = loadModule("CharacterData")
local selection = loadModule("CharacterStatsApplier")
local room = loadModule("WaitingRoomManager")
selection.Init()
room.Init()
local first, second = data.Characters[1].Id, data.Characters[2].Id
local alice, bob, outsider = player(1), player(2), player(3)

pick(alice, first)
assert(selection.GetChoice(alice) == nil, "Lobby must not accept character selections")
room.Join(alice, false)
assert(alice:GetAttribute("InWaitingRoom") == nil, "Test host restriction must remain")
room.Join(alice, true)
room.Join(bob, false)
assert(alice.Character.LastPivot.X ~= 0, "Joining must teleport to the waiting room")
pick(alice, first)
pick(bob, first)
assert(selection.GetChoice(alice) == first and selection.GetChoice(bob) == nil, "Simultaneous claims must have one winner")
pick(alice, second)
pick(bob, first)
assert(selection.GetChoice(bob) == first, "Switching must release the previous character")
request(alice, "Skin", "Explorador")
request(alice, "Perk", "Folego")
request(alice, "Perk", "FAKE")
assert(alice:GetAttribute("PerkId") == "Folego", "Reject unknown perks")
request(outsider, "Ready")
request(outsider, "Skin", "Noturno")
assert(outsider:GetAttribute("SkinId") == nil, "Outsiders cannot change a loadout")
request(alice, "Ready")
request(bob, "Ready")
assert(snapshot().endsAt > 0, "Everyone ready starts the countdown")
request(alice, "Skin", "Noturno")
assert(snapshot().endsAt == 0 and not alice:GetAttribute("MatchReady"), "Loadout changes cancel readiness")
advance(11)
assert(#started == 0, "A canceled timer cannot start the round")
request(alice, "Ready")
request(bob, "Leave")
assert(selection.GetChoice(bob) == nil and selection.GetRoster()[first] == nil, "Leaving releases the reservation")
assert(bob.Character.LastPivot.Z == -400, "Leaving returns to lobby")
room.Join(bob, false)
pick(bob, first)
request(bob, "Ready")
advance(11)
assert(#started == 1 and #started[1] == 2, "Only room members start the round")
assert(started[1][1] ~= outsider and started[1][2] ~= outsider)
pick(alice, first)
request(alice, "Skin", "Padrao")
assert(selection.GetChoice(alice) == second and alice:GetAttribute("SkinId") == "Noturno", "Loadout is locked after countdown")
room.Join(outsider, true)
assert(outsider:GetAttribute("InWaitingRoom") == nil, "Late joins stay in lobby")
request(outsider, "Sync")
assert(snapshot().state == "Playing" and #snapshot().members == 2, "Late client handshake gets current state")
room.Reset()
assert(next(selection.GetRoster()) == nil and alice:GetAttribute("SkinId") == nil, "Reset clears loadout and reservations")
room.Join(outsider, true)
assert(outsider:GetAttribute("InWaitingRoom") == nil, "Returning respawns cannot overlap the next round")
room.OpenLobby()

-- Capacity is bounded by the actual roster, even though Players.Max is 10.
local full = { alice, bob, outsider }
for i = 4, 8 do table.insert(full, player(i)) end
for _, p in full do room.Join(p, true) end
assert(#snapshot().members == 7 and full[8]:GetAttribute("InWaitingRoom") == nil)
assert(not selection.AssignMissing(full), "No fallback may assign duplicate characters")
pick(alice, first)
players.PlayerRemoving:Fire(alice)
assert(selection.GetRoster()[first] == nil, "Disconnect releases a character")
room.Join(full[8], true)
pick(full[8], first)
assert(selection.GetChoice(full[8]) == first, "Disconnected player's slot is reusable")
room.Reset()
room.OpenLobby()

-- The production minimum must be respected independently of server population.
config.Testing.SoloStart = false
room.Join(bob, true)
pick(bob, first)
request(bob, "Ready")
advance(11)
assert(#started == 1 and snapshot().endsAt == 0, "Below minimum cannot start")
room.Reset()
room.OpenLobby()

-- Perks apply mechanically only during the match, never in the lobby.
local scaling = loadModule("StatScaling")
bob:SetAttribute("PerkId", "Folego")
local base = scaling.StaminaRegen(bob)
bob:SetAttribute("InRound", true)
assert(math.abs(scaling.StaminaRegen(bob) - base * 1.1) < 0.0001)
bob:SetAttribute("PerkId", "Resistente")
local reduced = scaling.DamageTakenMultiplier(bob)
bob:SetAttribute("InRound", nil)
assert(math.abs(reduced - scaling.DamageTakenMultiplier(bob) * 0.95) < 0.0001)
print("PASS: lobby gates, exclusivity, switching, loadout validation, ready/cancel, stale timers, leaving, participants, late joins, reset, capacity, disconnect, minimum, perk effects")

-- Exercise the real round entry point: snapshot isolation and preparation guard.
modules.Elimination = { Reset = function() end, IsEliminated = function() return false end }
modules.RadioObjective = { Reset = function() end, RescueCountdownStarted = { Event = signal() } }
modules.RaftObjective = { Reset = function() end, RaftEscaped = { Event = signal() } }
modules.RoleAssignment = { AssignRoles = function(list)
	for _, p in list do p:SetAttribute("Role", config.Roles.Survivor) end
end }
modules.RoundManager = nil
local realRound = loadModule("RoundManager")
realRound.Init()
config.Testing.SoloStart = true
for _, phase in config.Phases do phase.Default = 0 end
local prepared = nil
realRound.RoundPrepared.Event:Connect(function(list) prepared = list end)
bob:SetAttribute("CharacterId", first)
outsider:SetAttribute("CharacterId", first)
assert(not pcall(realRound.StartRound, { bob, outsider }), "Round must independently reject duplicates")
outsider:SetAttribute("CharacterId", second)
local raced = false
function bob:LoadCharacter()
	raced = true
	assert(not pcall(realRound.StartRound, { bob, outsider }), "A yield during preparation must not permit a second round")
	player(99) -- Arrives while the participants are loading.
end
remotes.RoundStateChanged.events = {}
realRound.StartRound({ bob, outsider })
assert(raced and prepared and #prepared == 2, "Preparation must preserve the room's participant snapshot")
for _, event in remotes.RoundStateChanged.events do
	assert(event.player == bob or event.player == outsider, "Lobby players must not receive gameplay UI events")
end
assert(not realRound.IsRoundActive(), "Round state must be cleaned up at completion")
print("PASS: real round duplicate rejection, concurrent preparation guard, late arrival isolation, participant-only HUD events")
