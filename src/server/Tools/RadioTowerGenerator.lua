--!strict
--[[
	RadioTowerGenerator (ferramenta de editor)
	Monta a ESTAÇÃO DE RÁDIO inteira: torre de transmissão, abrigo técnico,
	gerador externo, tanque/galões de combustível, caixa de fusíveis, bateria
	reserva, cabeamento, cerca com placas de perigo, holofotes, baliza
	vermelha no topo e a estrada de manutenção chegando no portão.

	Antes isto gerava só uma caixa com um mastro. Agora gera o sítio todo,
	com os pontos de interação que server/RadioSiteSystem.lua usa pra rodar a
	corrente do objetivo (ver docs/Radio.md):

		peças -> combustível -> fusível -> ligar gerador -> painel -> socorro

	USO (Command Bar do Studio, em MODO DE EDIÇÃO, e salve depois):
		local Radio = require(game.ServerScriptService.Server.Tools.RadioTowerGenerator)
		Radio.Build()     -- guarda backup e refaz Workspace.Ilha.TorreDeRadio

	ASSETS (InsertService, só funciona em modo de edição -- em runtime cai no
	fallback em Parts, que é completo e não depende de nada):
		Torre    8788183000
		Gerador 10685426940

	CONTRATO com os sistemas de runtime (tudo por Attribute, nada por nome
	frágil; RadioSiteSystem cria os ProximityPrompts a partir daqui):

	  Model "TorreDeRadio"      EstacaoRadio = true
	  InteracaoRadio (string)   "Abastecer" | "Partida" | "Fusivel"
	                            | "PegarFusivel" | "Painel" | "Socorro"
	  GalaoCombustivel = true   galão; "Cheio" diz se ainda tem combustível
	  MotorGerador = true       corpo do gerador (som + fumaça saem daqui)
	  EscapeGerador = true      ponta do escapamento
	  BalizaRadio = true        luz vermelha do topo (pisca sempre; mais rápido com o gerador ligado)
	  LuzRadio = true           QUALQUER luz que só acende com o GERADOR
	                            ligado (holofotes do pátio, luminárias do
	                            abrigo, mostrador, voltímetro) --
	                            RadioSiteSystem liga todas juntas, sem
	                            distinguir qual é qual
	  Sabotavel = true          gerador e painel (SabotageSystem do Espião)
	  PontoLoot = true          loot do abrigo (ItemSpawner)

	  "ConsoleInstalacao" + ProximityPrompt "InstalarPeca" continuam existindo
	  com o mesmo nome porque RadioInstallSystem.lua procura por eles.
]]

local Workspace = game:GetService("Workspace")
local InsertService = game:GetService("InsertService")
local RunService = game:GetService("RunService")
local Terrain = Workspace.Terrain

local S = require(script.Parent.Structures)
local Layout = require(script.Parent.IslandLayout)

local RadioTowerGenerator = {}

-- Detalhes visuais nao devem esconder os prompts do proprio equipamento.
-- Paredes, portas, piso e vidro solido continuam consultaveis e colidiveis.
local function part(parent: Instance, name: string, size: Vector3, cf: CFrame, material: Enum.Material, color: Color3, opts: any?): Part
	local result = S.Part(parent, name, size, cf, material, color, opts)
	if opts and opts.CanCollide == false then result.CanQuery = false end
	return result
end
local function beam(parent: Instance, name: string, a: Vector3, b: Vector3, diameter: number, material: Enum.Material, color: Color3, collide: boolean?): Part?
	local result = S.Beam(parent, name, a, b, diameter, material, color, collide)
	if result and collide == false then result.CanQuery = false end
	return result
end

local TAU = math.pi * 2

--------------------------------------------------------------------------------
-- Medidas
--------------------------------------------------------------------------------

local CONFIG = {
	Assets = {
		Tower = 8788183000,
		Generator = 10685426940,
	},

	TowerHeight = 105, -- passa MUITO da copa das árvores (30-56 studs)
	TowerFootprint = 16,

	-- Pátio cercado. X = largura (esquerda/direita), Z = profundidade
	-- (o portão fica em -Z, virado pro centro da ilha).
	-- 2,2 vezes a area anterior, com faixa de circulacao entre os setores.
	Yard = { Width = 132, Depth = 112 },

	Road = { Width = 16, Length = 72 },

	Shelter = { Width = 36, Depth = 26, Height = 13 },

	Fence = {
		-- 9 studs de barreira sólida: JumpHeight do StarterCharacter é 7,2,
		-- então não dá pra pular a cerca. É isso que faz o portão e o rasgo
		-- na lateral serem as ÚNICAS entradas.
		Height = 9,
		PostSpacing = 8,
		MeshSpacing = 2.2, -- espaçamento dos arames verticais (aparência)
		GateWidth = 18,
		-- Rasgo na lateral +X, em Z local: a rota alternativa.
		GapFrom = -6,
		GapTo = 8,
	},
}

RadioTowerGenerator.CONFIG = CONFIG

local COL = {
	Concrete = Color3.fromRGB(134, 132, 126),
	ConcreteDark = Color3.fromRGB(96, 94, 90),
	Steel = Color3.fromRGB(126, 131, 136),
	SteelDark = Color3.fromRGB(78, 82, 86),
	Rust = Color3.fromRGB(118, 74, 44),
	Galvanized = Color3.fromRGB(160, 166, 170),
	ShelterWall = Color3.fromRGB(108, 114, 106),
	Roof = Color3.fromRGB(86, 90, 92),
	Panel = Color3.fromRGB(48, 56, 60),
	Screen = Color3.fromRGB(92, 214, 160),
	Hazard = Color3.fromRGB(226, 188, 44),
	HazardDark = Color3.fromRGB(30, 28, 24),
	Red = Color3.fromRGB(196, 44, 38),
	FuelRed = Color3.fromRGB(158, 52, 40),
	Tank = Color3.fromRGB(148, 152, 148),
	Cable = Color3.fromRGB(34, 34, 36),
	Gravel = Color3.fromRGB(104, 100, 94),
	Copper = Color3.fromRGB(176, 118, 70),
	WoodSpool = Color3.fromRGB(118, 92, 58),
}

--------------------------------------------------------------------------------
-- Utilidades
--------------------------------------------------------------------------------

local terrainRay = RaycastParams.new()
terrainRay.FilterType = Enum.RaycastFilterType.Include
terrainRay.FilterDescendantsInstances = { Terrain }
terrainRay.IgnoreWater = true

local function groundY(x: number, z: number, fallback: number?): number
	local hit = Workspace:Raycast(Vector3.new(x, 600, z), Vector3.new(0, -1400, 0), terrainRay)
	if hit then
		return hit.Position.Y
	end
	return fallback or Layout.Height(x, z)
end

local function getIlha(): Folder
	local ilha = Workspace:FindFirstChild("Ilha")
	if ilha and ilha:IsA("Folder") then
		return ilha
	end
	local folder = Instance.new("Folder")
	folder.Name = "Ilha"
	folder.Parent = Workspace
	return folder
end

local function firstBasePart(root: Instance?): BasePart?
	if not root then
		return nil
	end
	if root:IsA("BasePart") then
		return root
	end
	return root:FindFirstChildWhichIsA("BasePart", true)
end

-- Part que não colide e não entra em raycast (decoração pura).
local DECO = { CanCollide = false, CastShadow = false }

-- Cabo/fio com barriga: a reta pura denuncia que é Part.
local function cableRun(parent: Instance, name: string, a: Vector3, b: Vector3, sag: number, diameter: number, color: Color3)
	local steps = 6
	local prev = a
	for i = 1, steps do
		local t = i / steps
		local p = a:Lerp(b, t) - Vector3.new(0, math.sin(t * math.pi) * sag, 0)
		beam(parent, name, prev, p, diameter, Enum.Material.Rubber, color, false)
		prev = p
	end
end

-- Placa de aviso com texto de verdade (SurfaceGui, sem asset).
local function warningSign(parent: Instance, name: string, cf: CFrame, width: number, height: number, title: string, subtitle: string?, color: Color3?)
	local plate = part(parent, name, Vector3.new(width, height, 0.18), cf, Enum.Material.Metal, color or COL.Hazard, { CanCollide = false })
	local gui = Instance.new("SurfaceGui")
	gui.Name = "Texto"
	gui.Face = Enum.NormalId.Front
	gui.CanvasSize = Vector2.new(math.floor(width * 40), math.floor(height * 40))
	gui.LightInfluence = 0.6
	gui.MaxDistance = 120
	gui.Parent = plate

	local frame = Instance.new("Frame")
	frame.Size = UDim2.fromScale(1, 1)
	frame.BackgroundTransparency = 1
	frame.Parent = gui

	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, if subtitle then 0.58 else 1)
	label.Position = UDim2.fromScale(0, 0)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamBold
	label.Text = title
	label.TextColor3 = COL.HazardDark
	label.TextScaled = true
	label.Parent = frame

	if subtitle then
		local sub = Instance.new("TextLabel")
		sub.Size = UDim2.fromScale(1, 0.42)
		sub.Position = UDim2.fromScale(0, 0.58)
		sub.BackgroundTransparency = 1
		sub.Font = Enum.Font.Gotham
		sub.Text = subtitle
		sub.TextColor3 = COL.HazardDark
		sub.TextScaled = true
		sub.Parent = frame
	end
	return plate
end

-- Faixa zebrada de perigo (borda de plataforma, batente do gerador).
local function hazardStripe(parent: Instance, cf: CFrame, length: number, width: number, name: string)
	local count = math.max(2, math.floor(length / 1.6))
	for i = 1, count do
		local x = -length / 2 + (i - 0.5) * (length / count)
		part(parent, name, Vector3.new(length / count, 0.12, width), cf * CFrame.new(x, 0, 0), Enum.Material.SmoothPlastic, if i % 2 == 0 then COL.HazardDark else COL.Hazard, DECO)
	end
end

--------------------------------------------------------------------------------
-- Assets (InsertService -- só em modo de edição; runtime cai no fallback)
--------------------------------------------------------------------------------

local assetCache: { [number]: Model? } = {}
local assetFailed: { [number]: boolean } = {}

