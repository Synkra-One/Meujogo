--!strict
--[[
	DrawerPromptController
	Os prompts das gavetas (server/DrawerSystem.lua) são criados pelo servidor,
	mas só o cliente sabe o que ESTE jogador tem na mão. Aqui:
	  - "Guardar item" (GuardarPrompt) só aparece com a gaveta aberta, vazia
	    e uma Tool equipada;
	  - o Monstro não vê prompt de gaveta nenhum.
	GavetaFuncional é definido pelo servidor por casa a cada rodada. O cliente
	reaplica as condições locais quando esse estado muda; o servidor revalida.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local GameConfig = require(ReplicatedStorage.Modules.GameConfig)

local player = Players.LocalPlayer
local prompts: { [ProximityPrompt]: BasePart } = {}

local function holdingTool(): boolean
	local character = player.Character
	return character ~= nil and character:FindFirstChildOfClass("Tool") ~= nil
end

local function refresh(prompt: ProximityPrompt, front: BasePart)
	local blocked = front:GetAttribute("GavetaFuncional") ~= true
		or (not GameConfig.Drawers.MonsterCanUse and player:GetAttribute("Role") == GameConfig.Roles.Monster)
	if prompt.Name == "GavetaPrompt" then
		prompt.Enabled = not blocked
	else
		prompt.Enabled = not blocked
			and holdingTool()
			and front:GetAttribute("GavetaAberta") == true
			and front:GetAttribute("GavetaItem") == nil
	end
end

local function refreshAll()
	for prompt, front in prompts do
		refresh(prompt, front)
	end
end

local function track(instance: Instance)
	if not instance:IsA("ProximityPrompt") or (instance.Name ~= "GavetaPrompt" and instance.Name ~= "GuardarPrompt") then
		return
	end
	local front = instance.Parent
	if not front or not front:IsA("BasePart") or front:GetAttribute("Gaveta") ~= true or prompts[instance] then
		return
	end
	prompts[instance] = front
	refresh(instance, front)
	local connections = {
		instance:GetPropertyChangedSignal("Enabled"):Connect(function()
			refresh(instance, front)
		end),
		front:GetAttributeChangedSignal("GavetaFuncional"):Connect(function()
			refresh(instance, front)
		end),
		front:GetAttributeChangedSignal("GavetaAberta"):Connect(function()
			refresh(instance, front)
		end),
		front:GetAttributeChangedSignal("GavetaItem"):Connect(function()
			refresh(instance, front)
		end),
	}
	instance.AncestryChanged:Connect(function()
		if not instance:IsDescendantOf(Workspace) then
			prompts[instance] = nil
			for _, c in connections do
				c:Disconnect()
			end
		end
	end)
end

local function watchCharacter(character: Model)
	character.ChildAdded:Connect(function(child)
		if child:IsA("Tool") then
			refreshAll()
		end
	end)
	character.ChildRemoved:Connect(function(child)
		if child:IsA("Tool") then
			refreshAll()
		end
	end)
	refreshAll()
end

for _, d in Workspace:GetDescendants() do
	track(d)
end
Workspace.DescendantAdded:Connect(track)
player:GetAttributeChangedSignal("Role"):Connect(refreshAll)
if player.Character then
	watchCharacter(player.Character)
end
player.CharacterAdded:Connect(watchCharacter)
