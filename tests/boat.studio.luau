-- Física REAL do engine pro barco de fuga, num lugar descartável:
--   rojo build tests/Boat.project.json --output /tmp/boat-validation.rbxlx
--   run-in-roblox --place /tmp/boat-validation.rbxlx --script tests/boat.studio.luau
-- Gera só o trecho da ilha em volta do Farol (mesma conta do
-- IslandGenerator), monta a lancha padrão e dirige ela com os atuadores de
-- verdade: boiar, arrancar, virar, não andar na areia e o BoatSystem.Init
-- completo (prompts, peças, boias, ponto morto no servidor).
-- Saída: linhas PASS_BOAT / FAIL_BOAT e BOAT_STUDIO_DONE no fim.

local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local Terrain = Workspace.Terrain
local Server = game:GetService("ServerScriptService").Server

local Layout = require(Server.Tools.IslandLayout)
local BoatBuilder = require(Server.BoatBuilder)
local BoatPhysics = require(ReplicatedStorage.Modules.BoatPhysics)
local GameConfig = require(ReplicatedStorage.Modules.GameConfig)
local CFG = GameConfig.Boat
local LC = Layout.CONFIG

local failures = 0
local function check(ok, message)
	if ok then
		print("PASS_BOAT " .. message)
	else
		failures += 1
		warn("FAIL_BOAT " .. message)
	end
end

local function flat(v)
	local f = Vector3.new(v.X, 0, v.Z)
	return if f.Magnitude > 1e-3 then f.Unit else Vector3.new(0, 0, -1)
end
local function yawOf(cf)
	local f = flat(cf.LookVector)
	return math.atan2(-f.X, -f.Z)
end
local function wrap(a)
	return (a + math.pi) % (2 * math.pi) - math.pi
end

--------------------------------------------------------------------------------
-- Terreno: chunks em volta da costa do Farol + mar aberto pra fora
--------------------------------------------------------------------------------

Layout.Plan()
local farol = Layout.Site("Farol")
local angle = if farol then math.atan2(farol.z, farol.x) else 0
local coastDir = Vector3.new(math.cos(angle), 0, math.sin(angle))
local coastPoint = coastDir * Layout.CoastRadiusAt(angle)

local function writeRegion(center, halfChunks)
	local res, chunk = LC.VoxelRes, LC.Chunk
	local minY, maxY = LC.MinY, LC.MaxY
	local ny = (maxY - minY) // res
	local n = chunk // res
	local cx0 = math.floor(center.X / chunk) * chunk
	local cz0 = math.floor(center.Z / chunk) * chunk
	for ix = -halfChunks, halfChunks - 1 do
		for iz = -halfChunks, halfChunks - 1 do
			local cx, cz = cx0 + ix * chunk, cz0 + iz * chunk
			local materials, occupancies = table.create(n), table.create(n)
			for i = 1, n do
				local colM, colO = table.create(ny), table.create(ny)
				for j = 1, ny do
					colM[j] = table.create(n, Enum.Material.Air)
					colO[j] = table.create(n, 0)
				end
				materials[i], occupancies[i] = colM, colO
			end
			for i = 1, n do
				local x = cx + (i - 0.5) * res
				for k = 1, n do
					local z = cz + (k - 0.5) * res
					local h = Layout.Height(x, z)
					local material = Layout.Material(x, z)
					local waterLevel = Layout.WaterLevel(x, z)
					for j = 1, ny do
						local yb = minY + (j - 1) * res
						local occ = math.clamp((h - yb) / res, 0, 1)
						if occ > 0.02 then
							materials[i][j][k] = material
							occupancies[i][j][k] = occ
						elseif yb < waterLevel then
							materials[i][j][k] = Enum.Material.Water
							occupancies[i][j][k] = math.clamp((waterLevel - yb) / res, 0, 1)
						end
					end
				end
			end
			Terrain:WriteVoxels(Region3.new(Vector3.new(cx, minY, cz), Vector3.new(cx + chunk, maxY, cz + chunk)), res, materials, occupancies)
		end
		task.wait()
	end
