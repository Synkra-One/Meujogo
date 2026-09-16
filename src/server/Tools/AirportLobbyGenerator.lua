--!strict
--[[
	AirportLobbyGenerator (ferramenta de editor)

	Monta o LOBBY do jogo: um terminal de aeroporto compacto em volta do
	spawn que já existe. Não é um aeroporto inteiro -- é só a fatia interna
	que um terminal real teria entre a porta da rua e o portão de embarque:

		entrada -> check-in -> segurança -> concourse -> sala de embarque
		-> parede de vidro -> (área externa futura: pista, aviões, veículos)

	USO (Command Bar do Studio, em MODO DE EDIÇÃO, e salve com Ctrl+S depois):

		local Lobby = require(game.ServerScriptService.Server.Tools.AirportLobbyGenerator)
		Lobby.Generate()                      -- apaga e refaz Workspace.Lobby
		Lobby.Generate({ Terrain = false })    -- sem mexer no Terrain
		Lobby.Generate({ Assets = false })     -- só Parts + placeholders
		Lobby.Clear()

	ATENÇÃO: Generate() DESTRÓI Workspace.Lobby antes de refazer. Se você
	posicionou assets do Toolbox na mão lá dentro, eles vão junto. Tire-os da
	pasta antes de regerar.

	ÂNCORA
	  ORIGIN = LobbyManager.LOBBY_ORIGIN = (0, 40, -1500), e ORIGIN.Y é o
	  NÍVEL DO PISO ACABADO. Tudo aqui é relativo a ele: +Z = lado da rua,
	  -Z = lado da pista, +Y = cima.

	  Isso é de propósito. LobbyManager reescreve LobbySpawn/LobbyFloor/
	  IniciarPartida nessa posição TODO boot (ver o cabeçalho dele), então o
	  terminal é desenhado em volta dessas peças em vez de brigar com elas:

	    LobbySpawn      (0, 0.5, 0)   -> meio do saguão de check-in, de frente
	                                     pro vidro. O jogador nasce vendo o
	                                     terminal inteiro em enfiada: fascia
	                                     da segurança, salão alto, poltronas
	                                     e a janela panorâmica no fundo.
	    IniciarPartida  (0, 0.5, 20)  -> vira o totem de auto-atendimento no
	                                     meio do check-in.
	    LobbyFloor      (0, -1, 0)    -> fica ENTERRADO no piso novo; o
	                                     gerador só o deixa invisível (sem
	                                     tocar em LobbyManager, que não
	                                     regrava Transparency).

	  Pra mover o lobby, mude LOBBY_ORIGIN em LobbyManager e ORIGIN aqui.

	ELEVAÇÃO (terminal x pista)
	  O piso do terminal fica em ORIGIN.Y = 40, bem ACIMA do nível do chão
	  externo (GROUND_LEVEL_Y = 9, mais abaixo neste arquivo) onde ficam a
	  grama e o pátio pavimentado -- e onde, no futuro, ficam pista e aviões.
	  Área de embarque não pode estar na mesma altura de onde os aviões vão
	  taxiar; o salão de embarque de um terminal real fica um andar inteiro
	  acima da rampa. Os ~30 studs de diferença são preenchidos por uma
	  FUNDAÇÃO visível (Lobby/Airport/Foundation): paredes de concreto que
	  "plantam" o prédio no chão em vez de deixá-lo flutuando -- ver
	  buildFoundation() mais abaixo. Cair a grama nesse vão (por resíduo de
	  Terrain de uma versão antiga) deixou de ser sequer visível de dentro do
	  salão: o piso e a grama agora estão 30 studs distantes um do outro.

	VIZINHANÇA (não encostar)
	  - Terreno da ilha: IslandLayout.AreaHalf = 960, logo |z| <= 960. O
	    terminal vive em z -1456..-1612: longe.
	  - Sala de espera (WaitingRoomManager.origin): (120, 10, -1500), 52x44
	    -> ocupa x 94..146. A parede leste daqui para em x = +58.

	ASSETS DO TOOLBOX (InsertService -- só funciona em MODO DE EDIÇÃO)
	  Se o asset carrega, entra no lugar certo, ancorado e escalado pro
	  tamanho que a arquitetura reservou. Se não carrega (runtime, asset
	  privado, offline), o gerador constrói a versão equivalente em Part E
	  deixa um marcador invisível em Lobby/Airport/AssetPlaceholders com o
	  CFrame exato e o AssetId no Attribute. A arquitetura nunca depende de
	  asset nenhum.

	MARCADORES PRO FUTURO (Attributes; nenhum sistema lê isto ainda)
	  PontoEmbarque = true     balcão do portão -- âncora do matchmaking
	  PainelVoo = true         painel do voo (SurfaceGui com os labels
	                           Voo/Destino/Status/Passageiros já nomeados)
	  AreaFuturaPista = true   envelope reservado pra pista/aviões/veículos
]]

local Workspace = game:GetService("Workspace")
local InsertService = game:GetService("InsertService")
local Terrain = Workspace.Terrain

local S = require(script.Parent.Structures)

local AirportLobby = {}

local M = Enum.Material
local V3 = Vector3.new

-- Cilindro em pé: a Part "Cylinder" do Roblox tem o eixo em X local, então
-- qualquer coisa vertical e redonda nasce deitada sem isto.
local UPRIGHT = CFrame.Angles(0, 0, math.pi / 2)

--------------------------------------------------------------------------------
-- Medidas
--------------------------------------------------------------------------------

-- PRECISA bater com LobbyManager.LOBBY_ORIGIN.
local ORIGIN = Vector3.new(0, 40, -1500)

-- Nível do chão EXTERNO (grama/pátio/pista futura), independente da altura
-- do terminal -- NÃO usar ORIGIN.Y pra nada que fique do lado de fora do
-- vidro. Era o antigo ORIGIN.Y (10) de antes desta revisão elevar o prédio.
local GROUND_LEVEL_Y = 9

local L = {
	HalfWidth = 56, -- face INTERNA das paredes laterais (x = +-56)
	WallThick = 2,

	-- Cortes em Z, da rua pra pista. As profundidades dão ritmo: vestíbulo
	-- curto, check-in largo (o spawn cai aqui, em z = 0), segurança
	-- comprimida, concourse alta, embarque larga.
	ZFacade = 44,
	ZCheckIn = 28,
	ZSecurity = -8,
	ZConcourse = -32,
	ZWaiting = -52,
	ZPromenade = -80, -- fim das poltronas; daqui ao vidro é passeio livre
	ZGlass = -104,
	ZEave = -112, -- beiral: o telhado avança pra cobrir o vidro inclinado

	-- Pé-direito por faixa. A sequência 18 -> 26 -> 19 -> 34 é o truque de
	-- level design: comprime na segurança pra que o salão pareça enorme.
	HVestibule = 18,
	HCheckIn = 26,
	HSecurity = 19,
	HMain = 34,

	GlassSill = 1,
	GlassTop = 22, -- topo do trecho VERTICAL do vidro
	GlassApex = 33, -- topo do trecho INCLINADO (encosta no beiral)
	GlassLean = -6.5, -- quanto a inclinação avança pra fora, em Z

	-- 8 vãos de 14 studs = 112 = largura interna exata.
	GlassBays = 8,
	GlassBayWidth = 14,

	FloorDepth = 3,
	-- GroundDrop foi removido: a grama agora usa GROUND_LEVEL_Y (absoluto),
	-- não mais uma altura relativa ao piso do terminal -- ver o cabeçalho.
}

local C = {
	Floor = Color3.fromRGB(203, 200, 194),
	FloorJoint = Color3.fromRGB(157, 155, 150),
	FloorRunner = Color3.fromRGB(116, 119, 126),
	FloorAccent = Color3.fromRGB(176, 148, 106),
	Wall = Color3.fromRGB(214, 213, 209),
	WallDark = Color3.fromRGB(146, 148, 151),
	Skirting = Color3.fromRGB(88, 91, 96),
	Ceiling = Color3.fromRGB(228, 228, 226),
	Steel = Color3.fromRGB(131, 136, 142),
	SteelDark = Color3.fromRGB(70, 74, 80),
	Mullion = Color3.fromRGB(58, 62, 68),
	Glass = Color3.fromRGB(198, 220, 229),
	Counter = Color3.fromRGB(238, 237, 234),
	CounterTop = Color3.fromRGB(54, 58, 64),
	Screen = Color3.fromRGB(14, 18, 26),
	Accent = Color3.fromRGB(0, 92, 158), -- azul institucional do terminal
	AccentWarm = Color3.fromRGB(216, 146, 44),
	SignFace = Color3.fromRGB(22, 28, 36),
	TextOnSign = Color3.fromRGB(238, 242, 248),
	LightWarm = Color3.fromRGB(255, 245, 224),
	Apron = Color3.fromRGB(120, 122, 125),
	Rubber = Color3.fromRGB(36, 38, 42),
	Plant = Color3.fromRGB(56, 110, 50),
	Seat = Color3.fromRGB(36, 62, 96),
	Belt = Color3.fromRGB(44, 46, 50),
}

--------------------------------------------------------------------------------
-- Primitivas (tudo em coordenadas RELATIVAS a ORIGIN, y = 0 no piso)
--------------------------------------------------------------------------------

local function at(x: number, y: number, z: number): CFrame
	return CFrame.new(ORIGIN.X + x, ORIGIN.Y + y, ORIGIN.Z + z)
end

local function atYaw(x: number, y: number, z: number, yawDeg: number): CFrame
	return at(x, y, z) * CFrame.Angles(0, math.rad(yawDeg), 0)
end

-- Como `at()`, mas com Y ABSOLUTO em vez de relativo ao piso do terminal --
-- pra tudo que precisa ficar no nível do chão externo (grama, pátio, futura
-- pista), que não sobe junto quando o terminal fica mais alto.
local function atGround(x: number, y: number, z: number): CFrame
	return CFrame.new(ORIGIN.X + x, y, ORIGIN.Z + z)
end

type Opts = {
	Shape: Enum.PartType?,
	CanCollide: boolean?,
	Transparency: number?,
	CastShadow: boolean?,
}

local function box(parent: Instance, name: string, size: Vector3, cf: CFrame, mat: Enum.Material, col: Color3, opts: Opts?): Part
	return S.Part(parent, name, size, cf, mat, col, opts)
end

-- Decoração: sem colisão, sem sombra, fora do raycast. É o grosso da
-- contagem de peças, então é aqui que a otimização acontece de verdade.
local DECO: Opts = { CanCollide = false, CastShadow = false }

local function deco(parent: Instance, name: string, size: Vector3, cf: CFrame, mat: Enum.Material, col: Color3): Part
	local p = box(parent, name, size, cf, mat, col, DECO)
	p.CanQuery = false
	p.CanTouch = false
	return p
end

local function cylinder(parent: Instance, name: string, size: Vector3, cf: CFrame, mat: Enum.Material, col: Color3, collide: boolean?): Part
	local p = box(parent, name, size, cf, mat, col, { Shape = Enum.PartType.Cylinder, CanCollide = collide == true, CastShadow = false })
	if collide ~= true then
		p.CanQuery = false
		p.CanTouch = false
	end
	return p
end

local function folder(parent: Instance, name: string): Folder
	local f = Instance.new("Folder")
	f.Name = name
	f.Parent = parent
	return f
end

-- Caixa alongada entre dois pontos do mundo (fitas dos organizadores de fila).
local function spanBox(parent: Instance, name: string, a: Vector3, b: Vector3, thick: number, height: number, mat: Enum.Material, col: Color3)
	local len = (b - a).Magnitude
	if len < 0.05 then
		return
	end
	deco(parent, name, V3(thick, height, len), CFrame.lookAt((a + b) * 0.5, b), mat, col)
