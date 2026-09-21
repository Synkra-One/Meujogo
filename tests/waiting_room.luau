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
	function result:WaitForChild(name) return children[name] end
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
-- IsStudio = false: este teste simula um servidor PUBLICADO de verdade, onde
-- isDevRoleTester continua exigindo o UserId da lista (a válvula de
-- RunService:IsStudio() só relaxa isso dentro do Studio).
local runService = { IsStudio = function() return false end }
local services = { Players = players, ReplicatedStorage = storage, Workspace = workspaceMock, RunService = runService }
local remotes = setmetatable({}, { __index = function(t, key)
	local remote = { OnServerEvent = signal(), events = {} }
	function remote:FireClient(player, ...) table.insert(self.events, { player = player, args = { ... } }) end
	function remote:FireAllClients(...) table.insert(self.events, { args = { ... } }) end
	rawset(t, key, remote)
	return remote
end })
local started = {}
local roundActive = false
local roundStub = { RoundPrepared = { Event = signal() }, RoundEnded = { Event = signal() } }
function roundStub.IsRoundActive() return roundActive end
function roundStub.StartRound(participants)
	table.insert(started, table.clone(participants))
	roundActive = true
	-- Mirrors what the real RoundManager.prepareRound() does before firing
	-- RoundPrepared: CharacterStatsApplier's canSelectDuringRound gate needs
	-- InRound=true on each participant, or character selection never opens.
	for _, p in participants do p:SetAttribute("InRound", true) end
	roundStub.RoundPrepared.Event:Fire(participants)
end
local spawnGameCharacterHook = nil
local modules = { Remotes = remotes, RoundManager = roundStub,
	CharacterPresentation = { SpawnLobbyAvatar = function() end, SpawnGameCharacter = function(p)
		local character = object("Model")
		local root = object("Part"); root.Name = "HumanoidRootPart"; root.Parent = character
		local humanoid = object("Humanoid"); humanoid.Parent = character
		p.Character = character
		if spawnGameCharacterHook then spawnGameCharacterHook(p) end
		return character
	end, AwaitGameCharacterReady = function() end } }
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
	CFrame = { new = function(value) return value end, Angles = function() return setmetatable({}, { __mul = function(a) return a end }) end },
	Enum = { Material = { WoodPlanks = "Wood" }, NormalId = { Back = "Back" }, Font = { GothamBold = "Bold" },
		KeyCode = { E = "E", X = "X", ButtonX = "ButtonX", ButtonB = "ButtonB" } },
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
local function pick(p, id)
	clock += 0.1
	remotes.SelectCharacter.OnServerEvent:Fire(p, "Select", id)
end
local function confirm(p)
	clock += 0.1
	remotes.SelectCharacter.OnServerEvent:Fire(p, "Confirm")
end
local function flushSpawned()
	while #spawned > 0 do
		local pending = spawned
		spawned = {}
		for _, callback in pending do callback() end
	end
