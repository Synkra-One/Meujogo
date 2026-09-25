--!strict
--[[
	MenuScreens
	As telas do menu e a navegação entre elas. Só cuida de INTERFACE: quem
	decide o que acontece ao clicar é o MenuBoot, que passa os handlers.
	A cena 3D é do MenuScene; o áudio é do MenuSounds; o visual é do MenuTheme.

	TELAS
	  1. Carregamento  -- rápido (MenuConfig.Loading), com dicas girando
	  2. Clique para começar -- logo + texto pulsando
	  3. Menu principal -- coluna de botões à ESQUERDA, cena livre à direita
	  4. Painéis -- submenus "Em breve" e créditos, todos com VOLTAR

	ANTI-CLIQUE-DUPLO: `busy` é levantado no início de toda transição e só cai
	quando ela termina. Nenhum handler roda com ele levantado -- vale para
	mouse, toque, teclado e controle, porque todos passam pelo mesmo Activated.
]]

local UserInputService = game:GetService("UserInputService")
local GuiService = game:GetService("GuiService")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Config = require(script.Parent.MenuConfig)
local Theme = require(script.Parent.MenuTheme)
local Sounds = require(script.Parent.MenuSounds)

local Screens = {}
Screens.__index = Screens

export type Handlers = {
	OnPlay: () -> (),
}

export type Controller = typeof(setmetatable({} :: {
	gui: ScreenGui,
	loadingGui: ScreenGui,
	sounds: Sounds.Controller,
	handlers: Handlers,
	buttons: { [string]: Theme.Button },
	panels: { [string]: Frame },
	connections: { RBXScriptConnection },
	scrim: Frame,
	backdrop: ImageLabel?,
	column: Frame,
	content: Frame,
	footer: Frame,
	modalShade: Frame,
	returnFocus: GuiObject?,
	viewportConnection: RBXScriptConnection?,
	root: Frame,
	scale: UIScale,
	loadingScale: UIScale,
	busy: boolean,
	openPanel: string?,
	destroyed: boolean,
	pulse: RBXScriptConnection?,
}, Screens))

local Z = { Backdrop = 1, Scrim = 2, Vignette = 3, Content = 10, Panel = 40 }

--------------------------------------------------------------------------------
-- Construção
--------------------------------------------------------------------------------

local function newScreenGui(playerGui: Instance, name: string, order: number): ScreenGui
	local gui = Instance.new("ScreenGui")
	gui.Name, gui.DisplayOrder = name, order
	-- ResetOnSpawn false: morrer/renascer NÃO recria nem reabre o menu.
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.Enabled = false
	gui.Parent = playerGui
	return gui
end

-- Um UIScale por ScreenGui, re-medido quando a janela muda de tamanho:
-- é isto que deixa a mesma tela boa em PC, celular, tablet e console.
local function attachScale(self: Controller, parent: GuiObject): UIScale
	local scale = Instance.new("UIScale")
	scale.Scale = Theme.Scale(Workspace.CurrentCamera and Workspace.CurrentCamera.ViewportSize
		or Vector2.new(1280, 720))
	scale.Parent = parent
	parent.Size = UDim2.fromScale(1 / scale.Scale, 1 / scale.Scale)
	return scale
end

