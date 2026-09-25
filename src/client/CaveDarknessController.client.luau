--!strict
-- A caverna tem volumes invisíveis no mapa. O escuro é local ao observador:
-- a lanterna continua iluminando o mundo, e só o Monstro recebe visão própria.

local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage.Modules.GameConfig)
local player = Players.LocalPlayer

local darkness = Instance.new("ColorCorrectionEffect")
darkness.Name = "CaveSurvivorDarkness"
darkness.Enabled = false
darkness.Parent = Lighting

local visionAnchor = Instance.new("Part")
visionAnchor.Name = "LocalMonsterCaveVision"
visionAnchor.Size = Vector3.new(0.2, 0.2, 0.2)
visionAnchor.Transparency = 1
visionAnchor.Anchored = true
visionAnchor.CanCollide = false
visionAnchor.CanTouch = false
visionAnchor.CanQuery = false
visionAnchor.CastShadow = false

local vision = Instance.new("PointLight")
vision.Name = "MonsterCaveLight"
vision.Color = Color3.fromRGB(192, 183, 226)
vision.Brightness = 1.8
vision.Range = 44
vision.Shadows = false
vision.Enabled = false
vision.Parent = visionAnchor

local zonesFolder: Folder? = nil
local zones: { BasePart } = {}
local scanElapsed = 1
local darknessAmount = 0
local neutralTint = Color3.new(1, 1, 1)
local caveTint = Color3.fromRGB(194, 204, 220)

local function refreshZones()
	local island = workspace:FindFirstChild("Ilha")
	local cave = island and island:FindFirstChild("Caverna")
	local folder = cave and cave:FindFirstChild("DarknessZones")
	if folder == zonesFolder and folder and #zones == #folder:GetChildren() then
		return
	end
	zonesFolder = if folder and folder:IsA("Folder") then folder else nil
	table.clear(zones)
	if not zonesFolder then
		return
	end
	for _, child in zonesFolder:GetChildren() do
		if child:IsA("BasePart") then
			table.insert(zones, child)
		end
	end
end

local function cameraInsideCave(position: Vector3): boolean
	for _, zone in zones do
		local localPoint = zone.CFrame:PointToObjectSpace(position)
		local half = zone.Size * 0.5
		if math.abs(localPoint.X) <= half.X and math.abs(localPoint.Y) <= half.Y
			and math.abs(localPoint.Z) <= half.Z then
			return true
		end
	end
	return false
end

RunService.RenderStepped:Connect(function(dt)
	scanElapsed += dt
	if scanElapsed >= 0.35 then
		scanElapsed = 0
		refreshZones()
	end

	local camera = workspace.CurrentCamera
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local inCave = (root ~= nil and root:IsA("BasePart") and cameraInsideCave(root.Position))
		or (camera ~= nil and cameraInsideCave(camera.CFrame.Position))
	local monster = player:GetAttribute("Role") == GameConfig.Roles.Monster
		and player:GetAttribute("InRound") == true
		and player:GetAttribute("Eliminado") ~= true
	local target = if inCave and not monster then 1 else 0
	darknessAmount += (target - darknessAmount) * math.min(1, dt * 7)

	darkness.Enabled = darknessAmount > 0.01
	if darkness.Enabled then
		darkness.Brightness = -0.38 * darknessAmount
		darkness.Contrast = 0.19 * darknessAmount
		darkness.Saturation = -0.3 * darknessAmount
		darkness.TintColor = neutralTint:Lerp(caveTint, darknessAmount)
	end

	vision.Enabled = inCave and monster
	if vision.Enabled and camera then
		if visionAnchor.Parent ~= workspace then
			visionAnchor.Parent = workspace
		end
		visionAnchor.CFrame = camera.CFrame
	elseif visionAnchor.Parent then
		visionAnchor.Parent = nil
	end
end)
