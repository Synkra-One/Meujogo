--!strict
-- Clique esquerdo e ativação padrão de Tools por controle/toque.
-- Uma futura UI pode chamar Tool:Activate(). A hotbar existente equipa.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local Rules = require(ReplicatedStorage.Modules.CombatRules)
local Remotes = require(ReplicatedStorage.Modules.Remotes)
local player = Players.LocalPlayer
local connections: { RBXScriptConnection } = {}
local watched: { [Tool]: boolean } = {}
local function watchTool(instance: Instance)
	if not instance:IsA("Tool") or watched[instance] then return end
	local definition = Rules.Definition(instance)
	if not definition or definition.Kind == "Firearm" or definition.ClientDriven then return end
	watched[instance] = true
	table.insert(connections, instance.Activated:Connect(function()
		if instance.Parent ~= player.Character or not Rules.CanAttack(player)
			or UserInputService:GetFocusedTextBox() or player:GetAttribute("CursorLivre") == true then return end
		Remotes.WeaponAttack:FireServer(instance)
	end))
end
local function watchCharacter(character: Model)
	for _, connection in connections do connection:Disconnect() end
	table.clear(connections)
	table.clear(watched)
	for _, child in character:GetChildren() do watchTool(child) end
	table.insert(connections, character.ChildAdded:Connect(watchTool))
end
player.CharacterAdded:Connect(watchCharacter)
if player.Character then watchCharacter(player.Character) end
