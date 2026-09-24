--!strict
--[[
	MatchResultsController
	Tela de fim de partida. Primeira versão FUNCIONAL, não o visual
	definitivo: estrutura, dados e comportamento certos, com o estilo escuro
	sóbrio do resto do jogo (SourceSans, fundo preto translúcido, detalhe em
	dourado) pra não destoar enquanto o design final não chega.

	TUDO QUE ELA MOSTRA VEM DO SERVIDOR
	  O payload de Remotes.MatchResults já chega pronto: XP por categoria,
	  ações agrupadas, estatísticas com rótulo e valor FORMATADOS, destaques.
	  Este arquivo não calcula XP, não soma estatística e não decide destaque
	  -- ele desenha. Isso é de propósito: um cliente adulterado consegue no
	  máximo mentir pro próprio dono.

	INDIVIDUAL POR NATUREZA
	  Cada jogador recebe o payload DELE. O detalhamento, o histórico e as
	  estatísticas na tela são sempre do jogador local. A única coisa
	  compartilhada são os destaques, que são o placar público da partida.

	LAYOUT: UMA COLUNA ROLÁVEL
	  Duas colunas ficariam ótimas no monitor e ilegíveis no celular. Uma
	  coluna só, em seções empilhadas dentro de um ScrollingFrame com
	  AutomaticCanvasSize, funciona igual nos dois -- e cresce sozinha quando
	  o jogador fez muita coisa, sem número de altura escrito no código.

	CONTROLES: a tela NUNCA os bloqueia. Não há Modal, não há captura de
	input, o fundo não intercepta clique. Dá pra fechar no botão e ela some
	sozinha quando a próxima partida começa -- o jogador nunca fica preso
	atrás dela.
]]

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Modules.MatchRewardsConfig)
local Remotes = require(ReplicatedStorage.Modules.Remotes)
local Types = require(ReplicatedStorage.Modules.MatchStatsTypes)

local CFG = Config.Results

local LocalPlayer = Players.LocalPlayer
local playerGui = LocalPlayer:WaitForChild("PlayerGui")

local GOLD = Color3.fromRGB(226, 190, 104)
local TEXT = Color3.fromRGB(226, 221, 212)
local DIM = Color3.fromRGB(150, 145, 138)
local POSITIVE = Color3.fromRGB(160, 234, 152)
local NEGATIVE = Color3.fromRGB(217, 107, 102)
local PANEL = Color3.fromRGB(12, 11, 13)

--------------------------------------------------------------------------------
-- Interface base
--------------------------------------------------------------------------------

local screen = Instance.new("ScreenGui")
screen.Name = "MatchResultsGui"
screen.ResetOnSpawn = false
screen.IgnoreGuiInset = false -- respeita a barra do topo / notch do celular
screen.DisplayOrder = CFG.DisplayOrder
screen.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
screen.Enabled = false
screen.Parent = playerGui

-- Escurece o fundo, mas NÃO captura input: Active = false deixa clique e
-- toque passarem direto pro jogo atrás dela.
local backdrop = Instance.new("Frame")
backdrop.Name = "Backdrop"
backdrop.Size = UDim2.fromScale(1, 1)
backdrop.BackgroundColor3 = Color3.new(0, 0, 0)
backdrop.BackgroundTransparency = 0.45
backdrop.BorderSizePixel = 0
backdrop.Active = false
backdrop.Parent = screen

local panel = Instance.new("Frame")
panel.Name = "Panel"
panel.AnchorPoint = Vector2.new(0.5, 0.5)
panel.Position = UDim2.fromScale(0.5, 0.5)
-- Scale nos dois eixos: acompanha a tela em vez de um tamanho fixo em pixels.
panel.Size = UDim2.fromScale(0.62, 0.8)
panel.BackgroundColor3 = PANEL
panel.BackgroundTransparency = 0.08
panel.BorderSizePixel = 0
panel.Parent = screen

-- Piso e teto em pixels: num celular o painel ocupa quase tudo, num monitor
-- ultrawide ele não vira uma faixa de ponta a ponta.
local panelSize = Instance.new("UISizeConstraint")
panelSize.MinSize = Vector2.new(280, 320)
panelSize.MaxSize = Vector2.new(760, 900)
panelSize.Parent = panel

local panelCorner = Instance.new("UICorner")
panelCorner.CornerRadius = UDim.new(0, 8)
panelCorner.Parent = panel

local panelStroke = Instance.new("UIStroke")
panelStroke.Color = Color3.fromRGB(58, 52, 44)
panelStroke.Thickness = 1
panelStroke.Parent = panel

