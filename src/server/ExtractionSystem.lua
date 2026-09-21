--!strict
--[[
	ExtractionSystem
	O fim da linha do objetivo do Rádio: o helicóptero de resgate.

	Antes, concluir o rádio dava vitória sozinho -- RoundManager esperava
	RescueCountdownDuration e declarava os Sobreviventes vencedores, onde quer
	que eles estivessem. Agora o pedido de socorro só CHAMA o resgate; quem
	ganha é quem chega na praia.

	LINHA DO TEMPO
	  1. RadioSiteSystem conclui o pedido de socorro
	     -> RadioObjective.RescueCountdownStarted
	     -> RoundManager chama ExtractionSystem.Begin(duração)
	  2. INBOUND: nasce a zona de pouso na praia com FUMAÇA VERMELHA, feixe
	     de luz e um letreiro visível de qualquer lugar do mapa. Contagem
	     regressiva na tela de todo mundo. Entrar na zona agora NÃO faz nada
	     -- e o Monstro continua matando normalmente.
	  3. CHEGANDO: a contagem zera e o helicóptero VOA até a praia -- vem de
	     longe e alto, desacelerando, inclinado na curva, levanta o nariz pra
	     frear em cima da pista (flare) e desce reto até tocar o chão. A
	     trajetória é atualizada TODO FRAME; o resto do sistema roda
	     throttled, senão o voo ficaria travado.
	  4. POUSADO: vira sólido (dá pra esbarrar, não dá pra atravessar) e
	     libera o prompt "Embarcar".
	  5. A BORDO: quem embarca senta num assento, e a tela dele mostra DUAS
	     opções -- partir agora ou esperar os colegas. Sair exige o prompt
	     "Sair"; ninguém é ejetado sozinho.
	  6. PARTINDO: sobe reto, vira e acelera pro mar. No fim dispara
	     SurvivorsExtracted com quem está a bordo e o RoundManager encerra.

	Quem decide a hora de ir é o jogador: não existe decolagem automática. Se
	ninguém chegar, o helicóptero ESPERA (não existe segunda chance de chamar
	o resgate -- ir embora seria só frustrante). A partida ainda pode acabar
	pelo tempo ou pelo Monstro matando todo mundo.

	MODELO: CFG.ModeloId carrega o helicóptero do Toolbox; se falhar, entra
	uma versão em Parts com os mesmos nomes (PrimaryPart + "Rotor"), então
	nada mais precisa saber qual dos dois está no mapa. O rotor é achado por
	nome (rotor/hélice/blade/...) e gira por frame. Se o modelo voar de lado,
	é só ajustar GameConfig.Extraction.GuinadaModelo.

	Não restrinjo por papel: um Espião infiltrado também consegue embarcar.
	Quem decide o vencedor é o RoundManager.

	ONDE FICA A ZONA: na praia do lado OPOSTO ao site "Radio" do IslandLayout
	-- a corrida final atravessa a ilha inteira, com o Monstro sabendo
	exatamente pra onde todo mundo está indo. É calculado em runtime a partir
	do layout, então não precisa regerar o mapa pra existir.

	Uso (boot do servidor):
		require(script.ExtractionSystem).Init()
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local AssetRegistry = require(ReplicatedStorage.Modules.AssetRegistry)
local GameConfig = require(ReplicatedStorage.Modules.GameConfig)
local Remotes = require(ReplicatedStorage.Modules.Remotes)
local AssetLoader = require(ReplicatedStorage.Modules.AssetLoader)
local Layout = require(script.Parent.Tools.IslandLayout)

local ExtractionSystem = {}

-- Disparado com a lista de quem estava a bordo na decolagem. RoundManager
-- escuta e encerra a partida quando o helicóptero parte.
ExtractionSystem.SurvivorsExtracted = Instance.new("BindableEvent")

local CFG = GameConfig.Extraction

type State = "Idle" | "Inbound" | "Chegando" | "Pousado" | "Partindo" | "Fim"

type Seat = { seat: number, root: BasePart, wasAnchored: boolean }

local state: State = "Idle"
local zone: Model? = nil
local zoneCenter: Vector3 = Vector3.zero
local helicopter: Model? = nil
local rotorPiece: Instance? = nil
local label: TextLabel? = nil
local boardPrompt: ProximityPrompt? = nil
local exitPrompt: ProximityPrompt? = nil
local seatOffsets: { CFrame } = {}
local boarded: { [Player]: Seat } = {}
local approachDir: Vector3 = Vector3.new(0, 0, 1)
-- Altura do PIVÔ no pouso. PivotTo posiciona o pivô, que num helicóptero
-- fica no meio da fuselagem -- usar AlturaPouso direto enterraria os patins
-- (e metade do modelo) na areia. Medido do modelo real no spawn.
local landHeight = 5
local countdownEndsAt = 0 -- os.clock() em que o helicóptero começa a descer
local flightStartedAt = 0 -- os.clock() do início do voo atual
local lastBroadcast = 0
local initialized = false

--------------------------------------------------------------------------------
-- Utilidades
--------------------------------------------------------------------------------

local terrainRay = RaycastParams.new()
terrainRay.FilterType = Enum.RaycastFilterType.Include
terrainRay.FilterDescendantsInstances = { Workspace.Terrain }
terrainRay.IgnoreWater = true

local function groundAt(x: number, z: number): (number?, Enum.Material)
	local hit = Workspace:Raycast(Vector3.new(x, 500, z), Vector3.new(0, -1200, 0), terrainRay)
	if hit then
		return hit.Position.Y, hit.Material
	end
	return nil, Enum.Material.Air
end

local function part(parent: Instance, name: string, size: Vector3, cf: CFrame, material: Enum.Material, color: Color3, collide: boolean?): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.CFrame = cf
	p.Anchored = true
	p.CanCollide = collide == true
	p.Material = material
	p.Color = color
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = parent
	return p
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

-- Sobrevivente (ou Espião infiltrado) vivo e em pé. O Monstro nunca embarca.
local function canBoard(player: Player): boolean
	if player:GetAttribute("Role") == GameConfig.Roles.Monster then
		return false
	end
	if player:GetAttribute("Eliminado") == true or player:GetAttribute("Amarrado") == true then
		return false
	end
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	return character ~= nil and humanoid ~= nil and humanoid.Health > 0
end

local function distanceToZone(player: Player): number
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root or not root:IsA("BasePart") then
		return math.huge
	end
	-- Só no plano: subir num barranco do lado não deveria tirar ninguém da zona.
	local flat = Vector3.new(root.Position.X - zoneCenter.X, 0, root.Position.Z - zoneCenter.Z)
	return flat.Magnitude
end

local function tellEveryone(message: string)
	for _, player in Players:GetPlayers() do
		Remotes.LobbyMessage:FireClient(player, message)
	end
end

--------------------------------------------------------------------------------
-- Onde fica a zona de pouso
--------------------------------------------------------------------------------

--[[
	findBeachSpot()
	Ponto de areia na praia do lado oposto à Estação de Rádio. Anda de fora
	pra dentro a partir da costa até achar Sand acima da linha d'água; se a
	direção escolhida não servir (falésia ou o lago), gira
	alguns graus e tenta de novo.
]]
local function findBeachSpot(): Vector3?
	Layout.Plan()

	local baseAngle = 0
	local radio = Layout.Site("Radio")
	if radio then
		baseAngle = math.atan2(radio.z, radio.x) + math.pi -- lado oposto
	else
		-- Sem o site do rádio: ângulo estável pela seed, pra não mudar a
		-- cada rodada no mesmo mapa.
		baseAngle = (Layout.Seed() % 360) * math.pi / 180
	end

	local beach = Layout.CONFIG.BeachWidth
	local seaLevel = Layout.CONFIG.SeaLevel

	-- Varre ângulos em leque a partir do oposto: 0, +12, -12, +24, -24...
	for i = 0, 14 do
		local offset = math.rad((i // 2) * 12 * (if i % 2 == 0 then 1 else -1))
		local angle = baseAngle + offset
		local coast = Layout.CoastRadiusAt(angle)

		-- Da beira d'água pra dentro, procurando areia firme. Começa a ~40%
		-- da faixa de praia (18 studs de 45) porque a pista tem raio Raio:
		-- centrar perto demais da água deixaria metade do helipad no mar.
		for step = 0, 10 do
			local dist = coast - beach * (0.4 + step * 0.05)
			local x, z = math.cos(angle) * dist, math.sin(angle) * dist
			local y, material = groundAt(x, z)
			if y and material == Enum.Material.Sand and y > seaLevel + 1 then
				local spot = Vector3.new(x, y, z)
				return spot
			end
		end
	end
	return nil
end

--------------------------------------------------------------------------------
-- A zona: pista, fumaça vermelha, feixe e letreiro
--------------------------------------------------------------------------------

local COL = {
	Pad = Color3.fromRGB(46, 44, 42),
	PadLine = Color3.fromRGB(228, 226, 216),
	Smoke = Color3.fromRGB(214, 40, 32),
	Beam = Color3.fromRGB(255, 78, 60),
	Metal = Color3.fromRGB(96, 100, 104),
	Glass = Color3.fromRGB(120, 160, 180),
	Body = Color3.fromRGB(54, 72, 60),
	BodyDark = Color3.fromRGB(38, 50, 42),
}

local function redSmoke(parent: Instance, at: Vector3, index: number)
	local canister = part(parent, "Sinalizador_" .. index, Vector3.new(0.7, 1.4, 0.7), CFrame.new(at + Vector3.new(0, 0.7, 0)), Enum.Material.Metal, Color3.fromRGB(150, 40, 34))

	local emitter = Instance.new("ParticleEmitter")
	emitter.Name = "FumacaVermelha"
	emitter.Texture = "rbxasset://textures/particles/smoke_main.dds"
	emitter.Color = ColorSequence.new(COL.Smoke)
	emitter.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.25),
		NumberSequenceKeypoint.new(1, 1),
	})
	emitter.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 3),
		NumberSequenceKeypoint.new(1, 26),
	})
	emitter.Rate = 22
	emitter.Lifetime = NumberRange.new(5, 8)
	emitter.Speed = NumberRange.new(14, 20)
	emitter.SpreadAngle = Vector2.new(14, 14)
	emitter.Acceleration = Vector3.new(3, 5, 0)
	emitter.LightEmission = 0.35
	emitter.Parent = canister

	local glow = Instance.new("PointLight")
	glow.Color = COL.Beam
	glow.Brightness = 2
	glow.Range = 26
	glow.Shadows = false
	glow.Parent = canister
