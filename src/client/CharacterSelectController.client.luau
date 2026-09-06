--!strict
--[[
	CharacterSelectController
	Tela de escolha de personagem (aparece no Lobby, some quando a partida
	começa). O shell da UI está em StarterGui/CharacterSelectUI.model.json;
	os CARDS são montados aqui a partir de Modules/CharacterData -- adicionar
	um personagem novo lá faz o card aparecer sozinho, sem tocar em UI.

	CADA CARD tem: nome, apelido, os 7 atributos em barra (com o número),
	a passiva única quando existe, e o total (sempre 350).

	EXCLUSIVIDADE EM TEMPO REAL: o servidor manda Remotes.CharacterRoster
	(characterId -> UserId de quem pegou) sempre que alguém escolhe, troca ou
	sai. O card de um personagem tomado por OUTRO fica escurecido e não
	clicável; o SEU fica destacado em verde. Quem valida de verdade é o
	servidor (CharacterStatsApplier) -- aqui é só o feedback.

	As cores das barras vêm do próprio valor (vermelho fraco -> verde forte),
	então dá pra bater o olho e ver o perfil do personagem sem ler número.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local CharacterData = require(ReplicatedStorage.Modules.CharacterData)
local GameConfig = require(ReplicatedStorage.Modules.GameConfig)
local Remotes = require(ReplicatedStorage.Modules.Remotes)
local SafeWait = require(ReplicatedStorage.Modules.SafeWait)

local LocalPlayer = Players.LocalPlayer
local playerGui = LocalPlayer:WaitForChild("PlayerGui")

local gui = SafeWait.Child(playerGui, "CharacterSelectUI") :: ScreenGui
local overlay = SafeWait.Child(gui, "Overlay") :: Frame
local cardArea = SafeWait.Child(overlay, "CardArea") :: ScrollingFrame
local footer = SafeWait.Child(overlay, "FooterText") :: TextLabel
local closeButton = SafeWait.Child(overlay, "CloseButton") :: TextButton

--------------------------------------------------------------------------------
-- Estado
--------------------------------------------------------------------------------

type CardRefs = {
	button: TextButton,
	stroke: UIStroke,
	status: TextLabel,
}

local cards: { [string]: CardRefs } = {}
local roster: { [string]: number } = {}

--------------------------------------------------------------------------------
-- Construção dos cards
--------------------------------------------------------------------------------

-- Vermelho (0) -> amarelo (50) -> verde (100). Dá pra ler o perfil de relance.
local function statColor(value: number): Color3
	local t = math.clamp(value / 100, 0, 1)
	if t < 0.5 then
		return Color3.fromRGB(215, 70, 60):Lerp(Color3.fromRGB(225, 190, 65), t * 2)
	end
	return Color3.fromRGB(225, 190, 65):Lerp(Color3.fromRGB(80, 200, 130), (t - 0.5) * 2)
end

local function buildStatRow(parent: Instance, order: number, statKey: string, value: number)
	local row = Instance.new("Frame")
	row.Name = statKey
	row.LayoutOrder = order
	row.Size = UDim2.new(1, 0, 0, 17)
	row.BackgroundTransparency = 1
	row.Parent = parent

	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromOffset(84, 17)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.Gotham
	label.TextSize = 12
	label.TextColor3 = Color3.fromRGB(190, 190, 200)
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.Text = CharacterData.StatLabels[statKey] or statKey
	label.Parent = row

	local track = Instance.new("Frame")
	track.Position = UDim2.fromOffset(86, 4)
	track.Size = UDim2.new(1, -116, 0, 9)
	track.BackgroundColor3 = Color3.fromRGB(28, 30, 36)
	track.BorderSizePixel = 0
	track.Parent = row
	local trackCorner = Instance.new("UICorner")
	trackCorner.CornerRadius = UDim.new(1, 0)
	trackCorner.Parent = track

	local fill = Instance.new("Frame")
	fill.Size = UDim2.fromScale(math.clamp(value / 100, 0, 1), 1)
	fill.BackgroundColor3 = statColor(value)
	fill.BorderSizePixel = 0
	fill.Parent = track
	local fillCorner = Instance.new("UICorner")
	fillCorner.CornerRadius = UDim.new(1, 0)
	fillCorner.Parent = fill

	local number = Instance.new("TextLabel")
	number.AnchorPoint = Vector2.new(1, 0)
	number.Position = UDim2.new(1, 0, 0, 0)
	number.Size = UDim2.fromOffset(26, 17)
	number.BackgroundTransparency = 1
	number.Font = Enum.Font.GothamBold
	number.TextSize = 12
	number.TextColor3 = Color3.fromRGB(235, 235, 240)
	number.TextXAlignment = Enum.TextXAlignment.Right
	number.Text = tostring(value)
	number.Parent = row
end

local function buildCard(character: CharacterData.Character, order: number)
	local button = Instance.new("TextButton")
	button.Name = character.Id
	button.LayoutOrder = order
	button.BackgroundColor3 = Color3.fromRGB(22, 24, 30)
	button.BorderSizePixel = 0
	button.AutoButtonColor = false
	button.Text = ""
	button.Parent = cardArea

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 10)
	corner.Parent = button

	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(70, 74, 88)
	stroke.Thickness = 1.5
	stroke.Transparency = 0.3
	stroke.Parent = button

	local padding = Instance.new("UIPadding")
	padding.PaddingTop = UDim.new(0, 12)
	padding.PaddingLeft = UDim.new(0, 12)
	padding.PaddingRight = UDim.new(0, 12)
	padding.PaddingBottom = UDim.new(0, 10)
	padding.Parent = button

	local layout = Instance.new("UIListLayout")
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, 2)
	layout.Parent = button

	local nome = Instance.new("TextLabel")
	nome.LayoutOrder = 1
	nome.Size = UDim2.new(1, 0, 0, 20)
	nome.BackgroundTransparency = 1
	nome.Font = Enum.Font.GothamBold
	nome.TextSize = 15
	nome.TextColor3 = Color3.fromRGB(255, 255, 255)
	nome.TextXAlignment = Enum.TextXAlignment.Left
	nome.TextTruncate = Enum.TextTruncate.AtEnd
	nome.Text = character.Nome
	nome.Parent = button

	local apelido = Instance.new("TextLabel")
	apelido.LayoutOrder = 2
	apelido.Size = UDim2.new(1, 0, 0, 16)
	apelido.BackgroundTransparency = 1
	apelido.Font = Enum.Font.GothamMedium
	apelido.TextSize = 12
	apelido.TextColor3 = Color3.fromRGB(150, 175, 220)
	apelido.TextXAlignment = Enum.TextXAlignment.Left
	apelido.Text = character.Apelido
	apelido.Parent = button

	local spacer = Instance.new("Frame")
	spacer.LayoutOrder = 3
	spacer.Size = UDim2.new(1, 0, 0, 6)
	spacer.BackgroundTransparency = 1
	spacer.Parent = button

	for index, statKey in CharacterData.StatOrder do
		buildStatRow(button, 10 + index, statKey, (character.Stats :: any)[statKey])
	end

	local total = Instance.new("TextLabel")
	total.LayoutOrder = 30
	total.Size = UDim2.new(1, 0, 0, 16)
	total.BackgroundTransparency = 1
	total.Font = Enum.Font.Gotham
	total.TextSize = 11
	total.TextColor3 = Color3.fromRGB(120, 122, 132)
	total.TextXAlignment = Enum.TextXAlignment.Left
	total.Text = string.format("Total: %d pontos", CharacterData.SumStats(character))
	total.Parent = button

	if character.PassivaUnica then
		local passiva = Instance.new("TextLabel")
		passiva.LayoutOrder = 31
		passiva.Size = UDim2.new(1, 0, 0, 28)
		passiva.BackgroundTransparency = 1
		passiva.Font = Enum.Font.GothamMedium
		passiva.TextSize = 11
		passiva.TextColor3 = Color3.fromRGB(230, 190, 100)
		passiva.TextXAlignment = Enum.TextXAlignment.Left
		passiva.TextWrapped = true
		passiva.TextYAlignment = Enum.TextYAlignment.Top
		passiva.Text = "★ " .. character.PassivaUnica
		passiva.Parent = button
	end

	local status = Instance.new("TextLabel")
	status.LayoutOrder = 40
	status.Size = UDim2.new(1, 0, 0, 16)
	status.BackgroundTransparency = 1
	status.Font = Enum.Font.GothamBold
	status.TextSize = 12
	status.TextXAlignment = Enum.TextXAlignment.Left
	status.TextColor3 = Color3.fromRGB(150, 150, 160)
	status.Text = ""
	status.Parent = button

	button.Activated:Connect(function()
		local ownerId = roster[character.Id]
		if ownerId and ownerId ~= LocalPlayer.UserId then
			return -- já é de outro
		end
		Remotes.SelectCharacter:FireServer(character.Id)
	end)

	cards[character.Id] = { button = button, stroke = stroke, status = status }
