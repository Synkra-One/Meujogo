--!strict
local HUD = {}
HUD.__index = HUD
local WHITE = Color3.fromRGB(238, 242, 247)
local ACCENT = Color3.fromRGB(232, 180, 86)

local function label(parent: Instance, text: string, size: number, position: UDim2, dimensions: UDim2): TextLabel
	local item = Instance.new("TextLabel")
	item.BackgroundTransparency = 1
	item.Text, item.TextSize, item.TextColor3 = text, size, WHITE
	item.Font = Enum.Font.GothamMedium
	item.TextXAlignment = Enum.TextXAlignment.Left
	item.Position, item.Size = position, dimensions
	item.Parent = parent
	return item
end

function HUD.new(parent: PlayerGui)
	local self = setmetatable({}, HUD)
	local gui = Instance.new("ScreenGui")
	gui.Name, gui.ResetOnSpawn, gui.IgnoreGuiInset = "PistolHUD", false, true
	gui.DisplayOrder, gui.Enabled = 8, false
	gui.Parent = parent
	self.Gui = gui
	local panel = Instance.new("Frame")
	panel.Name = "Magazine"
	panel.AnchorPoint = Vector2.new(1, 1)
	panel.Position, panel.Size = UDim2.new(1, -22, 1, -26), UDim2.fromOffset(218, 112)
	panel.BackgroundColor3, panel.BackgroundTransparency = Color3.fromRGB(16, 21, 27), 0.12
	panel.BorderSizePixel = 0
	panel.Parent = gui
	local corner = Instance.new("UICorner")
	corner.CornerRadius, corner.Parent = UDim.new(0, 8), panel
	local stroke = Instance.new("UIStroke")
	stroke.Color, stroke.Transparency, stroke.Parent = ACCENT, 0.65, panel
	self.Name = label(panel, "GLOCK 17  /  9 mm", 12, UDim2.fromOffset(14, 10), UDim2.fromOffset(190, 18))
	self.Count = label(panel, "17 / 00", 34, UDim2.fromOffset(14, 30), UDim2.fromOffset(190, 40))
	self.Count.Font = Enum.Font.GothamBold
	self.Status = label(panel, "SEMIAUTOMÁTICA", 10, UDim2.fromOffset(14, 79), UDim2.fromOffset(194, 20))
	self.Status.TextColor3 = ACCENT
	local bar = Instance.new("Frame")
	bar.BorderSizePixel, bar.BackgroundColor3 = 0, Color3.fromRGB(51, 57, 63)
	bar.Position, bar.Size, bar.Parent = UDim2.fromOffset(14, 73), UDim2.fromOffset(190, 2), panel
	self.Progress = Instance.new("Frame")
	self.Progress.BorderSizePixel, self.Progress.BackgroundColor3 = 0, ACCENT
	self.Progress.Size, self.Progress.Parent = UDim2.fromScale(0, 1), bar
	self.Hints = label(gui, "BOTÃO DIREITO  Mirar     R  Recarregar     G  Largar", 11,
		UDim2.new(1, -440, 1, -22), UDim2.fromOffset(418, 17))
	self.Hints.TextXAlignment = Enum.TextXAlignment.Right
	self.Crosshair = Instance.new("Frame")
	self.Crosshair.Name, self.Crosshair.BackgroundTransparency = "Crosshair", 1
	self.Crosshair.Size, self.Crosshair.Parent = UDim2.fromOffset(1, 1), gui
	self.Arms = {}
	for i = 1, 4 do
		local arm = Instance.new("Frame")
		arm.AnchorPoint = Vector2.new(0.5, 0.5)
		arm.BackgroundColor3, arm.BorderSizePixel = WHITE, 0
		arm.Size = if i <= 2 then UDim2.fromOffset(2, 6) else UDim2.fromOffset(6, 2)
		arm.Parent = self.Crosshair
		table.insert(self.Arms, arm)
	end
	self.Hit = label(self.Crosshair, "×", 30, UDim2.fromOffset(-18, -18), UDim2.fromOffset(36, 36))
	self.Hit.Font, self.Hit.TextXAlignment = Enum.Font.GothamBold, Enum.TextXAlignment.Center
	self.Hit.Visible = false
	self.HitUntil = 0
	self.Feed = label(gui, "", 13, UDim2.new(0.5, -160, 0.67, 0), UDim2.fromOffset(320, 25))
	self.Feed.TextXAlignment = Enum.TextXAlignment.Center
	self.FeedUntil = 0
	self.Buttons = {}
	for i, text in { "ATIRAR", "MIRAR", "RECARREGAR" } do
		local button = Instance.new("TextButton")
		button.Name, button.Text = text, text
		button.TextSize, button.Font, button.TextColor3 = 12, Enum.Font.GothamBold, WHITE
		button.BackgroundColor3, button.BackgroundTransparency = Color3.fromRGB(24, 30, 37), 0.12
		button.Size = UDim2.fromOffset(106, 44)
		button.Position = UDim2.new(1, -128, 0.34, (i - 1) * 51)
		button.Parent = gui
		local rounding = Instance.new("UICorner")
		rounding.CornerRadius, rounding.Parent = UDim.new(0, 8), button
		table.insert(self.Buttons, button)
	end
	return self
end

function HUD:Update(position: Vector2, magazine: number, reserve: number, aiming: boolean, kick: number,
	reloading: boolean, progress: number, training: boolean, touch: boolean, blocked: boolean)
	self.Crosshair.Position = UDim2.fromOffset(position.X, position.Y)
	self.Crosshair.Visible = not blocked
	local gap = (if aiming then 5 else 10) + kick * 5
	self.Arms[1].Position, self.Arms[2].Position = UDim2.fromOffset(0, -gap), UDim2.fromOffset(0, gap)
	self.Arms[3].Position, self.Arms[4].Position = UDim2.fromOffset(-gap, 0), UDim2.fromOffset(gap, 0)
	self.Count.Text = string.format("%02d / %02d", magazine, reserve)
	self.Count.TextColor3 = if magazine == 0 then Color3.fromRGB(242, 102, 91) else WHITE
	self.Status.Text = if reloading then "RECARREGANDO..." elseif magazine == 0 then
		(if reserve > 0 then "RECARREGUE A PISTOLA" else "SEM MUNIÇÃO — PEGUE UMA CAIXA")
		elseif training then "TREINO • SOMENTE ALVOS" else "SEMIAUTOMÁTICA"
	self.Progress.Size = UDim2.fromScale(if reloading then math.clamp(progress, 0, 1) else 0, 1)
	self.Hit.Visible = os.clock() < self.HitUntil
	self.Feed.Visible = os.clock() < self.FeedUntil
	self.Hints.Visible = not touch
	for _, button in self.Buttons do button.Visible = touch and not blocked end
end

function HUD:Hitmarker(kind: string)
	self.HitUntil = os.clock() + 0.18
	self.Hit.TextColor3 = if kind == "Head" or kind == "HeadArmor" then ACCENT else WHITE
end

function HUD:Message(text: string)
	self.Feed.Text, self.FeedUntil = text, os.clock() + 2.5
end

return HUD
