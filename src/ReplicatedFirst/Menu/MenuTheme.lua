--!strict
--[[
	MenuTheme
	Construtores visuais do menu: tudo que é "como uma coisa se parece e como
	ela se move" mora aqui. MenuScreens cuida de "o que aparece quando".

	Nenhuma cor, tempo ou fonte é escolhida neste arquivo -- todas vêm do
	MenuConfig. Toda transição passa pelo TweenService.

	RESPONSIVO: o layout usa escala (fração da tela), não pixels fixos, e o
	Scale() abaixo ajusta o tamanho do texto/botões por tamanho de viewport,
	com alvo de toque maior em celular/tablet.
]]

local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local GuiService = game:GetService("GuiService")

local Config = require(script.Parent.MenuConfig)

local Theme = {}

local BASE_VIEWPORT = Vector2.new(1280, 720)

function Theme.Info(time: number?, style: Enum.EasingStyle?, direction: Enum.EasingDirection?): TweenInfo
	return TweenInfo.new(time or Config.Motion.ScreenFade, style or Config.Motion.Easing,
		direction or Config.Motion.Direction)
end

-- Tween com callback de conclusão que NÃO vaza conexão.
function Theme.Tween(instance: Instance, info: TweenInfo, goal: { [string]: any }, onDone: (() -> ())?): Tween
	local tween = TweenService:Create(instance, info, goal)
	if onDone then
		local connection: RBXScriptConnection
		connection = tween.Completed:Connect(function()
			connection:Disconnect()
			onDone()
		end)
	end
	tween:Play()
	return tween
end

function Theme.IsTouch(): boolean
	return UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
end

function Theme.IsConsole(): boolean
	return GuiService:IsTenFootInterface()
end

--[[
	Scale(camera)
	Fator único aplicado por UIScale. Celular ganha um pouco mais que a
	proporção pura (alvo de toque), console também (distância da TV).
]]
function Theme.Scale(viewport: Vector2): number
	local raw = math.min(viewport.X / BASE_VIEWPORT.X, viewport.Y / BASE_VIEWPORT.Y)
	local factor = math.clamp(raw, 0.62, 1.55)
	if Theme.IsTouch() then factor *= 1.18 end
	if Theme.IsConsole() then factor *= 1.22 end
	return factor
end

function Theme.Corner(parent: Instance, radius: number): UICorner
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, radius)
	corner.Parent = parent
	return corner
end

function Theme.Stroke(parent: Instance, color: Color3, thickness: number, transparency: number): UIStroke
	local stroke = Instance.new("UIStroke")
	stroke.Color, stroke.Thickness, stroke.Transparency = color, thickness, transparency
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Parent = parent
	return stroke
end

function Theme.Gradient(parent: Instance, rotation: number, transparency: NumberSequence): UIGradient
	local gradient = Instance.new("UIGradient")
	gradient.Rotation, gradient.Transparency = rotation, transparency
	gradient.Parent = parent
	return gradient
end

function Theme.Frame(parent: Instance, name: string, zIndex: number): Frame
	local frame = Instance.new("Frame")
	frame.Name, frame.ZIndex = name, zIndex
	frame.BackgroundTransparency, frame.BorderSizePixel = 1, 0
	frame.Size = UDim2.fromScale(1, 1)
	frame.Parent = parent
	return frame
end

function Theme.Label(parent: Instance, name: string, text: string, size: number, font: Enum.Font,
	color: Color3, zIndex: number): TextLabel
	local label = Instance.new("TextLabel")
	label.Name, label.Text, label.ZIndex = name, text, zIndex
	label.BackgroundTransparency, label.BorderSizePixel = 1, 0
	label.Font, label.TextSize, label.TextColor3 = font, size, color
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.RichText = false
	label.Parent = parent
	return label
end

--------------------------------------------------------------------------------
-- VINHETA -- quatro bordas em gradiente. Mesma ideia da vinheta do Fear, para
-- não precisar de nenhuma arte.
--------------------------------------------------------------------------------
function Theme.Vignette(parent: Instance, zIndex: number): { Frame }
	local size = math.clamp(Config.Background.VignetteSize, 0.05, 0.45)
	local edges: { Frame } = {}
	for _, data in {
		{ "Left", UDim2.fromScale(0, 0), UDim2.fromScale(size, 1), 0 },
		{ "Right", UDim2.fromScale(1 - size, 0), UDim2.fromScale(size, 1), 180 },
		{ "Top", UDim2.fromScale(0, 0), UDim2.fromScale(1, size), 90 },
		{ "Bottom", UDim2.fromScale(0, 1 - size), UDim2.fromScale(1, size), 270 },
	} do
		local edge = Instance.new("Frame")
		edge.Name = "Vignette" .. (data[1] :: string)
		edge.Position, edge.Size = data[2] :: UDim2, data[3] :: UDim2
		edge.BackgroundColor3 = Color3.new(0, 0, 0)
		edge.BackgroundTransparency = 1 - math.clamp(Config.Background.VignetteOpacity, 0, 1)
		edge.BorderSizePixel, edge.Active, edge.ZIndex = 0, false, zIndex
		edge.Parent = parent
		Theme.Gradient(edge, data[4] :: number, NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0),
			NumberSequenceKeypoint.new(0.55, 0.6),
			NumberSequenceKeypoint.new(1, 1),
		}))
		table.insert(edges, edge)
	end
	return edges
