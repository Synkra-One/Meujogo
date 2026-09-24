--!nocheck
-- `sources` vem de run_drawers.py: DrawerRules, DrawerSystem, Furniture,
-- HouseKit, GameConfig e ItemRegistry são REAIS; o resto do servidor
-- (DropItemSystem, ToolFactory, RoundManager...) é dublê mínimo. Prova:
--   - regras de encaixe/sorteio (DrawerRules);
--   - abrir/fechar desliza a frente pelo curso e a bandeja soldada vai junto;
--   - loot sorteado na 1ª abertura aparece deitado DENTRO do espaço útil,
--     escondido/sem "Pegar" com a gaveta fechada e visível aberta;
--   - "Guardar item" põe a Tool da mão na gaveta, recusa o que não cabe e
--     libera a gaveta quando alguém pega o item;
--   - Reset (RoundPrepared) fecha tudo, apaga o guardado e re-sorteia;
--   - Monstro não usa gaveta.

local stub = loadstring(sources.RobloxStub, "RobloxStub")()
local Workspace = stub.Workspace

Random = { new = function(seed)
	local state = (seed or 99) % 2147483646 + 1
	local function unit()
		state = (state * 16807) % 2147483647
		return state / 2147483647
	end
	return {
		NextNumber = function(_, low, high) return (low or 0) + unit() * ((high or 1) - (low or 0)) end,
		NextInteger = function(_, low, high) return low + math.floor(unit() * (high - low + 1)) end,
	}
end }
Vector2 = { new = function(x, y) return { X = x, Y = y } end }
TweenInfo = { new = function(...) return { ... } end }

local Color3M = {}
Color3M.__index = Color3M
function Color3M.Lerp(a, b, t) return Color3.new(a.R + (b.R - a.R) * t, a.G + (b.G - a.G) * t, a.B + (b.B - a.B) * t) end
function Color3.new(r, g, b) return setmetatable({ R = r or 0, G = g or 0, B = b or 0 }, Color3M) end
function Color3.fromRGB(r, g, b) return Color3.new(r / 255, g / 255, b / 255) end

local v3m = getmetatable(Vector3.new())
function v3m.Min(a, b) return Vector3.new(math.min(a.X, b.X), math.min(a.Y, b.Y), math.min(a.Z, b.Z)) end
function v3m.Max(a, b) return Vector3.new(math.max(a.X, b.X), math.max(a.Y, b.Y), math.max(a.Z, b.Z)) end
local cfm = getmetatable(CFrame.identity)
function cfm:VectorToObjectSpace(v) return Vector3.new(v:Dot(self.RightVector), v:Dot(self.UpVector), v:Dot(-self.LookVector)) end
function cfm:VectorToWorldSpace(v) return self.RightVector * v.X + self.UpVector * v.Y - self.LookVector * v.Z end
function cfm:PointToObjectSpace(p) return self:VectorToObjectSpace(p - self.Position) end
function cfm:Inverse()
	local r = self.R
	return CFrame.fromMatrix(self:VectorToObjectSpace(-self.Position), Vector3.new(r[1], r[2], r[3]), Vector3.new(r[4], r[5], r[6]), Vector3.new(r[7], r[8], r[9]))
end
function cfm:ToObjectSpace(o) return self:Inverse() * o end

--------------------------------------------------------------------------------
-- Sinais e eventos de Instance (o stub compartilhado não tem)
--------------------------------------------------------------------------------

local function Signal()
	local handlers = {}
	local s = {}
	function s:Connect(fn)
		table.insert(handlers, fn)
		return { Disconnect = function()
			local i = table.find(handlers, fn)
			if i then table.remove(handlers, i) end
		end }
	end
	function s:Once(fn)
		local c
		c = s:Connect(function(...) c.Disconnect() fn(...) end)
		return c
	end
	function s:Fire(...)
		for _, fn in table.clone(handlers) do fn(...) end
	end
	return s
