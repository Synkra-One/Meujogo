--!strict
--[[
	RepairMinigameController
	Interface e entrada do reparo de precisão. Desenha tudo por código (nenhuma
	imagem, modelo ou plugin externo) e NÃO decide nada: quem conta a sequência
	de acertos, classifica o teste e produz ruído é server/RepairMinigameSystem.lua.

	O marcador é desenhado com RepairMinigameConfig.MarkerAt sobre os
	parâmetros que o servidor sorteou, no relógio de servidor
	(Workspace:GetServerTimeNow) -- é por isso que o que se vê na barra é o
	que o servidor conta.

	ENTRADA
	  Teclado  a MESMA tecla do prompt que abriu o reparo (E, ou F enquanto o
	           HUD de poderes está ativo -- ver SurvivorPowersController) para
	           segurar; a tecla do prompt OU Espaço para acertar o teste.
	           Espaço é afundado (Sink) durante o reparo pra não pular.
	  Controle ButtonX segura, ButtonX/ButtonA acertam.
	  Celular  toque no prompt abre; o painel passa a "segurar" sozinho, o
	           botão grande acerta e o X cancela.
]]

local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Modules.RepairMinigameConfig)
local Remotes = require(ReplicatedStorage.Modules.Remotes)

local THEME = Config.Theme
local HIT_ACTION = "RepairMinigameHit"
local KEEPALIVE_INTERVAL = 0.25
-- Quando o reparo abre por clique de mouse ou toque no prompt, nenhuma tecla
-- está pressionada. Se nada for visto segurando nesta janela, o painel passa
-- a se sustentar sozinho e só o botão de cancelar fecha.
local HOLD_GRACE = 1

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local function create(class: string, parent: Instance?, properties: { [string]: any }): any
	local object = Instance.new(class)
	for key, value in properties do
		(object :: any)[key] = value
	end
	object.Parent = parent
	return object
end

--------------------------------------------------------------------------------
-- Interface
--------------------------------------------------------------------------------

local gui = create("ScreenGui", playerGui, {
	Name = "RepairMinigame",
	DisplayOrder = 35,
	IgnoreGuiInset = true,
	ResetOnSpawn = false,
	Enabled = false,
})

-- Âncora na base da tela. O painel é baixo e estreito de propósito: informa
-- sem tapar a visão de quem está sendo caçado enquanto repara.
local root = create("Frame", gui, {
	Name = "Panel",
	AnchorPoint = Vector2.new(0.5, 1),
	Position = UDim2.new(0.5, 0, 1, -28),
	Size = UDim2.fromOffset(560, 138),
	BackgroundTransparency = 1,
})
local rootScale = create("UIScale", root, { Scale = 1 })

-- Sombra simulada: uma chapa escura levemente maior, deslocada pra baixo.
local shadow = create("Frame", root, {
	Name = "Shadow",
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.new(0.5, 0, 0.5, 6),
	Size = UDim2.new(1, 16, 1, 16),
	BackgroundColor3 = Color3.new(0, 0, 0),
	BackgroundTransparency = 0.6,
	BorderSizePixel = 0,
	ZIndex = 1,
})
create("UICorner", shadow, { CornerRadius = UDim.new(0, 14) })

local plate = create("Frame", root, {
	Name = "Plate",
	Size = UDim2.fromScale(1, 1),
	BackgroundColor3 = THEME.Panel,
	BackgroundTransparency = 0.06,
	BorderSizePixel = 0,
	ZIndex = 2,
})
create("UICorner", plate, { CornerRadius = UDim.new(0, 10) })
-- Chapa metálica: claro em cima, escuro embaixo.
create("UIGradient", plate, {
	Rotation = 90,
	Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(34, 33, 32)),
		ColorSequenceKeypoint.new(0.5, THEME.Panel),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(8, 8, 9)),
	}),
})
local plateStroke = create("UIStroke", plate, {
	Color = THEME.PanelEdge,
	Thickness = 1.5,
	Transparency = 0.15,
})
-- Ferrugem: um degradê quente só nas pontas do contorno.
create("UIGradient", plateStroke, {
	Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, THEME.Rust),
		ColorSequenceKeypoint.new(0.35, THEME.PanelEdge),
		ColorSequenceKeypoint.new(0.7, THEME.PanelEdge),
		ColorSequenceKeypoint.new(1, THEME.Rust),
	}),
})
create("UIPadding", plate, {
	PaddingTop = UDim.new(0, 12),
	PaddingBottom = UDim.new(0, 12),
	PaddingLeft = UDim.new(0, 16),
	PaddingRight = UDim.new(0, 16),
})

