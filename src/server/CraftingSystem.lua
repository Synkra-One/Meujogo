--!strict
--[[
	CraftingSystem
	Crafting simples: consome materiais do inventário pessoal
	(RaftObjective.GetMaterialCount/ConsumeMaterial -- o mesmo estoque
	usado pra entregar na Jangada) e entrega a Tool crafted no Backpack.

	Receitas hoje (ItemRegistry.Items[id].Craft.Ingredients):
	  Lança de Bambu = 1 Madeira + 1 Corda -- o pedido original dizia
	    "bambu + corda", mas "bambu" não é um item coletável em nenhuma
	    tabela; virou Madeira.
	  Tocha = 1 Madeira + 1 Lona -- o "pano" da receita original é a MESMA
	    Lona rara que a Jangada usa pra vela. Craftar Tocha compete pelo
	    mesmo item raro, de propósito (fiel ao que foi pedido, mas é uma
	    tensão de balanceamento real: cada Lona vira uma escolha).

	Cliente dispara CraftItem:FireServer(itemId). Sem ingredientes
	suficientes, sem Craft definido, ou item desconhecido: rejeitado em
	silêncio, nada volta pro cliente. Nunca consome parcial -- ou tem tudo
	e crafta, ou não mexe em nada.

	Uso (chamar uma vez no boot do servidor):
		local CraftingSystem = require(script.CraftingSystem)
		CraftingSystem.Init()
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ItemRegistry = require(ReplicatedStorage.Modules.ItemRegistry)
local ToolFactory = require(ReplicatedStorage.Modules.ToolFactory)
local Remotes = require(ReplicatedStorage.Modules.Remotes)
local RaftObjective = require(script.Parent.RaftObjective)

local CraftingSystem = {}

local function hasIngredients(player: Player, ingredients: { [string]: number }): boolean
	for materialType, amount in ingredients do
		if RaftObjective.GetMaterialCount(player, materialType) < amount then
			return false
		end
	end
	return true
end

local function consumeIngredients(player: Player, ingredients: { [string]: number })
	for materialType, amount in ingredients do
		RaftObjective.ConsumeMaterial(player, materialType, amount)
	end
end

local function onCraftItem(player: Player, itemId: unknown)
	if typeof(itemId) ~= "string" then
		return
	end

	local def = ItemRegistry.Items[itemId]
	if not def or not def.Craft then
		return
	end

	if not player.Character or player.Character:GetAttribute("GrabLocked") == true then
		return
	end

	if not hasIngredients(player, def.Craft.Ingredients) then
		return
	end

	local tool = ToolFactory.Create(itemId)
	if not tool then
		warn(string.format("[CraftingSystem] ToolFactory não sabe criar '%s'.", itemId))
		return
	end

	consumeIngredients(player, def.Craft.Ingredients)

	local backpack = player:FindFirstChildOfClass("Backpack")
	tool.Parent = backpack or player
	print(string.format("[CraftingSystem] %s craftou %s.", player.Name, def.DisplayName))
end

--[[
	Init()
	Assina o RemoteEvent CraftItem. Chame uma vez no boot do servidor.
]]
function CraftingSystem.Init()
	Remotes.CraftItem.OnServerEvent:Connect(onCraftItem)
end

return CraftingSystem
