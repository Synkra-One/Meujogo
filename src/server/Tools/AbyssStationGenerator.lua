--!strict
-- Editor tool. Run Build() AFTER generating terrain, then save the place.
-- +Z points to the coast. All rooms, stairs and excavation use the same plan.
local Workspace = game:GetService("Workspace")
local ServerStorage = game:GetService("ServerStorage")
local RunService = game:GetService("RunService")
local S = require(script.Parent.Structures)
local Layout = require(script.Parent.IslandLayout)
local Plan = require(script.Parent.AbyssStationPlan)
local Furnishings = require(script.Parent.AbyssLabFurnishings)
local Generator = {}
Generator.CONFIG = Plan

local COL = {
	Wall = Color3.fromRGB(186, 200, 204), Lower = Color3.fromRGB(49, 77, 86),
	Floor = Color3.fromRGB(53, 66, 73), Ceiling = Color3.fromRGB(107, 124, 132),
	Trim = Color3.fromRGB(27, 42, 51), Steel = Color3.fromRGB(114, 139, 149),
	Light = Color3.fromRGB(170, 228, 235), Green = Color3.fromRGB(115, 222, 169),
	Amber = Color3.fromRGB(225, 177, 95), Rock = Color3.fromRGB(65, 77, 73),
}

local function folder(parent: Instance, name: string): Folder
	local f = Instance.new("Folder")
	f.Name = name
	f.Parent = parent
	return f
end

local function surface(frame: CFrame, z: number): number
	local p = frame * Vector3.new(0, 0, z)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = { Workspace.Terrain }
	params.IgnoreWater = true
	local hit = Workspace:Raycast(Vector3.new(p.X, 256, p.Z), Vector3.new(0, -512, 0), params)
	return if hit then hit.Position.Y else Layout.Height(p.X, p.Z)
end

local function stationFrame(origin: Vector3, coast: Vector3): CFrame
	return CFrame.fromMatrix(Vector3.new(origin.X, 0, origin.Z),
		Vector3.new(coast.Z, 0, -coast.X), Vector3.new(0, 1, 0), coast)
end

local function previousSite(existing: Instance?): (CFrame?, number?, number?, CFrame?)
	if not existing then return nil, nil, nil end
	local saved = existing:GetAttribute("AbismoFrame")
	if typeof(saved) == "CFrame" and existing:GetAttribute("AbismoVersion") == Plan.Version then
		return saved, existing:GetAttribute("AbismoEntryGround"), existing:GetAttribute("AbismoExitGround")
	end
	if typeof(saved) == "CFrame" then
		return nil, nil, nil, saved
	end
	local hatch = existing:FindFirstChild("Escotilha")
	local collar = hatch and hatch:FindFirstChild("ColarEscotilha")
	if collar and collar:IsA("BasePart") then
		-- The legacy collar consists of offset slabs; recover the shaft center
		-- from the complete hatch floor, not the first slab's off-center pivot.
		local sum, count = Vector3.zero, 0
		if hatch then
			for _, piece in hatch:GetDescendants() do
				if piece:IsA("BasePart") and piece.Name == "ColarEscotilha" then
					sum += piece.Position
					count += 1
				end
			end
		end
		-- The old entrance may be on a hill that cannot host the new safe stair.
		-- Return it separately so Build can seal it before choosing a new site.
		return nil, nil, nil, stationFrame(if count > 0 then sum / count else collar.Position, collar.CFrame.LookVector)
	end
	return nil, nil, nil
end