end

local function under(node, root)
	local cur = node.Parent
	while cur do
		if cur == root then return true end
		cur = cur.Parent
	end
	return false
end

local descendantAdded = Signal()
rawget(Workspace, "_props").DescendantAdded = descendantAdded
rawget(Workspace, "_props").IsDescendantOf = function() return false end

local rawNew = Instance.new
Instance.new = function(class, parent)
	local inst = rawNew(class)
	local props = rawget(inst, "_props")
	props.Destroying = Signal()
	props.AncestryChanged = Signal()
	props.Triggered = Signal()
	props.IsDescendantOf = function(self, root) return under(self, root) end
	props.GetFullName = function(self) return self.Name end
	local mt = getmetatable(inst)
	local oldNew = mt.__newindex
	mt.__newindex = function(t, k, v)
		oldNew(t, k, v)
		if k == "Parent" then
			t.AncestryChanged:Fire(t, v)
			for _, d in t:GetDescendants() do d.AncestryChanged:Fire(t, v) end
			if v and (v == Workspace or under(v, Workspace)) then
				descendantAdded:Fire(t)
			end
		end
	end
	if parent then inst.Parent = parent end
	return inst
end

--------------------------------------------------------------------------------
-- Módulos: reais via sources, dublês no cache
--------------------------------------------------------------------------------

local tokens
tokens = setmetatable({}, { __index = function(t, key)
	local token = setmetatable({ __module = key }, { __index = function(_, k) return tokens[k] end })
	rawset(t, key, token)
	return token
end })
local modules = {}
local env
local function loadModule(name)
	if modules[name] then return modules[name] end
	local fn = assert(loadstring(assert(sources[name], name), name))
	setfenv(fn, env)
	modules[name] = fn()
	return modules[name]
end
env = setmetatable({
	script = { Parent = tokens },
	require = function(token) return loadModule(token.__module) end,
	typeof = function(v)
		if type(v) == "table" and v.ClassName then return "Instance" end
		if type(v) == "table" and v.R and v.X then return "CFrame" end
		if type(v) == "table" and v.X and v.Y and v.Z then return "Vector3" end
		return typeof(v)
	end,
}, { __index = getfenv() })
game:GetService("ReplicatedStorage").Modules = {
	GameConfig = tokens.GameConfig, ItemRegistry = tokens.ItemRegistry, Remotes = tokens.Remotes,
	StatScaling = tokens.StatScaling, ToolFactory = tokens.ToolFactory,
	AssetRegistry = tokens.AssetRegistry, AssetLoader = tokens.AssetLoader,
}

-- TweenService: aplica o destino na hora e completa em seguida.
local tweens = 0
stub.Services.TweenService = { Create = function(_, inst, _, goal)
	local done = Signal()
	return {
		Completed = done,
		Play = function()
			tweens += 1
			for k, v in goal do inst[k] = v end
			done:Fire(Enum.PlaybackState.Completed)
		end,
	}
end }
stub.Services.Debris = { AddItem = function() end }
local soundM = { Play = function() end }
local oldNewForSound = Instance.new
Instance.new = function(class, parent)
	local inst = oldNewForSound(class, parent)
	if class == "Sound" then rawget(inst, "_props").Play = soundM.Play end
	return inst
end

local messages = {}
modules.Remotes = { LobbyMessage = { FireClient = function(_, player, text) table.insert(messages, text) end } }
modules.StatScaling = { LootRarityMultiplier = function() return 1 end }
local reach = true
modules.InteractionGuard = { CanReach = function() return reach end }
local roundPrepared = Signal()
modules.RoundManager = { RoundPrepared = { Event = roundPrepared } }