-- Brilho de reação (verde/amarelo/vermelho/azul) por cima da chapa inteira.
local flash = create("Frame", plate, {
	Name = "Flash",
	Size = UDim2.new(1, 32, 1, 24),
	Position = UDim2.fromOffset(-16, -12),
	BackgroundColor3 = THEME.Green,
	BackgroundTransparency = 1,
	BorderSizePixel = 0,
	ZIndex = 9,
})
create("UICorner", flash, { CornerRadius = UDim.new(0, 10) })

-- Linha 1: "Reparando..." + nome do ponto + precisão.
local header = create("Frame", plate, {
	Name = "Header",
	Size = UDim2.new(1, 0, 0, 16),
	BackgroundTransparency = 1,
	ZIndex = 3,
})
local statusLabel = create("TextLabel", header, {
	Name = "Status",
	Size = UDim2.fromScale(0.55, 1),
	BackgroundTransparency = 1,
	Font = Enum.Font.GothamMedium,
	Text = "Reparando...",
	TextColor3 = THEME.TextDim,
	TextSize = 12,
	TextXAlignment = Enum.TextXAlignment.Left,
	ZIndex = 3,
})
local accuracyLabel = create("TextLabel", header, {
	Name = "Accuracy",
	AnchorPoint = Vector2.new(1, 0),
	Position = UDim2.fromScale(1, 0),
	Size = UDim2.fromScale(0.45, 1),
	BackgroundTransparency = 1,
	Font = Enum.Font.GothamMedium,
	Text = "PRECISÃO  —",
	TextColor3 = THEME.TextDim,
	TextSize = 12,
	TextXAlignment = Enum.TextXAlignment.Right,
	ZIndex = 3,
})

-- Linha 2: barra da SEQUÊNCIA de acertos seguidos (só enche acertando).
local progressTrack = create("Frame", plate, {
	Name = "Progress",
	Position = UDim2.fromOffset(0, 24),
	Size = UDim2.new(1, 0, 0, 10),
	BackgroundColor3 = THEME.Track,
	BorderSizePixel = 0,
	ZIndex = 3,
})
create("UICorner", progressTrack, { CornerRadius = UDim.new(0, 5) })
create("UIStroke", progressTrack, { Color = THEME.PanelEdge, Thickness = 1, Transparency = 0.45 })
local progressFill = create("Frame", progressTrack, {
	Name = "Fill",
	Size = UDim2.fromScale(0, 1),
	BackgroundColor3 = THEME.Green,
	BorderSizePixel = 0,
	ZIndex = 4,
})
create("UICorner", progressFill, { CornerRadius = UDim.new(0, 5) })
create("UIGradient", progressFill, {
	Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(58, 122, 70)),
		ColorSequenceKeypoint.new(1, THEME.Green),
	}),
})
local percentLabel = create("TextLabel", progressTrack, {
	Name = "Percent",
	AnchorPoint = Vector2.new(1, 0.5),
	Position = UDim2.new(1, -6, 0.5, 0),
	Size = UDim2.fromOffset(46, 14),
	BackgroundTransparency = 1,
	Font = Enum.Font.GothamBold,
	Text = "0/3",
	TextColor3 = THEME.Text,
	TextSize = 11,
	TextXAlignment = Enum.TextXAlignment.Right,
	TextStrokeTransparency = 0.5,
	ZIndex = 6,
})

