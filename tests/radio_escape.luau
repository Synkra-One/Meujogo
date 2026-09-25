--!nocheck
for name, source in sources do assert(loadstring(source, name)) end
local stub = loadstring(sources.Stub, "Stub")()
local world, services = stub.Workspace, stub.Services
local function signal()
	local s = { listeners = {} }
	function s:Connect(fn)
		local c = { Connected = true, fn = fn }
		function c:Disconnect() self.Connected = false end
		table.insert(self.listeners, c); return c
	end
	function s:Once(fn)
		local c; c = self:Connect(function(...) c:Disconnect(); fn(...) end); return c
	end
	function s:Fire(...) for _, c in table.clone(self.listeners) do if c.Connected then c.fn(...) end end end
	return s
end
local originalNew = Instance.new
function Instance.new(class, parent)
	local o = originalNew(class)
	for _, name in { "ChildAdded", "DescendantAdded", "Destroying", "Touched", "Triggered", "PromptButtonHoldBegan",
		"PromptButtonHoldEnded", "CharacterAdded", "CharacterRemoving", "Died", "Activated", "AncestryChanged" } do o[name] = signal() end
	o.changed = {}
	function o:GetAttributeChangedSignal(key) self.changed[key] = self.changed[key] or signal(); return self.changed[key] end
	function o:SetAttribute(key, value)
		local old = self._attributes[key]; self._attributes[key] = value
		if old ~= value and self.changed[key] then self.changed[key]:Fire() end
	end
	local mt = getmetatable(o)
	local oldSet = mt.__newindex
	mt.__newindex = function(t, key, value)
		oldSet(t, key, value)
		if key == "Parent" and value then
			value.ChildAdded:Fire(t)
			local p = value
			while p do if p.DescendantAdded then p.DescendantAdded:Fire(t) end; p = p.Parent end
		end
	end
	function o:FindFirstChild(name, recursive)
		for _, d in (if recursive then self:GetDescendants() else self:GetChildren()) do if d.Name == name then return d end end
		return nil
	end
	function o:WaitForChild(name) return assert(self:FindFirstChild(name), name) end
	function o:FindFirstAncestorOfClass(className)
		local p = self.Parent
		while p do if p:IsA(className) then return p end; p = p.Parent end
		return nil
	end
	function o:IsDescendantOf(ancestor)
		local p = self.Parent
		while p do if p == ancestor then return true end; p = p.Parent end
		return false
	end
	function o:CanSetNetworkOwnership() return not self.Anchored end
	function o:SetNetworkOwner() end
	function o:GetStateEnabled() return true end
	function o:SetStateEnabled() end
	function o:Move() end
	function o:UnequipTools()
		local owner = services.Players:GetPlayerFromCharacter(self.Parent)
		if owner then
			for _, item in self.Parent:GetChildren() do if item:IsA("Tool") then item.Parent = owner:FindFirstChildOfClass("Backpack") end end
		end
	end
	function o:Play() self.IsPlaying = true end
	function o:Stop() self.IsPlaying = false end
	if class == "Sound" then o.IsPlaying, o.Volume = false, 1 end
	if class == "Tool" then o.TextureId, o.Enabled = "", true end
	if class == "BindableEvent" then o.Event = signal(); function o:Fire(...) self.Event:Fire(...) end end
	if parent then o.Parent = parent end
	return o
end
world.ChildAdded, world.DescendantAdded = signal(), signal()
local cf = getmetatable(CFrame.identity)
function cf:PointToWorldSpace(p) return self * p end
function cf:ToObjectSpace(other) return CFrame.new(other.Position - self.Position) end
function cf:Lerp(other, t) return CFrame.new(self.Position:Lerp(other.Position, t)) end
local vector = getmetatable(Vector3.zero)
function vector:Lerp(other, t) return self + (other - self) * t end
local newColor = Color3.new
function Color3.new(r, g, b)
	local c = newColor(r, g, b)
	function c:Lerp(o, t) return Color3.new(self.R + (o.R - self.R) * t, self.G + (o.G - self.G) * t, self.B + (o.B - self.B) * t) end
	return c
