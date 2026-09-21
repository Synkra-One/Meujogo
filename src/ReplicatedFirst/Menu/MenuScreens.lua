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
	  4. Painéis -- submenus "Em breve" e o acesso rápido, todos com VOLTAR

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
	OnQuickPlay: (string) -> (),
	OnQuit: () -> (),
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

	local content = Theme.Frame(root, "Content", Z.Content)
	self.scale = attachScale(self, content)

	-- COLUNA À ESQUERDA: a cena (e o monstro) fica livre à direita, então os
	-- botões nunca cobrem o que importa.
	local column = Instance.new("Frame")
	column.Name, column.ZIndex = "Column", Z.Content
	column.AnchorPoint = Vector2.new(0, 0.5)
	column.Position = UDim2.fromScale(0.07, 0.54)
	column.Size = UDim2.fromScale(0.3, 0.62)
	column.BackgroundTransparency, column.BorderSizePixel = 1, 0
	column.Parent = content
	self.column = column

	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Vertical
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, 8)
	layout.Parent = column

	local logo = Theme.Logo(content, Z.Content)
	logo.Position = UDim2.fromScale(0.07, 0.2)

	local version = Theme.Label(content, "Version", Config.Brand.Version, 13, Config.Fonts.Body,
		Config.Palette.TextDim, Z.Content)
	version.AnchorPoint = Vector2.new(0, 1)
	version.Position = UDim2.fromScale(0.07, 0.95)
	version.Size = UDim2.fromScale(0.3, 0.03)

	-- Reescala quando a janela muda (girar o celular, redimensionar o Studio).
	table.insert(self.connections, Workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function()
		Screens.Rescale(self)
	end))
	local camera = Workspace.CurrentCamera
	if camera then
		table.insert(self.connections, camera:GetPropertyChangedSignal("ViewportSize"):Connect(function()
			Screens.Rescale(self)
		end))
	end
	return self
end

function Screens.Rescale(self: Controller)
	if self.destroyed then return end
	local camera = Workspace.CurrentCamera
	local viewport = if camera then camera.ViewportSize else Vector2.new(1280, 720)
	local factor = Theme.Scale(viewport)
	if self.scale then self.scale.Scale = factor end
	if self.loadingScale then self.loadingScale.Scale = factor end
	-- Retrato (celular em pé): a coluna ocupa mais largura, senão o texto
	-- fica espremido.
	if self.column then
		local portrait = viewport.Y > viewport.X
		self.column.Size = UDim2.fromScale(if portrait then 0.55 else 0.3, if portrait then 0.5 else 0.62)
		self.column.Position = UDim2.fromScale(if portrait then 0.08 else 0.07, if portrait then 0.62 else 0.54)
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
	prompt.TextTransparency = 1
	if content and content:IsA("GuiObject") then
		-- Entra debaixo do mesmo UIScale das outras telas.
		prompt.Parent = content
	end

	-- A coluna de botões ainda não existe nesta tela: só logo + texto.
	self.column.Visible = false
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
	addBackButton(self, panel)
	self.panels[id] = panel
	return panel
end

function Screens.OpenPanel(self: Controller, id: string, title: string, build: (Frame) -> ())
	if self.busy or self.openPanel then return end
	self.busy = true
	self.openPanel = id
	local panel = buildPanel(self, id, title, build)
	panel.Visible = true
	panel.BackgroundTransparency = 1
	panel.Position = UDim2.fromScale(0.5, 0.54)
	local info = Theme.Info(Config.Motion.PanelSlide)
	Theme.Tween(panel, info, { BackgroundTransparency = 0.06, Position = UDim2.fromScale(0.5, 0.5) })
	-- A coluna recua enquanto o painel está aberto, em vez de sumir: o
	-- jogador continua entendendo onde está.
	Theme.Tween(self.column, info, { Position = UDim2.fromScale(0.02, self.column.Position.Y.Scale) })
	task.delay(Config.Motion.PanelSlide + Config.Motion.InputLockPadding, function()
		self.busy = false
		-- Foco de controle/teclado vai para o VOLTAR do painel aberto.
		local back = panel:FindFirstChild("Back", true)
		if back and back:IsA("GuiObject") and (Theme.IsConsole() or GuiService.SelectedObject) then
			GuiService.SelectedObject = back
		end
	end)
end

function Screens.ClosePanel(self: Controller)
	local id = self.openPanel
	if not id then return end
	local panel = self.panels[id]
	self.busy = true
	self.openPanel = nil
	local info = Theme.Info(Config.Motion.PanelSlide)
	if panel then
		Theme.Tween(panel, info, { BackgroundTransparency = 1, Position = UDim2.fromScale(0.5, 0.54) },
			function() panel.Visible = false end)
	end
	local portrait = self.column.Size.X.Scale > 0.4
	Theme.Tween(self.column, info,
		{ Position = UDim2.fromScale(if portrait then 0.08 else 0.07, self.column.Position.Y.Scale) })
	task.delay(Config.Motion.PanelSlide + Config.Motion.InputLockPadding, function()
		self.busy = false
	end)
end

