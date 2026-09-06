--!strict

-- Opcao secreta de teste: aperte M no cliente autorizado para usar o Model
-- "R6 novo" que esta salvo no Workspace/Explorer como o corpo jogavel.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterPlayer = game:GetService("StarterPlayer")
local Workspace = game:GetService("Workspace")

local Remotes = require(ReplicatedStorage.Modules.Remotes)

local TestRigSwap = {}

local ALLOWED_USER_IDS: { [number]: boolean } = {
	[11555748600] = true,
}

local RIG_NAME = "R6 novo"
local COOLDOWN_SECONDS = 1.5

local lastUseByUserId: { [number]: number } = {}

local function findRigTemplate(): Model?
	local direct = Workspace:FindFirstChild(RIG_NAME)
	if direct and direct:IsA("Model") and direct:FindFirstChildOfClass("Humanoid") and not Players:GetPlayerFromCharacter(direct) then
		return direct
	end

	for _, inst in Workspace:GetDescendants() do
		if inst.Name == RIG_NAME and inst:IsA("Model") and inst:FindFirstChildOfClass("Humanoid") and not Players:GetPlayerFromCharacter(inst) then
			return inst
		end
	end

	return nil
end

local function getPivot(character: Model?): CFrame
	if character then
		local root = character:FindFirstChild("HumanoidRootPart")
		if root and root:IsA("BasePart") then
			return root.CFrame
		end
		return character:GetPivot()
	end

	local spawn = Workspace:FindFirstChild("LobbySpawn")
	if spawn and spawn:IsA("BasePart") then
		return spawn.CFrame + Vector3.new(0, 3, 0)
	end

	return CFrame.new(0, 12, -400)
end

local function ensureCharacterScripts(character: Model)
	local starterCharacterScripts = StarterPlayer:FindFirstChild("StarterCharacterScripts")
	if not starterCharacterScripts then
		return
	end

	for _, scriptTemplate in starterCharacterScripts:GetChildren() do
		if not character:FindFirstChild(scriptTemplate.Name) then
			scriptTemplate:Clone().Parent = character
		end
	end
end

local function prepareRigClone(template: Model, player: Player, pivot: CFrame): Model
	local wasArchivable = template.Archivable
	template.Archivable = true
	local clone = template:Clone()
	template.Archivable = wasArchivable

	clone.Name = player.Name
	clone:SetAttribute("TestRigSwap", true)

	for _, inst in clone:GetDescendants() do
		if inst:IsA("BasePart") then
			inst.Anchored = false
			inst.CanTouch = true
			inst.CanQuery = true
		end
	end

	local humanoid = clone:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.DisplayName = player.DisplayName
		humanoid.Health = humanoid.MaxHealth
		-- Animator criado no servidor permite replicar as poses da pistola no rig de teste.
		if not humanoid:FindFirstChildOfClass("Animator") then
			Instance.new("Animator").Parent = humanoid
		end
	end

	local root = clone:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		clone.PrimaryPart = root
	end

	ensureCharacterScripts(clone)
	clone:PivotTo(pivot)
	return clone
end

local function swapToTestRig(player: Player)
	if not ALLOWED_USER_IDS[player.UserId] then
		return
	end

	local now = os.clock()
	local lastUse = lastUseByUserId[player.UserId]
	if lastUse and now - lastUse < COOLDOWN_SECONDS then
		return
	end
	lastUseByUserId[player.UserId] = now

	local template = findRigTemplate()
	if not template then
		warn("[TestRigSwap] Nao achei um Model chamado 'R6 novo' com Humanoid no Workspace.")
		Remotes.LobbyMessage:FireClient(player, "Nao achei o boneco R6 novo no Workspace.")
		return
	end

	local oldCharacter = player.Character
	local oldHumanoid = oldCharacter and oldCharacter:FindFirstChildOfClass("Humanoid")
	if oldHumanoid then oldHumanoid:UnequipTools() end
	local pivot = getPivot(oldCharacter)
	local clone = prepareRigClone(template, player, pivot)

	clone.Parent = Workspace
	player.Character = clone

	if oldCharacter and oldCharacter.Parent then
		oldCharacter:Destroy()
	end

	Remotes.LobbyMessage:FireClient(player, "Teste: corpo R6 novo aplicado. Aperte M para repetir.")
end

function TestRigSwap.Init()
	Remotes.TestRigSwap.OnServerEvent:Connect(swapToTestRig)
	Players.PlayerRemoving:Connect(function(player)
		lastUseByUserId[player.UserId] = nil
	end)
end

return TestRigSwap
