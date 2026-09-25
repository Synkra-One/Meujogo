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
for name, source in sources do assert(loadstring(source, name), "sintaxe: " .. name) end
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
for _, field in { "Music", "Hover", "Click", "Back", "Start", "Enter" } do
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
-- Botões: ids únicos, textos preenchidos, exatamente um "Entrar"
--------------------------------------------------------------------------------
local seen, playCount, quitCount = {}, 0, 0
for _, entry in Config.MainButtons do
	assert(type(entry.id) == "string" and entry.id ~= "", "todo botão tem id")
	assert(type(entry.label) == "string" and entry.label ~= "", "todo botão tem texto")
	assert(not seen[entry.id], "id duplicado: " .. entry.id)
	seen[entry.id] = true
	if entry.id == "Play" then
		playCount += 1
		assert(entry.label == "ENTRAR")
	end
	if entry.quit then quitCount += 1 end
	-- Todo submenu "em breve" precisa de uma explicação, senão o painel fica
	-- com uma palavra solta no meio da tela.
	if entry.soon then assert(type(entry.blurb) == "string" and entry.blurb ~= "", entry.id .. " sem blurb") end
end
near(playCount, 1, "exatamente um botão Entrar")
assert(quitCount == 0 and not seen.Quit and not seen.QuickPlay, "Sair e Acesso rápido removidos")
assert(not seen.Credits and Config.Credits.label == "CRÉDITOS", "créditos fora da coluna principal")
for _, required in { "Play", "Characters", "Shop", "Inventory", "Settings" } do
	assert(seen[required], "faltou o botão " .. required)
end

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
assert(Config.Scene.CharacterId == "RafaelMonteiro")
for _, path in Config.Scene.MonsterSources do
	assert(string.find(path, "RafaelMonteiro", 1, true), "o menu só procura o Rafael")
end
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

-- Nenhum botão pode cruzar o rodapé nas resoluções suportadas.
for _, size in {
	{ X = 1280, Y = 720 }, { X = 1920, Y = 1080 }, { X = 2560, Y = 1080 },
	{ X = 390, Y = 844 }, { X = 320, Y = 568 }, { X = 844, Y = 390 }, { X = 568, Y = 320 },
} do
	for _, touch in { false, true } do
		touchEnabled, keyboardEnabled = touch, not touch
		local layout = Theme.Layout(size)
		local bottom = layout.columnTop + layout.primaryHeight + 4 * (layout.buttonHeight + layout.gap)
		assert(bottom + 16 <= layout.height - layout.footerBottom - 44,
			"coluna cruza o rodapé: " .. size.X .. "x" .. size.Y .. " touch=" .. tostring(touch))
		assert(layout.columnWidth + layout.margin * 2 <= layout.width, "coluna sai da tela")
		near(layout.width * layout.factor, size.X, "canvas ocupa largura real")
		near(layout.height * layout.factor, size.Y, "canvas ocupa altura real")
	end
end
print("[Menu] todos os testes passaram")

-- Exercita as telas reais com instâncias/sinais determinísticos. Não renderiza.
local function signal()
	local listeners = {}
	local event = {}
	function event:Connect(callback)
		local connection = { Connected = true }
		function connection:Disconnect() self.Connected = false end
		table.insert(listeners, { callback, connection })
		return connection
	end
	function event:Fire(...)
		for _, pair in table.clone(listeners) do
			if pair[2].Connected then pair[1](...) end
		end
	end
	return event
end
local pending = {}
local function flush()
	while #pending > 0 do
		local callbacks = pending
		pending = {}
		for _, callback in callbacks do callback() end
	end
