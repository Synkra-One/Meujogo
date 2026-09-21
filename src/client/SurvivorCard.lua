--!strict
-- Compact roster tile. State is supplied by the controller; no remotes here.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Modules.SurvivorSelectionConfig)
local Portrait = require(script.Parent.SurvivorPortrait)
local UI = require(script.Parent.SurvivorSelectionTheme)
local Card = {}

function Card.Create(parent: Instance, character: any, order: number): any
	local color = Config.GetPortrait(character.Id).Accent
	local root = UI.Create("TextButton", parent, {
		Name = character.Id, LayoutOrder = order, Text = "", AutoButtonColor = false,
		Size = UDim2.fromOffset(104, 100), BackgroundColor3 = UI.Panel,
		BorderSizePixel = 0, Selectable = true, ClipsDescendants = false,
	})
	UI.Corner(root, 5)
	local scale = UI.Create("UIScale", root, {})
	local stroke = UI.Create("UIStroke", root, { Color = color, Transparency = 0.7, Thickness = 1 })
	local holder = UI.Frame(root, "Icon")
	holder.Size = UDim2.new(1, -8, 1, -26)
	holder.Position = UDim2.fromOffset(4, 0)
	Portrait.Create(holder, character.Id)
	local name = UI.Label(root, "DisplayName", string.match(character.Nome, "^%S+") or character.Nome, 11, true)
	name.Position = UDim2.new(0, 4, 1, -23)
	name.Size = UDim2.new(1, -8, 0, 20)
	name.TextXAlignment = Enum.TextXAlignment.Center
	local accent = UI.Create("Frame", root, {
		Name = "SelectedAccent", Position = UDim2.new(0, 0, 1, -3),
		Size = UDim2.new(1, 0, 0, 3), BackgroundColor3 = color, BorderSizePixel = 0,
		BackgroundTransparency = 1,
	})
	local status = UI.Label(root, "Status", "", 9, true)
	status.Size = UDim2.new(1, -4, 0, 18)
	status.Position = UDim2.fromOffset(2, 2)
	status.TextXAlignment = Enum.TextXAlignment.Center
	status.ZIndex = 3
	status.BackgroundColor3 = UI.Panel
	status.BackgroundTransparency = 0.15
	status.Visible = false
	return { Root = root, Stroke = stroke, Scale = scale, Status = status, Accent = accent,
		CharacterId = character.Id, Color = color, Tween = nil }
end

function Card.SetState(card: any, state: string, selected: boolean, hovered: boolean?, confirmed: boolean?)
	local available = state == "Available"
	card.Root.Active = available and not confirmed
	-- Unavailable tiles stay focusable so their information remains accessible.
	card.Root.Selectable = not confirmed
	card.Stroke.Color = if available then card.Color else UI.Muted
	card.Stroke.Thickness = if selected or hovered then 2 else 1
	card.Stroke.Transparency = if selected then 0 elseif hovered then 0.15 else 0.7
	card.Accent.BackgroundTransparency = if selected then 0 else 1
	card.Status.Visible = selected or not available
	card.Status.Text = if not available then ({ Taken = "RESERVADO", Locked = "BLOQUEADO", Unavailable = "INDISPONÍVEL" })[state] or state
		elseif confirmed then "CONFIRMADO" else "SELECIONADO"
	card.Status.TextColor3 = if selected and available then card.Color else UI.Muted
	card.Root.BackgroundColor3 = if selected then card.Color:Lerp(UI.Panel, 0.8) else UI.Panel
	if card.Tween then card.Tween:Cancel() end
	card.Tween = UI.Tween(card.Scale, { Scale = if hovered then 1.055 elseif selected then 1.025 else 1 })
end
return Card
