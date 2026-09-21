--!strict
-- Reusable character information, attribute bars and Q/E power cards.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Data = require(ReplicatedStorage.Modules.CharacterData)
local Registry = require(ReplicatedStorage.Modules.AssetRegistry)
local Config = require(ReplicatedStorage.Modules.SurvivorSelectionConfig)
local Assets = require(script.Parent.SurvivorSelectionAssets)
local UI = require(script.Parent.SurvivorSelectionTheme)
local Details = {}

function Details.Create(parent: Instance): any
	local root = UI.Create("ScrollingFrame", parent, {
		Name = "CharacterDetails", BackgroundColor3 = UI.Panel, BackgroundTransparency = 0.2,
		BorderSizePixel = 0, ScrollBarThickness = 3, ScrollBarImageColor3 = UI.Accent,
		CanvasSize = UDim2.new(), AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollingDirection = Enum.ScrollingDirection.Y, Selectable = false,
	})
	UI.Corner(root, 8)
	UI.Create("UIPadding", root, { PaddingLeft = UDim.new(0, 16), PaddingRight = UDim.new(0, 18),
		PaddingTop = UDim.new(0, 12), PaddingBottom = UDim.new(0, 14) })
	UI.Create("UIListLayout", root, { SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 7) })
	local function text(name: string, value: string, height: number, size: number, order: number, bold: boolean?): TextLabel
		local label = UI.Label(root, name, value, size, bold)
		label.Size = UDim2.new(1, 0, 0, height)
		label.AutomaticSize = Enum.AutomaticSize.Y
		label.TextWrapped = true
		label.LayoutOrder = order
		return label
	end
	local mode = text("PreviewState", "PRÉVIA DO SOBREVIVENTE", 13, 10, 1, true)
	mode.TextColor3 = UI.Muted
	local name = text("FullName", "", 28, 24, 2, true)
	local role = text("Role", "", 16, 12, 3, true)
	local description = text("Description", "", 28, 12, 4)
	description.TextColor3 = UI.Muted
	local powers = {}
	for slot = 1, 2 do
		local box = UI.Frame(root, "Power" .. slot)
		box.LayoutOrder = 4 + slot
		box.Size = UDim2.new(1, 0, 0, 80)
		box.AutomaticSize = Enum.AutomaticSize.Y
		box.BackgroundTransparency = 0.25
		box.BackgroundColor3 = Color3.fromRGB(27, 42, 48)
		UI.Corner(box, 5)
		local key = UI.Label(box, "Key", if slot == 1 then "Q" else "E", 18, true)
		key.Position = UDim2.fromOffset(10, 8)
		key.Size = UDim2.fromOffset(28, 25)
		key.TextXAlignment = Enum.TextXAlignment.Center
		local icon = UI.Create("ImageLabel", box, { Name = "Icon", BackgroundTransparency = 1,
			Position = UDim2.fromOffset(12, 40), Size = UDim2.fromOffset(24, 24), ScaleType = Enum.ScaleType.Fit })
		local glyph = UI.Label(box, "PlaceholderIcon", if slot == 1 then "◇" else "◈", 24, true)
		glyph.Position, glyph.Size = icon.Position, icon.Size
		glyph.TextXAlignment = Enum.TextXAlignment.Center
		local title = UI.Label(box, "PowerName", "", 12, true)
		title.Position = UDim2.fromOffset(48, 8)
		title.Size = UDim2.new(1, -58, 0, 16)
		title.TextWrapped = true
		title.AutomaticSize = Enum.AutomaticSize.Y
		local cooldown = UI.Label(box, "Cooldown", "", 10)
		cooldown.Position = UDim2.fromOffset(48, 38)
		cooldown.Size = UDim2.new(1, -58, 0, 14)
		cooldown.TextColor3 = UI.Muted
		local desc = UI.Label(box, "Description", "", 11)
		desc.Position = UDim2.fromOffset(48, 55)
		desc.Size = UDim2.new(1, -58, 0, 28)
		desc.AutomaticSize = Enum.AutomaticSize.Y
		desc.TextWrapped = true
		desc.TextYAlignment = Enum.TextYAlignment.Top
		UI.Create("UIPadding", box, { PaddingBottom = UDim.new(0, 8) })
		powers[slot] = { Title = title, Cooldown = cooldown, Description = desc, Icon = icon, Glyph = glyph, Key = key }
	end
	text("StatsCaption", "ATRIBUTOS", 18, 10, 7, true).TextColor3 = UI.Muted
	local stats = {}
	for index, id in Data.StatOrder do
		local row = UI.Frame(root, id)
		row.LayoutOrder = 7 + index
		row.Size = UDim2.new(1, 0, 0, 18)
		local label = UI.Label(row, "Label", Data.StatLabels[id], 11)
		label.Size = UDim2.new(0.38, 0, 1, 0)
		label.TextColor3 = UI.Muted
		local track = UI.Frame(row, "Track")
		track.BackgroundColor3 = Color3.fromRGB(49, 64, 68)
		track.BackgroundTransparency = 0.2
		track.Position = UDim2.new(0.4, 0, 0.5, -2)
		track.Size = UDim2.new(0.6, -34, 0, 4)
		local bar = UI.Frame(track, "Fill")
		bar.BackgroundTransparency = 0
		bar.Size = UDim2.fromScale(0, 1)
		local value = UI.Label(row, "Value", "", 11, true)
		value.Position = UDim2.new(1, -30, 0, 0)
		value.Size = UDim2.new(0, 30, 1, 0)
		value.TextXAlignment = Enum.TextXAlignment.Right
		stats[id] = { Bar = bar, Value = value }
	end
	local passive = text("Passive", "", 20, 11, 16)
	passive.TextColor3 = Color3.fromRGB(213, 196, 148)
	return { Root = root, Name = name, Role = role, Description = description, Mode = mode,
		Powers = powers, Stats = stats, Passive = passive, Id = nil }
end

function Details.Update(view: any, character: any, mode: string)
	view.Mode.Text = mode
	if view.Id == character.Id then return end
	view.Id = character.Id
	local color = Config.GetPortrait(character.Id).Accent
	view.Name.Text = character.Nome
	view.Role.Text = string.upper(character.Apelido)
	view.Role.TextColor3 = color
	view.Description.Text = character.Description or ""
	view.Passive.Text = if character.PassivaUnica then "PASSIVA  ·  " .. character.PassivaUnica else ""
	view.Passive.Visible = character.PassivaUnica ~= nil
	for id, row in view.Stats do
		local value = character.Stats[id] or 0
		row.Value.Text = tostring(value)
		row.Bar.BackgroundColor3 = color
		UI.Tween(row.Bar, { Size = UDim2.fromScale(math.clamp(value / 100, 0, 1), 1) }, 0.25)
	end
	for slot, power in view.Powers do
		local id = character["PowerId" .. slot]
		local entry = id and Registry.SurvivorPowers[id]
		power.Title.Text = if entry then entry.Label else character["PowerName" .. slot] or "Sem poder"
		power.Cooldown.Text = tostring(character["PowerCooldown" .. slot] or 0) .. "s de recarga"
		power.Description.Text = character["PowerDescription" .. slot] or ""
		power.Key.TextColor3 = color
		power.Glyph.TextColor3 = color
		power.Icon.Image = Assets.Content("AbilityIcons", character["PowerIcon" .. slot] or (entry and entry.Icon))
		power.Icon.Visible = power.Icon.Image ~= ""
		power.Glyph.Visible = not power.Icon.Visible
	end
end
return Details