-- Tool com Handle de tamanho dado (+ uma peça soldada, como a Tocha).
local toolSizes = {
	Chocolate = Vector3.new(1, 0.25, 0.5),
	Bandagem = Vector3.new(0.7, 0.5, 0.5),
	LancaDeBambu = Vector3.new(0.25, 0.25, 4.2),
	TacoBeisebol = Vector3.new(0.45, 0.45, 3.4),
	Tocha = Vector3.new(0.25, 0.25, 2),
	Lanterna = Vector3.new(0.5, 0.5, 1.8),
	Gasolina = Vector3.new(1.2, 1.8, 0.7),
	Sinalizador = Vector3.new(0.4, 1.4, 0.4),
}
local function makeTool(name, size)
	local tool = Instance.new("Tool")
	tool.Name = name
	local handle = Instance.new("Part")
	handle.Name = "Handle"
	handle.Size = size
	handle.CFrame = CFrame.new(0, 50, 0) * CFrame.Angles(0.3, 0.2, 0.1)
	handle.Parent = tool
	rawget(tool, "_props").GetPivot = function(self) return (self.PrimaryPart or handle).CFrame end
	rawget(tool, "_props").PivotTo = function(self, target)
		local pivot = self:GetPivot()
		local delta = target * pivot:Inverse()
		for _, d in self:GetDescendants() do
			if d:IsA("BasePart") then d.CFrame = delta * d.CFrame end
		end
	end
	return tool
end
modules.ToolFactory = { Create = function(itemId)
	local size = toolSizes[itemId]
	if not size then return nil end
	return makeTool(itemId, size)
end }
local picked = Signal()
modules.DropItemSystem = {
	PlaceInWorld = function(tool, cframe, parent)
		tool:SetAttribute("_Dropped", true)
		tool.Parent = parent or Workspace
		if not tool.PrimaryPart then tool.PrimaryPart = tool:FindFirstChild("Handle") end
		tool:PivotTo(cframe)
		local prompt = Instance.new("ProximityPrompt")
		prompt.Name = "PegarPrompt"
		prompt.Parent = tool:FindFirstChild("Handle")
	end,
}

local checks = 0
local function check(condition, message, ...)
	checks += 1
	if not condition then error(string.format(message, ...), 0) end
end
local function near(a, b, tol) return math.abs(a - b) < (tol or 1e-4) end
local function nearV(a, b, tol) return (a - b).Magnitude < (tol or 1e-4) end

--------------------------------------------------------------------------------
-- DrawerRules
--------------------------------------------------------------------------------

