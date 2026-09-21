--!strict
-- Presentation-only orchestration. Server retains reservation, deadline and spawn authority.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local GuiService = game:GetService("GuiService")
local Input = game:GetService("UserInputService")
local Actions = game:GetService("ContextActionService")
local Workspace = game:GetService("Workspace")
local Data = require(ReplicatedStorage.Modules.CharacterData)
local Config = require(ReplicatedStorage.Modules.SurvivorSelectionConfig)
local State = require(ReplicatedStorage.Modules.SurvivorSelectionState)
local Remotes = require(ReplicatedStorage.Modules.Remotes)
local Card = require(script.Parent.SurvivorCard)
local Details = require(script.Parent.SurvivorDetails)
local Preview = require(script.Parent.SurvivorPreview)
local Backdrop = require(script.Parent.SurvivorBackdrop)
local Assets = require(script.Parent.SurvivorSelectionAssets)
local UI = require(script.Parent.SurvivorSelectionTheme)
local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local backgroundGui = UI.Create("ScreenGui", playerGui, {
	Name = "SurvivorSelectionBackdrop", DisplayOrder = 41, ResetOnSpawn = false,
	ScreenInsets = Enum.ScreenInsets.None, Enabled = false, ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
})
local backdrop = Backdrop.Create(backgroundGui)
local gui = UI.Create("ScreenGui", playerGui, {
	Name = "SurvivorSelectionUI", DisplayOrder = 42, ResetOnSpawn = false,
	ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets, Enabled = false, ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
})
local root = UI.Create("CanvasGroup", gui, {
	Name = "Root", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1,
	BorderSizePixel = 0, GroupTransparency = 0,
})
local header = UI.Frame(root, "Header")
local kicker = UI.Label(header, "Kicker", "N Á U F R A G O S   /   PREPARAÇÃO", 10, true)
kicker.TextColor3 = UI.Accent
local title = UI.Label(header, "Title", "QUEM VOCÊ SERÁ?", 28, true)
local timer = UI.Frame(header, "Countdown")
timer.BackgroundTransparency = 0.15
timer.BackgroundColor3 = UI.Panel
UI.Corner(timer, 6)
local timerStroke = UI.Create("UIStroke", timer, { Color = UI.Accent, Transparency = 0.4 })
local timerScale = UI.Create("UIScale", timer, {})
local timerCaption = UI.Label(timer, "Caption", "PARTIDA EM", 9, true)
timerCaption.Size = UDim2.new(1, 0, 0, 15)
timerCaption.Position = UDim2.fromOffset(0, 5)
timerCaption.TextXAlignment = Enum.TextXAlignment.Center
local timerText = UI.Label(timer, "Seconds", "30", 28, true)
timerText.Size = UDim2.new(1, 0, 1, -20)
timerText.Position = UDim2.fromOffset(0, 18)
timerText.TextXAlignment = Enum.TextXAlignment.Center
local body = UI.Frame(root, "Body")
local preview = Preview.Create(body)
local details = Details.Create(body)
local rail = UI.Frame(root, "Roster")
local railTitle = UI.Label(rail, "Caption", "SOBREVIVENTES", 10, true)
railTitle.TextColor3 = UI.Muted
railTitle.Size = UDim2.new(0.5, 0, 0, 16)
local previewHint = UI.Label(rail, "PreviewHint", "", 10)
previewHint.Position = UDim2.fromScale(0.45, 0)
previewHint.Size = UDim2.new(0.55, 0, 0, 16)
previewHint.TextXAlignment = Enum.TextXAlignment.Right
previewHint.TextColor3 = UI.Muted
local cardArea = UI.Create("ScrollingFrame", rail, {
	Name = "Characters", BackgroundTransparency = 1, BorderSizePixel = 0,
	Position = UDim2.fromOffset(0, 19), Size = UDim2.new(1, 0, 1, -19),
	CanvasSize = UDim2.new(), AutomaticCanvasSize = Enum.AutomaticSize.X,
	ScrollingDirection = Enum.ScrollingDirection.X, ScrollBarThickness = 3,
	ScrollBarImageColor3 = UI.Accent, Selectable = false,
})
UI.Create("UIPadding", cardArea, { PaddingLeft = UDim.new(0, 8), PaddingRight = UDim.new(0, 8),
	PaddingTop = UDim.new(0, 6), PaddingBottom = UDim.new(0, 6) })
local rowLayout = UI.Create("UIListLayout", cardArea, { FillDirection = Enum.FillDirection.Horizontal,
	SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 10), VerticalAlignment = Enum.VerticalAlignment.Center })
