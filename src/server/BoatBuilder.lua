--!strict
--[[
	BoatBuilder
	Deixa o barco de fuga pronto pra física (docs/Barco.md). Não decide
	regra nenhuma -- quem manda é o BoatSystem; aqui só tem geometria.

	DE ONDE VEM O BARCO (Find)
	  1. Qualquer Model do Workspace com o Attribute BarcoFuga = true.
	  2. Um Model com nome de barco (GameConfig.Boat.NomesProcurados), com
	     pelo menos um assento, perto do mar -- fora das construções geradas
	     (píer, boias, casa de barcos, barco furado e canoa do Lago).
	  3. Nada? BuildDefault(): uma lancha de console central em Parts,
	     amarrada num píer na praia perto do Farol.

	PREPARO (os dois casos terminam no mesmo Layout)
	  - Todas as Parts soldadas na raiz, soltas (Anchored = false), com os
	    scripts e movers antigos do modelo DESLIGADOS (um barco do Toolbox
	    costuma trazer o próprio BodyVelocity, que brigaria com o nosso).
	  - "QuadroBarco": Attachment na LINHA D'ÁGUA, LookVector = proa. É o
	    referencial de toda a física (BoatPhysics) e dos efeitos.
	  - Atuadores (LinearVelocity + AngularVelocity) no Attachment "Impulso",
	    no centro de massa do conjunto.
	  - Assento do piloto = VehicleSeat (o ControlModule do Roblox já traduz
	    teclado, controle e toque em ThrottleFloat/SteerFloat); passageiros
	    em Seats. CanTouch = false em todos: ninguém senta esbarrando, só
	    pelos prompts (que o servidor valida).
	  - Pontos de interação (motor, tanque, ignição, embarque, empurrar) e
	    Attachments de efeito (esteira, spray, escapamento, farol).
	  - "FiacaoMotor": Model com Sabotavel = true -- o Espião sabota pelo
	    SabotageSystem que já existe, e o Sobrevivente repara pelo minigame.
	  - ModelStreamingMode = Persistent: com StreamingEnabled, o barco (e os
	    Attributes de estado dele) existe em TODO cliente, perto ou longe.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local BoatPhysics = require(ReplicatedStorage.Modules.BoatPhysics)
local Layout = require(script.Parent.Tools.IslandLayout)

local BoatBuilder = {}

export type Layout = {
	model: Model,
	root: BasePart,
	frame: Attachment,
	helm: VehicleSeat,
	seats: { Seat },
	anchors: { [string]: BasePart },
	lights: { Light },
	glow: { BasePart },
	visuals: { [string]: { BasePart } },
	moorings: { Beam },
	wiring: Model,
	home: CFrame,
	length: number,
	width: number,
	isDefault: boolean,
	itemSpots: { CFrame },
}

local COL = {
	Hull = Color3.fromRGB(236, 236, 231),
	Stripe = Color3.fromRGB(24, 46, 84),
	Bottom = Color3.fromRGB(96, 34, 30),
	Deck = Color3.fromRGB(196, 194, 186),
	Cushion = Color3.fromRGB(226, 216, 194),
	Steel = Color3.fromRGB(196, 199, 204),
	Dark = Color3.fromRGB(30, 32, 36),
	Engine = Color3.fromRGB(26, 28, 31),
	EngineAccent = Color3.fromRGB(178, 36, 30),
	Glass = Color3.fromRGB(150, 186, 204),
	Rope = Color3.fromRGB(186, 160, 112),
	Wood = Color3.fromRGB(104, 76, 50),
	WoodDark = Color3.fromRGB(74, 54, 36),
	BuoyRed = Color3.fromRGB(196, 44, 34),
	BuoyWhite = Color3.fromRGB(236, 234, 226),
	Lamp = Color3.fromRGB(255, 196, 72),
}

local UPRIGHT = CFrame.Angles(0, 0, math.pi / 2) -- cilindro de pé (eixo X -> Y)
-- Spray de proa: LookVector pra fora e pra trás, levantado 25° (o efeito
-- emite pela frente do Attachment).
local SPRAY_PORT = CFrame.Angles(0, math.rad(115), 0) * CFrame.Angles(math.rad(25), 0, 0)
local SPRAY_STARBOARD = CFrame.Angles(0, math.rad(-115), 0) * CFrame.Angles(math.rad(25), 0, 0)

--------------------------------------------------------------------------------
-- Primitivas
--------------------------------------------------------------------------------

type PartOpts = {
	shape: Enum.PartType?,
	collide: boolean?,
	transparency: number?,
	reflectance: number?,
	shadow: boolean?,
}

local function style(p: BasePart, material: Enum.Material, color: Color3, opts: PartOpts?)
	p.Material = material
	p.Color = color
	p.Anchored = true
	p.CanCollide = if opts and opts.collide ~= nil then opts.collide else true
	p.Transparency = if opts and opts.transparency then opts.transparency else 0
	p.Reflectance = if opts and opts.reflectance then opts.reflectance else 0
	p.CastShadow = if opts and opts.shadow ~= nil then opts.shadow else true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
end

local function part(parent: Instance, name: string, size: Vector3, cf: CFrame, material: Enum.Material, color: Color3, opts: PartOpts?): Part
	local p = Instance.new("Part")
	p.Name = name
	if opts and opts.shape then
		p.Shape = opts.shape
	end
	p.Size = size
	p.CFrame = cf
	style(p, material, color, opts)
	p.Parent = parent
	return p
end

local function wedge(parent: Instance, name: string, size: Vector3, cf: CFrame, material: Enum.Material, color: Color3, opts: PartOpts?): WedgePart
	local w = Instance.new("WedgePart")
	w.Name = name
	w.Size = size
	w.CFrame = cf
	style(w, material, color, opts)
	w.Parent = parent
	return w
end

-- Cilindro entre dois pontos (tubos, estais, estacas).
local function rod(parent: Instance, name: string, a: Vector3, b: Vector3, dia: number, material: Enum.Material, color: Color3, opts: PartOpts?): Part?
	local delta = b - a
	local len = delta.Magnitude
	if len < 0.05 then
		return nil
	end
	local axis = delta.Unit
	local up = axis:Cross(Vector3.new(0, 1, 0))
	if up.Magnitude < 1e-3 then
		up = Vector3.new(1, 0, 0)
	end
	local cf = CFrame.fromMatrix((a + b) * 0.5, axis, up.Unit)
	local merged: PartOpts = { shape = Enum.PartType.Cylinder }
	if opts then
		merged.collide = opts.collide
		merged.transparency = opts.transparency
		merged.reflectance = opts.reflectance
		merged.shadow = opts.shadow
	end
	return part(parent, name, Vector3.new(len, dia, dia), cf, material, color, merged)
end

-- Ponto invisível de interação/efeito (âncora de ProximityPrompt).
local function marker(parent: Instance, name: string, cf: CFrame): Part
	local m = part(parent, name, Vector3.new(0.8, 0.8, 0.8), cf, Enum.Material.SmoothPlastic, Color3.new(1, 1, 1),
		{ collide = false, transparency = 1, shadow = false })
	m.CanQuery = false
	m.CanTouch = false
	m.Massless = true
	return m
end

local function pointLight(parent: Instance, color: Color3, range: number, brightness: number): PointLight
	local light = Instance.new("PointLight")
	light.Color = color
	light.Range = range
	light.Brightness = brightness
	light.Shadows = false
	light.Enabled = false
	light.Parent = parent
	return light
end

local function attachmentAt(root: BasePart, name: string, world: CFrame): Attachment
	local existing = root:FindFirstChild(name)
	if existing then
		existing:Destroy()
	end
	local a = Instance.new("Attachment")
	a.Name = name
	a.CFrame = root.CFrame:ToObjectSpace(world)
	a.Parent = root
	return a
end

local function flat(v: Vector3): Vector3
	local f = Vector3.new(v.X, 0, v.Z)
	if f.Magnitude < 1e-3 then
		return Vector3.new(0, 0, -1)
	end
	return f.Unit
end

local function getIlha(): Instance
	local ilha = Workspace:FindFirstChild("Ilha")
	if ilha then
		return ilha
	end
	local folder = Instance.new("Folder")
	folder.Name = "Ilha"
	folder.Parent = Workspace
	return folder
end

--------------------------------------------------------------------------------
-- Terreno
--------------------------------------------------------------------------------

local terrainRay = RaycastParams.new()
terrainRay.FilterType = Enum.RaycastFilterType.Include
terrainRay.FilterDescendantsInstances = { Workspace.Terrain }
terrainRay.IgnoreWater = true

local function groundAt(x: number, z: number): (number?, Enum.Material)
	local hit = Workspace:Raycast(Vector3.new(x, 400, z), Vector3.new(0, -900, 0), terrainRay)
	if hit then
		return hit.Position.Y, hit.Material
	end
	return nil, Enum.Material.Air
end

local function seaLevel(): number
	return Layout.CONFIG.SeaLevel
end

--[[
	findShore(angle)
	Anda da água pra terra ao longo do raio `angle` e devolve o primeiro
	ponto de AREIA seca (acima do mar) e a direção pro mar. Exige água funda
	logo à frente (pro barco não nascer encalhado) e areia firme atrás (pra
	ponta do píer).
]]
local function findShore(angle: number): (Vector3?, Vector3?)
	local sea = seaLevel()
	local dir = Vector3.new(math.cos(angle), 0, math.sin(angle))
	local coast = Layout.CoastRadiusAt(angle)
	for dist = coast + 24, coast - 40, -2 do
		local x, z = dir.X * dist, dir.Z * dist
		local y, material = groundAt(x, z)
		if y and y > sea + 1 then
			if material ~= Enum.Material.Sand then
				return nil, nil -- costa de pedra/grama: tenta outro ângulo
			end
			local innerY = groundAt(x - dir.X * 6, z - dir.Z * 6)
			local farWater = groundAt(x + dir.X * 26, z + dir.Z * 26)
			if innerY and innerY > sea + 1 and (farWater == nil or farWater < sea - 3) then
				return Vector3.new(x, y, z), dir
			end
			return nil, nil
		end
	end
	return nil, nil
end

-- Ponto de praia pro píer: perto do Farol (marco que o jogador acha no
-- mapa), mas fora da ponta rochosa dele. Sem Farol, 90° do rádio.
local function findDockSpot(): (Vector3?, Vector3?)
	Layout.Plan()
	local farol = Layout.Site("Farol")
	local radio = Layout.Site("Radio")
	local baseAngle = if farol then math.atan2(farol.z, farol.x)
		elseif radio then math.atan2(radio.z, radio.x) + math.pi / 2
		else (Layout.Seed() % 360) * math.pi / 180
	for i = 1, 30 do
		-- Leque: +7°, -7°, +14°, -14°... (o próprio Farol fica de fora).
		local step = math.ceil(i / 2) * 7
		local offset = math.rad(if i % 2 == 1 then step else -step)
		local spot, dir = findShore(baseAngle + offset)
		if spot and dir then
			return spot, dir
		end
	end
	return nil, nil
end

--------------------------------------------------------------------------------
-- Acha o barco do mapa
--------------------------------------------------------------------------------

local function isGeneratedDecor(instance: Instance): boolean
	local ilha = Workspace:FindFirstChild("Ilha")
	local pois = ilha and ilha:FindFirstChild("POIs")
	return pois ~= nil and instance:IsDescendantOf(pois)
end

local function nameMatches(name: string, hints: { string }): boolean
	local lower = string.lower(name)
	for _, hint in hints do
		if string.find(lower, string.lower(hint), 1, true) then
			return true
		end
	end
	return false
end

local function nearSea(model: Model): boolean
	Layout.Plan()
	local pos = model:GetPivot().Position
	local _, _, inland = Layout.IslandInfo(pos.X, pos.Z)
	return inland < 45
end

local function isCharacter(model: Model): boolean
	return model:FindFirstChildOfClass("Humanoid") ~= nil or Players:GetPlayerFromCharacter(model) ~= nil
end

-- Construções com "barco" no nome que NÃO são barco: o píer e as boias que
-- este módulo monta, a casa de barcos do Lago e os barcos de enfeite.
local NOT_A_BOAT: { [string]: boolean } = {
	PierBarco = true,
	LimiteFuga = true,
	ItensBarco = true,
	CasaDeBarcos = true,
	BarcoVirado = true,
	Canoa = true,
}

-- Achar pelo NOME é só um palpite (o Attribute é o jeito certo), então
-- exige cara de barco pilotável: pelo menos um assento.
local function looksLikeEscapeBoat(model: Model, cfg: any): boolean
	if NOT_A_BOAT[model.Name] or model:GetAttribute("Construcao") ~= nil or isCharacter(model)
		or isGeneratedDecor(model) or not nameMatches(model.Name, cfg.NomesProcurados) then
		return false
	end
	if not model:FindFirstChildWhichIsA("VehicleSeat", true) and not model:FindFirstChildWhichIsA("Seat", true) then
		return false
	end
	return nearSea(model)
end

function BoatBuilder.Find(cfg: any): Model?
	for _, d in Workspace:GetDescendants() do
		if d:IsA("Model") and d:GetAttribute("BarcoFuga") == true and not isCharacter(d) then
			return d
		end
	end

	local best: Model? = nil
	local bestVolume = 0
	for _, d in Workspace:GetDescendants() do
		if d:IsA("Model") and looksLikeEscapeBoat(d, cfg) then
			local _, size = d:GetBoundingBox()
			local volume = size.X * size.Y * size.Z
			-- Maior candidato (um barco bem maior que um remo solto), mas não
			-- uma pasta inteira de mapa por engano.
			if volume > bestVolume and volume < 400000 and d:FindFirstChildWhichIsA("BasePart", true) then
				best, bestVolume = d, volume
			end
		end
	end
	return best
end

--------------------------------------------------------------------------------
-- Preparo comum (qualquer barco)
--------------------------------------------------------------------------------

local function silenceLegacy(model: Model)
	for _, d in model:GetDescendants() do
		if d:IsA("Script") or d:IsA("LocalScript") then
			if d.Enabled then
				d.Enabled = false
				warn(string.format("[Barco] Script '%s' do modelo desligado -- o BoatSystem controla o barco.", d:GetFullName()))
			end
		elseif d:IsA("BodyMover") then
			d:Destroy()
		elseif d:IsA("LinearVelocity") or d:IsA("AngularVelocity") or d:IsA("VectorForce") or d:IsA("AlignPosition")
			or d:IsA("AlignOrientation") or d:IsA("Torque") or d:IsA("LineForce") then
			if d.Name ~= BoatPhysics.LinearName and d.Name ~= BoatPhysics.AngularName then
				(d :: Constraint).Enabled = false
			end
		end
	end
end

local function weldAll(model: Model, root: BasePart)
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") and d ~= root then
			local weld = Instance.new("WeldConstraint")
			weld.Name = "SoldaBarco"
			weld.Part0 = root
			weld.Part1 = d
			weld.Parent = d
		end
	end
end

local function release(model: Model)
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			d.Anchored = false
		end
	end
end

local function createActuators(root: BasePart, frame: Attachment)
	for _, name in { BoatPhysics.LinearName, BoatPhysics.AngularName } do
		local old = root:FindFirstChild(name)
		if old then
			old:Destroy()
		end
	end
	local linear = Instance.new("LinearVelocity")
	linear.Name = BoatPhysics.LinearName
	linear.Attachment0 = frame
	linear.RelativeTo = Enum.ActuatorRelativeTo.World
	linear.VelocityConstraintMode = Enum.VelocityConstraintMode.Vector
	linear.ForceLimitsEnabled = true
	linear.ForceLimitMode = Enum.ForceLimitMode.PerAxis
	linear.MaxAxesForce = Vector3.new(0, 0, 0) -- a primeira passada do BoatPhysics define
	linear.VectorVelocity = Vector3.zero
	linear.Parent = root

	local angular = Instance.new("AngularVelocity")
	angular.Name = BoatPhysics.AngularName
	angular.Attachment0 = frame
	angular.RelativeTo = Enum.ActuatorRelativeTo.World
	angular.MaxTorque = 0
	angular.AngularVelocity = Vector3.zero
	angular.ReactionTorqueEnabled = false
	angular.Parent = root
end

local function configureSeat(seat: Seat | VehicleSeat)
	seat.CanTouch = false -- sentar só pelo prompt
	seat.Disabled = false
	if seat:IsA("VehicleSeat") then
		seat.HeadsUpDisplay = false
		seat.MaxSpeed = 0
		seat.Torque = 0
		seat.TurnSpeed = 0
	end
end

-- Fiação do motor: alvo de sabotagem. Attributes ANTES do Parent, porque o
-- SabotageSystem descobre alvos por DescendantAdded.
local function buildWiring(model: Model, cf: CFrame): Model
	local wiring = Instance.new("Model")
	wiring.Name = "FiacaoMotor"
	wiring:SetAttribute("Sabotavel", true)
	wiring:SetAttribute("Sabotado", false)
	local box = part(wiring, "CaixaFiacao", Vector3.new(0.9, 0.55, 0.35), cf, Enum.Material.SmoothPlastic, COL.Dark)
	box.CanCollide = false
	box.Massless = true
	local cable = part(wiring, "Chicote", Vector3.new(0.12, 1.2, 0.12), cf * CFrame.new(0, -0.8, 0),
		Enum.Material.SmoothPlastic, COL.EngineAccent, { collide = false })
	cable.Massless = true
	wiring.PrimaryPart = box
	wiring.Parent = model
	return wiring
end

local function finalize(layout: Layout)
	local model = layout.model
	model:SetAttribute("BarcoFuga", true)
	model:SetAttribute("Comprimento", layout.length)
	model:SetAttribute("Largura", layout.width)
	model:SetAttribute("FaseOnda", (layout.home.Position.X * 0.37 + layout.home.Position.Z * 0.11) % (math.pi * 2))
	model:SetAttribute("Padrao", layout.isDefault)
	model.ModelStreamingMode = Enum.ModelStreamingMode.Persistent
	weldAll(model, layout.root)
	release(model)
	-- Atuadores no CENTRO DE MASSA (com o conjunto já soldado): força fora
	-- dele vira torque, e a sustentação na linha d'água faria o barco
	-- caturrar sozinho. O QuadroBarco continua sendo o referencial de medida.
	local impulse = attachmentAt(layout.root, "Impulso",
		CFrame.new(layout.root.AssemblyCenterOfMass) * layout.frame.WorldCFrame.Rotation)
	createActuators(layout.root, impulse)
	layout.root:SetNetworkOwner(nil)
	for _, seat in layout.seats do
		configureSeat(seat)
	end
	configureSeat(layout.helm)
end

--------------------------------------------------------------------------------
-- Lancha padrão (Parts)
--------------------------------------------------------------------------------
--[[
	Referencial local: origem na LINHA D'ÁGUA, no meio do casco; -Z = proa,
	+X = boreste (direita), +Y = cima. Casco de 21,5 x 7 studs: fundo a -0.9
	(calado), convés a +0.9 -- ACIMA da água, senão a água do Terrain
	aparece dentro do barco (Part não desloca voxel) --, borda a +2.5.
]]

local HULL_BOTTOM = -0.9
local DECK_TOP = 0.9
local GUNWALE = 2.5
local HALF_BEAM = 3.5
local BOW_TIP = -11
local BOW_BASE = -5.5
local TRANSOM = 8.5

-- Meia proa em cunha, deitada: o triângulo da cunha fica no plano XZ.
-- side = 1 boreste, -1 bombordo.
local function bowHalfCF(base: CFrame, side: number, halfWidth: number, y: number): CFrame
	local center = (base * CFrame.new(side * halfWidth / 2, y, (BOW_TIP + BOW_BASE) / 2)).Position
	local lateral = base:VectorToWorldSpace(Vector3.new(side, 0, 0))
	local back = base:VectorToWorldSpace(Vector3.new(0, 0, 1))
	local localX = lateral:Cross(back) -- mão direita: X = Y x Z
	return CFrame.fromMatrix(center, localX, lateral, back)
end

local function buildDefaultHull(model: Model, base: CFrame, layout: { [string]: any })
	local bowLength = BOW_BASE - BOW_TIP
	local wall = GUNWALE - HULL_BOTTOM
	local wallY = (GUNWALE + HULL_BOTTOM) / 2
	local hullLength = TRANSOM - BOW_BASE
	local hullZ = (TRANSOM + BOW_BASE) / 2

	local bottom = part(model, "Fundo", Vector3.new(HALF_BEAM * 2 - 0.8, 0.6, hullLength), base * CFrame.new(0, HULL_BOTTOM + 0.3, hullZ),
		Enum.Material.SmoothPlastic, COL.Bottom)
	bottom.CustomPhysicalProperties = PhysicalProperties.new(0.7, 0.85, 0.05)
	layout.root = bottom

	part(model, "Conves", Vector3.new(HALF_BEAM * 2 - 0.8, 0.3, hullLength), base * CFrame.new(0, DECK_TOP - 0.15, hullZ),
		Enum.Material.SmoothPlastic, COL.Deck)
	-- Porão (volume escondido entre o fundo e o convés): dá massa/flutuação
	-- de casco de verdade sem aparecer.
	part(model, "Porao", Vector3.new(HALF_BEAM * 2 - 1, DECK_TOP - HULL_BOTTOM - 0.95, hullLength - 0.6),
		base * CFrame.new(0, (DECK_TOP - 0.3 + HULL_BOTTOM + 0.6) / 2, hullZ), Enum.Material.SmoothPlastic, COL.Bottom,
		{ transparency = 1, shadow = false })

	for _, side in { -1, 1 } do
		local tag = if side < 0 then "BB" else "BE"
		part(model, "Costado" .. tag, Vector3.new(0.5, wall, hullLength), base * CFrame.new(side * (HALF_BEAM - 0.25), wallY, hullZ),
			Enum.Material.SmoothPlastic, COL.Hull)
		-- Faixa de linha d'água (a "cara" de lancha).
		part(model, "Faixa" .. tag, Vector3.new(0.06, 0.45, hullLength), base * CFrame.new(side * (HALF_BEAM + 0.02), 0.45, hullZ),
			Enum.Material.SmoothPlastic, COL.Stripe, { collide = false })
		part(model, "Borda" .. tag, Vector3.new(0.75, 0.16, hullLength + 0.2), base * CFrame.new(side * (HALF_BEAM - 0.3), GUNWALE + 0.08, hullZ),
			Enum.Material.SmoothPlastic, COL.Deck)
		-- Proa: meia cunha maciça (convés de proa na altura da borda).
		wedge(model, "Proa" .. tag, Vector3.new(wall, HALF_BEAM, bowLength), bowHalfCF(base, side, HALF_BEAM, wallY),
			Enum.Material.SmoothPlastic, COL.Hull)
		wedge(model, "FaixaProa" .. tag, Vector3.new(0.45, HALF_BEAM + 0.12, bowLength + 0.2), bowHalfCF(base, side, HALF_BEAM + 0.12, 0.45),
			Enum.Material.SmoothPlastic, COL.Stripe, { collide = false })
	end

	part(model, "Espelho", Vector3.new(HALF_BEAM * 2, wall, 0.5), base * CFrame.new(0, wallY, TRANSOM - 0.25),
		Enum.Material.SmoothPlastic, COL.Hull)
	part(model, "FaixaPopa", Vector3.new(HALF_BEAM * 2 + 0.04, 0.45, 0.06), base * CFrame.new(0, 0.45, TRANSOM + 0.02),
		Enum.Material.SmoothPlastic, COL.Stripe, { collide = false })

	-- Nome no espelho de popa (todo barco de verdade tem um).
	local plate = part(model, "Nome", Vector3.new(4.2, 0.8, 0.05), base * CFrame.new(0, 1.55, TRANSOM + 0.04),
		Enum.Material.SmoothPlastic, COL.Hull, { collide = false })
	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Back
	gui.CanvasSize = Vector2.new(420, 80)
	gui.LightInfluence = 1
	gui.Parent = plate
	local text = Instance.new("TextLabel")
	text.BackgroundTransparency = 1
	text.Size = UDim2.fromScale(1, 1)
	text.Font = Enum.Font.GothamBlack
	text.Text = "ESPERANÇA"
	text.TextColor3 = COL.Stripe
	text.TextScaled = true
	text.Parent = gui

	-- Guarda-corpo de inox em volta da proa.
	local railY = GUNWALE + 0.95
	local tip = (base * CFrame.new(0, railY, BOW_TIP + 0.7)).Position
	for _, side in { -1, 1 } do
		local back = (base * CFrame.new(side * (HALF_BEAM - 0.35), railY, BOW_BASE + 0.3)).Position
		rod(model, "Guarda", tip, back, 0.14, Enum.Material.Metal, COL.Steel, { collide = false, reflectance = 0.25 })
		for f = 0.25, 1, 0.375 do
			local top = tip:Lerp(back, f)
			rod(model, "Balaustre", top, top - Vector3.new(0, 0.95, 0), 0.1, Enum.Material.Metal, COL.Steel, { collide = false, reflectance = 0.25 })
		end
	end
	part(model, "CunhoProa", Vector3.new(0.35, 0.2, 0.7), base * CFrame.new(0, GUNWALE + 0.1, BOW_TIP + 2.2),
		Enum.Material.Metal, COL.Steel, { collide = false, reflectance = 0.2 })
end

local function buildDefaultConsole(model: Model, base: CFrame, layout: { [string]: any })
	local consoleZ = 0.2
	part(model, "Console", Vector3.new(2.4, 2.2, 1.9), base * CFrame.new(0, DECK_TOP + 1.1, consoleZ),
		Enum.Material.SmoothPlastic, COL.Hull)
	part(model, "TampoConsole", Vector3.new(2.6, 0.18, 2.1), base * CFrame.new(0, DECK_TOP + 2.29, consoleZ),
		Enum.Material.SmoothPlastic, COL.Dark)
	-- Painel inclinado virado pro piloto (+Z) e para-brisa na frente.
	local dash = part(model, "Painel", Vector3.new(2.2, 0.95, 0.12), base * CFrame.new(0, DECK_TOP + 1.75, consoleZ + 1.0) * CFrame.Angles(math.rad(-28), 0, 0),
		Enum.Material.SmoothPlastic, COL.Dark, { collide = false })
	local windshield = part(model, "ParaBrisa", Vector3.new(2.7, 1.25, 0.1),
		base * CFrame.new(0, DECK_TOP + 2.95, consoleZ - 0.55) * CFrame.Angles(math.rad(26), 0, 0),
		Enum.Material.Glass, COL.Glass, { collide = false, transparency = 0.55 })
	windshield.CastShadow = false
	for _, x in { -1.38, 1.38 } do
		-- Acompanha o caimento do vidro: base na frente do tampo, topo recuado.
		rod(model, "MolduraParaBrisa", (base * CFrame.new(x, DECK_TOP + 2.39, consoleZ - 0.83)).Position,
			(base * CFrame.new(x, DECK_TOP + 3.51, consoleZ - 0.27)).Position, 0.1, Enum.Material.Metal, COL.Steel, { collide = false, reflectance = 0.25 })
	end

	-- Volante e manete.
	local wheelCF = base * CFrame.new(-0.45, DECK_TOP + 1.8, consoleZ + 1.12) * CFrame.Angles(0, -math.pi / 2, 0) * CFrame.Angles(0, 0, math.rad(34))
	part(model, "Volante", Vector3.new(0.12, 1.05, 1.05), wheelCF, Enum.Material.SmoothPlastic, COL.Dark, { shape = Enum.PartType.Cylinder, collide = false })
	part(model, "CuboVolante", Vector3.new(0.22, 0.3, 0.3), wheelCF * CFrame.new(0.08, 0, 0), Enum.Material.Metal, COL.Steel, { shape = Enum.PartType.Cylinder, collide = false })
	part(model, "Manete", Vector3.new(0.12, 0.6, 0.12), base * CFrame.new(0.95, DECK_TOP + 2.1, consoleZ + 1.05) * CFrame.Angles(math.rad(-20), 0, 0),
		Enum.Material.Metal, COL.Steel, { collide = false })

	-- Mostradores (acendem com o motor).
	for i, x in { -0.55, 0.05 } do
		local gauge = part(model, "Mostrador" .. i, Vector3.new(0.05, 0.36, 0.36),
			dash.CFrame * CFrame.new(x, 0.12, 0.07) * CFrame.Angles(0, math.pi / 2, 0),
			Enum.Material.SmoothPlastic, Color3.fromRGB(40, 60, 50), { shape = Enum.PartType.Cylinder, collide = false })
		table.insert(layout.glow, gauge)
	end

	-- Ignição: onde a chave entra (ponto do prompt "Colocar chave").
	local ignition = part(model, "Ignicao", Vector3.new(0.34, 0.34, 0.1), dash.CFrame * CFrame.new(0.75, -0.18, 0.07),
		Enum.Material.Metal, COL.Steel, { collide = false, reflectance = 0.2 })
	layout.anchors.Ignicao = ignition
	local keyBlade = part(model, "ChaveVisual", Vector3.new(0.08, 0.34, 0.08), ignition.CFrame * CFrame.new(0, -0.14, 0.12),
		Enum.Material.Metal, COL.Steel, { collide = false, transparency = 1 })
	local keyFloat = part(model, "ChaveboiaVisual", Vector3.new(0.5, 0.26, 0.26), ignition.CFrame * CFrame.new(0, -0.62, 0.16) * UPRIGHT,
		Enum.Material.SmoothPlastic, Color3.fromRGB(255, 120, 24), { shape = Enum.PartType.Cylinder, collide = false, transparency = 1 })
	layout.visuals.Chave = { keyBlade, keyFloat }

	-- Holofote no tampo do console, virado pra proa.
	local lamp = part(model, "Holofote", Vector3.new(0.55, 0.45, 0.45), base * CFrame.new(0, DECK_TOP + 2.62, consoleZ - 0.6),
		Enum.Material.Metal, COL.Steel, { collide = false, reflectance = 0.3 })
	local spot = Instance.new("SpotLight")
	spot.Name = "Holofote"
	spot.Face = Enum.NormalId.Front
	spot.Angle = 50
	spot.Range = 70
	spot.Brightness = 3.2
	spot.Color = Color3.fromRGB(255, 244, 222)
	spot.Shadows = true
	spot.Enabled = false
	spot.Parent = lamp
	table.insert(layout.lights, spot)
	local lens = part(model, "LenteHolofote", Vector3.new(0.4, 0.35, 0.05), lamp.CFrame * CFrame.new(0, 0, -0.24),
		Enum.Material.SmoothPlastic, Color3.fromRGB(80, 80, 76), { collide = false })
	table.insert(layout.glow, lens)
end

local function buildDefaultSeats(model: Model, base: CFrame, layout: { [string]: any })
	local helm = Instance.new("VehicleSeat")
	helm.Name = "AssentoPiloto"
	helm.Size = Vector3.new(2.2, 1, 1.8)
	helm.CFrame = base * CFrame.new(0, DECK_TOP + 0.5, 2.9)
	style(helm, Enum.Material.Fabric, COL.Cushion)
	helm.Parent = model
	layout.helm = helm
	part(model, "EncostoPiloto", Vector3.new(2.2, 1.5, 0.3), base * CFrame.new(0, DECK_TOP + 1.7, 3.95) * CFrame.Angles(math.rad(-8), 0, 0),
		Enum.Material.Fabric, COL.Cushion, { collide = false })

	local function seat(name: string, size: Vector3, cf: CFrame): Seat
		local s = Instance.new("Seat")
		s.Name = name
		s.Size = size
		s.CFrame = cf
		style(s, Enum.Material.Fabric, COL.Cushion)
		s.Parent = model
		table.insert(layout.seats, s)
		return s
	end

	-- Dois na frente do console (costas no console), três no banco de popa.
	seat("Assento1", Vector3.new(2, 1, 1.4), base * CFrame.new(-1.15, DECK_TOP + 0.5, -1.55))
	seat("Assento2", Vector3.new(2, 1, 1.4), base * CFrame.new(1.15, DECK_TOP + 0.5, -1.55))
	for i, x in { -2.0, 0, 2.0 } do
		seat("Assento" .. (i + 2), Vector3.new(1.9, 1, 1.5), base * CFrame.new(x, DECK_TOP + 0.5, 6.95))
	end
	part(model, "EncostoPopa", Vector3.new(HALF_BEAM * 2 - 1, 1.2, 0.3), base * CFrame.new(0, DECK_TOP + 1.55, 7.8),
		Enum.Material.Fabric, COL.Cushion, { collide = false })
end

local function buildDefaultEngine(model: Model, base: CFrame, layout: { [string]: any })
	local z = TRANSOM + 1.05
	part(model, "Suporte", Vector3.new(1.1, 0.9, 0.6), base * CFrame.new(0, GUNWALE - 0.2, TRANSOM + 0.3), Enum.Material.Metal, COL.Dark)
	local cowl = part(model, "CapoMotor", Vector3.new(1.7, 2.2, 2.0), base * CFrame.new(0, GUNWALE + 0.75, z), Enum.Material.SmoothPlastic, COL.Engine)
	part(model, "FaixaCapo", Vector3.new(1.74, 0.22, 2.04), base * CFrame.new(0, GUNWALE + 1.2, z), Enum.Material.SmoothPlastic, COL.EngineAccent, { collide = false })
	part(model, "TopoCapo", Vector3.new(1.5, 0.25, 1.8), base * CFrame.new(0, GUNWALE + 1.95, z), Enum.Material.SmoothPlastic, COL.Engine, { collide = false })
	local shaftTop, shaftBottom = GUNWALE + 0.75 - 1.1, HULL_BOTTOM - 0.8
	part(model, "Coluna", Vector3.new(0.55, shaftTop - shaftBottom, 0.7), base * CFrame.new(0, (shaftTop + shaftBottom) / 2, z), Enum.Material.SmoothPlastic, COL.Engine, { collide = false })
	part(model, "Rabeta", Vector3.new(0.75, 0.75, 1.5), base * CFrame.new(0, HULL_BOTTOM - 0.8, z + 0.1), Enum.Material.SmoothPlastic, COL.Engine, { collide = false })
	layout.anchors.Motor = cowl

	-- Hélice (some até ser instalada; de pé o barco encalhado mostra ela).
	local hub = part(model, "HeliceCubo", Vector3.new(0.5, 0.36, 0.36), base * CFrame.new(0, HULL_BOTTOM - 0.8, z + 1.05) * CFrame.Angles(0, math.pi / 2, 0),
		Enum.Material.Metal, COL.Steel, { shape = Enum.PartType.Cylinder, collide = false, transparency = 1 })
	local blades = { hub }
	for i = 0, 2 do
		local blade = part(model, "HelicePa", Vector3.new(0.1, 0.95, 0.42),
			hub.CFrame * CFrame.Angles(i * math.pi * 2 / 3, 0, 0) * CFrame.new(0, 0.5, 0) * CFrame.Angles(0, math.rad(22), 0),
			Enum.Material.Metal, COL.Steel, { collide = false, transparency = 1 })
		table.insert(blades, blade)
	end
	layout.visuals.Helice = blades

	-- Vela: cachimbo na lateral do capô (aparece instalado).
	local boot = part(model, "VelaVisual", Vector3.new(0.45, 0.26, 0.26), cowl.CFrame * CFrame.new(0.95, 0.2, 0.3),
		Enum.Material.SmoothPlastic, Color3.fromRGB(20, 20, 22), { shape = Enum.PartType.Cylinder, collide = false, transparency = 1 })
	layout.visuals.Vela = { boot }

	layout.wiring = buildWiring(model, cowl.CFrame * CFrame.new(-0.95, -0.6, 0.2) * CFrame.Angles(0, math.pi / 2, 0))
end

local function buildDefaultDetails(model: Model, base: CFrame, layout: { [string]: any })
	-- Bocal do tanque na borda de boreste.
	local cap = part(model, "TampaTanque", Vector3.new(0.18, 0.5, 0.5), base * CFrame.new(HALF_BEAM - 0.3, GUNWALE + 0.2, 4.6) * UPRIGHT,
		Enum.Material.Metal, COL.Steel, { shape = Enum.PartType.Cylinder, collide = false, reflectance = 0.3 })
	layout.anchors.Tanque = cap

	-- Luzes de navegação: vermelha a bombordo, verde a boreste, branca na popa.
	for _, spec in {
		{ name = "LuzBombordo", x = -1.4, color = Color3.fromRGB(255, 48, 40) },
		{ name = "LuzBoreste", x = 1.4, color = Color3.fromRGB(52, 255, 110) },
	} do
		local lamp = part(model, spec.name, Vector3.new(0.35, 0.25, 0.35), base * CFrame.new(spec.x, GUNWALE + 0.3, -8.3),
			Enum.Material.SmoothPlastic, spec.color, { collide = false })
		table.insert(layout.glow, lamp)
		table.insert(layout.lights, pointLight(lamp, spec.color, 9, 1.2))
	end
	local mastBase = (base * CFrame.new(-2.9, GUNWALE + 0.1, TRANSOM - 0.5)).Position
	local mastTop = mastBase + base:VectorToWorldSpace(Vector3.new(0, 2.6, 0))
	rod(model, "MastroLuz", mastBase, mastTop, 0.12, Enum.Material.Metal, COL.Steel, { collide = false, reflectance = 0.25 })
	local stern = part(model, "LuzPopa", Vector3.new(0.3, 0.3, 0.3), CFrame.new(mastTop) * base.Rotation,
		Enum.Material.SmoothPlastic, Color3.fromRGB(255, 250, 236), { shape = Enum.PartType.Ball, collide = false })
	table.insert(layout.glow, stern)
	table.insert(layout.lights, pointLight(stern, Color3.fromRGB(255, 244, 222), 12, 1))

	part(model, "CunhoPopa", Vector3.new(0.35, 0.2, 0.7), base * CFrame.new(-(HALF_BEAM - 0.45), GUNWALE + 0.1, TRANSOM - 1.2),
		Enum.Material.Metal, COL.Steel, { collide = false, reflectance = 0.2 })

	-- Âncoras dos prompts de fora do barco.
	layout.anchors.EmbarqueBB = marker(model, "EmbarqueBB", base * CFrame.new(-HALF_BEAM - 0.3, GUNWALE - 0.4, -2.2))
	layout.anchors.EmbarqueBE = marker(model, "EmbarqueBE", base * CFrame.new(HALF_BEAM + 0.3, GUNWALE - 0.4, -2.2))
	layout.anchors.Proa = marker(model, "EmpurrarProa", base * CFrame.new(0, 1.2, BOW_TIP - 0.4))
	layout.anchors.Popa = marker(model, "EmpurrarPopa", base * CFrame.new(0, 1.2, TRANSOM + 2.4))
end

--[[
	Pier(shore, outward) -> (pier, bollards, itemSpots)
	Tábuas da areia até 26 studs mar adentro, na altura da praia (o convés
	da lancha fica ~3 studs abaixo: dá pra pular pra dentro e pra fora).
]]
local function buildPier(parent: Instance, shore: Vector3, outward: Vector3): (Model, { Attachment }, { CFrame })
	local pier = Instance.new("Model")
	pier.Name = "PierBarco"
	local deckY = shore.Y + 0.2
	local start = Vector3.new(shore.X, deckY, shore.Z) - outward * 7
	local base = CFrame.lookAt(start, start + outward)
	local length = 34
	local planks = math.floor(length / 2)
	for i = 0, planks - 1 do
		local shade = if i % 3 == 0 then COL.WoodDark else COL.Wood
		part(pier, "Tabua", Vector3.new(6, 0.35, 1.85), base * CFrame.new(0, 0, -(i * 2 + 1)), Enum.Material.WoodPlanks, shade)
	end
	for i = 0, length, 6 do
		for _, side in { -1, 1 } do
			local top = (base * CFrame.new(side * 3.1, 0.6, -i)).Position
			rod(pier, "Estaca", top, top - Vector3.new(0, 16, 0), 0.7, Enum.Material.Wood, COL.WoodDark)
		end
	end
	for _, side in { -1, 1 } do
		part(pier, "Longarina", Vector3.new(0.35, 0.5, length), base * CFrame.new(side * 3.05, -0.35, -length / 2), Enum.Material.Wood, COL.WoodDark)
	end

	local bollards: { Attachment } = {}
	for _, z in { -(length - 3), -(length - 15) } do
		local post = part(pier, "Cabeco", Vector3.new(0.7, 0.9, 0.7), base * CFrame.new(3.0, 0.62, z) * UPRIGHT,
			Enum.Material.Metal, COL.Dark, { shape = Enum.PartType.Cylinder })
		local a = Instance.new("Attachment")
		a.Name = "Amarra"
		a.Position = Vector3.new(0.3, 0, 0)
		a.Parent = post
		table.insert(bollards, a)
	end

	-- Lampião no fim do píer: acha o barco no escuro.
	local lampTop = (base * CFrame.new(-2.7, 4.2, -(length - 1))).Position
	rod(pier, "PosteLampiao", lampTop - Vector3.new(0, 4.1, 0), lampTop, 0.28, Enum.Material.Wood, COL.WoodDark)
	local lamp = part(pier, "Lampiao", Vector3.new(0.6, 0.7, 0.6), CFrame.new(lampTop + Vector3.new(0, 0.3, 0)),
		Enum.Material.Neon, COL.Lamp, { collide = false })
	local light = pointLight(lamp, Color3.fromRGB(255, 208, 140), 26, 1.1)
	light.Enabled = true
	light.Shadows = true

	-- Itens de teste espalhados nas tábuas perto da areia.
	local spots: { CFrame } = {}
	for i = 0, 3 do
		table.insert(spots, base * CFrame.new(-1.6 + (i % 2) * 3.2, 0.9, -(5 + math.floor(i / 2) * 3.5)))
	end

	pier.Parent = parent
	return pier, bollards, spots
end

function BoatBuilder.BuildDefault(cfg: any): Layout?
	local shore, outward = findDockSpot()
	if not shore or not outward then
		return nil
	end
	local ilha = getIlha()
	local old = ilha:FindFirstChild("PierBarco")
	if old then
		old:Destroy()
	end
	local _, bollards, spots = buildPier(ilha, shore, outward)

	-- Lancha de proa pro mar, encostada no fim do píer (lado boreste do píer).
	local side = Vector3.new(-outward.Z, 0, outward.X)
	local center = shore + outward * 20 + side * (3.4 + HALF_BEAM + 0.6)
	local frameHome = CFrame.lookAt(Vector3.new(center.X, seaLevel(), center.Z), Vector3.new(center.X, seaLevel(), center.Z) + outward)

	local model = Instance.new("Model")
	model.Name = "BarcoFuga"
	local layout: { [string]: any } = {
		model = model,
		seats = {},
		anchors = {},
		lights = {},
		glow = {},
		visuals = {},
		moorings = {},
		home = frameHome, -- trocado pelo pivot real logo abaixo
		length = TRANSOM - BOW_TIP + 2,
		width = HALF_BEAM * 2,
		isDefault = true,
		itemSpots = spots,
	}
	buildDefaultHull(model, frameHome, layout)
	buildDefaultConsole(model, frameHome, layout)
	buildDefaultSeats(model, frameHome, layout)
	buildDefaultEngine(model, frameHome, layout)
	buildDefaultDetails(model, frameHome, layout)
	model.PrimaryPart = layout.root
	-- Reset de rodada usa PivotTo: precisa do pivot do MODEL, não do
	-- referencial da linha d'água usado pra montar.
	layout.home = model:GetPivot()

	local root = layout.root :: BasePart
	local frame = attachmentAt(root, BoatPhysics.FrameName, frameHome)
	layout.frame = frame

	-- Amarras: cordas (Beam curvo) do cunho da proa/popa aos cabeços.
	local cleats = { model:FindFirstChild("CunhoProa"), model:FindFirstChild("CunhoPopa") }
	for i, cleat in cleats do
		local bollard = bollards[i]
		if cleat and cleat:IsA("BasePart") and bollard then
			local a = Instance.new("Attachment")
			a.Name = "Amarra"
			a.Parent = cleat
			local rope = Instance.new("Beam")
			rope.Name = "CaboAmarra"
			rope.Attachment0 = a
			rope.Attachment1 = bollard
			rope.Width0, rope.Width1 = 0.14, 0.14
			rope.Segments = 12
			rope.CurveSize0, rope.CurveSize1 = -1.4, 1.4
			rope.Color = ColorSequence.new(COL.Rope)
			rope.LightInfluence = 1
			rope.FaceCamera = true
			rope.Parent = cleat
			table.insert(layout.moorings, rope)
		end
	end

	-- Efeitos (o cliente acha pelo nome; ver BoatEffects).
	attachmentAt(root, "EsteiraBB", frameHome * CFrame.new(-HALF_BEAM + 0.4, 0.05, TRANSOM - 0.2))
	attachmentAt(root, "EsteiraBE", frameHome * CFrame.new(HALF_BEAM - 0.4, 0.05, TRANSOM - 0.2))
	attachmentAt(root, "Helice", frameHome * CFrame.new(0, 0.05, TRANSOM + 2.3))
	attachmentAt(root, "SprayBB", frameHome * CFrame.new(-HALF_BEAM, 0.25, -5.2) * SPRAY_PORT)
	attachmentAt(root, "SprayBE", frameHome * CFrame.new(HALF_BEAM, 0.25, -5.2) * SPRAY_STARBOARD)
	attachmentAt(root, "Proa", frameHome * CFrame.new(0, 0.2, BOW_TIP + 0.4))
	attachmentAt(root, "Escapamento", frameHome * CFrame.new(0, GUNWALE + 1.3, TRANSOM + 2.1))
	attachmentAt(root, "SomMotor", frameHome * CFrame.new(0, GUNWALE + 0.8, TRANSOM + 1.05))

	model.Parent = ilha
	local result = layout :: any
	finalize(result)
	return result
end

--------------------------------------------------------------------------------
-- Barco do mapa (qualquer Model)
--------------------------------------------------------------------------------

local HELM_HINTS = { "piloto", "driver", "helm", "pilot", "captain", "capitao", "timao" }

local function localExtents(model: Model, frame: CFrame): (Vector3, Vector3)
	local minV = Vector3.new(math.huge, math.huge, math.huge)
	local maxV = Vector3.new(-math.huge, -math.huge, -math.huge)
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") and d.Transparency < 1 then
			local half = d.Size / 2
			for _, sx in { -1, 1 } do
				for _, sy in { -1, 1 } do
					for _, sz in { -1, 1 } do
						local p = frame:PointToObjectSpace((d.CFrame * CFrame.new(half.X * sx, half.Y * sy, half.Z * sz)).Position)
						minV = Vector3.new(math.min(minV.X, p.X), math.min(minV.Y, p.Y), math.min(minV.Z, p.Z))
						maxV = Vector3.new(math.max(maxV.X, p.X), math.max(maxV.Y, p.Y), math.max(maxV.Z, p.Z))
					end
				end
			end
		end
	end
	if minV.X == math.huge then
		local _, size = model:GetBoundingBox()
		return -size / 2, size / 2
	end
	return minV, maxV
end

local function pickHelm(model: Model): (Seat | VehicleSeat)?
	local vehicle = model:FindFirstChildWhichIsA("VehicleSeat", true)
	if vehicle then
		return vehicle
	end
	for _, d in model:GetDescendants() do
		if d:IsA("Seat") and nameMatches(d.Name, HELM_HINTS) then
			return d
		end
	end
	return nil
end

function BoatBuilder.PrepareExisting(model: Model, cfg: any): Layout
	silenceLegacy(model)

	local root = model.PrimaryPart
	if not root then
		local biggest: BasePart? = nil
		for _, d in model:GetDescendants() do
			if d:IsA("BasePart") and (not biggest or d.Size.Magnitude > biggest.Size.Magnitude) then
				biggest = d
			end
		end
		root = biggest
		model.PrimaryPart = biggest
	end
	assert(root, "[Barco] O modelo do barco não tem nenhuma BasePart.")
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			d.Anchored = true -- monta tudo parado; finalize solta no fim
		end
	end

	-- Frente: o assento do piloto olha pra proa. Sem assento, o eixo maior.
	local helmCandidate = pickHelm(model)
	local boxCF, boxSize = model:GetBoundingBox()
	local forward: Vector3
	if helmCandidate then
		forward = flat(helmCandidate.CFrame.LookVector)
	elseif boxSize.Z >= boxSize.X then
		forward = flat(boxCF.LookVector)
	else
		forward = flat(boxCF.RightVector)
	end
	forward = CFrame.Angles(0, math.rad(cfg.GuinadaModelo or 0), 0):VectorToWorldSpace(forward)

	local probe = CFrame.lookAt(boxCF.Position, boxCF.Position + forward)
	local minV, maxV = localExtents(model, probe)
	-- Recentra no meio do casco, na linha d'água (fundo + calado).
	local centerLocal = Vector3.new((minV.X + maxV.X) / 2, minV.Y + cfg.CaladoModelo, (minV.Z + maxV.Z) / 2)
	local frameCF = probe * CFrame.new(centerLocal)
	local length = maxV.Z - minV.Z
	local width = maxV.X - minV.X
	local height = maxV.Y - minV.Y
	local deckY = math.min(height * 0.45, 2.2)
	local sternZ = maxV.Z - centerLocal.Z -- +Z local = popa
	local bowZ = minV.Z - centerLocal.Z
	local halfW = width / 2

	local layout: { [string]: any } = {
		model = model,
		root = root,
		seats = {},
		anchors = {},
		lights = {},
		glow = {},
		visuals = {},
		moorings = {},
		home = model:GetPivot(),
		length = length,
		width = width,
		isDefault = false,
		itemSpots = {},
	}

	-- Piloto: VehicleSeat. Um Seat comum no lugar vira VehicleSeat invisível
	-- (o original fica desligado pra ninguém sentar duas vezes).
	local helm: VehicleSeat
	if helmCandidate and helmCandidate:IsA("VehicleSeat") then
		helm = helmCandidate
	else
		helm = Instance.new("VehicleSeat")
		helm.Name = "AssentoPiloto"
		if helmCandidate then
			helm.Size = helmCandidate.Size
			helm.CFrame = helmCandidate.CFrame
			helmCandidate.Disabled = true
			helmCandidate.CanTouch = false
		else
			helm.Size = Vector3.new(2, 1, 2)
			helm.CFrame = frameCF * CFrame.new(0, deckY, sternZ * 0.45)
		end
		helm.Transparency = 1
		helm.Anchored = true
		helm.CanCollide = false
		helm.Parent = model
	end
	layout.helm = helm

	for _, d in model:GetDescendants() do
		if d:IsA("Seat") and d ~= helmCandidate and not d.Disabled then
			table.insert(layout.seats, d)
		elseif d:IsA("VehicleSeat") and d ~= helm then
			-- Um timão só: VehicleSeat extra do modelo não pode virar piloto.
			d.Disabled = true
			d.CanTouch = false
		end
	end
	if #layout.seats == 0 then
		-- Sem bancos: passageiros em duas colunas no meio do barco.
		for i = 1, math.max(cfg.Assentos - 1, 1) do
			local col = if i % 2 == 1 then -1 else 1
			local row = math.floor((i - 1) / 2)
			local s = Instance.new("Seat")
			s.Name = "Assento" .. i
			s.Size = Vector3.new(1.8, 1, 1.8)
			s.CFrame = frameCF * CFrame.new(col * math.min(halfW * 0.45, 1.6), deckY, bowZ * 0.25 + row * 2.4)
			s.Transparency = 1
			s.Anchored = true
			s.CanCollide = false
			s.Parent = model
			table.insert(layout.seats, s)
		end
	end
	while #layout.seats > cfg.Assentos - 1 do
		local extra = table.remove(layout.seats) :: Seat
		extra.Disabled = true -- sem prompt nem toque: ninguém senta fora da lotação
		extra.CanTouch = false
	end

	local function anchor(name: string, offset: CFrame): BasePart
		local old = model:FindFirstChild(name)
		if old then
			old:Destroy()
		end
		return marker(model, name, frameCF * offset)
	end
	layout.anchors.Motor = anchor("PontoMotor", CFrame.new(0, deckY + 0.6, sternZ - 0.6))
	layout.anchors.Tanque = anchor("PontoTanque", CFrame.new(halfW * 0.6, deckY + 0.4, sternZ - 3))
	layout.anchors.Ignicao = anchor("PontoIgnicao", frameCF:ToObjectSpace(helm.CFrame * CFrame.new(0, 1, -1.4)))
	layout.anchors.EmbarqueBB = anchor("EmbarqueBB", CFrame.new(-halfW - 0.3, deckY, 0))
	layout.anchors.EmbarqueBE = anchor("EmbarqueBE", CFrame.new(halfW + 0.3, deckY, 0))
	layout.anchors.Proa = anchor("EmpurrarProa", CFrame.new(0, deckY * 0.5, bowZ - 0.4))
	layout.anchors.Popa = anchor("EmpurrarPopa", CFrame.new(0, deckY * 0.5, sternZ + 0.8))
	layout.wiring = buildWiring(model, frameCF * CFrame.new(0, deckY + 0.2, sternZ - 1.2))

	-- Luzes: holofote na proa + luz de popa (o modelo pode não ter nenhuma).
	local bowLight = anchor("Holofote", CFrame.new(0, deckY + 1.2, bowZ + 1.2))
	local spot = Instance.new("SpotLight")
	spot.Name = "Holofote"
	spot.Face = Enum.NormalId.Front
	spot.Angle = 50
	spot.Range = 70
	spot.Brightness = 3.2
	spot.Color = Color3.fromRGB(255, 244, 222)
	spot.Enabled = false
	spot.Parent = bowLight
	table.insert(layout.lights, spot)
	local sternLight = anchor("LuzPopa", CFrame.new(0, height - cfg.CaladoModelo, sternZ - 0.5))
	table.insert(layout.lights, pointLight(sternLight, Color3.fromRGB(255, 244, 222), 12, 1))

	local frame = attachmentAt(root, BoatPhysics.FrameName, frameCF)
	layout.frame = frame
	attachmentAt(root, "EsteiraBB", frameCF * CFrame.new(-halfW + 0.4, 0.05, sternZ - 0.2))
	attachmentAt(root, "EsteiraBE", frameCF * CFrame.new(halfW - 0.4, 0.05, sternZ - 0.2))
	attachmentAt(root, "Helice", frameCF * CFrame.new(0, 0.05, sternZ + 1))
	attachmentAt(root, "SprayBB", frameCF * CFrame.new(-halfW, 0.25, bowZ * 0.5) * SPRAY_PORT)
	attachmentAt(root, "SprayBE", frameCF * CFrame.new(halfW, 0.25, bowZ * 0.5) * SPRAY_STARBOARD)
	attachmentAt(root, "Proa", frameCF * CFrame.new(0, 0.2, bowZ + 0.4))
	attachmentAt(root, "Escapamento", frameCF * CFrame.new(0, deckY + 1, sternZ + 0.4))
	attachmentAt(root, "SomMotor", frameCF * CFrame.new(0, deckY + 0.6, sternZ - 0.4))

	-- Itens de teste: na areia firme mais próxima, entre o barco e o centro.
	local toCenter = flat(-frameCF.Position)
	for dist = 6, 90, 3 do
		local p = frameCF.Position + toCenter * dist
		local y, material = groundAt(p.X, p.Z)
		if y and y > seaLevel() + 1 and material ~= Enum.Material.Water then
			for i = 0, 3 do
				local side = Vector3.new(-toCenter.Z, 0, toCenter.X)
				local spot2 = p + toCenter * 3 + side * ((i - 1.5) * 2.4)
				local gy = groundAt(spot2.X, spot2.Z) or y
				table.insert(layout.itemSpots, CFrame.new(spot2.X, gy + 0.9, spot2.Z))
			end
			break
		end
	end

	local result = layout :: any
	finalize(result)
	return result
end

--[[
	Build(cfg) -> Layout?
	Barco do mapa se existir; senão a lancha padrão com píer. nil só se o
	mapa não tiver praia nenhuma (ilha não gerada) -- aí não há fuga de barco.
]]
function BoatBuilder.Build(cfg: any): Layout?
	local existing = BoatBuilder.Find(cfg)
	if existing then
		print(string.format("[Barco] Usando o barco do mapa: %s%s", existing:GetFullName(),
			if existing:GetAttribute("BarcoFuga") == true then ""
				else " (achado pelo nome -- marque BarcoFuga = true nele pra não depender disso)"))
		return BoatBuilder.PrepareExisting(existing, cfg)
	end
	local layout = BoatBuilder.BuildDefault(cfg)
	if layout then
		local p = layout.home.Position
		print(string.format("[Barco] Nenhum barco marcado no mapa -- lancha padrão com píer em (%.0f, %.0f). "
			.. "Pra usar o seu, dê o Attribute BarcoFuga = true no Model dele.", p.X, p.Z))
	end
	return layout
end

--------------------------------------------------------------------------------
-- Limite do mapa: anel de boias
--------------------------------------------------------------------------------

--[[
	BuildFinishRing(cfg) -> Folder
	Boias vermelhas e brancas com lanterna no anel de chegada. O servidor
	decide a fuga pela distância; as boias são o "é ali" visível. O pisca e
	o balanço são do cliente (BoatEffects), pra não custar replicação.
]]
function BoatBuilder.BuildFinishRing(cfg: any): Folder
	local ilha = getIlha()
	local old = ilha:FindFirstChild("LimiteFuga")
	if old then
		old:Destroy()
	end
	local folder = Instance.new("Folder")
	folder.Name = "LimiteFuga"
	folder:SetAttribute("Raio", cfg.RaioChegada)

	local radius = cfg.RaioChegada
	local count = math.max(12, math.ceil(2 * math.pi * radius / cfg.BoiasEspacamento))
	local y = seaLevel()
	for i = 1, count do
		local angle = (i - 1) / count * math.pi * 2
		local pos = Vector3.new(math.cos(angle) * radius, y, math.sin(angle) * radius)
		local buoy = Instance.new("Model")
		buoy.Name = "Boia"
		local base = CFrame.new(pos) * CFrame.Angles(0, -angle, 0)
		local body = part(buoy, "Flutuador", Vector3.new(1.8, 2.3, 2.3), base * CFrame.new(0, 0.3, 0) * UPRIGHT,
			Enum.Material.SmoothPlastic, COL.BuoyRed, { shape = Enum.PartType.Cylinder })
		part(buoy, "Faixa", Vector3.new(0.45, 2.36, 2.36), base * CFrame.new(0, 0.55, 0) * UPRIGHT,
			Enum.Material.SmoothPlastic, COL.BuoyWhite, { shape = Enum.PartType.Cylinder, collide = false })
		part(buoy, "Cone", Vector3.new(1.1, 1.3, 1.3), base * CFrame.new(0, 1.7, 0) * UPRIGHT,
			Enum.Material.SmoothPlastic, COL.BuoyRed, { shape = Enum.PartType.Cylinder, collide = false })
		rod(buoy, "Haste", (base * CFrame.new(0, 2.2, 0)).Position, (base * CFrame.new(0, 4.4, 0)).Position, 0.18,
			Enum.Material.Metal, COL.Dark, { collide = false })
		local lamp = part(buoy, "Lanterna", Vector3.new(0.5, 0.5, 0.5), base * CFrame.new(0, 4.6, 0),
			Enum.Material.Neon, COL.Lamp, { shape = Enum.PartType.Ball, collide = false })
		if i % 2 == 0 then
			local light = pointLight(lamp, COL.Lamp, 16, 1.4)
			light.Enabled = true
		end
		if i % 3 == 0 then
			local sign = Instance.new("BillboardGui")
			sign.Name = "Aviso"
			sign.Size = UDim2.fromOffset(150, 34)
			sign.StudsOffsetWorldSpace = Vector3.new(0, 7, 0)
			sign.MaxDistance = 320
			sign.LightInfluence = 0
			sign.Parent = lamp
			local text = Instance.new("TextLabel")
			text.Size = UDim2.fromScale(1, 1)
			text.BackgroundColor3 = Color3.fromRGB(12, 14, 18)
			text.BackgroundTransparency = 0.35
			text.Font = Enum.Font.GothamBold
			text.Text = "LIMITE · FUGA"
			text.TextColor3 = COL.Lamp
			text.TextSize = 15
			text.Parent = sign
		end
		buoy.PrimaryPart = body
		buoy:SetAttribute("Fase", angle * 3.7)
		buoy.Parent = folder
	end
	folder.Parent = ilha
	return folder
end

return BoatBuilder
