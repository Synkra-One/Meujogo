--!nocheck
-- sources vem do runner; plano, gerador e mobiliário são módulos REAIS.
-- Aqui verificamos sólidos/aberturas e escavação solicitada, não renderização.
local stub = loadstring(sources.RobloxStub, "RobloxStub")()
local Workspace = stub.Workspace
Vector2 = { new = function(x, y) return { X = x, Y = y } end }
RaycastParams = { new = function() return {} end }
Random = { new = function(seed)
	local state = seed or 123
	local function unit()
		state = (state * 16807) % 2147483647
		return state / 2147483647
	end
	return {
		NextNumber = function(_, low, high)
			return (low or 0) + unit() * ((high or 1) - (low or 0))
		end,
		NextInteger = function(_, low, high) return low + math.floor(unit() * (high - low + 1)) end,
	}
end }
function Workspace:Raycast() return nil end

-- Extensões estritamente locais: o stub compartilhado permanece intacto.
local cfMethods = getmetatable(CFrame.identity)
function cfMethods:PointToObjectSpace(position)
	local delta = position - self.Position
	return Vector3.new(delta:Dot(self.RightVector), delta:Dot(self.UpVector), delta:Dot(-self.LookVector))
end
function cfMethods:PointToWorldSpace(position) return self * position end
function cfMethods:VectorToObjectSpace(vector)
	return Vector3.new(vector:Dot(self.RightVector), vector:Dot(self.UpVector), vector:Dot(-self.LookVector))
end
function cfMethods:Inverse()
	local r = self.R
	local position = self:VectorToObjectSpace(-self.Position)
	return CFrame.fromMatrix(position, Vector3.new(r[1], r[2], r[3]), Vector3.new(r[4], r[5], r[6]), Vector3.new(r[7], r[8], r[9]))
end
function cfMethods:ToObjectSpace(other) return self:Inverse() * other end

local modules = {}
local tokens = setmetatable({}, { __index = function(t, key)
	local token = { __module = key }
	rawset(t, key, token)
	return token
end })
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
	-- Structures carrega AssetRegistry/AssetLoader por ReplicatedStorage.Modules.
	require = function(token) return loadModule(token.__module or token.Name) end,
	typeof = function(value)
		if type(value) == "table" and value.R then return "CFrame" end
		if type(value) == "table" and value.X and value.Z then return "Vector3" end
		return typeof(value)
	end,
}, { __index = getfenv() })

local checks = 0
local function check(condition, message, ...)
	checks += 1
	if not condition then error(string.format(message, ...), 0) end
end
local function near(a, b) return math.abs(a - b) < 0.001 end
local function contains(box, x, y, z)
	return x >= box.Lo.X - 0.001 and x <= box.Hi.X + 0.001
		and y >= box.Lo.Y - 0.001 and y <= box.Hi.Y + 0.001
		and z >= box.Lo.Z - 0.001 and z <= box.Hi.Z + 0.001
end
local function overlaps(box, lo, hi)
	return box.Lo.X < hi.X - 0.001 and box.Hi.X > lo.X + 0.001
		and box.Lo.Y < hi.Y - 0.001 and box.Hi.Y > lo.Y + 0.001
		and box.Lo.Z < hi.Z - 0.001 and box.Hi.Z > lo.Z + 0.001
end
local function anyContains(boxes, x, y, z)
	for _, box in boxes do
		if contains(box, x, y, z) then return true end
	end
	return false
end
local function bounds(frame, cf, size)
	local localCF = frame:ToObjectSpace(cf)
	local extent = stub.PartExtents({ CFrame = localCF, Size = size }) / 2
	return { Lo = localCF.Position - extent, Hi = localCF.Position + extent }
end
local function isDoorDecoration(part)
	local node = part
	while node do
		if node:GetAttribute("Porta") == true then return true end
		node = node.Parent
	end
	return false
end

game:GetService("ReplicatedStorage").Modules = { AssetRegistry = tokens.AssetRegistry, AssetLoader = tokens.AssetLoader }

