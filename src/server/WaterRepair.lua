--!strict
-- Repara agua legada do mapa salvo: remove planos falsos e garante Terrain Water.
local WaterRepair = {}

local IslandGenerator = require(script.Parent.Tools.IslandGenerator)

function WaterRepair.Init()
	task.defer(function()
		local ok, err = pcall(function()
			IslandGenerator.RepairWater()
		end)
		if not ok then
			warn("[WaterRepair] Falha ao reparar agua do mapa: " .. tostring(err))
		end
	end)
end

return WaterRepair
