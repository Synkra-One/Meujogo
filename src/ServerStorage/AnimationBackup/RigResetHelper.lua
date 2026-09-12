local RigResetHelper = {}

local RIG_NAMES = {
	"monstro",
	"bolha",
}

local function getBackupFolder()
	local serverStorage = game:GetService("ServerStorage")
	local folder = serverStorage:FindFirstChild("AnimationBackup")

	if not folder then
		folder = Instance.new("Folder")
		folder.Name = "AnimationBackup"
		folder.Parent = serverStorage
	end

	return folder
end

local function relativePath(root: Instance, descendant: Instance): string
	local rootName = root:GetFullName()
	local fullName = descendant:GetFullName()

	return string.sub(fullName, #rootName + 2)
end

local function getMotorMap(model: Model): {[string]: Motor6D}
	local motors = {}

	for _, descendant in ipairs(model:GetDescendants()) do
		if descendant:IsA("Motor6D") then
			motors[relativePath(model, descendant)] = descendant
		end
	end

	return motors
end

local function clearTransforms(model: Model)
	for _, descendant in ipairs(model:GetDescendants()) do
		if descendant:IsA("Motor6D") then
			descendant.Transform = CFrame.identity
		end
	end
end

local function poseFromMotors(model: Model): boolean
	local root = model:FindFirstChild("HumanoidRootPart") or model.PrimaryPart

	if not root or not root:IsA("BasePart") then
		warn("RigResetHelper: rig sem HumanoidRootPart/PrimaryPart", model:GetFullName())
		return false
	end

	model.PrimaryPart = root
	clearTransforms(model)

	local anchored = {}
	for _, descendant in ipairs(model:GetDescendants()) do
		if descendant:IsA("BasePart") then
			anchored[descendant] = descendant.Anchored
			descendant.Anchored = true
		end
	end

	local solved = {
		[root] = true,
	}
	local changed = true

	while changed do
		changed = false

		for _, descendant in ipairs(model:GetDescendants()) do
			if descendant:IsA("Motor6D") and descendant.Part0 and descendant.Part1 then
				if solved[descendant.Part0] and not solved[descendant.Part1] then
					descendant.Part1.CFrame = descendant.Part0.CFrame * descendant.C0 * descendant.C1:Inverse()
					solved[descendant.Part1] = true
					changed = true
				end
			end
		end
	end

	for part, wasAnchored in pairs(anchored) do
		part.Anchored = wasAnchored
	end

	return true
end

local function setPrimaryPart(model: Model)
	local root = model:FindFirstChild("HumanoidRootPart")

	if root and root:IsA("BasePart") then
		model.PrimaryPart = root
	end
end

function RigResetHelper.CreateBackups(rigNames: {string}?)
	local folder = getBackupFolder()

	for _, name in ipairs(rigNames or RIG_NAMES) do
		local rig = workspace:FindFirstChild(name)

		if rig and rig:IsA("Model") then
			local oldBackup = folder:FindFirstChild(name .. "_original")
			if oldBackup then
				oldBackup:Destroy()
			end

			local wasArchivable = rig.Archivable
			rig.Archivable = true
			local clone = rig:Clone()
			rig.Archivable = wasArchivable

			clone.Name = name .. "_original"
			setPrimaryPart(clone)
			clearTransforms(clone)
			clone.Parent = folder
		else
			warn("RigResetHelper: rig nao encontrado para backup", name)
		end
	end
end

function RigResetHelper.ResetRig(name: string): boolean
	local folder = getBackupFolder()
	local backup = folder:FindFirstChild(name .. "_original")
	local current = workspace:FindFirstChild(name)

	if not backup or not backup:IsA("Model") then
		warn("RigResetHelper: backup nao encontrado", name)
		return false
	end

	if not current or not current:IsA("Model") then
		local clone = backup:Clone()
		clone.Name = name
		setPrimaryPart(clone)
		clearTransforms(clone)
		clone.Parent = workspace
		return true
	end

	local backupMotors = getMotorMap(backup)

	for path, motor in pairs(getMotorMap(current)) do
		local backupMotor = backupMotors[path]

		if backupMotor then
			motor.C0 = backupMotor.C0
			motor.C1 = backupMotor.C1
		end

		motor.Transform = CFrame.identity
	end

	setPrimaryPart(current)
	return poseFromMotors(current)
end

function RigResetHelper.ResetAll(): boolean
	local ok = true

	for _, name in ipairs(RIG_NAMES) do
		ok = RigResetHelper.ResetRig(name) and ok
	end

	return ok
end

return RigResetHelper
