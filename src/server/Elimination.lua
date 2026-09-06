--!strict
--[[
	Elimination
	Placeholder compartilhado de "morte", usado por mais de um sistema:
	  - LethalAbility  (habilidade letal do Espião)
	  - ConfrontSystem (execução com a Arma Rara)

	Extraído pra cá justamente porque a lógica final de morte/respawn ainda
	não existe: quando ela for escrita, é UM lugar só pra trocar, em vez de
	duas cópias divergindo.

	Efeito atual: marca o character como "Eliminado", ancora todas as partes,
	zera os controles do Humanoid e move o character pra workspace.Eliminados.

	POR QUE O ATTRIBUTE VAI TAMBÉM NO PLAYER, não só no character:
	o "Ultimate R6 Movement System" traz um DeathRespawnHandler que, ao
	Humanoid.Died, dá player:LoadCharacter() depois de ~5s. Se a marca de
	eliminado vivesse só no character, o jogador voltaria com um character
	NOVO, sem a marca, e o RoundManager passaria a contá-lo como vivo de novo
	-- a rodada nunca terminaria. Com a marca no Player ela sobrevive ao
	respawn: você renasce (o "feel" do pacote), mas continua FORA da rodada.
	Quem limpa isso é o começo de uma partida nova (Reset).
]]

local Workspace = game:GetService("Workspace")

local Elimination = {}

local eliminatedFolder: Folder? = nil

-- Cria (ou reaproveita) a pasta "Eliminados" em workspace, sob demanda.
local function getEliminatedFolder(): Folder
	if eliminatedFolder and eliminatedFolder.Parent then
		return eliminatedFolder
	end

	local existing = Workspace:FindFirstChild("Eliminados")
	if existing and existing:IsA("Folder") then
		eliminatedFolder = existing
		return existing
	end

	local folder = Instance.new("Folder")
	folder.Name = "Eliminados"
	folder.Parent = Workspace
	eliminatedFolder = folder
	return folder
end

--[[
	IsEliminated(player)
	true se o character atual do jogador já foi eliminado.
]]
function Elimination.IsEliminated(player: Player): boolean
	if player:GetAttribute("Eliminado") == true then
		return true -- sobrevive ao respawn do DeathRespawnHandler (ver cabeçalho)
	end
	local character = player.Character
	return character ~= nil and character:GetAttribute("Eliminado") == true
end

--[[
	Reset(player)
	Tira a marca de eliminado. Chame no INÍCIO de uma partida nova, senão
	quem morreu na anterior nasce já eliminado.
]]
function Elimination.Reset(player: Player)
	player:SetAttribute("Eliminado", nil)
	local character = player.Character
	if character then
		character:SetAttribute("Eliminado", nil)
	end
end

--[[
	Eliminate(player)
	Aplica o efeito placeholder de eliminação. Idempotente: chamar duas
	vezes no mesmo character não faz nada na segunda.
]]
function Elimination.Eliminate(player: Player)
	local character = player.Character
	if not character or character:GetAttribute("Eliminado") == true then
		return
	end

	character:SetAttribute("Eliminado", true)
	player:SetAttribute("Eliminado", true) -- sobrevive ao respawn (ver cabeçalho)

	for _, descendant in character:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant.Anchored = true
		end
	end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.WalkSpeed = 0
		humanoid.JumpPower = 0
		humanoid.JumpHeight = 0
	end

	character.Parent = getEliminatedFolder()
end

return Elimination
