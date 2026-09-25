--!strict
--[[
	HUDController
	Preenche e atualiza a MainHUD (StarterGui/MainHUD.model.json) pro
	jogador local. Visual simples de propósito (cores/fontes padrão) --
	o polimento fica pra depois, isso aqui só liga os dados.

	(1) Liga/desliga a ScreenGui com RoundStateChanged/RoundEnded (a fase e o
	    tempo restante NÃO são mais exibidos).
	(2) RoleFrame.RoleText: Attribute "Role" do LocalPlayer.
	(3) SpyCooldownFrame: só visível quando Role == "Espiao". Mostra os
	    cooldowns de Sabotagem e Habilidade Letal, alimentados pelo novo
	    RemoteEvent CooldownUpdate (disparado por SabotageSystem.lua e
	    LethalAbility.lua quando o jogador usa a habilidade com sucesso).

	VISIBILIDADE: a ScreenGui nasce com Enabled = false (definido no próprio
	MainHUD.model.json, pra não piscar na tela antes deste script rodar).
	Liga no primeiro RoundStateChanged (partida começou) e desliga de novo
	no RoundEnded -- no Lobby não deve aparecer HUD de partida nenhuma.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage.Modules.GameConfig)
local Remotes = require(ReplicatedStorage.Modules.Remotes)
local SafeWait = require(ReplicatedStorage.Modules.SafeWait)

local LocalPlayer = Players.LocalPlayer
local playerGui = LocalPlayer:WaitForChild("PlayerGui") -- sempre existe, criado pelo engine
local mainHUD = SafeWait.Child(playerGui, "MainHUD") :: ScreenGui

local roleText = SafeWait.Child(SafeWait.Child(mainHUD, "RoleFrame"), "RoleText") :: TextLabel
local spyCooldownFrame = SafeWait.Child(mainHUD, "SpyCooldownFrame") :: Frame
local sabotageCooldownText = SafeWait.Child(spyCooldownFrame, "SabotageCooldownText") :: TextLabel
local lethalCooldownText = SafeWait.Child(spyCooldownFrame, "LethalCooldownText") :: TextLabel
local monsterCooldownFrame = SafeWait.Child(mainHUD, "MonsterCooldownFrame") :: Frame
local teleportCooldownText = SafeWait.Child(monsterCooldownFrame, "TeleportCooldownText") :: TextLabel

local function formatDuration(seconds: number): string
	seconds = math.max(0, math.ceil(seconds))
	return string.format("%02d:%02d", seconds // 60, seconds % 60)
end

--------------------------------------------------------------------------------
-- (1) Visibilidade da HUD
--------------------------------------------------------------------------------

Remotes.RoundStateChanged.OnClientEvent:Connect(function()
	mainHUD.Enabled = true
end)

Remotes.RoundEnded.OnClientEvent:Connect(function()
	mainHUD.Enabled = false
end)

--------------------------------------------------------------------------------
-- (2) Papel do jogador local
--------------------------------------------------------------------------------

local function refreshRoleText()
	local role = LocalPlayer:GetAttribute("Role")
	roleText.Text = "Papel: " .. ((type(role) == "string") and role or "--")
	spyCooldownFrame.Visible = role == GameConfig.Roles.Spy
	monsterCooldownFrame.Visible = role == GameConfig.Roles.Monster
end

LocalPlayer:GetAttributeChangedSignal("Role"):Connect(refreshRoleText)

--------------------------------------------------------------------------------
-- (3) Cooldowns do Espião
--------------------------------------------------------------------------------

local sabotageReadyAt = 0
local lethalReadyAt = 0
local teleportReadyAt = 0

local function refreshCooldownText(label: TextLabel, actionName: string, readyAt: number, readyWord: string?)
	local remaining = readyAt - os.time()
	if remaining <= 0 then
		label.Text = string.format("%s: %s", actionName, readyWord or "pronta")
	else
		label.Text = string.format("%s: %s", actionName, formatDuration(remaining))
	end
end

local function refreshCooldownTexts()
	refreshCooldownText(sabotageCooldownText, "Sabotagem", sabotageReadyAt)
	refreshCooldownText(lethalCooldownText, "Habilidade letal", lethalReadyAt)
	refreshCooldownText(teleportCooldownText, "Teleporte (Q)", teleportReadyAt, "pronto")
end

Remotes.CooldownUpdate.OnClientEvent:Connect(function(abilityName: string, readyAt: number)
	if abilityName == "Sabotagem" then
		sabotageReadyAt = readyAt
	elseif abilityName == "HabilidadeLetal" then
		lethalReadyAt = readyAt
	end
	refreshCooldownTexts()
end)

Remotes.MonsterTeleport.OnClientEvent:Connect(function(kind: string, value: any)
	if kind == "cooldown" then
		teleportReadyAt = tonumber(value) or 0
		refreshCooldownTexts()
	end
end)

--------------------------------------------------------------------------------
-- Loop de atualização (1x por segundo é suficiente pra um timer em texto)
--------------------------------------------------------------------------------

refreshRoleText()
refreshCooldownTexts()

task.spawn(function()
	while true do
		task.wait(1)
		refreshCooldownTexts()
	end
end)
