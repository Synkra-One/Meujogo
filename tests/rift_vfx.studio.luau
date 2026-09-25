-- Engine real: geometria, lifecycle, corrida de close/beat, cancel e cleanup.
-- rojo build tests/RiftVFX.project.json -o /tmp/rift-vfx-validation.rbxlx
-- run-in-roblox --place /tmp/rift-vfx-validation.rbxlx --script tests/rift_vfx.studio.luau
assert(game.ReplicatedStorage:FindFirstChild("RiftVFX"):IsA("ModuleScript"), "use somente o lugar isolado RiftVFXValidation")
-- Rojo pode autoconectar ao abrir um novo lugar e inserir o boot completo.
-- Nesta cópia descartável só o módulo de VFX deve rodar, sem mapa/DataStore.
local function isolate(node)
	if node:IsA("BaseScript") and (node:IsDescendantOf(game:GetService("ServerScriptService"))
		or node:IsDescendantOf(workspace) or node:IsDescendantOf(game:GetService("ReplicatedFirst"))) then
		node.Disabled = true
	end
end
local isolation = game.DescendantAdded:Connect(isolate)
for _, node in game:GetDescendants() do isolate(node) end
local VFX = require(game.ReplicatedStorage.RiftVFX)
game:GetService("RunService"):Run() -- TweenService avança durante a simulação
task.wait(0.4)
local errors = {}
local log = game:GetService("LogService").MessageOut:Connect(function(message, kind)
	if kind == Enum.MessageType.MessageError then table.insert(errors, message) end
end)
local checked = 0
local surfaceY = workspace.Ground.Position.Y + workspace.Ground.Size.Y * 0.5
local function check(ok, message)
	assert(ok, message)
	checked += 1
end
local function new(x, upright)
	return VFX.new({cframe = CFrame.new(x, surfaceY, 0), width = 10, upright = upright})
end
local r = new(0, false)
local model = r.Core.Parent
check(model ~= nil, "portal criado")
check(math.abs(r.Core.Position.Y - (surfaceY + 0.08)) < 0.02, "portal assentado na superfície real do chão")
local beamCount, emitterCount = 0, 0
for _, node in model:GetDescendants() do
	if node:IsA("BasePart") then
		check(node.Anchored and not node.CanCollide and not node.CanQuery and not node.CanTouch, "VFX não bloqueia gameplay")
	elseif node:IsA("Beam") then
		beamCount += 1
		check(node.Attachment0 ~= nil and node.Attachment1 ~= nil, "beam conectado")
	elseif node:IsA("ParticleEmitter") then
		emitterCount += 1
	end
end
check(beamCount > 30 and emitterCount >= 10, "camadas completas")
r:Open(0.12)
task.wait(0.2)
check(model.Aperture.Value > 0.99, "abertura concluiu")
local yMin, yMax = math.huge, -math.huge
for _, node in model:GetDescendants() do
	if node:IsA("Attachment") then
		yMin = math.min(yMin, node.WorldPosition.Y)
		yMax = math.max(yMax, node.WorldPosition.Y)
	end
end
check(yMax - yMin > 1, "volume acima do chão, não coplanar")
local before = model.Core.RimNode1.Position
task.wait(0.1)
check((model.Core.RimNode1.Position - before).Magnitude > 0.01, "órbita animada")
r:Enter()
task.wait(0.1)
r:Emerge()
task.wait(0.1)
r:Close(0.12)
r:Emerge() -- evento atrasado não pode reativar um portal fechando
task.wait(0.25)
check(model.Aperture.Value < 0.01, "fechamento concluiu")
for _, node in model:GetDescendants() do
	if node:IsA("ParticleEmitter") then check(not node.Enabled and node.Rate == 0, "close não reativa emissores") end
end
task.wait(VFX.Style.ResidualTail)
check(r.Core.Parent == nil, "rastro limpa modelo")
r:Destroy()
r:Cancel()

local cancelled = new(15, true)
cancelled:Open(1)
task.wait(0.08)
cancelled:Cancel()
cancelled:Enter()
cancelled:Emerge()
task.wait(0.3 + VFX.Style.ResidualTail)
check(cancelled.Core.Parent == nil, "cancel durante abertura limpa tudo")

local external = new(-15, false)
external:Open(0.1)
task.wait(0.12)
external.Core.Parent:Destroy() -- RoundEnded faz ClearAllChildren
task.wait(0.1)
external:Destroy()
check(external.Core.Parent == nil, "remoção externa desconecta a animação")

local maxLifetime = VFX.Style.HardMaxLifetime
VFX.Style.HardMaxLifetime = 0.15
local orphan = new(0, false)
orphan:Open(0.05)
task.wait(0.3)
check(orphan.Core.Parent == nil, "timeout limpa portal sem beat de close")
VFX.Style.HardMaxLifetime = maxLifetime
check(#workspace.RiftVFX:GetChildren() == 0, "nenhuma fenda residual")
log:Disconnect()
isolation:Disconnect()
check(#errors == 0, "nenhum erro de runtime: " .. table.concat(errors, "; "))
print(string.format("[RiftVFX] PASS: %d verificações no engine real", checked))