local function loadAssetModel(assetId: number): Model?
	if assetId <= 0 then return nil end -- opcao offline/validacao com as Parts
	if assetCache[assetId] then
		return assetCache[assetId]
	end
	if assetFailed[assetId] then
		return nil
	end

	local ok, container = pcall(function()
		return InsertService:LoadAsset(assetId)
	end)
	if not ok or typeof(container) ~= "Instance" then
		ok, container = pcall(function()
			local holder = Instance.new("Model")
			for _, obj in game:GetObjects("rbxassetid://" .. assetId) do
				obj.Parent = holder
			end
			return holder
		end)
	end
	if not ok or typeof(container) ~= "Instance" then
		assetFailed[assetId] = true
		warn(string.format("[RadioTowerGenerator] Asset %d não carregou (%s) -- usando a versão em Parts.", assetId, tostring(container)))
		return nil
	end

	local holder = container :: Instance
	holder.Parent = nil
	for _, d in holder:GetDescendants() do
		if d:IsA("LuaSourceContainer") then
			d:Destroy()
		elseif d:IsA("BasePart") then
			d.Anchored = true
		end
	end

	local children = holder:GetChildren()
	local model: Model
	if #children == 1 and children[1]:IsA("Model") then
		model = children[1]:Clone() :: Model
	else
		model = Instance.new("Model")
		model.Name = "Asset_" .. assetId
		for _, child in children do
			child:Clone().Parent = model
		end
	end
	if not model.PrimaryPart then
		model.PrimaryPart = model:FindFirstChildWhichIsA("BasePart", true)
	end
	model.Parent = nil
	assetCache[assetId] = model
	return model
end

local function modelBottomY(model: Model): number?
	local minY = math.huge
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			local cf, s = d.CFrame, d.Size
			local ext = math.abs(cf.RightVector.Y) * s.X + math.abs(cf.UpVector.Y) * s.Y + math.abs(cf.LookVector.Y) * s.Z
			minY = math.min(minY, cf.Position.Y - ext * 0.5)
		end
	end
	return if minY < math.huge then minY else nil
end

--[[
	placeAsset(assetId, parent, cf, targetHeight, name)
	Escala o modelo pra targetHeight, assenta a base no Y do cf e devolve o
	clone -- ou nil se o asset não carregou (aí quem chamou monta em Parts).
]]
local function placeAsset(assetId: number, parent: Instance, cf: CFrame, targetHeight: number, name: string): Model?
	local template = loadAssetModel(assetId)
	if not template then
		return nil
	end
	local clone = template:Clone()
	clone.Name = name

	local _, size = clone:GetBoundingBox()
	if size.Y > 0.01 then
		clone:ScaleTo(clone:GetScale() * (targetHeight / size.Y))
	end
	clone:PivotTo(cf)
	local bottom = modelBottomY(clone)
	if bottom then
		clone:PivotTo(clone:GetPivot() + Vector3.new(0, cf.Position.Y - bottom, 0))
	end
	for _, d in clone:GetDescendants() do
		if d:IsA("BasePart") then
			d.Anchored = true
		end
	end
	clone.Parent = parent
	return clone
end

--------------------------------------------------------------------------------
-- Onde fica a estação, e o terraplano
--------------------------------------------------------------------------------

--[[
	siteCFrame()
	Centro do sítio, já no Y do pátio, com o PORTÃO virado pro centro da ilha
	(é de lá que a trilha de manutenção chega).

	Usa o site "Radio" do IslandLayout quando ele existe. Num mapa salvo antes
	desse site existir, usa um ponto provisório afastado da Torre de Vigia.
	Build() prioriza a posição da estação já salva, quando ela existe.
]]
local function siteCFrame(): (CFrame, number)
	Layout.Plan()

	local x, z
	local site = Layout.Site("Radio")
	if site then
		x, z = site.x, site.z
	else
		local torre = Layout.Site("Torre")
		if torre then
			local len = math.sqrt(torre.x * torre.x + torre.z * torre.z)
			local outward = if len > 1 then Vector2.new(torre.x / len, torre.z / len) else Vector2.new(1, 0)
			x = torre.x - outward.X * 78
			z = torre.z - outward.Y * 78
			warn("[RadioTowerGenerator] Sem site 'Radio' no layout -- usando um ponto ao lado da Torre de Vigia. Regere o terreno pra ganhar a clareira e a trilha.")
		else
			local anchor = firstBasePart(getIlha():FindFirstChild("TorreDeVigia", true))
			local base = if anchor then anchor.Position + Vector3.new(78, 0, 0) else Vector3.new(80, 0, 0)
			x, z = base.X, base.Z
			warn("[RadioTowerGenerator] Sem layout e sem Torre de Vigia -- estação num ponto provisório.")
		end
	end

	-- Altura do pátio = média do terreno sob a área cercada.
	local sum, n = 0, 0
	for gx = -2, 2 do
		for gz = -2, 2 do
			sum += groundY(x + gx * CONFIG.Yard.Width / 4, z + gz * CONFIG.Yard.Depth / 4)
			n += 1
		end
	end
	local padY = sum / n

	local center = Vector3.new(x, padY, z)
	local toCenter = Vector3.new(-x, 0, -z)
	if toCenter.Magnitude < 1 then
		toCenter = Vector3.new(0, 0, 1)
	end
	return CFrame.lookAt(center, center + toCenter.Unit * 10), padY
end

-- Terraplanagem: corta o morro e aterra o buraco, igual a um pátio de
-- verdade. Sem isso a cerca fica flutuando de um lado e enterrada do outro.
local function levelYard(cf: CFrame)
	local W = CONFIG.Yard.Width + 10
	local D = CONFIG.Yard.Depth + 10
	Terrain:FillBlock(cf * CFrame.new(0, -5, 0), Vector3.new(W, 10, D), Enum.Material.Ground)
	Terrain:FillBlock(cf * CFrame.new(0, 14, 0), Vector3.new(W, 28, D), Enum.Material.Air)
end

-- Estrada de manutenção: desce do portão até o terreno natural.
local function buildRoad(parent: Instance, cf: CFrame, padY: number, sculpt: boolean)
	local steps = 8
	local segLen = CONFIG.Road.Length / steps
	local startZ = CONFIG.Yard.Depth / 2

	for i = 1, steps do
		local t = i / steps
		local z = startZ + (i - 0.5) * segLen
		local p = (cf * CFrame.new(0, 0, -z)).Position
		local natural = groundY(p.X, p.Z, padY)
		local y = padY + (natural - padY) * t
		local segCF = cf * CFrame.new(0, y - padY, -z)

		if sculpt then
			Terrain:FillBlock(segCF * CFrame.new(0, -3, 0), Vector3.new(CONFIG.Road.Width, 6, segLen + 2), Enum.Material.Ground)
			Terrain:FillBlock(segCF * CFrame.new(0, 9, 0), Vector3.new(CONFIG.Road.Width, 18, segLen + 2), Enum.Material.Air)
		end

		-- Marcas de pneu: duas faixas de cascalho mais escuro.
		for _, sx in { -2.6, 2.6 } do
			part(parent, "Rodado", Vector3.new(2.2, 0.18, segLen), segCF * CFrame.new(sx, 0.1, 0), Enum.Material.Ground, COL.Gravel, DECO)
		end
	end
end

-- Árvores/arbustos/rochas geradas em cima do sítio saem: o pátio foi aberto.
local function clearVegetation(cf: CFrame, backup: Folder?): number
	local ilha = getIlha()
	local center = cf.Position
	-- Diagonal: o raio antigo deixava arvores dentro dos cantos do patio.
	local radius = Vector2.new(CONFIG.Yard.Width, CONFIG.Yard.Depth).Magnitude * 0.5 + 8
	local roadEnd = (cf * CFrame.new(0, 0, -(CONFIG.Yard.Depth / 2 + CONFIG.Road.Length))).Position
	local removed = 0

	local function nearRoad(p: Vector3): boolean
		local a = Vector3.new(center.X, 0, center.Z)
		local b = Vector3.new(roadEnd.X, 0, roadEnd.Z)
		local ab = b - a
		local t = math.clamp((Vector3.new(p.X, 0, p.Z) - a):Dot(ab) / ab:Dot(ab), 0, 1)
		return ((a + ab * t) - Vector3.new(p.X, 0, p.Z)).Magnitude < CONFIG.Road.Width * 0.75
	end

	for _, folderName in { "Floresta", "Vegetacao", "Rochas" } do
		local folder = ilha:FindFirstChild(folderName)
		if not folder then
			continue
		end
		for _, obj in folder:GetChildren() do
			local pivot = if obj:IsA("Model") then obj:GetPivot().Position elseif obj:IsA("BasePart") then obj.Position else nil
			if pivot then
				local flat = Vector3.new(pivot.X - center.X, 0, pivot.Z - center.Z)
				if flat.Magnitude < radius or nearRoad(pivot) then
					if backup then
						local saved = backup:FindFirstChild(folderName)
						if not saved then
							saved = Instance.new("Folder")
							saved.Name = folderName
							saved.Parent = backup
						end
						obj.Parent = saved
					else
						obj:Destroy()
					end
					removed += 1
				end
			end
		end
	end
	return removed
end

--------------------------------------------------------------------------------
-- Torre de transmissão
--------------------------------------------------------------------------------

-- Treliça em Parts: usada quando o asset da torre não carrega (runtime) e
-- como referência de escala pra quando ele carrega.
local function latticeTower(parent: Instance, cf: CFrame, height: number, baseWidth: number, topWidth: number)
	local segments = 10
	local corners = { Vector2.new(-1, -1), Vector2.new(1, -1), Vector2.new(1, 1), Vector2.new(-1, 1) }

	local function nodeAt(c: Vector2, t: number): Vector3
		local half = (baseWidth + (topWidth - baseWidth) * t) * 0.5
		return (cf * CFrame.new(c.X * half, t * height, c.Y * half)).Position
	end

	for i = 0, segments - 1 do
		local t0, t1 = i / segments, (i + 1) / segments
		for k, c in corners do
			-- Montante (colide só na parte de baixo: é onde o jogador encosta).
			beam(parent, "Montante", nodeAt(c, t0), nodeAt(c, t1), 0.55, Enum.Material.Metal, COL.Steel, i < 3)
			local nextC = corners[k % 4 + 1]
			beam(parent, "Travessa", nodeAt(c, t1), nodeAt(nextC, t1), 0.3, Enum.Material.Metal, COL.SteelDark, false)
			beam(parent, "Diagonal", nodeAt(c, t0), nodeAt(nextC, t1), 0.26, Enum.Material.Metal, COL.SteelDark, false)
		end
	end
end

