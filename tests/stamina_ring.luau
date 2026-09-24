-- StaminaRing real é injetado por run_stamina_ring.py. GUI de verdade precisa
-- do Studio -- aqui rasterizamos o que o anel desenha SEM supor recorte:
-- cada cápsula visível (Frame + UICorner 100%, girada) cobre os pontos a até
-- meia altura do segmento central dela. Recorte (ClipsDescendants) NÃO entra
-- na conta: no Studio ele não recorta o UIStroke, e foi confiar nele que
-- deixou a barra acesa pela metade abaixo de 50%.

local ring_src = sources.StaminaRing
assert(not ring_src:find("RunService"), "StaminaRing não devia depender de RunService")
assert(not ring_src:find("task%.spawn") and not ring_src:find("task%.delay"), "StaminaRing não devia rodar timer próprio")
assert(not ring_src:find("CreateEditableImage") and not ring_src:find("WritePixels"),
	"StaminaRing não deve voltar a depender de EditableImage (quebrou em produção)")
assert(not ring_src:find("ImageLabel") and not ring_src:find("rbxassetid"),
	"o anel é UI nativa: nada de imagem que depende de upload manual")
assert(not ring_src:find("FALLBACK_PARTS"), "os quadradinhos segmentados não podem voltar")
assert(not ring_src:find("ClipsDescendants%s*=%s*true") and not ring_src:find("UIGradient"),
	"o preenchimento não pode depender de recorte/gradiente (o Studio não recorta UIStroke)")

local function assertClose(a, b, tolerance, message)
	if math.abs(a - b) > tolerance then
		error(string.format("%s: esperado ~%.4f, veio %.4f", message, b, a), 0)
	end
end

--------------------------------------------------------------------------------
-- Dublês mínimos de Roblox: GUI é só bolsa de propriedades.
--------------------------------------------------------------------------------

local Color3M = {}
Color3M.__index = Color3M
local Color3 = {}
function Color3.new(r, g, b) return setmetatable({ R = r or 0, G = g or 0, B = b or 0 }, Color3M) end
function Color3.fromRGB(r, g, b) return Color3.new((r or 0) / 255, (g or 0) / 255, (b or 0) / 255) end
function Color3M.Lerp(a, b, t) return Color3.new(a.R + (b.R - a.R) * t, a.G + (b.G - a.G) * t, a.B + (b.B - a.B) * t) end
local Vector2 = { new = function(x, y) return { X = x or 0, Y = y or 0 } end }
local UDim = { new = function(s, o) return { Scale = s, Offset = o } end }
local UDim2 = {
	fromOffset = function(x, y) return { X = x, Y = y } end,
	fromScale = function(x, y) return { SX = x, SY = y } end,
}
local NumberSequenceKeypoint = { new = function(t, v) return { Time = t, Value = v } end }
local NumberSequence = { new = function(keypoints) return { Keypoints = keypoints } end }

local created = {}
local InstanceM = {}
local Instance = {
	new = function(className)
		local item = setmetatable({ ClassName = className, Visible = true, _children = {} }, {
			__newindex = function(t, k, v)
				if k == "Parent" then
					rawset(t, "_parent", v)
					if v and rawget(v, "_children") then table.insert(v._children, t) end
					return
				end
				rawset(t, k, v)
			end,
			__index = function(t, k)
				if k == "Parent" then return rawget(t, "_parent") end
				return InstanceM[k]
			end,
		})
		table.insert(created, item)
		return item
	end,
}
local Enum = setmetatable({}, {
	__index = function()
		return setmetatable({}, { __index = function(_, member) return { Name = member } end })
	end,
})

local modules = {}
local env = setmetatable({
	Color3 = Color3, Vector2 = Vector2, UDim = UDim, UDim2 = UDim2, Instance = Instance, Enum = Enum,
	NumberSequence = NumberSequence, NumberSequenceKeypoint = NumberSequenceKeypoint,
	require = function(name) return modules[name] end,
}, { __index = getfenv() })

local fn = assert(loadstring(ring_src, "StaminaRing"))
setfenv(fn, env)
local StaminaRing = fn()

