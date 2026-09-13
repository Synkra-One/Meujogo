--!strict
--[[
	DiscoveredItemsStore
	Acumula, no cliente, os itens que server/ItemDiscovery.lua já marcou como
	descobertos por ESTE jogador (Remotes.MapDiscovery). Consumido pelos dois
	mapas (Modules/IslandMapUI, via client/MonsterTeleportController e
	client/SurvivorMapController) pra desenhar os ícones.

	PERSISTE PELA SESSÃO INTEIRA (não zera entre rodadas): os itens do mapa
	não são resorteados a cada partida (Tools/ItemSpawner.lua roda uma vez, em
	modo de edição, e fica salvo no lugar) -- então uma descoberta continua
	válida na rodada seguinte, e o servidor nunca reenvia a mesma (ver
	`seen` em ItemDiscovery.lua). Só volta a ficar vazio se o cliente
	reconectar no servidor.

	Uso:
		local Store = require(...)
		for _, entry in Store.GetAll() do ... end
		Store.Changed:Connect(function(entry) ... end) -- dispara por item novo
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Remotes = require(ReplicatedStorage.Modules.Remotes)

local DiscoveredItemsStore = {}

local changedEvent = Instance.new("BindableEvent")
DiscoveredItemsStore.Changed = changedEvent.Event -- (entry) por item novo

local byKey: { [string]: { [string]: any } } = {}
local ordered: { { [string]: any } } = {}
local connected = false

local function onDiscovered(entry: unknown)
	if typeof(entry) ~= "table" then
		return
	end
	local key = (entry :: any).key
	if type(key) ~= "string" or byKey[key] then
		return
	end
	byKey[key] = entry :: any
	table.insert(ordered, entry :: any)
	changedEvent:Fire(entry)
end

--[[
	GetAll()
	Cópia da lista acumulada até agora (na ordem em que chegaram).
]]
function DiscoveredItemsStore.GetAll(): { { [string]: any } }
	return table.clone(ordered)
end

--[[
	Init()
	Liga a escuta do remote. Idempotente -- pode ser chamado por mais de um
	controlador (Monstro e Sobrevivente) sem duplicar a conexão.
]]
function DiscoveredItemsStore.Init()
	if connected then
		return
	end
	connected = true
	Remotes.MapDiscovery.OnClientEvent:Connect(onDiscovered)
end

DiscoveredItemsStore.Init()

return DiscoveredItemsStore
