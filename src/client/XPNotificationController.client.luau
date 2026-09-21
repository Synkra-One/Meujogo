--!strict
--[[
	XPNotificationController
	Notificação discreta de XP no canto superior direito, durante a partida.

	O QUE ELE *NÃO* FAZ
	  Não calcula XP, não decide o que vale uma ação e não guarda total
	  nenhum. Ele desenha o que o servidor mandou por Remotes.
	  MatchXPNotification, que é Server -> Client e não tem OnServerEvent --
	  não existe caminho daqui pra criar ou alterar recompensa. Se este
	  arquivo inteiro for adulterado por um exploit, o pior que acontece é o
	  jogador ver números errados NA PRÓPRIA TELA: o relatório final vem do
	  servidor de novo, e é ele que vale.

	POR QUE O CANTO SUPERIOR DIREITO
	  É o único canto livre da HUD hoje: objetivos em cima à esquerda, fase no
	  topo ao centro, papel embaixo à esquerda, munição embaixo ao centro,
	  minimapa e fôlego embaixo à direita, vinheta de medo no meio. A posição
	  vem de MatchRewardsConfig.Notification.Position -- nenhum número de
	  posição está escrito aqui, então mover a pilha é mexer na config.

	SEGURANÇA DE TELA (computador e celular)
	  - IgnoreGuiInset = false: a pilha começa ABAIXO da barra do Roblox, que
	    é onde fica o notch/câmera no celular.
	  - Largura em Scale com piso e teto em pixels (UISizeConstraint): num
	    monitor ultrawide o card não vira uma faixa gigante, e num celular
	    estreito ele não fica ilegível.
	  - Nada de input: os frames têm Active = false e não capturam toque nem
	    clique, então a notificação nunca rouba um tiro ou um movimento.

	FILA
	  Uma por vez (MaxVisible), em ordem de prioridade. Ações IGUAIS que
	  chegam dentro de MergeWindow viram uma linha só ("Acertou o Monstro ×3
	  -- +30 XP"), tanto na fila quanto num card já visível -- é o que impede
	  uma rajada de acertos de virar seis cards enfileirados. Fila cheia
	  descarta a de MENOR prioridade, nunca a mais importante (escapar,
	  concluir objetivo, salvar aliado, eliminar sobrevivente).
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Modules.MatchRewardsConfig)
local Remotes = require(ReplicatedStorage.Modules.Remotes)

local CFG = Config.Notification
local COLORS = CFG.Colors

local LocalPlayer = Players.LocalPlayer
local playerGui = LocalPlayer:WaitForChild("PlayerGui")

--------------------------------------------------------------------------------
-- Cores
--------------------------------------------------------------------------------

local function color(triple: { number }): Color3
	return Color3.new(triple[1], triple[2], triple[3])
end

local BACKGROUND = color(COLORS.Background)
local STROKE = color(COLORS.Stroke)
local LABEL_COLOR = color(COLORS.Label)
local POSITIVE = color(COLORS.Positive)
local HIGHLIGHT = color(COLORS.Highlight)
local NEGATIVE = color(COLORS.Negative)

local function xpColor(xp: number, priority: number): Color3
	if xp < 0 then
		return NEGATIVE
	end
	return if priority >= 4 then HIGHLIGHT else POSITIVE
end

--------------------------------------------------------------------------------
-- Interface
--------------------------------------------------------------------------------

local screen = Instance.new("ScreenGui")
screen.Name = "MatchXPNotifications"
screen.ResetOnSpawn = false -- a pilha não pode sumir quando o jogador respawna
screen.IgnoreGuiInset = false -- respeita a barra do topo / notch do celular
screen.DisplayOrder = CFG.DisplayOrder
screen.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
screen.Enabled = false
screen.Parent = playerGui

local stack = Instance.new("Frame")
stack.Name = "Stack"
stack.BackgroundTransparency = 1
stack.AnchorPoint = Vector2.new(CFG.Position.AnchorPoint[1], CFG.Position.AnchorPoint[2])
stack.Position = UDim2.new(
	CFG.Position.Scale[1],
	CFG.Position.Offset[1],
	CFG.Position.Scale[2],
	CFG.Position.Offset[2]
)
stack.Size = UDim2.new(CFG.CardWidthScale, 0, 0, (CFG.CardHeight + CFG.CardSpacing) * CFG.MaxVisible)
-- Sem input: a notificação nunca pode engolir um clique/toque do jogador.
stack.Active = false
stack.Selectable = false
stack.Parent = screen

local stackWidth = Instance.new("UISizeConstraint")
stackWidth.MinSize = Vector2.new(CFG.CardMinWidth, 0)
stackWidth.MaxSize = Vector2.new(CFG.CardMaxWidth, math.huge)
stackWidth.Parent = stack

local layout = Instance.new("UIListLayout")
layout.FillDirection = Enum.FillDirection.Vertical
layout.HorizontalAlignment = Enum.HorizontalAlignment.Right
layout.VerticalAlignment = Enum.VerticalAlignment.Top
layout.SortOrder = Enum.SortOrder.LayoutOrder
layout.Padding = UDim.new(0, CFG.CardSpacing)
layout.Parent = stack

--------------------------------------------------------------------------------
-- Som
--------------------------------------------------------------------------------

-- Os SoundIds ainda não existem no projeto (ver a nota em
-- MatchRewardsConfig.Notification.Sound). String vazia simplesmente não toca
-- nada -- o card aparece igual, sem erro no Output.
local function playSound(isPenalty: boolean)
	if not CFG.Sound.Enabled then
		return
	end
	-- Gancho pra uma opção futura de "desligar sons" nas configurações do
	-- jogador. Nada escreve neste Attribute hoje, então o som fica ligado.
	if LocalPlayer:GetAttribute(CFG.MuteAttribute) == true then
		return
	end

	local id = if isPenalty then CFG.Sound.PenaltyId else CFG.Sound.GainId
	if id == "" then
		return
	end

	local sound = Instance.new("Sound")
	sound.SoundId = id
	sound.Volume = CFG.Sound.Volume
	sound.Parent = SoundService
	sound.Ended:Once(function()
		sound:Destroy()
	end)
	-- Rede de segurança: se o id for inválido, Ended nunca dispara e o Sound
	-- ficaria pendurado no SoundService pra sempre.
	task.delay(5, function()
		if sound.Parent then
			sound:Destroy()
		end
	end)
	sound:Play()
end

local lastSoundAt = -math.huge

local function maybePlaySound(isPenalty: boolean)
	local now = os.clock()
	-- Limite de frequência: sem isso, uma rajada de acertos vira uma
	-- metralhadora de bipes -- exatamente o oposto de "discreto".
	if now - lastSoundAt < CFG.Sound.MinInterval then
		return
	end
	lastSoundAt = now
	playSound(isPenalty)
end

--------------------------------------------------------------------------------
-- Fila
--------------------------------------------------------------------------------

type Entry = {
	ActionId: string,
	Label: string,
	XP: number,
	Priority: number,
	Count: number,
	QueuedAt: number,
}

type Card = {
	Entry: Entry,
	Frame: Frame,
	LabelText: TextLabel,
	XPText: TextLabel,
	ShownAt: number,
	Closing: boolean,
}

local queue: { Entry } = {}
local visible: { Card } = {}
local seenIds: { [string]: boolean } = {} -- descarta payload repetido
local seenOrder: { string } = {}

local function formatXP(xp: number): string
	-- Menos real (U+2212), não hífen: o traço do hífen fica visualmente menor
	-- que o "+" e a lista de valores parece desalinhada.
	return if xp >= 0 then string.format("+%d XP", xp) else string.format("\u{2212}%d XP", -xp)
end

local function entryLabel(entry: Entry): string
	if entry.Count > 1 then
		return string.format("%s ×%d", entry.Label, entry.Count)
	end
	return entry.Label
end

local function refreshCard(card: Card)
	card.LabelText.Text = entryLabel(card.Entry)
	card.XPText.Text = formatXP(card.Entry.XP)
	card.XPText.TextColor3 = xpColor(card.Entry.XP, card.Entry.Priority)
end

--------------------------------------------------------------------------------
-- Cards
--------------------------------------------------------------------------------

local function destroyCard(card: Card)
	local index = table.find(visible, card)
	if index then
		table.remove(visible, index)
	end
	card.Frame:Destroy()
	if #visible == 0 and #queue == 0 then
		screen.Enabled = false
	end
end

local function closeCard(card: Card)
	if card.Closing then
		return
	end
	card.Closing = true

	local info = TweenInfo.new(CFG.FadeOutTime, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
	local slide = UDim2.new(CFG.SlideFraction, 0, 0, 0)

	TweenService:Create(card.Frame, info, {
		BackgroundTransparency = 1,
		Position = slide,
	}):Play()
	TweenService:Create(card.LabelText, info, { TextTransparency = 1 }):Play()
	TweenService:Create(card.XPText, info, { TextTransparency = 1 }):Play()
	local stroke = card.Frame:FindFirstChildOfClass("UIStroke")
	if stroke then
		TweenService:Create(stroke, info, { Transparency = 1 }):Play()
	end

	task.delay(CFG.FadeOutTime, function()
		destroyCard(card)
	end)
end

local function createCard(entry: Entry): Card
	local frame = Instance.new("Frame")
	frame.Name = "XPNotification"
	frame.Size = UDim2.new(1, 0, 0, CFG.CardHeight)
	frame.BackgroundColor3 = BACKGROUND
	frame.BackgroundTransparency = 1 -- entra com fade
	frame.BorderSizePixel = 0
	frame.Active = false
	frame.Selectable = false
	-- Prioridade alta primeiro na pilha (LayoutOrder menor = mais acima).
	frame.LayoutOrder = 10 - entry.Priority
	frame.Position = UDim2.new(CFG.SlideFraction, 0, 0, 0)

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 5)
	corner.Parent = frame

	local stroke = Instance.new("UIStroke")
	stroke.Color = STROKE
	stroke.Thickness = 1
	stroke.Transparency = 1
	stroke.Parent = frame

	local padding = Instance.new("UIPadding")
	padding.PaddingLeft = UDim.new(0, 10)
	padding.PaddingRight = UDim.new(0, 10)
	padding.PaddingTop = UDim.new(0, 5)
	padding.PaddingBottom = UDim.new(0, 5)
	padding.Parent = frame

	local labelText = Instance.new("TextLabel")
	labelText.Name = "Label"
	labelText.BackgroundTransparency = 1
	labelText.Size = UDim2.new(1, 0, 0.5, 0)
	labelText.Position = UDim2.fromScale(0, 0)
	labelText.Font = Enum.Font.SourceSans
	labelText.TextColor3 = LABEL_COLOR
	labelText.TextTransparency = 1
	labelText.TextScaled = true
	labelText.TextXAlignment = Enum.TextXAlignment.Right
	labelText.TextYAlignment = Enum.TextYAlignment.Bottom
	labelText.Parent = frame

	-- TextScaled sozinho deixaria o texto gigante num card largo. O
	-- UITextSizeConstraint mantém a escala legível nos dois extremos
	-- (celular estreito e monitor largo).
	local labelSize = Instance.new("UITextSizeConstraint")
	labelSize.MinTextSize = 10
	labelSize.MaxTextSize = 15
	labelSize.Parent = labelText

	local xpText = Instance.new("TextLabel")
	xpText.Name = "XP"
	xpText.BackgroundTransparency = 1
	xpText.Size = UDim2.new(1, 0, 0.5, 0)
	xpText.Position = UDim2.fromScale(0, 0.5)
	xpText.Font = Enum.Font.SourceSansBold
	xpText.TextTransparency = 1
	xpText.TextScaled = true
	xpText.TextXAlignment = Enum.TextXAlignment.Right
	xpText.TextYAlignment = Enum.TextYAlignment.Top
	xpText.Parent = frame

	local xpSize = Instance.new("UITextSizeConstraint")
	xpSize.MinTextSize = 12
	xpSize.MaxTextSize = 19
	xpSize.Parent = xpText

	frame.Parent = stack

	local card: Card = {
		Entry = entry,
		Frame = frame,
		LabelText = labelText,
		XPText = xpText,
		ShownAt = os.clock(),
		Closing = false,
	}
	refreshCard(card)

	local info = TweenInfo.new(CFG.FadeInTime, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	TweenService:Create(frame, info, {
		BackgroundTransparency = CFG.Colors.BackgroundTransparency,
		Position = UDim2.fromScale(0, 0),
	}):Play()
	TweenService:Create(stroke, info, { Transparency = 0.5 }):Play()
	TweenService:Create(labelText, info, { TextTransparency = 0.05 }):Play()
	TweenService:Create(xpText, info, { TextTransparency = 0 }):Play()

	return card
end

--------------------------------------------------------------------------------
-- Bombeamento da fila
--------------------------------------------------------------------------------

local function showNext()
	if #queue == 0 or #visible >= CFG.MaxVisible then
		return
	end

	-- Maior prioridade primeiro; empate resolve por ordem de chegada, pra a
	-- fila não embaralhar ações do mesmo peso.
	table.sort(queue, function(a, b)
		if a.Priority ~= b.Priority then
			return a.Priority > b.Priority
		end
		return a.QueuedAt < b.QueuedAt
	end)

	local entry = table.remove(queue, 1) :: Entry
	screen.Enabled = true
	local card = createCard(entry)
	table.insert(visible, card)
	maybePlaySound(entry.XP < 0)
end

--[[
	push(payload)
	Entrada única da fila. Faz, nesta ordem:
	  1. descarta payload repetido (mesmo Id);
	  2. tenta fundir num card VISÍVEL da mesma ação ainda dentro da janela;
	  3. tenta fundir numa entrada da FILA da mesma ação;
	  4. enfileira nova -- e, se a fila estourar, corta a de menor prioridade.
]]
local function push(payload: any)
	if type(payload) ~= "table" or type(payload.XP) ~= "number" or type(payload.Label) ~= "string" then
		return -- payload malformado: ignora em silêncio
	end

	local id = payload.Id
	if type(id) == "string" then
		if seenIds[id] then
			return -- (1) mesma notificação chegando duas vezes
		end
		seenIds[id] = true
		table.insert(seenOrder, id)
		-- Janela deslizante de ids: sem isso a tabela cresceria pela partida
		-- inteira só pra guardar ids que nunca mais voltam.
		if #seenOrder > 200 then
			local oldest = table.remove(seenOrder, 1) :: string
			seenIds[oldest] = nil
		end
	end

	local actionId = tostring(payload.ActionId)
	local priority = if type(payload.Priority) == "number" then payload.Priority else 1
	local now = os.clock()

	-- (2) Card visível da mesma ação, ainda jovem: soma nele.
	for _, card in visible do
		if not card.Closing and card.Entry.ActionId == actionId
			and now - card.ShownAt <= CFG.MergeWindow then
			card.Entry.Count += 1
			card.Entry.XP += payload.XP
			card.ShownAt = now -- renova o tempo de tela do card fundido
			refreshCard(card)
			return
		end
	end

	-- (3) Entrada da fila da mesma ação.
	for _, entry in queue do
		if entry.ActionId == actionId and now - entry.QueuedAt <= CFG.MergeWindow then
			entry.Count += 1
			entry.XP += payload.XP
			entry.Priority = math.max(entry.Priority, priority)
			return
		end
	end

	-- (4) Nova entrada.
	table.insert(queue, {
		ActionId = actionId,
		Label = payload.Label,
		XP = payload.XP,
		Priority = priority,
		Count = 1,
		QueuedAt = now,
	})

	if #queue > CFG.MaxQueue then
		-- Descarta a MENOS importante (e, entre iguais, a mais antiga): uma
		-- fila longa demais mostraria "escapou da ilha" trinta segundos depois
		-- de o jogador já ter escapado.
		local worstIndex, worst = 1, queue[1]
		for index, entry in queue do
			if entry.Priority < worst.Priority
				or (entry.Priority == worst.Priority and entry.QueuedAt < worst.QueuedAt) then
				worstIndex, worst = index, entry
			end
		end
		table.remove(queue, worstIndex)
	end

	showNext()
end

--------------------------------------------------------------------------------
-- Ciclo
--------------------------------------------------------------------------------

Remotes.MatchXPNotification.OnClientEvent:Connect(push)

-- Fecha o que passou do tempo e puxa o próximo. Um Heartbeat só, e ele sai na
-- primeira linha quando não há nada na tela nem na fila.
RunService.Heartbeat:Connect(function()
	if #visible == 0 and #queue == 0 then
		return
	end

	local now = os.clock()
	-- Percorre de trás pra frente: closeCard remove da lista durante o laço.
	for index = #visible, 1, -1 do
		local card = visible[index]
		if not card.Closing and now - card.ShownAt >= CFG.Duration then
			closeCard(card)
		end
	end

	showNext()
end)

-- Fim de partida: limpa fila e cards. Sem isso, uma notificação atrasada
-- apareceria por cima da tela de resultados.
Remotes.RoundEnded.OnClientEvent:Connect(function()
	table.clear(queue)
	for index = #visible, 1, -1 do
		closeCard(visible[index])
	end
	table.clear(seenIds)
	table.clear(seenOrder)
end)