-- Linha 3: a barra de sincronização (só aparece durante um teste).
local testFrame = create("Frame", plate, {
	Name = "Test",
	Position = UDim2.fromOffset(0, 44),
	Size = UDim2.new(1, 0, 0, 50),
	BackgroundTransparency = 1,
	Visible = false,
	ZIndex = 3,
})
local syncTrack = create("Frame", testFrame, {
	Name = "Track",
	Position = UDim2.fromOffset(0, 12),
	Size = UDim2.new(1, 0, 0, 26),
	BackgroundColor3 = THEME.Red,
	BorderSizePixel = 0,
	ClipsDescendants = true,
	ZIndex = 3,
})
create("UICorner", syncTrack, { CornerRadius = UDim.new(0, 6) })
create("UIGradient", syncTrack, {
	Rotation = 90,
	Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(96, 32, 26)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(58, 20, 17)),
	}),
})
local syncStroke = create("UIStroke", syncTrack, { Color = THEME.PanelEdge, Thickness = 1.4, Transparency = 0.2 })

local yellowZone = create("Frame", syncTrack, {
	Name = "Yellow",
	Size = UDim2.fromScale(0, 1),
	BackgroundColor3 = THEME.Yellow,
	BackgroundTransparency = 0.45,
	BorderSizePixel = 0,
	ZIndex = 4,
})
local greenZone = create("Frame", syncTrack, {
	Name = "Green",
	Size = UDim2.fromScale(0, 1),
	BackgroundColor3 = THEME.Green,
	BackgroundTransparency = 0.25,
	BorderSizePixel = 0,
	ZIndex = 5,
})
local perfectZone = create("Frame", syncTrack, {
	Name = "Perfect",
	Size = UDim2.fromScale(0, 1),
	BackgroundColor3 = THEME.Perfect,
	BackgroundTransparency = 0.1,
	BorderSizePixel = 0,
	Visible = false,
	ZIndex = 6,
})
create("UIGradient", perfectZone, {
	Rotation = 90,
	Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(150, 220, 246)),
		ColorSequenceKeypoint.new(1, THEME.Perfect),
	}),
})

-- Marcador luminoso: halo largo e translúcido por trás da lâmina fina.
local markerGlow = create("Frame", syncTrack, {
	Name = "MarkerGlow",
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0, 0.5),
	Size = UDim2.fromOffset(22, 34),
	BackgroundColor3 = THEME.Marker,
	BackgroundTransparency = 0.72,
	BorderSizePixel = 0,
	ZIndex = 7,
})
create("UICorner", markerGlow, { CornerRadius = UDim.new(0.5, 0) })
local marker = create("Frame", syncTrack, {
	Name = "Marker",
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0, 0.5),
	Size = UDim2.fromOffset(4, 30),
	BackgroundColor3 = THEME.Marker,
	BorderSizePixel = 0,
	ZIndex = 8,
})
create("UICorner", marker, { CornerRadius = UDim.new(0, 2) })

local hintLabel = create("TextLabel", testFrame, {
	Name = "Hint",
	AnchorPoint = Vector2.new(0.5, 1),
	Position = UDim2.new(0.5, 0, 1, 0),
	Size = UDim2.new(1, 0, 0, 14),
	BackgroundTransparency = 1,
	Font = Enum.Font.GothamBold,
	Text = "",
	TextColor3 = THEME.Text,
	TextSize = 11,
	ZIndex = 6,
})

-- Dica de "segure para reparar" enquanto nenhum teste está na tela.
local holdLabel = create("TextLabel", plate, {
	Name = "HoldHint",
	Position = UDim2.fromOffset(0, 52),
	Size = UDim2.new(1, 0, 0, 16),
	BackgroundTransparency = 1,
	Font = Enum.Font.GothamMedium,
	Text = "",
	TextColor3 = THEME.TextDim,
	TextSize = 11,
	ZIndex = 3,
})