end

local t0 = os.clock()
writeRegion(coastPoint, 4)
local seaCenter = coastPoint + coastDir * (60 + 450)
Terrain:FillBlock(CFrame.lookAt(Vector3.new(seaCenter.X, -13, seaCenter.Z), Vector3.new(seaCenter.X, -13, seaCenter.Z) + coastDir),
	Vector3.new(900, 34, 900), Enum.Material.Water)
print(string.format("[BoatStudio] terreno em %.1fs", os.clock() - t0))

--------------------------------------------------------------------------------
-- Montagem
--------------------------------------------------------------------------------

local layout = BoatBuilder.Build(CFG)
check(layout ~= nil, "lancha padrão montada na praia perto do Farol")
if not layout then
	print(string.format("BOAT_STUDIO_DONE failures=%d", failures))
	return
end
local model, root, frame = layout.model, layout.root, layout.frame
check(model:GetAttribute("BarcoFuga") == true and model.PrimaryPart == root, "Model marcado, raiz = PrimaryPart")
check(layout.helm:IsA("VehicleSeat") and #layout.seats == CFG.Assentos - 1, "timão + passageiros = lotação")
for _, key in { "Motor", "Tanque", "Ignicao", "EmbarqueBB", "EmbarqueBE", "Proa", "Popa" } do
	check(layout.anchors[key] ~= nil and layout.anchors[key]:IsDescendantOf(model), "ponto de interação " .. key)
end
check(not root.Anchored and root:FindFirstChild(BoatPhysics.LinearName) and root:FindFirstChild(BoatPhysics.AngularName), "solto com atuadores")
local impulse = root:FindFirstChild("Impulso")
check(impulse and (impulse.WorldPosition - root.AssemblyCenterOfMass).Magnitude < 0.05, "atuadores no centro de massa")
local waterY, depth = BoatPhysics.Probe(frame.WorldPosition)
check(waterY ~= nil and math.abs(waterY - LC.SeaLevel) < 0.6, string.format("sonda acha a superfície (%.2f)", waterY or -999))
check(depth ~= nil and depth > CFG.Calado * 2.5, string.format("nasce em água funda (%.1f studs)", depth or -1))
local landY = BoatPhysics.Probe(coastPoint - coastDir * 25)
check(landY == nil, "sonda reconhece terra firme")
local pier = Workspace.Ilha:FindFirstChild("PierBarco")
check(pier ~= nil and #layout.itemSpots >= 4, "píer com lugar pras peças de teste")

--------------------------------------------------------------------------------
-- Câmera de perseguição (modo de edição: no Run o DataModel é servidor e
-- RenderStepped não dispara)
--------------------------------------------------------------------------------

do
	local okCamera, cameraErr = pcall(function()
		local BoatCamera = require(ReplicatedStorage.ClienteTeste.BoatCamera)
		local camera = Workspace.CurrentCamera
		BoatCamera.StartChase(model)
		local rendered = 0
		local counter = RunService.RenderStepped:Connect(function()
			rendered += 1
		end)
		local deadline = os.clock() + 3
		while rendered < 20 and os.clock() < deadline do
			task.wait()
		end
		counter:Disconnect()
		if rendered == 0 then
			BoatCamera.Stop()
			error("sem RenderStepped neste contexto -- câmera fica pro playtest")
		end
		assert(camera.CameraType == Enum.CameraType.Scriptable, "câmera não assumiu")
		local toBoat = frame.WorldPosition - camera.CFrame.Position
		assert(toBoat.Magnitude > 10 and toBoat.Magnitude < 60, "câmera longe/perto demais: " .. toBoat.Magnitude)
		assert(camera.CFrame.LookVector:Dot(toBoat.Unit) > 0.8, "câmera não olha pro barco")
		assert(camera.CFrame.Position.Y > LC.SeaLevel + 1, "câmera abaixo d'água")
		BoatCamera.Stop()
		assert(camera.CameraType == Enum.CameraType.Custom, "câmera não devolvida")
	end)
	check(okCamera, "BoatCamera persegue o barco e devolve a câmera " .. tostring(cameraErr))
end

--------------------------------------------------------------------------------
-- Física
--------------------------------------------------------------------------------

RunService:Run()
task.wait(0.3)
local controller = BoatPhysics.Bind(model, CFG)
check(controller ~= nil, "controlador liga nos atuadores")

local function drive(seconds, throttle, steer, engineOn, onStep)
	local elapsed = 0
	local connection = RunService.PreSimulation:Connect(function(dt)
		elapsed += dt
		local s = if type(steer) == "function" then steer() else steer
		local telemetry = BoatPhysics.Step(controller, dt, throttle, s, engineOn)
		if onStep then
			onStep(telemetry, elapsed)
		end
	end)
	local started = os.clock()
	while elapsed < seconds and os.clock() - started < seconds * 4 + 5 do
		task.wait()
	end
	connection:Disconnect()
end

-- Parado e desligado: boia na linha d'água, de pé, sem sair do lugar.
local start = frame.WorldPosition
local maxDev, minUp = 0, 1
drive(3, 0, 0, false, function(_, elapsed)
	if elapsed > 1.5 then
		local cf = frame.WorldCFrame
		maxDev = math.max(maxDev, math.abs(cf.Position.Y - LC.SeaLevel))
		minUp = math.min(minUp, cf.UpVector.Y)
	end
end)
local drift = Vector3.new(frame.WorldPosition.X - start.X, 0, frame.WorldPosition.Z - start.Z).Magnitude
check(maxDev < 0.8, string.format("boia na linha d'água (desvio máx %.2f)", maxDev))
check(minUp > 0.985, string.format("parado fica de pé (up.Y mín %.3f)", minUp))
check(drift < 2, string.format("parado não deriva (%.2f studs)", drift))

-- Acelerador todo: arranca, plana, continua na água e de pé.
local p0 = frame.WorldPosition
local forward0 = flat(frame.WorldCFrame.LookVector)
local lastSpeed, maxDevRun, minUpRun, peakPitch = 0, 0, 1, -90
drive(5, 1, 0, true, function(telemetry, elapsed)
	lastSpeed = telemetry.speed
	local cf = frame.WorldCFrame
	if elapsed > 1 then
		maxDevRun = math.max(maxDevRun, math.abs(cf.Position.Y - LC.SeaLevel))
	end
	minUpRun = math.min(minUpRun, cf.UpVector.Y)
	peakPitch = math.max(peakPitch, math.deg(math.asin(math.clamp(cf.LookVector.Y, -1, 1))))
end)
local traveled = (frame.WorldPosition - p0):Dot(forward0)
check(traveled > 110, string.format("arranca pro mar (%.0f studs em 5s)", traveled))
check(lastSpeed > 38, string.format("velocidade depois de 5s (%.1f studs/s)", lastSpeed))
check(maxDevRun < 1.5, string.format("continua na água acelerando (desvio máx %.2f)", maxDevRun))
check(minUpRun > 0.95, string.format("não capota acelerando (up.Y mín %.3f)", minUpRun))
check(peakPitch > 2, string.format("proa sobe na arrancada (%.1f°)", peakPitch))

-- Curva pra direita.
local yaw0 = yawOf(frame.WorldCFrame)
local minRoll = 0
drive(3, 0.8, 1, true, function()
	local cf = frame.WorldCFrame
	minRoll = math.min(minRoll, cf.RightVector.Y)
end)
local turned = wrap(yawOf(frame.WorldCFrame) - yaw0)
check(turned < -math.rad(60), string.format("vira pra direita (%.0f°)", math.deg(turned)))
check(minRoll < -0.05, string.format("deita pra dentro da curva (right.Y mín %.3f)", minRoll))

-- Soltou o acelerador: desacelera sozinho.
local before = 0
drive(0.2, 1, 0, true, function(t)
	before = t.speed
end)
local after = before
drive(5, 0, 0, true, function(t)
	after = t.speed
end)
check(after < before * 0.4, string.format("água freia sem acelerador (%.0f -> %.0f)", before, after))

-- ENCALHADO: posto na areia da praia, acelerando, não sai do lugar.
local pierStart = nil
for _, plank in pier:GetChildren() do
	if plank.Name == "Tabua" and (not pierStart or plank.Position.Magnitude < pierStart.Magnitude) then
		pierStart = plank.Position
	end
end
local side = Vector3.new(-coastDir.Z, 0, coastDir.X)
local beach = pierStart - side * 22 - coastDir * 6
local hit = Workspace:Raycast(beach + Vector3.new(0, 60, 0), Vector3.new(0, -120, 0))
local beachY = if hit then hit.Position.Y else LC.ShoreHeight
local frameToPivot = frame.WorldCFrame:ToObjectSpace(model:GetPivot())
local onBeach = CFrame.lookAt(Vector3.new(beach.X, beachY + CFG.Calado + 0.3, beach.Z), Vector3.new(beach.X, beachY + CFG.Calado + 0.3, beach.Z) - coastDir)
model:PivotTo(onBeach * frameToPivot)
root.AssemblyLinearVelocity = Vector3.zero
root.AssemblyAngularVelocity = Vector3.zero
BoatPhysics.Reset(controller)
local surfaces = {}
drive(0.6, 0, 0, false)
local landed = frame.WorldPosition
drive(3, 1, 0.5, true, function(telemetry)
	surfaces[telemetry.surface] = (surfaces[telemetry.surface] or 0) + 1
end)
local movedHorizontal = Vector3.new(frame.WorldPosition.X - landed.X, 0, frame.WorldPosition.Z - landed.Z).Magnitude
check((surfaces.Encalhado or 0) > 0 and not surfaces.Agua, "na areia a sonda diz ENCALHADO")
check(movedHorizontal < 2, string.format("na areia o motor não empurra (%.2f studs)", movedHorizontal))
check(frame.WorldCFrame.UpVector.Y > 0.9, "encalhado fica assentado, não capota")

--------------------------------------------------------------------------------
-- Barco do MAPA: "Speedboat" genérico do Toolbox, sem o Attribute
--------------------------------------------------------------------------------

model:Destroy()
local toolbox = Instance.new("Model")
toolbox.Name = "Speedboat"
local yaw = math.rad(37)
local at = coastPoint + coastDir * 45
local base = CFrame.new(at.X, LC.SeaLevel + 0.2, at.Z) * CFrame.Angles(0, yaw, 0)
local hull = Instance.new("Part")
hull.Name = "Hull"
hull.Size = Vector3.new(6, 2, 16)
hull.CFrame = base
hull.Anchored = true
hull.Parent = toolbox
local deck = Instance.new("Part")
deck.Name = "Deck"
deck.Size = Vector3.new(5.6, 0.4, 15)
deck.CFrame = base * CFrame.new(0, 1.2, 0)
deck.Anchored = true
deck.Parent = toolbox
local driverSeat = Instance.new("VehicleSeat")
driverSeat.Name = "DriveSeat"
driverSeat.Size = Vector3.new(2, 1, 2)
driverSeat.CFrame = base * CFrame.new(0, 1.9, 3)
driverSeat.Anchored = true
driverSeat.Parent = toolbox
local legacyScript = Instance.new("Script")
legacyScript.Name = "BoatScript"
legacyScript.Parent = toolbox
local legacyMover = Instance.new("BodyVelocity")
legacyMover.Parent = hull
toolbox.Parent = Workspace

local mapLayout = BoatBuilder.Build(CFG)
check(mapLayout ~= nil and mapLayout.model == toolbox and not mapLayout.isDefault, "acha o barco do mapa pelo nome (com assento), sem Attribute")
if mapLayout then
	check(legacyScript.Enabled == false and legacyMover.Parent == nil, "script e mover do modelo desligados")
	check(mapLayout.helm == driverSeat, "VehicleSeat do modelo vira o timão")
	local look = flat(mapLayout.frame.WorldCFrame.LookVector)
	check(look:Dot(flat(driverSeat.CFrame.LookVector)) > 0.99, "a frente sai do assento do piloto")
	check(#mapLayout.seats >= 1, "sem bancos no modelo, cria lugares de passageiro")
	local mapController = BoatPhysics.Bind(toolbox, CFG)
	check(mapController ~= nil, "atuadores no barco do mapa")
	controller = mapController
	frame = mapLayout.frame
	local minUpMap, devMap = 1, 0
	drive(2.5, 0, 0, false, function(_, elapsed)
		if elapsed > 1.2 then
			minUpMap = math.min(minUpMap, frame.WorldCFrame.UpVector.Y)
			devMap = math.max(devMap, math.abs(frame.WorldPosition.Y - LC.SeaLevel))
		end
	end)
	check(minUpMap > 0.98 and devMap < 1, string.format("barco do mapa boia de pé (up %.3f, desvio %.2f)", minUpMap, devMap))
	local from = frame.WorldPosition
	drive(3, 1, 0, true)
	local advanced = (frame.WorldPosition - from):Dot(look)
	check(advanced > 40, string.format("barco do mapa anda pra frente (%.0f studs em 3s)", advanced))
end
toolbox:Destroy()

--------------------------------------------------------------------------------
-- BoatSystem.Init completo
--------------------------------------------------------------------------------

local BoatSystem = require(Server.BoatSystem)
local ok, err = pcall(BoatSystem.Init)
check(ok, "BoatSystem.Init sem erro " .. tostring(err))
local ref = ReplicatedStorage:FindFirstChild("BarcoFuga")
local boat = ref and ref.Value
check(boat and boat:GetAttribute("BarcoFuga") == true and boat ~= model, "referência publicada pro cliente")
check(boat and boat.Name == "BarcoFuga" and boat:GetAttribute("Padrao") == true,
	"sem barco no mapa monta a lancha padrão (o píer não é confundido com barco)")
local ring = Workspace.Ilha:FindFirstChild("LimiteFuga")
check(ring and #ring:GetChildren() >= 50, "anel de boias do limite")
local prompts = {}
if boat then
	for _, d in boat:GetDescendants() do
		if d:IsA("ProximityPrompt") then
			prompts[d.Name] = (prompts[d.Name] or 0) + 1
		end
	end
end
check(prompts.InstalarPecaBarco == 1 and prompts.AbastecerBarco == 1 and prompts.ChaveBarco == 1
	and prompts.PilotarBarco == 1 and prompts.EmbarcarBarco == 2 and prompts.EmpurrarBarco == 2, "prompts do barco")
local function countItems()
	local found = {}
	for _, d in Workspace:GetDescendants() do
		if d:IsA("Tool") and d:GetAttribute("_BarcoItem") == true then
			found[d:GetAttribute("WorldItemId")] = (found[d:GetAttribute("WorldItemId")] or 0) + 1
		end
	end
	return found
end
local items = countItems()
check(items.HeliceBarco == 1 and items.VelaIgnicao == 1 and items.ChaveBarco == 1 and items.Gasolina == 1, "uma peça de cada por rodada")
task.wait(3)
if boat and boat.PrimaryPart then
	local q = boat.PrimaryPart:FindFirstChild(BoatPhysics.FrameName)
	check(q and math.abs(q.WorldPosition.Y - LC.SeaLevel) < 0.9 and q.WorldCFrame.UpVector.Y > 0.98,
		"sem piloto, o servidor mantém o barco boiando")
end
local okReset, resetErr = pcall(BoatSystem.Reset)
check(okReset, "Reset de rodada sem erro " .. tostring(resetErr))
task.wait(0.5)
items = countItems()
check(items.HeliceBarco == 1 and items.VelaIgnicao == 1 and items.ChaveBarco == 1 and items.Gasolina == 1, "reset repõe as peças sem duplicar")

--------------------------------------------------------------------------------
-- Cliente: efeitos e câmera no barco de verdade (propriedades do engine)
--------------------------------------------------------------------------------

local client = ReplicatedStorage:FindFirstChild("ClienteTeste")
local okEffects, effectsErr = pcall(function()
	local BoatEffects = require(client.BoatEffects)
	-- Os efeitos se desligam com a câmera a mais de 520 studs (a do Studio
	-- nasce na origem): põe a câmera olhando o barco antes de cada passo.
	local camera = Workspace.CurrentCamera
	local function lookAtBoat()
		local p = boat:GetPivot().Position
		camera.CFrame = CFrame.lookAt(p + Vector3.new(0, 18, 40), p)
	end
	lookAtBoat()
	local handle = BoatEffects.Attach(boat)
	assert(handle, "Attach devolveu nil")
	local emitters = 0
	for _ in handle.emitters do
		emitters += 1
	end
	assert(emitters >= 8 and handle.trail, "faltam emissores/esteira: " .. emitters)
	for _ = 1, 30 do
		lookAtBoat()
		BoatEffects.Update(handle, 1 / 30, { speed = 52, planing = 1, rpm = 0.95, throttle = 1, steer = 0.6, surface = "Agua" })
	end
	assert(handle.trail.Enabled, "esteira desligada em velocidade")
	assert(handle.emitters.SprayBB.Rate > handle.emitters.SprayBE.Rate, "spray maior do lado de fora da curva")
	lookAtBoat()
	BoatEffects.Update(handle, 1 / 30, { speed = 0, planing = 0, rpm = 0, throttle = 0, steer = 0, surface = "Encalhado" })
	assert(not handle.trail.Enabled, "esteira ligada encalhado")
	camera.CFrame = CFrame.new(0, 50, 0)
	BoatEffects.Update(handle, 1 / 30, { speed = 52, planing = 1, rpm = 0.95, throttle = 1, steer = 0, surface = "Agua" })
	assert(not handle.trail.Enabled and handle.emitters.SprayBB.Rate == 0, "longe da câmera os efeitos desligam")
	BoatEffects.Splash(handle, 1)
	BoatEffects.UpdateBuoys(0.1)
	BoatEffects.Destroy(handle)
end)
check(okEffects, "BoatEffects roda no barco real " .. tostring(effectsErr))


--------------------------------------------------------------------------------
-- Sons: o engine consegue baixar cada id de AssetRegistry.Sounds.Barco?
--------------------------------------------------------------------------------

do
	local ContentProvider = game:GetService("ContentProvider")
	local sounds = require(ReplicatedStorage.Modules.AssetRegistry).Sounds.Barco
	local probes, statuses = {}, {}
	for _, id in sounds do
		if id ~= "" then
			local probe = Instance.new("Sound")
			probe.SoundId = id
			table.insert(probes, probe)
		end
	end
	local okPreload, preloadErr = pcall(function()
		ContentProvider:PreloadAsync(probes, function(contentId, status)
			statuses[contentId] = status
		end)
	end)
	check(okPreload, "PreloadAsync dos sons " .. tostring(preloadErr))
	for key, id in sounds do
		if id ~= "" then
			check(statuses[id] == Enum.AssetFetchStatus.Success, string.format("som %s carrega (%s: %s)", key, id, tostring(statuses[id])))
		end
	end
end

print(string.format("BOAT_STUDIO_DONE failures=%d", failures))
