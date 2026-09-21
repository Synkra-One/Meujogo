--!strict
--[[
	StaminaRing

	Um ÚNICO arco contínuo de fôlego, vermelho-vinho, que só encurta conforme a
	stamina cai. Sem segmentos, sem pecinhas, sem quadrado girando.

	POR QUE ESTA É A TERCEIRA TÉCNICA (e as duas anteriores morreram)
	  1. EditableImage: desde o engine 648 a classe não herda mais de Instance;
	     `editableImage.Parent = x` dá erro e derrubava o HUD inteiro.
	  2. Recorte de descendentes + retângulo rotacionado: o engine NÃO corta
	     descendente que tenha Rotation. Os retângulos gigantes apareciam
	     inteiros na tela, formando uma estrela vermelha.
	  Aqui não existe objeto rotacionado nem recorte: o corte é feito por
	  UIGradient, que só muda a TRANSPARÊNCIA do que já está desenhado.

	COMO O ARCO É FEITO
	  Duas ImageLabels, cada uma mostrando metade do anel (a textura já vem
	  cortada assim no atlas): a direita cobre 0°..180° e a esquerda
	  180°..360°, horário a partir das 12h. As duas são QUADRADAS e centradas
	  no mesmo ponto, então a linha de corte do gradiente (offset 0.5) passa
	  exatamente pelo centro do anel, em qualquer rotação.

	  Cada uma leva um UIGradient com degrau seco de transparência: opaco de um
	  lado da linha, invisível do outro. Girando o gradiente em θ, a parte
	  opaca vira o setor 0..θ. Só a propriedade Rotation muda por frame.

	  θ = fração * 360. Direita usa clamp(θ, 0, 180) e esquerda
	  clamp(θ, 180, 360): até 50% só a direita acende; daí em diante a direita
	  fica cheia e a esquerda continua o traço.

	FONTE DO VALOR: quem chama :SetProgress() manda o fôlego REAL já
	normalizado (0..1), lido do Attribute "Stamina" do jogador
	(StaminaSystem.lua, servidor, 0..100). Este módulo não controla, gasta nem
	regenera fôlego, não roda timer e não tem valor próprio.
]]

-- Vermelho-vinho escuro pedido para o arco (referência Friday the 13th).
local FILL_COLOR = Color3.fromRGB(125, 23, 32) -- #7D1720
local LERP_RATE = 26 -- aparência converge em ~120ms; não atrasa a leitura do valor real
local SNAP_EPSILON = 0.0005

--[[
	ATLAS -- ÚNICO PONTO A PREENCHER À MÃO, UM UPLOAD SÓ.

	Suba Imagens/Minimapa/StaminaRingAtlas.png (Studio > Asset Manager >
	Images > Add Images, ou arraste num Decal e copie o Id) e cole aqui:
		local ATLAS = "rbxassetid://SEU_ID"

	É uma imagem 1024x1024 com três quadrantes de 512, gerada a partir do
	próprio export do Figma:
		(0,0)     moldura de metal -- SEM a trilha vermelha que vinha pintada
		          dentro do PNG original (ela virava uma barra falsa fixa)
		(512,0)   metade direita do anel (0°..180°)
		(0,512)   metade esquerda do anel (180°..360°)

	Sem o Id o HUD avisa no Output e não desenha nada -- melhor isso do que
	vermelho falso na tela.
]]
local ATLAS = ""

local QUADRANT = Vector2.new(512, 512)
local RECT_FRAME = Vector2.new(0, 0)
local RECT_RIGHT = Vector2.new(512, 0)
local RECT_LEFT = Vector2.new(0, 512)

-- Degrau seco: opaco até a metade do gradiente, invisível depois. As duas
-- pontas (0 e 1) são obrigatórias em NumberSequence.
local CUT = NumberSequence.new({
	NumberSequenceKeypoint.new(0, 0),
	NumberSequenceKeypoint.new(0.4995, 0),
	NumberSequenceKeypoint.new(0.5005, 1),
	NumberSequenceKeypoint.new(1, 1),
})

local StaminaRing = {}
StaminaRing.__index = StaminaRing