local root = { _children = {} }
local INNER, THICK = 89, 5
local ring = StaminaRing.new(root, { center = Vector2.new(160, 160), innerRadius = INNER, thickness = THICK, zIndex = 6 })

--------------------------------------------------------------------------------
-- 0) Estrutura: trilho (1 UIStroke) + cápsulas opacas. Só cápsula gira.
--------------------------------------------------------------------------------

local strokes = 0
for _, item in created do
	if item.ClassName == "UIStroke" then
		strokes += 1
		assert(item.Thickness == THICK, "espessura do trilho tem que ser a configurada")
	end
	assert(not item.ClipsDescendants, "nada no anel usa recorte")
	if rawget(item, "Rotation") ~= nil then
		assert(item.Name and item.Name:match("^Arco%d+$"), "só as cápsulas do arco giram (" .. tostring(item.Name) .. ")")
	end
end
assert(strokes == 1, "um trilho só")

local holder = ring.holder
local size = holder.Size.X
local c = size / 2
assert(holder.Position.X == 160 and holder.Position.Y == 160, "anel tem que ser concêntrico ao mapa")
assert(ring._trackStroke.Transparency < 1, "o trilho tem que aparecer")
assert(#ring._pieces >= 60, "cápsulas suficientes pra curva ficar lisa")
for _, piece in ring._pieces do
	assert(piece.BackgroundTransparency == 0, "cápsulas opacas: a sobreposição não pode aparecer")
	assert(piece.Size.Y == THICK, "cápsula com a espessura do anel")
	assert(piece.ZIndex > ring._trackStroke.Parent.ZIndex, "o preenchimento fica por cima do trilho")
end

local fill = ring._pieces[1].BackgroundColor3
assert(fill.R > 0.8 and fill.G > 0.8 and fill.B > 0.75, "o preenchimento tem que ser claro (contraste com o mapa)")
local track = ring._trackStroke.Color
assert(track.R < 0.1 and track.G < 0.1, "o trilho tem que ser escuro e discreto")

--------------------------------------------------------------------------------
-- Rasteriza: ponto (ângulo horário a partir das 12h, raio) aceso?
--------------------------------------------------------------------------------

local rc = INNER + THICK / 2
local function lit(angleDeg, radius)
	local a = math.rad(angleDeg)
	local px, py = c + math.sin(a) * radius, c - math.cos(a) * radius
	for _, piece in ring._pieces do
		if piece.Visible then
			local rot = math.rad(piece.Rotation or 0)
			local ux, uy = math.cos(rot), math.sin(rot)
			local half = (piece.Size.X - piece.Size.Y) / 2
			local rx, ry = px - piece.Position.X, py - piece.Position.Y
			local along = math.clamp(rx * ux + ry * uy, -half, half)
			local dx, dy = rx - along * ux, ry - along * uy
			if math.sqrt(dx * dx + dy * dy) <= piece.Size.Y / 2 + 1e-9 then
				return true
			end
		end
	end
	return false
end

-- Aceso na espessura toda (meio e perto das duas bordas).
local function covered(angleDeg)
	return lit(angleDeg, rc) and lit(angleDeg, INNER + 0.4) and lit(angleDeg, INNER + THICK - 0.4)
end
local function anyLit(angleDeg)
	return lit(angleDeg, rc) or lit(angleDeg, INNER + 0.6) or lit(angleDeg, INNER + THICK - 0.6)
end

-- Ponta redonda passa meia espessura do ângulo exato (em graus no raio do meio).
local CAP_DEG = math.deg((THICK / 2) / rc)

local function checkArc(fraction)
	ring:_apply(fraction, true)
	local theta = fraction * 360
	for i = 0, math.floor(theta * 10) do
		local angle = i / 10
		if angle <= theta then
			assert(covered(angle), string.format("a %.1f%% o grau %.1f devia estar aceso (anel contínuo, espessura inteira)", fraction * 100, angle))
		end
	end
	if fraction < 1 then
		-- Nada aceso depois da ponta nem antes do começo (12h).
		for i = 0, 3599 do
			local angle = i / 10
			if angle > theta + CAP_DEG + 0.3 and angle < 360 - CAP_DEG - 0.3 then
				assert(not anyLit(angle), string.format("a %.1f%% o grau %.1f NÃO podia estar aceso", fraction * 100, angle))
			end
		end
	end
end

--------------------------------------------------------------------------------
-- 1) Proporcional, contínuo, começa às 12h -- inclusive ABAIXO de 50%.
--------------------------------------------------------------------------------