function Screens.new(playerGui: Instance, sounds: Sounds.Controller, handlers: Handlers): Controller
	local loadingGui = newScreenGui(playerGui, "MenuLoading", 1001)
	local gui = newScreenGui(playerGui, "MainMenu", 1000)

	local root = Theme.Frame(gui, "Root", Z.Content)
	root.BackgroundColor3 = Config.Palette.Background
	root.BackgroundTransparency = 1
	root.ZIndex = Z.Backdrop

	local self: Controller = setmetatable({
		gui = gui, loadingGui = loadingGui, sounds = sounds, handlers = handlers,
		buttons = {}, panels = {}, connections = {},
		scrim = nil :: any, backdrop = nil, column = nil :: any, root = root,
		scale = nil :: any, loadingScale = nil :: any,
		content = nil :: any, footer = nil :: any, modalShade = nil :: any,
		returnFocus = nil, viewportConnection = nil,
		busy = false, openPanel = nil, destroyed = false, pulse = nil,
	}, Screens)

	-- FUNDO 2D opcional (MenuConfig.Background.Image). Sem imagem, o que
	-- aparece atrás é a cena 3D.
	local image = Config.AssetId(Config.Background.Image)
	if image then
		local backdrop = Instance.new("ImageLabel")
		backdrop.Name, backdrop.Image, backdrop.ZIndex = "Backdrop", image, Z.Backdrop
		backdrop.Size = UDim2.fromScale(1, 1)
		backdrop.BackgroundTransparency, backdrop.BorderSizePixel = 1, 0
		backdrop.ImageTransparency = Config.Background.ImageTransparency
		backdrop.ScaleType = Enum.ScaleType.Crop
		backdrop.Parent = root
		self.backdrop = backdrop
	end

	local scrim = Theme.Frame(root, "Scrim", Z.Scrim)
	scrim.BackgroundColor3 = Color3.new(0, 0, 0)
	scrim.BackgroundTransparency = 1 - math.clamp(Config.Background.Scrim, 0, 1)
	self.scrim = scrim

	Theme.Vignette(root, Z.Vignette)

	local wash = Theme.Frame(root, "LeftWash", Z.Vignette)
	wash.BackgroundColor3, wash.BackgroundTransparency = Config.Palette.Background, 0.08
	wash.Size = UDim2.fromScale(0.76, 1)
	Theme.Gradient(wash, 0, NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(0.48, 0.2),
		NumberSequenceKeypoint.new(1, 1),
	}))

	local content = Theme.Frame(root, "Content", Z.Content)
	self.content = content
	self.scale = attachScale(self, content)
	self.column = Theme.Frame(content, "Column", Z.Content)
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Vertical
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = self.column

	local logo = Theme.Logo(content, Z.Content)
	logo.AnchorPoint = Vector2.zero
	local section = Theme.Label(content, "Section", "MENU PRINCIPAL", 10, Config.Fonts.Button,
		Config.Palette.TextDim, Z.Content)
	section.Size = UDim2.fromOffset(200, 18)

	self.footer = Theme.Frame(content, "Footer", Z.Content)
	self.footer.Visible = false
	local version = Theme.Label(self.footer, "Version", Config.Brand.Version, 11, Config.Fonts.Body,
		Config.Palette.TextDim, Z.Content)
	version.Size = UDim2.new(0.5, 0, 1, 0)

	local character = Theme.Frame(content, "CharacterCaption", Z.Content)
	local rule = Theme.Frame(character, "Rule", Z.Content)
	rule.Size = UDim2.fromOffset(28, 2)
	rule.BackgroundColor3, rule.BackgroundTransparency = Config.Palette.Accent, 0
	local name = Theme.Label(character, "Name", Config.Scene.CharacterName, 15, Config.Fonts.Button,
		Config.Palette.Text, Z.Content)
	name.Position, name.Size = UDim2.fromOffset(0, 14), UDim2.fromOffset(250, 24)
	local role = Theme.Label(character, "Role", Config.Scene.CharacterSubtitle, 10, Config.Fonts.Body,
		Config.Palette.TextDim, Z.Content)
	role.Position, role.Size = UDim2.fromOffset(0, 40), UDim2.fromOffset(250, 20)

	local shade = Theme.Frame(content, "ModalShade", Z.Panel - 1)
	shade.BackgroundColor3, shade.BackgroundTransparency = Config.Palette.Background, 0.2
	shade.Active, shade.Visible = true, false
	self.modalShade = shade

	local function bindViewport()
		if self.viewportConnection then self.viewportConnection:Disconnect() end
		local camera = Workspace.CurrentCamera
		self.viewportConnection = if camera then camera:GetPropertyChangedSignal("ViewportSize"):Connect(function()
			Screens.Rescale(self)
		end) else nil
		Screens.Rescale(self)
	end
	table.insert(self.connections, Workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(bindViewport))
	bindViewport()
	return self
end