-- Botão grande do celular + cancelar. Ficam fora da chapa, acima dela, pro
-- polegar não cobrir a barra que ele precisa ler.
local touchDock = create("Frame", root, {
	Name = "TouchDock",
	AnchorPoint = Vector2.new(0.5, 1),
	Position = UDim2.new(0.5, 0, 0, -12),
	Size = UDim2.fromOffset(300, 92),
	BackgroundTransparency = 1,
	Visible = false,
	ZIndex = 3,
})
local hitButton = create("TextButton", touchDock, {
	Name = "Hit",
	AnchorPoint = Vector2.new(0.5, 1),
	Position = UDim2.new(0.5, 0, 1, 0),
	Size = UDim2.fromOffset(92, 92),
	BackgroundColor3 = Color3.fromRGB(28, 27, 26),
	BackgroundTransparency = 0.05,
	AutoButtonColor = false,
	Font = Enum.Font.GothamBold,
	Text = "BATER",
	TextColor3 = THEME.Text,
	TextSize = 15,
	ZIndex = 4,
})
create("UICorner", hitButton, { CornerRadius = UDim.new(0.5, 0) })
local hitStroke = create("UIStroke", hitButton, { Color = THEME.Yellow, Thickness = 2.5, Transparency = 0.3 })
local cancelButton = create("TextButton", touchDock, {
	Name = "Cancel",
	AnchorPoint = Vector2.new(0.5, 1),
	Position = UDim2.new(0.5, 86, 1, -14),
	Size = UDim2.fromOffset(46, 46),
	BackgroundColor3 = Color3.fromRGB(22, 21, 20),
	BackgroundTransparency = 0.15,
	AutoButtonColor = false,
	Font = Enum.Font.GothamBold,
	Text = "✕",
	TextColor3 = THEME.TextDim,
	TextSize = 18,
	ZIndex = 4,
})
create("UICorner", cancelButton, { CornerRadius = UDim.new(0.5, 0) })
create("UIStroke", cancelButton, { Color = THEME.PanelEdge, Thickness = 1.5, Transparency = 0.3 })

--------------------------------------------------------------------------------
-- Sons (fallbacks nativos do Roblox; troque pelos ids da experiência)
--------------------------------------------------------------------------------

local SOUNDS = {
	Green = { id = "rbxasset://sounds/impact_generic.mp3", volume = 0.35, pitch = 1.25 },
	Perfect = { id = "rbxasset://sounds/electronicpingshort.wav", volume = 0.4, pitch = 1.35 },
	Yellow = { id = "rbxasset://sounds/impact_generic.mp3", volume = 0.28, pitch = 0.85 },
	Red = { id = "rbxasset://sounds/impact_generic.mp3", volume = 0.6, pitch = 0.45 },
	Miss = { id = "rbxasset://sounds/impact_generic.mp3", volume = 0.5, pitch = 0.5 },
}

local function playSound(grade: string)
	local spec = SOUNDS[grade]
	if not spec then
		return
	end
	local sound = create("Sound", SoundService, {
		SoundId = spec.id,
		Volume = spec.volume,
		PlaybackSpeed = spec.pitch,
	})
	sound.Ended:Once(function()
		sound:Destroy()
	end)
	sound:Play()
	-- Rede de segurança: som que nunca carregar não vaza instância.
	task.delay(4, function()
		if sound.Parent then
			sound:Destroy()
		end
	end)
end

--------------------------------------------------------------------------------
-- Estado da sessão local
--------------------------------------------------------------------------------

local session: {
	token: number,
	part: BasePart,
	holdKey: Enum.KeyCode?,
	gamepadKey: Enum.KeyCode,
	implicitHold: boolean,
	sawHold: boolean,
	openedAt: number,
	lastKeepalive: number,
	test: Config.Test?,
	markerImpactUntil: number,
}? = nil

local visible = false
-- Enquanto o painel desliza, o laço de render NÃO mexe na posição: os dois
-- escrevem em root.Position e o laço venceria todo frame, matando a animação.
local slideTween: Tween? = nil

local function isTouchOnly(): boolean
	return UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
end