--[[
	buildTower(parent, cf, rng)
	Torre + fundações + estais + plataforma de serviço + baliza. Devolve a
	posição do topo (pra puxar o cabo de antena e pendurar a luz).
]]
local function buildTower(parent: Instance, cf: CFrame, rng: Random): Vector3
	local folder = Instance.new("Folder")
	folder.Name = "Torre"
	folder.Parent = parent

	local H = CONFIG.TowerHeight
	local W = CONFIG.TowerFootprint

	-- Fundação: laje + 4 blocos de concreto sob os montantes.
	part(folder, "LajeTorre", Vector3.new(W + 6, 1.2, W + 6), cf * CFrame.new(0, 0.6, 0), Enum.Material.Concrete, COL.Concrete)
	for _, c in { Vector2.new(-1, -1), Vector2.new(1, -1), Vector2.new(1, 1), Vector2.new(-1, 1) } do
		part(folder, "Sapata", Vector3.new(3.4, 2.2, 3.4), cf * CFrame.new(c.X * W / 2, 1.1, c.Y * W / 2), Enum.Material.Concrete, COL.ConcreteDark)
	end

	local baseCF = cf * CFrame.new(0, 1.2, 0)
	if not placeAsset(CONFIG.Assets.Tower, folder, baseCF, H, "TorreAsset") then
		latticeTower(folder, baseCF, H, W, 3.2)
	end

	-- Estais: três âncoras de concreto puxando o terço superior.
	local guyY = H * 0.66
	for i = 1, 3 do
		local ang = math.rad(30 + (i - 1) * 120)
		local dist = H * 0.42
		local anchorFlat = cf * CFrame.new(math.cos(ang) * dist, 0, math.sin(ang) * dist)
		local anchorY = groundY(anchorFlat.Position.X, anchorFlat.Position.Z, cf.Position.Y)
		local anchorPos = Vector3.new(anchorFlat.Position.X, anchorY, anchorFlat.Position.Z)
		part(folder, "AncoraEstai_" .. i, Vector3.new(3, 1.6, 3), CFrame.new(anchorPos + Vector3.new(0, 0.5, 0)), Enum.Material.Concrete, COL.ConcreteDark)
		part(folder, "OlhalEstai_" .. i, Vector3.new(0.4, 1.8, 0.4), CFrame.new(anchorPos + Vector3.new(0, 2, 0)), Enum.Material.Metal, COL.SteelDark, DECO)
		cableRun(folder, "Estai_" .. i, anchorPos + Vector3.new(0, 2.6, 0), (baseCF * CFrame.new(0, guyY, 0)).Position, 2.5, 0.16, COL.SteelDark)
	end

	-- Plataforma de serviço a ~28 studs, com escada de treliça (dá pra subir).
	local platY = 28
	part(folder, "PlataformaServico", Vector3.new(10, 0.5, 10), baseCF * CFrame.new(0, platY, 0), Enum.Material.DiamondPlate, COL.Steel)
	for _, side in { Vector3.new(0, 0, -1), Vector3.new(0, 0, 1), Vector3.new(-1, 0, 0), Vector3.new(1, 0, 0) } do
		local guard = baseCF * CFrame.new(side.X * 5, platY + 1.7, side.Z * 5) * CFrame.Angles(0, if side.X ~= 0 then math.pi / 2 else 0, 0)
		part(folder, "GuardaCorpo", Vector3.new(10, 0.16, 0.16), guard * CFrame.new(0, 1.5, 0), Enum.Material.Metal, COL.SteelDark, DECO)
		part(folder, "GuardaCorpo", Vector3.new(10, 0.16, 0.16), guard * CFrame.new(0, 0.6, 0), Enum.Material.Metal, COL.SteelDark, DECO)
	end
	hazardStripe(folder, baseCF * CFrame.new(0, platY + 0.3, -5), 10, 0.8, "FaixaPlataforma")

	local ladder = Instance.new("TrussPart")
	ladder.Name = "EscadaTorre"
	ladder.Size = Vector3.new(2, platY, 2)
	ladder.CFrame = baseCF * CFrame.new(W / 2 - 1, platY / 2, 0)
	ladder.Anchored = true
	ladder.Material = Enum.Material.Metal
	ladder.Color = COL.Galvanized
	ladder.Parent = folder

	-- Antenas no topo: chicote vertical, dois dipolos e uma parabólica.
	local top = (baseCF * CFrame.new(0, H, 0)).Position
	part(folder, "ChicoteAntena", Vector3.new(0.22, 12, 0.22), CFrame.new(top + Vector3.new(0, 6, 0)), Enum.Material.Metal, COL.Galvanized, DECO)
	for i, h in { H - 6, H - 13 } do
		part(folder, "BracoDipolo_" .. i, Vector3.new(9, 0.18, 0.18), baseCF * CFrame.new(0, h, 0) * CFrame.Angles(0, rng:NextNumber(0, TAU), 0), Enum.Material.Metal, COL.Galvanized, DECO)
	end
	part(folder, "Parabolica", Vector3.new(0.5, 5, 5), baseCF * CFrame.new(2.4, H * 0.55, 0) * CFrame.Angles(0, 0, math.rad(88)), Enum.Material.SmoothPlastic, COL.Galvanized, {
		Shape = Enum.PartType.Cylinder,
		CanCollide = false,
	})

	-- Baliza vermelha do topo + uma intermediária (aviso aeronáutico).
	for i, h in { H + 0.8, H * 0.55 } do
		local lamp = part(folder, "Baliza_" .. i, Vector3.new(1.5, 1.5, 1.5), baseCF * CFrame.new(0, h, 0), Enum.Material.Neon, COL.Red, {
			Shape = Enum.PartType.Ball,
			CanCollide = false,
			CastShadow = false,
		})
		lamp:SetAttribute("BalizaRadio", true)
		local light = Instance.new("PointLight")
		light.Name = "LuzBaliza"
		light.Color = Color3.fromRGB(255, 70, 60)
		light.Brightness = 2.5
		light.Range = 42
		light.Shadows = false
		light.Parent = lamp
	end

	-- Coaxial subindo do casario até as antenas do topo.
	cableRun(folder, "Coaxial", (baseCF * CFrame.new(W / 2 - 0.6, 1.5, 0)).Position, top - Vector3.new(0, 3, 0), 0, 0.18, COL.Cable)

	-- Aterramento e placa na perna da torre.
	beam(folder, "Aterramento", (baseCF * CFrame.new(W / 2, 1, 0)).Position, (cf * CFrame.new(W / 2 + 2, 0.2, 2)).Position, 0.14, Enum.Material.Metal, COL.Copper, false)
	warningSign(folder, "PlacaTorre", cf * CFrame.new(-W / 2 + 1, 4, -W / 2 - 0.2), 3.4, 2.4, "PERIGO", "RISCO DE QUEDA · NÃO SUBA")

	return top
end

--------------------------------------------------------------------------------
-- Abrigo técnico
--------------------------------------------------------------------------------

-- Luz que só funciona com o gerador ligado (RadioSiteSystem liga/desliga).
local function poweredLight(host: BasePart, color: Color3, brightness: number, range: number, spot: boolean?)
	host:SetAttribute("LuzRadio", true)
	local light: Light
	if spot then
		local s = Instance.new("SpotLight")
		s.Face = Enum.NormalId.Bottom
		s.Angle = 70
		light = s
	else
		light = Instance.new("PointLight")
	end
	light.Name = "LuzRadio"
	light.Color = color
	light.Brightness = brightness
	light.Range = range
	light.Shadows = true
	light.Enabled = false
	light.Parent = host
	return light
end