end
UDim2.fromOffset = function(x, y) return UDim2.new(0, x, 0, y) end
Vector2 = { new = function(x, y) return { X = x, Y = y } end }
RaycastParams = { new = function() return {} end }
for _, name in { "NumberSequence", "NumberSequenceKeypoint", "ColorSequence", "NumberRange", "TweenInfo" } do getfenv()[name] = { new = function(...) return {...} end } end
Random = { new = function() return { NextNumber = function(_, a, b) return ((a or 0) + (b or 1)) / 2 end } end }
local now, occluded = 0, false
function world:GetServerTimeNow() return now end
function world:Raycast(origin, direction, params)
	if params.FilterType == Enum.RaycastFilterType.Include then
		return { Position = Vector3.new(origin.X, 10, origin.Z), Material = Enum.Material.Sand }
	end
	return if occluded then { Position = origin + direction * 0.5, Normal = Vector3.new(0, 1, 0) } else nil
end
local players = Instance.new("Players")
services.Players = players
players.PlayerAdded, players.PlayerRemoving = signal(), signal()
function players:GetPlayers() return self:GetChildren() end
function players:GetPlayerFromCharacter(c) for _, p in self:GetPlayers() do if p.Character == c then return p end end; return nil end
local heartbeat, frames = signal(), {}
services.RunService = {
	Heartbeat = heartbeat, IsEdit = function() return false end,
	BindToRenderStep = function(_, name, _, fn) frames[name] = fn end,
	UnbindFromRenderStep = function(_, name) frames[name] = nil end,
}
services.UserInputService = { MouseBehavior = Enum.MouseBehavior.LockCenter, MouseIconEnabled = false }
services.TweenService = { Create = function() return { Play = function() end } end }
services.ReplicatedStorage = Instance.new("ReplicatedStorage")
local tokens = setmetatable({}, { __index = function(_, name) return name end })
services.ReplicatedStorage.Modules = tokens
local remotes = setmetatable({}, { __index = function(t, name)
	local r = { OnServerEvent = signal(), OnClientEvent = signal(), sent = {} }
	function r:FireClient(p, ...)
		table.insert(self.sent, { player = p, args = {...} })
		if p == players.LocalPlayer then self.OnClientEvent:Fire(...) end
	end
	function r:FireAllClients(...) table.insert(self.sent, { args = {...} }) end
	function r:FireServer(...) self.OnServerEvent:Fire(players.LocalPlayer, ...) end
	rawset(t, name, r); return r
end })
local repairs, modules = {}, {}
modules.Remotes = remotes
modules.Structures = {}
modules.IslandLayout = { Plan = function() end, Site = function() return { x = 100, z = 0 } end,
	Seed = function() return 1 end, CoastRadiusAt = function() return 500 end, CONFIG = { BeachWidth = 45, SeaLevel = 0 } }
modules.AssetLoader = { Load = function() return nil end }
modules.StatScaling = { RepairMultiplier = function() return 1 end }
modules.SafeAttribute = { Get = function(o, key) return o:GetAttribute(key) end }
modules.WeaponSystem = { NoiseMade = Instance.new("BindableEvent") }
modules.GeneratorErrorSound = { SetGenerator = function() end }
modules.RepairMinigameSystem = {
	ResetTask = function(id) repairs[id] = nil end,
	Start = function(p, spec)
		if spec.canStart(p) and modules.InteractionGuard.CanReach(p, spec.part, spec.range) then repairs[spec.taskId] = { p = p, spec = spec } end
	end,
}
modules.ItemIcons = { IconForItemId = function() return "" end }
modules.FlashlightConfig, modules.FlashlightRig, modules.BaseballBatConfig = {}, {}, {}
modules.DropItemSystem = {
	HasInventorySpace = function() return true end,
	PlaceInWorld = function(tool, pose, parent)
		tool:FindFirstChild("Handle").CFrame = pose
		tool.Parent = parent
	end,
}
local deferred = {}
local env = setmetatable({
	script = { Parent = setmetatable({ Tools = tokens }, { __index = tokens }) },
	task = { defer = function(fn) table.insert(deferred, fn) end },
	os = { clock = function() return now end },
	print = function() end,
}, { __index = getfenv() })
local function load(name)
	if modules[name] then return modules[name] end
	local fn = assert(loadstring(assert(sources[name], name), name)); setfenv(fn, env)
	modules[name] = fn(); return modules[name]