local panelPadding = Instance.new("UIPadding")
panelPadding.PaddingLeft = UDim.new(0, 16)
panelPadding.PaddingRight = UDim.new(0, 16)
panelPadding.PaddingTop = UDim.new(0, 14)
panelPadding.PaddingBottom = UDim.new(0, 56) -- espaço do botão fixo no rodapé
panelPadding.Parent = panel

local content = Instance.new("ScrollingFrame")
content.Name = "Content"
content.Size = UDim2.fromScale(1, 1)
content.BackgroundTransparency = 1
content.BorderSizePixel = 0
content.ScrollBarThickness = 4
content.ScrollBarImageColor3 = GOLD
content.ScrollBarImageTransparency = 0.5
content.CanvasSize = UDim2.new()
content.AutomaticCanvasSize = Enum.AutomaticSize.Y -- cresce com o conteúdo
content.ScrollingDirection = Enum.ScrollingDirection.Y
content.ElasticBehavior = Enum.ElasticBehavior.WhenScrollable
content.Parent = panel

local contentLayout = Instance.new("UIListLayout")
contentLayout.FillDirection = Enum.FillDirection.Vertical
contentLayout.SortOrder = Enum.SortOrder.LayoutOrder
contentLayout.Padding = UDim.new(0, 6)
contentLayout.Parent = content

local closeButton = Instance.new("TextButton")
closeButton.Name = "Close"
closeButton.AnchorPoint = Vector2.new(0.5, 1)
closeButton.Position = UDim2.new(0.5, 0, 1, -14)
closeButton.Size = UDim2.new(0.5, 0, 0, 34)
closeButton.BackgroundColor3 = Color3.fromRGB(32, 28, 24)
closeButton.BorderSizePixel = 0
closeButton.Font = Enum.Font.SourceSansBold
closeButton.Text = "Continuar"
closeButton.TextColor3 = GOLD
closeButton.TextSize = 18
closeButton.AutoButtonColor = true
closeButton.Parent = panel

local closeSize = Instance.new("UISizeConstraint")
-- Alvo de toque confortável no celular, sem virar um botão gigante no monitor.
closeSize.MinSize = Vector2.new(150, 34)
closeSize.MaxSize = Vector2.new(320, 40)
closeSize.Parent = closeButton

local closeCorner = Instance.new("UICorner")
closeCorner.CornerRadius = UDim.new(0, 6)
closeCorner.Parent = closeButton

--------------------------------------------------------------------------------
-- Construtores de linha
--------------------------------------------------------------------------------

local order = 0

local function nextOrder(): number
	order += 1
	return order
end

local function makeLabel(text: string, size: number, textColor: Color3, font: Enum.Font, height: number): TextLabel
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.new(1, 0, 0, height)
	label.Font = font
	label.Text = text
	label.TextColor3 = textColor
	label.TextSize = size
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.TextTruncate = Enum.TextTruncate.AtEnd
	label.LayoutOrder = nextOrder()
	label.Parent = content
	return label
end

local function makeSectionTitle(text: string)
	local spacer = Instance.new("Frame")
	spacer.BackgroundTransparency = 1
	spacer.Size = UDim2.new(1, 0, 0, 8)
	spacer.LayoutOrder = nextOrder()
	spacer.Parent = content

	local title = makeLabel(string.upper(text), 14, GOLD, Enum.Font.SourceSansBold, 20)
	title.Name = "SectionTitle"
end

--[[
	makeRow(left, right, rightColor)
	Linha de duas colunas: descrição à esquerda, valor à direita. É o formato
	de tudo que é "rótulo -> número" (categoria, ação, estatística), então
	todas ficam alinhadas entre si sem nenhum cálculo de posição.
]]
local function makeRow(left: string, right: string, rightColor: Color3?): Frame
	local row = Instance.new("Frame")
	row.BackgroundTransparency = 1
	row.Size = UDim2.new(1, 0, 0, 20)
	row.LayoutOrder = nextOrder()
	row.Parent = content

	local leftLabel = Instance.new("TextLabel")
	leftLabel.BackgroundTransparency = 1
	-- 0.68 / 0.32: sobra espaço pro texto longo da ação sem apertar o valor.
	leftLabel.Size = UDim2.fromScale(0.68, 1)
	leftLabel.Font = Enum.Font.SourceSans
	leftLabel.Text = left
	leftLabel.TextColor3 = TEXT
	leftLabel.TextSize = 15
	leftLabel.TextXAlignment = Enum.TextXAlignment.Left
	leftLabel.TextTruncate = Enum.TextTruncate.AtEnd
	leftLabel.Parent = row

	local rightLabel = Instance.new("TextLabel")
	rightLabel.BackgroundTransparency = 1
	rightLabel.AnchorPoint = Vector2.new(1, 0)
	rightLabel.Position = UDim2.fromScale(1, 0)
	rightLabel.Size = UDim2.fromScale(0.32, 1)
	rightLabel.Font = Enum.Font.SourceSansBold
	rightLabel.Text = right
	rightLabel.TextColor3 = rightColor or TEXT
	rightLabel.TextSize = 15
	rightLabel.TextXAlignment = Enum.TextXAlignment.Right
	rightLabel.Parent = row

	return row