local Generator = loadModule("AbyssStationGenerator")
local Plan = loadModule("AbyssStationPlan")
local function inspect(frame, terrainEnabled, entryGround, exitGround)
	entryGround, exitGround = entryGround or 24, exitGround or 9
	local plan = Plan.Create(entryGround, exitGround)
	local station = Generator.Build(7331, { Frame = frame, EntryGround = entryGround, ExitGround = exitGround, Terrain = terrainEnabled })
	check(station and station:IsA("Model"), "Build deve devolver o Model da estação")
	check(station.Name == "EstacaoAbismo" and station.Parent == Workspace:FindFirstChild("Ilha"), "hierarquia da estação mudou")
	check(station:GetAttribute("EstacaoAbismo") == true and station:GetAttribute("Construcao") == "Abismo", "marcadores de integração ausentes")
	local shells, solids, steps, doors, doorByName = {}, {}, {}, {}, {}
	local partCount, lootCount = 0, 0
	for _, part in station:GetDescendants() do
		check(part.ClassName ~= "TrussPart", "acesso de escalar reapareceu: %s", part.Name)
		check(not string.find(string.lower(part.Name), "escotilha"), "escotilha reapareceu: %s", part.Name)
		if part:IsA("BasePart") then
			partCount += 1
			local box = bounds(frame, part.CFrame, part.Size)
			box.Part = part
			if part:GetAttribute("AbismoShell") == true then
				check(part.CanCollide and part.Anchored, "casca precisa ser sólida e fixa: %s", part.Name)
				table.insert(shells, box)
			end
			if part.CanCollide and not isDoorDecoration(part) then table.insert(solids, box) end
			if part:GetAttribute("AbismoStep") == true then table.insert(steps, box) end
			if part:GetAttribute("PontoLoot") == true then lootCount += 1 end
			if part:GetAttribute("Porta") == true then
				table.insert(doors, part)
				doorByName[part.Name] = part
			end
		end
	end
	check(partCount > 900 and partCount < 6000, "orçamento/inventário inesperado: %d peças", partCount)
	check(#shells > 30, "casca não identificada para verificação")
	check(lootCount >= 8, "salas sem pontos de loot: %d", lootCount)
	check(#doors == #plan.Doors, "esperadas %d portas funcionais; encontradas %d", #plan.Doors, #doors)
	for _, specification in plan.Doors do
		local door = doorByName["Door" .. specification.Name]
		check(door ~= nil, "porta não existe: %s", specification.Name)
		check(door:GetAttribute("PortaAberta") == false, "%s começa em estado inválido", door.Name)
		check(near(door:GetAttribute("LarguraPorta"), door.Size.X), "%s tem dobradiça/largura incompatível", door.Name)
		local closed = door:GetAttribute("CFrameFechada")
		check(closed and (closed.Position - door.Position).Magnitude < 0.001, "%s não tem pose fechada válida", door.Name)
		local localPosition = frame:PointToObjectSpace(door.Position)
		check(math.abs(localPosition.X - specification.X) < 1.5 and math.abs(localPosition.Z - specification.Z) < 1.5, "%s fora da face da abertura", door.Name)
		-- Sample the real DoorSystem hinge arc against the structural shell.
		local width = door.Size.X
		for angle = 0, 100, 5 do
			local pose = closed * CFrame.new(-width / 2, 0, 0) * CFrame.Angles(0, math.rad(angle), 0) * CFrame.new(width / 2, 0, 0)
			for along = -width / 2 + 0.1, width / 2 - 0.1, 0.3 do
				for _, depth in { -0.2, 0.2 } do
					local p = frame:PointToObjectSpace(pose * Vector3.new(along, 0, depth))
					check(not anyContains(shells, p.X, p.Y, p.Z), "%s atravessa parede ao abrir %d graus", door.Name, angle)
					check(not anyContains(solids, p.X, p.Y - 2, p.Z), "%s atravessa móvel ao abrir %d graus", door.Name, angle)
				end
			end
		end
		for _, decoration in door:GetDescendants() do
			if decoration:IsA("BasePart") then
				check(not decoration.Anchored and not decoration.CanCollide, "%s ficaria parado/bloquearia a porta ao abrir", decoration.Name)
				local welded = false
				for _, joint in door:GetDescendants() do
					if joint.ClassName == "WeldConstraint" and ((joint.Part0 == door and joint.Part1 == decoration) or (joint.Part1 == door and joint.Part0 == decoration)) then welded = true end
				end
				check(welded, "%s não está soldado à folha %s", decoration.Name, door.Name)
			end
		end
	end
	check(doorByName.DoorEntrada:GetAttribute("AbismoPortaPrincipal") == true, "porta principal sem gancho de gameplay")

	-- Piso e teto contínuos em TODAS as salas, inclusive no encontro entre elas.
	for _, room in plan.Rooms do
		for x = room.X0 + 0.1, room.X1 - 0.1, 1 do
			for z = room.Z0 + 0.1, room.Z1 - 0.1, 1 do
				check(anyContains(shells, x, room.Floor - 0.1, z), "%s: buraco de piso em %.1f,%.1f", room.Name, x, z)
				check(anyContains(shells, x, room.Floor + room.Height + 0.1, z), "%s: teto aberto em %.1f,%.1f", room.Name, x, z)
			end
		end
	end
	-- Abre somente os vãos declarados no plano; partições compartilhadas também
	-- são verificadas pelo lado da sala que não construiu a parede.
	local function declaredOpening(x, y, z)
		if y > Plan.Floor + Plan.DoorHeight - 0.01 then return false end
		for _, room in plan.Rooms do
			for side, openings in room.Openings do
				local onWall = (side == "XMin" and near(x, room.X0)) or (side == "XMax" and near(x, room.X1))
					or (side == "ZMin" and near(z, room.Z0)) or (side == "ZMax" and near(z, room.Z1))
				if onWall then
					local axis = if string.sub(side, 1, 1) == "X" then z else x
					for _, opening in openings do
						if axis > opening[1] - 0.001 and axis < opening[2] + 0.001 then return true end
					end
				end
			end
		end
		return false
	end
	for _, room in plan.Rooms do
		for _, side in { "XMin", "XMax", "ZMin", "ZMax" } do
			local alongX = string.sub(side, 1, 1) == "Z"
			local start = if alongX then room.X0 else room.Z0
			local finish = if alongX then room.X1 else room.Z1
			for axis = start + 0.25, finish - 0.1, 0.5 do
				for y = room.Floor + 0.25, room.Floor + room.Height - 0.1, 1 do
					local x = if alongX then axis else (if side == "XMin" then room.X0 else room.X1)
					local z = if not alongX then axis else (if side == "ZMin" then room.Z0 else room.Z1)
					check(anyContains(shells, x, y, z) or declaredOpening(x, y, z), "%s: parede %s aberta fora de porta em (%.2f,%.2f,%.2f)", room.Name, side, x, y, z)
				end
			end
		end
	end

	-- Um degrau desenha uma escada; a tolerância acompanha o espelho do plano.
	local tolerance = Plan.MaxRiser + 0.2
	-- O mobiliário se espalha pelas paredes conforme os vãos do plano: nada
	-- pode furar a casca nem passar do teto da própria sala.
	for _, room in plan.Rooms do
		local folder = station:FindFirstChild(room.Name)
		local furniture = folder and folder:FindFirstChild("Mobiliario_" .. room.Kind)
		check((room.Kind == "Corredor") == (furniture == nil), "%s: mobiliário no lugar errado", room.Name)
		for _, piece in (if furniture then furniture:GetDescendants() else {}) do
			if piece:IsA("BasePart") then
				local box = bounds(frame, piece.CFrame, piece.Size)
				check(box.Lo.X > room.X0 + 0.2 and box.Hi.X < room.X1 - 0.2
					and box.Lo.Z > room.Z0 + 0.2 and box.Hi.Z < room.Z1 - 0.2
					and box.Hi.Y < room.Floor + room.Height - 0.2,
					"%s: %s do mobiliário atravessa a casca", room.Name, piece.Name)
			end
		end
	end

	local function surface(x, z, expected)
		local floor = -math.huge
		for _, box in solids do
			if x >= box.Lo.X - 0.001 and x <= box.Hi.X + 0.001 and z >= box.Lo.Z - 0.001 and z <= box.Hi.Z + 0.001
				and box.Hi.Y <= expected + tolerance and box.Hi.Y >= expected - tolerance then
				floor = math.max(floor, box.Hi.Y)
			end
		end
		return floor
	end
	-- `climb` é o quanto o personagem sobe sem pular: na escada o degrau
	-- seguinte fica acima dos pés e não conta como obstáculo.
	local function freeBody(x, y, z, radius, depth, climb)
		local lo, hi = Vector3.new(x - radius, y + (climb or 0.7), z - depth), Vector3.new(x + radius, y + 8, z + depth)
		for _, box in solids do
			if overlaps(box, lo, hi) then return false, box.Part.Name end
		end
		return true
	end
	local function expectedHeight(z)
		for _, stair in plan.Stairs do
			if z >= stair.Z0 and z <= stair.Z1 then return stair.Y0 + (stair.Y1 - stair.Y0) * (z - stair.Z0) / (stair.Z1 - stair.Z0) end
		end
		return if z < plan.Stairs[1].Z0 then plan.EntryFloor elseif z > plan.Stairs[2].Z1 then plan.ExitFloor else Plan.Floor
	end
	-- Faixa central com 4 studs de largura, da minicaverna até a saída seca.
	for z = Plan.CaveZ0 + 8, Plan.PatioZ1 - 8, 0.25 do
		local expected = expectedHeight(z)
		for _, x in { -2, 0, 2 } do
			local floor = surface(x, z, expected)
			check(floor > -math.huge, "buraco na rota principal x=%.2f z=%.2f (piso esperado %.2f)", x, z, expected)
			local free, obstruction = freeBody(x, floor, z, 0.4, 0.05, Plan.MaxRiser + 0.05)
			check(free, "rota principal sem altura livre de 8 studs em x=%.2f z=%.2f: %s", x, z, tostring(obstruction))
		end
	end
	local countedSteps = 0
	for _, stair in plan.Stairs do
		local found = {}
		for _, box in steps do
			if box.Lo.Z >= stair.Z0 - 0.001 and box.Hi.Z <= stair.Z1 + 0.001 then table.insert(found, box) end
		end
		table.sort(found, function(a, b) return a.Lo.Z < b.Lo.Z end)
		check(#found == stair.Count, "%s: quantidade de degraus difere do plano (%d/%d)", stair.Name, #found, stair.Count)
		local previousZ, previousY = stair.Z0, stair.Y0
		for _, step in found do
			check(near(step.Lo.Z, previousZ), "%s: fresta entre degraus em z=%.2f", stair.Name, step.Lo.Z)
			check(step.Hi.Z - step.Lo.Z >= Plan.MinTread - 0.001, "%s: degrau estreito demais", stair.Name)
			check(math.abs(step.Hi.Y - previousY) <= Plan.MaxRiser + 0.001, "%s: espelho maior que %.2f em z=%.2f", stair.Name, Plan.MaxRiser, step.Lo.Z)
			previousZ, previousY = step.Hi.Z, step.Hi.Y
		end
		check(near(previousZ, stair.Z1) and math.abs(previousY - stair.Y1) <= Plan.MaxRiser + 0.001, "%s não se conecta ao patamar", stair.Name)
		countedSteps += #found
	end
	check(countedSteps == #steps, "existem degraus fora das duas escadas")
	-- A reforma trocou lance longo por corpo maior: menos degraus para o mesmo
	-- desnível e escadas bem mais curtas que o corpo do laboratório.
	local descent = (plan.EntryFloor - Plan.Floor) + (plan.ExitFloor - Plan.Floor)
	check(countedSteps < descent / 0.7, "escadaria voltou a ficar densa: %d degraus para %d studs", countedSteps, descent)
	local stairLength = 0
	for _, stair in plan.Stairs do stairLength += stair.Z1 - stair.Z0 end
	local body = plan.Stairs[2].Z0 - plan.Stairs[1].Z1
	check(body > stairLength * 1.2, "corpo do laboratório (%d) precisa ser maior que as escadas (%d)", body, stairLength)

	-- BFS real dos volumes sólidos: cada sala precisa ser acessível a pé.
	local spine = plan.Rooms[2]
	local startZ = math.floor((spine.Z0 + spine.Z1) / 2)
	local queue, seen = { { 0, startZ } }, { ["0," .. startZ] = true }
	local function pointInStation(x, z)
		for _, room in plan.Rooms do
			if x >= room.X0 and x <= room.X1 and z >= room.Z0 and z <= room.Z1 then return true end
		end
		return false
	end
	local index = 1
	while index <= #queue do
		local cell = queue[index]
		index += 1
		for _, delta in { { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } } do
			local x, z = cell[1] + delta[1], cell[2] + delta[2]
			local key = x .. "," .. z
			if not seen[key] and pointInStation(x, z) and surface(x, z, Plan.Floor) > -math.huge and freeBody(x, Plan.Floor, z, 1.1, 1.1) then
				seen[key] = true
				table.insert(queue, { x, z })
			end
		end
	end
	for _, room in plan.Rooms do
		local x, z = math.floor((room.X0 + room.X1) / 2), math.floor((room.Z0 + room.Z1) / 2)
		check(seen[x .. "," .. z], "%s inacessível: passagem bloqueada ou sem altura", room.Name)
	end

	if terrainEnabled then
		local fills, airCount = {}, 0
		for _, fill in stub.TerrainFills do
			check(fill.Material.Name ~= "Water", "laboratório/saída recebeu água de terreno")
			local box = bounds(frame, fill.CFrame, fill.Size)
			box.Material = fill.Material.Name
			table.insert(fills, box)
			if box.Material == "Air" then airCount += 1 end
		end
		local function finalTerrain(x, y, z)
			for i = #fills, 1, -1 do
				if contains(fills[i], x, y, z) then return fills[i].Material end
			end
			return nil
		end
		check(airCount > 0, "nenhuma escavação emitida")
		for _, room in plan.Rooms do
			local margin = Plan.TerrainMargin
			for _, x in { room.X0 - Plan.Wall / 2 - margin, room.X1 + Plan.Wall / 2 + margin } do
				for _, y in { room.Floor - Plan.Slab - margin, room.Floor + room.Height + Plan.Slab + Plan.CeilingMargin } do
					for _, z in { room.Z0 - Plan.Wall / 2 - margin, room.Z1 + Plan.Wall / 2 + margin } do
						check(finalTerrain(x, y, z) == "Air", "%s: escavação sem margem de 8 studs em %.1f,%.1f,%.1f", room.Name, x, y, z)
					end
				end
			end
			for x = room.X0, room.X1, 4 do
				for z = room.Z0, room.Z1, 4 do
					for y = room.Floor - 1, room.Floor + room.Height + 1, 4 do
						check(finalTerrain(x, y, z) == "Air", "%s: terreno não escavado/reintroduzido no interior em %.1f,%.1f,%.1f", room.Name, x, y, z)
					end
				end
			end
		end
	end
	local hall, capsule
	for _, room in plan.Rooms do
		if room.Kind == "Bioteste" then hall = room end
	end
	check(hall and (hall.X1 - hall.X0) * (hall.Z1 - hall.Z0) >= 4000, "salão de testes pequeno demais")
	for _, item in station:GetDescendants() do
		if item:GetAttribute("FrogGenerator") == true then capsule = item end
	end
	check(capsule ~= nil, "Frog Generator não foi montado no salão de testes")
	local capsuleParts = 0
	for _, piece in capsule:GetDescendants() do
		if piece:IsA("BasePart") then
			capsuleParts += 1
			local p = frame:PointToObjectSpace(piece.Position)
			check(p.X > hall.X0 and p.X < hall.X1 and p.Z > hall.Z0 and p.Z < hall.Z1,
				"%s do Frog Generator ficou fora do salão", piece.Name)
		end
	end
	check(capsuleParts > 20, "Frog Generator sem a cápsula montada: %d peças", capsuleParts)
	print(string.format("Abismo: %d peças, %d degraus, %d portas, %d células caminháveis; frame yaw %.2f", partCount, #steps, #doors, #queue, frame.LookVector.X))
	return station, doorByName.DoorEntrada
end

local axisFrame = CFrame.new(150, 0, -210)
inspect(axisFrame, true)
table.clear(stub.TerrainFills)
local frame = CFrame.new(-320, 0, 280) * CFrame.Angles(0, math.rad(37), 0)
local station, entrance = inspect(frame, true)
local closed = entrance:GetAttribute("CFrameFechada")
local previousFills = #stub.TerrainFills
local rebuilt = Generator.Build(7331, { Terrain = false })
check(rebuilt ~= station and station.Parent == nil, "reconstrução não substitui modelo anterior")
check(#stub.TerrainFills == previousFills, "Terrain=false alterou terreno")
local count = 0
local rebuiltEntrance
for _, child in Workspace:FindFirstChild("Ilha"):GetChildren() do
	if child.Name == "EstacaoAbismo" then count += 1 end
end
for _, child in rebuilt:GetDescendants() do
	if child.Name == "DoorEntrada" then rebuiltEntrance = child end
end
check(count == 1, "reconstrução deixou %d estações", count)
check(rebuiltEntrance and (rebuiltEntrance.Position - closed.Position).Magnitude < 0.001, "reconstrução migrou a entrada")
check((rebuiltEntrance.CFrame.LookVector - closed.LookVector).Magnitude < 0.001, "reconstrução inverteu o acesso/costa")
local success = pcall(function()
	Generator.Build(7331, { Frame = frame, EntryGround = 250, ExitGround = 9, Terrain = true })
end)
check(not success, "plano com escada impossível foi aceito")
check(rebuilt.Parent == Workspace:FindFirstChild("Ilha"), "plano inválido removeu a estação anterior")
check(#stub.TerrainFills == previousFills, "plano inválido alterou terreno antes da validação")

table.clear(stub.TerrainFills)
inspect(axisFrame, true, 42, 12)

-- Auto-localização no relevo real do Layout, inclusive arredondamento de voxel.
Generator.Clear()
local Layout = loadModule("IslandLayout")
function Workspace:Raycast(origin)
	local y = math.ceil(Layout.Height(origin.X, origin.Z) / 4) * 4
	return { Position = Vector3.new(origin.X, y, origin.Z) }
end
local auto = Generator.Build(1337)
check(auto.Parent == Workspace:FindFirstChild("Ilha"), "seed padrão não tem local viável")
check(auto:GetAttribute("AbismoExitGround") >= Layout.CONFIG.SeaLevel + 2, "saída automática submersa")

-- Recover the center of a legacy four-piece hatch (the first slab is offset).
Generator.Clear()
local ilha = Workspace:FindFirstChild("Ilha")
local old = Instance.new("Model")
old.Name, old.Parent = "EstacaoAbismo", ilha
local hatch = Instance.new("Folder")
hatch.Name, hatch.Parent = "Escotilha", old
local legacyFrame = CFrame.new(320, 0, -220) * CFrame.Angles(0, math.rad(23), 0)
local S = loadModule("Structures")
for _, offset in { Vector3.new(0, 25, -7.25), Vector3.new(0, 25, 7.25), Vector3.new(-7.25, 25, 0), Vector3.new(7.25, 25, 0) } do
	S.Part(hatch, "ColarEscotilha", Vector3.new(4, 2, 4), legacyFrame * CFrame.new(offset) * CFrame.Angles(0, math.pi, 0), Enum.Material.Concrete, Color3.new(1, 1, 1))
end
local function scenery(name, position)
	local f = ilha:FindFirstChild(name)
	if not f then f = Instance.new("Folder"); f.Name, f.Parent = name, ilha end
	return S.Part(f, "CenarioExistente", Vector3.new(3, 12, 3), legacyFrame * CFrame.new(position), Enum.Material.Wood, Color3.new(0, 1, 0))
end
local tree = scenery("Floresta", Vector3.new(0, 25, -76))
local grass = scenery("Vegetacao", Vector3.new(1, 24, -72))
local rock = scenery("Rochas", Vector3.new(0, 11, 170))
local outside = scenery("Floresta", Vector3.new(100, 25, -76))
table.clear(stub.TerrainFills)
local migrated = Generator.Build(1337, { EntryGround = 24, ExitGround = 9 })
local recovered = migrated:GetAttribute("AbismoFrame")
check((recovered.Position - legacyFrame.Position).Magnitude > 10, "migração manteve o sítio antigo alto demais")
check(old.Parent == nil, "modelo antigo não substituído")
check(stub.TerrainFills[1].Material.Name == "Rock", "poço antigo não fechado antes de escavar")
check(tree.Parent == ilha:FindFirstChild("Floresta") and grass.Parent == ilha:FindFirstChild("Vegetacao"), "cenário antigo foi removido fora da nova estação")
check(rock.Parent == ilha:FindFirstChild("Rochas") and outside.Parent == ilha:FindFirstChild("Floresta"), "cenário externo foi removido")
-- Ponto de entrada da Command Bar: relatório no Output e em ServerStorage.DiagAbismo.
Generator.Clear()
table.clear(stub.TerrainFills)
local report = loadModule("AbyssStationRunner").Run(7331)
local diag = game:GetService("ServerStorage"):FindFirstChild("DiagAbismo")
check(diag and diag.Value == report, "Runner não gravou o relatório em ServerStorage.DiagAbismo")
check(string.find(report, "OK: estação construída", 1, true), "Runner não reportou sucesso:\n%s", report)
check(string.find(report, "FrogGenerator no modelo: true", 1, true), "Runner não achou o Frog Generator:\n%s", report)
check(Workspace:FindFirstChild("Ilha"):FindFirstChild("EstacaoAbismo") ~= nil, "Runner não construiu a estação")
print(string.format("PASS: Estação Abismo; %d verificações de geometria, acesso, integração e reconstrução", checks))
