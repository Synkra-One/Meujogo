--!strict
--[[
	SurvivalMinimapHUD

	Painel circular inspirado no HUD de sobrevivencia: o mapa real da ilha fica
	no centro, vida e folego ocupam arcos independentes, e itens descobertos
	permanecem marcados usando a mesma lista do mapa grande.
]]

local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local IslandMapData = require(ReplicatedStorage.Modules.IslandMapData)
local MapMarkers = require(ReplicatedStorage.Modules.MapMarkers)

local SurvivalMinimapHUD = {}
SurvivalMinimapHUD.__index = SurvivalMinimapHUD

local WIDGET_SIZE = 320
local MAP_SIZE = 214
local MAP_CENTER = Vector2.new(177, 154)
local MAP_RESOLUTION = 42
local ARC_SEGMENTS = 24

local COLORS = {
	Shell = Color3.fromRGB(13, 15, 18),
	ShellEdge = Color3.fromRGB(100, 103, 101),
	MapEdge = Color3.fromRGB(194, 196, 188),
	Health = Color3.fromRGB(239, 55, 48),
	HealthLow = Color3.fromRGB(255, 104, 56),
	Stamina = Color3.fromRGB(67, 196, 239),
	StaminaLow = Color3.fromRGB(242, 177, 63),
	Empty = Color3.fromRGB(46, 49, 52),
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

local function buildArc(parent: Instance, name: string, radius: number, thickness: number, zIndex: number): { Frame }
	local result: { Frame } = {}
	for index = 1, ARC_SEGMENTS do
		local progress = (index - 1) / (ARC_SEGMENTS - 1)
		local angle = math.rad(270 - progress * 180)
		local segment = frame(parent, string.format("%s_%02d", name, index), COLORS.Empty, zIndex)
		segment.AnchorPoint = Vector2.new(0.5, 0.5)
		segment.Position = UDim2.fromOffset(
			MAP_CENTER.X + math.cos(angle) * radius,
			MAP_CENTER.Y + math.sin(angle) * radius
		)
		segment.Size = UDim2.fromOffset(thickness, 11)
		segment.Rotation = math.deg(angle) + 90
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0, 2)
		corner.Parent = segment
		result[index] = segment
	end
	return result
end

local function updateArc(segments: { Frame }, value: number, color: Color3)
	local activeCount = math.floor(math.clamp(value, 0, 1) * #segments + 0.5)
	for index, segment in segments do
		local active = index <= activeCount
		segment.BackgroundColor3 = if active then color else COLORS.Empty
		segment.BackgroundTransparency = if active then 0.04 else 0.38
	end
end

function SurvivalMinimapHUD.new(parent: Instance)
	local self = setmetatable({}, SurvivalMinimapHUD)
	self.payload = nil
	self.built = false
	self.discovered = {}
	self.pending = {}
	self.queued = {}
	self.healthShown = 1
	self.staminaShown = 1

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

	local shadow = circle(root, "Shadow", 250, Color3.new(0, 0, 0), 1)
	shadow.Position = UDim2.fromOffset(MAP_CENTER.X + 4, MAP_CENTER.Y + 5)
	shadow.BackgroundTransparency = 0.35

	local shell = circle(root, "Shell", 238, COLORS.Shell, 2)
	shell.Position = UDim2.fromOffset(MAP_CENTER.X, MAP_CENTER.Y)
	stroke(shell, COLORS.ShellEdge, 5, 0.34)

	self.healthSegments = buildArc(root, "Health", 148, 12, 4)
	self.staminaSegments = buildArc(root, "Stamina", 127, 10, 4)

	local mapClip = circle(root, "MapClip", MAP_SIZE, Color3.fromRGB(8, 12, 12), 3)
	mapClip.Position = UDim2.fromOffset(MAP_CENTER.X, MAP_CENTER.Y)
	mapClip.ClipsDescendants = true
	stroke(mapClip, COLORS.MapEdge, 3, 0.26)
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

	local healthBadge = circle(root, "HealthBadge", 49, Color3.fromRGB(10, 11, 13), 10)
	healthBadge.Position = UDim2.fromOffset(78, 20)
	stroke(healthBadge, COLORS.Health, 3, 0.05)
	local heart = textLabel(healthBadge, "Heart", "♥", 27, 11)
	heart.Size = UDim2.fromScale(1, 1)
	heart.TextColor3 = COLORS.Health

	local staminaBadge = circle(root, "StaminaBadge", 43, Color3.fromRGB(10, 11, 13), 10)
	staminaBadge.Position = UDim2.fromOffset(121, 43)
	stroke(staminaBadge, COLORS.Stamina, 3, 0.05)
	local runner = textLabel(staminaBadge, "Runner", "⚡", 25, 11)
	runner.Size = UDim2.fromScale(1, 1)
	runner.TextColor3 = COLORS.Stamina

	local healthValue = textLabel(root, "HealthValue", "100", 13, 11)
	healthValue.Position = UDim2.fromOffset(34, 45)
	healthValue.Size = UDim2.fromOffset(44, 18)
	healthValue.TextXAlignment = Enum.TextXAlignment.Right
	healthValue.TextColor3 = COLORS.Health
	self.healthValue = healthValue

	local staminaValue = textLabel(root, "StaminaValue", "100", 13, 11)
	staminaValue.Position = UDim2.fromOffset(82, 64)
	staminaValue.Size = UDim2.fromOffset(42, 18)
	staminaValue.TextXAlignment = Enum.TextXAlignment.Right
	staminaValue.TextColor3 = COLORS.Stamina
	self.staminaValue = staminaValue

	local loading = textLabel(mapClip, "Loading", "CARREGANDO MAPA", 11, 9)
	loading.Size = UDim2.fromScale(1, 1)
	loading.TextColor3 = Color3.fromRGB(155, 159, 151)
	self.loading = loading

	task.spawn(function()
		self:_prepare()
	end)
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

function SurvivalMinimapHUD:Update(dt: number, health: number, stamina: number, exhausted: boolean, holding: boolean)
	self.healthShown += (math.clamp(health, 0, 1) - self.healthShown) * math.min(1, dt * 12)
	-- `stamina` já é suavemente amostrada pelo servidor a 20 Hz. Não aplicar
	-- outra interpolação aqui: ela atrasava o arco em relação ao momento real
	-- em que o sprint acabava ou era liberado novamente.
	self.staminaShown = math.clamp(stamina, 0, 1)

	local healthColor = if self.healthShown < 0.3 then COLORS.HealthLow else COLORS.Health
	local staminaColor = if exhausted
		then COLORS.Health
		elseif self.staminaShown < 0.3 then COLORS.StaminaLow
		else COLORS.Stamina
	updateArc(self.healthSegments, self.healthShown, healthColor)
	updateArc(self.staminaSegments, self.staminaShown, staminaColor)
	self.healthValue.Text = tostring(math.floor(math.clamp(health, 0, 1) * 100 + 0.5))
	self.healthValue.TextColor3 = healthColor
	self.staminaValue.Text = tostring(math.floor(math.clamp(stamina, 0, 1) * 100 + 0.5))
	self.staminaValue.TextColor3 = staminaColor

	local pulse = (math.sin(os.clock() * 8) + 1) * 0.5
	self.root.GroupTransparency = if self.staminaShown >= 0.995 and self.healthShown >= 0.995 and not holding
		then 0.08
		elseif exhausted then pulse * 0.08
		else 0
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