export type Config = {
	center: Vector2,
	ringSize: number,
	frameSize: number?,
	atlas: string?,
	fillZIndex: number?,
	frameZIndex: number?,
}

function StaminaRing.new(parent: Instance, config: Config)
	local self = setmetatable({}, StaminaRing)

	local atlas = config.atlas or ATLAS
	local ringSize = config.ringSize
	local center = config.center

	local function newPiece(name: string, rect: Vector2, size: number, zIndex: number): ImageLabel
		local label = Instance.new("ImageLabel")
		label.Name = name
		label.AnchorPoint = Vector2.new(0.5, 0.5)
		label.Position = UDim2.fromOffset(center.X, center.Y)
		label.Size = UDim2.fromOffset(size, size)
		label.BackgroundTransparency = 1
		label.BorderSizePixel = 0
		label.Image = atlas
		label.ImageRectOffset = rect
		label.ImageRectSize = QUADRANT
		label.ScaleType = Enum.ScaleType.Stretch
		label.Visible = atlas ~= ""
		label.ZIndex = zIndex
		label.Parent = parent
		return label
	end

	local fillZIndex = config.fillZIndex or 6

	-- As duas metades do arco. Quadradas e concêntricas: é isso que faz a
	-- linha de corte do gradiente cair no centro exato do anel.
	local function newArc(name: string, rect: Vector2): (ImageLabel, UIGradient)
		local label = newPiece(name, rect, ringSize, fillZIndex)
		label.ImageColor3 = FILL_COLOR
		local gradient = Instance.new("UIGradient")
		gradient.Transparency = CUT
		gradient.Parent = label
		return label, gradient
	end

	self._rightArc, self._rightCut = newArc("StaminaArcRight", RECT_RIGHT)
	self._leftArc, self._leftCut = newArc("StaminaArcLeft", RECT_LEFT)

	-- Moldura: PURAMENTE DECORATIVA, por cima do arco.
	self.frameImage = newPiece("StaminaRingFrame", RECT_FRAME,
		config.frameSize or ringSize, config.frameZIndex or 10)

	if atlas == "" then
		warn("[StaminaRing] Sem ImageId: suba Imagens/Minimapa/StaminaRingAtlas.png"
			.. " e cole o rbxassetid em src/client/StaminaRing.lua (constante ATLAS).")
	end

	self._target = 1
	self._displayed = 1
	self._lastDrawn = -1
	self:_apply(1, true)
	return self
end

function StaminaRing:_apply(fraction: number, force: boolean?)
	if not force and math.abs(fraction - self._lastDrawn) < 0.0004 then
		return
	end
	self._lastDrawn = fraction

	-- Zero é zero: nada de arco residual na tela.
	local visible = fraction > 0 and self._rightArc.Image ~= ""
	self._rightArc.Visible = visible
	self._leftArc.Visible = visible
	if not visible then
		return
	end

	local degrees = fraction * 360
	self._rightCut.Rotation = math.clamp(degrees, 0, 180)
	self._leftCut.Rotation = math.clamp(degrees, 180, 360)
end

--[[
	SetProgress(fraction)

	fraction: fôlego REAL já normalizado 0..1 (ex.: staminaAtual / staminaMax).
	Só guarda e desenha -- não gasta, não regenera, não inventa valor. Fora da
	faixa é limitado; nil/NaN viram 0 (nunca "cheio" por engano).
]]
function StaminaRing:SetProgress(fraction: number?)
	local value = if type(fraction) == "number" and fraction == fraction then fraction else 0
	self._target = math.clamp(value, 0, 1)
end

--[[
	Update(dt) -- só aparência: aproxima o desenho do valor dado em
	SetProgress. Converge em ~120ms e encosta EXATO no alvo (0 apaga o arco,
	1 fecha o círculo). Sem timer interno: quem chama é o RenderStepped do HUD.
]]
function StaminaRing:Update(dt: number)
	local target = self._target
	local alpha = 1 - math.exp(-LERP_RATE * math.max(dt or 0, 0))
	self._displayed += (target - self._displayed) * alpha
	if math.abs(target - self._displayed) < SNAP_EPSILON then
		self._displayed = target
	end
	self:_apply(self._displayed, false)
end

return StaminaRing
