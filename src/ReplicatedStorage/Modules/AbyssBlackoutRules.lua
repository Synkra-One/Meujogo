--!strict
--[[
	AbyssBlackoutRules
	Matemática pura do Apagão do Abismo: nenhuma conexão, nenhum Remote,
	nenhuma autoridade. Servidor e cliente usam as MESMAS funções, então a
	tela do Sobrevivente e o bloqueio real da lanterna terminam juntos.

	Nada aqui guarda Fear: o valor continua sendo do FearSystem.
]]
local Rules = {}

local function smooth(value: number): number
	local t = math.clamp(value, 0, 1)
	return t * t * (3 - 2 * t)
end

--[[
	FearAmount(base, gainMultiplier, influence, maxFear)
	Converte os pontos de configuração em pontos FINAIS pro FearSystem.AddFear.

	gainMultiplier é o StatScaling.FearGainMultiplier EXISTENTE (Compostura
	0 -> 1.5, 100 -> 0.55). influence (0..1) mistura esse fator com 1 pra
	Compostura alta sofrer "um pouco menos", e não virar imunidade:
		efetivo = 1 + (gainMultiplier - 1) * influence
	O clamp final é só sanidade -- quem aplica o teto real de Fear é o
	FearSystem (math.clamp(value + amount, 0, MaxFear)).
]]
function Rules.FearAmount(base: number, gainMultiplier: number, influence: number, maxFear: number): number
	if type(base) ~= "number" or base ~= base or base <= 0 then return 0 end
	local multiplier = if type(gainMultiplier) == "number" and gainMultiplier == gainMultiplier
		then gainMultiplier else 1
	local blended = 1 + (multiplier - 1) * math.clamp(influence, 0, 1)
	return math.clamp(base * math.max(blended, 0), 0, maxFear)
end

-- Distância 3D simples: o grito atravessa parede, só o raio conta.
function Rules.InRadius(origin: Vector3, point: Vector3, radius: number): boolean
	if radius <= 0 then return false end
	return (point - origin).Magnitude <= radius
end

-- Tempo restante do efeito, em segundos, a partir de Workspace:GetServerTimeNow().
function Rules.Remaining(endsAt: number, now: number): number
	if type(endsAt) ~= "number" or endsAt ~= endsAt then return 0 end
	return math.max(0, endsAt - now)
end

export type Presentation = { Opacity: number, Blend: number, Blur: number }

--[[
	Presentation(elapsed, duration, config)
	Envelope do pulso na tela da vítima:
	  - ataque rápido (PulseAttack) até o pico PulseOpacity;
	  - queda exponencial (PulseDecay) até SustainOpacity, que fica enquanto
	    a lanterna estiver bloqueada;
	  - alívio (PulseRelease) nos últimos segundos, então ZERO no fim.
	Blend 1 = cor do pulso (vermelho escuro), 0 = escuridão sustentada.
	Fora da janela devolve tudo zerado: nenhum efeito permanente.
]]
function Rules.Presentation(elapsed: number, duration: number, config: any): Presentation
	if type(elapsed) ~= "number" or elapsed ~= elapsed or elapsed < 0
		or type(duration) ~= "number" or duration <= 0 or elapsed >= duration then
		return { Opacity = 0, Blend = 0, Blur = 0 }
	end
	local attack = smooth(elapsed / math.max(config.PulseAttack, 1e-3))
	local burst = math.exp(-math.max(0, elapsed - config.PulseAttack) / math.max(config.PulseDecay, 1e-3))
	local release = smooth(math.min(1, (duration - elapsed) / math.max(config.PulseRelease, 1e-3)))
	local sustain = math.clamp(config.SustainOpacity, 0, 1)
	local peak = math.clamp(config.PulseOpacity, 0, 1)
	local level = sustain + (peak - sustain) * burst
	local opacity = math.clamp(level * attack * release, 0, 1)
	return { Opacity = opacity, Blend = math.clamp(burst * attack, 0, 1),
		Blur = math.clamp(config.Blur, 0, 8) * math.clamp(opacity / math.max(peak, 1e-3), 0, 1) }
end

return Rules