end

--------------------------------------------------------------------------------
-- LOGO -- imagem se você tiver, texto se não tiver. Os dois ficam bons.
--------------------------------------------------------------------------------
function Theme.Logo(parent: Instance, zIndex: number): GuiObject
	local image = Config.AssetId(Config.Brand.LogoImage)
	if image then
		local logo = Instance.new("ImageLabel")
		logo.Name, logo.Image, logo.ZIndex = "Logo", image, zIndex
		logo.BackgroundTransparency, logo.BorderSizePixel = 1, 0
		logo.ScaleType = Enum.ScaleType.Fit
		logo.AnchorPoint = Vector2.new(0, 0.5)
		logo.Size = UDim2.fromScale(Config.Brand.LogoHeightScale * Config.Brand.LogoAspectRatio,
			Config.Brand.LogoHeightScale)
		logo.Parent = parent
		return logo
	end
	local holder = Instance.new("Frame")
	holder.Name, holder.ZIndex = "Logo", zIndex
	holder.BackgroundTransparency, holder.BorderSizePixel = 1, 0
	holder.AnchorPoint = Vector2.new(0, 0.5)
	holder.Size = UDim2.fromScale(0.62, Config.Brand.LogoHeightScale * 1.5)
	holder.Parent = parent

	local title = Theme.Label(holder, "Title", Config.Brand.Title, 58, Config.Fonts.Display,
		Config.Palette.Text, zIndex + 1)
	title.Size = UDim2.fromScale(1, 0.62)
	Theme.Stroke(title, Color3.new(0, 0, 0), 2, 0.45)

	local subtitle = Theme.Label(holder, "Subtitle", Config.Brand.Subtitle, 17, Config.Fonts.Body,
		Config.Palette.Accent, zIndex + 1)
	subtitle.Position, subtitle.Size = UDim2.fromScale(0, 0.64), UDim2.fromScale(1, 0.24)
	-- Espaçamento largo dá o ar de "abertura de filme" sem precisar de fonte
	-- customizada (a Roblox não expõe letter-spacing).
	subtitle.Text = string.upper(table.concat(string.split(Config.Brand.Subtitle, ""), " "))
	return holder
end

--------------------------------------------------------------------------------
-- BOTÃO -- minimalista: barra de acento à esquerda que cresce no hover, fundo
-- que acende, texto que clareia e desloca. Teclado/controle usam o MESMO
-- caminho visual (SetFocus), então "selecionado" é sempre legível.
--------------------------------------------------------------------------------
export type Button = {
	Instance: TextButton,
	SetFocus: (boolean) -> (),
	SetEnabled: (boolean) -> (),
	Destroy: () -> (),
}