end

--[[
	buildZone(center)
	Monta a zona inteira. O letreiro é AlwaysOnTop com MaxDistance enorme de
	propósito: é ele que responde "pra onde eu corro?" de qualquer canto da
	ilha, através da floresta e do relevo.
]]
local function buildZone(center: Vector3): Model
	local model = Instance.new("Model")
	model.Name = "ZonaExtracao"
	model:SetAttribute("ZonaExtracao", true)
	model.Parent = getIlha()

	local R = CFG.Raio

	-- Pista: disco escuro com um "H" pintado e borda marcada.
	local pad = part(model, "Pista", Vector3.new(0.4, R * 2, R * 2), CFrame.new(center + Vector3.new(0, 0.2, 0)) * CFrame.Angles(0, 0, math.pi / 2), Enum.Material.Asphalt, COL.Pad)
	pad.Shape = Enum.PartType.Cylinder
	model.PrimaryPart = pad

	for _, dx in { -3.2, 3.2 } do
		part(model, "MarcaH", Vector3.new(1.6, 0.12, 9), CFrame.new(center + Vector3.new(dx, 0.45, 0)), Enum.Material.SmoothPlastic, COL.PadLine)
	end
	part(model, "MarcaH", Vector3.new(6.4, 0.12, 1.6), CFrame.new(center + Vector3.new(0, 0.45, 0)), Enum.Material.SmoothPlastic, COL.PadLine)

	-- Balizas da borda + fumaça vermelha em quatro pontos.
	for i = 1, 8 do
		local a = (i - 1) / 8 * math.pi * 2
		local edge = center + Vector3.new(math.cos(a) * R, 0, math.sin(a) * R)
		local y = groundAt(edge.X, edge.Z)
		local at = Vector3.new(edge.X, y or center.Y, edge.Z)
		local cone = part(model, "Baliza_" .. i, Vector3.new(1.1, 1.6, 1.1), CFrame.new(at + Vector3.new(0, 0.8, 0)), Enum.Material.SmoothPlastic, COL.Beam)
		local light = Instance.new("PointLight")
		light.Color = COL.Beam
		light.Brightness = 1.4
		light.Range = 18
		light.Shadows = false
		light.Parent = cone
		if i % 2 == 1 then
			redSmoke(model, at, i)
		end
	end

	-- Feixe vermelho subindo: o "onde é" visto de longe, sem depender de UI.
	for i = 1, 6 do
		local h = 30
		local beamPart = part(model, "Feixe_" .. i, Vector3.new(h, 7 - i * 0.6, 7 - i * 0.6), CFrame.new(center + Vector3.new(0, 6 + (i - 1) * h, 0)) * CFrame.Angles(0, 0, math.pi / 2), Enum.Material.Neon, COL.Beam)
		beamPart.Shape = Enum.PartType.Cylinder
		beamPart.Transparency = 0.72 + i * 0.03
		beamPart.CanQuery = false
	end

	-- Letreiro visível de qualquer lugar (atravessa terreno e floresta).
	local anchor = part(model, "Letreiro", Vector3.new(1, 1, 1), CFrame.new(center + Vector3.new(0, 34, 0)), Enum.Material.SmoothPlastic, COL.Beam)
	anchor.Transparency = 1
	anchor.CanQuery = false

	local billboard = Instance.new("BillboardGui")
	billboard.Name = "AvisoExtracao"
	billboard.Adornee = anchor
	billboard.AlwaysOnTop = true
	billboard.LightInfluence = 0
	billboard.MaxDistance = 3000
	billboard.Size = UDim2.fromOffset(260, 74)
	billboard.Parent = anchor

	local frame = Instance.new("TextLabel")
	frame.Size = UDim2.fromScale(1, 1)
	frame.BackgroundColor3 = Color3.fromRGB(18, 10, 10)
	frame.BackgroundTransparency = 0.25
	frame.BorderSizePixel = 0
	frame.Font = Enum.Font.GothamBold
	frame.Text = "EXTRAÇÃO"
	frame.TextColor3 = Color3.fromRGB(255, 120, 100)
	frame.TextSize = 22
	frame.TextWrapped = true
	frame.Parent = billboard

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 6)
	corner.Parent = frame

	local stroke = Instance.new("UIStroke")
	stroke.Color = COL.Beam
	stroke.Thickness = 2
	stroke.Parent = frame

	label = frame
	return model
