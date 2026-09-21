-- Paste this whole file into Roblox Studio's Command Bar and run it once.
-- It keeps the old Handle and its animation joints, hides only its visual part,
-- and welds the new "crowbar" object to that legacy Handle.

local WORKSPACE_MODEL_NAME = "crowbar animations"
local RIG_NAME = "R6"
local LEGACY_HANDLE_NAME = "Handle"
local NEW_VISUAL_NAME = "crowbar"
local CROWBAR_ASSET_ID = 81510444

-- Optional overrides. Leave MAIN_PART_NAME empty to let the script choose:
-- 1) a part named Handle/Grip/Main/Root inside the new crowbar, 2) nearest part
-- to the old Handle, 3) largest part.
local MAIN_PART_NAME = ""

-- If the selected visual grip is rotated differently than the old Handle, adjust
-- this offset and run again from the backup. The default overlays main part on
-- the legacy Handle exactly.
local VISUAL_TO_HANDLE_OFFSET = CFrame.new()

local function fail(message)
	error("[CrowbarVisualSetup] " .. message, 0)
end

local function getFullName(instance)
	local ok, result = pcall(function()
		return instance:GetFullName()
	end)
	return if ok then result else instance.Name
end

local function firstModelOrPart(container)
	if container:IsA("Model") then
		local childModel = nil
		local childPart = nil
		for _, child in ipairs(container:GetChildren()) do
			if not childModel and child:IsA("Model") then
				childModel = child
			elseif not childPart and child:IsA("BasePart") then
				childPart = child
			end
		end
		return childModel or childPart or container
	end
	if container:IsA("BasePart") then
		return container
	end
	return nil
end

local function loadCrowbarAsset(parent)
	local insertService = game:GetService("InsertService")
	local ok, asset = pcall(function()
		return insertService:LoadAsset(CROWBAR_ASSET_ID)
	end)
	if not ok or not asset then
		fail(("Could not load crowbar asset %d: %s"):format(CROWBAR_ASSET_ID, tostring(asset)))
	end

	local visual = firstModelOrPart(asset)
	if not visual then
		asset:Destroy()
		fail(("Crowbar asset %d did not contain a Model or BasePart."):format(CROWBAR_ASSET_ID))
	end

	visual.Name = NEW_VISUAL_NAME
	visual.Parent = parent
	if visual ~= asset then
		for _, child in ipairs(asset:GetChildren()) do
			if child ~= visual then
				child:Destroy()
			end
		end
		asset:Destroy()
	end
	return visual
end

local root = workspace:FindFirstChild(WORKSPACE_MODEL_NAME)
if not root then
	fail(('Could not find Workspace.%q. Keep the model open in Workspace and try again.'):format(WORKSPACE_MODEL_NAME))
end

local rig = root:FindFirstChild(RIG_NAME)
if not rig or not rig:IsA("Model") then
	fail(('Could not find Model %q inside %s.'):format(RIG_NAME, getFullName(root)))
end

local newVisual = rig:FindFirstChild(NEW_VISUAL_NAME, true)
if not newVisual then
	print(("[CrowbarVisualSetup] %q was not found inside the rig. Loading asset %d..."):format(NEW_VISUAL_NAME, CROWBAR_ASSET_ID))
	newVisual = loadCrowbarAsset(rig)
end

local legacyHandle = nil
for _, descendant in ipairs(rig:GetDescendants()) do
	if descendant.Name == LEGACY_HANDLE_NAME and descendant:IsA("BasePart") and descendant ~= newVisual and not descendant:IsDescendantOf(newVisual) then
		legacyHandle = descendant
		break
	end
end
if not legacyHandle then
	fail(('Could not find a legacy BasePart named %q outside the new %q visual inside %s.'):format(LEGACY_HANDLE_NAME, NEW_VISUAL_NAME, getFullName(rig)))
end
if newVisual:IsDescendantOf(legacyHandle) then
	fail(('The new %q object is inside the legacy Handle. Move it under the rig, beside Handle, and run again.'):format(NEW_VISUAL_NAME))
end

local oldArchivable = rig.Archivable
rig.Archivable = true
local backup = rig:Clone()
rig.Archivable = oldArchivable
backup.Name = ("%s_Backup_CrowbarVisual_%s"):format(RIG_NAME, os.date("%Y%m%d_%H%M%S"))
backup.Parent = root
print(("[CrowbarVisualSetup] Backup created: %s"):format(getFullName(backup)))

