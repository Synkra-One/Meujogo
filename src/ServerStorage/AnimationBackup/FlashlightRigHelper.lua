--!strict
-- Studio helper for Moon Animator: attaches the placed flashlight model to an
-- R6 right arm with Motor6D/Weld joints while preserving the current pose.

local FlashlightRigHelper = {}

local FLASHLIGHT_NAMES = {
	["[ungroup] flashlight"] = true,
	["ungroup flashlight"] = true,
	["flashlight"] = true,
	["lanterna"] = true,
}

local RIG_NAMES = {
	["r6 flashlight"] = true,
	["r6 novo"] = true,
	["startercharacter"] = true,
	["monstro"] = true,
	["bolha"] = true,
}

local function lowerName(instance: Instance): string
	return string.lower(instance.Name)
end

local function isR6Rig(model: Instance?): boolean
	if not model or not model:IsA("Model") then
		return false
	end
	local rightArm = model:FindFirstChild("Right Arm")
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	return rightArm ~= nil
		and rightArm:IsA("BasePart")
		and humanoid ~= nil
		and humanoid.RigType == Enum.HumanoidRigType.R6
end

local function modelAncestor(instance: Instance?): Model?
	local current = instance
	while current do
		if current:IsA("Model") then
			return current
		end
		current = current.Parent
	end
	return nil
end

local function selectedInstances(): { Instance }
	local ok, selection = pcall(function()
		return game:GetService("Selection"):Get()
	end)
	return if ok and type(selection) == "table" then selection else {}
end

local function findRig(selection: { Instance }): Model?
	for _, instance in ipairs(selection) do
		local model = modelAncestor(instance)
		if isR6Rig(model) then
			return model
		end
	end

	for _, child in ipairs(workspace:GetChildren()) do
		if isR6Rig(child) and RIG_NAMES[lowerName(child)] then
			return child :: Model
		end
	end

	for _, child in ipairs(workspace:GetChildren()) do
		if isR6Rig(child) then
			return child :: Model
		end
	end

	return nil
end

local function isFlashlightRoot(instance: Instance): boolean
	if instance:IsA("Model") or instance:IsA("Tool") then
		return FLASHLIGHT_NAMES[lowerName(instance)] == true
	end
	return instance:IsA("BasePart") and FLASHLIGHT_NAMES[lowerName(instance)] == true
end

local function findFlashlight(selection: { Instance }, rig: Model?): Instance?
	for _, instance in ipairs(selection) do
		local current: Instance? = instance
		while current and current ~= workspace do
			if current ~= rig and isFlashlightRoot(current) then
				return current
			end
			current = current.Parent
		end
	end

	for _, descendant in ipairs(workspace:GetDescendants()) do
		local insideRig = rig ~= nil and descendant:IsDescendantOf(rig)
		if descendant ~= rig and not insideRig and isFlashlightRoot(descendant) then
			return descendant
		end
	end

	return nil
end

local function collectParts(root: Instance): { BasePart }
	local parts = {}
	if root:IsA("BasePart") then
		table.insert(parts, root)
	end
	for _, descendant in ipairs(root:GetDescendants()) do
		if descendant:IsA("BasePart") then
			table.insert(parts, descendant)
		end
	end
	return parts
end

local function namedPart(root: Instance, name: string): BasePart?
	if root:IsA("BasePart") and root.Name == name then
		return root
	end
	local found = root:FindFirstChild(name, true)
	return if found and found:IsA("BasePart") then found else nil
end

local function chooseHandle(root: Instance, parts: { BasePart }): BasePart?
	local handle = namedPart(root, "Handle") or namedPart(root, "Flashlight") or namedPart(root, "Body")
	if handle then
		return handle
	end

	table.sort(parts, function(a, b)
		return a.Size.Magnitude > b.Size.Magnitude
	end)
	return parts[1]
end

local function partSet(parts: { BasePart }): { [BasePart]: boolean }
	local set = {}
	for _, part in ipairs(parts) do
		set[part] = true
	end
	return set
end

local function clearFlashlightJoints(root: Instance, parts: { BasePart })
	local set = partSet(parts)
	for _, descendant in ipairs(root:GetDescendants()) do
		if descendant:IsA("JointInstance") then
			if (descendant.Part0 and set[descendant.Part0]) or (descendant.Part1 and set[descendant.Part1]) then
				descendant:Destroy()
			end
		elseif descendant:IsA("Constraint") then
			descendant:Destroy()
		end
	end
end

local function weldToHandle(handle: BasePart, part: BasePart)
	if part == handle then
		return
	end

	local weld = Instance.new("Weld")
	weld.Name = "FlashlightPartWeld"
	weld.Part0 = handle
	weld.Part1 = part
	weld.C0 = handle.CFrame:ToObjectSpace(part.CFrame)
	weld.C1 = CFrame.identity
	weld.Parent = part
end

local function setStudioPartState(part: BasePart)
	part.Anchored = false
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = false
	part.Massless = true
end

function FlashlightRigHelper.Attach(rig: Model?, flashlight: Instance?): (boolean, string)
	local selection = selectedInstances()
	rig = rig or findRig(selection)
	if not isR6Rig(rig) then
		return false, "nao achei um rig R6 com Right Arm"
	end

	flashlight = flashlight or findFlashlight(selection, rig)
	if not flashlight then
		return false, "nao achei o modelo [Ungroup] Flashlight/Lanterna no Workspace"
	end

	local rightArm = (rig :: Model):FindFirstChild("Right Arm")
	if not rightArm or not rightArm:IsA("BasePart") then
		return false, "o rig encontrado nao tem Right Arm como BasePart"
	end

	local parts = collectParts(flashlight)
	if #parts == 0 then
		return false, "o modelo da lanterna nao tem nenhuma BasePart"
	end

	local handle = chooseHandle(flashlight, parts)
	if not handle then
		return false, "nao consegui escolher a peca principal da lanterna"
	end

	for _, part in ipairs(parts) do
		setStudioPartState(part)
	end
	clearFlashlightJoints(flashlight, parts)

	for _, part in ipairs(parts) do
		weldToHandle(handle, part)
	end

	local old = rightArm:FindFirstChild("RightGripFlashlight")
	if old then
		old:Destroy()
	end

	local motor = Instance.new("Motor6D")
	motor.Name = "RightGripFlashlight"
	motor.Part0 = rightArm
	motor.Part1 = handle
	motor.C0 = rightArm.CFrame:ToObjectSpace(handle.CFrame)
	motor.C1 = CFrame.identity
	motor.Transform = CFrame.identity
	motor.Parent = rightArm

	flashlight:SetAttribute("MoonAnimatorAttached", true)
	flashlight:SetAttribute("MoonAnimatorRig", (rig :: Model).Name)
	flashlight:SetAttribute("MoonAnimatorHandle", handle.Name)

	local ok, selectionService = pcall(function()
		return game:GetService("Selection")
	end)
	if ok then
		selectionService:Set({ rig :: Model, flashlight })
	end

	return true, string.format(
		"%s preso em %s.Right Arm usando %s; posicao atual preservada.",
		flashlight:GetFullName(),
		(rig :: Model).Name,
		handle.Name
	)
end

return FlashlightRigHelper