end
environment.task = { delay = function(_, callback) table.insert(pending, callback) end }
environment.ColorSequence = { new = function(...) return { ... } end }
environment.Vector2.zero = { X = 0, Y = 0 }
environment.UDim2 = {
	new = function(xs, xo, ys, yo) return { X = { Scale = xs, Offset = xo }, Y = { Scale = ys, Offset = yo } } end,
	fromScale = function(x, y) return { X = { Scale = x, Offset = 0 }, Y = { Scale = y, Offset = 0 } } end,
	fromOffset = function(x, y) return { X = { Scale = 0, Offset = x }, Y = { Scale = 0, Offset = y } } end,
}
local function node(class)
	local properties = { ClassName = class, Name = class, Visible = true, children = {}, changes = {} }
	local item = setmetatable({}, {
		__index = properties,
		__newindex = function(self, key, value)
			if key == "Parent" then
				if properties.Parent then
					local old = properties.Parent.children
					local index = table.find(old, self)
					if index then table.remove(old, index) end
				end
				if value then table.insert(value.children, self) end
			end
			properties[key] = value
		end,
	})
	for _, name in { "Activated", "MouseEnter", "MouseLeave", "SelectionGained", "SelectionLost" } do
		item[name] = signal()
	end
	function item:IsA(name)
		return name == class or (name == "GuiObject" and table.find({"Frame", "TextLabel", "TextButton", "ImageLabel"}, class) ~= nil)
	end
	function item:GetChildren() return table.clone(self.children) end
	function item:GetDescendants()
		local result = {}
		for _, child in self.children do
			table.insert(result, child)
			for _, descendant in child:GetDescendants() do table.insert(result, descendant) end
		end
		return result
	end
	function item:FindFirstChild(name, recursive)
		for _, child in (if recursive then self:GetDescendants() else self.children) do
			if child.Name == name then return child end
		end
		return nil
	end
	function item:FindFirstChildOfClass(name)
		for _, child in self.children do if child.ClassName == name then return child end end
		return nil
	end
	function item:GetPropertyChangedSignal(name)
		self.changes[name] = self.changes[name] or signal()
		return self.changes[name]
	end
	function item:Destroy()
		for _, child in self:GetChildren() do child:Destroy() end
		self.Parent = nil
		self.Destroyed = true
	end
	function item:Play() self.PlayCount = (self.PlayCount or 0) + 1 end
	return item
end
environment.Instance = { new = node }
services.SoundService = node("SoundService")
services.Workspace = node("Workspace")
services.Workspace.CurrentCamera = node("Camera")
services.Workspace.CurrentCamera.ViewportSize = { X = 1280, Y = 720 }
services.UserInputService.InputBegan = signal()
services.TweenService.Create = function(_, instance, _, goal)
	local completed = signal()
	return {
		Completed = completed,
		Play = function()
			for property, value in goal do instance[property] = value end
			table.insert(pending, function() completed:Fire() end)
		end,
	}
end
local Sounds = loadModule("MenuSounds")
local Screens = loadModule("MenuScreens")
local sound = Sounds.new()
local plays = 0
local screen = Screens.new(node("PlayerGui"), sound, { OnPlay = function() plays += 1 end })
Screens.ShowMenu(screen)
flush()
assert(screen.buttons.Play.Instance:FindFirstChild("Label").Text == "ENTRAR")
assert(screen.buttons.QuickPlay == nil and screen.buttons.Quit == nil)
assert(screen.buttons.Credits.Instance.Parent == screen.footer)
assert(screen.buttons.Credits.Instance.AnchorPoint.X == 1 and screen.footer.AnchorPoint.Y == 1)
local credits = screen.buttons.Credits.Instance
services.GuiService.SelectedObject = credits
credits.Activated:Fire()
-- Durante a abertura e depois dela, ENTRAR não pode atravessar o modal.
screen.buttons.Play.Instance.Activated:Fire()
flush()
screen.buttons.Play.Instance.Activated:Fire()
assert(plays == 0 and screen.openPanel == "Credits" and screen.modalShade.Visible)
assert(services.GuiService.SelectedObject == screen.buttons.BackCredits.Instance)
screen.buttons.BackCredits.Instance.Activated:Fire()
flush()
assert(screen.openPanel == nil and not screen.modalShade.Visible)
assert(services.GuiService.SelectedObject == credits, "fechar restaura foco no botão de origem")
screen.buttons.Play.Instance.Activated:Fire()
flush()
assert(plays == 1 and sound.effects.Enter.PlayCount == 1)
-- Trocar CurrentCamera deve religar o listener de resolução.
local oldCamera = services.Workspace.CurrentCamera
local newCamera = node("Camera")
newCamera.ViewportSize = { X = 390, Y = 844 }
services.Workspace.CurrentCamera = newCamera
services.Workspace:GetPropertyChangedSignal("CurrentCamera"):Fire()
local expected = Theme.Layout(newCamera.ViewportSize)
near(screen.column.Size.X.Offset, expected.columnWidth)
newCamera.ViewportSize = { X = 844, Y = 390 }
newCamera:GetPropertyChangedSignal("ViewportSize"):Fire()
expected = Theme.Layout(newCamera.ViewportSize)
near(screen.column.Size.X.Offset, expected.columnWidth)
Screens.Destroy(screen)
Sounds.Destroy(sound)
flush()
assert(screen.gui.Destroyed and sound.folder.Destroyed)
print("[Menu] construção, navegação, créditos, áudio e troca de câmera passaram")