function Screens.Rescale(self: Controller)
	if self.destroyed then return end
	local camera = Workspace.CurrentCamera
	local viewport = if camera then camera.ViewportSize else Vector2.new(1280, 720)
	local layout = Theme.Layout(viewport)
	for _, scale in { self.scale, self.loadingScale } do
		if scale then
			scale.Scale = layout.factor
			local canvas = scale.Parent :: GuiObject
			canvas.Size = UDim2.fromScale(1 / layout.factor, 1 / layout.factor)
		end
	end
	self.column.Position = UDim2.fromOffset(layout.margin, layout.columnTop)
	self.column.Size = UDim2.fromOffset(layout.columnWidth, 400)
	local list = self.column:FindFirstChildOfClass("UIListLayout")
	if list then list.Padding = UDim.new(0, layout.gap) end
	for _, child in self.column:GetChildren() do
		if child:IsA("Frame") then
			child.Size = UDim2.new(1, 0, 0, if child.Name == "PlayHolder" then layout.primaryHeight else layout.buttonHeight)
		end
	end
	local logo = self.content:FindFirstChild("Logo") :: GuiObject
	logo.Position = UDim2.fromOffset(layout.margin, layout.logoTop)
	logo.Size = UDim2.fromOffset(if layout.portrait then layout.columnWidth else math.min(layout.width * 0.56, 620), 110)
	local section = self.content:FindFirstChild("Section") :: GuiObject
	section.Position = UDim2.fromOffset(layout.margin + 2, layout.columnTop - 28)
	self.footer.AnchorPoint = Vector2.new(0, 1)
	self.footer.Position = UDim2.new(0, layout.margin, 1, -layout.footerBottom)
	self.footer.Size = UDim2.new(1, -layout.margin * 2, 0, 44)
	local caption = self.content:FindFirstChild("CharacterCaption") :: GuiObject
	caption.Visible = not layout.portrait
	caption.Position = UDim2.new(0.69, 0, 1, -160)
	caption.Size = UDim2.fromOffset(250, 60)
	for _, panel in self.panels do
		panel.Size = UDim2.fromOffset(math.min(620, layout.width - layout.margin * 2), math.min(400, layout.height - 100))
	end
end

--------------------------------------------------------------------------------
-- 1. CARREGAMENTO
--------------------------------------------------------------------------------

function Screens.ShowLoading(self: Controller)
	if not Config.Loading.Enabled then return end
	local gui = self.loadingGui
	local back = Theme.Frame(gui, "Back", 1)
	back.BackgroundColor3 = Config.Palette.Background
	back.BackgroundTransparency = 0

	local content = Theme.Frame(back, "Content", 2)
	self.loadingScale = attachScale(self, content)

	local title = Theme.Label(content, "Title", Config.Brand.Title, 40, Config.Fonts.Display,
		Config.Palette.Text, 3)
	title.AnchorPoint = Vector2.new(0.5, 1)
	title.Position = UDim2.fromScale(0.5, 0.48)
	title.Size = UDim2.fromScale(0.8, 0.1)
	title.TextXAlignment = Enum.TextXAlignment.Center

	local status = Theme.Label(content, "Status", Config.Loading.Text, 14, Config.Fonts.Body,
		Config.Palette.Accent, 3)
	status.AnchorPoint = Vector2.new(0.5, 0)
	status.Position = UDim2.fromScale(0.5, 0.52)
	status.Size = UDim2.fromScale(0.8, 0.05)
	status.TextXAlignment = Enum.TextXAlignment.Center

	-- Barra de progresso: o preenchimento é conduzido por SetLoadingProgress.
	local track = Instance.new("Frame")
	track.Name, track.ZIndex = "Track", 3
	track.AnchorPoint = Vector2.new(0.5, 0)
	track.Position = UDim2.fromScale(0.5, 0.6)
	track.Size = UDim2.fromScale(0.26, 0.004)
	track.BackgroundColor3 = Config.Palette.PanelStroke
	track.BackgroundTransparency, track.BorderSizePixel = 0.55, 0
	track.Parent = content

	local fill = Instance.new("Frame")
	fill.Name, fill.ZIndex = "Fill", 4
	fill.Size = UDim2.fromScale(0, 1)
	fill.BackgroundColor3 = Config.Palette.AccentBright
	fill.BackgroundTransparency, fill.BorderSizePixel = 0, 0
	fill.Parent = track

	local tip = Theme.Label(content, "Tip", "", 13, Config.Fonts.Body, Config.Palette.TextDim, 3)
	tip.AnchorPoint = Vector2.new(0.5, 0)
	tip.Position = UDim2.fromScale(0.5, 0.66)
	tip.Size = UDim2.fromScale(0.7, 0.05)
	tip.TextXAlignment = Enum.TextXAlignment.Center

	gui.Enabled = true

	-- Dicas girando enquanto carrega. Uma conexão só, encerrada no Hide.
	local tips = Config.Loading.Tips
	if #tips > 0 then
		local index, accumulated = 0, math.huge
		self.pulse = RunService.Heartbeat:Connect(function(dt: number)
			accumulated += dt
            if accumulated < Config.Loading.TipInterval then return end
			accumulated = 0
			index = index % #tips + 1
			tip.Text = tips[index]
			tip.TextTransparency = 1
			Theme.Tween(tip, Theme.Info(0.35, Enum.EasingStyle.Quad), { TextTransparency = 0 })
		end)
	end