--[[
	ShowMenu(canQuickPlay)
	Monta a coluna de botões e faz a entrada. canQuickPlay vem do servidor
	(GameConfig.Testing) -- o botão de acesso rápido só existe para quem tem
	permissão, e mesmo assim quem valida de verdade é o servidor.
]]
function Screens.ShowMenu(self: Controller, canQuickPlay: boolean)
	self.column.Visible = true
	self.gui.Enabled = true

	local order = 0
	local function addButton(id: string, label: string, options: any, onClick: () -> ())
		order += 1
		local holder = Instance.new("Frame")
		holder.Name, holder.LayoutOrder = id .. "Holder", order
		holder.Size = UDim2.new(1, 0, 0, if options and options.compact then 34 else 44)
		holder.BackgroundTransparency, holder.BorderSizePixel = 1, 0
		holder.Parent = self.column

		local button = Theme.Button(holder, id, label, Z.Content + 1, options)
		button.Instance.MouseEnter:Connect(function() Sounds.Hover(self.sounds) end)
		button.Instance.Activated:Connect(function()
			if self.busy then return end
			Sounds.Play(self.sounds, "Click")
			Theme.Press(button.Instance)
			onClick()
		end)
		self.buttons[id] = button
		-- Entrada escalonada: cada botão desliza um pouquinho depois do outro.
		holder.Position = UDim2.new(-0.25, 0, 0, 0)
		button.Instance.BackgroundTransparency = 1
		task.delay(0.04 * order, function()
			if self.destroyed then return end
			Theme.Tween(holder, Theme.Info(Config.Motion.PanelSlide), { Position = UDim2.new(0, 0, 0, 0) })
			Theme.Tween(button.Instance, Theme.Info(Config.Motion.PanelSlide), { BackgroundTransparency = 0.35 })
		end)
		return button
	end

	-- ACESSO RÁPIDO primeiro: é o que você vai usar toda hora testando.
	if canQuickPlay and Config.QuickPlay.Enabled then
		addButton("QuickPlay", Config.QuickPlay.Label, { primary = true }, function()
			Screens.OpenPanel(self, "QuickPlay", Config.QuickPlay.Label, function(body)
				local hint = Theme.Label(body, "Hint", Config.QuickPlay.Hint, 14, Config.Fonts.Body,
					Config.Palette.TextDim, Z.Panel + 2)
				hint.Position, hint.Size = UDim2.fromScale(0, 0), UDim2.fromScale(1, 0.12)
				hint.TextXAlignment = Enum.TextXAlignment.Center
				hint.TextWrapped = true

				local list = Instance.new("Frame")
				list.Name, list.ZIndex = "Roles", Z.Panel + 2
				list.Position, list.Size = UDim2.fromScale(0.12, 0.18), UDim2.fromScale(0.76, 0.62)
				list.BackgroundTransparency, list.BorderSizePixel = 1, 0
				list.Parent = body

				local layout = Instance.new("UIListLayout")
				layout.Padding = UDim.new(0, 8)
				layout.SortOrder = Enum.SortOrder.LayoutOrder
				layout.Parent = list

				for index, option in Config.QuickPlay.Options do
					local holder = Instance.new("Frame")
					holder.LayoutOrder = index
					holder.Size = UDim2.new(1, 0, 0, 40)
					holder.BackgroundTransparency, holder.BorderSizePixel = 1, 0
					holder.Parent = list
					local button = Theme.Button(holder, option.id, option.label, Z.Panel + 3,
						{ primary = option.id == "Monster" })
					button.Instance.MouseEnter:Connect(function() Sounds.Hover(self.sounds) end)
					button.Instance.Activated:Connect(function()
						if self.busy then return end
						Sounds.Play(self.sounds, "Click")
						Theme.Press(button.Instance)
						self.handlers.OnQuickPlay(option.id)
					end)
				end
			end)
		end)
	end

	for _, entry in Config.MainButtons do
		if entry.quit and not Config.ShowQuitButton then continue end
		local id = entry.id :: string
		if id == "Play" then
			addButton(id, entry.label :: string, { primary = true }, function()
				self.handlers.OnPlay()
			end)
		elseif entry.quit then
			addButton(id, entry.label :: string, { danger = true, compact = true }, function()
				Screens.OpenPanel(self, "Quit", "SAIR", function(body)
					panelMessage(self, body, "SAIR DO SERVIDOR?",
						"A Roblox não fecha o aplicativo por script. Isto desconecta você desta partida.")
					local holder = Instance.new("Frame")
					holder.AnchorPoint = Vector2.new(0.5, 1)
					holder.Position, holder.Size = UDim2.fromScale(0.5, 1), UDim2.new(0.6, 0, 0, 40)
					holder.BackgroundTransparency, holder.BorderSizePixel = 1, 0
					holder.Parent = body
					local confirm = Theme.Button(holder, "Confirm", "CONFIRMAR", Z.Panel + 3, { danger = true })
					confirm.Instance.MouseEnter:Connect(function() Sounds.Hover(self.sounds) end)
					confirm.Instance.Activated:Connect(function()
						if self.busy then return end
						Sounds.Play(self.sounds, "Click")
						self.handlers.OnQuit()
					end)
				end)
			end)
		else
			addButton(id, entry.label :: string, nil, function()
				Screens.OpenPanel(self, id, entry.label :: string, function(body)
					panelMessage(self, body, "EM BREVE", entry.blurb)
				end)
			end)
		end
	end

	-- Console/controle: manda o foco para o primeiro botão, senão o jogador
	-- fica sem cursor e sem seleção.
	if Theme.IsConsole() then
		local first = self.column:FindFirstChildWhichIsA("Frame")
		local button = first and first:FindFirstChildWhichIsA("TextButton")
		if button then GuiService.SelectedObject = button end
	end
	-- Escape/B fecham o painel aberto, como em qualquer menu de console.
	table.insert(self.connections, UserInputService.InputBegan:Connect(function(input, gameProcessed)
		if gameProcessed or not self.openPanel then return end
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