local footer = UI.Frame(root, "Footer")
local status = UI.Label(footer, "Status", "Escolha quem vai enfrentar a noite.", 11)
status.TextColor3 = UI.Muted
status.TextWrapped = true
local help = UI.Label(footer, "Controls", "", 10)
help.TextColor3 = UI.Muted
local confirm = UI.Create("TextButton", footer, {
	Name = "Confirm", Text = "Selecione um sobrevivente", Font = Enum.Font.GothamBold,
	TextSize = 14, TextColor3 = Color3.fromRGB(8, 22, 26), BackgroundColor3 = UI.Accent,
	BorderSizePixel = 0, AutoButtonColor = false, TextWrapped = true, Selectable = false,
})
UI.Corner(confirm, 5)
local confirmStroke = UI.Create("UIStroke", confirm, { Color = UI.Text, Transparency = 0.8 })
local toastGui = UI.Create("ScreenGui", playerGui, { Name = "SurvivorConfirmedFeedback", DisplayOrder = 43,
	ResetOnSpawn = false, ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets })
local toast = UI.Label(toastGui, "Confirmed", "ESCOLHA CONFIRMADA", 15, true)
toast.AnchorPoint = Vector2.new(0.5, 0)
toast.Position = UDim2.new(0.5, 0, 0, 16)
toast.Size = UDim2.new(0.85, 0, 0, 48)
toast.BackgroundColor3 = UI.Panel
toast.TextColor3 = UI.Accent
toast.TextXAlignment = Enum.TextXAlignment.Center
toast.Visible = false
UI.Corner(toast, 6)

local sounds: { [string]: Sound } = {}
for name, reference in Config.Sounds do
	sounds[name] = UI.Create("Sound", gui, { Name = name, SoundId = Assets.Content("Sounds", reference),
		Volume = if name == "Hover" then 0.08 else 0.22,
		PlaybackSpeed = if name == "Hover" then 1.6 elseif name == "Confirm" then 0.8 else 1.1 })
end
local function sound(name: string)
	local item = sounds[name]
	if item and item.SoundId ~= "" then item:Play() end
end

local cards: { [string]: any } = {}
local snapshot: any = nil
-- `choice` is optimistic UI state. `desired` remains set until the server
-- acknowledges it, so a mouse leave can never make a successful click look
-- like it selected somebody else.
local choice: string? = nil
local hovered: string? = nil -- Hover/focus never sends a remote.
local desired: string? = nil
local readyRequested = false
local pendingConfirm = false
local confirmed = false
local visible = false
local sessionDeadline = 0
local sendGeneration = 0
local lastSecond: number? = nil
local confirmationShown = false
local savedMouse: Enum.MouseBehavior? = nil
local savedIcon = true
local savedCursor: any = nil
local savedFocus: GuiObject? = nil
local detailsScroll = 0
local connections: { RBXScriptConnection } = {}
local function connect(signal: RBXScriptSignal, callback: any)
	table.insert(connections, signal:Connect(callback))
end
local function availability(id: string): string
	return State.Availability(snapshot, id, player.UserId)
end
local function refresh()
	local fallback = Data.Characters[1].Id
	local locked = confirmed or pendingConfirm
	local id = State.Preview(choice, hovered, fallback, locked)
	local character = Data.GetById(id)
	if not character then return end
	local color = Config.GetPortrait(id).Accent
	local mode = if confirmed then "ESCOLHA CONFIRMADA" elseif hovered and hovered ~= choice then "PRÉVIA · AINDA NÃO SELECIONADO"
		elseif choice then "SEU SOBREVIVENTE" else "PRÉVIA · ESCOLHA UM SOBREVIVENTE"
	Details.Update(details, character, mode)
	if visible then preview.Set(id) end
	backdrop.Update(if character.Background and character.Background ~= "" then character.Background else Config.Background, color)
	for cardId, card in cards do
		Card.SetState(card, availability(cardId), choice == cardId, hovered == cardId and not locked, confirmed)
	end
	local selected = Data.GetById(choice)
	local canConfirm = State.CanConfirm(choice, if choice then availability(choice) else "Unavailable", pendingConfirm, confirmed)
	confirm.Active = canConfirm
	confirm.Selectable = canConfirm
	confirm.BackgroundColor3 = if selected then Config.GetPortrait(selected.Id).Accent else UI.Muted
	confirm.BackgroundTransparency = if canConfirm or confirmed or choice then 0 else 0.35
	confirm.Text = if confirmed then "✓  ESCOLHA CONFIRMADA" elseif pendingConfirm then "CONFIRMANDO…"
		elseif desired then "PRONTO" elseif not selected then "Selecione um sobrevivente"
		elseif availability(selected.Id) ~= "Available" then "Personagem reservado · escolha outro"
		else "PRONTO"
	previewHint.Text = if hovered and hovered ~= choice then "PRÉVIA" elseif choice then "ESCOLHA SELECIONADA" else ""