local function keyName(code: Enum.KeyCode?): string
	if not code then
		return "E"
	end
	if code == Enum.KeyCode.Space then
		return "ESPAÇO"
	end
	return code.Name
end

-- No celular o painel sobe: o botão de pulo e o dock de poderes ocupam a faixa
-- de baixo, e o botão grande de bater precisa de espaço confortável.
local function restPosition(): UDim2
	return UDim2.new(0.5, 0, 1, if isTouchOnly() then -150 else -28)
end

local function setPanelVisible(show: boolean)
	if slideTween then
		slideTween:Cancel()
		slideTween = nil
	end

	local rest = restPosition()
	local offscreen = UDim2.new(rest.X.Scale, rest.X.Offset, 1, 40)
	local slide: Tween

	if show then
		visible = true
		gui.Enabled = true
		root.Position = offscreen
		plate.BackgroundTransparency = 1
		slide = TweenService:Create(root, TweenInfo.new(0.26, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
			Position = rest,
		})
		TweenService:Create(plate, TweenInfo.new(0.2), { BackgroundTransparency = 0.06 }):Play()
	else
		visible = false
		slide = TweenService:Create(root, TweenInfo.new(0.22, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
			Position = offscreen,
		})
		TweenService:Create(plate, TweenInfo.new(0.18), { BackgroundTransparency = 1 }):Play()
	end

	slideTween = slide
	slide.Completed:Once(function()
		if slideTween == slide then
			slideTween = nil
		end
		if not visible then
			gui.Enabled = false
		end
	end)
	slide:Play()
end

local function pulseFlash(color: Color3, strength: number)
	flash.BackgroundColor3 = color
	flash.BackgroundTransparency = strength
	TweenService:Create(flash, TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		BackgroundTransparency = 1,
	}):Play()
end

local function showTest(test: Config.Test)
	local current = session
	if not current then
		return
	end
	current.test = test
	testFrame.Visible = true
	holdLabel.Visible = false

	-- Zonas: largura e posição vêm SÓ dos parâmetros do servidor.
	local function place(frame: Frame, half: number)
		frame.Position = UDim2.fromScale(math.max(0, test.center - half), 0)
		frame.Size = UDim2.fromScale(math.min(1, half * 2), 1)
	end
	place(yellowZone, test.yellowHalf)
	place(greenZone, test.greenHalf)
	perfectZone.Visible = test.perfectHalf > 0
	if test.perfectHalf > 0 then
		place(perfectZone, test.perfectHalf)
	end

	-- Variação visual por teste (requisito: a aparência do teste muda).
	if test.style == 1 then
		syncTrack.Size = UDim2.new(1, 0, 0, 26)
		syncTrack.Position = UDim2.fromOffset(0, 12)
		marker.Size = UDim2.fromOffset(4, 30)
		syncStroke.Color = THEME.PanelEdge
	elseif test.style == 2 then
		syncTrack.Size = UDim2.new(1, 0, 0, 20)
		syncTrack.Position = UDim2.fromOffset(0, 15)
		marker.Size = UDim2.fromOffset(3, 26)
		syncStroke.Color = THEME.Rust
	else
		syncTrack.Size = UDim2.new(1, 0, 0, 32)
		syncTrack.Position = UDim2.fromOffset(0, 9)
		marker.Size = UDim2.fromOffset(6, 36)
		syncStroke.Color = Color3.fromRGB(62, 58, 54)
	end

	local label = if isTouchOnly() then "TOQUE EM BATER" else keyName(current.holdKey) .. " ou ESPAÇO"
	hintLabel.Text = if test.perfectHalf > 0 then label .. "  ·  MIRE O AZUL" else label
	hintLabel.TextColor3 = if test.perfectHalf > 0 then THEME.Perfect else THEME.Yellow
	hitStroke.Color = if test.perfectHalf > 0 then THEME.Perfect else THEME.Yellow

	statusLabel.Text = "Sincronize!"
	statusLabel.TextColor3 = THEME.Yellow
end

