-- Real module sources are injected by run_menu.py; only Roblox services are mocked.
-- Cobre o que dá para cobrir fora do Studio: a configuração da tela inicial e a
-- matemática pura de escala/IDs. Renderização, câmera e som exigem playtest.
local function near(a, b, message)
	assert(math.abs(a - b) < 1e-6, (message or "mismatch") .. ": " .. tostring(a) .. " / " .. tostring(b))
end
local function enumTable(names)
	local t = {}
	for _, name in names do t[name] = { Name = name } end
	return setmetatable(t, { __index = function(_, key) return { Name = key } end })
end
local touchEnabled, keyboardEnabled, tenFoot = false, true, false
local services = {
	TweenService = { Create = function() return { Play = function() end, Completed = { Connect = function() end } } end },
	UserInputService = setmetatable({}, { __index = function(_, key)
		if key == "TouchEnabled" then return touchEnabled end
		if key == "KeyboardEnabled" then return keyboardEnabled end
		return function() end
	end }),
	GuiService = { IsTenFootInterface = function() return tenFoot end },
	RunService = { Heartbeat = { Connect = function() end }, RenderStepped = { Connect = function() end } },
	Players = { LocalPlayer = {} },
	Workspace = { CurrentCamera = nil },
	ReplicatedStorage = {},
	SoundService = {},
}
local environment = setmetatable({
	game = { GetService = function(_, name) return assert(services[name], name) end },
	script = { Parent = setmetatable({}, { __index = function(_, key) return key end }) },
	Color3 = { fromRGB = function(r, g, b) return { R = r, G = g, B = b } end,
		new = function(r, g, b) return { R = r, G = g, B = b } end },
	Vector3 = { new = function(x, y, z) return { X = x, Y = y, Z = z } end },
	Vector2 = { new = function(x, y) return { X = x, Y = y } end },
	UDim = { new = function(a, b) return { Scale = a, Offset = b } end },
	UDim2 = { new = function(...) return { ... } end, fromScale = function(...) return { ... } end,
		fromOffset = function(...) return { ... } end },
	TweenInfo = { new = function(...) return { ... } end },
	NumberSequence = { new = function(...) return { ... } end },
	NumberSequenceKeypoint = { new = function(...) return { ... } end },
	Enum = {
		Font = enumTable({ "GothamBlack", "GothamBold", "GothamMedium", "Gotham" }),
		Material = enumTable({ "Ground", "Slate", "Wood", "Metal", "SmoothPlastic", "CorrodedMetal", "DiamondPlate" }),
		KeyCode = enumTable({ "Escape", "ButtonB" }),
		EasingStyle = enumTable({ "Quint", "Quad", "Sine", "Linear" }),
		EasingDirection = enumTable({ "Out", "InOut" }),
		NormalId = enumTable({ "Front", "Top", "Bottom" }),
		ApplyStrokeMode = enumTable({ "Border" }),
		ScaleType = enumTable({ "Fit", "Crop", "Stretch" }),
		TextXAlignment = enumTable({ "Left", "Center" }),
		FillDirection = enumTable({ "Vertical" }),
		SortOrder = enumTable({ "LayoutOrder" }),
		SurfaceType = enumTable({ "Smooth" }),
		CameraType = enumTable({ "Scriptable", "Custom" }),
		AnimationPriority = enumTable({ "Idle" }),
		HumanoidDisplayDistanceType = enumTable({ "None" }),
		CoreGuiType = enumTable({ "Chat", "PlayerList", "EmotesMenu" }),
		UserInputType = enumTable({ "MouseMovement", "MouseWheel", "Focus", "Gyro", "Accelerometer" }),
		ZIndexBehavior = enumTable({ "Sibling" }),
	},
}, { __index = getfenv() })
local modules = {}
local function loadModule(name)
	if modules[name] then return modules[name] end
	local chunk = assert(loadstring(assert(sources[name], name), name))
	setfenv(chunk, environment)
	modules[name] = chunk()
	return modules[name]
end
environment.require = loadModule
local Config = loadModule("MenuConfig")
local Theme = loadModule("MenuTheme")

--------------------------------------------------------------------------------
-- IDs de asset: vazio = desligado, sem inventar nada
--------------------------------------------------------------------------------
assert(Config.AssetId("") == nil, "vazio desliga")
assert(Config.AssetId(nil) == nil)
assert(Config.AssetId(123) == nil, "só string")
assert(Config.AssetId("0") == nil, "zero não é asset")
assert(Config.AssetId("rbxassetid://0") == nil)
assert(Config.AssetId("cole seu id aqui") == nil, "texto solto é ignorado, não vira Sound quebrado")
assert(Config.AssetId("1234") == "rbxassetid://1234")
assert(Config.AssetId("rbxassetid://1234") == "rbxassetid://1234")
assert(Config.AssetId("rbxasset://sounds/volume_slider.ogg") == "rbxasset://sounds/volume_slider.ogg",
	"sons embutidos da Roblox passam intactos")

-- Nenhum ID de upload foi inventado: os padrões são só rbxasset:// ou vazios.
for _, field in { "Music", "Hover", "Click", "Back", "Start" } do
	local value = Config.Sounds[field]
	assert(value == "" or string.sub(value, 1, 11) == "rbxasset://",
		"som padrão precisa ser embutido ou vazio: " .. field .. " = " .. tostring(value))
end
assert(Config.Brand.LogoImage == "", "logo fica vazia até você colar a sua")
assert(Config.Background.Image == "", "fundo 2D fica vazio até você colar o seu")
assert(Config.Scene.MonsterAnimationId == "", "animação do monstro fica vazia")

