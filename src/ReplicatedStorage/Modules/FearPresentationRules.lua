--!strict
-- Apenas apresentação do Fear replicado; não calcula ameaça, ganho ou gameplay.
local Rules = {}

function Rules.AssetId(value: unknown): string?
	if type(value) ~= "string" then return nil end
	local digits = string.match(value, "^rbxassetid://(%d+)$") or string.match(value, "^(%d+)$")
	if not digits or not tonumber(digits) or (tonumber(digits) :: number) <= 0 then return nil end
	return "rbxassetid://" .. digits
end

function Rules.Ratio(value: number, first: number, last: number): number
	if last <= first then return 0 end
	local t = math.clamp((value - first) / (last - first), 0, 1)
	return t * t * (3 - 2 * t)
end

function Rules.Smooth(current: number, target: number, dt: number, smoothTime: number): number
	return current + (target - current) * (1 - math.exp(-dt / math.max(smoothTime, 0.001)))
end

function Rules.Targets(fear: number, config: any): { [string]: number }
	local heart = Rules.Ratio(fear, config.HeartbeatStartFear, config.MaxFear)
	local breath = Rules.Ratio(fear, config.BreathingStartFear, config.MaxFear)
	return {
		HeartbeatVolume = heart * config.HeartbeatMaxVolume,
		HeartbeatPlaybackSpeed = config.HeartbeatMinPlaybackSpeed
			+ heart * (config.HeartbeatMaxPlaybackSpeed - config.HeartbeatMinPlaybackSpeed),
		BreathingVolume = breath * config.BreathingMaxVolume,
		BreathingPlaybackSpeed = config.BreathingMinPlaybackSpeed
			+ breath * (config.BreathingMaxPlaybackSpeed - config.BreathingMinPlaybackSpeed),
		VignetteOpacity = Rules.Ratio(fear, config.VignetteStartFear, config.VignetteMaxFear)
			* math.clamp(config.VignetteMaxOpacity, 0, 0.4),
		BlurSize = Rules.Ratio(fear, config.BlurStartFear, config.MaxFear) * math.clamp(config.BlurMaxSize, 0, 4),
		-- Sem mixer central de FOV: nunca escreve por cima do tween de mira/sprint.
		FearFOVOffset = 0,
	}
end

return Rules