end
local function ensureCardVisible(id: string)
	local card = cards[id]
	if not card then return end
	local x = card.Root.AbsolutePosition.X - cardArea.AbsolutePosition.X + cardArea.CanvasPosition.X
	local width = cardArea.AbsoluteSize.X
	local target = cardArea.CanvasPosition.X
	if x < target + 8 then target = x - 8
	elseif x + card.Root.AbsoluteSize.X > target + width - 8 then target = x + card.Root.AbsoluteSize.X - width + 8 end
	cardArea.CanvasPosition = Vector2.new(math.clamp(target, 0, math.max(0, cardArea.AbsoluteCanvasSize.X - width)), 0)
end
local function hover(id: string?)
	if not visible or confirmed or pendingConfirm or hovered == id then return end
	hovered = id
	if id then sound("Hover") end
	refresh()
end
local function selectCharacter(id: string)
	if not visible or confirmed or pendingConfirm or availability(id) ~= "Available" then return end
	hovered = id
	if desired == id or (choice == id and not desired) then refresh(); return end
	choice = id
	desired = id
	readyRequested = false
	sendGeneration += 1
	local token = sendGeneration
	sound("Select")
	refresh()
	-- Envie a escolha imediatamente. O servidor recebe os RemoteEvents do
	-- mesmo cliente em ordem, portanto o clique seguinte em PRONTO pode enviar
	-- Confirm sem depender de uma janela artificial de 120 ms.
	Remotes.SelectCharacter:FireServer("Select", id)
	-- Se a confirmação de escolha não chegar, apenas sincronize novamente. Não
	-- apague a seleção otimista: isso fazia o botão PRONTO desaparecer e dava a
	-- impressão de que o clique não funcionou.
	task.delay(1.5, function()
		if token ~= sendGeneration or not visible or desired ~= id then return end
		Remotes.SelectCharacter:FireServer("Sync")
	end)
end
local function sendConfirmation()
	if not State.CanConfirm(choice, if choice then availability(choice) else "Unavailable", pendingConfirm, confirmed) then return end
	pendingConfirm = true
	hovered = nil
	refresh()
	Remotes.SelectCharacter:FireServer("Confirm")
	task.delay(1.5, function()
		if visible and pendingConfirm and not confirmed then
			pendingConfirm = false
			Remotes.SelectCharacter:FireServer("Sync")
			refresh()
		end
	end)
end
local function confirmSelection()
	if not visible or confirmed or pendingConfirm or not choice then return end
	if availability(choice) ~= "Available" then return end
	-- Select e Confirm são RemoteEvents confiáveis e ordenados pelo Roblox.
	-- Confirmar imediatamente evita que o botão fique apenas visualmente
	-- disponível enquanto espera um segundo evento de sincronização.
	sendConfirmation()
end
for index, character in Data.Characters do
	local card = Card.Create(cardArea, character, index)
	cards[character.Id] = card
	connect(card.Root.Activated, function() selectCharacter(character.Id) end)
	connect(card.Root.MouseEnter, function() if Input.MouseEnabled then hover(character.Id) end end)
	connect(card.Root.MouseLeave, function() if hovered == character.Id then hover(nil) end end)
	connect(card.Root.SelectionGained, function() hover(character.Id); ensureCardVisible(character.Id) end)
	connect(card.Root.SelectionLost, function() if hovered == character.Id then hover(nil) end end)
