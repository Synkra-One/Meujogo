-- StaminaRing real é injetado por run_stamina_ring.py. GUI de verdade precisa
-- do Studio -- aqui reproduzimos a regra do UIGradient (opaco de um lado da
-- linha de corte) em cima das rotações que o módulo aplica, e medimos o arco
-- resultante grau a grau.

assert(not sources.StaminaRing:find("RunService"), "StaminaRing não devia depender de RunService")
assert(not sources.StaminaRing:find("task%.spawn") and not sources.StaminaRing:find("task%.delay"),
	"StaminaRing não devia rodar timer próprio")
-- Técnica 1 que morreu: EditableImage não herda mais de Instance (engine 648).
assert(not sources.StaminaRing:find("CreateEditableImage") and not sources.StaminaRing:find("WritePixels"),
	"StaminaRing não deve voltar a depender de EditableImage (quebrou em produção)")
-- Técnica 2 que morreu: o engine NÃO corta descendente rotacionado, então
-- recorte + Rotation virava uma estrela de retângulos gigantes na tela.
assert(not sources.StaminaRing:find("ClipsDescendants"),
	"nada de ClipsDescendants: o engine não corta objeto rotacionado e o preenchimento vazou pela tela")
assert(not sources.StaminaRing:find("%.Rotation = math") or sources.StaminaRing:find("Cut%.Rotation"),
	"quem gira é o gradiente, nunca o objeto")
-- O arco é UMA imagem por metade. Nada de voltar a fatiar em pedacinhos.
assert(not sources.StaminaRing:find("SEGMENT") and not sources.StaminaRing:find("Segment"),
	"o preenchimento não pode voltar a ser feito de segmentos")

local function assertClose(a, b, tolerance, message)
	if math.abs(a - b) > tolerance then
		error(string.format("%s: esperado ~%.4f, veio %.4f", message, b, a), 0)
	end
end

--------------------------------------------------------------------------------
-- Dublês mínimos de Roblox: GUI é só bolsa de propriedades.
--------------------------------------------------------------------------------

local Color3 = {
	new = function(r, g, b) return { R = r or 0, G = g or 0, B = b or 0 } end,
	fromRGB = function(r, g, b) return { R = (r or 0) / 255, G = (g or 0) / 255, B = (b or 0) / 255 } end,
}
local Vector2 = { new = function(x, y) return { X = x or 0, Y = y or 0 } end }
local UDim2 = {
	new = function(xs, xo, ys, yo) return { XS = xs, XO = xo, YS = ys, YO = yo } end,
	fromOffset = function(x, y) return { X = x, Y = y } end,
	fromScale = function(x, y) return { X = x, Y = y } end,
}
local NumberSequenceKeypoint = { new = function(t, v) return { Time = t, Value = v } end }
local NumberSequence = { new = function(keypoints) return { Keypoints = keypoints } end }
local created = {}
local Instance = {
	new = function(className)
		local item = { ClassName = className }
		table.insert(created, item)
		return item
	end,
}
local Enum = setmetatable({}, {
	__index = function()
		return setmetatable({}, { __index = function(_, member) return { Name = member } end })
	end,
})

local warnings = {}
local modules = {}
local env
env = setmetatable({
	Color3 = Color3, Vector2 = Vector2, UDim2 = UDim2, Instance = Instance, Enum = Enum,
	NumberSequence = NumberSequence, NumberSequenceKeypoint = NumberSequenceKeypoint,
	warn = function(...) table.insert(warnings, table.concat({ ... }, " ")) end,
	require = function(name) return modules[name] end,
}, { __index = getfenv() })

local function loadModule(name)
	local fn = assert(loadstring(assert(sources[name], name), name))
	setfenv(fn, env)
	modules[name] = fn()
	return modules[name]
end

local StaminaRing = loadModule("StaminaRing")

local MAP_SIZE = 168
local RING_SIZE = MAP_SIZE / 0.75

local fakeParent = {}
local ring = StaminaRing.new(fakeParent, {
	center = Vector2.new(160, 160),
	ringSize = RING_SIZE,
	frameSize = RING_SIZE,
	atlas = "rbxassetid://000000",
	fillZIndex = 6,
	frameZIndex = 10,
})

--------------------------------------------------------------------------------
-- 0) Estrutura: duas imagens (uma por metade) + moldura. Nada de N peças.
--------------------------------------------------------------------------------

local images, gradients = 0, 0
for _, item in created do
	if item.ClassName == "ImageLabel" then
		images += 1
	elseif item.ClassName == "UIGradient" then
		gradients += 1
	end
end
assert(images == 3, string.format("esperado 2 metades do arco + 1 moldura, achei %d ImageLabels", images))
assert(gradients == 2, "cada metade do arco precisa do seu gradiente de corte")