--[[
	buildShelter(parent, cf)
	Casinha de alvenaria com porta de aço, janela, rack de instalação das
	peças, painel de controle e a mesa do operador com o rádio. cf = centro
	do abrigo no chão, olhando pro portão.
]]
local function buildShelter(parent: Instance, cf: CFrame): { [string]: BasePart }
	local folder = Instance.new("Folder")
	folder.Name = "Abrigo"
	folder.Parent = parent

	local W, D, H = CONFIG.Shelter.Width, CONFIG.Shelter.Depth, CONFIG.Shelter.Height
	local out: { [string]: BasePart } = {}

	-- Laje e soleira.
	part(folder, "LajeAbrigo", Vector3.new(W + 2, 0.8, D + 2), cf * CFrame.new(0, 0.4, 0), Enum.Material.Concrete, COL.Concrete)
	local floorCF = cf * CFrame.new(0, 0.8, 0)

	-- Paredes (a da frente tem porta, a lateral tem janela).
	local doorW, doorH = 6, 8.5
	S.WallWithOpenings(folder, floorCF * CFrame.new(0, 0, -D / 2), W, H, 0.7, { { x0 = -doorW / 2, x1 = doorW / 2, y0 = 0, y1 = doorH } }, Enum.Material.Concrete, COL.ShelterWall)
	S.WallWithOpenings(folder, floorCF * CFrame.new(0, 0, D / 2), W, H, 0.7, {}, Enum.Material.Concrete, COL.ShelterWall)
	S.WallWithOpenings(folder, floorCF * CFrame.new(-W / 2, 0, 0) * CFrame.Angles(0, math.pi / 2, 0), D, H, 0.7, {}, Enum.Material.Concrete, COL.ShelterWall)
	S.WallWithOpenings(folder, floorCF * CFrame.new(W / 2, 0, 0) * CFrame.Angles(0, math.pi / 2, 0), D, H, 0.7, {
		{ x0 = 2, x1 = 8, y0 = 0, y1 = doorH }, -- saida lateral, z = -5
		{ x0 = -9, x1 = -3, y0 = 5.5, y1 = 8.5 },
	}, Enum.Material.Concrete, COL.ShelterWall)

	-- Vidro sujo da janela.
	local glass = part(folder, "Janela", Vector3.new(0.22, 3, 6), floorCF * CFrame.new(W / 2, 7, 6), Enum.Material.Glass, Color3.fromRGB(150, 170, 165))
	glass.Transparency = 0.55

	-- Telhado metálico com caimento e beiral.
	part(folder, "Telhado", Vector3.new(W + 3, 0.4, D + 3), floorCF * CFrame.new(0, H + 0.4, 0) * CFrame.Angles(math.rad(3), 0, 0), Enum.Material.CorrodedMetal, COL.Roof)
	part(folder, "Calha", Vector3.new(W + 3, 0.35, 0.35), floorCF * CFrame.new(0, H, -D / 2 - 1.4), Enum.Material.Metal, COL.SteelDark, DECO)

	-- Porta de aço (DoorSystem abre/fecha pelo Attribute "Porta").
	local doorCF = floorCF * CFrame.new(0, doorH / 2, -D / 2)
	local door = part(folder, "Porta", Vector3.new(doorW, doorH, 0.28), doorCF, Enum.Material.DiamondPlate, COL.SteelDark)
	door:SetAttribute("Porta", true)
	door:SetAttribute("PortaAberta", false)
	door:SetAttribute("CFrameFechada", doorCF)
	door:SetAttribute("LarguraPorta", doorW)
	-- A porta lateral usa o mesmo contrato do DoorSystem da entrada.
	local sideCF = floorCF * CFrame.new(W / 2, doorH / 2, -5) * CFrame.Angles(0, math.pi / 2, 0)
	local sideDoor = part(folder, "PortaServico", Vector3.new(doorW, doorH, 0.28), sideCF, Enum.Material.DiamondPlate, COL.SteelDark)
	sideDoor:SetAttribute("Porta", true)
	sideDoor:SetAttribute("PortaAberta", false)
	sideDoor:SetAttribute("CFrameFechada", sideCF)
	sideDoor:SetAttribute("LarguraPorta", doorW)
	for _, leaf in { door, sideDoor } do
		local handle = part(leaf, "Macaneta", Vector3.new(0.22, 0.22, 0.6), leaf.CFrame * CFrame.new(doorW / 2 - 0.6, 0, -0.3), Enum.Material.Metal, COL.Galvanized, DECO)
		handle.Anchored = false
		handle.Massless = true
		local weld = Instance.new("WeldConstraint")
		weld.Part0 = leaf
		weld.Part1 = handle
		weld.Parent = handle
	end

	-- Marquise, patamar baixo e estrutura aparente da fachada.
	part(folder, "PatamarEntrada", Vector3.new(13, 0.4, 7), cf * CFrame.new(0, 0.2, -D / 2 - 3.5), Enum.Material.Concrete, COL.Concrete)
	part(folder, "Marquise", Vector3.new(14, 0.45, 7.5), floorCF * CFrame.new(0, 10.1, -D / 2 - 3.1), Enum.Material.Metal, COL.Roof)
	for _, x in { -6, 6 } do
		part(folder, "PilarMarquise", Vector3.new(0.45, 10.1, 0.45), floorCF * CFrame.new(x, 5.05, -D / 2 - 6), Enum.Material.Metal, COL.SteelDark)
	end
	part(folder, "PatamarServico", Vector3.new(5, 0.4, 8), cf * CFrame.new(W / 2 + 2.5, 0.2, -5), Enum.Material.Concrete, COL.Concrete)
	for _, x in { -W / 2, W / 2 } do
		for _, z in { -D / 2, D / 2 } do
			part(folder, "Pilarete", Vector3.new(0.95, H, 0.95), floorCF * CFrame.new(x, H / 2, z), Enum.Material.Concrete, COL.ConcreteDark)
		end
	end
	for _, z in { -D / 2 - 0.38, D / 2 + 0.38 } do
		part(folder, "FaixaFachada", Vector3.new(W, 0.9, 0.12), floorCF * CFrame.new(0, 9.5, z), Enum.Material.Metal, Color3.fromRGB(46, 79, 80), DECO)
		part(folder, "RodapeExterno", Vector3.new(W, 0.7, 0.12), floorCF * CFrame.new(0, 0.35, z), Enum.Material.Concrete, COL.ConcreteDark, DECO)
	end
	for x = -W / 2, W / 2, 3 do
		part(folder, "JuntaTelhado", Vector3.new(0.12, 0.12, D + 3), floorCF * CFrame.new(x, H + 0.65, 0) * CFrame.Angles(math.rad(3), 0, 0), Enum.Material.Metal, COL.Galvanized, DECO)
	end
	warningSign(folder, "Identificacao", floorCF * CFrame.new(0, 11.5, -D / 2 - 0.5), 13, 1.6, "ESTAÇÃO DE RÁDIO", nil, Color3.fromRGB(198, 210, 202))

	-- Luminária externa sobre a porta.
	local lamp = part(folder, "LuminariaPorta", Vector3.new(1.6, 0.5, 1), floorCF * CFrame.new(0, doorH + 0.9, -D / 2 - 0.6), Enum.Material.Metal, COL.SteelDark, { CanCollide = false })
	poweredLight(lamp, Color3.fromRGB(255, 226, 170), 1.6, 22)

	----------------------------------------------------------------------------
	-- Interior
	----------------------------------------------------------------------------
	-- As três estações ficam em paredes diferentes, com o meio da sala livre:
	-- o rack no fundo à esquerda, o painel na parede lateral e a mesa do
	-- operador na direita. Tudo posicionado em fração de W/D, então mudar o
	-- tamanho do abrigo no CONFIG reposiciona o interior junto.
	local inner = floorCF
	local backZ = D / 2 - 1.4
	local leftX = -W / 2 + 0.9
	-- Piso legivel, faixas finas e corredor de 12 studs livre entre as tasks.
	part(folder, "PisoTecnico", Vector3.new(W - 1, 0.08, D - 1), inner * CFrame.new(0, 0.04, 0), Enum.Material.SmoothPlastic, Color3.fromRGB(61, 70, 73), DECO)
	for _, x in { -6, 6 } do
		part(folder, "LinhaCirculacao", Vector3.new(0.12, 0.03, D - 3), inner * CFrame.new(x, 0.1, 0), Enum.Material.SmoothPlastic, COL.Hazard, DECO)
	end
	for z = -D / 2 + 4, D / 2 - 2, 4 do
		part(folder, "JuntaPiso", Vector3.new(W - 1, 0.015, 0.035), inner * CFrame.new(0, 0.085, z), Enum.Material.SmoothPlastic, COL.Panel, DECO)
	end

	-- Rack do transmissor (onde as 3 peças são instaladas).
	local rack = part(folder, "ConsoleInstalacao", Vector3.new(5.5, 7, 2), inner * CFrame.new(-W * 0.3, 3.5, backZ), Enum.Material.Metal, COL.Panel)
	part(folder, "TrilhoRack", Vector3.new(5, 0.2, 0.2), inner * CFrame.new(-W * 0.3, 6, backZ - 1.1), Enum.Material.Metal, COL.SteelDark, DECO)
	for i = 1, 4 do
		part(folder, "GavetaRack_" .. i, Vector3.new(4.8, 1.1, 0.3), inner * CFrame.new(-W * 0.3, 1.2 + i * 1.35, backZ - 1.05), Enum.Material.Metal, COL.SteelDark, DECO)
	end
	out.Rack = rack
	warningSign(folder, "SetorInstalacao", inner * CFrame.new(-W * 0.3, 9.4, D / 2 - 0.5), 9, 1.6, "01 / TRANSMISSOR", "INSTALE AS TRÊS PEÇAS", Color3.fromRGB(192, 210, 202))

	-- Painel de controle na parede lateral: disjuntores + voltímetro.
	local panel = part(folder, "PainelControle", Vector3.new(0.9, 5.4, 4), inner * CFrame.new(leftX, 4.2, 0), Enum.Material.Metal, COL.Panel)
	panel:SetAttribute("InteracaoRadio", "Painel")
	panel:SetAttribute("Sabotavel", true)
	for i = 1, 4 do
		part(folder, "Disjuntor_" .. i, Vector3.new(0.3, 0.7, 0.45), inner * CFrame.new(leftX + 0.5, 5.8 - i * 0.85, -0.9), Enum.Material.SmoothPlastic, COL.SteelDark, DECO)
	end
	local vu = part(folder, "Voltimetro", Vector3.new(0.2, 1.1, 1.4), inner * CFrame.new(leftX + 0.55, 5.8, 1.1), Enum.Material.Neon, COL.Screen, DECO)
	vu.Transparency = 0.25
	vu:SetAttribute("LuzRadio", true)
	out.Painel = panel
	warningSign(folder, "SetorEnergia", inner * CFrame.new(leftX + 0.6, 8.4, 0) * CFrame.Angles(0, -math.pi / 2, 0), 7, 1.6, "02 / CONTROLE", "ENERGIA DA ESTAÇÃO", Color3.fromRGB(192, 210, 202))

	-- Mesa do operador com o rádio, o microfone e o manual.
	local deskX = W * 0.28
	part(folder, "Mesa", Vector3.new(7, 0.35, 2.8), inner * CFrame.new(deskX, 3, 1.8), Enum.Material.Metal, COL.SteelDark)
	for _, sx in { -3, 3 } do
		part(folder, "PeMesa", Vector3.new(0.3, 3, 2.6), inner * CFrame.new(deskX + sx, 1.5, 1.8), Enum.Material.Metal, COL.SteelDark, DECO)
	end
	local console = part(folder, "ConsoleRadio", Vector3.new(4, 2, 2.2), inner * CFrame.new(deskX - 0.2, 4.2, 1.8), Enum.Material.Metal, COL.Panel)
	console:SetAttribute("InteracaoRadio", "Socorro")
	local dial = part(folder, "Mostrador", Vector3.new(2.6, 0.9, 0.15), inner * CFrame.new(deskX - 0.2, 4.6, 0.72) * CFrame.Angles(math.rad(-12), 0, 0), Enum.Material.Neon, COL.Screen, DECO)
	dial.Transparency = 0.3
	dial:SetAttribute("LuzRadio", true)
	for i = 1, 3 do
		part(folder, "Botao_" .. i, Vector3.new(0.35, 0.35, 0.35), inner * CFrame.new(deskX - 1.4 + i * 0.7, 3.9, 0.74), Enum.Material.SmoothPlastic, COL.Red, {
			Shape = Enum.PartType.Cylinder,
			CanCollide = false,
			CastShadow = false,
		})
	end
	part(folder, "Microfone", Vector3.new(0.5, 0.5, 1.4), inner * CFrame.new(deskX + 2.4, 3.4, 1.4) * CFrame.Angles(math.rad(20), 0, 0), Enum.Material.SmoothPlastic, COL.HazardDark, DECO)
	cableRun(folder, "CaboMicrofone", (inner * CFrame.new(deskX + 2.4, 3.3, 1.4)).Position, (inner * CFrame.new(deskX + 1.2, 3.6, 2.1)).Position, 0.5, 0.09, COL.Cable)
	out.Console = console
	warningSign(folder, "SetorTransmissao", inner * CFrame.new(deskX, 8.8, backZ), 10, 1.6, "03 / COMUNICAÇÕES", "ENVIE O PEDIDO DE SOCORRO", Color3.fromRGB(192, 210, 202))

	-- Cadeira e prateleira (fundo à direita).
	part(folder, "Cadeira", Vector3.new(1.8, 0.3, 1.8), inner * CFrame.new(deskX, 2.2, -1.2), Enum.Material.Metal, COL.SteelDark)
	part(folder, "EncostoCadeira", Vector3.new(1.8, 2, 0.25), inner * CFrame.new(deskX, 3.2, -2), Enum.Material.Metal, COL.SteelDark, DECO)
	part(folder, "Prateleira", Vector3.new(7, 0.25, 2.2), inner * CFrame.new(W * 0.25, 3.4, backZ), Enum.Material.Metal, COL.SteelDark)

	-- Fusível reserva na prateleira: é ele que vai pra caixa lá fora.
	local fuse = part(folder, "FusivelReserva", Vector3.new(0.55, 0.55, 1.5), inner * CFrame.new(W * 0.25 - 1.2, 3.85, backZ - 0.35) * CFrame.Angles(0, 0, math.rad(90)), Enum.Material.Glass, COL.Copper, {
		Shape = Enum.PartType.Cylinder,
		CanCollide = false,
	})
	fuse:SetAttribute("InteracaoRadio", "PegarFusivel")
	local fuseGlow = Instance.new("PointLight")
	fuseGlow.Name = "BrilhoFusivel"
	fuseGlow.Color = Color3.fromRGB(255, 196, 120)
	fuseGlow.Brightness = 0.6
	fuseGlow.Range = 8
	fuseGlow.Shadows = false
	fuseGlow.Parent = fuse
	out.Fusivel = fuse
	warningSign(folder, "EtiquetaFusivel", inner * CFrame.new(W * 0.25, 5.3, backZ + 0.8), 6, 1.1, "FUSÍVEL RESERVA", nil, COL.Hazard)

	-- Luminária interna + loot pros Sobreviventes que entrarem.
	for _, x in { -W * 0.25, W * 0.25 } do
		local ceiling = part(folder, "LuminariaTeto", Vector3.new(5, 0.3, 1), inner * CFrame.new(x, H - 0.6, 0), Enum.Material.Metal, COL.SteelDark, DECO)
		poweredLight(ceiling, Color3.fromRGB(236, 240, 255), 1.6, 24)
	end
	-- Bateria independente: permite ler as tasks antes de ligar o gerador.
	local emergency = part(folder, "LuzEmergencia", Vector3.new(1.8, 0.4, 0.4), inner * CFrame.new(0, 8.9, -D / 2 + 0.7), Enum.Material.Neon, Color3.fromRGB(235, 170, 85), DECO)
	local emergencyLight = Instance.new("PointLight")
	emergencyLight.Color = emergency.Color
	emergencyLight.Brightness = 0.8
	emergencyLight.Range = 27
	emergencyLight.Shadows = true
	emergencyLight.Parent = emergency
	S.LootPoint(folder, inner * CFrame.new(-W * 0.32, 1.2, -D * 0.25))
	S.LootPoint(folder, inner * CFrame.new(W * 0.28, 3.4, 2.6))

	warningSign(folder, "PlacaAbrigo", floorCF * CFrame.new(-W * 0.3, 5.6, -D / 2 - 0.45), 3.4, 2.2, "SALA TÉCNICA", "SOMENTE AUTORIZADOS")
	return out