end

function Screens.SetLoadingProgress(self: Controller, alpha: number)
	local fill = self.loadingGui:FindFirstChild("Fill", true)
	if fill and fill:IsA("Frame") then
		Theme.Tween(fill, Theme.Info(0.25, Enum.EasingStyle.Quad),
			{ Size = UDim2.fromScale(math.clamp(alpha, 0, 1), 1) })
	end
end

function Screens.HideLoading(self: Controller, onDone: () -> ())
	if self.pulse then self.pulse:Disconnect(); self.pulse = nil end
	if not Config.Loading.Enabled or not self.loadingGui.Enabled then onDone(); return end
	local back = self.loadingGui:FindFirstChild("Back")
	if not back or not back:IsA("Frame") then
		self.loadingGui.Enabled = false
		onDone()
		return
	end
	local info = Theme.Info(Config.Motion.ScreenFade)
	for _, descendant in back:GetDescendants() do
		if descendant:IsA("TextLabel") then
			Theme.Tween(descendant, info, { TextTransparency = 1 })
		elseif descendant:IsA("Frame") then
			Theme.Tween(descendant, info, { BackgroundTransparency = 1 })
		end
	end
	Theme.Tween(back, info, { BackgroundTransparency = 1 }, function()
		self.loadingGui.Enabled = false
		onDone()
	end)
end

--------------------------------------------------------------------------------
-- 2. CLIQUE PARA COMEÇAR
--------------------------------------------------------------------------------

function Screens.ShowStart(self: Controller, onStart: () -> ())
	local content = self.gui:FindFirstChild("Content", true)
	local prompt = Theme.Label(self.root, "PressAnyKey", Config.Flow.PressAnyKeyText, 18,
		Config.Fonts.Button, Config.Palette.Text, Z.Content + 5)
	prompt.AnchorPoint = Vector2.new(0.5, 0.5)
	prompt.Position = UDim2.fromScale(0.5, 0.82)
	prompt.Size = UDim2.fromScale(0.8, 0.06)
	prompt.TextXAlignment = Enum.TextXAlignment.Center
	prompt.TextWrapped = true
	prompt.TextTransparency = 1
	if content and content:IsA("GuiObject") then
		-- Entra debaixo do mesmo UIScale das outras telas.
		prompt.Parent = content
	end

	-- A coluna de botões ainda não existe nesta tela: só logo + texto.
	self.column.Visible = false
	(self.content:FindFirstChild("Section") :: GuiObject).Visible = false
	self.gui.Enabled = true
	self.root.BackgroundTransparency = 1

	local info = Theme.Info(Config.Motion.ScreenFade)
	Theme.Tween(prompt, info, { TextTransparency = 0 })

	-- Brilho suave e contínuo, via tween em laço (nada de RenderStepped só
	-- para piscar um texto).
	local alive = true
	local function pulse(fadeOut: boolean)
		if not alive or self.destroyed then return end
		Theme.Tween(prompt, Theme.Info(Config.Flow.PressAnyKeyPulse, Enum.EasingStyle.Sine,
			Enum.EasingDirection.InOut), { TextTransparency = if fadeOut then 0.62 else 0 }, function()
			pulse(not fadeOut)
		end)
	end
	task.delay(Config.Motion.ScreenFade, function() pulse(true) end)

	local started = false
	local startConnections: { RBXScriptConnection } = {}
	local function trigger()
		if started or self.busy then return end
		started, alive = true, false
		for _, connection in startConnections do connection:Disconnect() end
		table.clear(startConnections)
		self.busy = true
		Sounds.Play(self.sounds, "Start")
		Theme.Tween(prompt, Theme.Info(Config.Motion.StartFade), { TextTransparency = 1 }, function()
			prompt:Destroy()
			self.busy = false
			onStart()
		end)
	end

	-- Qualquer tecla, clique, toque ou botão de controle -- mas NÃO mexer o
	-- mouse, girar a roda ou o jogo ganhar/perder foco, senão a tela some
	-- sozinha antes de o jogador ler o que está escrito.
	local ignored = {
		[Enum.UserInputType.MouseMovement] = true,
		[Enum.UserInputType.MouseWheel] = true,
		[Enum.UserInputType.Focus] = true,
		[Enum.UserInputType.Gyro] = true,
		[Enum.UserInputType.Accelerometer] = true,
	}
	table.insert(startConnections, UserInputService.InputBegan:Connect(function(input, gameProcessed)
		if gameProcessed or ignored[input.UserInputType] then return end
		trigger()
	end))
	for _, connection in startConnections do table.insert(self.connections, connection) end