local function hideTest()
	local current = session
	if current then
		current.test = nil
	end
	testFrame.Visible = false
	holdLabel.Visible = true
	statusLabel.Text = "Reparando... aguarde o teste"
	statusLabel.TextColor3 = THEME.TextDim
end

-- A barra de cima mostra a SEQUÊNCIA de acertos (não um progresso que sobe
-- sozinho): só enche acertando, e esvazia inteira no erro.
local function setStreak(streak: number, required: number, lost: boolean?)
	local ratio = if required > 0 then math.clamp(streak / required, 0, 1) else 0
	percentLabel.Text = string.format("%d/%d", streak, required)
	if lost then
		progressFill.BackgroundColor3 = THEME.Red
		TweenService:Create(progressFill, TweenInfo.new(0.35, Enum.EasingStyle.Quad), {
			BackgroundColor3 = THEME.Green,
			Size = UDim2.fromScale(0, 1),
		}):Play()
		return
	end
	progressFill.BackgroundColor3 = THEME.Green
	TweenService:Create(progressFill, TweenInfo.new(0.2, Enum.EasingStyle.Quad), {
		Size = UDim2.fromScale(ratio, 1),
	}):Play()
end

--------------------------------------------------------------------------------
-- Entrada
--------------------------------------------------------------------------------

local function sendHit()
	local current = session
	local test = current and current.test
	if not current or not test then
		return
	end
	local elapsed = Workspace:GetServerTimeNow() - test.startsAt
	if elapsed < 0 then
		return -- ainda no respiro antes do marcador andar
	end
	-- Só o instante -- nunca a posição, a nota ou o progresso.
	Remotes.RepairMinigame:FireServer("Hit", current.token, test.id, elapsed)
	current.test = nil
	current.markerImpactUntil = os.clock() + 0.18
end

local function release()
	local current = session
	if not current then
		return
	end
	Remotes.RepairMinigame:FireServer("Release", current.token)
end

local function bindInput()
	local current = session
	if not current then
		return
	end
	local keys: { Enum.KeyCode } = { Enum.KeyCode.Space, Enum.KeyCode.ButtonX, Enum.KeyCode.ButtonA }
	if current.holdKey then
		table.insert(keys, current.holdKey)
	end
	ContextActionService:BindActionAtPriority(
		HIT_ACTION,
		function(_, state: Enum.UserInputState, input: InputObject)
			if state ~= Enum.UserInputState.Begin then
				return Enum.ContextActionResult.Pass
			end
			sendHit()
			-- Espaço/ButtonA são afundados pra não pular no meio do reparo;
			-- a tecla do prompt segue passando (poderes continuam acessíveis).
			if input.KeyCode == Enum.KeyCode.Space or input.KeyCode == Enum.KeyCode.ButtonA then
				return Enum.ContextActionResult.Sink
			end
			return Enum.ContextActionResult.Pass
		end,
		false,
		Enum.ContextActionPriority.High.Value,
		table.unpack(keys)
	)
end

local function unbindInput()
	ContextActionService:UnbindAction(HIT_ACTION)
end

--------------------------------------------------------------------------------
-- Abertura / fechamento
--------------------------------------------------------------------------------

-- A tecla do prompt é remapeada LOCALMENTE (E -> F) enquanto o HUD de poderes
-- está ativo. Ler do próprio prompt é o único jeito de mostrar a tecla certa
-- sem duplicar aquela regra aqui.
local function promptKeys(part: BasePart): (Enum.KeyCode?, Enum.KeyCode)
	for _, child in part:GetChildren() do
		if child:IsA("ProximityPrompt") and child.Enabled then
			return child.KeyboardKeyCode, child.GamepadKeyCode
		end
	end
	for _, child in part:GetChildren() do
		if child:IsA("ProximityPrompt") then
			return child.KeyboardKeyCode, child.GamepadKeyCode
		end
	end
	return Enum.KeyCode.E, Enum.KeyCode.ButtonX
end

