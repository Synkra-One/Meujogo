--!strict
--[[
	Elimination
	Placeholder compartilhado de "morte", usado por mais de um sistema:
	  - LethalAbility  (habilidade letal do Espião)
	  - ConfrontSystem (execução com a Arma Rara)

	Extraído pra cá justamente porque a lógica final de morte/respawn ainda
	não existe: quando ela for escrita, é UM lugar só pra trocar, em vez de
	duas cópias divergindo.

	Efeito atual: marca o character como "Eliminado", trava somente a raiz,
	zera os controles do Humanoid e mantém o corpo no Workspace até o respawn.
	Manter o Model como character ativo é importante: mover o character para
	uma subpasta fazia Player.Character ser invalidado cedo demais em alguns
	clientes, interrompendo animação, câmera e tela de morte.

	POR QUE O ATTRIBUTE VAI TAMBÉM NO PLAYER, não só no character:
	o "Ultimate R6 Movement System" traz um DeathRespawnHandler que, ao
	Humanoid.Died, dá player:LoadCharacter() depois de ~5s. Se a marca de
	eliminado vivesse só no character, o jogador voltaria com um character
	NOVO, sem a marca, e o RoundManager passaria a contá-lo como vivo de novo
	-- a rodada nunca terminaria. Com a marca no Player ela sobrevive ao
	respawn: você renasce (o "feel" do pacote), mas continua FORA da rodada.
	Quem limpa isso é o começo de uma partida nova (Reset).
]]

local Elimination = {}

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

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.WalkSpeed = 0
		humanoid.JumpPower = 0
		humanoid.JumpHeight = 0
		humanoid.AutoRotate = false
	end

	-- Ancorar cada braço/perna impede os Motor6D da animação de morte de
	-- moverem o rig. A raiz basta para o cadáver não deslizar nem cair.
	local root = character:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		root.Anchored = true
		root.AssemblyLinearVelocity = Vector3.zero
		root.AssemblyAngularVelocity = Vector3.zero
	end

	-- O cadáver continua visível, mas não bloqueia jogadores, ataques,
	-- raycasts de habilidade nem a câmera.
	for _, descendant in character:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant.CanCollide = false
			descendant.CanTouch = false
			descendant.CanQuery = false
		end
	end
end

return Elimination
