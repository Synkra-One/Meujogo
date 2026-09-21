--!strict
--[[
	SurvivalMinimapHUD

	Painel circular no canto inferior direito, montado em três camadas que se
	encaixam pelo ZIndex:

	  3  disco do mapa da ilha
	  6  arco de fôlego (StaminaRing) -- anel vermelho-vinho, cortado por
	     UIGradient, que só encurta conforme o fôlego cai
	 10  moldura do Figma ............. só decoração, por cima de tudo

	A barra de vida e o gauge antigo de fôlego (arcos de 24 segmentos +
	badges) saíram daqui: o arco é a única leitura de fôlego na tela, e ele só
	desenha o valor que StaminaHUD.client.luau lê do Attribute "Stamina".
]]

local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local IslandMapData = require(ReplicatedStorage.Modules.IslandMapData)
local MapMarkers = require(ReplicatedStorage.Modules.MapMarkers)
local StaminaRing = require(script.Parent.StaminaRing)

local SurvivalMinimapHUD = {}
SurvivalMinimapHUD.__index = SurvivalMinimapHUD

local WIDGET_SIZE = 320
local MAP_SIZE = 168
local MAP_CENTER = Vector2.new(160, 160)
local MAP_RESOLUTION = 42

-- Geometria calibrada pixel a pixel em cima do export real do Figma
-- (Imagens/Minimapa/3c71779a-444d-4931-be0d-12a0b3069dd0.png, 1254x1254): a
-- trilha vermelha original ocupa a faixa de raio ~0.75..0.89 da metade da
-- imagem, e é nela que o arco tem que cair.
--
-- O atlas do arco (StaminaRingAtlas.png) desenha o anel exatamente nessa
-- faixa, então basta arco e moldura saírem no MESMO tamanho e centrados no
-- mesmo ponto pra encaixarem -- tamanhos diferentes viram dois anéis
-- concêntricos. RING_SIZE sai do tamanho do mapa pro anel encostar na borda
-- dele sem folga.
local RING_INNER_FRAC = 0.75
local RING_SIZE = MAP_SIZE / RING_INNER_FRAC

-- Camadas: mapa (3) < arco (6) < moldura do Figma (10). O arco tem furo
-- próprio na textura, então passa por cima do mapa sem tapá-lo.
local FILL_ZINDEX = 6
local FRAME_ZINDEX = 10

local COLORS = {
	MapEdge = Color3.fromRGB(194, 196, 188),
	Text = Color3.fromRGB(238, 238, 226),
	Poi = Color3.fromRGB(221, 214, 190),
	Player = Color3.fromRGB(255, 255, 255),
}

export type DiscoveredEntry = {
	key: string,
	x: number,
	z: number,
	itemId: string?,
	category: string,
	label: string?,
}

type Payload = {
	resolution: number,
	mapHalf: number,
	rects: string,
	pois: { { [string]: any } },
	trails: { { number } },
}

local function frame(parent: Instance, name: string, color: Color3?, zIndex: number?): Frame
	local item = Instance.new("Frame")
	item.Name = name
	item.BorderSizePixel = 0
	item.BackgroundColor3 = color or Color3.new(0, 0, 0)
	item.BackgroundTransparency = if color then 0 else 1
	item.ZIndex = zIndex or 1
	item.Parent = parent
	return item
end

local function circle(parent: Instance, name: string, size: number, color: Color3, zIndex: number): Frame
	local item = frame(parent, name, color, zIndex)
	item.AnchorPoint = Vector2.new(0.5, 0.5)
	item.Size = UDim2.fromOffset(size, size)
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(1, 0)
	corner.Parent = item
	return item
end

local function textLabel(parent: Instance, name: string, text: string, size: number, zIndex: number): TextLabel
	local label = Instance.new("TextLabel")
	label.Name = name
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamBold
	label.Text = text
	label.TextColor3 = COLORS.Text
	label.TextSize = size
	label.TextStrokeColor3 = Color3.new(0, 0, 0)
	label.TextStrokeTransparency = 0.35
	label.ZIndex = zIndex
	label.Parent = parent
	return label
end

local function stroke(parent: Instance, color: Color3, thickness: number, transparency: number): UIStroke
	local item = Instance.new("UIStroke")
	item.Color = color
	item.Thickness = thickness
	item.Transparency = transparency
	item.Parent = parent
	return item
end