-- Arco e moldura no mesmo tamanho e no mesmo centro: é o que faz encaixar.
assert(ring._rightArc.Size.X == RING_SIZE and ring.frameImage.Size.X == RING_SIZE,
	"arco e moldura têm que sair do mesmo tamanho, senão viram dois anéis concêntricos")
assert(ring._rightArc.Position.X == ring.frameImage.Position.X
	and ring._rightArc.Position.Y == ring.frameImage.Position.Y, "arco e moldura têm que ser concêntricos")
assert(ring.frameImage.ZIndex > ring._rightArc.ZIndex, "a moldura tem que ficar por cima do arco")

-- Cada metade lê o seu quadrante do atlas.
assert(ring._rightArc.ImageRectOffset.X == 512 and ring._rightArc.ImageRectOffset.Y == 0,
	"metade direita tem que ler o quadrante (512,0)")
assert(ring._leftArc.ImageRectOffset.X == 0 and ring._leftArc.ImageRectOffset.Y == 512,
	"metade esquerda tem que ler o quadrante (0,512)")
assert(ring.frameImage.ImageRectOffset.X == 0 and ring.frameImage.ImageRectOffset.Y == 0,
	"moldura tem que ler o quadrante (0,0)")
assert(ring._rightArc.ImageColor3.R > ring._rightArc.ImageColor3.G, "o arco tem que ser vermelho-vinho")

--------------------------------------------------------------------------------
-- Mede o arco: regra do UIGradient -- opaco onde (p - centro) . u < 0, com
-- u = (cos rot, sin rot). Cada metade só existe na sua faixa de ângulo.
--------------------------------------------------------------------------------

local function coveredAt(angleDeg)
	local a = math.rad(angleDeg)
	local px, py = math.sin(a), -math.cos(a) -- horário a partir das 12h
	for _, side in {
		{ arc = ring._rightArc, cut = ring._rightCut, from = 0, to = 180 },
		{ arc = ring._leftArc, cut = ring._leftCut, from = 180, to = 360 },
	} do
		local inTexture = angleDeg >= side.from and angleDeg <= side.to
		if inTexture and side.arc.Visible then
			local r = math.rad(side.cut.Rotation)
			if px * math.cos(r) + py * math.sin(r) < 0 then
				return true
			end
		end
	end
	return false
end

local function arcSpan()
	local hits = 0
	for i = 0, 3599 do
		if coveredAt(i / 10) then
			hits += 1
		end
	end
	return hits / 10
end

--------------------------------------------------------------------------------
-- 1) Comprimento proporcional: o arco só encurta.
--------------------------------------------------------------------------------

for _, case in { 1, 0.9, 0.75, 0.5, 0.25, 0.1 } do
	ring:_apply(case, true)
	assertClose(arcSpan(), case * 360, 1.2,
		string.format("a %.0f%% o arco devia ter %.0f graus", case * 100, case * 360))
end

-- Contínuo: começa nas 12h e não tem falha no meio do trecho aceso.
ring:_apply(0.6, true)
assert(coveredAt(0.5), "o arco tem que começar nas 12h")
local gaps, previous = 0, true
for i = 1, 2159 do -- 0..216 graus = 60%
	local now = coveredAt(i / 10)
	if previous and not now then
		gaps += 1
	end
	previous = now
end
assert(gaps == 0, "não pode haver divisão/buraco dentro do arco: ele é contínuo")

--------------------------------------------------------------------------------
-- 2) ZERO É ZERO: acabou o fôlego, não sobra vermelho nenhum.
--------------------------------------------------------------------------------

ring:_apply(0, true)
assert(ring._rightArc.Visible == false and ring._leftArc.Visible == false,
	"a 0% as duas metades do arco têm que sumir da tela")
assert(arcSpan() == 0, "a 0% não pode sobrar NENHUM grau de arco aceso")

ring:_apply(1, true)
assert(ring._rightArc.Visible == true, "a 100% o arco tem que voltar a aparecer")
assertClose(arcSpan(), 360, 1.2, "a 100% o círculo tem que fechar")

--------------------------------------------------------------------------------
-- 3) Segue o valor real, sem timer próprio e sem inventar valor.
--------------------------------------------------------------------------------

ring:SetProgress(1)
for _ = 1, 5 do
	ring:Update(1 / 60)
end
assertClose(ring._displayed, 1, 1e-6, "valor parado em 1 não devia se mover sozinho")

ring:SetProgress(0)
local afterOneFrame
for i = 1, 10 do
	ring:Update(1 / 60)
	if i == 1 then
		afterOneFrame = ring._displayed
	end
end
assert(afterOneFrame < 1 and afterOneFrame > 0, "primeiro frame devia suavizar, não saltar")
for _ = 1, 60 do
	ring:Update(1 / 60)