end
for index, character in Data.Characters do
	local button = cards[character.Id].Root
	button.NextSelectionLeft = cards[Data.Characters[(index - 2) % #Data.Characters + 1].Id].Root
	button.NextSelectionRight = cards[Data.Characters[index % #Data.Characters + 1].Id].Root
	button.NextSelectionDown = confirm
end
connect(confirm.Activated, confirmSelection)
connect(confirm.SelectionGained, function() confirmStroke.Transparency = 0 end)
connect(confirm.SelectionLost, function() confirmStroke.Transparency = 0.8 end)

local function layout()
	local width, height = root.AbsoluteSize.X, root.AbsoluteSize.Y
	local narrow, short = width < 600, height < 500
	local margin = if narrow or short then 12 else 28
	local headerHeight = if short then 54 else 76
	local footerHeight = if narrow then 82 else 65
	local railHeight = if short then 91 else 125
	local contentWidth = math.max(1, width - margin * 2)
	header.Position = UDim2.fromOffset(margin, 2)
	header.Size = UDim2.fromOffset(contentWidth, headerHeight - 4)
	kicker.Position = UDim2.fromOffset(0, 2)
	kicker.Size = UDim2.new(1, -96, 0, 14)
	kicker.TextSize = if narrow then 9 else 10
	title.Position = UDim2.fromOffset(0, 19)
	title.Size = UDim2.new(1, -96, 0, 32)
	title.TextSize = if narrow or short then 20 else 28
	timer.Position = UDim2.new(1, -82, 0, 0)
	timer.Size = UDim2.fromOffset(82, if short then 48 else 62)
	timerText.TextSize = if short then 23 else 28
	local bodyHeight = math.max(40, height - headerHeight - footerHeight - railHeight - 12)
	body.Position = UDim2.fromOffset(margin, headerHeight)
	body.Size = UDim2.fromOffset(contentWidth, bodyHeight)
	if narrow and not short then
		local heroHeight = math.clamp(bodyHeight * 0.38, 90, 220)
		preview.Root.Position = UDim2.new()
		preview.Root.Size = UDim2.new(1, 0, 0, heroHeight)
		details.Root.Position = UDim2.fromOffset(0, heroHeight + 4)
		details.Root.Size = UDim2.new(1, 0, 1, -heroHeight - 4)
	else
		local infoWidth = math.min(440, contentWidth * (if short then 0.53 else 0.42))
		preview.Root.Position = UDim2.new()
		preview.Root.Size = UDim2.new(1, -infoWidth - 14, 1, 0)
		details.Root.Position = UDim2.new(1, -infoWidth, 0, 0)
		details.Root.Size = UDim2.new(0, infoWidth, 1, 0)
	end
	details.Name.TextSize = if short or narrow then 20 else 26
	rail.Position = UDim2.fromOffset(margin, height - footerHeight - railHeight)
	rail.Size = UDim2.fromOffset(contentWidth, railHeight)
	local cardHeight = if short then 58 else 91
	local cardWidth = math.clamp(math.floor((contentWidth - 76) / #Data.Characters), 78, 124)
	for _, card in cards do card.Root.Size = UDim2.fromOffset(cardWidth, cardHeight) end
	local totalWidth = #Data.Characters * (cardWidth + 10) + 6
	rowLayout.HorizontalAlignment = if totalWidth <= contentWidth then Enum.HorizontalAlignment.Center else Enum.HorizontalAlignment.Left
	footer.Position = UDim2.fromOffset(margin, height - footerHeight + 4)
	footer.Size = UDim2.fromOffset(contentWidth, footerHeight - 8)
	if narrow then
		status.Position, status.Size = UDim2.new(), UDim2.new(1, 0, 0, 23)
		status.TextSize = 10
		confirm.Position = UDim2.fromOffset(0, 27)
		confirm.Size = UDim2.new(1, 0, 0, 44)
		help.Visible = false
	else
		status.Position, status.Size = UDim2.new(), UDim2.new(0.45, -10, 0, 26)
		help.Position, help.Size = UDim2.fromOffset(0, 29), UDim2.new(0.48, -10, 0, 20)
		help.Visible = true
		confirm.Position = UDim2.new(0.49, 0, 0, 4)
		confirm.Size = UDim2.new(0.51, 0, 0, 46)
	end
end
connect(root:GetPropertyChangedSignal("AbsoluteSize"), layout)
task.defer(layout)

local function navigate(direction: number)
	local current = hovered or choice
	local index = if direction > 0 then 0 else 1
	for i, character in Data.Characters do if character.Id == current then index = i; break end end
	for offset = 1, #Data.Characters do
		local target = Data.Characters[(index - 1 + direction * offset) % #Data.Characters + 1].Id
		if availability(target) == "Available" then
			selectCharacter(target)
			ensureCardVisible(target)
			return
		end
	end
end
local function keyboardAction(_name: string, state: Enum.UserInputState, input: InputObject): Enum.ContextActionResult
	if not visible or Input:GetFocusedTextBox() then return Enum.ContextActionResult.Pass end
	if state == Enum.UserInputState.Begin then
		if input.KeyCode == Enum.KeyCode.Left or input.KeyCode == Enum.KeyCode.Up then navigate(-1)
		elseif input.KeyCode == Enum.KeyCode.Right or input.KeyCode == Enum.KeyCode.Down then navigate(1)
		else confirmSelection() end
	end
	return Enum.ContextActionResult.Sink
end
local function inputHelp(kind: Enum.UserInputType)
	local gamepad = string.find(kind.Name, "Gamepad") ~= nil
	help.Text = if gamepad then "A escolher · X confirmar · analógico direito: detalhes"
		elseif kind == Enum.UserInputType.Touch then "Toque para escolher · confirme abaixo"
		else "← → escolher · Enter / X confirmar"
	if visible and gamepad and not GuiService.SelectedObject and not confirmed then
		GuiService.SelectedObject = cards[choice or Data.Characters[1].Id].Root
	end
end
connect(Input.LastInputTypeChanged, inputHelp)
connect(Input.InputChanged, function(input: InputObject)
	if input.KeyCode == Enum.KeyCode.Thumbstick2 then
		detailsScroll = if math.abs(input.Position.Y) > 0.2 then -input.Position.Y else 0
	end
end)
inputHelp(Input:GetLastInputType())

local function setVisible(value: boolean)
	if visible == value then return end
	visible = value
	gui.Enabled, backgroundGui.Enabled = value, value
	if value then
		savedMouse, savedIcon, savedCursor = Input.MouseBehavior, Input.MouseIconEnabled, player:GetAttribute("CursorLivre")
		savedFocus = GuiService.SelectedObject
		player:SetAttribute("CursorLivre", true)
		Input.MouseBehavior = Enum.MouseBehavior.Default
		Input.MouseIconEnabled = true
		root.GroupTransparency = 1
		root.Position = UDim2.fromOffset(0, 10)
		UI.Tween(root, { GroupTransparency = 0, Position = UDim2.new() }, 0.3)
		lastSecond = nil
		Actions:BindActionAtPriority("SurvivorSelectionKeys", keyboardAction, false, 3000,
			Enum.KeyCode.Left, Enum.KeyCode.Right, Enum.KeyCode.Up, Enum.KeyCode.Down,
			Enum.KeyCode.Return, Enum.KeyCode.KeypadEnter, Enum.KeyCode.X, Enum.KeyCode.ButtonX)
		inputHelp(Input:GetLastInputType())
		refresh()
	else
		detailsScroll = 0
		sendGeneration += 1
		desired, hovered = nil, nil
		Actions:UnbindAction("SurvivorSelectionKeys")
		preview.Clear()
		player:SetAttribute("CursorLivre", savedCursor)
		if savedMouse then Input.MouseBehavior = savedMouse end
		Input.MouseIconEnabled = savedIcon
		if GuiService.SelectedObject and GuiService.SelectedObject:IsDescendantOf(gui) then
			GuiService.SelectedObject = if savedFocus and savedFocus.Parent then savedFocus else nil
		end
	end
end
local function refreshVisibility()
	local matchState = if ReplicatedStorage.GetAttribute then ReplicatedStorage:GetAttribute("MatchState") else nil
	local selecting = snapshot and snapshot.state == "Selecting"
		and (matchState == nil or matchState == "Selecting")
	local allowed = player:GetAttribute("CharacterSelectOpen") == true
		or (confirmed and player:GetAttribute("InWaitingRoom") == true)
		or (selecting and player:GetAttribute("InWaitingRoom") == true and not confirmed)
	setVisible(selecting and allowed and player:GetAttribute("Role") ~= "Monstro" or false)
end
local function showConfirmation()
	if confirmationShown or not visible then return end
	confirmationShown = true
	sound("Confirm")
	toast.Visible = true
	toast.TextTransparency = 0
	toast.BackgroundTransparency = 0.1
	UI.Tween(confirmStroke, { Transparency = 0 }, 0.15)
	task.delay(0.75, function()
		UI.Tween(toast, { TextTransparency = 1, BackgroundTransparency = 1 }, 0.3)
		task.delay(0.32, function() toast.Visible = false end)
	end)
end
connect(Remotes.CharacterRoster.OnClientEvent, function(payload: any)
	if type(payload) ~= "table" or payload.state == nil then return end
	if payload.state == "Selecting" and payload.endsAt ~= sessionDeadline then
		sessionDeadline = payload.endsAt
		hovered, desired, choice = nil, nil, nil
		readyRequested = false
		confirmed, pendingConfirm, confirmationShown = false, false, false
		sendGeneration += 1
		details.Root.CanvasPosition = Vector2.zero
		cardArea.CanvasPosition = Vector2.zero
	end
	snapshot = payload
	local serverChoice = if type(payload.choices) == "table" then payload.choices[player.UserId] else nil
	if desired then
		if serverChoice == desired then
			choice = serverChoice
			desired = nil
		else
			-- An older broadcast can arrive after a fast local click. Preserve the
			-- local selection until the server accepts it or sends a rejection.
			choice = desired
		end
	else
		choice = serverChoice
	end
	-- Attribute replication and RemoteEvent replication can arrive in either
	-- order. Never let an older roster (the Select acknowledgement) erase the
	-- confirmed flag that the server already replicated for this player.
	local serverConfirmed = type(payload.confirmed) == "table" and payload.confirmed[player.UserId] == true
	confirmed = serverConfirmed or player:GetAttribute("CharacterSelectionConfirmed") == true
	if confirmed then pendingConfirm = false; desired = nil; readyRequested = false; showConfirmation() end
	local ready = 0
	if type(payload.confirmed) == "table" then
		for userId, value in payload.confirmed do
			local id = payload.choices and payload.choices[userId]
			if value and not Data.IsMonsterCharacter(id) then ready += 1 end
		end
	end
	status.Text = if confirmed then "Escolha confirmada. Aguardando a equipe."
		else string.format("%d escolhas confirmadas · a noite se aproxima", ready)
	if choice then confirm.NextSelectionUp = cards[choice] and cards[choice].Root end
	refresh()
	refreshVisibility()
	if readyRequested and not desired and not confirmed then
		readyRequested = false
		sendConfirmation()
	end
end)
connect(Remotes.LobbyMessage.OnClientEvent, function(message: any)
	if not visible or type(message) ~= "string" then return end
	desired, pendingConfirm, readyRequested = nil, false, false
	choice = if snapshot and type(snapshot.choices) == "table" then snapshot.choices[player.UserId] else nil
	status.Text = message
	refresh()
end)
for _, attribute in { "CharacterSelectOpen", "Role", "InWaitingRoom", "CharacterSelectionConfirmed" } do
	connect(player:GetAttributeChangedSignal(attribute), function()
		if player:GetAttribute("CharacterSelectionConfirmed") == true and visible then
			confirmed = true
			pendingConfirm = false
			showConfirmation()
			refresh()
		end
		refreshVisibility()
	end)
end
connect(RunService.RenderStepped, function(dt: number)
	if not visible then return end
	-- O CustomShiftLock lê este atributo a cada frame. Mantê-lo aqui evita que
	-- outro painel do lobby restaure o LockCenter no meio de um clique.
	player:SetAttribute("CursorLivre", true)
	Input.MouseBehavior = Enum.MouseBehavior.Default
	Input.MouseIconEnabled = true
	preview.Step(os.clock())
	if detailsScroll ~= 0 then
		local maximum = math.max(0, details.Root.AbsoluteCanvasSize.Y - details.Root.AbsoluteSize.Y)
		details.Root.CanvasPosition = Vector2.new(0, math.clamp(details.Root.CanvasPosition.Y + detailsScroll * dt * 280, 0, maximum))
	end
end)
connect(RunService.Heartbeat, function()
	if not visible or not snapshot or type(snapshot.endsAt) ~= "number" then return end
	local seconds = math.max(0, math.ceil(snapshot.endsAt - Workspace:GetServerTimeNow()))
	if seconds == lastSecond then return end
	lastSecond = seconds
	timerText.Text = string.format("%02d", seconds)
	local warning = seconds <= Config.WarningAt
	local color = if warning then Color3.fromRGB(238, 132, 101) else UI.Accent
	timerText.TextColor3, timerStroke.Color = color, color
	timerCaption.Text = if warning then "PREPARE-SE" else "PARTIDA EM"
	if warning and seconds > 0 then
		sound("Countdown")
		timerScale.Scale = 1.08
		UI.Tween(timerScale, { Scale = 1 }, 0.3)
	end
	-- The server auto-confirms the acknowledged choice (or a free fallback).
end)
script.Destroying:Connect(function()
	setVisible(false)
	for _, connection in connections do connection:Disconnect() end
	preview.Clear()
	gui:Destroy()
	backgroundGui:Destroy()
	toastGui:Destroy()
end)
Remotes.SelectCharacter:FireServer("Sync")
