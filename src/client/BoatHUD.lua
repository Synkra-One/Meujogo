--!strict
--[[
	BoatHUD
	Interface do barco de fuga (docs/Barco.md), toda feita em código (mesmo
	caminho de ExtractionController), então não precisa de nada no StarterGui.

	  Checklist   canto superior esquerdo, embaixo do rádio: Hélice, Vela,
	              Gasolina, Chave e o estado do motor. Todo mundo na partida
	              vê -- inclusive o Monstro, igual a barra do rádio.
	  Pilotagem   embaixo, só pra quem está sentado no barco: velocidade em
	              NÓS, estado do motor, quanto falta pro limite e as teclas
	              do dispositivo que está sendo usado.
	  Cinema      faixas pretas, "VOCÊ ESCAPOU" e escurecimento no fim da
	              cena de fuga.

	Só desenha: quem manda no estado é o servidor (Attributes do barco).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local BoatRules = require(ReplicatedStorage.Modules.BoatRules)
local GameConfig = require(ReplicatedStorage.Modules.GameConfig)

local CFG = GameConfig.Boat
-- 1 stud ~ 0,28 m (personagem de 5 studs ~ 1,75 m). 1 m/s = 1,944 nós.
local STUD_METERS = 0.28
local KNOTS_PER_STUD = STUD_METERS * 1.944

local ACCENT = Color3.fromRGB(96, 196, 214)
local DONE = Color3.fromRGB(128, 226, 150)
local PENDING = Color3.fromRGB(150, 156, 164)
local WARN = Color3.fromRGB(255, 176, 96)
local DANGER = Color3.fromRGB(255, 104, 88)

local BoatHUD = {}

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local function create(className: string, props: { [string]: any }, parent: Instance?): any
	local instance = Instance.new(className)
	for key, value in props do
		(instance :: any)[key] = value
	end
	if parent then
		instance.Parent = parent
	end
	return instance
end

local function corner(parent: Instance, radius: number)
	create("UICorner", { CornerRadius = UDim.new(0, radius) }, parent)
end

local screen = create("ScreenGui", {
	Name = "BarcoHUD",
	ResetOnSpawn = false,
	IgnoreGuiInset = false,
	DisplayOrder = 6,
	Enabled = true,
}, playerGui)

--------------------------------------------------------------------------------
-- Checklist
--------------------------------------------------------------------------------

local checklist = create("Frame", {
	Name = "Checklist",
	Position = UDim2.fromOffset(10, 80),
	Size = UDim2.fromOffset(260, 128),
	BackgroundColor3 = Color3.fromRGB(12, 16, 20),
	BackgroundTransparency = 0.3,
	BorderSizePixel = 0,
	Visible = false,
}, screen)
corner(checklist, 8)
create("UIStroke", { Color = ACCENT, Thickness = 1, Transparency = 0.45 }, checklist)

create("TextLabel", {
	Position = UDim2.fromOffset(10, 6),
	Size = UDim2.new(1, -20, 0, 18),
	BackgroundTransparency = 1,
	Font = Enum.Font.GothamBold,
	Text = "BARCO DE FUGA",
	TextColor3 = ACCENT,
	TextSize = 13,
	TextXAlignment = Enum.TextXAlignment.Left,
}, checklist)

local rows: { [string]: TextLabel } = {}
for index, step in BoatRules.Steps do
	local column = (index - 1) % 2
	local line = (index - 1) // 2
	rows[step.key] = create("TextLabel", {
		Position = UDim2.new(column * 0.5, 10, 0, 28 + line * 22),
		Size = UDim2.new(0.5, -14, 0, 20),
		BackgroundTransparency = 1,
		Font = Enum.Font.Gotham,
		Text = "○  " .. step.label,
		TextColor3 = PENDING,
		TextSize = 13,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
	}, checklist)
end

local statusLabel = create("TextLabel", {
	Position = UDim2.fromOffset(10, 76),
	Size = UDim2.new(1, -20, 0, 44),
	BackgroundTransparency = 1,
	Font = Enum.Font.GothamMedium,
	Text = "",
	TextColor3 = PENDING,
	TextSize = 13,
	TextWrapped = true,
	TextXAlignment = Enum.TextXAlignment.Left,
	TextYAlignment = Enum.TextYAlignment.Top,
}, checklist)

--------------------------------------------------------------------------------
-- Pilotagem
--------------------------------------------------------------------------------

local drive = create("Frame", {
	Name = "Pilotagem",
	AnchorPoint = Vector2.new(0.5, 1),
	Position = UDim2.new(0.5, 0, 1, -104),
	Size = UDim2.new(0.92, 0, 0, 92),
	BackgroundColor3 = Color3.fromRGB(10, 14, 18),
	BackgroundTransparency = 0.25,
	BorderSizePixel = 0,
	Visible = false,
}, screen)
create("UISizeConstraint", { MaxSize = Vector2.new(460, 92) }, drive)
corner(drive, 10)
create("UIStroke", { Color = ACCENT, Thickness = 1.5, Transparency = 0.35 }, drive)

local speedValue = create("TextLabel", {
	Position = UDim2.fromOffset(14, 8),
	Size = UDim2.fromOffset(96, 46),
	BackgroundTransparency = 1,
	Font = Enum.Font.GothamBlack,
	Text = "0",
	TextColor3 = Color3.fromRGB(240, 246, 248),
	TextSize = 40,
	TextXAlignment = Enum.TextXAlignment.Right,
}, drive)
create("TextLabel", {
	Position = UDim2.fromOffset(114, 26),
	Size = UDim2.fromOffset(40, 20),
	BackgroundTransparency = 1,
	Font = Enum.Font.GothamBold,
	Text = "nós",
	TextColor3 = PENDING,
	TextSize = 14,
	TextXAlignment = Enum.TextXAlignment.Left,
}, drive)

local throttleTrack = create("Frame", {
	Position = UDim2.fromOffset(14, 60),
	Size = UDim2.fromOffset(140, 6),
	BackgroundColor3 = Color3.fromRGB(40, 46, 52),
	BorderSizePixel = 0,
}, drive)
corner(throttleTrack, 3)
local throttleFill = create("Frame", {
	Size = UDim2.fromScale(0, 1),
	BackgroundColor3 = ACCENT,
	BorderSizePixel = 0,
}, throttleTrack)
corner(throttleFill, 3)

local engineChip = create("TextLabel", {
	AnchorPoint = Vector2.new(1, 0),
	Position = UDim2.new(1, -12, 0, 10),
	Size = UDim2.fromOffset(170, 24),
	BackgroundColor3 = Color3.fromRGB(30, 34, 40),
	BorderSizePixel = 0,
	Font = Enum.Font.GothamBold,
	Text = "MOTOR DESLIGADO",
	TextColor3 = PENDING,
	TextSize = 13,
}, drive)
corner(engineChip, 6)

-- Seta pro ponto do limite mais perto (sempre pra fora da ilha), girada
-- pela direção da câmera: pra cima = em frente.
local limitArrow = create("TextLabel", {
	AnchorPoint = Vector2.new(1, 0),
	Position = UDim2.new(1, -12, 0, 36),
	Size = UDim2.fromOffset(22, 22),
	BackgroundTransparency = 1,
	Font = Enum.Font.GothamBlack,
	Text = "▲",
	TextColor3 = Color3.fromRGB(255, 208, 120),
	TextSize = 18,
}, drive)

local limitLabel = create("TextLabel", {
	AnchorPoint = Vector2.new(1, 0),
	Position = UDim2.new(1, -38, 0, 38),
	Size = UDim2.new(1, -206, 0, 20),
	BackgroundTransparency = 1,
	Font = Enum.Font.GothamMedium,
	Text = "",
	TextColor3 = Color3.fromRGB(255, 208, 120),
	TextSize = 13,
	TextXAlignment = Enum.TextXAlignment.Right,
	TextTruncate = Enum.TextTruncate.AtEnd,
}, drive)

local hintLabel = create("TextLabel", {
	Position = UDim2.new(0, 170, 0, 62),
	Size = UDim2.new(1, -182, 0, 22),
	BackgroundTransparency = 1,
	Font = Enum.Font.Gotham,
	Text = "",
	TextColor3 = Color3.fromRGB(176, 182, 190),
	TextSize = 12,
	TextXAlignment = Enum.TextXAlignment.Right,
	TextTruncate = Enum.TextTruncate.AtEnd,
}, drive)

--------------------------------------------------------------------------------
-- Cinema
--------------------------------------------------------------------------------

local cinema = create("ScreenGui", {
	Name = "BarcoCinema",
	ResetOnSpawn = false,
	IgnoreGuiInset = true,
	DisplayOrder = 40,
	Enabled = false,
}, playerGui)
local barTop = create("Frame", {
	Size = UDim2.fromScale(1, 0),
	BackgroundColor3 = Color3.new(0, 0, 0),
	BorderSizePixel = 0,
}, cinema)
local barBottom = create("Frame", {
	AnchorPoint = Vector2.new(0, 1),
	Position = UDim2.fromScale(0, 1),
	Size = UDim2.fromScale(1, 0),
	BackgroundColor3 = Color3.new(0, 0, 0),
	BorderSizePixel = 0,
}, cinema)
local fade = create("Frame", {
	Size = UDim2.fromScale(1, 1),
	BackgroundColor3 = Color3.new(0, 0, 0),
	BackgroundTransparency = 1,
	BorderSizePixel = 0,
	ZIndex = 5,
}, cinema)
local title = create("TextLabel", {
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.44),
	Size = UDim2.new(0.9, 0, 0, 64),
	BackgroundTransparency = 1,
	Font = Enum.Font.GothamBlack,
	Text = "VOCÊ ESCAPOU",
	TextColor3 = Color3.fromRGB(244, 246, 240),
	TextScaled = true,
	TextTransparency = 1,
	ZIndex = 6,
}, cinema)
create("UITextSizeConstraint", { MaxTextSize = 64 }, title)
local subtitle = create("TextLabel", {
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.fromScale(0.5, 0.52),
	Size = UDim2.new(0.9, 0, 0, 26),
	BackgroundTransparency = 1,
	Font = Enum.Font.GothamMedium,
	Text = "",
	TextColor3 = Color3.fromRGB(196, 214, 220),
	TextSize = 20,
	TextTransparency = 1,
	ZIndex = 6,
}, cinema)

--------------------------------------------------------------------------------
-- API
--------------------------------------------------------------------------------

function BoatHUD.SetMatchVisible(visible: boolean)
	checklist.Visible = visible
end

function BoatHUD.UpdateChecklist(model: Model?)
	if not model then
		statusLabel.Text = ""
		return
	end
	for _, step in BoatRules.Steps do
		local row = rows[step.key]
		local done = model:GetAttribute(step.key) == true
		row.Text = (if done then "✓  " else "○  ") .. step.label
		row.TextColor3 = if done then DONE else PENDING
		row.Font = if done then Enum.Font.GothamBold else Enum.Font.Gotham
	end
	local wiring = model:FindFirstChild("FiacaoMotor")
	local text, color
	if model:GetAttribute("Escapando") == true then
		text, color = "Fugindo da ilha!", DONE
	elseif wiring and wiring:GetAttribute("Sabotado") == true then
		text, color = "Fiação do motor cortada -- repare no motor.", DANGER
	elseif model:GetAttribute("Encalhado") == true then
		text, color = "Encalhado -- empurre de volta pra água.", WARN
	elseif model:GetAttribute("MotorLigado") == true then
		text, color = "Motor ligado. Pilote até as boias do limite.", DONE
	elseif model:GetAttribute("DandoPartida") == true then
		text, color = "Dando partida...", WARN
	else
		local missing = BoatRules.Missing({
			HeliceInstalada = model:GetAttribute("HeliceInstalada") == true,
			VelaInstalada = model:GetAttribute("VelaInstalada") == true,
			Abastecido = model:GetAttribute("Abastecido") == true,
			ChaveInserida = model:GetAttribute("ChaveInserida") == true,
		})
		if #missing == 0 then
			text, color = "Pronto: sente no timão e dê a partida.", ACCENT
		else
			text, color = "Falta: " .. table.concat(missing, ", ") .. ".", PENDING
		end
	end
	statusLabel.Text = text
	statusLabel.TextColor3 = color
end

local function controlHints(role: string): string
	local gamepad = UserInputService.GamepadEnabled and UserInputService:GetLastInputType().Name:find("Gamepad") ~= nil
	local touch = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
	if role ~= "Piloto" then
		return if gamepad then "Passageiro · A sair" elseif touch then "Passageiro · pular para sair" else "Passageiro · [Espaço] sair"
	end
	if gamepad then
		return "RT acelera · LT ré · analógico vira · Y motor · A sair"
	elseif touch then
		return "Analógico pilota · botão MOTOR · pular para sair"
	end
	return "W/S acelera · A/D vira · [F] motor · [Espaço] sair"
end

--[[
	UpdateDrive(model, role, speed, throttle, distance, arrowDegrees)
	`distance` = studs até o anel de chegada (<= 0 cruzou). `arrowDegrees`
	= pra onde fica o limite em relação à câmera (0 = em frente, 90 = direita).
]]
function BoatHUD.UpdateDrive(model: Model, role: string, speed: number, throttle: number, distance: number, arrowDegrees: number)
	drive.Visible = true
	speedValue.Text = string.format("%d", math.floor(math.abs(speed) * KNOTS_PER_STUD + 0.5))
	throttleFill.Size = UDim2.fromScale(math.clamp(math.abs(throttle), 0, 1), 1)
	throttleFill.BackgroundColor3 = if throttle < -0.05 then WARN else ACCENT

	local wiring = model:FindFirstChild("FiacaoMotor")
	local text, color = "MOTOR DESLIGADO", PENDING
	if wiring and wiring:GetAttribute("Sabotado") == true then
		text, color = "FIAÇÃO CORTADA", DANGER
	elseif model:GetAttribute("Encalhado") == true then
		text, color = "ENCALHADO", DANGER
	elseif model:GetAttribute("MotorLigado") == true then
		text, color = if model:GetAttribute("Superficie") == "Raso" then "RASPANDO NO FUNDO" else "MOTOR LIGADO",
			if model:GetAttribute("Superficie") == "Raso" then WARN else DONE
	elseif model:GetAttribute("DandoPartida") == true then
		text, color = "DANDO PARTIDA...", WARN
	end
	engineChip.Text = text
	engineChip.TextColor3 = color

	if distance > 0 then
		limitLabel.Text = string.format("Limite do mapa: %d m", math.floor(distance * STUD_METERS + 0.5))
		limitArrow.Visible = true
		limitArrow.Rotation = arrowDegrees
	else
		limitLabel.Text = "Limite cruzado!"
		limitArrow.Visible = false
	end
	hintLabel.Text = controlHints(role)
end

function BoatHUD.HideDrive()
	drive.Visible = false
end

local cinemaToken = 0

--[[
	PlayCinema(duration, subtitle)
	Faixas entram, título aparece na segunda metade e a tela escurece no
	fim. Só pra quem estava a bordo -- os outros veem o barco indo embora.
]]
function BoatHUD.PlayCinema(duration: number, subtitleText: string)
	cinemaToken += 1
	local token = cinemaToken
	cinema.Enabled = true
	drive.Visible = false
	checklist.Visible = false
	fade.BackgroundTransparency = 1
	title.TextTransparency = 1
	subtitle.TextTransparency = 1
	subtitle.Text = subtitleText
	local bars = TweenInfo.new(0.9, Enum.EasingStyle.Quart, Enum.EasingDirection.Out)
	TweenService:Create(barTop, bars, { Size = UDim2.fromScale(1, 0.12) }):Play()
	TweenService:Create(barBottom, bars, { Size = UDim2.fromScale(1, 0.12) }):Play()

	task.delay(math.max(duration * 0.45, 1), function()
		if token ~= cinemaToken then
			return
		end
		local show = TweenInfo.new(1.4, Enum.EasingStyle.Sine, Enum.EasingDirection.Out)
		TweenService:Create(title, show, { TextTransparency = 0 }):Play()
		task.delay(0.5, function()
			if token == cinemaToken then
				TweenService:Create(subtitle, show, { TextTransparency = 0.1 }):Play()
			end
		end)
	end)
	task.delay(math.max(duration - 1.4, 0.5), function()
		if token ~= cinemaToken then
			return
		end
		TweenService:Create(fade, TweenInfo.new(1.4, Enum.EasingStyle.Sine, Enum.EasingDirection.In), { BackgroundTransparency = 0 }):Play()
	end)
end

-- Some com a cena (resultado da partida chegou / personagem trocou).
function BoatHUD.StopCinema()
	if not cinema.Enabled then
		return
	end
	cinemaToken += 1
	local token = cinemaToken
	local out = TweenInfo.new(0.6, Enum.EasingStyle.Sine, Enum.EasingDirection.Out)
	TweenService:Create(fade, out, { BackgroundTransparency = 1 }):Play()
	TweenService:Create(title, out, { TextTransparency = 1 }):Play()
	TweenService:Create(subtitle, out, { TextTransparency = 1 }):Play()
	TweenService:Create(barTop, out, { Size = UDim2.fromScale(1, 0) }):Play()
	TweenService:Create(barBottom, out, { Size = UDim2.fromScale(1, 0) }):Play()
	task.delay(0.7, function()
		if token == cinemaToken then
			cinema.Enabled = false
		end
	end)
end

return BoatHUD