end

-- Texto numa face da peça. Toda a sinalização do terminal passa por aqui.
local function label(host: BasePart, face: Enum.NormalId, text: string, color: Color3, font: Enum.Font, alignLeft: boolean?): TextLabel
	local gui = Instance.new("SurfaceGui")
	gui.Name = "Sign_" .. face.Name
	gui.Face = face
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 40
	gui.LightInfluence = 0 -- placa de aeroporto é retroiluminada: não escurece
	gui.Parent = host

	local tl = Instance.new("TextLabel")
	tl.Name = "Text"
	tl.Size = UDim2.fromScale(0.94, 0.86)
	tl.Position = UDim2.fromScale(0.03, 0.07)
	tl.BackgroundTransparency = 1
	tl.Text = text
	tl.Font = font
	tl.TextColor3 = color
	tl.TextScaled = true
	tl.TextWrapped = true
	tl.TextXAlignment = if alignLeft then Enum.TextXAlignment.Left else Enum.TextXAlignment.Center
	tl.Parent = gui
	return tl
end

local function pointLight(host: BasePart, range: number, brightness: number, color: Color3)
	local light = Instance.new("PointLight")
	light.Range = range
	light.Brightness = brightness
	light.Color = color
	light.Shadows = false -- luz sem sombra é ordens de grandeza mais barata
	light.Parent = host
end

--------------------------------------------------------------------------------
-- Assets do Toolbox
--------------------------------------------------------------------------------

type AssetSpec = {
	Id: number,
	Label: string, -- nome legível; aparece no relatório final
	Footprint: number?, -- maior dimensão horizontal que o projeto reservou
	Ground: boolean?, -- true (padrão): assenta a BASE no y do CFrame
}

local ASSETS: { [string]: AssetSpec } = {
	Seats = { Id = 10183298246, Label = "Airport Seats", Footprint = 19, Ground = true },
	SecurityGate = { Id = 10759833003, Label = "Security Gate", Footprint = 8, Ground = true },
	Scanner = { Id = 10131830908, Label = "Luggage Scanner", Footprint = 13, Ground = true },
	Sign = { Id = 13776711189, Label = "Airport Sign", Footprint = 14, Ground = false },
	CeilingLight = { Id = 91305696624692, Label = "Ceiling Light", Footprint = 7, Ground = false },
	Vending = { Id = 5645721073, Label = "Vending Machine", Footprint = 5, Ground = true },
	Computer = { Id = 8301328809, Label = "Computador", Footprint = 2.4, Ground = true },
	Clock = { Id = 8084763732, Label = "Relógio", Footprint = 4.5, Ground = false },
}

local assetCache: { [number]: Model } = {}
local assetFailed: { [number]: boolean } = {}
local placeholderFolder: Folder? = nil
local report: { [number]: { Label: string, Loaded: number, Missing: number } } = {}
local useAssets = true

local function reportFor(spec: AssetSpec)
	local row = report[spec.Id]
	if not row then
		row = { Label = spec.Label, Loaded = 0, Missing = 0 }
		report[spec.Id] = row
	end
	return row
end

-- Mesma estratégia do RadioTowerGenerator: LoadAsset e, se falhar, GetObjects.
-- Os dois só funcionam em modo de edição; em runtime cai no fallback em Parts.
local function loadAssetModel(assetId: number): Model?
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
		return nil
	end

	local holder = container :: Instance
	holder.Parent = nil
	for _, d in holder:GetDescendants() do
		if d:IsA("LuaSourceContainer") then
			d:Destroy() -- nunca deixar script de Toolbox entrar no lugar
		elseif d:IsA("BasePart") then
			d.Anchored = true
		end
	end

	local children = holder:GetChildren()
	local model: Model
	if #children == 1 and children[1]:IsA("Model") then
		model = (children[1] :: Model):Clone()
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

	if not model:FindFirstChildWhichIsA("BasePart", true) then
		assetFailed[assetId] = true
		return nil
	end

	assetCache[assetId] = model
	return model
end

local function modelBottomY(model: Model): number?
	local minY = math.huge
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			local cf, s = d.CFrame, d.Size
			local ext = math.abs(cf.RightVector.Y) * s.X
				+ math.abs(cf.UpVector.Y) * s.Y
				+ math.abs(cf.LookVector.Y) * s.Z
			minY = math.min(minY, cf.Position.Y - ext * 0.5)
		end
	end
	return if minY < math.huge then minY else nil
end

local function makePlaceholder(spec: AssetSpec, name: string, cf: CFrame)
	local parent = placeholderFolder
	if not parent then
		return
	end
	local m = S.Marker(parent, "PLACEHOLDER_" .. name, cf, {
		AssetId = spec.Id,
		AssetName = spec.Label,
		ColocarAqui = true,
	})
	m:SetAttribute("CFrameAlvo", cf)
	reportFor(spec).Missing += 1
end

--[[
	Tenta colocar o asset do Toolbox em `cf`. Conseguindo, devolve o Model já
	ancorado, escalado pro tamanho que a arquitetura reservou e assentado no
	chão. Falhando, chama `fallback` (que constrói o equivalente em Parts) e
	registra um marcador invisível em AssetPlaceholders.
]]
local function placeAsset(parent: Instance, spec: AssetSpec, name: string, cf: CFrame, fallback: (Instance, CFrame) -> ()): Model?
	local template = if useAssets then loadAssetModel(spec.Id) else nil
	if not template then
		fallback(parent, cf)
		makePlaceholder(spec, name, cf)
		return nil
	end

	local model = template:Clone()
	model.Name = name

	-- Normaliza a escala: um asset de Toolbox pode vir em qualquer tamanho e
	-- não dá pra saber antes. Só mexe se estiver mesmo fora da faixa, pra não
	-- distorcer um asset que já veio certo.
	local footprint = spec.Footprint
	if footprint then
		local _, size = model:GetBoundingBox()
		local largest = math.max(size.X, size.Z)
		if largest > 0.1 then
			local scale = footprint / largest
			if scale < 0.72 or scale > 1.4 then
				local okScale = pcall(function()
					model:ScaleTo(model:GetScale() * scale)
				end)
				if not okScale then
					warn(string.format("[AirportLobby] Não deu pra escalar %s (%d).", spec.Label, spec.Id))
				end
			end
		end
	end

	model:PivotTo(cf)
	if spec.Ground ~= false then
		local bottom = modelBottomY(model)
		if bottom then
			model:PivotTo(model:GetPivot() + V3(0, cf.Position.Y - bottom, 0))
		end
	end

	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			d.Anchored = true
		end
	end
	model:SetAttribute("AssetId", spec.Id)
	model:SetAttribute("AssetName", spec.Label)
	model.Parent = parent
	reportFor(spec).Loaded += 1
	return model
end

--------------------------------------------------------------------------------
-- Arquitetura: piso
--------------------------------------------------------------------------------

local function buildFloor(parent: Instance)
	local f = folder(parent, "Floor")

	local depth = L.ZFacade - L.ZEave
	local zMid = (L.ZFacade + L.ZEave) / 2
	local width = L.HalfWidth * 2 + L.WallThick * 2

	local slab = box(f, "FloorSlab", V3(width, L.FloorDepth, depth), at(0, -L.FloorDepth / 2, zMid), M.Concrete, C.Floor)
	slab.Reflectance = 0.05

	-- Embasamento: avança 4 studs além das paredes. Como a grama externa fica
	-- 1 stud abaixo do piso, o que aparece por fora é uma soleira de concreto
	-- em vez de uma laje flutuando.
	deco(f, "Plinth", V3(width + 8, L.FloorDepth + 1, depth + 8), at(0, -(L.FloorDepth + 1) / 2 - 0.4, zMid), M.Concrete, C.Apron)

	-- Juntas do piso: 0,05 acima da laje e sem colisão, então não brigam por
	-- profundidade com ela nem criam degrau.
	local jy, jt = 0.05, 0.2
	local runLen = L.ZFacade - L.ZGlass
	local runMid = (L.ZFacade + L.ZGlass) / 2

	deco(f, "RunnerBand", V3(18, jt, runLen), at(0, jy, runMid), M.SmoothPlastic, C.FloorRunner).Reflectance = 0.04
	for _, x in { -44, -28, 28, 44 } do
		deco(f, "JointX_" .. tostring(x), V3(0.7, jt, runLen), at(x, jy, runMid), M.SmoothPlastic, C.FloorJoint)
	end
	for _, z in { L.ZCheckIn, L.ZSecurity, L.ZConcourse, L.ZWaiting, L.ZPromenade } do
		deco(f, "JointZ_" .. tostring(z), V3(112, jt, 0.7), at(0, jy, z), M.SmoothPlastic, C.FloorJoint)
	end

	-- Faixa de advertência colada no vidro.
	deco(f, "GlassWarningBand", V3(112, jt, 3), at(0, jy, L.ZGlass + 3), M.SmoothPlastic, C.FloorAccent)

	-- Medalhão no spawn: dá um motivo visual pro jogador nascer exatamente ali.
	cylinder(f, "SpawnMedallion", V3(jt, 16, 16), at(0, jy, 0) * UPRIGHT, M.SmoothPlastic, C.Accent)
	cylinder(f, "SpawnMedallionInner", V3(jt + 0.02, 11, 11), at(0, jy + 0.03, 0) * UPRIGHT, M.SmoothPlastic, C.Floor)
end

--------------------------------------------------------------------------------
-- Arquitetura: paredes
--------------------------------------------------------------------------------

local function sideWalls(f: Instance, name: string, zFront: number, zBack: number, height: number)
	local depth = zFront - zBack
	local zMid = (zFront + zBack) / 2

	for _, side in { -1, 1 } do
		local tag = name .. "_" .. (if side < 0 then "W" else "E")
		box(f, "Wall_" .. tag, V3(L.WallThick, height, depth), at((L.HalfWidth + L.WallThick / 2) * side, height / 2, zMid), M.Concrete, C.Wall)
		-- Rodapé escuro: ancora a parede no chão e esconde a emenda.
		deco(f, "Skirting_" .. tag, V3(0.5, 2, depth), at((L.HalfWidth - 0.2) * side, 1, zMid), M.SmoothPlastic, C.Skirting)
		-- Faixa horizontal de acabamento.
		deco(f, "Band_" .. tag, V3(0.4, 1.2, depth), at((L.HalfWidth - 0.15) * side, math.min(height - 3, 11), zMid), M.SmoothPlastic, C.WallDark)
	end
end

