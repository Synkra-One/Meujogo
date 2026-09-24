--!strict
--[[
	ItemIcons
	Imagem (ícone) de cada Tool pra mostrar no slot da hotbar
	(HotbarController.client.luau) e no Tool.TextureId (ToolFactory.lua).

	POR QUE ISSO EXISTE
	  As Tools placeholder de ToolFactory.lua não têm arte própria. Aqui fica
	  UMA entrada por item: quando você tiver o decal/imagem final de um item,
	  cole o rbxassetid em Map[itemId] e o ícone aparece na hotbar E na mochila
	  automaticamente -- nada mais precisa mudar.

	ORDEM DE RESOLUÇÃO (ItemIcons.Resolve):
	  1. tool.TextureId, se já estiver preenchido (ToolFactory usa Map[] pra
	     preencher; um asset real do Toolbox pode já vir com textura).
	  2. Map[itemId] -- pelo Attribute do item (ItemRegistry).
	  3. Map[tool.Name] -- pelo NOME da Tool. É o caminho das armas de fogo
	     (Glock17), que não estão no ItemRegistry.
	  4. rbxthumb do AssetId do item (Lanterna/Chocolate têm modelo real do
	     Toolbox -- dá pra usar a miniatura dele como ícone sem arte extra).
	  5. "" -- sem imagem; a hotbar renderiza o modelo 3D da própria Tool num
	     ViewportFrame (e, se nem isso der, um ícone-letra).

	COMO COLOCAR UM PNG DE VERDADE (ex: a pistola)
	  O Roblox não carrega arquivo local: a imagem PRECISA estar publicada.
	  No Studio: aba Asset Manager -> Images -> Bulk Import -> escolha o PNG.
	  Clique com o botão direito no que subiu -> "Copy Asset ID". Cole aqui:
	      Glock17 = "rbxassetid://SEU_ID",
	  Pronto -- o ícone passa a aparecer no slot da hotbar E na Tool
	  (ToolFactory já copia pro TextureId). Enquanto o ID não vier, o slot
	  mostra o modelo 3D real da arma, então nunca fica vazio.

	Map aceita as duas chaves: a CHAVE de ItemRegistry.Items ou o NOME da Tool
	(ex: "Glock17").
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ItemRegistry = require(ReplicatedStorage.Modules.ItemRegistry)

local ItemIcons = {}

-- Cole aqui os rbxassetid dos ícones finais quando tiver. "" = ainda não
-- existe -> usa miniatura do AssetId (se houver) ou o ícone-letra.
ItemIcons.Map = {
	-- Itens do ItemRegistry (chave = id do item)
	LancaDeBambu = "",
	TacoBeisebol = "",
	Tocha = "",
	Lanterna = "",
	Chocolate = "",
	Bandagem = "",
	Gasolina = "",
	LancaAncestral = "",
	-- Peças do Rádio: usadas pelo marcador de item descoberto no mapa.
	Antena = "",
	Bateria = "",
	Transmissor = "",

	-- Armas de fogo (chave = nome da Tool em WeaponAssets/Tools).
	-- >>> COLE AQUI O ID DO PNG DA PISTOLA <<< (ver cabeçalho pra como subir)
	Glock17 = "",
} :: { [string]: string }

-- itemId -> AttributeName, pra descobrir qual item uma Tool é só olhando os
-- Attributes dela (mesmo contrato que WeaponSystem/UtilityItemSystem usam).
local ATTRIBUTE_TO_ITEM: { [string]: string } = {}
for itemId, def in ItemRegistry.Items do
	if def.AttributeName then
		ATTRIBUTE_TO_ITEM[def.AttributeName] = itemId
	end
end

--[[
	ItemIdFromTool(tool)
	Chave de ItemRegistry.Items correspondente à Tool, lida pelos Attributes.
	nil se a Tool não tiver nenhum Attribute conhecido.
]]
function ItemIcons.ItemIdFromTool(tool: Tool): string?
	for attributeName, itemId in ATTRIBUTE_TO_ITEM do
		if tool:GetAttribute(attributeName) == true then
			return itemId
		end
	end
	return nil
end

--[[
	IconForItemId(itemId)
	Só os passos 2 e 3 da resolução (Map -> rbxthumb do AssetId). "" se nada.
	Usado por ToolFactory.lua pra preencher tool.TextureId na criação.
]]
function ItemIcons.IconForItemId(itemId: string): string
	local mapped = ItemIcons.Map[itemId]
	if mapped and mapped ~= "" then
		return mapped
	end

	local def = ItemRegistry.Items[itemId]
	if def and def.AssetId then
		return string.format("rbxthumb://type=Asset&id=%d&w=150&h=150", def.AssetId)
	end

	return ""
end

--[[
	Resolve(tool)
	Imagem final pra mostrar no slot da hotbar (ordem completa 1..4).
	Devolve "" quando não há imagem nenhuma -- quem chama decide o fallback.
]]
function ItemIcons.Resolve(tool: Tool): string
	if tool.TextureId ~= "" then
		return tool.TextureId
	end

	local itemId = ItemIcons.ItemIdFromTool(tool)
	if itemId then
		local icon = ItemIcons.IconForItemId(itemId)
		if icon ~= "" then
			return icon
		end
	end

	-- Sem Attribute conhecido (ou sem ícone por ele): tenta pelo NOME da
	-- Tool -- é assim que as armas de fogo entram, já que não têm entrada
	-- no ItemRegistry.
	local byName = ItemIcons.Map[tool.Name]
	if byName and byName ~= "" then
		return byName
	end

	return ""
end

return ItemIcons
