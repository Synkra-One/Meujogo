--!strict
-- Confirmacao visual de golpe corpo a corpo. Este script nunca decide acerto:
-- so reage ao WeaponImpact, emitido pelo servidor depois de DamageSystem.Apply.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Debris = game:GetService("Debris")
local Workspace = game:GetService("Workspace")

local Remotes = require(ReplicatedStorage.Modules.Remotes)
local CombatConfig = require(ReplicatedStorage.Modules.WeaponCombatConfig)
local player = Players.LocalPlayer

local function impactVisual(position: Vector3, color: Color3)
	local point = Instance.new("Part")
	point.Name = "WeaponImpactFX"
	point.Size = Vector3.new(0.16, 0.16, 0.16)
	point.Anchored, point.CanCollide, point.CanTouch, point.CanQuery = true, false, false, false
	point.Material, point.Color, point.Transparency = Enum.Material.Neon, color, 0.08
	point.Position = position
	point.Parent = Workspace

	local sparks = Instance.new("ParticleEmitter")
	sparks.Name = "ImpactSparks"
	sparks.Color = ColorSequence.new(color)
	sparks.LightEmission = 0.7
	sparks.Lifetime = NumberRange.new(0.12, 0.22)
	sparks.Speed = NumberRange.new(8, 14)
	sparks.SpreadAngle = Vector2.new(180, 180)
	sparks.Rate = 0
	sparks.Size = NumberSequence.new(0.11, 0)
	sparks.Parent = point
	sparks:Emit(10)
	Debris:AddItem(point, 0.3)
end

local function impactSound(position: Vector3, soundId: string)
	if soundId == "" then return end
	local anchor = Instance.new("Part")
	anchor.Name = "WeaponImpactAudio"
	anchor.Size = Vector3.new(0.1, 0.1, 0.1)
	anchor.Anchored, anchor.CanCollide, anchor.CanTouch, anchor.CanQuery = true, false, false, false
	anchor.Transparency, anchor.Position, anchor.Parent = 1, position, Workspace
	local sound = Instance.new("Sound")
	sound.SoundId, sound.Volume, sound.RollOffMaxDistance = soundId, 0.55, 55
	sound.Parent = anchor
	sound:Play()
	Debris:AddItem(anchor, 2)
end

local function shakeCamera(amount: number)
	local started = os.clock()
	RunService:BindToRenderStep("WeaponImpactShake", Enum.RenderPriority.Camera.Value + 1, function()
		local elapsed = os.clock() - started
		if elapsed >= 0.11 then
			RunService:UnbindFromRenderStep("WeaponImpactShake")
			return
		end
		local camera = Workspace.CurrentCamera
		if camera then
			local fade = 1 - elapsed / 0.11
			camera.CFrame *= CFrame.new(
				(math.random() - 0.5) * amount * fade,
				(math.random() - 0.5) * amount * fade,
				0
			)
		end
	end)
end

Remotes.WeaponImpact.OnClientEvent:Connect(function(attacker: Player, weaponId: string, position: Vector3, stunned: boolean?)
	if typeof(position) ~= "Vector3" then return end
	local profile = (CombatConfig :: any)[weaponId]
	if type(profile) ~= "table" then return end
	local color = if stunned then Color3.fromRGB(255, 216, 78) else profile.ImpactColor
	impactVisual(position, color)
	impactSound(position, profile.ImpactSound)
	if attacker == player then
		shakeCamera(profile.ImpactShake)
	end
end)
