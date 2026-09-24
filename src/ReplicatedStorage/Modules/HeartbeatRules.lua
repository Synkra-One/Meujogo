--!strict
-- Regras puras compartilhadas; nenhum estado de medo é armazenado aqui.
local Rules = {}

function Rules.Evaluate(fear: number, maxFear: number, distance: number, movement: string?,
	injury: number, stealth: number, obstructed: boolean, cfg: any): (number, number, number)
	if fear ~= fear or distance ~= distance or fear <= cfg.MinFear or distance >= cfg.MaxRange
		or distance < 0 then return 0, cfg.MinBPM, 0 end
	local tension = math.clamp((fear - cfg.MinFear) / (maxFear - cfg.MinFear), 0, 1)
	local strength = tension ^ 1.25 * (1 - distance / cfg.MaxRange) ^ cfg.DistanceExponent
	strength *= stealth * (1 + math.clamp(injury, 0, 1) * cfg.InjuryBoost)
	if movement == "Sprint" then strength *= cfg.SprintMultiplier
	elseif movement == "Crouch" then strength *= cfg.CrouchMultiplier end
	if obstructed then strength *= cfg.ObstacleMultiplier end
	-- Saturação suave mantém o medo crescente mesmo correndo/ferido.
	strength = strength / (1 + strength * 0.35)
	return math.clamp(strength, 0, 1), cfg.MinBPM + (cfg.MaxBPM - cfg.MinBPM) * tension, tension
end

function Rules.Pulse(phase: number, tension: number, cfg: any): number
	local duty = cfg.MinPulseDuty + (cfg.MaxPulseDuty - cfg.MinPulseDuty) * tension
	if phase >= duty then return 0 end
	return math.sin(math.pi * phase / duty) ^ 2
end

function Rules.Smooth(current: number, target: number, dt: number, cfg: any): number
	local duration = if target > current then cfg.FadeIn else cfg.FadeOut
	return current + (target - current) * (1 - math.exp(-dt * 5 / duration))
end

return Rules