local Rules = loadModule("DrawerRules")
local ok, order = Rules.FitOrientation(Vector3.new(0.25, 0.25, 4.2), Vector3.new(4.7, 0.65, 1.3))
check(ok and order[1] == 3, "pé de cabra deveria deitar ao longo da largura")
check(not (Rules.FitOrientation(Vector3.new(0.25, 0.25, 4.2), Vector3.new(1.45, 0.42, 0.9))), "pé de cabra não cabe em criado-mudo")
ok, order = Rules.FitOrientation(Vector3.new(1.2, 1.8, 0.7), Vector3.new(2.2, 0.8, 1.9))
check(ok and order[2] == 3, "galão deveria deitar com o lado fino pra cima")
ok, order = Rules.FitOrientation(Vector3.new(0.3, 0.3, 2.0), Vector3.new(1.2, 0.5, 2.4))
check(ok and order[3] == 3, "item longo cabe pela profundidade quando a largura não dá")
local picks = Rules.ChooseLoot(100, 1, 3, Random.new(3))
check(#picks >= 1 and #picks <= 3, "1–3 itens por casa, veio %d", #picks)
local seenPick = {}
for _, i in picks do
	check(i >= 1 and i <= 100 and not seenPick[i], "sorteio repetiu/saiu da faixa")
	seenPick[i] = true
end
check(#Rules.ChooseLoot(2, 5, 7, Random.new(3)) == 2, "limita às gavetas existentes")
check(#Rules.ChooseLoot(0, 1, 3, Random.new(3)) == 0, "sem gaveta, sem loot")
local counts = { Comum = 0, Media = 0, Rara = 0 }
local r = Random.new(11)
for _ = 1, 4000 do counts[Rules.RollRarity({ Comum = 70, Media = 25, Rara = 5 }, 1, r)] += 1 end
check(counts.Comum > 2600 and counts.Comum < 3000 and counts.Rara > 120 and counts.Rara < 290, "pesos de raridade fora (%d/%d/%d)", counts.Comum, counts.Media, counts.Rara)
local lucky = { Comum = 0, Media = 0, Rara = 0 }
for _ = 1, 4000 do lucky[Rules.RollRarity({ Comum = 70, Media = 25, Rara = 5 }, 2.4, r)] += 1 end
check(lucky.Rara > counts.Rara * 1.3, "Sorte deveria aumentar o raro (%d vs %d)", lucky.Rara, counts.Rara)

--------------------------------------------------------------------------------
-- DrawerSystem com uma cômoda e um gaveteiro reais
--------------------------------------------------------------------------------

loadModule("Structures")
local Furniture = loadModule("Furniture")
local GameConfig = loadModule("GameConfig")
local room = Instance.new("Folder")
room.Name = "Casa"
room:SetAttribute("CasaGerada", true)
room.Parent = Workspace
local base = CFrame.new(30, 8, -12) * CFrame.Angles(0, 0.6, 0)
Furniture.Dresser(room, base, Color3.new(0.5, 0.4, 0.3))
Furniture.ToolChest(room, base * CFrame.new(8, 0, 0), Color3.new(0.5, 0.2, 0.2))
Furniture.Nightstand(room, base * CFrame.new(-6, 0, 0), Color3.new(0.3, 0.2, 0.1), false)

-- Exercita todas as geometrias primeiro; a política real por casa vem abaixo.
local realFunctional = GameConfig.Drawers.FunctionalPerHouse
local realLoot = GameConfig.Drawers.LootPerHouse
GameConfig.Drawers.FunctionalPerHouse = { Min = 8, Max = 8 }
local System = loadModule("DrawerSystem")
System.Init()

local fronts = {}
for _, d in room:GetDescendants() do
	if d:GetAttribute("Gaveta") == true then table.insert(fronts, d) end
end
check(#fronts == 8, "cômoda (4) + gaveteiro (3) + criado-mudo (1) = 8 gavetas, veio %d", #fronts)

local function promptOf(front, name)
	for _, c in front:GetChildren() do
		if c.Name == name then return c end
	end
	return nil
end

local survivor = { Name = "Ana", Character = nil }
function survivor:GetAttribute(k) if k == "Role" then return GameConfig.Roles.Survivor end return nil end
local backpack = Instance.new("Backpack")
function survivor:FindFirstChildOfClass(c) if c == "Backpack" then return backpack end return nil end
local character = Instance.new("Model")
character.Name = "AnaChar"
local humanoid = Instance.new("Humanoid")
humanoid.Health = 100
humanoid.Parent = character
rawget(humanoid, "_props").UnequipTools = function()
	for _, c in character:GetChildren() do
		if c.ClassName == "Tool" then c.Parent = backpack end
	end
end
survivor.Character = character
local monster = { Name = "Jason" }
function monster:GetAttribute(k) if k == "Role" then return GameConfig.Roles.Monster end return nil end

for _, front in fronts do
	check(promptOf(front, "GavetaPrompt") and promptOf(front, "GuardarPrompt"), "prompts da gaveta")
	check(promptOf(front, "GuardarPrompt").Enabled == false, "Guardar começa desligado (cliente liga)")
	check(promptOf(front, "GuardarPrompt").KeyboardKeyCode == GameConfig.Drawers.StoreKey, "tecla de guardar")
end

-- Abrir/fechar: frente e bandeja soldada deslizam pelo curso.
local front = fronts[1]
local closed = front:GetAttribute("CFrameFechada")
local travel = front:GetAttribute("GavetaCurso")
promptOf(front, "GavetaPrompt").Triggered:Fire(monster)
check(front:GetAttribute("GavetaAberta") == false, "Monstro não abre gaveta")
promptOf(front, "GavetaPrompt").Triggered:Fire(survivor)
check(front:GetAttribute("GavetaAberta") == true, "sobrevivente abre")
check(nearV(front.CFrame.Position, (closed * CFrame.new(0, 0, -travel)).Position), "frente deveria deslizar o curso inteiro")
check(promptOf(front, "GavetaPrompt").ActionText == "Fechar", "prompt vira Fechar")
promptOf(front, "GavetaPrompt").Triggered:Fire(survivor)
check(front:GetAttribute("GavetaAberta") == false and nearV(front.CFrame.Position, closed.Position), "fecha de volta")

-- Loot: força todas as gavetas a ter item e abre cada uma.
local function itemIn(f)
	for _, d in f.Parent:GetDescendants() do
		if d.ClassName == "Tool" then return d end
	end
	return nil
end
local function checkInsideUsable(f, tool, open)
	local pose = f:GetAttribute("CFrameFechada") * CFrame.new(0, 0, if open then -f:GetAttribute("GavetaCurso") else 0)
	local slot = pose * f:GetAttribute("GavetaSlot")
	local interior = f:GetAttribute("GavetaInterior")
	for _, p in tool:GetDescendants() do
		if p:IsA("BasePart") then
			local half = p.Size / 2
			for _, sx in { -1, 1 } do for _, sy in { -1, 1 } do for _, sz in { -1, 1 } do
				local c = p.CFrame * Vector3.new(sx * half.X, sy * half.Y, sz * half.Z)
				local l = slot:PointToObjectSpace(c)
				check(math.abs(l.X) <= interior.X / 2 + 0.01 and l.Y >= -0.01 and l.Y <= interior.Y + 0.015 and math.abs(l.Z) <= interior.Z / 2 + 0.01,
					"item %s fora do espaço útil da gaveta (%.2f, %.2f, %.2f)", tool.Name, l.X, l.Y, l.Z)
			end end end
		end
	end
end

-- Força loot em todas as geometrias para validar encaixe/visibilidade.
GameConfig.Drawers.LootPerHouse = { Min = 8, Max = 8 }
roundPrepared:Fire({})
local found = 0
for _, f in fronts do
	promptOf(f, "GavetaPrompt").Triggered:Fire(survivor)
	local tool = itemIn(f)
	if tool then
		found += 1
		check(tool:FindFirstChild("Handle").Anchored == true, "item da gaveta fica ancorado")
		check(tool:GetAttribute("OcultoNaGaveta") == nil, "aberta: item visível")
		check(promptOf(tool:FindFirstChild("Handle"), "PegarPrompt").Enabled == true, "aberta: Pegar ligado")
		check(f:GetAttribute("GavetaItem") ~= nil, "GavetaItem publicado pro cliente")
		checkInsideUsable(f, tool, true)
		promptOf(f, "GavetaPrompt").Triggered:Fire(survivor)
		check(tool:GetAttribute("OcultoNaGaveta") == true, "fechada: item oculto")
		check(promptOf(tool:FindFirstChild("Handle"), "PegarPrompt").Enabled == false, "fechada: Pegar desligado")
		checkInsideUsable(f, tool, false)
		promptOf(f, "GavetaPrompt").Triggered:Fire(survivor)
		checkInsideUsable(f, tool, true)
	end
end
check(found >= 6, "loot deveria aparecer na maioria das gavetas (%d/8)", found)

-- Pegar (DropItemSystem move a Tool pro Backpack) libera a gaveta.
local withItem
for _, f in fronts do
	if itemIn(f) then withItem = f break end
end
local tool = itemIn(withItem)
tool.Parent = backpack
check(withItem:GetAttribute("GavetaItem") == nil, "pegar o item libera a gaveta")
check(tool:GetAttribute("OcultoNaGaveta") == nil, "item pego não fica marcado como oculto")

-- Guardar item da mão.
local crowbar = makeTool("Pé de cabra", Vector3.new(0.25, 0.25, 4.2))
crowbar:SetAttribute("WorldItemId", "LancaDeBambu")
crowbar.Parent = character
local nightFront
for _, f in fronts do
	if f:GetAttribute("GavetaMovel") == "Criado-mudo" then nightFront = f end
end
local nightTool = itemIn(nightFront)
if nightTool then nightTool.Parent = backpack end
check(nightFront:GetAttribute("GavetaAberta") == true, "criado-mudo ficou aberto do laço acima")
promptOf(nightFront, "GuardarPrompt").Triggered:Fire(survivor)
check(crowbar.Parent == character and #messages == 1, "pé de cabra não cabe no criado-mudo: avisa e fica na mão")
local wide
for _, f in fronts do
	if f:GetAttribute("GavetaMovel") == "Gaveteiro" then
		local t = itemIn(f)
		if t then t.Parent = backpack end
		wide = f
		break
	end
end
check(wide:GetAttribute("GavetaAberta") == true, "gaveteiro aberto")
promptOf(wide, "GuardarPrompt").Triggered:Fire(survivor)
check(crowbar.Parent and under(crowbar, wide.Parent), "pé de cabra guardado no gaveteiro")
check(wide:GetAttribute("GavetaItem") == "Pé de cabra", "GavetaItem = nome do item")
checkInsideUsable(wide, crowbar, true)
promptOf(wide, "GuardarPrompt").Triggered:Fire(survivor)
check(under(crowbar, wide.Parent), "gaveta cheia não aceita outro item")

-- Reset de rodada: fecha tudo, apaga o guardado, re-sorteia.
GameConfig.Drawers.LootPerHouse = realLoot
roundPrepared:Fire({})
check(crowbar.Parent == nil, "item guardado some no reset da rodada")
for _, f in fronts do
	check(f:GetAttribute("GavetaAberta") == false and nearV(f.CFrame.Position, f:GetAttribute("CFrameFechada").Position), "reset fecha a gaveta")
	check(itemIn(f) == nil and f:GetAttribute("GavetaItem") == nil, "reset esvazia a gaveta")
end

-- Sem alcance/visão (InteractionGuard) nada acontece.
reach = false
promptOf(fronts[2], "GavetaPrompt").Triggered:Fire(survivor)
check(fronts[2]:GetAttribute("GavetaAberta") == false, "sem alcance não abre")

-- Política real: limites independentes por casa, uma gaveta superior por móvel,
-- bloqueio no servidor mesmo se um cliente disparar o prompt decorativo.
reach = true
GameConfig.Drawers.FunctionalPerHouse = realFunctional
local houses = {}
for h = 1, 3 do
	local house = Instance.new("Model", Workspace)
	house.Name = "CasaTeste" .. h
	house:SetAttribute("CasaGerada", true)
	for n = 1, 10 do
		Furniture.Dresser(house, CFrame.new(n * 10, h * 20, 0), Color3.new(0.5, 0.4, 0.3))
	end
	table.insert(houses, house)
end
local layouts = {}
local contents = {}
for round = 1, 12 do
	roundPrepared:Fire({})
	for h, house in houses do
		local active, loot, signature, ids = 0, 0, {}, {}
		local furnitureSeen = {}
		for i, f in house:GetDescendants() do
			if f:GetAttribute("Gaveta") ~= true then continue end
			local functional = f:GetAttribute("GavetaFuncional") == true
			check(promptOf(f, "GavetaPrompt").Enabled == functional, "prompt reflete gaveta funcional")
			promptOf(f, "GavetaPrompt").Triggered:Fire(survivor)
			check(f:GetAttribute("GavetaAberta") == functional, "servidor bloqueia gaveta decorativa")
			if functional then
				active += 1
				local owner = f.Parent.Parent
				check(not furnitureSeen[owner], "somente uma gaveta por móvel quando há móveis suficientes")
				furnitureSeen[owner] = true
				for _, other in owner:GetDescendants() do
					if other:GetAttribute("Gaveta") == true then
						check(f:GetAttribute("CFrameFechada").Position.Y >= other:GetAttribute("CFrameFechada").Position.Y, "prioriza gaveta de cima")
					end
				end
			end
			local item = itemIn(f)
			if item then
				loot += 1
				table.insert(signature, tostring(i))
				table.insert(ids, item.Name)
			end
		end
		check(active >= 5 and active <= 7, "casa %d: %d gavetas funcionais", h, active)
		check(loot >= 1 and loot <= 3, "casa %d: %d itens", h, loot)
		layouts[h .. ":" .. table.concat(signature, ",")] = true
		contents[table.concat(ids, ",")] = true
	end
end
local variations, itemVariations = 0, 0
for _ in layouts do variations += 1 end
for _ in contents do itemVariations += 1 end
check(variations > #houses and itemVariations > 1, "gavetas e itens devem variar entre rodadas")

-- Caixas manuais reabrem; as geradas mudam de posição e ambas sorteiam
-- conteúdo novo, sem permitir segunda coleta dentro da mesma rodada.
env.RaycastParams = { new = function() return {} end }
modules.IslandLayout = { CoastRadiusMax = function() return 100 end }
modules.StatScaling.LootQuantityMultiplier = function() return 1 end
modules.StatScaling.Of = function() return 50 end
local crateResults = {}
modules.Remotes.OpenCrate = {
	OnServerEvent = Signal(),
	FireClient = function(_, _, ids) table.insert(crateResults, table.concat(ids, ",")) end,
}
local root = Instance.new("Part", character)
root.Name = "HumanoidRootPart"
local island = Instance.new("Folder", Workspace)
island.Name = "Ilha"
local marker = Instance.new("Part", island)
marker:SetAttribute("PontoLoot", true)
marker.Position = Vector3.new(15, 2, 0)
local manual = Instance.new("Part", houses[1])
manual:SetAttribute("CaixaLoot", true)
manual.Color = Color3.new(0.4, 0.3, 0.2)
manual.Transparency = 0
local originalColor = manual.Color
local Crates = loadModule("LootCrateSystem")
Crates.Init()
GameConfig.LootCrates.Count = 2
local crateContents, cratePositions = {}, {}
for round = 1, 8 do
	roundPrepared:Fire({})
	check(manual:GetAttribute("CaixaAberta") == false and manual.Transparency == 0 and manual.Color == originalColor, "caixa manual restaurada")
	local targets = { manual }
	local generated = Workspace:FindFirstChild("CaixasLoot"):GetChildren()
	check(#generated == 2, "caixas geradas renovadas")
	for _, crate in generated do table.insert(targets, crate) end
	for _, crate in targets do
		root.CFrame = crate.CFrame
		local before = #crateResults
		local prompt = crate:FindFirstChildOfClass("ProximityPrompt")
		check(prompt.Enabled == true, "caixa pode abrir a cada rodada")
		prompt.Triggered:Fire(survivor)
		check(#crateResults == before + 1 and crate:GetAttribute("CaixaAberta") == true, "caixa entrega uma vez")
		prompt.Triggered:Fire(survivor)
		check(#crateResults == before + 1, "caixa não duplica loot")
		crateContents[crateResults[#crateResults]] = true
	end
	cratePositions[tostring(generated[1].Position.X)] = true
end
local crateVariation, positionVariation = 0, 0
for _ in crateContents do crateVariation += 1 end
for _ in cratePositions do positionVariation += 1 end
check(crateVariation > 1 and positionVariation > 1, "caixas variam conteúdo e posição por partida")

print(string.format("PASS: gavetas; %d verificações (%d tweens)", checks, tweens))