--------------------------------------------------------------------------------
-- Carregamento: o pedido era ~3 s, o mais rápido possível
--------------------------------------------------------------------------------
assert(Config.Loading.MaxSeconds <= 3, "carregamento no máximo 3 s")
assert(Config.Loading.MinSeconds >= 0 and Config.Loading.MinSeconds < Config.Loading.MaxSeconds,
	"mínimo abaixo do máximo")
assert(Config.Loading.TipInterval > 0)

--------------------------------------------------------------------------------
-- Botões: ids únicos, textos preenchidos, exatamente um "Jogar"
--------------------------------------------------------------------------------
local seen, playCount, quitCount = {}, 0, 0
for _, entry in Config.MainButtons do
	assert(type(entry.id) == "string" and entry.id ~= "", "todo botão tem id")
	assert(type(entry.label) == "string" and entry.label ~= "", "todo botão tem texto")
	assert(not seen[entry.id], "id duplicado: " .. entry.id)
	seen[entry.id] = true
	if entry.id == "Play" then playCount += 1 end
	if entry.quit then quitCount += 1 end
	-- Todo submenu "em breve" precisa de uma explicação, senão o painel fica
	-- com uma palavra solta no meio da tela.
	if entry.soon then assert(type(entry.blurb) == "string" and entry.blurb ~= "", entry.id .. " sem blurb") end
end
near(playCount, 1, "exatamente um botão Jogar")
assert(quitCount <= 1, "no máximo um botão Sair")
for _, required in { "Play", "Characters", "Shop", "Inventory", "Settings", "Credits" } do
	assert(seen[required], "faltou o botão " .. required)
end

--------------------------------------------------------------------------------
-- Acesso rápido: as opções têm de bater com os papéis reais do jogo
--------------------------------------------------------------------------------
local optionIds = {}
for _, option in Config.QuickPlay.Options do
	assert(type(option.id) == "string" and type(option.label) == "string")
	optionIds[option.id] = true
end
for _, required in { "Survivor", "Monster", "Spy", "Random" } do
	assert(optionIds[required], "acesso rápido sem a opção " .. required)
end
assert(Config.QuickPlay.StepTimeout > 0)

--------------------------------------------------------------------------------
-- Tempos e curvas
--------------------------------------------------------------------------------
for _, field in { "ScreenFade", "PanelSlide", "ButtonHover", "ButtonPress", "StartFade", "PlayFade" } do
	local value = Config.Motion[field]
	assert(type(value) == "number" and value > 0 and value <= 2, "tempo fora de faixa: " .. field)
end
assert(Config.Motion.InputLockPadding >= 0, "a trava anti-clique-duplo não pode ser negativa")

--------------------------------------------------------------------------------
-- Cena: tem de nascer LONGE da ilha e do lobby
--   IslandLayout.AreaHalf = 960 (ilha), LobbyManager.LOBBY_ORIGIN.z = -1500
--------------------------------------------------------------------------------
local origin = Config.Scene.Origin
assert(math.abs(origin.X) > 960 or math.abs(origin.Z) > 960 or origin.Y > 2000,
	"a cena do menu não pode ser montada em cima da ilha")
assert(math.abs(origin.Z - (-1500)) > 500 or origin.Y > 2000, "nem em cima do lobby")
assert(Config.Scene.SetSize.X > 0 and Config.Scene.SetSize.Y > 0 and Config.Scene.SetSize.Z > 0)
assert(#Config.Scene.MonsterSources > 0, "pelo menos um caminho de modelo a tentar")
assert(Config.Scene.CameraFieldOfView > 0 and Config.Scene.CameraFieldOfView < 120)
assert(Config.Scene.BreathSpeed > 0 and Config.Scene.BreathHeight > 0, "respiração configurável")

--------------------------------------------------------------------------------
-- Escala responsiva: PC, celular, tablet e console
--------------------------------------------------------------------------------
local desktop = Theme.Scale({ X = 1280, Y = 720 })
near(desktop, 1, "1280x720 é a referência")
local big = Theme.Scale({ X = 2560, Y = 1440 })
assert(big > desktop and big <= 1.55, "4K cresce, mas com teto")
local small = Theme.Scale({ X = 640, Y = 360 })
assert(small < desktop and small >= 0.62, "janela pequena encolhe, mas com piso")
local portrait = Theme.Scale({ X = 390, Y = 844 })
assert(portrait >= 0.62, "celular em pé nunca fica ilegível")

touchEnabled, keyboardEnabled = true, false
local phone = Theme.Scale({ X = 1280, Y = 720 })
assert(phone > desktop, "toque ganha alvo maior que mouse")
touchEnabled, keyboardEnabled = false, true
local tvSize = { X = 1920, Y = 1080 }
local normalTv = Theme.Scale(tvSize)
tenFoot = true
local console = Theme.Scale(tvSize)
tenFoot = false
assert(console > normalTv, "console cresce por causa da distância da TV: "
	.. tostring(console) .. " / " .. tostring(normalTv))

-- Sempre dentro do teto/piso, em qualquer tela imaginável.
for _, size in { { X = 320, Y = 240 }, { X = 800, Y = 600 }, { X = 3840, Y = 2160 }, { X = 1080, Y = 2400 } } do
	local factor = Theme.Scale(size)
	assert(factor >= 0.62 and factor <= 1.55 * 1.23, "escala fora dos limites: " .. tostring(factor))
end

print("[Menu] todos os testes passaram")
