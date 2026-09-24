--!nocheck
-- `sources` vem de run_houses.py: HouseKit, Furniture, CampCabin e
-- CasaDoCaseiro são os módulos REAIS. Prova que as casas montam e que a
-- geometria funciona pra jogar: portas giram sem bater em nada, gavetas
-- abrem sem entrar em parede/móvel e ficam escondidas quando fechadas,
-- móveis não atravessam paredes nem uns aos outros, e tudo cabe no
-- Footprint que o HouseGenerator usa. Física/render continuam no Studio.

local stub = loadstring(sources.RobloxStub, "RobloxStub")()
local Workspace = stub.Workspace

Random = { new = function(seed)
	local state = (seed or 123) % 2147483646 + 1
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

-- Color3 com Lerp (o stub compartilhado devolve tabela crua).
local Color3M = {}
Color3M.__index = Color3M
function Color3M.Lerp(a, b, t)
	return Color3.new(a.R + (b.R - a.R) * t, a.G + (b.G - a.G) * t, a.B + (b.B - a.B) * t)
end
function Color3.new(r, g, b) return setmetatable({ R = r or 0, G = g or 0, B = b or 0 }, Color3M) end
function Color3.fromRGB(r, g, b) return Color3.new(r / 255, g / 255, b / 255) end

local v3Methods = getmetatable(Vector3.new())
function v3Methods.Lerp(a, b, t) return a + (b - a) * t end
local cfMethods = getmetatable(CFrame.identity)
function cfMethods:VectorToObjectSpace(v)
	return Vector3.new(v:Dot(self.RightVector), v:Dot(self.UpVector), v:Dot(-self.LookVector))
end
function cfMethods:PointToObjectSpace(p) return self:VectorToObjectSpace(p - self.Position) end
function cfMethods:Inverse()
	local r = self.R
	local position = self:VectorToObjectSpace(-self.Position)
	return CFrame.fromMatrix(position, Vector3.new(r[1], r[2], r[3]), Vector3.new(r[4], r[5], r[6]), Vector3.new(r[7], r[8], r[9]))
end
function cfMethods:ToObjectSpace(other) return self:Inverse() * other end

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
}, { __index = getfenv() })
game:GetService("ReplicatedStorage").Modules = { AssetRegistry = tokens.AssetRegistry, AssetLoader = tokens.AssetLoader }

local checks = 0
local failures, seen = {}, {}
local function check(condition, message, ...)
	checks += 1
	if not condition then
		local text = string.format(message, ...)
		if not seen[text] then
			seen[text] = true
			table.insert(failures, text)
		end
	end
end

--------------------------------------------------------------------------------
-- Geometria: caixas orientadas (SAT)
--------------------------------------------------------------------------------

local function obb(cf, size, shrink)
	local s = shrink or 0
	return {
		C = cf.Position,
		A = { cf.RightVector, cf.UpVector, -cf.LookVector },
		E = { math.max(size.X / 2 - s, 0.001), math.max(size.Y / 2 - s, 0.001), math.max(size.Z / 2 - s, 0.001) },
	}
end

local function intersects(a, b)
	local axes = {}
	for i = 1, 3 do
		table.insert(axes, a.A[i])
		table.insert(axes, b.A[i])
	end
	for i = 1, 3 do
		for j = 1, 3 do
			local c = a.A[i]:Cross(b.A[j])
			if c.Magnitude > 1e-6 then table.insert(axes, c.Unit) end
		end
	end
	local d = b.C - a.C
	for _, ax in axes do
		local ra, rb = 0, 0
		for i = 1, 3 do
			ra += a.E[i] * math.abs(a.A[i]:Dot(ax))
			rb += b.E[i] * math.abs(b.A[i]:Dot(ax))
		end
		if math.abs(d:Dot(ax)) > ra + rb then return false end
	end
	return true
end

local function corners(box)
	local out = {}
	for _, sx in { -1, 1 } do
		for _, sy in { -1, 1 } do
			for _, sz in { -1, 1 } do
				table.insert(out, box.C + box.A[1] * (sx * box.E[1]) + box.A[2] * (sy * box.E[2]) + box.A[3] * (sz * box.E[3]))
			end
		end
	end
	return out
