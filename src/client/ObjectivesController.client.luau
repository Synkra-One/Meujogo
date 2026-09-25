--!strict
--[[
	ObjectivesController
	Preenche e atualiza a ObjectivesHUD (StarterGui/ObjectivesHUD.model.json)
	a partir do RemoteEvent ObjectiveProgress (RadioObjective e ExtractionSystem).

	objectiveId recebidos hoje (ver ReplicatedStorage/Modules/Remotes.lua):
	  "RadioPecas"     -- current/max = peças coletadas / 3
	  "TodasPecasInstaladas" -- as 3 peças foram instaladas no rack (RadioInstallSystem)
	  "RadioSocorro"   -- current/max = % do chamado de socorro sendo transmitido (RadioSiteSystem)
	  "RadioSintonia"  -- legado (sintonia antiga); RadioSiteSystem dispara isto
	                       em 100 junto de "RadioCompleto" ao concluir o socorro
	  "RadioCompleto"  -- rádio concluído (chamado de socorro enviado)
	  "ExtracaoChamada"  -- current = SEGUNDOS até o helicóptero pousar (1x/s)
	  "ExtracaoPousou"   -- helicóptero no chão, embarque liberado
	  "ExtracaoEmbarque" -- current = SEGUNDOS até decolar (1x/s)
	  "ExtracaoConcluida" -- current = quantos foram resgatados, players = lista

	ATENÇÃO: nos quatro "Extracao*", `current` vem em SEGUNDOS, não em
	porcentagem -- eles alimentam um relógio (formatClock), não uma barra.

	Não forço a barra pra "cheia" nos eventos de conclusão (RadioCompleto,
	RadioCompleto): pela ordem em que RadioObjective/ExtractionSystem disparam as
	coisas, o progresso já chega em 100% pelo evento anterior antes da
	conclusão ser possível. Assim não preciso hardcodar "3" ou "100" aqui.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Remotes = require(ReplicatedStorage.Modules.Remotes)
local SafeWait = require(ReplicatedStorage.Modules.SafeWait)

local LocalPlayer = Players.LocalPlayer
local playerGui = LocalPlayer:WaitForChild("PlayerGui") -- sempre existe, criado pelo engine
local objectivesHUD = SafeWait.Child(playerGui, "ObjectivesHUD") :: ScreenGui

local radioFrame = SafeWait.Child(objectivesHUD, "RadioFrame")
local radioBarBackground = SafeWait.Child(radioFrame, "RadioBarBackground")
local radioBarFill = SafeWait.Child(radioBarBackground, "RadioBarFill") :: Frame
local radioBarText = SafeWait.Child(radioBarBackground, "RadioBarText") :: TextLabel
local radioTowerText = SafeWait.Child(radioFrame, "RadioTowerText") :: TextLabel

local notificationLabel = SafeWait.Child(objectivesHUD, "NotificationLabel") :: TextLabel

local NOTIFICATION_FADE_DURATION = 0.4
local NOTIFICATION_HOLD_DURATION = 3.5

-- Segundos -> "1:23", pras contagens da extração.
local function formatClock(seconds: number): string
	local s = math.max(0, math.floor(seconds))
	return string.format("%d:%02d", s // 60, s % 60)
end

-- O aviso grande de "corre pra praia" só aparece uma vez por rodada, no
-- primeiro tique da contagem (que chega uma vez por segundo).
local extractionWarned = false

-- A ScreenGui nasce com Enabled = false (ObjectivesHUD.model.json): objetivo
-- de partida não faz sentido no Lobby. Liga quando a partida começa
-- (RoundStateChanged) e desliga quando acaba (RoundEnded).
--
-- RoundStateChanged dispara em TODA troca de fase (Queda/Exploracao/Corrida/
-- Desfecho), não só no início -- por isso o reset do texto/cor do rádio (que
-- fica "grudado" de uma rodada pra outra, já que nada mais reescreve
-- radioTowerText em 0%) só acontece na fase "Queda", a primeira.
Remotes.RoundStateChanged.OnClientEvent:Connect(function(phase: string)
	objectivesHUD.Enabled = true
	if phase == "Queda" then
		radioTowerText.Text = "Torre: Inativa" -- default de ObjectivesHUD.model.json
		radioTowerText.TextColor3 = Color3.new(1, 1, 1)
		radioBarFill.Size = UDim2.new(0, 0, 1, 0)
		radioBarText.Text = "Peças: 0/3"
		extractionWarned = false
	end
end)

Remotes.RoundEnded.OnClientEvent:Connect(function()
	objectivesHUD.Enabled = false
end)

--------------------------------------------------------------------------------
-- Barras de progresso
--------------------------------------------------------------------------------

local function setBarFill(fill: Frame, current: number, max: number)
	local ratio = (max > 0) and math.clamp(current / max, 0, 1) or 0
	fill.Size = UDim2.new(ratio, 0, 1, 0)
end

--------------------------------------------------------------------------------
-- Notificação grande e temporária
--------------------------------------------------------------------------------

-- Token evita que uma notificação antiga "esconda" uma nova disparada
-- enquanto a primeira ainda estava com o fade de saída agendado.
local notificationToken = 0

local function showNotification(text: string)
	notificationToken += 1
	local myToken = notificationToken

	notificationLabel.Text = text
	notificationLabel.Visible = true
	notificationLabel.BackgroundTransparency = 1
	notificationLabel.TextTransparency = 1

	TweenService:Create(notificationLabel, TweenInfo.new(NOTIFICATION_FADE_DURATION), {
		BackgroundTransparency = 0.3,
		TextTransparency = 0,
	}):Play()

	task.delay(NOTIFICATION_FADE_DURATION + NOTIFICATION_HOLD_DURATION, function()
		if notificationToken ~= myToken then
			return -- outra notificação assumiu o label nesse meio tempo
		end

		local fadeOut = TweenService:Create(notificationLabel, TweenInfo.new(NOTIFICATION_FADE_DURATION), {
			BackgroundTransparency = 1,
			TextTransparency = 1,
		})
		fadeOut:Play()
		fadeOut.Completed:Wait()

		if notificationToken == myToken then
			notificationLabel.Visible = false
		end
	end)
end

--------------------------------------------------------------------------------
-- Dispatch do ObjectiveProgress
--------------------------------------------------------------------------------

local function getPlayerNames(players: unknown): { string }
	local names = {}
	if typeof(players) ~= "table" then
		return names
	end

	for _, entry in players :: { unknown } do
		if typeof(entry) == "Instance" and entry:IsA("Player") then
			table.insert(names, entry.Name)
		end
	end

	return names
end

Remotes.ObjectiveProgress.OnClientEvent:Connect(function(objectiveId: string, current: number, max: number, players: unknown)
	if objectiveId == "RadioPecas" then
		setBarFill(radioBarFill, current, max)
		radioBarText.Text = string.format("Peças: %d/%d", current, max)
	elseif objectiveId == "TodasPecasInstaladas" then
		showNotification("Peças instaladas! Vá até a Estação de Rádio.")
	elseif objectiveId == "RadioSocorro" then
		-- Progresso do chamado de socorro (RadioSiteSystem), enquanto
		-- alguém segura o console transmitindo. Some sozinho quando
		-- "RadioCompleto" sobrescreve o texto abaixo.
		if current < 100 then
			radioTowerText.Text = string.format("Transmitindo socorro: %d%%", current)
			radioTowerText.TextColor3 = Color3.new(1, 1, 1)
		end
	elseif objectiveId == "RadioSintonia" then
		radioTowerText.Text = string.format("Sintonia: %d%%", current)
	elseif objectiveId == "RadioCompleto" then
		radioTowerText.Text = "Socorro enviado!"
		radioTowerText.TextColor3 = Color3.new(0.4, 1, 0.4)
		showNotification("Pedido de socorro enviado! Resgate a caminho!")
	elseif objectiveId == "ExtracaoChamada" then
		-- Contagem até o helicóptero pousar. `current` chega em SEGUNDOS
		-- restantes (não em %), um evento por segundo, vindo do
		-- ExtractionSystem. A primeira mensagem é o aviso grande de "corre".
		if not extractionWarned then
			extractionWarned = true
			showNotification("RESGATE A CAMINHO — corra até a fumaça vermelha na praia!")
		end
		radioTowerText.Text = string.format("Helicóptero em %s", formatClock(current))
		radioTowerText.TextColor3 = Color3.fromRGB(255, 150, 120)
	elseif objectiveId == "ExtracaoPousou" then
		radioTowerText.Text = "Helicóptero POUSOU"
		radioTowerText.TextColor3 = Color3.new(0.4, 1, 0.4)
		showNotification("O helicóptero pousou! Entre na zona para embarcar.")
	elseif objectiveId == "ExtracaoEmbarque" then
		radioTowerText.Text = string.format("Decola em %s", formatClock(current))
		radioTowerText.TextColor3 = Color3.fromRGB(255, 220, 120)
	elseif objectiveId == "ExtracaoConcluida" then
		radioTowerText.Text = "Resgatados!"
		radioTowerText.TextColor3 = Color3.new(0.4, 1, 0.4)
		local names = getPlayerNames(players)
		local who = (#names > 0) and table.concat(names, ", ") or "alguém"
		showNotification(string.format("Helicóptero decolou! Resgatados: %s", who))
	-- Barco de fuga (server/BoatSystem.lua). O checklist do barco fica na
	-- BarcoHUD (client/BoatHUD.lua); aqui só os avisos grandes.
	elseif objectiveId == "BarcoPronto" then
		showNotification("O barco está pronto! Sente no timão e dê a partida.")
	elseif objectiveId == "BarcoLigado" then
		showNotification("O motor do barco pegou! Pro mar aberto, até as boias do limite!")
	elseif objectiveId == "BarcoFugiu" then
		local names = getPlayerNames(players)
		local who = (#names > 0) and table.concat(names, ", ") or "alguém"
		showNotification(string.format("O barco escapou da ilha! A bordo: %s", who))
	end
end)