-- A estação nasce do lado OPOSTO da ilha em relação à montanha: o covil do
-- Monstro e o laboratório nunca ficam na mesma encosta. Varremos os ângulos
-- todos, exigimos separação angular e distância da boca da caverna, e
-- escolhemos o melhor corredor costeiro que sobrar.
local function findSite(): CFrame
	local mountainX, mountainZ = Layout.MountainSite()
	local caveX, caveZ = Layout.CaveEntrance()
	local mountainAngle = math.atan2(mountainZ, mountainX)
	local seaFloor = math.max(Plan.ExitGround.Min, Layout.CONFIG.SeaLevel + 2)
	local bodyMin, bodyMax = Plan.EntryStairZ[2], Plan.ExitStairZ[1]
	local candidates = {}
	for i = 0, 71 do
		local angle = i * math.pi / 36
		local sea = Vector3.new(math.cos(angle), 0, math.sin(angle))
		local dist = Layout.CoastRadiusAt(angle) - Plan.CoastDistance
		local cf = stationFrame(sea * dist, sea)
		local clear, mountain, caveGap, body = true, 0, math.huge, math.huge
		for _, z in Plan.SiteSamples do
			local p = cf * Vector3.new(0, 0, z)
			if Layout.IsClearAt(p.X, p.Z, 20) then clear = false end
			mountain = math.max(mountain, Layout.MountainContribution(p.X, p.Z))
			caveGap = math.min(caveGap, math.sqrt((p.X - caveX) ^ 2 + (p.Z - caveZ) ^ 2))
			if z > bodyMin and z < bodyMax then
				-- Rocha sobre o teto: medimos também as alas, não só o eixo.
				for _, x in { -66, 0, 88 } do
					local q = cf * Vector3.new(x, 0, z)
					body = math.min(body, Layout.Height(q.X, q.Z))
					if Layout.IsClearAt(q.X, q.Z, 8) then clear = false end
				end
			end
		end
		if dist > 140 then
			table.insert(candidates, {
				Frame = cf, Clear = clear, Mountain = mountain, CaveGap = caveGap, Body = body,
				Entry = surface(cf, Plan.EntryProbeZ), Exit = surface(cf, Plan.ExitProbeZ),
				Separation = math.abs(math.atan2(math.sin(angle - mountainAngle), math.cos(angle - mountainAngle))),
			})
		end
	end
	local function pick(separation: number, caveGap: number, strict: boolean): CFrame?
		local best, bestScore = nil, -math.huge
		for _, site in candidates do
			local usable = site.Separation >= separation and site.CaveGap >= caveGap
				and site.Entry >= Plan.EntryGround.Min and site.Entry <= Plan.EntryGround.Max
				and site.Exit >= seaFloor and site.Exit <= Plan.ExitGround.Max
				and site.Mountain < (if strict then 2 else 24)
				and site.Body >= Plan.BodyGroundMin - (if strict then 0 else 5)
				and (site.Clear or not strict)
			if usable then
				-- Longe da caverna primeiro; depois terreno cômodo para a escada.
				local score = site.Separation * 40 + site.CaveGap * 0.04
					- math.abs(site.Entry - 22) - math.abs(site.Exit - 9) * 0.5
					+ (if site.Clear then 60 else 0)
				if score > bestScore then best, bestScore = site.Frame, score end
			end
		end
		return best
	end
	-- 120 graus de separação é "do outro lado"; abaixo disso já avisamos.
	local site = pick(2.1, Plan.CaveClearance, true)
	if site then return site end
	site = pick(2.1, Plan.CaveClearance * 0.75, false)
	if site then
		warn("[Abismo] Nenhum corredor totalmente livre do lado oposto; usando o melhor e limpando sua área.")
		return site
	end
	site = pick(1.4, Plan.CaveClearance * 0.6, false)
	if site then
		warn("[Abismo] Costa oposta inviável nesta seed; a estação ficou a menos de 80 graus da montanha.")
		return site
	end
	error("Abismo: nenhum local livre para a estação. Informe Build(seed, { Frame = ..., EntryGround = ..., ExitGround = ... }).")
end

local function block(parent: Instance, frame: CFrame, name: string,
	x0: number, x1: number, y0: number, y1: number, z0: number, z1: number,
	color: Color3, material: Enum.Material?, shell: boolean?, collide: boolean?): Part
	local low, high = Vector3.new(x0, y0, z0), Vector3.new(x1, y1, z1)
	local p = S.Part(parent, name, high - low, frame * CFrame.new((low + high) / 2),
		material or Enum.Material.Metal, color, { CanCollide = collide ~= false })
	p.CanTouch = false
	if collide == false then p.CanQuery = false end
	p:SetAttribute("AbismoLocalMin", low)
	p:SetAttribute("AbismoLocalMax", high)
	if shell then p:SetAttribute("AbismoShell", true) end
	return p
