-- Executed by run_match_tests.rb against the actual modules with a virtual clock.
local function fixture()
	local now, jobs = 0, {}
	local scheduler = {}
	local function resume(thread, ...)
		local ok, delay = coroutine.resume(thread, ...)
		assert(ok, tostring(delay))
		if coroutine.status(thread) ~= "dead" then
			table.insert(jobs, { at = now + (delay or 0.01), thread = thread })
		end
	end
	function scheduler.spawn(callback, ...) resume(coroutine.create(callback), ...) end
	function scheduler.wait(duration) return coroutine.yield(duration or 0.01) end
	function scheduler.delay(duration, callback)
		table.insert(jobs, { at = now + duration, thread = coroutine.create(callback) })
	end
	local function advance(duration)
		local deadline = now + duration
		while true do
			table.sort(jobs, function(a, b) return a.at < b.at end)
			if not jobs[1] or jobs[1].at > deadline then break end
			local job = table.remove(jobs, 1)
			now = job.at
			resume(job.thread)
		end
		now = deadline
	end
	local function signal()
		local listeners = {}
	return {
		Connect = function(_, callback)
			table.insert(listeners, callback)
			return { Disconnect = function() end }
		end,
		Once = function(_, callback)
			local connection
			connection = { Connected = true, Disconnect = function(self) self.Connected = false end }
			table.insert(listeners, function(...)
				if connection.Connected then connection:Disconnect(); callback(...) end
			end)
			return connection
		end,
			Fire = function(_, ...)
				for _, callback in table.clone(listeners) do scheduler.spawn(callback, ...) end
			end,
		}
	end
	local function object()
		local attributes = {}
		return {
			SetAttribute = function(_, key, value) attributes[key] = value end,
			GetAttribute = function(_, key) return attributes[key] end,
			FindFirstChild = function() return nil end,
		}
	end
	local Players = object()
	Players.PlayerAdded, Players.PlayerRemoving = signal(), signal()
	local people = {}
	function Players:GetPlayers() return people end
	local function player(id)
		local p = object()
		p.Parent, p.UserId, p.Name, p.DisplayName = Players, id, "Player" .. id, "Player" .. id
		p.CharacterAdded = signal()
		function p:LoadCharacter()
			self.Character = object()
			self.Character.Destroying = signal()
			self.Character.PivotTo = function() end
			local humanoid = { Died = signal() }
			self.Character.FindFirstChildOfClass = function(_, name)
				return if name == "Humanoid" then humanoid else nil
			end
			self.Character.WaitForChild = function(_, name)
				return if name == "Humanoid" then humanoid else object()
			end
			self.loads = (self.loads or 0) + 1
			self.CharacterAdded:Fire(self.Character)
		end
		p:LoadCharacter()
		table.insert(people, p)
		return p
	end
	local Config = {
		Players = { Min = 2, Max = 10 },
		Testing = { SoloStart = false, DevRoleChooser = true, DevRoleUserIds = { 1 } },
		Roles = { Survivor = "Sobrevivente", Monster = "Monstro", Spy = "Espiao" },
		Round = { MonsterWinsAtSurvivorsAlive = 0, WinCheckInterval = 0.1 },
		PhaseOrder = { "Queda" }, Phases = { Queda = { Default = 100 } },
	}
	local Remotes = setmetatable({}, { __index = function(t, key)
		local remote = { OnServerEvent = signal(), sent = {} }
		function remote:FireClient(...) table.insert(self.sent, { ... }) end
		remote.FireAllClients = remote.FireClient
		rawset(t, key, remote)
		return remote
	end })
	local RS = object()
	RS.Modules = setmetatable({}, { __index = function(_, name) return name end })
	local workspace = object()
	function workspace:GetServerTimeNow() return now end
	local RunService = { IsStudio = function() return false end }
	local ServerScriptService = {}
	function ServerScriptService:WaitForChild(name)
		return if name == "Server" then self else name
	end
	local vector = setmetatable({}, { __add = function(a) return a end })
	local selectionChanged = { Event = signal() }
	local selectionStub = {
		ClearChoice = function(p) p:SetAttribute("CharacterSelectionConfirmed", nil) end,
		GetChoice = function() return nil end,
		GetRoster = function() return {} end,
		IsConfirmed = function(p) return p:GetAttribute("CharacterSelectionConfirmed") == true end,
		SelectionChanged = selectionChanged,
		BeginSelection = function(list)
			for _, p in list do p:SetAttribute("CharacterSelectOpen", true) end
			return true
		end,
		EveryoneConfirmed = function(list)
			for _, p in list do if p:GetAttribute("CharacterSelectionConfirmed") ~= true then return false end end
			return true
		end,
		FinishSelection = function(list)
			for _, p in list do
				p:SetAttribute("CharacterSelectionConfirmed", true)
				p:SetAttribute("CharacterSelectOpen", nil)
			end
			return true
		end,
		CancelSelection = function(list)
			for _, p in list or {} do
				p:SetAttribute("CharacterSelectionConfirmed", nil)
				p:SetAttribute("CharacterSelectOpen", nil)
			end
		end,
		RemoveParticipant = function(p) p:SetAttribute("CharacterSelectOpen", nil) end,
	}
	local modules = {
		GameConfig = Config, Remotes = Remotes,
		Elimination = {
			IsEliminated = function(p) return p:GetAttribute("Eliminado") == true end,
			Reset = function(p) p:SetAttribute("Eliminado", nil) end,
		},
		RadioObjective = { Reset = function() end, RescueCountdownStarted = { Event = signal() } },
		RadioSiteSystem = { Reset = function() end },
		ExtractionSystem = { Reset = function() end, Begin = function() return true end, SurvivorsExtracted = { Event = signal() } },
		CharacterData = { Characters = { 1, 2, 3, 4, 5, 6, 7, 8, 9, 10 } },
		SurvivorSelectionConfig = { Duration = 30, GetSelectableCharacters = function() return { 1, 2, 3, 4, 5, 6, 7, 8, 9, 10 } end },
		LoadoutData = {},
		CharacterStatsApplier = selectionStub,
		CharacterPresentation = {
			SpawnGameCharacter = function(p) p:LoadCharacter(); return p.Character end,
			AwaitGameCharacterReady = function() end,
			SpawnLobbyAvatar = function(p) p:LoadCharacter() end,
		},
	}
	local env = setmetatable({
		game = { GetService = function(_, name)
			return ({
				Players = Players, ReplicatedStorage = RS, Workspace = workspace,
				RunService = RunService, ServerScriptService = ServerScriptService,
			})[name]
		end },
		script = { Parent = setmetatable({}, { __index = function(_, name) return name end }) },
		task = scheduler, os = { clock = function() return now end, time = function() return now end },
		print = function() end, warn = function() end,
		Random = { new = function() return { NextInteger = function(_, a, b) return math.random(a, b) end } end },
		Vector3 = { new = function() return vector end }, Color3 = { fromRGB = function() return {} end },
		CFrame = { new = function() return {} end },
		Enum = { Material = { WoodPlanks = 1 }, NormalId = { Back = 1 }, Font = { GothamBold = 1 } },
		UDim2 = { fromScale = function() return {} end },
		Instance = { new = function(class)
			if class == "RemoteEvent" then return { FireClient = function() end } end
			if class == "BindableEvent" then
				local event = signal()
				return { Event = event, Fire = function(_, ...) event:Fire(...) end }
			end
			return object()
		end },
	}, { __index = getfenv() })
	env.require = function(name)
		if not modules[name] then
			local fn = assert(loadstring(sources[name], name))
			setfenv(fn, env)
			modules[name] = fn()
		end
		return modules[name]
	end
	local round = env.require("RoundManager")
	round.Init()
	round.SetSpawnHandler(function() end)
	return {
		player = player, config = Config, modules = modules, load = env.require, round = round,
		advance = advance, task = scheduler, players = Players, remotes = Remotes, storage = RS,
	}