local function readPayload(): Payload?
	local value = ReplicatedStorage:FindFirstChild(IslandMapData.ValueName)
	if not value then
		value = ReplicatedStorage:WaitForChild(IslandMapData.ValueName, 20)
	end
	if not value or not value:IsA("StringValue") or value.Value == "" then
		return nil
	end
	local ok, decoded = pcall(function()
		return HttpService:JSONDecode(value.Value)
	end)
	if not ok or type(decoded) ~= "table" then
		return nil
	end
	return decoded :: any
end

local function buildReducedRects(payload: Payload): { IslandMapData.Rect }
	local sourceRects = IslandMapData.DecodeRects(payload.rects)
	local sourceResolution = payload.resolution
	local cells: { { number } } = {}
	for y = 1, sourceResolution do
		cells[y] = table.create(sourceResolution, 1)
	end
	for _, rect in sourceRects do
		for y = rect.y + 1, math.min(rect.y + rect.h, sourceResolution) do
			local row = cells[y]
			for x = rect.x + 1, math.min(rect.x + rect.w, sourceResolution) do
				row[x] = rect.c
			end
		end
	end

	local reduced: { { number } } = {}
	for y = 1, MAP_RESOLUTION do
		local sourceY = math.clamp(math.floor((y - 0.5) / MAP_RESOLUTION * sourceResolution) + 1, 1, sourceResolution)
		local row = table.create(MAP_RESOLUTION, 1)
		for x = 1, MAP_RESOLUTION do
			local normalizedX = ((x - 0.5) / MAP_RESOLUTION) * 2 - 1
			local normalizedY = ((y - 0.5) / MAP_RESOLUTION) * 2 - 1
			if normalizedX * normalizedX + normalizedY * normalizedY <= 1 then
				local sourceX = math.clamp(math.floor((x - 0.5) / MAP_RESOLUTION * sourceResolution) + 1, 1, sourceResolution)
				row[x] = cells[sourceY][sourceX]
			else
				row[x] = 0
			end
		end
		reduced[y] = row
	end
	return IslandMapData.MergeRects(reduced, MAP_RESOLUTION)
end

function SurvivalMinimapHUD.new(parent: Instance)
	local self = setmetatable({}, SurvivalMinimapHUD)
	self.payload = nil
	self.built = false
	self.discovered = {}
	self.pending = {}
	self.queued = {}
	self.healthShown = 1

	local root = Instance.new("CanvasGroup")
	root.Name = "VitalsMinimap"
	root.AnchorPoint = Vector2.new(1, 1)
	root.Position = UDim2.new(1, -24, 1, -138)
	root.Size = UDim2.fromOffset(WIDGET_SIZE, WIDGET_SIZE)
	root.BackgroundTransparency = 1
	root.Parent = parent
	self.root = root

	local scale = Instance.new("UIScale")
	scale.Scale = if UserInputService.TouchEnabled then 0.8 else 1
	scale.Parent = root

	-- Aqui existia um círculo preto de sombra com raio MAIOR que o anel: ele
	-- vazava por fora e virava um halo escuro em volta do HUD. Removido. O
	-- único fundo que sobra é o disco do próprio mapa, dentro do anel.
	local mapClip = circle(root, "MapClip", MAP_SIZE, Color3.fromRGB(8, 12, 12), 3)
	mapClip.Position = UDim2.fromOffset(MAP_CENTER.X, MAP_CENTER.Y)
	mapClip.ClipsDescendants = true
	stroke(mapClip, COLORS.MapEdge, 2, 0.3)
	self.mapClip = mapClip

	local terrain = frame(mapClip, "Terrain", nil, 3)
	terrain.Size = UDim2.fromScale(1, 1)
	self.terrain = terrain

	local trails = frame(mapClip, "Trails", nil, 4)
	trails.Size = UDim2.fromScale(1, 1)
	self.trails = trails

	local pois = frame(mapClip, "POIs", nil, 5)
	pois.Size = UDim2.fromScale(1, 1)
	self.pois = pois

	local items = frame(mapClip, "Items", nil, 6)
	items.Size = UDim2.fromScale(1, 1)
	self.items = items

	local playerHalo = circle(mapClip, "PlayerHalo", 22, Color3.new(0, 0, 0), 7)
	playerHalo.BackgroundTransparency = 0.35
	playerHalo.Visible = false
	self.playerHalo = playerHalo

	local playerArrow = textLabel(mapClip, "Player", "▲", 23, 8)
	playerArrow.AnchorPoint = Vector2.new(0.5, 0.5)
	playerArrow.Size = UDim2.fromOffset(26, 26)
	playerArrow.TextColor3 = COLORS.Player
	playerArrow.Visible = false
	self.playerArrow = playerArrow

	for _, compass in {
		{ name = "N", position = UDim2.new(0.5, 0, 0, 4) },
		{ name = "E", position = UDim2.new(1, -5, 0.5, 0) },
		{ name = "S", position = UDim2.new(0.5, 0, 1, -5) },
		{ name = "W", position = UDim2.new(0, 5, 0.5, 0) },
	} do
		local label = textLabel(mapClip, "Compass" .. compass.name, compass.name, 12, 9)
		label.AnchorPoint = Vector2.new(0.5, 0.5)
		label.Position = compass.position
		label.Size = UDim2.fromOffset(18, 16)
	end

	local loading = textLabel(mapClip, "Loading", "CARREGANDO MAPA", 11, 9)
	loading.Size = UDim2.fromScale(1, 1)
	loading.TextColor3 = Color3.fromRGB(155, 159, 151)
	self.loading = loading

	-- Mapa carrega independente do anel: se o anel falhar por algum motivo,
	-- o resto do HUD (mapa, bússola) não pode travar junto de novo.
	task.spawn(function()
		self:_prepare()
	end)

	-- Arco de fôlego: o preenchimento entra ABAIXO do mapa (o mapa é o que faz
	-- o furo do anel) e a moldura do Figma por cima de tudo.
	local ok, staminaRing = pcall(StaminaRing.new, root, {
		center = MAP_CENTER,
		ringSize = RING_SIZE,
		frameSize = RING_SIZE, -- tem que ser igual a ringSize: mesma imagem, só escalada por esse tamanho
		fillZIndex = FILL_ZINDEX,
		frameZIndex = FRAME_ZINDEX,
	})
	if ok then
		self.staminaRing = staminaRing
	else
		warn("SurvivalMinimapHUD: StaminaRing falhou ao construir, HUD segue sem o anel -- " .. tostring(staminaRing))
	end

	return self