end

local function carve(frame: CFrame, x0: number, x1: number, y0: number, y1: number, z0: number, z1: number)
	Workspace.Terrain:FillBlock(frame * CFrame.new((x0 + x1) / 2, (y0 + y1) / 2, (z0 + z1) / 2),
		Vector3.new(x1 - x0, y1 - y0, z1 - z0), Enum.Material.Air)
end

local function sign(parent: Instance, cf: CFrame, text: string, width: number, color: Color3)
	local plate = S.Part(parent, "Sinal_" .. text, Vector3.new(width, 1.5, 0.14), cf,
		Enum.Material.SmoothPlastic, COL.Trim, { CanCollide = false })
	plate.CanTouch, plate.CanQuery = false, false
	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 36
	gui.Parent = plate
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamBold
	label.Text = text
	label.TextColor3 = color
	label.TextScaled = true
	label.Parent = gui
end

local function lamp(parent: Instance, frame: CFrame, x: number, y: number, z: number, width: number)
	block(parent, frame, "Luminaria", x - width / 2 - 0.2, x + width / 2 + 0.2, y, y + 0.25, z - 0.5, z + 0.5, COL.Trim, nil, false, false)
	local p = block(parent, frame, "Difusor", x - width / 2, x + width / 2, y - 0.08, y, z - 0.32, z + 0.32, COL.Light, Enum.Material.Neon, false, false)
	local light = Instance.new("PointLight")
	light.Color, light.Brightness, light.Range, light.Shadows = COL.Light, 1.25, 22, false
	light.Parent = p
end

local function wall(parent: Instance, frame: CFrame, axis: string, fixed: number,
	a0: number, a1: number, floorY: number, height: number, openings: any)
	local function panel(lo: number, hi: number, bottom: number)
		if hi <= lo then return end
		local function piece(name: string, f0: number, f1: number, y0: number, y1: number, color: Color3, solid: boolean)
			if axis == "X" then
				block(parent, frame, name, f0, f1, y0, y1, lo, hi, color, nil, solid, solid)
			else
				block(parent, frame, name, lo, hi, y0, y1, f0, f1, color, nil, solid, solid)
			end
		end
		piece("PainelLaboratorio", fixed - 1, fixed + 1, bottom, floorY + height + 0.15, COL.Wall, true)
		if bottom < floorY + 1 then
			for _, side in { -1, 1 } do
				local f = fixed + side * 1.035
				piece("RodapeTecnico", f - 0.025, f + 0.025, floorY + 0.1, floorY + 3.5, COL.Lower, false)
			end
		end
	end
	local cursor = a0
	for _, opening in openings or {} do
		panel(cursor, opening[1], floorY - 0.15)
		panel(opening[1], opening[2], floorY + Plan.DoorHeight)
		cursor = opening[2]
	end
	panel(cursor, a1, floorY - 0.15)
end

local function roomShell(parent: Instance, frame: CFrame, spec: any): Folder
	local f = folder(parent, spec.Name)
	block(f, frame, "PisoContinuo", spec.X0 - 1, spec.X1 + 1, spec.Floor - Plan.Slab, spec.Floor,
		spec.Z0 - 1, spec.Z1 + 1, COL.Floor, Enum.Material.Metal, true)
	block(f, frame, "TetoSelado", spec.X0 - 1, spec.X1 + 1, spec.Floor + spec.Height, spec.Floor + spec.Height + Plan.Slab,
		spec.Z0 - 1, spec.Z1 + 1, COL.Ceiling, nil, true)
	for _, edge in { "XMin", "XMax", "ZMin", "ZMax" } do
		local skip = spec.Skip[edge]
		if skip == true then continue end
		local x = string.sub(edge, 1, 1) == "X"
		local low = string.sub(edge, 2) == "Min"
		local fixed = if x then (if low then spec.X0 else spec.X1) else (if low then spec.Z0 else spec.Z1)
		local a0 = if x then spec.Z0 - 1 else spec.X0 - 1
		local a1 = if x then spec.Z1 + 1 else spec.X1 + 1
		if type(skip) == "number" then
			-- O vizinho mais baixo levanta a parede até `skip`; aqui fechamos
			-- apenas a faixa acima dele, bem acima do vão das portas.
			if x then
				block(f, frame, "PainelLaboratorio", fixed - 1, fixed + 1, spec.Floor + skip, spec.Floor + spec.Height + 0.15, a0, a1, COL.Wall, nil, true)
			else
				block(f, frame, "PainelLaboratorio", a0, a1, spec.Floor + skip, spec.Floor + spec.Height + 0.15, fixed - 1, fixed + 1, COL.Wall, nil, true)
			end
			continue
		end
		wall(f, frame, if x then "X" else "Z", fixed, a0, a1, spec.Floor, spec.Height, spec.Openings[edge])
	end
	return f
