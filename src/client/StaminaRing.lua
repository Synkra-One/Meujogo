--!strict
--[[
	StaminaRing

	Anel fino e contínuo de fôlego em volta do minimapa: trilho escuro
	discreto + preenchimento claro com pontas arredondadas, começando às 12h e
	correndo no sentido horário. Só DESENHA o valor que recebe -- não gasta,
	não regenera, não roda timer e não tem escala própria.

	COMO É DESENHADO (UI nativa, sem imagem, sem recorte, sem gradiente)
	  Trilho: um Frame redondo (UICorner 100%) com UIStroke -- círculo liso.

	  Preenchimento: ARC_PIECES cápsulas (Frame + UICorner 100%) opacas,
	  deitadas ao longo do círculo, cada uma cobrindo 360/ARC_PIECES graus e
	  sobrepondo a vizinha pelas pontas redondas. Como são opacas e da mesma
	  cor, a sobreposição não aparece: o resultado é uma faixa lisa (a corda
	  de 4° desvia < 0,1 px do círculo). A última cápsula acesa vai só até o
	  ângulo exato do fôlego, então a ponta anda contínua, sem degrau, e já é
	  redonda. As pontas de início (12h) e fim saem de graça.

	  POR QUE NÃO RECORTE: a versão anterior pintava o anel com UIStroke dentro
	  de containers com ClipsDescendants. No Studio o contorno do UIStroke NÃO
	  é recortado pelo container, então abaixo de 50% continuava aparecendo
	  meia volta acesa -- a barra "só funcionava até a metade". Aqui nada
	  depende de recorte: cada cápsula aparece inteira ou não aparece.

	  Fôlego 0: todas as cápsulas somem; só o trilho fica.
]]

local StaminaRing = {}
StaminaRing.__index = StaminaRing

local TRACK_COLOR = Color3.fromRGB(10, 12, 14)
local TRACK_TRANSPARENCY = 0.35
local FILL_COLOR = Color3.fromRGB(238, 234, 220) -- claro: contrasta com o mapa escuro
local LOW_COLOR = Color3.fromRGB(240, 182, 128) -- ainda claro, aquece no fim do fôlego
local LOW_FRACTION = 0.25
local SMOOTH_RATE = 14 -- ~70 ms de constante: suave sem ficar pra trás
local SNAP_EPSILON = 0.002
local ARC_PIECES = 90 -- 4° cada

export type Config = {
	center: Vector2, -- centro do anel no pai (offset)
	innerRadius: number, -- raio da borda de DENTRO do anel
	thickness: number,
	zIndex: number?,
}

--[[
	Fraction(value, max) -> número 0..1 ou nil
	Normaliza o fôlego REAL pelo teto REAL publicado pelo servidor.
	  value/max não numéricos ou NaN -> nil (quem chama mantém o último valor
	  conhecido em vez de inventar um).
	  max <= 0 -> 0 (sem fôlego possível, barra vazia).
]]
function StaminaRing.Fraction(value: unknown, max: unknown): number?
	if type(value) ~= "number" or value ~= value or type(max) ~= "number" or max ~= max then
		return nil
	end
	if max <= 0 then
		return 0
	end
	return math.clamp(value / max, 0, 1)
end

local function roundFrame(parent: Instance, name: string, size: number, x: number, y: number, zIndex: number): Frame
	local item = Instance.new("Frame")
	item.Name = name
	item.AnchorPoint = Vector2.new(0.5, 0.5)
	item.Position = UDim2.fromOffset(x, y)
	item.Size = UDim2.fromOffset(size, size)
	item.BackgroundTransparency = 1
	item.BorderSizePixel = 0
	item.ZIndex = zIndex
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(1, 0)
	corner.Parent = item
	item.Parent = parent
	return item
end

local function ringStroke(target: Frame, thickness: number, color: Color3, transparency: number): UIStroke
	local stroke = Instance.new("UIStroke")
	-- UIStroke cresce pra FORA da borda: o trilho vai de innerRadius até
	-- innerRadius + thickness, sem invadir o disco do mapa.
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Thickness = thickness
	stroke.Color = color
	stroke.Transparency = transparency
	stroke.Parent = target
	return stroke
end

