--!strict
-- Server-only target selection for the Monster Grab.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local GameConfig = require(ReplicatedStorage.Modules.GameConfig)
local Elimination = require(script.Parent.Elimination)

local GrabTargeting = {}

export type Candidate = {
	player: Player,
	character: Model,
	humanoid: Humanoid,
	root: BasePart,
	distance: number,
}

local function isTargetRole(player: Player): boolean
	local role = player:GetAttribute("Role")
	return role == GameConfig.Roles.Survivor or role == GameConfig.Roles.Spy
end

local function visiblePoint(monsterCharacter: Model, victimCharacter: Model, origin: Vector3, point: Vector3): boolean
	local delta = point - origin
	if delta.Magnitude < 0.01 then
		return true
	end

	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { monsterCharacter }
	params.IgnoreWater = true

	local hit = Workspace:Raycast(origin, delta, params)
	return hit == nil or hit.Instance:IsDescendantOf(victimCharacter)
end

local function hasLineOfSight(monsterCharacter: Model, monsterRoot: BasePart, victimCharacter: Model, victimRoot: BasePart): boolean
	local originPart = monsterCharacter:FindFirstChild("Head") or monsterCharacter:FindFirstChild("Torso")
	local origin = if originPart and originPart:IsA("BasePart") then originPart.Position else monsterRoot.Position

	for _, name in { "Head", "UpperTorso", "Torso", "HumanoidRootPart" } do
		local pointPart = victimCharacter:FindFirstChild(name)
		if pointPart and pointPart:IsA("BasePart") and visiblePoint(monsterCharacter, victimCharacter, origin, pointPart.Position) then
			return true
		end
	end

	return visiblePoint(monsterCharacter, victimCharacter, origin, victimRoot.Position)
end

function GrabTargeting.FindBest(monsterPlayer: Player, monsterCharacter: Model, monsterRoot: BasePart, config: any): Candidate?
	local best: Candidate? = nil
	local halfAngle = math.rad(math.clamp(config.GrabAngle, 1, 179) * 0.5)
	local coneCos = math.cos(halfAngle)
	local forward = monsterRoot.CFrame.LookVector * Vector3.new(1, 0, 1)
	if forward.Magnitude < 0.01 then
		return nil
	end
	forward = forward.Unit

	for _, player in Players:GetPlayers() do
		if player == monsterPlayer or not isTargetRole(player) or player:GetAttribute("InRound") ~= true
			or Elimination.IsEliminated(player) then
			continue
		end

		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if not character or not humanoid or humanoid.Health <= 0 or not root or not root:IsA("BasePart")
			or root.Anchored or humanoid.Sit or humanoid.PlatformStand
			or character:GetAttribute("GrabLocked") == true or character:GetAttribute("Eliminado") == true
			or character:FindFirstChild("Dead") or character:FindFirstChildOfClass("ForceField")
			or character:GetAttribute("Invulneravel") == true or character:GetAttribute("Imune") == true
			or character:GetAttribute("ExtractionBoarded") == true then
			continue
		end

		local offset = root.Position - monsterRoot.Position
		local distance = offset.Magnitude
		local horizontal = offset * Vector3.new(1, 0, 1)
		if distance < 0.01 or distance > config.GrabRange or horizontal.Magnitude < 0.01
			or math.abs(offset.Y) > config.MaxVerticalDifference
			or horizontal.Unit:Dot(forward) < coneCos then
			continue
		end

		if not hasLineOfSight(monsterCharacter, monsterRoot, character, root) then
			continue
		end

		if not best or distance < best.distance then
			best = {
				player = player,
				character = character,
				humanoid = humanoid,
				root = root,
				distance = distance,
			}
		end
	end

	return best
end

return GrabTargeting