end

local function roomFinish(parent: Instance, frame: CFrame, room: any)
	local y = room.Floor
	for x = room.X0 + 6, room.X1 - 2, 6 do
		block(parent, frame, "JuntaPiso", x - 0.025, x + 0.025, y + 0.008, y + 0.018, room.Z0 + 1.1, room.Z1 - 1.1, COL.Steel, nil, false, false)
	end
	for z = room.Z0 + 6, room.Z1 - 2, 6 do
		block(parent, frame, "JuntaPiso", room.X0 + 1.1, room.X1 - 1.1, y + 0.008, y + 0.018, z - 0.025, z + 0.025, COL.Steel, nil, false, false)
	end
	-- Salas largas recebem fileiras de luminárias, não uma só no eixo.
	local width, depth = room.X1 - room.X0, room.Z1 - room.Z0
	local cx, cz = (room.X0 + room.X1) / 2, (room.Z0 + room.Z1) / 2
	local columns = math.max(1, math.round(width / 26))
	for i = 1, columns do
		local x = room.X0 + width * (i - 0.5) / columns
		for z = room.Z0 + 6, room.Z1 - 3, 12 do lamp(parent, frame, x, y + room.Height - 0.35, z, 7) end
	end
	S.Marker(parent, "Zona" .. room.Name, frame * CFrame.new(cx, y + 1, cz), { AbismoZona = room.Name })
	if room.Kind == "Bioteste" then
		Furnishings.TestHall(parent, frame * CFrame.new(cx, y, cz), room)
		S.LootPoint(parent, frame * CFrame.new(cx - width * 0.3, y + 0.4, cz - depth * 0.34))
		S.LootPoint(parent, frame * CFrame.new(cx + width * 0.06, y + 0.4, cz + depth * 0.3))
	elseif room.Kind ~= "Corredor" then
		Furnishings.Room(parent, frame * CFrame.new(cx, y, cz), room)
		S.LootPoint(parent, frame * CFrame.new(cx + width * 0.18, y + 0.4, cz + depth * 0.3))
	else
		for _, x in { -8.4, 8.4 } do
			block(parent, frame, "GuiaSaida", x - 0.08, x + 0.08, y + 0.02, y + 0.04, room.Z0 + 2, room.Z1 - 2, COL.Green, Enum.Material.Neon, false, false)
		end
		sign(parent, frame * CFrame.new(0, y + room.Height - 4.5, room.Z1 - 3), "SAÍDA  ↑  COSTA", 12, COL.Green)
		sign(parent, frame * CFrame.new(0, y + room.Height - 4.5, room.Z0 + 3) * CFrame.Angles(0, math.pi, 0), "↓  RECEPÇÃO / SUPERFÍCIE", 12, COL.Light)
	end
end