end

function SurvivalMinimapHUD:_prepare()
	local payload = readPayload()
	if not payload then
		self.loading.Text = "MAPA INDISPONIVEL"
		return
	end
	self.payload = payload
	local palette = IslandMapData.BuildPalette()
	local rects = buildReducedRects(payload)
	for index, rect in rects do
		if rect.c == 0 then
			continue
		end
		local cell = frame(self.terrain, "Land", palette[rect.c] or Color3.fromRGB(80, 80, 80), 3)
		cell.Position = UDim2.fromScale(rect.x / MAP_RESOLUTION, rect.y / MAP_RESOLUTION)
		cell.Size = UDim2.fromScale((rect.w + 0.2) / MAP_RESOLUTION, (rect.h + 0.2) / MAP_RESOLUTION)
		if index % 180 == 0 then
			task.wait()
		end
	end

	for _, segment in payload.trails do
		local u1, v1 = IslandMapData.WorldToMap(segment[1], segment[2], payload.mapHalf)
		local u2, v2 = IslandMapData.WorldToMap(segment[3], segment[4], payload.mapHalf)
		local dx, dy = u2 - u1, v2 - v1
		local length = math.sqrt(dx * dx + dy * dy)
		if length > 0.0001 then
			local line = frame(self.trails, "Trail", Color3.fromRGB(184, 160, 111), 4)
			line.AnchorPoint = Vector2.new(0.5, 0.5)
			line.Position = UDim2.fromScale((u1 + u2) * 0.5, (v1 + v2) * 0.5)
			line.Size = UDim2.new(length, 0, 0, 1)
			line.Rotation = math.deg(math.atan2(dy, dx))
			line.BackgroundTransparency = 0.28
		end
	end

	for _, poi in payload.pois do
		if type(poi.x) == "number" and type(poi.z) == "number" then
			local u, v = IslandMapData.WorldToMap(poi.x, poi.z, payload.mapHalf)
			local mark = frame(self.pois, "POI", COLORS.Poi, 5)
			mark.AnchorPoint = Vector2.new(0.5, 0.5)
			mark.Position = UDim2.fromScale(u, v)
			mark.Size = UDim2.fromOffset(6, 6)
			mark.Rotation = 45
			stroke(mark, Color3.new(0, 0, 0), 1, 0.3)
		end
	end

	self.built = true
	self.loading.Visible = false
	local pending = self.pending
	self.pending = {}
	for _, entry in pending do
		self.queued[entry.key] = nil
		self:AddDiscoveredItem(entry)
	end
