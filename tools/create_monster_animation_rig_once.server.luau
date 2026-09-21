-- Execute UMA vez na Command Bar, em modo de edição.
-- A cópia vem do template canônico em ReplicatedStorage; este script não cria
-- joints, não recalcula escala e nunca escreve C0/C1.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local template = ReplicatedStorage:FindFirstChild("MonsterAnimationRig")
if not template or not template:IsA("Model") then
	warn("[MonsterAnimationRig] ReplicatedStorage.MonsterAnimationRig não existe.")
	return
end

local targetName = "Monster Animation Rig (Authoring)"
local existing = Workspace:FindFirstChild(targetName)
if existing then
	warn("[MonsterAnimationRig] A cópia de autoria já existe; nada foi substituído: " .. existing:GetFullName())
	return
end

local rig = template:Clone()
rig.Name = targetName
rig:SetAttribute("AnimationRig", true)
rig:SetAttribute("SourceTemplate", template:GetFullName())

local humanoid = rig:FindFirstChildOfClass("Humanoid")
if not humanoid then
	warn("[MonsterAnimationRig] Template inválido: Humanoid ausente.")
	rig:Destroy()
	return
end
if not humanoid:FindFirstChildOfClass("Animator") then
	Instance.new("Animator").Parent = humanoid
end

for _, item in rig:GetDescendants() do
	if item:IsA("BasePart") then
		item.CanCollide = false
		item.CanTouch = false
		item.CanQuery = false
		item.Massless = true
		item.Anchored = item.Name == "HumanoidRootPart"
	end
end

rig.Parent = Workspace
rig:PivotTo(CFrame.new(0, rig:GetExtentsSize().Y * 0.5, 0))
print("[MonsterAnimationRig] Pronto: " .. rig:GetFullName())
print("Abra Plugins > Animation Editor, selecione este rig e crie/publice a animação.")
