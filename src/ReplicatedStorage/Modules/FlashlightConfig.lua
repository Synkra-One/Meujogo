--!strict
-- Battery uses percentage points; exposure uses seconds of continuous light.
return table.freeze({
	BatteryMax = 100,
	BatteryDrainRate = 100 / 60,
	ModelLength = 1.8,
	FlashlightRange = 36,
	BeamAngle = 38,
	Brightness = 3.5,
	-- Visual layer: a tight hotspot, broad spill and a small local fill light.
	-- These values do not change the server-side targeting cone.
	SpillAngle = 64,
	SpillBrightness = 0.65,
	FillRange = 7,
	FillBrightness = 0.18,
	LightColor = table.freeze({ 240, 247, 226 }),
	-- Flashlight animation layer. These R6 clips are published by the game
	-- owner/group and should key only the upper body/held flashlight joints.
	-- Locomotion remains owned by Animate + the movement pack.
	AnimationFadeTime = 0.16,
	AnimationLoadWarningDelay = 2,
	AnimationStateDebounce = 0.09,
	AnimationAirDebounce = 0.06,
	-- R6 aiming is intentionally led by the right shoulder. These are additive
	-- radians-per-radian multipliers over the authored holding pose.
	PoseAimResponsiveness = 10.5,
	PoseBlendResponsiveness = 18,
	-- A pitch of 1 follows the camera one-for-one.  The holding animation is
	-- already the neutral arm position, so the right arm can carry most of
	-- the vertical aiming without taking ownership of the locomotion layer.
	RightAimPitch = 1.0,
	RightAimYaw = 0.70,
	LeftAimPitch = 0.52,
	LeftAimYaw = 0.32,
	-- Keep this deliberately subtle: it sells the pose without replacing the
	-- normal Animate head/neck behaviour.
	NeckAimPitch = 0.28,
	NeckAimYaw = 0.10,
	Animations = table.freeze({
		Equip = "rbxassetid://82905353934076",
		Idle = "rbxassetid://103502806390125",
		Click = "rbxassetid://92755233522139",
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
	VisualDistance = 140,
	VisualRayInterval = 1 / 15,
	MaxBlur = 3,
	DisorientationBlur = 2,
	MaxAudioVolume = 0.07,
	-- Built-in assets work without an additional audio upload.
	SwitchSound = "rbxasset://sounds/volume_slider.ogg",
	EmptySound = "rbxasset://sounds/volume_slider.ogg",
	ExposureSound = "rbxasset://sounds/volume_slider.ogg",
})
