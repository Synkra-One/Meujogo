--!strict
-- A escalada automática em TrussPart faz o personagem subir só por encostar.
-- SetStateEnabled não replica: o servidor e cada cliente dono do Humanoid
-- desligam Climbing em todo respawn.

local Players = game:GetService("Players")
local player = Players.LocalPlayer

local function disableClimbing(character: Model)
	local humanoid = character:WaitForChild("Humanoid", 10)
	if humanoid and humanoid:IsA("Humanoid") and player.Character == character then
		humanoid:SetStateEnabled(Enum.HumanoidStateType.Climbing, false)
	end
end

player.CharacterAdded:Connect(function(character)
	task.spawn(disableClimbing, character)
end)
if player.Character then
	task.spawn(disableClimbing, player.Character)
end
