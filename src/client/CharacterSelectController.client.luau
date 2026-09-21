--!strict
--[[
	CharacterSelectController
	Preparação do lobby: skin, perk e pronto.
	Não abre no lobby inicial. O shell fica em StarterGui/CharacterSelectUI.model.json;
	a escolha de sobrevivente em si vive na tela dedicada
	SurvivorSelectionController, aberta depois que todos ficam prontos.

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
local LoadoutData = require(ReplicatedStorage.Modules.LoadoutData)
local Remotes = require(ReplicatedStorage.Modules.Remotes)
local SafeWait = require(ReplicatedStorage.Modules.SafeWait)

local LocalPlayer = Players.LocalPlayer
local playerGui = LocalPlayer:WaitForChild("PlayerGui")

local gui = SafeWait.Child(playerGui, "CharacterSelectUI") :: ScreenGui
local overlay = SafeWait.Child(gui, "Overlay") :: Frame
local cardArea = SafeWait.Child(overlay, "CardArea") :: ScrollingFrame
local footer = SafeWait.Child(overlay, "FooterText") :: TextLabel
local closeButton = SafeWait.Child(overlay, "CloseButton") :: TextButton
local title = SafeWait.Child(overlay, "TitleText") :: TextLabel
local subtitle = SafeWait.Child(overlay, "SubtitleText") :: TextLabel
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

title.Text = "PREPARAÇÃO DA PARTIDA"
title.TextSize = 23
title.Position = UDim2.fromOffset(0, 8)
subtitle.Position = UDim2.fromOffset(12, 44)
subtitle.Size = UDim2.new(1, -24, 0, 32)
subtitle.TextSize = 13
subtitle.TextWrapped = true
footer.Position = UDim2.new(0, 16, 1, -116)
footer.Size = UDim2.new(1, -32, 0, 48)
footer.TextSize = 13
closeButton.Position = UDim2.new(0, 16, 1, -14)
closeButton.AnchorPoint = Vector2.new(0, 1)
closeButton.Size = UDim2.new(0.3, -16, 0, 42)
closeButton.Text = "Ver preparação"
closeButton.TextSize = 14

local function actionButton(name: string, text: string, x: number, color: Color3): TextButton
	local button = closeButton:Clone()
	button.Name = name
	button.Text = text
	button.Position = UDim2.new(x, 8, 1, -14)
	button.Size = UDim2.new(0.35, -20, 0, 42)
	button.BackgroundColor3 = color
	button.Parent = overlay
	return button
end
local readyButton = actionButton("ReadyButton", "Pronto", 0.3, Color3.fromRGB(43, 116, 77))
local leaveButton = actionButton("LeaveButton", "Sair da sala", 0.65, Color3.fromRGB(112, 51, 48))

-- Botão separado para reabrir também no celular, sem depender da tecla M.
local reopenGui = Instance.new("ScreenGui")
reopenGui.Name = "WaitingRoomShortcut"
reopenGui.ResetOnSpawn = false
reopenGui.DisplayOrder = 13
reopenGui.Parent = playerGui
local reopen = Instance.new("TextButton")
reopen.AnchorPoint = Vector2.new(0.5, 0)
reopen.Position = UDim2.new(0.5, 0, 0, 12)
reopen.Size = UDim2.fromOffset(240, 42)
reopen.BackgroundColor3 = Color3.fromRGB(37, 71, 58)
reopen.TextColor3 = Color3.new(1, 1, 1)
reopen.Font = Enum.Font.GothamBold
reopen.TextSize = 14
reopen.Text = "Preparar personagem  [C]"
reopen.Visible = false
reopen.Parent = reopenGui

local side = Instance.new("ScrollingFrame")
side.Name = "Preparation"
side.BackgroundColor3 = Color3.fromRGB(19, 24, 27)
side.BorderSizePixel = 0
side.ScrollBarThickness = 4
side.CanvasSize = UDim2.new()
side.AutomaticCanvasSize = Enum.AutomaticSize.Y
side.Parent = overlay
local sidePadding = Instance.new("UIPadding")
sidePadding.PaddingLeft = UDim.new(0, 12)
sidePadding.PaddingRight = UDim.new(0, 12)
sidePadding.PaddingTop = UDim.new(0, 10)
sidePadding.PaddingBottom = UDim.new(0, 12)
sidePadding.Parent = side
local sideLayout = Instance.new("UIListLayout")
sideLayout.Padding = UDim.new(0, 8)
sideLayout.SortOrder = Enum.SortOrder.LayoutOrder
sideLayout.Parent = side

local function sideLabel(text: string, order: number): TextLabel
	local label = Instance.new("TextLabel")
	label.Size = UDim2.new(1, -4, 0, 24)
	label.AutomaticSize = Enum.AutomaticSize.Y
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamMedium
	label.TextSize = 13
	label.TextColor3 = Color3.fromRGB(215, 220, 216)
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.TextYAlignment = Enum.TextYAlignment.Top
	label.TextWrapped = true
	label.Text = text
	label.LayoutOrder = order
	label.Parent = side
	return label
end
sideLabel("PARTICIPANTES", 1)
local memberLabel = sideLabel("", 2)
sideLabel("SKIN · visual humano", 3)
local skinButtons: { [string]: TextButton } = {}
local perkButtons: { [string]: TextButton } = {}

local function optionButton(id: string, name: string, description: string, order: number, action: string): TextButton
	local button = Instance.new("TextButton")
	button.Name = id
	button.Size = UDim2.new(1, -4, 0, 58)
	button.BackgroundColor3 = Color3.fromRGB(32, 38, 43)
	button.BorderSizePixel = 0
	button.Font = Enum.Font.Gotham
	button.TextSize = 12
	button.TextWrapped = true
	button.TextColor3 = Color3.fromRGB(227, 231, 228)
	button.Text = name .. "\n" .. description
	button.LayoutOrder = order
	button.Parent = side
	button.Activated:Connect(function() Remotes.WaitingRoom:FireServer(action, id) end)
	return button
end
for index, skin in LoadoutData.Skins do
	skinButtons[skin.Id] = optionButton(skin.Id, skin.Nome, skin.Descricao, 3 + index, "Skin")
end
sideLabel("PERK · escolha um bônus", 10)
for index, perk in LoadoutData.Perks do
	perkButtons[perk.Id] = optionButton(perk.Id, perk.Nome, perk.Descricao, 10 + index, "Perk")
end
local devRoleTitle = sideLabel("DEV · papel da partida", 20)
local devRoleHint = sideLabel("Escolha um papel para testar sem depender do sorteio. Só aparece para dev autorizado.", 21)
local devRoleButtons: { [string]: TextButton } = {}

local function devRoleButton(id: string, name: string, description: string, order: number): TextButton
	return optionButton(id, name, description, order, "DevRole")
end

devRoleButtons.Random = devRoleButton("Random", "Sorteio normal", "Deixa o jogo sortear normalmente.", 22)
devRoleButtons[GameConfig.Roles.Monster] = devRoleButton(GameConfig.Roles.Monster, "Jason / Monstro", "Força você a nascer como Jason na caverna.", 23)
devRoleButtons[GameConfig.Roles.Survivor] = devRoleButton(GameConfig.Roles.Survivor, "Sobrevivente", "Força gameplay humana de sobrevivência.", 24)
devRoleButtons[GameConfig.Roles.Spy] = devRoleButton(GameConfig.Roles.Spy, "Espião", "Força gameplay de sabotagem.", 25)

local selectingCharacter = false

local function layoutPanels()
	local width = overlay.AbsoluteSize.X
	local bodyHeight = math.max(80, overlay.AbsoluteSize.Y - 210)
	cardArea.Visible = selectingCharacter
	if width >= 900 then
		if selectingCharacter then
			cardArea.Position = UDim2.fromOffset(16, 84)
			cardArea.Size = UDim2.new(0.68, -24, 0, bodyHeight)
			side.Position = UDim2.new(0.68, 0, 0, 84)
			side.Size = UDim2.new(0.32, -16, 0, bodyHeight)
		else
			side.Position = UDim2.fromOffset(120, 84)
			side.Size = UDim2.new(1, -240, 0, bodyHeight)
		end
	else
		if selectingCharacter then
			cardArea.Position = UDim2.fromOffset(12, 84)
			cardArea.Size = UDim2.new(1, -24, 0, math.floor(bodyHeight * 0.6))
			side.Position = UDim2.fromOffset(12, 92 + math.floor(bodyHeight * 0.6))
			side.Size = UDim2.new(1, -24, 0, math.floor(bodyHeight * 0.4) - 8)
		else
			side.Position = UDim2.fromOffset(12, 84)
			side.Size = UDim2.new(1, -24, 0, bodyHeight)
		end
	end
	local grid = cardArea:FindFirstChildOfClass("UIGridLayout")
	if grid then
		local areaWidth = math.max(1, cardArea.AbsoluteSize.X - 12)
		local columns = math.max(1, math.floor((areaWidth + 14) / 264))
		grid.CellSize = UDim2.fromOffset(math.floor((areaWidth - (columns - 1) * 14) / columns), 320)
	end
end
overlay:GetPropertyChangedSignal("AbsoluteSize"):Connect(layoutPanels)
cardArea:GetPropertyChangedSignal("AbsoluteSize"):Connect(layoutPanels)
task.defer(layoutPanels)

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
local inRoom = false
local snapshot: any = nil

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
		if not selectingCharacter then return end
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

local function setVisible(visible: boolean, keepCursorFree: boolean?)
	visible = visible and (inRoom or selectingCharacter)
	gui.Enabled = visible
	-- O fluxo normal deixa a tela completamente limpa. O atalho de reabertura
	-- continua disponível apenas pela tecla M, sem manter um botão sobre o jogo.
	reopen.Visible = false
	readyButton.Visible = inRoom
	leaveButton.Visible = inRoom
	cardArea.Visible = selectingCharacter

	if selectingCharacter then
		title.Text = "ESCOLHA SEU PERSONAGEM"
		subtitle.Text = "Seu papel já foi sorteado. Cada personagem humano só pode ser escolhido por 1 jogador."
		closeButton.Text = "Escolher depois"
		reopen.Text = "Escolher personagem  [C]"
	else
		title.Text = "PREPARAÇÃO DA PARTIDA"
		closeButton.Text = "Ver preparação"
		reopen.Text = "Preparar skin/perk  [C]"
	end
	layoutPanels()

	-- LIBERA O CURSOR enquanto a tela está aberta. A câmera de ombro
	-- (SmoothShiftLock, pacote de movimento) trava a mira no centro; ela lê
	-- este Attribute e solta o mouse enquanto ele estiver true. Some quando
	-- a tela fecha -> a mira volta pro centro pra jogar.
	-- Durante Revealing/Starting a tela de preparacao fecha, mas a partida
	-- ainda nao assumiu a camera. Nao teleporte a mira para o centro nesse
	-- intervalo; o estado Playing fara a troca uma unica vez.
	-- A tela dedicada de escolha (SurvivorSelectionController) assume o mouse
	-- nesta fase. Este controller antigo continua responsável apenas pela
	-- preparação do lobby; nunca pode travar a mira no centro por causa de uma
	-- mudança de CharacterSelectOpen/Role enquanto a escolha está aberta.
	local dedicatedSelection = playerGui:FindFirstChild("SurvivorSelectionUI")
	local selectionOwnsCursor = player:GetAttribute("CharacterSelectOpen") == true
		or ReplicatedStorage:GetAttribute("MatchState") == "Selecting"
		or (dedicatedSelection and (dedicatedSelection :: ScreenGui).Enabled == true)
	local cursorFree = visible or keepCursorFree == true or selectionOwnsCursor
	LocalPlayer:SetAttribute("CursorLivre", if cursorFree then true else nil)
	UserInputService.MouseBehavior = if cursorFree then Enum.MouseBehavior.Default else Enum.MouseBehavior.LockCenter
	UserInputService.MouseIconEnabled = cursorFree

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

	if not selectingCharacter then
		footer.Text = "O papel será sorteado quando a partida começar. Se você cair como Sobrevivente ou Espião, a escolha de personagem abre depois do aviso. Se cair como Monstro, você vira Jason automaticamente."
		footer.TextColor3 = Color3.fromRGB(220, 190, 120)
	elseif myPick then
		local character = CharacterData.GetById(myPick)
		footer.Text = string.format(
			"%s (%s) reservado para você.",
			character and character.Nome or myPick,
			character and character.Apelido or ""
		)
		footer.TextColor3 = Color3.fromRGB(120, 220, 170)
	else
		footer.Text = "Escolha um personagem livre. Cada personagem só pode ser usado por uma pessoa nesta partida."
		footer.TextColor3 = Color3.fromRGB(220, 190, 120)
	end
end

Remotes.CharacterRoster.OnClientEvent:Connect(function(newRoster)
	-- O contrato novo envia um snapshot completo. Aceitar a tabela crua tambem
	-- mantém compatibilidade com servidores antigos durante Studio Play.
	roster = if type(newRoster) == "table" and type(newRoster.roster) == "table"
		then newRoster.roster
		elseif type(newRoster) == "table" then newRoster
		else {}
	refreshCards()
end)

--------------------------------------------------------------------------------
-- Só aparece para quem entrou na fila da partida
--------------------------------------------------------------------------------

closeButton.Activated:Connect(function()
	setVisible(false)
end)
reopen.Activated:Connect(function() setVisible(true) end)
readyButton.Activated:Connect(function()
	-- Mantém o ponteiro disponível no instante do clique, antes mesmo do
	-- próximo Heartbeat atualizar o painel.
	LocalPlayer:SetAttribute("CursorLivre", true)
	UserInputService.MouseBehavior = Enum.MouseBehavior.Default
	UserInputService.MouseIconEnabled = true
	Remotes.WaitingRoom:FireServer("Ready")
end)
leaveButton.Activated:Connect(function() Remotes.WaitingRoom:FireServer("Leave") end)

UserInputService.InputBegan:Connect(function(input: InputObject, gameProcessed: boolean)
	if gameProcessed or (not inRoom and not selectingCharacter) then
		return
	end
	if input.KeyCode == Enum.KeyCode.M then
		setVisible(not gui.Enabled)
	end
end)

Remotes.WaitingRoom.OnClientEvent:Connect(function(newSnapshot)
	if type(newSnapshot) ~= "table" then return end
	snapshot = newSnapshot
	local wasInRoom = inRoom
	local me = nil
	local lines = {}
	for _, member in snapshot.members do
		if member.userId == LocalPlayer.UserId then me = member end
		local character = CharacterData.GetById(member.characterId)
		local devSuffix = if member.canDevRole == true and type(member.devRole) == "string"
			then "\nDEV: " .. member.devRole
			else ""
		table.insert(lines, string.format("%s %s\n%s", if member.ready then "✓" else "○", member.name,
			(if character then character.Nome else "Aguardando sorteio do papel…") .. devSuffix))
	end
	inRoom = snapshot.state == "Waiting" and me ~= nil
	roster = snapshot.roster
	memberLabel.Text = table.concat(lines, "\n\n")
	readyButton.Text = if me and me.ready then "Cancelar pronto" else "Pronto"
	readyButton.BackgroundColor3 = if me and me.ready then Color3.fromRGB(139, 105, 43) else Color3.fromRGB(43, 116, 77)
	for id, button in skinButtons do
		button.BackgroundColor3 = if me and me.skinId == id then Color3.fromRGB(43, 92, 68) else Color3.fromRGB(32, 38, 43)
	end
	for id, button in perkButtons do
		button.BackgroundColor3 = if me and me.perkId == id then Color3.fromRGB(43, 92, 68) else Color3.fromRGB(32, 38, 43)
	end
	local canDevRole = me ~= nil and me.canDevRole == true and inRoom
	devRoleTitle.Visible = canDevRole
	devRoleHint.Visible = canDevRole
	local selectedDevRole = if me and type(me.devRole) == "string" then me.devRole else "Random"
	for id, button in devRoleButtons do
		button.Visible = canDevRole
		button.BackgroundColor3 = if selectedDevRole == id then Color3.fromRGB(109, 45, 45) else Color3.fromRGB(32, 38, 43)
	end
	refreshCards()
	local preserveCursor = (snapshot.state == "Revealing" or snapshot.state == "Starting") and not inRoom
	setVisible(inRoom and (not wasInRoom or gui.Enabled), preserveCursor)
end)

local function refreshCharacterSelectionState()
	-- A tela profissional dedicada é dona desta fase. Este controller continua
	-- exclusivamente com skin/perk/pronto e fecha assim que a seleção começa.
	selectingCharacter = false
	refreshCards()
	if not inRoom and gui.Enabled then
		setVisible(false)
	else
		layoutPanels()
	end
end

LocalPlayer:GetAttributeChangedSignal("CharacterSelectOpen"):Connect(refreshCharacterSelectionState)
LocalPlayer:GetAttributeChangedSignal("Role"):Connect(refreshCharacterSelectionState)

RunService.Heartbeat:Connect(function()
	-- Enquanto o painel de preparação estiver visível, ele é o dono do
	-- ponteiro. O ShiftLock e o menu podem tentar restaurar o LockCenter no
	-- mesmo frame em que o jogador clica em Pronto; reaplicar aqui mantém o
	-- cursor visível e clicável.
	if inRoom and gui.Enabled then
		LocalPlayer:SetAttribute("CursorLivre", true)
		UserInputService.MouseBehavior = Enum.MouseBehavior.Default
		UserInputService.MouseIconEnabled = true
	end
	if selectingCharacter then
		local role = LocalPlayer:GetAttribute("Role")
		subtitle.Text = string.format(
			"Você é %s. Escolha um personagem humano livre para aplicar seus atributos.",
			if type(role) == "string" then role else "participante"
		)
		return
	end
	if not inRoom or not snapshot then return end
	if snapshot.endsAt > 0 then
		local seconds = math.max(0, math.ceil(snapshot.endsAt - Workspace:GetServerTimeNow()))
		subtitle.Text = string.format("Todos prontos · a partida começa em %ds", seconds)
		reopen.Text = string.format("Começa em %ds · Abrir preparação", seconds)
	elseif #snapshot.members < snapshot.minimum then
		subtitle.Text = string.format("%d/%d jogadores · aguardando mais %d para começar", #snapshot.members, snapshot.capacity, snapshot.minimum - #snapshot.members)
		reopen.Text = "Preparar personagem  [C]"
	else
		subtitle.Text = string.format("%d/%d jogadores · aguardando todos ficarem prontos", #snapshot.members, snapshot.capacity)
		reopen.Text = "Preparar personagem  [C]"
	end
end)

refreshCards()
setVisible(false)
refreshCharacterSelectionState()
-- Handshake após conectar os listeners: cobre entrada tardia e cliente lento.
Remotes.WaitingRoom:FireServer("Sync")
