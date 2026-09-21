--!strict
--[[
	DayNightCycle

	Cada rodada começa aplicando o preset Night. O servidor interpola a
	iluminação global ao longo do relógio da partida e chega ao preset de dia
	quando 19:30 já tiverem passado dos 20 minutos totais.

	Lighting replica automaticamente para todos os clientes, então não existe
	um relógio separado por jogador nem uma decisão visual local divergente.
]]

local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local GameConfig = require(ReplicatedStorage.Modules.GameConfig)
local LightingPresets = require(ReplicatedStorage.Modules.LightingPresets)
local RoundManager = require(script.Parent.RoundManager)

local CFG = GameConfig.DayNight
local NIGHT = LightingPresets.Presets.Night
local DAY = LightingPresets.Presets.CloudyMorning

local DayNightCycle = {}
local initialized = false
local roundStartedAt: number? = nil
local elapsedSinceUpdate = CFG.UpdateInterval

local function numberLerp(a: number, b: number, t: number): number
	return a + (b - a) * t
end

local function colorLerp(a: Color3, b: Color3, t: number): Color3
	return a:Lerp(b, t)
end

local function applyBlend(progress: number)
	local night = NIGHT.Properties
	local day = DAY.Properties
	local atmosphere = Lighting:FindFirstChild("Atmosphere")
	local colorCorrection = Lighting:FindFirstChild("SomberColor")
	local bloom = Lighting:FindFirstChild("LowLightBloom")
	local sunRays = Lighting:FindFirstChild("WeakDuskRays")

	Lighting.Ambient = colorLerp(night.Ambient, day.Ambient, progress)
	Lighting.OutdoorAmbient = colorLerp(night.OutdoorAmbient, day.OutdoorAmbient, progress)
	Lighting.Brightness = numberLerp(night.Brightness, day.Brightness, progress)
	Lighting.ClockTime = numberLerp(CFG.StartClockTime, CFG.FullDayClockTime, progress)
	Lighting.ExposureCompensation = numberLerp(night.ExposureCompensation, day.ExposureCompensation, progress)
	Lighting.FogColor = colorLerp(night.FogColor, day.FogColor, progress)
	Lighting.FogStart = numberLerp(night.FogStart, day.FogStart, progress)
	Lighting.FogEnd = numberLerp(night.FogEnd, day.FogEnd, progress)

	if atmosphere and atmosphere:IsA("Atmosphere") then
		atmosphere.Density = numberLerp(NIGHT.Atmosphere.Density, DAY.Atmosphere.Density, progress)
		atmosphere.Offset = numberLerp(NIGHT.Atmosphere.Offset, DAY.Atmosphere.Offset, progress)
		atmosphere.Color = colorLerp(NIGHT.Atmosphere.Color, DAY.Atmosphere.Color, progress)
		atmosphere.Decay = colorLerp(NIGHT.Atmosphere.Decay, DAY.Atmosphere.Decay, progress)
		atmosphere.Glare = numberLerp(NIGHT.Atmosphere.Glare, DAY.Atmosphere.Glare, progress)
		atmosphere.Haze = numberLerp(NIGHT.Atmosphere.Haze, DAY.Atmosphere.Haze, progress)
	end
	if colorCorrection and colorCorrection:IsA("ColorCorrectionEffect") then
		colorCorrection.Brightness = numberLerp(NIGHT.SomberColor.Brightness, DAY.SomberColor.Brightness, progress)
		colorCorrection.Contrast = numberLerp(NIGHT.SomberColor.Contrast, DAY.SomberColor.Contrast, progress)
		colorCorrection.Saturation = numberLerp(NIGHT.SomberColor.Saturation, DAY.SomberColor.Saturation, progress)
		colorCorrection.TintColor = colorLerp(NIGHT.SomberColor.TintColor, DAY.SomberColor.TintColor, progress)
	end
	if bloom and bloom:IsA("BloomEffect") then
		bloom.Intensity = numberLerp(NIGHT.LowLightBloom.Intensity, DAY.LowLightBloom.Intensity, progress)
		bloom.Size = numberLerp(NIGHT.LowLightBloom.Size, DAY.LowLightBloom.Size, progress)
		bloom.Threshold = numberLerp(NIGHT.LowLightBloom.Threshold, DAY.LowLightBloom.Threshold, progress)
	end
	if sunRays and sunRays:IsA("SunRaysEffect") then
		sunRays.Intensity = numberLerp(NIGHT.WeakDuskRays.Intensity, DAY.WeakDuskRays.Intensity, progress)
		sunRays.Spread = numberLerp(NIGHT.WeakDuskRays.Spread, DAY.WeakDuskRays.Spread, progress)
	end
	Lighting:SetAttribute("DayNightProgress", progress)
	Lighting:SetAttribute("DayNightElapsed", if roundStartedAt then Workspace:GetServerTimeNow() - roundStartedAt else 0)
end

local function startRound()
	LightingPresets.Apply("Night")
	roundStartedAt = Workspace:GetServerTimeNow()
	elapsedSinceUpdate = CFG.UpdateInterval
	applyBlend(0)
end

local function endRound()
	roundStartedAt = nil
	Lighting:SetAttribute("DayNightProgress", nil)
	Lighting:SetAttribute("DayNightElapsed", nil)
	LightingPresets.Apply(GameConfig.Environment.LightingPreset)
end

function DayNightCycle.Init()
	if initialized then return end
	initialized = true
	assert(CFG.DawnStartsAt >= 0 and CFG.FullDayAt > CFG.DawnStartsAt,
		"DayNight: janela do amanhecer inválida")
	assert(CFG.FullDayAt <= GameConfig.Match.DurationDefault,
		"DayNight: o dia completo não pode passar do fim da partida")
	RoundManager.RoundPrepared.Event:Connect(startRound)
	RoundManager.RoundEnded.Event:Connect(endRound)
	RunService.Heartbeat:Connect(function(dt)
		if not roundStartedAt then return end
		elapsedSinceUpdate += dt
		if elapsedSinceUpdate < CFG.UpdateInterval then return end
		elapsedSinceUpdate = 0
		local elapsed = Workspace:GetServerTimeNow() - roundStartedAt
		local progress = math.clamp(
			(elapsed - CFG.DawnStartsAt) / (CFG.FullDayAt - CFG.DawnStartsAt),
			0,
			1
		)
		applyBlend(progress)
	end)
end

return DayNightCycle