local function buildWalls(parent: Instance)
	local f = folder(parent, "Walls")

	sideWalls(f, "Vestibule", L.ZFacade, L.ZCheckIn, L.HVestibule)
	sideWalls(f, "CheckIn", L.ZCheckIn, L.ZSecurity, L.HCheckIn)
	sideWalls(f, "Security", L.ZSecurity, L.ZConcourse, L.HSecurity)
	sideWalls(f, "Main", L.ZConcourse, L.ZGlass, L.HMain)

	-- Retorno até o beiral: fecha o canto entre a lateral e o vidro inclinado.
	for _, side in { -1, 1 } do
		box(f, "GlassReturn_" .. (if side < 0 then "W" else "E"), V3(L.WallThick, L.HMain, L.ZGlass - L.ZEave), at((L.HalfWidth + L.WallThick / 2) * side, L.HMain / 2, (L.ZGlass + L.ZEave) / 2), M.Concrete, C.Wall)
	end

	-- Pilastras verticais na metade do fundo do salão: quebram a parede longa
	-- sem custar quase nada. Ficam fora do trecho onde moram o painel de
	-- partidas, o relógio e a porta de serviço.
	for _, z in { -70, -84, -98 } do
		for _, side in { -1, 1 } do
			deco(f, "Pilaster_" .. tostring(z) .. (if side < 0 then "W" else "E"), V3(1, L.HMain - 2, 3), at((L.HalfWidth - 0.5) * side, (L.HMain - 2) / 2, z), M.Concrete, C.WallDark)
		end
	end

	-- Porta de serviço na parede oeste: sugere que o terminal continua além
	-- do que foi construído.
	deco(f, "ServiceDoorFrame", V3(0.6, 10.5, 9), at(-L.HalfWidth + 0.3, 5, -40), M.Metal, C.SteelDark)
	local door = deco(f, "ServiceDoor", V3(0.4, 9.5, 8), at(-L.HalfWidth + 0.6, 4.75, -40), M.Metal, C.Steel)
	label(door, Enum.NormalId.Right, "ACESSO\nRESTRITO", C.TextOnSign, Enum.Font.GothamBold)
end

--------------------------------------------------------------------------------
-- Arquitetura: fachada da entrada
--------------------------------------------------------------------------------

local function buildFacade(parent: Instance)
	local f = folder(parent, "Facade")
	local h = L.HVestibule
	local z = L.ZFacade

	-- 5 montantes, 4 vãos de porta de 24 studs.
	for _, x in { -56, -28, 0, 28, 56 } do
		box(f, "Pier_" .. tostring(x), V3(4, h, L.WallThick), at(x, h / 2, z), M.Concrete, C.Wall)
	end
	box(f, "FacadeHeader", V3(116, 3, L.WallThick + 0.6), at(0, h - 1.5, z), M.Concrete, C.WallDark)

	for _, cx in { -42, -14, 14, 42 } do
		-- Portas de correr ABERTAS: duas folhas encostadas nas laterais do
		-- vão, 12 studs livres no meio pra passar.
		for _, side in { -1, 1 } do
			local leaf = box(f, "SlidingLeaf", V3(6, h - 5, 0.4), at(cx + 9 * side, (h - 5) / 2, z), M.Glass, C.Glass, { Transparency = 0.6 })
			leaf.Reflectance = 0.1
			deco(f, "LeafFrame", V3(6.4, 0.5, 0.7), at(cx + 9 * side, h - 5, z), M.Metal, C.Mullion)
		end
		local transom = box(f, "Transom", V3(24, 2, 0.4), at(cx, h - 4, z), M.Glass, C.Glass, { Transparency = 0.62, CanCollide = false, CastShadow = false })
		transom.Reflectance = 0.1
		deco(f, "TransomSill", V3(24, 0.4, 0.7), at(cx, h - 5.2, z), M.Metal, C.Mullion)
	end

	-- Meio-fio e marquise: sem isso o terminal termina num degrau seco.
	box(f, "Curbside", V3(150, L.FloorDepth + 1, 40), at(0, -(L.FloorDepth + 1) / 2 + 0.1, z + 18), M.Concrete, C.Apron)
	deco(f, "Canopy", V3(124, 1, 22), at(0, h - 2, z + 12), M.Metal, C.Steel)
	for _, x in { -48, -16, 16, 48 } do
		deco(f, "CanopyPost", V3(1.2, h - 2, 1.2), at(x, (h - 2) / 2, z + 21), M.Metal, C.SteelDark)
	end

	--[[
		Pátio de desembarque FECHADO (telas laterais + parapeito da via).

		As portas da entrada são de passar mesmo -- 12 studs livres por vão --
		e sem isto o jogador saía pela frente, contornava o prédio por fora e
		aparecia do lado da pista, que é justamente a área que ainda não
		existe. Fechar o pátio mantém a porta utilizável e devolve à parede de
		vidro o papel de ÚNICA vista pro lado ar.
	]]
	for _, side in { -1, 1 } do
		local sx = (L.HalfWidth + L.WallThick) * side
		box(f, "ForecourtScreen_" .. (if side < 0 then "W" else "E"), V3(L.WallThick, 12, 36), at(sx, 6, z + 18), M.Concrete, C.Wall)
		deco(f, "ForecourtScreenCap_" .. (if side < 0 then "W" else "E"), V3(L.WallThick + 0.6, 0.6, 36), at(sx, 12.3, z + 18), M.Metal, C.SteelDark)
	end
	box(f, "ForecourtParapet", V3(118, 5, 2), at(0, 2.5, z + 35), M.Concrete, C.Wall)
	deco(f, "ForecourtRail", V3(118, 0.4, 0.4), at(0, 7.4, z + 35), M.Metal, C.Steel)
	for x = -56, 56, 8 do
		deco(f, "ForecourtRailPost", V3(0.4, 2.6, 0.4), at(x, 6.2, z + 35), M.Metal, C.Steel)
	end

	-- Letreiro na marquise, lendo de fora pra dentro.
	local fascia = deco(f, "TerminalSign", V3(60, 5, 1), at(0, h - 4.5, z + 22.6), M.SmoothPlastic, C.SignFace)
	label(fascia, Enum.NormalId.Back, "NÁUFRAGOS · TERMINAL 1", C.TextOnSign, Enum.Font.GothamBold)
	pointLight(fascia, 26, 1.1, C.LightWarm)

	-- Sinalização de chegada, virada pra dentro do saguão.
	local inner = deco(f, "ArrivalSign", V3(34, 3.4, 0.5), at(0, h - 7, z - 1.4), M.SmoothPlastic, C.Accent)
	label(inner, Enum.NormalId.Front, "CHECK-IN  ↓     EMBARQUE  ↓", C.TextOnSign, Enum.Font.GothamMedium)
end

--------------------------------------------------------------------------------
-- Arquitetura: teto, treliças e pilares
--------------------------------------------------------------------------------

local function ceilingSlab(f: Instance, name: string, zFront: number, zBack: number, height: number)
	box(f, name, V3(L.HalfWidth * 2 + L.WallThick * 2, 2, zFront - zBack), at(0, height + 1, (zFront + zBack) / 2), M.Concrete, C.Ceiling)
end

-- Face vertical entre dois pés-direitos. Além de fechar o vão, é a melhor
-- superfície de sinalização que um terminal tem.
local function fasciaBand(f: Instance, name: string, z: number, lower: number, upper: number): Part
	return box(f, name, V3(L.HalfWidth * 2 + L.WallThick * 2, upper - lower, 2), at(0, lower + (upper - lower) / 2, z), M.Concrete, C.WallDark)
end

local function buildCeiling(parent: Instance)
	local f = folder(parent, "Ceiling")

	ceilingSlab(f, "Ceiling_Vestibule", L.ZFacade, L.ZCheckIn, L.HVestibule)
	ceilingSlab(f, "Ceiling_CheckIn", L.ZCheckIn, L.ZSecurity, L.HCheckIn)
	ceilingSlab(f, "Ceiling_Security", L.ZSecurity, L.ZConcourse, L.HSecurity)
	-- O telhado principal avança até o beiral pra cobrir o vidro inclinado.
	ceilingSlab(f, "Ceiling_Main", L.ZConcourse, L.ZEave, L.HMain)

	fasciaBand(f, "Fascia_Vestibule", L.ZCheckIn, L.HVestibule, L.HCheckIn)

	-- Fascia da segurança: é EXATAMENTE o que se vê do spawn, porque o teto
	-- de 26 do check-in deixa essa faixa exposta e o de 19 esconde o resto.
	local secFascia = fasciaBand(f, "Fascia_Security", L.ZSecurity, L.HSecurity, L.HCheckIn)
	label(secFascia, Enum.NormalId.Back, "CONTROLE DE SEGURANÇA", C.TextOnSign, Enum.Font.GothamBold)
	pointLight(secFascia, 26, 0.8, C.LightWarm)

	-- Fascia alta do concourse: o que se vê ao olhar PRA TRÁS depois de
	-- passar a segurança.
	local concFascia = fasciaBand(f, "Fascia_Concourse", L.ZConcourse, L.HSecurity, L.HMain)
	label(concFascia, Enum.NormalId.Front, "PORTÕES  A1 – A4", C.TextOnSign, Enum.Font.GothamBold)

	-- Forro rebaixado sobre os balcões de check-in: profundidade no teto
	-- plano e luz só onde interessa.
	for _, side in { -1, 1 } do
		deco(f, "CheckInSoffit_" .. (if side < 0 then "W" else "E"), V3(24, 2, 32), at(36 * side, L.HCheckIn - 5, 10), M.Concrete, C.Ceiling)
	end

	-- Treliças aparentes do salão, alinhadas com as colunas.
	local trusses = folder(f, "Trusses")
	local span = L.HalfWidth * 2 + 2
	for _, z in { -40, -62, -84, -100 } do
		deco(trusses, "TrussTop_" .. tostring(z), V3(span, 1, 1.4), at(0, L.HMain - 1.6, z), M.Metal, C.Steel)
		deco(trusses, "TrussBottom_" .. tostring(z), V3(span, 0.9, 1.1), at(0, L.HMain - 4.2, z), M.Metal, C.Steel)
		for x = -48, 48, 16 do
			deco(trusses, "TrussWeb", V3(0.7, 2.6, 0.7), at(x, L.HMain - 2.9, z), M.Metal, C.SteelDark)
		end
	end
	for _, x in { -38, 0, 38 } do
		deco(trusses, "Purlin_" .. tostring(x), V3(0.9, 0.9, L.ZConcourse - L.ZEave), at(x, L.HMain - 2.4, (L.ZConcourse + L.ZEave) / 2), M.Metal, C.Steel)
	end
end

local function buildPillars(parent: Instance)
	local f = folder(parent, "Pillars")
	for _, z in { -42, -64, -86 } do
		for _, side in { -1, 1 } do
			local x = 42 * side
			local tag = tostring(z) .. (if side < 0 then "W" else "E")
			box(f, "PillarBase_" .. tag, V3(5.4, 1.2, 5.4), at(x, 0.6, z), M.Concrete, C.Skirting)
			box(f, "PillarShaft_" .. tag, V3(3.8, L.HMain - 2.4, 3.8), at(x, L.HMain / 2, z), M.Concrete, C.Wall)
			deco(f, "PillarCap_" .. tag, V3(5.4, 1.2, 5.4), at(x, L.HMain - 0.6, z), M.Concrete, C.WallDark)
		end
	end
end

--------------------------------------------------------------------------------
-- Parede panorâmica de vidro
--------------------------------------------------------------------------------