local function stairs(parent: Instance, frame: CFrame, spec: any)
	local f = folder(parent, spec.Name)
	for i = 1, spec.Count do
		local z0 = spec.Z0 + (i - 1) * spec.Tread
		local z1 = spec.Z0 + i * spec.Tread
		local y = spec.Y0 + i * spec.Riser
		local previous = y - spec.Riser
		local low, high = math.min(y, previous), math.max(y, previous)
		local step = block(f, frame, "Degrau", spec.X0 - 1, spec.X1 + 1, low - 2.5, y, z0, z1, COL.Floor, Enum.Material.DiamondPlate, true)
		step:SetAttribute("AbismoStep", true)
		step:SetAttribute("AbismoStair", spec.Name)
		step:SetAttribute("AbismoStepIndex", i)
		block(f, frame, "BordaDegrau", spec.X0 + 1.7, spec.X1 - 1.7, y + 0.008, y + 0.018, z0 + 0.04, z0 + 0.18, COL.Amber, nil, false, false)
		for _, x in { spec.X0 - 1, spec.X1 + 1 } do
			block(f, frame, "ParedeEscada", x - 1, x + 1, low - 2.5, high + Plan.StairHeadroom + 2, z0 - 0.03, z1 + 0.03, COL.Wall, nil, true)
		end
		block(f, frame, "TetoEscada", spec.X0 - 2, spec.X1 + 2, high + Plan.StairHeadroom, high + Plan.StairHeadroom + 2, z0 - 0.03, z1 + 0.03, COL.Ceiling, nil, true)
		if i % 12 == 5 then lamp(f, frame, 0, high + Plan.StairHeadroom - 0.3, (z0 + z1) / 2, 6) end
	end
	for _, x in { spec.X0 + 1.5, spec.X1 - 1.5 } do
		S.Beam(f, "Corrimao", frame * Vector3.new(x, spec.Y0 + 3.2, spec.Z0), frame * Vector3.new(x, spec.Y1 + 3.2, spec.Z1), 0.22, Enum.Material.Metal, COL.Steel, false)
	end
	S.Marker(f, "Zona" .. spec.Name, frame * CFrame.new(0, (spec.Y0 + spec.Y1) / 2 + 2, (spec.Z0 + spec.Z1) / 2), { AbismoZona = spec.Name })
end

local function door(parent: Instance, frame: CFrame, spec: any): Part
	local f = folder(parent, "Porta" .. spec.Name)
	local yaw = if spec.Side then (if spec.X > 0 then -math.pi / 2 else math.pi / 2) else (if spec.Exit then math.pi else 0)
	-- Mount on the opening side of the two-stud wall, so the hinge/leaf
	-- clears the jamb throughout DoorSystem's 100-degree swing.
	local cf = frame * CFrame.new(spec.X, spec.Floor + Plan.DoorHeight / 2, spec.Z) * CFrame.Angles(0, yaw, 0) * CFrame.new(0, 0, -1.25)
	local leaf = S.Part(f, "Door" .. spec.Name, Vector3.new(spec.Width - 0.2, Plan.DoorHeight - 0.15, 0.45), cf, Enum.Material.Metal, COL.Lower)
	leaf:SetAttribute("Porta", true)
	leaf:SetAttribute("PortaAberta", false)
	leaf:SetAttribute("CFrameFechada", cf)
	leaf:SetAttribute("LarguraPorta", spec.Width - 0.2)
	if spec.Main then leaf:SetAttribute("AbismoPortaPrincipal", true) end
	if spec.Exit then leaf:SetAttribute("AbismoSaidaMaritima", true) end
	for _, side in { -1, 1 } do
		for _, detail in {
			{ "Visor", Vector3.new(spec.Width * 0.5, 2, 0.12), Vector3.new(0, 1.8, side * 0.29), COL.Light },
			{ "BarraAbertura", Vector3.new(spec.Width * 0.62, 0.22, 0.22), Vector3.new(0, -1.2, side * 0.48), COL.Steel },
		} do
			local p = S.Part(leaf, detail[1], detail[2], cf * CFrame.new(detail[3]), Enum.Material.Metal, detail[4], { CanCollide = false })
			p.Anchored, p.Massless, p.CanTouch, p.CanQuery = false, true, false, false
			local weld = Instance.new("WeldConstraint")
			weld.Part0, weld.Part1, weld.Parent = leaf, p, p
		end
	end
	local title = ({ Entrada = "ABISMO / ACESSO", Saida = "SAÍDA / COSTA", Laboratorio = "01 / LABORATÓRIO",
		Bioteste = "02 / SALÃO DE TESTES", Controle = "03 / CONTROLE", Clinica = "04 / ENFERMARIA",
		Arquivo = "05 / ARQUIVO", Utilidades = "06 / ÁREA TÉCNICA" })[spec.Name] or spec.Name
	for _, side in { -1, 1 } do
		sign(f, cf * CFrame.new(0, 6.1, side * 1.12) * CFrame.Angles(0, if side > 0 then math.pi else 0, 0), title, spec.Width, if spec.Exit then COL.Green else COL.Light)
	end
	return leaf