end

--------------------------------------------------------------------------------
-- 3. MENU PRINCIPAL
--------------------------------------------------------------------------------

local function panelMessage(self: Controller, body: Frame, text: string, blurb: string?)
	local heading = Theme.Label(body, "Soon", text, 30, Config.Fonts.Display,
		Config.Palette.Accent, Z.Panel + 2)
	heading.AnchorPoint = Vector2.new(0.5, 0.5)
	heading.Position = UDim2.fromScale(0.5, 0.42)
	heading.Size = UDim2.fromScale(1, 0.2)
	heading.TextXAlignment = Enum.TextXAlignment.Center

	if blurb then
		local detail = Theme.Label(body, "Blurb", blurb, 15, Config.Fonts.Body,
			Config.Palette.TextDim, Z.Panel + 2)
		detail.AnchorPoint = Vector2.new(0.5, 0)
		detail.Position = UDim2.fromScale(0.5, 0.58)
		detail.Size = UDim2.fromScale(0.9, 0.2)
		detail.TextXAlignment = Enum.TextXAlignment.Center
		detail.TextWrapped = true
	end
end

-- Botão VOLTAR: todo painel tem um, no mesmo lugar, com o mesmo som.
local function addBackButton(self: Controller, panel: Frame)
	local holder = Instance.new("Frame")
	holder.Name, holder.ZIndex = "BackHolder", Z.Panel + 1
	holder.AnchorPoint = Vector2.new(0.5, 1)
	holder.Position = UDim2.new(0.5, 0, 1, -18)
	holder.Size = UDim2.new(0.44, 0, 0, 40)
	holder.BackgroundTransparency, holder.BorderSizePixel = 1, 0
	holder.Parent = panel

	local back = Theme.Button(holder, "Back", "VOLTAR", Z.Panel + 2, { compact = false })
	back.Instance.Size = UDim2.fromScale(1, 1)
	back.Instance.MouseEnter:Connect(function() Sounds.Hover(self.sounds) end)
	back.Instance.SelectionGained:Connect(function() Sounds.Hover(self.sounds) end)
	back.Instance.Activated:Connect(function()
		if self.busy then return end
		Sounds.Play(self.sounds, "Back")
		Theme.Press(back.Instance)
		Screens.ClosePanel(self)
	end)
	return back
end

local function buildPanel(self: Controller, id: string, title: string, build: (Frame) -> ()): Frame
	local existing = self.panels[id]
	if existing then return existing end
	local panel, body = Theme.Panel(self.root, "Panel" .. id, title, Z.Panel)
	local content = self.gui:FindFirstChild("Content", true)
	if content and content:IsA("GuiObject") then panel.Parent = content end
	build(body)
	self.buttons["Back" .. id] = addBackButton(self, panel)
	self.panels[id] = panel
	Screens.Rescale(self)
	return panel
