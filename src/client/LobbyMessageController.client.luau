--!strict
--[[
	LobbyMessageController
	Toast simples pra LobbyMessage (LobbyManager.lua) -- sem isso a
	mensagem seria disparada e ninguém veria. É deliberadamente pequeno e
	construído em código (sem StarterGui/*.model.json próprio): é um aviso
	pontual de lobby, não uma HUD persistente como MainHUD/ObjectivesHUD.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Remotes = require(ReplicatedStorage.Modules.Remotes)

local LocalPlayer = Players.LocalPlayer
local playerGui = LocalPlayer:WaitForChild("PlayerGui")

local DISPLAY_DURATION = 3
local FADE_DURATION = 0.3

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "LobbyMessageToast"
screenGui.ResetOnSpawn = false
screenGui.Parent = playerGui

local label = Instance.new("TextLabel")
label.Size = UDim2.new(0, 420, 0, 44)
label.Position = UDim2.new(0.5, 0, 0, 70)
label.AnchorPoint = Vector2.new(0.5, 0)
label.BackgroundColor3 = Color3.new(0, 0, 0)
label.BackgroundTransparency = 1
label.TextTransparency = 1
label.TextColor3 = Color3.new(1, 1, 1)
label.TextSize = 18
label.Font = Enum.Font.SourceSansBold
label.Text = ""
label.Parent = screenGui

local token = 0

local function showMessage(message: string)
	token += 1
	local myToken = token

	label.Text = message
	label.BackgroundTransparency = 1
	label.TextTransparency = 1

	TweenService:Create(label, TweenInfo.new(FADE_DURATION), {
		BackgroundTransparency = 0.3,
		TextTransparency = 0,
	}):Play()

	task.delay(FADE_DURATION + DISPLAY_DURATION, function()
		if token ~= myToken then
			return
		end

		TweenService:Create(label, TweenInfo.new(FADE_DURATION), {
			BackgroundTransparency = 1,
			TextTransparency = 1,
		}):Play()
	end)
end

Remotes.LobbyMessage.OnClientEvent:Connect(showMessage)