end

local function landings(parent: Instance, frame: CFrame, plan: any)
	local y = plan.EntryFloor
	local up, down = plan.Stairs[1], plan.Stairs[2]
	local shaft = Plan.StairHalf + 2 -- face externa da caixa da escada
	local cave = folder(parent, "CavernaDeEntrada")
	-- Solid foundation and rock shoulders cover the complete surface excavation.
	block(cave, frame, "BaseCaverna", -26, 26, y - 12, y, Plan.CaveZ0, Plan.EntryDoorZ + 8, COL.Rock, Enum.Material.Slate, true)
	for z = Plan.CaveZ0 + 8, Plan.EntryDoorZ - 4, 4 do
		for _, side in { -1, 1 } do
			local x0, x1 = if side < 0 then -26 else 13, if side < 0 then -13 else 26
			block(cave, frame, "RochaLateral", x0, x1, y - 12, y + 25, z - 0.1, z + 4.1, COL.Rock, Enum.Material.Slate, true)
		end
		block(cave, frame, "AbobadaRocha", -26, 26, y + 16 + math.sin(z) * 0.35, y + 28, z - 0.1, z + 4.1, COL.Rock, Enum.Material.Slate, true)
	end
	-- Faceted boulders break the silhouette, outside the walkable entrance.
	for _, side in { -1, 1 } do
		for i = 1, 4 do
			S.Part(cave, "RochaNatural", Vector3.new(10, 14 + i, 11), frame * CFrame.new(side * (20 + i), y + 3, Plan.CaveZ0 + 8 + i * 9) * CFrame.Angles(0.13 * i, 0.22 * side * i, 0.15 * side), Enum.Material.Slate, COL.Rock)
		end
	end
	wall(cave, frame, "Z", Plan.EntryDoorZ, -13, 13, y, 16, { { -6, 6 } })
	local entry = { Name = "Vestibulo", X0 = -10, X1 = 10, Z0 = Plan.EntryDoorZ, Z1 = up.Z0, Floor = y, Height = 14,
		Skip = { ZMin = true }, Openings = { ZMax = { { -Plan.StairHalf, Plan.StairHalf } } } }
	roomShell(parent, frame, entry)
	lamp(cave, frame, 0, y + 13.2, Plan.EntryDoorZ + 4, 5)
	S.Marker(cave, "EntradaFloresta", frame * CFrame.new(0, y + 1, Plan.CaveZ0 + 12), { AbismoZona = "Caverna", EntradaAbismo = true })
	-- Upper stairwell protrudes near the entrance: wrap its outside in rock.
	for z = up.Z0, up.Z1 - 4, 4 do
		local level = up.Y0 + (up.Y1 - up.Y0) * (z - up.Z0) / (up.Z1 - up.Z0)
		block(cave, frame, "CoberturaRochosa", -26, 26, level + Plan.StairHeadroom + 2.1, level + 32, z - 0.05, z + 4.05, COL.Rock, Enum.Material.Slate, true)
		for _, side in { -1, 1 } do
			block(cave, frame, "EncostaRochosa", if side < 0 then -26 else shaft + 0.1, if side < 0 then -shaft - 0.1 else 26, level - 12, level + 32, z - 0.05, z + 4.05, COL.Rock, Enum.Material.Slate, true)
		end
	end
	local ey = plan.ExitFloor
	local exit = { Name = "SaidaSeca", X0 = -10, X1 = 10, Z0 = down.Z1, Z1 = Plan.ExitDoorZ, Floor = ey, Height = 14,
		Skip = { ZMax = true }, Openings = { ZMin = { { -Plan.StairHalf, Plan.StairHalf } }, ZMax = { { -6, 6 } } } }
	local out = roomShell(parent, frame, exit)
	block(out, frame, "PatioSaida", -26, 26, ey - 12, ey, Plan.ExitDoorZ, Plan.PatioZ1, COL.Floor, Enum.Material.Concrete, true)
	-- Enclose the excavated upper escape stair; no open trench at the beach.
	for z = down.Z0, Plan.ExitDoorZ - 4, 4 do
		local level = if z >= down.Z1 then ey else down.Y0 + (down.Y1 - down.Y0) * (z + 4 - down.Z0) / (down.Z1 - down.Z0)
		for _, side in { -1, 1 } do
			block(out, frame, "AlaSaida", if side < 0 then -26 else shaft + 0.1, if side < 0 then -shaft - 0.1 else 26, level - 12, level + 32, z, z + 4.05, COL.Rock, Enum.Material.Slate, true)
		end
		block(out, frame, "CoberturaSaida", -26, 26, level + Plan.StairHeadroom + 2.1, level + 32, z, z + 4.05, COL.Rock, Enum.Material.Slate, true)
	end
	wall(out, frame, "Z", Plan.ExitDoorZ, -26, 26, ey, 26, { { -6, 6 } })
	lamp(out, frame, 0, ey + 13.2, Plan.ExitDoorZ - 4, 5)
	S.Marker(out, "SaidaCosta", frame * CFrame.new(0, ey + 1, Plan.PatioZ1 - 6), { AbismoZona = "Costa", AbismoSaidaMaritima = true, SaidaSeca = true })