end

function SurvivalMinimapHUD:AddDiscoveredItem(entry: DiscoveredEntry?)
	if not entry or type(entry.key) ~= "string" or self.discovered[entry.key] or self.queued[entry.key] then
		return
	end
	if not self.built or not self.payload then
		self.queued[entry.key] = true
		table.insert(self.pending, entry)
		return
	end

	local payload = self.payload :: Payload
	local u, v = IslandMapData.WorldToMap(entry.x, entry.z, payload.mapHalf)
	local holder = frame(self.items, "Item", nil, 6)
	holder.AnchorPoint = Vector2.new(0.5, 0.5)
	holder.Position = UDim2.fromScale(u, v)
	holder.Size = UDim2.fromOffset(12, 12)

	local image = MapMarkers.ImageFor(entry.itemId)
	if image ~= "" then
		local icon = Instance.new("ImageLabel")
		icon.BackgroundTransparency = 1
		icon.Image = image
		icon.Size = UDim2.fromScale(1, 1)
		icon.ZIndex = 6
		icon.Parent = holder
		stroke(icon, Color3.new(0, 0, 0), 1, 0.25)
	else
		local markerStyle = MapMarkers.Style(entry.category)
		local badge = circle(holder, "Badge", 11, markerStyle.Color, 6)
		badge.Position = UDim2.fromScale(0.5, 0.5)
		stroke(badge, Color3.new(0, 0, 0), 1, 0.2)
		local glyph = textLabel(badge, "Glyph", markerStyle.Glyph, 8, 7)
		glyph.Size = UDim2.fromScale(1, 1)
	end
	self.discovered[entry.key] = holder
end

function SurvivalMinimapHUD:SetDiscoveredItems(entries: { DiscoveredEntry })
	for _, entry in entries do
		self:AddDiscoveredItem(entry)
	end
end

-- health entra só pra decidir o fade de "tudo cheio e parado" (não vira gauge
-- nenhum aqui); stamina é o fôlego real 0..1 -- StaminaRing cuida da
-- suavização visual sozinho, sem timer próprio.
--[[
	Update(..., fearHidden)
	fearHidden (0..1) vem de FearPresentationRules.HudFade: em pânico o painel
	inteiro -- mapa E arco de fôlego, que moram no mesmo CanvasGroup -- apaga.
	É só leitura: o Attribute "Stamina" e o mapa continuam intactos por baixo.
]]
function SurvivalMinimapHUD:Update(dt: number, health: number, stamina: number, exhausted: boolean, holding: boolean, fearHidden: number?)
	self.healthShown += (math.clamp(health, 0, 1) - self.healthShown) * math.min(1, dt * 12)
	local staminaFraction = math.clamp(stamina, 0, 1)
	if self.staminaRing then
		-- `stamina` já chega normalizado (StaminaHUD divide o Attribute 0..100
		-- por 100). NÃO dividir de novo aqui.
		self.staminaRing:SetProgress(staminaFraction)
		self.staminaRing:Update(dt)
	end

	local pulse = (math.sin(os.clock() * 8) + 1) * 0.5
	local idle = if staminaFraction >= 0.995 and self.healthShown >= 0.995 and not holding
		then 0.08
		elseif exhausted then pulse * 0.08
		else 0
	-- O medo só pode ESCONDER mais, nunca revelar: o maior dos dois ganha.
	local hidden = math.clamp(if type(fearHidden) == "number" and fearHidden == fearHidden then fearHidden else 0, 0, 1)
	self.root.GroupTransparency = math.max(idle, hidden)
	self.root.Visible = hidden < 0.999
end

function SurvivalMinimapHUD:UpdatePlayer(position: Vector3?, heading: number?)
	local payload = self.payload
	if not payload or not position then
		self.playerArrow.Visible = false
		self.playerHalo.Visible = false
		return
	end
	local u, v = IslandMapData.WorldToMap(position.X, position.Z, payload.mapHalf)
	if u < 0 or u > 1 or v < 0 or v > 1 then
		self.playerArrow.Visible = false
		self.playerHalo.Visible = false
		return
	end
	local mapPosition = UDim2.fromScale(math.clamp(u, 0.03, 0.97), math.clamp(v, 0.03, 0.97))
	self.playerArrow.Position = mapPosition
	self.playerHalo.Position = mapPosition
	self.playerArrow.Rotation = heading or 0
	self.playerArrow.Visible = true
	self.playerHalo.Visible = true
end

return SurvivalMinimapHUD