end
env.require = load
local config = load("GameConfig")
local function tick(seconds)
	for _ = 1, math.ceil(seconds / 0.1) do
		now += 0.1; heartbeat:Fire(0.1)
		for _, fn in deferred do fn() end; table.clear(deferred)
		for _, fn in frames do fn(0.1) end
	end
end
local checks = 0
local function check(value, message) checks += 1; assert(value, message) end
local function create(class, name, parent) local o = Instance.new(class, parent); o.Name = name; return o end
local island = create("Folder", "Ilha", world)
local function player(name, role)
	local p = create("Player", name, players)
	p:SetAttribute("InRound", true); p:SetAttribute("Role", role or config.Roles.Survivor)
	create("Backpack", "Backpack", p); create("PlayerGui", "PlayerGui", p)
	local c = create("Model", name, world); p.Character = c
	local h = create("Humanoid", "Humanoid", c)
	h.Health, h.AutoRotate, h.WalkSpeed, h.JumpPower, h.JumpHeight = 100, true, 16, 50, 7
	h.DisplayDistanceType, h.HealthDisplayType = Enum.HumanoidDisplayDistanceType.Viewer, Enum.HumanoidHealthDisplayType.DisplayWhenDamaged
	local root = create("Part", "HumanoidRootPart", c); root.Transparency = 1
	local torso = create("Part", "Torso", c); torso.Transparency = 0.25
	local face = create("Decal", "face", torso); face.Transparency = 0.2
	return p, c, root, torso
end
local p, c, root, torso = player("Survivor")
local other = player("Other")
local monster = player("Monster", config.Roles.Monster)
players.LocalPlayer = p
world.CurrentCamera = create("Camera", "Camera", world)
world.CurrentCamera.FieldOfView = 72
world.CurrentCamera.CameraType = Enum.CameraType.Custom
world.CurrentCamera.ViewportSize = Vector2.new(1280, 720)
local match = load("MatchStateService")
match.Init(); match.Set("InMatch")
load("InteractionGuard")
local function station()
	local m = create("Model", "TorreDeRadio", island)
	for _, key in { "Abastecer", "Partida", "Fusivel", "PegarFusivel", "Painel", "Socorro" } do
		create("Part", key, m):SetAttribute("InteracaoRadio", key)
	end
	for _, key in { "MotorGerador", "EscapeGerador" } do create("Part", key, m):SetAttribute(key, true) end
	create("Part", "ConsoleInstalacao", m)
	return m
end
local generator = load("RadioTowerGenerator")
local rebuilds = 0
generator.Build = function()
	rebuilds += 1
	local old = island:FindFirstChild("TorreDeRadio"); if old then old:Destroy() end
	return station()
end
create("Model", "TorreDeRadio", island)
local site = generator.Ensure()
check(rebuilds == 1 and generator.Validate(site), "incomplete station repaired before initialization")
create("Part", "GalaoCombustivel_1", site):SetAttribute("GalaoCombustivel", true)
create("Part", "AlcaGalao_1", site); create("Part", "BicoGalao_1", site)
local factory = load("ToolFactory")
local gasoline = assert(factory.Create("Gasolina")); gasoline.Parent = site
check(gasoline:GetAttribute("Gasolina") and gasoline:FindFirstChild("Handle"), "asset failure still produces real Gasolina tool")
generator.Ensure()
check(not site:FindFirstChild("GalaoCombustivel_1") and not site:FindFirstChild("AlcaGalao_1") and gasoline.Parent == site, "legacy cans removed, real tool preserved")
local duplicate = create("Part", "Duplicate", site); duplicate:SetAttribute("InteracaoRadio", "Partida")
check(not generator.Validate(site), "duplicate interaction rejected")
duplicate:Destroy()
local objective = load("RadioObjective")
local extraction = load("ExtractionSystem")
local calls = 0
objective.RescueCountdownStarted.Event:Connect(function() calls += 1; extraction.Begin(0.1) end)
objective.Init(); extraction.Init()
load("RadioInstallSystem").Init()
local radio = load("RadioSiteSystem"); radio.Init()
load("ExtractionController")
local function prompt(key) return site:FindFirstChild(key):FindFirstChildOfClass("ProximityPrompt") end
local function repair(key)
	prompt(key).Triggered:Fire(p)
	local id = if key == "Partida" then "RadioPartida" else "RadioPainel"
	local session = repairs[id]; repairs[id] = nil
	if session and session.spec.canStart(p) then session.spec.onComplete(p) end