end

local function excavate(frame: CFrame, plan: any, legacyFrame: CFrame?)
	if legacyFrame then
		-- Seal the old vertical shaft before carving the new diagonal access.
		local p = legacyFrame.Position
		local top = Layout.Height(p.X, p.Z)
		Workspace.Terrain:FillBlock(legacyFrame * CFrame.new(0, (-4 + top) / 2, 0), Vector3.new(24, top + 4, 24), Enum.Material.Rock)
	end
	local margin = Plan.TerrainMargin
	for _, room in plan.Rooms do
		carve(frame, room.X0 - 1 - margin, room.X1 + 1 + margin, room.Floor - Plan.Slab - margin,
			room.Floor + room.Height + Plan.Slab + Plan.CeilingMargin, room.Z0 - 1 - margin, room.Z1 + 1 + margin)
	end
	for _, stair in plan.Stairs do
		for i = 1, stair.Count do
			local y, prev = stair.Y0 + i * stair.Riser, stair.Y0 + (i - 1) * stair.Riser
			carve(frame, stair.X0 - 2 - margin, stair.X1 + 2 + margin, math.min(y, prev) - 2.5 - margin,
				math.max(y, prev) + Plan.StairHeadroom + 2 + margin,
				stair.Z0 + (i - 1) * stair.Tread - margin, stair.Z0 + i * stair.Tread + margin)
		end
	end
	carve(frame, -20, 20, plan.EntryFloor - 10, plan.EntryFloor + 26, Plan.CaveZ0 + 4, plan.Stairs[1].Z0 + 8)
	carve(frame, -20, 20, plan.ExitFloor - 10, plan.ExitFloor + 26, plan.Stairs[2].Z1 - 8, Plan.PatioZ1 - 4)
end

