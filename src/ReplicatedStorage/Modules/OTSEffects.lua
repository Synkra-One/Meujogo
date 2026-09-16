--!strict
--[[
	OTSEffects
	Efeitos visuais de tiro que precisam ser vistos por TODOS os jogadores,
	por isso são criados no servidor (OTSFirearmService.lua) e replicam:
	  - CreateTracer(muzzleCFrame, endPosition): Beam do Muzzle até o impacto
	  - CreateImpact(position, instance, normal): furo/partículas/som por
	    material (Terrain -> "Ground", personagem -> "Flesh")
	Port do WeaponModule do OTS, sem wait() bloqueante. Templates vêm de
	ReplicatedStorage/WeaponAssets/{Effects,Audios} (Rojo, .rbxmx).
	Instâncias criadas vão pra Workspace/System/{Tracers,Impacts}
	(default.project.json).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local SafeWait = require(script.Parent.SafeWait)

local WeaponAssets = SafeWait.Child(ReplicatedStorage, "WeaponAssets")
local Effects = SafeWait.Child(WeaponAssets, "Effects")
local Audios = SafeWait.Child(WeaponAssets, "Audios")

local OTSEffects = {}

local TRACER_LIFETIME = 0.25
local IMPACT_LIFETIME = 15
local FLESH_LIFETIME = 3

local function systemFolder(name: string): Instance
	local system = Workspace:FindFirstChild("System")
	if not system then
		system = Instance.new("Folder")
		system.Name = "System"
		system.Parent = Workspace
	end
	local folder = system:FindFirstChild(name)
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = name
		folder.Parent = system
	end
	return folder
end

--------------------------------------------------------------------------------
-- Tracer
--------------------------------------------------------------------------------

function OTSEffects.CreateTracer(muzzleCFrame: CFrame, endPosition: Vector3)
	local tracers = Effects:FindFirstChild("Tracers")
	local startTemplate = tracers and tracers:FindFirstChild("Start")
	local endTemplate = tracers and tracers:FindFirstChild("End")
	if not startTemplate or not endTemplate or not startTemplate:IsA("BasePart") or not endTemplate:IsA("BasePart") then
		return
	end

	local startPart = startTemplate:Clone()
	local endPart = endTemplate:Clone()
	for _, part in { startPart, endPart } do
		part.Anchored, part.CanCollide, part.CanTouch, part.CanQuery = true, false, false, false
	end
	local beam = startPart:FindFirstChildOfClass("Beam")
	local endAttachment = endPart:FindFirstChildOfClass("Attachment")
	if beam and endAttachment then
		beam.Attachment1 = endAttachment
	end

	local folder = systemFolder("Tracers")
	startPart.CFrame = muzzleCFrame
	endPart.Position = endPosition
	startPart.Parent = folder
	endPart.Parent = folder

	local transparency = startPart:FindFirstChild("BeamTransparency")
	task.delay(0.04, function()
		if transparency and transparency:IsA("NumberValue") and beam then
			transparency.Changed:Connect(function(value)
				beam.Transparency = NumberSequence.new(value)
			end)
			TweenService:Create(transparency, TweenInfo.new(0.12), { Value = 1 }):Play()
		end
	end)

	task.delay(TRACER_LIFETIME, function()
		startPart:Destroy()
		endPart:Destroy()
	end)
end

--------------------------------------------------------------------------------
-- Impacto
--------------------------------------------------------------------------------

local function spawnImpact(templateFolderName: string, position: Vector3, normal: Vector3, weldTo: BasePart?, lifetime: number)
	local impacts = Effects:FindFirstChild("ImpactEffects")
	local templateFolder = impacts and impacts:FindFirstChild(templateFolderName)
	local template = templateFolder and templateFolder:FindFirstChild("Part")
	if not template or not template:IsA("BasePart") then
		return
	end

	local impact = template:Clone()
	impact.Massless, impact.CanCollide, impact.CanTouch, impact.CanQuery = true, false, false, false
	impact.Anchored = weldTo == nil
	impact.CFrame = CFrame.lookAt(position, position + normal)
	impact.Parent = systemFolder("Impacts")

	if weldTo then
		local weld = Instance.new("WeldConstraint")
		weld.Part0 = impact
		weld.Part1 = weldTo
		weld.Parent = impact
	end

	local sounds = Audios:FindFirstChild("ImpactSounds")
	local soundFolder = sounds and sounds:FindFirstChild(templateFolderName)
	if soundFolder then
		local options = soundFolder:GetChildren()
		if #options > 0 then
			local pick = options[math.random(1, #options)]
			if pick:IsA("Sound") then
				local sound = pick:Clone()
				sound.PlayOnRemove = false
				sound.Parent = impact
				sound:Play()
			end
		end
	end

	for _, child in impact:GetChildren() do
		if child:IsA("ParticleEmitter") then
			task.delay(0.1, function()
				child:Emit(10)
			end)
		end
	end

	task.delay(lifetime, function()
		impact:Destroy()
	end)
end

function OTSEffects.CreateImpact(position: Vector3, instance: Instance, normal: Vector3)
	local model = instance:FindFirstAncestorOfClass("Model")
	local isCharacter = model ~= nil and model:FindFirstChildOfClass("Humanoid") ~= nil

	if isCharacter then
		spawnImpact("Flesh", position, normal, if instance:IsA("BasePart") then instance else nil, FLESH_LIFETIME)
	elseif instance:IsA("Terrain") then
		spawnImpact("Ground", position, normal, nil, IMPACT_LIFETIME)
	elseif instance:IsA("BasePart") then
		local impacts = Effects:FindFirstChild("ImpactEffects")
		local materialName = instance.Material.Name
		local folderName = if impacts and impacts:FindFirstChild(materialName) then materialName else "Concrete"
		spawnImpact(folderName, position, normal, instance, IMPACT_LIFETIME)
	end
end

return OTSEffects
