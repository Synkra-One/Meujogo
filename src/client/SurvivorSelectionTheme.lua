--!strict
-- Shared UI primitives. No character data or network state lives here.
local TweenService = game:GetService("TweenService")
local Theme = {}
Theme.Text = Color3.fromRGB(233, 240, 238)
Theme.Muted = Color3.fromRGB(148, 168, 170)
Theme.Accent = Color3.fromRGB(107, 211, 200)
Theme.Panel = Color3.fromRGB(13, 24, 29)

function Theme.Create(class: string, parent: Instance?, properties: { [string]: any }): any
	local item = Instance.new(class)
	for key, value in properties do (item :: any)[key] = value end
	item.Parent = parent
	return item
end

function Theme.Frame(parent: Instance, name: string): Frame
	return Theme.Create("Frame", parent, {
		Name = name, BackgroundTransparency = 1, BorderSizePixel = 0,
	})
end

function Theme.Label(parent: Instance, name: string, text: string, size: number, bold: boolean?): TextLabel
	return Theme.Create("TextLabel", parent, {
		Name = name, Text = text, TextSize = size, BackgroundTransparency = 1,
		BorderSizePixel = 0, TextColor3 = Theme.Text,
		Font = if bold then Enum.Font.GothamBold else Enum.Font.Gotham,
		TextXAlignment = Enum.TextXAlignment.Left,
	})
end

function Theme.Tween(item: Instance, properties: { [string]: any }, duration: number?): Tween
	local tween = TweenService:Create(item, TweenInfo.new(duration or 0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), properties)
	tween:Play()
	return tween
end

function Theme.Corner(item: Instance, radius: number)
	Theme.Create("UICorner", item, { CornerRadius = UDim.new(0, radius) })
end

return Theme
