--!strict
local Config = require(game:GetService("ReplicatedStorage").Modules.FlashlightConfig)
local HUD = {}
HUD.__index = HUD

local function frame(parent: Instance, position: UDim2, size: UDim2, color: Color3): Frame
	local item = Instance.new("Frame")
	item.BorderSizePixel, item.Position, item.Size = 0, position, size
	item.BackgroundColor3, item.Parent = color, parent
	return item
end

function HUD.new(parent: PlayerGui)
	local gui = Instance.new("ScreenGui")
	gui.Name, gui.ResetOnSpawn, gui.DisplayOrder, gui.Enabled = "FlashlightHUD", false, 9, false
	gui.IgnoreGuiInset = true
	gui.Parent = parent
	-- O painel antigo da esquerda foi absorvido pelo novo HUD circular. A mira
	-- central continua sendo controlada por este modulo.
	local panel = frame(gui, UDim2.new(0, 14, 1, -96), UDim2.fromOffset(160, 46), Color3.fromRGB(17, 20, 23))
	panel.AnchorPoint, panel.BackgroundTransparency = Vector2.new(0, 1), 0.2
	panel.Visible = false
	local corner = Instance.new("UICorner")
	corner.CornerRadius, corner.Parent = UDim.new(0, 5), panel
	local body = frame(panel, UDim2.fromOffset(12, 15), UDim2.fromOffset(25, 14), Color3.fromRGB(216, 225, 219))
	frame(body, UDim2.fromOffset(25, 4), UDim2.fromOffset(3, 6), body.BackgroundColor3)
	local inside = frame(body, UDim2.fromOffset(2, 2), UDim2.fromOffset(21, 10), Color3.fromRGB(24, 29, 29))
	local fill = frame(inside, UDim2.fromOffset(1, 1), UDim2.new(1, -2, 1, -2), Color3.fromRGB(165, 212, 187))
	local count = Instance.new("TextLabel")
	count.Position, count.Size = UDim2.fromOffset(47, 4), UDim2.fromOffset(100, 23)
	count.BackgroundTransparency, count.Font, count.TextSize = 1, Enum.Font.GothamMedium, 18
	count.TextXAlignment, count.Parent = Enum.TextXAlignment.Left, panel
	local status = count:Clone()
	status.Position, status.Size, status.TextSize = UDim2.fromOffset(47, 26), UDim2.fromOffset(105, 14), 9
	status.Parent = panel
	local dot = frame(gui, UDim2.fromScale(0.5, 0.5), UDim2.fromOffset(3, 3), Color3.fromRGB(229, 237, 227))
	dot.AnchorPoint = Vector2.new(0.5, 0.5)
	local burst = count:Clone()
	burst.Name, burst.AnchorPoint, burst.Position = "BurstStatus", Vector2.new(0.5, 0), UDim2.fromScale(0.5, 0.61)
	burst.Size, burst.TextSize, burst.TextXAlignment = UDim2.fromOffset(340, 24), 12, Enum.TextXAlignment.Center
	burst.Parent = gui
	local feedback = burst:Clone()
	feedback.Name, feedback.Position, feedback.Parent = "BurstFeedback", UDim2.fromScale(0.5, 0.57), gui
	feedback.Text = ""
	local cooldown = frame(gui, UDim2.fromScale(0.5, 0.65), UDim2.fromOffset(150, 3), Color3.fromRGB(230, 239, 213))
	cooldown.AnchorPoint = Vector2.new(0.5, 0)
	return setmetatable({ Gui = gui, Count = count, Status = status, Fill = fill, Dot = dot,
		Burst = burst, Feedback = feedback, Cooldown = cooldown, feedbackUntil = 0 }, HUD)
end

function HUD:BurstFeedback(result: string, accepted: boolean)
	local text = { Hit = "ACERTOU · monstro ofuscado", Miss = "SEM ACERTO", Battery = "BATERIA INSUFICIENTE",
		Cooldown = "CLARÃO RECARREGANDO", Range = "MONSTRO FORA DO ALCANCE", Blocked = "CLARÃO INDISPONÍVEL",
		Aim = "AJUSTE A MIRA", Obstructed = "LANTERNA OBSTRUÍDA" }
	self.Feedback.Text = (text :: any)[result] or "CLARÃO INDISPONÍVEL"
	if accepted then self.Feedback.Text ..= string.format("  −%g%%", Config.FlashBurstCost) end
	self.Feedback.TextColor3 = if result == "Hit" then Color3.fromRGB(237, 248, 205) else Color3.fromRGB(227, 173, 128)
	self.feedbackUntil = os.clock() + 1.8
end

function HUD:Update(visible: boolean, battery: number, enabled: boolean, now: number, cooldown: number?)
	self.Gui.Enabled = visible
	if not visible then return end
	local fraction = math.clamp(battery / Config.BatteryMax, 0, 1)
	local color = if fraction <= 0.2 then Color3.fromRGB(234, 105, 99)
		elseif fraction <= 0.5 then Color3.fromRGB(222, 189, 106) else Color3.fromRGB(170, 218, 194)
	self.Count.Text = string.format("%d%%", math.ceil(fraction * 100))
	self.Count.TextColor3, self.Fill.BackgroundColor3 = color, color
	self.Fill.Size = UDim2.new(fraction, -2 * fraction, 1, -2)
	self.Status.Text = if enabled then "LIGADA" else "DESLIGADA"
	self.Status.TextColor3 = Color3.fromRGB(174, 184, 182)
	self.Count.TextTransparency = if fraction > 0 and fraction <= 0.1 then 0.12 + 0.12 * math.sin(now * 4) else 0
	self.Dot.Visible = enabled
	local remaining = cooldown or 0
	self.Burst.Text = if remaining > 0 then string.format("CLARÃO · %.1fs", remaining)
		elseif battery < Config.FlashBurstCost then string.format("CLARÃO · precisa de %g%%", Config.FlashBurstCost)
		else string.format("%s / %s / TOQUE · CLARÃO · %g%%", Config.FlashBurstKey,
			string.gsub(Config.FlashBurstGamepadKey, "Button", ""), Config.FlashBurstCost)
	self.Burst.TextColor3 = if remaining > 0 or battery < Config.FlashBurstCost
		then Color3.fromRGB(160, 165, 167) else Color3.fromRGB(230, 239, 213)
	self.Cooldown.Visible = remaining > 0
	self.Cooldown.Size = UDim2.fromOffset(150 * (1 - math.clamp(remaining / Config.FlashBurstCooldown, 0, 1)), 3)
	self.Feedback.Visible = now < self.feedbackUntil
end

return HUD