local function buildGlass(parent: Instance)
	local f = folder(parent, "Glass")

	local half = L.GlassBays * L.GlassBayWidth / 2
	local lowerH = L.GlassTop - L.GlassSill

	-- Trecho inclinado: do topo do vidro vertical até o beiral.
	local dy = L.GlassApex - L.GlassTop
	local dz = L.GlassLean
	local slopeLen = math.sqrt(dy * dy + dz * dz)
	local slopeCFrame = CFrame.Angles(-math.atan2(-dz, dy), 0, 0)
	local slopeMidY = L.GlassTop + dy / 2
	local slopeMidZ = L.ZGlass + dz / 2

	-- A porta do portão ocupa o vão centrado em x = -35 (futura ponte de
	-- embarque): porta metálica embaixo, vidro em cima.
	local doorBayCenter = -35

	for i = 0, L.GlassBays - 1 do
		local cx = -half + L.GlassBayWidth * (i + 0.5)
		local paneW = L.GlassBayWidth - 1.2

		if math.abs(cx - doorBayCenter) < 0.01 then
			local door = box(f, "JetBridgeDoor", V3(paneW, 11, 0.6), at(cx, 5.5 + L.GlassSill, L.ZGlass), M.Metal, C.SteelDark)
			label(door, Enum.NormalId.Back, "EMBARQUE\nA1", C.TextOnSign, Enum.Font.GothamBold)
			deco(f, "JetBridgeDoorBar", V3(paneW - 2, 0.4, 0.9), at(cx, 7, L.ZGlass + 0.4), M.Metal, C.Steel)
			local upper = box(f, "GlassPane_Door", V3(paneW, lowerH - 11, 0.5), at(cx, L.GlassSill + 11 + (lowerH - 11) / 2, L.ZGlass), M.Glass, C.Glass, { Transparency = 0.82, CanCollide = false, CastShadow = false })
			upper.Reflectance = 0.09
		else
			local pane = box(f, "GlassPane_" .. tostring(i + 1), V3(paneW, lowerH, 0.5), at(cx, L.GlassSill + lowerH / 2, L.ZGlass), M.Glass, C.Glass, { Transparency = 0.82, CastShadow = false })
			pane.Reflectance = 0.09
		end

		-- Trecho inclinado sem colisão: fica 22+ studs no alto, ninguém
		-- alcança, e caixa de colisão inclinada só custaria física à toa.
		local slope = box(f, "GlassSlope_" .. tostring(i + 1), V3(paneW, slopeLen, 0.5), at(cx, slopeMidY, slopeMidZ) * slopeCFrame, M.Glass, C.Glass, { Transparency = 0.8, CanCollide = false, CastShadow = false })
		slope.Reflectance = 0.1
	end

	for i = 0, L.GlassBays do
		local x = -half + L.GlassBayWidth * i
		box(f, "Mullion_" .. tostring(i), V3(1.4, L.GlassTop, 1.6), at(x, L.GlassTop / 2, L.ZGlass), M.Metal, C.Mullion)
		deco(f, "MullionSlope_" .. tostring(i), V3(1.2, slopeLen, 1.4), at(x, slopeMidY, slopeMidZ) * slopeCFrame, M.Metal, C.Mullion)
	end

	box(f, "GlassSill", V3(half * 2, L.GlassSill, 2.4), at(0, L.GlassSill / 2, L.ZGlass), M.Metal, C.SteelDark)
	deco(f, "GlassTransom", V3(half * 2, 1.2, 2), at(0, 11.5, L.ZGlass), M.Metal, C.Mullion)
	deco(f, "GlassHead", V3(half * 2, 1.4, 2.2), at(0, L.GlassTop, L.ZGlass), M.Metal, C.Mullion)
	deco(f, "EaveBeam", V3(half * 2 + 4, 2, 3), at(0, L.GlassApex, L.ZGlass + L.GlassLean), M.Metal, C.SteelDark)
	for _, x in { -42, -14, 14, 42 } do
		deco(f, "EaveStrut", V3(0.9, 0.9, math.abs(L.GlassLean) + 3), at(x, L.GlassApex + 0.6, L.ZGlass + L.GlassLean / 2), M.Metal, C.Steel)
	end
end

--------------------------------------------------------------------------------
-- Organizadores de fila (check-in, segurança e portão)
--------------------------------------------------------------------------------

local function stanchion(parent: Instance, x: number, z: number): Vector3
	local top = 3.4
	cylinder(parent, "StanchionBase", V3(0.3, 1.8, 1.8), at(x, 0.15, z) * UPRIGHT, M.Metal, C.SteelDark)
	cylinder(parent, "StanchionPost", V3(top, 0.5, 0.5), at(x, top / 2, z) * UPRIGHT, M.Metal, C.Steel)
	return ORIGIN + V3(x, top - 0.4, z)
end

local function queueLine(parent: Instance, points: { { number } })
	local previous: Vector3? = nil
	for _, pt in points do
		local topPoint = stanchion(parent, pt[1], pt[2])
		if previous then
			spanBox(parent, "QueueBelt", previous, topPoint, 0.16, 0.7, M.SmoothPlastic, C.Accent)
		end
		previous = topPoint
	end
end

-- Monitor de mesa, usado nos balcões de check-in e no portão. `cf` é o
-- centro da TELA, já com a leve inclinação de "encarar o passageiro".
local function fallbackComputer(parent: Instance, cf: CFrame)
	local f = folder(parent, "Computer_Fallback")
	deco(f, "Screen", V3(0.4, 2.6, 3.6), cf, M.SmoothPlastic, C.Screen)
	deco(f, "Bezel", V3(0.5, 2.8, 3.8), cf * CFrame.new(-0.05, 0, 0), M.Metal, C.SteelDark)
end

local function fallbackClock(parent: Instance, cf: CFrame)
	local f = folder(parent, "Clock_Fallback")
	cylinder(f, "Face", V3(0.6, 4.5, 4.5), cf, M.SmoothPlastic, C.SignFace)
	local dial = deco(f, "Dial", V3(0.2, 3.7, 3.7), cf * CFrame.new(0.35, 0, 0), M.SmoothPlastic, C.TextOnSign)
	label(dial, Enum.NormalId.Right, "12:00", C.SignFace, Enum.Font.Code)
end

--------------------------------------------------------------------------------
-- Check-in
--------------------------------------------------------------------------------

local function checkInCounter(parent: Instance, side: number, indexBase: number)
	local x = 36 * side
	local f = folder(parent, "Counter_" .. (if side < 0 then "W" else "E"))

	box(f, "CounterBody", V3(7, 3.2, 30), at(x, 1.6, 10), M.SmoothPlastic, C.Counter)
	deco(f, "CounterTop", V3(8.6, 0.4, 30.8), at(x, 3.4, 10), M.SmoothPlastic, C.CounterTop)
	deco(f, "CounterReveal", V3(7.3, 0.5, 30.4), at(x, 0.4, 10), M.SmoothPlastic, C.Accent)

	-- Retaguarda: painel do operador e esteira de bagagem.
	box(f, "BackPanel", V3(1.6, 11, 30), at(48 * side, 5.5, 10), M.SmoothPlastic, C.WallDark)
	deco(f, "BaggageBelt", V3(5, 0.8, 30), at(43 * side, 1, 10), M.SmoothPlastic, C.Belt)
	for z = -3, 23, 3 do
		cylinder(f, "BeltRoller", V3(4.8, 0.4, 0.4), at(43 * side, 1.5, z), M.Metal, C.Steel)
	end
	deco(f, "BeltSideW", V3(0.4, 1.4, 30), at(40.4 * side, 1.7, 10), M.Metal, C.SteelDark)
	deco(f, "BeltSideE", V3(0.4, 1.4, 30), at(45.6 * side, 1.7, 10), M.Metal, C.SteelDark)

	-- Quatro posições de atendimento, cada uma com computador e número.
	for i = 0, 3 do
		local z = -2 + i * 8
		local screenCF = at(x - 2.4 * side, 4.9, z) * CFrame.Angles(0, 0, math.rad(-8 * side))
		placeAsset(f, ASSETS.Computer, string.format("Computer_%s%d", if side < 0 then "W" else "E", i), screenCF, fallbackComputer)
		deco(f, "MonitorStand", V3(0.8, 1.1, 0.8), at(x - 2.4 * side, 3.8, z), M.Metal, C.SteelDark)

		local plate = deco(f, "DeskNumber", V3(0.4, 2, 3), at(47.1 * side, 9, z), M.SmoothPlastic, C.Accent)
		label(plate, if side < 0 then Enum.NormalId.Left else Enum.NormalId.Right, tostring(indexBase + i), C.TextOnSign, Enum.Font.GothamBold)
	end

	-- Placa suspensa identificando o bloco.
	local sign = deco(f, "CounterSign", V3(0.6, 3.4, 12), at(x, 13, 24), M.SmoothPlastic, C.SignFace)
	label(sign, if side < 0 then Enum.NormalId.Right else Enum.NormalId.Left, string.format("CHECK-IN %d–%d", indexBase, indexBase + 3), C.TextOnSign, Enum.Font.GothamBold)
	for _, dz in { -5, 5 } do
		deco(f, "SignRod", V3(0.25, 5, 0.25), at(x, 16.2, 24 + dz), M.Metal, C.SteelDark)
	end
end

local function buildCheckIn(parent: Instance)
	local f = folder(parent, "CheckIn")

	checkInCounter(f, -1, 1)
	checkInCounter(f, 1, 5)

	queueLine(folder(f, "QueueWest"), { { -26, 24 }, { -26, 17 }, { -26, 10 }, { -26, 3 } })
	queueLine(folder(f, "QueueEast"), { { 26, 24 }, { 26, 17 }, { 26, 10 }, { 26, 3 } })

	--[[
		Totem de auto-atendimento em volta de "IniciarPartida".

		Essa Part é criada e reposicionada por LobbyManager em (0, 0.5, 20)
		todo boot -- não dá pra mover e não vale a pena lutar. Então o cenário
		abraça ela: dois pilaretes com tela e uma placa suspensa fazem o Neon
		azul do prompt parecer o quiosque de embarque.
	]]
	local totem = folder(f, "SelfServiceTotem")
	for _, side in { -1, 1 } do
		local x = 5.5 * side
		box(totem, "TotemPillar", V3(2.6, 9, 2.6), at(x, 4.5, 20), M.SmoothPlastic, C.Counter)
		local screen = deco(totem, "TotemScreen", V3(0.3, 4, 2), at(x - 1.4 * side, 6, 20), M.SmoothPlastic, C.Screen)
		label(screen, if side < 0 then Enum.NormalId.Left else Enum.NormalId.Right, "AUTO\nATEND.", C.TextOnSign, Enum.Font.GothamMedium)
	end
	local totemSign = deco(totem, "TotemSign", V3(16, 3, 0.5), at(0, 11.5, 20), M.SmoothPlastic, C.Accent)
	label(totemSign, Enum.NormalId.Back, "PREPARAÇÃO DA PARTIDA", C.TextOnSign, Enum.Font.GothamBold)
	label(totemSign, Enum.NormalId.Front, "PREPARAÇÃO DA PARTIDA", C.TextOnSign, Enum.Font.GothamBold)
	deco(totem, "TotemRod", V3(0.3, 4, 0.3), at(0, 15, 20), M.Metal, C.SteelDark)

	-- Placa de orientação pendurada, virada pra quem entra.
	local way = deco(f, "Wayfinding_CheckIn", V3(30, 4, 0.5), at(0, L.HCheckIn - 8, 27), M.SmoothPlastic, C.SignFace)
	label(way, Enum.NormalId.Back, "↑ CHECK-IN        SEGURANÇA ↓", C.TextOnSign, Enum.Font.GothamMedium)
	for _, dx in { -12, 12 } do
		deco(f, "WayfindingRod", V3(0.25, 6, 0.25), at(dx, L.HCheckIn - 3, 27), M.Metal, C.SteelDark)
	end
end

--------------------------------------------------------------------------------
-- Segurança
--------------------------------------------------------------------------------

