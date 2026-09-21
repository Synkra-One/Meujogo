--!strict
local Workspace = game:GetService("Workspace")
local Modules = game:GetService("ReplicatedStorage").Modules
local Config = require(Modules.FlashlightConfig)
local Rules = require(Modules.FlashlightRules)
local Targeting = {}

function Targeting.Source(character: Model, tool: Tool): (Vector3?, RaycastParams?)
	local head = character:FindFirstChild("Head")
	local handle = tool:FindFirstChild("Handle")
	local origin = handle and handle:FindFirstChild("FlashlightOrigin")
	if not head or not head:IsA("BasePart") or not origin or not origin:IsA("Attachment") then return nil, nil end
	local position = origin.WorldPosition
	local offset = position - head.Position
	if offset.Magnitude ~= offset.Magnitude or offset.Magnitude > Config.MaxMuzzleDistance then return nil, nil end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { character }
	-- Prevent a hand/Handle clipped through a wall from becoming a valid origin.
	if offset.Magnitude > 0.01 and Workspace:Raycast(head.Position, offset, params) then return nil, nil end
	return position, params
end

function Targeting.Hits(origin: Vector3, direction: Vector3, target: Model, params: RaycastParams, range: number?, angle: number?): boolean
	-- Head and torso samples permit partial cover, but every accepted sample
	-- must be in the actual cone and the first visible hit must be this target.
	for _, name in { "Head", "UpperTorso", "Torso", "HumanoidRootPart" } do
		local part = target:FindFirstChild(name)
		if part and part:IsA("BasePart") and Rules.InCone(origin, direction, part.Position, range, angle) then
			local result = Workspace:Raycast(origin, part.Position - origin, params)
			if (result and result.Instance:IsDescendantOf(target)) or (range ~= nil and result == nil) then return true end
		end
	end
	return false
end

return Targeting
