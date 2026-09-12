--!strict
local Lighting = game:GetService("Lighting")
local SoundService = game:GetService("SoundService")
local Modules = game:GetService("ReplicatedStorage").Modules
local Config = require(Modules.FlashlightConfig)
local GameConfig = require(Modules.GameConfig)
local FX = {}
FX.__index = FX

function FX.new(player: Player)
	local blur = Instance.new("BlurEffect")
	blur.Name, blur.Size, blur.Enabled, blur.Parent = "FlashlightExposureBlur", 0, false, Lighting
	local color = Instance.new("ColorCorrectionEffect")
	color.Name, color.Enabled, color.Parent = "FlashlightExposureColor", false, Lighting
	local sound = Instance.new("Sound")
	sound.Name, sound.SoundId = "FlashlightExposureAudio", Config.ExposureSound
	sound.Looped, sound.Volume, sound.PlaybackSpeed, sound.Parent = true, 0, 0.45, SoundService
	return setmetatable({ player = player, blur = blur, color = color, sound = sound, intensity = 0 }, FX)
end

function FX:Update(dt: number)
	local character = self.player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local active = self.player:GetAttribute("Role") == GameConfig.Roles.Monster
		and self.player:GetAttribute("InRound") == true and self.player:GetAttribute("Eliminado") ~= true
		and humanoid ~= nil and humanoid.Health > 0
	local target = if active and character then character:GetAttribute("FlashlightIntensity") or 0 else 0
	self.intensity = if active then self.intensity + (target - self.intensity) * (1 - math.exp(-8 * dt)) else 0
	local amount = self.intensity
	local untilTime = if active and character then character:GetAttribute("FlashlightDisorientedUntil") or 0 else 0
	local remaining = math.clamp(untilTime - workspace:GetServerTimeNow(), 0, Config.MaxExposureDisorientation)
	local pulse = math.sin(remaining / Config.MaxExposureDisorientation * math.pi)
	self.blur.Enabled, self.color.Enabled = amount > 0.005, amount > 0.005
	self.blur.Size = amount * Config.MaxBlur + pulse * Config.DisorientationBlur
	self.color.Brightness = amount * 0.025 + pulse * 0.015
	self.color.Contrast, self.color.Saturation = -amount * 0.035, -amount * 0.12
	self.color.TintColor = Color3.new(1, 1 - amount * 0.015, 1 - amount * 0.04)
	self.sound.Volume = amount * Config.MaxAudioVolume
	if amount > 0.03 then
		if not self.sound.IsPlaying then self.sound:Play() end
	elseif self.sound.IsPlaying then self.sound:Stop() end
end

function FX:Destroy()
	self.blur:Destroy()
	self.color:Destroy()
	self.sound:Destroy()
end

return FX