local function fallbackScanner(parent: Instance, cf: CFrame)
	local f = folder(parent, "LuggageScanner_Fallback")
	local function rel(dx: number, dy: number, dz: number): CFrame
		return cf * CFrame.new(dx, dy, dz)
	end

	-- Túnel de raio-X com o vão da esteira no meio.
	box(f, "ScannerBodyW", V3(4.5, 5.5, 6), rel(-4, 2.75, 0), M.Metal, C.Steel)
	box(f, "ScannerBodyE", V3(4.5, 5.5, 6), rel(4, 2.75, 0), M.Metal, C.Steel)
	box(f, "ScannerRoof", V3(12.5, 2, 6), rel(0, 6.5, 0), M.Metal, C.Steel)
	deco(f, "ScannerCurtainIn", V3(4, 3.4, 0.4), rel(0, 3.2, -3.1), M.SmoothPlastic, C.Rubber)
	deco(f, "ScannerCurtainOut", V3(4, 3.4, 0.4), rel(0, 3.2, 3.1), M.SmoothPlastic, C.Rubber)

	-- Esteira entrando e saindo do túnel.
	box(f, "Belt", V3(3.6, 2.6, 10), rel(0, 1.3, 0), M.SmoothPlastic, C.Belt)
	deco(f, "BeltRailW", V3(0.4, 0.8, 10), rel(-2.1, 2.8, 0), M.Metal, C.SteelDark)
	deco(f, "BeltRailE", V3(0.4, 0.8, 10), rel(2.1, 2.8, 0), M.Metal, C.SteelDark)

	deco(f, "OperatorScreen", V3(3.6, 2.6, 0.4), rel(-6.4, 6, -2), M.SmoothPlastic, C.Screen)
	box(f, "StatusLamp", V3(0.8, 0.8, 0.8), rel(0, 7.8, 0), M.Neon, C.AccentWarm, { Shape = Enum.PartType.Ball, CanCollide = false, CastShadow = false })
end

local function fallbackSecurityGate(parent: Instance, cf: CFrame)
	local f = folder(parent, "SecurityGate_Fallback")
	local function rel(dx: number, dy: number, dz: number): CFrame
		return cf * CFrame.new(dx, dy, dz)
	end

	-- Pórtico detector: os montantes colidem, o vão fica livre pra passar.
	box(f, "GatePostW", V3(1.4, 9, 2.6), rel(-4.2, 4.5, 0), M.SmoothPlastic, C.Counter)
	box(f, "GatePostE", V3(1.4, 9, 2.6), rel(4.2, 4.5, 0), M.SmoothPlastic, C.Counter)
	deco(f, "GateLintel", V3(10, 1.6, 2.6), rel(0, 9.8, 0), M.SmoothPlastic, C.Counter)
	deco(f, "GateStripeW", V3(0.4, 7, 0.5), rel(-3.4, 4.5, -1.4), M.Neon, C.Accent)
	deco(f, "GateStripeE", V3(0.4, 7, 0.5), rel(3.4, 4.5, -1.4), M.Neon, C.Accent)
	deco(f, "GateLamp", V3(1.4, 0.5, 1.4), rel(0, 9.2, -1.3), M.Neon, Color3.fromRGB(70, 210, 120))
end

local function buildSecurity(parent: Instance)
	local f = folder(parent, "Security")

	local zWall = -27
	local wall = folder(f, "Partition")

	--[[
		A divisória é montada em SEGMENTOS, deixando exatamente dois vãos por
		raia: um tomado pelo túnel de raio-X (por onde passa a BAGAGEM) e um
		livre com o pórtico detector (por onde passa a PESSOA).

		Isso não é detalhe estético. Na primeira versão o scanner ficava no
		eixo da raia e a esteira -- 2,6 studs de altura -- barrava o caminho:
		o checkpoint não tinha por onde andar e a metade de trás do terminal
		ficava inacessível. Separar bagagem e pedestre é o que um checkpoint
		de verdade faz, e é o que faz a planta funcionar.

		Vãos livres resultantes, por lado: x 15,0..8,0 entre os montantes do
		pórtico -- 7 studs, folgado pra um R6 (2 studs de largura).
	]]
	local function segment(name: string, xFrom: number, xTo: number)
		local width = xTo - xFrom
		local cx = (xFrom + xTo) / 2
		box(wall, name, V3(width, 9, 1.6), at(cx, 4.5, zWall), M.SmoothPlastic, C.Counter)
		deco(wall, name .. "Cap", V3(width, 0.5, 2.2), at(cx, 9.2, zWall), M.SmoothPlastic, C.Accent)
	end
	segment("PartitionOuter_W", -57, -31)
	segment("PartitionPier_W", -20, -16)
	segment("PartitionCenter", -7, 7)
	segment("PartitionPier_E", 16, 20)
	segment("PartitionOuter_E", 31, 57)

	for _, side in { -1, 1 } do
		local tag = if side < 0 then "W" else "E"
		local lane = folder(f, "Lane_" .. tag)
		local walkX = 11.5 * side -- eixo do pórtico: por onde a PESSOA passa
		local bagX = 26 * side -- eixo da esteira: por onde a BAGAGEM passa

		-- Fila em serpentina desaguando no detector.
		queueLine(folder(lane, "Queue"), { { 17 * side, -12 }, { 17 * side, -19 }, { 6 * side, -19 }, { 6 * side, -12 } })

		-- Mesa de bandejas na boca da esteira.
		box(lane, "TrayTable", V3(6, 3, 3), at(bagX, 1.5, -16), M.SmoothPlastic, C.Counter)
		for i = 0, 2 do
			deco(lane, "Tray", V3(3.4, 0.5, 2.4), at(bagX, 3.3 + i * 0.35, -16), M.SmoothPlastic, C.AccentWarm)
		end

		placeAsset(lane, ASSETS.Scanner, "LuggageScanner_" .. tag, at(bagX, 0, zWall), fallbackScanner)
		placeAsset(lane, ASSETS.SecurityGate, "SecurityGate_" .. tag, at(walkX, 0, zWall), fallbackSecurityGate)

		-- Mesa de recolhimento, já do lado limpo e fora do eixo de passagem.
		box(lane, "RecollectTable", V3(5, 3, 3), at(20 * side, 1.5, -31), M.SmoothPlastic, C.Counter)

		deco(lane, "LaneMark", V3(7, 0.2, 0.6), at(walkX, 0.05, -21), M.SmoothPlastic, C.AccentWarm)
		deco(lane, "LaneMark2", V3(7, 0.2, 0.6), at(walkX, 0.05, -13), M.SmoothPlastic, C.AccentWarm)

		local laneSign = deco(lane, "LaneSign", V3(6, 2, 0.4), at(walkX, 10.6, zWall), M.SmoothPlastic, C.Accent)
		label(laneSign, Enum.NormalId.Back, if side < 0 then "RAIA 1" else "RAIA 2", C.TextOnSign, Enum.Font.GothamBold)
	end

	-- Posto do supervisor, do lado limpo, olhando as duas raias.
	local desk = folder(f, "SupervisorDesk")
	box(desk, "DeskBody", V3(3.4, 3.4, 9), at(-50, 1.7, -31), M.SmoothPlastic, C.Counter)
	deco(desk, "DeskTop", V3(4.2, 0.4, 9.6), at(-50, 3.6, -31), M.SmoothPlastic, C.CounterTop)
	deco(desk, "DeskScreen", V3(0.4, 2.4, 3.2), at(-48.6, 5, -31), M.SmoothPlastic, C.Screen)
	deco(desk, "DeskChair", V3(2.4, 0.5, 2.4), at(-53, 2.2, -31), M.Fabric, C.SteelDark)
end

--------------------------------------------------------------------------------
-- Sala de embarque (poltronas)
--------------------------------------------------------------------------------

--[[
	Fileira de poltronas de aeroporto em Parts. Versão enxuta de propósito:
	11 peças por fileira em vez das ~20 que um assento-a-assento custaria. O
	desenho (viga contínua, pés recuados, braços dividindo os lugares) já lê
	como banco de terminal na distância em que ele vai ser visto.

	Convenção: o ENCOSTO fica no +Z local, então a fileira colocada sem
	rotação deixa quem senta olhando pro vidro (-Z).
]]
local function fallbackSeatRow(parent: Instance, cf: CFrame)
	local f = folder(parent, "SeatRow_Fallback")
	local seats = 5
	local pitch = 3.8
	local length = seats * pitch

	local function rel(dx: number, dy: number, dz: number): CFrame
		return cf * CFrame.new(dx, dy, dz)
	end

	deco(f, "Frame", V3(length + 1, 0.7, 1.2), rel(0, 1.4, 0.4), M.Metal, C.SteelDark)
	for _, dx in { -length / 2 + 2, length / 2 - 2 } do
		box(f, "Leg", V3(0.8, 1.4, 3.6), rel(dx, 0.7, 0.4), M.Metal, C.SteelDark)
	end
	box(f, "SeatPan", V3(length, 0.7, 3.2), rel(0, 2.1, -0.2), M.Fabric, C.Seat)
	box(f, "SeatBack", V3(length, 3.6, 0.7), rel(0, 3.9, 1.5), M.Fabric, C.Seat)
	deco(f, "BackCap", V3(length, 0.4, 1.1), rel(0, 5.8, 1.5), M.SmoothPlastic, C.SteelDark)
	for i = 0, seats do
		deco(f, "Armrest", V3(0.5, 0.5, 3), rel(-length / 2 + i * pitch, 2.7, -0.1), M.SmoothPlastic, C.SteelDark)
	end
end

local function buildWaitingArea(parent: Instance)
	local f = folder(parent, "WaitingArea")

	-- Dois blocos de 3 fileiras de 5 lugares. Corredor central de 30 studs
	-- livre do salão até o vidro e ~16 studs de folga em cada lateral: dá pra
	-- circular por fora, por dentro e chegar na janela sem desviar de nada.
	for _, side in { -1, 1 } do
		local tag = if side < 0 then "W" else "E"
		local block = folder(f, "SeatBlock_" .. tag)
		for i, z in { -58, -66, -74 } do
			placeAsset(block, ASSETS.Seats, string.format("Seats_%s%d", tag, i), at(25 * side, 0, z), fallbackSeatRow)
		end
	end

	-- Bancada de encostar na janela, no lado livre do passeio: o convite pra
	-- chegar perto do vidro em vez de só olhar de longe.
	local bar = folder(f, "WindowBar")
	box(bar, "BarTop", V3(34, 0.6, 2.6), at(26, 4, -98), M.SmoothPlastic, C.CounterTop)
	for _, dx in { -14, 0, 14 } do
		box(bar, "BarLeg", V3(0.6, 4, 0.6), at(26 + dx, 2, -98), M.Metal, C.Steel)
	end
	for _, dx in { -12, -4, 4, 12 } do
		cylinder(bar, "BarStool", V3(0.5, 2.2, 2.2), at(26 + dx, 3, -95) * UPRIGHT, M.SmoothPlastic, C.Seat, true)
		deco(bar, "StoolPost", V3(0.5, 3, 0.5), at(26 + dx, 1.5, -95), M.Metal, C.Steel)
	end

	-- Painel grande de partidas na parede leste, legível assim que se sai da
	-- segurança. É só cenário; o painel ligável fica no portão.
	local board = deco(f, "DepartureBoard", V3(0.6, 12, 30), at(L.HalfWidth - 0.4, 14, -48), M.SmoothPlastic, C.SignFace)
	label(
		board,
		Enum.NormalId.Left,
		"PARTIDAS\n\n815   ???          A1    AGUARDANDO\n902   ---          A2    CANCELADO\n118   ---          A3    CANCELADO",
		C.TextOnSign,
		Enum.Font.Code,
		true
	)
	pointLight(board, 24, 0.9, C.Accent)
end

--------------------------------------------------------------------------------
-- Portão de embarque
--------------------------------------------------------------------------------

