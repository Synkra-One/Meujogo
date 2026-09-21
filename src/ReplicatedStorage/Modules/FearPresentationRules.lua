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

--[[
	Darken(fear, time, config)
	Opacidade da camada de escurecimento, com respiração lenta. `time` é um
	relógio contínuo (os.clock() serve): a função é pura, então o teste
	consegue reproduzir qualquer instante. Abaixo de DarkenStartFear devolve 0
	-- a camada é desligada, nunca "quase invisível".
]]
function Rules.Darken(fear: number, time: number, config: any): number
	local ratio = Rules.Ratio(fear, config.DarkenStartFear, config.DarkenMaxFear)
	if ratio <= 0 then return 0 end
	local ceiling = math.clamp(config.DarkenMaxOpacity, 0, 0.6)
	local pulse = 1 - math.clamp(config.DarkenPulseAmount, 0, 0.5)
		* (0.5 + 0.5 * math.sin(time * math.pi * 2 * math.max(config.DarkenPulseSpeed, 0)))
	return math.clamp(ratio * ceiling * pulse, 0, ceiling)
end

export type HudFade = { Vitals: number, Hotbar: number, FullMapBlocked: boolean }

--[[
	HudFade(fear, config)
	Quanto esconder de cada parte do HUD: 0 = normal, 1 = sumiu. O mapa grande
	é booleano porque ele abre/fecha, não desaparece aos poucos.
	Nenhum valor daqui altera fôlego, itens ou o mapa em si -- é só leitura.
]]
function Rules.HudFade(fear: number, config: any): HudFade
	return {
		Vitals = Rules.Ratio(fear, config.HudFadeStartFear, config.HudFadeFullFear),
		Hotbar = Rules.Ratio(fear, config.HotbarFadeStartFear, config.HotbarFadeFullFear),
		FullMapBlocked = fear >= config.FullMapBlockFear,
	}
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
		-- Sem pulso: Targets é usado por quem só tem o valor de Fear. O
		-- escurecimento animado vem de Rules.Darken, que recebe o tempo.
		DarkenBase = Rules.Ratio(fear, config.DarkenStartFear, config.DarkenMaxFear)
			* math.clamp(config.DarkenMaxOpacity, 0, 0.6),
		-- Sem mixer central de FOV: nunca escreve por cima do tween de mira/sprint.
		FearFOVOffset = 0,
	}
end

return Rules