local function closeSession(reason: string, completed: boolean)
	if not session then
		return
	end
	session = nil
	unbindInput()
	testFrame.Visible = false
	touchDock.Visible = false
	-- O motivo fica legível durante a saída (o painel leva ~0,22s pra sumir).
	if reason ~= "" then
		statusLabel.Text = reason
		statusLabel.TextColor3 = if completed then THEME.Green else THEME.TextDim
	end
	if completed then
		pulseFlash(THEME.Green, 0.55)
	end
	setPanelVisible(false)
end

local function openSession(token: number, part: BasePart, label: string, streak: number, required: number)
	local keyboardKey, gamepadKey = promptKeys(part)
	session = {
		token = token,
		part = part,
		holdKey = keyboardKey,
		gamepadKey = gamepadKey,
		implicitHold = isTouchOnly(),
		sawHold = false,
		openedAt = os.clock(),
		lastKeepalive = 0,
		test = nil,
		markerImpactUntil = 0,
	}

	progressFill.Size = UDim2.fromScale(if required > 0 then math.clamp(streak / required, 0, 1) else 0, 1)
	progressFill.BackgroundColor3 = THEME.Green
	percentLabel.Text = string.format("%d/%d", streak, required)
	accuracyLabel.Text = "PRECISÃO  —"
	accuracyLabel.TextColor3 = THEME.TextDim
	holdLabel.Text = if isTouchOnly()
		then string.format("%s  ·  acerte %d seguidas", label, required)
		else string.format("%s  ·  acerte %d seguidas  ·  segure %s", label, required, keyName(keyboardKey))
	touchDock.Visible = isTouchOnly()
	hideTest()
	bindInput()
	setPanelVisible(true)
end

--------------------------------------------------------------------------------
-- Remote
--------------------------------------------------------------------------------

Remotes.RepairMinigame.OnClientEvent:Connect(function(action: string, token: unknown, a: unknown, b: unknown, c: unknown, d: unknown, e: unknown, f: unknown)
	if action == "Start" then
		if typeof(a) ~= "Instance" or not (a :: Instance):IsA("BasePart") or type(token) ~= "number" then
			return
		end
		openSession(
			token,
			a :: BasePart,
			if type(b) == "string" then b else "Reparo",
			if type(c) == "number" then c else 0,
			if type(d) == "number" then d else 3
		)
		return
	end

	local current = session
	if not current or token ~= current.token then
		return
	end

	if action == "Streak" then
		-- Conserto Relâmpago deu acertos de graça.
		if type(a) == "number" and type(b) == "number" then
			setStreak(a, b)
		end
	elseif action == "Test" then
		if type(a) == "table" then
			showTest(a :: any)
		end
	elseif action == "Result" then
		-- a = id do teste, b = nota, c/d = sequência atual/necessária,
		-- e = segundos travado, f = precisão da sessão.
		local grade = if type(b) == "string" then b else "Red"
		local streak = if type(c) == "number" then c else 0
		local required = if type(d) == "number" then d else 3
		hideTest()
		playSound(grade)
		if grade == "Perfect" then
			pulseFlash(THEME.Perfect, 0.45)
		elseif grade == "Green" then
			pulseFlash(THEME.Green, 0.6)
		elseif grade == "Yellow" then
			pulseFlash(THEME.Yellow, 0.6)
		else
			pulseFlash(THEME.Red, 0.35)
		end

		local hit = grade == "Perfect" or grade == "Green"
		setStreak(streak, required, not hit and streak == 0)
		if hit then
			statusLabel.Text = string.format("Acertou! %d de %d seguidas", streak, required)
			statusLabel.TextColor3 = THEME.Green
		elseif grade == "Yellow" then
			statusLabel.Text = "Quase! Sequência perdida"
			statusLabel.TextColor3 = THEME.Yellow
		else
			statusLabel.Text = if grade == "Miss" then "Deixou passar! Sequência perdida" else "Errou! Sequência perdida"
			statusLabel.TextColor3 = THEME.Red
		end
		if type(f) == "number" then
			accuracyLabel.Text = string.format("PRECISÃO  %d%%", f)
			accuracyLabel.TextColor3 = if f >= 75 then THEME.Green elseif f >= 40 then THEME.Yellow else THEME.Red
		end
	elseif action == "Stop" then
		closeSession(if type(a) == "string" then a else "", b == true)
	end
end)

