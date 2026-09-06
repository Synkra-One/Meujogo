--!strict
--[[
	RoleRevealController
	O "sorteio" no começo da partida: uma tela cheia que embaralha os papéis
	feito caça-níquel, desacelera e trava no SEU papel com um flash, cor e som
	-- depois mostra o objetivo em uma linha e some sozinha.

	Substitui o antigo OnboardingController/OnboardingHUD (era um cartão de
	texto estático). Toda a UI é construída aqui em código pra ter controle
	fino da animação; nada de model.json.

	GATILHO: Remotes.RoundStateChanged com a 1ª fase (GameConfig.PhaseOrder[1],
	"Queda"). Espera o Attribute "Role" do jogador local chegar (o servidor
	sorteia em RoleAssignment, replica sozinho) e então roda a sequência.
	Reaparece toda rodada -- o papel muda entre partidas.

	SEQUÊNCIA (~7s):
	  0.0s  overlay escurece
	  0.4s  começa a embaralhar "SOBREVIVENTE / MONSTRO / ESPIÃO" (tick a cada troca)
	  ~3s   trava no papel real: flash branco, punch de escala, cor do papel, som
	  ~3.3s aparece "VOCÊ É O MONSTRO" + objetivo em 1 linha
	  ~6s   fade out
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage.Modules.GameConfig)
local Remotes = require(ReplicatedStorage.Modules.Remotes)

local LocalPlayer = Players.LocalPlayer
local playerGui = LocalPlayer:WaitForChild("PlayerGui")

local ROLE_WAIT_TIMEOUT = 4

-- Ordem em que o caça-níquel roda (não é a probabilidade -- é só visual).
local WHEEL = {
	GameConfig.Roles.Survivor,
	GameConfig.Roles.Monster,
	GameConfig.Roles.Spy,
}

local ROLE_INFO: { [string]: { Label: string, Title: string, Color: Color3, Objective: string } } = {
	[GameConfig.Roles.Survivor] = {
		Label = "SOBREVIVENTE",
		Title = "VOCÊ É SOBREVIVENTE",
		Color = Color3.fromRGB(80, 195, 165),
		Objective = "Fuja da ilha: monte o Rádio ou a Jangada antes que o tempo acabe.",
	},
	[GameConfig.Roles.Monster] = {
		Label = "MONSTRO",
		Title = "VOCÊ É O MONSTRO",
		Color = Color3.fromRGB(210, 55, 45),
		Objective = "Cace e elimine todos os Sobreviventes. Cuidado com a luz.",
	},
	[GameConfig.Roles.Spy] = {
		Label = "ESPIÃO",
		Title = "VOCÊ É O ESPIÃO",
		Color = Color3.fromRGB(165, 100, 210),
		Objective = "Finja ser Sobrevivente, sabote as fugas e use sua habilidade letal.",
	},
}

local TICK_SOUND = "rbxasset://sounds/electronicpingshort.wav"
local REVEAL_SOUND = "rbxasset://sounds/impact_water.mp3"

-- Trava o movimento durante o sorteio (mais dramático e evita cair no mar /
-- sair da caverna sem ver o papel). Usa o ControlModule do PlayerModule --
-- jeito oficial, não briga com o WalkSpeed que o Crouching controla.
local function setControlsEnabled(enabled: boolean)
	local ok, controls = pcall(function()
		local scripts = LocalPlayer:WaitForChild("PlayerScripts", 5)
		local playerModule = scripts and scripts:WaitForChild("PlayerModule", 5)
		return playerModule and require(playerModule :: ModuleScript):GetControls()
	end)
	if ok and controls then
		if enabled then
			(controls :: any):Enable()
		else
			(controls :: any):Disable()
		end
	end
end

--------------------------------------------------------------------------------
-- UI (construída uma vez)
--------------------------------------------------------------------------------

local gui = Instance.new("ScreenGui")
gui.Name = "RoleRevealHUD"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.DisplayOrder = 20
gui.Enabled = false
gui.Parent = playerGui

local overlay = Instance.new("Frame")
overlay.Size = UDim2.fromScale(1, 1)
overlay.BackgroundColor3 = Color3.fromRGB(6, 6, 8)
overlay.BackgroundTransparency = 1
overlay.BorderSizePixel = 0
overlay.Parent = gui

-- Barra de cor atrás do papel (dá o "flash" e a identidade)
local accent = Instance.new("Frame")
accent.AnchorPoint = Vector2.new(0.5, 0.5)
accent.Position = UDim2.fromScale(0.5, 0.5)
accent.Size = UDim2.new(1, 0, 0, 4)
accent.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
accent.BackgroundTransparency = 1
accent.BorderSizePixel = 0
accent.Parent = overlay

local kicker = Instance.new("TextLabel")
kicker.AnchorPoint = Vector2.new(0.5, 1)
kicker.Position = UDim2.new(0.5, 0, 0.5, -70)
kicker.Size = UDim2.fromOffset(400, 28)
kicker.BackgroundTransparency = 1
kicker.Font = Enum.Font.GothamMedium
kicker.Text = "SORTEANDO SEU PAPEL"
kicker.TextSize = 16
kicker.TextColor3 = Color3.fromRGB(180, 180, 190)
kicker.TextTransparency = 1
kicker.Parent = overlay

local roleLabel = Instance.new("TextLabel")
roleLabel.AnchorPoint = Vector2.new(0.5, 0.5)
roleLabel.Position = UDim2.fromScale(0.5, 0.5)
roleLabel.Size = UDim2.fromOffset(900, 120)
roleLabel.BackgroundTransparency = 1
roleLabel.Font = Enum.Font.GothamBlack
roleLabel.Text = ""
roleLabel.TextScaled = false
roleLabel.TextSize = 84
roleLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
roleLabel.TextTransparency = 1
roleLabel.Parent = overlay

local titleLabel = Instance.new("TextLabel")
titleLabel.AnchorPoint = Vector2.new(0.5, 0)
titleLabel.Position = UDim2.new(0.5, 0, 0.5, 60)
titleLabel.Size = UDim2.fromOffset(700, 30)
titleLabel.BackgroundTransparency = 1
titleLabel.Font = Enum.Font.GothamBold
titleLabel.Text = ""
titleLabel.TextSize = 22
titleLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
titleLabel.TextTransparency = 1
titleLabel.Parent = overlay

local objectiveLabel = Instance.new("TextLabel")
objectiveLabel.AnchorPoint = Vector2.new(0.5, 0)
objectiveLabel.Position = UDim2.new(0.5, 0, 0.5, 96)
objectiveLabel.Size = UDim2.fromOffset(680, 40)
objectiveLabel.BackgroundTransparency = 1
objectiveLabel.Font = Enum.Font.Gotham
objectiveLabel.Text = ""
objectiveLabel.TextSize = 17
objectiveLabel.TextWrapped = true
objectiveLabel.TextColor3 = Color3.fromRGB(205, 205, 215)
objectiveLabel.TextTransparency = 1
objectiveLabel.Parent = overlay

local function makeSound(id: string, volume: number): Sound
	local s = Instance.new("Sound")
	s.SoundId = id
	s.Volume = volume
	s.Parent = gui
	return s
end
local tickSound = makeSound(TICK_SOUND, 0.35)
local revealSound = makeSound(REVEAL_SOUND, 0.6)

--------------------------------------------------------------------------------
-- Sequência
--------------------------------------------------------------------------------

local runToken = 0

local function fade(instance: Instance, props: { [string]: any }, time: number, style: Enum.EasingStyle?)
	TweenService:Create(
		instance,
		TweenInfo.new(time, style or Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		props
	):Play()
end

local function playReveal(role: string)
	local info = ROLE_INFO[role]
	if not info then
		return
	end

	runToken += 1
	local myToken = runToken

	setControlsEnabled(false)
	-- Rede de segurança: se a sequência abaixo travar/errar, o movimento
	-- volta sozinho em 12s (a sequência normal leva ~7s).
	task.delay(12, function()
		if runToken == myToken then
			setControlsEnabled(true)
		end
	end)

	gui.Enabled = true
	overlay.BackgroundTransparency = 1
	accent.BackgroundTransparency = 1
	accent.Size = UDim2.new(1, 0, 0, 4)
	accent.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	roleLabel.Text = ""
	roleLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
	roleLabel.TextTransparency = 1
	roleLabel.TextSize = 84
	titleLabel.Text = ""
	titleLabel.TextTransparency = 1
	objectiveLabel.Text = ""
	objectiveLabel.TextTransparency = 1
	kicker.TextTransparency = 1

	fade(overlay, { BackgroundTransparency = 0.12 }, 0.35)
	fade(kicker, { TextTransparency = 0.15 }, 0.4)
	fade(roleLabel, { TextTransparency = 0 }, 0.3)

	-- Caça-níquel: troca o texto com intervalo crescente (ease-out) até parar.
	task.spawn(function()
		local elapsed = 0
		local duration = 2.6
		local wheelIndex = 1
		while elapsed < duration do
			if runToken ~= myToken then
				return
			end
			roleLabel.Text = ROLE_INFO[WHEEL[wheelIndex]].Label
			roleLabel.TextColor3 = Color3.fromRGB(235, 235, 240)
			pcall(function()
				tickSound.PlaybackSpeed = 0.9 + elapsed / duration
				tickSound:Play()
			end)
			wheelIndex = wheelIndex % #WHEEL + 1

			-- intervalo cresce de 0.05s até ~0.32s (desacelera)
			local p = elapsed / duration
			local interval = 0.05 + (0.3 * p * p)
			elapsed += interval
			task.wait(interval)
		end

		if runToken ~= myToken then
			return
		end

		-- TRAVA no papel real
		roleLabel.Text = info.Label

		-- flash: barra de cor abre + branco -> cor
		accent.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
		accent.BackgroundTransparency = 0
		accent.Size = UDim2.new(1, 0, 0, 4)
		fade(accent, { Size = UDim2.new(1, 0, 0, 130), BackgroundColor3 = info.Color }, 0.35, Enum.EasingStyle.Back)
		fade(accent, { BackgroundTransparency = 0.35 }, 0.9)

		-- punch de escala no texto
		roleLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
		roleLabel.TextSize = 128
		fade(roleLabel, { TextSize = 92 }, 0.4, Enum.EasingStyle.Back)
		task.delay(0.12, function()
			if runToken == myToken then
				roleLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
			end
		end)

		pcall(function()
			revealSound:Play()
		end)

		kicker.Text = "SEU PAPEL"
		fade(kicker, { TextTransparency = 0.3 }, 0.3)

		task.wait(0.35)
		if runToken ~= myToken then
			return
		end
		titleLabel.Text = info.Title
		titleLabel.TextColor3 = info.Color
		objectiveLabel.Text = info.Objective
		fade(titleLabel, { TextTransparency = 0 }, 0.35)
		fade(objectiveLabel, { TextTransparency = 0.05 }, 0.4)

		-- segura e some
		task.wait(2.8)
		if runToken ~= myToken then
			return
		end
		fade(overlay, { BackgroundTransparency = 1 }, 0.5)
		fade(accent, { BackgroundTransparency = 1 }, 0.5)
		fade(roleLabel, { TextTransparency = 1 }, 0.5)
		fade(titleLabel, { TextTransparency = 1 }, 0.5)
		fade(objectiveLabel, { TextTransparency = 1 }, 0.5)
		fade(kicker, { TextTransparency = 1 }, 0.5)
		task.wait(0.55)
		if runToken == myToken then
			gui.Enabled = false
			setControlsEnabled(true)
		end
	end)
end

--------------------------------------------------------------------------------
-- Gatilho
--------------------------------------------------------------------------------

local function waitForRole(): string?
	local role = LocalPlayer:GetAttribute("Role")
	if type(role) == "string" then
		return role
	end
	local deadline = os.clock() + ROLE_WAIT_TIMEOUT
	while os.clock() < deadline do
		task.wait(0.1)
		role = LocalPlayer:GetAttribute("Role")
		if type(role) == "string" then
			return role
		end
	end
	return nil
end

Remotes.RoundStateChanged.OnClientEvent:Connect(function(phase: string)
	if phase ~= GameConfig.PhaseOrder[1] then
		return
	end
	task.spawn(function()
		local role = waitForRole()
		if role and ROLE_INFO[role] then
			playReveal(role)
		end
	end)
end)
