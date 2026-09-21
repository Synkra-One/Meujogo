--!strict
-- Matemática pura: não identifica jogadores nem cria loops/conexões.
local FearRules = {}

export type Config = {
	MaxFear: number, MaxFearDistance: number, MinFearDistance: number,
	MaxProximityFearPerSecond: number, ProximityCurveExponent: number,
	FearRecoveryDelay: number, BaseFearRecoveryPerSecond: number,
	MaxFearGainPerSecond: number,
}
export type State = { value: number, safeFor: number }

function FearRules.ProximityRate(distance: number, config: Config): number
	local t = math.clamp((config.MaxFearDistance - distance)
		/ (config.MaxFearDistance - config.MinFearDistance), 0, 1)
	local x = t ^ config.ProximityCurveExponent
	-- Smoothstep: valor e inclinação contínuos inclusive nos limites
	-- MinFearDistance/MaxFearDistance. O clamp final existe porque
	-- x²(3-2x) pode fechar um ULP acima de 1 com x ≈ 1 em ponto flutuante --
	-- o ganho base nunca pode passar do teto documentado na config.
	return math.clamp(config.MaxProximityFearPerSecond * x * x * (3 - 2 * x),
		0, config.MaxProximityFearPerSecond)
end

-- Retorna ganho/s, recuperação ativa e recuperação/s para o debug.
function FearRules.Step(state: State, distance: number, gainMultiplier: number,
	recoveryMultiplier: number, dt: number, config: Config): (number, boolean, number)
	if distance < config.MaxFearDistance then
		state.safeFor = 0
		local gain = math.min(config.MaxFearGainPerSecond, FearRules.ProximityRate(distance, config) * gainMultiplier)
		state.value = math.clamp(state.value + gain * dt, 0, config.MaxFear)
		return gain, false, 0
	end
	local previousSafe = state.safeFor
	state.safeFor = math.min(config.FearRecoveryDelay, previousSafe + dt)
	-- Só a fração do tick DEPOIS dos 4s recupera; não antecipa um tick inteiro.
	local recoveryDt = math.max(0, dt - math.max(0, config.FearRecoveryDelay - previousSafe))
	local recovering = recoveryDt > 0 and state.value > 0
	local rate = if recovering then config.BaseFearRecoveryPerSecond * recoveryMultiplier else 0
	state.value = math.clamp(state.value - rate * recoveryDt, 0, config.MaxFear)
	return 0, recovering, rate
end

export type EffectConfig = {
	MaxFear: number,
	FearStates: { Nervous: number, Scared: number, Panicked: number, ExtremePanic: number },
	StaminaPenaltyStartFear: number, MinStaminaRegenMultiplier: number, StaminaRegenCurveExponent: number,
}

function FearRules.GetState(value: number, config: EffectConfig): string
	local limits = config.FearStates
	if value >= limits.ExtremePanic then return "ExtremePanic" end
	if value >= limits.Panicked then return "Panicked" end
	if value >= limits.Scared then return "Scared" end
	if value >= limits.Nervous then return "Nervous" end
	return "Calm"
end

function FearRules.StaminaRegenMultiplier(value: number, config: EffectConfig): number
	local t = math.clamp((value - config.StaminaPenaltyStartFear)
		/ (config.MaxFear - config.StaminaPenaltyStartFear), 0, 1)
	return 1 - (1 - config.MinStaminaRegenMultiplier) * t ^ config.StaminaRegenCurveExponent
end

function FearRules.EffectChance(value: number, threshold: number, maximum: number, low: number, high: number): number
	if value < threshold then return 0 end
	local t = math.clamp((value - threshold) / (maximum - threshold), 0, 1)
	return math.clamp(low + (high - low) * t, 0, 1)
end

return FearRules