function StaminaRing.new(parent: Instance, config: Config)
	local self = setmetatable({}, StaminaRing)
	local inner = config.innerRadius
	local thickness = config.thickness
	local zIndex = config.zIndex or 6
	local outer = inner + thickness
	local size = math.ceil(outer * 2) + 4 -- folga pra borda antisserrilhada
	local c = size / 2

	local holder = Instance.new("Frame")
	holder.Name = "StaminaRing"
	holder.AnchorPoint = Vector2.new(0.5, 0.5)
	holder.Position = UDim2.fromOffset(config.center.X, config.center.Y)
	holder.Size = UDim2.fromOffset(size, size)
	holder.BackgroundTransparency = 1
	holder.BorderSizePixel = 0
	holder.ZIndex = zIndex
	holder.Parent = parent
	self.holder = holder

	-- Trilho: sempre visível, inclusive com o fôlego em zero.
	local track = roundFrame(holder, "Trilho", inner * 2, c, c, zIndex)
	self._trackStroke = ringStroke(track, thickness, TRACK_COLOR, TRACK_TRANSPARENCY)

	-- Preenchimento: cápsulas no raio do MEIO da espessura.
	local fill = Instance.new("Frame")
	fill.Name = "Preenchimento"
	fill.Size = UDim2.fromOffset(size, size)
	fill.BackgroundTransparency = 1
	fill.BorderSizePixel = 0
	fill.ZIndex = zIndex + 1
	fill.Parent = holder
	self._pieces = {}
	for i = 1, ARC_PIECES do
		local piece = roundFrame(fill, string.format("Arco%02d", i), thickness, c, c, zIndex + 1)
		piece.BackgroundColor3 = FILL_COLOR
		piece.BackgroundTransparency = 0
		piece.Visible = false
		self._pieces[i] = piece
	end

	self._center = c
	self._radius = inner + thickness / 2
	self._thickness = thickness
	self._shown = {} -- cápsula -> ângulo final desenhado (nil = escondida)
	self._color = FILL_COLOR
	self._target = 1
	self._displayed = 1
	self._lastDrawn = -1
	self:_apply(1, true)
	return self
end

-- Cápsula do ângulo `fromDeg` ao `toDeg` (horário a partir das 12h): corda
-- entre os dois pontos no raio do meio, + meia espessura de ponta redonda
-- de cada lado.
function StaminaRing:_place(piece: Frame, fromDeg: number, toDeg: number)
	local c, r = self._center, self._radius
	local a, b = math.rad(fromDeg), math.rad(toDeg)
	local x0, y0 = c + math.sin(a) * r, c - math.cos(a) * r
	local x1, y1 = c + math.sin(b) * r, c - math.cos(b) * r
	local dx, dy = x1 - x0, y1 - y0
	piece.Position = UDim2.fromOffset((x0 + x1) / 2, (y0 + y1) / 2)
	piece.Size = UDim2.fromOffset(math.sqrt(dx * dx + dy * dy) + self._thickness, self._thickness)
	piece.Rotation = math.deg(math.atan2(dy, dx))
end

function StaminaRing:_apply(fraction: number, force: boolean?)
	if not force and math.abs(fraction - self._lastDrawn) < 0.0002 then
		return
	end
	self._lastDrawn = fraction

	local color = if fraction < LOW_FRACTION
		then FILL_COLOR:Lerp(LOW_COLOR, 1 - fraction / LOW_FRACTION)
		else FILL_COLOR
	local recolor = force or color ~= self._color
	self._color = color

	-- Zero é zero: nenhuma cápsula acesa, só o trilho.
	local degrees = math.clamp(fraction, 0, 1) * 360
	local step = 360 / ARC_PIECES
	for i, piece in self._pieces do
		local fromDeg = (i - 1) * step
		local toDeg = if degrees > fromDeg then math.min(i * step, degrees) else nil
		if toDeg ~= self._shown[i] or force then
			self._shown[i] = toDeg
			if toDeg then
				self:_place(piece, fromDeg, toDeg)
			end
			piece.Visible = toDeg ~= nil
		end
		if recolor then
			piece.BackgroundColor3 = color
		end
	end
end

--[[
	SetProgress(fraction)
	fraction: fôlego REAL já normalizado 0..1 (use StaminaRing.Fraction). Fora
	da faixa é limitado; nil/NaN mantêm o último valor (nada inventado).
]]
function StaminaRing:SetProgress(fraction: number?)
	if type(fraction) ~= "number" or fraction ~= fraction then
		return
	end
	self._target = math.clamp(fraction, 0, 1)
end

--[[
	Update(dt) -- só aparência: aproxima o desenho do valor real e encosta
	EXATO nele (0 apaga o preenchimento, 1 fecha o círculo). Quem chama é o
	RenderStepped do HUD; não há timer aqui.
]]
function StaminaRing:Update(dt: number)
	local target = self._target
	local alpha = 1 - math.exp(-SMOOTH_RATE * math.max(dt or 0, 0))
	self._displayed += (target - self._displayed) * alpha
	if math.abs(target - self._displayed) < SNAP_EPSILON then
		self._displayed = target
	end
	self:_apply(self._displayed, false)
end

return StaminaRing
