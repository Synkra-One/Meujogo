--!strict
-- Mantém câmera e controles ligados ao corpo atual durante as trocas
-- lobby <-> partida. Este script vive em PlayerScripts, então não desaparece
-- junto com o character antigo.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Remotes = require(ReplicatedStorage.Modules.Remotes)
local player = Players.LocalPlayer
local generation = 0

local function enableControlsIfInMatch()
	if ReplicatedStorage:GetAttribute("MatchState") ~= "InMatch"
		or player:GetAttribute("ExtractionBoarded") == true
		or player:GetAttribute("GameplayEnabled") ~= true then
		return
	end
	pcall(function()
		local playerModule = player:WaitForChild("PlayerScripts", 5):WaitForChild("PlayerModule", 5)
		local controls = require(playerModule :: ModuleScript):GetControls()
		controls:Enable()
	end)
end

local function bindCharacter(character: Model)
	generation += 1
	local myGeneration = generation
	local humanoid = character:WaitForChild("Humanoid", 10)
	local root = character:WaitForChild("HumanoidRootPart", 10)
	if not humanoid or not humanoid:IsA("Humanoid") or not root or not root:IsA("BasePart") then return end
	if player.Character ~= character or generation ~= myGeneration then return end

	-- O script de movimento publica esta marca somente depois de instalar os
	-- listeners de Shift e inicializar os atributos de sprint.
	local deadline = os.clock() + 5
	while character:GetAttribute("MovementControllerReady") ~= true and os.clock() < deadline do
		if player.Character ~= character or generation ~= myGeneration then return end
		RunService.Heartbeat:Wait()
	end

	-- MatchStateController é o dono da trava. O corpo novo pode aparecer
	-- enquanto ainda está em Loading; nunca libere os controles só porque o
	-- respawn terminou.
	enableControlsIfInMatch()
	-- PlayerModule e o engine também atualizam CameraSubject durante respawn.
	-- Reafirmar por alguns frames remove a disputa de ordem sem manter um loop.
	for _ = 1, 8 do
		if player.Character ~= character or generation ~= myGeneration then return end
		local camera = Workspace.CurrentCamera
		if camera and player:GetAttribute("ExtractionBoarded") ~= true then
			camera.CameraType = Enum.CameraType.Custom
			camera.CameraSubject = humanoid
		end
		RunService.RenderStepped:Wait()
	end

	local token = character:GetAttribute("CharacterPresentationToken")
	if type(token) == "number" then
		Remotes.CharacterPresentationReady:FireServer(token)
	end
end

player.CharacterRemoving:Connect(function()
	generation += 1
end)
player.CharacterAdded:Connect(function(character)
	task.spawn(bindCharacter, character)
end)
if player.Character then task.spawn(bindCharacter, player.Character) end
