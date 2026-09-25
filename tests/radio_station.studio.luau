-- Execute em um lugar descartavel via tests/RadioStation.project.json.
-- Raycasts reais do engine: parede, porta, janela e cada task do novo abrigo.
local Server = game:GetService("ServerScriptService").Server
local Workspace = game:GetService("Workspace")
local Radio = require(Server.Tools.RadioTowerGenerator)
local Guard = require(Server.InteractionGuard)
Radio.CONFIG.Assets.Tower = 0
Radio.CONFIG.Assets.Generator = 0
-- O teste de geometria nao depende de downloads de audio (inclui o
-- placeholder rbxassetid://0 do gerador, que gera erro assincrono no Studio).
local assets = require(game:GetService("ReplicatedStorage").Modules.AssetRegistry)
for key in assets.Sounds.RadioSite do assets.Sounds.RadioSite[key] = "" end

local ilha = Instance.new("Folder")
ilha.Name = "Ilha"
ilha.Parent = Workspace
local previous = Instance.new("Model")
previous.Name = "TorreDeRadio"
previous.Parent = ilha
local floor = Instance.new("Part")
floor.Name = "PisoPatio"
floor.Anchored = true
floor.CFrame = CFrame.new(0, 20.2, 0) * CFrame.Angles(0, math.rad(27), 0)
floor.Parent = previous
local base = floor.CFrame * CFrame.new(0, -0.2, 0)
local forest = Instance.new("Folder")
forest.Name = "Floresta"
forest.Parent = ilha
local tree = Instance.new("Part")
tree.Name = "ValidationTree"
tree.Anchored = true
tree.CFrame = base * CFrame.new(60, 3, 45)
tree.Parent = forest
local station = Radio.Build()
assert(Radio.Validate(station), "generated station failed structural validation")
for _, part in station:GetDescendants() do
	assert(part:GetAttribute("GalaoCombustivel") ~= true, "legacy decorative fuel remains")
end
assert((station.PrimaryPart.Position - (base * CFrame.new(0, 0.2, 0)).Position).Magnitude < 0.01, "regeneration moved station")
assert(station.PrimaryPart.Size.X == 128 and station.PrimaryPart.Size.Z == 108)
assert(station.Abrigo.LajeAbrigo.Size.X == 38 and station.Abrigo.LajeAbrigo.Size.Z == 28)
if game:GetService("RunService"):IsEdit() then
	local backups = game:GetService("ServerStorage"):FindFirstChild("MapEditBackups")
	assert(backups and previous:IsDescendantOf(backups), "previous station not backed up")
	local backup = previous.Parent
	assert(backup.TerrenoAnterior:IsA("TerrainRegion"), "terrain not backed up")
	assert(typeof(backup.TerrenoAnterior:GetAttribute("MinCell")) == "Vector3")
	assert(tree:IsDescendantOf(backup), "vegetation inside enlarged corner not backed up")
	print("PASS_RADIO_BACKUP: saved station, terrain and corner vegetation")
else
	assert(tree.Parent == forest, "runtime removed forest")
end

local character = Instance.new("Model")
character.Name = "ValidationCharacter"
character.Parent = Workspace
local humanoid = Instance.new("Humanoid")
humanoid.Parent = character
local root = Instance.new("Part")
root.Name = "HumanoidRootPart"
root.Anchored = true
root.Parent = character
local head = Instance.new("Part")
head.Name = "Head"
head.Anchored = true
head.Parent = character
local match = require(Server.MatchStateService)
match.Set("InMatch")
local player = {
	Character = character, Parent = game:GetService("Players"),
	GetAttribute = function(_, name)
		return if name == "InRound" or name == "GameplayEnabled" then true else nil
	end,
}
local function stand(localPosition)
	root.CFrame = base * CFrame.new(localPosition)
	head.CFrame = root.CFrame * CFrame.new(0, 1.5, 0)
end
local function canUse(name, from, expected)
	local target = assert(station:FindFirstChild(name, true), name)
	stand(from)
	assert(Guard.CanReach(player, target, 12) == expected, name .. " unexpected reachability")
	if expected then
		-- Tambem consulta decoracoes (CanQuery), como a visibilidade do prompt.
		local params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Exclude
		params.FilterDescendantsInstances = { character, target }
		params.IgnoreWater = true
		local obstruction = Workspace:Raycast(head.Position, target.Position - head.Position, params)
		assert(not obstruction, name .. " prompt hidden by " .. (if obstruction then obstruction.Instance.Name else ""))
	end
end

-- Aproximacoes reais de todos os pontos funcionais.
canUse("ConsoleInstalacao", Vector3.new(-42.8, 3.8, -1), true)
canUse("PainelControle", Vector3.new(-45, 3.8, -8), true)
canUse("ConsoleRadio", Vector3.new(-22, 3.8, -11), true)
canUse("FusivelReserva", Vector3.new(-24.2, 3.8, -0.2), true)
canUse("CaixaFusiveis", Vector3.new(-21, 3.4, -27), true)
canUse("PartidaGerador", Vector3.new(6.4, 3.4, -32), true)
canUse("BocalCombustivel", Vector3.new(3.4, 3.4, -32), true)
-- Mesmo alcance, mas do lado de fora da parede do abrigo.
canUse("PainelControle", Vector3.new(-53, 3.8, -8), false)
canUse("FusivelReserva", Vector3.new(-24.2, 3.8, 8), false)

-- Porta fechada bloqueia, aberta permite acesso; janela solida bloqueia.
local item = Instance.new("Part")
item.Name = "PickupBehindDoor"
item.Anchored = true
item.CanCollide = false
item.CFrame = base * CFrame.new(-32, 3.8, -19)
item.Parent = station
stand(Vector3.new(-32, 3.8, -25))
assert(not Guard.CanReach(player, item, 10), "pickup through closed door")
local door = station.Abrigo.Porta
local closed = door.CFrame
-- Mesma dobradica e abertura de 100 graus usadas por DoorSystem.
door.CFrame = closed * CFrame.new(-3, 0, 0) * CFrame.Angles(0, math.rad(100), 0) * CFrame.new(3, 0, 0)
assert(Guard.CanReach(player, item, 10), "open doorway blocked")
door.CFrame = closed
local sideDoor = station.Abrigo.PortaServico
local sideClosed = sideDoor.CFrame
item.CFrame = base * CFrame.new(-18, 3.8, -13)
stand(Vector3.new(-10, 3.8, -13))
assert(not Guard.CanReach(player, item, 10), "pickup through closed service door")
sideDoor.CFrame = sideClosed * CFrame.new(-3, 0, 0) * CFrame.Angles(0, math.rad(100), 0) * CFrame.new(3, 0, 0)
assert(Guard.CanReach(player, item, 10), "open service doorway blocked")
sideDoor.CFrame = sideClosed
item.CFrame = base * CFrame.new(-16, 7.8, -2)
stand(Vector3.new(-11, 7.8, -2))
assert(not Guard.CanReach(player, item, 10), "pickup through glass")
stand(Vector3.new(90, 3.8, 0))
assert(not Guard.CanReach(player, item, 10), "out-of-range pickup")
item:Destroy()

-- Inicializadores de producao: nomes/attributes continuam achando as tasks.
require(Server.RadioInstallSystem).Init()
require(Server.RadioSiteSystem).Init()
require(Server.DoorSystem).Init()
local keys = { Abastecer = false, Partida = false, Fusivel = false, PegarFusivel = false, Painel = false, Socorro = false }
for _, obj in station:GetDescendants() do
	local key = obj:GetAttribute("InteracaoRadio")
	if key then
		assert(keys[key] == false, "duplicate interaction " .. key)
		keys[key] = true
		local prompt = assert(obj:FindFirstChildOfClass("ProximityPrompt"), key .. " missing prompt")
		-- O corpo do gerador (modelo do Toolbox) oculta o proprio bocal/partida.
		local generatorPoint = key == "Abastecer" or key == "Partida"
		assert(prompt.RequiresLineOfSight ~= generatorPoint, key .. " line-of-sight mismatch")
	end
end
for key, found in keys do assert(found, "missing task " .. key) end
assert(station:FindFirstChild("InstalarPeca", true).RequiresLineOfSight)
assert(station.Abrigo.PortaServico:GetAttribute("Porta") == true)
assert(station.Abrigo.Porta:FindFirstChild("PortaPrompt"))
assert(station.Abrigo.PortaServico:FindFirstChild("PortaPrompt"))
assert(station.Abrigo.Janela.CanCollide and station.Abrigo.Janela.CanQuery)
print("PASS_RADIO_STATION: preserved position; enlarged yard/shelter; seven reachable tasks; walls/closed doors/glass block; open door works; runtime prompts initialized")
