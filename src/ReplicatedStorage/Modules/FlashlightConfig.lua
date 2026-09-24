--!strict
-- Battery uses percentage points; exposure uses seconds of continuous light.
return table.freeze({
	-- Attributes que DESLIGAM e travam a lanterna enquanto estiverem true no
	-- character OU no Player. Fonte única: FlashlightSystem (servidor) e
	-- FlashlightController (cliente) leem esta mesma lista, então um poder
	-- novo só precisa ligar o Attribute -- sem segunda lanterna, sem mexer no
	-- inventário. "AbyssBlackout" é o Apagão do Abismo (server/AbyssBlackout).
	BlockingFlags = table.freeze({
		"GrabLocked", "ShadowRushBusy", "TeleportBusy", "PowerStunned", "AbyssBlackout",
	}),
	BatteryMax = 100,
	BatteryDrainRate = 100 / 60,
	FlashBurstCost = 25,
	FlashBurstKey = "V",
	FlashBurstGamepadKey = "ButtonL2",
	FlashBurstCooldown = 8,
	FlashBurstRange = 32,
	FlashBurstAngle = 24,
	FlashBurstStunDuration = 2,
	FlashBurstPowerBlockDuration = 2.5,
	FlashBurstBlindDuration = 4,
	FlashBurstInputInterval = 0.15,
	FlashBurstMaxAimYaw = 100, -- shoulder aim + replication/parallax tolerance
	FlashBurstMaxAimPitch = 88,
	FlashBurstVisualDuration = 0.32,
	FlashBurstBrightness = 16,
	FlashBurstBlindOpacity = 0.82,
	FlashBurstSound = "rbxasset://sounds/impact_explosion_03.mp3",
	FlashBurstSoundVolume = 0.35,
	FlashBurstRingSound = "rbxasset://sounds/volume_slider.ogg",
	FlashBurstRingVolume = 0.12,
	FlashBurstRingPitch = 3,
	ModelLength = 1.8,
	-- Gameplay cone for monster exposure; visual lighting is tuned separately.
	FlashlightRange = 48,
	BeamAngle = 38,
	LightRange = 58,
	LightAngle = 48,
	Brightness = 4.6,
	-- Visual layer: a tight hotspot, broad spill and a small local fill light.
	-- These values do not change the server-side targeting cone.
	SpillAngle = 76,
	SpillBrightness = 1.0,
	FillRange = 9,
	FillBrightness = 0.25,
	LightColor = table.freeze({ 240, 247, 226 }),
	-- Flashlight animation layer. These R6 clips are published by the game
	-- owner/group and should key only the upper body/held flashlight joints.
	-- Locomotion remains owned by Animate + the movement pack.
	AnimationFadeTime = 0.16,
	AnimationLoadWarningDelay = 2,
	AnimationStateDebounce = 0.09,
	AnimationAirDebounce = 0.06,
	-- The right shoulder aligns the actual lens; the other joints add a
	-- smaller torso-space aim offset over the authored holding animation.
	PoseAimResponsiveness = 10.5,
	PoseBlendResponsiveness = 18,
	-- Degrees relative to the character; the shoulder camera turns the body
	-- beyond the lateral limit. Left/head values below are aim multipliers.
	AimPitchLimit = 80,
	AimYawLimit = 80,
	LeftAimPitch = 0.52,
	LeftAimYaw = 0.32,
	-- Keep this deliberately subtle: it sells the pose without replacing the
	-- normal Animate head/neck behaviour.
	NeckAimPitch = 0.42,
	NeckAimYaw = 0.45,
	Animations = table.freeze({
		Equip = "rbxassetid://82905353934076",
		Idle = "rbxassetid://103502806390125",
		Click = "rbxassetid://92755233522139",
		Burst = "", -- optional published R6 clip; procedural recoil works without it
	}),
	LowBatteryThreshold = 18,
	LowBatteryFlicker = 0.28,
	ExposureRate = 1,
	ExposureDecayRate = 1.5,
	EffectStartExposure = 1,
	MaxExposure = 6,
	MonsterSlow = 0.08,
	Damage = 4,
	DamageExposure = 2.5,
	DamageCooldown = 4,
	MaxExposureDisorientation = 0.65,
	ResistanceDuration = 5,
	ResistanceEffectMultiplier = 0.1,
	ServerInterval = 0.1,
	AimSendInterval = 0.125,
	AimTimeout = 0.75,
	ToggleCooldown = 0.15,
	MaxMuzzleDistance = 5,
	VisualDistance = 180,
	VisualRayInterval = 1 / 15,
	MaxBlur = 3,
	DisorientationBlur = 2,
	MaxAudioVolume = 0.07,
	-- Built-in assets work without an additional audio upload.
	SwitchSound = "rbxasset://sounds/volume_slider.ogg",
	EmptySound = "rbxasset://sounds/volume_slider.ogg",
	ExposureSound = "rbxasset://sounds/volume_slider.ogg",
})
