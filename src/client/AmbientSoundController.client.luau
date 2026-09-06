--!strict
--[[
	AmbientSoundController
	Tensão ambiente (batimento/dissonância) pro Sobrevivente que fica fora
	de qualquer Part "ZonaSegura" por muito tempo -- as mesmas Parts que
	MonsterLightWeakness.lua usa pra enfraquecer o Monstro.

	Um único Sound em loop toca o tempo todo (evita reiniciar o loop a cada
	checagem); só o VOLUME sobe/desce conforme GameConfig.Tension:
	  - fora de zona segura por mais que TimeOutsideSafeZoneThreshold: o
	    volume sobe linearmente até MaxVolume ao longo de RampUpDuration.
	  - voltar pra dentro de uma zona segura zera o acumulador na hora.

	Só se aplica a Role == "Sobrevivente" (Monstro/Espião não têm esse cue).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")

local GameConfig = require(ReplicatedStorage.Modules.GameConfig)
local AssetRegistry = require(ReplicatedStorage.Modules.AssetRegistry)
local StatScaling = require(ReplicatedStorage.Modules.StatScaling)

local LocalPlayer = Players.LocalPlayer

local tensionSound = Instance.new("Sound")
tensionSound.Name = "TensionHeartbeat"
tensionSound.SoundId = AssetRegistry.Sounds.HeartbeatTension
tensionSound.Looped = true
tensionSound.Volume = 0
tensionSound.Parent = SoundService
tensionSound:Play()

local timeOutsideSafeZone = 0

local function isSurvivor(): boolean
	return LocalPlayer:GetAttribute("Role") == GameConfig.Roles.Survivor
end

local function isInSafeZone(rootPart: BasePart): boolean
	for _, touching in rootPart:GetTouchingParts() do
		if touching:GetAttribute("ZonaSegura") == true then
			return true
		end
	end
	return false
end

task.spawn(function()
	while true do
		task.wait(GameConfig.Tension.CheckInterval)

		local character = LocalPlayer.Character
		local rootPart = character and character:FindFirstChild("HumanoidRootPart")

		if not (isSurvivor() and rootPart and rootPart:IsA("BasePart")) then
			timeOutsideSafeZone = 0
			tensionSound.Volume = 0
			continue
		end

		if isInSafeZone(rootPart) then
			timeOutsideSafeZone = 0
		else
			timeOutsideSafeZone += GameConfig.Tension.CheckInterval
		end

		-- FURTIVIDADE -> estica o tempo que dá pra ficar fora de Zona Segura
		-- antes da tensão começar a subir. Marina/Kevin (Furtividade 95)
		-- aguentam ~2.2x mais que Rafael (Furtividade 10).
		local threshold = GameConfig.Tension.TimeOutsideSafeZoneThreshold
			* StatScaling.StealthThresholdMultiplier(LocalPlayer)
		local overThreshold = timeOutsideSafeZone - threshold
		local ratio = math.clamp(overThreshold / GameConfig.Tension.RampUpDuration, 0, 1)
		tensionSound.Volume = ratio * GameConfig.Tension.MaxVolume
	end
end)
