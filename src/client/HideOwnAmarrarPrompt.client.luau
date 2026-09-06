--!strict
--[[
	HideOwnAmarrarPrompt
	ConfrontSystem.lua (Parte 2, servidor) cria um ProximityPrompt "Amarrar"
	no HumanoidRootPart de TODO jogador -- é assim que outro jogador consegue
	amarrar você. O problema: o Roblox não tem como o servidor esconder um
	prompt só do dono e mostrar pros outros; o prompt fica visível pra
	QUALQUER personagem dentro do alcance, incluindo o próprio dono (que
	está a distância zero do próprio corpo, ou seja, sempre "no alcance").

	Sem isso, todo jogador vê "Amarrar" grudado em si mesmo o tempo todo, em
	qualquer lugar do mapa -- inclusive competindo com outros prompts perto
	(o Roblox prioriza o mais próximo pra exibir, e "grudado em mim" ganha
	de qualquer coisa a alguns metros de distância, como o "Iniciar Partida"
	do Lobby).

	Corrigido aqui, no cliente: desliga (Enabled = false) só na SUA PRÓPRIA
	tela o prompt "Amarrar" que está no seu personagem. Isso não muda nada
	pro servidor nem pros outros jogadores -- cada cliente tem sua própria
	cópia replicada do jogo, então esse Enabled=false é local só pra você;
	quem quiser te amarrar continua vendo e conseguindo usar o prompt
	normalmente na tela dele.
]]

local Players = game:GetService("Players")
local LocalPlayer = Players.LocalPlayer

local function hideIfAmarrar(instance: Instance)
	if instance:IsA("ProximityPrompt") and instance.Name == "Amarrar" then
		instance.Enabled = false
	end
end

local function watchCharacter(character: Model)
	local root = character:WaitForChild("HumanoidRootPart", 10)
	if not root then
		return
	end

	for _, child in root:GetChildren() do
		hideIfAmarrar(child)
	end

	root.ChildAdded:Connect(hideIfAmarrar)
end

LocalPlayer.CharacterAdded:Connect(watchCharacter)
if LocalPlayer.Character then
	watchCharacter(LocalPlayer.Character)
end