end

local function formatXP(xp: number): string
	return if xp >= 0 then string.format("+%d XP", xp) else string.format("\u{2212}%d XP", -xp)
end

local function xpColor(xp: number): Color3
	return if xp >= 0 then POSITIVE else NEGATIVE
end

--------------------------------------------------------------------------------
-- Montagem
--------------------------------------------------------------------------------

local function clearContent()
	order = 0
	for _, child in content:GetChildren() do
		if not child:IsA("UIListLayout") then
			child:Destroy()
		end
	end
end

local function build(payload: Types.ResultsPayload)
	clearContent()

	----------------------------------------------------------------------------
	-- Cabeçalho: resultado da partida e papel do jogador
	----------------------------------------------------------------------------
	makeLabel("FIM DE PARTIDA", 13, DIM, Enum.Font.SourceSansBold, 16)
	makeLabel(string.format("Vitória: %s", tostring(payload.Winner)), 24, GOLD, Enum.Font.SourceSansBold, 30)

	local reason = makeLabel(tostring(payload.Reason), 14, DIM, Enum.Font.SourceSans, 34)
	reason.TextWrapped = true
	reason.TextTruncate = Enum.TextTruncate.None

	makeRow("Seu papel", tostring(payload.Role), TEXT)
	if payload.Escaped then
		local method = if payload.EscapeMethod == "Helicoptero" then "helicóptero" else payload.EscapeMethod
		makeRow("Seu destino", if method then "Escapou de " .. method else "Escapou", POSITIVE)
	elseif payload.Eliminated then
		makeRow("Seu destino", "Eliminado", NEGATIVE)
	end

	if payload.IsMVP then
		local mvp = makeLabel("★  MELHOR DA PARTIDA", 18, GOLD, Enum.Font.SourceSansBold, 26)
		mvp.Name = "MVPBadge"
	end
	makeSectionTitle("Seus destaques")
	local hasMine = false
	for _, highlight in payload.Highlights do
		if highlight.UserId == LocalPlayer.UserId then
			hasMine = true
			local row = makeRow(highlight.Name, tostring(highlight.Value), GOLD)
			local name = row:FindFirstChildOfClass("TextLabel")
			if name then name.TextColor3 = GOLD end
		end
	end
	if not hasMine then
		makeRow("Nenhum destaque nesta partida", "", DIM)
	end

	----------------------------------------------------------------------------
	-- XP
	----------------------------------------------------------------------------
	makeSectionTitle("Experiência")
	makeRow("XP total da partida", formatXP(payload.MatchXP), xpColor(payload.MatchXP))
	makeRow("Pontuação de desempenho", tostring(payload.PerformanceScore), TEXT)

	----------------------------------------------------------------------------
	-- Progresso da conta (persistente entre partidas). Ausente quando a
	-- persistência está desligada ou o perfil não pôde ser gravado -- nesse
	-- caso a seção inteira some, em vez de mostrar um nível que pode não ter
	-- sido salvo de verdade.
	----------------------------------------------------------------------------
	local account = payload.Account
	if account then
		makeSectionTitle("Progresso da conta")
		if account.LeveledUp then
			local levelUp = makeLabel(
				string.format("▲  SUBIU PRO NÍVEL %d", account.Level),
				18,
				GOLD,
				Enum.Font.SourceSansBold,
				26
			)
			levelUp.Name = "LevelUpBadge"
		else
			makeRow("Nível da conta", string.format("Nível %d", account.Level), TEXT)
		end

		if account.AtMaxLevel then
			makeRow("Progresso", "Nível máximo", GOLD)
		else
			makeRow(
				"Progresso pro próximo nível",
				string.format("%d / %d XP", account.XPIntoLevel, account.XPForNextLevel),
				TEXT
			)
		end

		makeRow("XP total da conta", string.format("%d XP", account.TotalXP), DIM)
	end

	makeSectionTitle("XP por categoria")
	local anyCategory = false
	-- CategoryOrder, não pairs: a ordem das fatias tem que ser a mesma toda
	-- partida, senão a tela parece embaralhada entre uma e outra.
	for _, category in Types.CategoryOrder do
		local value = payload.XPBreakdown[category] or 0
		if value ~= 0 then
			anyCategory = true
			makeRow(Types.CategoryLabel[category] or category, formatXP(value), xpColor(value))
		end
	end
	if not anyCategory then
		makeRow("Nenhum XP registrado nesta partida", "", DIM)
	end

	----------------------------------------------------------------------------
	-- Ações (já agrupadas pelo servidor)
	----------------------------------------------------------------------------
	makeSectionTitle("O que rendeu XP")
	if #payload.Actions == 0 then
		makeRow("Nenhuma ação registrada", "", DIM)
	else
		for _, action in payload.Actions do
			-- O servidor já agrupou repetições; aqui só mostramos a contagem.
			local text = action.Label
			if action.Count > 1 then
				text = string.format("%s ×%d", action.Label, action.Count)
			elseif action.Detail then
				text = string.format("%s (%s)", action.Label, action.Detail)
			end
			makeRow(text, formatXP(action.XP), xpColor(action.XP))
		end
	end

	----------------------------------------------------------------------------
	-- Estatísticas pessoais (rótulo e valor já formatados pelo servidor)
	----------------------------------------------------------------------------
	makeSectionTitle("Suas estatísticas")
	for _, stat in payload.Stats do
		makeRow(stat.Label, stat.Value, TEXT)
	end

	----------------------------------------------------------------------------
	-- Destaques da partida (públicos)
	----------------------------------------------------------------------------
	local hasOthers = false
	for _, highlight in payload.Highlights do
		if highlight.UserId ~= LocalPlayer.UserId then
			if not hasOthers then
				makeSectionTitle("Outros destaques")
				hasOthers = true
			end
			makeRow(string.format("%s — %s", highlight.Name, highlight.PlayerName), tostring(highlight.Value), TEXT)
		end
	end
