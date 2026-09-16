-- Moon Animator 2 safety net.
-- Keeps versioned copies of ServerStorage.MoonAnimator2Saves and can restore a
-- copy without overwriting the current (possibly damaged) files.

local ServerStorage = game:GetService("ServerStorage")
local Selection = game:GetService("Selection")

local toolbar = plugin:CreateToolbar("Moon Backup Seguro")
local protectButton = toolbar:CreateButton("ProtectMoon", "Salvar agora os arquivos reais do Moon Animator 2", "")
local recoverButton = toolbar:CreateButton("RecoverMoon", "Recuperar o ultimo backup saudavel sem apagar nada", "")
local autoButton = toolbar:CreateButton("AutoProtect", "Ligar/desligar backups automaticos do Moon Animator 2", "")
local backupRigsButton = toolbar:CreateButton("BackupRigs", "Guardar uma copia limpa dos rigs", "")
local resetRigsButton = toolbar:CreateButton("ResetRigs", "Restaurar a pose dos rigs a partir da copia limpa", "")
local poseButton = toolbar:CreateButton("PoseSnapshot", "Guardar a pose atual dos rigs", "")
local attachFlashlightButton = toolbar:CreateButton("AttachFlashlight", "Prender [Ungroup] Flashlight ao Right Arm para animar no Moon", "")

local RIG_NAMES = { "monstro", "bolha" }
local MOON_FOLDER_NAME = "MoonAnimator2Saves"
local MAX_HEALTHY_SNAPSHOTS = 30
local MAX_SUSPECT_SNAPSHOTS = 10
local MAX_POSE_SNAPSHOTS = 12
local SNAPSHOT_INTERVAL = 45
local AUTO_SETTING = "MoonBackupSeguro.AutoProtect.v2"

local autosaveEnabled = plugin:GetSetting(AUTO_SETTING)
if autosaveEnabled == nil then
	autosaveEnabled = true
end
autoButton:SetActive(autosaveEnabled)

local busy = false

local function timestamp()
	local now = DateTime.now():ToUniversalTime()
	return string.format("%04d%02d%02d_%02d%02d%02d", now.Year, now.Month, now.Day, now.Hour, now.Minute, now.Second)
end

local function uniqueName(parent, wanted)
	if not parent:FindFirstChild(wanted) then
		return wanted
	end

	local suffix = 2
	while parent:FindFirstChild(string.format("%s_%d", wanted, suffix)) do
		suffix += 1
	end
	return string.format("%s_%d", wanted, suffix)
end

local function getBackupFolder()
	local folder = ServerStorage:FindFirstChild("AnimationBackup")
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = "AnimationBackup"
		folder.Parent = ServerStorage
	end
	return folder
end

local function getChildFolder(parent, name)
	local folder = parent:FindFirstChild(name)
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = name
		folder.Parent = parent
	end
	return folder
end

local function cloneArchivable(instance)
	local wasArchivable = instance.Archivable
	instance.Archivable = true
	local ok, clone = pcall(function()
		return instance:Clone()
	end)
	instance.Archivable = wasArchivable

	if not ok then
		warn("MoonBackupSeguro: falha ao copiar", instance:GetFullName(), clone)
		return nil
	end
	return clone
end

local function stableHashStep(hash, value)
	for index = 1, #value do
		-- Keeps multiplication below the exact-integer limit of Lua numbers.
		hash = bit32.band(hash * 33 + string.byte(value, index), 0xffffffff)
	end
	return hash
end

local function valueText(instance)
	if not instance:IsA("ValueBase") then
		return ""
	end

	local ok, result = pcall(function()
		return tostring(instance.Value)
	end)
	return ok and result or "<unreadable>"
end

local function inspectTree(root)
	local descendants = root:GetDescendants()
	local lines = {}
	local topLevelTracks = 0

	for _, child in ipairs(root:GetChildren()) do
		if child:IsA("Folder") or child:IsA("Model") then
			topLevelTracks += 1
		end
	end

	for _, descendant in ipairs(descendants) do
		table.insert(lines, descendant:GetFullName() .. "\0" .. descendant.ClassName .. "\0" .. valueText(descendant))
	end
	table.sort(lines)

	local hash = 2166136261
	for _, line in ipairs(lines) do
		hash = stableHashStep(hash, line)
	end

	return {
		childCount = #root:GetChildren(),
		descendantCount = #descendants,
		topLevelTracks = topLevelTracks,
		fingerprint = string.format("%08x", hash),
	}