end


--------------------------------------------------------------------------------
-- O helicóptero: modelo, rotor e assentos
--------------------------------------------------------------------------------

local COL_HELI = {
	Metal = Color3.fromRGB(96, 100, 104),
	Glass = Color3.fromRGB(120, 160, 180),
	Body = Color3.fromRGB(54, 72, 60),
	BodyDark = Color3.fromRGB(38, 50, 42),
}

-- Nomes que um modelo de helicóptero costuma dar pro rotor. Procuro por
-- pedaço do nome, em minúsculas, porque cada asset escreve do seu jeito.
local ROTOR_HINTS = { "rotor", "helice", "hélice", "blade", "propeller", "prop", "pas", "palas" }

local function looksLikeRotor(name: string): boolean
	local lower = string.lower(name)
	for _, hint in ROTOR_HINTS do
		if string.find(lower, hint, 1, true) then
			return true
		end
	end
	return false
end

--[[
	findRotor(model)
	Acha o que gira. Prefere um Model (gira inteiro com PivotTo, que é o caso
	de um rotor com várias pás separadas); se não houver, aceita uma BasePart
	só. Devolve nil se o asset não tiver nada com cara de rotor -- aí o
	helicóptero simplesmente não gira, em vez de quebrar.
]]
local function findRotor(model: Model): Instance?
	local fallbackPart: BasePart? = nil
	for _, d in model:GetDescendants() do
		if looksLikeRotor(d.Name) then
			if d:IsA("Model") and d.PrimaryPart then
				return d
			elseif d:IsA("BasePart") and not fallbackPart then
				fallbackPart = d
			end
		end
	end
	return fallbackPart