end
assert(ring._displayed == 0, "fôlego real zerado devia deixar o arco EXATAMENTE em 0")
assert(ring._rightArc.Visible == false, "e o arco sumido de vez")
for _ = 1, 10 do
	ring:Update(1 / 60)
end
assert(ring._displayed == 0, "o arco não pode voltar sozinho sem o valor real subir")

--------------------------------------------------------------------------------
-- 4) CORRIDA REAL ATÉ ZERAR: servidor publicando 0..100 caindo a 21/s
--    (StaminaDrain máximo). O desenho não pode ficar pra trás nem sobrar arco.
--------------------------------------------------------------------------------

ring:SetProgress(1)
for _ = 1, 30 do
	ring:Update(1 / 60)
end

local serverValue = 100 -- MAX do StaminaSystem
local worstGap = 0
while serverValue > 0 do
	serverValue = math.max(0, serverValue - 21 * (1 / 60))
	ring:SetProgress(serverValue / 100)
	ring:Update(1 / 60)
	worstGap = math.max(worstGap, math.abs(ring._displayed - serverValue / 100))
end
assert(worstGap < 0.03,
	string.format("o arco não pode ficar pra trás do fôlego real na corrida (pior gap %.3f)", worstGap))
for _ = 1, 20 do
	ring:Update(1 / 60)
end
assert(ring._displayed == 0 and ring._rightArc.Visible == false and arcSpan() == 0,
	"no fim da corrida não pode sobrar nada de vermelho: fôlego 0 = arco 0")

--------------------------------------------------------------------------------
-- 5) Regeneração e mudanças bruscas.
--------------------------------------------------------------------------------

serverValue = 0
while serverValue < 100 do
	serverValue = math.min(100, serverValue + 22 * (1 / 60))
	ring:SetProgress(serverValue / 100)
	ring:Update(1 / 60)
end
for _ = 1, 20 do
	ring:Update(1 / 60)
end
assert(ring._displayed == 1, "regenerando até o topo o arco tem que fechar o círculo (exatamente 1)")

for _, value in { 0.12, 0.93, 0.05, 1, 0.5, 0 } do
	ring:SetProgress(value)
	for _ = 1, 40 do
		ring:Update(1 / 60)
	end
	assertClose(ring._displayed, value, 1e-9, "mudança brusca tem que ser alcançada exatamente")
end

ring:SetProgress(1.8)
assert(ring._target == 1, "valor acima de 1 tem que ser limitado em 1")
ring:SetProgress(-3)
assert(ring._target == 0, "valor negativo tem que ser limitado em 0")
ring:SetProgress(nil)
assert(ring._target == 0, "valor nil não pode virar fôlego cheio inventado")

--------------------------------------------------------------------------------
-- 6) Sem ImageId: nada é desenhado e o Output explica o que fazer.
--------------------------------------------------------------------------------

local blank = StaminaRing.new({}, { center = Vector2.new(0, 0), ringSize = RING_SIZE })
assert(blank._rightArc.Visible == false and blank.frameImage.Visible == false,
	"sem atlas nada pode ser desenhado (nem vermelho falso, nem caixa preta)")
assert(#warnings > 0 and warnings[1]:find("StaminaRingAtlas"),
	"sem atlas o Output tem que dizer qual arquivo subir")
blank:SetProgress(1)
blank:Update(1 / 60)
assert(blank._rightArc.Visible == false, "sem atlas, nem com fôlego cheio pode aparecer coisa na tela")

--------------------------------------------------------------------------------
-- 7) Regressões do HUD que hospeda o arco (só texto: GUI exige Studio).
--------------------------------------------------------------------------------

local hud = sources.SurvivalMinimapHUD
assert(not hud:find('"Shadow"'), "o círculo preto Shadow não pode voltar: vazava por fora do anel")
assert(not hud:find("buildArc") and not hud:find("updateArc"),
	"os arcos antigos não podem voltar -- viram uma segunda barra de fôlego")
assert(not hud:find("staminaSegments") and not hud:find("StaminaBadge") and not hud:find("staminaValue"),
	"nenhum outro indicador de fôlego pode existir além do arco")
assert(hud:find("SetProgress"), "o HUD tem que alimentar o arco pela API pública SetProgress")
assert(not hud:find("stamina / 100") and not hud:find("stamina/100"),
	"o valor já chega normalizado 0..1: dividir por 100 de novo deixaria o arco quase sempre vazio")
assert(hud:find("frameSize = RING_SIZE"),
	"arco e moldura precisam do mesmo tamanho, senão aparecem dois anéis concêntricos")
assert(hud:find("FRAME_ZINDEX = 10") and hud:find("FILL_ZINDEX = 6"),
	"a moldura tem que ficar por cima do arco, e o arco por cima do mapa")

print("StaminaRing: todos os testes passaram")