end

local passed = 0
local function test(name, callback)
	callback()
	passed += 1
	print("PASS " .. name)
end

test("2-10 players always have a monster and survivors; spy requires 3", function()
	for size = 2, 10 do
		for _ = 1, 30 do
			local f, roster, counts = fixture(), {}, {}
			for id = 1, size do table.insert(roster, f.player(id)) end
			roster[1]:SetAttribute("DevForceRole", "Espiao")
			f.load("RoleAssignment").AssignRoles(roster)
			for _, p in roster do
				local role = p:GetAttribute("Role")
				counts[role] = (counts[role] or 0) + 1
			end
			assert(counts.Monstro == 1)
			assert((counts.Espiao or 0) == (if size >= 3 then 1 else 0))
			assert(counts.Sobrevivente == (if size >= 3 then size - 2 else 1))
		end
	end
end)

test("two-player round stays active until the survivor is eliminated", function()
	local f = fixture()
	local roster = { f.player(1), f.player(2) }
	f.task.spawn(function() f.round.StartRound(roster) end)
	f.advance(12)
	assert(f.round.IsRoundActive(), "Round ended immediately")
	for _, p in roster do
		if p:GetAttribute("Role") == "Sobrevivente" then p:SetAttribute("Eliminado", true) end
	end
	f.advance(0.3)
	assert(not f.round.IsRoundActive())
	assert(f.remotes.RoundEnded.sent[1][2] == "Monstro")
end)