end

--------------------------------------------------------------------------------
-- Gerador, combustível e quadro elétrico
--------------------------------------------------------------------------------

local function buildGenerator(parent: Instance, cf: CFrame): { [string]: BasePart }
	local folder = Instance.new("Folder")
	folder.Name = "Gerador"
	folder.Parent = parent
	local out: { [string]: BasePart } = {}

	-- Base de concreto com faixa de perigo em volta.
	part(folder, "BaseGerador", Vector3.new(12, 0.7, 8.5), cf * CFrame.new(0, 0.35, 0), Enum.Material.Concrete, COL.Concrete)
	hazardStripe(folder, cf * CFrame.new(0, 0.72, -4.1), 12, 0.7, "FaixaGerador")
	hazardStripe(folder, cf * CFrame.new(0, 0.72, 4.1), 12, 0.7, "FaixaGerador")

	local padCF = cf * CFrame.new(0, 0.7, 0)
	local asset = placeAsset(CONFIG.Assets.Generator, folder, padCF, 5.5, "GeradorAsset")

	-- Corpo: ou o asset, ou a versão em Parts (skid + bloco + radiador).
	local body: BasePart
	if asset then
		body = firstBasePart(asset) :: BasePart
	else
		part(folder, "Skid", Vector3.new(8, 0.6, 4), padCF * CFrame.new(0, 0.3, 0), Enum.Material.Metal, COL.SteelDark)
		body = part(folder, "CorpoGerador", Vector3.new(6.4, 3.2, 3.4), padCF * CFrame.new(0, 2.2, 0), Enum.Material.Metal, COL.Steel)
		part(folder, "Radiador", Vector3.new(0.6, 2.6, 3), padCF * CFrame.new(-3.4, 2.2, 0), Enum.Material.DiamondPlate, COL.SteelDark)
		part(folder, "TampaMotor", Vector3.new(5, 0.4, 3), padCF * CFrame.new(0, 3.9, 0), Enum.Material.DiamondPlate, COL.SteelDark, DECO)
		for i = 1, 4 do
			part(folder, "Aleta_" .. i, Vector3.new(0.2, 2.2, 2.8), padCF * CFrame.new(-3.1 + i * 0.22, 2.2, 0), Enum.Material.Metal, COL.SteelDark, DECO)
		end
	end
	body.Name = "CorpoGerador"
	body:SetAttribute("MotorGerador", true)
	body:SetAttribute("Sabotavel", true)
	out.Corpo = body

	local anchorCF = padCF * CFrame.new(0, 0, 0)

	-- Escapamento (a fumaça sai daqui quando liga).
	part(folder, "TuboEscape", Vector3.new(0.7, 4.5, 0.7), anchorCF * CFrame.new(2.6, 4, 1.2), Enum.Material.CorrodedMetal, COL.Rust, { CanCollide = false })
	local exhaust = part(folder, "PontaEscape", Vector3.new(0.9, 0.5, 0.9), anchorCF * CFrame.new(2.6, 6.3, 1.2), Enum.Material.CorrodedMetal, COL.Rust, { CanCollide = false })
	exhaust:SetAttribute("EscapeGerador", true)
	out.Escape = exhaust

	-- Bocal de combustível (interação: abastecer).
	local filler = part(folder, "BocalCombustivel", Vector3.new(1.5, 0.9, 1.5), anchorCF * CFrame.new(-1.6, 4.2, -1.1), Enum.Material.Metal, COL.FuelRed, {
		Shape = Enum.PartType.Cylinder,
		CanCollide = false,
	})
	filler.Orientation = filler.Orientation + Vector3.new(0, 0, 90)
	filler:SetAttribute("InteracaoRadio", "Abastecer")
	part(folder, "TanqueGerador", Vector3.new(4.4, 1.2, 2.6), anchorCF * CFrame.new(-0.4, 3.7, -1.1), Enum.Material.Metal, COL.SteelDark, DECO)
	out.Bocal = filler

	-- Painel de partida (interação: ligar).
	local starter = part(folder, "PartidaGerador", Vector3.new(2.2, 2.4, 0.6), anchorCF * CFrame.new(1.4, 2.6, -2), Enum.Material.Metal, COL.Panel)
	starter:SetAttribute("InteracaoRadio", "Partida")
	part(folder, "ChavePartida", Vector3.new(0.5, 0.5, 0.3), anchorCF * CFrame.new(1.4, 3.1, -2.35), Enum.Material.Metal, COL.Galvanized, {
		Shape = Enum.PartType.Cylinder,
		CanCollide = false,
		CastShadow = false,
	})
	local led = part(folder, "LedPartida", Vector3.new(0.3, 0.3, 0.2), anchorCF * CFrame.new(2, 2.1, -2.35), Enum.Material.Neon, COL.Red, {
		Shape = Enum.PartType.Ball,
		CanCollide = false,
		CastShadow = false,
	})
	led:SetAttribute("LuzRadio", true)
	out.Partida = starter

	warningSign(folder, "PlacaGerador", anchorCF * CFrame.new(-2.6, 2.6, -2.2), 2.6, 1.8, "INFLAMÁVEL", "NÃO OPERE SEM VENTILAÇÃO")
	return out
end

