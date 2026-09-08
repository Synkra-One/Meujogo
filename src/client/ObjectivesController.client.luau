--!strict
--[[
	ObjectivesController
	Preenche e atualiza a ObjectivesHUD (StarterGui/ObjectivesHUD.model.json)
	a partir do RemoteEvent ObjectiveProgress (RadioObjective, RaftObjective).

	objectiveId recebidos hoje (ver ReplicatedStorage/Modules/Remotes.lua):
	  "RadioPecas"     -- current/max = peças coletadas / 3
	  "RadioCompleto"  -- torre sintonizada com sucesso
	  "JangadaProgresso" -- current/max = progresso % / 100
	  "FugaJangada"    -- current = quantos escaparam, players = lista

	Não forço a barra pra "cheia" nos eventos de conclusão (RadioCompleto,
	FugaJangada): pela ordem em que RadioObjective/RaftObjective disparam as
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

local raftFrame = SafeWait.Child(objectivesHUD, "RaftFrame")
local raftBarBackground = SafeWait.Child(raftFrame, "RaftBarBackground")
local raftBarFill = SafeWait.Child(raftBarBackground, "RaftBarFill") :: Frame
local raftBarText = SafeWait.Child(raftBarBackground, "RaftBarText") :: TextLabel

local notificationLabel = SafeWait.Child(objectivesHUD, "NotificationLabel") :: TextLabel

local NOTIFICATION_FADE_DURATION = 0.4
local NOTIFICATION_HOLD_DURATION = 3.5

-- A ScreenGui nasce com Enabled = false (ObjectivesHUD.model.json): objetivo
-- de partida não faz sentido no Lobby. Liga quando a partida começa
-- (RoundStateChanged) e desliga quando acaba (RoundEnded).
Remotes.RoundStateChanged.OnClientEvent:Connect(function()
	objectivesHUD.Enabled = true
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
	elseif objectiveId == "RadioSintonia" then
		radioTowerText.Text = string.format("Sintonia: %d%%", current)
	elseif objectiveId == "RadioCompleto" then
		radioTowerText.Text = "Torre: Ativada!"
		radioTowerText.TextColor3 = Color3.new(0.4, 1, 0.4)
		showNotification("Rádio sintonizado! Resgate a caminho!")
	elseif objectiveId == "JangadaProgresso" then
		setBarFill(raftBarFill, current, max)
		raftBarText.Text = string.format("Jangada: %d%%", math.floor(current))
	elseif objectiveId == "FugaJangada" then
		if current > 0 then
			local names = getPlayerNames(players)
			local who = (#names > 0) and table.concat(names, ", ") or "alguém"
			showNotification(string.format("Fuga na jangada! A bordo: %s", who))
		else
			showNotification("A jangada partiu... vazia.")
		end
	end
end)