test("preparation is awaited and concurrent starts are rejected", function()
	local f = fixture()
	local roster = { f.player(1), f.player(2) }
	local arrived, prepared = false, false
	f.round.SetSpawnHandler(function() f.task.wait(3); arrived = true end)
	f.round.RoundPrepared.Event:Connect(function()
		assert(arrived and f.round.IsRoundActive())
		prepared = true
	end)
	f.task.spawn(function() f.round.StartRound(roster) end)
	f.advance(1)
	assert(not f.round.IsRoundActive() and not prepared)
	assert(not pcall(f.round.StartRound, roster))
	f.advance(3)
	assert(prepared and f.round.IsRoundActive())
end)

test("failed preparation releases the round for a later retry", function()
	local f = fixture()
	local roster = { f.player(1), f.player(2) }
	f.round.SetSpawnHandler(function() error("spawn failed") end)
	assert(not pcall(f.round.StartRound, roster))
	assert(not f.round.IsRoundActive())
	f.round.SetSpawnHandler(function() end)
	f.task.spawn(function() f.round.StartRound(roster) end)
	f.advance(1)
	assert(f.round.IsRoundActive())
end)

test("old rescue timer cannot end the next round", function()
	local f = fixture()
	local roster = { f.player(1), f.player(2) }
	f.task.spawn(function() f.round.StartRound(roster) end)
	f.modules.RadioObjective.RescueCountdownStarted.Event:Fire(5)
	f.advance(0.3)
	f.task.spawn(function() f.round.StartRound(roster) end)
	f.advance(6)
	assert(f.round.IsRoundActive(), "Previous rescue timer ended the new round")
end)

test("monster disconnection resolves the round", function()
	local f = fixture()
	local roster = { f.player(1), f.player(2) }
	f.task.spawn(function() f.round.StartRound(roster) end)
	for _, p in roster do if p:GetAttribute("Role") == "Monstro" then p.Parent = nil end end
	f.advance(0.3)
	assert(not f.round.IsRoundActive())
	assert(f.remotes.RoundEnded.sent[1][2] == "Sobreviventes")
end)

