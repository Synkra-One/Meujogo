--!strict
--[[
	StaminaHUD
	As DUAS pontas de cliente do fôlego (a lógica é toda do servidor, em
	server/StaminaSystem.lua):

	  1. INTENÇÃO -- avisa o servidor quando você segura/solta Shift
	     (Remotes.SprintIntent). É só a intenção: o servidor confere a
	     velocidade real do personagem antes de gastar fôlego, então mentir
	     aqui não dá vantagem nenhuma.

	  2. BARRA -- desenha o fôlego lendo o Attribute "Stamina" do Player, que
	     o servidor escreve e o Roblox replica sozinho. Nenhum remote de volta.

	Substituiu o StaminaSystem client-side do pacote de movimento, que era
	100% cliente (dava pra editar o valor e correr pra sempre).

	A barra some sozinha quando o fôlego está cheio e você não está correndo,
	pra não poluir a tela.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local ContextActionService = game:GetService("ContextActionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Remotes = require(ReplicatedStorage.Modules.Remotes)

local LocalPlayer = Players.LocalPlayer
local playerGui = LocalPlayer:WaitForChild("PlayerGui")

local BAR_WIDTH = 210
local BAR_HEIGHT = 12

--------------------------------------------------------------------------------
-- Intenção de correr
--------------------------------------------------------------------------------

local holding = false

local function setHolding(value: boolean)
	if value == holding then
		return
	end
	holding = value
	Remotes.SprintIntent:FireServer(value)
end

-- Teclado: as duas Shift. Não uso Sink -- o script Crouching do pacote também
-- escuta Shift pra entrar no estado de corrida, e sinkar quebraria ele.
UserInputService.InputBegan:Connect(function(input: InputObject, gameProcessed: boolean)
	if gameProcessed then
		return
	end
	if input.KeyCode == Enum.KeyCode.LeftShift or input.KeyCode == Enum.KeyCode.RightShift then
		setHolding(true)
	end
end)
UserInputService.InputEnded:Connect(function(input: InputObject)
	if input.KeyCode == Enum.KeyCode.LeftShift or input.KeyCode == Enum.KeyCode.RightShift then
		setHolding(false)
	end
end)

-- Mobile/gamepad: botão de correr na tela (só aparece em touch) + L3.
ContextActionService:BindAction("SprintIntent", function(_, state: Enum.UserInputState)
	if state == Enum.UserInputState.Begin then
		setHolding(true)
	elseif state == Enum.UserInputState.End or state == Enum.UserInputState.Cancel then
		setHolding(false)
	end
	return Enum.ContextActionResult.Pass
end, UserInputService.TouchEnabled, Enum.KeyCode.ButtonL3)
if UserInputService.TouchEnabled then
	-- SetTitle só existe quando a action criou botão de toque.
	ContextActionService:SetTitle("SprintIntent", "Correr")
end

-- Soltou o personagem (morreu, respawnou): zera a intenção pra não ficar
-- "correndo" preso do outro lado.
LocalPlayer.CharacterRemoving:Connect(function()
	setHolding(false)
end)

--------------------------------------------------------------------------------
-- Barra
--------------------------------------------------------------------------------

local gui = Instance.new("ScreenGui")
gui.Name = "StaminaHUD"
gui.ResetOnSpawn = false
gui.DisplayOrder = 6
gui.Parent = playerGui

local holder = Instance.new("Frame")
holder.AnchorPoint = Vector2.new(0, 1)
-- Acima da hotbar (14 da borda + 64 do slot + folga) e da barra de vida do pacote.
holder.Position = UDim2.new(0, 14, 1, -120)
holder.Size = UDim2.fromOffset(BAR_WIDTH, BAR_HEIGHT + 16)
holder.BackgroundTransparency = 1
holder.Parent = gui

local label = Instance.new("TextLabel")
label.Size = UDim2.fromOffset(BAR_WIDTH, 14)
label.BackgroundTransparency = 1
label.Font = Enum.Font.GothamBold
label.TextSize = 11
label.TextColor3 = Color3.fromRGB(225, 225, 232)
label.TextStrokeTransparency = 0.6
label.TextXAlignment = Enum.TextXAlignment.Left
label.Text = "FÔLEGO"
label.Parent = holder

local track = Instance.new("Frame")
track.Position = UDim2.fromOffset(0, 16)
track.Size = UDim2.fromOffset(BAR_WIDTH, BAR_HEIGHT)
track.BackgroundColor3 = Color3.fromRGB(16, 17, 21)
track.BackgroundTransparency = 0.25
track.BorderSizePixel = 0
track.Parent = holder
local trackCorner = Instance.new("UICorner")
trackCorner.CornerRadius = UDim.new(1, 0)
trackCorner.Parent = track

local fill = Instance.new("Frame")
fill.Size = UDim2.fromScale(1, 1)
fill.BackgroundColor3 = Color3.fromRGB(235, 195, 90)
fill.BorderSizePixel = 0
fill.Parent = track
local fillCorner = Instance.new("UICorner")
fillCorner.CornerRadius = UDim.new(1, 0)
fillCorner.Parent = fill

local shown = 1

RunService.RenderStepped:Connect(function(dt: number)
	local raw = LocalPlayer:GetAttribute("Stamina")
	local target = math.clamp((if type(raw) == "number" then raw else 100) / 100, 0, 1)
	local exhausted = LocalPlayer:GetAttribute("StaminaExausto") == true

	-- Suaviza (o servidor manda a 10 Hz; a barra roda a 60).
	shown += (target - shown) * math.min(1, dt * 14)
	fill.Size = UDim2.fromScale(math.max(shown, 0), 1)

	fill.BackgroundColor3 = if exhausted
		then Color3.fromRGB(215, 75, 65)
		elseif shown < 0.3 then Color3.fromRGB(230, 140, 70)
		else Color3.fromRGB(235, 195, 90)

	-- Some quando está cheio e parado; volta assim que gasta.
	local full = shown >= 0.995 and not holding
	local alpha = if full then 0.75 else 0
	track.BackgroundTransparency = 0.25 + alpha * 0.7
	fill.BackgroundTransparency = alpha
	label.TextTransparency = alpha
	label.Text = if exhausted then "FÔLEGO (exausto)" else "FÔLEGO"
end)