end
local fuelPrompt = prompt("Abastecer")
local function refuel(who)
	fuelPrompt.PromptButtonHoldBegan:Fire(who); tick(4); fuelPrompt.Triggered:Fire(who); fuelPrompt.PromptButtonHoldEnded:Fire(who)
end
gasoline.Parent = other:FindFirstChildOfClass("Backpack")
refuel(p)
check(site:GetAttribute("Combustivel") == 0, "another player's fuel cannot be used")
create("Part", "GhostCan", site):SetAttribute("GalaoCombustivel", true)
refuel(p); repair("Partida")
check(site:GetAttribute("Combustivel") == 0 and not site:GetAttribute("GeradorLigado"), "legacy decoration cannot refuel or start generator")
gasoline.Parent = p:FindFirstChildOfClass("Backpack")
fuelPrompt.Triggered:Fire(p)
check(gasoline.Parent ~= nil and site:GetAttribute("Combustivel") == 0, "forged instant refuel rejected")
fuelPrompt.PromptButtonHoldBegan:Fire(p); tick(2); gasoline.Parent = other:FindFirstChildOfClass("Backpack"); tick(2); fuelPrompt.Triggered:Fire(p)
check(site:GetAttribute("Combustivel") == 0, "fuel removed during hold cancels")
gasoline.Parent = p:FindFirstChildOfClass("Backpack")
refuel(p); fuelPrompt.Triggered:Fire(p)
check(site:GetAttribute("Combustivel") == 270 and gasoline.Parent == nil, "one tool fills the tank exactly once")
local spare = assert(factory.Create("Gasolina")); spare.Parent = p:FindFirstChildOfClass("Backpack")
site:SetAttribute("Combustivel", 260); refuel(p)
check(spare.Parent ~= nil and site:GetAttribute("Combustivel") == 260, "nearly full tank does not waste gasoline")
site:SetAttribute("Combustivel", 270); refuel(p)
check(spare.Parent ~= nil and site:GetAttribute("Combustivel") == 270, "full tank does not consume item")
spare:Destroy(); site:SetAttribute("Combustivel", 270)
repair("Partida")
check(not site:GetAttribute("GeradorLigado"), "starter requires fuse")
remotes.TransmissionMinigame.OnServerEvent:Fire(p, "InstallFuse")
check(not site:GetAttribute("FusivelInstalado"), "cannot install uncarried fuse")
prompt("PegarFusivel").Triggered:Fire(p)
remotes.TransmissionMinigame.OnServerEvent:Fire(p, "InstallFuse")
repair("Partida")
check(site:GetAttribute("GeradorLigado"), "fuel and fuse permit startup")
repair("Painel")
check(not site:GetAttribute("PainelAtivo"), "panel requires all installed pieces")
local installPrompt = site:FindFirstChild("InstalarPeca", true)
for _, kind in { "Antena", "Bateria", "Transmissor" } do
	local tool = create("Tool", kind, p:FindFirstChildOfClass("Backpack"))
	tool:SetAttribute("PecaRadio", true); tool:SetAttribute("TipoPeca", kind)
	installPrompt.Triggered:Fire(p)
	local session = assert(repairs.RadioInstalar); session.spec.onComplete(p)
	check(site:GetAttribute(kind .. "Instalada") and tool.Parent == nil, "installed piece consumes the carried tool")
