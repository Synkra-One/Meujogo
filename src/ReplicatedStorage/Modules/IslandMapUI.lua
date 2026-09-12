--!strict
--[[
	IslandMapUI (era MonsterMapUI)
	O mapa da ilha em visão de cima. Roda no CLIENTE, em dois modos:

	  "teleport" -- o Monstro abre com Q pra escolher o destino do teleporte
	               (fenda). Clicar chama onPick(worldPos). Mostra o próprio
	               Monstro (UpdateMonster) e a boca da Caverna.
	  "view"     -- Sobreviventes/Espião abrem com M só pra se orientar
	               (client/SurvivorMapController). Não aceita clique, mostra
	               um marcador verde de "você" (UpdateSelf) e ESCONDE a
	               Caverna (é o spawn do Monstro -- não revela pro time humano).

	Os dois modos compartilham a mesma camada de ITENS DESCOBERTOS
	(AddDiscoveredItem/SetDiscoveredItems): quando um jogador passa perto de
	um item do mundo (server/ItemDiscovery.lua), o ícone dele fica marcado no
	mapa daquele jogador para o resto da partida.

	NÃO É ESTÉTICO: cada retângulo desenhado vem da grade que server/IslandMap
	amostrou de IslandLayout (a mesma matemática que escreveu o terreno), então
	a proporção é 1:1 com o mundo. Clicar em (u, v) devolve o (x, z) real por
	IslandMapData.MapToWorld -- e é esse ponto que vai pro servidor validar
	(modo "teleport"; o modo "view" não usa isso).

	API:
		local ui = IslandMapUI.new(playerGui, { mode = "teleport", onPick = fn })
		local ui = IslandMapUI.new(playerGui, { mode = "view" })
		ui:Prepare()                  -- monta em background (chame cedo)
		ui:Show(anchorPos, statusText) -- anchorPos = posição do Monstro (teleport) ou sua própria (view)
		ui:Hide()
		ui:IsOpen()
		ui:SetStatus(texto)
		ui:UpdateMonster(pos)          -- modo teleport
		ui:UpdateSelf(pos)             -- modo view
		ui:AddDiscoveredItem(entry)    -- entry = {key, x, z, itemId, category, label}
		ui:SetDiscoveredItems(list)
		ui:Destroy()
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HttpService = game:GetService("HttpService")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local GuiService = game:GetService("GuiService")

local IslandMapData = require(ReplicatedStorage.Modules.IslandMapData)
local MapMarkers = require(ReplicatedStorage.Modules.MapMarkers)

local IslandMapUI = {}
IslandMapUI.__index = IslandMapUI

--------------------------------------------------------------------------------
-- Estilo (mexa aqui pra mudar a cara do mapa)
--------------------------------------------------------------------------------

local Style = {
	Backdrop = Color3.fromRGB(0, 0, 0),
	BackdropTransparency = 0.42,
	Panel = Color3.fromRGB(11, 12, 15),
	PanelStroke = Color3.fromRGB(58, 24, 28), -- carmim apagado (bate com a fenda)
	Inner = Color3.fromRGB(6, 7, 9),
	Text = Color3.fromRGB(214, 208, 198),
	TextDim = Color3.fromRGB(126, 120, 112),
	Accent = Color3.fromRGB(178, 62, 58),
	Trail = Color3.fromRGB(150, 128, 92),
	Grid = Color3.fromRGB(255, 255, 255),
	GridTransparency = 0.93,
	Poi = Color3.fromRGB(226, 214, 186),
	PoiCave = Color3.fromRGB(196, 76, 68),
	Monster = Color3.fromRGB(228, 92, 84),
	Self = Color3.fromRGB(120, 224, 150),
	CursorOk = Color3.fromRGB(150, 226, 158),
	CursorBad = Color3.fromRGB(226, 96, 88),

	PanelScale = 0.82, -- fração da menor dimensão da tela
	TrailThickness = 2,
	GridLines = 8,
	-- Sobreposição entre retângulos vizinhos: mata as costuras finas que
	-- apareciam como grade fixa entre blocos de mesma cor (0.06 -> 0.22).
	RectBleed = 0.22,
}
IslandMapUI.Style = Style

--------------------------------------------------------------------------------
-- Helpers
--------------------------------------------------------------------------------

local function newFrame(parent: Instance, name: string, color: Color3?): Frame
	local f = Instance.new("Frame")
	f.Name = name
	f.BorderSizePixel = 0
	f.BackgroundColor3 = color or Color3.new(0, 0, 0)
	f.BackgroundTransparency = if color then 0 else 1
	f.Parent = parent
	return f
end

local function newText(parent: Instance, name: string, text: string, size: number, color: Color3): TextLabel
	local l = Instance.new("TextLabel")
	l.Name = name
	l.BackgroundTransparency = 1
	l.Text = text
	l.TextSize = size
	l.TextColor3 = color
	l.Font = Enum.Font.GothamMedium
	l.TextXAlignment = Enum.TextXAlignment.Left
	l.Parent = parent
	return l
end

--------------------------------------------------------------------------------
-- Construção
--------------------------------------------------------------------------------

export type Payload = {
	resolution: number,
	mapHalf: number,
	seaLevel: number?,
	rects: string,
	pois: { { [string]: any } },
	trails: { { number } },
	cave: { number },
}

export type Mode = "teleport" | "view"

export type DiscoveredEntry = {
	key: string,
	x: number,
	z: number,
	itemId: string?,
	category: string,
	label: string?,
}

export type Options = {
	mode: Mode?,
	onPick: ((Vector3) -> ())?,
}

function IslandMapUI.new(playerGui: Instance, opts: any?)
	-- Compatibilidade: aceitar `onPick` solto (assinatura antiga de MonsterMapUI)
	-- além do options table novo.
	local resolved: Options
	if type(opts) == "function" then
		resolved = { mode = "teleport", onPick = opts :: (Vector3) -> () }
	else
		resolved = (opts :: Options?) or {}
	end

	local self = setmetatable({}, IslandMapUI)
	self.playerGui = playerGui
	self.mode = resolved.mode or "teleport"
	self.onPick = resolved.onPick
	self.open = false
	self.built = false
	self.building = false
	self.payload = nil :: Payload?
	self.cells = nil :: { { number } }?
	self.conns = {} :: { RBXScriptConnection }
	self.haloTweens = nil :: { Tween }?
	self.discovered = {} :: { [string]: Frame }
	self.pendingItems = nil :: { DiscoveredEntry }?
	return self
end

function IslandMapUI:_readPayload(): Payload?
	local value = ReplicatedStorage:FindFirstChild(IslandMapData.ValueName)
	if not value then
		value = ReplicatedStorage:WaitForChild(IslandMapData.ValueName, 20) :: StringValue?
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

-- Grade de consulta (pra saber se o ponto clicado é água antes de mandar).
local function rebuildCells(rects: { IslandMapData.Rect }, resolution: number): { { number } }
	local cells: { { number } } = {}
	for j = 1, resolution do
		cells[j] = table.create(resolution, 1)
	end
	for _, r in rects do
		for j = r.y + 1, math.min(r.y + r.h, resolution) do
			local row = cells[j]
			for i = r.x + 1, math.min(r.x + r.w, resolution) do
				row[i] = r.c
			end
		end
	end
	return cells
end

function IslandMapUI:_buildGui()
	local gui = Instance.new("ScreenGui")
	gui.Name = if self.mode == "view" then "SurvivorMap" else "MonsterMap"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 40
	gui.Enabled = false
	gui.Parent = self.playerGui
	self.gui = gui

	local backdrop = newFrame(gui, "Backdrop", Style.Backdrop)
	backdrop.Size = UDim2.fromScale(1, 1)
	backdrop.BackgroundTransparency = Style.BackdropTransparency
	backdrop.ZIndex = 1

	local panel = newFrame(gui, "Panel", Style.Panel)
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.Position = UDim2.fromScale(0.5, 0.5)
	panel.Size = UDim2.fromScale(Style.PanelScale, Style.PanelScale)
	panel.ZIndex = 2
	local aspect = Instance.new("UIAspectRatioConstraint")
	aspect.AspectRatio = 1
	aspect.DominantAxis = Enum.DominantAxis.Height
	aspect.Parent = panel
	local panelCorner = Instance.new("UICorner")
	panelCorner.CornerRadius = UDim.new(0, 4)
	panelCorner.Parent = panel
	local panelStroke = Instance.new("UIStroke")
	panelStroke.Color = Style.PanelStroke
	panelStroke.Thickness = 2
	panelStroke.Transparency = 0.15
	panelStroke.Parent = panel
	local pad = Instance.new("UIPadding")
	pad.PaddingTop = UDim.new(0, 40)
	pad.PaddingBottom = UDim.new(0, 34)
	pad.PaddingLeft = UDim.new(0, 12)
	pad.PaddingRight = UDim.new(0, 12)
	pad.Parent = panel

	-- Cabeçalho (fora do padding: ancorado no topo do panel)
	local titleText = if self.mode == "view" then "MAPA DA ILHA" else "FENDA — ESCOLHA O DESTINO"
	local title = newText(panel, "Title", titleText, 17, Style.Text)
	title.Font = Enum.Font.GothamBold
	title.Position = UDim2.new(0, 0, 0, -32)
	title.Size = UDim2.new(1, 0, 0, 22)
	title.ZIndex = 3

	local status = newText(panel, "Status", "", 14, Style.TextDim)
	status.TextXAlignment = Enum.TextXAlignment.Right
	status.Position = UDim2.new(0, 0, 0, -32)
	status.Size = UDim2.new(1, 0, 0, 22)
	status.ZIndex = 3
	self.status = status

	local hintText = if self.mode == "view"
		then "M ou botão direito para fechar"
		else "clique no mapa para abrir a fenda   ·   Q ou botão direito para fechar"
	local hint = newText(panel, "Hint", hintText, 13, Style.TextDim)
	hint.TextXAlignment = Enum.TextXAlignment.Center
	hint.Position = UDim2.new(0, 0, 1, 6)
	hint.Size = UDim2.new(1, 0, 0, 20)
	hint.ZIndex = 3

	-- Área do mapa (quadrada, é aqui que a matemática acontece)
	local area = newFrame(panel, "MapArea", Style.Inner)
	area.Size = UDim2.fromScale(1, 1)
	area.ClipsDescendants = true
	area.ZIndex = 3
	local areaAspect = Instance.new("UIAspectRatioConstraint")
	areaAspect.AspectRatio = 1
	areaAspect.Parent = area
	self.area = area

	local terrain = newFrame(area, "Terrain")
	terrain.Size = UDim2.fromScale(1, 1)
	terrain.ZIndex = 3
	self.terrainLayer = terrain

	local overlay = newFrame(area, "Overlay")
	overlay.Size = UDim2.fromScale(1, 1)
	overlay.ZIndex = 5
	self.overlay = overlay

	local markers = newFrame(area, "Markers")
	markers.Size = UDim2.fromScale(1, 1)
	markers.ZIndex = 7
	self.markers = markers

	local items = newFrame(area, "Items")
	items.Size = UDim2.fromScale(1, 1)
	items.ZIndex = 7
	self.itemsLayer = items

	local cursor = newFrame(area, "Cursor")
	cursor.Size = UDim2.fromScale(1, 1)
	cursor.ZIndex = 9
	self.cursorLayer = cursor

	return gui
end

function IslandMapUI:_drawTerrain(payload: Payload, rects: { IslandMapData.Rect })
	local palette = IslandMapData.BuildPalette()
	local res = payload.resolution
	local bleed = Style.RectBleed
	local layer = self.terrainLayer

	for index, r in rects do
		local f = Instance.new("Frame")
		f.Name = "c"
		f.BorderSizePixel = 0
		f.BackgroundColor3 = palette[r.c] or Color3.new(1, 0, 1)
		f.Position = UDim2.fromScale(r.x / res, r.y / res)
		f.Size = UDim2.fromScale((r.w + bleed) / res, (r.h + bleed) / res)
		f.ZIndex = 3
		f.Parent = layer
		if index % 220 == 0 then
			task.wait()
		end
	end
end

function IslandMapUI:_drawGrid()
	local n = Style.GridLines
	for i = 1, n - 1 do
		local v = newFrame(self.overlay, "gv", Style.Grid)
		v.BackgroundTransparency = Style.GridTransparency
		v.Position = UDim2.fromScale(i / n, 0)
		v.Size = UDim2.new(0, 1, 1, 0)
		v.ZIndex = 5
		local h = newFrame(self.overlay, "gh", Style.Grid)
		h.BackgroundTransparency = Style.GridTransparency
		h.Position = UDim2.fromScale(0, i / n)
		h.Size = UDim2.new(1, 0, 0, 1)
		h.ZIndex = 5
	end
end

function IslandMapUI:_drawTrails(payload: Payload)
	local half = payload.mapHalf
	for _, seg in payload.trails do
		local u1, v1 = IslandMapData.WorldToMap(seg[1], seg[2], half)
		local u2, v2 = IslandMapData.WorldToMap(seg[3], seg[4], half)
		local du, dv = u2 - u1, v2 - v1
		local len = math.sqrt(du * du + dv * dv)
		if len < 1e-4 then
			continue
		end
		local line = newFrame(self.overlay, "trail", Style.Trail)
		line.AnchorPoint = Vector2.new(0.5, 0.5)
		line.Position = UDim2.fromScale((u1 + u2) / 2, (v1 + v2) / 2)
		line.Size = UDim2.new(len, 0, 0, Style.TrailThickness)
		line.Rotation = math.deg(math.atan2(dv, du))
		line.BackgroundTransparency = 0.45
		line.ZIndex = 6
	end
end

local function poiIcon(parent: Instance, u: number, v: number, label: string, color: Color3, zIndex: number)
	local holder = Instance.new("Frame")
	holder.Name = "poi"
	holder.BackgroundTransparency = 1
	holder.AnchorPoint = Vector2.new(0.5, 0.5)
	holder.Position = UDim2.fromScale(u, v)
	holder.Size = UDim2.fromOffset(10, 10)
	holder.ZIndex = zIndex
	holder.Parent = parent

	local diamond = Instance.new("Frame")
	diamond.Name = "d"
	diamond.BorderSizePixel = 0
	diamond.BackgroundColor3 = color
	diamond.AnchorPoint = Vector2.new(0.5, 0.5)
	diamond.Position = UDim2.fromScale(0.5, 0.5)
	diamond.Size = UDim2.fromOffset(7, 7)
	diamond.Rotation = 45
	diamond.ZIndex = zIndex
	diamond.Parent = holder
	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(0, 0, 0)
	stroke.Thickness = 1
	stroke.Transparency = 0.35
	stroke.Parent = diamond

	local text = Instance.new("TextLabel")
	text.Name = "t"
	text.BackgroundTransparency = 1
	text.Text = label
	text.TextSize = 12
	text.Font = Enum.Font.GothamMedium
	text.TextColor3 = color
	text.TextXAlignment = Enum.TextXAlignment.Center
	text.AnchorPoint = Vector2.new(0.5, 0)
	text.Position = UDim2.new(0.5, 0, 0, 7)
	text.Size = UDim2.fromOffset(120, 14)
	text.ZIndex = zIndex
	text.Parent = holder
	local textStroke = Instance.new("UIStroke")
	textStroke.Color = Color3.fromRGB(0, 0, 0)
	textStroke.Thickness = 2
	textStroke.Transparency = 0.25
	textStroke.Parent = text

	return holder
end

function IslandMapUI:_drawPois(payload: Payload)
	local half = payload.mapHalf
	for _, poi in payload.pois do
		local u, v = IslandMapData.WorldToMap(poi.x, poi.z, half)
		poiIcon(self.markers, u, v, poi.n, Style.Poi, 7)
	end
	-- A boca da Caverna é o spawn do Monstro -- não revela no mapa do
	-- Sobrevivente/Espião (modo "view").
	if self.mode ~= "view" and payload.cave and #payload.cave >= 2 then
		local u, v = IslandMapData.WorldToMap(payload.cave[1], payload.cave[2], half)
		poiIcon(self.markers, u, v, "Caverna", Style.PoiCave, 7)
	end
end

function IslandMapUI:_drawChrome(payload: Payload)
	-- Rosa dos ventos (norte = -Z = topo)
	local north = newText(self.overlay, "N", "N", 15, Style.TextDim)
	north.Font = Enum.Font.GothamBold
	north.TextXAlignment = Enum.TextXAlignment.Center
	north.AnchorPoint = Vector2.new(0.5, 0)
	north.Position = UDim2.new(0.5, 0, 0, 4)
	north.Size = UDim2.fromOffset(20, 18)
	north.ZIndex = 8

	-- Barra de escala (200 studs) -- reforça que a proporção é real
	local studs = 200
	local frac = studs / (payload.mapHalf * 2)
	local bar = newFrame(self.overlay, "scaleBar", Style.Text)
	bar.AnchorPoint = Vector2.new(0, 1)
	bar.Position = UDim2.new(0, 10, 1, -20)
	bar.Size = UDim2.new(frac, 0, 0, 2)
	bar.BackgroundTransparency = 0.25
	bar.ZIndex = 8
	for _, x in { 0, 1 } do
		local tick = newFrame(bar, "tick", Style.Text)
		tick.AnchorPoint = Vector2.new(x, 1)
		tick.Position = UDim2.fromScale(x, 1)
		tick.Size = UDim2.fromOffset(2, 7)
		tick.BackgroundTransparency = 0.25
		tick.ZIndex = 8
	end
	local barLabel = newText(self.overlay, "scaleText", studs .. " studs", 12, Style.TextDim)
	barLabel.AnchorPoint = Vector2.new(0, 1)
	barLabel.Position = UDim2.new(0, 10, 1, -6)
	barLabel.Size = UDim2.fromOffset(120, 14)
	barLabel.ZIndex = 8

	-- Cantos
	for _, corner in { { 0, 0 }, { 1, 0 }, { 0, 1 }, { 1, 1 } } do
		local cx, cy = corner[1], corner[2]
		for _, axis in { "h", "v" } do
			local t = newFrame(self.overlay, "corner", Style.Accent)
			t.AnchorPoint = Vector2.new(cx, cy)
			t.Position = UDim2.fromScale(cx, cy)
			t.Size = if axis == "h" then UDim2.fromOffset(16, 2) else UDim2.fromOffset(2, 16)
			t.BackgroundTransparency = 0.25
			t.ZIndex = 8
		end
	end
end

function IslandMapUI:_drawCursor()
	local layer = self.cursorLayer

	local h = newFrame(layer, "ch", Style.CursorOk)
	h.AnchorPoint = Vector2.new(0.5, 0.5)
	h.Size = UDim2.new(0, 26, 0, 1)
	h.BackgroundTransparency = 0.15
	h.ZIndex = 9
	local v = newFrame(layer, "cv", Style.CursorOk)
	v.AnchorPoint = Vector2.new(0.5, 0.5)
	v.Size = UDim2.new(0, 1, 0, 26)
	v.BackgroundTransparency = 0.15
	v.ZIndex = 9
	local ring = newFrame(layer, "cr")
	ring.AnchorPoint = Vector2.new(0.5, 0.5)
	ring.Size = UDim2.fromOffset(14, 14)
	ring.BackgroundTransparency = 1
	ring.ZIndex = 9
	local ringCorner = Instance.new("UICorner")
	ringCorner.CornerRadius = UDim.new(1, 0)
	ringCorner.Parent = ring
	local ringStroke = Instance.new("UIStroke")
	ringStroke.Color = Style.CursorOk
	ringStroke.Thickness = 1.5
	ringStroke.Transparency = 0.1
	ringStroke.Parent = ring

	local readout = newText(layer, "readout", "", 12, Style.Text)
	readout.AnchorPoint = Vector2.new(0, 1)
	readout.Position = UDim2.fromOffset(14, -8)
	readout.Size = UDim2.fromOffset(220, 16)
	readout.ZIndex = 9
	local readoutStroke = Instance.new("UIStroke")
	readoutStroke.Color = Color3.new(0, 0, 0)
	readoutStroke.Thickness = 2
	readoutStroke.Transparency = 0.2
	readoutStroke.Parent = readout

	self.cursor = { h = h, v = v, ring = ring, stroke = ringStroke, readout = readout }
	self:_setCursorVisible(false)
end

function IslandMapUI:_setCursorVisible(visible: boolean)
	local c = self.cursor
	if not c then
		return
	end
	c.h.Visible = visible
	c.v.Visible = visible
	c.ring.Visible = visible
	c.readout.Visible = visible
end

-- Um "ponto de posição" pulsante (bolinha + halo animável). Usado tanto pro
-- Monstro (modo teleport) quanto pra "você" (modo view) -- mesmo desenho,
-- cor diferente.
function IslandMapUI:_drawPositionDot(name: string, color: Color3): (Frame, Frame, UIStroke)
	local dot = newFrame(self.markers, name, color)
	dot.AnchorPoint = Vector2.new(0.5, 0.5)
	dot.Size = UDim2.fromOffset(9, 9)
	dot.ZIndex = 8
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(1, 0)
	c.Parent = dot
	local s = Instance.new("UIStroke")
	s.Color = Color3.new(0, 0, 0)
	s.Thickness = 1.5
	s.Transparency = 0.3
	s.Parent = dot

	local halo = newFrame(self.markers, name .. "Halo")
	halo.AnchorPoint = Vector2.new(0.5, 0.5)
	halo.Size = UDim2.fromOffset(9, 9)
	halo.BackgroundTransparency = 1
	halo.ZIndex = 8
	local hc = Instance.new("UICorner")
	hc.CornerRadius = UDim.new(1, 0)
	hc.Parent = halo
	local hs = Instance.new("UIStroke")
	hs.Color = color
	hs.Thickness = 1.5
	hs.Transparency = 0.4
	hs.Parent = halo

	dot.Visible = false
	halo.Visible = false
	return dot, halo, hs
end

function IslandMapUI:_drawMarkers()
	self.monsterMarker, self.monsterHalo, self.monsterHaloStroke = self:_drawPositionDot("monster", Style.Monster)
	self.selfMarker, self.selfHalo, self.selfHaloStroke = self:_drawPositionDot("self", Style.Self)
end

--------------------------------------------------------------------------------
-- Itens descobertos (client/DiscoveredItemsStore.lua alimenta isto)
--------------------------------------------------------------------------------

function IslandMapUI:_itemMarker(entry: DiscoveredEntry): Frame
	local half = (self.payload :: Payload).mapHalf
	local u, v = IslandMapData.WorldToMap(entry.x, entry.z, half)

	local holder = Instance.new("Frame")
	holder.Name = "item"
	holder.BackgroundTransparency = 1
	holder.AnchorPoint = Vector2.new(0.5, 0.5)
	holder.Position = UDim2.fromScale(u, v)
	holder.Size = UDim2.fromOffset(15, 15)
	holder.ZIndex = 7
	holder.Parent = self.itemsLayer

	local image = MapMarkers.ImageFor(entry.itemId)
	if image ~= "" then
		local icon = Instance.new("ImageLabel")
		icon.BackgroundTransparency = 1
		icon.Image = image
		icon.Size = UDim2.fromScale(1, 1)
		icon.ZIndex = 7
		icon.Parent = holder
		local iconStroke = Instance.new("UIStroke")
		iconStroke.Color = Color3.new(0, 0, 0)
		iconStroke.Thickness = 1
		iconStroke.Transparency = 0.4
		iconStroke.Parent = icon
	else
		-- Sem PNG próprio ainda (ItemIcons.Map vazio): glifo desenhado, cor +
		-- letra/símbolo por categoria (Modules/MapMarkers.lua). Assim que um
		-- rbxassetid real for colado lá, o ícone passa a usar a imagem sozinho.
		local style = MapMarkers.Style(entry.category)
		local badge = Instance.new("Frame")
		badge.Name = "badge"
		badge.BackgroundColor3 = style.Color
		badge.Size = UDim2.fromScale(1, 1)
		badge.ZIndex = 7
		badge.Parent = holder
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0.3, 0)
		corner.Parent = badge
		local stroke = Instance.new("UIStroke")
		stroke.Color = Color3.new(0, 0, 0)
		stroke.Thickness = 1
		stroke.Transparency = 0.25
		stroke.Parent = badge

		local glyph = Instance.new("TextLabel")
		glyph.Name = "glyph"
		glyph.BackgroundTransparency = 1
		glyph.Text = style.Glyph
		glyph.TextColor3 = Color3.new(1, 1, 1)
		glyph.Font = Enum.Font.GothamBold
		glyph.TextSize = 10
		glyph.Size = UDim2.fromScale(1, 1)
		glyph.ZIndex = 8
		glyph.Parent = badge
		local glyphStroke = Instance.new("UIStroke")
		glyphStroke.Color = Color3.new(0, 0, 0)
		glyphStroke.Thickness = 1
		glyphStroke.Transparency = 0.55
		glyphStroke.Parent = glyph
	end

	if entry.label and entry.label ~= "" then
		local nameLabel = Instance.new("TextLabel")
		nameLabel.Name = "name"
		nameLabel.BackgroundTransparency = 1
		nameLabel.Text = entry.label
		nameLabel.TextSize = 10
		nameLabel.Font = Enum.Font.GothamMedium
		nameLabel.TextColor3 = Style.TextDim
		nameLabel.TextXAlignment = Enum.TextXAlignment.Center
		nameLabel.AnchorPoint = Vector2.new(0.5, 0)
		nameLabel.Position = UDim2.new(0.5, 0, 1, 1)
		nameLabel.Size = UDim2.fromOffset(90, 12)
		nameLabel.Visible = false -- só aparece com a lupa (mapa grande o suficiente); evita poluir
		nameLabel.ZIndex = 7
		nameLabel.Parent = holder
	end

	return holder
end

--[[
	AddDiscoveredItem(entry)
	entry = { key, x, z, itemId, category, label }. Ignora repique (mesma
	`key` já desenhada). Se o mapa ainda não foi montado, fica pendente e
	entra assim que Prepare() rodar.
]]
function IslandMapUI:AddDiscoveredItem(entry: DiscoveredEntry?)
	if not entry or not entry.key or self.discovered[entry.key] then
		return
	end
	if not self.built or not self.payload then
		local pending = self.pendingItems or {}
		table.insert(pending, entry)
		self.pendingItems = pending
		return
	end
	self.discovered[entry.key] = self:_itemMarker(entry)
end

--[[
	SetDiscoveredItems(list)
	Aplica uma lista inteira (usado ao abrir o mapa com o acumulado do
	DiscoveredItemsStore). Idempotente por `key`.
]]
function IslandMapUI:SetDiscoveredItems(list: { DiscoveredEntry })
	for _, entry in list do
		self:AddDiscoveredItem(entry)
	end
end

--------------------------------------------------------------------------------
-- Montagem (em background: ~1000+ Frames, não pode travar o frame)
--------------------------------------------------------------------------------

function IslandMapUI:Prepare(): boolean
	if self.built or self.building then
		return self.built
	end
	self.building = true

	local payload = self:_readPayload()
	if not payload then
		self.building = false
		warn("[IslandMapUI] ReplicatedStorage." .. IslandMapData.ValueName .. " não chegou -- o mapa não pode ser montado.")
		return false
	end
	self.payload = payload

	local rects = IslandMapData.DecodeRects(payload.rects)
	self.cells = rebuildCells(rects, payload.resolution)

	self:_buildGui()
	self:_drawTerrain(payload, rects)
	self:_drawGrid()
	self:_drawTrails(payload)
	self:_drawPois(payload)
	self:_drawChrome(payload)
	self:_drawMarkers()
	self:_drawCursor()
	if self.mode ~= "view" then
		self:_wireInput()
	end

	self.built = true
	self.building = false

	if self.pendingItems then
		local pending = self.pendingItems
		self.pendingItems = nil
		for _, entry in pending do
			self:AddDiscoveredItem(entry)
		end
	end

	return true
end

--------------------------------------------------------------------------------
-- Input: mover a mira, clicar pra escolher (só modo "teleport")
--------------------------------------------------------------------------------

-- Pixel de tela cheia -> (u, v) dentro da área do mapa (0..1), ou nil fora dela.
-- A ScreenGui usa IgnoreGuiInset, então TODA entrada de mouse precisa somar o
-- inset (GetMouseLocation e InputObject.Position vêm sem ele).
function IslandMapUI:_uvFromPixel(px: number, py: number): (number?, number?)
	local area = self.area :: Frame
	local abs, size = area.AbsolutePosition, area.AbsoluteSize
	if size.X < 1 or size.Y < 1 then
		return nil, nil
	end
	local u = (px - abs.X) / size.X
	local v = (py - abs.Y) / size.Y
	if u < 0 or u > 1 or v < 0 or v > 1 then
		return nil, nil
	end
	return u, v
end

function IslandMapUI:_uvFromInput(input: InputObject): (number?, number?)
	local inset = GuiService:GetGuiInset()
	return self:_uvFromPixel(input.Position.X + inset.X, input.Position.Y + inset.Y)
end

function IslandMapUI:_isWaterAt(u: number, v: number): boolean
	local payload = self.payload
	local cells = self.cells
	if not payload or not cells then
		return false
	end
	local res = payload.resolution
	local i = math.clamp(math.floor(u * res) + 1, 1, res)
	local j = math.clamp(math.floor(v * res) + 1, 1, res)
	local paletteIndex = cells[j][i]
	return IslandMapData.WaterTerrain[IslandMapData.TerrainOf(paletteIndex)] == true
end

function IslandMapUI:_updateCursor(u: number, v: number)
	local c = self.cursor
	local payload = self.payload
	if not c or not payload then
		return
	end
	self:_setCursorVisible(true)
	local pos = UDim2.fromScale(u, v)
	c.h.Position = pos
	c.v.Position = pos
	c.ring.Position = pos

	local water = self:_isWaterAt(u, v)
	local color = if water then Style.CursorBad else Style.CursorOk
	c.h.BackgroundColor3 = color
	c.v.BackgroundColor3 = color
	c.stroke.Color = color

	local x, z = IslandMapData.MapToWorld(u, v, payload.mapHalf)
	-- A leitura fica do lado da mira, mas vira pra dentro perto das bordas.
	c.readout.AnchorPoint = Vector2.new(if u > 0.72 then 1 else 0, 1)
	c.readout.Position = UDim2.new(u, if u > 0.72 then -14 else 14, v, -8)
	c.readout.TextXAlignment = if u > 0.72 then Enum.TextXAlignment.Right else Enum.TextXAlignment.Left
	c.readout.TextColor3 = color
	c.readout.Text = if water
		then string.format("%d, %d  ·  água", math.floor(x), math.floor(z))
		else string.format("%d, %d", math.floor(x), math.floor(z))
end

-- Mira do mouse (mouse absoluto), em (u, v) dentro da área do mapa.
function IslandMapUI:_pointerUV(): (number?, number?)
	local loc = UserInputService:GetMouseLocation()
	local inset = GuiService:GetGuiInset()
	return self:_uvFromPixel(loc.X + inset.X, loc.Y + inset.Y)
end

function IslandMapUI:_wireInput()
	local area = self.area :: Frame

	-- FONTE ÚNICA da mira: poll do mouse absoluto todo frame enquanto aberto.
	-- (Antes havia também um InputChanged/MouseMovement atualizando a mira numa
	-- coordenada com offset diferente -- as duas fontes brigavam e a mira
	-- "pulava de canto a canto". Agora só o poll manda.)
	table.insert(self.conns, RunService.RenderStepped:Connect(function()
		if not self.open then
			return
		end
		local u, v = self:_pointerUV()
		if u and v then
			self:_updateCursor(u, v)
		else
			self:_setCursorVisible(false)
		end
	end))

	table.insert(self.conns, area.InputBegan:Connect(function(input)
		if not self.open then
			return
		end
		if input.UserInputType ~= Enum.UserInputType.MouseButton1 and input.UserInputType ~= Enum.UserInputType.Touch then
			return
		end
		if not self.onPick then
			return
		end
		-- Mouse: usa a MESMA fonte da mira (poll), pra o clique cair exatamente
		-- onde a mira está. Toque: só o InputObject tem a posição.
		local u, v
		if input.UserInputType == Enum.UserInputType.Touch then
			u, v = self:_uvFromInput(input)
		else
			u, v = self:_pointerUV()
		end
		if not u or not v then
			return
		end
		self:_updateCursor(u, v)
		local payload = self.payload :: Payload
		local x, z = IslandMapData.MapToWorld(u, v, payload.mapHalf)
		-- Y é irrelevante: o servidor faz raycast pro chão a partir de (x, z).
		self.onPick(Vector3.new(x, payload.seaLevel or 0, z))
	end))

	table.insert(self.conns, (self.area :: Frame).MouseLeave:Connect(function()
		self:_setCursorVisible(false)
	end))
end

--------------------------------------------------------------------------------
-- Abrir / fechar
--------------------------------------------------------------------------------

function IslandMapUI:SetStatus(text: string)
	if self.status then
		self.status.Text = text
	end
end

function IslandMapUI:UpdateMonster(position: Vector3?)
	local payload = self.payload
	if not payload or not self.monsterMarker then
		return
	end
	if not position then
		self.monsterMarker.Visible = false
		self.monsterHalo.Visible = false
		return
	end
	local u, v = IslandMapData.WorldToMap(position.X, position.Z, payload.mapHalf)
	local pos = UDim2.fromScale(math.clamp(u, 0, 1), math.clamp(v, 0, 1))
	self.monsterMarker.Position = pos
	self.monsterHalo.Position = pos
	self.monsterMarker.Visible = true
	self.monsterHalo.Visible = true
end

function IslandMapUI:UpdateSelf(position: Vector3?)
	local payload = self.payload
	if not payload or not self.selfMarker then
		return
	end
	if not position then
		self.selfMarker.Visible = false
		self.selfHalo.Visible = false
		return
	end
	local u, v = IslandMapData.WorldToMap(position.X, position.Z, payload.mapHalf)
	local pos = UDim2.fromScale(math.clamp(u, 0, 1), math.clamp(v, 0, 1))
	self.selfMarker.Position = pos
	self.selfHalo.Position = pos
	self.selfMarker.Visible = true
	self.selfHalo.Visible = true
end

function IslandMapUI:IsOpen(): boolean
	return self.open == true
end

--[[
	Show(anchorPos, statusText)
	anchorPos é a posição do Monstro no modo "teleport", ou a sua própria
	posição no modo "view" -- o próprio módulo decide qual marcador atualizar
	e pulsar, então quem chama só passa "onde estou agora".
]]
function IslandMapUI:Show(anchorPos: Vector3?, statusText: string?): boolean
	if not self.built and not self:Prepare() then
		return false
	end
	self.open = true
	if self.mode == "view" then
		self:UpdateSelf(anchorPos)
	else
		self:UpdateMonster(anchorPos)
	end
	self:SetStatus(statusText or "")
	self:_setCursorVisible(false)
	self.gui.Enabled = true

	-- pulso do marcador de posição (o do modo ativo só)
	local halo = if self.mode == "view" then self.selfHalo else self.monsterHalo
	local stroke = if self.mode == "view" then self.selfHaloStroke else self.monsterHaloStroke
	if halo and stroke then
		halo.Size = UDim2.fromOffset(9, 9)
		stroke.Transparency = 0.35
		local t = TweenService:Create(
			halo,
			TweenInfo.new(1.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out, -1),
			{ Size = UDim2.fromOffset(30, 30) }
		)
		local t2 = TweenService:Create(
			stroke,
			TweenInfo.new(1.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out, -1),
			{ Transparency = 1 }
		)
		t:Play()
		t2:Play()
		self.haloTweens = { t, t2 }
	end

	-- fade de entrada
	local panel = self.gui:FindFirstChild("Panel") :: Frame
	if panel then
		panel.BackgroundTransparency = 1
		TweenService:Create(panel, TweenInfo.new(0.18), { BackgroundTransparency = 0 }):Play()
	end
	return true
end

function IslandMapUI:Hide()
	self.open = false
	if self.gui then
		self.gui.Enabled = false
	end
	self:_setCursorVisible(false)
	if self.haloTweens then
		for _, t in self.haloTweens do
			t:Cancel()
		end
		self.haloTweens = nil
	end
end

function IslandMapUI:Destroy()
	self:Hide()
	for _, c in self.conns do
		c:Disconnect()
	end
	table.clear(self.conns)
	if self.gui then
		self.gui:Destroy()
		self.gui = nil
	end
	self.built = false
	self.cells = nil
	self.payload = nil
	table.clear(self.discovered)
	self.pendingItems = nil
end

return IslandMapUI