end

-- Normaliza a escala do asset pelo maior lado (o Toolbox não segue nenhuma).
local function scaleToLength(model: Model, targetLength: number)
	local _, size = model:GetBoundingBox()
	local longest = math.max(size.X, size.Y, size.Z, 0.01)
	model:ScaleTo(model:GetScale() * (targetLength / longest))
end

-- Versão em Parts: entra quando o asset não carrega. Mantém os mesmos nomes
-- ("Rotor", PrimaryPart) que o resto do sistema procura.
local function buildFallbackHelicopter(parent: Instance): Model
	local model = Instance.new("Model")
	model.Name = "Helicoptero"
	model.Parent = parent

	local origin = CFrame.new()
	local body = part(model, "Fuselagem", Vector3.new(7, 6, 16), origin, Enum.Material.Metal, COL_HELI.Body)
	model.PrimaryPart = body
	local glass = part(model, "Cabine", Vector3.new(6.2, 4.4, 5), origin * CFrame.new(0, 0.6, -7), Enum.Material.Glass, COL_HELI.Glass)
	glass.Transparency = 0.45
	part(model, "Cauda", Vector3.new(2, 2, 14), origin * CFrame.new(0, 1.4, 13), Enum.Material.Metal, COL_HELI.Body)
	part(model, "LemeCauda", Vector3.new(0.6, 5, 3), origin * CFrame.new(0, 4, 19), Enum.Material.Metal, COL_HELI.BodyDark)
	part(model, "RotorCauda", Vector3.new(0.5, 6, 0.9), origin * CFrame.new(1.2, 3.4, 18), Enum.Material.Metal, COL_HELI.Metal)

	for _, sx in { -3, 3 } do
		part(model, "Patim", Vector3.new(0.8, 0.8, 13), origin * CFrame.new(sx, -4.2, 0), Enum.Material.Metal, COL_HELI.Metal)
		part(model, "Suporte", Vector3.new(0.5, 3, 0.5), origin * CFrame.new(sx, -2.6, -3), Enum.Material.Metal, COL_HELI.Metal)
		part(model, "Suporte", Vector3.new(0.5, 3, 0.5), origin * CFrame.new(sx, -2.6, 3), Enum.Material.Metal, COL_HELI.Metal)
	end
	part(model, "Mastro", Vector3.new(1.2, 2, 1.2), origin * CFrame.new(0, 4, -1), Enum.Material.Metal, COL_HELI.Metal)

	local rotorModel = Instance.new("Model")
	rotorModel.Name = "Rotor"
	rotorModel.Parent = model
	local hub = part(rotorModel, "Cubo", Vector3.new(1.6, 0.6, 1.6), origin * CFrame.new(0, 5.2, -1), Enum.Material.Metal, COL_HELI.Metal)
	rotorModel.PrimaryPart = hub
	for i = 1, 4 do
		local a = (i - 1) * math.pi / 2
		part(rotorModel, "Pa_" .. i, Vector3.new(1.8, 0.25, 24), origin * CFrame.new(0, 5.2, -1) * CFrame.Angles(0, a, 0) * CFrame.new(0, 0, -12), Enum.Material.Metal, COL_HELI.BodyDark)
	end

	return model
end

