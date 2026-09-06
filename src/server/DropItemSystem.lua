--!strict
--[[
	DropItemSystem
	Larga Tools no chão a pedido do cliente (Remotes.DropItem, disparado por
	HotbarController.client.luau -- tecla G ou o botão de largar no slot).

	CONTRATO
	  Client -> Server: Remotes.DropItem:FireServer(tool)
	  O servidor só aceita se `tool` for uma Tool que, NESSE instante, está no
	  Backpack OU no Character do próprio jogador que disparou. Qualquer outra
	  coisa é ignorada em silêncio (mesmo espírito dos outros remotes do jogo).

	O QUE ACONTECE AO LARGAR
	  - Desequipa (Humanoid:UnequipTools) pra Tool sair do Character.
	  - Joga a Tool no Workspace, com o Handle à frente do personagem e um
	    empurrãozinho pra frente/cima (parece que foi "largada", não some).
	  - Handle passa a colidir (CanCollide = true) pra descansar no chão, e
	    para de responder a toque (CanTouch = false) pra NÃO ser pega pelo
	    pickup-por-toque legado do engine -- só pelo ProximityPrompt abaixo.
	  - Pendura um ProximityPrompt "Pegar" (ObjectText = nome da Tool), igual
	    aos pickups de ItemSpawner.lua: ao acionar, a Tool volta pro Backpack
	    de quem pegou, com Handle restaurado (CanCollide = false, CanTouch =
	    true) pra voltar a funcionar normal na mão.
	  - Depois de DROP_LIFETIME segundos, se a Tool AINDA estiver largada no
	    chão (ninguém pegou), ela é destruída pra não acumular lixo no mapa.
	    Se alguém pegou antes, ela está no Backpack e não é mexida.

	TAMBÉM É A PORTA DE "ITEM NO CHÃO" DO MAPA: DropItemSystem.PlaceInWorld
	(tool, cframe, parent?, lifetime?) põe uma Tool pronta pra ser pega sem
	passar por jogador nenhum -- é o que o WeaponSpawner.lua usa pra espalhar
	as pistolas. Com lifetime = nil a Tool FICA no mapa (o drop do jogador
	passa DROP_LIFETIME e some sozinha).

	Uso (uma vez no boot do servidor):
		local DropItemSystem = require(script.DropItemSystem)
		DropItemSystem.Init()
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Remotes = require(ReplicatedStorage.Modules.Remotes)

local DropItemSystem = {}

local DROP_LIFETIME = 180 -- s no chão antes do Debris limpar (se ninguém pegar)
local DROP_FORWARD = 3.5 -- studs à frente do personagem
local PICKUP_DISTANCE = 8 -- alcance do ProximityPrompt "Pegar"

local function getHandle(tool: Tool): BasePart?
	local handle = tool:FindFirstChild("Handle")
	if handle and handle:IsA("BasePart") then
		return handle
	end
	-- Tools sem Handle nomeado: usa a primeira BasePart que achar.
	for _, descendant in tool:GetDescendants() do
		if descendant:IsA("BasePart") then
			return descendant
		end
	end
	return nil
end

-- Guarda o estado original das BaseParts pra restaurar quando a Tool for pega.
local function makeGroundReady(tool: Tool)
	local handle = getHandle(tool)
	if handle then
		tool:SetAttribute("_DropOrigCanCollide", handle.CanCollide)
		tool:SetAttribute("_DropOrigCanTouch", handle.CanTouch)
		handle.CanCollide = true
		handle.CanTouch = false
	end
end

local function restoreFromGround(tool: Tool)
	local handle = getHandle(tool)
	if handle then
		local origCollide = tool:GetAttribute("_DropOrigCanCollide")
		local origTouch = tool:GetAttribute("_DropOrigCanTouch")
		handle.CanCollide = if type(origCollide) == "boolean" then origCollide else false
		handle.CanTouch = if type(origTouch) == "boolean" then origTouch else true
	end
	tool:SetAttribute("_DropOrigCanCollide", nil)
	tool:SetAttribute("_DropOrigCanTouch", nil)
	tool:SetAttribute("_Dropped", nil)
end

local function attachPickupPrompt(tool: Tool)
	local handle = getHandle(tool)
	if not handle then
		return
	end

	local existing = handle:FindFirstChild("PegarPrompt")
	if existing then
		existing:Destroy()
	end

	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "PegarPrompt"
	prompt.ActionText = "Pegar"
	prompt.ObjectText = tool.Name
	prompt.MaxActivationDistance = PICKUP_DISTANCE
	prompt.RequiresLineOfSight = false
	prompt.Parent = handle

	prompt.Triggered:Connect(function(player: Player)
		-- Corrida: dois jogadores acionam quase junto. Quem chegar primeiro
		-- limpa "_Dropped" (restoreFromGround); o segundo cai fora aqui.
		-- Testa o Attribute, NÃO o Parent: arma do mapa vive em
		-- Workspace.ArmasNoChao, não solta no Workspace.
		if tool:GetAttribute("_Dropped") ~= true or tool.Parent == nil then
			return
		end

		local backpack = player:FindFirstChildOfClass("Backpack")
		if not backpack then
			return
		end

		prompt:Destroy()
		restoreFromGround(tool)
		tool.Parent = backpack
	end)
end

--[[
	PlaceInWorld(tool, cframe, parent?, lifetime?)
	Põe uma Tool no chão pronta pra ser pega, sem passar por jogador nenhum --
	é o que o WeaponSpawner.lua usa pra espalhar as armas pelo mapa.
	  lifetime: segundos até sumir sozinha se ninguém pegar. nil = FICA
	  (é o caso das armas do mapa; o drop do jogador usa DROP_LIFETIME).
]]
function DropItemSystem.PlaceInWorld(tool: Tool, cframe: CFrame, parent: Instance?, lifetime: number?)
	tool:SetAttribute("_Dropped", true)
	makeGroundReady(tool)
	tool.Parent = parent or Workspace

	local handle = getHandle(tool)
	if handle then
		handle.CFrame = cframe
		handle.AssemblyLinearVelocity = Vector3.zero
	end

	attachPickupPrompt(tool)

	if lifetime then
		-- Limpa só se continuar largada no chão (não usa Debris: se alguém
		-- pegar antes, a Tool está no Backpack e NÃO pode ser destruída).
		task.delay(lifetime, function()
			-- "_Dropped" ainda true = ninguém pegou (restoreFromGround limpa).
			if tool.Parent ~= nil and tool:GetAttribute("_Dropped") == true then
				tool:Destroy()
			end
		end)
	end
end

local function dropTool(player: Player, tool: Tool)
	local character = player.Character
	local backpack = player:FindFirstChildOfClass("Backpack")

	-- Posse: precisa estar na mão ou na mochila do próprio jogador AGORA.
	if tool.Parent ~= character and tool.Parent ~= backpack then
		return
	end

	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if humanoid and tool.Parent == character then
		humanoid:UnequipTools() -- tira do Character -> volta pro Backpack
	end

	-- Sem HumanoidRootPart (morrendo/carregando), larga onde a Tool já está.
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local currentHandle = getHandle(tool)
	local dropCFrame = if root and root:IsA("BasePart")
		then root.CFrame * CFrame.new(0, 0.5, -DROP_FORWARD)
		elseif currentHandle then currentHandle.CFrame
		else CFrame.new()

	DropItemSystem.PlaceInWorld(tool, dropCFrame, Workspace, DROP_LIFETIME)

	-- Empurrãozinho pra frente/cima: parece que foi largada, não que sumiu.
	local handle = getHandle(tool)
	if handle and root and root:IsA("BasePart") then
		handle.AssemblyLinearVelocity = root.CFrame.LookVector * 10 + Vector3.new(0, 8, 0)
	end
end

--[[
	Init()
	Liga o listener do Remotes.DropItem. Chame uma vez no boot do servidor.
]]
function DropItemSystem.Init()
	Remotes.DropItem.OnServerEvent:Connect(function(player: Player, tool: unknown)
		if typeof(tool) ~= "Instance" or not (tool :: Instance):IsA("Tool") then
			return
		end
		dropTool(player, tool :: Tool)
	end)
end

return DropItemSystem