local function hideIntrudingVegetation(ilha: Instance, frame: CFrame, plan: any)
	local bounds = {
		{ -30, 30, Plan.Floor - 14, plan.EntryFloor + 34, Plan.CaveZ0 - 4, plan.Stairs[1].Z1 },
		{ -30, 30, Plan.Floor - 14, plan.ExitFloor + 34, plan.Stairs[2].Z0, Plan.PatioZ1 + 4 },
	}
	for _, room in plan.Rooms do
		table.insert(bounds, { room.X0 - 2, room.X1 + 2, room.Floor - 2, room.Floor + room.Height + 2, room.Z0 - 2, room.Z1 + 2 })
	end
	local backup = ServerStorage:FindFirstChild("AbismoVegetacaoPreservada")
	for _, name in { "Floresta", "Vegetacao", "Rochas" } do
		local source = ilha:FindFirstChild(name)
		if not source then continue end
		for _, item in source:GetChildren() do
			local cf: CFrame?
			local size: Vector3?
			if item:IsA("Model") then cf, size = item:GetBoundingBox()
			elseif item:IsA("BasePart") then cf, size = item.CFrame, item.Size end
			if not cf or not size then continue end
			local low, high = Vector3.new(math.huge, math.huge, math.huge), Vector3.new(-math.huge, -math.huge, -math.huge)
			for _, x in { -1, 1 } do for _, y in { -1, 1 } do for _, z in { -1, 1 } do
				local p = frame:PointToObjectSpace(cf * Vector3.new(size.X * x / 2, size.Y * y / 2, size.Z * z / 2))
				low = Vector3.new(math.min(low.X, p.X), math.min(low.Y, p.Y), math.min(low.Z, p.Z))
				high = Vector3.new(math.max(high.X, p.X), math.max(high.Y, p.Y), math.max(high.Z, p.Z))
			end end end
			for _, b in bounds do
				if high.X >= b[1] and low.X <= b[2] and high.Y >= b[3] and low.Y <= b[4] and high.Z >= b[5] and low.Z <= b[6] then
					if not backup then backup = folder(ServerStorage, "AbismoVegetacaoPreservada") end
					item:SetAttribute("AbismoPastaOriginal", name)
					item.Parent = backup
					break
				end
			end
		end
	end
end

function Generator.Clear()
	local ilha = Workspace:FindFirstChild("Ilha")
	local station = ilha and ilha:FindFirstChild("EstacaoAbismo")
	if station then station:Destroy() end
	-- Terrain excavation is permanent; regenerate the island to undo it.
end

function Generator.Build(seed: number?, options: any?): Model
	options = options or {}
	Layout.Plan(seed)
	local ilha = Workspace:FindFirstChild("Ilha")
	local existing = ilha and ilha:FindFirstChild("EstacaoAbismo")
	local savedFrame, savedEntry, savedExit, legacyFrame = previousSite(existing)
	local frame = options.Frame or savedFrame or findSite()
	assert(typeof(frame) == "CFrame" and math.abs(frame.Position.Y) < 0.001 and frame.UpVector.Y > 0.9999,
		"Abismo: Frame deve ser horizontal, com origem Y=0")
	if options.Frame then savedEntry, savedExit = nil, nil end
	local entry = options.EntryGround or savedEntry or surface(frame, Plan.EntryProbeZ)
	local exit = options.ExitGround or savedExit or surface(frame, Plan.ExitProbeZ)
	local plan = Plan.Create(entry, exit) -- validate BEFORE deleting or excavating
	local model = Instance.new("Model")
	model.Name = "EstacaoAbismo"
	model:SetAttribute("EstacaoAbismo", true)
	model:SetAttribute("Construcao", "Abismo")
	model:SetAttribute("AbismoVersion", Plan.Version)
	model:SetAttribute("AbismoFrame", frame)
	model:SetAttribute("AbismoEntryGround", entry)
	model:SetAttribute("AbismoExitGround", exit)
	for _, room in plan.Rooms do
		local f = roomShell(model, frame, room)
		roomFinish(f, frame, room)
	end
	for _, stair in plan.Stairs do stairs(model, frame, stair) end
	landings(model, frame, plan)
	for _, spec in plan.Doors do
		local leaf = door(model, frame, spec)
		if spec.Main then model.PrimaryPart = leaf end
	end
	if options.Terrain ~= false then excavate(frame, plan, legacyFrame) end
	if not ilha then ilha = folder(Workspace, "Ilha") end
	hideIntrudingVegetation(ilha, frame, plan)
	if existing then existing:Destroy() end
	-- DoorSystem sees complete door attributes on DescendantAdded.
	model.Parent = ilha
	if RunService:IsRunning() then warn("[Abismo] Gerado durante Play: gere em modo de edição e salve para manter a estação.") end
	print(string.format("[Abismo] Laboratório completo: caverna, %d degraus em dois lances, salão de testes com o Frog Generator, %d portas e saída seca.",
		plan.Stairs[1].Count + plan.Stairs[2].Count, #plan.Doors))
	return model
end

return Generator