test("any account opens the room; two ready members start one round", function()
	local f = fixture()
	local room = f.load("WaitingRoomManager")
	room.Init()
	local a, b = f.player(200), f.player(300)
	room.Join(a)
	room.Join(a)
	assert(a:GetAttribute("InWaitingRoom") == true)
	f.remotes.WaitingRoom.OnServerEvent:Fire(a, "Ready")
	f.advance(3)
	assert(not f.round.IsRoundActive(), "Started without the second player")
	room.Join(b)
	f.remotes.WaitingRoom.OnServerEvent:Fire(b, "Ready")
	a:SetAttribute("CharacterSelectionConfirmed", true)
	b:SetAttribute("CharacterSelectionConfirmed", true)
	f.modules.CharacterStatsApplier.SelectionChanged.Event:Fire(a, "Confirmed")
	f.advance(3)
	assert(f.round.IsRoundActive() and f.storage:GetAttribute("MatchState") == "Playing")
	assert(a.loads == 2 and b.loads == 2, "Duplicate round or membership")
	local late = f.player(400)
	room.Join(late)
	assert(late:GetAttribute("InWaitingRoom") ~= true)
end)

test("leaving during survivor selection cancels it", function()
	local f = fixture()
	local room = f.load("WaitingRoomManager")
	room.Init()
	local a, b = f.player(200), f.player(300)
	room.Join(a); room.Join(b)
	f.remotes.WaitingRoom.OnServerEvent:Fire(a, "Ready")
	f.remotes.WaitingRoom.OnServerEvent:Fire(b, "Ready")
	f.advance(0.2)
	f.players.PlayerRemoving:Fire(b)
	f.advance(3)
	assert(not f.round.IsRoundActive())
	assert(b:GetAttribute("InWaitingRoom") == nil)
end)

test("room recovers after failed preparation and accepts a new round", function()
	local f = fixture()
	local room = f.load("WaitingRoomManager")
	room.Init()
	local a, b = f.player(200), f.player(300)
	f.round.SetSpawnHandler(function() error("spawn unavailable") end)
	room.Join(a); room.Join(b)
	f.remotes.WaitingRoom.OnServerEvent:Fire(a, "Ready")
	f.remotes.WaitingRoom.OnServerEvent:Fire(b, "Ready")
	a:SetAttribute("CharacterSelectionConfirmed", true)
	b:SetAttribute("CharacterSelectionConfirmed", true)
	f.modules.CharacterStatsApplier.SelectionChanged.Event:Fire(a, "Confirmed")
	f.advance(3)
	assert(f.storage:GetAttribute("MatchState") == "Lobby")
	assert(a:GetAttribute("InRound") == nil and b:GetAttribute("InRound") == nil)
	f.round.SetSpawnHandler(function() end)
	room.Join(b); room.Join(a)
	f.remotes.WaitingRoom.OnServerEvent:Fire(a, "Ready")
	f.remotes.WaitingRoom.OnServerEvent:Fire(b, "Ready")
	a:SetAttribute("CharacterSelectionConfirmed", true)
	b:SetAttribute("CharacterSelectionConfirmed", true)
	f.modules.CharacterStatsApplier.SelectionChanged.Event:Fire(a, "Confirmed")
	f.advance(3)
	assert(f.round.IsRoundActive())
end)

test("old death callback cannot respawn a replacement character", function()
	local f = fixture()
	f.load("DeathRespawnHandler")
	local p = f.player(200)
	f.players.PlayerAdded:Fire(p)
	p:SetAttribute("InRound", true)
	p.Character:WaitForChild("Humanoid").Died:Fire()
	assert(p:GetAttribute("Eliminado") == true)
	f.advance(5)
	p:LoadCharacter()
	local character, loads = p.Character, p.loads
	f.advance(3)
	assert(p.Character == character and p.loads == loads)
end)

test("normal death still respawns once and preserves elimination", function()
	local f = fixture()
	f.load("DeathRespawnHandler")
	local p = f.player(200)
	f.players.PlayerAdded:Fire(p)
	p:SetAttribute("InRound", true)
	local loads = p.loads
	p.Character:WaitForChild("Humanoid").Died:Fire()
	f.advance(7)
	assert(p.loads == loads + 1 and p:GetAttribute("Eliminado") == true)
end)

print(string.format("%d match regression tests passed", passed))