local function fallbackSign(parent: Instance, cf: CFrame)
	local f = folder(parent, "HangingSign_Fallback")
	local panel = deco(f, "Panel", V3(14, 4, 0.5), cf, M.SmoothPlastic, C.SignFace)
	label(panel, Enum.NormalId.Back, "PORTÃO A1 →", C.TextOnSign, Enum.Font.GothamBold)
	label(panel, Enum.NormalId.Front, "← PORTÃO A1", C.TextOnSign, Enum.Font.GothamBold)
	for _, dx in { -5, 5 } do
		deco(f, "Rod", V3(0.25, 5, 0.25), cf * CFrame.new(dx, 4.5, 0), M.Metal, C.SteelDark)
	end
end

local function buildBoardingGate(parent: Instance)
	local f = folder(parent, "BoardingGate")

	-- O portão fica no lado oeste do passeio, alinhado com a porta da futura
	-- ponte de embarque no vidro (x = -35). Assimétrico de propósito: deixa o
	-- lado leste inteiro livre pra vista da janela.
	local gx, gz = -28, -90

	local desk = folder(f, "GateDesk")
	box(desk, "DeskBody", V3(12, 3.4, 3.6), at(gx, 1.7, gz), M.SmoothPlastic, C.Counter)
	deco(desk, "DeskTop", V3(13, 0.4, 4.4), at(gx, 3.6, gz), M.SmoothPlastic, C.CounterTop)
	deco(desk, "DeskStripe", V3(12.3, 0.6, 3.9), at(gx, 0.5, gz), M.SmoothPlastic, C.Accent)
	box(desk, "BackCounter", V3(12, 6, 1.6), at(gx, 3, gz - 5), M.SmoothPlastic, C.WallDark)
	for i, dx in { -3.4, 3.4 } do
		placeAsset(desk, ASSETS.Computer, "GateComputer_" .. tostring(i), at(gx + dx, 5, gz + 1.6), fallbackComputer)
	end

	-- Pedestal do leitor de cartão de embarque: onde a interação da partida
	-- naturalmente vai morar.
	box(desk, "ScannerPedestal", V3(2, 4, 2), at(gx + 8.5, 2, gz + 2), M.SmoothPlastic, C.Counter)
	deco(desk, "BoardingPassReader", V3(2.2, 0.6, 2.2), at(gx + 8.5, 4.2, gz + 2), M.Neon, C.Accent)

	-- Âncora nomeada pro matchmaking futuro. Nenhum sistema aqui ainda -- é só
	-- um ponto estável que outro script vai achar por Attribute.
	local anchor = S.Marker(f, "PontoEmbarque", at(gx + 8.5, 0, gz + 4), {
		PontoEmbarque = true,
		PortaoId = "A1",
		VooId = "815",
	})
	anchor.Size = V3(4, 1, 4)

	queueLine(folder(f, "GateQueue"), { { gx - 8, gz + 6 }, { gx - 8, gz + 13 }, { gx + 2, gz + 13 }, { gx + 2, gz + 6 } })

	--[[
		Painel do voo, pendurado sobre o balcão. A SurfaceGui já vem com os
		labels separados e nomeados (Voo/Destino/Status/Passageiros) pra um
		sistema futuro só trocar o .Text de cada um. NENHUMA lógica de
		matchmaking foi ligada: os valores abaixo são fixos.
	]]
	-- Pendurado ALTO (y 16..24) de propósito. O portão fica encostado no
	-- vidro, então qualquer coisa aqui entra na frente da janela; manter o
	-- painel acima da linha do horizonte deixa os 15 studs de baixo do vidro
	-- limpos -- que é exatamente onde a pista, os aviões e os veículos vão
	-- aparecer. Quem está sentado continua vendo o pátio inteiro.
	local panel = deco(f, "PainelVoo", V3(16, 8, 0.8), at(gx, 20, gz - 3), M.SmoothPlastic, C.SignFace)
	panel:SetAttribute("PainelVoo", true)
	panel:SetAttribute("PortaoId", "A1")
	for _, dx in { -6.5, 6.5 } do
		deco(f, "PanelRod", V3(0.3, 10, 0.3), at(gx + dx, 29, gz - 3), M.Metal, C.SteelDark)
	end

	local gui = Instance.new("SurfaceGui")
	gui.Name = "Painel"
	gui.Face = Enum.NormalId.Back
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 40
	gui.LightInfluence = 0
	gui.Parent = panel

	local listing = Instance.new("Frame")
	listing.Name = "Linhas"
	listing.Size = UDim2.fromScale(0.92, 0.86)
	listing.Position = UDim2.fromScale(0.04, 0.07)
	listing.BackgroundTransparency = 1
	listing.Parent = gui

	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Vertical
	layout.Padding = UDim.new(0, 6)
	layout.Parent = listing

	type FlightLine = { Name: string, Text: string, Color: Color3 }
	local lines: { FlightLine } = {
		{ Name = "Voo", Text = "VOO 815", Color = C.AccentWarm },
		{ Name = "Destino", Text = "DESTINO: ???", Color = C.TextOnSign },
		{ Name = "Status", Text = "STATUS: AGUARDANDO", Color = C.TextOnSign },
		{ Name = "Passageiros", Text = "PASSAGEIROS: 0/10", Color = C.TextOnSign },
	}
	for i, line in lines do
		local tl = Instance.new("TextLabel")
		tl.Name = line.Name
		tl.LayoutOrder = i
		tl.Size = UDim2.fromScale(1, 0.22)
		tl.BackgroundTransparency = 1
		tl.Text = line.Text
		tl.TextColor3 = line.Color
		tl.Font = Enum.Font.Code
		tl.TextScaled = true
		tl.TextXAlignment = Enum.TextXAlignment.Left
		tl.Parent = listing
	end
	pointLight(panel, 28, 1.1, C.Accent)

	-- Placa suspensa do portão (asset Airport Sign, quando ele carrega).
	placeAsset(f, ASSETS.Sign, "GateSign_A1", at(gx, 21, -80), fallbackSign)

	-- Marcação de piso do portão.
	deco(f, "GateFloorMark", V3(26, 0.2, 16), at(gx, 0.06, -86), M.SmoothPlastic, C.FloorAccent)
	local gateNumber = deco(f, "GateNumberFloor", V3(10, 0.22, 7), at(gx, 0.09, -86), M.SmoothPlastic, C.SignFace)
	label(gateNumber, Enum.NormalId.Top, "A1", C.TextOnSign, Enum.Font.GothamBold)
end

--------------------------------------------------------------------------------
-- Iluminação
--------------------------------------------------------------------------------

local function fallbackCeilingLight(parent: Instance, cf: CFrame)
	local f = folder(parent, "CeilingLight_Fallback")
	deco(f, "Housing", V3(8.4, 0.5, 3.4), cf, M.Metal, C.SteelDark)
	deco(f, "Lens", V3(7.6, 0.3, 2.8), cf * CFrame.new(0, -0.35, 0), M.Neon, C.LightWarm)
end

