--!strict
local Lighting = game:GetService("Lighting")
local SoundService = game:GetService("SoundService")
local Modules = game:GetService("ReplicatedStorage").Modules
local Config = require(Modules.FlashlightConfig)
local GameConfig = require(Modules.GameConfig)
local Rules = require(Modules.FlashlightRules)
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
	local gui = Instance.new("ScreenGui")
	gui.Name, gui.IgnoreGuiInset, gui.ResetOnSpawn, gui.DisplayOrder = "FlashBurstBlind", true, false, 35
	gui.Enabled, gui.Parent = false, player:WaitForChild("PlayerGui")
	local white = Instance.new("Frame")
	white.Size, white.BorderSizePixel, white.BackgroundColor3 = UDim2.fromScale(1, 1), 0, Color3.new(1, 1, 1)
	white.BackgroundTransparency, white.Parent = 1, gui
	local bloom = Instance.new("BloomEffect")
	bloom.Name, bloom.Enabled, bloom.Size, bloom.Threshold, bloom.Parent = "FlashBurstBloom", false, 32, 0.7, Lighting
	local ring = Instance.new("Sound")
	ring.Name, ring.SoundId, ring.Looped = "FlashBurstTinnitus", Config.FlashBurstRingSound, true
	ring.Volume, ring.PlaybackSpeed, ring.Parent = 0, Config.FlashBurstRingPitch, SoundService
	-- Loop the sustained portion of the bundled tone. A published ringing
	-- asset can replace it centrally without changing any networking.
	if string.sub(Config.FlashBurstRingSound, 1, 11) == "rbxasset://" then
		ring.PlaybackRegionsEnabled = true
		ring.LoopRegion = NumberRange.new(0.04, 0.16)
	end
	return setmetatable({ player = player, blur = blur, color = color, sound = sound, intensity = 0,
		gui = gui, white = white, bloom = bloom, ring = ring }, FX)
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
	-- Read ONLY the local player's character. World impact effects never
	-- call this path, so spectators/survivors cannot receive the whiteout/audio.
	local burstAt = if active and character then character:GetAttribute("FlashBurstAt") or 0 else 0
	local blindUntil = if active and character then character:GetAttribute("FlashBurstBlindUntil") or 0 else 0
	local blind = Rules.BurstEnvelope(workspace:GetServerTimeNow(), burstAt, blindUntil)
	self.gui.Enabled, self.bloom.Enabled = blind > 0, blind > 0
	self.white.BackgroundTransparency = 1 - blind * Config.FlashBurstBlindOpacity
	self.bloom.Intensity = blind * 1.2
	self.blur.Size += blind * 5
	self.blur.Enabled = self.blur.Enabled or blind > 0
	self.ring.Volume = Config.FlashBurstRingVolume * blind
	if blind > 0 then
		if not self.ring.IsPlaying then self.ring:Play() end
	elseif self.ring.IsPlaying then self.ring:Stop() end
end

function FX:Destroy()
	self.blur:Destroy()
	self.color:Destroy()
	self.sound:Destroy()
	self.ring:Destroy()
	self.bloom:Destroy()
	self.gui:Destroy()
end

return FX
