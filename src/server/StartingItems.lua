--!strict
--[[
	StartingItems
	Entrega os itens iniciais de cada papel quando a partida e preparada
	(RoundManager.RoundPrepared: personagem da partida ja criado e desembarcado).
	A lista vive em GameConfig.StartingItems; itens que o jogador ja carrega
	(mesma Attribute do ItemRegistry) nao sao duplicados.

	Uso (uma vez no boot do servidor, depois de RoundManager.Init()):
		require(script.StartingItems).Init()
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage.Modules.GameConfig)
local ItemRegistry = require(ReplicatedStorage.Modules.ItemRegistry)
local ToolFactory = require(ReplicatedStorage.Modules.ToolFactory)
local RoundManager = require(script.Parent.RoundManager)

local StartingItems = {}

local function carrying(player: Player, attributeName: string): boolean
	local containers: { Instance } = {}
	local backpack = player:FindFirstChildOfClass("Backpack")
	if backpack then
		table.insert(containers, backpack)
	end
	if player.Character then
		table.insert(containers, player.Character)
	end
	for _, container in containers do
		for _, child in container:GetChildren() do
			if child:IsA("Tool") and child:GetAttribute(attributeName) == true then
				return true
			end
		end
	end
	return false
end

local function give(player: Player)
	local role = player:GetAttribute("Role")
	local ids = if type(role) == "string" then GameConfig.StartingItems[role] else nil
	if not ids then
		return
	end
	local backpack = player:FindFirstChildOfClass("Backpack") or player:WaitForChild("Backpack", 5)
	if not backpack then
		return
	end
	for _, itemId in ids do
		local def = ItemRegistry.Items[itemId]
		if def and not (def.AttributeName and carrying(player, def.AttributeName)) then
			local tool = ToolFactory.Create(itemId)
			if tool and player.Parent == Players then
				tool.Parent = backpack
			elseif tool then
				tool:Destroy()
			end
		end
	end
end

function StartingItems.Init()
	RoundManager.RoundPrepared.Event:Connect(function(players: { Player })
		for _, player in players do
			task.spawn(give, player)
		end
	end)
end

return StartingItems