local function buildLighting(parent: Instance)
	local f = folder(parent, "Lighting")

	-- 19 luminárias no total. Alcance largo em vez de muitas fontes, e nenhuma
	-- projeta sombra: é o que mantém o terminal legível sem pesar.
	type Fixture = { x: number, y: number, z: number, range: number, brightness: number }
	local fixtures: { Fixture } = {}
	local function add(x: number, y: number, z: number, range: number, brightness: number)
		table.insert(fixtures, { x = x, y = y, z = z, range = range, brightness = brightness })
	end

	for _, x in { -30, 0, 30 } do
		add(x, L.HVestibule - 1.2, 36, 34, 1.1)
	end
	for _, z in { 20, 0 } do
		for _, x in { -36, 36 } do
			add(x, L.HCheckIn - 6.2, z, 32, 1.2) -- embutidas no forro rebaixado
		end
	end
	add(0, L.HCheckIn - 1.4, 10, 40, 1.0)

	-- Segurança: mais luz, porque é a faixa de teto baixo.
	for _, z in { -12, -28 } do
		for _, x in { -19, 19 } do
			add(x, L.HSecurity - 1.4, z, 30, 1.35)
		end
	end

	for _, z in { -40, -60, -80, -98 } do
		for _, x in { -26, 26 } do
			add(x, L.HMain - 5, z, 46, 1.5)
		end
	end

	for i, fx in fixtures do
		local cf = at(fx.x, fx.y, fx.z)
		local model = placeAsset(f, ASSETS.CeilingLight, string.format("CeilingLight_%02d", i), cf, fallbackCeilingLight)
		-- O asset do Toolbox pode não trazer luz nenhuma; a fonte é sempre nossa.
		local host: BasePart? = if model then (model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart", true)) else nil
		if not host then
			local emitter = deco(f, "LightSource_" .. tostring(i), V3(1, 0.4, 1), cf * CFrame.new(0, -0.6, 0), M.SmoothPlastic, C.LightWarm)
			emitter.Transparency = 1
			host = emitter
		end
		pointLight(host :: BasePart, fx.range, fx.brightness, C.LightWarm)
	end

	-- Foco no balcão do portão: puxa o olho pro objetivo do lobby.
	local spotHost = deco(f, "GateSpotHost", V3(1.6, 0.6, 1.6), at(-28, L.HMain - 4, -90), M.Metal, C.SteelDark)
	local spot = Instance.new("SpotLight")
	spot.Angle = 70
	spot.Range = 40
	spot.Brightness = 2
	spot.Face = Enum.NormalId.Bottom
	spot.Color = C.LightWarm
	spot.Shadows = false
	spot.Parent = spotHost
end

--------------------------------------------------------------------------------
-- Props
--------------------------------------------------------------------------------

local function fallbackVending(parent: Instance, cf: CFrame)
	local f = folder(parent, "VendingMachine_Fallback")
	local function rel(dx: number, dy: number, dz: number): CFrame
		return cf * CFrame.new(dx, dy, dz)
	end
	box(f, "Body", V3(4.6, 9, 3), rel(0, 4.5, 0), M.SmoothPlastic, C.Accent)
	local front = deco(f, "Front", V3(3.4, 6, 0.3), rel(-0.6, 5.2, -1.6), M.Glass, C.Glass)
	front.Transparency = 0.45
	for i = 0, 3 do
		deco(f, "Shelf", V3(3.2, 0.25, 0.8), rel(-0.6, 3 + i * 1.5, -1.3), M.SmoothPlastic, C.SteelDark)
	end
	deco(f, "Keypad", V3(1, 3, 0.3), rel(1.6, 5.4, -1.6), M.SmoothPlastic, C.SignFace)
	deco(f, "Base", V3(4.8, 0.6, 3.2), rel(0, 0.3, 0), M.SmoothPlastic, C.SteelDark)
	deco(f, "Header", V3(4.4, 1.6, 0.2), rel(0, 8.4, -1.6), M.Neon, C.LightWarm)
end

local function trashBin(parent: Instance, x: number, z: number)
	cylinder(parent, "TrashBin", V3(4.4, 3, 3), at(x, 2.2, z) * UPRIGHT, M.Metal, C.SteelDark, true)
	deco(parent, "BinLid", V3(3.3, 0.5, 3.3), at(x, 4.6, z), M.SmoothPlastic, C.Skirting)
end

local function planter(parent: Instance, x: number, z: number)
	box(parent, "PlanterBox", V3(6, 3, 6), at(x, 1.5, z), M.Concrete, C.Wall)
	deco(parent, "PlanterSoil", V3(5.2, 0.4, 5.2), at(x, 3.1, z), M.Ground, C.Skirting)
	for i = 0, 2 do
		local angle = i * math.pi * 2 / 3
		box(parent, "Shrub", V3(3.4, 4.6, 3.4), at(x + math.cos(angle) * 1.1, 5.2, z + math.sin(angle) * 1.1), M.Grass, C.Plant, { Shape = Enum.PartType.Ball, CanCollide = false, CastShadow = false })
	end
end

local function luggageCart(parent: Instance, x: number, z: number, yaw: number)
	local f = folder(parent, "LuggageCart")
	local cf = atYaw(x, 0, z, yaw)
	box(f, "Deck", V3(4, 0.5, 6.5), cf * CFrame.new(0, 1.6, 0), M.Metal, C.Steel)
	deco(f, "Handle", V3(3.8, 3.4, 0.3), cf * CFrame.new(0, 3.3, 3), M.Metal, C.SteelDark)
	for _, dx in { -1.6, 1.6 } do
		for _, dz in { -2.6, 2.6 } do
			cylinder(f, "Wheel", V3(0.5, 1.1, 1.1), cf * CFrame.new(dx, 0.6, dz), M.SmoothPlastic, C.Rubber)
		end
	end
	deco(f, "Bag", V3(3, 2.2, 4), cf * CFrame.new(0, 2.9, -0.4), M.Fabric, C.SteelDark)
end

local function buildProps(parent: Instance)
	local f = folder(parent, "Props")

	-- Máquinas de conveniência encostadas na parede oeste, viradas pro salão.
	local vending = folder(f, "Vending")
	placeAsset(vending, ASSETS.Vending, "VendingMachine_1", atYaw(-52, 0, -58, -90), fallbackVending)
	placeAsset(vending, ASSETS.Vending, "VendingMachine_2", atYaw(-52, 0, -64, -90), fallbackVending)

	-- Quiosque de informações, lado leste.
	local kiosk = folder(f, "InfoKiosk")
	box(kiosk, "KioskBody", V3(5, 3.6, 10), at(50, 1.8, -66), M.SmoothPlastic, C.Counter)
	deco(kiosk, "KioskTop", V3(6, 0.4, 11), at(50, 3.8, -66), M.SmoothPlastic, C.CounterTop)
	local kioskSign = deco(kiosk, "KioskSign", V3(0.5, 3, 9), at(50, 8.5, -66), M.SmoothPlastic, C.Accent)
	label(kioskSign, Enum.NormalId.Left, "INFORMAÇÕES", C.TextOnSign, Enum.Font.GothamBold)
	for _, dz in { -3.5, 3.5 } do
		deco(kiosk, "KioskPost", V3(0.4, 4, 0.4), at(50, 5.5, -66 + dz), M.Metal, C.SteelDark)
	end

	local bins = folder(f, "Bins")
	trashBin(bins, -14, -52)
	trashBin(bins, 14, -52)
	trashBin(bins, -38, -78)
	trashBin(bins, 38, -78)
	trashBin(bins, 30, 22)

	local planters = folder(f, "Planters")
	planter(planters, -50, -42)
	planter(planters, 50, -42)
	planter(planters, -50, -98)
	planter(planters, 50, -98)
	planter(planters, -50, 34)
	planter(planters, 50, 34)

	local carts = folder(f, "Carts")
	luggageCart(carts, -18, 30, 0)
	luggageCart(carts, 20, 26, 25)
	luggageCart(carts, 46, -24, 90)

	-- Malas soltas: baratas, e é o que faz o lugar parecer usado.
	local bags = folder(f, "Luggage")
	local drops = { { -30, 36, 0 }, { 24, 18, 18 }, { -16, -50, 40 }, { 12, -62, -20 }, { -34, -86, 65 }, { 46, -82, 10 } }
	for i, d in drops do
		local cf = atYaw(d[1], 0, d[2], d[3])
		box(bags, "Suitcase_" .. tostring(i), V3(3, 4.4, 1.8), cf * CFrame.new(0, 2.2, 0), M.Fabric, (if i % 2 == 0 then C.Seat else C.SteelDark))
		deco(bags, "SuitcaseHandle", V3(1.4, 1.2, 0.3), cf * CFrame.new(0, 4.9, 0), M.Metal, C.Steel)
	end

	-- Relógio do saguão, na parede oeste (eixo do cilindro em X = encara o salão).
	placeAsset(f, ASSETS.Clock, "TerminalClock", at(-L.HalfWidth + 0.9, 18, -47), fallbackClock)

	-- Sinalização suspensa no salão, indicando o caminho do portão.
	local way = deco(f, "Wayfinding_Concourse", V3(28, 3.6, 0.5), at(0, 20, -38), M.SmoothPlastic, C.SignFace)
	label(way, Enum.NormalId.Front, "PORTÕES A1–A4   ↓", C.TextOnSign, Enum.Font.GothamMedium)
	label(way, Enum.NormalId.Back, "↑ SAGUÃO / SAÍDA", C.TextOnSign, Enum.Font.GothamMedium)
	for _, dx in { -11, 11 } do
		deco(f, "WayRod", V3(0.25, 13, 0.25), at(dx, 28.3, -38), M.Metal, C.SteelDark)
	end
end

--------------------------------------------------------------------------------
-- Área externa (reservada pra pista futura)
--------------------------------------------------------------------------------

--[[
	BUG CORRIGIDO: ZNear estava em -1400 (mundo) = z relativo +100, ou seja
	NA FRENTE da fachada de entrada (z relativo = 44) -- a grama cobria o chão
	inteiro por baixo do terminal e vazava pelas portas da frente, porque
	"halfwidth 460" também é bem maior que a largura do prédio. Um terminal
	com grama nascendo debaixo dele não lê como aeroporto nenhum. Agora
	ZNear é travado no BORDO DE TRÁS do pátio pavimentado (abaixo), então a
	grama só começa depois de toda a pavimentação, nunca embaixo do prédio.
]]
local APRON_DEPTH = 46
local APRON_BACK_Z = L.ZGlass - 25 - APRON_DEPTH / 2 -- relativo: -152

local EXTERIOR = {
	HalfWidth = 460,
	ZNear = ORIGIN.Z + APRON_BACK_Z, -- mundo -- logo depois do pátio pavimentado
	ZFar = -2800, -- mundo
	Chunks = 4,
}

--[[
	Terrain é estado GLOBAL e PERSISTENTE do lugar -- diferente de Part, não
	existe dentro de Workspace.Lobby e AirportLobby.Clear() nunca o tocava.
	Uma versão anterior deste gerador escrevia grama em ZNear = -1400 (mundo),
	na FRENTE da fachada; corrigir o número no código não apaga o que já foi
	gravado no voxel grid -- só FillBlock com Air remove. Sem isto, qualquer
	lugar que já rodou a versão antiga fica com grama fantasma para sempre,
	mesmo depois de Generate({ Terrain = false }) ou de Clear().

	Por isso varremos com Air uma janela generosa ANTES de decidir se
	replanta grama ou não: cobre tanto a faixa antiga (ZNear -1400) quanto a
	atual (-1652), com folga.
]]
--[[
	Faixa BEM generosa de propósito. Duas fontes de resíduo, e nenhuma delas
	respeita exatamente a caixa que a gente pede:

	  1) A versão com o bug escrevia grama numa faixa de X/Z diferente da
	     atual -- corrigir o número no código não desfaz o que já foi
	     gravado no voxel grid.
	  2) SmoothTerrain do Roblox ARREDONDA a superfície nas bordas de um
	     FillBlock -- o topo pode "estufar" alguns studs ALÉM da caixa que
	     foi pedida. Uma margem vertical apertada (a versão anterior usava
	     Top=15, ~5 studs acima do piso) deixa exatamente essa sobra visível
	     furando o piso por dentro do salão -- foi o que aconteceu aqui.

	Por isso a margem vertical agora é enorme (Y -100..100, ~90 studs acima
	do piso) e a horizontal cobre folgadamente as duas versões. É uma
	operação de editor, roda uma vez; não precisa ser econômica.
]]
local LEGACY_SWEEP = {
	HalfWidth = 520,
	ZNear = -1280, -- mundo -- folga bem além da fachada (relativo +220)
	ZFar = -2900, -- mundo -- folga além do fim da grama
	Bottom = -100,
	Top = 100,
	Chunks = 8,
}

local function sweepExteriorTerrain()
	local height = LEGACY_SWEEP.Top - LEGACY_SWEEP.Bottom
	local chunkDepth = (LEGACY_SWEEP.ZNear - LEGACY_SWEEP.ZFar) / LEGACY_SWEEP.Chunks
	for i = 0, LEGACY_SWEEP.Chunks - 1 do
		Terrain:FillBlock(
			CFrame.new(0, LEGACY_SWEEP.Bottom + height / 2, LEGACY_SWEEP.ZNear - chunkDepth * (i + 0.5)),
			V3(LEGACY_SWEEP.HalfWidth * 2, height, chunkDepth),
			Enum.Material.Air
		)
	end
end

local function buildExterior(parent: Instance, withTerrain: boolean)
	local f = folder(parent, "ExteriorFutureArea")

	-- Sempre limpa primeiro -- inclusive quando withTerrain = false, que é
	-- exatamente o caso de "só quero tirar a grama".
	sweepExteriorTerrain()

	--[[
		Pátio pavimentado entre o vidro e a grama -- pista/táxi mesmo, não só
		concreto liso: Asphalt escuro com eixo pintado e faixa de borda, do
		jeito que se vê saindo de qualquer portão de embarque de verdade. Fica
		nesta pasta de propósito -- é a primeira coisa a sumir quando a pista
		de verdade for construída. Largura = a mesma da grama (HalfWidth*2),
		pra não sobrar nenhuma faixa de void entre os dois.

		Y = GROUND_LEVEL_Y, ABSOLUTO -- não `at()`, que agora despencaria
		30 studs junto com o piso elevado do terminal.
	]]
	local apronWidth = EXTERIOR.HalfWidth * 2
	box(f, "Apron", V3(apronWidth, L.FloorDepth + 1, APRON_DEPTH), atGround(0, GROUND_LEVEL_Y - (L.FloorDepth + 1) / 2 + 0.1, L.ZGlass - 25), M.Asphalt, C.Apron)
	deco(f, "ApronCenterline", V3(1, 0.2, APRON_DEPTH - 6), atGround(0, GROUND_LEVEL_Y + 0.15, L.ZGlass - 25), M.SmoothPlastic, C.AccentWarm)
	deco(f, "ApronEdgeLineNear", V3(apronWidth, 0.2, 0.6), atGround(0, GROUND_LEVEL_Y + 0.15, L.ZGlass - 4), M.SmoothPlastic, C.TextOnSign)
	deco(f, "ApronEdgeLineFar", V3(apronWidth, 0.2, 0.6), atGround(0, GROUND_LEVEL_Y + 0.15, L.ZGlass - 46), M.SmoothPlastic, C.TextOnSign)
	for x = -420, 420, 60 do
		deco(f, "ApronDash", V3(6, 0.2, 1), atGround(x, GROUND_LEVEL_Y + 0.16, L.ZGlass - 25), M.SmoothPlastic, C.AccentWarm)
	end

	-- Envelope reservado. Nenhum sistema lê isto hoje; é documentação viva pra
	-- quem for construir a pista não ter que medir de novo. Fica no nível do
	-- CHÃO (onde a pista de verdade vai nascer), não na altura do terminal.
	local reserve = S.Marker(f, "AreaFuturaPista", CFrame.new(ORIGIN.X, GROUND_LEVEL_Y, (EXTERIOR.ZNear + EXTERIOR.ZFar) / 2), {
		AreaFuturaPista = true,
		LarguraStuds = EXTERIOR.HalfWidth * 2,
		ProfundidadeStuds = EXTERIOR.ZNear - EXTERIOR.ZFar,
		BordaDoVidroZ = ORIGIN.Z + L.ZGlass,
		NivelDoChaoY = GROUND_LEVEL_Y,
	})
	reserve.Size = V3(8, 8, 8)

	if not withTerrain then
		-- A varredura acima já tirou a grama (velha e nova). Sem replantar.
		return
	end

	-- Grama plana, só a partir de onde o pátio pavimentado termina. Em
	-- pedaços porque um FillBlock único desse volume é lento e trava o
	-- Studio sem dar sinal de vida.
	local top = GROUND_LEVEL_Y
	local bottom = -30
	local height = top - bottom
	local chunkDepth = (EXTERIOR.ZNear - EXTERIOR.ZFar) / EXTERIOR.Chunks
	for i = 0, EXTERIOR.Chunks - 1 do
		Terrain:FillBlock(
			CFrame.new(0, bottom + height / 2, EXTERIOR.ZNear - chunkDepth * (i + 0.5)),
			V3(EXTERIOR.HalfWidth * 2, height, chunkDepth),
			Enum.Material.Grass
		)
	end