end

for index, character in CharacterData.Characters do
	buildCard(character, index)
end

--------------------------------------------------------------------------------
-- Visibilidade
--------------------------------------------------------------------------------

local function setVisible(visible: boolean)
	if gui.Enabled == visible then
		return
	end
	gui.Enabled = visible

	-- LIBERA O CURSOR enquanto a tela está aberta. A câmera de ombro
	-- (SmoothShiftLock, pacote de movimento) trava a mira no centro; ela lê
	-- este Attribute e solta o mouse enquanto ele estiver true. Some quando
	-- a tela fecha -> a mira volta pro centro pra jogar.
	LocalPlayer:SetAttribute("CursorLivre", visible or nil)

	if visible then
		overlay.BackgroundTransparency = 1
		TweenService:Create(overlay, TweenInfo.new(0.25), { BackgroundTransparency = 0.15 }):Play()
	end
end

--------------------------------------------------------------------------------
-- Roster -> estado visual
--------------------------------------------------------------------------------

local function refreshCards()
	local myPick: string? = nil

	for id, refs in cards do
		local ownerId = roster[id]
		local mine = ownerId == LocalPlayer.UserId
		local takenByOther = ownerId ~= nil and not mine

		if mine then
			myPick = id
			refs.stroke.Color = Color3.fromRGB(80, 210, 140)
			refs.stroke.Transparency = 0
			refs.stroke.Thickness = 2.5
			refs.button.BackgroundColor3 = Color3.fromRGB(26, 38, 32)
			refs.status.Text = "SEU PERSONAGEM"
			refs.status.TextColor3 = Color3.fromRGB(80, 210, 140)
			refs.button.Active = true
		elseif takenByOther then
			local other = Players:GetPlayerByUserId(ownerId :: number)
			refs.stroke.Color = Color3.fromRGB(60, 62, 72)
			refs.stroke.Transparency = 0.6
			refs.stroke.Thickness = 1.5
			refs.button.BackgroundColor3 = Color3.fromRGB(15, 16, 19)
			refs.status.Text = "Escolhido por " .. (other and other.DisplayName or "outro jogador")
			refs.status.TextColor3 = Color3.fromRGB(190, 90, 80)
			refs.button.Active = false
		else
			refs.stroke.Color = Color3.fromRGB(70, 74, 88)
			refs.stroke.Transparency = 0.3
			refs.stroke.Thickness = 1.5
			refs.button.BackgroundColor3 = Color3.fromRGB(22, 24, 30)
			refs.status.Text = "Clique para escolher"
			refs.status.TextColor3 = Color3.fromRGB(150, 150, 160)
			refs.button.Active = true
		end
	end

	if myPick then
		local character = CharacterData.GetById(myPick)
		footer.Text = string.format(
			"Você é %s (%s). Feche e vá ao pilar Iniciar Partida — ou clique em outro card pra trocar.",
			character and character.Nome or myPick,
			character and character.Apelido or ""
		)
		footer.TextColor3 = Color3.fromRGB(120, 220, 170)
	else
		footer.Text = "Escolha um personagem. Se a partida começar sem escolha, você recebe um sorteado."
		footer.TextColor3 = Color3.fromRGB(220, 190, 120)
	end