--[[
	createHelicopter(parent)
	Carrega o modelo real (CFG.ModeloId) ou cai no fallback em Parts. Devolve
	já ancorado, sem colisão (a colisão liga no pouso) e com o som do rotor
	tocando.
]]
local function createHelicopter(parent: Instance): Model
	local model: Model? = nil

	local template = AssetLoader.Load(CFG.ModeloId)
	if template then
		local clone = template:Clone()
		clone.Name = "Helicoptero"
		scaleToLength(clone, CFG.ComprimentoModelo)
		if not clone.PrimaryPart then
			-- Sem PrimaryPart não dá pra pivotar com precisão: elejo a maior
			-- Part, que num helicóptero é sempre a fuselagem.
			local biggest: BasePart? = nil
			for _, d in clone:GetDescendants() do
				if d:IsA("BasePart") and (not biggest or d.Size.Magnitude > biggest.Size.Magnitude) then
					biggest = d
				end
			end
			clone.PrimaryPart = biggest
		end
		if clone.PrimaryPart then
			clone.Parent = parent
			model = clone
		else
			clone:Destroy()
			warn("[Extraction] O modelo do helicóptero não tem nenhuma BasePart -- usando a versão em Parts.")
		end
	end

	if not model then
		model = buildFallbackHelicopter(parent)
	end
	local heli = model :: Model

	for _, d in heli:GetDescendants() do
		if d:IsA("BasePart") then
			d.Anchored = true
			d.CanCollide = false -- liga só quando pousar
		end
	end

	local sound = Instance.new("Sound")
	sound.Name = "SomHelicoptero"
	sound.SoundId = AssetRegistry.Sounds.Extracao.Helicoptero
	sound.Looped = true
	sound.Volume = 1
	sound.RollOffMode = Enum.RollOffMode.InverseTapered
	sound.RollOffMinDistance = 40
	sound.RollOffMaxDistance = 900
	sound.Parent = heli.PrimaryPart
	sound:Play()

	return heli
end

-- Colisão só na estrutura: pás girando que empurram jogador viram bug, não
-- realismo. (E durante o voo tudo fica sem colisão, senão o helicóptero
-- descendo prensaria quem estivesse na pista.)
local function setSolid(model: Model, solid: boolean, rotorPiece: Instance?)
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			local isRotor = rotorPiece ~= nil and (d == rotorPiece or d:IsDescendantOf(rotorPiece :: Instance))
			d.CanCollide = solid and not isRotor
		end
	end
end

-- Assentos deduzidos da caixa delimitadora: funciona tanto pro modelo real
-- (cuja geometria interna eu não conheço) quanto pro fallback.
local function buildSeatOffsets(model: Model): { CFrame }
	local _, size = model:GetBoundingBox()
	local seats: { CFrame } = {}
	local spread = math.max(1.8, size.X * 0.22)
	for i = 1, 6 do
		local col = (i - 1) % 2 -- duas colunas
		local row = (i - 1) // 2 -- três fileiras
		local x = (if col == 0 then -1 else 1) * spread
		local z = (row - 1) * math.max(2.2, size.Z * 0.16)
		seats[i] = CFrame.new(x, -size.Y * 0.12, z)
	end
	return seats
end

--------------------------------------------------------------------------------
-- Voo: trajetória, atitude e rotor (atualizado TODO FRAME)
--------------------------------------------------------------------------------

local function easeOutCubic(t: number): number
	return 1 - (1 - t) ^ 3
end

local function easeInOutSine(t: number): number
	return -(math.cos(math.pi * t) - 1) / 2
end

local function easeInCubic(t: number): number
	return t * t * t
end

-- Pose final: aponta pra direção de voo, corrige a guinada do modelo e
-- aplica atitude. Pitch positivo = nariz PRA CIMA.
local function flightPose(pos: Vector3, facing: Vector3, pitchDeg: number, rollDeg: number): CFrame
	local dir = if facing.Magnitude > 0.001 then facing.Unit else Vector3.new(0, 0, 1)
	return CFrame.lookAt(pos, pos + dir)
		* CFrame.Angles(0, math.rad(CFG.GuinadaModelo), 0)
		* CFrame.Angles(math.rad(pitchDeg), 0, math.rad(rollDeg))
end

local function entryPoint(): Vector3
	return zoneCenter - approachDir * CFG.DistanciaEntrada + Vector3.new(0, CFG.AlturaEntrada, 0)
end

local function flarePoint(): Vector3
	return zoneCenter + Vector3.new(0, CFG.AlturaFlare, 0)
end

local function groundPoint(): Vector3
	return zoneCenter + Vector3.new(0, landHeight, 0)
end

--[[
	arrivalCFrame(t)
	Chegada em duas partes, como um helicóptero de verdade:
	  t 0..0.68  aproximação -- vem longe e alto, desacelerando, inclinado na
	             curva, nariz baixo acelerando e depois LEVANTANDO o nariz
	             (flare) pra matar a velocidade em cima da pista;
	  t 0.68..1  descida vertical, nivelando até tocar o chão.
]]
local function arrivalCFrame(t: number): CFrame
	local approachEnd = 0.68
	local entry, flare, ground = entryPoint(), flarePoint(), groundPoint()

	if t < approachEnd then
		local a = t / approachEnd
		local pos = entry:Lerp(flare, easeOutCubic(a))

		local pitch
		if a < 0.55 then
			pitch = -CFG.PicoNarizBaixo * math.sin(a / 0.55 * math.pi * 0.5)
		else
			local f = (a - 0.55) / 0.45
			pitch = -CFG.PicoNarizBaixo * (1 - f) + CFG.PicoNarizAlto * f
		end
		local roll = CFG.PicoRolagem * math.sin(a * math.pi) * (1 - a)
		return flightPose(pos, approachDir, pitch, roll)
	end

	local b = (t - approachEnd) / (1 - approachEnd)
	local pos = flare:Lerp(ground, easeInOutSine(b))
	local pitch = CFG.PicoNarizAlto * (1 - b)
	return flightPose(pos, approachDir, pitch, 0)
