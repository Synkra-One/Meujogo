--!strict
--[[
	MenuTheme
	Construtores visuais do menu: tudo que é "como uma coisa se parece e como
	ela se move" mora aqui. MenuScreens cuida de "o que aparece quando".

	A paleta, os tempos e as famílias de fonte vêm do MenuConfig. Toda transição passa pelo TweenService.

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

-- Medidas em pixels lógicos. O canvas compensa o UIScale para os cantos
-- continuarem presos à tela real, inclusive em retrato e ultrawide.
function Theme.Layout(viewport: Vector2)
	local factor = math.min(Theme.Scale(viewport), viewport.Y / 540)
	local width, height = viewport.X / factor, viewport.Y / factor
	local portrait = viewport.Y > viewport.X
	local compact = height < 680
	local margin = if portrait then 28 else math.clamp(width * 0.065, 36, 120)
	local logoTop = if compact then 42 else height * 0.14
	return {
		factor = factor, width = width, height = height, portrait = portrait,
		margin = margin, logoTop = logoTop,
		columnTop = if portrait then height * 0.42 else logoTop + (if compact then 112 else 150),
		columnWidth = if portrait then width - margin * 2 else math.clamp(width * 0.29, 310, 390),
		primaryHeight = if compact then 62 else 78,
		buttonHeight = if compact then 44 else 50,
		gap = if compact then 8 else 10,
		footerBottom = 24,
	}
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

	local eyebrow = Theme.Label(holder, "Eyebrow", "UMA ILHA. NENHUMA GARANTIA.", 11,
		Config.Fonts.Button, Config.Palette.Accent, zIndex + 1)
	eyebrow.Position, eyebrow.Size = UDim2.fromOffset(2, 0), UDim2.new(1, 0, 0, 18)

	local title = Theme.Label(holder, "Title", Config.Brand.Title, 58, Config.Fonts.Display,
		Config.Palette.Text, zIndex + 1)
	title.Position, title.Size = UDim2.fromOffset(0, 20), UDim2.new(1, 0, 0, 62)
	title.TextScaled = true
	local limits = Instance.new("UITextSizeConstraint")
	limits.MinTextSize, limits.MaxTextSize = 24, 58
	limits.Parent = title

	local subtitle = Theme.Label(holder, "Subtitle", Config.Brand.Subtitle, 13, Config.Fonts.Body,
		Config.Palette.TextDim, zIndex + 1)
	subtitle.Position, subtitle.Size = UDim2.fromOffset(2, 88), UDim2.new(1, 0, 0, 20)

	return holder
end

--------------------------------------------------------------------------------
-- BOTÃO -- cartões arredondados, ação principal em âmbar e seta animada. Teclado/controle usam o MESMO
-- caminho visual (SetFocus), então "selecionado" é sempre legível.
--------------------------------------------------------------------------------
export type Button = {
	Instance: TextButton,
	SetFocus: (boolean) -> (),
	SetEnabled: (boolean) -> (),
	Destroy: () -> (),
}

function Theme.Button(parent: Instance, name: string, text: string, zIndex: number,
	options: { primary: boolean?, compact: boolean?, subtitle: string?, index: number? }?): Button
	local opts = options or {}
	local palette = Config.Palette
	local primary = opts.primary == true
	local compact = opts.compact == true

	local button = Instance.new("TextButton")
	button.Name, button.ZIndex = name, zIndex
	button.AutoButtonColor = false
	button.BackgroundColor3 = if primary then palette.Accent else palette.Panel
	button.BackgroundTransparency = if primary then 0 else 0.24
	button.BorderSizePixel, button.Text = 0, ""
	button.Size = UDim2.fromScale(1, 1)
	button.Parent = parent
	Theme.Corner(button, if compact then 8 else 12)
	local stroke = Theme.Stroke(button, if primary then palette.AccentBright else palette.PanelStroke,
		1, if primary then 0.2 else 0.65)
	local gradient = Instance.new("UIGradient")
	gradient.Rotation = 20
	gradient.Color = ColorSequence.new(palette.Highlight, if primary then palette.Accent else palette.TextDim)
	gradient.Parent = button

	local inset = if opts.index then 48 else 22
	local ink = if primary then palette.OnAccent else palette.Text
	local label = Theme.Label(button, "Label", text, if primary then 26 elseif compact then 13 else 15,
		Config.Fonts.Button, ink, zIndex + 1)
	label.Position = UDim2.fromOffset(inset, if opts.subtitle then -9 else 0)
	label.Size = UDim2.new(1, -inset - 46, 1, 0)

	if opts.subtitle then
		local subtitle = Theme.Label(button, "Subtitle", opts.subtitle, 10, Config.Fonts.Body, ink, zIndex + 1)
		subtitle.Position, subtitle.Size = UDim2.new(0, inset, 0.5, 10), UDim2.new(1, -inset - 40, 0, 16)
		subtitle.TextTransparency = 0.22
	end
	if opts.index then
		local index = Theme.Label(button, "Index", string.format("%02d", opts.index), 10,
			Config.Fonts.Body, palette.Accent, zIndex + 1)
		index.Position, index.Size = UDim2.fromOffset(18, 0), UDim2.new(0, 24, 1, 0)
	end
	local arrow = Theme.Label(button, "Arrow", "›", if primary then 32 else 23,
		Config.Fonts.Body, ink, zIndex + 1)
	arrow.AnchorPoint = Vector2.new(1, 0.5)
	arrow.Position, arrow.Size = UDim2.new(1, -16, 0.5, 0), UDim2.fromOffset(20, 32)
	arrow.TextXAlignment = Enum.TextXAlignment.Center
	arrow.TextTransparency = if primary then 0 else 0.5

	local enabled, hovered, selected, manualFocus = true, false, false, false
	local function apply(instant: boolean?)
		local info = Theme.Info(if instant then 0 else Config.Motion.ButtonHover,
			Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
		local on = enabled and (hovered or selected or manualFocus)
		Theme.Tween(button, info, {
			BackgroundColor3 = if primary then (if on then palette.AccentBright else palette.Accent) else palette.Panel,
			BackgroundTransparency = if not enabled then 0.65 elseif primary then 0 elseif on then 0.02 else 0.24,
		})
		Theme.Tween(stroke, info, {
			Transparency = if on then 0 else if primary then 0.2 else 0.65,
			Color = if on or primary then palette.AccentBright else palette.PanelStroke,
		})
		Theme.Tween(label, info, {
			TextColor3 = if primary then palette.OnAccent elseif on then palette.Highlight else palette.Text,
			Position = UDim2.fromOffset(inset + (if on then 4 else 0), if opts.subtitle then -9 else 0),
			TextTransparency = if enabled then 0 else 0.45,
		})
		Theme.Tween(arrow, info, {
			Position = UDim2.new(1, if on then -10 else -16, 0.5, 0),
			TextTransparency = if on or primary then 0 else 0.5,
		})
	end
	local connections: { RBXScriptConnection } = {
		button.MouseEnter:Connect(function() hovered = true; apply() end),
		button.MouseLeave:Connect(function() hovered = false; apply() end),
		button.SelectionGained:Connect(function() selected = true; apply() end),
		button.SelectionLost:Connect(function() selected = false; apply() end),
	}
	return {
		Instance = button,
		SetFocus = function(value: boolean) manualFocus = value; apply() end,
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
-- PAINEL -- caixa usada pelos submenus ("Em breve", créditos, etc).
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
	Theme.Corner(panel, 16)
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
