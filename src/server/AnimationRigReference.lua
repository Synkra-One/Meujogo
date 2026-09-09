--!strict
-- Mantem somente o dummy de animacao do Monster em 1.2x durante o Play para
-- comparacao e preview. Nao toca em Player.Character nem no R6 novo.

local Workspace = game:GetService("Workspace")

local AnimationRigReference = {}
local TARGET_SCALE = 1.2
local BODY_NAMES = {
	"Head", "Torso", "Right Arm", "Left Arm",
	"Right Leg", "Left Leg", "HumanoidRootPart",
}
local REFERENCE_NAMES: { [string]: boolean } = {
	["r6 monster"] = true,
}

local function bodyBottom(model: Model): number
	local bottom = math.huge
	for _, name in BODY_NAMES do
		local part = model:FindFirstChild(name)
		if part and part:IsA("BasePart") then
			bottom = math.min(bottom, part.Position.Y - part.Size.Y * 0.5)
		end
	end
	return bottom
end

local function isReference(instance: Instance): boolean
	return instance:IsA("Model") and REFERENCE_NAMES[string.lower(instance.Name)] == true
end

local function prepare(instance: Instance)
	if not isReference(instance) then return end
	local model = instance :: Model
	local root = model:FindFirstChild("HumanoidRootPart")
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	if not root or not root:IsA("BasePart") or not humanoid
		or humanoid.RigType ~= Enum.HumanoidRigType.R6 then
		warn("[AnimationRigReference] " .. model.Name .. " nao e um rig R6 completo.")
		return
	end

	local floor = bodyBottom(model)
	if math.abs(model:GetScale() - TARGET_SCALE) > 1e-4 then
		model:ScaleTo(TARGET_SCALE)
	end
	local scaledBottom = bodyBottom(model)
	if floor < math.huge and scaledBottom < math.huge then
		model:PivotTo(model:GetPivot() + Vector3.new(0, floor - scaledBottom, 0))
	end

	root.Anchored = true
	model:SetAttribute("AnimationReference", true)
	model:SetAttribute("MonsterScaleMultiplier", TARGET_SCALE)
	print(string.format(
		"[AnimationRigReference] %s confirmado em %.1fx (altura %.2f).",
		model:GetFullName(), model:GetScale(), model:GetExtentsSize().Y
	))
end

function AnimationRigReference.Init()
	for _, child in Workspace:GetChildren() do
		prepare(child)
	end
	Workspace.ChildAdded:Connect(prepare)
end

return AnimationRigReference