end

local function inspectMoonFolder(folder)
	local files = {}
	local totalDescendants = 0
	local combined = {}

	for _, file in ipairs(folder:GetChildren()) do
		local info = inspectTree(file)
		files[file.Name] = info
		totalDescendants += info.descendantCount
		table.insert(combined, file.Name .. ":" .. info.fingerprint)
	end
	table.sort(combined)

	local hash = 2166136261
	for _, value in ipairs(combined) do
		hash = stableHashStep(hash, value)
	end

	return {
		fileCount = #folder:GetChildren(),
		totalDescendants = totalDescendants,
		fingerprint = string.format("%08x", hash),
		files = files,
	}
end

local function snapshotFolders()
	local root = getBackupFolder()
	return getChildFolder(root, "MoonHealthySnapshots"), getChildFolder(root, "MoonSuspectSnapshots")
end

local function sortedSnapshots(folder)
	local result = folder:GetChildren()
	table.sort(result, function(a, b)
		return a.Name > b.Name
	end)
	return result
end

local function latestSnapshot(folder)
	return sortedSnapshots(folder)[1]
end

local function trimSnapshots(folder, limit)
	local snapshots = sortedSnapshots(folder)
	for index = limit + 1, #snapshots do
		snapshots[index]:Destroy()
	end
end

local function readSnapshotStats(snapshot)
	local stats = {}
	local manifest = snapshot and snapshot:FindFirstChild("Manifest")
	if not manifest then
		return stats
	end

	for _, entry in ipairs(manifest:GetChildren()) do
		stats[entry.Value] = {
			descendantCount = entry:GetAttribute("DescendantCount") or 0,
			topLevelTracks = entry:GetAttribute("TopLevelTracks") or 0,
		}
	end
	return stats
end

local function degradationReasons(current, baselineSnapshot)
	local reasons = {}
	local baseline = readSnapshotStats(baselineSnapshot)

	for name, previous in pairs(baseline) do
		local now = current.files[name]
		if not now then
			table.insert(reasons, string.format("arquivo '%s' desapareceu", name))
		elseif previous.topLevelTracks >= 2 and now.topLevelTracks < previous.topLevelTracks then
			table.insert(reasons, string.format("'%s' caiu de %d para %d trilhas/rigs", name, previous.topLevelTracks, now.topLevelTracks))
		elseif previous.descendantCount >= 20 and now.descendantCount < math.floor(previous.descendantCount * 0.6) then
			table.insert(reasons, string.format("'%s' perdeu muitos dados (%d -> %d)", name, previous.descendantCount, now.descendantCount))
		end
	end
	return reasons
end