for _, case in { 1, 0.95, 0.75, 0.62, 0.51, 0.5, 0.49, 0.37, 0.25, 0.1, 0.02, 0.004 } do
	checkArc(case)
end

-- Ponta anda contínua (sem degrau de cápsula): entre 30,0% e 30,3% o último
-- grau aceso acompanha o valor.
for _, f in { 0.300, 0.301, 0.302, 0.303 } do
	ring:_apply(f, true)
	assert(covered(f * 360 - 0.05) and not anyLit(f * 360 + CAP_DEG + 0.3), "a ponta tem que seguir o valor exato")
end

--------------------------------------------------------------------------------
-- 2) ZERO É ZERO: nenhuma cápsula; o trilho fica.
--------------------------------------------------------------------------------

ring:_apply(0, true)
for _, piece in ring._pieces do
	assert(not piece.Visible, "a 0% nenhuma cápsula pode aparecer")
end
for i = 0, 359 do
	assert(not anyLit(i), "a 0% não pode sobrar NENHUM grau aceso")
end
assert(ring._trackStroke.Transparency < 1, "o trilho continua visível com o fôlego vazio")

ring:_apply(1, true)
for i = 0, 3599 do
	assert(covered(i / 10), "a 100% o círculo fecha sem fresta")
end

--------------------------------------------------------------------------------
-- 3) Fraction: valor e teto REAIS do servidor.
--------------------------------------------------------------------------------

assert(StaminaRing.Fraction(50, 100) == 0.5, "50/100 = metade")
assert(StaminaRing.Fraction(0, 100) == 0, "0 é vazio")
assert(StaminaRing.Fraction(100, 100) == 1, "cheio é 1")
assert(StaminaRing.Fraction(140, 100) == 1, "acima do teto limita em 1")
assert(StaminaRing.Fraction(-4, 100) == 0, "negativo limita em 0")
assert(StaminaRing.Fraction(30, 60) == 0.5, "usa o teto publicado, não 100 fixo")
assert(StaminaRing.Fraction(10, 0) == 0, "teto 0 = sem fôlego possível, vazio")
assert(StaminaRing.Fraction(10, -5) == 0, "teto negativo = vazio")
assert(StaminaRing.Fraction(nil, 100) == nil, "sem valor: não inventa")
assert(StaminaRing.Fraction(50, nil) == nil, "sem teto: não inventa escala")
assert(StaminaRing.Fraction(0 / 0, 100) == nil, "NaN não vira fôlego")

--------------------------------------------------------------------------------
-- 4) Corrida até zerar, parar, recuperar -- alimentado EXATAMENTE como o
--    servidor publica: 20 Hz e uma casa decimal (StaminaSystem.publish).
--------------------------------------------------------------------------------

local function published(value) return math.floor(math.clamp(value, 0, 100) * 10 + 0.5) / 10 end
local MAX = 100
local server = MAX
ring:SetProgress(1)
for _ = 1, 30 do ring:Update(1 / 60) end
assert(ring._displayed == 1, "parado e cheio")

local frame, sinceTick, lastSent = 0, 0, published(server)
local function run(seconds, rate, dir)
	local worst = 0
	for _ = 1, math.floor(seconds * 60) do
		frame += 1
		sinceTick += 1 / 60
		server = math.clamp(server + dir * rate / 60, 0, MAX)
		if sinceTick >= 0.05 then
			sinceTick = 0
			lastSent = published(server)
		end
		ring:SetProgress(StaminaRing.Fraction(lastSent, MAX))
		ring:Update(1 / 60)
		worst = math.max(worst, math.abs(ring._displayed - server / MAX))
		if frame % 20 == 0 then
			-- O que está NA TELA bate com o valor: aceso até θ, apagado depois.
			local theta = ring._lastDrawn * 360
			if theta > 0.5 then assert(covered(theta - 0.3), "aceso até a ponta") end
			if theta < 360 - 2 * CAP_DEG - 1 then
				assert(not anyLit(theta + CAP_DEG + 0.5), string.format("apagado depois da ponta (%.1f°)", theta))
				assert(not anyLit(359 - CAP_DEG), "o resto da volta apagado")
			end
		end
	end
	return worst