end

Remotes.CharacterRoster.OnClientEvent:Connect(function(newRoster, roundActive)
	roster = if type(newRoster) == "table" then newRoster else {}
	refreshCards()
	if roundActive == true then
		setVisible(false) -- entrei no meio de uma partida
	end
end)

--------------------------------------------------------------------------------
-- Aparece no Lobby, some na partida
--------------------------------------------------------------------------------

local UserInputService = game:GetService("UserInputService")

-- No Lobby dá pra fechar (pra ir ao pilar "Iniciar Partida") e reabrir com C.
-- Enquanto a partida está rolando, a tela fica desligada de vez.
local roundRunning = false

closeButton.Activated:Connect(function()
	setVisible(false)
end)

UserInputService.InputBegan:Connect(function(input: InputObject, gameProcessed: boolean)
	if gameProcessed or roundRunning then
		return
	end
	if input.KeyCode == Enum.KeyCode.C then
		setVisible(not gui.Enabled)
	end
end)

-- A partida começando esconde a tela; o fim da partida (volta pro Lobby)
-- traz de volta pra quem quiser trocar de personagem.
Remotes.RoundStateChanged.OnClientEvent:Connect(function(phase: string)
	roundRunning = true
	if phase == GameConfig.PhaseOrder[1] then
		setVisible(false)
	end
end)
Remotes.RoundEnded.OnClientEvent:Connect(function()
	roundRunning = false
	task.delay(2, function()
		if not roundRunning then
			setVisible(true)
		end
	end)
end)

refreshCards()
setVisible(true)