end

local function insideBox(p, box, tol)
	local d = p - box.C
	for i = 1, 3 do
		if math.abs(d:Dot(box.A[i])) > box.E[i] + tol then return false end
	end
	return true
end

local function isA(part, class) return part:IsA(class) end

-- O stub não tem IsDescendantOf.
local function under(node, root)
	local cur = node.Parent
	while cur do
		if cur == root then return true end
		cur = cur.Parent
	end
	return false
end

local function parts(root)
	local out = {}
	for _, d in root:GetDescendants() do
		if isA(d, "BasePart") then table.insert(out, d) end
	end
	return out
end

local function topChild(part, folder)
	local node = part
	while node and node.Parent ~= folder do node = node.Parent end
	return node
end

local function describe(part)
	local names = {}
	local node = part
	for _ = 1, 4 do
		if not node or node.ClassName == "Workspace" then break end
		table.insert(names, 1, node.Name)
		node = node.Parent
	end
	return table.concat(names, ".")
end

--------------------------------------------------------------------------------
-- Casa
--------------------------------------------------------------------------------

local function doorTarget(leaf, angleFrac)
	local closed = leaf:GetAttribute("CFrameFechada")
	local width = leaf:GetAttribute("LarguraPorta")
	local side = if leaf:GetAttribute("DobradicaDireita") == true then 1 else -1
	local hinge = closed * CFrame.new(side * width / 2, 0, 0)
	return hinge * CFrame.Angles(0, -side * math.rad(100) * angleFrac, 0) * CFrame.new(-side * width / 2, 0, 0)
end

