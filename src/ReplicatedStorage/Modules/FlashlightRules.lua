--!strict
local Config = require(script.Parent.FlashlightConfig)
local Rules = {}

export type ExposureState = {
	exposure: number,
	resistantUntil: number,
	disorientedUntil: number,
	nextDamageAt: number,
}

function Rules.NewExposure(): ExposureState
	return { exposure = 0, resistantUntil = 0, disorientedUntil = 0, nextDamageAt = 0 }
end

function Rules.Battery(value: number, enabled: boolean, dt: number): number
	return math.clamp(value - (if enabled then Config.BatteryDrainRate * dt else 0), 0, Config.BatteryMax)
end

-- Exactly one update per monster, regardless of the number of light sources.
function Rules.Step(state: ExposureState, illuminated: boolean, dt: number, now: number): (boolean, boolean)
	if now < state.resistantUntil then
		state.exposure = math.max(0, state.exposure - Config.ExposureDecayRate * dt)
		return false, false
	end
	state.exposure = math.clamp(state.exposure + (if illuminated then Config.ExposureRate else -Config.ExposureDecayRate) * dt,
		0, Config.MaxExposure)
	local damage = illuminated and state.exposure >= Config.DamageExposure and now >= state.nextDamageAt
	if damage then state.nextDamageAt = now + Config.DamageCooldown end
	local peak = illuminated and state.exposure >= Config.MaxExposure
	if peak then
		state.disorientedUntil = now + Config.MaxExposureDisorientation
		state.resistantUntil = state.disorientedUntil + Config.ResistanceDuration
		state.exposure = 0
	end
	return damage, peak
end

function Rules.Intensity(state: ExposureState, illuminated: boolean, now: number): number
	if now < state.disorientedUntil then return 1 end
	if now < state.resistantUntil then return if illuminated then Config.ResistanceEffectMultiplier else 0 end
	return math.clamp(state.exposure / Config.MaxExposure, 0, 1)
end

function Rules.Slow(state: ExposureState, illuminated: boolean, now: number): number
	if now < state.disorientedUntil then return Config.MonsterSlow end
	if now < state.resistantUntil then return if illuminated then Config.MonsterSlow * Config.ResistanceEffectMultiplier else 0 end
	return Config.MonsterSlow * math.clamp((state.exposure - Config.EffectStartExposure)
		/ (Config.MaxExposure - Config.EffectStartExposure), 0, 1)
end

function Rules.ValidDirection(direction: any): boolean
	if typeof(direction) ~= "Vector3" then return false end
	local length = direction.Magnitude
	return length == length and length > 0.9 and length < 1.1
end

function Rules.InCone(origin: Vector3, direction: Vector3, point: Vector3, range: number?, angle: number?): boolean
	local offset = point - origin
	local distance = offset.Magnitude
	return distance > 0.01 and distance <= (range or Config.FlashlightRange)
		and direction:Dot(offset / distance) >= math.cos(math.rad((angle or Config.BeamAngle) / 2))
end

function Rules.ValidBurstAim(root: BasePart?, direction: any): boolean
	if not root or not Rules.ValidDirection(direction) then return false end
	local aim = root.CFrame:VectorToObjectSpace(direction.Unit)
	return math.abs(math.asin(math.clamp(aim.Y, -1, 1))) <= math.rad(Config.FlashBurstMaxAimPitch)
		and math.abs(math.atan2(-aim.X, -aim.Z)) <= math.rad(Config.FlashBurstMaxAimYaw)
end

-- Shared by monster inputs and server entry points. A distinct flag avoids
-- clearing somebody else's stun when the flashlight's power lock expires.
function Rules.PowerBlocked(character: Model?): boolean
	return character ~= nil and (character:GetAttribute("PowerStunned") == true
		or character:GetAttribute("FlashPowerBlocked") == true)
end

function Rules.BurstEnvelope(now: number, startedAt: number, endsAt: number): number
	if now < startedAt or now >= endsAt or endsAt <= startedAt then return 0 end
	local attack = math.clamp((now - startedAt) / 0.08, 0, 1)
	local fade = math.clamp((endsAt - now) / math.max(0.1, (endsAt - startedAt) * 0.75), 0, 1)
	return attack * fade * fade * (3 - 2 * fade)
end

return Rules