local function buildFuel(parent: Instance, cf: CFrame, geradorPos: Vector3): { BasePart }
	local folder = Instance.new("Folder")
	folder.Name = "Combustivel"
	folder.Parent = parent
	local cans: { BasePart } = {}

	-- Bacia de contenção (mureta baixa em volta).
	part(folder, "PisoContencao", Vector3.new(14, 0.5, 10), cf * CFrame.new(0, 0.25, 0), Enum.Material.Concrete, COL.ConcreteDark)
	for _, z in { -4.75, 4.75 } do
		part(folder, "MuretaContencao", Vector3.new(14, 1.4, 0.6), cf * CFrame.new(0, 0.9, z), Enum.Material.Concrete, COL.Concrete)
	end
	for _, x in { -6.7, 6.7 } do
		part(folder, "MuretaContencao", Vector3.new(0.6, 1.4, 10), cf * CFrame.new(x, 0.9, 0), Enum.Material.Concrete, COL.Concrete)
	end

	-- Tanque horizontal sobre cavaletes.
	for _, sx in { -2.6, 2.6 } do
		part(folder, "Cavalete", Vector3.new(1, 2.4, 4.4), cf * CFrame.new(sx, 1.7, 0), Enum.Material.Metal, COL.SteelDark)
	end
	part(folder, "TanqueCombustivel", Vector3.new(9, 4.4, 4.4), cf * CFrame.new(0, 4.1, 0) * CFrame.Angles(0, 0, math.rad(90)), Enum.Material.Metal, COL.Tank, {
		Shape = Enum.PartType.Cylinder,
	})
	part(folder, "TampaTanque", Vector3.new(0.7, 1.1, 1.1), cf * CFrame.new(-1.5, 6.4, 0) * CFrame.Angles(0, 0, math.rad(90)), Enum.Material.Metal, COL.FuelRed, {
		Shape = Enum.PartType.Cylinder,
		CanCollide = false,
	})
	local gauge = part(folder, "NivelTanque", Vector3.new(0.3, 2.6, 0.3), cf * CFrame.new(4.4, 4.4, 1.2), Enum.Material.Glass, Color3.fromRGB(190, 160, 90), DECO)
	gauge.Transparency = 0.35
	warningSign(folder, "PlacaCombustivel", cf * CFrame.new(0, 4.4, -2.35), 5, 2.4, "DIESEL — INFLAMÁVEL", "PROIBIDO FOGO E FAÍSCA")

	-- Mangueira do tanque indo pro lado do gerador.
	cableRun(folder, "Mangueira", (cf * CFrame.new(-1.5, 5.6, 0)).Position, geradorPos + Vector3.new(0, 1.2, 0), 1.2, 0.28, COL.HazardDark)

	-- Galões: é o que o jogador despeja no gerador.
	for i = 1, 3 do
		local can = part(folder, "GalaoCombustivel_" .. i, Vector3.new(1.7, 2.4, 1.1), cf * CFrame.new(-4.6 + (i - 1) * 1.9, 1.7, -3.2) * CFrame.Angles(0, math.rad(-8 + i * 7), 0), Enum.Material.Metal, COL.FuelRed)
		can:SetAttribute("GalaoCombustivel", true)
		can:SetAttribute("Cheio", true)
		part(folder, "AlcaGalao_" .. i, Vector3.new(1.1, 0.25, 0.25), can.CFrame * CFrame.new(0, 1.3, 0), Enum.Material.Metal, COL.SteelDark, DECO)
		part(folder, "BicoGalao_" .. i, Vector3.new(0.35, 0.8, 0.35), can.CFrame * CFrame.new(0.6, 1.2, 0.3) * CFrame.Angles(math.rad(25), 0, 0), Enum.Material.Metal, COL.HazardDark, DECO)
		table.insert(cans, can)
	end
	return cans
end

-- Quadro de fusíveis, bateria reserva e todo o cabeamento visível.
local function buildPower(parent: Instance, boxCF: CFrame, palletCF: CFrame, shelter: { [string]: BasePart }, gerador: { [string]: BasePart }, towerBase: Vector3): BasePart
	local folder = Instance.new("Folder")
	folder.Name = "Eletrica"
	folder.Parent = parent

	-- Caixa de fusíveis na parede externa do abrigo, do lado da porta.
	local box = part(folder, "CaixaFusiveis", Vector3.new(2.6, 3.2, 1), boxCF, Enum.Material.Metal, COL.Galvanized)
	box:SetAttribute("InteracaoRadio", "Fusivel")
	part(folder, "TampaFusiveis", Vector3.new(2.4, 3, 0.12), boxCF * CFrame.new(0.1, 0, -0.62) * CFrame.Angles(0, math.rad(-38), 0), Enum.Material.Metal, COL.SteelDark, { CanCollide = false })
	-- Soquete vazio: dá pra ver que falta o fusível.
	part(folder, "SoqueteVazio", Vector3.new(0.6, 0.6, 0.5), boxCF * CFrame.new(0, 0.4, -0.45), Enum.Material.SmoothPlastic, COL.HazardDark, DECO)
	for i = 1, 3 do
		part(folder, "FusivelOk_" .. i, Vector3.new(0.4, 0.4, 1), boxCF * CFrame.new(-0.8 + (i - 1) * 0.55, -0.6, -0.4) * CFrame.Angles(0, 0, math.rad(90)), Enum.Material.Glass, COL.Copper, DECO)
	end
	warningSign(folder, "PlacaChoque", boxCF * CFrame.new(0, 2.3, -0.55), 2.4, 1.4, "ALTA TENSÃO", nil, COL.Hazard)

	-- Bateria reserva num estrado, ao lado da caixa.
	local pallet = palletCF
	part(folder, "Estrado", Vector3.new(4.4, 0.5, 3), pallet, Enum.Material.Wood, Color3.fromRGB(96, 76, 52))
	for i = 1, 2 do
		local batt = part(folder, "BateriaReserva_" .. i, Vector3.new(1.8, 1.5, 2.2), pallet * CFrame.new(-1 + (i - 1) * 2, 1, 0), Enum.Material.SmoothPlastic, Color3.fromRGB(58, 72, 58))
		part(folder, "PoloMais_" .. i, Vector3.new(0.3, 0.3, 0.3), batt.CFrame * CFrame.new(-0.5, 0.85, 0), Enum.Material.Metal, COL.Red, {
			Shape = Enum.PartType.Cylinder,
			CanCollide = false,
			CastShadow = false,
		})
		part(folder, "PoloMenos_" .. i, Vector3.new(0.3, 0.3, 0.3), batt.CFrame * CFrame.new(0.5, 0.85, 0), Enum.Material.Metal, COL.SteelDark, {
			Shape = Enum.PartType.Cylinder,
			CanCollide = false,
			CastShadow = false,
		})
	end

	-- Cabos: gerador -> caixa de fusíveis -> abrigo -> base da torre.
	local corpo = gerador.Corpo
	cableRun(folder, "CaboForca", corpo.Position + Vector3.new(0, 1.4, 0), box.Position + Vector3.new(0, -1, 0), 1.6, 0.3, COL.Cable)
	cableRun(folder, "CaboComando", corpo.Position + Vector3.new(0.6, 1.2, 0), box.Position + Vector3.new(0.6, -1.4, 0), 1.9, 0.16, COL.Cable)
	cableRun(folder, "CaboAbrigo", box.Position + Vector3.new(0, 1.4, 0), shelter.Painel.Position + Vector3.new(0, 2.4, 0), 0.8, 0.26, COL.Cable)
	cableRun(folder, "CaboAntena", shelter.Rack.Position + Vector3.new(0, 3.6, 0), towerBase + Vector3.new(0, 6, 0), 2.6, 0.22, COL.Cable)

	-- Eletroduto rígido subindo a parede + haste de aterramento.
	part(folder, "Eletroduto", Vector3.new(0.32, 4.2, 0.32), boxCF * CFrame.new(1.6, 2.2, 0.2), Enum.Material.Metal, COL.Galvanized, DECO)
	part(folder, "HasteTerra", Vector3.new(0.22, 2.4, 0.22), boxCF * CFrame.new(2.4, -2.4, 1.4), Enum.Material.Metal, COL.Copper, DECO)
	return box
end

--------------------------------------------------------------------------------
-- Cerca, portão e iluminação do pátio
--------------------------------------------------------------------------------

--[[
	fenceRun(folder, cf, from, to)
	Um trecho reto de alambrado: postes, malha (arames horizontais e
	verticais), arame farpado inclinado no topo e -- o que faltava -- uma
	BARREIRA INVISÍVEL que colide de verdade.

	A malha inteira é decoração (CanCollide = false): fio de 0,09 stud não é
	colisor confiável e, na primeira versão, só os postes colidiam -- dava pra
	atravessar a cerca andando entre eles. A barreira é uma Part só, alta o
	bastante (Fence.Height) pra não ser pulada.
]]
local function fenceRun(folder: Instance, cf: CFrame, from: Vector2, to: Vector2)
	local F = CONFIG.Fence
	local a = (cf * CFrame.new(from.X, 0, from.Y)).Position
	local b = (cf * CFrame.new(to.X, 0, to.Y)).Position
	local len = (b - a).Magnitude
	if len < 1 then
		return
	end
	local mid = CFrame.lookAt((a + b) * 0.5, b)

	-- A cerca de verdade: invisível, sólida, do chão até o topo.
	local barrier = part(folder, "BarreiraCerca", Vector3.new(0.5, F.Height, len), mid * CFrame.new(0, F.Height / 2, 0), Enum.Material.Metal, COL.SteelDark, {
		Transparency = 1,
		CastShadow = false,
	})
	barrier.CanQuery = false -- não atrapalha os raycasts dos sistemas

	local posts = math.max(1, math.round(len / F.PostSpacing))
	for i = 0, posts do
		local p = a:Lerp(b, i / posts)
		part(folder, "PosteCerca", Vector3.new(0.5, F.Height, 0.5), CFrame.new(p + Vector3.new(0, F.Height / 2, 0)), Enum.Material.Metal, COL.Galvanized, { CastShadow = false })
		-- Braço inclinado que segura o arame farpado.
		part(folder, "BracoFarpado", Vector3.new(0.24, 1.6, 0.24), CFrame.new(p + Vector3.new(0, F.Height + 0.5, 0)) * CFrame.Angles(math.rad(28), 0, 0), Enum.Material.Metal, COL.Galvanized, DECO)
	end

	-- Malha: horizontais de cima a baixo + verticais no espaçamento da tela.
	for i = 1, 6 do
		local y = F.Height * (i / 7)
		part(folder, "ArameHorizontal", Vector3.new(0.1, 0.1, len), mid * CFrame.new(0, y, 0), Enum.Material.Metal, COL.SteelDark, DECO)
	end
	local verticals = math.max(1, math.floor(len / F.MeshSpacing))
	for i = 0, verticals do
		local z = -len / 2 + (len / verticals) * i
		part(folder, "ArameVertical", Vector3.new(0.08, F.Height, 0.08), mid * CFrame.new(0, F.Height / 2, z), Enum.Material.Metal, COL.SteelDark, DECO)
	end

	for i = 1, 3 do
		part(folder, "ArameFarpado", Vector3.new(0.07, 0.07, len), mid * CFrame.new(0, F.Height + 0.4 + i * 0.35, -i * 0.32), Enum.Material.Metal, COL.Rust, DECO)
	end
end

