--!strict
-- Matemática compartilhável/testável; nenhuma autoridade de movimento no cliente.
local Rules = {}

local function smooth(value: number): number
	local t = math.clamp(value, 0, 1)
	return t * t * (3 - 2 * t)
end

-- Shared speed envelope; the existing Humanoid controller keeps steering,
-- gravity, slopes and physical collision. No position writer or input relay.
function Rules.Speed(state: string, elapsed: number, base: number, exitSpeed: number, cfg: any): number
	if state == "EnteringShadow" then return base end
	if state == "ShadowRush" then
		return base + (cfg.ShadowRushMaxSpeed - base) * smooth(elapsed / cfg.ShadowRushAcceleration)
	end
	if state == "Materializing" then
		return exitSpeed + (base - exitSpeed) * smooth(elapsed / cfg.ShadowRushExitDeceleration)
	end
	return base
end

function Rules.Hidden(state: string, elapsed: number, from: number, cfg: any): number
	if state == "EnteringShadow" then return smooth(elapsed / cfg.ShadowRushEnterDuration) end
	if state == "ShadowRush" then return 1 end
	if state == "Materializing" then return from * (1 - smooth(elapsed / cfg.ShadowRushMaterializeDuration)) end
	return 0
end

function Rules.Direction(value: unknown): Vector3?
	if typeof(value) ~= "Vector3" then return nil end
	local v = value :: Vector3
	if v.X ~= v.X or v.Y ~= v.Y or v.Z ~= v.Z
		or math.abs(v.X) > 1.01 or math.abs(v.Y) > 0.01 or math.abs(v.Z) > 1.01
		or v.Magnitude > 1.05 then return nil end
	local horizontal = Vector3.new(v.X, 0, v.Z)
	return if horizontal.Magnitude > 1 then horizontal.Unit else horizontal
end

function Rules.Velocity(current: Vector3, input: Vector3, dt: number, cfg: any, exiting: boolean): Vector3
	if exiting then
		local speed = math.max(0, current.Magnitude - cfg.ShadowRushMaxSpeed * dt / cfg.ShadowRushExitDeceleration)
		return if speed > 0 then current.Unit * speed else Vector3.zero
	end
	local time = if exiting then cfg.ShadowRushExitDeceleration else cfg.ShadowRushAcceleration
	local target = if exiting then Vector3.zero else input * cfg.ShadowRushMaxSpeed
	-- Exponential steering smooths corners; acceleration/deceleration bounds
	-- prevent instant reversal even when the input jumps from forward to back.
	local delta = (target - current) * (1 - math.exp(-dt / cfg.ShadowRushTurnResponse))
	local maxDelta = cfg.ShadowRushMaxSpeed * dt / time
	if delta.Magnitude > maxDelta then delta = delta.Unit * maxDelta end
	local result = current + delta
	return if result.Magnitude > cfg.ShadowRushMaxSpeed then result.Unit * cfg.ShadowRushMaxSpeed else result
end

function Rules.SegmentDistance(point: Vector3, a: Vector3, b: Vector3): number
	local delta = b - a
	local t = if delta:Dot(delta) > 1e-6 then math.clamp((point - a):Dot(delta) / delta:Dot(delta), 0, 1) else 0
	return (point - (a + delta * t)).Magnitude
end

function Rules.InBounds(point: Vector3, half: number, margin: number): boolean
	return math.abs(point.X) <= half - margin and math.abs(point.Z) <= half - margin
end

return Rules