end
local function snapshot() return remotes.WaitingRoom.events[#remotes.WaitingRoom.events].args[1] end
local config = loadModule("GameConfig")
local data = loadModule("CharacterData")
local selectionConfig = loadModule("SurvivorSelectionConfig")
local selection = loadModule("CharacterStatsApplier")
local room = loadModule("WaitingRoomManager")
selection.Init()
room.Init()
local first, second = data.Characters[1].Id, data.Characters[2].Id
local alice, bob, outsider = player(1), player(2), player(3)

pick(alice, first)
assert(selection.GetChoice(alice) == nil, "Lobby must not accept character selections")
room.Join(alice)
room.Join(bob)
assert(alice.Character.LastPivot == nil, "Joining must keep the player in the lobby")
-- Character choice now opens only after the round is prepared (InRound +
-- CharacterSelectOpen); being in the waiting room alone must not be enough.
pick(alice, first)
assert(selection.GetChoice(alice) == nil, "Waiting room alone must not open character selection")

-- Acesso rápido (MenuBoot.client.luau): o botão só APARECE para
-- GameConfig.Testing.DevRoleUserIds, mas qualquer sessão de teste do Studio
-- (inclusive multi-cliente, onde cada cliente recebe um UserId falso) tem de
-- FUNCIONAR -- por isso o servidor relaxa via RunService:IsStudio().
assert(alice.UserId ~= config.Testing.DevRoleUserIds[1], "sanity: alice não está na lista de UserIds")
request(alice, "DevRole", "Monstro")
assert(alice:GetAttribute("DevForceRole") == nil, "fora do Studio, só a lista de UserId vale")
runService.IsStudio = function() return true end
request(alice, "DevRole", "Monstro")
assert(alice:GetAttribute("DevForceRole") == config.Roles.Monster,
	"dentro do Studio, qualquer cliente de teste pode forçar o papel")
request(alice, "DevRole", "Random")
assert(alice:GetAttribute("DevForceRole") == nil, "\"Random\" limpa a forçagem")
runService.IsStudio = function() return false end
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
-- AssignMissing is the one entry point that populates a reservation without
-- going through the round-gated remote; used here to give bob something for
-- leaving to release.
assert(selection.AssignMissing({ bob }))
assert(selection.GetChoice(bob) == first, "AssignMissing must hand out the first free character")
request(bob, "Leave")
assert(selection.GetChoice(bob) == nil and selection.GetRoster()[first] == nil, "Leaving releases the reservation")
assert(bob.Character.LastPivot == nil, "Leaving must keep the player in the lobby")
room.Join(bob)
request(bob, "Ready")
advance(11 + selectionConfig.RoleRevealDuration)
assert(#started == 1 and #started[1] == 2, "Only room members start the round")
assert(started[1][1] ~= outsider and started[1][2] ~= outsider)
-- The round is now active: CharacterStatsApplier opened CharacterSelectOpen
-- for alice and bob (neither had chosen yet), so selection finally works.
assert(alice:GetAttribute("InRound") and bob:GetAttribute("InRound"), "Starting the round must set InRound")
pick(alice, first)
pick(bob, first)
assert(selection.GetChoice(alice) == first and selection.GetChoice(bob) == nil, "Simultaneous claims must have one winner")
-- A rejected claim leaves the window open (CharacterSelectOpen only closes
-- on an accepted pick), so bob can still claim a different character.
pick(bob, second)
assert(selection.GetChoice(bob) == second, "A rejected claim can still pick a free character")
pick(alice, second)
request(alice, "Skin", "Padrao")
assert(selection.GetChoice(alice) == first and alice:GetAttribute("SkinId") == "Noturno", "Selection window closes after the first accepted pick")
room.Join(outsider)
assert(outsider:GetAttribute("InWaitingRoom") == nil, "Late joins stay in lobby")
request(outsider, "Sync")
assert(snapshot().state == "Playing" and #snapshot().members == 2, "Late client handshake gets current state")
room.Reset()
assert(next(selection.GetRoster()) == nil and alice:GetAttribute("SkinId") == nil, "Reset clears loadout and reservations")
room.Join(outsider)
assert(outsider:GetAttribute("InWaitingRoom") == nil, "Returning respawns cannot overlap the next round")
room.OpenLobby()

-- Capacity is bounded by the actual roster, even though Players.Max is 10.
local full = { alice, bob, outsider }
for i = 4, 8 do table.insert(full, player(i)) end
for _, p in full do room.Join(p) end
assert(#snapshot().members == 7 and full[8]:GetAttribute("InWaitingRoom") == nil)
assert(not selection.AssignMissing(full), "No fallback may assign duplicate characters")
assert(selection.AssignMissing({ alice }))
players.PlayerRemoving:Fire(alice)
assert(selection.GetRoster()[first] == nil, "Disconnect releases a character")
room.Join(full[8])
assert(selection.AssignMissing({ full[8] }))
assert(selection.GetChoice(full[8]) == first, "Disconnected player's slot is reusable")
room.Reset()
room.OpenLobby()

-- The production minimum must be respected independently of server population.
config.Testing.SoloStart = false
room.Join(bob)
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
modules.RadioSiteSystem = { Reset = function() end }
modules.ExtractionSystem = { Reset = function() end, Begin = function() return true end,
	SurvivorsExtracted = { Event = signal() } }
modules.RoleAssignment = { AssignRoles = function(list)
	for _, p in list do p:SetAttribute("Role", config.Roles.Survivor) end
end }
modules.RoundManager = nil
local realRound = loadModule("RoundManager")
realRound.Init()
realRound.SetSpawnHandler(function() end)
config.Testing.SoloStart = true
for _, phase in config.Phases do phase.Default = 0 end
local prepared = nil
realRound.RoundPrepared.Event:Connect(function(list) prepared = list end)
-- Character choice now happens only after the round starts (see the
-- CharacterStatsApplier scenario above), so RoundManager no longer guards
-- StartRound against duplicate CharacterId attributes -- that check was
-- deliberately removed when the redesign moved exclusivity into setChoice.
-- CharacterPresentation.SpawnGameCharacter (not Player:LoadCharacter, which
-- RoundManager no longer calls) is the current yield point during prep.
local raced = false
spawnGameCharacterHook = function(p)
	if p ~= bob then return end
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
print("PASS: real round concurrent preparation guard, late arrival isolation, participant-only HUD events")