local function buildFence(parent: Instance, cf: CFrame): { [string]: BasePart }
	local folder = Instance.new("Folder")
	folder.Name = "Cerca"
	folder.Parent = parent

	local F = CONFIG.Fence
	local hw, hd = CONFIG.Yard.Width / 2, CONFIG.Yard.Depth / 2
	local gate = F.GateWidth
	local out: { [string]: BasePart } = {}

	-- Frente (-Z): dois trechos, com o portão no meio.
	fenceRun(folder, cf, Vector2.new(-hw, -hd), Vector2.new(-gate / 2, -hd))
	fenceRun(folder, cf, Vector2.new(gate / 2, -hd), Vector2.new(hw, -hd))
	-- Fundo (+Z) e lateral esquerda (-X), inteiras.
	fenceRun(folder, cf, Vector2.new(-hw, hd), Vector2.new(hw, hd))
	fenceRun(folder, cf, Vector2.new(-hw, -hd), Vector2.new(-hw, hd))
	-- Lateral direita (+X): tem um rasgo. É a rota que o Monstro usa pra
	-- entrar sem passar pelo portão -- e a fuga de quem está preso.
	fenceRun(folder, cf, Vector2.new(hw, -hd), Vector2.new(hw, F.GapFrom))
	fenceRun(folder, cf, Vector2.new(hw, F.GapTo), Vector2.new(hw, hd))
	-- Tela arrebentada caída no chão marcando o rasgo.
	for i = 1, 3 do
		local z = F.GapFrom + (F.GapTo - F.GapFrom) * (i / 4)
		part(folder, "CercaCaida_" .. i, Vector3.new(5, 0.2, 6), cf * CFrame.new(hw - 2 + i * 0.8, 0.2, z) * CFrame.Angles(0, math.rad(i * 9), math.rad(3)), Enum.Material.Metal, COL.Rust, { CanCollide = false })
	end
	part(folder, "PosteTorto", Vector3.new(0.5, F.Height, 0.5), cf * CFrame.new(hw + 0.6, 2.8, F.GapFrom + 1) * CFrame.Angles(math.rad(62), 0, 0), Enum.Material.Metal, COL.Rust, { CastShadow = false })

	-- Portão de duas folhas (DoorSystem abre/fecha). Tão alto quanto a cerca:
	-- de nada adianta a barreira se dá pra pular por cima do portão.
	local leafH = F.Height - 0.5
	for i, side in { -1, 1 } do
		local leafW = gate / 2
		local leafCF = cf * CFrame.new(side * (gate / 4), leafH / 2, -hd)
		local leaf = part(folder, "Porta", Vector3.new(leafW, leafH, 0.3), leafCF, Enum.Material.Metal, COL.Galvanized)
		leaf:SetAttribute("Porta", true)
		leaf:SetAttribute("PortaAberta", false)
		leaf:SetAttribute("CFrameFechada", leafCF)
		leaf:SetAttribute("LarguraPorta", leafW)
		for k = 1, 5 do
			part(folder, "BarraPortao", Vector3.new(0.2, leafH - 0.4, 0.2), leafCF * CFrame.new(-leafW / 2 + k * (leafW / 6), 0, -0.22), Enum.Material.Metal, COL.SteelDark, DECO)
		end
		out["Folha" .. i] = leaf
	end
	-- Pilares do portão.
	for _, sx in { -gate / 2 - 0.5, gate / 2 + 0.5 } do
		part(folder, "PilarPortao", Vector3.new(1.2, F.Height + 1.5, 1.2), cf * CFrame.new(sx, (F.Height + 1.5) / 2, -hd), Enum.Material.Concrete, COL.Concrete)
	end

	-- Placas: portão, frente e as duas laterais.
	warningSign(folder, "PlacaPortao", cf * CFrame.new(0, F.Height + 1.4, -hd - 0.4), 8, 3, "ESTAÇÃO REPETIDORA", "ÁREA RESTRITA — PROIBIDA A ENTRADA")
	warningSign(folder, "PlacaAltaTensao", cf * CFrame.new(-hw * 0.5, 4.6, -hd - 0.35), 4, 2.8, "PERIGO", "ALTA TENSÃO")
	warningSign(folder, "PlacaRisco", cf * CFrame.new(hw * 0.55, 4.6, -hd - 0.35), 4, 2.8, "RISCO DE CHOQUE", "NÃO TOQUE NOS CABOS")
	warningSign(folder, "PlacaLateral", cf * CFrame.new(-hw - 0.35, 4.6, 0) * CFrame.Angles(0, math.rad(-90), 0), 4, 2.8, "PERIGO", "ALTA TENSÃO")
	return out
end

local function buildYardLighting(parent: Instance, cf: CFrame)
	local folder = Instance.new("Folder")
	folder.Name = "Iluminacao"
	folder.Parent = parent

	-- Quatro cantos: o pátio é grande demais pra dois holofotes cobrirem.
	-- Cada um aponta pro centro, então as sombras caem pra fora -- quem está
	-- no meio do pátio fica bem visível, que é o ponto.
	local hw, hd = CONFIG.Yard.Width / 2 - 6, CONFIG.Yard.Depth / 2 - 6
	local spots = {
		Vector2.new(-hw, -hd),
		Vector2.new(hw, -hd),
		Vector2.new(-hw, hd),
		Vector2.new(hw, hd),
	}
	for i, spot in spots do
		local base = cf * CFrame.new(spot.X, 0, spot.Y)
		-- Cabeça virada pro centro do pátio.
		local yaw = math.atan2(-spot.X, -spot.Y)
		part(folder, "BasePoste_" .. i, Vector3.new(2, 0.6, 2), base * CFrame.new(0, 0.3, 0), Enum.Material.Concrete, COL.Concrete)
		part(folder, "PosteLuz_" .. i, Vector3.new(0.55, 17, 0.55), base * CFrame.new(0, 8.5, 0), Enum.Material.Metal, COL.Galvanized)
		local head = part(folder, "Holofote_" .. i, Vector3.new(2.6, 1.1, 1.8), base * CFrame.new(0, 16.8, 0) * CFrame.Angles(0, yaw, 0) * CFrame.new(0, 0, -0.7) * CFrame.Angles(math.rad(-40), 0, 0), Enum.Material.Metal, COL.SteelDark, { CanCollide = false })
		poweredLight(head, Color3.fromRGB(255, 238, 206), 3.4, 70, true)
		cableRun(folder, "CaboPoste_" .. i, base.Position + Vector3.new(0, 16, 0), base.Position + Vector3.new(0, 0.6, 0), 0, 0.12, COL.Cable)
	end
end

--------------------------------------------------------------------------------
-- Equipamento que preenche o pátio
--------------------------------------------------------------------------------

-- Transformador no pátio: o que baixa a tensão do gerador pro abrigo.
local function buildTransformer(parent: Instance, cf: CFrame)
	local folder = Instance.new("Folder")
	folder.Name = "Transformador"
	folder.Parent = parent

	part(folder, "BaseTrafo", Vector3.new(8, 0.6, 6), cf * CFrame.new(0, 0.3, 0), Enum.Material.Concrete, COL.Concrete)
	local body = part(folder, "CorpoTrafo", Vector3.new(5, 4.4, 3.6), cf * CFrame.new(0, 2.8, 0), Enum.Material.Metal, Color3.fromRGB(96, 102, 98))
	for i = 1, 6 do
		part(folder, "AletaTrafo_" .. i, Vector3.new(0.25, 3.4, 1.2), cf * CFrame.new(-2.5, 2.8, -1.6 + i * 0.5), Enum.Material.Metal, COL.SteelDark, DECO)
		part(folder, "AletaTrafo2_" .. i, Vector3.new(0.25, 3.4, 1.2), cf * CFrame.new(2.5, 2.8, -1.6 + i * 0.5), Enum.Material.Metal, COL.SteelDark, DECO)
	end
	-- Buchas de porcelana em cima.
	for i = 1, 3 do
		part(folder, "Bucha_" .. i, Vector3.new(1.1, 0.9, 0.9), cf * CFrame.new(-1.6 + (i - 1) * 1.6, 5.5, 0) * CFrame.Angles(0, 0, math.rad(90)), Enum.Material.Marble, Color3.fromRGB(180, 174, 160), {
			Shape = Enum.PartType.Cylinder,
			CanCollide = false,
		})
	end
	warningSign(folder, "PlacaTrafo", cf * CFrame.new(0, 2.6, -1.95), 3, 2, "ALTA TENSÃO", "NÃO ABRA")
	return body
end

-- Parabólica montada no chão (enlace ponto-a-ponto da repetidora).
local function buildGroundDish(parent: Instance, cf: CFrame)
	local folder = Instance.new("Folder")
	folder.Name = "Parabolica"
	folder.Parent = parent

	part(folder, "BaseParabolica", Vector3.new(8, 0.6, 8), cf * CFrame.new(0, 0.3, 0), Enum.Material.Concrete, COL.Concrete)
	part(folder, "PedestalParabolica", Vector3.new(1.4, 5, 1.4), cf * CFrame.new(0, 3, 0), Enum.Material.Metal, COL.Galvanized)
	part(folder, "PratoParabolica", Vector3.new(0.6, 9, 9), cf * CFrame.new(0, 6.4, 0) * CFrame.Angles(0, math.rad(-25), 0) * CFrame.Angles(0, 0, math.rad(50)), Enum.Material.SmoothPlastic, COL.Galvanized, {
		Shape = Enum.PartType.Cylinder,
		CanCollide = false,
	})
	part(folder, "BracoAlimentador", Vector3.new(0.3, 3.4, 0.3), cf * CFrame.new(1.4, 8.4, 1.8) * CFrame.Angles(math.rad(-40), 0, 0), Enum.Material.Metal, COL.SteelDark, DECO)
	cableRun(folder, "CaboParabolica", (cf * CFrame.new(0, 1.2, 0)).Position, (cf * CFrame.new(-3.4, 0.4, -3)).Position, 0.3, 0.14, COL.Cable)
end

