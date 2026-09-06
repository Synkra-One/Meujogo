--!strict
--[[
	SabotageProximity
	Cria um ProximityPrompt em cada objeto Sabotável (Attribute "Sabotavel"
	== true) do Workspace, para o jogador local disparar a sabotagem.

	Só faz sentido para o Espião, então este script espera o Attribute
	"Role" do LocalPlayer virar GameConfig.Roles.Spy antes de criar
	qualquer prompt (RoleAssignment/AppearanceManager definem esse
	Attribute no servidor, e Attributes de Player replicam para todo
	cliente).

	Os prompts são criados só neste client (não vão para o servidor nem
	para outros jogadores), então só o próprio Espião os vê. A validação
	de verdade (Role, cooldown, distância) é feita no servidor em
	SabotageSystem.lua -- este script é só a interação visual.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local GameConfig = require(ReplicatedStorage.Modules.GameConfig)
local Remotes = require(ReplicatedStorage.Modules.Remotes)

local LocalPlayer = Players.LocalPlayer

-- Ajustável: distância em que o prompt aparece para o jogador.
local PROMPT_MAX_DISTANCE = 10

local function waitUntilSpy()
	while LocalPlayer:GetAttribute("Role") ~= GameConfig.Roles.Spy do
		LocalPlayer:GetAttributeChangedSignal("Role"):Wait()
	end
end

-- ProximityPrompt precisa de uma BasePart como Parent: se o alvo for um
-- Model, usa o PrimaryPart dele.
local function getPromptParent(target: Instance): BasePart?
	if target:IsA("BasePart") then
		return target
	elseif target:IsA("Model") then
		return target.PrimaryPart
	end

	return nil
end

local function attachPrompt(target: Instance)
	if target:FindFirstChildOfClass("ProximityPrompt") then
		return
	end

	local promptParent = getPromptParent(target)
	if not promptParent then
		return
	end

	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = "Sabotar"
	prompt.ObjectText = target.Name
	prompt.MaxActivationDistance = PROMPT_MAX_DISTANCE
	prompt.HoldDuration = 0.5
	prompt.Parent = promptParent

	prompt.Triggered:Connect(function()
		Remotes.SabotageAction:FireServer(target)
	end)
end

local function scanExisting()
	for _, descendant in Workspace:GetDescendants() do
		if descendant:GetAttribute("Sabotavel") == true then
			attachPrompt(descendant)
		end
	end
end

local function watchNew()
	Workspace.DescendantAdded:Connect(function(descendant)
		if descendant:GetAttribute("Sabotavel") == true then
			attachPrompt(descendant)
		end
	end)
end

waitUntilSpy()
scanExisting()
watchNew()
