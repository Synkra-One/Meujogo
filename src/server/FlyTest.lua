--!strict
--[[
	FlyTest (servidor)
	Par do client/FlyTest.client.luau (modo voar de TESTE): enquanto o jogador
	voa, o personagem fica Invulneravel (DamageSystem ignora dano de quem tem o
	Attribute), e continua por POUSO_FOLGA segundos depois de parar de voar,
	pra nenhuma queda/impacto do pouso matar.

	Só funciona dentro do Studio e com GameConfig.Testing.Voar = true; no jogo
	publicado o remote é ignorado. Não toma o Attribute de quem já o tem (o
	barco de fuga marca os resgatados): só limpa o que ele mesmo pôs.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local GameConfig = require(ReplicatedStorage.Modules.GameConfig)
local Remotes = require(ReplicatedStorage.Modules.Remotes)

local FlyTest = {}

local POUSO_FOLGA = 4

local owned: { [Model]: number } = {} -- personagem -> token do último pedido

function FlyTest.Init()
	if GameConfig.Testing.Voar ~= true or not RunService:IsStudio() then
		return
	end
	Remotes.FlyTest.OnServerEvent:Connect(function(player: Player, flying: unknown)
		local character = player.Character
		if not character or typeof(flying) ~= "boolean" then
			return
		end
		local token = (owned[character] or 0) + 1
		if flying then
			if character:GetAttribute("Invulneravel") ~= true or owned[character] then
				character:SetAttribute("Invulneravel", true)
				owned[character] = token
			end
			return
		end
		if not owned[character] then
			return
		end
		owned[character] = token
		task.delay(POUSO_FOLGA, function()
			if owned[character] == token then
				owned[character] = nil
				if character.Parent then
					character:SetAttribute("Invulneravel", nil)
				end
			end
		end)
	end)
	Players.PlayerRemoving:Connect(function(player: Player)
		if player.Character then
			owned[player.Character] = nil
		end
	end)
end

return FlyTest