function Theme.Button(parent: Instance, name: string, text: string, zIndex: number,
	options: { primary: boolean?, danger: boolean?, compact: boolean? }?): Button
	local opts = options or {}
	local accent = if opts.danger then Config.Palette.Danger
		elseif opts.primary then Config.Palette.AccentBright
		else Config.Palette.Accent

	local button = Instance.new("TextButton")
	button.Name, button.ZIndex = name, zIndex
	button.AutoButtonColor = false -- o realce é todo nosso, via tween
	button.BackgroundColor3 = Config.Palette.Panel
	button.BackgroundTransparency = 0.35
	button.BorderSizePixel = 0
	button.Text = ""
	button.Size = UDim2.fromScale(1, if opts.compact then 0.5 else 1)
	button.Parent = parent
	Theme.Corner(button, 3)

	local stroke = Theme.Stroke(button, Config.Palette.PanelStroke, 1, 0.55)

	local bar = Instance.new("Frame")
	bar.Name, bar.ZIndex = "Bar", zIndex + 1
	bar.AnchorPoint = Vector2.new(0, 0.5)
	bar.Position = UDim2.fromScale(0, 0.5)
	bar.Size = UDim2.new(0, 3, 0.42, 0)
	bar.BackgroundColor3 = accent
	bar.BackgroundTransparency, bar.BorderSizePixel = 0.25, 0
	bar.Parent = button

	local label = Theme.Label(button, "Label", text, if opts.compact then 15 else 19,
		Config.Fonts.Button, Config.Palette.TextDim, zIndex + 1)
	label.Position = UDim2.new(0, 18, 0, 0)
	label.Size = UDim2.new(1, -30, 1, 0)

	local enabled = true
	local focused = false

	local function apply(instant: boolean?)
		local info = Theme.Info(if instant then 0 else Config.Motion.ButtonHover,
			Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
		local on = focused and enabled
		Theme.Tween(button, info, {
			BackgroundTransparency = if not enabled then 0.75 elseif on then 0.08 else 0.35,
		})
		Theme.Tween(stroke, info, { Transparency = if on then 0.1 else 0.55,
			Color = if on then accent else Config.Palette.PanelStroke })
		Theme.Tween(bar, info, {
			Size = if on then UDim2.new(0, 4, 1, 0) else UDim2.new(0, 3, 0.42, 0),
			BackgroundTransparency = if not enabled then 0.7 elseif on then 0 else 0.25,
		})
		Theme.Tween(label, info, {
			TextColor3 = if not enabled then Config.Palette.TextDim
				elseif on then Config.Palette.Highlight else Config.Palette.Text,
			Position = if on then UDim2.new(0, 26, 0, 0) else UDim2.new(0, 18, 0, 0),
			TextTransparency = if enabled then 0 else 0.45,
		})
	end
	apply(true)

	local connections: { RBXScriptConnection } = {
		button.MouseEnter:Connect(function() focused = true; apply() end),
		button.MouseLeave:Connect(function() focused = false; apply() end),
		-- Controle/teclado: a própria Roblox move o SelectionObject.
		button.SelectionGained:Connect(function() focused = true; apply() end),
		button.SelectionLost:Connect(function() focused = false; apply() end),
	}

	local api: Button
	api = {
		Instance = button,
		SetFocus = function(value: boolean)
			focused = value
			apply()
		end,
		SetEnabled = function(value: boolean)
			enabled = value
			button.Active, button.Selectable = value, value
			apply()
		end,
		Destroy = function()
			for _, connection in connections do connection:Disconnect() end
			table.clear(connections)
			button:Destroy()
		end,
	}
	return api
end

--[[
	Press(button)
	Afundada curta ao clicar. Puramente visual: quem decide se o clique vale
	é o MenuScreens (que segura os cliques durante transições).
]]
function Theme.Press(button: TextButton)
	local info = Theme.Info(Config.Motion.ButtonPress, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	local label = button:FindFirstChild("Label")
	if label and label:IsA("TextLabel") then
		Theme.Tween(label, info, { TextTransparency = 0.45 }, function()
			Theme.Tween(label, info, { TextTransparency = 0 })
		end)
	end
end

--------------------------------------------------------------------------------
-- PAINEL -- caixa usada pelos submenus ("Em breve", acesso rápido, etc).
--------------------------------------------------------------------------------
function Theme.Panel(parent: Instance, name: string, title: string, zIndex: number): (Frame, Frame)
	local panel = Instance.new("Frame")
	panel.Name, panel.ZIndex = name, zIndex
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.Position = UDim2.fromScale(0.5, 0.5)
	panel.Size = UDim2.fromScale(0.52, 0.56)
	panel.BackgroundColor3 = Config.Palette.Panel
	panel.BackgroundTransparency = 0.06
	panel.BorderSizePixel = 0
	panel.Visible = false
	panel.Parent = parent
	Theme.Corner(panel, 4)
	Theme.Stroke(panel, Config.Palette.PanelStroke, 1, 0.35)

	local header = Instance.new("Frame")
	header.Name, header.ZIndex = "Header", zIndex + 1
	header.Size = UDim2.new(1, 0, 0, 3)
	header.BackgroundColor3 = Config.Palette.Accent
	header.BackgroundTransparency, header.BorderSizePixel = 0.15, 0
	header.Parent = panel

	local heading = Theme.Label(panel, "Title", title, 22, Config.Fonts.Button,
		Config.Palette.Text, zIndex + 1)
	heading.Position = UDim2.new(0, 26, 0, 18)
	heading.Size = UDim2.new(1, -52, 0, 30)

	local body = Instance.new("Frame")
	body.Name, body.ZIndex = "Body", zIndex + 1
	body.Position = UDim2.new(0, 26, 0, 58)
	body.Size = UDim2.new(1, -52, 1, -122)
	body.BackgroundTransparency, body.BorderSizePixel = 1, 0
	body.Parent = panel

	return panel, body
end

return Theme