--------------------------------------------------------------------------------
-- Laço: marcador, keep-alive e detecção de soltar a tecla
--------------------------------------------------------------------------------

local function holdIsDown(current: typeof(session)): boolean
	if not current then
		return false
	end
	if current.holdKey and UserInputService:IsKeyDown(current.holdKey) then
		return true
	end
	if UserInputService:IsGamepadButtonDown(Enum.UserInputType.Gamepad1, current.gamepadKey) then
		return true
	end
	return false
end

RunService.RenderStepped:Connect(function()
	local current = session
	if not current then
		return
	end

	local camera = Workspace.CurrentCamera
	local viewport = if camera then camera.ViewportSize else Vector2.new(1280, 720)
	rootScale.Scale = math.clamp(math.min(viewport.X / 900, viewport.Y / 640), 0.7, 1.05)
	-- Acompanha giro de tela / troca de dispositivo, mas nunca durante o
	-- deslize de entrada ou saída (ver slideTween).
	if not slideTween then
		root.Position = restPosition()
	end

	-- Soltar para cancelar. A janela de carência cobre o caso de o reparo ter
	-- sido aberto por clique/toque no prompt, quando nenhuma tecla está baixa.
	if not current.implicitHold then
		if holdIsDown(current) then
			current.sawHold = true
		elseif current.sawHold then
			release()
			return
		elseif os.clock() - current.openedAt > HOLD_GRACE then
			current.implicitHold = true
			touchDock.Visible = true
			holdLabel.Text = "Mantenha-se perto do ponto"
		end
	end

	if os.clock() - current.lastKeepalive >= KEEPALIVE_INTERVAL then
		current.lastKeepalive = os.clock()
		Remotes.RepairMinigame:FireServer("Hold", current.token)
	end

	local test = current.test
	if test then
		local elapsed = Workspace:GetServerTimeNow() - test.startsAt
		local x = Config.MarkerAt(test, elapsed)
		marker.Position = UDim2.fromScale(x, 0.5)
		markerGlow.Position = UDim2.fromScale(x, 0.5)
		-- Pulsa mais forte perto do alvo: dá leitura periférica do acerto.
		local closeness = 1 - math.clamp(math.abs(x - test.center) / math.max(test.yellowHalf, 0.01), 0, 1)
		markerGlow.BackgroundTransparency = 0.78 - closeness * 0.3
		markerGlow.Size = UDim2.fromOffset(20 + closeness * 12, 34)
	elseif os.clock() < current.markerImpactUntil then
		-- Impacto do acerto: a lâmina incha e apaga onde o jogador bateu.
		local t = (current.markerImpactUntil - os.clock()) / 0.18
		markerGlow.BackgroundTransparency = 0.3 + (1 - t) * 0.7
		markerGlow.Size = UDim2.fromOffset(22 + t * 26, 34 + t * 10)
	end
end)

--------------------------------------------------------------------------------
-- Botões de toque
--------------------------------------------------------------------------------

hitButton.Activated:Connect(function()
	sendHit()
	TweenService:Create(hitButton, TweenInfo.new(0.08), { BackgroundTransparency = 0.35 }):Play()
	task.delay(0.1, function()
		TweenService:Create(hitButton, TweenInfo.new(0.14), { BackgroundTransparency = 0.05 }):Play()
	end)
end)
cancelButton.Activated:Connect(release)

-- Sair da partida/morrer fecha o painel mesmo que o "Stop" do servidor se
-- perca no caminho (o servidor já encerrou a sessão dele de qualquer forma).
player.CharacterRemoving:Connect(function()
	closeSession("", false)
end)
Remotes.RoundEnded.OnClientEvent:Connect(function()
	closeSession("", false)
end)