end

function Screens.OpenPanel(self: Controller, id: string, title: string, build: (Frame) -> ())
	if self.busy or self.openPanel then return end
	self.busy = true
	self.openPanel = id
	self.returnFocus = GuiService.SelectedObject
	self.modalShade.Visible = true
	for key, button in self.buttons do
		if not string.match(key, "^Back") then button.SetEnabled(false) end
	end
	local panel = buildPanel(self, id, title, build)
	panel.Visible = true
	panel.BackgroundTransparency = 1
	panel.Position = UDim2.fromScale(0.5, 0.54)
	local info = Theme.Info(Config.Motion.PanelSlide)
	Theme.Tween(panel, info, { BackgroundTransparency = 0.06, Position = UDim2.fromScale(0.5, 0.5) })

	task.delay(Config.Motion.PanelSlide + Config.Motion.InputLockPadding, function()
		if self.destroyed then return end
		self.busy = false
		-- Foco de controle/teclado vai para o VOLTAR do painel aberto.
		local back = panel:FindFirstChild("Back", true)
		if back and back:IsA("GuiObject") and (Theme.IsConsole() or self.returnFocus) then
			GuiService.SelectedObject = back
		end
	end)
end

function Screens.ClosePanel(self: Controller)
	local id = self.openPanel
	if not id or self.busy then return end
	local panel = self.panels[id]
	self.busy = true
	self.openPanel = nil
	local info = Theme.Info(Config.Motion.PanelSlide)
	if panel then
		Theme.Tween(panel, info, { BackgroundTransparency = 1, Position = UDim2.fromScale(0.5, 0.54) },
			function() panel.Visible = false end)
	end
	task.delay(Config.Motion.PanelSlide + Config.Motion.InputLockPadding, function()
		if self.destroyed then return end
		self.modalShade.Visible = false
		for key, button in self.buttons do
			if not string.match(key, "^Back") then button.SetEnabled(true) end
		end
		GuiService.SelectedObject = self.returnFocus
		self.returnFocus = nil
		self.busy = false
	end)
end

