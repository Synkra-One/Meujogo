--!strict
--[[
	MapMarkers
	Categoria -> aparência do marcador de item descoberto no mapa
	(Modules/IslandMapUI.lua). Compartilhado servidor (server/ItemDiscovery.lua
	decide a categoria de cada item do mundo) e cliente (desenha o marcador).

	POR QUE GLIFO EM VEZ DE IMAGEM
	  Não existe PNG próprio pra nenhum item ainda (Modules/ItemIcons.lua está
	  vazio). Em vez de esperar arte, cada categoria ganha uma cor + um
	  glifo/letra desenhados em código (TextLabel), então o mapa já marca os
	  itens com uma diferença visual clara por tipo. ImageFor() delega pra
	  ItemIcons: no dia que alguém preencher ItemIcons.Map[itemId] com um
	  rbxassetid real, o marcador passa a usar a imagem sozinho -- nada aqui
	  nem em IslandMapUI precisa mudar.

	Uso:
		local MapMarkers = require(game.ReplicatedStorage.Modules.MapMarkers)
		local category = MapMarkers.CategoryOf("Glock17") -- por nome de Tool
		local category = MapMarkers.CategoryOf(nil, "FacaImprovisada") -- por itemId do ItemRegistry
		local style = MapMarkers.Style(category) -- { Color, Glyph }
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ItemRegistry = require(ReplicatedStorage.Modules.ItemRegistry)
local ItemIcons = require(ReplicatedStorage.Modules.ItemIcons)

local MapMarkers = {}

MapMarkers.Category = {
	Firearm = "Firearm", -- armas de fogo (hoje só a Glock17)
	Melee = "Melee", -- Faca Improvisada, Crowbar, Wrench
	Light = "Light", -- Tocha, Lanterna
	Heal = "Heal", -- Chocolate, Bandagem
	Radio = "Radio", -- Antena, Bateria, Transmissor
	Fuel = "Fuel", -- Gasolina
	Rare = "Rare", -- Crowbar Ancestral
	Crate = "Crate", -- caixa de loot (sem itemId específico)
}

local STYLE: { [string]: { Color: Color3, Glyph: string } } = {
	[MapMarkers.Category.Firearm] = { Color = Color3.fromRGB(213, 82, 72), Glyph = "P" },
	[MapMarkers.Category.Melee] = { Color = Color3.fromRGB(196, 164, 130), Glyph = "/" },
	[MapMarkers.Category.Light] = { Color = Color3.fromRGB(240, 200, 120), Glyph = "L" },
	[MapMarkers.Category.Heal] = { Color = Color3.fromRGB(120, 220, 150), Glyph = "+" },
	[MapMarkers.Category.Radio] = { Color = Color3.fromRGB(150, 200, 240), Glyph = "R" },
	[MapMarkers.Category.Fuel] = { Color = Color3.fromRGB(230, 140, 60), Glyph = "G" },
	[MapMarkers.Category.Rare] = { Color = Color3.fromRGB(233, 193, 99), Glyph = "★" },
	[MapMarkers.Category.Crate] = { Color = Color3.fromRGB(180, 150, 110), Glyph = "▪" },
}
local DEFAULT_STYLE = { Color = Color3.fromRGB(200, 200, 200), Glyph = "?" }

-- itemId de ItemRegistry.Items -> categoria.
local ITEM_CATEGORY: { [string]: string } = {
	FacaImprovisada = MapMarkers.Category.Melee,
	LancaDeBambu = MapMarkers.Category.Melee,
	PedraAfiada = MapMarkers.Category.Melee,
	TacoBeisebol = MapMarkers.Category.Melee,
	Tocha =MapMarkers.Category.Light,
	Lanterna = MapMarkers.Category.Light,
	Chocolate = MapMarkers.Category.Heal,
	Bandagem = MapMarkers.Category.Heal,
	Antena = MapMarkers.Category.Radio,
	Bateria = MapMarkers.Category.Radio,
	Transmissor = MapMarkers.Category.Radio,
	Gasolina = MapMarkers.Category.Fuel,
	LancaAncestral = MapMarkers.Category.Rare,
}

-- Nome da Tool -> categoria, pro que não está no ItemRegistry (armas de fogo:
-- GameConfig.Firearms.Allowed lista os nomes válidos, hoje só "Glock17").
local TOOL_NAME_CATEGORY: { [string]: string } = {
	Glock17 = MapMarkers.Category.Firearm,
}

--[[
	CategoryOf(toolName?, itemId?)
	Resolve pelo itemId (ItemRegistry) quando existir; senão tenta pelo nome
	da Tool (armas de fogo). Devolve Material como fallback neutro -- nunca
	deveria bater fora de um bug de chamada (caixas de loot usam
	MapMarkers.Category.Crate diretamente, não passam por aqui).
]]
function MapMarkers.CategoryOf(toolName: string?, itemId: string?): string
	if itemId then
		local byId = ITEM_CATEGORY[itemId]
		if byId then
			return byId
		end
	end
	if toolName then
		local byName = TOOL_NAME_CATEGORY[toolName]
		if byName then
			return byName
		end
	end
	return MapMarkers.Category.Material
end

function MapMarkers.Style(category: string?): { Color: Color3, Glyph: string }
	if category and STYLE[category] then
		return STYLE[category]
	end
	return DEFAULT_STYLE
end

--[[
	ImageFor(itemId?)
	Imagem real, se algum dia ItemIcons.Map[itemId] for preenchido (PNG
	publicado). "" = sem imagem -- quem desenha usa o glifo (Style acima).
]]
function MapMarkers.ImageFor(itemId: string?): string
	if not itemId then
		return ""
	end
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

return MapMarkers