print(("[CrowbarVisualSetup] Legacy Handle: %s"):format(getFullName(legacyHandle)))
for _, descendant in ipairs(rig:GetDescendants()) do
	if descendant:IsA("Motor6D") or descendant:IsA("Weld") or descendant:IsA("WeldConstraint") then
		local part0 = descendant.Part0
		local part1 = descendant.Part1
		if part0 == legacyHandle or part1 == legacyHandle then
			print(("[CrowbarVisualSetup] Existing connector: %s | %s -> %s"):format(
				getFullName(descendant),
				part0 and getFullName(part0) or "nil",
				part1 and getFullName(part1) or "nil"
			))
		end
	elseif descendant:IsA("Attachment") and descendant.Parent == legacyHandle then
		print(("[CrowbarVisualSetup] Handle attachment: %s | Position=%s Orientation=%s"):format(
			getFullName(descendant),
			tostring(descendant.Position),
			tostring(descendant.Orientation)
		))
	end
end

local visualParts = {}
if newVisual:IsA("BasePart") then
	table.insert(visualParts, newVisual)
elseif newVisual:IsA("Model") then
	for _, descendant in ipairs(newVisual:GetDescendants()) do
		if descendant:IsA("BasePart") then
			table.insert(visualParts, descendant)
		end
	end
else
	fail(('%q must be either a BasePart or a Model containing BaseParts. Found %s.'):format(NEW_VISUAL_NAME, newVisual.ClassName))
end

if #visualParts == 0 then
	fail(("The new %q visual has no BasePart descendants."):format(NEW_VISUAL_NAME))
end

local function partVolume(part)
	return part.Size.X * part.Size.Y * part.Size.Z
end

local function chooseMainPart()
	if MAIN_PART_NAME ~= "" then
		local named = newVisual:FindFirstChild(MAIN_PART_NAME, true)
		if named and named:IsA("BasePart") then
			return named
		end
		fail(('MAIN_PART_NAME is %q, but no matching BasePart was found inside %s.'):format(MAIN_PART_NAME, getFullName(newVisual)))
	end

	local namePriority = {
		handle = true,
		grip = true,
		main = true,
		root = true,
	}
	for _, part in ipairs(visualParts) do
		if namePriority[string.lower(part.Name)] then
			return part
		end
	end

	local nearest = nil
	local nearestDistance = math.huge
	for _, part in ipairs(visualParts) do
		local distance = (part.Position - legacyHandle.Position).Magnitude
		if distance < nearestDistance then
			nearest = part
			nearestDistance = distance
		end
	end
	if nearest and nearestDistance <= math.max(legacyHandle.Size.Magnitude, 3) then
		return nearest
	end

	local largest = visualParts[1]
	for _, part in ipairs(visualParts) do
		if partVolume(part) > partVolume(largest) then
			largest = part
		end
	end
	return largest
end

local mainPart = chooseMainPart()
print(("[CrowbarVisualSetup] New visual: %s"):format(getFullName(newVisual)))
print(("[CrowbarVisualSetup] Main visual part: %s"):format(getFullName(mainPart)))

if newVisual:IsA("Model") then
	newVisual.PrimaryPart = mainPart
	newVisual:PivotTo(legacyHandle.CFrame * VISUAL_TO_HANDLE_OFFSET)
else
	newVisual.CFrame = legacyHandle.CFrame * VISUAL_TO_HANDLE_OFFSET
end

for _, part in ipairs(visualParts) do
	part.Anchored = false
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = false
	part.Massless = true
end

for _, part in ipairs(visualParts) do
	if part ~= mainPart then
		local existing = part:FindFirstChild("CrowbarVisual_InternalWeld")
		if existing and existing:IsA("WeldConstraint") then
			existing.Part0 = mainPart
			existing.Part1 = part
		else
			local weld = Instance.new("WeldConstraint")
			weld.Name = "CrowbarVisual_InternalWeld"
			weld.Part0 = mainPart
			weld.Part1 = part
			weld.Parent = part
		end
	end
end

local handleWeld = mainPart:FindFirstChild("CrowbarVisual_ToLegacyHandle")
if handleWeld and handleWeld:IsA("WeldConstraint") then
	handleWeld.Part0 = legacyHandle
	handleWeld.Part1 = mainPart
else
	handleWeld = Instance.new("WeldConstraint")
	handleWeld.Name = "CrowbarVisual_ToLegacyHandle"
	handleWeld.Part0 = legacyHandle
	handleWeld.Part1 = mainPart
	handleWeld.Parent = mainPart
end

legacyHandle.Transparency = 1
for _, child in ipairs(legacyHandle:GetDescendants()) do
	if child:IsA("Decal") or child:IsA("Texture") then
		child.Transparency = 1
	end
end

print("[CrowbarVisualSetup] Done.")
print("[CrowbarVisualSetup] The old Handle and its existing joints were preserved.")
print("[CrowbarVisualSetup] The new crowbar is visual-only and follows the legacy Handle through equip, idle, charging, charged, hit1 and hit2.")
print("[CrowbarVisualSetup] Scrub the Moon Animator animations now. If the grip is rotated wrong, restore the backup, adjust MAIN_PART_NAME or VISUAL_TO_HANDLE_OFFSET, and run again.")