function Screens.ShowMenu(self: Controller)
	if self.buttons.Play then return end
	self.column.Visible, self.footer.Visible, self.gui.Enabled = true, true, true
	(self.content:FindFirstChild("Section") :: GuiObject).Visible = true

	local navigation: { TextButton } = {}
	local function bindButton(button: Theme.Button, onClick: () -> (), sound: string)
		button.Instance.MouseEnter:Connect(function()
			if not self.busy and not self.openPanel then Sounds.Hover(self.sounds) end
		end)
		button.Instance.SelectionGained:Connect(function()
			if not self.busy then Sounds.Hover(self.sounds) end
		end)
		button.Instance.Activated:Connect(function()
			if self.busy or self.openPanel then return end
			Sounds.Play(self.sounds, sound)
			Theme.Press(button.Instance)
			onClick()
		end)
		table.insert(navigation, button.Instance)
	end

	for order, entry in Config.MainButtons do
		local holder = Theme.Frame(self.column, entry.id .. "Holder", Z.Content)
		holder.LayoutOrder = order
		local button = Theme.Button(holder, entry.id, entry.label, Z.Content + 1, {
			primary = entry.primary, subtitle = entry.subtitle,
			index = if entry.primary then nil else order - 1,
		})
		self.buttons[entry.id] = button
		bindButton(button, function()
			if entry.id == "Play" then self.handlers.OnPlay(); return end
			Screens.OpenPanel(self, entry.id, entry.label, function(body)
				panelMessage(self, body, "EM BREVE", entry.blurb)
			end)
		end, if entry.primary then "Enter" else "Click")
		-- O UIListLayout controla o holder. Animamos o filho, que está livre.
		button.Instance.Position = UDim2.fromOffset(-24, 0)
		button.Instance.Visible = false
		task.delay(0.055 * (order - 1), function()
			if self.destroyed then return end
			button.Instance.Visible = true
			Theme.Tween(button.Instance, Theme.Info(Config.Motion.PanelSlide), { Position = UDim2.fromOffset(0, 0) })
		end)
	end

	local credits = Theme.Button(self.footer, "Credits", Config.Credits.label, Z.Content + 1, { compact = true })
	credits.Instance.AnchorPoint = Vector2.new(1, 1)
	credits.Instance.Position, credits.Instance.Size = UDim2.fromScale(1, 1), UDim2.fromOffset(154, 44)
	self.buttons.Credits = credits
	bindButton(credits, function()
		Screens.OpenPanel(self, "Credits", Config.Credits.label, function(body)
			panelMessage(self, body, "EM BREVE", Config.Credits.blurb)
		end)
	end, "Click")

	for index, button in navigation do
		button.NextSelectionUp = navigation[if index == 1 then #navigation else index - 1]
		button.NextSelectionDown = navigation[if index == #navigation then 1 else index + 1]
	end
	Screens.Rescale(self)
	if Theme.IsConsole() then GuiService.SelectedObject = self.buttons.Play.Instance end
	table.insert(self.connections, UserInputService.InputBegan:Connect(function(input, gameProcessed)
		if gameProcessed or self.busy or not self.openPanel then return end
		if input.KeyCode == Enum.KeyCode.Escape or input.KeyCode == Enum.KeyCode.ButtonB then
			Sounds.Play(self.sounds, "Back")
			Screens.ClosePanel(self)
		end
	end))
end

--------------------------------------------------------------------------------
-- 4. SAÍDA
--------------------------------------------------------------------------------

--[[
	Close(onDone)
	Fade out do menu inteiro. onDone roda DEPOIS da transição -- é ele que
	devolve câmera, controles e HUD ao gameplay.
]]
function Screens.Close(self: Controller, onDone: () -> ())
	if self.destroyed then return end
	if self.busy then
		-- Uma transição de painel estava rodando. Fechar é prioritário, então
		-- em vez de desistir (o que deixaria o menu preso na tela para
		-- sempre), esperamos ela terminar e tentamos de novo.
		task.delay(Config.Motion.PanelSlide + Config.Motion.InputLockPadding, function()
			Screens.Close(self, onDone)
		end)
		return
	end
	self.busy = true
	GuiService.SelectedObject = nil
	local info = Theme.Info(Config.Motion.PlayFade)
	-- Um véu preto por cima de tudo: cobre a troca de câmera, que é o momento
	-- mais feio da transição. Fica FORA de `root` de propósito -- quando ele
	-- abrir, o menu já terá sido escondido e não pode reaparecer por baixo.
	-- Active = true para nenhum botão continuar clicável atrás dele.
	local veil = Theme.Frame(self.gui, "Veil", Z.Panel + 50)
	veil.BackgroundColor3 = Color3.new(0, 0, 0)
	veil.BackgroundTransparency = 1
	veil.Active = true
	Theme.Tween(veil, info, { BackgroundTransparency = 0 }, function()
		-- Esconde o menu ANTES de soltar a câmera: daqui em diante só o véu
		-- preto está na tela.
		self.root.Visible = false
		GuiService.SelectedObject = nil
		onDone()
		-- Só depois que o gameplay assumiu é que o véu abre, revelando o jogo.
		task.delay(0.05, function()
			if self.destroyed then return end
			Theme.Tween(veil, Theme.Info(Config.Motion.ScreenFade), { BackgroundTransparency = 1 }, function()
				self.gui.Enabled = false
				veil:Destroy()
				self.busy = false
			end)
		end)
	end)
end

function Screens.Destroy(self: Controller)
	if self.destroyed then return end
	self.destroyed = true
	if self.viewportConnection then self.viewportConnection:Disconnect(); self.viewportConnection = nil end
	if self.pulse then self.pulse:Disconnect(); self.pulse = nil end
	for _, connection in self.connections do connection:Disconnect() end
	table.clear(self.connections)
	for _, button in self.buttons do button.Destroy() end
	table.clear(self.buttons)
	table.clear(self.panels)
	GuiService.SelectedObject = nil
	self.gui:Destroy()
	self.loadingGui:Destroy()
end

return Screens