end

-- Correr: a barra desce junto (Diego: gasto 21/s, o pior caso).
local drainGap = run(6, 21, -1)
assert(server == 0, "o fôlego do servidor zerou")
assert(drainGap < 0.035, string.format("a barra não pode ficar pra trás da corrida (pior %.3f)", drainGap))
assert(ring._displayed == 0, "fôlego 0 = barra EXATAMENTE 0")
for i = 0, 359 do assert(not anyLit(i), "esgotado: nada aceso (grau " .. i .. ")") end

-- Exausto parado (RegenDelay): continua vazio, nada volta sozinho.
run(1.2, 0, 1)
assert(ring._displayed == 0 and not anyLit(90) and not anyLit(270), "enquanto não recupera, fica vazio")

-- Parou de correr: sobe junto até encher.
local regenGap = run(8, 22, 1)
assert(server == MAX, "o servidor encheu")
assert(regenGap < 0.035, string.format("a barra não pode ficar pra trás na recuperação (pior %.3f)", regenGap))
assert(ring._displayed == 1, "recuperado = círculo fechado (exatamente 1)")

-- Corre um pouco, para: a barra acompanha nos dois sentidos, sem travar.
run(1.5, 16, -1)
local mid = ring._displayed
run(0.5, 0, 1)
assertClose(ring._displayed, server / MAX, 0.002, "parou: a barra encosta no valor real")
run(3, 14, 1)
assert(ring._displayed > mid, "recuperando: a barra sobe")

-- nil (Attribute ainda não chegou) não mexe na barra.
ring:SetProgress(0.4)
for _ = 1, 60 do ring:Update(1 / 60) end
ring:SetProgress(nil)
for _ = 1, 60 do ring:Update(1 / 60) end
assertClose(ring._displayed, 0.4, 1e-9, "sem valor novo a barra mantém o último valor real")

--------------------------------------------------------------------------------
-- 5) Regressões do fluxo (texto: GUI e rede exigem Studio).
--------------------------------------------------------------------------------

local hud = sources.SurvivalMinimapHUD
assert(not hud:find('"Shadow"'), "o círculo preto Shadow não pode voltar: vazava por fora do anel")
assert(not hud:find("buildArc") and not hud:find("updateArc") and not hud:find("staminaSegments"),
	"os arcos/segmentos antigos não podem voltar -- viram uma segunda barra")
assert(hud:find("SetProgress"), "o HUD alimenta o anel pela API pública SetProgress")
assert(not hud:find("/ 100") and not hud:find("/100"), "o valor já chega normalizado: nada de dividir por 100 de novo")
assert(hud:find("RING_INNER_RADIUS = MAP_SIZE / 2"), "o anel começa por fora do disco do mapa (não cobre o mapa)")

local statusHud = sources.StaminaHUD
assert(statusHud:find('GetAttribute%("StaminaMax"%)'), "a HUD usa o teto REAL publicado pelo servidor")
assert(statusHud:find("StaminaRing.Fraction"), "a normalização passa pelo StaminaRing.Fraction (clamp + teto 0)")
assert(not statusHud:find('GetAttribute%("Stamina"%)[^\n]*/%s*100') and not statusHud:find("raw%s*/%s*100"),
	"nada de escala 100 inventada na HUD")
assert(statusHud:find('GetAttribute%("IsSprinting"%)'), "a intenção enviada é o estado real de corrida do pacote")

local server_src = sources.StaminaSystem
assert(server_src:find('"StaminaMax"'), "o servidor publica o teto do fôlego")
assert(not server_src:find('GetAttribute%("IsSprinting"%)'),
	"o servidor não pode ler IsSprinting do root: é Attribute do cliente e nunca replica")

print("StaminaRing: todos os testes passaram")
