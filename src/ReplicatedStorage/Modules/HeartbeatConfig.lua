--!strict
-- Medo continua pertencendo ao FearSystem. Distâncias em studs, tempos em segundos.
return {
	Enabled = true,
	MaxRange = 96,
	MinFear = 25,
	UpdateInterval = 0.2,
	SnapshotTimeout = 1.2,
	MaxVolume = 0.85,
	-- Garante que uma detecção já validada não fique inaudível só porque o
	-- primeiro pulso visual ainda é fraco. O fade continua suave até zero.
	MinVolume = 0.16,
	AudibleStrength = 0.01,
	MinBPM = 62,
	MaxBPM = 156,
	SprintMultiplier = 1.3,
	CrouchMultiplier = 0.65,
	InjuryBoost = 0.45, -- proporcional à vida perdida
	StealthMultiplier = { Min = 1.15, Max = 0.45 }, -- mesma escala do StatScaling
	ObstacleMultiplier = 0.55, -- parede atenua, não bloqueia
	DistanceExponent = 0.8,
	FadeIn = 0.3,
	FadeOut = 0.65,
	-- A aura é deliberadamente discreta e mais lenta que o coração.
	AuraFillIntensity = 0.16,
	AuraOutlineIntensity = 0.42,
	AuraPulseRateMultiplier = 0.4,
	AuraMinPulseDuty = 0.09,
	AuraMaxPulseDuty = 0.24,
	-- Coração 3D no peito: X negativo = lado esquerdo do personagem;
	-- Z negativo = frente do torso no sistema de coordenadas do avatar.
	HeartChestOffset = Vector3.new(-0.28, 0.12, -0.52),
	HeartMinSize = 0.38,
	HeartMaxSize = 0.68,
	MinPulseDuty = 0.18,
	MaxPulseDuty = 0.65, -- sempre existe um intervalo invisível
	SoundId = "rbxassetid://9043365842",
	ModelAssetId = 1994009448,
	TemplateName = "HeartbeatHeart",
	AssetsFolder = "HeartbeatAssets",
	-- Um ciclo do áudio (lub-dub). Ajustar no Studio se o asset tiver silêncio inicial.
	AudioStartTime = 0,
	AudioCycleDuration = 0.75,
	AudioReferenceBPM = 72,
}