local function writeManifest(snapshot, stats, reasons)
	local manifest = Instance.new("Folder")
	manifest.Name = "Manifest"
	manifest.Parent = snapshot

	for name, info in pairs(stats.files) do
		local entry = Instance.new("StringValue")
		entry.Name = uniqueName(manifest, "File")
		entry.Value = name
		entry:SetAttribute("DescendantCount", info.descendantCount)
		entry:SetAttribute("TopLevelTracks", info.topLevelTracks)
		entry:SetAttribute("ChildCount", info.childCount)
		entry:SetAttribute("Fingerprint", info.fingerprint)
		entry.Parent = manifest
	end

	snapshot:SetAttribute("Fingerprint", stats.fingerprint)
	snapshot:SetAttribute("FileCount", stats.fileCount)
	snapshot:SetAttribute("TotalDescendants", stats.totalDescendants)
	snapshot:SetAttribute("Healthy", #reasons == 0)
	snapshot:SetAttribute("Reason", table.concat(reasons, "; "))
end

local function createMoonSnapshot(force)
	if busy then
		return false
	end

	local moonFolder = ServerStorage:FindFirstChild(MOON_FOLDER_NAME)
	if not moonFolder then
		warn("MoonBackupSeguro: ServerStorage.MoonAnimator2Saves nao existe. Salve o arquivo no Moon primeiro.")
		return false
	end
	if #moonFolder:GetChildren() == 0 then
		warn("MoonBackupSeguro: MoonAnimator2Saves esta vazio; nenhum backup foi criado.")
		return false
	end

	busy = true
	local ok, result = pcall(function()
		local healthyFolder, suspectFolder = snapshotFolders()
		local stats = inspectMoonFolder(moonFolder)
		local baseline = latestSnapshot(healthyFolder)

		if not force and baseline and baseline:GetAttribute("Fingerprint") == stats.fingerprint then
			return false
		end

		local reasons = degradationReasons(stats, baseline)
		local destination = #reasons == 0 and healthyFolder or suspectFolder
		local snapshot = Instance.new("Folder")
		snapshot.Name = uniqueName(destination, "moon_" .. timestamp())

		local data = cloneArchivable(moonFolder)
		if not data then
			snapshot:Destroy()
			error("nao foi possivel copiar MoonAnimator2Saves")
		end
		data.Name = "Data"
		data.Parent = snapshot
		writeManifest(snapshot, stats, reasons)
		snapshot.Parent = destination

		trimSnapshots(healthyFolder, MAX_HEALTHY_SNAPSHOTS)
		trimSnapshots(suspectFolder, MAX_SUSPECT_SNAPSHOTS)
		if #reasons == 0 then
			print(string.format("MoonBackupSeguro: backup saudavel criado (%d arquivo(s), %d objetos)", stats.fileCount, stats.totalDescendants))
		else
			warn("MoonBackupSeguro: possivel corrupcao detectada; copia separada como SUSPEITA. " .. table.concat(reasons, "; "))
		end
		return true
	end)
	busy = false

	if not ok then
		warn("MoonBackupSeguro: erro ao criar backup", result)
		return false
	end
	return result
end

local function recoverLatestHealthy()
	if busy then
		return
	end

	local healthyFolder = select(1, snapshotFolders())
	local snapshot = latestSnapshot(healthyFolder)
	local data = snapshot and snapshot:FindFirstChild("Data")
	if not data then
		warn("MoonBackupSeguro: ainda nao existe backup saudavel para recuperar.")
		return
	end

	local moonFolder = ServerStorage:FindFirstChild(MOON_FOLDER_NAME)
	if not moonFolder then
		moonFolder = Instance.new("Folder")
		moonFolder.Name = MOON_FOLDER_NAME
		moonFolder.Parent = ServerStorage
	end

	local recovered = {}
	for _, savedFile in ipairs(data:GetChildren()) do
		local clone = cloneArchivable(savedFile)
		if clone then
			clone.Name = uniqueName(moonFolder, "RECUPERADO_" .. savedFile.Name)
			clone:SetAttribute("RecoveredFromSnapshot", snapshot.Name)
			clone.Parent = moonFolder
			table.insert(recovered, clone)
		end
	end

	Selection:Set(recovered)
	print(string.format("MoonBackupSeguro: %d arquivo(s) recuperado(s) sem substituir os atuais. Abra o arquivo RECUPERADO_ no Moon.", #recovered))
end

local function clearTransforms(model)
	for _, descendant in ipairs(model:GetDescendants()) do
		if descendant:IsA("Motor6D") then
			descendant.Transform = CFrame.identity
		end
	end
end

local function setPrimaryPart(model)
	local root = model:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		model.PrimaryPart = root
	end
end

local function createRigBackups()
	local folder = getBackupFolder()
	for _, name in ipairs(RIG_NAMES) do
		local rig = workspace:FindFirstChild(name)
		if rig and rig:IsA("Model") then
			local clone = cloneArchivable(rig)
			if clone then
				clone.Name = uniqueName(folder, name .. "_original_" .. timestamp())
				setPrimaryPart(clone)
				clearTransforms(clone)
				clone.Parent = folder
			end
		else
			warn("MoonBackupSeguro: rig nao encontrado", name)
		end
	end
	print("MoonBackupSeguro: copias dos rigs criadas sem apagar as anteriores")
end

local function getLatestRigBackup(name)
	local prefix = name .. "_original_"
	local matches = {}
	for _, child in ipairs(getBackupFolder():GetChildren()) do
		if child:IsA("Model") and string.sub(child.Name, 1, #prefix) == prefix then
			table.insert(matches, child)
		end
	end
	table.sort(matches, function(a, b) return a.Name > b.Name end)
	return matches[1] or getBackupFolder():FindFirstChild(name .. "_original")
end

local function relativePath(root, descendant)
	return string.sub(descendant:GetFullName(), #root:GetFullName() + 2)
end

local function getMotorMap(model)
	local motors = {}
	for _, descendant in ipairs(model:GetDescendants()) do
		if descendant:IsA("Motor6D") then
			motors[relativePath(model, descendant)] = descendant
		end
	end
	return motors
end

local function resetRig(name)
	local backup = getLatestRigBackup(name)
	local current = workspace:FindFirstChild(name)
	if not backup or not backup:IsA("Model") then
		warn("MoonBackupSeguro: backup do rig nao encontrado", name)
		return false
	end

	if not current or not current:IsA("Model") then
		local clone = cloneArchivable(backup)
		if not clone then return false end
		clone.Name = name
		setPrimaryPart(clone)
		clearTransforms(clone)
		clone.Parent = workspace
		return true
	end

	local backupMotors = getMotorMap(backup)
	for path, motor in pairs(getMotorMap(current)) do
		local original = backupMotors[path]
		if original then
			motor.C0 = original.C0
			motor.C1 = original.C1
		end
		motor.Transform = CFrame.identity
	end
	return true
end

local function resetRigs()
	-- Resetting a live rig while Moon is open can make it capture a bad pose.
	createMoonSnapshot(true)
	local ok = true
	for _, name in ipairs(RIG_NAMES) do
		ok = resetRig(name) and ok
	end
	warn("MoonBackupSeguro: reset concluido. Feche/reabra o arquivo no Moon antes de continuar.", ok)
end

local function createPoseSnapshot()
	local poses = getChildFolder(getBackupFolder(), "PoseSnapshots")
	local snapshot = Instance.new("Folder")
	snapshot.Name = uniqueName(poses, "pose_" .. timestamp())
	for _, name in ipairs(RIG_NAMES) do
		local rig = workspace:FindFirstChild(name)
		if rig and rig:IsA("Model") then
			local clone = cloneArchivable(rig)
			if clone then
				clone.Name = name
				clone.Parent = snapshot
			end
		end
	end
	snapshot.Parent = poses
	trimSnapshots(poses, MAX_POSE_SNAPSHOTS)
	print("MoonBackupSeguro: pose salva", snapshot.Name)
end

local function attachFlashlightToRightArm()
	local backupFolder = ServerStorage:FindFirstChild("AnimationBackup")
	local helperModule = backupFolder and backupFolder:FindFirstChild("FlashlightRigHelper")
	if not helperModule or not helperModule:IsA("ModuleScript") then
		warn("MoonBackupSeguro: FlashlightRigHelper nao encontrado em ServerStorage.AnimationBackup. Sincronize o Rojo e tente de novo.")
		return
	end

	local ok, helper = pcall(require, helperModule)
	if not ok then
		warn("MoonBackupSeguro: falha ao carregar FlashlightRigHelper", helper)
		return
	end

	local attached, message = helper.Attach()
	if attached then
		print("MoonBackupSeguro:", message)
	else
		warn("MoonBackupSeguro:", message)
	end
end

protectButton.Click:Connect(function() createMoonSnapshot(true) end)
recoverButton.Click:Connect(recoverLatestHealthy)
backupRigsButton.Click:Connect(createRigBackups)
resetRigsButton.Click:Connect(resetRigs)
poseButton.Click:Connect(createPoseSnapshot)
attachFlashlightButton.Click:Connect(attachFlashlightToRightArm)
autoButton.Click:Connect(function()
	autosaveEnabled = not autosaveEnabled
	plugin:SetSetting(AUTO_SETTING, autosaveEnabled)
	autoButton:SetActive(autosaveEnabled)
	print("MoonBackupSeguro: protecao automatica", autosaveEnabled and "LIGADA" or "DESLIGADA")
end)

task.spawn(function()
	task.wait(8)
	if autosaveEnabled then
		createMoonSnapshot(false)
	end

	while true do
		task.wait(SNAPSHOT_INTERVAL)
		-- ValueBase.Value changes do not add/remove descendants. Reinspect every
		-- cycle; the fingerprint prevents duplicate automatic snapshots.
		if autosaveEnabled then
			createMoonSnapshot(false)
		end
	end
end)

print("MoonBackupSeguro v2 carregado. Protecao automatica:", autosaveEnabled and "LIGADA" or "DESLIGADA")
