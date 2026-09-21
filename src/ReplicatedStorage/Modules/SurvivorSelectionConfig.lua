--!strict
--[[
	SurvivorSelectionConfig
	Configuracao compartilhada da etapa de escolha de sobrevivente.

	CharacterData é a fonte do elenco, paletas e referências de assets.
	Este módulo guarda tempos, sons, fundo global e overrides de disponibilidade.
	Portraits permanece como override de compatibilidade; novas configurações
	devem ser feitas nos registros de CharacterData. Sem assets importados,
	o cliente constrói miniaturas e prévias R6 locais.
]]

local CharacterData = require(script.Parent.CharacterData)

local SurvivorSelectionConfig = {}

SurvivorSelectionConfig.Duration = 30
SurvivorSelectionConfig.WarningAt = 10
SurvivorSelectionConfig.RoleRevealDuration = 7.5
SurvivorSelectionConfig.DefaultCharacterId = CharacterData.Characters[1].Id

export type AvailabilityState = "Available" | "Locked" | "Unavailable"
export type Portrait = {
	Mode: "Viewport" | "Image",
	ImageId: string?,
	RigName: string?,
	Accent: Color3,
	BodyColor: Color3,
	ShirtColor: Color3,
	PantsColor: Color3,
}

-- Deixe vazio enquanto todo o elenco estiver liberado. Exemplos futuros:
--   RafaelMonteiro = "Locked"
--   CamilaDuarte = "Unavailable"
SurvivorSelectionConfig.Availability = {} :: { [string]: AvailabilityState }

local DEFAULT_PORTRAIT: Portrait = {
	Mode = "Viewport",
	ImageId = "",
	RigName = nil,
	Accent = Color3.fromRGB(79, 205, 190),
	BodyColor = Color3.fromRGB(220, 190, 165),
	ShirtColor = Color3.fromRGB(52, 77, 86),
	PantsColor = Color3.fromRGB(34, 43, 50),
}

-- Optional legacy overrides. New assets belong in CharacterData.
SurvivorSelectionConfig.Portraits = {} :: { [string]: Portrait }
SurvivorSelectionConfig.Background = ""
SurvivorSelectionConfig.Sounds = {
	Hover = "rbxasset://sounds/electronicpingshort.wav",
	Select = "rbxasset://sounds/electronicpingshort.wav",
	Confirm = "rbxasset://sounds/electronicpingshort.wav",
	Countdown = "rbxasset://sounds/electronicpingshort.wav",
}

function SurvivorSelectionConfig.GetAvailability(characterId: unknown): AvailabilityState
	if type(characterId) ~= "string" or not CharacterData.GetById(characterId) or CharacterData.IsMonsterCharacter(characterId) then
		return "Unavailable"
	end
	return SurvivorSelectionConfig.Availability[characterId]
		or (CharacterData.GetById(characterId) :: any).Availability or "Available"
end

function SurvivorSelectionConfig.IsSelectable(characterId: unknown): boolean
	return SurvivorSelectionConfig.GetAvailability(characterId) == "Available"
end

function SurvivorSelectionConfig.GetPortrait(characterId: string): Portrait
	local override = SurvivorSelectionConfig.Portraits[characterId]
	if override then return override end
	local character = CharacterData.GetById(characterId)
	if not character then return DEFAULT_PORTRAIT end
	return {
		Mode = if character.Icon and character.Icon ~= "" then "Image" else "Viewport",
		ImageId = character.Icon,
		RigName = character.PreviewModel or character.Id,
		Accent = character.ThemeColor or DEFAULT_PORTRAIT.Accent,
		BodyColor = character.BodyColor or DEFAULT_PORTRAIT.BodyColor,
		ShirtColor = character.ShirtColor or DEFAULT_PORTRAIT.ShirtColor,
		PantsColor = character.PantsColor or DEFAULT_PORTRAIT.PantsColor,
	}
end

function SurvivorSelectionConfig.GetSelectableCharacters(): { CharacterData.Character }
	local result = {}
	for _, character in CharacterData.Characters do
		if SurvivorSelectionConfig.IsSelectable(character.Id) then
			table.insert(result, character)
		end
	end
	return result
end

return SurvivorSelectionConfig
