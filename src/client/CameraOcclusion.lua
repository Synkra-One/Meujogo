--!strict
-- A varredura volumetrica protege a lente; o raio protege paredes finas.
-- A consulta de sobreposicao cobre pecas ja intersectando a esfera, caso
-- que Spherecast nao detecta (porta fechando, spawn ou streaming).
local Occlusion = {}

function Occlusion.Release(previous: number, limit: number, response: number, dt: number): number
	if limit <= previous then return limit end
	return previous + (limit - previous) * (1 - math.exp(-response * math.max(dt, 0)))
end

function Occlusion.Distance(world: WorldRoot, origin: Vector3, target: Vector3,
	radius: number, padding: number, rayParams: RaycastParams, overlapParams: OverlapParams): number
	local delta = target - origin
	local length = delta.Magnitude
	if length < 0.001 then return 0 end
	local direction = delta / length
	local allowed = length
	local sphere = world:Spherecast(origin, radius, delta, rayParams)
	local ray = world:Raycast(origin, delta, rayParams)
	for _, hit in { sphere, ray } do
		allowed = math.min(allowed, math.max(0, hit.Distance - padding))
	end

	-- Conservative OBB overlap: never accept a camera center inside a wall.
	-- The engine broad phase alone can report nearby corners that do not
	-- actually intersect the sphere, so check the nearest point as well.
	local function occupied(distance: number): boolean
		local point = origin + direction * distance
		for _, part in world:GetPartBoundsInRadius(point, radius, overlapParams) do
			local localPoint = part.CFrame:PointToObjectSpace(point)
			local half = part.Size * 0.5
			local nearest = Vector3.new(
				math.clamp(localPoint.X, -half.X, half.X),
				math.clamp(localPoint.Y, -half.Y, half.Y),
				math.clamp(localPoint.Z, -half.Z, half.Z)
			)
			if (localPoint - nearest).Magnitude < radius then return true end
		end
		return false
	end
	if occupied(allowed) then
		local step = math.max(radius * 0.5, length / 32)
		repeat allowed = math.max(0, allowed - step) until allowed == 0 or not occupied(allowed)
	end
	return allowed
end

return Occlusion