local function inspectHouse(Style, houseCF, label)
	local folder = Instance.new("Folder")
	folder.Name = "Casas"
	folder.Parent = Workspace
	local model = Style.Build(folder, houseCF, { Name = label, Seed = 7 })
	check(model and model.Parent == folder, "%s: Build deve devolver o Model", label)
	check(model:GetAttribute("CasaGerada") == true and model:GetAttribute("Construcao") == Style.Style, "%s: atributos do Model", label)
	local all = parts(model)
	check(#all > 300, "%s: casa com poucas peças (%d)", label, #all)

	local estrutura = model:FindFirstChild("Estrutura")
	local moveis = model:FindFirstChild("Moveis")
	local portas = model:FindFirstChild("Portas")
	local externo = model:FindFirstChild("Externo")
	check(estrutura and moveis and portas and externo, "%s: pastas da casa", label)

	-- Piso acabado em y = 0 local.
	local floor = model.PrimaryPart
	check(floor and floor.Name == "Piso", "%s: PrimaryPart = Piso", label)
	local floorTop = houseCF:PointToObjectSpace(floor.CFrame.Position).Y + floor.Size.Y / 2
	check(math.abs(floorTop) < 1e-3, "%s: topo do piso em %.3f, esperado 0", label, floorTop)

	-- Colisores por grupo.
	local solids = {}
	for _, p in all do
		if p.CanCollide ~= false then table.insert(solids, p) end
	end

	-- Footprint: nada colide fora da área reservada.
	local fp = Style.Footprint
	for _, p in all do
		if p.Name == "SpawnPOI" then continue end
		for _, c in corners(obb(p.CFrame, p.Size)) do
			local l = houseCF:PointToObjectSpace(c)
			check(l.X >= fp.MinX - 0.05 and l.X <= fp.MaxX + 0.05 and l.Z >= fp.MinZ - 0.05 and l.Z <= fp.MaxZ + 0.05,
				"%s: %s sai do Footprint em (%.2f, %.2f)", label, describe(p), l.X, l.Z)
		end
	end

	-- Móvel não atravessa parede/estrutura nem outro móvel.
	local furnitureSolids = {}
	for _, p in solids do
		if under(p, moveis) then table.insert(furnitureSolids, p) end
	end
	local structureSolids = {}
	for _, p in solids do
		if under(p, estrutura) and p.Name ~= "Piso" and p.Name ~= "PisoAla" and p.Name ~= "Revestimento" then table.insert(structureSolids, p) end
	end
	for _, f in furnitureSolids do
		local fb = obb(f.CFrame, f.Size, 0.04)
		for _, s in structureSolids do
			check(not intersects(fb, obb(s.CFrame, s.Size, 0.04)), "%s: móvel %s atravessa %s", label, describe(f), describe(s))
		end
	end
	for i = 1, #furnitureSolids do
		local a = furnitureSolids[i]
		local ga = topChild(a, moveis)
		local ab = obb(a.CFrame, a.Size, 0.04)
		for j = i + 1, #furnitureSolids do
			local b = furnitureSolids[j]
			if topChild(b, moveis) ~= ga then
				check(not intersects(ab, obb(b.CFrame, b.Size, 0.04)), "%s: %s encosta dentro de %s", label, describe(a), describe(b))
			end
		end
	end

	-- Janelas: vidro dentro do vão (não atravessa parede).
	local janelas = model:FindFirstChild("Janelas")
	local walls = {}
	for _, p in parts(estrutura) do
		if p.Name == "Parede" then table.insert(walls, p) end
	end
	for _, p in parts(janelas) do
		if p.CanCollide ~= false then
			local box = obb(p.CFrame, p.Size, 0.03)
			for _, w in walls do
				check(not intersects(box, obb(w.CFrame, w.Size, 0.03)), "%s: %s atravessa a parede %s (vidro em %s, parede em %s tam %s)", label, describe(p), describe(w), tostring(houseCF:PointToObjectSpace(p.Position)), tostring(houseCF:PointToObjectSpace(w.Position)), tostring(w.Size))
			end
		end
	end

	-- Telhado nunca desce pra dentro de um cômodo (rincão da ala, beirais).
	-- Cada piso vai até o forro/piso de cima mais baixo que fica sobre ele;
	-- piso sem nada em cima (palheiro aberto pro telhado) não conta.
	local function localBox(p)
		local c = houseCF:PointToObjectSpace(p.CFrame.Position)
		local e = stub.PartExtents({ CFrame = houseCF:Inverse() * p.CFrame, Size = p.Size }) / 2
		return c, e
	end
	local rooms = {}
	local sawCeiling = false
	for _, fl in parts(estrutura) do
		if string.sub(fl.Name, 1, 4) == "Piso" then
			local fc, fe = localBox(fl)
			local floorTop = fc.Y + fe.Y
			local ceiling = math.huge
			for _, c in parts(estrutura) do
				if c.Name == "Forro" or c.Name == "PisoSuperior" then
					local cc, ce = localBox(c)
					local bottom = cc.Y - ce.Y
					if bottom > floorTop + 3 and math.abs(cc.X - fc.X) < fe.X and math.abs(cc.Z - fc.Z) < fe.Z then
						ceiling = math.min(ceiling, bottom)
					end
				end
			end
			if ceiling < math.huge then
				sawCeiling = true
				local h = ceiling - floorTop - 0.2
				table.insert(rooms, obb(houseCF * CFrame.new(fc.X, floorTop + 0.05 + h / 2, fc.Z), Vector3.new(fe.X * 2 - 1.2, h, fe.Z * 2 - 1.2)))
			end
		end
	end
	check(sawCeiling, "%s: nenhum cômodo com forro", label)
	for _, p in all do
		if p.Name == "Telhado" or p.Name == "Testeira" or p.Name == "Empena" or p.Name == "Cumeeira" then
			local box = obb(p.CFrame, p.Size, 0.02)
			for _, room in rooms do
				check(not intersects(box, room), "%s: %s entra dentro de um cômodo", label, describe(p))
			end
		end
	end

	-- Passagens sem porta (VaoTopo marca o topo de cada uma) livres pra andar.
	for _, top in parts(estrutura) do
		if top.Name == "VaoTopo" then
			local h = houseCF:PointToObjectSpace(top.CFrame.Position).Y
			local passage = obb(top.CFrame * CFrame.new(0, -h / 2 + 0.2, 0), Vector3.new(top.Size.X - 0.8, h - 1.2, 3.4))
			for _, s in solids do
				if s.Name ~= "Parede" then
					check(not intersects(passage, obb(s.CFrame, s.Size, 0.02)), "%s: passagem sem porta bloqueada por %s", label, describe(s))
				end
			end
		end
	end

	-- Portas: atributos, giro de 0..100° sem bater em nada, vão livre dos dois lados.
	local doors = {}
	for _, p in all do
		if p:GetAttribute("Porta") == true then table.insert(doors, p) end
	end
	check(#doors >= 4, "%s: esperado >= 4 portas funcionais, achei %d", label, #doors)
	for _, leaf in doors do
		check(leaf:GetAttribute("CFrameFechada") ~= nil and math.abs(leaf:GetAttribute("LarguraPorta") - leaf.Size.X) < 1e-6, "%s: atributos da porta %s", label, describe(leaf))
		local own = topChild(leaf, portas)
		for step = 1, 20 do
			local cf = doorTarget(leaf, step / 20)
			local box = obb(cf, leaf.Size, 0.1)
			for _, s in solids do
				if s ~= leaf and not under(s, own) then
					check(not intersects(box, obb(s.CFrame, s.Size, 0.02)), "%s: %s bate em %s aos %d graus", label, describe(leaf), describe(s), step * 5)
				end
			end
		end
		local closed = leaf:GetAttribute("CFrameFechada")
		for _, side in { -1, 1 } do
			local clear = obb(closed * CFrame.new(0, 0.4, side * 1.5), Vector3.new(leaf.Size.X - 0.6, leaf.Size.Y - 1.4, 1.6))
			for _, s in solids do
				if s ~= leaf and not under(s, own) then
					check(not intersects(clear, obb(s.CFrame, s.Size, 0.02)), "%s: passagem da %s bloqueada por %s", label, describe(leaf), describe(s))
				end
			end
		end
	end

	-- Gavetas.
	local drawers = {}
	for _, p in all do
		if p:GetAttribute("Gaveta") == true then table.insert(drawers, p) end
	end
	local minDrawers = if label == "Celeiro" then 8 else 18
	check(#drawers >= minDrawers, "%s: poucas gavetas (%d)", label, #drawers)
	local longOnes = 0
	for _, front in drawers do
		local closed = front:GetAttribute("CFrameFechada")
		local travel = front:GetAttribute("GavetaCurso")
		local interior = front:GetAttribute("GavetaInterior")
		local slot = front:GetAttribute("GavetaSlot")
		check(closed and travel and interior and slot and type(front:GetAttribute("GavetaMovel")) == "string", "%s: atributos da gaveta %s", label, describe(front))
		check(interior.X > 1 and interior.Y > 0.3 and interior.Z > 0.6, "%s: gaveta apertada demais %s", label, describe(front))
		if interior.X >= 4.3 and interior.Y >= 0.5 then longOnes += 1 end

		local drawerModel = front.Parent
		local furniture = topChild(front, moveis) or topChild(front, externo)
		-- Peças da bandeja soldadas na frente.
		local welded = 0
		for _, d in drawerModel:GetDescendants() do
			if d.ClassName == "WeldConstraint" then
				check(d.Part0 == front, "%s: solda de gaveta fora da frente", label)
				welded += 1
			end
		end
		check(welded >= 5, "%s: bandeja da gaveta sem solda (%d)", label, welded)

		-- Fechada: bandeja escondida dentro do corpo do móvel.
		local bodies = {}
		for _, p in parts(furniture) do
			if p.Name == "Corpo" then table.insert(bodies, obb(p.CFrame, p.Size)) end
		end
		for _, piece in parts(drawerModel) do
			if piece.Name == "Fundo" or piece.Name == "Traseira" or piece.Name == "Lateral" then
				for _, c in corners(obb(piece.CFrame, piece.Size)) do
					local ok = false
					for _, b in bodies do
						if insideBox(c, b, 0.02) then ok = true break end
					end
					check(ok, "%s: %s aparece fora do móvel com a gaveta fechada", label, describe(piece))
				end
			end
		end

		-- Aberta: frente + espaço útil não entram em nada fora do próprio móvel.
		local openCF = closed * CFrame.new(0, 0, -travel)
		local slotCF = openCF * slot
		local usable = obb(slotCF * CFrame.new(0, interior.Y / 2, 0), interior, 0.02)
		local frontBox = obb(openCF, front.Size, 0.02)
		for _, s in solids do
			if not under(s, furniture) then
				local sb = obb(s.CFrame, s.Size, 0.02)
				check(not intersects(frontBox, sb) and not intersects(usable, sb), "%s: gaveta de %s abre dentro de %s", label, describe(front), describe(s))
			end
		end
		-- O espaço útil fica todo fora do corpo (item à vista com a gaveta aberta).
		for _, b in bodies do
			local shrunk = { C = b.C, A = b.A, E = { b.E[1] - 0.05, b.E[2] - 0.05, b.E[3] - 0.05 } }
			check(not intersects(usable, shrunk), "%s: espaço útil da gaveta %s continua dentro do móvel", label, describe(front))
		end
	end
	check(longOnes >= 2, "%s: precisa de gaveta pro Pé de cabra (4,2 studs), achei %d", label, longOnes)

	-- Marcadores: SpawnPOI fora da casa e caixas de loot com espaço livre.
	local spawns, loots = 0, 0
	for _, p in all do
		if p:GetAttribute("SpawnPOI") == true then
			spawns += 1
			local l = houseCF:PointToObjectSpace(p.Position)
			check(l.Z < fp.MinZ, "%s: SpawnPOI deveria ficar na frente da escada", label)
		elseif p:GetAttribute("PontoLoot") == true then
			loots += 1
			-- LootCrateSystem: caixa 3x2,4x3 com desvio de até 1,2 em volta do ponto.
			local area = obb(p.CFrame * CFrame.new(0, -1.5 + 1.25, 0), Vector3.new(5.4, 2.3, 5.4))
			for _, s in solids do
				if s.Name ~= "Piso" and s.Name ~= "PisoAla" and s.Name ~= "Revestimento" then
					check(not intersects(area, obb(s.CFrame, s.Size, 0.02)), "%s: caixa do PontoLoot bateria em %s", label, describe(s))
				end
			end
		end
	end
	check(spawns == 1 and loots >= 2, "%s: marcadores (%d spawn, %d loot)", label, spawns, loots)

	-- Escadas externas: todo degrau abaixo do piso e acima do chão.
	for _, p in all do
		if p.Name == "Degrau" then
			local top = houseCF:PointToObjectSpace(p.CFrame.Position).Y + p.Size.Y / 2
			check(top < 0 and top > -Style.Found - 0.01, "%s: degrau fora da faixa (%.2f)", label, top)
		end
	end
	-- Escadas internas: espelho <= 0,6 (Humanoid sobe andando) e cabeça livre
	-- (5,6 studs acima de cada degrau sem laje/viga no caminho).
	local steps = {}
	for _, p in all do
		if p.Name == "DegrauInterno" then table.insert(steps, p) end
	end
	table.sort(steps, function(a, b) return a.CFrame.Position.Y + a.Size.Y / 2 < b.CFrame.Position.Y + b.Size.Y / 2 end)
	for i, p in steps do
		local top = p.CFrame.Position.Y + p.Size.Y / 2
		if i > 1 then
			local prev = steps[i - 1]
			local rise = top - (prev.CFrame.Position.Y + prev.Size.Y / 2)
			check(rise > 0 and rise <= 0.61, "%s: degrau interno com espelho %.2f", label, rise)
		end
		local head = obb(p.CFrame * CFrame.new(0, p.Size.Y / 2 + 0.1 + 2.8, 0), Vector3.new(p.Size.X - 0.8, 5.6, p.Size.Z - 0.2))
		for _, s in solids do
			if s.Name ~= "DegrauInterno" and s.Name ~= "CorrimaoEscada" then
				check(not intersects(head, obb(s.CFrame, s.Size, 0.02)), "%s: sem altura na escada (degrau a %.1f bate em %s)", label, top, describe(s))
			end
		end
	end

	print(string.format("[houses] %s ok: %d peças, %d portas, %d gavetas (%d longas)", label, #all, #doors, #drawers, longOnes))
	folder:Destroy()
	return model
end

loadModule("Structures")
local CampCabin = loadModule("CampCabin")
local CasaDoCaseiro = loadModule("CasaDoCaseiro")

local Celeiro = loadModule("Celeiro")
local styles = { { CampCabin, "CampCabin" }, { CasaDoCaseiro, "CasaDoCaseiro" }, { Celeiro, "Celeiro" } }
if sources.CasaDaFazenda then
	table.insert(styles, { loadModule("CasaDaFazenda"), "CasaDaFazenda" })
end
for _, frame in { CFrame.new(0, 0, 0), CFrame.new(120, 31.5, -64) * CFrame.Angles(0, 0.73, 0) } do
	for _, st in styles do
		inspectHouse(st[1], frame, st[2])
	end
end

--------------------------------------------------------------------------------
-- Modelos de referência ("Modelos para as casas"): cama e luminária assentam
-- pela caixa real, mantendo a orientação de pé do modelo original.
--------------------------------------------------------------------------------

local function referenceModel(name, size, cf)
	local m = Instance.new("Model")
	m.Name = name
	local p = Instance.new("Part")
	p.Size = size
	p.CFrame = cf
	p.Parent = m
	local pivot = cf * CFrame.new(0, 1.3, 0.7) -- pivot "torto" de propósito, como os do Toolbox
	m.GetPivot = function(self) return rawget(self, "_pivot") or pivot end
	m.PivotTo = function(self, target)
		local delta = target * self:GetPivot():Inverse()
		for _, d in self:GetDescendants() do
			if d:IsA("BasePart") then d.CFrame = delta * d.CFrame end
		end
		rawset(self, "_pivot", target)
	end
	return m
end

local refs = Instance.new("Folder")
refs.Name = "Modelos para as casas"
refs.Parent = Workspace
referenceModel("Bed horror game", Vector3.new(6.76, 3.73, 10), CFrame.new(179, 26.9, 1393) * CFrame.Angles(0, math.pi, 0)).Parent = refs
referenceModel("ceiling ligh", Vector3.new(4.9, 3.5, 5.2), CFrame.new(184, 22.3, 1379)).Parent = refs

local Kit = loadModule("HouseKit")
local Furniture = loadModule("Furniture")
local frame = CFrame.new(40, 12, 8) * CFrame.Angles(0, 0.4, 0)
local holder = Instance.new("Folder")
holder.Parent = Workspace
local bed = Furniture.Bed(holder, frame, Vector3.new(3, 0, 5), math.pi / 2, Color3.new(1, 0, 0))
check(bed.Name == "Cama", "cama de referência deveria ser usada")
local lo, hi = Kit.WorldBounds(bed)
local target = frame * CFrame.new(3, 0, 5)
check(math.abs(lo.Y - target.Position.Y) < 1e-4, "cama de referência deveria encostar no piso (base %.3f, piso %.3f)", lo.Y, target.Position.Y)
check(math.abs((lo.X + hi.X) / 2 - target.Position.X) < 1e-4 and math.abs((lo.Z + hi.Z) / 2 - target.Position.Z) < 1e-4, "cama de referência fora do centro pedido")
local bedPart = bed:GetChildren()[1]
check(math.abs(bedPart.CFrame.UpVector.Y - 1) < 1e-6, "cama de referência deveria continuar de pé")
Kit.CeilingLight(holder, frame, Vector3.new(0, 11, 0), true, 0.5)
local lamp = holder:FindFirstChild("Luminaria")
local llo, lhi = Kit.WorldBounds(lamp)
check(math.abs(lhi.Y - (frame * CFrame.new(0, 11, 0)).Position.Y) < 1e-4, "luminária de referência deveria encostar no forro")

if #failures > 0 then
	for i = 1, math.min(#failures, 60) do print("FAIL: " .. failures[i]) end
	error(string.format("%d falha(s) em %d verificações", #failures, checks), 0)
end
print(string.format("PASS: casas grandes; %d verificações de geometria", checks))