end

--[[
	departureCFrame(t)
	Partida: sobe reto tirando os patins do chão, depois acelera pro mar
	ganhando altura, com o nariz baixo e inclinando na saída.
]]
local function departureCFrame(t: number): CFrame
	local climbEnd = 0.3
	local ground, flare = groundPoint(), flarePoint()
	local exit = zoneCenter - approachDir * CFG.DistanciaEntrada + Vector3.new(0, CFG.AlturaEntrada, 0)

	if t < climbEnd then
		local a = t / climbEnd
		local pos = ground:Lerp(flare, easeInOutSine(a))
		return flightPose(pos, approachDir, CFG.PicoNarizAlto * 0.35 * a, 0)
	end

	local b = (t - climbEnd) / (1 - climbEnd)
	local pos = flare:Lerp(exit, easeInCubic(b))
	local pitch = -CFG.PicoNarizBaixo * math.sin(b * math.pi)
	local roll = -CFG.PicoRolagem * math.sin(b * math.pi) * 0.8
	-- Sai de ré em relação à chegada: vira e vai embora pro mar.
	return flightPose(pos, -approachDir, pitch, roll)
end

local function spinRotor(dt: number)
	local piece = rotorPiece
	if not piece then
		return
	end
	local delta = dt * CFG.RotorRPS * math.pi * 2
	if piece:IsA("Model") and piece.PrimaryPart then
		piece:PivotTo(piece:GetPivot() * CFrame.Angles(0, delta, 0))
	elseif piece:IsA("BasePart") then
		piece.CFrame = piece.CFrame * CFrame.Angles(0, delta, 0)
	end
end

-- Passageiros acompanham o helicóptero pela pose relativa do assento (mesmo
-- truque de manter o root ancorado + CFrame por frame).
local function lockPassengers()
	local model = helicopter
	if not model then
		return
	end
	local pivot = model:GetPivot()
	for _, info in boarded do
		if info.root.Parent then
			info.root.CFrame = pivot * (seatOffsets[info.seat] or CFrame.new())
		end
	end
end

--------------------------------------------------------------------------------
-- Embarque, desembarque e a escolha na tela
--------------------------------------------------------------------------------

