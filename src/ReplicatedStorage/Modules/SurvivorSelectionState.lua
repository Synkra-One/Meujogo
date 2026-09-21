--!strict
-- Pure presentation rules, independent from Roblox services and remotes.
local State = {}
function State.Availability(snapshot: any, id: string, userId: number): string
	local availability = snapshot and snapshot.availability and snapshot.availability[id]
	if availability and availability ~= "Available" then return availability end
	local owner = snapshot and snapshot.roster and snapshot.roster[id]
	if owner and owner ~= userId then return "Taken" end
	return "Available"
end
function State.Preview(choice: string?, hover: string?, fallback: string, locked: boolean): string
	return (if not locked then hover else nil) or choice or fallback
end
function State.CanConfirm(choice: string?, availability: string, pending: boolean, confirmed: boolean): boolean
	return choice ~= nil and availability == "Available" and not pending and not confirmed
end
-- Fit a full bounding box, including depth, using the viewport's real aspect.
-- Padding leaves space for idle motion and custom animation silhouettes.
function State.CameraDistance(x: number, y: number, z: number, aspect: number, fov: number): number
	local tangent = math.tan(math.rad(fov * 0.5))
	-- The preview orbits up to eight degrees: depth can become screen width.
	local orbit = math.sin(math.rad(8))
	local width, depth = x + z * orbit, z + x * orbit
	return math.max(y * 0.5 / tangent, width * 0.5 / (tangent * math.max(aspect, 0.05))) * 1.22 + depth * 0.5
end
return State