-- Galpão aberto de manutenção: caixotes, carretéis e um ponto de loot.
local function buildStorageShed(parent: Instance, cf: CFrame, rng: Random)
	local folder = Instance.new("Folder")
	folder.Name = "Deposito"
	folder.Parent = parent

	local W, D, H = 12, 8, 7
	part(folder, "PisoDeposito", Vector3.new(W, 0.5, D), cf * CFrame.new(0, 0.25, 0), Enum.Material.Concrete, COL.ConcreteDark)
	for _, c in { Vector2.new(-1, -1), Vector2.new(1, -1), Vector2.new(1, 1), Vector2.new(-1, 1) } do
		part(folder, "PilarDeposito", Vector3.new(0.5, H, 0.5), cf * CFrame.new(c.X * (W / 2 - 0.5), H / 2, c.Y * (D / 2 - 0.5)), Enum.Material.Metal, COL.Galvanized)
	end
	part(folder, "TelhadoDeposito", Vector3.new(W + 1.5, 0.35, D + 1.5), cf * CFrame.new(0, H + 0.2, 0) * CFrame.Angles(math.rad(4), 0, 0), Enum.Material.CorrodedMetal, COL.Roof)
	-- Fundo fechado (+Z), o resto aberto.
	part(folder, "FundoDeposito", Vector3.new(W, H, 0.4), cf * CFrame.new(0, H / 2, D / 2), Enum.Material.CorrodedMetal, COL.ShelterWall)

	for i = 1, 4 do
		local s = rng:NextNumber(1.8, 3)
		part(folder, "CaixoteDeposito_" .. i, Vector3.new(s, s * 0.8, s), cf * CFrame.new(rng:NextNumber(-4, 4), s * 0.4 + 0.5, rng:NextNumber(-2, 2.5)) * CFrame.Angles(0, rng:NextNumber(0, TAU), 0), Enum.Material.WoodPlanks, COL.Rust)
	end
	-- Carretéis de cabo deitados, do lado de DENTRO do pátio (pra fora eles
	-- cairiam em cima da cerca).
	for i = 1, 2 do
		part(folder, "Carretel_" .. i, Vector3.new(1.2, 5, 5), cf * CFrame.new(W / 2 + 3 + i * 6, 2.5, rng:NextNumber(-2, 2)) * CFrame.Angles(0, rng:NextNumber(0, TAU), 0), Enum.Material.Wood, COL.WoodSpool, {
			Shape = Enum.PartType.Cylinder,
		})
	end
	S.LootPoint(folder, cf * CFrame.new(2.5, 1.4, 1.5))
end

--------------------------------------------------------------------------------
-- Montagem
--------------------------------------------------------------------------------

function RadioTowerGenerator.Clear()
	local ilha = Workspace:FindFirstChild("Ilha")
	if not ilha then
		return
	end
	for _, name in { "TorreDeRadio", "PecasRadioTeste" } do
		local found = ilha:FindFirstChild(name)
		if found then
			found:Destroy()
		end
	end
end

--[[
	Build(seed?)
	Refaz Workspace.Ilha.TorreDeRadio inteira. Em edição guarda a versão
	anterior, terreno e vegetação em ServerStorage.MapEditBackups.
	Em runtime gera apenas as construções, sem modificar o terreno.
]]
function RadioTowerGenerator.Build(seed: number?): Model
	local ilha = getIlha()
	local old = ilha:FindFirstChild("TorreDeRadio")
	-- Regenerar um mapa salvo preserva a localizacao/rotacao da estacao.
	local oldFloor = old and old:FindFirstChild("PisoPatio", true)
	local savedCF = if oldFloor and oldFloor:IsA("BasePart") then oldFloor.CFrame * CFrame.new(0, -0.2, 0) else nil
	local cf, padY = siteCFrame()
	if savedCF then cf, padY = savedCF, savedCF.Position.Y end
	local sculpt = RunService:IsEdit()
	local backup: Folder? = nil
	if sculpt then
		game:GetService("ChangeHistoryService"):SetWaypoint("Antes de ampliar estacao de radio")
		local storage = game:GetService("ServerStorage")
		local backups = storage:FindFirstChild("MapEditBackups")
		if not backups then
			backups = Instance.new("Folder")
			backups.Name = "MapEditBackups"
			backups.Parent = storage
		end
		backup = Instance.new("Folder")
		backup.Name = "Radio_" .. os.date("!%Y%m%d_%H%M%S") .. "_" .. (#backups:GetChildren() + 1)
		backup.Parent = backups
		-- Copia somente a regiao editada do terreno (inclui estrada rotacionada).
		local reach = CONFIG.Yard.Depth / 2 + CONFIG.Road.Length + 12
		local low = cf.Position - Vector3.new(reach, 64, reach)
		local high = cf.Position + Vector3.new(reach, 128, reach)
		local minCell = Vector3int16.new(math.floor(low.X / 4), math.floor(low.Y / 4), math.floor(low.Z / 4))
		local maxCell = Vector3int16.new(math.ceil(high.X / 4), math.ceil(high.Y / 4), math.ceil(high.Z / 4))
		local terrainCopy = Terrain:CopyRegion(Region3int16.new(minCell, maxCell))
		terrainCopy.Name = "TerrenoAnterior"
		terrainCopy:SetAttribute("MinCell", Vector3.new(minCell.X, minCell.Y, minCell.Z))
		terrainCopy.Parent = backup
	end
	if old then
		if backup then old.Parent = backup else old:Destroy() end
	end

	local rng = Random.new(seed or 20240917)

	local model = Instance.new("Model")
	model.Name = "TorreDeRadio"
	model:SetAttribute("Construcao", "Radio")
	model:SetAttribute("EstacaoRadio", true)
	model:SetAttribute("RadioLayoutVersion", 2)
	model.Parent = ilha

	-- Terreno e vegetação só em modo de edição: em runtime este Build é o
	-- fallback do RadioInstallSystem, e um servidor ao vivo não pode sair
	-- reescrevendo terreno nem apagando a floresta embaixo dos jogadores.
	local removed = 0
	if sculpt then
		levelYard(cf)
		removed = clearVegetation(cf, backup)
	end

	-- Piso do pátio: laje de concreto na frente do abrigo + cascalho solto.
	local yard = Instance.new("Folder")
	yard.Name = "Patio"
	yard.Parent = model
	local hw, hd = CONFIG.Yard.Width / 2, CONFIG.Yard.Depth / 2
	local slab = part(yard, "PisoPatio", Vector3.new(CONFIG.Yard.Width - 4, 0.4, CONFIG.Yard.Depth - 4), cf * CFrame.new(0, 0.2, 0), Enum.Material.Ground, COL.Gravel, { CastShadow = false })
	for i = 1, 26 do
		local p = cf * CFrame.new(rng:NextNumber(-hw + 6, hw - 6), 0.42, rng:NextNumber(-hd + 6, hd - 6))
		part(yard, "Cascalho_" .. i, Vector3.new(rng:NextNumber(4, 11), 0.16, rng:NextNumber(4, 11)), p * CFrame.Angles(0, rng:NextNumber(0, TAU), 0), Enum.Material.Pebble, COL.ConcreteDark, DECO)
	end
	-- Pátio de manobra logo depois do portão: é onde o caminhão dava ré.
	-- Para antes da base do gerador, senão a marca atravessa o concreto.
	for _, sx in { -2.6, 2.6 } do
		part(yard, "RodadoPatio", Vector3.new(2.2, 0.18, 14), cf * CFrame.new(sx, 0.44, -hd + 7), Enum.Material.Ground, COL.Gravel, DECO)
	end

	buildRoad(yard, cf, padY, sculpt)
	buildFence(model, cf)
	buildYardLighting(model, cf)

	-- Distribuição pelo pátio inteiro: torre no fundo à direita, abrigo na
	-- frente à esquerda, gerador no meio e combustível no canto oposto ao
	-- abrigo. Ninguém fecha o objetivo sem atravessar o pátio aberto várias
	-- vezes -- e agora com distância de verdade pra ser perseguido no meio.
	local towerCF = cf * CFrame.new(33, 0, 29)
	buildTower(model, towerCF, rng)

	local shelterCF = cf * CFrame.new(-32, 0, -8)
	local shelter = buildShelter(model, shelterCF)

	local geradorCF = cf * CFrame.new(5, 0, -26)
	local gerador = buildGenerator(model, geradorCF)

	buildFuel(model, cf * CFrame.new(43, 0, -29), gerador.Corpo.Position)

	-- Caixa de fusíveis na parede da frente do abrigo, ao lado da porta, com
	-- a bateria reserva no estrado logo embaixo.
	local boxCF = shelterCF * CFrame.new(11, 4.8, -CONFIG.Shelter.Depth / 2 - 0.5)
	local palletCF = shelterCF * CFrame.new(11, 0.55, -CONFIG.Shelter.Depth / 2 - 3.5)
	buildPower(model, boxCF, palletCF, shelter, gerador, towerCF.Position)

	-- Equipamento que ocupa o resto do pátio.
	buildTransformer(model, cf * CFrame.new(10, 0, 0))
	buildGroundDish(model, cf * CFrame.new(53, 0, 8))
	buildStorageShed(model, cf * CFrame.new(-41, 0, 34), rng)

	-- Caminho de pedestres ate a sala tecnica, sem degraus no meio da fuga.
	part(yard, "AcessoAbrigo", Vector3.new(12, 0.1, 22), cf * CFrame.new(-32, 0.47, -37), Enum.Material.Concrete, COL.ConcreteDark, DECO)
	part(yard, "AcessoPortao", Vector3.new(43, 0.1, 8), cf * CFrame.new(-16, 0.47, -48), Enum.Material.Concrete, COL.ConcreteDark, DECO)
	for _, point in { Vector3.new(-22, 0, -40), Vector3.new(-8, 0, -40), Vector3.new(20, 0, -40) } do
		local bollard = part(yard, "BalizadorPatio", Vector3.new(0.65, 2.6, 0.65), cf * CFrame.new(point + Vector3.new(0, 1.3, 0)), Enum.Material.Metal, COL.SteelDark)
		poweredLight(bollard, Color3.fromRGB(255, 217, 158), 0.8, 13)
	end

	-- Prompt de instalação das peças: mesmo nome de sempre, agora no rack
	-- dentro do abrigo (RadioInstallSystem procura por ele).
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "InstalarPeca"
	prompt.ActionText = "Instalar peça"
	prompt.ObjectText = "Rack do transmissor"
	prompt.Enabled = false
	prompt.RequiresLineOfSight = true
	prompt.MaxActivationDistance = 10
	prompt.HoldDuration = 0
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.GamepadKeyCode = Enum.KeyCode.ButtonX
	prompt.ClickablePrompt = true
	prompt.Parent = shelter.Rack

	model.PrimaryPart = slab

	if sculpt then
		game:GetService("ChangeHistoryService"):SetWaypoint("Estacao de radio ampliada")
		print(string.format(
			"[RadioTowerGenerator] Estação de rádio montada em (%.0f, %.0f) -- torre de %d studs, %d objetos de vegetação movidos para ServerStorage.MapEditBackups. Salve o lugar.",
			cf.Position.X, cf.Position.Z, CONFIG.TowerHeight, removed
		))
	else
		warn(string.format(
			"[RadioTowerGenerator] Estação provisória montada em runtime em (%.0f, %.0f), sem terraplanagem. Rode Build() no Studio e salve.",
			cf.Position.X, cf.Position.Z
		))
	end
	return model
end

return RadioTowerGenerator