local function formatTime(seconds: number): string
	local s = math.max(0, math.ceil(seconds))
	return string.format("%d:%02d", s // 60, s % 60)
end

local function setLabel(text: string, color: Color3?)
	local current = label
	if current then
		current.Text = text
		if color then
			current.TextColor3 = color
		end
	end
end

local function boardedCount(): number
	local n = 0
	for _ in boarded do
		n += 1
	end
	return n
end

local function freeSeat(): number?
	local taken: { [number]: boolean } = {}
	for _, info in boarded do
		taken[info.seat] = true
	end
	for i = 1, #seatOffsets do
		if not taken[i] then
			return i
		end
	end
	return nil
end

local function refreshPrompts()
	local board = boardPrompt
	if board then
		board.Enabled = state == "Pousado" and freeSeat() ~= nil
	end
	local exit = exitPrompt
	if exit then
		exit.Enabled = state == "Pousado" and boardedCount() > 0
	end
end

local function unboard(player: Player, message: string?)
	local info = boarded[player]
	if not info then
		return
	end
	boarded[player] = nil

	if info.root.Parent then
		info.root.Anchored = info.wasAnchored
		-- Coloca do lado de fora: soltar alguém DENTRO da fuselagem sólida
		-- deixaria o personagem preso na geometria.
		local model = helicopter
		if model then
			local side = model:GetPivot() * CFrame.new(0, 0, 0)
			local outside = Vector3.new(side.Position.X, zoneCenter.Y + 4, side.Position.Z)
				+ (side.RightVector * (CFG.Raio * 0.55))
			info.root.CFrame = CFrame.new(outside)
		end
	end

	Remotes.ExtractionChoice:FireClient(player, "Fechar")
	if message then
		Remotes.LobbyMessage:FireClient(player, message)
	end
	refreshPrompts()
end

local function board(player: Player)
	if state ~= "Pousado" or boarded[player] then
		return
	end
	if not canBoard(player) then
		return
	end
	if distanceToZone(player) > CFG.Raio + 8 then
		return
	end

	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root or not root:IsA("BasePart") then
		return
	end

	local seat = freeSeat()
	if not seat then
		Remotes.LobbyMessage:FireClient(player, "O helicóptero está lotado.")
		return
	end

	boarded[player] = { seat = seat, root = root, wasAnchored = root.Anchored }
	root.Anchored = true
	lockPassengers()

	-- As duas opções: partir agora ou segurar o voo pelos outros.
	Remotes.ExtractionChoice:FireClient(player, "Abrir")
	setLabel(string.format("A BORDO: %d", boardedCount()), Color3.fromRGB(140, 255, 150))
	refreshPrompts()
	print(string.format("[Extraction] %s embarcou (%d a bordo).", player.Name, boardedCount()))
end

local beginDeparture: (Player?) -> ()

-- Client -> Server: "Partir" | "Esperar". Quem não está a bordo é ignorado.
local function onChoice(player: Player, choice: unknown)
	if not boarded[player] then
		return
	end
	if choice == "Partir" then
		beginDeparture(player)
	elseif choice == "Esperar" then
		Remotes.ExtractionChoice:FireClient(player, "Fechar")
		Remotes.LobbyMessage:FireClient(player, "Segurando o voo. Use o prompt pra sair, ou espere os outros.")
	end
end

--------------------------------------------------------------------------------
-- Máquina de estados
--------------------------------------------------------------------------------

local function clearWorld()
	for player in boarded do
		unboard(player)
	end
	table.clear(boarded)

	if zone then
		zone:Destroy()
		zone = nil
	end
	if helicopter then
		helicopter:Destroy()
		helicopter = nil
	end
	rotorPiece = nil
	boardPrompt = nil
	exitPrompt = nil
	label = nil
	table.clear(seatOffsets)
end

local function newPrompt(host: BasePart, name: string, action: string, hold: number): ProximityPrompt
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = name
	prompt.ActionText = action
	prompt.ObjectText = "Helicóptero"
	prompt.HoldDuration = hold
	prompt.MaxActivationDistance = 14
	prompt.RequiresLineOfSight = false
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.GamepadKeyCode = Enum.KeyCode.ButtonX
	prompt.ClickablePrompt = true
	prompt.Enabled = false
	prompt.Parent = host
	return prompt
end

local function spawnHelicopter()
	local model = createHelicopter(getIlha())
	helicopter = model
	rotorPiece = findRotor(model)
	seatOffsets = buildSeatOffsets(model)

	-- Quanto o pivô fica acima da base do modelo, pra pousar os patins no
	-- chão em vez de enfiar a fuselagem na areia.
	local boxCF, boxSize = model:GetBoundingBox()
	landHeight = (model:GetPivot().Position.Y - (boxCF.Position.Y - boxSize.Y / 2)) + CFG.AlturaPouso

	-- Vem do mar pra terra: a direção de voo aponta pro centro da ilha.
	local outward = Vector3.new(zoneCenter.X, 0, zoneCenter.Z)
	approachDir = if outward.Magnitude > 1 then -outward.Unit else Vector3.new(0, 0, 1)

	local host = model.PrimaryPart
	if host then
		boardPrompt = newPrompt(host, "EmbarcarHelicoptero", "Embarcar", 0.5)
		exitPrompt = newPrompt(host, "SairHelicoptero", "Sair", 0.5)
		;(boardPrompt :: ProximityPrompt).Triggered:Connect(board)
		;(exitPrompt :: ProximityPrompt).Triggered:Connect(function(player: Player)
			unboard(player, "Você desembarcou.")
		end)
	end

	model:PivotTo(arrivalCFrame(0))
	state = "Chegando"
	flightStartedAt = os.clock()
	setLabel("CHEGANDO")
end

local function onLanded()
	state = "Pousado"
	local model = helicopter
	if model then
		model:PivotTo(arrivalCFrame(1))
		-- Sólido só agora: no ar ele prensaria quem estivesse na pista.
		setSolid(model, true, rotorPiece)
	end
	setLabel("EMBARQUE ABERTO", Color3.fromRGB(140, 255, 150))
	refreshPrompts()
	Remotes.ObjectiveProgress:FireAllClients("ExtracaoPousou", 1, 1)
	tellEveryone("O helicóptero pousou. Interaja pra embarcar!")
	print("[Extraction] Helicóptero pousou -- embarque liberado.")
end

local function finishDeparture()
	state = "Fim"

	local rescued: { Player } = {}
	for player, info in boarded do
		if info.root.Parent then
			info.root.Anchored = info.wasAnchored
		end
		if player.Parent == Players then
			table.insert(rescued, player)
		end
	end
	table.clear(boarded)

	local names = {}
	for _, player in rescued do
		table.insert(names, player.Name)
	end
	print(string.format("[Extraction] Helicóptero partiu com %d a bordo: %s", #rescued, table.concat(names, ", ")))

	Remotes.ObjectiveProgress:FireAllClients("ExtracaoConcluida", #rescued, #Players:GetPlayers(), rescued)
	ExtractionSystem.SurvivorsExtracted:Fire(rescued)
end

-- Declarada lá em cima (onChoice precisa dela antes desta linha).
function beginDeparture(byPlayer: Player?)
	if state ~= "Pousado" or boardedCount() == 0 then
		return
	end

	state = "Partindo"
	flightStartedAt = os.clock()

	local model = helicopter
	if model then
		setSolid(model, false, rotorPiece) -- subindo, não empurra ninguém
	end
	for player in boarded do
		Remotes.ExtractionChoice:FireClient(player, "Fechar")
	end
	if boardPrompt then
		boardPrompt.Enabled = false
	end
	if exitPrompt then
		exitPrompt.Enabled = false
	end

	setLabel("DECOLANDO", Color3.fromRGB(255, 220, 120))
	tellEveryone(string.format("O helicóptero decolou com %d a bordo!", boardedCount()))
	print(string.format("[Extraction] Decolagem pedida por %s.", byPlayer and byPlayer.Name or "ninguém"))
end

-- Todo frame: voo, rotor e passageiros. Separado do step() throttled porque
-- animação a 4 fps fica travada -- e o pedido era justamente o contrário.
local function updateFlight(dt: number)
	local model = helicopter
	if not model or not model.PrimaryPart then
		return
	end

	local now = os.clock()
	if state == "Chegando" then
		local t = math.clamp((now - flightStartedAt) / CFG.DuracaoChegada, 0, 1)
		model:PivotTo(arrivalCFrame(t))
		if t >= 1 then
			onLanded()
		end
	elseif state == "Partindo" then
		local t = math.clamp((now - flightStartedAt) / CFG.DuracaoPartida, 0, 1)
		model:PivotTo(departureCFrame(t))
		if t >= 1 then
			finishDeparture()
			return
		end
	end

	spinRotor(dt)
	lockPassengers()
end

-- Throttled: contagem, avisos e as checagens que não precisam de 60 fps.
local function step()
	local now = os.clock()

	if state == "Inbound" then
		local remaining = countdownEndsAt - now
		setLabel(string.format("HELICÓPTERO EM %s", formatTime(remaining)))

		if now - lastBroadcast >= 1 then
			lastBroadcast = now
			local total = math.max(1, GameConfig.RadioObjective.RescueCountdownDuration)
			Remotes.ObjectiveProgress:FireAllClients("ExtracaoChamada", math.max(0, math.ceil(remaining)), total)
		end

		if remaining <= 0 then
			spawnHelicopter()
			print("[Extraction] Contagem zerou -- helicóptero na aproximação.")
		end
		return
	end

	if state == "Pousado" then
		-- Quem morreu ou foi amarrado no assento perde a vaga.
		for player in boarded do
			if not canBoard(player) then
				unboard(player)
			end
		end
		local n = boardedCount()
		if n > 0 then
			setLabel(string.format("A BORDO: %d", n), Color3.fromRGB(140, 255, 150))
		else
			setLabel("EMBARQUE ABERTO", Color3.fromRGB(140, 255, 150))
		end
		refreshPrompts()
	end
end

--------------------------------------------------------------------------------
-- API
--------------------------------------------------------------------------------

--[[
	Begin(duration)
	Chama o resgate: monta a zona na praia e começa a contagem. Devolve false
	se não deu pra achar praia (mapa sem ilha gerada, por exemplo) -- aí quem
	chamou decide o que fazer, porque deixar a partida sem desfecho seria
	pior do que qualquer alternativa.
]]
function ExtractionSystem.Begin(duration: number?): boolean
	if state ~= "Idle" then
		return true -- já chamado nesta rodada
	end

	local spot = findBeachSpot()
	if not spot then
		warn("[Extraction] Não achei praia pra zona de extração -- o resgate não tem onde pousar.")
		return false
	end

	zoneCenter = spot
	zone = buildZone(spot)
	state = "Inbound"
	table.clear(boarded)
	lastBroadcast = 0
	countdownEndsAt = os.clock() + (duration or GameConfig.RadioObjective.RescueCountdownDuration)

	local total = math.max(1, duration or GameConfig.RadioObjective.RescueCountdownDuration)
	Remotes.ObjectiveProgress:FireAllClients("ExtracaoChamada", math.ceil(total), math.ceil(total))
	tellEveryone("Resgate a caminho! Corra até a fumaça vermelha na praia.")
	print(string.format("[Extraction] Zona de extração em (%.0f, %.0f) -- pouso em %ds.", spot.X, spot.Z, total))
	return true
end

--[[
	Reset()
	Apaga a zona e o helicóptero e volta pro estado inicial. RoundManager
	chama no preparo de cada rodada.
]]
function ExtractionSystem.Reset()
	clearWorld()
	state = "Idle"
	countdownEndsAt = 0
	flightStartedAt = 0
	lastBroadcast = 0
	zoneCenter = Vector3.zero
end

function ExtractionSystem.IsActive(): boolean
	return state ~= "Idle" and state ~= "Fim"
end

function ExtractionSystem.Init()
	if initialized then
		return
	end
	initialized = true

	Remotes.ExtractionChoice.OnServerEvent:Connect(onChoice)
	Players.PlayerRemoving:Connect(function(player)
		boarded[player] = nil
	end)

	local elapsed = 0
	RunService.Heartbeat:Connect(function(dt)
		if state == "Idle" then
			return
		end

		-- Voo todo frame (suavidade), resto throttled.
		updateFlight(dt)

		elapsed += dt
		if elapsed < CFG.IntervaloChecagem then
			return
		end
		elapsed = 0
		step()
	end)

	print("[Extraction] Pronto -- esperando o pedido de socorro do rádio.")
end

return ExtractionSystem