end

--------------------------------------------------------------------------------
-- Abrir / fechar
--------------------------------------------------------------------------------

local isOpen = false
local openToken = 0

local function open(payload: Types.ResultsPayload)
	-- Abertura duplicada é impossível: um segundo payload REDESENHA o painel
	-- que já está aberto em vez de empilhar outro por cima.
	build(payload)

	if isOpen then
		return
	end
	isOpen = true

	screen.Enabled = true
	backdrop.BackgroundTransparency = 1
	panel.BackgroundTransparency = 1
	panel.Size = UDim2.fromScale(0.58, 0.76)

	local info = TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	TweenService:Create(backdrop, info, { BackgroundTransparency = 0.45 }):Play()
	TweenService:Create(panel, info, {
		BackgroundTransparency = 0.08,
		Size = UDim2.fromScale(0.62, 0.8),
	}):Play()
end

local function close()
	if not isOpen then
		return
	end
	isOpen = false
	openToken += 1

	local info = TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
	TweenService:Create(backdrop, info, { BackgroundTransparency = 1 }):Play()
	TweenService:Create(panel, info, { BackgroundTransparency = 1 }):Play()

	local token = openToken
	task.delay(0.2, function()
		-- Se a tela reabriu nesse meio tempo (partida nova), não desliga.
		if token == openToken and not isOpen then
			screen.Enabled = false
			clearContent()
		end
	end)
end

closeButton.Activated:Connect(close)

Remotes.MatchResults.OnClientEvent:Connect(function(payload: any)
	if type(payload) ~= "table" or type(payload.Actions) ~= "table" or type(payload.Stats) ~= "table" then
		return -- payload malformado: não desenha nada em vez de quebrar a tela
	end

	openToken += 1
	local token = openToken
	-- Atraso curto pro jogador ver o desfecho antes de levar um painel na
	-- cara. Se algo cancelar (partida nova), o token muda e isto não abre.
	task.delay(CFG.OpenDelay, function()
		if token == openToken then
			open(payload)
		end
	end)
end)

-- Partida nova começou: fecha na hora. É o que garante que o relatório de uma
-- partida nunca fique na tela por cima da seguinte.
Remotes.RoundStateChanged.OnClientEvent:Connect(close)
