--!strict
--[[
	AssetRegistry
	Registro central: nome lógico -> asset real (ou placeholder), pro resto
	do código nunca precisar saber "o que é" cada coisa hoje.

	POR QUE ISSO EXISTE
	  Sem isto, "o Monstro é um torso preto 1.5x maior" ficaria escrito
	  dentro da lógica de AppearanceManager, e "a Tocha é reconhecida pelo
	  Attribute 'Tocha'" ficaria espalhado em cada script que precisa achar
	  uma Tocha. Trocar qualquer um desses detalhes viraria uma busca por
	  todo o código. Aqui, cada nome lógico tem UMA entrada; quem consome
	  (AppearanceManager, ConfrontSystem, MonsterLightWeakness) só pergunta
	  "o que é o Monstro_Modelo hoje" e aplica o que vier.

	MODELOS 3D (ex: Monstro_Modelo)
	  MeshId: rbxassetid de um SpecialMesh, quando você tiver um modelo
	  pronto. Vazio ("") = ainda não existe, usa o campo Placeholder.
	  Quando preencher o MeshId, NADA na lógica que consome precisa mudar.

	TOOLS (Tocha_Item, CristalAncestral_Modelo, ArmaRara_Item)
	  Essas Tools ainda são colocadas manualmente no Studio (não são
	  clonadas por script), então não têm "modelo" pra registrar -- o que
	  existe hoje é só o nome do Attribute usado pelos scripts pra
	  reconhecer qual Tool é qual. Ainda assim ficam aqui: se um dia o
	  Attribute mudar de nome, ou a Tool virar um template clonável, é uma
	  linha só pra trocar, não uma busca em ConfrontSystem/MonsterLightWeakness.

	Uso:
		local AssetRegistry = require(game.ReplicatedStorage.Modules.AssetRegistry)
		local monster = AssetRegistry.Monstro_Modelo
]]

local AssetRegistry = {}

AssetRegistry.Monstro_Modelo = {
	-- rbxassetid de um SpecialMesh pro torso, quando existir. Vazio = usa
	-- o Placeholder abaixo.
	MeshId = "",

	-- Vale nos dois casos (com ou sem MeshId real).
	ScaleMultiplier = 1.5,

	-- Fallback enquanto MeshId estiver vazio.
	Placeholder = {
		TorsoColor = Color3.new(0, 0, 0),
	},
}

AssetRegistry.Tocha_Item = {
	-- Nome do Attribute que identifica a Tool "Tocha" no mundo.
	-- Usado por MonsterLightWeakness.lua (Parte "Tocha").
	AttributeName = "Tocha",
}

AssetRegistry.CristalAncestral_Modelo = {
	-- Usado por ConfrontSystem.lua (Parte 1 -- Detectar).
	AttributeName = "CristalAncestral",
}

AssetRegistry.ArmaRara_Item = {
	-- Usado por ConfrontSystem.lua (Parte 3 -- Executar).
	AttributeName = "ArmaRara",
}

--------------------------------------------------------------------------------
-- SONS (placeholder -- troque cada rbxassetid quando tiver o som real)
--------------------------------------------------------------------------------

AssetRegistry.Sounds = {
	-- SoundManager.lua: música/ambiente por fase.
	PhaseMusic = {
		Queda = "rbxassetid://0",
		Exploracao = "rbxassetid://0",
		Corrida = "rbxassetid://0",
		Desfecho = "rbxassetid://0",
	},

	-- SoundManager.lua: efeitos curtos posicionais.
	PlayerKilled = "rbxassetid://0",
	PlayerRestrained = "rbxassetid://0",
	ItemThrow = "rbxassetid://0", -- impacto da Pedra Afiada (WeaponSystem.lua)

	-- AmbientSoundController.client.luau: tensão por ficar fora de zona segura.
	HeartbeatTension = "rbxassetid://0",
}

return AssetRegistry