end

--------------------------------------------------------------------------------
-- Fundação -- o terminal fica ELEVADO acima do nível do chão/pista (não faz
-- sentido a sala de embarque estar na mesma altura de onde os aviões vão
-- taxiar), mas precisa "pousar" em alguma coisa visível, não flutuar.
--------------------------------------------------------------------------------

local function buildFoundation(parent: Instance)
	local f = folder(parent, "Foundation")

	--[[
		Todas as alturas aqui são Y ABSOLUTO (não relativo a ORIGIN.Y como o
		resto do arquivo) -- é a ponte entre o piso elevado e o chão externo,
		então ela PRECISA das duas referências ao mesmo tempo.

		Topo: 1 stud DENTRO do Plinth de buildFloor (mesma fórmula), pra
		nunca sobrar fresta visível na emenda entre "prédio" e "fundação".
		Fundo: "planta" um pouco abaixo do nível do pátio/grama, em vez de
		parar exatamente nele -- evita fresta se o terreno variar.
	]]
	local plinthBottom = ORIGIN.Y - (L.FloorDepth + 1) - 0.4 -- mesma conta do Plinth em buildFloor
	local top = plinthBottom + 1
	local bottom = GROUND_LEVEL_Y - 5
	local height = top - bottom
	if height <= 0 then
		warn("[AirportLobby] ORIGIN.Y baixo demais -- a fundação ficaria com altura negativa.")
		return
	end

	-- Um pouco além das paredes externas: dá o efeito de "podium" clássico
	-- de terminal (a base é mais larga que o volume que ela sustenta).
	local halfX = L.HalfWidth + L.WallThick + 4
	local zFront = L.ZFacade + 12 -- cobre até debaixo do meio-fio de desembarque
	local zBack = L.ZEave - 2 -- relativo
	local width = halfX * 2
	local depth = zFront - zBack
	local zMid = (zFront + zBack) / 2
	local midY = bottom + height / 2

	-- Paredes ocas (ninguém entra aqui, não precisa ser sólido por dentro):
	-- fecham o volume visto de fora inteiro, sem fresta em nenhum lado. Y
	-- vem de atGround (absoluto), X/Z de at() (relativo) -- então construímos
	-- o CFrame na mão em vez de usar os dois helpers ao mesmo tempo.
	local function podiumCF(x: number, z: number): CFrame
		return CFrame.new(ORIGIN.X + x, midY, ORIGIN.Z + z)
	end
	box(f, "PodiumWall_Front", V3(width + L.WallThick * 2, height, L.WallThick * 2), podiumCF(0, zFront), M.Concrete, C.WallDark)
	box(f, "PodiumWall_Back", V3(width + L.WallThick * 2, height, L.WallThick * 2), podiumCF(0, zBack), M.Concrete, C.WallDark)
	box(f, "PodiumWall_W", V3(L.WallThick * 2, height, depth), podiumCF(-halfX, zMid), M.Concrete, C.WallDark)
	box(f, "PodiumWall_E", V3(L.WallThick * 2, height, depth), podiumCF(halfX, zMid), M.Concrete, C.WallDark)

	-- Frisos marcando as transições -- "prédio" em cima, "fundação" embaixo,
	-- "chão" no rodapé. Sem eles o volume lê como um bloco genérico enorme.
	deco(f, "PodiumCap", V3(width + 6, 1, depth + 6), CFrame.new(ORIGIN.X, top + 0.5, ORIGIN.Z + zMid), M.Concrete, C.Skirting)
	deco(f, "PodiumFooting", V3(width + 10, 1.6, depth + 10), CFrame.new(ORIGIN.X, bottom - 0.6, ORIGIN.Z + zMid), M.Concrete, C.SteelDark)

	-- Pilastras verticais nas quatro faces: textura, não deixa parecer uma
	-- caixa lisa gigante enterrada no chão.
	for z = zBack + 10, zFront - 10, 20 do
		for _, side in { -1, 1 } do
			deco(f, "PodiumRib", V3(2, height - 2, 3), podiumCF(halfX * side, z), M.Concrete, C.Wall)
		end
	end
	for x = -halfX + 14, halfX - 14, 20 do
		deco(f, "PodiumRibFront", V3(3, height - 2, 2), podiumCF(x, zFront), M.Concrete, C.Wall)
		deco(f, "PodiumRibBack", V3(3, height - 2, 2), podiumCF(x, zBack), M.Concrete, C.Wall)
	end

	-- Contraventamento diagonal nas duas quinas junto da janela -- lê como
	-- estrutura de apoio de verdade bem no ponto que o jogador mais encara
	-- (de frente pro vidro, olhando pra fora e pra baixo).
	for _, side in { -1, 1 } do
		local x = halfX * side
		local topPoint = Vector3.new(ORIGIN.X + x, top - 2, ORIGIN.Z + zBack + 6)
		local bottomPoint = Vector3.new(ORIGIN.X + x * 0.55, bottom + 2, ORIGIN.Z + zBack + 6)
		spanBox(f, "PodiumBrace", topPoint, bottomPoint, 1.2, 1.2, M.Metal, C.Steel)
	end
end

--------------------------------------------------------------------------------
-- Peças que pertencem ao LobbyManager
--------------------------------------------------------------------------------

--[[
	LobbySpawn/LobbyFloor/IniciarPartida são de LobbyManager e vivem na RAIZ do
	Workspace (ele procura com FindFirstChild NÃO recursivo -- movê-las pra
	dentro de Lobby/ faria ele criar duplicatas no próximo boot). Então aqui só
	se ajusta o que LobbyManager NÃO reescreve:

	  LobbySpawn  -> ele escreve Anchored/Neutral/Size/Position. Transparency,
	                 CanCollide, Duration e a ROTAÇÃO do CFrame sobrevivem.
	  LobbyFloor  -> Transparency. A face de cima dele está exatamente na mesma
	                 altura do piso novo; sem isto as duas brigam por
	                 profundidade e o chão fica piscando.
]]
local function adoptExistingLobbyParts()
	local spawnLocation = Workspace:FindFirstChild("LobbySpawn")
	if spawnLocation and spawnLocation:IsA("SpawnLocation") then
		spawnLocation.Transparency = 1
		spawnLocation.CanCollide = false
		spawnLocation.CastShadow = false
		spawnLocation.Duration = 0 -- sem forcefield azul no lobby
		-- Rotação identidade = LookVector (0,0,-1): nasce olhando pro vidro.
		spawnLocation.CFrame = CFrame.new(spawnLocation.Position)
	else
		warn("[AirportLobby] LobbySpawn não encontrado -- sincronize o Rojo ou rode o jogo uma vez antes.")
	end

	local lobbyFloor = Workspace:FindFirstChild("LobbyFloor")
	if lobbyFloor and lobbyFloor:IsA("BasePart") then
		lobbyFloor.Transparency = 1
		lobbyFloor.CastShadow = false
	end

	local startPart = Workspace:FindFirstChild("IniciarPartida")
	if startPart and startPart:IsA("BasePart") then
		startPart.CastShadow = false
	end
end

--------------------------------------------------------------------------------
-- API
--------------------------------------------------------------------------------

function AirportLobby.Clear()
	local existing = Workspace:FindFirstChild("Lobby")
	if existing then
		existing:Destroy()
	end
	sweepExteriorTerrain()
end

export type BuildOptions = {
	Assets: boolean?, -- false: nem tenta o Toolbox, só Parts + placeholders
	Terrain: boolean?, -- false: não escreve a grama externa
}

function AirportLobby.Build(options: BuildOptions?): Folder
	local opts: BuildOptions = options or {}
	useAssets = opts.Assets ~= false
	local withTerrain = opts.Terrain ~= false

	table.clear(report)
	table.clear(assetFailed)

	AirportLobby.Clear()

	local lobby = Instance.new("Folder")
	lobby.Name = "Lobby"
	lobby:SetAttribute("Gerado", true)
	lobby.Parent = Workspace

	local airport = folder(lobby, "Airport")
	local architecture = folder(airport, "Architecture")
	placeholderFolder = folder(airport, "AssetPlaceholders")

	buildFloor(architecture)
	buildWalls(architecture)
	buildFacade(architecture)
	buildCeiling(architecture)
	buildPillars(architecture)
	buildGlass(architecture)

	buildCheckIn(airport)
	buildSecurity(airport)
	buildWaitingArea(airport)
	buildBoardingGate(airport)
	buildLighting(airport)
	buildProps(airport)
	buildFoundation(airport)
	buildExterior(airport, withTerrain)

	adoptExistingLobbyParts()

	local parts = 0
	for _, d in lobby:GetDescendants() do
		if d:IsA("BasePart") then
			parts += 1
		end
	end
	print(string.format("[AirportLobby] Terminal montado em (%.0f, %.0f, %.0f) -- %d peças.", ORIGIN.X, ORIGIN.Y, ORIGIN.Z, parts))

	local missingAny = false
	for id, row in report do
		if row.Missing > 0 then
			missingAny = true
			warn(string.format("[AirportLobby] %s (%d): %d posição(ões) SEM o asset -- versão em Parts no lugar, marcador em Lobby/Airport/AssetPlaceholders.", row.Label, id, row.Missing))
		else
			print(string.format("[AirportLobby] %s (%d): %d colocado(s).", row.Label, id, row.Loaded))
		end
	end
	if missingAny then
		print("[AirportLobby] Pra colocar na mão: insira o modelo pelo Toolbox, arraste pro CFrame do PLACEHOLDER correspondente (Attribute CFrameAlvo) e apague o placeholder junto com a pasta _Fallback ao lado.")
	end
	if withTerrain then
		print(string.format("[AirportLobby] Grama externa: x +-%d, z %d..%d. O vidro está em z = %d -- todo o resto é espaço livre pra pista.", EXTERIOR.HalfWidth, EXTERIOR.ZNear, EXTERIOR.ZFar, ORIGIN.Z + L.ZGlass))
	end
	print("[AirportLobby] Salve o lugar (Ctrl+S) -- geometria gerada não volta pelo Rojo.")

	placeholderFolder = nil
	return lobby
end

-- Alias: o resto das ferramentas do projeto usa Generate().
function AirportLobby.Generate(options: BuildOptions?): Folder
	return AirportLobby.Build(options)
end

return AirportLobby