end
repair("Painel"); prompt("Socorro").Triggered:Fire(p); tick(2)
check(site:GetAttribute("SinalProgresso") > 0 and calls == 0, "signal progresses over time")
root.CFrame = CFrame.new(200, 0, 0); tick(0.3)
check(not site:GetAttribute("SocorroEmAndamento"), "walking away interrupts signal")
root.CFrame = CFrame.new(); prompt("Socorro").Triggered:Fire(p)
site:FindFirstChild("MotorGerador"):SetAttribute("Sabotado", true); tick(0.3)
check(not site:GetAttribute("GeradorLigado") and not site:GetAttribute("PainelAtivo") and not site:GetAttribute("SocorroEmAndamento"), "sabotage drops energy and transmission")
site:FindFirstChild("MotorGerador"):SetAttribute("Sabotado", false)
repair("Partida"); repair("Painel"); site:SetAttribute("Combustivel", 0.1); tick(0.3)
check(site:GetAttribute("Combustivel") == 0 and not site:GetAttribute("GeradorLigado"), "empty tank shuts generator down")
gasoline = assert(factory.Create("Gasolina")); gasoline.Parent = p:FindFirstChildOfClass("Backpack"); refuel(p)
repair("Partida"); repair("Painel"); prompt("Socorro").Triggered:Fire(p); tick(15)
check(calls == 1 and site:GetAttribute("SocorroEnviado") and not site:GetAttribute("GeradorLigado"), "complete call starts exactly one extraction and stops generator")
prompt("Socorro").Triggered:Fire(p); tick(12)
check(calls == 1, "completed radio cannot trigger another extraction")
local heli = assert(island:FindFirstChild("Helicoptero"))
local board = assert(heli:FindFirstChild("EmbarcarHelicoptero", true))
check(board.Enabled, "helicopter lands and enables boarding")
local entry = heli.PrimaryPart.CFrame * CFrame.new(10, 0, 0)
root.CFrame = entry
p:SetAttribute("InRound", false); board.Triggered:Fire(p)
check(not p:GetAttribute("ExtractionBoarded"), "outsider cannot board")
p:SetAttribute("InRound", true)
root.CFrame = entry + Vector3.new(0, 100, 0); board.Triggered:Fire(p)
check(not p:GetAttribute("ExtractionBoarded"), "vertical distance is validated")
root.CFrame = entry; c:SetAttribute("GrabLocked", true); board.Triggered:Fire(p)
check(not p:GetAttribute("ExtractionBoarded"), "grabbed player cannot board")
c:SetAttribute("GrabLocked", nil); board.Triggered:Fire(p); tick(0.1)
check(p:GetAttribute("ExtractionBoarded") and torso.Transparency == 1 and not torso.CanCollide, "passenger hidden and noncolliding")
check(not match.IsGameplayEnabled(p) and p:GetAttribute("MovementLocked"), "passenger cannot move or use gameplay actions")
check(world.CurrentCamera.CameraType == Enum.CameraType.Scriptable and (world.CurrentCamera.CFrame.Position - heli:GetPivot().Position).Magnitude > 20, "camera outside fuselage")
local accessory = create("Part", "LateAccessory", c)
check(accessory.Transparency == 1, "new accessory hidden while aboard")
local hud = assert(p:FindFirstChild("PlayerGui"):FindFirstChild("ExtracaoHUD"))
remotes.ExtractionChoice.OnServerEvent:Fire(p, "Esperar")
check(hud.Enabled and p:GetAttribute("ExtractionBoarded"), "wait preserves camera and exit choices")
remotes.ExtractionChoice.OnServerEvent:Fire(p, "Sair")
check(not p:GetAttribute("ExtractionBoarded") and torso.Transparency == 0.25 and accessory.Transparency == 0 and torso.CanCollide and not root.Anchored, "exit restores original body properties")
check((root.Position - entry.Position).Magnitude < 0.01 and world.CurrentCamera.CameraType == Enum.CameraType.Custom and world.CurrentCamera.FieldOfView == 72, "exit restores ground position and camera")
check(match.IsGameplayEnabled(p), "exit restores gameplay")
check(c:FindFirstChildOfClass("Humanoid").DisplayDistanceType == Enum.HumanoidDisplayDistanceType.Viewer, "exit restores overhead name visibility")
board.Triggered:Fire(p)
local otherRoot = other.Character:FindFirstChild("HumanoidRootPart"); otherRoot.CFrame = entry
board.Triggered:Fire(other)
extraction.Reset()
check(not root.Anchored and not otherRoot.Anchored and not p:GetAttribute("ExtractionBoarded") and not other:GetAttribute("ExtractionBoarded"), "reset restores every passenger")
check(not hud.Enabled and not frames.ExtractionPassengerCamera, "reset releases HUD and camera")
extraction.Begin(0.1); tick(12)
heli = assert(island:FindFirstChild("Helicoptero"))
board = assert(heli:FindFirstChild("EmbarcarHelicoptero", true))
entry = heli.PrimaryPart.CFrame * CFrame.new(10, 0, 0)
local monsterRoot = monster.Character:FindFirstChild("HumanoidRootPart"); monsterRoot.CFrame = entry
board.Triggered:Fire(monster)
check(not monster:GetAttribute("ExtractionBoarded"), "monster cannot board")
root.CFrame = entry; board.Triggered:Fire(p)
p.CharacterRemoving:Fire(c)
check(not root.Anchored and torso.Transparency == 0.25 and not p:GetAttribute("ExtractionBoarded"), "character removal restores passenger")
board.Triggered:Fire(p)
local human = c:FindFirstChildOfClass("Humanoid"); human.Health = 0; tick(0.3)
check(not p:GetAttribute("ExtractionBoarded"), "death removes passenger")
human.Health = 100
otherRoot.CFrame = entry; board.Triggered:Fire(other)
players.PlayerRemoving:Fire(other); other.Parent = nil
check(not otherRoot.Anchored and not other:GetAttribute("ExtractionBoarded"), "disconnect restores passenger")
local spy = player("Spy", config.Roles.Spy)
spy.Character:FindFirstChild("HumanoidRootPart").CFrame = entry
board.Triggered:Fire(spy)
check(spy:GetAttribute("ExtractionBoarded"), "active spy can still board")
remotes.ExtractionChoice.OnServerEvent:Fire(spy, "Sair")
root.CFrame = entry; board.Triggered:Fire(p)
local rescued, departureCount = nil, 0
extraction.SurvivorsExtracted.Event:Connect(function(list) rescued = list; departureCount += 1 end)
remotes.ExtractionChoice.OnServerEvent:Fire(p, "Partir")
remotes.ExtractionChoice.OnServerEvent:Fire(p, "Sair")
check(p:GetAttribute("ExtractionBoarded"), "cannot exit after takeoff")
tick(2)
check(world.CurrentCamera.CameraType == Enum.CameraType.Scriptable and root.Anchored, "camera follows departure without freeing body")
tick(8)
check(departureCount == 1 and #rescued == 1 and rescued[1] == p, "departure reports only eligible passenger once")
check(root.Anchored and torso.Transparency == 1, "no fall from aircraft before round cleanup")
extraction.Reset()
check(not root.Anchored and torso.Transparency == 0.25 and (root.Position - entry.Position).Magnitude < 0.01, "end-of-flight cleanup restores body on ground")
objective.Reset(); radio.Reset()
check(site:GetAttribute("Combustivel") == 0 and not site:GetAttribute("FusivelInstalado") and not site:GetAttribute("SocorroEnviado") and site:GetAttribute("SinalProgresso") == 0, "second round starts clean")
local pieces = load("RadioPieces"); pieces.Init()
local testItems = assert(island:FindFirstChild("PecasRadioTeste"))
local function countGas()
	local n = 0
	for _, item in testItems:GetChildren() do if item:IsA("Tool") and item:GetAttribute("Gasolina") == true then n += 1 end end
	return n
end
check(countGas() == 1 and testItems:FindFirstChild("Antena") and testItems:FindFirstChild("Bateria") and testItems:FindFirstChild("Transmissor"), "test station has three pieces and one real fuel item")
local testGas = testItems:FindFirstChildOfClass("Tool"); testGas.Parent = p:FindFirstChildOfClass("Backpack")
pieces.Reset()
check(testGas.Parent == nil and countGas() == 1, "new round removes carried test fuel and creates exactly one fresh item")
pieces.Reset()
check(countGas() == 1, "repeated reset never duplicates gasoline")
print(string.format("PASS radio_escape: %d checks, real objective, extraction, passenger and camera modules", checks))
