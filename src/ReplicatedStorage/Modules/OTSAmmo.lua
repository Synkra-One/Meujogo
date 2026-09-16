--!strict
--[[
	OTSAmmo (compartilhado client/server)
	Só LEITURA e as regrinhas de nomenclatura da munição. Quem ESCREVE é o
	servidor (AmmoSystem.lua) -- este módulo existe pra client e server
	concordarem em "qual munição essa arma usa" e "onde a reserva está
	guardada" sem duplicar a regra nos dois lados.

	DOIS ESTOQUES, não confunda:
	  PENTE   -> Tool/Settings/Config/Ammo (NumberValue). Gasta 1 por tiro
	             (OTSFirearmService). É o número da esquerda na HUD.
	  RESERVA -> Attribute "Municao_<Tipo>" no Player (ex: "Municao_Pistola").
	             Recarregar move RESERVA -> PENTE. É o número da direita.

	A reserva mora num Attribute do Player de propósito: Attributes replicam
	sozinhos pra todos os clientes, então a HUD (client/OTSController) lê direto,
	sem precisar de RemoteEvent nenhum pra ficar em sincronia.

	Números (tipos por arma, teto, quanto cada caixa dá): GameConfig.Firearms.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local GameConfig = require(ReplicatedStorage.Modules.GameConfig)

local Ammo = {}

--[[
	TypeFor(tool)
	Tipo de munição da arma: Attribute "AmmoType" da Tool, senão
	GameConfig.Firearms.AmmoTypes[tool.Name], senão o DefaultAmmoType.
]]
function Ammo.TypeFor(tool: Tool): string
	local attr = tool:GetAttribute("AmmoType")
	if type(attr) == "string" and attr ~= "" then
		return attr
	end
	return GameConfig.Firearms.AmmoTypes[tool.Name] or GameConfig.Firearms.DefaultAmmoType
end

--[[ Nome do Attribute onde a reserva desse tipo é guardada no Player. ]]
function Ammo.AttributeName(ammoType: string): string
	return "Municao_" .. ammoType
end

--[[ Reserva atual do jogador pra esse tipo (0 se nunca foi setada). ]]
function Ammo.GetReserve(player: Player, ammoType: string): number
	local value = player:GetAttribute(Ammo.AttributeName(ammoType))
	return if type(value) == "number" then value else 0
end

--[[ Teto de reserva desse tipo (math.huge se não houver limite configurado). ]]
function Ammo.MaxReserve(ammoType: string): number
	return GameConfig.Firearms.MaxReserve[ammoType] or math.huge
end

--[[ Munição no PENTE da arma (Settings/Config/Ammo). ]]
function Ammo.GetMagazine(tool: Tool): number
	local settings = tool:FindFirstChild("Settings")
	local config = settings and settings:FindFirstChild("Config")
	local ammo = config and config:FindFirstChild("Ammo")
	if ammo and ammo:IsA("NumberValue") then
		return ammo.Value
	end
	return 0
end

--[[ Capacidade do pente (Settings/Config/MaxAmmo). ]]
function Ammo.GetMagazineMax(tool: Tool): number
	local settings = tool:FindFirstChild("Settings")
	local config = settings and settings:FindFirstChild("Config")
	local maxAmmo = config and config:FindFirstChild("MaxAmmo")
	if maxAmmo and maxAmmo:IsA("NumberValue") then
		return maxAmmo.Value
	end
	return 0
end

return Ammo
